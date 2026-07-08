#include "filter_design_test_support.hpp"

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
#include <type_traits>
#include <vector>

#include "../../../include/cusignal/filter_design/filter_design.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace filter_design_test_hooks
        {
            float consume_last_kernel_ms();
        }
    } // namespace zx_gpu_backend
} // namespace cusignal

namespace
{
    namespace filter_design_api = cusignal::filter_design_api;
    using cusignal::core::Complex;
    using cusignal::core::ComplexSignal;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    using cusignal::core::Float16;
    using cusignal::core::IndexVector;
    using cusignal::core::NamedFloatPairParameter;
    using cusignal::core::NamedFloatParameter;
    using cusignal::core::NamedTaylorParameter;
    using cusignal::core::PassZeroSpec;
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

    struct FilterDesignCase
    {
        std::string id;
        std::string category;
        std::string input_kind = "real"; // cmplx_sort 使用的输入域
        int numtaps = 0; // firwin / firwin2 的 FIR taps 数
        float attenuation = 0.0; // kaiser_atten / kaiser_beta 的衰减（dB）
        float width = -1.0; // firwin 的过渡带宽度（负值表示禁用）
        float nyq = -1.0; // 兼容旧接口的 Nyquist 频率参数（负值表示未使用）
        float fs = 2.0; // 用于 cutoff/freq 归一化的采样频率
        int nfreqs = 0; // firwin2 的插值网格大小
        bool antisymmetric = false; // 强制 firwin2 生成反对称冲激响应
        bool scale = true; // 开启设计 taps 的单位增益归一化
        bool cutoff_is_scalar = false; // 当 cutoff 为标量而非向量时为 true
        bool pass_zero_is_bool = true; // pass_zero 使用 bool 或 string 编码
        bool pass_zero_bool = true; // pass_zero 以 bool 编码时的取值
        std::string pass_zero_string;
        RealSignal cutoff;
        RealSignal freq;
        RealSignal gain;
        std::optional<WindowSpec> window;
        fs::path input_file;
        fs::path expected_values_file;
        fs::path expected_indices_file;
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较
    };

    struct OutputBundle
    {
        bool is_complex = false;
        RealSignal real_values;
        ComplexSignal complex_values;
        IndexVector indices;
        bool has_indices = false;
    };

    struct DeviceOutputBundle
    {
        bool is_complex = false;
        ZxGpuRealSignal real_values;
        ZxGpuComplexSignal complex_values;
        ZxGpuIndexSignal indices;
        bool has_indices = false;
    };

