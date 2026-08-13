#include "demod_test_support.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "../../../include/cusignal/core/helpers.hpp"
#include "../../../include/cusignal/demod/demod.hpp"
#include "../common/live_perf.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace demod_test_hooks
        {
            float consume_last_kernel_ms();
        }
    }
}

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::RealArray;
    using cusignal::core::Shape;

    struct CliOptions
    {
        bool emit_report = false; // 是否在 data/reports 下输出 markdown/json/csv 报告
        bool gpu_only_perf = false; // perf 模式下跳过 CPU 输出与 CPU 计时
        std::string case_set = "accuracy"; // 用例集合：accuracy / perf / full / smoke
        int warmup = 5; // 基准统计前的不计时预热次数
        int repeat = 30; // 用于统计延迟的计时迭代次数
    };

    struct ErrorMetrics
    {
        float max_abs_error = 0.0f;
        float max_rel_error = 0.0f;
        float mixed_error = 0.0f;
        float rmse = 0.0f;
    };

    struct TimingStats
    {
        float mean_ms = 0.0f;
        float median_ms = 0.0f;
        float p95_ms = 0.0f;
        float min_ms = 0.0f;
        float max_ms = 0.0f;
        float std_ms = 0.0f;
    };

    struct Summary
    {
        bool pass = true;
        int accuracy_cases = 0;
        int perf_cases = 0;
        ErrorMetrics cpu_gpu_error;
        ErrorMetrics reference_error;
        std::optional<TimingStats> cpu_perf;
        std::optional<TimingStats> gpu_e2e_perf;
        std::optional<TimingStats> gpu_kernel_perf;
    };

    struct Case
    {
        std::string id;
        ComplexArray input;
        int axis = -1; // fm_demod 相位差分所沿用的轴
        RealArray expected;
        bool expect_exception = false; // 标记该用例是否应抛出异常
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path generated_root()
    {
        return cusignal_test::live_perf::generated_unit_root(
                   repo_root() / "data" / "generated" / "unit") /
               "demod" / "fm_demod";
    }

    fs::path report_root()
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "demod" / "fm_demod";
    }

    std::string read_text_file(const fs::path &path)
    {
        std::ifstream input(path);
        if (!input)
        {
            throw std::runtime_error("failed to open file: " + path.string());
        }
        std::ostringstream buffer;
        buffer << input.rdbuf();
        return buffer.str();
    }

    CliOptions parse_args(int argc, char **argv)
    {
        CliOptions options;
        for (int index = 1; index < argc; ++index)
        {
            const std::string arg = argv[index];
            if (arg == "--emit-report")
            {
                options.emit_report = true;
            }
            else if (arg == "--gpu-only-perf")
            {
                options.gpu_only_perf = true;
            }
            else if (arg == "--case-set" && index + 1 < argc)
            {
                options.case_set = argv[++index];
            }
            else if (arg == "--warmup" && index + 1 < argc)
            {
                options.warmup = std::stoi(argv[++index]);
            }
            else if (arg == "--repeat" && index + 1 < argc)
            {
                options.repeat = std::stoi(argv[++index]);
            }
        }
        return options;
    }

    ComplexArray make_complex_array(const Shape &shape, const std::vector<Complex> &values)
    {
        ComplexArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    RealArray make_real_array(const Shape &shape, const std::vector<float> &values)
    {
        RealArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    std::string format_float(float value)
    {
        std::ostringstream stream;
        stream << std::scientific << std::setprecision(6) << value;
        return stream.str();
    }

    std::string format_fixed(float value)
    {
        std::ostringstream stream;
        stream << std::fixed << std::setprecision(3) << value;
        return stream.str();
    }

    ErrorMetrics compare_real(const std::vector<float> &lhs, const std::vector<float> &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("shape mismatch while comparing real outputs");
        }
        ErrorMetrics metrics;
        if (lhs.empty())
        {
            return metrics;
        }
        float sq = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float abs_error = std::fabs(static_cast<float>(lhs[index] - rhs[index]));
            const float denom = std::max(std::fabs(static_cast<float>(rhs[index])), 1e-12f);
            const float rel_error = abs_error / denom;
            metrics.max_abs_error = std::max(metrics.max_abs_error, static_cast<float>(abs_error));
            metrics.max_rel_error = std::max(metrics.max_rel_error, static_cast<float>(rel_error));
            sq += abs_error * abs_error;
        }
        metrics.rmse = static_cast<float>(std::sqrt(sq / static_cast<float>(lhs.size())));
        return metrics;
    }

    TimingStats summarize(std::vector<float> samples)
    {
        TimingStats stats;
        if (samples.empty())
        {
            return stats;
        }
        std::sort(samples.begin(), samples.end());
        const float sum = std::accumulate(samples.begin(), samples.end(), 0.0f);
        stats.mean_ms = sum / static_cast<float>(samples.size());
        stats.median_ms = samples.size() % 2 == 0
                              ? 0.5f * (samples[samples.size() / 2 - 1] + samples[samples.size() / 2])
                              : samples[samples.size() / 2];
        stats.p95_ms = samples[std::min(samples.size() - 1, (samples.size() * 95) / 100)];
        stats.min_ms = samples.front();
        stats.max_ms = samples.back();
        float variance_sum = 0.0;
        for (const float sample : samples)
        {
            const float diff = static_cast<float>(sample) - stats.mean_ms;
            variance_sum += diff * diff;
        }
        stats.std_ms = static_cast<float>(std::sqrt(variance_sum / static_cast<float>(samples.size())));
        return stats;
    }

    template <typename Callable>
    TimingStats measure(int warmup, int repeat, Callable callable)
    {
        for (int index = 0; index < warmup; ++index)
        {
            callable();
        }
        std::vector<float> samples;
        samples.reserve(static_cast<std::size_t>(repeat));
        for (int index = 0; index < repeat; ++index)
        {
            const auto start = std::chrono::steady_clock::now();
            callable();
            const auto stop = std::chrono::steady_clock::now();
            samples.push_back(
                std::chrono::duration<float, std::milli>(stop - start).count());
        }
        return summarize(std::move(samples));
    }

    void write_complex_csv(const fs::path &path, const std::vector<Complex> &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,real,imag\n";
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output << index << "," << values[index].real() << "," << values[index].imag() << "\n";
        }
    }

    void write_real_csv(const fs::path &path, const std::vector<float> &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,value\n";
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output << index << "," << values[index] << "\n";
        }
    }

    void write_reports(const Summary &summary, const CliOptions &options)
    {
        if (!options.emit_report)
        {
            return;
        }
        fs::create_directories(report_root());
        {
            std::ofstream output(report_root() / "latest_summary.md");
            output << "# fm_demod\n\n";
            output << "- pass: " << (summary.pass ? "true" : "false") << "\n";
            output << "- accuracy_cases: " << summary.accuracy_cases << "\n";
            output << "- perf_cases: " << summary.perf_cases << "\n";
        }
        {
            cusignal_test::report::write_summary_only_metrics(
                "demod",
                "fm_demod",
                repo_root(),
                report_root(),
                __cplusplus,
                CUDART_VERSION,
                options,
                summary);
        }
        {
            std::ofstream output(report_root() / "latest_cases.csv");
            output << "case_id,category,pass\nsummary,aggregate," << (summary.pass ? "1" : "0") << "\n";
        }
    }

    float reference_wrapped_phase_difference(const Complex &current, const Complex &next)
    {
        float delta = std::atan2(next.imag(), next.real()) -
            std::atan2(current.imag(), current.real());
        if (delta > 3.14159265358979323846f)
        {
            delta -= 6.28318530717958647692f;
        }
        else if (delta < -3.14159265358979323846f)
        {
            delta += 6.28318530717958647692f;
        }
        return delta;
    }

    Case long_wrapped_phase_case()
    {
        constexpr std::size_t count = 4096;
        constexpr float phase_step = 2.9f;
        std::vector<Complex> values;
        values.reserve(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            const float phase = phase_step * static_cast<float>(index);
            values.emplace_back(std::cos(phase), std::sin(phase));
        }

        std::vector<float> expected(count - 1, 0.0f);
        for (std::size_t index = 0; index + 1 < count; ++index)
        {
            expected[index] = reference_wrapped_phase_difference(
                values[index], values[index + 1]);
        }
        return {
            "long_wrapped_phase",
            make_complex_array(Shape{count}, std::move(values)),
            -1,
            make_real_array(Shape{count - 1}, std::move(expected)),
            false};
    }

    Case amplitude_extremes_case()
    {
        const float huge = std::numeric_limits<float>::max() * 0.25f;
        const float tiny = std::numeric_limits<float>::min() * 4.0f;
        std::vector<Complex> values{
            Complex(huge, 0.0f),
            Complex(huge * std::cos(0.4f), huge * std::sin(0.4f)),
            Complex(tiny * std::cos(0.8f), tiny * std::sin(0.8f)),
            Complex(tiny * std::cos(1.2f), tiny * std::sin(1.2f)),
            Complex(0.0f, 0.0f),
            Complex(std::cos(0.5f), std::sin(0.5f))};
        const std::size_t count = values.size();
        std::vector<float> expected(count - 1, 0.0f);
        for (std::size_t index = 0; index + 1 < count; ++index)
        {
            expected[index] = reference_wrapped_phase_difference(
                values[index], values[index + 1]);
        }
        return {
            "amplitude_extremes",
            make_complex_array(Shape{count}, std::move(values)),
            -1,
            make_real_array(Shape{count - 1}, std::move(expected)),
            false};
    }

    std::vector<Case> accuracy_cases()
    {
        std::vector<Case> cases{
            {"constant_step",
             make_complex_array(
                 Shape{4},
                 {Complex(1.0f, 0.0f),
                  Complex(std::cos(0.5f), std::sin(0.5f)),
                  Complex(std::cos(1.0f), std::sin(1.0f)),
                  Complex(std::cos(1.5f), std::sin(1.5f))}),
             -1,
             make_real_array(Shape{3}, {0.5f, 0.5f, 0.5f}),
             false},
            {"unwrap_step",
             make_complex_array(
                 Shape{4},
                 {Complex(std::cos(2.8f), std::sin(2.8f)),
                  Complex(std::cos(3.1f), std::sin(3.1f)),
                  Complex(std::cos(-3.0f), std::sin(-3.0f)),
                  Complex(std::cos(-2.7f), std::sin(-2.7f))}),
             -1,
             make_real_array(Shape{3}, {0.29999995f, 0.18318558f, 0.29999995f}),
             false},
            {"matrix_axis0",
             make_complex_array(
                 Shape{3, 2},
                 {Complex(1.0f, 0.0f),
                  Complex(std::cos(1.0f), std::sin(1.0f)),
                  Complex(std::cos(0.5f), std::sin(0.5f)),
                  Complex(std::cos(1.5f), std::sin(1.5f)),
                  Complex(std::cos(1.0f), std::sin(1.0f)),
                  Complex(std::cos(2.0f), std::sin(2.0f))}),
             0,
             make_real_array(Shape{2, 2}, {0.5f, 0.5f, 0.5f, 0.5f}),
             false},
            {"invalid_axis",
             make_complex_array(Shape{2}, {Complex(1.0f, 0.0f), Complex(0.0f, 1.0f)}),
             3,
             {},
             true},
            {"single_sample",
             make_complex_array(Shape{1}, {Complex(1.0f, 0.0f)}),
             -1,
             make_real_array(Shape{0}, {}),
             false},
        };
        cases.push_back(long_wrapped_phase_case());
        cases.push_back(amplitude_extremes_case());
        return cases;
    }

    Case perf_case()
    {
        Shape shape{64, 512};
        int axis = -1;
        float phase_step = 0.01f;

        const fs::path manifest_path = generated_root() / "manifest.json";
        if (fs::exists(manifest_path))
        {
            const auto root = cusignal_test::json::parse(read_text_file(manifest_path)).as_object();
            const auto &cases = root.at("perf_cases").as_array();
            if (cases.empty())
            {
                throw std::runtime_error("fm_demod manifest has no perf_cases");
            }
            const auto &object = cases.front().as_object();
            const auto shape_iter = object.find("shape");
            if (shape_iter != object.end())
            {
                shape.clear();
                for (const auto &value : shape_iter->second.as_array())
                {
                    shape.push_back(static_cast<std::size_t>(value.as_number()));
                }
            }
            const auto axis_iter = object.find("axis");
            if (axis_iter != object.end())
            {
                axis = static_cast<int>(axis_iter->second.as_number());
            }
            const auto phase_iter = object.find("phase_step");
            if (phase_iter != object.end())
            {
                phase_step = phase_iter->second.as_number();
            }
        }

        std::size_t size = 1;
        for (const std::size_t extent : shape)
        {
            size *= extent;
        }
        std::vector<Complex> values(size, Complex(0.0f, 0.0f));
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            const float phase = phase_step * static_cast<float>(index);
            values[index] = Complex(std::cos(phase), std::sin(phase));
        }
        return {"perf_case", make_complex_array(shape, values), axis, {}, false};
    }

    float speedup(const std::optional<TimingStats> &cpu, const std::optional<TimingStats> &gpu)
    {
        if (!cpu.has_value() || !gpu.has_value() || gpu->median_ms <= 0.0f)
        {
            return 0.0f;
        }
        return cpu->median_ms / gpu->median_ms;
    }
} // namespace

