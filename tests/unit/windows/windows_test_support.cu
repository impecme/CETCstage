#include "windows_test_support.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "../../../include/cusignal/windows/windows.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace windows_test_hooks
        {
            float consume_last_kernel_ms();
        }
    } // namespace zx_gpu_backend
} // namespace cusignal

namespace
{
    using cusignal::core::NamedFloatPairParameter;
    using cusignal::core::NamedFloatParameter;
    using cusignal::core::NamedTaylorParameter;
    using cusignal::core::Float16;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    using cusignal::core::RealSignal;
    using cusignal::core::WindowSpec;

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

    struct WindowCase
    {
        std::string id;
        std::string category;
        int size = 0; // 窗口输出长度
        bool sym = true; // 对称窗口形式（false 表示周期形式）
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string mode = "default"; // get_window 特殊场景模式覆盖值
        float param0 = 0.0; // 第一个形状参数（beta/std/alpha 等）
        float param1 = 0.0; // 需要时使用的第二个形状参数
        int int_param0 = 0; // 整型形状参数（例如 nbar）
        bool bool_param0 = false; // 布尔形状参数（例如 norm）
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较
        RealSignal coefficients;
        std::optional<WindowSpec> spec;
        fs::path expected_file;
    };

    using JsonArray = cusignal_test::json::Array;
    using JsonObject = cusignal_test::json::Object;
    using JsonValue = cusignal_test::json::Value;
    using CpuWindowFunction = std::function<RealSignal(const WindowCase &)>;
    using GpuWindowFunction = std::function<ZxGpuRealSignal(const WindowCase &)>;

    struct Runner
    {
        CpuWindowFunction cpu;
        GpuWindowFunction gpu;
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path reference_root(const std::string &op)
    {
        return repo_root() / "data" / "reference" / "unit" / "windows" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return repo_root() / "data" / "generated" / "unit" / "windows" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / "reports" / "unit" / "windows" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / "reports" / "unit" / "windows";
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

    void write_text_file(const fs::path &path, const std::string &content)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write file: " + path.string());
        }
        output << content;
    }

    std::string json_escape(const std::string &input)
    {
        std::ostringstream stream;
        for (char value : input)
        {
            switch (value)
            {
            case '\\':
                stream << "\\\\";
                break;
            case '"':
                stream << "\\\"";
                break;
            case '\n':
                stream << "\\n";
                break;
            case '\r':
                stream << "\\r";
                break;
            case '\t':
                stream << "\\t";
                break;
            default:
                stream << value;
                break;
            }
        }
        return stream.str();
    }

    std::string current_timestamp()
    {
        std::time_t now = std::time(nullptr);
        std::tm local_tm{};
        localtime_r(&now, &local_tm);
        char buffer[32];
        std::strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", &local_tm);
        return buffer;
    }

