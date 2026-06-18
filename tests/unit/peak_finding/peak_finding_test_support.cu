#include "peak_finding_test_support.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "../../../include/cusignal/core/helpers.hpp"
#include "../../../include/cusignal/peak_finding/peak_finding.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace peak_finding_test_hooks
        {
            float consume_last_kernel_ms();
        }
    }
}

namespace
{
    namespace peak_api = cusignal::peak_finding_api;
    using cusignal::core::AxisIndices;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::DeviceAxisIndices;
    using cusignal::core::IndexVector;
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
        RealArray data;
        std::string comparator; // argrelextrema 比较器：greater / less
        int axis = 0; // 极值搜索所沿用的轴
        int order = 1; // 局部比较邻域半宽
        std::string mode = "clip"; // 边界处理方式：clip / wrap
        AxisIndices expected;
        bool expect_exception = false; // 标记该用例是否应抛出异常
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path generated_root(const std::string &op)
    {
        return repo_root() / "data" / "generated" / "unit" / "peak_finding" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / "reports" / "unit" / "peak_finding" / op;
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

    ErrorMetrics compare_indices(const AxisIndices &lhs, const AxisIndices &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("axis count mismatch while comparing indices");
        }
        ErrorMetrics metrics;
        float sq = 0.0;
        std::size_t count = 0;
        for (std::size_t axis = 0; axis < lhs.size(); ++axis)
        {
            if (lhs[axis].size() != rhs[axis].size())
            {
                throw std::runtime_error("index size mismatch while comparing indices");
            }
            for (std::size_t index = 0; index < lhs[axis].size(); ++index)
            {
                const float abs_error = std::fabs(static_cast<float>(lhs[axis][index] - rhs[axis][index]));
                const float denom =
                    std::max(std::fabs(static_cast<float>(rhs[axis][index])), 1e-30f);
                metrics.max_abs_error = std::max(metrics.max_abs_error, static_cast<float>(abs_error));
                metrics.max_rel_error =
                    std::max(metrics.max_rel_error, static_cast<float>(abs_error / denom));
                sq += abs_error * abs_error;
                count += 1;
            }
        }
        if (count != 0)
        {
            metrics.rmse = static_cast<float>(std::sqrt(sq / static_cast<float>(count)));
        }
        return metrics;
    }

    AxisIndices to_host(const DeviceAxisIndices &device)
    {
        AxisIndices host;
        host.reserve(device.size());
        for (const auto &axis : device)
        {
            host.push_back(axis.get());
        }
        return host;
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
        stats.median_ms = samples[samples.size() / 2];
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

    void write_index_csv(const fs::path &path, const IndexVector &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,value\n";
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output << index << "," << values[index] << "\n";
        }
    }

    void write_reports(const std::string &op, const Summary &summary, const CliOptions &options)
    {
        if (!options.emit_report)
        {
            return;
        }
        fs::create_directories(report_root(op));
        {
            std::ofstream output(report_root(op) / "latest_summary.md");
            output << "# " << op << "\n\n";
            output << "- pass: " << (summary.pass ? "true" : "false") << "\n";
            output << "- accuracy_cases: " << summary.accuracy_cases << "\n";
            output << "- perf_cases: " << summary.perf_cases << "\n";
        }
        {
            cusignal_test::report::write_summary_only_metrics(
                "peak_finding",
                op,
                repo_root(),
                report_root(op),
                __cplusplus,
                CUDART_VERSION,
                options,
                summary);
        }
        {
            std::ofstream output(report_root(op) / "latest_cases.csv");
            output << "case_id,category,pass\nsummary,aggregate," << (summary.pass ? "1" : "0") << "\n";
        }
    }

    std::vector<Case> argrelmax_cases()
    {
        return {
            {"max_1d",
             make_real_array(Shape{7}, {1, 3, 2, 4, 3, 5, 1}),
             "greater",
             0,
             1,
             "clip",
             AxisIndices{{1, 3, 5}},
             false},
            {"max_2d_axis1",
             make_real_array(Shape{2, 5}, {1, 3, 2, 4, 3, 0, 1, 0, 2, 1}),
             "greater",
             1,
             1,
             "clip",
             AxisIndices{{0, 0, 1, 1}, {1, 3, 1, 3}},
             false},
            {"plateau_none",
             make_real_array(Shape{4}, {1, 2, 2, 1}),
             "greater",
             0,
             1,
             "clip",
             AxisIndices{{}},
             false},
        };
    }

    std::vector<Case> argrelmin_cases()
    {
        return {
            {"min_1d",
             make_real_array(Shape{5}, {3, 1, 2, 0, 1}),
             "less",
             0,
             1,
             "clip",
             AxisIndices{{1, 3}},
             false},
            {"min_wrap",
             make_real_array(Shape{3}, {2, 1, 2}),
             "less",
             0,
             1,
             "wrap",
             AxisIndices{{1}},
             false},
        };
    }