int run_fm_demod_tests(int argc, char **argv)
{
    const CliOptions options = parse_args(argc, argv);
    Summary summary;

    if (options.case_set == "accuracy" || options.case_set == "full" || options.case_set == "smoke")
    {
        for (const Case &test_case : accuracy_cases())
        {
            summary.accuracy_cases += 1;
            bool cpu_exception = false;
            bool gpu_exception = false;
            RealArray cpu;
            RealArray gpu;
            try
            {
                cpu = cusignal::cpu::demod::fm_demod(test_case.input, test_case.axis);
            }
            catch (const std::exception &)
            {
                cpu_exception = true;
            }
            try
            {
                gpu = cusignal::zx_gpu_backend::demod::fm_demod(test_case.input, test_case.axis).get();
            }
            catch (const std::exception &)
            {
                gpu_exception = true;
            }

            if (test_case.expect_exception)
            {
                summary.pass = summary.pass && cpu_exception && gpu_exception;
                continue;
            }

            if (cpu_exception || gpu_exception)
            {
                summary.pass = false;
                continue;
            }

            const ErrorMetrics cpu_gpu = compare_real(cpu.values, gpu.values);
            const ErrorMetrics cpu_ref = compare_real(cpu.values, test_case.expected.values);
            const ErrorMetrics gpu_ref = compare_real(gpu.values, test_case.expected.values);
            summary.cpu_gpu_error.max_abs_error =
                std::max(summary.cpu_gpu_error.max_abs_error, cpu_gpu.max_abs_error);
            summary.cpu_gpu_error.max_rel_error =
                std::max(summary.cpu_gpu_error.max_rel_error, cpu_gpu.max_rel_error);
            summary.cpu_gpu_error.rmse =
                std::max(summary.cpu_gpu_error.rmse, cpu_gpu.rmse);
            summary.reference_error.max_abs_error =
                std::max({summary.reference_error.max_abs_error, cpu_ref.max_abs_error, gpu_ref.max_abs_error});
            summary.reference_error.max_rel_error =
                std::max({summary.reference_error.max_rel_error, cpu_ref.max_rel_error, gpu_ref.max_rel_error});
            summary.reference_error.rmse =
                std::max({summary.reference_error.rmse, cpu_ref.rmse, gpu_ref.rmse});
            summary.pass = summary.pass &&
                           cpu_ref.max_abs_error < 1e-4f &&
                           gpu_ref.max_abs_error < 1e-4f;
        }
    }

    if (options.case_set == "perf" || options.case_set == "full" || options.case_set == "smoke")
        {
            summary.perf_cases = 1;
            const Case perf = perf_case();
            const ZxGpuComplexArray device_input = ZxGpuComplexArray::from_host(perf.input);
            auto gpu_perf = [&]() {
                return cusignal::zx_gpu_backend::demod::fm_demod(device_input, perf.axis);
            };
            if (!options.gpu_only_perf)
            {
                summary.cpu_perf = measure(options.warmup, options.repeat, [&]() {
                    (void)cusignal::cpu::demod::fm_demod(perf.input, perf.axis);
                });
        }

        std::vector<float> kernel_samples;
            summary.gpu_e2e_perf = measure(options.warmup, options.repeat, [&]() {
                (void)cusignal::zx_gpu_backend::demod_test_hooks::consume_last_kernel_ms();
                // E2E must include a fresh H2D upload and D2H materialization.
                const ZxGpuComplexArray fresh_input = ZxGpuComplexArray::from_host(perf.input);
                (void)cusignal::zx_gpu_backend::demod::fm_demod(fresh_input, perf.axis).get();
                cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
                kernel_samples.push_back(cusignal::zx_gpu_backend::demod_test_hooks::consume_last_kernel_ms());
            });
            summary.gpu_kernel_perf = summarize(std::move(kernel_samples));

            if (options.emit_report)
            {
                if (!options.gpu_only_perf)
                {
                    write_complex_csv(generated_root() / "input" / "perf_case__x.csv", perf.input.values);
                    const RealArray gpu = gpu_perf().get();
                    const RealArray cpu = cusignal::cpu::demod::fm_demod(perf.input, perf.axis);
                    write_real_csv(generated_root() / "output_samples" / "perf_case__cpu__signal.csv", cpu.values);
                    write_real_csv(generated_root() / "output_samples" / "perf_case__gpu__signal.csv", gpu.values);
                }
            }
        }

    std::cout << "[demod/fm_demod] " << (summary.pass ? "PASS" : "FAIL")
              << "  accuracy_cases=" << summary.accuracy_cases
              << "  perf_cases=" << summary.perf_cases << "\n";
    std::cout << "cpu_gpu_error : max_abs=" << format_float(summary.cpu_gpu_error.max_abs_error)
              << "  max_rel=" << format_float(summary.cpu_gpu_error.max_rel_error)
              << "  rmse=" << format_float(summary.cpu_gpu_error.rmse) << "\n";
    std::cout << "reference_error : max_abs=" << format_float(summary.reference_error.max_abs_error)
              << "  max_rel=" << format_float(summary.reference_error.max_rel_error)
              << "  rmse=" << format_float(summary.reference_error.rmse) << "\n";
    if (summary.cpu_perf.has_value())
    {
        std::cout << "cpu_perf_ms   : median=" << format_fixed(summary.cpu_perf->median_ms)
                  << "  mean=" << format_fixed(summary.cpu_perf->mean_ms)
                  << "  p95=" << format_fixed(summary.cpu_perf->p95_ms) << "\n";
    }
    if (summary.gpu_e2e_perf.has_value())
    {
        const bool kernel_valid = summary.gpu_kernel_perf.has_value() &&
                                  summary.gpu_kernel_perf->median_ms > 0.0f;
        std::cout << "gpu_perf_ms   : e2e_median=" << format_fixed(summary.gpu_e2e_perf->median_ms)
                  << "  kernel_median="
                  << (kernel_valid ? format_fixed(summary.gpu_kernel_perf->median_ms) : "n/a")
                  << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                  << "  e2e_speedup=" << format_fixed(speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x"
                  << "  kernel_speedup="
                  << (kernel_valid ? format_fixed(speedup(summary.cpu_perf, summary.gpu_kernel_perf)) + "x" : "n/a")
                  << "\n";
    }
    if (options.emit_report)
    {
        write_reports(summary, options);
        std::cout << "reports       : "
                  << (report_root() / "latest_summary.md").lexically_relative(repo_root()).string() << "\n";
    }
    return summary.pass ? 0 : 1;
}