    using JsonArray = cusignal_test::json::Array;
    using JsonObject = cusignal_test::json::Object;
    using JsonValue = cusignal_test::json::Value;
    using CpuRunner = std::function<OutputBundle(const FilterDesignCase &)>;
    using GpuRunner = std::function<DeviceOutputBundle(const FilterDesignCase &)>;

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
        return repo_root() / "data" / "reference" / "unit" / "filter_design" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return repo_root() / "data" / "generated" / "unit" / "filter_design" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / "reports" / "unit" / "filter_design" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / "reports" / "unit" / "filter_design";
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
                continue;
            }
            values.push_back(std::stod(line.substr(line.find_last_of(',') == std::string::npos ? 0 : line.find_last_of(',') + 1)));
        }
        return values;
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
                throw std::runtime_error("invalid complex CSV row: " + line);
            }
            const float real = std::stod(line.substr(0, comma));
            const float imag = std::stod(line.substr(comma + 1));
            values.emplace_back(real, imag);
        }
        return values;
    }

    IndexVector read_index_csv(const fs::path &path)
    {
        std::ifstream input(path);
        if (!input)
        {
            throw std::runtime_error("failed to open CSV file: " + path.string());
        }

        IndexVector values;
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
            values.push_back(std::stoi(line.substr(line.find_last_of(',') == std::string::npos ? 0 : line.find_last_of(',') + 1)));
        }
        return values;
    }

    RealSignal make_cmplx_sort_real_input(const FilterDesignCase &test_case)
    {
        if (test_case.id == "real_case")
        {
            return RealSignal{-3.0, 1.0, -2.0, 2.0, 0.5};
        }
        throw std::runtime_error("unsupported real cmplx_sort case: " + test_case.id);
    }

    ComplexSignal make_cmplx_sort_complex_input(const FilterDesignCase &test_case)
    {
        if (test_case.id == "complex_case")
        {
            return ComplexSignal{
                Complex(1.0, 1.0),
                Complex(3.0, 4.0),
                Complex(0.0, 1.0),
                Complex(-2.0, 0.0),
                Complex(-2.0, 2.0)};
        }
        if (test_case.id == "perf_complex")
        {
            constexpr std::size_t sample_count = 4096;
            const float pi = std::acos(-1.0);
            const float phase_scale = (8.0 * pi) / static_cast<float>(sample_count - 1);
            ComplexSignal input;
            input.reserve(sample_count);
            for (std::size_t index = 0; index < sample_count; ++index)
            {
                const float phase = phase_scale * static_cast<float>(index);
                input.emplace_back(std::cos(phase), std::sin(phase));
            }
            return input;
        }
        throw std::runtime_error("unsupported complex cmplx_sort case: " + test_case.id);
    }

    OutputBundle make_cmplx_sort_expected_bundle(const FilterDesignCase &test_case)
    {
        OutputBundle expected;
        expected.has_indices = true;
        if (test_case.input_kind == "complex")
        {
            const ComplexSignal input = make_cmplx_sort_complex_input(test_case);
            const filter_design_api::ComplexSortResult sorted = cusignal::cpu::filter_design::cmplx_sort(input);
            expected.is_complex = true;
            expected.complex_values = std::get<ComplexSignal>(sorted.values);
            expected.indices = sorted.indices;
            return expected;
        }

        const RealSignal input = make_cmplx_sort_real_input(test_case);
        const filter_design_api::ComplexSortResult sorted = cusignal::cpu::filter_design::cmplx_sort(input);
        expected.real_values = std::get<RealSignal>(sorted.values);
        expected.indices = sorted.indices;
        return expected;
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

    void write_index_csv(const fs::path &path, const IndexVector &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write CSV file: " + path.string());
        }
        output << "value\n";
        for (int value : values)
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

    ComplexSignal sample_values(const ComplexSignal &values, std::size_t limit = 32)
    {
        if (values.size() <= limit)
        {
            return values;
        }
        return ComplexSignal(values.begin(), values.begin() + static_cast<long>(limit));
    }

    IndexVector sample_values(const IndexVector &values, std::size_t limit = 32)
    {
        if (values.size() <= limit)
        {
            return values;
        }
        return IndexVector(values.begin(), values.begin() + static_cast<long>(limit));
    }

    void write_output_samples(
        const fs::path &base_dir,
        const std::string &case_id,
        const std::string &backend,
        const OutputBundle &bundle,
        std::vector<Artifact> *artifacts)
    {
        const fs::path values_path = base_dir / (case_id + "__" + backend + "__signal.csv");
        if (bundle.is_complex)
        {
            write_complex_csv(values_path, sample_values(bundle.complex_values));
        }
        else
        {
            write_real_csv(values_path, sample_values(bundle.real_values));
        }
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{backend + "_signal", values_path});
        }

        if (bundle.has_indices)
        {
            const fs::path indices_path = base_dir / (case_id + "__" + backend + "__indices.csv");
            write_index_csv(indices_path, sample_values(bundle.indices));
            if (artifacts != nullptr)
            {
                artifacts->push_back(Artifact{backend + "_indices", indices_path});
            }
        }
    }

    std::string relative_path_string(const fs::path &path)
    {
        return fs::relative(path, repo_root()).generic_string();
    }

    float mixed_error_for_sample(float abs_error, float expected_norm, float atol, float reference_scale)
    {
        const float effective_atol = std::max(std::max(atol, 1.0e-5f), 1.0e-2f * reference_scale);
        return expected_norm <= effective_atol ? abs_error : abs_error / expected_norm;
    }

    ErrorMetrics compute_error_metrics(const RealSignal &lhs, const RealSignal &rhs, float mixed_atol = 1.0e-5f)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("shape mismatch while comparing real outputs");
        }

        ErrorMetrics metrics;
        metrics.compared_samples = lhs.size();
        float reference_scale = 0.0f;
        for (float value : lhs)
        {
            reference_scale = std::max(reference_scale, std::fabs(value));
        }
        float l2_sum = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float abs_error = std::fabs(lhs[index] - rhs[index]);
            const float expected_norm = std::fabs(lhs[index]);
            const float denom = std::max(std::fabs(rhs[index]), 1e-15f);
            const float rel_error = abs_error / denom;
            const float mixed_error = mixed_error_for_sample(abs_error, expected_norm, mixed_atol, reference_scale);
            metrics.max_abs_error = std::max(metrics.max_abs_error, abs_error);
            metrics.max_rel_error = std::max(metrics.max_rel_error, rel_error);
            metrics.mixed_error = std::max(metrics.mixed_error, mixed_error);
            l2_sum += abs_error * abs_error;
            if (abs_error > 0.0 && metrics.first_mismatch_index < 0)
            {
                metrics.first_mismatch_index = static_cast<long long>(index);
                metrics.exact_match = false;
            }
        }
        metrics.l2_error = std::sqrt(l2_sum);
        metrics.rmse = lhs.empty() ? 0.0 : std::sqrt(l2_sum / static_cast<float>(lhs.size()));
        return metrics;
    }

    ErrorMetrics compute_error_metrics(const ComplexSignal &lhs, const ComplexSignal &rhs, float mixed_atol = 1.0e-5f)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::runtime_error("shape mismatch while comparing complex outputs");
        }

        ErrorMetrics metrics;
        metrics.compared_samples = lhs.size();
        float reference_scale = 0.0f;
        for (const Complex &value : lhs)
        {
            reference_scale = std::max(reference_scale, std::abs(value));
        }
        float l2_sum = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float abs_error = std::abs(lhs[index] - rhs[index]);
            const float expected_norm = std::abs(lhs[index]);
            const float denom = std::max(std::abs(rhs[index]), 1e-15f);
            const float rel_error = abs_error / denom;
            const float mixed_error = mixed_error_for_sample(abs_error, expected_norm, mixed_atol, reference_scale);
            metrics.max_abs_error = std::max(metrics.max_abs_error, abs_error);
            metrics.max_rel_error = std::max(metrics.max_rel_error, rel_error);
            metrics.mixed_error = std::max(metrics.mixed_error, mixed_error);
            l2_sum += abs_error * abs_error;
            if (abs_error > 0.0 && metrics.first_mismatch_index < 0)
            {
                metrics.first_mismatch_index = static_cast<long long>(index);
                metrics.exact_match = false;
            }
        }
        metrics.l2_error = std::sqrt(l2_sum);
        metrics.rmse = lhs.empty() ? 0.0 : std::sqrt(l2_sum / static_cast<float>(lhs.size()));
        return metrics;
    }

    bool within_tolerance(const RealSignal &lhs, const RealSignal &rhs, float atol, float rtol)
    {
        if (lhs.size() != rhs.size())
        {
            return false;
        }
        const float effective_atol = std::max(atol, 1.0e-5f);
        const float effective_rtol = std::max(rtol, 1.0e-5f);
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float tolerance = effective_atol + effective_rtol * std::fabs(rhs[index]);
            if (std::fabs(lhs[index] - rhs[index]) > tolerance)
            {
                return false;
            }
        }
        return true;
    }

    bool within_tolerance(const ComplexSignal &lhs, const ComplexSignal &rhs, float atol, float rtol)
    {
        if (lhs.size() != rhs.size())
        {
            return false;
        }
        const float effective_atol = std::max(atol, 1.0e-5f);
        const float effective_rtol = std::max(rtol, 1.0e-5f);
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float tolerance = effective_atol + effective_rtol * std::abs(rhs[index]);
            if (std::abs(lhs[index] - rhs[index]) > tolerance)
            {
                return false;
            }
        }
        return true;
    }

    TimingStats summarize_timings(const std::vector<float> &samples_ms)
    {
        if (samples_ms.empty())
        {
            throw std::runtime_error("cannot summarize empty timing sample set");
        }
        TimingStats stats;
        stats.samples_ms = samples_ms;
        std::vector<float> sorted = samples_ms;
        std::sort(sorted.begin(), sorted.end());
        stats.min_ms = sorted.front();
        stats.max_ms = sorted.back();
        const float sum = std::accumulate(samples_ms.begin(), samples_ms.end(), 0.0);
        stats.mean_ms = sum / static_cast<float>(samples_ms.size());
        if (sorted.size() % 2 == 0)
        {
            stats.median_ms = 0.5 * (sorted[sorted.size() / 2 - 1] + sorted[sorted.size() / 2]);
        }
        else
        {
            stats.median_ms = sorted[sorted.size() / 2];
        }
        const std::size_t p95_index = static_cast<std::size_t>(
            std::ceil(0.95 * static_cast<float>(sorted.size())) - 1.0);
        stats.p95_ms = sorted[std::min(p95_index, sorted.size() - 1)];
        float variance = 0.0;
        for (float sample : samples_ms)
        {
            const float diff = sample - stats.mean_ms;
            variance += diff * diff;
        }
        variance /= static_cast<float>(samples_ms.size());
        stats.std_ms = std::sqrt(variance);
        return stats;
    }

    template <typename Callable>
    TimingStats benchmark_host_latency(const CliOptions &options, Callable callable)
    {
        std::vector<float> durations;
        for (int iteration = 0; iteration < options.warmup; ++iteration)
        {
            callable();
        }
        for (int iteration = 0; iteration < options.repeat; ++iteration)
        {
            const auto start = std::chrono::high_resolution_clock::now();
            callable();
            const auto stop = std::chrono::high_resolution_clock::now();
            durations.push_back(
                std::chrono::duration<float, std::milli>(stop - start).count());
        }
        return summarize_timings(durations);
    }

    template <typename Callable>
    TimingStats benchmark_gpu_kernel_latency(const CliOptions &options, Callable callable)
    {
        std::vector<float> durations;
        for (int iteration = 0; iteration < options.warmup; ++iteration)
        {
            callable();
            (void)cusignal::zx_gpu_backend::filter_design_test_hooks::consume_last_kernel_ms();
        }
        for (int iteration = 0; iteration < options.repeat; ++iteration)
        {
            callable();
            durations.push_back(
                cusignal::zx_gpu_backend::filter_design_test_hooks::consume_last_kernel_ms());
        }
        return summarize_timings(durations);
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

    PassZeroSpec parse_pass_zero(const JsonValue &value)
    {
        const JsonObject &object = as_object(value);
        const std::string kind = get_string(object, "kind");
        if (kind == "bool")
        {
            return PassZeroSpec{get_bool(object, "value")};
        }
        if (kind == "string")
        {
            return PassZeroSpec{get_string(object, "value")};
        }
        throw std::runtime_error("unsupported pass_zero kind");
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
                    stream << "{\n  \"kind\": \"string\",\n  \"value\": \"" << json_escape(value) << "\"\n}";
                }
                else if constexpr (std::is_same_v<T, float>)
                {
                    stream << "{\n  \"kind\": \"float\",\n  \"value\": " << value << "\n}";
                }
                else if constexpr (std::is_same_v<T, NamedFloatParameter>)
                {
                    stream << "{\n  \"kind\": \"named_float\",\n  \"name\": \"" << json_escape(value.name)
                           << "\",\n  \"value\": " << value.value << "\n}";
                }
                else if constexpr (std::is_same_v<T, NamedFloatPairParameter>)
                {
                    stream << "{\n  \"kind\": \"named_pair\",\n  \"name\": \"" << json_escape(value.name)
                           << "\",\n  \"first\": " << value.first << ",\n  \"second\": " << value.second << "\n}";
                }
                else if constexpr (std::is_same_v<T, NamedTaylorParameter>)
                {
                    stream << "{\n  \"kind\": \"named_taylor\",\n  \"name\": \"" << json_escape(value.name)
                           << "\",\n  \"nbar\": " << value.nbar << ",\n  \"sll\": " << value.sll
                           << ",\n  \"norm\": " << (value.norm ? "true" : "false") << "\n}";
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

    std::string build_pass_zero_json(const FilterDesignCase &test_case)
    {
        std::ostringstream stream;
        if (test_case.pass_zero_is_bool)
        {
            stream << "{\n  \"kind\": \"bool\",\n  \"value\": "
                   << (test_case.pass_zero_bool ? "true" : "false") << "\n}";
        }
        else
        {
            stream << "{\n  \"kind\": \"string\",\n  \"value\": \"" << json_escape(test_case.pass_zero_string)
                   << "\"\n}";
        }
        return stream.str();
    }

    std::string build_case_spec_json(const FilterDesignCase &test_case)
    {
        std::ostringstream stream;
        stream << "{\n"
               << "  \"id\": \"" << json_escape(test_case.id) << "\"";
        if (test_case.numtaps > 0)
        {
            stream << ",\n  \"numtaps\": " << test_case.numtaps;
        }
        if (!test_case.cutoff.empty())
        {
            if (test_case.cutoff_is_scalar)
            {
                stream << ",\n  \"cutoff\": " << test_case.cutoff.front();
            }
            else
            {
                stream << ",\n  \"cutoff\": [";
                for (std::size_t index = 0; index < test_case.cutoff.size(); ++index)
                {
                    if (index != 0)
                    {
                        stream << ", ";
                    }
                    stream << test_case.cutoff[index];
                }
                stream << "]";
            }
        }
        if (!test_case.freq.empty())
        {
            stream << ",\n  \"freq\": [";
            for (std::size_t index = 0; index < test_case.freq.size(); ++index)
            {
                if (index != 0)
                {
                    stream << ", ";
                }
                stream << test_case.freq[index];
            }
            stream << "]";
        }
        if (!test_case.gain.empty())
        {
            stream << ",\n  \"gain\": [";
            for (std::size_t index = 0; index < test_case.gain.size(); ++index)
            {
                if (index != 0)
                {
                    stream << ", ";
                }
                stream << test_case.gain[index];
            }
            stream << "]";
        }
        if (!test_case.input_file.empty())
        {
            stream << ",\n  \"x_file\": \"" << json_escape(relative_path_string(test_case.input_file)) << "\"";
        }
        stream << ",\n  \"attenuation\": " << test_case.attenuation
               << ",\n  \"width\": " << test_case.width
               << ",\n  \"nyq\": " << test_case.nyq
               << ",\n  \"fs\": " << test_case.fs
               << ",\n  \"nfreqs\": " << test_case.nfreqs
               << ",\n  \"antisymmetric\": " << (test_case.antisymmetric ? "true" : "false")
               << ",\n  \"scale\": " << (test_case.scale ? "true" : "false");
        if (test_case.window.has_value())
        {
            stream << ",\n  \"window\": " << build_window_spec_json(*test_case.window);
        }
        if (!test_case.cutoff.empty())
        {
            stream << ",\n  \"pass_zero\": " << build_pass_zero_json(test_case);
        }
        stream << "\n}\n";
        return stream.str();
    }

    std::vector<FilterDesignCase> load_cases(
        const fs::path &manifest_path,
        const std::string &category)
    {
        std::vector<FilterDesignCase> cases;
        const JsonValue manifest = cusignal_test::json::parse(read_text_file(manifest_path));
        const JsonObject &root = as_object(manifest);
        const JsonArray &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const JsonValue &item : case_array)
        {
            const JsonObject &object = as_object(item);
            FilterDesignCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.input_kind = get_optional_string(object, "input_kind").value_or("real"); // cmplx_sort 输入类型：real / complex
            test_case.numtaps = get_optional_int(object, "numtaps", 0); // FIR taps 数
            test_case.attenuation = get_optional_number(object, "attenuation", 0.0); // 衰减（dB）
            test_case.width = get_optional_number(object, "width", -1.0); // firwin 过渡带宽度
            test_case.nyq = get_optional_number(object, "nyq", -1.0); // 兼容旧接口的 Nyquist 参数
            test_case.fs = get_optional_number(object, "fs", 2.0); // 采样频率
            test_case.nfreqs = get_optional_int(object, "nfreqs", 0); // firwin2 插值网格大小
            test_case.antisymmetric = get_optional_bool(object, "antisymmetric", false); // 反对称响应开关
            test_case.scale = get_optional_bool(object, "scale", true); // 设计后增益归一化开关
            test_case.atol = get_optional_number(object, "atol", 0.0); // 绝对误差容限
            test_case.rtol = get_optional_number(object, "rtol", 0.0); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype
            if (const auto cutoff_iter = object.find("cutoff"); cutoff_iter != object.end())
            {
                if (cutoff_iter->second.is_number())
                {
                    test_case.cutoff = RealSignal{cutoff_iter->second.as_number()};
                    test_case.cutoff_is_scalar = true;
                }
                else
                {
                    test_case.cutoff = json_array_to_signal(cutoff_iter->second);
                    test_case.cutoff_is_scalar = false;
                }
            }
            if (const auto freq_iter = object.find("freq"); freq_iter != object.end())
            {
                test_case.freq = json_array_to_signal(freq_iter->second);
            }
            if (const auto gain_iter = object.find("gain"); gain_iter != object.end())
            {
                test_case.gain = json_array_to_signal(gain_iter->second);
            }
            if (const auto window_iter = object.find("window"); window_iter != object.end())
            {
                test_case.window = parse_window_spec(window_iter->second);
            }
            if (const auto pass_zero_iter = object.find("pass_zero"); pass_zero_iter != object.end())
            {
                const PassZeroSpec pass_zero = parse_pass_zero(pass_zero_iter->second);
                if (std::holds_alternative<bool>(pass_zero))
                {
                    test_case.pass_zero_is_bool = true;
                    test_case.pass_zero_bool = std::get<bool>(pass_zero);
                }
                else
                {
                    test_case.pass_zero_is_bool = false;
                    test_case.pass_zero_string = std::get<std::string>(pass_zero);
                }
            }
            if (const std::optional<std::string> input_file = get_optional_string(object, "x_file"))
            {
                test_case.input_file = base / *input_file;
            }
            else if (const std::optional<std::string> input_file = get_optional_string(object, "input_file"))
            {
                test_case.input_file = base / *input_file;
            }
            if (const std::optional<std::string> expected_values_file =
                    get_optional_string(object, "expected_signal_file"))
            {
                test_case.expected_values_file = base / *expected_values_file;
            }
            else if (const std::optional<std::string> expected_values_file =
                         get_optional_string(object, "expected_values_file"))
            {
                test_case.expected_values_file = base / *expected_values_file;
            }
            if (const std::optional<std::string> expected_indices_file = get_optional_string(object, "expected_indices_file"))
            {
                test_case.expected_indices_file = base / *expected_indices_file;
            }
            cases.push_back(std::move(test_case));
        }
        return cases;
    }

    OutputBundle materialize(const DeviceOutputBundle &device)
    {
        OutputBundle host;
        host.is_complex = device.is_complex;
        host.has_indices = device.has_indices;
        if (device.is_complex)
        {
            host.complex_values = device.complex_values.get();
        }
        else
        {
            host.real_values = device.real_values.get();
        }
        if (device.has_indices)
        {
            host.indices = device.indices.get();
        }
        return host;
    }

    float quantize_float16(float value)
    {
        return __half2float(Float16(value));
    }

    OutputBundle apply_dtype_quantization(const OutputBundle &bundle, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return bundle;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported filter_design dtype compatibility case: " + dtype);
        }
        if (bundle.is_complex)
        {
            throw std::runtime_error("float16 compatibility case must use real filter_design output");
        }

        OutputBundle quantized = bundle;
        for (float &value : quantized.real_values)
        {
            value = quantize_float16(value);
        }
        return quantized;
    }

    std::size_t value_size(const OutputBundle &bundle)
    {
        return bundle.is_complex ? bundle.complex_values.size() : bundle.real_values.size();
    }

    OutputBundle load_expected_bundle(const std::string &op, const FilterDesignCase &test_case)
    {
        if (op == "cmplx_sort")
        {
            return make_cmplx_sort_expected_bundle(test_case);
        }

        OutputBundle expected;
        expected.has_indices = !test_case.expected_indices_file.empty();
        expected.is_complex = (op == "cmplx_sort" && test_case.input_kind == "complex");
        if (expected.is_complex)
        {
            expected.complex_values = read_complex_csv(test_case.expected_values_file);
        }
        else
        {
            expected.real_values = read_real_csv(test_case.expected_values_file);
        }
        if (expected.has_indices)
        {
            expected.indices = read_index_csv(test_case.expected_indices_file);
        }
        return expected;
    }

    std::optional<std::string> compare_indices(const IndexVector &lhs, const IndexVector &rhs)
    {
        if (lhs == rhs)
        {
            return std::nullopt;
        }
        std::ostringstream note;
        note << "index mismatch";
        return note.str();
    }

    OutputBundle scalar_output(float value)
    {
        OutputBundle bundle;
        bundle.real_values = RealSignal{value};
        return bundle;
    }

    DeviceOutputBundle scalar_output_device(float value)
    {
        DeviceOutputBundle bundle;
        bundle.real_values = ZxGpuRealSignal::from_host(RealSignal{value});
        return bundle;
    }

    OutputBundle make_output(const RealSignal &values)
    {
        OutputBundle bundle;
        bundle.real_values = values;
        return bundle;
    }

    OutputBundle make_output(const ComplexSignal &values)
    {
        OutputBundle bundle;
        bundle.is_complex = true;
        bundle.complex_values = values;
        return bundle;
    }

    DeviceOutputBundle make_output(const ZxGpuRealSignal &values)
    {
        DeviceOutputBundle bundle;
        bundle.real_values = values;
        return bundle;
    }

    DeviceOutputBundle make_output(const ZxGpuComplexSignal &values)
    {
        DeviceOutputBundle bundle;
        bundle.is_complex = true;
        bundle.complex_values = values;
        return bundle;
    }

    Runner resolve_runner(const std::string &op)
    {
        using namespace cusignal;
        if (op == "kaiser_beta")
        {
            return Runner{
                [](const FilterDesignCase &test_case)
                {
                    return scalar_output(cpu::filter_design::kaiser_beta(test_case.attenuation));
                },
                [](const FilterDesignCase &test_case)
                {
                    return scalar_output_device(zx_gpu_backend::filter_design::kaiser_beta(test_case.attenuation));
                }};
        }
        if (op == "kaiser_atten")
        {
            return Runner{
                [](const FilterDesignCase &test_case)
                {
                    return scalar_output(cpu::filter_design::kaiser_atten(test_case.numtaps, test_case.width));
                },
                [](const FilterDesignCase &test_case)
                {
                    return scalar_output_device(zx_gpu_backend::filter_design::kaiser_atten(test_case.numtaps, test_case.width));
                }};
        }
        if (op == "cmplx_sort")
        {
            return Runner{
                [](const FilterDesignCase &test_case)
                {
                    return make_cmplx_sort_expected_bundle(test_case);
                },
                [](const FilterDesignCase &test_case)
                {
                    DeviceOutputBundle bundle;
                    if (test_case.input_kind == "complex")
                    {
                        const ComplexSignal input = make_cmplx_sort_complex_input(test_case);
                        const filter_design_api::ZxGpuComplexSortResult sorted =
                            zx_gpu_backend::filter_design::cmplx_sort(input);
                        bundle.is_complex = true;
                        bundle.complex_values = std::get<ZxGpuComplexSignal>(sorted.values);
                        bundle.indices = sorted.indices;
                        bundle.has_indices = true;
                    }
                    else
                    {
                        const RealSignal input = make_cmplx_sort_real_input(test_case);
                        const filter_design_api::ZxGpuComplexSortResult sorted =
                            zx_gpu_backend::filter_design::cmplx_sort(input);
                        bundle.real_values = std::get<ZxGpuRealSignal>(sorted.values);
                        bundle.indices = sorted.indices;
                        bundle.has_indices = true;
                    }
                    return bundle;
                }};
        }
        if (op == "firwin")
        {
            return Runner{
                [](const FilterDesignCase &test_case)
                {
                    const WindowSpec window = test_case.window.value_or(WindowSpec{std::string("hamming")});
                    const PassZeroSpec pass_zero = test_case.pass_zero_is_bool
                                                       ? PassZeroSpec{test_case.pass_zero_bool}
                                                       : PassZeroSpec{test_case.pass_zero_string};
                    if (test_case.cutoff_is_scalar)
                    {
                        return make_output(cpu::filter_design::firwin(
                            test_case.numtaps,
                            test_case.cutoff.front(),
                            test_case.width,
                            window,
                            pass_zero,
                            test_case.scale,
                            test_case.nyq,
                            test_case.fs));
                    }
                    return make_output(cpu::filter_design::firwin(
                        test_case.numtaps,
                        test_case.cutoff,
                        test_case.width,
                        window,
                        pass_zero,
                        test_case.scale,
                        test_case.nyq,
                        test_case.fs));
                },
                [](const FilterDesignCase &test_case)
                {
                    const WindowSpec host_window = test_case.window.value_or(WindowSpec{std::string("hamming")});
                    const ZxGpuWindowSpec window = to_zx_gpu_window_spec(host_window);
                    const PassZeroSpec pass_zero = test_case.pass_zero_is_bool
                                                       ? PassZeroSpec{test_case.pass_zero_bool}
                                                       : PassZeroSpec{test_case.pass_zero_string};
                    if (test_case.cutoff_is_scalar)
                    {
                        return make_output(zx_gpu_backend::filter_design::firwin(
                            test_case.numtaps,
                            test_case.cutoff.front(),
                            test_case.width,
                            window,
                            pass_zero,
                            test_case.scale,
                            test_case.nyq,
                            test_case.fs));
                    }
                    return make_output(zx_gpu_backend::filter_design::firwin(
                        test_case.numtaps,
                        test_case.cutoff,
                        test_case.width,
                        window,
                        pass_zero,
                        test_case.scale,
                        test_case.nyq,
                        test_case.fs));
                }};
        }
        if (op == "firwin2")
        {
            return Runner{
                [](const FilterDesignCase &test_case)
                {
                    const WindowSpec window = test_case.window.value_or(WindowSpec{std::string("hamming")});
                    return make_output(cpu::filter_design::firwin2(
                        test_case.numtaps,
                        test_case.freq,
                        test_case.gain,
                        test_case.nfreqs,
                        window,
                        test_case.nyq,
                        test_case.antisymmetric,
                        test_case.fs));
                },
                [](const FilterDesignCase &test_case)
                {
                    const WindowSpec host_window = test_case.window.value_or(WindowSpec{std::string("hamming")});
                    return make_output(zx_gpu_backend::filter_design::firwin2(
                        test_case.numtaps,
                        test_case.freq,
                        test_case.gain,
                        test_case.nfreqs,
                        to_zx_gpu_window_spec(host_window),
                        test_case.nyq,
                        test_case.antisymmetric,
                        test_case.fs));
                }};
        }
        throw std::runtime_error("unsupported filter_design operator: " + op);
    }

    ErrorMetrics output_error(const OutputBundle &lhs, const OutputBundle &rhs, float mixed_atol = 1.0e-5f)
    {
        if (lhs.is_complex != rhs.is_complex)
        {
            throw std::runtime_error("output kind mismatch while comparing results");
        }
        return lhs.is_complex
                   ? compute_error_metrics(lhs.complex_values, rhs.complex_values, mixed_atol)
                   : compute_error_metrics(lhs.real_values, rhs.real_values, mixed_atol);
    }

    bool output_within_tolerance(const OutputBundle &lhs, const OutputBundle &rhs, float atol, float rtol)
    {
        if (lhs.is_complex != rhs.is_complex)
        {
            return false;
        }
        return lhs.is_complex
                   ? within_tolerance(lhs.complex_values, rhs.complex_values, atol, rtol)
                   : within_tolerance(lhs.real_values, rhs.real_values, atol, rtol);
    }

    std::string build_timing_json(const TimingStats &stats)
    {
        std::ostringstream stream;
        stream << "{"
               << "\"mean_ms\":" << stats.mean_ms << ','
               << "\"median_ms\":" << stats.median_ms << ','
               << "\"p95_ms\":" << stats.p95_ms << ','
               << "\"min_ms\":" << stats.min_ms << ','
               << "\"max_ms\":" << stats.max_ms << ','
               << "\"std_ms\":" << stats.std_ms << "}";
        return stream.str();
    }

    std::string build_error_json(const ErrorMetrics &metrics)
    {
        std::ostringstream stream;
        stream << "{"
               << "\"max_abs_error\":" << metrics.max_abs_error << ','
               << "\"max_rel_error\":" << metrics.max_rel_error << ','
               << "\"mixed_error\":" << metrics.mixed_error << ','
               << "\"rmse\":" << metrics.rmse << ','
               << "\"l2_error\":" << metrics.l2_error << ','
               << "\"exact_match\":" << (metrics.exact_match ? "true" : "false") << ','
               << "\"first_mismatch_index\":" << metrics.first_mismatch_index << ','
               << "\"compared_samples\":" << metrics.compared_samples << "}";
        return stream.str();
    }

    std::string relative_or_empty(const fs::path &path)
    {
        return path.empty() ? std::string() : relative_path_string(path);
    }

    OperatorSummary summarize_cases(const std::string &op, const std::vector<CaseReport> &reports)
    {
        OperatorSummary summary;
        summary.operator_name = op;

        float max_ref_abs = 0.0;
        float max_ref_rel = 0.0;
        float max_ref_mixed = 0.0;
        float max_ref_rmse = 0.0;
        bool have_reference = false;
        std::vector<float> cpu_perf;
        std::vector<float> gpu_e2e_perf;
        std::vector<float> gpu_kernel_perf;

        for (const CaseReport &report : reports)
        {
            summary.pass = summary.pass && report.pass;
            if (!report.pass)
            {
                summary.failed_cases.push_back(report.case_id);
            }
            summary.cpu_gpu_error.max_abs_error =
                std::max(summary.cpu_gpu_error.max_abs_error, report.cpu_gpu_error.max_abs_error);
            summary.cpu_gpu_error.max_rel_error =
                std::max(summary.cpu_gpu_error.max_rel_error, report.cpu_gpu_error.max_rel_error);
            summary.cpu_gpu_error.mixed_error =
                std::max(summary.cpu_gpu_error.mixed_error, report.cpu_gpu_error.mixed_error);
            summary.cpu_gpu_error.rmse = std::max(summary.cpu_gpu_error.rmse, report.cpu_gpu_error.rmse);

            if (report.category == "accuracy")
            {
                ++summary.accuracy_cases;
            }
            else
            {
                ++summary.perf_cases;
            }

            if (report.cpu_reference_error.has_value())
            {
                have_reference = true;
                max_ref_abs = std::max(max_ref_abs, report.cpu_reference_error->max_abs_error);
                max_ref_rel = std::max(max_ref_rel, report.cpu_reference_error->max_rel_error);
                max_ref_mixed = std::max(max_ref_mixed, report.cpu_reference_error->mixed_error);
                max_ref_rmse = std::max(max_ref_rmse, report.cpu_reference_error->rmse);
            }
            if (report.cpu_perf.has_value())
            {
                cpu_perf.push_back(report.cpu_perf->median_ms);
            }
            if (report.gpu_e2e_perf.has_value())
            {
                gpu_e2e_perf.push_back(report.gpu_e2e_perf->median_ms);
            }
            if (report.gpu_kernel_perf.has_value())
            {
                gpu_kernel_perf.push_back(report.gpu_kernel_perf->median_ms);
            }
        }

        if (have_reference)
        {
            summary.reference_error = ErrorMetrics{};
            summary.reference_error->max_abs_error = max_ref_abs;
            summary.reference_error->max_rel_error = max_ref_rel;
            summary.reference_error->mixed_error = max_ref_mixed;
            summary.reference_error->rmse = max_ref_rmse;
        }
        if (!cpu_perf.empty())
        {
            summary.cpu_perf = summarize_timings(cpu_perf);
        }
        if (!gpu_e2e_perf.empty())
        {
            summary.gpu_e2e_perf = summarize_timings(gpu_e2e_perf);
        }
        if (!gpu_kernel_perf.empty())
        {
            summary.gpu_kernel_perf = summarize_timings(gpu_kernel_perf);
        }
        return summary;
    }

    void write_operator_reports(
        const std::string &op,
        const CliOptions &options,
        const std::vector<CaseReport> &reports)
    {
        const OperatorSummary summary = summarize_cases(op, reports);
        cusignal_test::report::write_operator_report(
            "filter_design",
            op,
            repo_root(),
            report_root(op),
            __cplusplus,
            CUDART_VERSION,
            options,
            summary,
            reports,
            cusignal_test::report::WritePolicy{});
    }

    void update_module_reports()
    {
        cusignal_test::report::update_module_reports("filter_design", module_report_root());
    }

    void print_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << "[filter_design/" << op << "] " << (summary.pass ? "PASS" : "FAIL")
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
        else
        {
            std::cout << "reference_error : max_abs=n/a  max_rel=n/a  rmse=n/a\n";
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
        std::cout << "reports       : data/reports/unit/filter_design/" << op << "/latest_summary.md\n";
    }

    CaseReport evaluate_accuracy_case(
        const std::string &op,
        const FilterDesignCase &test_case,
        const Runner &runner)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;
        const OutputBundle cpu_output =
            apply_dtype_quantization(runner.cpu(test_case), test_case.dtype);
        const OutputBundle gpu_output =
            apply_dtype_quantization(materialize(runner.gpu(test_case)), test_case.dtype);
        const OutputBundle expected =
            apply_dtype_quantization(load_expected_bundle(op, test_case), test_case.dtype);
        report.samples = value_size(cpu_output);
        report.cpu_gpu_error = output_error(cpu_output, gpu_output, test_case.atol);
        report.cpu_reference_error = output_error(cpu_output, expected, test_case.atol);
        report.gpu_reference_error = output_error(gpu_output, expected, test_case.atol);
        report.pass = output_within_tolerance(cpu_output, expected, test_case.atol, test_case.rtol) &&
                      output_within_tolerance(gpu_output, expected, test_case.atol, test_case.rtol);
        if (expected.has_indices)
        {
            const std::optional<std::string> cpu_note = compare_indices(cpu_output.indices, expected.indices);
            const std::optional<std::string> gpu_note = compare_indices(gpu_output.indices, expected.indices);
            if (cpu_note.has_value() || gpu_note.has_value())
            {
                report.pass = false;
                report.note = cpu_note.value_or(gpu_note.value());
            }
        }
        return report;
    }

    CaseReport evaluate_perf_case(
        const std::string &op,
        const FilterDesignCase &test_case,
        const Runner &runner,
        const CliOptions &options)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;
        OutputBundle gpu_output;
        if (!options.gpu_only_perf)
        {
            gpu_output = materialize(runner.gpu(test_case));
            report.samples = value_size(gpu_output);
        }
        else
        {
            report.samples = test_case.numtaps > 0 ? static_cast<std::size_t>(test_case.numtaps) : 0;
        }
        if (!options.gpu_only_perf)
        {
            const OutputBundle cpu_output = runner.cpu(test_case);
            report.cpu_gpu_error = output_error(cpu_output, gpu_output, test_case.atol);
        }
        report.pass = true;
        if (!options.gpu_only_perf)
        {
            report.cpu_perf = benchmark_host_latency(options, [&]()
                                                     { (void)runner.cpu(test_case); });
        }
        report.gpu_e2e_perf = benchmark_host_latency(options, [&]()
                                                     {
                                                         (void)runner.gpu(test_case);
                                                         cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
                                                     });
        report.gpu_kernel_perf = benchmark_gpu_kernel_latency(options, [&]()
                                                              { (void)runner.gpu(test_case); });

        if (options.emit_report)
        {
            if (!options.gpu_only_perf)
            {
                const fs::path gen_root = generated_root(op);
                const OutputBundle cpu_output = runner.cpu(test_case);
                write_output_samples(
                    gen_root / "output_samples",
                    test_case.id,
                    "cpu",
                    cpu_output,
                    &report.artifacts);
                write_output_samples(
                    gen_root / "output_samples",
                    test_case.id,
                    "gpu",
                    gpu_output,
                    &report.artifacts);
            }
        }
        return report;
    }

    int run_filter_design_operator_tests(const std::string &op, int argc, char **argv)
    {
        const CliOptions options = parse_cli(argc, argv);
        const Runner runner = resolve_runner(op);
        std::vector<CaseReport> reports;
        if (include_accuracy_cases(options))
        {
            const std::vector<FilterDesignCase> accuracy_cases =
                load_cases(reference_root(op) / "manifest.json", "accuracy");
            for (const FilterDesignCase &test_case : accuracy_cases)
            {
                reports.push_back(evaluate_accuracy_case(op, test_case, runner));
            }
        }
        if (include_perf_cases(options))
        {
            const std::vector<FilterDesignCase> perf_cases =
                load_cases(generated_root(op) / "manifest.json", "perf");
            for (const FilterDesignCase &test_case : perf_cases)
            {
                reports.push_back(evaluate_perf_case(op, test_case, runner, options));
            }
        }

        write_operator_reports(op, options, reports);
        update_module_reports();
        const OperatorSummary summary = summarize_cases(op, reports);
        print_terminal_summary(op, summary);
        return summary.pass ? 0 : 1;
    }
} // namespace

int run_kaiser_beta_tests(int argc, char **argv)
{
    try
    {
        return run_filter_design_operator_tests("kaiser_beta", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filter_design] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_kaiser_atten_tests(int argc, char **argv)
{
    try
    {
        return run_filter_design_operator_tests("kaiser_atten", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filter_design] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_cmplx_sort_tests(int argc, char **argv)
{
    try
    {
        return run_filter_design_operator_tests("cmplx_sort", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filter_design] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_firwin_tests(int argc, char **argv)
{
    try
    {
        return run_filter_design_operator_tests("firwin", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filter_design] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_firwin2_tests(int argc, char **argv)
{
    try
    {
        return run_filter_design_operator_tests("firwin2", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filter_design] ERROR: " << error.what() << '\n';
        return 1;
    }
}