    std::vector<Case> argrelextrema_cases()
    {
        return {
            {"extrema_greater_order2",
             make_real_array(Shape{9}, {0, 1, 3, 1, 0, 2, 5, 1, 0}),
             "greater",
             0,
             2,
             "clip",
             AxisIndices{{2, 6}},
             false},
            {"extrema_less_2d",
             make_real_array(Shape{2, 5}, {2, 1, 2, 0, 2, 5, 4, 5, 3, 5}),
             "less",
             1,
             1,
             "clip",
             AxisIndices{{0, 0, 1, 1}, {1, 3, 1, 3}},
             false},
            {"invalid_order",
             make_real_array(Shape{3}, {1, 0, 1}),
             "greater",
             0,
             0,
             "clip",
             {},
             true},
        };
    }

    Case perf_case(const std::string &comparator)
    {
        Shape shape{128, 256};
        int axis = 1;
        int order = 2;
        std::string mode = "clip";
        const fs::path manifest_path = generated_root("argrelextrema") / "manifest.json";
        if (fs::exists(manifest_path))
        {
            const auto root = cusignal_test::json::parse(read_text_file(manifest_path)).as_object();
            const auto &cases = root.at("perf_cases").as_array();
            if (cases.empty())
            {
                throw std::runtime_error("argrelextrema manifest has no perf_cases");
            }
            const auto &object = cases.front().as_object();
            if (const auto iter = object.find("shape"); iter != object.end())
            {
                shape.clear();
                for (const auto &value : iter->second.as_array())
                {
                    shape.push_back(static_cast<std::size_t>(value.as_number()));
                }
            }
            if (const auto iter = object.find("axis"); iter != object.end())
            {
                axis = static_cast<int>(iter->second.as_number());
            }
            if (const auto iter = object.find("order"); iter != object.end())
            {
                order = static_cast<int>(iter->second.as_number());
            }
            if (const auto iter = object.find("mode"); iter != object.end())
            {
                mode = iter->second.as_string();
            }
        }

        const std::size_t total = cusignal::core::shape_product(shape);
        const std::size_t axis_index = static_cast<std::size_t>(cusignal::core::normalize_axis(axis, shape.size()));
        const std::size_t axis_len = shape[axis_index];
        std::vector<float> values(total, 0.0f);
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            const float coord = static_cast<float>(axis_len == 0 ? 0 : index % axis_len);
            values[index] = std::sin(0.05f * coord) + 0.0001f * static_cast<float>(index / std::max<std::size_t>(axis_len, 1));
        }
        return {"perf_case", make_real_array(shape, values), comparator, axis, order, mode, {}, false};
    }

    float speedup(const std::optional<TimingStats> &cpu, const std::optional<TimingStats> &gpu)
    {
        if (!cpu.has_value() || !gpu.has_value() || gpu->median_ms <= 0.0f)
        {
            return 0.0f;
        }
        return cpu->median_ms / gpu->median_ms;
    }

    template <typename CpuCallable, typename GpuCallable>
    Summary run_cases(
        const std::string &op,
        const std::vector<Case> &cases,
        const CliOptions &options,
        CpuCallable cpu_callable,
        GpuCallable gpu_callable)
    {
        Summary summary;
        if (options.case_set == "accuracy" || options.case_set == "full" || options.case_set == "smoke")
        {
            for (const Case &test_case : cases)
            {
                summary.accuracy_cases += 1;
                bool cpu_exception = false;
                bool gpu_exception = false;
                peak_api::ExtremaResult cpu_result;
                peak_api::ZxGpuExtremaResult gpu_result;
                try
                {
                    cpu_result = cpu_callable(test_case);
                }
                catch (const std::exception &)
                {
                    cpu_exception = true;
                }
                try
                {
                    gpu_result = gpu_callable(test_case);
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

                const AxisIndices gpu_host = to_host(gpu_result.indices);
                const ErrorMetrics cpu_gpu = compare_indices(cpu_result.indices, gpu_host);
                const ErrorMetrics cpu_ref = compare_indices(cpu_result.indices, test_case.expected);
                const ErrorMetrics gpu_ref = compare_indices(gpu_host, test_case.expected);
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
                               cpu_ref.max_abs_error == 0.0f &&
                               gpu_ref.max_abs_error == 0.0f;
            }
        }

        if (options.case_set == "perf" || options.case_set == "full" || options.case_set == "smoke")
        {
            summary.perf_cases = 1;
            const Case perf = perf_case(op == "argrelmin" ? "less" : "greater");
            const ZxGpuRealArray device_data = ZxGpuRealArray::from_host(perf.data);
            auto gpu_perf = [&]() {
                return cusignal::zx_gpu_backend::peak_finding::argrelextrema(
                    device_data,
                    perf.comparator,
                    perf.axis,
                    perf.order,
                    perf.mode);
            };
            if (!options.gpu_only_perf)
            {
                summary.cpu_perf = measure(options.warmup, options.repeat, [&]() {
                    (void)cpu_callable(perf);
                });
            }
            std::vector<float> kernel_samples;
            summary.gpu_e2e_perf = measure(options.warmup, options.repeat, [&]() {
                (void)cusignal::zx_gpu_backend::peak_finding_test_hooks::consume_last_kernel_ms();
                (void)gpu_perf();
                cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
                kernel_samples.push_back(cusignal::zx_gpu_backend::peak_finding_test_hooks::consume_last_kernel_ms());
            });
            summary.gpu_kernel_perf = summarize(std::move(kernel_samples));

            if (options.emit_report)
            {
                if (!options.gpu_only_perf)
                {
                    write_real_csv(generated_root(op) / "input" / "perf_case__data.csv", perf.data.values);
                    const AxisIndices gpu = to_host(gpu_perf().indices);
                    const AxisIndices cpu = cpu_callable(perf).indices;
                    for (std::size_t axis = 0; axis < cpu.size(); ++axis)
                    {
                        write_index_csv(
                            generated_root(op) / "output_samples" /
                                ("perf_case__cpu__axis" + std::to_string(axis) + "_indices.csv"),
                            cpu[axis]);
                    }
                    for (std::size_t axis = 0; axis < gpu.size(); ++axis)
                    {
                        write_index_csv(
                            generated_root(op) / "output_samples" /
                                ("perf_case__gpu__axis" + std::to_string(axis) + "_indices.csv"),
                            gpu[axis]);
                    }
                }
            }
        }

        std::cout << "[peak_finding/" << op << "] " << (summary.pass ? "PASS" : "FAIL")
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
            std::cout << "gpu_perf_ms   : e2e_median=" << format_fixed(summary.gpu_e2e_perf->median_ms)
                      << "  kernel_median="
                      << format_fixed(summary.gpu_kernel_perf.has_value() ? summary.gpu_kernel_perf->median_ms : 0.0f)
                      << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                      << "  e2e_speedup=" << format_fixed(speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x"
                      << "  kernel_speedup=" << format_fixed(speedup(summary.cpu_perf, summary.gpu_kernel_perf)) << "x\n";
        }
        if (options.emit_report)
        {
            write_reports(op, summary, options);
            std::cout << "reports       : "
                      << (report_root(op) / "latest_summary.md").lexically_relative(repo_root()).string() << "\n";
        }
        return summary;
    }
} // namespace

