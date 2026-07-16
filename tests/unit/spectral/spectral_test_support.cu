#include "spectral_test_support.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
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
#include <utility>
#include <variant>
#include <vector>

#include "../../../include/cusignal/core/helpers.hpp"
#include "../../../include/cusignal/spectral/spectral.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace spectral_test_hooks
        {
            float consume_last_kernel_ms();
            int consume_last_periodogram_cache_state();
            void set_periodogram_cache_override(int mode);
            void reset_periodogram_cache();
            int consume_last_welch_cache_state();
            void set_welch_cache_override(int mode);
            void reset_welch_cache();
            int consume_last_istft_cache_state();
            void set_istft_cache_override(int mode);
            void reset_istft_cache();
        }
    } // namespace zx_gpu_backend
} // namespace cusignal

namespace
{
    namespace spectral_api = cusignal::spectral_api;
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexArrayLike;
    using cusignal::core::ComplexSignal;
    using cusignal::core::Float16;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    using cusignal::core::DetrendSpec;
    using cusignal::core::NamedFloatPairParameter;
    using cusignal::core::NamedFloatParameter;
    using cusignal::core::NamedTaylorParameter;
    using cusignal::core::RealArray;
    using cusignal::core::RealArrayLike;
    using cusignal::core::RealSignal;
    using cusignal::core::RealSignalLike;
    using cusignal::core::Shape;
    using cusignal::core::WindowSpec;
    using JsonArray = cusignal_test::json::Array;
    using JsonObject = cusignal_test::json::Object;
    using JsonValue = cusignal_test::json::Value;

