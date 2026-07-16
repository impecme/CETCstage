#include "correlate_test_support.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "../../../include/cusignal/core/helpers.hpp"
#include "../../../include/cusignal/correlate/correlate.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace correlate_test_hooks
        {
            float consume_last_kernel_ms();
            bool last_correlation_used_fft();
        }
    }
}

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::Float16;
    using cusignal::core::Float16Array;
    using cusignal::core::Int16;
    using cusignal::core::Int16Array;
    using cusignal::core::Int32;
    using cusignal::core::Int32Array;
    using cusignal::core::Int8;
    using cusignal::core::Int8Array;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuFloat16Array;
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuInt16Array;
    using cusignal::core::ZxGpuInt32Array;
    using cusignal::core::ZxGpuInt8Array;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::IndexVector;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;

    struct CliOptions
    {
        bool emit_report = false; // 是否在 data/reports 下输出 markdown/json/csv 报告
        bool gpu_only_perf = false; // perf 模式下跳过 CPU 输出与 CPU 计时
        bool verbose = false; // 是否在 stdout 打印逐用例诊断信息
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
        std::vector<float> samples_ms;
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

    struct CorrCase
    {
        std::string id;
        std::string category;
        std::string mode; // correlate 输出模式：full / same / valid
        std::string method; // correlate 算法提示：auto / direct / fft
        bool is_complex = false; // 选择实数或复数相关计算路径
        std::string dtype = "float32"; // 实数兼容路径的目标 dtype
        Shape shape1;
        Shape shape2;
        RealArray in1_real;
        RealArray in2_real;
        ComplexArray in1_complex;
        ComplexArray in2_complex;
        RealArray expected_real;
        ComplexArray expected_complex;
    };

    struct LagCase
    {
        std::string id;
        std::string category;
        int in1_len = 0; // correlation_lags 的第一个信号长度
        int in2_len = 0; // correlation_lags 的第二个信号长度
        std::string mode; // lags 模式：full / same / valid
        IndexVector expected;
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path generated_root(const std::string &op)
    {
        return repo_root() / "data" / "generated" / "unit" / "correlate" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / "reports" / "unit" / "correlate" / op;
    }

    RealArray make_real_array(const Shape &shape, const std::vector<float> &values)
    {
        RealArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    template <typename T>
    cusignal::core::Array<T> make_typed_array(const Shape &shape, const std::vector<T> &values)
    {
        cusignal::core::Array<T> array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    ComplexArray make_complex_array(const Shape &shape, const std::vector<Complex> &values)
    {
        ComplexArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    ErrorMetrics compare_real(const std::vector<float> &lhs, const std::vector<float> &rhs);

    template <typename T>
    float scalar_to_float(const T &value)
    {
        return static_cast<float>(value);
    }

    template <>
    float scalar_to_float<Float16>(const Float16 &value)
    {
        return static_cast<float>(value);
    }

    template <typename T>
    T scalar_from_float(float value)
    {
        return static_cast<T>(std::llround(value));
    }

    template <>
    Float16 scalar_from_float<Float16>(float value)
    {
        return Float16(value);
    }

    template <>
    float scalar_from_float<float>(float value)
    {
        return value;
    }

    template <typename T>
    RealArray to_real_array(const cusignal::core::Array<T> &array)
    {
        RealArray output;
        output.shape = array.shape;
        output.values.reserve(array.values.size());
        for (const T &value : array.values)
        {
            output.values.push_back(scalar_to_float(value));
        }
        return output;
    }

    template <typename T>
    cusignal::core::Array<T> from_real_array(const RealArray &array)
    {
        cusignal::core::Array<T> output;
        output.shape = array.shape;
        output.values.reserve(array.values.size());
        for (float value : array.values)
        {
            output.values.push_back(scalar_from_float<T>(value));
        }
        return output;
    }

    template <typename T>
    ErrorMetrics compare_typed_as_float(
        const cusignal::core::Array<T> &lhs,
        const cusignal::core::Array<T> &rhs)
    {
        std::vector<float> lhs_values;
        std::vector<float> rhs_values;
        lhs_values.reserve(lhs.values.size());
        rhs_values.reserve(rhs.values.size());
        for (const T &value : lhs.values)
        {
            lhs_values.push_back(scalar_to_float(value));
        }
        for (const T &value : rhs.values)
        {
            rhs_values.push_back(scalar_to_float(value));
        }
        return compare_real(lhs_values, rhs_values);
    }

    template <typename T, typename DeviceArrayType>
    void evaluate_typed_compat_case(
        const CorrCase &test_case,
        Summary &summary,
        const std::vector<T> &left_values,
        const std::vector<T> &right_values,
        const std::vector<T> &expected_values,
        bool is_2d)
    {
        const auto left = make_typed_array<T>(test_case.shape1, left_values);
        const auto right = make_typed_array<T>(test_case.shape2, right_values);
        const auto expected = make_typed_array<T>(
            is_2d ? Shape{3, 3} : Shape{5},
            expected_values);

        const DeviceArrayType left_device = DeviceArrayType::from_host(left);
        const DeviceArrayType right_device = DeviceArrayType::from_host(right);
        const auto left_roundtrip = left_device.get();
        const auto right_roundtrip = right_device.get();

        const RealArray left_real = to_real_array(left_roundtrip);
        const RealArray right_real = to_real_array(right_roundtrip);
        const RealArray cpu_real = is_2d
            ? cusignal::cpu::correlate::correlate2d(left_real, right_real, test_case.mode, "wrap", 0.0f)
            : cusignal::cpu::correlate::correlate(left_real, right_real, test_case.mode, test_case.method);
        const RealArray gpu_real = is_2d
            ? cusignal::zx_gpu_backend::correlate::correlate2d(left_real, right_real, test_case.mode, "wrap", 0.0f).get()
            : cusignal::zx_gpu_backend::correlate::correlate(left_real, right_real, test_case.mode, test_case.method).get();

        const auto cpu = from_real_array<T>(cpu_real);
        const auto gpu = from_real_array<T>(gpu_real);
        const ErrorMetrics cpu_gpu = compare_typed_as_float(cpu, gpu);
        const ErrorMetrics cpu_ref = compare_typed_as_float(cpu, expected);
        const ErrorMetrics gpu_ref = compare_typed_as_float(gpu, expected);
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

    void evaluate_numeric_compat_case(const CorrCase &test_case, Summary &summary, bool is_2d)
    {
        if (is_2d)
        {
            if (test_case.dtype == "float16")
            {
                evaluate_typed_compat_case<Float16, ZxGpuFloat16Array>(
                    test_case,
                    summary,
                    {Float16(1.0f), Float16(2.0f), Float16(3.0f), Float16(4.0f)},
                    {Float16(0.0f), Float16(1.0f), Float16(2.0f), Float16(1.0f)},
                    {Float16(8.0f), Float16(8.0f), Float16(8.0f), Float16(12.0f), Float16(12.0f), Float16(12.0f), Float16(8.0f), Float16(8.0f), Float16(8.0f)},
                    true);
            }
            else if (test_case.dtype == "int8")
            {
                evaluate_typed_compat_case<Int8, ZxGpuInt8Array>(
                    test_case, summary, {1, 2, 3, 4}, {0, 1, 2, 1}, {8, 8, 8, 12, 12, 12, 8, 8, 8}, true);
            }
            else if (test_case.dtype == "int16")
            {
                evaluate_typed_compat_case<Int16, ZxGpuInt16Array>(
                    test_case, summary, {1, 2, 3, 4}, {0, 1, 2, 1}, {8, 8, 8, 12, 12, 12, 8, 8, 8}, true);
            }
            else if (test_case.dtype == "int32")
            {
                evaluate_typed_compat_case<Int32, ZxGpuInt32Array>(
                    test_case, summary, {1, 2, 3, 4}, {0, 1, 2, 1}, {8, 8, 8, 12, 12, 12, 8, 8, 8}, true);
            }
            else
            {
                throw std::runtime_error("unsupported correlate2d dtype compatibility case: " + test_case.dtype);
            }
            return;
        }

        if (test_case.dtype == "float16")
        {
            evaluate_typed_compat_case<Float16, ZxGpuFloat16Array>(
                test_case,
                summary,
                {Float16(1.0f), Float16(2.0f), Float16(3.0f)},
                {Float16(1.0f), Float16(0.0f), Float16(1.0f)},
                {Float16(1.0f), Float16(2.0f), Float16(4.0f), Float16(2.0f), Float16(3.0f)},
                false);
        }
        else if (test_case.dtype == "int8")
        {
            evaluate_typed_compat_case<Int8, ZxGpuInt8Array>(
                test_case, summary, {1, 2, 3}, {1, 0, 1}, {1, 2, 4, 2, 3}, false);
        }
        else if (test_case.dtype == "int16")
        {
            evaluate_typed_compat_case<Int16, ZxGpuInt16Array>(
                test_case, summary, {1, 2, 3}, {1, 0, 1}, {1, 2, 4, 2, 3}, false);
        }
        else if (test_case.dtype == "int32")
        {
            evaluate_typed_compat_case<Int32, ZxGpuInt32Array>(
                test_case, summary, {1, 2, 3}, {1, 0, 1}, {1, 2, 4, 2, 3}, false);
        }
        else
        {
            throw std::runtime_error("unsupported correlate dtype compatibility case: " + test_case.dtype);
        }
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
            else if (arg == "--verbose")
            {
                options.verbose = true;
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

    ErrorMetrics compare_complex(const std::vector<Complex> &lhs, const std::vector<Complex> &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("shape mismatch while comparing complex outputs");
        }
        ErrorMetrics metrics;
        if (lhs.empty())
        {
            return metrics;
        }
        float sq = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float abs_error = std::abs(lhs[index] - rhs[index]);
            const float denom = std::max(static_cast<float>(std::abs(rhs[index])), 1e-12f);
            const float rel_error = abs_error / denom;
            metrics.max_abs_error = std::max(metrics.max_abs_error, static_cast<float>(abs_error));
            metrics.max_rel_error = std::max(metrics.max_rel_error, static_cast<float>(rel_error));
            sq += abs_error * abs_error;
        }
        metrics.rmse = static_cast<float>(std::sqrt(sq / static_cast<float>(lhs.size())));
        return metrics;
    }

    ErrorMetrics compare_index(const IndexVector &lhs, const IndexVector &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("shape mismatch while comparing index outputs");
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
            metrics.max_abs_error = std::max(metrics.max_abs_error, static_cast<float>(abs_error));
            sq += abs_error * abs_error;
        }
        metrics.rmse = static_cast<float>(std::sqrt(sq / static_cast<float>(lhs.size())));
        return metrics;
    }

    TimingStats summarize_timings(std::vector<float> samples)
    {
        TimingStats stats;
        if (samples.empty())
        {
            return stats;
        }
        stats.samples_ms = samples;
        std::sort(samples.begin(), samples.end());
        const float sum = std::accumulate(samples.begin(), samples.end(), 0.0f);
        stats.mean_ms = sum / static_cast<float>(samples.size());
        stats.median_ms = samples[samples.size() / 2];
        const std::size_t p95_index =
            std::min(samples.size() - 1, (samples.size() * 95) / 100);
        stats.p95_ms = samples[p95_index];
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
    TimingStats measure_timing(int warmup, int repeat, Callable callable)
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
        return summarize_timings(std::move(samples));
    }

    TimingStats summarize_measured_kernel_timings(
        std::vector<float> samples,
        int warmup,
        int repeat)
    {
        if (warmup < 0 || repeat <= 0)
        {
            throw std::invalid_argument("timing requires warmup >= 0 and repeat > 0");
        }
        const std::size_t expected =
            static_cast<std::size_t>(warmup) + static_cast<std::size_t>(repeat);
        if (samples.size() != expected)
        {
            throw std::runtime_error("kernel timing sample count mismatch");
        }
        samples.erase(
            samples.begin(),
            samples.begin() + static_cast<std::ptrdiff_t>(warmup));
        return summarize_timings(std::move(samples));
    }

    void write_real_csv(const fs::path &path, const std::vector<float> &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,value\n";
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output << index << "," << std::setprecision(9) << values[index] << "\n";
        }
    }

    void write_complex_csv(const fs::path &path, const std::vector<Complex> &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        output << "index,real,imag\n";
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output << index << ","
                   << std::setprecision(9) << values[index].real() << ","
                   << std::setprecision(9) << values[index].imag() << "\n";
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

    void write_summary_files(
        const std::string &op,
        const Summary &summary,
        const CliOptions &options)
    {
        if (!options.emit_report)
        {
            return;
        }
        const fs::path root = report_root(op);
        fs::create_directories(root);

        {
            std::ofstream summary_file(root / "latest_summary.md");
            summary_file << "# " << op << "\n\n";
            summary_file << "- pass: " << (summary.pass ? "true" : "false") << "\n";
            summary_file << "- accuracy_cases: " << summary.accuracy_cases << "\n";
            summary_file << "- perf_cases: " << summary.perf_cases << "\n";
            summary_file << "- cpu_gpu_max_abs: " << summary.cpu_gpu_error.max_abs_error << "\n";
            summary_file << "- reference_max_abs: " << summary.reference_error.max_abs_error << "\n";
        }

        {
            cusignal_test::report::write_summary_only_metrics(
                "correlate",
                op,
                repo_root(),
                root,
                __cplusplus,
                CUDART_VERSION,
                options,
                summary);
        }

        {
            std::ofstream cases(root / "latest_cases.csv");
            cases << "case_id,category,pass\n";
            cases << "summary,aggregate," << (summary.pass ? "1" : "0") << "\n";
        }
    }

    float speedup(const std::optional<TimingStats> &cpu, const std::optional<TimingStats> &gpu)
    {
        if (!cpu.has_value() || !gpu.has_value() || gpu->median_ms <= 0.0f)
        {
            return 0.0f;
        }
        return cpu->median_ms / gpu->median_ms;
    }

    int report_and_return(
        const std::string &op,
        const Summary &summary,
        const CliOptions &options)
    {
        std::cout << "[correlate/" << op << "] "
                  << (summary.pass ? "PASS" : "FAIL")
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
                      << "  kernel_speedup=" << format_fixed(speedup(summary.cpu_perf, summary.gpu_kernel_perf)) << "x"
                      << "\n";
        }
        if (options.emit_report)
        {
            write_summary_files(op, summary, options);
            std::cout << "reports       : " << (report_root(op) / "latest_summary.md").lexically_relative(repo_root()).string() << "\n";
        }
        return summary.pass ? 0 : 1;
    }

    std::vector<CorrCase> correlate_accuracy_cases()
    {
        return {
            CorrCase{
                "real_full_direct",
                "accuracy",
                "full",
                "direct",
                false,
                "float32",
                Shape{3},
                Shape{3},
                make_real_array(Shape{3}, {1.0f, 2.0f, 3.0f}),
                make_real_array(Shape{3}, {0.0f, 1.0f, 0.5f}),
                {},
                {},
                make_real_array(Shape{5}, {0.5f, 2.0f, 3.5f, 3.0f, 0.0f}),
                {}},
            CorrCase{
                "complex_full_fft",
                "accuracy",
                "full",
                "fft",
                true,
                "complex64",
                Shape{2},
                Shape{2},
                {},
                {},
                make_complex_array(Shape{2}, {Complex(1.0f, 1.0f), Complex(2.0f, -1.0f)}),
                make_complex_array(Shape{2}, {Complex(1.0f, -2.0f), Complex(-1.0f, 0.5f)}),
                {},
                make_complex_array(
                    Shape{3},
                    {Complex(-0.5f, -1.5f), Complex(-3.5f, 3.0f), Complex(4.0f, 3.0f)})},
            CorrCase{
                "float16_full_direct_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "float16",
                Shape{3},
                Shape{3},
                {},
                {},
                {},
                {},
                {},
                {}},
            CorrCase{
                "int8_full_direct_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "int8",
                Shape{3},
                Shape{3},
                {},
                {},
                {},
                {},
                {},
                {}},
            CorrCase{
                "int16_full_direct_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "int16",
                Shape{3},
                Shape{3},
                {},
                {},
                {},
                {},
                {},
                {}},
            CorrCase{
                "int32_full_direct_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "int32",
                Shape{3},
                Shape{3},
                {},
                {},
                {},
                {},
                {},
                {}},
        };
    }

    std::vector<CorrCase> correlate2d_accuracy_cases()
    {
        return {
            CorrCase{
                "real_full_wrap",
                "accuracy",
                "full",
                "direct",
                false,
                "float32",
                Shape{2, 2},
                Shape{2, 2},
                make_real_array(Shape{2, 2}, {1.0f, 2.0f, 3.0f, 4.0f}),
                make_real_array(Shape{2, 2}, {0.0f, 1.0f, 2.0f, 1.0f}),
                {},
                {},
                make_real_array(Shape{3, 3}, {8.0f, 8.0f, 8.0f, 12.0f, 12.0f, 12.0f, 8.0f, 8.0f, 8.0f}),
                {}},
            CorrCase{
                "complex_same_fill",
                "accuracy",
                "same",
                "direct",
                true,
                "complex64",
                Shape{2, 2},
                Shape{2, 2},
                {},
                {},
                make_complex_array(
                    Shape{2, 2},
                    {Complex(1.0f, 1.0f), Complex(2.0f, -1.0f), Complex(0.5f, 0.25f), Complex(-1.0f, 2.0f)}),
                make_complex_array(
                    Shape{2, 2},
                    {Complex(1.0f, -1.0f), Complex(0.5f, 0.5f), Complex(-0.5f, 1.0f), Complex(2.0f, -0.25f)}),
                {},
                make_complex_array(
                    Shape{2, 2},
                    {Complex(1.75f, 2.25f), Complex(4.75f, -3.0f), Complex(1.9375f, 0.625f), Complex(-2.0f, 3.625f)})},
            CorrCase{
                "float16_full_wrap_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "float16",
                Shape{2, 2},
                Shape{2, 2},
                {},
                {},
                {},
                {},
                {},
                {}},
            CorrCase{
                "int8_full_wrap_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "int8",
                Shape{2, 2},
                Shape{2, 2},
                {},
                {},
                {},
                {},
                {},
                {}},
            CorrCase{
                "int16_full_wrap_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "int16",
                Shape{2, 2},
                Shape{2, 2},
                {},
                {},
                {},
                {},
                {},
                {}},
            CorrCase{
                "int32_full_wrap_compat",
                "accuracy",
                "full",
                "direct",
                false,
                "int32",
                Shape{2, 2},
                Shape{2, 2},
                {},
                {},
                {},
                {},
                {},
                {}},
        };
    }

    std::vector<LagCase> lag_accuracy_cases()
    {
        return {
            {"full_case", "accuracy", 5, 3, "full", {-2, -1, 0, 1, 2, 3, 4}},
            {"same_case", "accuracy", 5, 4, "same", {-2, -1, 0, 1, 2}},
            {"valid_case", "accuracy", 2, 5, "valid", {-3, -2, -1, 0}},
        };
    }

    CorrCase correlate_perf_case(bool for_2d)
    {
        if (!for_2d)
        {
            std::vector<float> a(2048, 0.0f);
            std::vector<float> b(257, 0.0f);
            for (std::size_t i = 0; i < a.size(); ++i)
            {
                a[i] = std::sin(0.01f * static_cast<float>(i));
            }
            for (std::size_t i = 0; i < b.size(); ++i)
            {
                b[i] = std::cos(0.02f * static_cast<float>(i));
            }
            return CorrCase{
                "perf_real_auto",
                "perf",
                "same",
                "auto",
                false,
                "float32",
                Shape{a.size()},
                Shape{b.size()},
                make_real_array(Shape{a.size()}, a),
                make_real_array(Shape{b.size()}, b),
                {},
                {},
                {},
                {}};
        }

        std::vector<float> a(64 * 64, 0.0f);
        std::vector<float> b(7 * 7, 0.0f);
        for (std::size_t i = 0; i < a.size(); ++i)
        {
            a[i] = std::sin(0.03f * static_cast<float>(i));
        }
        for (std::size_t i = 0; i < b.size(); ++i)
        {
            b[i] = std::cos(0.05f * static_cast<float>(i));
        }
        return CorrCase{
            "perf_real2d_same",
            "perf",
                "same",
                "direct",
                false,
                "float32",
                Shape{64, 64},
                Shape{7, 7},
            make_real_array(Shape{64, 64}, a),
            make_real_array(Shape{7, 7}, b),
            {},
            {},
            {},
            {}};
    }

    LagCase lag_perf_case()
    {
        return {"perf_lags", "perf", 4096, 1025, "full", {}};
    }

    Summary run_correlate_impl(const CliOptions &options)
    {
        Summary summary;
        for (const CorrCase &test_case : correlate_accuracy_cases())
        {
            summary.accuracy_cases += 1;
            if (!test_case.is_complex)
            {
                if (test_case.dtype != "float32")
                {
                    evaluate_numeric_compat_case(test_case, summary, false);
                    continue;
                }
                const RealArray cpu =
                    cusignal::cpu::correlate::correlate(
                        test_case.in1_real, test_case.in2_real, test_case.mode, test_case.method);
                const ZxGpuRealArray gpu =
                    cusignal::zx_gpu_backend::correlate::correlate(
                        test_case.in1_real, test_case.in2_real, test_case.mode, test_case.method);
                const RealArray gpu_host = gpu.get();
                const ErrorMetrics cpu_gpu = compare_real(cpu.values, gpu_host.values);
                const ErrorMetrics cpu_ref = compare_real(cpu.values, test_case.expected_real.values);
                const ErrorMetrics gpu_ref = compare_real(gpu_host.values, test_case.expected_real.values);
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
            else
            {
                const ComplexArray cpu =
                    cusignal::cpu::correlate::correlate(
                        test_case.in1_complex, test_case.in2_complex, test_case.mode, test_case.method);
                const ZxGpuComplexArray gpu =
                    cusignal::zx_gpu_backend::correlate::correlate(
                        test_case.in1_complex, test_case.in2_complex, test_case.mode, test_case.method);
                const ComplexArray gpu_host = gpu.get();
                const ErrorMetrics cpu_gpu = compare_complex(cpu.values, gpu_host.values);
                const ErrorMetrics cpu_ref = compare_complex(cpu.values, test_case.expected_complex.values);
                const ErrorMetrics gpu_ref = compare_complex(gpu_host.values, test_case.expected_complex.values);
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

        {
            summary.accuracy_cases += 1;
            std::vector<float> left_values(65, 0.0f);
            std::vector<float> right_values(65, 0.0f);
            for (std::size_t index = 0; index < left_values.size(); ++index)
            {
                left_values[index] = std::sin(0.07f * static_cast<float>(index));
                right_values[index] = std::cos(0.11f * static_cast<float>(index));
            }
            const RealArray left = make_real_array(Shape{left_values.size()}, left_values);
            const RealArray right = make_real_array(Shape{right_values.size()}, right_values);
            const RealArray cpu = cusignal::cpu::correlate::correlate(left, right, "same", "auto");
            const ZxGpuRealArray gpu_device =
                cusignal::zx_gpu_backend::correlate::correlate(left, right, "same", "auto");
            const bool used_fft =
                cusignal::zx_gpu_backend::correlate_test_hooks::last_correlation_used_fft();
            const RealArray gpu = gpu_device.get();
            const ErrorMetrics error = compare_real(cpu.values, gpu.values);
            summary.cpu_gpu_error.max_abs_error =
                std::max(summary.cpu_gpu_error.max_abs_error, error.max_abs_error);
            summary.cpu_gpu_error.max_rel_error =
                std::max(summary.cpu_gpu_error.max_rel_error, error.max_rel_error);
            summary.cpu_gpu_error.rmse =
                std::max(summary.cpu_gpu_error.rmse, error.rmse);
            summary.reference_error.max_abs_error =
                std::max(summary.reference_error.max_abs_error, error.max_abs_error);
            summary.reference_error.max_rel_error =
                std::max(summary.reference_error.max_rel_error, error.max_rel_error);
            summary.reference_error.rmse =
                std::max(summary.reference_error.rmse, error.rmse);
            const bool contract_pass = used_fft && error.max_abs_error < 1e-4f;
            summary.pass = summary.pass && contract_pass;
            std::cout << "[correlate] auto_fft_path_contract="
                      << (contract_pass ? "PASS" : "FAIL") << "\n";
        }

        if (options.case_set == "perf" || options.case_set == "full" || options.case_set == "smoke")
        {
            summary.perf_cases = 1;
            const CorrCase perf = correlate_perf_case(false);
            if (!options.gpu_only_perf)
            {
                summary.cpu_perf = measure_timing(options.warmup, options.repeat, [&]() {
                    (void)cusignal::cpu::correlate::correlate(perf.in1_real, perf.in2_real, perf.mode, perf.method);
                });
            }
            std::vector<float> kernel_samples;
            summary.gpu_e2e_perf = measure_timing(options.warmup, options.repeat, [&]() {
                (void)cusignal::zx_gpu_backend::correlate_test_hooks::consume_last_kernel_ms();
                (void)cusignal::zx_gpu_backend::correlate::correlate(perf.in1_real, perf.in2_real, perf.mode, perf.method);
                cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
                kernel_samples.push_back(cusignal::zx_gpu_backend::correlate_test_hooks::consume_last_kernel_ms());
            });
            summary.gpu_kernel_perf = summarize_measured_kernel_timings(
                std::move(kernel_samples), options.warmup, options.repeat);

            if (!options.gpu_only_perf)
            {
                const RealArray cpu =
                    cusignal::cpu::correlate::correlate(
                        perf.in1_real, perf.in2_real, perf.mode, perf.method);
                const ZxGpuRealArray gpu_device =
                    cusignal::zx_gpu_backend::correlate::correlate(
                        perf.in1_real, perf.in2_real, perf.mode, perf.method);
                const bool used_fft =
                    cusignal::zx_gpu_backend::correlate_test_hooks::last_correlation_used_fft();
                const RealArray gpu = gpu_device.get();
                const ErrorMetrics error = compare_real(cpu.values, gpu.values);
                summary.cpu_gpu_error.max_abs_error =
                    std::max(summary.cpu_gpu_error.max_abs_error, error.max_abs_error);
                summary.cpu_gpu_error.max_rel_error =
                    std::max(summary.cpu_gpu_error.max_rel_error, error.max_rel_error);
                summary.cpu_gpu_error.rmse =
                    std::max(summary.cpu_gpu_error.rmse, error.rmse);
                const bool perf_surface_pass =
                    used_fft && error.max_abs_error < 2e-3f && error.rmse < 5e-4f;
                summary.pass = summary.pass && perf_surface_pass;
                std::cout << "[correlate] fft_perf_surface_contract="
                          << (perf_surface_pass ? "PASS" : "FAIL")
                          << " max_abs=" << format_float(error.max_abs_error)
                          << " rmse=" << format_float(error.rmse) << "\n";
            }

            if (options.emit_report)
            {
                if (!options.gpu_only_perf)
                {
                    const fs::path gen = generated_root("correlate");
                    write_real_csv(gen / "input" / (perf.id + "__in1.csv"), perf.in1_real.values);
                    write_real_csv(gen / "input" / (perf.id + "__in2.csv"), perf.in2_real.values);
                    const RealArray gpu =
                        cusignal::zx_gpu_backend::correlate::correlate(perf.in1_real, perf.in2_real, perf.mode, perf.method).get();
                    const RealArray cpu =
                        cusignal::cpu::correlate::correlate(perf.in1_real, perf.in2_real, perf.mode, perf.method);
                    write_real_csv(gen / "output_samples" / (perf.id + "__cpu__values.csv"), cpu.values);
                    write_real_csv(gen / "output_samples" / (perf.id + "__gpu__values.csv"), gpu.values);
                }
            }
        }
        return summary;
    }

    Summary run_correlate2d_impl(const CliOptions &options)
    {
        Summary summary;
        for (const CorrCase &test_case : correlate2d_accuracy_cases())
        {
            summary.accuracy_cases += 1;
            if (!test_case.is_complex)
            {
                if (test_case.dtype != "float32")
                {
                    evaluate_numeric_compat_case(test_case, summary, true);
                    continue;
                }
                const RealArray cpu =
                    cusignal::cpu::correlate::correlate2d(
                        test_case.in1_real, test_case.in2_real, test_case.mode, "wrap", 0.0f);
                const ZxGpuRealArray gpu =
                    cusignal::zx_gpu_backend::correlate::correlate2d(
                        test_case.in1_real, test_case.in2_real, test_case.mode, "wrap", 0.0f);
                const RealArray gpu_host = gpu.get();
                const ErrorMetrics cpu_gpu = compare_real(cpu.values, gpu_host.values);
                const ErrorMetrics cpu_ref = compare_real(cpu.values, test_case.expected_real.values);
                const ErrorMetrics gpu_ref = compare_real(gpu_host.values, test_case.expected_real.values);
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
            else
            {
                const ComplexArray cpu =
                    cusignal::cpu::correlate::correlate2d(
                        test_case.in1_complex, test_case.in2_complex, test_case.mode, "fill", 0.0f);
                const ZxGpuComplexArray gpu =
                    cusignal::zx_gpu_backend::correlate::correlate2d(
                        test_case.in1_complex, test_case.in2_complex, test_case.mode, "fill", 0.0f);
                const ComplexArray gpu_host = gpu.get();
                const ErrorMetrics cpu_gpu = compare_complex(cpu.values, gpu_host.values);
                const ErrorMetrics cpu_ref = compare_complex(cpu.values, test_case.expected_complex.values);
                const ErrorMetrics gpu_ref = compare_complex(gpu_host.values, test_case.expected_complex.values);
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
            const CorrCase perf = correlate_perf_case(true);
            if (!options.gpu_only_perf)
            {
                summary.cpu_perf = measure_timing(options.warmup, options.repeat, [&]() {
                    (void)cusignal::cpu::correlate::correlate2d(perf.in1_real, perf.in2_real, perf.mode, "fill", 0.0f);
                });
            }
            std::vector<float> kernel_samples;
            summary.gpu_e2e_perf = measure_timing(options.warmup, options.repeat, [&]() {
                (void)cusignal::zx_gpu_backend::correlate_test_hooks::consume_last_kernel_ms();
                (void)cusignal::zx_gpu_backend::correlate::correlate2d(perf.in1_real, perf.in2_real, perf.mode, "fill", 0.0f);
                cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
                kernel_samples.push_back(cusignal::zx_gpu_backend::correlate_test_hooks::consume_last_kernel_ms());
            });
            summary.gpu_kernel_perf = summarize_measured_kernel_timings(
                std::move(kernel_samples), options.warmup, options.repeat);

            if (options.emit_report)
            {
                if (!options.gpu_only_perf)
                {
                    const fs::path gen = generated_root("correlate2d");
                    write_real_csv(gen / "input" / (perf.id + "__in1.csv"), perf.in1_real.values);
                    write_real_csv(gen / "input" / (perf.id + "__in2.csv"), perf.in2_real.values);
                    const RealArray gpu =
                        cusignal::zx_gpu_backend::correlate::correlate2d(perf.in1_real, perf.in2_real, perf.mode, "fill", 0.0f).get();
                    const RealArray cpu =
                        cusignal::cpu::correlate::correlate2d(perf.in1_real, perf.in2_real, perf.mode, "fill", 0.0f);
                    write_real_csv(gen / "output_samples" / (perf.id + "__cpu__values.csv"), cpu.values);
                    write_real_csv(gen / "output_samples" / (perf.id + "__gpu__values.csv"), gpu.values);
                }
            }
        }
        return summary;
    }

    Summary run_lags_impl(const CliOptions &options)
    {
        Summary summary;
        for (const LagCase &test_case : lag_accuracy_cases())
        {
            summary.accuracy_cases += 1;
            const IndexVector cpu =
                cusignal::cpu::correlate::correlation_lags(test_case.in1_len, test_case.in2_len, test_case.mode);
            const IndexVector gpu =
                cusignal::zx_gpu_backend::correlate::correlation_lags(test_case.in1_len, test_case.in2_len, test_case.mode).get();
            const ErrorMetrics cpu_gpu = compare_index(cpu, gpu);
            const ErrorMetrics cpu_ref = compare_index(cpu, test_case.expected);
            const ErrorMetrics gpu_ref = compare_index(gpu, test_case.expected);
            summary.cpu_gpu_error.max_abs_error =
                std::max(summary.cpu_gpu_error.max_abs_error, cpu_gpu.max_abs_error);
            summary.reference_error.max_abs_error =
                std::max({summary.reference_error.max_abs_error, cpu_ref.max_abs_error, gpu_ref.max_abs_error});
            summary.pass = summary.pass &&
                           cpu_ref.max_abs_error == 0.0f &&
                           gpu_ref.max_abs_error == 0.0f;
        }

        if (options.case_set == "perf" || options.case_set == "full" || options.case_set == "smoke")
        {
            summary.perf_cases = 1;
            const LagCase perf = lag_perf_case();
            if (!options.gpu_only_perf)
            {
                summary.cpu_perf = measure_timing(options.warmup, options.repeat, [&]() {
                    (void)cusignal::cpu::correlate::correlation_lags(perf.in1_len, perf.in2_len, perf.mode);
                });
            }
            std::vector<float> kernel_samples;
            summary.gpu_e2e_perf = measure_timing(options.warmup, options.repeat, [&]() {
                (void)cusignal::zx_gpu_backend::correlate_test_hooks::consume_last_kernel_ms();
                (void)cusignal::zx_gpu_backend::correlate::correlation_lags(perf.in1_len, perf.in2_len, perf.mode);
                cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
                kernel_samples.push_back(cusignal::zx_gpu_backend::correlate_test_hooks::consume_last_kernel_ms());
            });
            summary.gpu_kernel_perf = summarize_measured_kernel_timings(
                std::move(kernel_samples), options.warmup, options.repeat);
            if (options.emit_report)
            {
                if (!options.gpu_only_perf)
                {
                    const fs::path gen = generated_root("correlation_lags");
                    write_index_csv(gen / "input" / (perf.id + "__lengths.csv"), {perf.in1_len, perf.in2_len});
                    const IndexVector gpu =
                        cusignal::zx_gpu_backend::correlate::correlation_lags(perf.in1_len, perf.in2_len, perf.mode).get();
                    const IndexVector cpu =
                        cusignal::cpu::correlate::correlation_lags(perf.in1_len, perf.in2_len, perf.mode);
                    write_index_csv(gen / "output_samples" / (perf.id + "__cpu__lags.csv"), cpu);
                    write_index_csv(gen / "output_samples" / (perf.id + "__gpu__lags.csv"), gpu);
                }
            }
        }
        return summary;
    }
} // namespace

int run_correlate_tests(int argc, char **argv)
{
    return report_and_return("correlate", run_correlate_impl(parse_args(argc, argv)), parse_args(argc, argv));
}

int run_correlate2d_tests(int argc, char **argv)
{
    return report_and_return("correlate2d", run_correlate2d_impl(parse_args(argc, argv)), parse_args(argc, argv));
}

int run_correlation_lags_tests(int argc, char **argv)
{
    return report_and_return("correlation_lags", run_lags_impl(parse_args(argc, argv)), parse_args(argc, argv));
}
