#include "radartools_test_support.hpp"

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
#include "../../../include/cusignal/radartools/radartools.hpp"
#include "../../../src/common/radartools_detail.hpp"
#include "../common/live_perf.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace radartools_test_hooks
        {
            float consume_last_kernel_ms();
        }
    } // namespace zx_gpu_backend
} // namespace cusignal

namespace
{
    namespace radartools_api = cusignal::radartools_api;
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::Float16;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    using cusignal::core::NamedFloatPairParameter;
    using cusignal::core::NamedFloatParameter;
    using cusignal::core::NamedTaylorParameter;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
    using cusignal::core::WindowSpec;
    namespace detail = cusignal::radartools_detail;
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

    struct RadarCase
    {
        std::string id;
        std::string category;
        Shape x_shape;
        Shape templ_shape;
        Shape y_shape;
        Shape sv_shape;
        int nfft = 0; // pulse_doppler / ambiguity 处理的 FFT 长度
        bool normalize = false; // 是否对模糊函数输出做归一化
        bool calc_cov = true; // 是否在 mvdr 中计算协方差矩阵
        float fs = 1.0; // 距离/频率轴使用的采样频率
        float prf = 1.0; // 多普勒轴使用的脉冲重复频率
        std::string cut = "2d"; // 模糊函数切片模式：2d / delay / doppler
        float cut_value = 0.0; // 一维模糊函数切片时的切片坐标
        float pfa = 1e-3; // CFAR 目标虚警率
        int cells = 0; // 1D CA-CFAR 的对称训练/参考单元数
        int guard_cells = 0; // CFAR 中 CUT 周围的保护单元数
        int reference_cells = 0; // 用于噪声估计的参考单元数
        Shape guard_shape;
        Shape reference_shape;
        WindowSpec window = std::string();
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        std::string dtype = "float32"; // 兼容路径 dtype；float16 用例按 FP16 量化后比较

        fs::path x_file;
        fs::path templ_file;
        fs::path y_file;
        fs::path sv_file;

        fs::path expected_signal_file;
        fs::path expected_values_file;
        fs::path expected_axis_file;
        fs::path expected_delay_axis_file;
        fs::path expected_doppler_axis_file;
        fs::path expected_threshold_file;
        fs::path expected_detections_file;
        fs::path expected_value_file;

        std::optional<ComplexArray> generated_complex_x;
        std::optional<ComplexSignal> generated_template;
        std::optional<ComplexSignal> generated_y;
        std::optional<RealArray> generated_real_x;
        std::optional<ComplexArray> generated_sv;
    };