    constexpr int kPeriodogramCacheAuto = -1;
    constexpr int kPeriodogramCacheBypass = 0;
    constexpr int kPeriodogramCacheEnabled = 1;
    constexpr int kPeriodogramCacheStateBypass = 0;
    constexpr int kPeriodogramCacheStateMiss = 1;
    constexpr int kPeriodogramCacheStateHit = 2;
    constexpr int kWelchCacheAuto = -1;
    constexpr int kWelchCacheBypass = 0;
    constexpr int kWelchCacheEnabled = 1;
    constexpr int kWelchCacheStateBypass = 0;
    constexpr int kWelchCacheStateMiss = 1;
    constexpr int kWelchCacheStateHit = 2;
    constexpr int kIstftCacheAuto = -1;
    constexpr int kIstftCacheBypass = 0;
    constexpr int kIstftCacheEnabled = 1;
    constexpr int kIstftCacheStateBypass = 0;
    constexpr int kIstftCacheStateMiss = 1;
    constexpr int kIstftCacheStateHit = 2;

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
        RealSignal,
        RealArray,
        ComplexArray,
    };

    struct OutputField
    {
        std::string name;
        FieldKind kind = FieldKind::RealSignal;
        Shape shape;
        RealSignal real_values;
        ComplexSignal complex_values;
    };

    struct DeviceOutputField
    {
        std::string name;
        FieldKind kind = FieldKind::RealSignal;
        Shape shape;
        ZxGpuRealSignal real_signal;
        ZxGpuRealArray real_array;
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

    struct SpectralCase
    {
        std::string id;
        std::string category;

        Shape x_shape;
        Shape y_shape;
        Shape zxx_shape;

        float fs = 1.0; // 频率轴缩放使用的采样频率
        int nfft = 0; // FFT 长度（0 表示算子默认值）
        int nperseg = 0; // STFT 系列算子的分段/窗长度
        int noverlap = -1; // 相邻分段重叠长度（-1 表示默认）
        int axis = -1; // 频谱变换所沿用的输入轴
        int time_axis = -1; // 复数谱图输入中的 ISTFT 时间轴
        int freq_axis = -2; // 复数谱图输入中的 ISTFT 频率轴

        bool precenter = false; // Lomb-Scargle 投影前先去均值
        bool normalize = false; // 启用归一化的 Lomb-Scargle 功率
        bool return_onesided = true; // 实数输入时返回单边频谱
        bool padded = true; // 对最后分段补零以覆盖完整窗口
        bool input_onesided = true; // ISTFT 输入谱图为单边
        bool boundary_enabled = true; // 当 boundary != none 时应用边界扩展

        float period_scalar = 0.0; // period_file 缺失时 vectorstrength 使用的标量周期
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限

        std::string dtype = "float32"; // 兼容性用例的数据类型标签
        std::string scaling = "density"; // PSD 缩放模式：density 或 spectrum
        std::string average = "mean"; // Welch 平均模式：mean 或 median
        std::string mode = "psd"; // spectrogram 输出模式：psd/complex/magnitude/phase/angle
        std::string boundary = "zeros"; // STFT 边界模式（zeros/even/odd/constant/none）

        WindowSpec window = std::string("boxcar");
        DetrendSpec detrend = std::string("constant");

        fs::path x_file;
        fs::path y_file;
        fs::path zxx_file;
        fs::path freqs_file;
        fs::path events_file;
        fs::path period_file;

        fs::path expected_signal_file;
        fs::path expected_values_file;
        fs::path expected_frequencies_file;
        fs::path expected_times_file;
        fs::path expected_strength_file;
        fs::path expected_phase_file;

        std::optional<RealArray> generated_x;
        std::optional<RealArray> generated_y;
        std::optional<ComplexArray> generated_zxx;
        std::optional<RealSignal> generated_freqs;
        std::optional<RealSignal> generated_events;
        std::optional<RealSignal> generated_periods;
    };

    using CpuRunner = std::function<OutputBundle(const SpectralCase &)>;
    using GpuRunner = std::function<DeviceOutputBundle(const SpectralCase &)>;

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
        return repo_root() / "data" / "reference" / "unit" / "spectral" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return repo_root() / "data" / "generated" / "unit" / "spectral" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / "reports" / "unit" / "spectral" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / "reports" / "unit" / "spectral";
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
            return WindowSpec{get_optional_number(object, "value", 0.0)};
        }
        if (kind == "named_float")
        {
            return WindowSpec{
                NamedFloatParameter{
                    get_string(object, "name"),
                    get_optional_number(object, "value", 0.0)}};
        }
        if (kind == "named_pair")
        {
            return WindowSpec{
                NamedFloatPairParameter{
                    get_string(object, "name"),
                    get_optional_number(object, "first", 0.0),
                    get_optional_number(object, "second", 0.0)}};
        }
        if (kind == "taylor")
        {
            return WindowSpec{
                NamedTaylorParameter{
                    get_string(object, "name"),
                    get_optional_int(object, "nbar", 4),
                    get_optional_number(object, "sll", 30.0),
                    get_optional_bool(object, "norm", true)}};
        }
        if (kind == "array")
        {
            RealSignal values;
            for (const JsonValue &item : as_array(object.at("values")))
            {
                values.push_back(item.as_number());
            }
            return WindowSpec{values};
        }
        throw std::runtime_error("unsupported window spec kind");
    }

    ZxGpuWindowSpec to_zx_gpu_window_spec(const WindowSpec &spec)
    {
        return std::visit(
            [](const auto &value) -> ZxGpuWindowSpec {
                return ZxGpuWindowSpec{value};
            },
            spec);
    }

    std::string build_window_spec_json(const WindowSpec &spec)
    {
        return std::visit(
            [](const auto &value) {
                using T = std::decay_t<decltype(value)>;
                std::ostringstream stream;
                if constexpr (std::is_same_v<T, std::string>)
                {
                    stream << "{\"kind\":\"string\",\"value\":\""
                           << cusignal_test::report::json_escape(value) << "\"}";
                }
                else if constexpr (std::is_same_v<T, float>)
                {
                    stream << "{\"kind\":\"float\",\"value\":" << value << "}";
                }
                else if constexpr (std::is_same_v<T, NamedFloatParameter>)
                {
                    stream << "{\"kind\":\"named_float\",\"name\":\""
                           << cusignal_test::report::json_escape(value.name)
                           << "\",\"value\":" << value.value << "}";
                }
                else if constexpr (std::is_same_v<T, NamedFloatPairParameter>)
                {
                    stream << "{\"kind\":\"named_pair\",\"name\":\""
                           << cusignal_test::report::json_escape(value.name)
                           << "\",\"first\":" << value.first
                           << ",\"second\":" << value.second << "}";
                }
                else if constexpr (std::is_same_v<T, NamedTaylorParameter>)
                {
                    stream << "{\"kind\":\"taylor\",\"name\":\""
                           << cusignal_test::report::json_escape(value.name)
                           << "\",\"nbar\":" << value.nbar
                           << ",\"sll\":" << value.sll
                           << ",\"norm\":" << (value.norm ? "true" : "false") << "}";
                }
                else
                {
                    stream << "{\"kind\":\"array\",\"values\":[";
                    for (std::size_t index = 0; index < value.size(); ++index)
                    {
                        if (index != 0)
                        {
                            stream << ',';
                        }
                        stream << value[index];
                    }
                    stream << "]}";
                }
                return stream.str();
            },
            spec);
    }

    DetrendSpec parse_detrend_spec(const JsonValue &value)
    {
        if (value.is_bool())
        {
            return DetrendSpec{value.as_bool()};
        }
        if (value.is_string())
        {
            return DetrendSpec{value.as_string()};
        }
        throw std::runtime_error("unsupported detrend spec");
    }

    std::string build_detrend_json(const DetrendSpec &spec)
    {
        return std::visit(
            [](const auto &value) {
                using T = std::decay_t<decltype(value)>;
                if constexpr (std::is_same_v<T, bool>)
                {
                    return std::string(value ? "true" : "false");
                }
                else
                {
                    return std::string("\"") + cusignal_test::report::json_escape(value) + "\"";
                }
            },
            spec);
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
            values.emplace_back(
                std::stod(line.substr(0, comma)),
                std::stod(line.substr(comma + 1)));
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

    RealArray make_real_array_from_flat(const Shape &shape, const RealSignal &values)
    {
        RealArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    ComplexArray make_complex_array_from_flat(const Shape &shape, const ComplexSignal &values)
    {
        ComplexArray array;
        array.shape = shape;
        array.values = values;
        return array;
    }

    RealArray load_real_array(const fs::path &path, const Shape &shape)
    {
        return make_real_array_from_flat(shape, read_real_csv(path));
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
            throw std::runtime_error("unsupported spectral dtype compatibility case: " + dtype);
        }
        RealSignal quantized = signal;
        for (float &value : quantized)
        {
            value = quantize_float16(value);
        }
        return quantized;
    }

    RealArray apply_dtype_quantization(const RealArray &array, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return array;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported spectral dtype compatibility case: " + dtype);
        }
        RealArray quantized = array;
        quantized.values = apply_dtype_quantization(quantized.values, dtype);
        return quantized;
    }

    ComplexArray load_complex_array(const fs::path &path, const Shape &shape)
    {
        return make_complex_array_from_flat(shape, read_complex_csv(path));
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

    RealSignal generate_real_signal_pattern(
        std::size_t length,
        float freq1,
        float freq2,
        float phase,
        float amplitude,
        float bias)
    {
        RealSignal values(length, 0.0);
        for (std::size_t index = 0; index < length; ++index)
        {
            const float x = static_cast<float>(index);
            values[index] =
                bias +
                amplitude * (std::sin(freq1 * x + phase) + 0.35 * std::cos(freq2 * x - 0.17));
        }
        return values;
    }

    RealSignal generate_irregular_times(
        std::size_t count,
        float start,
        float stop,
        float jitter)
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
        for (std::size_t index = 0; index < count; ++index)
        {
            const float alpha = static_cast<float>(index) / static_cast<float>(count - 1);
            values[index] = start + alpha * (stop - start) + jitter * std::sin(0.37 * static_cast<float>(index));
        }
        return values;
    }

    RealSignal generate_real_linspace(
        float start,
        float stop,
        std::size_t count)
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

    RealArray generate_real_array_pattern(
        const Shape &shape,
        float freq_row,
        float freq_col,
        float phase,
        float amplitude,
        float bias)
    {
        RealArray array = cusignal::core::make_real_array(shape);
        if (shape.size() == 1)
        {
            array.values = generate_real_signal_pattern(shape[0], freq_row, freq_col, phase, amplitude, bias);
            return array;
        }
        if (shape.size() != 2)
        {
            throw std::runtime_error("real_array_pattern expects rank-1 or rank-2 shape");
        }
        const std::size_t rows = shape[0];
        const std::size_t cols = shape[1];
        for (std::size_t row = 0; row < rows; ++row)
        {
            for (std::size_t col = 0; col < cols; ++col)
            {
                const float angle =
                    phase +
                    freq_row * static_cast<float>(row) +
                    freq_col * static_cast<float>(col);
                array.values[row * cols + col] =
                    bias +
                    amplitude * (std::sin(angle) + 0.2 * std::cos(0.13 * static_cast<float>((row + 1) * (col + 2))));
            }
        }
        return array;
    }

    ComplexArray generate_complex_matrix_pattern(
        const Shape &shape,
        float freq_row,
        float freq_col,
        float phase,
        float amplitude)
    {
        if (shape.size() != 2)
        {
            throw std::runtime_error("complex_matrix_pattern expects rank-2 shape");
        }
        ComplexArray output = cusignal::core::make_complex_array(shape);
        const std::size_t rows = shape[0];
        const std::size_t cols = shape[1];
        for (std::size_t row = 0; row < rows; ++row)
        {
            for (std::size_t col = 0; col < cols; ++col)
            {
                const float base = phase +
                                    freq_row * static_cast<float>(row) +
                                    freq_col * static_cast<float>(col);
                const float cross = 0.091 * static_cast<float>((row + 1) * (col + 2));
                const float real = std::cos(base) + 0.19 * std::sin(cross);
                const float imag = std::sin(base) - 0.17 * std::cos(cross);
                output.values[row * cols + col] = amplitude * Complex(real, imag);
            }
        }
        return output;
    }

    std::optional<RealSignal> parse_real_signal_generator(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return std::nullopt;
        }
        const JsonObject &spec = as_object(iter->second);
        const std::string kind = get_string(spec, "kind");
        if (kind == "real_signal_pattern")
        {
            return generate_real_signal_pattern(
                static_cast<std::size_t>(get_optional_int(spec, "length", 0)),
                get_optional_number(spec, "freq1", 0.11),
                get_optional_number(spec, "freq2", 0.031),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0),
                get_optional_number(spec, "bias", 0.0));
        }
        if (kind == "irregular_times")
        {
            return generate_irregular_times(
                static_cast<std::size_t>(get_optional_int(spec, "count", 0)),
                get_optional_number(spec, "start", 0.0),
                get_optional_number(spec, "stop", 1.0),
                get_optional_number(spec, "jitter", 0.0));
        }
        if (kind == "real_linspace")
        {
            return generate_real_linspace(
                get_optional_number(spec, "start", 0.0),
                get_optional_number(spec, "stop", 1.0),
                static_cast<std::size_t>(get_optional_int(spec, "count", 0)));
        }
        throw std::runtime_error("unsupported real signal generator kind");
    }

    std::optional<RealArray> parse_real_array_generator(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return std::nullopt;
        }
        const JsonObject &spec = as_object(iter->second);
        const std::string kind = get_string(spec, "kind");
        if (kind == "real_array_pattern")
        {
            return generate_real_array_pattern(
                json_array_to_shape(spec.at("shape")),
                get_optional_number(spec, "freq_row", 0.11),
                get_optional_number(spec, "freq_col", 0.031),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0),
                get_optional_number(spec, "bias", 0.0));
        }
        if (kind == "real_signal_pattern")
        {
            RealSignal signal = generate_real_signal_pattern(
                static_cast<std::size_t>(get_optional_int(spec, "length", 0)),
                get_optional_number(spec, "freq1", 0.11),
                get_optional_number(spec, "freq2", 0.031),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0),
                get_optional_number(spec, "bias", 0.0));
            return make_real_array_from_flat(Shape{signal.size()}, signal);
        }
        if (kind == "irregular_times")
        {
            RealSignal signal = generate_irregular_times(
                static_cast<std::size_t>(get_optional_int(spec, "count", 0)),
                get_optional_number(spec, "start", 0.0),
                get_optional_number(spec, "stop", 1.0),
                get_optional_number(spec, "jitter", 0.0));
            return make_real_array_from_flat(Shape{signal.size()}, signal);
        }
        if (kind == "real_linspace")
        {
            RealSignal signal = generate_real_linspace(
                get_optional_number(spec, "start", 0.0),
                get_optional_number(spec, "stop", 1.0),
                static_cast<std::size_t>(get_optional_int(spec, "count", 0)));
            return make_real_array_from_flat(Shape{signal.size()}, signal);
        }
        throw std::runtime_error("unsupported real array generator kind");
    }

    std::optional<ComplexArray> parse_complex_array_generator(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return std::nullopt;
        }
        const JsonObject &spec = as_object(iter->second);
        const std::string kind = get_string(spec, "kind");
        if (kind == "complex_matrix_pattern")
        {
            return generate_complex_matrix_pattern(
                json_array_to_shape(spec.at("shape")),
                get_optional_number(spec, "freq_row", 0.21),
                get_optional_number(spec, "freq_col", 0.07),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0));
        }
        throw std::runtime_error("unsupported complex array generator kind");
    }

    OutputBundle make_bundle(const RealSignal &values, const std::string &name = "signal")
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{name, FieldKind::RealSignal, Shape{values.size()}, values, {}});
        return bundle;
    }

    OutputBundle make_bundle(const spectral_api::RealSpectrumResult &result)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{result.frequencies.size()}, result.frequencies, {}});
        bundle.fields.push_back(OutputField{"values", FieldKind::RealArray, result.values.shape, result.values.values, {}});
        return bundle;
    }

    OutputBundle make_bundle(const spectral_api::ComplexSpectrumResult &result)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{result.frequencies.size()}, result.frequencies, {}});
        bundle.fields.push_back(OutputField{"values", FieldKind::ComplexArray, result.values.shape, {}, result.values.values});
        return bundle;
    }

    OutputBundle make_bundle(const spectral_api::SpectrogramResult &result)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{result.frequencies.size()}, result.frequencies, {}});
        bundle.fields.push_back(OutputField{"times", FieldKind::RealSignal, Shape{result.times.size()}, result.times, {}});
        std::visit(
            [&](const auto &value) {
                using T = std::decay_t<decltype(value)>;
                if constexpr (std::is_same_v<T, RealArray>)
                {
                    bundle.fields.push_back(OutputField{"values", FieldKind::RealArray, value.shape, value.values, {}});
                }
                else
                {
                    bundle.fields.push_back(OutputField{"values", FieldKind::ComplexArray, value.shape, {}, value.values});
                }
            },
            result.values);
        return bundle;
    }

    OutputBundle make_bundle(const spectral_api::StftResult &result)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{result.frequencies.size()}, result.frequencies, {}});
        bundle.fields.push_back(OutputField{"times", FieldKind::RealSignal, Shape{result.times.size()}, result.times, {}});
        bundle.fields.push_back(OutputField{"values", FieldKind::ComplexArray, result.values.shape, {}, result.values.values});
        return bundle;
    }

    OutputBundle make_bundle(const spectral_api::IstftResult &result)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"times", FieldKind::RealSignal, Shape{result.times.size()}, result.times, {}});
        bundle.fields.push_back(OutputField{"signal", FieldKind::RealArray, result.signal.shape, result.signal.values, {}});
        return bundle;
    }

    OutputBundle make_bundle(const spectral_api::VectorStrengthResult &result)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"strength", FieldKind::RealSignal, Shape{result.strength.size()}, result.strength, {}});
        bundle.fields.push_back(OutputField{"phase", FieldKind::RealSignal, Shape{result.phase.size()}, result.phase, {}});
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const ZxGpuRealSignal &values, const std::string &name = "signal")
    {
        DeviceOutputBundle bundle;
        DeviceOutputField field;
        field.name = name;
        field.kind = FieldKind::RealSignal;
        field.shape = Shape{values.size()};
        field.real_signal = values;
        bundle.fields.push_back(std::move(field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const spectral_api::ZxGpuRealSpectrumResult &result)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField freq_field;
        freq_field.name = "frequencies";
        freq_field.kind = FieldKind::RealSignal;
        freq_field.shape = Shape{result.frequencies.size()};
        freq_field.real_signal = result.frequencies;
        bundle.fields.push_back(std::move(freq_field));
        DeviceOutputField values_field;
        values_field.name = "values";
        values_field.kind = FieldKind::RealArray;
        values_field.shape = result.values.shape();
        values_field.real_array = result.values;
        bundle.fields.push_back(std::move(values_field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const spectral_api::ZxGpuComplexSpectrumResult &result)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField freq_field;
        freq_field.name = "frequencies";
        freq_field.kind = FieldKind::RealSignal;
        freq_field.shape = Shape{result.frequencies.size()};
        freq_field.real_signal = result.frequencies;
        bundle.fields.push_back(std::move(freq_field));
        DeviceOutputField values_field;
        values_field.name = "values";
        values_field.kind = FieldKind::ComplexArray;
        values_field.shape = result.values.shape();
        values_field.complex_array = result.values;
        bundle.fields.push_back(std::move(values_field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const spectral_api::ZxGpuSpectrogramResult &result)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField freq_field;
        freq_field.name = "frequencies";
        freq_field.kind = FieldKind::RealSignal;
        freq_field.shape = Shape{result.frequencies.size()};
        freq_field.real_signal = result.frequencies;
        bundle.fields.push_back(std::move(freq_field));
        DeviceOutputField time_field;
        time_field.name = "times";
        time_field.kind = FieldKind::RealSignal;
        time_field.shape = Shape{result.times.size()};
        time_field.real_signal = result.times;
        bundle.fields.push_back(std::move(time_field));
        std::visit(
            [&](const auto &value) {
                using T = std::decay_t<decltype(value)>;
                DeviceOutputField values_field;
                values_field.name = "values";
                if constexpr (std::is_same_v<T, ZxGpuRealArray>)
                {
                    values_field.kind = FieldKind::RealArray;
                    values_field.shape = value.shape();
                    values_field.real_array = value;
                }
                else
                {
                    values_field.kind = FieldKind::ComplexArray;
                    values_field.shape = value.shape();
                    values_field.complex_array = value;
                }
                bundle.fields.push_back(std::move(values_field));
            },
            result.values);
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const spectral_api::ZxGpuStftResult &result)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField freq_field;
        freq_field.name = "frequencies";
        freq_field.kind = FieldKind::RealSignal;
        freq_field.shape = Shape{result.frequencies.size()};
        freq_field.real_signal = result.frequencies;
        bundle.fields.push_back(std::move(freq_field));
        DeviceOutputField time_field;
        time_field.name = "times";
        time_field.kind = FieldKind::RealSignal;
        time_field.shape = Shape{result.times.size()};
        time_field.real_signal = result.times;
        bundle.fields.push_back(std::move(time_field));
        DeviceOutputField values_field;
        values_field.name = "values";
        values_field.kind = FieldKind::ComplexArray;
        values_field.shape = result.values.shape();
        values_field.complex_array = result.values;
        bundle.fields.push_back(std::move(values_field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const spectral_api::ZxGpuIstftResult &result)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField time_field;
        time_field.name = "times";
        time_field.kind = FieldKind::RealSignal;
        time_field.shape = Shape{result.times.size()};
        time_field.real_signal = result.times;
        bundle.fields.push_back(std::move(time_field));
        DeviceOutputField signal_field;
        signal_field.name = "signal";
        signal_field.kind = FieldKind::RealArray;
        signal_field.shape = result.signal.shape();
        signal_field.real_array = result.signal;
        bundle.fields.push_back(std::move(signal_field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const spectral_api::ZxGpuVectorStrengthResult &result)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField strength_field;
        strength_field.name = "strength";
        strength_field.kind = FieldKind::RealSignal;
        strength_field.shape = Shape{result.strength.size()};
        strength_field.real_signal = result.strength;
        bundle.fields.push_back(std::move(strength_field));
        DeviceOutputField phase_field;
        phase_field.name = "phase";
        phase_field.kind = FieldKind::RealSignal;
        phase_field.shape = Shape{result.phase.size()};
        phase_field.real_signal = result.phase;
        bundle.fields.push_back(std::move(phase_field));
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
            if (field.kind == FieldKind::ComplexArray)
            {
                host_field.complex_values = field.complex_array.get().values;
            }
            else if (field.kind == FieldKind::RealArray)
            {
                host_field.real_values = field.real_array.get().values;
            }
            else
            {
                host_field.real_values = field.real_signal.get();
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
            throw std::runtime_error("unsupported spectral dtype compatibility case: " + dtype);
        }
        OutputBundle quantized = bundle;
        for (OutputField &field : quantized.fields)
        {
            if (field.kind != FieldKind::ComplexArray)
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
            result.mixed_error = std::max(result.mixed_error, metrics.mixed_error);
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

    float mixed_error_for_sample(float abs_error, float expected_norm, float atol, float reference_scale)
    {
        const float effective_atol = std::max(std::max(atol, 1.0e-5f), 1.0e-1f * reference_scale);
        return expected_norm <= effective_atol ? abs_error : abs_error / expected_norm;
    }

    ErrorMetrics compute_real_error(
        const Shape &lhs_shape,
        const RealSignal &lhs,
        const Shape &rhs_shape,
        const RealSignal &rhs,
        float mixed_atol = 1.0e-5f)
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
        float reference_scale = 0.0f;
        for (float value : lhs)
        {
            reference_scale = std::max(reference_scale, std::abs(value));
        }
        float l2_sum = 0.0;
        float rmse_sum = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float diff = lhs[index] - rhs[index];
            const float abs_error = std::abs(diff);
            const float expected_norm = std::abs(lhs[index]);
            const float rel_error = abs_error / std::max(std::abs(rhs[index]), 1e-30f);
            const float mixed_error = mixed_error_for_sample(abs_error, expected_norm, mixed_atol, reference_scale);
            metrics.max_abs_error = std::max(metrics.max_abs_error, abs_error);
            metrics.max_rel_error = std::max(metrics.max_rel_error, rel_error);
            metrics.mixed_error = std::max(metrics.mixed_error, mixed_error);
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
        const ComplexSignal &rhs,
        float mixed_atol = 1.0e-5f)
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
        float reference_scale = 0.0f;
        for (const Complex &value : lhs)
        {
            reference_scale = std::max(reference_scale, std::abs(value));
        }
        float l2_sum = 0.0;
        float rmse_sum = 0.0;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const Complex diff = lhs[index] - rhs[index];
            const float abs_error = std::abs(diff);
            const float expected_norm = std::abs(lhs[index]);
            const float rel_error = abs_error / std::max(std::abs(rhs[index]), 1e-30f);
            const float mixed_error = mixed_error_for_sample(abs_error, expected_norm, mixed_atol, reference_scale);
            metrics.max_abs_error = std::max(metrics.max_abs_error, abs_error);
            metrics.max_rel_error = std::max(metrics.max_rel_error, rel_error);
            metrics.mixed_error = std::max(metrics.mixed_error, mixed_error);
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

    ErrorMetrics compute_bundle_error(const OutputBundle &lhs, const OutputBundle &rhs, float mixed_atol = 1.0e-5f)
    {
        if (lhs.fields.size() != rhs.fields.size())
        {
            throw std::runtime_error("field count mismatch while comparing spectral outputs");
        }
        std::vector<ErrorMetrics> all_metrics;
        for (std::size_t index = 0; index < lhs.fields.size(); ++index)
        {
            const OutputField &lhs_field = lhs.fields[index];
            const OutputField &rhs_field = rhs.fields[index];
            if (lhs_field.name != rhs_field.name || lhs_field.kind != rhs_field.kind)
            {
                throw std::runtime_error("field mismatch while comparing spectral outputs");
            }
            if (lhs_field.kind == FieldKind::ComplexArray)
            {
                all_metrics.push_back(compute_complex_error(
                    lhs_field.shape,
                    lhs_field.complex_values,
                    rhs_field.shape,
                    rhs_field.complex_values,
                    mixed_atol));
            }
            else
            {
                all_metrics.push_back(compute_real_error(
                    lhs_field.shape,
                    lhs_field.real_values,
                    rhs_field.shape,
                    rhs_field.real_values,
                    mixed_atol));
            }
        }
        return combine_metrics(all_metrics);
    }

    bool field_within_tolerance(const OutputField &actual, const OutputField &expected, float atol, float rtol)
    {
        if (actual.kind != expected.kind || actual.shape != expected.shape)
        {
            return false;
        }
        const float effective_atol = std::max(atol, 2.0e-5f);
        const float effective_rtol = std::max(rtol, 2.0e-5f);
        if (actual.kind == FieldKind::ComplexArray)
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

    bool bundle_within_tolerance(const OutputBundle &actual, const OutputBundle &expected, float atol, float rtol)
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
            (void)cusignal::zx_gpu_backend::spectral_test_hooks::consume_last_kernel_ms();
        }
        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            callable();
            durations.push_back(cusignal::zx_gpu_backend::spectral_test_hooks::consume_last_kernel_ms());
        }
        return compute_timing_stats(durations);
    }

    enum class PeriodogramProbeWindowKind
    {
        Hann,
        Boxcar,
        Kaiser,
        HostExplicit,
        DeviceExplicit,
    };

    struct PeriodogramCacheProbeCase
    {
        std::string id;
        Shape shape;
        float fs = 1024.0f;
        int nfft = 0;
        bool return_onesided = true;
        std::string scaling = "density";
        int axis = -1;
        PeriodogramProbeWindowKind window_kind =
            PeriodogramProbeWindowKind::Hann;
        bool cacheable = true;
    };

    class PeriodogramCacheOverrideReset
    {
    public:
        ~PeriodogramCacheOverrideReset()
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_periodogram_cache_override(kPeriodogramCacheAuto);
            cusignal::zx_gpu_backend::spectral_test_hooks::
                reset_periodogram_cache();
            (void)cusignal::zx_gpu_backend::spectral_test_hooks::
                consume_last_periodogram_cache_state();
        }
    };

    RealArray make_periodogram_cache_probe_input(const Shape &shape)
    {
        RealArray input;
        input.shape = shape;
        input.values.resize(cusignal::core::shape_product(shape));
        for (std::size_t index = 0; index < input.values.size(); ++index)
        {
            if (index % 127 == 0)
            {
                input.values[index] = -0.0f;
                continue;
            }
            const float x = static_cast<float>(index);
            input.values[index] =
                0.75f * std::sin(0.013f * x + 0.05f) +
                0.25f * std::cos(0.031f * x - 0.15f) +
                static_cast<float>(static_cast<int>(index % 19) - 9) * 0.0078125f;
        }
        return input;
    }

    RealSignal make_periodogram_cache_explicit_window(int size)
    {
        RealSignal window(static_cast<std::size_t>(size));
        for (int index = 0; index < size; ++index)
        {
            window[static_cast<std::size_t>(index)] =
                0.25f + 0.75f * static_cast<float>((index % 19) + 1) / 20.0f;
        }
        return window;
    }

    ZxGpuWindowSpec make_periodogram_cache_probe_window(
        PeriodogramProbeWindowKind kind,
        int size)
    {
        if (kind == PeriodogramProbeWindowKind::Hann)
        {
            return ZxGpuWindowSpec{std::string("hann")};
        }
        if (kind == PeriodogramProbeWindowKind::Boxcar)
        {
            return ZxGpuWindowSpec{std::string("boxcar")};
        }
        if (kind == PeriodogramProbeWindowKind::Kaiser)
        {
            return ZxGpuWindowSpec{NamedFloatParameter{"kaiser", 5.0f}};
        }
        RealSignal window = make_periodogram_cache_explicit_window(size);
        if (kind == PeriodogramProbeWindowKind::DeviceExplicit)
        {
            return ZxGpuWindowSpec{ZxGpuRealSignal::from_host(window)};
        }
        return ZxGpuWindowSpec{std::move(window)};
    }

    std::uint32_t float_bits(float value)
    {
        std::uint32_t bits = 0;
        static_assert(sizeof(bits) == sizeof(value), "float32 bit width");
        std::memcpy(&bits, &value, sizeof(bits));
        return bits;
    }

    bool bitwise_equal_output_bundles(
        const OutputBundle &lhs,
        const OutputBundle &rhs,
        std::string *mismatch)
    {
        if (lhs.fields.size() != rhs.fields.size())
        {
            *mismatch = "field_count";
            return false;
        }
        for (std::size_t field_index = 0; field_index < lhs.fields.size(); ++field_index)
        {
            const OutputField &lhs_field = lhs.fields[field_index];
            const OutputField &rhs_field = rhs.fields[field_index];
            if (lhs_field.name != rhs_field.name ||
                lhs_field.kind != rhs_field.kind ||
                lhs_field.shape != rhs_field.shape)
            {
                *mismatch = "field_metadata:" + std::to_string(field_index);
                return false;
            }
            if (lhs_field.kind == FieldKind::ComplexArray)
            {
                if (lhs_field.complex_values.size() != rhs_field.complex_values.size())
                {
                    *mismatch = lhs_field.name + ":size";
                    return false;
                }
                for (std::size_t index = 0; index < lhs_field.complex_values.size(); ++index)
                {
                    const Complex lhs_value = lhs_field.complex_values[index];
                    const Complex rhs_value = rhs_field.complex_values[index];
                    if (float_bits(lhs_value.real()) != float_bits(rhs_value.real()) ||
                        float_bits(lhs_value.imag()) != float_bits(rhs_value.imag()))
                    {
                        *mismatch = lhs_field.name + ":" + std::to_string(index);
                        return false;
                    }
                }
                continue;
            }
            if (lhs_field.real_values.size() != rhs_field.real_values.size())
            {
                *mismatch = lhs_field.name + ":size";
                return false;
            }
            for (std::size_t index = 0; index < lhs_field.real_values.size(); ++index)
            {
                if (float_bits(lhs_field.real_values[index]) !=
                    float_bits(rhs_field.real_values[index]))
                {
                    *mismatch = lhs_field.name + ":" + std::to_string(index);
                    return false;
                }
            }
        }
        return true;
    }

    std::size_t output_float_count(const OutputBundle &bundle)
    {
        std::size_t count = 0;
        for (const OutputField &field : bundle.fields)
        {
            count += field.kind == FieldKind::ComplexArray
                         ? field.complex_values.size() * 2
                         : field.real_values.size();
        }
        return count;
    }

    OutputBundle run_periodogram_cache_probe_path(
        const ZxGpuRealArray &x,
        const PeriodogramCacheProbeCase &test_case,
        int cache_mode,
        int *observed_state)
    {
        cusignal::zx_gpu_backend::spectral_test_hooks::
            set_periodogram_cache_override(cache_mode);
        const std::size_t line_len = test_case.shape.back();
        const int effective_len =
            test_case.nfft > 0 &&
                    static_cast<std::size_t>(test_case.nfft) < line_len
                ? test_case.nfft
                : static_cast<int>(line_len);
        ZxGpuWindowSpec window = make_periodogram_cache_probe_window(
            test_case.window_kind,
            effective_len);
        OutputBundle output = materialize(make_device_bundle(
            cusignal::zx_gpu_backend::spectral::periodogram(
                x,
                test_case.fs,
                std::move(window),
                test_case.nfft,
                DetrendSpec{std::string("constant")},
                test_case.return_onesided,
                test_case.scaling,
                test_case.axis)));
        *observed_state =
            cusignal::zx_gpu_backend::spectral_test_hooks::
                consume_last_periodogram_cache_state();
        return output;
    }

    int run_periodogram_cache_device_ab_probe()
    {
        PeriodogramCacheOverrideReset reset;
        std::ofstream report;
        const char *report_path =
            std::getenv("CUSIGNAL_PERIODOGRAM_CACHE_DEVICE_AB_REPORT");
        if (report_path != nullptr && report_path[0] != '\0')
        {
            report.open(report_path);
            if (!report)
            {
                throw std::runtime_error(
                    "failed to open periodogram cache device A/B report");
            }
        }

        bool invalid_override_rejected = false;
        try
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_periodogram_cache_override(7);
        }
        catch (const std::invalid_argument &)
        {
            invalid_override_rejected = true;
        }
        if (!invalid_override_rejected)
        {
            throw std::runtime_error(
                "invalid periodogram cache override was accepted");
        }

        const std::vector<PeriodogramCacheProbeCase> cases = {
            {"official_accuracy", {256}, 1024.0f, 0, true, "density", -1,
             PeriodogramProbeWindowKind::Hann, true},
            {"official_perf", {32768}, 1024.0f, 0, true, "density", -1,
             PeriodogramProbeWindowKind::Hann, true},
            {"truncated_spectrum", {1024}, 800.0f, 512, true, "spectrum", -1,
             PeriodogramProbeWindowKind::Hann, true},
            {"padded_boxcar", {1024}, 1200.0f, 2048, true, "density", -1,
             PeriodogramProbeWindowKind::Boxcar, true},
            {"kaiser", {2048}, 1600.0f, 0, true, "density", -1,
             PeriodogramProbeWindowKind::Kaiser, true},
            {"two_sided", {1024}, 900.0f, 1024, false, "density", -1,
             PeriodogramProbeWindowKind::Hann, true},
            {"multiline", {2, 512}, 700.0f, 0, true, "density", 1,
             PeriodogramProbeWindowKind::Hann, true},
            {"host_explicit", {512}, 600.0f, 0, true, "density", -1,
             PeriodogramProbeWindowKind::HostExplicit, false},
            {"device_explicit", {512}, 500.0f, 0, true, "density", -1,
             PeriodogramProbeWindowKind::DeviceExplicit, false},
        };

        std::size_t checked_cases = 0;
        std::size_t checked_float_outputs = 0;
        std::size_t cache_misses = 0;
        std::size_t cache_hits = 0;
        std::size_t bypasses = 0;
        for (const PeriodogramCacheProbeCase &test_case : cases)
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                reset_periodogram_cache();
            const ZxGpuRealArray x = ZxGpuRealArray::from_host(
                make_periodogram_cache_probe_input(test_case.shape));
            int bypass_state = -1;
            int miss_state = -1;
            int hit_state = -1;
            int automatic_state = -1;
            const OutputBundle bypass = run_periodogram_cache_probe_path(
                x,
                test_case,
                kPeriodogramCacheBypass,
                &bypass_state);
            const OutputBundle first_cached = run_periodogram_cache_probe_path(
                x,
                test_case,
                kPeriodogramCacheEnabled,
                &miss_state);
            const OutputBundle second_cached = run_periodogram_cache_probe_path(
                x,
                test_case,
                kPeriodogramCacheEnabled,
                &hit_state);
            const OutputBundle automatic = run_periodogram_cache_probe_path(
                x,
                test_case,
                kPeriodogramCacheAuto,
                &automatic_state);

            const int expected_first =
                test_case.cacheable
                    ? kPeriodogramCacheStateMiss
                    : kPeriodogramCacheStateBypass;
            const int expected_reuse =
                test_case.cacheable
                    ? kPeriodogramCacheStateHit
                    : kPeriodogramCacheStateBypass;
            if (bypass_state != kPeriodogramCacheStateBypass ||
                miss_state != expected_first ||
                hit_state != expected_reuse ||
                automatic_state != expected_reuse)
            {
                throw std::runtime_error(
                    "periodogram cache route mismatch for case " + test_case.id);
            }

            std::string mismatch;
            for (const auto &candidate : {
                     std::pair<const char *, const OutputBundle *>(
                         "first_cached", &first_cached),
                     std::pair<const char *, const OutputBundle *>(
                         "second_cached", &second_cached),
                     std::pair<const char *, const OutputBundle *>(
                         "automatic", &automatic)})
            {
                if (!bitwise_equal_output_bundles(
                        bypass,
                        *candidate.second,
                        &mismatch))
                {
                    throw std::runtime_error(
                        "periodogram bypass/cache mismatch for case " +
                        test_case.id + "/" + candidate.first + " at " + mismatch);
                }
            }

            const int states[] = {
                bypass_state,
                miss_state,
                hit_state,
                automatic_state};
            for (int state : states)
            {
                cache_misses += state == kPeriodogramCacheStateMiss ? 1 : 0;
                cache_hits += state == kPeriodogramCacheStateHit ? 1 : 0;
                bypasses += state == kPeriodogramCacheStateBypass ? 1 : 0;
            }
            ++checked_cases;
            checked_float_outputs += output_float_count(bypass);
        }

        if (report)
        {
            report << "summary\tpass\tchecked_cases\t" << checked_cases
                   << "\tchecked_float_outputs\t" << checked_float_outputs
                   << "\tcache_misses\t" << cache_misses
                   << "\tcache_hits\t" << cache_hits
                   << "\tbypasses\t" << bypasses
                   << "\tperformance\tnot_run\n";
        }
        std::cout << "[periodogram-cache-device-ab] PASS"
                  << " checked_cases=" << checked_cases
                  << " checked_float_outputs=" << checked_float_outputs
                  << " cache_misses=" << cache_misses
                  << " cache_hits=" << cache_hits
                  << " bypasses=" << bypasses
                  << " performance=not_run\n";
        return 0;
    }

    struct WelchCacheProbeCase
    {
        std::string id;
        Shape shape;
        float fs = 800.0f;
        int nperseg = 128;
        int noverlap = 64;
        int nfft = 128;
        bool return_onesided = true;
        std::string scaling = "density";
        int axis = -1;
        std::string average = "mean";
        PeriodogramProbeWindowKind window_kind =
            PeriodogramProbeWindowKind::Hann;
        bool cacheable = true;
    };

    class WelchCacheOverrideReset
    {
    public:
        ~WelchCacheOverrideReset()
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_welch_cache_override(kWelchCacheAuto);
            cusignal::zx_gpu_backend::spectral_test_hooks::
                reset_welch_cache();
            (void)cusignal::zx_gpu_backend::spectral_test_hooks::
                consume_last_welch_cache_state();
        }
    };

    OutputBundle run_welch_cache_probe_path(
        const ZxGpuRealArray &x,
        const WelchCacheProbeCase &test_case,
        int cache_mode,
        int *observed_state)
    {
        cusignal::zx_gpu_backend::spectral_test_hooks::
            set_welch_cache_override(cache_mode);
        const std::size_t line_len = test_case.shape.back();
        const int window_size =
            test_case.nperseg > 0
                ? std::min<int>(
                      test_case.nperseg,
                      static_cast<int>(line_len))
                : std::min<int>(256, static_cast<int>(line_len));
        ZxGpuWindowSpec window = make_periodogram_cache_probe_window(
            test_case.window_kind,
            window_size);
        OutputBundle output = materialize(make_device_bundle(
            cusignal::zx_gpu_backend::spectral::welch(
                x,
                test_case.fs,
                std::move(window),
                test_case.nperseg,
                test_case.noverlap,
                test_case.nfft,
                DetrendSpec{std::string("constant")},
                test_case.return_onesided,
                test_case.scaling,
                test_case.axis,
                test_case.average)));
        *observed_state =
            cusignal::zx_gpu_backend::spectral_test_hooks::
                consume_last_welch_cache_state();
        return output;
    }

    int run_welch_cache_device_ab_probe()
    {
        WelchCacheOverrideReset reset;
        std::ofstream report;
        const char *report_path =
            std::getenv("CUSIGNAL_WELCH_CACHE_DEVICE_AB_REPORT");
        if (report_path != nullptr && report_path[0] != '\0')
        {
            report.open(report_path);
            if (!report)
            {
                throw std::runtime_error(
                    "failed to open welch cache device A/B report");
            }
        }

        bool invalid_override_rejected = false;
        try
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_welch_cache_override(7);
        }
        catch (const std::invalid_argument &)
        {
            invalid_override_rejected = true;
        }
        if (!invalid_override_rejected)
        {
            throw std::runtime_error(
                "invalid welch cache override was accepted");
        }

        const std::vector<WelchCacheProbeCase> cases = {
            {"official_accuracy", {512}, 800.0f, 128, 64, 128, true,
             "density", -1, "mean", PeriodogramProbeWindowKind::Hann, true},
            {"official_perf", {32768}, 800.0f, 256, 128, 256, true,
             "density", -1, "mean", PeriodogramProbeWindowKind::Hann, true},
            {"spectrum_scaling", {1024}, 1200.0f, 128, 32, 256, true,
             "spectrum", -1, "mean", PeriodogramProbeWindowKind::Hann, true},
            {"median_average", {2048}, 1000.0f, 256, 128, 256, true,
             "density", -1, "median", PeriodogramProbeWindowKind::Hann, true},
            {"two_sided", {1024}, 900.0f, 128, 64, 128, false,
             "density", -1, "mean", PeriodogramProbeWindowKind::Hann, true},
            {"padded_boxcar", {1024}, 1100.0f, 128, 0, 256, true,
             "density", -1, "mean", PeriodogramProbeWindowKind::Boxcar, true},
            {"kaiser", {2048}, 1600.0f, 256, 128, 256, true,
             "density", -1, "mean", PeriodogramProbeWindowKind::Kaiser, true},
            {"multiline", {2, 512}, 700.0f, 128, 64, 128, true,
             "density", 1, "mean", PeriodogramProbeWindowKind::Hann, true},
            {"host_explicit", {512}, 600.0f, 128, 64, 128, true,
             "density", -1, "mean",
             PeriodogramProbeWindowKind::HostExplicit, false},
            {"device_explicit", {512}, 500.0f, 128, 64, 128, true,
             "density", -1, "mean",
             PeriodogramProbeWindowKind::DeviceExplicit, false},
            {"default_window_length", {1024}, 750.0f, 0, -1, 0, true,
             "density", -1, "mean", PeriodogramProbeWindowKind::Hann, true},
        };

        std::size_t checked_cases = 0;
        std::size_t checked_float_outputs = 0;
        std::size_t cache_misses = 0;
        std::size_t cache_hits = 0;
        std::size_t bypasses = 0;
        for (const WelchCacheProbeCase &test_case : cases)
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                reset_welch_cache();
            const ZxGpuRealArray x = ZxGpuRealArray::from_host(
                make_periodogram_cache_probe_input(test_case.shape));
            int bypass_state = -1;
            int miss_state = -1;
            int hit_state = -1;
            int automatic_state = -1;
            const OutputBundle bypass = run_welch_cache_probe_path(
                x,
                test_case,
                kWelchCacheBypass,
                &bypass_state);
            const OutputBundle first_cached = run_welch_cache_probe_path(
                x,
                test_case,
                kWelchCacheEnabled,
                &miss_state);
            const OutputBundle second_cached = run_welch_cache_probe_path(
                x,
                test_case,
                kWelchCacheEnabled,
                &hit_state);
            const OutputBundle automatic = run_welch_cache_probe_path(
                x,
                test_case,
                kWelchCacheAuto,
                &automatic_state);

            const int expected_first =
                test_case.cacheable
                    ? kWelchCacheStateMiss
                    : kWelchCacheStateBypass;
            const int expected_reuse =
                test_case.cacheable
                    ? kWelchCacheStateHit
                    : kWelchCacheStateBypass;
            if (bypass_state != kWelchCacheStateBypass ||
                miss_state != expected_first ||
                hit_state != expected_reuse ||
                automatic_state != expected_reuse)
            {
                throw std::runtime_error(
                    "welch cache route mismatch for case " + test_case.id);
            }

            std::string mismatch;
            for (const auto &candidate : {
                     std::pair<const char *, const OutputBundle *>(
                         "first_cached", &first_cached),
                     std::pair<const char *, const OutputBundle *>(
                         "second_cached", &second_cached),
                     std::pair<const char *, const OutputBundle *>(
                         "automatic", &automatic)})
            {
                if (!bitwise_equal_output_bundles(
                        bypass,
                        *candidate.second,
                        &mismatch))
                {
                    throw std::runtime_error(
                        "welch bypass/cache mismatch for case " +
                        test_case.id + "/" + candidate.first + " at " + mismatch);
                }
            }

            const int states[] = {
                bypass_state,
                miss_state,
                hit_state,
                automatic_state};
            for (int state : states)
            {
                cache_misses += state == kWelchCacheStateMiss ? 1 : 0;
                cache_hits += state == kWelchCacheStateHit ? 1 : 0;
                bypasses += state == kWelchCacheStateBypass ? 1 : 0;
            }
            ++checked_cases;
            checked_float_outputs += output_float_count(bypass);
        }

        cusignal::zx_gpu_backend::spectral_test_hooks::
            reset_welch_cache();
        WelchCacheProbeCase base_case = cases.front();
        WelchCacheProbeCase adjacent_case = base_case;
        adjacent_case.id = "adjacent_fs";
        adjacent_case.fs = std::nextafter(base_case.fs, base_case.fs + 1.0f);
        const ZxGpuRealArray adjacent_x = ZxGpuRealArray::from_host(
            make_periodogram_cache_probe_input(base_case.shape));
        int base_miss_state = -1;
        int adjacent_miss_state = -1;
        int adjacent_hit_state = -1;
        int adjacent_bypass_state = -1;
        const OutputBundle base_cached = run_welch_cache_probe_path(
            adjacent_x,
            base_case,
            kWelchCacheEnabled,
            &base_miss_state);
        const OutputBundle adjacent_cached = run_welch_cache_probe_path(
            adjacent_x,
            adjacent_case,
            kWelchCacheEnabled,
            &adjacent_miss_state);
        const OutputBundle adjacent_automatic = run_welch_cache_probe_path(
            adjacent_x,
            adjacent_case,
            kWelchCacheAuto,
            &adjacent_hit_state);
        const OutputBundle adjacent_bypass = run_welch_cache_probe_path(
            adjacent_x,
            adjacent_case,
            kWelchCacheBypass,
            &adjacent_bypass_state);
        (void)base_cached;
        if (base_miss_state != kWelchCacheStateMiss ||
            adjacent_miss_state != kWelchCacheStateMiss ||
            adjacent_hit_state != kWelchCacheStateHit ||
            adjacent_bypass_state != kWelchCacheStateBypass)
        {
            throw std::runtime_error(
                "welch adjacent-float cache invalidation mismatch");
        }
        std::string adjacent_mismatch;
        if (!bitwise_equal_output_bundles(
                adjacent_bypass,
                adjacent_cached,
                &adjacent_mismatch) ||
            !bitwise_equal_output_bundles(
                adjacent_bypass,
                adjacent_automatic,
                &adjacent_mismatch))
        {
            throw std::runtime_error(
                "welch adjacent-float bypass/cache mismatch at " +
                adjacent_mismatch);
        }
        cache_misses += 2;
        cache_hits += 1;
        bypasses += 1;
        ++checked_cases;
        checked_float_outputs += output_float_count(adjacent_bypass);

        if (report)
        {
            report << "summary\tpass\tchecked_cases\t" << checked_cases
                   << "\tchecked_float_outputs\t" << checked_float_outputs
                   << "\tcache_misses\t" << cache_misses
                   << "\tcache_hits\t" << cache_hits
                   << "\tbypasses\t" << bypasses
                   << "\tperformance\tnot_run\n";
        }
        std::cout << "[welch-cache-device-ab] PASS"
                  << " checked_cases=" << checked_cases
                  << " checked_float_outputs=" << checked_float_outputs
                  << " cache_misses=" << cache_misses
                  << " cache_hits=" << cache_hits
                  << " bypasses=" << bypasses
                  << " performance=not_run\n";
        return 0;
    }

    struct IstftCacheProbeCase
    {
        std::string id;
        Shape shape;
        float fs = 400.0f;
        int nperseg = 64;
        int noverlap = 48;
        int nfft = 128;
        bool input_onesided = true;
        bool boundary = true;
        int time_axis = -1;
        int freq_axis = -2;
        PeriodogramProbeWindowKind window_kind =
            PeriodogramProbeWindowKind::Hann;
        bool cacheable = true;
    };

    class IstftCacheOverrideReset
    {
    public:
        ~IstftCacheOverrideReset()
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_istft_cache_override(kIstftCacheAuto);
            cusignal::zx_gpu_backend::spectral_test_hooks::
                reset_istft_cache();
            (void)cusignal::zx_gpu_backend::spectral_test_hooks::
                consume_last_istft_cache_state();
        }
    };

    ComplexArray make_istft_cache_probe_input(const Shape &shape)
    {
        ComplexArray input = cusignal::core::make_complex_array(shape);
        for (std::size_t index = 0; index < input.values.size(); ++index)
        {
            const float x = static_cast<float>(index);
            const float real =
                0.35f * std::cos(0.017f * x + 0.2f) +
                0.11f * std::sin(0.031f * x - 0.4f);
            const float imag =
                0.29f * std::sin(0.023f * x + 0.1f) -
                0.07f * std::cos(0.043f * x - 0.3f);
            input.values[index] = Complex(real, imag);
        }
        return input;
    }

    int resolved_istft_probe_nperseg(const IstftCacheProbeCase &test_case)
    {
        if (test_case.nperseg > 0)
        {
            return test_case.nperseg;
        }
        const std::size_t freq_bins =
            test_case.shape[test_case.shape.size() - 2];
        return test_case.input_onesided
                   ? 2 * (static_cast<int>(freq_bins) - 1)
                   : static_cast<int>(freq_bins);
    }

    OutputBundle run_istft_cache_probe_path(
        const ZxGpuComplexArray &zxx,
        const IstftCacheProbeCase &test_case,
        int cache_mode,
        int *observed_state)
    {
        cusignal::zx_gpu_backend::spectral_test_hooks::
            set_istft_cache_override(cache_mode);
        ZxGpuWindowSpec window = make_periodogram_cache_probe_window(
            test_case.window_kind,
            resolved_istft_probe_nperseg(test_case));
        OutputBundle output = materialize(make_device_bundle(
            cusignal::zx_gpu_backend::spectral::istft(
                zxx,
                test_case.fs,
                std::move(window),
                test_case.nperseg,
                test_case.noverlap,
                test_case.nfft,
                test_case.input_onesided,
                test_case.boundary,
                test_case.time_axis,
                test_case.freq_axis)));
        *observed_state =
            cusignal::zx_gpu_backend::spectral_test_hooks::
                consume_last_istft_cache_state();
        return output;
    }

    void require_istft_probe_state(
        const std::string &case_id,
        int observed,
        int expected,
        const char *path)
    {
        if (observed != expected)
        {
            throw std::runtime_error(
                "istft cache route mismatch for case " + case_id +
                "/" + path);
        }
    }

    void require_istft_probe_output(
        const std::string &case_id,
        const char *path,
        const OutputBundle &baseline,
        const OutputBundle &candidate)
    {
        std::string mismatch;
        if (!bitwise_equal_output_bundles(
                baseline,
                candidate,
                &mismatch))
        {
            throw std::runtime_error(
                "istft bypass/cache mismatch for case " + case_id +
                "/" + path + " at " + mismatch);
        }
    }

    int run_istft_cache_device_ab_probe()
    {
        IstftCacheOverrideReset reset;
        std::ofstream report;
        const char *report_path =
            std::getenv("CUSIGNAL_ISTFT_CACHE_DEVICE_AB_REPORT");
        if (report_path != nullptr && report_path[0] != '\0')
        {
            report.open(report_path);
            if (!report)
            {
                throw std::runtime_error(
                    "failed to open istft cache device A/B report");
            }
        }

        bool invalid_override_rejected = false;
        try
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_istft_cache_override(7);
        }
        catch (const std::invalid_argument &)
        {
            invalid_override_rejected = true;
        }
        if (!invalid_override_rejected)
        {
            throw std::runtime_error(
                "invalid istft cache override was accepted");
        }

        const std::vector<IstftCacheProbeCase> cases = {
            {"official_accuracy", {65, 25}, 400.0f, 64, 48, 128, true,
             true, -1, -2, PeriodogramProbeWindowKind::Hann, true},
            {"official_perf", {129, 257}, 400.0f, 128, 96, 256, true,
             true, -1, -2, PeriodogramProbeWindowKind::Hann, true},
            {"two_sided", {128, 17}, 900.0f, 128, 64, 128, false,
             false, -1, -2, PeriodogramProbeWindowKind::Hann, true},
            {"boundary_disabled", {65, 9}, 600.0f, 64, 32, 128, true,
             false, -1, -2, PeriodogramProbeWindowKind::Boxcar, true},
            {"padded_nfft", {129, 11}, 1200.0f, 96, 48, 256, true,
             true, -1, -2, PeriodogramProbeWindowKind::Hann, true},
            {"kaiser", {65, 13}, 800.0f, 64, 32, 128, true,
             true, -1, -2, PeriodogramProbeWindowKind::Kaiser, true},
            {"default_sizes", {65, 9}, 750.0f, 0, -1, 0, true,
             true, -1, -2, PeriodogramProbeWindowKind::Hann, true},
            {"multiline", {2, 65, 9}, 700.0f, 64, 32, 128, true,
             true, -1, -2, PeriodogramProbeWindowKind::Hann, true},
            {"host_explicit", {65, 9}, 500.0f, 64, 32, 128, true,
             false, -1, -2, PeriodogramProbeWindowKind::HostExplicit, false},
            {"device_explicit", {65, 9}, 550.0f, 64, 32, 128, true,
             false, -1, -2, PeriodogramProbeWindowKind::DeviceExplicit, false},
        };

        std::size_t checked_cases = 0;
        std::size_t checked_float_outputs = 0;
        std::size_t cache_misses = 0;
        std::size_t cache_hits = 0;
        std::size_t bypasses = 0;
        const auto count_state = [&](int state) {
            cache_misses += state == kIstftCacheStateMiss ? 1 : 0;
            cache_hits += state == kIstftCacheStateHit ? 1 : 0;
            bypasses += state == kIstftCacheStateBypass ? 1 : 0;
        };

        for (const IstftCacheProbeCase &test_case : cases)
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                reset_istft_cache();
            const ZxGpuComplexArray zxx = ZxGpuComplexArray::from_host(
                make_istft_cache_probe_input(test_case.shape));
            int bypass_state = -1;
            int miss_state = -1;
            int hit_state = -1;
            int automatic_state = -1;
            const OutputBundle bypass = run_istft_cache_probe_path(
                zxx,
                test_case,
                kIstftCacheBypass,
                &bypass_state);
            const OutputBundle first_cached = run_istft_cache_probe_path(
                zxx,
                test_case,
                kIstftCacheEnabled,
                &miss_state);
            const OutputBundle second_cached = run_istft_cache_probe_path(
                zxx,
                test_case,
                kIstftCacheEnabled,
                &hit_state);
            const OutputBundle automatic = run_istft_cache_probe_path(
                zxx,
                test_case,
                kIstftCacheAuto,
                &automatic_state);

            const int expected_first =
                test_case.cacheable
                    ? kIstftCacheStateMiss
                    : kIstftCacheStateBypass;
            const int expected_reuse =
                test_case.cacheable
                    ? kIstftCacheStateHit
                    : kIstftCacheStateBypass;
            require_istft_probe_state(
                test_case.id,
                bypass_state,
                kIstftCacheStateBypass,
                "bypass");
            require_istft_probe_state(
                test_case.id,
                miss_state,
                expected_first,
                "first_cached");
            require_istft_probe_state(
                test_case.id,
                hit_state,
                expected_reuse,
                "second_cached");
            require_istft_probe_state(
                test_case.id,
                automatic_state,
                expected_reuse,
                "automatic");
            require_istft_probe_output(
                test_case.id,
                "first_cached",
                bypass,
                first_cached);
            require_istft_probe_output(
                test_case.id,
                "second_cached",
                bypass,
                second_cached);
            require_istft_probe_output(
                test_case.id,
                "automatic",
                bypass,
                automatic);

            for (int state : {
                     bypass_state,
                     miss_state,
                     hit_state,
                     automatic_state})
            {
                count_state(state);
            }
            ++checked_cases;
            checked_float_outputs += output_float_count(bypass);
        }

        cusignal::zx_gpu_backend::spectral_test_hooks::
            reset_istft_cache();
        IstftCacheProbeCase base_case = cases.front();
        IstftCacheProbeCase adjacent_case = base_case;
        adjacent_case.id = "adjacent_fs";
        adjacent_case.fs =
            std::nextafter(base_case.fs, base_case.fs + 1.0f);
        const ZxGpuComplexArray adjacent_zxx =
            ZxGpuComplexArray::from_host(
                make_istft_cache_probe_input(base_case.shape));
        int base_miss_state = -1;
        int adjacent_miss_state = -1;
        int adjacent_hit_state = -1;
        int adjacent_bypass_state = -1;
        const OutputBundle base_cached = run_istft_cache_probe_path(
            adjacent_zxx,
            base_case,
            kIstftCacheEnabled,
            &base_miss_state);
        const OutputBundle adjacent_cached = run_istft_cache_probe_path(
            adjacent_zxx,
            adjacent_case,
            kIstftCacheEnabled,
            &adjacent_miss_state);
        const OutputBundle adjacent_automatic = run_istft_cache_probe_path(
            adjacent_zxx,
            adjacent_case,
            kIstftCacheAuto,
            &adjacent_hit_state);
        const OutputBundle adjacent_bypass = run_istft_cache_probe_path(
            adjacent_zxx,
            adjacent_case,
            kIstftCacheBypass,
            &adjacent_bypass_state);
        (void)base_cached;
        require_istft_probe_state(
            adjacent_case.id,
            base_miss_state,
            kIstftCacheStateMiss,
            "base_miss");
        require_istft_probe_state(
            adjacent_case.id,
            adjacent_miss_state,
            kIstftCacheStateMiss,
            "time_axis_miss");
        require_istft_probe_state(
            adjacent_case.id,
            adjacent_hit_state,
            kIstftCacheStateHit,
            "time_axis_hit");
        require_istft_probe_state(
            adjacent_case.id,
            adjacent_bypass_state,
            kIstftCacheStateBypass,
            "bypass");
        require_istft_probe_output(
            adjacent_case.id,
            "cached",
            adjacent_bypass,
            adjacent_cached);
        require_istft_probe_output(
            adjacent_case.id,
            "automatic",
            adjacent_bypass,
            adjacent_automatic);
        for (int state : {
                 base_miss_state,
                 adjacent_miss_state,
                 adjacent_hit_state,
                 adjacent_bypass_state})
        {
            count_state(state);
        }
        ++checked_cases;
        checked_float_outputs += output_float_count(adjacent_bypass);

        cusignal::zx_gpu_backend::spectral_test_hooks::
            reset_istft_cache();
        IstftCacheProbeCase changed_window_case = base_case;
        changed_window_case.id = "changed_window";
        changed_window_case.window_kind =
            PeriodogramProbeWindowKind::Kaiser;
        int hann_miss_state = -1;
        int kaiser_miss_state = -1;
        int kaiser_hit_state = -1;
        int kaiser_bypass_state = -1;
        const OutputBundle hann_cached = run_istft_cache_probe_path(
            adjacent_zxx,
            base_case,
            kIstftCacheEnabled,
            &hann_miss_state);
        const OutputBundle kaiser_cached = run_istft_cache_probe_path(
            adjacent_zxx,
            changed_window_case,
            kIstftCacheEnabled,
            &kaiser_miss_state);
        const OutputBundle kaiser_automatic = run_istft_cache_probe_path(
            adjacent_zxx,
            changed_window_case,
            kIstftCacheAuto,
            &kaiser_hit_state);
        const OutputBundle kaiser_bypass = run_istft_cache_probe_path(
            adjacent_zxx,
            changed_window_case,
            kIstftCacheBypass,
            &kaiser_bypass_state);
        (void)hann_cached;
        require_istft_probe_state(
            changed_window_case.id,
            hann_miss_state,
            kIstftCacheStateMiss,
            "hann_miss");
        require_istft_probe_state(
            changed_window_case.id,
            kaiser_miss_state,
            kIstftCacheStateMiss,
            "kaiser_miss");
        require_istft_probe_state(
            changed_window_case.id,
            kaiser_hit_state,
            kIstftCacheStateHit,
            "kaiser_hit");
        require_istft_probe_state(
            changed_window_case.id,
            kaiser_bypass_state,
            kIstftCacheStateBypass,
            "kaiser_bypass");
        require_istft_probe_output(
            changed_window_case.id,
            "cached",
            kaiser_bypass,
            kaiser_cached);
        require_istft_probe_output(
            changed_window_case.id,
            "automatic",
            kaiser_bypass,
            kaiser_automatic);
        for (int state : {
                 hann_miss_state,
                 kaiser_miss_state,
                 kaiser_hit_state,
                 kaiser_bypass_state})
        {
            count_state(state);
        }
        ++checked_cases;
        checked_float_outputs += output_float_count(kaiser_bypass);

        if (report)
        {
            report << "summary\tpass\tchecked_cases\t" << checked_cases
                   << "\tchecked_float_outputs\t" << checked_float_outputs
                   << "\tcache_misses\t" << cache_misses
                   << "\tcache_hits\t" << cache_hits
                   << "\tbypasses\t" << bypasses
                   << "\tperformance\tnot_run\n";
        }
        std::cout << "[istft-cache-device-ab] PASS"
                  << " checked_cases=" << checked_cases
                  << " checked_float_outputs=" << checked_float_outputs
                  << " cache_misses=" << cache_misses
                  << " cache_hits=" << cache_hits
                  << " bypasses=" << bypasses
                  << " performance=not_run\n";
        return 0;
    }

    float median_speedup(const std::optional<TimingStats> &baseline, const std::optional<TimingStats> &candidate)
    {
        if (!baseline.has_value() || !candidate.has_value() || candidate->median_ms <= 0.0)
        {
            return 0.0;
        }
        return baseline->median_ms / candidate->median_ms;
    }

    bool include_accuracy_cases(const CliOptions &options)
    {
        return options.case_set == "accuracy" || options.case_set == "full" || options.case_set == "smoke";
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

    RealArray load_x_array(const SpectralCase &test_case)
    {
        RealArray array;
        if (test_case.generated_x.has_value())
        {
            array = *test_case.generated_x;
        }
        else
        {
            array = load_real_array(test_case.x_file, test_case.x_shape);
        }
        return apply_dtype_quantization(array, test_case.dtype);
    }

    RealArray load_y_array(const SpectralCase &test_case)
    {
        RealArray array;
        if (test_case.generated_y.has_value())
        {
            array = *test_case.generated_y;
        }
        else
        {
            array = load_real_array(test_case.y_file, test_case.y_shape);
        }
        return apply_dtype_quantization(array, test_case.dtype);
    }

    ComplexArray load_zxx(const SpectralCase &test_case)
    {
        if (test_case.generated_zxx.has_value())
        {
            return *test_case.generated_zxx;
        }
        return load_complex_array(test_case.zxx_file, test_case.zxx_shape);
    }

    RealSignal load_x_signal(const SpectralCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_x.has_value())
        {
            signal = test_case.generated_x->values;
        }
        else
        {
            signal = read_real_csv(test_case.x_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    RealSignal load_y_signal(const SpectralCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_y.has_value())
        {
            signal = test_case.generated_y->values;
        }
        else
        {
            signal = read_real_csv(test_case.y_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    RealSignal load_freqs(const SpectralCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_freqs.has_value())
        {
            signal = *test_case.generated_freqs;
        }
        else
        {
            signal = read_real_csv(test_case.freqs_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    RealSignal load_events(const SpectralCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_events.has_value())
        {
            signal = *test_case.generated_events;
        }
        else
        {
            signal = read_real_csv(test_case.events_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    RealSignal load_periods(const SpectralCase &test_case)
    {
        RealSignal signal;
        if (test_case.generated_periods.has_value())
        {
            signal = *test_case.generated_periods;
        }
        else
        {
            signal = read_real_csv(test_case.period_file);
        }
        return apply_dtype_quantization(signal, test_case.dtype);
    }

    Runner resolve_runner(const std::string &op)
    {
        if (op == "lombscargle")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::lombscargle(
                        load_x_signal(test_case),
                        load_y_signal(test_case),
                        load_freqs(test_case),
                        test_case.precenter,
                        test_case.normalize));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::lombscargle(
                        load_x_signal(test_case),
                        load_y_signal(test_case),
                        load_freqs(test_case),
                        test_case.precenter,
                        test_case.normalize));
                }};
        }
        if (op == "periodogram")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::periodogram(
                        load_x_array(test_case),
                        test_case.fs,
                        test_case.window,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::periodogram(
                        load_x_array(test_case),
                        test_case.fs,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis));
                }};
        }
        if (op == "welch")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::welch(
                        load_x_array(test_case),
                        test_case.fs,
                        test_case.window,
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis,
                        test_case.average));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::welch(
                        load_x_array(test_case),
                        test_case.fs,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis,
                        test_case.average));
                }};
        }
        if (op == "csd")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::csd(
                        load_x_array(test_case),
                        load_y_array(test_case),
                        test_case.fs,
                        test_case.window,
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis,
                        test_case.average));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::csd(
                        load_x_array(test_case),
                        load_y_array(test_case),
                        test_case.fs,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis,
                        test_case.average));
                }};
        }
        if (op == "spectrogram")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::spectrogram(
                        load_x_array(test_case),
                        test_case.fs,
                        test_case.window,
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis,
                        test_case.mode));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::spectrogram(
                        load_x_array(test_case),
                        test_case.fs,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.scaling,
                        test_case.axis,
                        test_case.mode));
                }};
        }
        if (op == "stft")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::stft(
                        load_x_array(test_case),
                        test_case.fs,
                        test_case.window,
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.boundary,
                        test_case.padded,
                        test_case.axis));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::stft(
                        load_x_array(test_case),
                        test_case.fs,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.return_onesided,
                        test_case.boundary,
                        test_case.padded,
                        test_case.axis));
                }};
        }
        if (op == "istft")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::istft(
                        load_zxx(test_case),
                        test_case.fs,
                        test_case.window,
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.input_onesided,
                        test_case.boundary_enabled,
                        test_case.time_axis,
                        test_case.freq_axis));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::istft(
                        load_zxx(test_case),
                        test_case.fs,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.input_onesided,
                        test_case.boundary_enabled,
                        test_case.time_axis,
                        test_case.freq_axis));
                }};
        }
        if (op == "coherence")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    return make_bundle(cusignal::cpu::spectral::coherence(
                        load_x_array(test_case),
                        load_y_array(test_case),
                        test_case.fs,
                        test_case.window,
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.axis));
                },
                [](const SpectralCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::coherence(
                        load_x_array(test_case),
                        load_y_array(test_case),
                        test_case.fs,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nperseg,
                        test_case.noverlap,
                        test_case.nfft,
                        test_case.detrend,
                        test_case.axis));
                }};
        }
        if (op == "vectorstrength")
        {
            return Runner{
                [](const SpectralCase &test_case) {
                    if (test_case.period_scalar > 0.0)
                    {
                        return make_bundle(cusignal::cpu::spectral::vectorstrength(
                            load_events(test_case),
                            test_case.period_scalar));
                    }
                    return make_bundle(cusignal::cpu::spectral::vectorstrength(
                        load_events(test_case),
                        load_periods(test_case)));
                },
                [](const SpectralCase &test_case) {
                    if (test_case.period_scalar > 0.0)
                    {
                        return make_device_bundle(cusignal::zx_gpu_backend::spectral::vectorstrength(
                            load_events(test_case),
                            test_case.period_scalar));
                    }
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::vectorstrength(
                        load_events(test_case),
                        load_periods(test_case)));
                }};
        }
        throw std::runtime_error("unsupported spectral operator: " + op);
    }

    OutputBundle load_expected_bundle(const std::string &op, const SpectralCase &test_case)
    {
        if (op == "lombscargle")
        {
            return make_bundle(read_real_csv(test_case.expected_signal_file));
        }
        if (op == "periodogram" || op == "welch" || op == "coherence")
        {
            OutputBundle bundle;
            const RealSignal frequencies = read_real_csv(test_case.expected_frequencies_file);
            bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{frequencies.size()}, frequencies, {}});
            bundle.fields.push_back(OutputField{"values", FieldKind::RealArray, Shape{frequencies.size()}, read_real_csv(test_case.expected_values_file), {}});
            return bundle;
        }
        if (op == "csd")
        {
            OutputBundle bundle;
            const RealSignal frequencies = read_real_csv(test_case.expected_frequencies_file);
            bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{frequencies.size()}, frequencies, {}});
            bundle.fields.push_back(OutputField{"values", FieldKind::ComplexArray, Shape{frequencies.size()}, {}, read_complex_csv(test_case.expected_values_file)});
            return bundle;
        }
        if (op == "spectrogram")
        {
            OutputBundle bundle;
            const RealSignal frequencies = read_real_csv(test_case.expected_frequencies_file);
            const RealSignal times = read_real_csv(test_case.expected_times_file);
            bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{frequencies.size()}, frequencies, {}});
            bundle.fields.push_back(OutputField{"times", FieldKind::RealSignal, Shape{times.size()}, times, {}});
            const Shape value_shape{frequencies.size(), times.size()};
            if (test_case.mode == "complex")
            {
                bundle.fields.push_back(OutputField{"values", FieldKind::ComplexArray, value_shape, {}, read_complex_csv(test_case.expected_values_file)});
            }
            else
            {
                bundle.fields.push_back(OutputField{"values", FieldKind::RealArray, value_shape, read_real_csv(test_case.expected_values_file), {}});
            }
            return bundle;
        }
        if (op == "stft")
        {
            OutputBundle bundle;
            const RealSignal frequencies = read_real_csv(test_case.expected_frequencies_file);
            const RealSignal times = read_real_csv(test_case.expected_times_file);
            bundle.fields.push_back(OutputField{"frequencies", FieldKind::RealSignal, Shape{frequencies.size()}, frequencies, {}});
            bundle.fields.push_back(OutputField{"times", FieldKind::RealSignal, Shape{times.size()}, times, {}});
            bundle.fields.push_back(OutputField{"values", FieldKind::ComplexArray, Shape{frequencies.size(), times.size()}, {}, read_complex_csv(test_case.expected_values_file)});
            return bundle;
        }
        if (op == "istft")
        {
            OutputBundle bundle;
            const RealSignal times = read_real_csv(test_case.expected_times_file);
            bundle.fields.push_back(OutputField{"times", FieldKind::RealSignal, Shape{times.size()}, times, {}});
            bundle.fields.push_back(OutputField{"signal", FieldKind::RealArray, Shape{times.size()}, read_real_csv(test_case.expected_signal_file), {}});
            return bundle;
        }
        if (op == "vectorstrength")
        {
            OutputBundle bundle;
            const RealSignal strength = read_real_csv(test_case.expected_strength_file);
            const RealSignal phase = read_real_csv(test_case.expected_phase_file);
            bundle.fields.push_back(OutputField{"strength", FieldKind::RealSignal, Shape{strength.size()}, strength, {}});
            bundle.fields.push_back(OutputField{"phase", FieldKind::RealSignal, Shape{phase.size()}, phase, {}});
            return bundle;
        }
        throw std::runtime_error("unsupported expected bundle operator");
    }

    void write_field_sample(
        const fs::path &base_dir,
        const std::string &case_id,
        const std::string &backend,
        const OutputField &field,
        std::vector<Artifact> *artifacts)
    {
        const fs::path path = base_dir / (case_id + "__" + backend + "__" + field.name + ".csv");
        if (field.kind == FieldKind::ComplexArray)
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

    std::string build_case_spec_json(const std::string &op, const SpectralCase &test_case)
    {
        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"operator\": \"" << cusignal_test::report::json_escape(op) << "\",\n";
        stream << "  \"id\": \"" << cusignal_test::report::json_escape(test_case.id) << "\",\n";
        stream << "  \"fs\": " << test_case.fs << ",\n";
        stream << "  \"nfft\": " << test_case.nfft << ",\n";
        stream << "  \"nperseg\": " << test_case.nperseg << ",\n";
        stream << "  \"noverlap\": " << test_case.noverlap << ",\n";
        stream << "  \"axis\": " << test_case.axis << ",\n";
        stream << "  \"time_axis\": " << test_case.time_axis << ",\n";
        stream << "  \"freq_axis\": " << test_case.freq_axis << ",\n";
        stream << "  \"precenter\": " << (test_case.precenter ? "true" : "false") << ",\n";
        stream << "  \"normalize\": " << (test_case.normalize ? "true" : "false") << ",\n";
        stream << "  \"return_onesided\": " << (test_case.return_onesided ? "true" : "false") << ",\n";
        stream << "  \"padded\": " << (test_case.padded ? "true" : "false") << ",\n";
        stream << "  \"input_onesided\": " << (test_case.input_onesided ? "true" : "false") << ",\n";
        stream << "  \"boundary_enabled\": " << (test_case.boundary_enabled ? "true" : "false") << ",\n";
        stream << "  \"period_scalar\": " << test_case.period_scalar << ",\n";
        stream << "  \"dtype\": \"" << cusignal_test::report::json_escape(test_case.dtype) << "\",\n";
        stream << "  \"scaling\": \"" << cusignal_test::report::json_escape(test_case.scaling) << "\",\n";
        stream << "  \"average\": \"" << cusignal_test::report::json_escape(test_case.average) << "\",\n";
        stream << "  \"mode\": \"" << cusignal_test::report::json_escape(test_case.mode) << "\",\n";
        stream << "  \"boundary\": \"" << cusignal_test::report::json_escape(test_case.boundary) << "\",\n";
        stream << "  \"window\": " << build_window_spec_json(test_case.window) << ",\n";
        stream << "  \"detrend\": " << build_detrend_json(test_case.detrend) << "\n";
        stream << "}\n";
        return stream.str();
    }

    void write_input_samples(
        const fs::path &base_dir,
        const std::string &op,
        const SpectralCase &test_case,
        std::vector<Artifact> *artifacts)
    {
        fs::create_directories(base_dir);
        const fs::path spec_path = base_dir / (test_case.id + "__spec.json");
        cusignal_test::report::write_text_file(spec_path, build_case_spec_json(op, test_case));
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{"case_spec", spec_path});
        }

        if (test_case.generated_x.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__x.csv");
            write_real_csv(path, test_case.generated_x->values);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"x_input", path});
        }
        if (test_case.generated_y.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__y.csv");
            write_real_csv(path, test_case.generated_y->values);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"y_input", path});
        }
        if (test_case.generated_zxx.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__zxx.csv");
            write_complex_csv(path, test_case.generated_zxx->values);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"zxx_input", path});
        }
        if (test_case.generated_freqs.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__freqs.csv");
            write_real_csv(path, *test_case.generated_freqs);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"freqs_input", path});
        }
        if (test_case.generated_events.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__events.csv");
            write_real_csv(path, *test_case.generated_events);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"events_input", path});
        }
        if (test_case.generated_periods.has_value())
        {
            const fs::path path = base_dir / (test_case.id + "__period.csv");
            write_real_csv(path, *test_case.generated_periods);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"period_input", path});
        }
    }

    std::size_t sample_count(const OutputBundle &bundle)
    {
        if (bundle.fields.empty())
        {
            return 0;
        }
        const OutputField &field = bundle.fields.front();
        return field.kind == FieldKind::ComplexArray ? field.complex_values.size() : field.real_values.size();
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
            summary.cpu_gpu_error.mixed_error =
                std::max(summary.cpu_gpu_error.mixed_error, report.cpu_gpu_error.mixed_error);
            summary.cpu_gpu_error.rmse =
                std::max(summary.cpu_gpu_error.rmse, report.cpu_gpu_error.rmse);
            if (report.cpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error = std::max(reference_error.max_abs_error, report.cpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(reference_error.max_rel_error, report.cpu_reference_error->max_rel_error);
                reference_error.mixed_error = std::max(reference_error.mixed_error, report.cpu_reference_error->mixed_error);
                reference_error.rmse = std::max(reference_error.rmse, report.cpu_reference_error->rmse);
            }
            if (report.gpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error = std::max(reference_error.max_abs_error, report.gpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(reference_error.max_rel_error, report.gpu_reference_error->max_rel_error);
                reference_error.mixed_error = std::max(reference_error.mixed_error, report.gpu_reference_error->mixed_error);
                reference_error.rmse = std::max(reference_error.rmse, report.gpu_reference_error->rmse);
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
            "spectral",
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
        cusignal_test::report::update_module_reports("spectral", module_report_root());
    }

    void print_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << "[spectral/" << op << "] "
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
        std::cout << "reports       : data/reports/unit/spectral/" << op << "/latest_summary.md\n";
    }

    CaseReport make_failed_case_report(const SpectralCase &test_case, const std::string &message)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;
        report.pass = false;
        report.note = message;
        return report;
    }

    std::vector<SpectralCase> load_spectral_cases(const fs::path &manifest_path, const std::string &category)
    {
        std::vector<SpectralCase> cases;
        const JsonValue manifest = cusignal_test::json::parse(
            cusignal_test::report::read_text_file(manifest_path));
        const JsonObject &root = as_object(manifest);
        const JsonArray &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const JsonValue &item : case_array)
        {
            const JsonObject &object = as_object(item);
            SpectralCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.fs = get_optional_number(object, "fs", 1.0); // 采样频率
            test_case.nfft = get_optional_int(object, "nfft", 0); // FFT 长度
            test_case.nperseg = get_optional_int(object, "nperseg", 0); // 分段长度
            test_case.noverlap = get_optional_int(object, "noverlap", -1); // 重叠长度
            test_case.axis = get_optional_int(object, "axis", -1); // 变换轴
            test_case.time_axis = get_optional_int(object, "time_axis", -1); // ISTFT 时间轴
            test_case.freq_axis = get_optional_int(object, "freq_axis", -2); // ISTFT 频率轴
            test_case.precenter = get_optional_bool(object, "precenter", false); // Lomb-Scargle 去均值开关
            test_case.normalize = get_optional_bool(object, "normalize", false); // Lomb-Scargle 归一化开关
            test_case.return_onesided = get_optional_bool(object, "return_onesided", true); // 单边频谱开关
            test_case.padded = get_optional_bool(object, "padded", true); // STFT 尾段补零开关
            test_case.input_onesided = get_optional_bool(object, "input_onesided", true); // ISTFT 单边输入开关
            test_case.boundary_enabled = get_optional_bool(object, "boundary_enabled", true); // STFT 边界扩展开关
            test_case.period_scalar = get_optional_number(object, "period_scalar", 0.0); // vectorstrength 的标量周期
            test_case.atol = get_optional_number(object, "atol", 0.0); // 绝对误差容限
            test_case.rtol = get_optional_number(object, "rtol", 0.0); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // dtype 兼容性标签
            test_case.scaling = get_optional_string(object, "scaling").value_or("density"); // PSD 缩放模式
            test_case.average = get_optional_string(object, "average").value_or("mean"); // Welch 平均模式
            test_case.mode = get_optional_string(object, "mode").value_or("psd"); // spectrogram 输出模式
            test_case.boundary = get_optional_string(object, "boundary").value_or("zeros"); // STFT 边界模式
            if (const auto iter = object.find("window"); iter != object.end()) test_case.window = parse_window_spec(iter->second);
            if (const auto iter = object.find("detrend"); iter != object.end()) test_case.detrend = parse_detrend_spec(iter->second);
            if (const auto iter = object.find("x_shape"); iter != object.end()) test_case.x_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("y_shape"); iter != object.end()) test_case.y_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("zxx_shape"); iter != object.end()) test_case.zxx_shape = json_array_to_shape(iter->second);

            if (auto v = get_optional_string(object, "x_file")) test_case.x_file = base / *v;
            if (auto v = get_optional_string(object, "y_file")) test_case.y_file = base / *v;
            if (auto v = get_optional_string(object, "zxx_file")) test_case.zxx_file = base / *v;
            if (auto v = get_optional_string(object, "freqs_file")) test_case.freqs_file = base / *v;
            if (auto v = get_optional_string(object, "events_file")) test_case.events_file = base / *v;
            if (auto v = get_optional_string(object, "period_file")) test_case.period_file = base / *v;

            if (auto v = get_optional_string(object, "expected_signal_file")) test_case.expected_signal_file = base / *v;
            if (auto v = get_optional_string(object, "expected_values_file")) test_case.expected_values_file = base / *v;
            if (auto v = get_optional_string(object, "expected_frequencies_file")) test_case.expected_frequencies_file = base / *v;
            if (auto v = get_optional_string(object, "expected_times_file")) test_case.expected_times_file = base / *v;
            if (auto v = get_optional_string(object, "expected_strength_file")) test_case.expected_strength_file = base / *v;
            if (auto v = get_optional_string(object, "expected_phase_file")) test_case.expected_phase_file = base / *v;

            if (category == "perf")
            {
                test_case.generated_x = parse_real_array_generator(object, "x_generator");
                test_case.generated_y = parse_real_array_generator(object, "y_generator");
                test_case.generated_zxx = parse_complex_array_generator(object, "zxx_generator");
                test_case.generated_freqs = parse_real_signal_generator(object, "freqs_generator");
                test_case.generated_events = parse_real_signal_generator(object, "events_generator");
                test_case.generated_periods = parse_real_signal_generator(object, "period_generator");
                if (test_case.generated_x.has_value() && test_case.x_shape.empty())
                {
                    test_case.x_shape = test_case.generated_x->shape;
                }
                if (test_case.generated_y.has_value() && test_case.y_shape.empty())
                {
                    test_case.y_shape = test_case.generated_y->shape;
                }
                if (test_case.generated_zxx.has_value() && test_case.zxx_shape.empty())
                {
                    test_case.zxx_shape = test_case.generated_zxx->shape;
                }
            }
            cases.push_back(std::move(test_case));
        }
        return cases;
    }

    CaseReport evaluate_accuracy_case(
        const std::string &op,
        const SpectralCase &test_case,
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
        report.samples = sample_count(cpu_output);
        report.cpu_gpu_error = compute_bundle_error(cpu_output, gpu_output, test_case.atol);
        report.cpu_reference_error = compute_bundle_error(cpu_output, expected, test_case.atol);
        report.gpu_reference_error = compute_bundle_error(gpu_output, expected, test_case.atol);
        report.pass = bundle_within_tolerance(cpu_output, expected, test_case.atol, test_case.rtol) &&
                      bundle_within_tolerance(gpu_output, expected, test_case.atol, test_case.rtol);
        return report;
    }

    CaseReport evaluate_perf_case(
        const std::string &op,
        const SpectralCase &test_case,
        const Runner &runner,
        const CliOptions &options)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;

        std::optional<ZxGpuRealArray> csd_x;
        std::optional<ZxGpuRealArray> csd_y;
        if (op == "csd")
        {
            csd_x.emplace(ZxGpuRealArray::from_host(load_x_array(test_case)));
            csd_y.emplace(ZxGpuRealArray::from_host(load_y_array(test_case)));
        }
        std::optional<ZxGpuRealArray> spectral_x;
        if (op == "spectrogram" || op == "stft")
        {
            const RealArray x = load_x_array(test_case);
            report.samples = x.values.size();
            spectral_x.emplace(ZxGpuRealArray::from_host(x));
        }
        std::optional<ZxGpuRealSignal> vectorstrength_events;
        std::optional<RealSignal> vectorstrength_periods;
        if (op == "vectorstrength")
        {
            const RealSignal events = load_events(test_case);
            report.samples = events.size();
            vectorstrength_events.emplace(ZxGpuRealSignal::from_host(events));
            if (!(test_case.period_scalar > 0.0))
            {
                vectorstrength_periods.emplace(load_periods(test_case));
            }
        }
        auto run_gpu_perf = [&]() -> DeviceOutputBundle {
            if (csd_x.has_value() && csd_y.has_value())
            {
                return make_device_bundle(cusignal::zx_gpu_backend::spectral::csd(
                    *csd_x,
                    *csd_y,
                    test_case.fs,
                    to_zx_gpu_window_spec(test_case.window),
                    test_case.nperseg,
                    test_case.noverlap,
                    test_case.nfft,
                    test_case.detrend,
                    test_case.return_onesided,
                    test_case.scaling,
                    test_case.axis,
                    test_case.average));
            }
            if (vectorstrength_events.has_value())
            {
                if (test_case.period_scalar > 0.0)
                {
                    return make_device_bundle(cusignal::zx_gpu_backend::spectral::vectorstrength(
                        *vectorstrength_events,
                        test_case.period_scalar));
                }
                return make_device_bundle(cusignal::zx_gpu_backend::spectral::vectorstrength(
                    *vectorstrength_events,
                    *vectorstrength_periods));
            }
            if (op == "spectrogram" && spectral_x.has_value())
            {
                return make_device_bundle(cusignal::zx_gpu_backend::spectral::spectrogram(
                    *spectral_x,
                    test_case.fs,
                    to_zx_gpu_window_spec(test_case.window),
                    test_case.nperseg,
                    test_case.noverlap,
                    test_case.nfft,
                    test_case.detrend,
                    test_case.return_onesided,
                    test_case.scaling,
                    test_case.axis,
                    test_case.mode));
            }
            if (op == "stft" && spectral_x.has_value())
            {
                return make_device_bundle(cusignal::zx_gpu_backend::spectral::stft(
                    *spectral_x,
                    test_case.fs,
                    to_zx_gpu_window_spec(test_case.window),
                    test_case.nperseg,
                    test_case.noverlap,
                    test_case.nfft,
                    test_case.detrend,
                    test_case.return_onesided,
                    test_case.boundary,
                    test_case.padded,
                    test_case.axis));
            }
            return runner.gpu(test_case);
        };

        OutputBundle gpu_output;
        if (!options.gpu_only_perf)
        {
            gpu_output = materialize(run_gpu_perf());
            report.samples = sample_count(gpu_output);
        }
        else if (report.samples == 0)
        {
            const Shape &shape = test_case.zxx_shape.empty() ? test_case.x_shape : test_case.zxx_shape;
            report.samples = cusignal::core::shape_product(shape);
        }
        if (!options.gpu_only_perf)
        {
            const OutputBundle cpu_output = runner.cpu(test_case);
            report.cpu_gpu_error = compute_bundle_error(cpu_output, gpu_output, test_case.atol);
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
        report.gpu_kernel_perf = benchmark_gpu_kernel_latency(options, [&]() { (void)run_gpu_perf(); });

        if (options.emit_report)
        {
            if (!options.gpu_only_perf)
            {
                const fs::path op_generated_root = generated_root(op);
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

    int run_spectral_operator_tests(const std::string &op, int argc, char **argv)
    {
        const CliOptions options = parse_cli(argc, argv);
        const Runner runner = resolve_runner(op);
        std::vector<CaseReport> reports;

        if (include_accuracy_cases(options))
        {
            const auto accuracy_cases = load_spectral_cases(reference_root(op) / "manifest.json", "accuracy");
            for (const SpectralCase &test_case : accuracy_cases)
            {
                try
                {
                    reports.push_back(evaluate_accuracy_case(op, test_case, runner));
                }
                catch (const std::exception &error)
                {
                    reports.push_back(make_failed_case_report(test_case, error.what()));
                }
            }
        }
        if (include_perf_cases(options))
        {
            const auto perf_cases = load_spectral_cases(generated_root(op) / "manifest.json", "perf");
            for (const SpectralCase &test_case : perf_cases)
            {
                try
                {
                    reports.push_back(evaluate_perf_case(op, test_case, runner, options));
                }
                catch (const std::exception &error)
                {
                    reports.push_back(make_failed_case_report(test_case, error.what()));
                }
            }
        }

        write_reports(op, options, reports);
        update_module_reports();
        const OperatorSummary summary = summarize_cases(op, reports);
        print_terminal_summary(op, summary);
        return summary.pass ? 0 : 1;
    }
} // namespace

int run_lombscargle_tests(int argc, char **argv)
{
    try
    {
        return run_spectral_operator_tests("lombscargle", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_periodogram_tests(int argc, char **argv)
{
    try
    {
        if (std::getenv("CUSIGNAL_PERIODOGRAM_CACHE_DEVICE_AB") != nullptr)
        {
            return run_periodogram_cache_device_ab_probe();
        }
        if (std::getenv("CUSIGNAL_PERIODOGRAM_CACHE_BYPASS") != nullptr)
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_periodogram_cache_override(kPeriodogramCacheBypass);
        }
        return run_spectral_operator_tests("periodogram", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_welch_tests(int argc, char **argv)
{
    try
    {
        if (std::getenv("CUSIGNAL_WELCH_CACHE_DEVICE_AB") != nullptr)
        {
            return run_welch_cache_device_ab_probe();
        }
        if (std::getenv("CUSIGNAL_WELCH_CACHE_BYPASS") != nullptr)
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_welch_cache_override(kWelchCacheBypass);
        }
        return run_spectral_operator_tests("welch", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_csd_tests(int argc, char **argv)
{
    try
    {
        return run_spectral_operator_tests("csd", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_spectrogram_tests(int argc, char **argv)
{
    try
    {
        return run_spectral_operator_tests("spectrogram", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_stft_tests(int argc, char **argv)
{
    try
    {
        return run_spectral_operator_tests("stft", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_istft_tests(int argc, char **argv)
{
    try
    {
        if (std::getenv("CUSIGNAL_ISTFT_CACHE_DEVICE_AB") != nullptr)
        {
            return run_istft_cache_device_ab_probe();
        }
        if (std::getenv("CUSIGNAL_ISTFT_CACHE_BYPASS") != nullptr)
        {
            cusignal::zx_gpu_backend::spectral_test_hooks::
                set_istft_cache_override(kIstftCacheBypass);
        }
        return run_spectral_operator_tests("istft", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_coherence_tests(int argc, char **argv)
{
    try
    {
        return run_spectral_operator_tests("coherence", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_vectorstrength_tests(int argc, char **argv)
{
    try
    {
        return run_spectral_operator_tests("vectorstrength", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[spectral] ERROR: " << error.what() << '\n';
        return 1;
    }
}
