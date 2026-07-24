#include "wavelets_test_support.hpp"

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

#include "../../../include/cusignal/core/helpers.hpp"
#include "../../../include/cusignal/wavelets/wavelets.hpp"
#include "../common/live_perf.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace wavelets_test_hooks
        {
            float consume_last_kernel_ms();
        }
    } // namespace zx_gpu_backend
} // namespace cusignal

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::Float16;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::RealSignal;
    using cusignal::core::RealSignalLike;
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

    enum class FieldKind
    {
        Real,
        Complex,
    };

    struct OutputField
    {
        std::string name;
        FieldKind kind = FieldKind::Real;
        Shape shape;
        RealSignal real_values;
        ComplexSignal complex_values;
    };

    struct DeviceOutputField
    {
        std::string name;
        FieldKind kind = FieldKind::Real;
        Shape shape;
        ZxGpuRealSignal real_signal;
        ZxGpuComplexSignal complex_signal;
        ZxGpuComplexArray complex_array;
    };

    struct OutputBundle
    {
        std::vector<OutputField> fields;
    };

    struct DeviceOutputBundle
    {
        std::vector<DeviceOutputField> fields;
    };

    struct WaveletsCase
    {
        std::string id;
        std::string category;
        std::string wavelet;

        int points = 0; // morlet/morlet2/ricker/qmf 的输出支撑长度
        float w = 5.0; // morlet/morlet2 的 omega0 参数
        float s = 1.0; // morlet2 的尺度参数
        float a = 1.0; // ricker 的宽度参数
        bool complete = true; // 为 true 时使用完整 Morlet 形式
        bool expect_invalid_argument = false; // 标记该用例是否应抛出异常

        float hk_start = 0.0; // 生成核定义域的起始值
        float hk_stop = 0.0; // 生成核定义域的终止值
        std::size_t hk_count = 0; // 生成核定义域的采样点数
        float data_start = 0.0; // 生成 CWT 输入的起始值
        float data_stop = 0.0; // 生成 CWT 输入的终止值
        std::size_t data_count = 0; // 生成 CWT 输入的采样点数
        float widths_start = 0.0; // 生成 CWT widths 的起始值
        float widths_stop = 0.0; // 生成 CWT widths 的终止值
        std::size_t widths_count = 0; // 生成 CWT widths 的采样点数

        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较

        fs::path hk_file;
        fs::path data_file;
        fs::path widths_file;
        fs::path expected_signal_file;
        fs::path expected_values_file;

        std::optional<RealSignal> generated_hk;
        std::optional<RealSignal> generated_data;
        std::optional<RealSignal> generated_widths;
    };

    using CpuRunner = std::function<OutputBundle(const WaveletsCase &)>;
    using GpuRunner = std::function<DeviceOutputBundle(const WaveletsCase &)>;

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
        return repo_root() / "data" / "reference" / "unit" / "wavelets" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return cusignal_test::live_perf::generated_unit_root(
                   repo_root() / "data" / "generated" / "unit") /
               "wavelets" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "wavelets" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "wavelets";
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

    RealSignal make_linspace(float start, float stop, std::size_t count)
    {
        RealSignal values(count, 0.0);
        if (count == 0)
        {
            return values;
        }
        if (count == 1)
        {
            values[0] = start;
            return values;
        }
        const float step = (stop - start) / static_cast<float>(count - 1);
        for (std::size_t index = 0; index < count; ++index)
        {
            values[index] = start + step * static_cast<float>(index);
        }
        return values;
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
            const std::size_t comma = line.find_last_of(',');
            values.push_back(std::stod(comma == std::string::npos ? line : line.substr(comma + 1)));
        }
        return values;
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
            throw std::runtime_error("unsupported wavelets dtype compatibility case: " + dtype);
        }
        RealSignal quantized = signal;
        for (float &value : quantized)
        {
            value = quantize_float16(value);
        }
        return quantized;
    }

    ComplexSignal read_complex_csv(const fs::path &path)
    {
        std::ifstream input(path);
        if (!input)
        {
            throw std::runtime_error("failed to open CSV file: " + path.string());
        }

        ComplexSignal values;
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
            const std::size_t comma = line.find(',');
            if (comma == std::string::npos)
            {
                throw std::runtime_error("expected real,imag complex CSV row");
            }
            values.emplace_back(std::stod(line.substr(0, comma)), std::stod(line.substr(comma + 1)));
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

    void write_complex_csv(const fs::path &path, const ComplexSignal &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write CSV file: " + path.string());
        }
        output << "real,imag\n";
        output << std::setprecision(17);
        for (const Complex &value : values)
        {
            output << value.real() << ',' << value.imag() << '\n';
        }
    }

    RealSignal sample_real_values(const RealSignal &values, std::size_t limit = 32)
    {
        if (values.size() <= limit)
        {
            return values;
        }
        return RealSignal(values.begin(), values.begin() + static_cast<long>(limit));
    }

    ComplexSignal sample_complex_values(const ComplexSignal &values, std::size_t limit = 32)
    {
        if (values.size() <= limit)
        {
            return values;
        }
        return ComplexSignal(values.begin(), values.begin() + static_cast<long>(limit));
    }

    OutputBundle make_bundle(const RealSignal &signal)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"signal", FieldKind::Real, Shape{signal.size()}, signal, {}});
        return bundle;
    }

    OutputBundle make_bundle(const ComplexSignal &signal)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"signal", FieldKind::Complex, Shape{signal.size()}, {}, signal});
        return bundle;
    }

    OutputBundle make_bundle(const ComplexArray &values)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"values", FieldKind::Complex, values.shape, {}, values.values});
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const ZxGpuRealSignal &signal)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField field;
        field.name = "signal";
        field.kind = FieldKind::Real;
        field.shape = Shape{signal.size()};
        field.real_signal = signal;
        bundle.fields.push_back(std::move(field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const ZxGpuComplexSignal &signal)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField field;
        field.name = "signal";
        field.kind = FieldKind::Complex;
        field.shape = Shape{signal.size()};
        field.complex_signal = signal;
        bundle.fields.push_back(std::move(field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const ZxGpuComplexArray &values)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField field;
        field.name = "values";
        field.kind = FieldKind::Complex;
        field.shape = values.shape();
        field.complex_array = values;
        bundle.fields.push_back(std::move(field));
        return bundle;
    }

    OutputBundle materialize(const DeviceOutputBundle &device_bundle)
    {
        OutputBundle host_bundle;
        for (const DeviceOutputField &field : device_bundle.fields)
        {
            OutputField host_field;
            host_field.name = field.name;
            host_field.kind = field.kind;
            host_field.shape = field.shape;
            if (field.kind == FieldKind::Real)
            {
                host_field.real_values = field.real_signal.get();
            }
            else if (field.shape.size() <= 1)
            {
                host_field.complex_values = field.complex_signal.get();
            }
            else
            {
                host_field.complex_values = field.complex_array.get().values;
            }
            host_bundle.fields.push_back(std::move(host_field));
        }
        return host_bundle;
    }

    OutputBundle apply_dtype_quantization(const OutputBundle &bundle, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return bundle;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported wavelets dtype compatibility case: " + dtype);
        }
        OutputBundle quantized = bundle;
        for (OutputField &field : quantized.fields)
        {
            if (field.kind == FieldKind::Real)
            {
                field.real_values = apply_dtype_quantization(field.real_values, dtype);
            }
        }
        return quantized;
    }

    ErrorMetrics combine_metrics(const std::vector<ErrorMetrics> &metrics_list)
    {
        ErrorMetrics result;
        for (const ErrorMetrics &metrics : metrics_list)
        {
            result.max_abs_error = std::max(result.max_abs_error, metrics.max_abs_error);
            result.max_rel_error = std::max(result.max_rel_error, metrics.max_rel_error);
            result.rmse = std::max(result.rmse, metrics.rmse);
            result.l2_error = std::max(result.l2_error, metrics.l2_error);
            result.exact_match = result.exact_match && metrics.exact_match;
            if (result.first_mismatch_index < 0 && metrics.first_mismatch_index >= 0)
            {
                result.first_mismatch_index = metrics.first_mismatch_index;
            }
            result.compared_samples += metrics.compared_samples;
        }
        return result;
    }

    ErrorMetrics compute_real_error(
        const Shape &lhs_shape,
        const RealSignal &lhs,
        const Shape &rhs_shape,
        const RealSignal &rhs)
    {
        if (lhs_shape != rhs_shape)
        {
            throw std::runtime_error("shape mismatch while comparing real outputs");
        }
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("size mismatch while comparing real outputs");
        }
        ErrorMetrics metrics;
        metrics.compared_samples = lhs.size();
        float l2_sum = 0.0;
        float rmse_sum = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float diff = lhs[index] - rhs[index];
            const float abs_error = std::abs(diff);
            const float rel_error = abs_error / std::max(std::abs(rhs[index]), 1e-30f);
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

    ErrorMetrics compute_complex_error(
        const Shape &lhs_shape,
        const ComplexSignal &lhs,
        const Shape &rhs_shape,
        const ComplexSignal &rhs)
    {
        if (lhs_shape != rhs_shape)
        {
            throw std::runtime_error("shape mismatch while comparing complex outputs");
        }
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("size mismatch while comparing complex outputs");
        }
        ErrorMetrics metrics;
        metrics.compared_samples = lhs.size();
        float l2_sum = 0.0;
        float rmse_sum = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const Complex diff = lhs[index] - rhs[index];
            const float abs_error = std::abs(diff);
            const float rel_error = abs_error / std::max(std::abs(rhs[index]), 1e-30f);
            metrics.max_abs_error = std::max(metrics.max_abs_error, abs_error);
            metrics.max_rel_error = std::max(metrics.max_rel_error, rel_error);
            rmse_sum += abs_error * abs_error;
            l2_sum += abs_error * abs_error;
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

    ErrorMetrics compute_bundle_error(const OutputBundle &lhs, const OutputBundle &rhs)
    {
        if (lhs.fields.size() != rhs.fields.size())
        {
            throw std::runtime_error("field count mismatch while comparing wavelets outputs");
        }
        std::vector<ErrorMetrics> all_metrics;
        for (std::size_t index = 0; index < lhs.fields.size(); ++index)
        {
            const OutputField &lhs_field = lhs.fields[index];
            const OutputField &rhs_field = rhs.fields[index];
            if (lhs_field.name != rhs_field.name || lhs_field.kind != rhs_field.kind)
            {
                throw std::runtime_error("field mismatch while comparing wavelets outputs");
            }
            if (lhs_field.kind == FieldKind::Complex)
            {
                all_metrics.push_back(compute_complex_error(
                    lhs_field.shape,
                    lhs_field.complex_values,
                    rhs_field.shape,
                    rhs_field.complex_values));
            }
            else
            {
                all_metrics.push_back(compute_real_error(
                    lhs_field.shape,
                    lhs_field.real_values,
                    rhs_field.shape,
                    rhs_field.real_values));
            }
        }
        return combine_metrics(all_metrics);
    }

    bool field_within_tolerance(
        const OutputField &actual,
        const OutputField &expected,
        float atol,
        float rtol)
    {
        if (actual.kind != expected.kind || actual.shape != expected.shape)
        {
            return false;
        }
        const float effective_atol = std::max(atol, 1.0e-5f);
        const float effective_rtol = std::max(rtol, 1.0e-5f);
        if (actual.kind == FieldKind::Complex)
        {
            if (actual.complex_values.size() != expected.complex_values.size())
            {
                return false;
            }
            for (std::size_t index = 0; index < actual.complex_values.size(); ++index)
            {
                const float diff = std::abs(actual.complex_values[index] - expected.complex_values[index]);
                const float threshold =
                    effective_atol + effective_rtol * std::abs(expected.complex_values[index]);
                if (diff > threshold)
                {
                    return false;
                }
            }
            return true;
        }
        if (actual.real_values.size() != expected.real_values.size())
        {
            return false;
        }
        for (std::size_t index = 0; index < actual.real_values.size(); ++index)
        {
            const float diff = std::abs(actual.real_values[index] - expected.real_values[index]);
            const float threshold =
                effective_atol + effective_rtol * std::abs(expected.real_values[index]);
            if (diff > threshold)
            {
                return false;
            }
        }
        return true;
    }

    bool bundle_within_tolerance(
        const OutputBundle &actual,
        const OutputBundle &expected,
        float atol,
        float rtol)
    {
        if (actual.fields.size() != expected.fields.size())
        {
            return false;
        }
        for (std::size_t index = 0; index < actual.fields.size(); ++index)
        {
            if (actual.fields[index].name != expected.fields[index].name)
            {
                return false;
            }
            if (!field_within_tolerance(actual.fields[index], expected.fields[index], atol, rtol))
            {
                return false;
            }
        }
        return true;
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
            durations.push_back(std::chrono::duration<float, std::milli>(stop - start).count());
        }
        return compute_timing_stats(durations);
    }

    template <typename Callable>
    TimingStats benchmark_gpu_kernel_latency(const CliOptions &options, Callable callable)
    {
        for (int warmup = 0; warmup < options.warmup; ++warmup)
        {
            callable();
            (void)cusignal::zx_gpu_backend::wavelets_test_hooks::consume_last_kernel_ms();
        }
        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            callable();
            durations.push_back(cusignal::zx_gpu_backend::wavelets_test_hooks::consume_last_kernel_ms());
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

    RealSignal load_hk_signal(const WaveletsCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_hk.has_value())
        {
            signal = *test_case.generated_hk;
        }
        else
        {
            signal = read_real_csv(test_case.hk_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    RealSignal load_data_signal(const WaveletsCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_data.has_value())
        {
            signal = *test_case.generated_data;
        }
        else
        {
            signal = read_real_csv(test_case.data_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    RealSignal load_widths_signal(const WaveletsCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_widths.has_value())
        {
            signal = *test_case.generated_widths;
        }
        else
        {
            signal = read_real_csv(test_case.widths_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    std::string build_case_spec_json(const std::string &op, const WaveletsCase &test_case)
    {
        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"operator\": \"" << cusignal_test::report::json_escape(op) << "\",\n";
        stream << "  \"id\": \"" << cusignal_test::report::json_escape(test_case.id) << "\",\n";
        stream << "  \"points\": " << test_case.points << ",\n";
        stream << "  \"w\": " << test_case.w << ",\n";
        stream << "  \"s\": " << test_case.s << ",\n";
        stream << "  \"a\": " << test_case.a << ",\n";
        stream << "  \"complete\": " << (test_case.complete ? "true" : "false") << ",\n";
        stream << "  \"wavelet\": \"" << cusignal_test::report::json_escape(test_case.wavelet) << "\",\n";
        stream << "  \"dtype\": \"" << cusignal_test::report::json_escape(test_case.dtype) << "\"\n";
        stream << "}\n";
        return stream.str();
    }

    void write_input_samples(
        const fs::path &base_dir,
        const std::string &op,
        const WaveletsCase &test_case,
        std::vector<Artifact> *artifacts)
    {
        fs::create_directories(base_dir);
        const fs::path spec_path = base_dir / (test_case.id + "__spec.json");
        cusignal_test::report::write_text_file(spec_path, build_case_spec_json(op, test_case));
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{"case_spec", spec_path});
        }

        if (test_case.generated_hk.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__hk.csv");
            write_real_csv(path, *test_case.generated_hk);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"hk_input", path});
        }
        if (test_case.generated_data.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__data.csv");
            write_real_csv(path, *test_case.generated_data);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"data_input", path});
        }
        if (test_case.generated_widths.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__widths.csv");
            write_real_csv(path, *test_case.generated_widths);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"widths_input", path});
        }
    }

    void write_field_sample(
        const fs::path &base_dir,
        const std::string &case_id,
        const std::string &backend,
        const OutputField &field,
        std::vector<Artifact> *artifacts)
    {
        const fs::path path = base_dir / (case_id + "__" + backend + "__" + field.name + ".csv");
        if (field.kind == FieldKind::Complex)
        {
            write_complex_csv(path, sample_complex_values(field.complex_values));
        }
        else
        {
            write_real_csv(path, sample_real_values(field.real_values));
        }
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{backend + "_" + field.name, path});
        }
    }

    std::size_t output_shape_size(const OutputBundle &bundle)
    {
        if (bundle.fields.empty())
        {
            return 0;
        }
        return bundle.fields.front().kind == FieldKind::Complex
                   ? bundle.fields.front().complex_values.size()
                   : bundle.fields.front().real_values.size();
    }

    std::vector<WaveletsCase> load_wavelets_cases(
        const std::string &op,
        const fs::path &manifest_path,
        const std::string &category)
    {
        std::vector<WaveletsCase> cases;
        const JsonValue manifest = cusignal_test::json::parse(
            cusignal_test::report::read_text_file(manifest_path));
        const JsonObject &root = as_object(manifest);
        const JsonArray &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const JsonValue &item : case_array)
        {
            const JsonObject &object = as_object(item);
            WaveletsCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.wavelet = get_optional_string(object, "wavelet").value_or(""); // 小波族名称（用于 cwt）
            test_case.points = get_optional_int(object, "points", 0); // 支撑长度参数
            test_case.w = get_optional_number(object, "w", 5.0); // Morlet omega0 参数
            test_case.s = get_optional_number(object, "s", 1.0); // morlet2 尺度
            test_case.a = get_optional_number(object, "a", 1.0); // ricker 宽度
            test_case.complete = get_optional_bool(object, "complete", true); // 完整 Morlet 开关
            test_case.expect_invalid_argument =
                get_optional_bool(object, "expect_invalid_argument", false); // 该用例是否应抛出异常
            test_case.atol = get_optional_number(object, "atol", 0.0); // 绝对误差容限
            test_case.rtol = get_optional_number(object, "rtol", 0.0); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype

            if (auto v = get_optional_string(object, "hk_file")) test_case.hk_file = base / *v;
            if (auto v = get_optional_string(object, "data_file")) test_case.data_file = base / *v;
            if (auto v = get_optional_string(object, "widths_file")) test_case.widths_file = base / *v;
            if (auto v = get_optional_string(object, "expected_signal_file")) test_case.expected_signal_file = base / *v;
            if (auto v = get_optional_string(object, "expected_values_file")) test_case.expected_values_file = base / *v;

            if (category == "perf")
            {
                if (op == "qmf")
                {
                    test_case.hk_start = get_optional_number(object, "hk_start", -1.0); // hk linspace 起点
                    test_case.hk_stop = get_optional_number(object, "hk_stop", 1.0); // hk linspace 终点
                    test_case.hk_count = static_cast<std::size_t>(std::llround(
                        get_optional_number(object, "hk_count", 0.0)));
                    test_case.generated_hk = make_linspace(
                        test_case.hk_start,
                        test_case.hk_stop,
                        test_case.hk_count);
                }
                else if (op == "cwt")
                {
                    test_case.data_start = get_optional_number(object, "data_start", -1.0); // data linspace 起点
                    test_case.data_stop = get_optional_number(object, "data_stop", 1.0); // data linspace 终点
                    test_case.data_count = static_cast<std::size_t>(std::llround(
                        get_optional_number(object, "data_count", 0.0)));
                    test_case.widths_start = get_optional_number(object, "widths_start", 1.0); // widths linspace 起点
                    test_case.widths_stop = get_optional_number(object, "widths_stop", 1.0); // widths linspace 终点
                    test_case.widths_count = static_cast<std::size_t>(std::llround(
                        get_optional_number(object, "widths_count", 0.0)));
                    test_case.generated_data = make_linspace(
                        test_case.data_start,
                        test_case.data_stop,
                        test_case.data_count);
                    test_case.generated_widths = make_linspace(
                        test_case.widths_start,
                        test_case.widths_stop,
                        test_case.widths_count);
                }
            }
            cases.push_back(std::move(test_case));
        }

        return cases;
    }

    Runner resolve_runner(const std::string &op)
    {
        if (op == "qmf")
        {
            return Runner{
                [](const WaveletsCase &test_case) {
                    return make_bundle(cusignal::cpu::wavelets::qmf(load_hk_signal(test_case)));
                },
                [](const WaveletsCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::wavelets::qmf(load_hk_signal(test_case)));
                }};
        }
        if (op == "morlet")
        {
            return Runner{
                [](const WaveletsCase &test_case) {
                    return make_bundle(cusignal::cpu::wavelets::morlet(
                        test_case.points,
                        test_case.w,
                        test_case.s,
                        test_case.complete));
                },
                [](const WaveletsCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::wavelets::morlet(
                        test_case.points,
                        test_case.w,
                        test_case.s,
                        test_case.complete));
                }};
        }
        if (op == "ricker")
        {
            return Runner{
                [](const WaveletsCase &test_case) {
                    return make_bundle(cusignal::cpu::wavelets::ricker(
                        test_case.points,
                        test_case.a));
                },
                [](const WaveletsCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::wavelets::ricker(
                        test_case.points,
                        test_case.a));
                }};
        }
        if (op == "morlet2")
        {
            return Runner{
                [](const WaveletsCase &test_case) {
                    return make_bundle(cusignal::cpu::wavelets::morlet2(
                        test_case.points,
                        test_case.s,
                        test_case.w));
                },
                [](const WaveletsCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::wavelets::morlet2(
                        test_case.points,
                        test_case.s,
                        test_case.w));
                }};
        }
        if (op == "cwt")
        {
            return Runner{
                [](const WaveletsCase &test_case) {
                    return make_bundle(cusignal::cpu::wavelets::cwt(
                        load_data_signal(test_case),
                        test_case.wavelet,
                        load_widths_signal(test_case)));
                },
                [](const WaveletsCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::wavelets::cwt(
                        load_data_signal(test_case),
                        test_case.wavelet,
                        load_widths_signal(test_case)));
                }};
        }
        throw std::runtime_error("unsupported wavelets operator: " + op);
    }

    OutputBundle load_expected_bundle(const std::string &op, const WaveletsCase &test_case)
    {
        if (op == "qmf" || op == "ricker")
        {
            return apply_dtype_quantization(
                make_bundle(read_real_csv(test_case.expected_signal_file)),
                test_case.dtype);
        }
        if (op == "morlet" || op == "morlet2")
        {
            return make_bundle(read_complex_csv(test_case.expected_signal_file));
        }
        if (op == "cwt")
        {
            const std::size_t rows = load_widths_signal(test_case).size();
            const std::size_t cols = load_data_signal(test_case).size();
            ComplexArray values;
            values.shape = Shape{rows, cols};
            values.values = read_complex_csv(test_case.expected_values_file);
            return make_bundle(values);
        }
        throw std::runtime_error("unsupported expected bundle operator");
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
            summary.cpu_gpu_error.max_abs_error =
                std::max(summary.cpu_gpu_error.max_abs_error, report.cpu_gpu_error.max_abs_error);
            summary.cpu_gpu_error.max_rel_error =
                std::max(summary.cpu_gpu_error.max_rel_error, report.cpu_gpu_error.max_rel_error);
            summary.cpu_gpu_error.rmse =
                std::max(summary.cpu_gpu_error.rmse, report.cpu_gpu_error.rmse);

            if (report.cpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error =
                    std::max(reference_error.max_abs_error, report.cpu_reference_error->max_abs_error);
                reference_error.max_rel_error =
                    std::max(reference_error.max_rel_error, report.cpu_reference_error->max_rel_error);
                reference_error.rmse =
                    std::max(reference_error.rmse, report.cpu_reference_error->rmse);
            }
            if (report.gpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error =
                    std::max(reference_error.max_abs_error, report.gpu_reference_error->max_abs_error);
                reference_error.max_rel_error =
                    std::max(reference_error.max_rel_error, report.gpu_reference_error->max_rel_error);
                reference_error.rmse =
                    std::max(reference_error.rmse, report.gpu_reference_error->rmse);
            }
            if (report.cpu_perf.has_value()) cpu_perf_medians.push_back(report.cpu_perf->median_ms);
            if (report.gpu_e2e_perf.has_value()) gpu_e2e_perf_medians.push_back(report.gpu_e2e_perf->median_ms);
            if (report.gpu_kernel_perf.has_value()) gpu_kernel_perf_medians.push_back(report.gpu_kernel_perf->median_ms);
            if (!report.pass) summary.failed_cases.push_back(report.case_id);
        }

        if (has_reference_error) summary.reference_error = reference_error;
        if (!cpu_perf_medians.empty()) summary.cpu_perf = compute_timing_stats(cpu_perf_medians);
        if (!gpu_e2e_perf_medians.empty()) summary.gpu_e2e_perf = compute_timing_stats(gpu_e2e_perf_medians);
        if (!gpu_kernel_perf_medians.empty()) summary.gpu_kernel_perf = compute_timing_stats(gpu_kernel_perf_medians);
        return summary;
    }

    void write_reports(const std::string &op, const CliOptions &options, const std::vector<CaseReport> &cases)
    {
        const OperatorSummary summary = summarize_cases(op, cases);
        cusignal_test::report::write_operator_report(
            "wavelets",
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
        cusignal_test::report::update_module_reports("wavelets", module_report_root());
    }

    void print_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << "[wavelets/" << op << "] "
                  << (summary.pass ? "PASS" : "FAIL")
                  << "  accuracy_cases=" << summary.accuracy_cases
                  << "  perf_cases=" << summary.perf_cases << '\n';
        std::cout << "cpu_gpu_error : max_abs=" << format_float(summary.cpu_gpu_error.max_abs_error)
                  << "  max_rel=" << format_float(summary.cpu_gpu_error.max_rel_error)
                  << "  rmse=" << format_float(summary.cpu_gpu_error.rmse) << '\n';
        if (summary.reference_error.has_value())
        {
            std::cout << "reference_error : max_abs=" << format_float(summary.reference_error->max_abs_error)
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
            std::cout << "gpu_perf_ms   : e2e_median=" << format_fixed(summary.gpu_e2e_perf->median_ms)
                      << "  kernel_median="
                      << (summary.gpu_kernel_perf.has_value() ? format_fixed(summary.gpu_kernel_perf->median_ms) : "n/a")
                      << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                      << "  e2e_speedup=" << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x"
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
        std::cout << "reports       : data/.reports_staging/unit/wavelets/" << op << "/latest_summary.md\n";
    }

    CaseReport evaluate_accuracy_case(
        const std::string &op,
        const WaveletsCase &test_case,
        const Runner &runner)
    {
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

        const OutputBundle cpu_output =
            apply_dtype_quantization(runner.cpu(test_case), test_case.dtype);
        const OutputBundle gpu_output =
            apply_dtype_quantization(materialize(runner.gpu(test_case)), test_case.dtype);
        const OutputBundle expected = load_expected_bundle(op, test_case);
        report.samples = output_shape_size(cpu_output);
        report.cpu_gpu_error = compute_bundle_error(cpu_output, gpu_output);
        report.cpu_reference_error = compute_bundle_error(cpu_output, expected);
        report.gpu_reference_error = compute_bundle_error(gpu_output, expected);
        report.pass =
            bundle_within_tolerance(cpu_output, expected, test_case.atol, test_case.rtol) &&
            bundle_within_tolerance(gpu_output, expected, test_case.atol, test_case.rtol);
        return report;
    }

    CaseReport evaluate_perf_case(
        const std::string &op,
        const WaveletsCase &test_case,
        const Runner &runner,
        const CliOptions &options)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;

        std::optional<ZxGpuRealSignal> qmf_device_input;
        if (op == "qmf")
        {
            qmf_device_input.emplace(ZxGpuRealSignal::from_host(load_hk_signal(test_case)));
        }
        std::optional<ZxGpuRealSignal> cwt_device_data;
        std::optional<RealSignal> cwt_widths;
        if (op == "cwt")
        {
            const RealSignal data = load_data_signal(test_case);
            cwt_widths.emplace(load_widths_signal(test_case));
            report.samples = data.size() * cwt_widths->size();
            cwt_device_data.emplace(ZxGpuRealSignal::from_host(data));
        }
        auto run_gpu_perf = [&]() {
            if (qmf_device_input.has_value())
            {
                return make_device_bundle(
                    cusignal::zx_gpu_backend::wavelets::qmf(*qmf_device_input));
            }
            if (cwt_device_data.has_value() && cwt_widths.has_value())
            {
                return make_device_bundle(cusignal::zx_gpu_backend::wavelets::cwt(
                    *cwt_device_data,
                    test_case.wavelet,
                    *cwt_widths));
            }
            return runner.gpu(test_case);
        };

        OutputBundle gpu_output;
        if (!options.gpu_only_perf)
        {
            gpu_output = materialize(run_gpu_perf());
            report.samples = output_shape_size(gpu_output);
        }
        else if (report.samples == 0)
        {
            report.samples = 0;
        }
        if (!options.gpu_only_perf)
        {
            const OutputBundle cpu_output = runner.cpu(test_case);
            report.cpu_gpu_error = compute_bundle_error(cpu_output, gpu_output);
        }
        report.pass = true;

        if (!options.gpu_only_perf)
        {
            report.cpu_perf = benchmark_host_latency(options, [&]() { (void)runner.cpu(test_case); });
        }
        report.gpu_e2e_perf = benchmark_host_latency(options, [&]() {
            (void)run_gpu_perf();
            cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
        });
        report.gpu_kernel_perf =
            benchmark_gpu_kernel_latency(options, [&]() { (void)run_gpu_perf(); });

        if (options.emit_report)
        {
            const fs::path op_generated_root = generated_root(op);
            if (!options.gpu_only_perf)
            {
                write_input_samples(op_generated_root / "input", op, test_case, &report.artifacts);
                const OutputBundle cpu_output = runner.cpu(test_case);
                for (const OutputField &field : cpu_output.fields)
                {
                    write_field_sample(op_generated_root / "output_samples", test_case.id, "cpu", field, &report.artifacts);
                }
                for (const OutputField &field : gpu_output.fields)
                {
                    write_field_sample(op_generated_root / "output_samples", test_case.id, "gpu", field, &report.artifacts);
                }
            }
        }

        return report;
    }

    int run_wavelets_operator_tests(const std::string &op, int argc, char **argv)
    {
        const CliOptions options = parse_cli(argc, argv);
        const Runner runner = resolve_runner(op);

        std::vector<CaseReport> reports;
        if (include_accuracy_cases(options))
        {
            const std::vector<WaveletsCase> accuracy_cases =
                load_wavelets_cases(op, reference_root(op) / "manifest.json", "accuracy");
            for (const WaveletsCase &test_case : accuracy_cases)
            {
                reports.push_back(evaluate_accuracy_case(op, test_case, runner));
            }
        }
        if (include_perf_cases(options))
        {
            const std::vector<WaveletsCase> perf_cases =
                load_wavelets_cases(op, generated_root(op) / "manifest.json", "perf");
            for (const WaveletsCase &test_case : perf_cases)
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

    int run_operator_entry(const std::string &op, int argc, char **argv)
    {
        try
        {
            return run_wavelets_operator_tests(op, argc, argv);
        }
        catch (const std::exception &error)
        {
            std::cerr << "[wavelets] ERROR: " << error.what() << '\n';
            return 1;
        }
    }
} // namespace

int run_qmf_tests(int argc, char **argv)
{
    return run_operator_entry("qmf", argc, argv);
}

int run_morlet_tests(int argc, char **argv)
{
    return run_operator_entry("morlet", argc, argv);
}

int run_ricker_tests(int argc, char **argv)
{
    return run_operator_entry("ricker", argc, argv);
}

int run_morlet2_tests(int argc, char **argv)
{
    return run_operator_entry("morlet2", argc, argv);
}

int run_cwt_tests(int argc, char **argv)
{
    return run_operator_entry("cwt", argc, argv);
}
