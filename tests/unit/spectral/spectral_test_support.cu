#include "spectral_test_support.hpp"

#include <cuda_runtime.h>

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
#include <variant>
#include <vector>

#include "../../../include/cusignal/core/helpers.hpp"
#include "../../../include/cusignal/spectral/spectral.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace cuda_backend
    {
        namespace spectral_test_hooks
        {
            float consume_last_kernel_ms();
        }
    } // namespace cuda_backend
} // namespace cusignal

namespace
{
    namespace spectral_api = cusignal::spectral_api;
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexArrayLike;
    using cusignal::core::ComplexSignal;
    using cusignal::core::CudaComplexArray;
    using cusignal::core::CudaComplexSignal;
    using cusignal::core::CudaRealArray;
    using cusignal::core::CudaRealSignal;
    using cusignal::core::CudaWindowSpec;
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
        CudaRealSignal real_signal;
        CudaRealArray real_array;
        CudaComplexArray complex_array;
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

    CudaWindowSpec to_cuda_window_spec(const WindowSpec &spec)
    {
        return std::visit(
            [](const auto &value) -> CudaWindowSpec {
                return CudaWindowSpec{value};
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

    DeviceOutputBundle make_device_bundle(const CudaRealSignal &values, const std::string &name = "signal")
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

    DeviceOutputBundle make_device_bundle(const spectral_api::CudaRealSpectrumResult &result)
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

    DeviceOutputBundle make_device_bundle(const spectral_api::CudaComplexSpectrumResult &result)
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

    DeviceOutputBundle make_device_bundle(const spectral_api::CudaSpectrogramResult &result)
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
                if constexpr (std::is_same_v<T, CudaRealArray>)
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

    DeviceOutputBundle make_device_bundle(const spectral_api::CudaStftResult &result)
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

    DeviceOutputBundle make_device_bundle(const spectral_api::CudaIstftResult &result)
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

    DeviceOutputBundle make_device_bundle(const spectral_api::CudaVectorStrengthResult &result)
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
            (void)cusignal::cuda_backend::spectral_test_hooks::consume_last_kernel_ms();
        }
        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            callable();
            durations.push_back(cusignal::cuda_backend::spectral_test_hooks::consume_last_kernel_ms());
        }
        return compute_timing_stats(durations);
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
        if (test_case.generated_x.has_value())
        {
            return *test_case.generated_x;
        }
        return load_real_array(test_case.x_file, test_case.x_shape);
    }

    RealArray load_y_array(const SpectralCase &test_case)
    {
        if (test_case.generated_y.has_value())
        {
            return *test_case.generated_y;
        }
        return load_real_array(test_case.y_file, test_case.y_shape);
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
        if (test_case.generated_x.has_value())
        {
            return test_case.generated_x->values;
        }
        return read_real_csv(test_case.x_file);
    }

    RealSignal load_y_signal(const SpectralCase &test_case)
    {
        if (test_case.generated_y.has_value())
        {
            return test_case.generated_y->values;
        }
        return read_real_csv(test_case.y_file);
    }

    RealSignal load_freqs(const SpectralCase &test_case)
    {
        if (test_case.generated_freqs.has_value())
        {
            return *test_case.generated_freqs;
        }
        return read_real_csv(test_case.freqs_file);
    }

    RealSignal load_events(const SpectralCase &test_case)
    {
        if (test_case.generated_events.has_value())
        {
            return *test_case.generated_events;
        }
        return read_real_csv(test_case.events_file);
    }

    RealSignal load_periods(const SpectralCase &test_case)
    {
        if (test_case.generated_periods.has_value())
        {
            return *test_case.generated_periods;
        }
        return read_real_csv(test_case.period_file);
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::lombscargle(
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::periodogram(
                        load_x_array(test_case),
                        test_case.fs,
                        to_cuda_window_spec(test_case.window),
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::welch(
                        load_x_array(test_case),
                        test_case.fs,
                        to_cuda_window_spec(test_case.window),
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::csd(
                        load_x_array(test_case),
                        load_y_array(test_case),
                        test_case.fs,
                        to_cuda_window_spec(test_case.window),
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::spectrogram(
                        load_x_array(test_case),
                        test_case.fs,
                        to_cuda_window_spec(test_case.window),
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::stft(
                        load_x_array(test_case),
                        test_case.fs,
                        to_cuda_window_spec(test_case.window),
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::istft(
                        load_zxx(test_case),
                        test_case.fs,
                        to_cuda_window_spec(test_case.window),
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::coherence(
                        load_x_array(test_case),
                        load_y_array(test_case),
                        test_case.fs,
                        to_cuda_window_spec(test_case.window),
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
                        return make_device_bundle(cusignal::cuda_backend::spectral::vectorstrength(
                            load_events(test_case),
                            test_case.period_scalar));
                    }
                    return make_device_bundle(cusignal::cuda_backend::spectral::vectorstrength(
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
            std::cout << "cpu_perf_ms   : median=n/a  mean=n/a  p95=n/a\n";
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
            std::cout << "gpu_perf_ms   : e2e_median=n/a  kernel_median=n/a  p95=n/a  e2e_speedup=n/a  kernel_speedup=n/a\n";
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

        const OutputBundle cpu_output = runner.cpu(test_case);
        const OutputBundle gpu_output = materialize(runner.gpu(test_case));
        const OutputBundle expected = load_expected_bundle(op, test_case);
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

        std::optional<CudaRealArray> csd_x;
        std::optional<CudaRealArray> csd_y;
        if (op == "csd")
        {
            csd_x.emplace(CudaRealArray::from_host(load_x_array(test_case)));
            csd_y.emplace(CudaRealArray::from_host(load_y_array(test_case)));
        }
        std::optional<CudaRealArray> spectral_x;
        if (op == "spectrogram" || op == "stft")
        {
            const RealArray x = load_x_array(test_case);
            report.samples = x.values.size();
            spectral_x.emplace(CudaRealArray::from_host(x));
        }
        std::optional<CudaRealSignal> vectorstrength_events;
        std::optional<RealSignal> vectorstrength_periods;
        if (op == "vectorstrength")
        {
            const RealSignal events = load_events(test_case);
            report.samples = events.size();
            vectorstrength_events.emplace(CudaRealSignal::from_host(events));
            if (!(test_case.period_scalar > 0.0))
            {
                vectorstrength_periods.emplace(load_periods(test_case));
            }
        }
        auto run_gpu_perf = [&]() -> DeviceOutputBundle {
            if (csd_x.has_value() && csd_y.has_value())
            {
                return make_device_bundle(cusignal::cuda_backend::spectral::csd(
                    *csd_x,
                    *csd_y,
                    test_case.fs,
                    to_cuda_window_spec(test_case.window),
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
                    return make_device_bundle(cusignal::cuda_backend::spectral::vectorstrength(
                        *vectorstrength_events,
                        test_case.period_scalar));
                }
                return make_device_bundle(cusignal::cuda_backend::spectral::vectorstrength(
                    *vectorstrength_events,
                    *vectorstrength_periods));
            }
            if (op == "spectrogram" && spectral_x.has_value())
            {
                return make_device_bundle(cusignal::cuda_backend::spectral::spectrogram(
                    *spectral_x,
                    test_case.fs,
                    to_cuda_window_spec(test_case.window),
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
                return make_device_bundle(cusignal::cuda_backend::spectral::stft(
                    *spectral_x,
                    test_case.fs,
                    to_cuda_window_spec(test_case.window),
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
            cusignal::core::throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
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