    using CpuRunner = std::function<OutputBundle(const RadarCase &)>;
    using GpuRunner = std::function<DeviceOutputBundle(const RadarCase &)>;

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
        return repo_root() / "data" / "reference" / "unit" / "radartools" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return cusignal_test::live_perf::generated_unit_root(
                   repo_root() / "data" / "generated" / "unit") /
               "radartools" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "radartools" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "radartools";
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
                    stream << "{\"kind\":\"string\",\"value\":\"" << cusignal_test::report::json_escape(value) << "\"}";
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
                return stream.str();
            },
            spec);
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

    RealArray apply_dtype_quantization(const RealArray &array, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return array;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported radartools dtype compatibility case: " + dtype);
        }
        RealArray quantized = array;
        for (float &value : quantized.values)
        {
            value = quantize_float16(value);
        }
        return quantized;
    }

    OutputBundle apply_dtype_quantization(const OutputBundle &bundle, const std::string &dtype)
    {
        if (dtype == "float32")
        {
            return bundle;
        }
        if (dtype != "float16")
        {
            throw std::runtime_error("unsupported radartools dtype compatibility case: " + dtype);
        }
        OutputBundle quantized = bundle;
        for (OutputField &field : quantized.fields)
        {
            if (field.kind != FieldKind::ComplexArray)
            {
                for (float &value : field.real_values)
                {
                    value = quantize_float16(value);
                }
            }
        }
        return quantized;
    }

    ComplexArray load_complex_array(const fs::path &path, const Shape &shape)
    {
        return make_complex_array_from_flat(shape, read_complex_csv(path));
    }

    ComplexSignal load_complex_signal(const fs::path &path)
    {
        return read_complex_csv(path);
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

    ComplexSignal generate_complex_signal_tone(
        std::size_t length,
        float freq,
        float phase,
        float amplitude)
    {
        ComplexSignal values(length, Complex(0.0, 0.0));
        for (std::size_t index = 0; index < length; ++index)
        {
            const float angle = phase + freq * static_cast<float>(index);
            values[index] = amplitude * Complex(std::cos(angle), std::sin(angle));
        }
        return values;
    }

    ComplexArray generate_complex_matrix_tone(
        const Shape &shape,
        float freq_row,
        float freq_col,
        float phase,
        float amplitude)
    {
        if (shape.size() != 2)
        {
            throw std::runtime_error("complex_matrix_tone expects rank-2 shape");
        }
        ComplexArray output = cusignal::core::make_complex_array(shape);
        const std::size_t rows = shape[0];
        const std::size_t cols = shape[1];
        for (std::size_t row = 0; row < rows; ++row)
        {
            for (std::size_t col = 0; col < cols; ++col)
            {
                const float angle = phase +
                                     freq_row * static_cast<float>(row) +
                                     freq_col * static_cast<float>(col);
                output.values[row * cols + col] =
                    amplitude * Complex(std::cos(angle), std::sin(angle));
            }
        }
        return output;
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
                const float cross = 0.071 * static_cast<float>((row + 1) * (col + 2));
                const float real =
                    std::cos(base) +
                    0.31 * std::sin(cross) +
                    0.05 * static_cast<float>(row % 3) -
                    0.03 * static_cast<float>(col % 5);
                const float imag =
                    std::sin(base) +
                    0.23 * std::cos(cross) -
                    0.04 * static_cast<float>(row % 4) +
                    0.02 * static_cast<float>(col % 7);
                output.values[row * cols + col] =
                    amplitude * Complex(real, imag);
            }
        }
        return output;
    }

    RealArray generate_real_vector_pattern(
        std::size_t length,
        float scale,
        float bias,
        int spike_index,
        float spike_value)
    {
        RealArray output = cusignal::core::make_real_array(Shape{length});
        for (std::size_t index = 0; index < length; ++index)
        {
            output.values[index] =
                bias + scale * (std::sin(0.1 * static_cast<float>(index)) +
                                0.25 * std::cos(0.03 * static_cast<float>(index)));
        }
        if (spike_index >= 0 && spike_index < static_cast<int>(length))
        {
            output.values[static_cast<std::size_t>(spike_index)] += spike_value;
        }
        return output;
    }

    RealArray generate_real_matrix_pattern(
        const Shape &shape,
        float scale,
        float bias,
        int spike_row,
        int spike_col,
        float spike_value)
    {
        if (shape.size() != 2)
        {
            throw std::runtime_error("real_matrix_pattern expects rank-2 shape");
        }
        RealArray output = cusignal::core::make_real_array(shape);
        const std::size_t rows = shape[0];
        const std::size_t cols = shape[1];
        for (std::size_t row = 0; row < rows; ++row)
        {
            for (std::size_t col = 0; col < cols; ++col)
            {
                output.values[row * cols + col] =
                    bias + scale * (std::sin(0.05 * static_cast<float>(row)) +
                                    std::cos(0.07 * static_cast<float>(col)) +
                                    0.1 * static_cast<float>((row + col) % 5));
            }
        }
        if (spike_row >= 0 && spike_col >= 0 &&
            spike_row < static_cast<int>(rows) && spike_col < static_cast<int>(cols))
        {
            output.values[static_cast<std::size_t>(spike_row) * cols + static_cast<std::size_t>(spike_col)] += spike_value;
        }
        return output;
    }

    ComplexArray generate_steering_vector(
        std::size_t length,
        float phase_step,
        float phase,
        bool column_vector)
    {
        const Shape shape = column_vector ? Shape{length, 1} : Shape{length};
        ComplexArray output = cusignal::core::make_complex_array(shape);
        for (std::size_t index = 0; index < length; ++index)
        {
            const float angle = phase + phase_step * static_cast<float>(index);
            output.values[index] = Complex(std::cos(angle), std::sin(angle));
        }
        return output;
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
        if (kind == "complex_matrix_tone")
        {
            const Shape shape = json_array_to_shape(spec.at("shape"));
            return generate_complex_matrix_tone(
                shape,
                get_optional_number(spec, "freq_row", 0.1),
                get_optional_number(spec, "freq_col", 0.2),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0));
        }
        if (kind == "complex_matrix_pattern")
        {
            const Shape shape = json_array_to_shape(spec.at("shape"));
            return generate_complex_matrix_pattern(
                shape,
                get_optional_number(spec, "freq_row", 0.1),
                get_optional_number(spec, "freq_col", 0.2),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0));
        }
        if (kind == "complex_signal_tone")
        {
            const ComplexSignal values = generate_complex_signal_tone(
                static_cast<std::size_t>(get_optional_int(spec, "length", 0)),
                get_optional_number(spec, "freq", 0.1),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0));
            ComplexArray output = cusignal::core::make_complex_array(Shape{values.size()});
            output.values = values;
            return output;
        }
        if (kind == "steering_vector")
        {
            return generate_steering_vector(
                static_cast<std::size_t>(get_optional_int(spec, "length", 0)),
                get_optional_number(spec, "phase_step", 0.0),
                get_optional_number(spec, "phase", 0.0),
                get_optional_bool(spec, "column_vector", true));
        }
        throw std::runtime_error("unsupported complex array generator kind");
    }

    std::optional<ComplexSignal> parse_complex_signal_generator(const JsonObject &object, const std::string &key)
    {
        const auto iter = object.find(key);
        if (iter == object.end())
        {
            return std::nullopt;
        }
        const JsonObject &spec = as_object(iter->second);
        const std::string kind = get_string(spec, "kind");
        if (kind == "complex_signal_tone")
        {
            return generate_complex_signal_tone(
                static_cast<std::size_t>(get_optional_int(spec, "length", 0)),
                get_optional_number(spec, "freq", 0.1),
                get_optional_number(spec, "phase", 0.0),
                get_optional_number(spec, "amplitude", 1.0));
        }
        throw std::runtime_error("unsupported complex signal generator kind");
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
        if (kind == "real_vector_pattern")
        {
            return generate_real_vector_pattern(
                static_cast<std::size_t>(get_optional_int(spec, "length", 0)),
                get_optional_number(spec, "scale", 1.0),
                get_optional_number(spec, "bias", 0.0),
                get_optional_int(spec, "spike_index", -1),
                get_optional_number(spec, "spike_value", 0.0));
        }
        if (kind == "real_matrix_pattern")
        {
            return generate_real_matrix_pattern(
                json_array_to_shape(spec.at("shape")),
                get_optional_number(spec, "scale", 1.0),
                get_optional_number(spec, "bias", 0.0),
                get_optional_int(spec, "spike_row", -1),
                get_optional_int(spec, "spike_col", -1),
                get_optional_number(spec, "spike_value", 0.0));
        }
        throw std::runtime_error("unsupported real array generator kind");
    }

    OutputBundle make_bundle(const ComplexArray &values, const std::string &name = "signal")
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{name, FieldKind::ComplexArray, values.shape, {}, values.values});
        return bundle;
    }

    OutputBundle make_bundle(float value)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"value", FieldKind::RealSignal, Shape{1}, RealSignal{value}, {}});
        return bundle;
    }

    OutputBundle make_bundle(const radartools_api::CfarResult &result)
    {
        OutputBundle bundle;
        bundle.fields.push_back(OutputField{"threshold", FieldKind::RealArray, result.threshold.shape, result.threshold.values, {}});
        bundle.fields.push_back(OutputField{"detections", FieldKind::RealArray, result.detections.shape, result.detections.values, {}});
        return bundle;
    }

    OutputBundle make_bundle(const radartools_api::AmbgfunResult &result)
    {
        OutputBundle bundle;
        std::visit(
            [&](const auto &value) {
                using T = std::decay_t<decltype(value)>;
                if constexpr (std::is_same_v<T, radartools_api::AmbgfunCutResult>)
                {
                    bundle.fields.push_back(OutputField{"values", FieldKind::RealSignal, Shape{value.values.size()}, value.values, {}});
                    bundle.fields.push_back(OutputField{"axis", FieldKind::RealSignal, Shape{value.axis.size()}, value.axis, {}});
                }
                else
                {
                    bundle.fields.push_back(OutputField{"values", FieldKind::RealArray, value.values.shape, value.values.values, {}});
                    bundle.fields.push_back(OutputField{"delay_axis", FieldKind::RealSignal, Shape{value.delay_axis.size()}, value.delay_axis, {}});
                    bundle.fields.push_back(OutputField{"doppler_axis", FieldKind::RealSignal, Shape{value.doppler_axis.size()}, value.doppler_axis, {}});
                }
            },
            result);
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const ZxGpuComplexArray &values, const std::string &name = "signal")
    {
        DeviceOutputBundle bundle;
        DeviceOutputField field;
        field.name = name;
        field.kind = FieldKind::ComplexArray;
        field.shape = values.shape();
        field.complex_array = values;
        bundle.fields.push_back(std::move(field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(float value)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField field;
        field.name = "value";
        field.kind = FieldKind::RealSignal;
        field.shape = Shape{1};
        field.real_signal = ZxGpuRealSignal::from_host(RealSignal{value});
        bundle.fields.push_back(std::move(field));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const radartools_api::ZxGpuCfarResult &result)
    {
        DeviceOutputBundle bundle;
        DeviceOutputField threshold;
        threshold.name = "threshold";
        threshold.kind = FieldKind::RealArray;
        threshold.shape = result.threshold.shape();
        threshold.real_array = result.threshold;
        bundle.fields.push_back(std::move(threshold));
        DeviceOutputField detections;
        detections.name = "detections";
        detections.kind = FieldKind::RealArray;
        detections.shape = result.detections.shape();
        detections.real_array = result.detections;
        bundle.fields.push_back(std::move(detections));
        return bundle;
    }

    DeviceOutputBundle make_device_bundle(const radartools_api::ZxGpuAmbgfunResult &result)
    {
        DeviceOutputBundle bundle;
        std::visit(
            [&](const auto &value) {
                using T = std::decay_t<decltype(value)>;
                if constexpr (std::is_same_v<T, radartools_api::ZxGpuAmbgfunCutResult>)
                {
                    DeviceOutputField values_field;
                    values_field.name = "values";
                    values_field.kind = FieldKind::RealSignal;
                    values_field.shape = Shape{value.values.size()};
                    values_field.real_signal = value.values;
                    bundle.fields.push_back(std::move(values_field));

                    DeviceOutputField axis_field;
                    axis_field.name = "axis";
                    axis_field.kind = FieldKind::RealSignal;
                    axis_field.shape = Shape{value.axis.size()};
                    axis_field.real_signal = value.axis;
                    bundle.fields.push_back(std::move(axis_field));
                }
                else
                {
                    DeviceOutputField values_field;
                    values_field.name = "values";
                    values_field.kind = FieldKind::RealArray;
                    values_field.shape = value.values.shape();
                    values_field.real_array = value.values;
                    bundle.fields.push_back(std::move(values_field));

                    DeviceOutputField delay_field;
                    delay_field.name = "delay_axis";
                    delay_field.kind = FieldKind::RealSignal;
                    delay_field.shape = Shape{value.delay_axis.size()};
                    delay_field.real_signal = value.delay_axis;
                    bundle.fields.push_back(std::move(delay_field));

                    DeviceOutputField doppler_field;
                    doppler_field.name = "doppler_axis";
                    doppler_field.kind = FieldKind::RealSignal;
                    doppler_field.shape = Shape{value.doppler_axis.size()};
                    doppler_field.real_signal = value.doppler_axis;
                    bundle.fields.push_back(std::move(doppler_field));
                }
            },
            result);
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

    ErrorMetrics compute_real_error(const Shape &lhs_shape, const RealSignal &lhs, const Shape &rhs_shape, const RealSignal &rhs)
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

    ErrorMetrics compute_complex_error(const Shape &lhs_shape, const ComplexSignal &lhs, const Shape &rhs_shape, const ComplexSignal &rhs)
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
            throw std::runtime_error("field count mismatch while comparing radartools outputs");
        }
        std::vector<ErrorMetrics> all_metrics;
        for (std::size_t index = 0; index < lhs.fields.size(); ++index)
        {
            const OutputField &lhs_field = lhs.fields[index];
            const OutputField &rhs_field = rhs.fields[index];
            if (lhs_field.name != rhs_field.name || lhs_field.kind != rhs_field.kind)
            {
                throw std::runtime_error("field mismatch while comparing radartools outputs");
            }
            if (lhs_field.kind == FieldKind::ComplexArray)
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

    bool field_within_tolerance(const OutputField &actual, const OutputField &expected, float atol, float rtol)
    {
        if (actual.kind != expected.kind || actual.shape != expected.shape)
        {
            return false;
        }
        const float effective_atol = std::max(atol, 1.0e-5f);
        const float effective_rtol = std::max(rtol, 1.0e-5f);
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
            (void)cusignal::zx_gpu_backend::radartools_test_hooks::consume_last_kernel_ms();
        }
        std::vector<float> durations;
        durations.reserve(static_cast<std::size_t>(options.repeat));
        for (int repeat = 0; repeat < options.repeat; ++repeat)
        {
            callable();
            durations.push_back(cusignal::zx_gpu_backend::radartools_test_hooks::consume_last_kernel_ms());
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

    std::size_t resolved_nfft(const std::string &op, const RadarCase &test_case)
    {
        if (test_case.nfft > 0)
        {
            return static_cast<std::size_t>(test_case.nfft);
        }
        if (op == "pulse_compression")
        {
            return test_case.x_shape.at(1);
        }
        if (op == "pulse_doppler")
        {
            return test_case.x_shape.at(0);
        }
        return 0;
    }

    Shape signal_shape(std::size_t size)
    {
        return Shape{size};
    }

    std::vector<RadarCase> load_radartools_cases(const fs::path &manifest_path, const std::string &category)
    {
        std::vector<RadarCase> cases;
        const JsonValue manifest = cusignal_test::json::parse(
            cusignal_test::report::read_text_file(manifest_path));
        const JsonObject &root = as_object(manifest);
        const JsonArray &case_array =
            as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();

        for (const JsonValue &item : case_array)
        {
            const JsonObject &object = as_object(item);
            RadarCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.nfft = get_optional_int(object, "nfft", 0); // FFT 长度
            test_case.normalize = get_optional_bool(object, "normalize", false); // 模糊函数归一化开关
            test_case.calc_cov = get_optional_bool(object, "calc_cov", true); // mvdr 协方差计算开关
            test_case.fs = get_optional_number(object, "fs", 1.0); // 采样频率
            test_case.prf = get_optional_number(object, "prf", 1.0); // 脉冲重复频率
            test_case.cut = get_optional_string(object, "cut").value_or("2d"); // 模糊函数切片选择
            test_case.cut_value = get_optional_number(object, "cut_value", 0.0); // 切片坐标
            test_case.pfa = get_optional_number(object, "pfa", 1e-3); // 虚警概率
            test_case.cells = get_optional_int(object, "cells", 0); // 1D CFAR 参考单元数
            test_case.guard_cells = get_optional_int(object, "guard_cells", 0); // CFAR 保护单元数
            test_case.reference_cells = get_optional_int(object, "reference_cells", 0); // CFAR 参考单元数
            test_case.atol = get_optional_number(object, "atol", 0.0); // 绝对误差容限
            test_case.rtol = get_optional_number(object, "rtol", 0.0); // 相对误差容限
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // 兼容 dtype
            if (const auto iter = object.find("x_shape"); iter != object.end()) test_case.x_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("templ_shape"); iter != object.end()) test_case.templ_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("y_shape"); iter != object.end()) test_case.y_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("sv_shape"); iter != object.end()) test_case.sv_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("guard_shape"); iter != object.end()) test_case.guard_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("reference_shape"); iter != object.end()) test_case.reference_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("window"); iter != object.end()) test_case.window = parse_window_spec(iter->second);
            if (auto v = get_optional_string(object, "x_file")) test_case.x_file = base / *v;
            if (auto v = get_optional_string(object, "templ_file")) test_case.templ_file = base / *v;
            if (auto v = get_optional_string(object, "y_file")) test_case.y_file = base / *v;
            if (auto v = get_optional_string(object, "sv_file")) test_case.sv_file = base / *v;
            if (auto v = get_optional_string(object, "expected_signal_file")) test_case.expected_signal_file = base / *v;
            if (auto v = get_optional_string(object, "expected_values_file")) test_case.expected_values_file = base / *v;
            if (auto v = get_optional_string(object, "expected_axis_file")) test_case.expected_axis_file = base / *v;
            if (auto v = get_optional_string(object, "expected_delay_axis_file")) test_case.expected_delay_axis_file = base / *v;
            if (auto v = get_optional_string(object, "expected_doppler_axis_file")) test_case.expected_doppler_axis_file = base / *v;
            if (auto v = get_optional_string(object, "expected_threshold_file")) test_case.expected_threshold_file = base / *v;
            if (auto v = get_optional_string(object, "expected_detections_file")) test_case.expected_detections_file = base / *v;
            if (auto v = get_optional_string(object, "expected_value_file")) test_case.expected_value_file = base / *v;

            if (category == "perf")
            {
                test_case.generated_complex_x = parse_complex_array_generator(object, "x_generator");
                test_case.generated_template = parse_complex_signal_generator(object, "templ_generator");
                test_case.generated_y = parse_complex_signal_generator(object, "y_generator");
                test_case.generated_real_x = parse_real_array_generator(object, "real_x_generator");
                test_case.generated_sv = parse_complex_array_generator(object, "sv_generator");
                if (test_case.generated_complex_x.has_value() && test_case.x_shape.empty())
                {
                    test_case.x_shape = test_case.generated_complex_x->shape;
                }
                if (test_case.generated_template.has_value() && test_case.templ_shape.empty())
                {
                    test_case.templ_shape = Shape{test_case.generated_template->size()};
                }
                if (test_case.generated_y.has_value() && test_case.y_shape.empty())
                {
                    test_case.y_shape = Shape{test_case.generated_y->size()};
                }
                if (test_case.generated_real_x.has_value() && test_case.x_shape.empty())
                {
                    test_case.x_shape = test_case.generated_real_x->shape;
                }
                if (test_case.generated_sv.has_value() && test_case.sv_shape.empty())
                {
                    test_case.sv_shape = test_case.generated_sv->shape;
                }
            }
            cases.push_back(std::move(test_case));
        }
        return cases;
    }

    ComplexArray load_complex_array_x(const RadarCase &test_case)
    {
        if (test_case.generated_complex_x.has_value())
        {
            return *test_case.generated_complex_x;
        }
        return load_complex_array(test_case.x_file, test_case.x_shape);
    }

    ComplexSignal load_complex_signal_x(const RadarCase &test_case)
    {
        if (test_case.generated_complex_x.has_value())
        {
            return test_case.generated_complex_x->values;
        }
        return read_complex_csv(test_case.x_file);
    }

    ComplexSignal load_template(const RadarCase &test_case)
    {
        if (test_case.generated_template.has_value())
        {
            return *test_case.generated_template;
        }
        return read_complex_csv(test_case.templ_file);
    }

    ComplexSignal load_y_signal(const RadarCase &test_case)
    {
        if (test_case.generated_y.has_value())
        {
            return *test_case.generated_y;
        }
        return read_complex_csv(test_case.y_file);
    }

    RealArray load_real_array_x(const RadarCase &test_case)
    {
        RealArray array;
        if (test_case.generated_real_x.has_value())
        {
            array = *test_case.generated_real_x;
        }
        else
        {
            array = load_real_array(test_case.x_file, test_case.x_shape);
        }
        return apply_dtype_quantization(array, test_case.dtype);
    }

    ComplexArray load_sv(const RadarCase &test_case)
    {
        if (test_case.generated_sv.has_value())
        {
            return *test_case.generated_sv;
        }
        return load_complex_array(test_case.sv_file, test_case.sv_shape);
    }

    Runner resolve_runner(const std::string &op)
    {
        if (op == "pulse_compression")
        {
            return Runner{
                [](const RadarCase &test_case) {
                    return make_bundle(cusignal::cpu::radartools::pulse_compression(
                        load_complex_array_x(test_case),
                        load_template(test_case),
                        test_case.normalize,
                        test_case.window,
                        test_case.nfft));
                },
                [](const RadarCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::pulse_compression(
                        load_complex_array_x(test_case),
                        load_template(test_case),
                        test_case.normalize,
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nfft));
                }};
        }
        if (op == "pulse_doppler")
        {
            return Runner{
                [](const RadarCase &test_case) {
                    return make_bundle(cusignal::cpu::radartools::pulse_doppler(
                        load_complex_array_x(test_case),
                        test_case.window,
                        test_case.nfft));
                },
                [](const RadarCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::pulse_doppler(
                        load_complex_array_x(test_case),
                        to_zx_gpu_window_spec(test_case.window),
                        test_case.nfft));
                }};
        }
        if (op == "ambgfun")
        {
            return Runner{
                [](const RadarCase &test_case) {
                    if (!test_case.y_file.empty() || test_case.generated_y.has_value())
                    {
                        return make_bundle(cusignal::cpu::radartools::ambgfun(
                            load_complex_signal_x(test_case),
                            load_y_signal(test_case),
                            test_case.fs,
                            test_case.prf,
                            test_case.cut,
                            test_case.cut_value));
                    }
                    return make_bundle(cusignal::cpu::radartools::ambgfun(
                        load_complex_signal_x(test_case),
                        test_case.fs,
                        test_case.prf,
                        test_case.cut,
                        test_case.cut_value));
                },
                [](const RadarCase &test_case) {
                    if (!test_case.y_file.empty() || test_case.generated_y.has_value())
                    {
                        return make_device_bundle(cusignal::zx_gpu_backend::radartools::ambgfun(
                            load_complex_signal_x(test_case),
                            load_y_signal(test_case),
                            test_case.fs,
                            test_case.prf,
                            test_case.cut,
                            test_case.cut_value));
                    }
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::ambgfun(
                        load_complex_signal_x(test_case),
                        test_case.fs,
                        test_case.prf,
                        test_case.cut,
                        test_case.cut_value));
                }};
        }
        if (op == "cfar_alpha")
        {
            return Runner{
                [](const RadarCase &test_case) {
                    return make_bundle(cusignal::cpu::radartools::cfar_alpha(test_case.pfa, test_case.cells));
                },
                [](const RadarCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::cfar_alpha(test_case.pfa, test_case.cells));
                }};
        }
        if (op == "ca_cfar")
        {
            return Runner{
                [](const RadarCase &test_case) {
                    if (!test_case.guard_shape.empty())
                    {
                        return make_bundle(cusignal::cpu::radartools::ca_cfar(
                            load_real_array_x(test_case),
                            test_case.guard_shape,
                            test_case.reference_shape,
                            test_case.pfa));
                    }
                    return make_bundle(cusignal::cpu::radartools::ca_cfar(
                        load_real_array_x(test_case),
                        test_case.guard_cells,
                        test_case.reference_cells,
                        test_case.pfa));
                },
                [](const RadarCase &test_case) {
                    if (!test_case.guard_shape.empty())
                    {
                        return make_device_bundle(cusignal::zx_gpu_backend::radartools::ca_cfar(
                            load_real_array_x(test_case),
                            test_case.guard_shape,
                            test_case.reference_shape,
                            test_case.pfa));
                    }
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::ca_cfar(
                        load_real_array_x(test_case),
                        test_case.guard_cells,
                        test_case.reference_cells,
                        test_case.pfa));
                }};
        }
        if (op == "mvdr")
        {
            return Runner{
                [](const RadarCase &test_case) {
                    return make_bundle(cusignal::cpu::radartools::mvdr(
                        load_complex_array_x(test_case),
                        load_sv(test_case),
                        test_case.calc_cov));
                },
                [](const RadarCase &test_case) {
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::mvdr(
                        load_complex_array_x(test_case),
                        load_sv(test_case),
                        test_case.calc_cov));
                }};
        }
        throw std::runtime_error("unsupported radartools operator: " + op);
    }

    OutputBundle load_expected_bundle(const std::string &op, const RadarCase &test_case)
    {
        if (op == "pulse_compression")
        {
            return make_bundle(load_complex_array(
                test_case.expected_signal_file,
                Shape{test_case.x_shape[0], resolved_nfft(op, test_case)}));
        }
        if (op == "pulse_doppler")
        {
            return make_bundle(load_complex_array(
                test_case.expected_signal_file,
                Shape{resolved_nfft(op, test_case), test_case.x_shape[1]}));
        }
        if (op == "ambgfun")
        {
            if (test_case.cut == "2d")
            {
                OutputBundle bundle;
                const std::size_t rows = test_case.x_shape[0] + (test_case.y_shape.empty() ? test_case.x_shape[0] : test_case.y_shape[0]) - 1;
                const std::size_t cols = static_cast<std::size_t>(detail::next_power_of_two(static_cast<int>(rows)));
                bundle.fields.push_back(OutputField{"values", FieldKind::RealArray, Shape{rows, cols}, read_real_csv(test_case.expected_values_file), {}});
                bundle.fields.push_back(OutputField{"delay_axis", FieldKind::RealSignal, signal_shape(rows), read_real_csv(test_case.expected_delay_axis_file), {}});
                bundle.fields.push_back(OutputField{"doppler_axis", FieldKind::RealSignal, signal_shape(cols), read_real_csv(test_case.expected_doppler_axis_file), {}});
                return bundle;
            }
            const std::size_t xlen = test_case.x_shape[0];
            const std::size_t ylen = test_case.y_shape.empty() ? xlen : test_case.y_shape[0];
            const std::size_t values_len = test_case.cut == "delay"
                                               ? static_cast<std::size_t>(detail::next_power_of_two(static_cast<int>(xlen + ylen - 1)))
                                               : (xlen + ylen - 1);
            OutputBundle bundle;
            bundle.fields.push_back(OutputField{"values", FieldKind::RealSignal, signal_shape(values_len), read_real_csv(test_case.expected_values_file), {}});
            bundle.fields.push_back(OutputField{"axis", FieldKind::RealSignal, signal_shape(values_len), read_real_csv(test_case.expected_axis_file), {}});
            return bundle;
        }
        if (op == "cfar_alpha")
        {
            OutputBundle bundle;
            bundle.fields.push_back(OutputField{"value", FieldKind::RealSignal, signal_shape(1), read_real_csv(test_case.expected_value_file), {}});
            return bundle;
        }
        if (op == "ca_cfar")
        {
            OutputBundle bundle;
            bundle.fields.push_back(OutputField{"threshold", FieldKind::RealArray, test_case.x_shape, read_real_csv(test_case.expected_threshold_file), {}});
            bundle.fields.push_back(OutputField{"detections", FieldKind::RealArray, test_case.x_shape, read_real_csv(test_case.expected_detections_file), {}});
            return bundle;
        }
        if (op == "mvdr")
        {
            return make_bundle(load_complex_array(test_case.expected_signal_file, test_case.sv_shape));
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

    std::string build_case_spec_json(const std::string &op, const RadarCase &test_case)
    {
        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"operator\": \"" << cusignal_test::report::json_escape(op) << "\",\n";
        stream << "  \"id\": \"" << cusignal_test::report::json_escape(test_case.id) << "\",\n";
        stream << "  \"nfft\": " << test_case.nfft << ",\n";
        stream << "  \"normalize\": " << (test_case.normalize ? "true" : "false") << ",\n";
        stream << "  \"calc_cov\": " << (test_case.calc_cov ? "true" : "false") << ",\n";
        stream << "  \"fs\": " << test_case.fs << ",\n";
        stream << "  \"prf\": " << test_case.prf << ",\n";
        stream << "  \"cut\": \"" << cusignal_test::report::json_escape(test_case.cut) << "\",\n";
        stream << "  \"cut_value\": " << test_case.cut_value << ",\n";
        stream << "  \"pfa\": " << test_case.pfa << ",\n";
        stream << "  \"cells\": " << test_case.cells << ",\n";
        stream << "  \"guard_cells\": " << test_case.guard_cells << ",\n";
        stream << "  \"reference_cells\": " << test_case.reference_cells << ",\n";
        stream << "  \"dtype\": \"" << cusignal_test::report::json_escape(test_case.dtype) << "\"";
        if (!detail::window_disabled(test_case.window))
        {
            stream << ",\n  \"window\": " << build_window_spec_json(test_case.window) << '\n';
        }
        else
        {
            stream << '\n';
        }
        stream << "}\n";
        return stream.str();
    }

    void write_input_samples(
        const fs::path &base_dir,
        const std::string &op,
        const RadarCase &test_case,
        std::vector<Artifact> *artifacts)
    {
        fs::create_directories(base_dir);
        const fs::path spec_path = base_dir / (test_case.id + "__spec.json");
        cusignal_test::report::write_text_file(spec_path, build_case_spec_json(op, test_case));
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{"case_spec", spec_path});
        }

        if (op == "pulse_compression" || op == "pulse_doppler")
        {
            if (test_case.generated_complex_x.has_value())
            {
                const fs::path path = base_dir / (test_case.id + "__x.csv");
                write_complex_csv(path, test_case.generated_complex_x->values);
                if (artifacts != nullptr) artifacts->push_back(Artifact{"x_input", path});
            }
        }
        if (op == "pulse_compression")
        {
            const ComplexSignal templ = load_template(test_case);
            const fs::path path = base_dir / (test_case.id + "__template.csv");
            write_complex_csv(path, templ);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"template_input", path});
        }
        if (op == "ambgfun")
        {
            const ComplexSignal x_values = load_complex_signal_x(test_case);
            const fs::path x_path = base_dir / (test_case.id + "__x.csv");
            write_complex_csv(x_path, x_values);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"x_input", x_path});
            if (!test_case.y_file.empty() || test_case.generated_y.has_value())
            {
                const ComplexSignal y_values = load_y_signal(test_case);
                const fs::path y_path = base_dir / (test_case.id + "__y.csv");
                write_complex_csv(y_path, y_values);
                if (artifacts != nullptr) artifacts->push_back(Artifact{"y_input", y_path});
            }
        }
        if (op == "ca_cfar")
        {
            const RealArray input = load_real_array_x(test_case);
            const fs::path path = base_dir / (test_case.id + "__x.csv");
            write_real_csv(path, input.values);
            if (artifacts != nullptr) artifacts->push_back(Artifact{"x_input", path});
        }
        if (op == "mvdr")
        {
            const ComplexArray x_values = load_complex_array_x(test_case);
            const ComplexArray sv_values = load_sv(test_case);
            const fs::path x_path = base_dir / (test_case.id + "__x.csv");
            const fs::path sv_path = base_dir / (test_case.id + "__sv.csv");
            write_complex_csv(x_path, x_values.values);
            write_complex_csv(sv_path, sv_values.values);
            if (artifacts != nullptr)
            {
                artifacts->push_back(Artifact{"x_input", x_path});
                artifacts->push_back(Artifact{"sv_input", sv_path});
            }
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

    std::size_t infer_perf_samples(const std::string &op, const RadarCase &test_case)
    {
        if (op == "pulse_doppler" && test_case.x_shape.size() >= 2)
        {
            return static_cast<std::size_t>(resolved_nfft(op, test_case)) * test_case.x_shape[1];
        }
        if (op == "ambgfun")
        {
            const std::size_t xlen = test_case.x_shape.empty() ? 0 : test_case.x_shape[0];
            const std::size_t ylen = test_case.y_shape.empty() ? xlen : test_case.y_shape[0];
            if (xlen == 0 || ylen == 0)
            {
                return 0;
            }
            const std::size_t rows = xlen + ylen - 1;
            if (test_case.cut == "2d")
            {
                return rows * static_cast<std::size_t>(detail::next_power_of_two(static_cast<int>(rows)));
            }
            return test_case.cut == "delay"
                       ? static_cast<std::size_t>(detail::next_power_of_two(static_cast<int>(rows)))
                       : rows;
        }
        if (!test_case.x_shape.empty())
        {
            std::size_t total = 1;
            for (const std::size_t dim : test_case.x_shape)
            {
                total *= dim;
            }
            return total;
        }
        return 0;
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
                reference_error.max_abs_error = std::max(reference_error.max_abs_error, report.cpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(reference_error.max_rel_error, report.cpu_reference_error->max_rel_error);
                reference_error.rmse = std::max(reference_error.rmse, report.cpu_reference_error->rmse);
            }
            if (report.gpu_reference_error.has_value())
            {
                has_reference_error = true;
                reference_error.max_abs_error = std::max(reference_error.max_abs_error, report.gpu_reference_error->max_abs_error);
                reference_error.max_rel_error = std::max(reference_error.max_rel_error, report.gpu_reference_error->max_rel_error);
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
            "radartools",
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
        cusignal_test::report::update_module_reports("radartools", module_report_root());
    }

    void print_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << "[radartools/" << op << "] "
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
        std::cout << "reports       : data/.reports_staging/unit/radartools/" << op << "/latest_summary.md\n";
    }

    CaseReport make_failed_case_report(const RadarCase &test_case, const std::string &message)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;
        report.pass = false;
        report.note = message;
        return report;
    }

    CaseReport evaluate_accuracy_case(
        const std::string &op,
        const RadarCase &test_case,
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
        report.cpu_gpu_error = compute_bundle_error(cpu_output, gpu_output);
        report.cpu_reference_error = compute_bundle_error(cpu_output, expected);
        report.gpu_reference_error = compute_bundle_error(gpu_output, expected);
        report.pass = bundle_within_tolerance(cpu_output, expected, test_case.atol, test_case.rtol) &&
                      bundle_within_tolerance(gpu_output, expected, test_case.atol, test_case.rtol);
        return report;
    }

    CaseReport evaluate_perf_case(
        const std::string &op,
        const RadarCase &test_case,
        const Runner &runner,
        const CliOptions &options)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;

        std::optional<ZxGpuComplexArray> pulse_compression_x;
        std::optional<ZxGpuComplexSignal> pulse_compression_template;
        if (op == "pulse_compression")
        {
            pulse_compression_x.emplace(ZxGpuComplexArray::from_host(load_complex_array_x(test_case)));
            pulse_compression_template.emplace(ZxGpuComplexSignal::from_host(load_template(test_case)));
        }
        std::optional<ZxGpuComplexArray> pulse_doppler_x;
        if (op == "pulse_doppler")
        {
            pulse_doppler_x.emplace(ZxGpuComplexArray::from_host(load_complex_array_x(test_case)));
        }
        std::optional<ZxGpuRealArray> ca_cfar_x;
        if (op == "ca_cfar")
        {
            ca_cfar_x.emplace(ZxGpuRealArray::from_host(load_real_array_x(test_case)));
        }
        std::optional<ZxGpuComplexSignal> ambgfun_x;
        std::optional<ZxGpuComplexSignal> ambgfun_y;
        if (op == "ambgfun" && options.gpu_only_perf)
        {
            ambgfun_x.emplace(ZxGpuComplexSignal::from_host(load_complex_signal_x(test_case)));
            if (!test_case.y_file.empty() || test_case.generated_y.has_value())
            {
                ambgfun_y.emplace(ZxGpuComplexSignal::from_host(load_y_signal(test_case)));
            }
        }
        auto run_gpu_perf = [&]() -> DeviceOutputBundle {
            if (pulse_compression_x.has_value() && pulse_compression_template.has_value())
            {
                return make_device_bundle(cusignal::zx_gpu_backend::radartools::pulse_compression(
                    *pulse_compression_x,
                    *pulse_compression_template,
                    test_case.normalize,
                    to_zx_gpu_window_spec(test_case.window),
                    test_case.nfft));
            }
            if (pulse_doppler_x.has_value())
            {
                return make_device_bundle(cusignal::zx_gpu_backend::radartools::pulse_doppler(
                    *pulse_doppler_x,
                    to_zx_gpu_window_spec(test_case.window),
                    test_case.nfft));
            }
            if (ca_cfar_x.has_value())
            {
                if (!test_case.guard_shape.empty())
                {
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::ca_cfar(
                        *ca_cfar_x,
                        test_case.guard_shape,
                        test_case.reference_shape,
                        test_case.pfa));
                }
                return make_device_bundle(cusignal::zx_gpu_backend::radartools::ca_cfar(
                    *ca_cfar_x,
                    test_case.guard_cells,
                    test_case.reference_cells,
                    test_case.pfa));
            }
            if (ambgfun_x.has_value())
            {
                if (ambgfun_y.has_value())
                {
                    return make_device_bundle(cusignal::zx_gpu_backend::radartools::ambgfun(
                        *ambgfun_x,
                        *ambgfun_y,
                        test_case.fs,
                        test_case.prf,
                        test_case.cut,
                        test_case.cut_value));
                }
                return make_device_bundle(cusignal::zx_gpu_backend::radartools::ambgfun(
                    *ambgfun_x,
                    test_case.fs,
                    test_case.prf,
                    test_case.cut,
                    test_case.cut_value));
            }
            return runner.gpu(test_case);
        };

        OutputBundle gpu_output;
        if (!options.gpu_only_perf)
        {
            gpu_output = materialize(run_gpu_perf());
            report.samples = sample_count(gpu_output);
        }
        else
        {
            report.samples = infer_perf_samples(op, test_case);
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

    int run_radartools_operator_tests(const std::string &op, int argc, char **argv)
    {
        const CliOptions options = parse_cli(argc, argv);
        const Runner runner = resolve_runner(op);
        std::vector<CaseReport> reports;

        if (include_accuracy_cases(options))
        {
            const auto accuracy_cases = load_radartools_cases(reference_root(op) / "manifest.json", "accuracy");
            for (const RadarCase &test_case : accuracy_cases)
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
            const auto perf_cases = load_radartools_cases(generated_root(op) / "manifest.json", "perf");
            for (const RadarCase &test_case : perf_cases)
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

    bool verify_pulse_host_input_cache_contract()
    {
        ComplexArray input;
        input.shape = Shape{2, 8};
        input.values.resize(16);
        for (std::size_t index = 0; index < input.values.size(); ++index)
        {
            input.values[index] = Complex(
                0.25f * static_cast<float>(index + 1),
                -0.125f * static_cast<float>(index % 5));
        }
        ComplexSignal templ{
            Complex(1.0f, 0.0f),
            Complex(0.5f, -0.25f),
            Complex(-0.25f, 0.5f),
            Complex(0.125f, 0.25f)};

        auto matches_cpu = [&](const ComplexArray &host_input) {
            const ComplexArray expected = cusignal::cpu::radartools::pulse_compression(
                host_input, templ, false, std::string{}, 8);
            const ComplexArray actual = cusignal::zx_gpu_backend::radartools::pulse_compression(
                host_input, templ, false, std::string{}, 8).get();
            const ErrorMetrics error = compute_complex_error(
                expected.shape,
                expected.values,
                actual.shape,
                actual.values);
            return error.max_abs_error <= 1.0e-4f && error.mixed_error == 0.0f;
        };

        const bool initial_pass = matches_cpu(input);
        input.values[3] += Complex(0.75f, -0.5f);
        const bool mutation_pass = matches_cpu(input);
        const bool cache_hit_pass = matches_cpu(input);
        ComplexArray doppler_input = input;
        doppler_input.values[0] += Complex(-1.25f, 0.75f);
        (void)cusignal::zx_gpu_backend::radartools::pulse_doppler(
            doppler_input, std::string{}, 2).get();
        const bool shared_storage_invalidation_pass = matches_cpu(input);
        const bool pass = initial_pass && mutation_pass && cache_hit_pass &&
                          shared_storage_invalidation_pass;
        std::cout << "[radartools] pulse_host_input_cache_contract="
                  << (pass ? "PASS" : "FAIL") << '\n';
        return pass;
    }

    bool verify_mvdr_host_input_cache_contract()
    {
        const fs::path base = reference_root("mvdr");
        ComplexArray input = load_complex_array(
            base / "input/calc_cov_true_x.csv", Shape{4, 16});
        ComplexArray steering = load_complex_array(
            base / "input/calc_cov_true_sv.csv", Shape{4, 1});

        auto matches_cpu = [&](const cusignal::core::ComplexArrayLike &x_like,
                               const cusignal::core::ComplexArrayLike &sv_like) {
            const ComplexArray expected = cusignal::cpu::radartools::mvdr(input, steering, true);
            const ComplexArray actual = cusignal::zx_gpu_backend::radartools::mvdr(
                x_like, sv_like, true).get();
            const ErrorMetrics error = compute_complex_error(
                expected.shape,
                expected.values,
                actual.shape,
                actual.values);
            return error.max_abs_error <= 1.0e-3f && error.mixed_error == 0.0f;
        };

        const bool initial_pass = matches_cpu(input, steering);
        input.values[17] += Complex(0.125f, -0.0625f);
        const bool input_mutation_pass = matches_cpu(input, steering);
        const bool cache_hit_pass = matches_cpu(input, steering);
        steering.values[2] += Complex(-0.03125f, 0.046875f);
        const bool steering_mutation_pass = matches_cpu(input, steering);
        const ZxGpuComplexArray device_input = ZxGpuComplexArray::from_host(input);
        const ZxGpuComplexArray device_steering = ZxGpuComplexArray::from_host(steering);
        const bool device_input_pass = matches_cpu(device_input, device_steering);
        const bool host_after_device_pass = matches_cpu(input, steering);
        const bool pass = initial_pass && input_mutation_pass && cache_hit_pass &&
                          steering_mutation_pass && device_input_pass && host_after_device_pass;
        std::cout << "[radartools] mvdr_host_input_cache_contract="
                  << (pass ? "PASS" : "FAIL") << '\n';
        return pass;
    }
} // namespace

int run_pulse_compression_tests(int argc, char **argv)
{
    try
    {
        const int result = run_radartools_operator_tests("pulse_compression", argc, argv);
        if (result != 0)
        {
            return result;
        }
        return verify_pulse_host_input_cache_contract() ? 0 : 1;
    }
    catch (const std::exception &error)
    {
        std::cerr << "[radartools] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_pulse_doppler_tests(int argc, char **argv)
{
    try
    {
        return run_radartools_operator_tests("pulse_doppler", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[radartools] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_ambgfun_tests(int argc, char **argv)
{
    try
    {
        return run_radartools_operator_tests("ambgfun", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[radartools] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_cfar_alpha_tests(int argc, char **argv)
{
    try
    {
        return run_radartools_operator_tests("cfar_alpha", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[radartools] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_ca_cfar_tests(int argc, char **argv)
{
    try
    {
        return run_radartools_operator_tests("ca_cfar", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[radartools] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_mvdr_tests(int argc, char **argv)
{
    try
    {
        const int result = run_radartools_operator_tests("mvdr", argc, argv);
        if (result != 0)
        {
            return result;
        }
        return verify_mvdr_host_input_cache_contract() ? 0 : 1;
    }
    catch (const std::exception &error)
    {
        std::cerr << "[radartools] ERROR: " << error.what() << '\n';
        return 1;
    }
}