    std::string timestamp_for_path()
    {
        std::time_t now = std::time(nullptr);
        std::tm local_tm{};
        localtime_r(&now, &local_tm);
        char buffer[32];
        std::strftime(buffer, sizeof(buffer), "%Y%m%d_%H%M%S", &local_tm);
        return buffer;
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

    float get_number(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end() || !iter->second.is_number())
        {
            throw std::runtime_error("missing numeric key: " + key);
        }
        return iter->second.as_number();
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

    bool get_bool(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end() || !iter->second.is_bool())
        {
            throw std::runtime_error("missing bool key: " + key);
        }
        return iter->second.as_bool();
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

    RealSignal json_array_to_signal(const JsonValue &value)
    {
        RealSignal signal;
        for (const JsonValue &item : as_array(value))
        {
            if (!item.is_number())
            {
                throw std::runtime_error("expected numeric array entry");
            }
            signal.push_back(item.as_number());
        }
        return signal;
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
                if (line.find("value") != std::string::npos)
                {
                    continue;
                }
            }

            std::istringstream stream(line);
            float value = 0.0;
            stream >> value;
            values.push_back(value);
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

    RealSignal sample_values(const RealSignal &values, std::size_t limit = 32)
    {
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
        const RealSignal &values,
        std::vector<Artifact> *artifacts)
    {
        const fs::path path = base_dir / (case_id + "__" + backend + "__signal.csv");
        write_real_csv(path, sample_values(values));
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{backend + "_signal", path});
        }
    }

    std::string relative_path_string(const fs::path &path)
    {
        return fs::relative(path, repo_root()).generic_string();
    }

    ErrorMetrics compute_error_metrics(const RealSignal &lhs, const RealSignal &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("shape mismatch while comparing windows");
        }

        ErrorMetrics metrics;
        metrics.compared_samples = lhs.size();
        float l2_sum = 0.0;
        float rmse_sum = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float diff = lhs[index] - rhs[index];
            const float abs_error = std::abs(diff);
            const float scale = std::max(std::abs(rhs[index]), 1e-30f);
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

        if (!lhs.empty())
        {
            metrics.rmse = std::sqrt(rmse_sum / static_cast<float>(lhs.size()));
        }
        metrics.l2_error = std::sqrt(l2_sum);
        return metrics;
    }

    bool within_tolerance(
        const RealSignal &actual,
        const RealSignal &expected,
        float atol,
        float rtol)
    {
        if (actual.size() != expected.size())
        {
            return false;
        }

        const float effective_atol = std::max(atol, 1.0e-5f);
        const float effective_rtol = std::max(rtol, 1.0e-5f);
        for (std::size_t index = 0; index < actual.size(); ++index)
        {
            const float diff = std::abs(actual[index] - expected[index]);
            const float threshold = effective_atol + effective_rtol * std::abs(expected[index]);
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

    RealSignal apply_dtype_quantization(const RealSignal &signal, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return signal;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported windows dtype compatibility case: " + dtype);
        }

        RealSignal quantized;
        quantized.reserve(signal.size());
        for (float value : signal)
        {
            quantized.push_back(quantize_float16(value));
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
        stats.median_ms = sorted[sorted.size() / 2];
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
            callable();
        }

        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            const auto start = std::chrono::steady_clock::now();
            callable();
            const auto stop = std::chrono::steady_clock::now();
            durations.push_back(
                std::chrono::duration<float, std::milli>(stop - start).count());
        }
        return compute_timing_stats(durations);
    }

    template <typename Callable>
    TimingStats benchmark_gpu_kernel_latency(const CliOptions &options, Callable callable)
    {
        for (int warmup = 0; warmup < options.warmup; ++warmup)
        {
            callable();
            (void)cusignal::zx_gpu_backend::windows_test_hooks::consume_last_kernel_ms();
        }

        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            callable();
            durations.push_back(cusignal::zx_gpu_backend::windows_test_hooks::consume_last_kernel_ms());
        }
        return compute_timing_stats(durations);
    }

    float median_speedup(
        const std::optional<TimingStats> &lhs,
        const std::optional<TimingStats> &rhs)
    {
        if (!lhs.has_value() || !rhs.has_value() || rhs->median_ms <= 0.0)
        {
            return 0.0;
        }
        return lhs->median_ms / rhs->median_ms;
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

    WindowSpec parse_window_spec(const JsonValue &value)
    {
        const JsonObject &object = as_object(value);
        const std::string kind = get_string(object, "kind");
        if (kind == "string")
        {
            return WindowSpec{get_string(object, "value")};
        }
        if (kind == "float")
        {
            return WindowSpec{get_number(object, "value")};
        }
        if (kind == "named_float")
        {
            return WindowSpec{NamedFloatParameter{
                get_string(object, "name"),
                get_number(object, "value")}};
        }
        if (kind == "named_pair")
        {
            return WindowSpec{NamedFloatPairParameter{
                get_string(object, "name"),
                get_number(object, "first"),
                get_number(object, "second")}};
        }
        if (kind == "named_taylor")
        {
            return WindowSpec{NamedTaylorParameter{
                get_string(object, "name"),
                get_optional_int(object, "nbar", 4),
                get_optional_number(object, "sll", 30.0),
                get_optional_bool(object, "norm", true)}};
        }
        if (kind == "array")
        {
            return WindowSpec{json_array_to_signal(object.at("values"))};
        }
        throw std::runtime_error("unsupported window spec kind");
    }

    ZxGpuWindowSpec to_zx_gpu_window_spec(const WindowSpec &spec)
    {
        if (std::holds_alternative<std::string>(spec))
        {
            return std::get<std::string>(spec);
        }
        if (std::holds_alternative<float>(spec))
        {
            return std::get<float>(spec);
        }
        if (std::holds_alternative<NamedFloatParameter>(spec))
        {
            return std::get<NamedFloatParameter>(spec);
        }
        if (std::holds_alternative<NamedFloatPairParameter>(spec))
        {
            return std::get<NamedFloatPairParameter>(spec);
        }
        if (std::holds_alternative<NamedTaylorParameter>(spec))
        {
            return std::get<NamedTaylorParameter>(spec);
        }
        return std::get<RealSignal>(spec);
    }

    std::string build_window_spec_json(const WindowSpec &spec)
    {
        std::ostringstream stream;
        std::visit(
            [&stream](const auto &value)
            {
                using T = std::decay_t<decltype(value)>;
                if constexpr (std::is_same_v<T, std::string>)
                {
                    stream << "{\n  \"kind\": \"string\",\n  \"value\": \""
                           << json_escape(value) << "\"\n}";
                }
                else if constexpr (std::is_same_v<T, float>)
                {
                    stream << "{\n  \"kind\": \"float\",\n  \"value\": " << value << "\n}";
                }
                else if constexpr (std::is_same_v<T, NamedFloatParameter>)
                {
                    stream << "{\n  \"kind\": \"named_float\",\n  \"name\": \""
                           << json_escape(value.name) << "\",\n  \"value\": " << value.value << "\n}";
                }
                else if constexpr (std::is_same_v<T, NamedFloatPairParameter>)
                {
                    stream << "{\n  \"kind\": \"named_pair\",\n  \"name\": \""
                           << json_escape(value.name) << "\",\n  \"first\": " << value.first
                           << ",\n  \"second\": " << value.second << "\n}";
                }
                else if constexpr (std::is_same_v<T, NamedTaylorParameter>)
                {
                    stream << "{\n  \"kind\": \"named_taylor\",\n  \"name\": \""
                           << json_escape(value.name) << "\",\n  \"nbar\": " << value.nbar
                           << ",\n  \"sll\": " << value.sll << ",\n  \"norm\": "
                           << (value.norm ? "true" : "false") << "\n}";
                }
                else
                {
                    stream << "{\n  \"kind\": \"array\",\n  \"values\": [";
                    for (std::size_t index = 0; index < value.size(); ++index)
                    {
                        if (index != 0)
                        {
                            stream << ", ";
                        }
                        stream << value[index];
                    }
                    stream << "]\n}";
                }
            },
            spec);
        return stream.str();
    }

    std::string build_case_spec_json(const WindowCase &test_case)
    {
        std::ostringstream stream;
        stream << "{\n"
               << "  \"id\": \"" << json_escape(test_case.id) << "\",\n"
               << "  \"size\": " << test_case.size << ",\n"
               << "  \"sym\": " << (test_case.sym ? "true" : "false") << ",\n"
               << "  \"mode\": \"" << json_escape(test_case.mode) << "\",\n"
               << "  \"param0\": " << test_case.param0 << ",\n"
               << "  \"param1\": " << test_case.param1 << ",\n"
               << "  \"int_param0\": " << test_case.int_param0 << ",\n"
               << "  \"bool_param0\": " << (test_case.bool_param0 ? "true" : "false") << ",\n"
               << "  \"dtype\": \"" << json_escape(test_case.dtype) << "\"";
        if (!test_case.coefficients.empty())
        {
            stream << ",\n  \"coefficients\": [";
            for (std::size_t index = 0; index < test_case.coefficients.size(); ++index)
            {
                if (index != 0)
                {
                    stream << ", ";
                }
                stream << test_case.coefficients[index];
            }
            stream << "]";
        }
        if (test_case.spec.has_value())
        {
            stream << ",\n  \"spec\": " << build_window_spec_json(*test_case.spec);
        }
        stream << "\n}\n";
        return stream.str();
    }

    std::vector<WindowCase> load_window_cases(const fs::path &manifest_path, const std::string &category)
    {
        std::vector<WindowCase> cases;
        const JsonValue manifest = cusignal_test::json::parse(read_text_file(manifest_path));
        const JsonObject &root = as_object(manifest);
        const JsonArray &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const JsonValue &item : case_array)
        {
            const JsonObject &object = as_object(item);
            WindowCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.size = get_optional_int(object, "size", 0); // 窗口长度
            test_case.sym = get_optional_bool(object, "sym", true); // 对称或周期形式
            test_case.atol = get_optional_number(object, "atol", 1e-12f); // 绝对误差容限
            test_case.rtol = get_optional_number(object, "rtol", 1e-12f); // 相对误差容限
            test_case.mode = get_optional_string(object, "mode").value_or("default"); // get_window 模式
            test_case.param0 = get_optional_number(object, "param0", 0.0); // 第一个形状参数
            test_case.param1 = get_optional_number(object, "param1", 0.0); // 第二个形状参数
            test_case.int_param0 = get_optional_int(object, "int_param0", 0); // 整型形状参数
            test_case.bool_param0 = get_optional_bool(object, "bool_param0", false); // 布尔形状参数
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype
            if (const auto iter = object.find("coefficients"); iter != object.end())
            {
                test_case.coefficients = json_array_to_signal(iter->second);
            }
            if (const auto iter = object.find("spec"); iter != object.end())
            {
                test_case.spec = parse_window_spec(iter->second);
            }
            if (const auto expected = get_optional_string(object, "expected_signal_file"))
            {
                test_case.expected_file = base / *expected;
            }
            else if (const auto expected = get_optional_string(object, "expected_file"))
            {
                test_case.expected_file = base / *expected;
            }
            cases.push_back(std::move(test_case));
        }

        return cases;
    }

    Runner resolve_runner(const std::string &op)
    {
        using namespace cusignal;

        if (op == "get_window")
        {
            return Runner{
                [](const WindowCase &test_case)
                {
                    if (!test_case.spec.has_value())
                    {
                        throw std::runtime_error("get_window case requires spec");
                    }
                    return cpu::windows::get_window(*test_case.spec, test_case.size, !test_case.sym);
                },
                [](const WindowCase &test_case)
                {
                    if (!test_case.spec.has_value())
                    {
                        throw std::runtime_error("get_window case requires spec");
                    }
                    return zx_gpu_backend::windows::get_window(
                        to_zx_gpu_window_spec(*test_case.spec),
                        test_case.size,
                        !test_case.sym);
                }};
        }
        if (op == "barthann")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::barthann(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::barthann(test_case.size, test_case.sym); }};
        }
        if (op == "bartlett")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::bartlett(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::bartlett(test_case.size, test_case.sym); }};
        }
        if (op == "blackman")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::blackman(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::blackman(test_case.size, test_case.sym); }};
        }
        if (op == "blackmanharris")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::blackmanharris(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::blackmanharris(test_case.size, test_case.sym); }};
        }
        if (op == "bohman")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::bohman(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::bohman(test_case.size, test_case.sym); }};
        }
        if (op == "boxcar")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::boxcar(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::boxcar(test_case.size, test_case.sym); }};
        }
        if (op == "chebwin")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::chebwin(test_case.size, test_case.param0, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::chebwin(test_case.size, test_case.param0, test_case.sym); }};
        }
        if (op == "cosine")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::cosine(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::cosine(test_case.size, test_case.sym); }};
        }
        if (op == "exponential")
        {
            return Runner{
                [](const WindowCase &test_case)
                {
                    if (test_case.mode == "center_tau")
                    {
                        return cpu::windows::exponential(test_case.size, test_case.param0, test_case.param1, test_case.sym);
                    }
                    return cpu::windows::exponential(test_case.size, test_case.param0, test_case.sym);
                },
                [](const WindowCase &test_case)
                {
                    if (test_case.mode == "center_tau")
                    {
                        return zx_gpu_backend::windows::exponential(test_case.size, test_case.param0, test_case.param1, test_case.sym);
                    }
                    return zx_gpu_backend::windows::exponential(test_case.size, test_case.param0, test_case.sym);
                }};
        }
        if (op == "flattop")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::flattop(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::flattop(test_case.size, test_case.sym); }};
        }
        if (op == "gaussian")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::gaussian(test_case.size, test_case.param0, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::gaussian(test_case.size, test_case.param0, test_case.sym); }};
        }
        if (op == "general_cosine")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::general_cosine(test_case.size, test_case.coefficients, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::general_cosine(test_case.size, test_case.coefficients, test_case.sym); }};
        }
        if (op == "general_gaussian")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::general_gaussian(test_case.size, test_case.param0, test_case.param1, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::general_gaussian(test_case.size, test_case.param0, test_case.param1, test_case.sym); }};
        }
        if (op == "general_hamming")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::general_hamming(test_case.size, test_case.param0, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::general_hamming(test_case.size, test_case.param0, test_case.sym); }};
        }
        if (op == "hamming")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::hamming(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::hamming(test_case.size, test_case.sym); }};
        }
        if (op == "hann")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::hann(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::hann(test_case.size, test_case.sym); }};
        }
        if (op == "kaiser")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::kaiser(test_case.size, test_case.param0, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::kaiser(test_case.size, test_case.param0, test_case.sym); }};
        }
        if (op == "nuttall")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::nuttall(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::nuttall(test_case.size, test_case.sym); }};
        }
        if (op == "parzen")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::parzen(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::parzen(test_case.size, test_case.sym); }};
        }
        if (op == "taylor")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::taylor(test_case.size, test_case.int_param0, test_case.param0, test_case.bool_param0, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::taylor(test_case.size, test_case.int_param0, test_case.param0, test_case.bool_param0, test_case.sym); }};
        }
        if (op == "triang")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::triang(test_case.size, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::triang(test_case.size, test_case.sym); }};
        }
        if (op == "tukey")
        {
            return Runner{
                [](const WindowCase &test_case) { return cpu::windows::tukey(test_case.size, test_case.param0, test_case.sym); },
                [](const WindowCase &test_case) { return zx_gpu_backend::windows::tukey(test_case.size, test_case.param0, test_case.sym); }};
        }
        throw std::runtime_error("unsupported windows operator: " + op);
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
                summary.cpu_gpu_error.max_abs_error,
                report.cpu_gpu_error.max_abs_error);
            summary.cpu_gpu_error.max_rel_error = std::max(
                summary.cpu_gpu_error.max_rel_error,
                report.cpu_gpu_error.max_rel_error);
            summary.cpu_gpu_error.rmse = std::max(summary.cpu_gpu_error.rmse, report.cpu_gpu_error.rmse);

            if (report.cpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error = std::max(
                    reference_error.max_abs_error,
                    report.cpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(
                    reference_error.max_rel_error,
                    report.cpu_reference_error->max_rel_error);
                reference_error.rmse = std::max(reference_error.rmse, report.cpu_reference_error->rmse);
            }
            if (report.gpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error = std::max(
                    reference_error.max_abs_error,
                    report.gpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(
                    reference_error.max_rel_error,
                    report.gpu_reference_error->max_rel_error);
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
            if (report.gpu_kernel_perf.has_value())
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

    std::string build_timing_stats_json(
        const TimingStats &stats,
        const CliOptions &options,
        int indent)
    {
        const std::string pad(static_cast<std::size_t>(indent), ' ');
        std::ostringstream stream;
        stream << "{\n"
               << pad << "  \"warmup\": " << options.warmup << ",\n"
               << pad << "  \"repeat\": " << options.repeat << ",\n"
               << pad << "  \"mean_ms\": " << stats.mean_ms << ",\n"
               << pad << "  \"median_ms\": " << stats.median_ms << ",\n"
               << pad << "  \"p95_ms\": " << stats.p95_ms << ",\n"
               << pad << "  \"min_ms\": " << stats.min_ms << ",\n"
               << pad << "  \"max_ms\": " << stats.max_ms << ",\n"
               << pad << "  \"std_ms\": " << stats.std_ms << "\n"
               << pad << "}";
        return stream.str();
    }

    std::string build_metrics_json(
        const std::string &op,
        const CliOptions &options,
        const OperatorSummary &summary,
        const std::vector<CaseReport> &cases)
    {
        std::ostringstream stream;
        stream << "{\n"
               << "  \"module\": \"windows\",\n"
               << "  \"operator\": \"" << json_escape(op) << "\",\n"
               << "  \"generated_at\": \"" << json_escape(current_timestamp()) << "\",\n"
               << "  \"summary\": {\n"
               << "    \"pass\": " << (summary.pass ? "true" : "false") << ",\n"
               << "    \"accuracy_cases\": " << summary.accuracy_cases << ",\n"
               << "    \"perf_cases\": " << summary.perf_cases << ",\n"
               << "    \"max_abs_error\": " << summary.cpu_gpu_error.max_abs_error << ",\n"
               << "    \"max_rel_error\": " << summary.cpu_gpu_error.max_rel_error << ",\n"
               << "    \"rmse\": " << summary.cpu_gpu_error.rmse << ",\n"
               << "    \"gpu_e2e_speedup\": "
               << median_speedup(summary.cpu_perf, summary.gpu_e2e_perf) << ",\n"
               << "    \"gpu_kernel_speedup\": "
               << median_speedup(summary.cpu_perf, summary.gpu_kernel_perf);

        if (summary.reference_error.has_value())
        {
            stream << ",\n    \"reference_error\": {\n"
                   << "      \"max_abs_error\": " << summary.reference_error->max_abs_error << ",\n"
                   << "      \"max_rel_error\": " << summary.reference_error->max_rel_error << ",\n"
                   << "      \"rmse\": " << summary.reference_error->rmse << "\n"
                   << "    }";
        }
        if (summary.cpu_perf.has_value())
        {
            stream << ",\n    \"cpu_perf\": "
                   << build_timing_stats_json(*summary.cpu_perf, options, 4);
        }
        if (summary.gpu_e2e_perf.has_value())
        {
            stream << ",\n    \"gpu_e2e_perf\": "
                   << build_timing_stats_json(*summary.gpu_e2e_perf, options, 4);
        }
        if (summary.gpu_kernel_perf.has_value())
        {
            stream << ",\n    \"gpu_kernel_perf\": "
                   << build_timing_stats_json(*summary.gpu_kernel_perf, options, 4);
        }
        stream << "\n  },\n"
               << "  \"cases\": [\n";

        for (std::size_t index = 0; index < cases.size(); ++index)
        {
            const CaseReport &report = cases[index];
            if (index != 0)
            {
                stream << ",\n";
            }
            stream << "    {\n"
                   << "      \"id\": \"" << json_escape(report.case_id) << "\",\n"
                   << "      \"category\": \"" << json_escape(report.category) << "\",\n"
                   << "      \"samples\": " << report.samples << ",\n"
                   << "      \"pass\": " << (report.pass ? "true" : "false") << ",\n"
                   << "      \"cpu_gpu_error\": {\n"
                   << "        \"max_abs_error\": " << report.cpu_gpu_error.max_abs_error << ",\n"
                   << "        \"max_rel_error\": " << report.cpu_gpu_error.max_rel_error << ",\n"
                   << "        \"rmse\": " << report.cpu_gpu_error.rmse << "\n"
                   << "      }";
            if (report.cpu_reference_error.has_value())
            {
                stream << ",\n      \"cpu_reference_error\": {\n"
                       << "        \"max_abs_error\": " << report.cpu_reference_error->max_abs_error << ",\n"
                       << "        \"max_rel_error\": " << report.cpu_reference_error->max_rel_error << ",\n"
                       << "        \"rmse\": " << report.cpu_reference_error->rmse << "\n"
                       << "      }";
            }
            if (report.gpu_reference_error.has_value())
            {
                stream << ",\n      \"gpu_reference_error\": {\n"
                       << "        \"max_abs_error\": " << report.gpu_reference_error->max_abs_error << ",\n"
                       << "        \"max_rel_error\": " << report.gpu_reference_error->max_rel_error << ",\n"
                       << "        \"rmse\": " << report.gpu_reference_error->rmse << "\n"
                       << "      }";
            }
            if (report.cpu_perf.has_value())
            {
                stream << ",\n      \"cpu_perf\": "
                       << build_timing_stats_json(*report.cpu_perf, options, 6);
            }
            if (report.gpu_e2e_perf.has_value())
            {
                stream << ",\n      \"gpu_e2e_perf\": "
                       << build_timing_stats_json(*report.gpu_e2e_perf, options, 6);
            }
            if (report.gpu_kernel_perf.has_value())
            {
                stream << ",\n      \"gpu_kernel_perf\": "
                       << build_timing_stats_json(*report.gpu_kernel_perf, options, 6);
            }
            if (!report.note.empty())
            {
                stream << ",\n      \"note\": \"" << json_escape(report.note) << "\"";
            }
            if (!report.artifacts.empty())
            {
                stream << ",\n      \"artifacts\": [\n";
                for (std::size_t artifact_index = 0; artifact_index < report.artifacts.size(); ++artifact_index)
                {
                    const Artifact &artifact = report.artifacts[artifact_index];
                    if (artifact_index != 0)
                    {
                        stream << ",\n";
                    }
                    stream << "        {\n"
                           << "          \"role\": \"" << json_escape(artifact.role) << "\",\n"
                           << "          \"path\": \"" << json_escape(relative_path_string(artifact.path)) << "\"\n"
                           << "        }";
                }
                stream << "\n      ]";
            }
            stream << "\n    }";
        }

        stream << "\n  ]\n}\n";
        return stream.str();
    }

    std::string build_cases_csv(const std::vector<CaseReport> &cases)
    {
        std::ostringstream stream;
        stream << "case_id,category,pass,samples,max_abs_error,max_rel_error,rmse,"
               << "cpu_ref_max_abs,cpu_ref_max_rel,gpu_ref_max_abs,gpu_ref_max_rel,"
               << "cpu_mean_ms,cpu_median_ms,gpu_e2e_mean_ms,gpu_e2e_median_ms,"
               << "gpu_kernel_mean_ms,gpu_kernel_median_ms,gpu_e2e_speedup,gpu_kernel_speedup,note\n";

        for (const CaseReport &report : cases)
        {
            stream << report.case_id << ','
                   << report.category << ','
                   << (report.pass ? "true" : "false") << ','
                   << report.samples << ','
                   << report.cpu_gpu_error.max_abs_error << ','
                   << report.cpu_gpu_error.max_rel_error << ','
                   << report.cpu_gpu_error.rmse << ','
                   << (report.cpu_reference_error.has_value() ? report.cpu_reference_error->max_abs_error : 0.0) << ','
                   << (report.cpu_reference_error.has_value() ? report.cpu_reference_error->max_rel_error : 0.0) << ','
                   << (report.gpu_reference_error.has_value() ? report.gpu_reference_error->max_abs_error : 0.0) << ','
                   << (report.gpu_reference_error.has_value() ? report.gpu_reference_error->max_rel_error : 0.0) << ','
                   << (report.cpu_perf.has_value() ? report.cpu_perf->mean_ms : 0.0) << ','
                   << (report.cpu_perf.has_value() ? report.cpu_perf->median_ms : 0.0) << ','
                   << (report.gpu_e2e_perf.has_value() ? report.gpu_e2e_perf->mean_ms : 0.0) << ','
                   << (report.gpu_e2e_perf.has_value() ? report.gpu_e2e_perf->median_ms : 0.0) << ','
                   << (report.gpu_kernel_perf.has_value() ? report.gpu_kernel_perf->mean_ms : 0.0) << ','
                   << (report.gpu_kernel_perf.has_value() ? report.gpu_kernel_perf->median_ms : 0.0) << ','
                   << median_speedup(report.cpu_perf, report.gpu_e2e_perf) << ','
                   << median_speedup(report.cpu_perf, report.gpu_kernel_perf) << ','
                   << '"' << json_escape(report.note) << '"' << '\n';
        }
        return stream.str();
    }

    std::string build_summary_markdown(
        const std::string &op,
        const OperatorSummary &summary,
        const std::vector<CaseReport> &cases)
    {
        std::ostringstream stream;
        stream << "# windows/" << op << " Summary\n\n"
               << "- generated_at: " << current_timestamp() << "\n"
               << "- pass: " << (summary.pass ? "true" : "false") << "\n"
               << "- accuracy_cases: " << summary.accuracy_cases << "\n"
               << "- perf_cases: " << summary.perf_cases << "\n"
               << "- cpu_gpu max_abs_error: " << format_float(summary.cpu_gpu_error.max_abs_error) << "\n"
               << "- cpu_gpu max_rel_error: " << format_float(summary.cpu_gpu_error.max_rel_error) << "\n"
               << "- gpu_e2e_speedup: "
               << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x\n"
               << "- gpu_kernel_speedup: "
               << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_kernel_perf)) << "x\n";
        if (summary.reference_error.has_value())
        {
            stream << "- reference max_abs_error: "
                   << format_float(summary.reference_error->max_abs_error) << "\n"
                   << "- reference max_rel_error: "
                   << format_float(summary.reference_error->max_rel_error) << "\n";
        }
        if (!summary.failed_cases.empty())
        {
            stream << "- failed_cases: ";
            for (std::size_t index = 0; index < summary.failed_cases.size(); ++index)
            {
                if (index != 0)
                {
                    stream << ", ";
                }
                stream << summary.failed_cases[index];
            }
            stream << '\n';
        }
        stream << "\n## Cases\n\n";
        for (const CaseReport &report : cases)
        {
            stream << "- " << report.case_id << " (" << report.category << "): "
                   << (report.pass ? "PASS" : "FAIL")
                   << ", samples=" << report.samples
                   << ", max_abs=" << format_float(report.cpu_gpu_error.max_abs_error)
                   << ", max_rel=" << format_float(report.cpu_gpu_error.max_rel_error);
            if (report.cpu_perf.has_value())
            {
                stream << ", cpu_median_ms=" << format_fixed(report.cpu_perf->median_ms);
            }
            if (report.gpu_e2e_perf.has_value())
            {
                stream << ", gpu_e2e_median_ms=" << format_fixed(report.gpu_e2e_perf->median_ms);
            }
            if (report.gpu_kernel_perf.has_value())
            {
                stream << ", gpu_kernel_median_ms=" << format_fixed(report.gpu_kernel_perf->median_ms);
            }
            stream << '\n';
        }
        return stream.str();
    }

    void write_reports(
        const std::string &op,
        const CliOptions &options,
        const std::vector<CaseReport> &cases)
    {
        const OperatorSummary summary = summarize_cases(op, cases);
        cusignal_test::report::write_operator_report(
            "windows",
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
        cusignal_test::report::update_module_reports("windows", module_report_root());
    }

    void print_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << "[windows/" << op << "] "
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
                      << (summary.gpu_kernel_perf.has_value()
                              ? format_fixed(summary.gpu_kernel_perf->median_ms)
                              : "n/a")
                      << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                      << "  e2e_speedup="
                      << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x"
                      << "  kernel_speedup="
                      << (summary.gpu_kernel_perf.has_value()
                              ? format_fixed(median_speedup(summary.cpu_perf, summary.gpu_kernel_perf)) + "x"
                              : "n/a")
                      << '\n';
        }
        else
        {
            std::cout << "gpu_perf_ms   : not_run (accuracy-only; use perf/full case set for timing)\n";
        }
        std::cout << "reports       : data/reports/unit/windows/" << op << "/latest_summary.md\n";
    }

    CaseReport evaluate_accuracy_case(
        const WindowCase &test_case,
        const Runner &runner,
        bool verbose)
    {
        (void)verbose;
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;

        const RealSignal cpu_output =
            apply_dtype_quantization(runner.cpu(test_case), test_case.dtype);
        const RealSignal gpu_output =
            apply_dtype_quantization(runner.gpu(test_case).get(), test_case.dtype);
        report.samples = cpu_output.size();
        report.cpu_gpu_error = compute_error_metrics(cpu_output, gpu_output);

        if (!test_case.expected_file.empty())
        {
            const RealSignal expected =
                apply_dtype_quantization(read_real_csv(test_case.expected_file), test_case.dtype);
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
        const WindowCase &test_case,
        const Runner &runner,
        const CliOptions &options)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;

        RealSignal gpu_output;
        if (!options.gpu_only_perf)
        {
            gpu_output = runner.gpu(test_case).get();
        }
        report.samples = test_case.size;
        if (!options.gpu_only_perf)
        {
            const RealSignal cpu_output = runner.cpu(test_case);
            report.cpu_gpu_error = compute_error_metrics(cpu_output, gpu_output);
        }
        report.pass = true;

        if (!options.gpu_only_perf)
        {
            report.cpu_perf = benchmark_host_latency(options, [&]() { (void)runner.cpu(test_case); });
        }
        report.gpu_e2e_perf = benchmark_host_latency(options, [&]() {
            (void)runner.gpu(test_case);
            cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
        });
        report.gpu_kernel_perf =
            benchmark_gpu_kernel_latency(options, [&]() { (void)runner.gpu(test_case); });

        if (options.emit_report)
        {
            if (!options.gpu_only_perf)
            {
                const fs::path op_generated_root = generated_root(op);
                const RealSignal cpu_output = runner.cpu(test_case);
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

    int run_windows_operator_tests(const std::string &op, int argc, char **argv)
    {
        const CliOptions options = parse_cli(argc, argv);
        const Runner runner = resolve_runner(op);

        std::vector<CaseReport> reports;
        if (include_accuracy_cases(options))
        {
            const std::vector<WindowCase> accuracy_cases =
                load_window_cases(reference_root(op) / "manifest.json", "accuracy");
            for (const WindowCase &test_case : accuracy_cases)
            {
                reports.push_back(evaluate_accuracy_case(test_case, runner, options.verbose));
            }
        }
        if (include_perf_cases(options))
        {
            const std::vector<WindowCase> perf_cases =
                load_window_cases(generated_root(op) / "manifest.json", "perf");
            for (const WindowCase &test_case : perf_cases)
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

int run_windows_target_tests(int argc, char **argv)
{
    try
    {
        const std::string stem = fs::path(argv[0]).stem().string();
        const std::string prefix = "windows_test_";
        if (stem.rfind(prefix, 0) != 0)
        {
            throw std::runtime_error("unexpected windows test executable name: " + stem);
        }
        return run_windows_operator_tests(stem.substr(prefix.size()), argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[windows] ERROR: " << error.what() << '\n';
        return 1;
    }
}