int run_argrelextrema_tests(int argc, char **argv)
{
    const CliOptions options = parse_args(argc, argv);
    const auto cpu = [](const Case &test_case) {
        return cusignal::cpu::peak_finding::argrelextrema(
            test_case.data,
            test_case.comparator,
            test_case.axis,
            test_case.order,
            test_case.mode);
    };
    const auto gpu = [](const Case &test_case) {
        return cusignal::zx_gpu_backend::peak_finding::argrelextrema(
            test_case.data,
            test_case.comparator,
            test_case.axis,
            test_case.order,
            test_case.mode);
    };
    return run_cases("argrelextrema", argrelextrema_cases(), options, cpu, gpu).pass ? 0 : 1;
}

int run_argrelmin_tests(int argc, char **argv)
{
    const CliOptions options = parse_args(argc, argv);
    const auto cpu = [](const Case &test_case) {
        return cusignal::cpu::peak_finding::argrelmin(
            test_case.data,
            test_case.axis,
            test_case.order,
            test_case.mode);
    };
    const auto gpu = [](const Case &test_case) {
        return cusignal::zx_gpu_backend::peak_finding::argrelmin(
            test_case.data,
            test_case.axis,
            test_case.order,
            test_case.mode);
    };
    return run_cases("argrelmin", argrelmin_cases(), options, cpu, gpu).pass ? 0 : 1;
}

int run_argrelmax_tests(int argc, char **argv)
{
    const CliOptions options = parse_args(argc, argv);
    const auto cpu = [](const Case &test_case) {
        return cusignal::cpu::peak_finding::argrelmax(
            test_case.data,
            test_case.axis,
            test_case.order,
            test_case.mode);
    };
    const auto gpu = [](const Case &test_case) {
        return cusignal::zx_gpu_backend::peak_finding::argrelmax(
            test_case.data,
            test_case.axis,
            test_case.order,
            test_case.mode);
    };
    return run_cases("argrelmax", argrelmax_cases(), options, cpu, gpu).pass ? 0 : 1;
}
