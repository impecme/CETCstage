#include "bsplines_test_support.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
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

#include "../../../include/cusignal/bsplines/bsplines.hpp"
#include "../../../include/cusignal/core/helpers.hpp"
#include "../common/live_perf.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace bsplines_test_hooks
        {
            float consume_last_kernel_ms();
        }
    } // namespace zx_gpu_backend
} // namespace cusignal

namespace
{
    using cusignal::core::Float16;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::RealArray;
    using cusignal::core::RealArrayLike;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
    using JsonArray = cusignal_test::json::Array;
    using JsonObject = cusignal_test::json::Object;
    using JsonValue = cusignal_test::json::Value;

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
        float max_abs_error = 0.0;
        float max_rel_error = 0.0;
        float mixed_error = 0.0;
        float rmse = 0.0;
        float l2_error = 0.0;
        bool exact_match = true;
        long long first_mismatch_index = -1;
        std::size_t compared_samples = 0;
    };

    struct TimingStats
    {
        float mean_ms = 0.0;
        float median_ms = 0.0;
        float p95_ms = 0.0;
        float min_ms = 0.0;
        float max_ms = 0.0;
        float std_ms = 0.0;
        std::vector<float> samples_ms;
    };

    struct Artifact
    {
        std::string role;
        fs::path path;
        std::string sha256;
    };

    struct CaseReport
    {
        std::string case_id;
        std::string category;
        std::size_t samples = 0;
        ErrorMetrics cpu_gpu_error;
        std::optional<ErrorMetrics> cpu_reference_error;
        std::optional<ErrorMetrics> gpu_reference_error;
        std::optional<TimingStats> cpu_perf;
        std::optional<TimingStats> gpu_e2e_perf;
        std::optional<TimingStats> gpu_kernel_perf;
        bool pass = true;
        std::string note;
        std::vector<Artifact> artifacts;
    };

    struct OperatorSummary
    {
        std::string operator_name;
        bool pass = true;
        int accuracy_cases = 0;
        int perf_cases = 0;
        ErrorMetrics cpu_gpu_error;
        std::optional<ErrorMetrics> reference_error;
        std::optional<TimingStats> cpu_perf;
        std::optional<TimingStats> gpu_e2e_perf;
        std::optional<TimingStats> gpu_kernel_perf;
        std::vector<std::string> failed_cases;
    };

    struct BsplinesCase
    {
        std::string id;
        std::string category;
        Shape x_shape;
        fs::path x_file;
        fs::path expected_signal_file;
        int n = 0; // gauss_spline 的阶数参数
        bool expect_invalid_argument = false; // 标记该用例是否应抛出异常
        float x_start = 0.0; // 性能用例输入生成下界
        float x_stop = 0.0; // 性能用例输入生成上界
        std::size_t x_count = 0; // 性能用例输入采样点数
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较
        std::optional<RealArray> generated_x;
    };

    using CpuRunner = std::function<RealArray(const BsplinesCase &)>;
    using GpuRunner = std::function<ZxGpuRealArray(const BsplinesCase &)>;

    struct Runner
    {
        CpuRunner cpu;
        GpuRunner gpu;
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path reference_root(const std::string &op)
    {
        return repo_root() / "data" / "reference" / "unit" / "bsplines" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return cusignal_test::live_perf::generated_unit_root(
                   repo_root() / "data" / "generated" / "unit") /
               "bsplines" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "bsplines" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "bsplines";
    }

    const JsonObject &as_object(const JsonValue &value)
    {
        if (!value.is_object())
        {
            throw std::runtime_error("expected JSON object");
        }
        return value.as_object();
    }

    const JsonArray &as_array(const JsonValue &value)
    {
        if (!value.is_array())
        {
            throw std::runtime_error("expected JSON array");
        }
        return value.as_array();
    }

    std::string get_string(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end() || !iter->second.is_string())
        {
            throw std::runtime_error("missing string key: " + key);
        }
        return iter->second.as_string();
    }

    std::optional<std::string> get_optional_string(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return std::nullopt;
        }
        if (!iter->second.is_string())
        {
            throw std::runtime_error("expected string key: " + key);
        }
        return iter->second.as_string();
    }

    float get_optional_number(const JsonObject &object, const std::string &key, float fallback)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return fallback;
        }
        if (!iter->second.is_number())
        {
            throw std::runtime_error("expected numeric key: " + key);
        }
        return iter->second.as_number();
    }

    int get_optional_int(const JsonObject &object, const std::string &key, int fallback)
    {
        return static_cast<int>(std::llround(get_optional_number(object, key, static_cast<float>(fallback))));
    }

    bool get_optional_bool(const JsonObject &object, const std::string &key, bool fallback)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return fallback;
        }
        if (!iter->second.is_bool())
        {
            throw std::runtime_error("expected bool key: " + key);
        }
        return iter->second.as_bool();
    }

    Shape json_array_to_shape(const JsonValue &value)
    {
        Shape shape;
        for (const JsonValue &item : as_array(value))
        {
            if (!item.is_number())
            {
                throw std::runtime_error("expected numeric shape entry");
            }
            shape.push_back(static_cast<std::size_t>(std::llround(item.as_number())));
        }
        return shape;
    }

    std::size_t shape_size(const Shape &shape)
    {
        return cusignal::core::shape_product(shape);
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

    RealSignal read_real_csv(const fs::path &path)
    {
        std::ifstream input(path);
        if (!input)
        {
            throw std::runtime_error("failed to open CSV file: " + path.string());
        }

        RealSignal values;
        std::string line;
        bool first_line = true;
        while (std::getline(input, line))
        {
            if (line.empty())
            {
                continue;
            }
            if (first_line)
            {
                first_line = false;
                continue;
            }
            values.push_back(std::stod(line.substr(line.find_last_of(',') == std::string::npos ? 0 : line.find_last_of(',') + 1)));
        }
        return values;
    }

    void write_real_csv(const fs::path &path, const RealSignal &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write CSV file: " + path.string());
        }
        output << "value\n";
        output << std::setprecision(17);
        for (float value : values)
        {
            output << value << '\n';
        }
    }

    RealArray make_real_array_from_flat(const Shape &shape, const RealSignal &values)
    {
        RealArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    RealArray load_real_array(const fs::path &path, const Shape &shape)
    {
        return make_real_array_from_flat(shape, read_real_csv(path));
    }

    RealArray make_linspace_array(const Shape &shape, float start, float stop, std::size_t count)
    {
        if (shape_size(shape) != count)
        {
            throw std::runtime_error("x_shape product does not match x_count");
        }

        RealSignal values(count, start);
        if (count > 1)
        {
            const float step = (stop - start) / static_cast<float>(count - 1);
            for (std::size_t index = 0; index < count; ++index)
            {
                values[index] = start + step * static_cast<float>(index);
            }
        }
        return make_real_array_from_flat(shape, values);
    }

    RealArray load_case_input(const BsplinesCase &test_case)
    {
        if (test_case.generated_x.has_value())
        {
            return *test_case.generated_x;
        }
        return load_real_array(test_case.x_file, test_case.x_shape);
    }

    RealSignal sample_values(const RealSignal &values, std::size_t limit = 32)
    {
        if (cusignal_test::cpu_reference_cache::write_full_outputs())
        {
            return values;
        }
        if (values.size() <= limit)
        {
            return values;
        }
        return RealSignal(values.begin(), values.begin() + static_cast<long>(limit));
    }

    void write_signal_sample(
        const fs::path &base_dir,
        const std::string &case_id,
        const std::string &backend,
        const RealArray &values,
        std::vector<Artifact> *artifacts)
    {
        const fs::path path = base_dir / (case_id + "__" + backend + "__signal.csv");
        write_real_csv(path, sample_values(values.values));
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{backend + "_signal", path});
        }
    }

    void write_input_sample(
        const fs::path &base_dir,
        const BsplinesCase &test_case,
        const RealArray &input,
        std::vector<Artifact> *artifacts)
    {
        const fs::path path = base_dir / (test_case.id + ".csv");
        write_real_csv(path, input.values);
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{"x_input", path});
        }
    }

    ErrorMetrics compute_error_metrics(const RealArray &lhs, const RealArray &rhs)
    {
        if (lhs.shape != rhs.shape)
        {
            throw std::runtime_error("shape mismatch while comparing bsplines outputs");
        }
        if (lhs.values.size() != rhs.values.size())
        {
            throw std::runtime_error("size mismatch while comparing bsplines outputs");
        }

        ErrorMetrics metrics;
        metrics.compared_samples = lhs.values.size();
        float l2_sum = 0.0;
        float rmse_sum = 0.0;
        for (std::size_t index = 0; index < lhs.values.size(); ++index)
        {
            const float diff = lhs.values[index] - rhs.values[index];
            const float abs_error = std::abs(diff);
            const float scale = std::max(std::abs(rhs.values[index]), 1e-30f);
            const float rel_error = abs_error / scale;
            metrics.max_abs_error = std::max(metrics.max_abs_error, abs_error);
            metrics.max_rel_error = std::max(metrics.max_rel_error, rel_error);
            rmse_sum += diff * diff;
            l2_sum += diff * diff;
            if (metrics.first_mismatch_index < 0 && abs_error != 0.0)
            {
                metrics.first_mismatch_index = static_cast<long long>(index);
                metrics.exact_match = false;
            }
        }
        if (!lhs.values.empty())
        {
            metrics.rmse = std::sqrt(rmse_sum / static_cast<float>(lhs.values.size()));
        }
        metrics.l2_error = std::sqrt(l2_sum);
        return metrics;
    }

    bool within_tolerance(
        const RealArray &actual,
        const RealArray &expected,
        float atol,
        float rtol)
    {
        if (actual.shape != expected.shape || actual.values.size() != expected.values.size())
        {
            return false;
        }

        const float effective_atol = std::max(atol, 1.0e-5f);
        const float effective_rtol = std::max(rtol, 1.0e-5f);
        for (std::size_t index = 0; index < actual.values.size(); ++index)
        {
            const float diff = std::abs(actual.values[index] - expected.values[index]);
            const float threshold =
                effective_atol + effective_rtol * std::abs(expected.values[index]);
            if (diff > threshold)
            {
                return false;
            }
        }
        return true;
    }

    float quantize_float16(float value)
    {
        return __half2float(Float16(value));
    }

    RealArray apply_dtype_quantization(const RealArray &array, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return array;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported bsplines dtype compatibility case: " + dtype);
        }

        RealArray quantized = array;
        for (float &value : quantized.values)
        {
            value = quantize_float16(value);
        }
        return quantized;
    }

    TimingStats compute_timing_stats(const std::vector<float> &samples)
    {
        TimingStats stats;
        stats.samples_ms = samples;
        if (samples.empty())
        {
            return stats;
        }

        const float total = std::accumulate(samples.begin(), samples.end(), 0.0);
        stats.mean_ms = total / static_cast<float>(samples.size());

        std::vector<float> sorted = samples;
        std::sort(sorted.begin(), sorted.end());
        stats.min_ms = sorted.front();
        stats.max_ms = sorted.back();
        stats.median_ms = sorted.size() % 2 == 0
                              ? 0.5f * (sorted[sorted.size() / 2 - 1] + sorted[sorted.size() / 2])
                              : sorted[sorted.size() / 2];
        const std::size_t p95_index =
            static_cast<std::size_t>(std::ceil(0.95 * static_cast<float>(sorted.size()))) - 1;
        stats.p95_ms = sorted[std::min<std::size_t>(p95_index, sorted.size() - 1)];

        float variance = 0.0;
        for (float sample : samples)
        {
            const float diff = sample - stats.mean_ms;
            variance += diff * diff;
        }
        variance /= static_cast<float>(samples.size());
        stats.std_ms = std::sqrt(variance);
        return stats;
    }

    template <typename Callable>
    TimingStats benchmark_host_latency(const CliOptions &options, Callable callable)
    {
        for (int warmup = 0; warmup < options.warmup; ++warmup)
        {
            cusignal::core::benchmark::note_iteration();
            callable();
        }

        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            const auto start = std::chrono::steady_clock::now();
            cusignal::core::benchmark::note_iteration();
            callable();
            const auto stop = std::chrono::steady_clock::now();
            durations.push_back(std::chrono::duration<float, std::milli>(stop - start).count());
        }
        return compute_timing_stats(durations);
    }

    template <typename Callable>
    TimingStats benchmark_gpu_kernel_latency(const CliOptions &options, Callable callable)
    {
        for (int warmup = 0; warmup < options.warmup; ++warmup)
        {
            cusignal::core::benchmark::note_iteration();
            callable();
            (void)cusignal::zx_gpu_backend::bsplines_test_hooks::consume_last_kernel_ms();
        }

        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            cusignal::core::benchmark::note_iteration();
            callable();
            durations.push_back(cusignal::zx_gpu_backend::bsplines_test_hooks::consume_last_kernel_ms());
        }
        return compute_timing_stats(durations);
    }

    float median_speedup(
        const std::optional<TimingStats> &baseline,
        const std::optional<TimingStats> &candidate)
    {
        if (!baseline.has_value() || !candidate.has_value() || candidate->median_ms <= 0.0)
        {
            return 0.0;
        }
        return baseline->median_ms / candidate->median_ms;
    }

    bool include_accuracy_cases(const CliOptions &options)
    {
        return options.case_set == "accuracy" || options.case_set == "full" ||
               options.case_set == "smoke";
    }

    bool include_perf_cases(const CliOptions &options)
    {
        return options.case_set == "perf" || options.case_set == "full";
    }

    CliOptions parse_cli(int argc, char **argv)
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
            else if (arg == "--case-set")
            {
                if (index + 1 >= argc)
                {
                    throw std::runtime_error("--case-set requires a value");
                }
                options.case_set = argv[++index];
            }
            else if (arg == "--warmup")
            {
                if (index + 1 >= argc)
                {
                    throw std::runtime_error("--warmup requires a value");
                }
                options.warmup = std::stoi(argv[++index]);
            }
            else if (arg == "--repeat")
            {
                if (index + 1 >= argc)
                {
                    throw std::runtime_error("--repeat requires a value");
                }
                options.repeat = std::stoi(argv[++index]);
            }
            else
            {
                throw std::runtime_error("unknown argument: " + arg);
            }
        }
        return options;
    }

    std::vector<BsplinesCase> load_bsplines_cases(
        const fs::path &manifest_path,
        const std::string &category)
    {
        std::vector<BsplinesCase> cases;
        const JsonValue manifest = cusignal_test::json::parse(
            cusignal_test::report::read_text_file(manifest_path));
        const JsonObject &root = as_object(manifest);
        const JsonArray &case_array = as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const JsonValue &item : case_array)
        {
            const JsonObject &object = as_object(item);
            BsplinesCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.n = get_optional_int(object, "n", 0); // gauss_spline 阶数 n
            test_case.expect_invalid_argument =
                get_optional_bool(object, "expect_invalid_argument", false); // 该用例是否应抛出异常
            test_case.atol = get_optional_number(object, "atol", 0.0); // 绝对误差容限
            test_case.rtol = get_optional_number(object, "rtol", 0.0); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype
            if (const auto iter = object.find("x_shape"); iter != object.end())
            {
                test_case.x_shape = json_array_to_shape(iter->second);
            }
            if (const auto path = get_optional_string(object, "x_file"))
            {
                test_case.x_file = base / *path;
            }
            if (const auto path = get_optional_string(object, "expected_signal_file"))
            {
                test_case.expected_signal_file = base / *path;
            }
            if (category == "perf")
            {
                test_case.x_start = get_optional_number(object, "x_start", -1.0); // 性能输入 linspace 起点
                test_case.x_stop = get_optional_number(object, "x_stop", 1.0); // 性能输入 linspace 终点
                test_case.x_count = static_cast<std::size_t>(
                    std::llround(get_optional_number(object, "x_count", static_cast<float>(shape_size(test_case.x_shape))))); // linspace 采样点数
                if (test_case.x_shape.empty())
                {
                    test_case.x_shape = Shape{test_case.x_count};
                }
                test_case.generated_x = make_linspace_array(
                    test_case.x_shape,
                    test_case.x_start,
                    test_case.x_stop,
                    test_case.x_count);
            }
            cases.push_back(std::move(test_case));
        }

        return cases;
    }

    Runner resolve_runner(const std::string &op)
    {
        if (op == "cubic")
        {
            return Runner{
                [](const BsplinesCase &test_case) {
                    return cusignal::cpu::bsplines::cubic(load_case_input(test_case));
                },
                [](const BsplinesCase &test_case) {
                    return cusignal::zx_gpu_backend::bsplines::cubic(load_case_input(test_case));
                }};
        }
        if (op == "quadratic")
        {
            return Runner{
                [](const BsplinesCase &test_case) {
                    return cusignal::cpu::bsplines::quadratic(load_case_input(test_case));
                },
                [](const BsplinesCase &test_case) {
                    return cusignal::zx_gpu_backend::bsplines::quadratic(load_case_input(test_case));
                }};
        }
        if (op == "gauss_spline")
        {
            return Runner{
                [](const BsplinesCase &test_case) {
                    return cusignal::cpu::bsplines::gauss_spline(load_case_input(test_case), test_case.n);
                },
                [](const BsplinesCase &test_case) {
                    return cusignal::zx_gpu_backend::bsplines::gauss_spline(load_case_input(test_case), test_case.n);
                }};
        }
        throw std::runtime_error("unsupported bsplines operator: " + op);
    }

    ZxGpuRealArray run_gpu_with_input(
        const std::string &op,
        const BsplinesCase &test_case,
        const RealArrayLike &input)
    {
        if (op == "cubic")
        {
            return cusignal::zx_gpu_backend::bsplines::cubic(input);
        }
        if (op == "quadratic")
        {
            return cusignal::zx_gpu_backend::bsplines::quadratic(input);
        }
        if (op == "gauss_spline")
        {
            return cusignal::zx_gpu_backend::bsplines::gauss_spline(input, test_case.n);
        }
        throw std::runtime_error("unsupported bsplines operator: " + op);
    }

    OperatorSummary summarize_cases(const std::string &op, const std::vector<CaseReport> &cases)
    {
        OperatorSummary summary;
        summary.operator_name = op;

        std::vector<float> cpu_perf_medians;
        std::vector<float> gpu_e2e_perf_medians;
        std::vector<float> gpu_kernel_perf_medians;
        ErrorMetrics reference_error;
        bool has_reference_error = false;

        for (const CaseReport &report : cases)
        {
            summary.pass = summary.pass && report.pass;
            if (report.category == "accuracy")
            {
                ++summary.accuracy_cases;
            }
            else
            {
                ++summary.perf_cases;
            }

            summary.cpu_gpu_error.max_abs_error = std::max(
                summary.cpu_gpu_error.max_abs_error, report.cpu_gpu_error.max_abs_error);
            summary.cpu_gpu_error.max_rel_error = std::max(
                summary.cpu_gpu_error.max_rel_error, report.cpu_gpu_error.max_rel_error);
            summary.cpu_gpu_error.rmse = std::max(summary.cpu_gpu_error.rmse, report.cpu_gpu_error.rmse);

            if (report.cpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error = std::max(
                    reference_error.max_abs_error, report.cpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(
                    reference_error.max_rel_error, report.cpu_reference_error->max_rel_error);
                reference_error.rmse = std::max(reference_error.rmse, report.cpu_reference_error->rmse);
            }
            if (report.gpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error = std::max(
                    reference_error.max_abs_error, report.gpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(
                    reference_error.max_rel_error, report.gpu_reference_error->max_rel_error);
                reference_error.rmse = std::max(reference_error.rmse, report.gpu_reference_error->rmse);
            }

            if (report.cpu_perf.has_value())
            {
                cpu_perf_medians.push_back(report.cpu_perf->median_ms);
            }
            if (report.gpu_e2e_perf.has_value())
            {
                gpu_e2e_perf_medians.push_back(report.gpu_e2e_perf->median_ms);
            }
            if (cusignal_test::report::valid_timing(report.gpu_kernel_perf))
            {
                gpu_kernel_perf_medians.push_back(report.gpu_kernel_perf->median_ms);
            }

            if (!report.pass)
            {
                summary.failed_cases.push_back(report.case_id);
            }
        }

        if (has_reference_error)
        {
            summary.reference_error = reference_error;
        }
        if (!cpu_perf_medians.empty())
        {
            summary.cpu_perf = compute_timing_stats(cpu_perf_medians);
        }
        if (!gpu_e2e_perf_medians.empty())
        {
            summary.gpu_e2e_perf = compute_timing_stats(gpu_e2e_perf_medians);
        }
        if (!gpu_kernel_perf_medians.empty())
        {
            summary.gpu_kernel_perf = compute_timing_stats(gpu_kernel_perf_medians);
        }
        return summary;
    }

    void write_reports(
        const std::string &op,
        const CliOptions &options,
        const std::vector<CaseReport> &cases)
    {
        const OperatorSummary summary = summarize_cases(op, cases);
        cusignal_test::report::write_operator_report(
            "bsplines",
            op,
            repo_root(),
            report_root(op),
            __cplusplus,
            CUDART_VERSION,
            options,
            summary,
            cases,
            cusignal_test::report::WritePolicy{});
    }

    void update_module_reports()
    {
        cusignal_test::report::update_module_reports("bsplines", module_report_root());
    }

    void print_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << "[bsplines/" << op << "] "
                  << (summary.pass ? "PASS" : "FAIL")
                  << "  accuracy_cases=" << summary.accuracy_cases
                  << "  perf_cases=" << summary.perf_cases << '\n';
        std::cout << "cpu_gpu_error : max_abs=" << format_float(summary.cpu_gpu_error.max_abs_error)
                  << "  max_rel=" << format_float(summary.cpu_gpu_error.max_rel_error)
                  << "  rmse=" << format_float(summary.cpu_gpu_error.rmse) << '\n';
        if (summary.reference_error.has_value())
        {
            std::cout << "reference_error : max_abs="
                      << format_float(summary.reference_error->max_abs_error)
                      << "  max_rel=" << format_float(summary.reference_error->max_rel_error)
                      << "  rmse=" << format_float(summary.reference_error->rmse) << '\n';
        }
        if (summary.cpu_perf.has_value())
        {
            std::cout << "cpu_perf_ms   : median=" << format_fixed(summary.cpu_perf->median_ms)
                      << "  mean=" << format_fixed(summary.cpu_perf->mean_ms)
                      << "  p95=" << format_fixed(summary.cpu_perf->p95_ms) << '\n';
        }
        else
        {
            std::cout << "cpu_perf_ms   : not_run (accuracy-only; use perf/full case set for timing)\n";
        }
        if (summary.gpu_e2e_perf.has_value())
        {
            std::cout << "gpu_perf_ms   : e2e_median="
                      << format_fixed(summary.gpu_e2e_perf->median_ms)
                      << "  kernel_median="
                      << (cusignal_test::report::valid_timing(summary.gpu_kernel_perf)
                              ? format_fixed(summary.gpu_kernel_perf->median_ms)
                              : "n/a")
                      << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                      << "  e2e_speedup="
                      << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x"
                      << "  kernel_speedup="
                      << (cusignal_test::report::valid_timing(summary.gpu_kernel_perf)
                              ? format_fixed(median_speedup(summary.cpu_perf, summary.gpu_kernel_perf)) + "x"
                              : "n/a")
                      << '\n';
        }
        else
        {
            std::cout << "gpu_perf_ms   : not_run (accuracy-only; use perf/full case set for timing)\n";
        }
        std::cout << "reports       : data/.reports_staging/unit/bsplines/" << op << "/latest_summary.md\n";
    }

    CaseReport evaluate_accuracy_case(
        const BsplinesCase &test_case,
        const Runner &runner,
        bool verbose)
    {
        (void)verbose;
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;

        if (test_case.expect_invalid_argument)
        {
            bool cpu_threw = false;
            bool gpu_threw = false;
            try
            {
                (void)runner.cpu(test_case);
            }
            catch (const std::invalid_argument &)
            {
                cpu_threw = true;
            }
            try
            {
                (void)runner.gpu(test_case);
            }
            catch (const std::invalid_argument &)
            {
                gpu_threw = true;
            }
            report.pass = cpu_threw && gpu_threw;
            report.note = report.pass ? "invalid_argument verified" : "invalid_argument mismatch";
            return report;
        }

        const RealArray cpu_output =
            apply_dtype_quantization(runner.cpu(test_case), test_case.dtype);
        const RealArray gpu_output =
            apply_dtype_quantization(runner.gpu(test_case).get(), test_case.dtype);
        report.samples = cpu_output.values.size();
        report.cpu_gpu_error = compute_error_metrics(cpu_output, gpu_output);

        if (!test_case.expected_signal_file.empty())
        {
            const RealArray expected = apply_dtype_quantization(
                load_real_array(test_case.expected_signal_file, test_case.x_shape),
                test_case.dtype);
            report.cpu_reference_error = compute_error_metrics(cpu_output, expected);
            report.gpu_reference_error = compute_error_metrics(gpu_output, expected);
            report.pass = within_tolerance(cpu_output, expected, test_case.atol, test_case.rtol) &&
                          within_tolerance(gpu_output, expected, test_case.atol, test_case.rtol);
        }
        else
        {
            report.pass = true;
        }

        return report;
    }

    CaseReport evaluate_perf_case(
        const std::string &op,
        const BsplinesCase &test_case,
        const Runner &runner,
        const CliOptions &options)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;

        const RealArray input = load_case_input(test_case);
        const ZxGpuRealArray device_input = ZxGpuRealArray::from_host(input);
        RealArray gpu_output;
        if (!options.gpu_only_perf)
        {
            gpu_output = run_gpu_with_input(op, test_case, device_input).get();
        }
        report.samples = input.values.size();
        if (!options.gpu_only_perf)
        {
            const RealArray cpu_output = runner.cpu(test_case);
            report.cpu_gpu_error = compute_error_metrics(cpu_output, gpu_output);
        }
        report.pass = true;

        if (!options.gpu_only_perf && !cusignal::core::benchmark::skip_cpu_timing())
        {
            report.cpu_perf = benchmark_host_latency(options, [&]() { (void)runner.cpu(test_case); });
        }
        const int benchmark_iterations = options.warmup + options.repeat;
        cusignal::core::benchmark::InputRefreshRun input_refresh(
            static_cast<std::uint64_t>(2 * benchmark_iterations), true);
        report.gpu_e2e_perf = benchmark_host_latency(options, [&]() {
            // E2E owns a fresh host-backed device input and a host materialization.
            const ZxGpuRealArray fresh_input = ZxGpuRealArray::from_host(input);
            (void)run_gpu_with_input(op, test_case, fresh_input).get();
            cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
        });
        report.gpu_kernel_perf =
            benchmark_gpu_kernel_latency(options, [&]() {
                // Stage a new input before the kernel event; the hook reports
                // kernel-only time.
                const ZxGpuRealArray fresh_input = ZxGpuRealArray::from_host(input);
                (void)run_gpu_with_input(op, test_case, fresh_input);
            });

        if (options.emit_report)
        {
            const fs::path op_generated_root = generated_root(op);
            if (!options.gpu_only_perf)
            {
                write_input_sample(op_generated_root / "input", test_case, input, &report.artifacts);
                const RealArray cpu_output = runner.cpu(test_case);
                write_signal_sample(
                    op_generated_root / "output_samples",
                    test_case.id,
                    "cpu",
                    cpu_output,
                    &report.artifacts);
                write_signal_sample(
                    op_generated_root / "output_samples",
                    test_case.id,
                    "gpu",
                    gpu_output,
                    &report.artifacts);
            }
        }

        return report;
    }

    int run_bsplines_operator_tests(const std::string &op, int argc, char **argv)
    {
        const CliOptions options = parse_cli(argc, argv);
        const Runner runner = resolve_runner(op);

        std::vector<CaseReport> reports;
        if (include_accuracy_cases(options))
        {
            const std::vector<BsplinesCase> accuracy_cases =
                load_bsplines_cases(reference_root(op) / "manifest.json", "accuracy");
            for (const BsplinesCase &test_case : accuracy_cases)
            {
                reports.push_back(evaluate_accuracy_case(test_case, runner, options.verbose));
            }
        }
        if (include_perf_cases(options))
        {
            const std::vector<BsplinesCase> perf_cases =
                load_bsplines_cases(generated_root(op) / "manifest.json", "perf");
            for (const BsplinesCase &test_case : perf_cases)
            {
                reports.push_back(evaluate_perf_case(op, test_case, runner, options));
            }
        }

        write_reports(op, options, reports);
        update_module_reports();

        const OperatorSummary summary = summarize_cases(op, reports);
        print_terminal_summary(op, summary);
        return summary.pass ? 0 : 1;
    }
} // namespace

int run_cubic_tests(int argc, char **argv)
{
    try
    {
        return run_bsplines_operator_tests("cubic", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[bsplines] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_quadratic_tests(int argc, char **argv)
{
    try
    {
        return run_bsplines_operator_tests("quadratic", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[bsplines] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_gauss_spline_tests(int argc, char **argv)
{
    try
    {
        return run_bsplines_operator_tests("gauss_spline", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[bsplines] ERROR: " << error.what() << '\n';
        return 1;
    }
}
