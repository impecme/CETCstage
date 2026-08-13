#include "filtering_test_support.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <cstring>
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
#include <variant>
#include <vector>

#include "../../../include/cusignal/filtering/filtering.hpp"
#include "../../../include/cusignal/core/helpers.hpp"
#include "../common/live_perf.hpp"
#include "../common/json.hpp"
#include "../common/report.hpp"

namespace fs = std::filesystem;

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace filtering_test_hooks
        {
            int consume_last_firfilter2_path();
            void set_firfilter2_path_override(int path);
            void set_channelize_poly_path_override(int path);
            bool resample_auto_uses_windowed_pack(
                const cusignal::core::Shape &shape,
                int output_size,
                int axis,
                const cusignal::core::ZxGpuWindowSpec &window,
                const std::string &domain);
            int consume_last_resample_path();
            void set_resample_path_override(int path);
            float consume_last_kernel_ms();
        }
    } // namespace zx_gpu_backend
} // namespace cusignal

namespace
{
    namespace filtering_api = cusignal::filtering_api;
    constexpr float kPi = 3.14159265358979323846f;
    constexpr int kChannelizePathAuto = -1;
    constexpr int kChannelizePathGeneric = 0;
    constexpr int kChannelizePathPoint = 1;
    constexpr float kChannelizeSweepMinGain = 0.005f;
    constexpr int kFirfilter2PathAuto = -1;
    constexpr int kFirfilter2PathGeneric = 0;
    constexpr int kFirfilter2PathDirect = 1;
    constexpr std::size_t kFirfilter2DirectTaps = 31;
    constexpr std::size_t kFirfilter2DirectMinAxisSize = 65536;
    constexpr float kFirfilter2SweepMinGain = 0.005f;
    constexpr int kResamplePathAuto = -1;
    constexpr int kResamplePathGeneric = 0;
    constexpr int kResamplePathFused = 1;
    constexpr int kResamplePathWindowedPack = 2;
    constexpr std::size_t kResampleFusedInputSize = 1048576;
    constexpr int kResampleFusedOutputSize = 1572864;
    constexpr float kResampleSweepMinGain = 0.005f;
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::Float16;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    using cusignal::core::IndexVector;
    using cusignal::core::NamedFloatPairParameter;
    using cusignal::core::NamedFloatParameter;
    using cusignal::core::NamedTaylorParameter;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
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

    struct FilteringCase
    {
        std::string id;
        std::string category;
        fs::path x_file;
        fs::path b_file;
        fs::path a_file;
        fs::path h_file;
        fs::path sos_file;
        fs::path zi_file;
        fs::path t_file;
        fs::path data_file;
        Shape x_shape;
        Shape zi_shape;
        Shape sos_shape;
        Shape data_shape;
        Shape expected_output_shape;
        Shape expected_state_shape;
        Shape n_shape;
        int axis = -1; // 向量化滤波算子的处理轴
        int up = 1; // upfirdn / resample_poly 的上采样倍数
        int down = 1; // upfirdn / resample_poly 的下采样倍数
        int q = 1; // decimate 的抽取倍数
        int n = 0; // 按算子语义使用的滤波阶数或 FFT 长度
        int n_chans = 0; // channelize_poly 的通道数
        int filter_order = 0; // lfilter_zi 性能用例的可缩放滤波阶数
        int x_count = 0; // channelize_poly 性能用例的输入样本数
        int h_count = 0; // channelize_poly 性能用例的原型滤波器长度
        int num = 0; // resample 的目标采样点数
        int padlen = -1; // filtfilt 的边界填充长度
        int irlen = -1; // filtfilt(gust) 的冲激响应长度提示
        float noise = -1.0; // wiener 的附加噪声功率
        float freq = 0.0; // freq_shift 的频移量
        float fs = 2.0; // 归一化频率参数对应的采样频率
        bool zero_phase = true; // 支持时启用前后向零相位路径
        bool overwrite_data = false; // 允许 detrend 原地修改数据
        std::string padtype = "odd"; // filtfilt 的边界扩展模式
        std::string method = "pad"; // filtfilt 方法：pad 或 gust
        std::string domain = "time"; // resample 域：time 或 freq
        std::string type = "linear"; // detrend 模式（linear / constant）
        std::string input_kind = "real"; // 输入数据类型族：real / complex
        std::string dtype = "float32"; // 兼容性用例的数据类型标签
        WindowSpec window = std::string();
        Shape mysize;
        IndexVector bp;
        float atol = 0.0; // 正确性校验的绝对误差容限
        float rtol = 0.0; // 正确性校验的相对误差容限
        fs::path expected_output_file;
        fs::path expected_state_file;
        fs::path expected_time_file;
        std::optional<RealArray> generated_real_x;
        std::optional<ComplexArray> generated_complex_x;
        std::optional<RealSignal> generated_b;
        std::optional<RealSignal> generated_a;
        std::optional<RealSignal> generated_h;
        std::optional<RealArray> generated_sos;
        std::optional<RealArray> generated_zi;
        std::optional<RealSignal> generated_t;
        std::optional<RealArray> generated_data;
    };

    struct OutputBundle
    {
        bool main_complex = false;
        RealArray real_output;
        ComplexArray complex_output;
        bool has_state = false;
        RealArray state;
        bool has_time = false;
        RealSignal time;
    };

    struct DeviceOutputBundle
    {
        bool main_complex = false;
        ZxGpuRealArray real_output;
        ZxGpuComplexArray complex_output;
        bool has_state = false;
        ZxGpuRealArray state;
        bool has_time = false;
        ZxGpuRealSignal time;
    };

    using JsonArray = cusignal_test::json::Array;
    using JsonObject = cusignal_test::json::Object;
    using JsonValue = cusignal_test::json::Value;
    using CpuRunner = std::function<OutputBundle(const FilteringCase &)>;
    using GpuRunner = std::function<DeviceOutputBundle(const FilteringCase &)>;

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
        return repo_root() / "data" / "reference" / "unit" / "filtering" / op;
    }

    fs::path generated_root(const std::string &op)
    {
        return cusignal_test::live_perf::generated_unit_root(
                   repo_root() / "data" / "generated" / "unit") /
               "filtering" / op;
    }

    fs::path report_root(const std::string &op)
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "filtering" / op;
    }

    fs::path module_report_root()
    {
        return repo_root() / "data" / ".reports_staging" / "unit" / "filtering";
    }

    RealArray make_real_array_from_flat(const Shape &shape, const RealSignal &values);
    ComplexArray make_complex_array_from_flat(const Shape &shape, const ComplexSignal &values);

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

    std::size_t shape_size(const Shape &shape)
    {
        if (shape.empty())
        {
            return 0;
        }
        return std::accumulate(
            shape.begin(), shape.end(), std::size_t{1}, std::multiplies<std::size_t>{});
    }

    std::size_t odd_length(std::size_t value)
    {
        return (value % 2 == 0) ? (value + 1) : value;
    }

    RealSignal make_generated_real_signal(std::size_t count, float scale = 1.0, float bias = 0.0)
    {
        RealSignal values(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            const float x = static_cast<float>(index);
            values[index] =
                bias + scale * (0.65 * std::sin(0.013 * x) + 0.25 * std::cos(0.031 * x) +
                                0.10 * std::sin(0.071 * x + 0.3)) +
                0.0005 * static_cast<float>(index % 23);
        }
        return values;
    }

    ComplexSignal make_generated_complex_signal(std::size_t count, float scale = 1.0)
    {
        ComplexSignal values(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            const float x = static_cast<float>(index);
            values[index] = Complex(
                scale * (0.8 * std::cos(0.017 * x) + 0.2 * std::sin(0.043 * x)),
                scale * (0.7 * std::sin(0.019 * x) - 0.15 * std::cos(0.029 * x)));
        }
        return values;
    }

    RealArray make_generated_real_array(const Shape &shape, float scale = 1.0, float bias = 0.0)
    {
        return make_real_array_from_flat(shape, make_generated_real_signal(shape_size(shape), scale, bias));
    }

    ComplexArray make_generated_complex_array(const Shape &shape, float scale = 1.0)
    {
        return make_complex_array_from_flat(shape, make_generated_complex_signal(shape_size(shape), scale));
    }

    RealSignal make_lowpass_like_taps(std::size_t length)
    {
        const std::size_t taps = odd_length(std::max<std::size_t>(length, 7));
        RealSignal values(taps, 0.0);
        const float center = static_cast<float>(taps - 1) / 2.0;
        float sum = 0.0;
        for (std::size_t index = 0; index < taps; ++index)
        {
            const float offset = static_cast<float>(index) - center;
            const float sinc =
                (std::abs(offset) < 1e-12f) ? 0.35f : std::sin(kPi * 0.35f * offset) / (kPi * offset);
            const float window =
                0.54f - 0.46f * std::cos((2.0f * kPi * static_cast<float>(index)) / static_cast<float>(taps - 1));
            values[index] = sinc * window;
            sum += values[index];
        }
        if (std::abs(sum) > 1e-12f)
        {
            for (float &value : values)
            {
                value /= sum;
            }
        }
        return values;
    }

    RealSignal make_stable_iir_b()
    {
        return RealSignal{0.06745527388907191, 0.13491054777814382, 0.06745527388907191};
    }

    RealSignal make_stable_iir_a()
    {
        return RealSignal{1.0, -1.1429805025399011, 0.41280159809618877};
    }

    RealSignal make_stable_fir_b_from_order(std::size_t order)
    {
        const std::size_t count = std::max<std::size_t>(order + 1, 2);
        RealSignal values(count, 0.0);
        float sum = 0.0;
        for (std::size_t index = 0; index < count; ++index)
        {
            const float weight = std::exp(-static_cast<float>(index) / static_cast<float>(count));
            values[index] = static_cast<float>(weight);
            sum += weight;
        }
        for (float &value : values)
        {
            value = static_cast<float>(static_cast<float>(value) / sum);
        }
        return values;
    }

    RealSignal make_unity_feedback_from_order(std::size_t order)
    {
        RealSignal values(std::max<std::size_t>(order + 1, 2), 0.0);
        values.front() = 1.0;
        return values;
    }

    RealArray make_default_sos(std::size_t sections)
    {
        RealArray sos;
        sos.shape = Shape{sections, 6};
        sos.values.reserve(sections * 6);
        for (std::size_t section = 0; section < sections; ++section)
        {
            const float scale = 1.0 - 0.08 * static_cast<float>(section);
            sos.values.push_back(0.06745527388907191 * scale);
            sos.values.push_back(0.13491054777814382 * scale);
            sos.values.push_back(0.06745527388907191 * scale);
            sos.values.push_back(1.0);
            sos.values.push_back(-1.1429805025399011 + 0.05 * static_cast<float>(section));
            sos.values.push_back(0.41280159809618877 - 0.03 * static_cast<float>(section));
        }
        return sos;
    }

    void populate_perf_inputs(const std::string &op, FilteringCase &test_case)
    {
        if (op == "wiener")
        {
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.4, 0.6);
            return;
        }
        if (op == "firfilter")
        {
            test_case.generated_b = make_lowpass_like_taps(33);
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.9, 0.05);
            return;
        }
        if (op == "lfilter")
        {
            test_case.generated_b = make_stable_iir_b();
            test_case.generated_a = make_stable_iir_a();
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.8, 0.0);
            return;
        }
        if (op == "firfilter_zi")
        {
            test_case.generated_b = make_lowpass_like_taps(33);
            return;
        }
        if (op == "lfilter_zi")
        {
            if (test_case.filter_order > 0)
            {
                const std::size_t order = static_cast<std::size_t>(test_case.filter_order);
                test_case.generated_b = make_stable_fir_b_from_order(order);
                test_case.generated_a = make_unity_feedback_from_order(order);
            }
            else
            {
                test_case.generated_b = make_stable_iir_b();
                test_case.generated_a = make_stable_iir_a();
            }
            return;
        }
        if (op == "firfilter2")
        {
            test_case.generated_b = make_lowpass_like_taps(31);
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.75, 0.1);
            return;
        }
        if (op == "filtfilt")
        {
            test_case.generated_b = make_stable_iir_b();
            test_case.generated_a = make_stable_iir_a();
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.75, 0.1);
            return;
        }
        if (op == "sosfilt")
        {
            const std::size_t sections =
                test_case.sos_shape.empty() ? 1 : static_cast<std::size_t>(test_case.sos_shape.front());
            test_case.generated_sos = make_default_sos(sections);
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.85, 0.0);
            return;
        }
        if (op == "hilbert")
        {
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 1.0, 0.0);
            return;
        }
        if (op == "hilbert2")
        {
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.7, 0.2);
            return;
        }
        if (op == "detrend")
        {
            test_case.generated_data =
                make_generated_real_array(test_case.data_shape, 0.6, 1.5);
            return;
        }
        if (op == "freq_shift")
        {
            test_case.generated_complex_x =
                make_generated_complex_array(test_case.x_shape, 1.0);
            return;
        }
        if (op == "channelize_poly")
        {
            const std::size_t x_count =
                test_case.x_count > 0
                    ? static_cast<std::size_t>(test_case.x_count)
                    : std::max<std::size_t>(static_cast<std::size_t>(test_case.n_chans) * 256, 1024);
            const std::size_t h_count =
                test_case.h_count > 0
                    ? odd_length(static_cast<std::size_t>(test_case.h_count))
                    : odd_length(std::max<std::size_t>(static_cast<std::size_t>(test_case.n_chans) * 12, 33));
            test_case.generated_complex_x =
                make_generated_complex_array(Shape{x_count}, 0.9);
            test_case.generated_h = make_lowpass_like_taps(h_count);
            return;
        }
        if (op == "decimate")
        {
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.9, 0.0);
            return;
        }
        if (op == "resample")
        {
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.95, 0.0);
            if (!test_case.t_file.empty())
            {
                const std::size_t count = shape_size(test_case.x_shape);
                RealSignal t(count, 0.0);
                for (std::size_t index = 0; index < count; ++index)
                {
                    t[index] = 0.00125 * static_cast<float>(index);
                }
                test_case.generated_t = std::move(t);
            }
            return;
        }
        if (op == "resample_poly")
        {
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.95, 0.0);
            return;
        }
        if (op == "upfirdn")
        {
            test_case.generated_h = make_lowpass_like_taps(17);
            test_case.generated_real_x =
                make_generated_real_array(test_case.x_shape, 0.9, 0.0);
            return;
        }
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

    IndexVector json_array_to_indices(const JsonValue &value)
    {
        IndexVector indices;
        for (const JsonValue &item : as_array(value))
        {
            if (!item.is_number())
            {
                throw std::runtime_error("expected numeric index entry");
            }
            indices.push_back(static_cast<int>(std::llround(item.as_number())));
        }
        return indices;
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
            values.emplace_back(std::stod(line.substr(0, comma)), std::stod(line.substr(comma + 1)));
        }
        return values;
    }

    void write_real_csv(const fs::path &path, const RealSignal &values)
    {
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
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

    RealSignal flatten(const RealArray &array)
    {
        return array.values;
    }

    ComplexSignal flatten(const ComplexArray &array)
    {
        return array.values;
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
            throw std::runtime_error("unsupported filtering dtype compatibility case: " + dtype);
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
            throw std::runtime_error("unsupported filtering dtype compatibility case: " + dtype);
        }
        RealArray quantized = array;
        quantized.values = apply_dtype_quantization(quantized.values, dtype);
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
            throw std::runtime_error("unsupported filtering dtype compatibility case: " + dtype);
        }
        OutputBundle quantized = bundle;
        if (!quantized.main_complex)
        {
            quantized.real_output = apply_dtype_quantization(quantized.real_output, dtype);
        }
        if (quantized.has_state)
        {
            quantized.state = apply_dtype_quantization(quantized.state, dtype);
        }
        if (quantized.has_time)
        {
            quantized.time = apply_dtype_quantization(quantized.time, dtype);
        }
        return quantized;
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

    std::string relative_path_string(const fs::path &path)
    {
        return fs::relative(path, repo_root()).generic_string();
    }

    std::string shape_to_json(const Shape &shape)
    {
        std::ostringstream stream;
        stream << '[';
        for (std::size_t index = 0; index < shape.size(); ++index)
        {
            stream << shape[index];
            if (index + 1 != shape.size())
            {
                stream << ", ";
            }
        }
        stream << ']';
        return stream.str();
    }

    std::string real_signal_to_json(const RealSignal &values)
    {
        std::ostringstream stream;
        stream << '[' << std::setprecision(17);
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            stream << values[index];
            if (index + 1 != values.size())
            {
                stream << ", ";
            }
        }
        stream << ']';
        return stream.str();
    }

    std::string index_vector_to_json(const IndexVector &values)
    {
        std::ostringstream stream;
        stream << '[';
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            stream << values[index];
            if (index + 1 != values.size())
            {
                stream << ", ";
            }
        }
        stream << ']';
        return stream.str();
    }

    std::string window_spec_to_json(const WindowSpec &window)
    {
        return std::visit(
            [](const auto &value) {
                std::ostringstream stream;
                using ValueType = std::decay_t<decltype(value)>;
                if constexpr (std::is_same_v<ValueType, std::string>)
                {
                    stream << "{\n  \"kind\": \"string\",\n  \"value\": \"" << json_escape(value)
                           << "\"\n}";
                }
                else if constexpr (std::is_same_v<ValueType, float>)
                {
                    stream << "{\n  \"kind\": \"float\",\n  \"value\": " << value << "\n}";
                }
                else if constexpr (std::is_same_v<ValueType, NamedFloatParameter>)
                {
                    stream << "{\n  \"kind\": \"named_float\",\n  \"name\": \""
                           << json_escape(value.name) << "\",\n  \"value\": " << value.value
                           << "\n}";
                }
                else if constexpr (std::is_same_v<ValueType, NamedFloatPairParameter>)
                {
                    stream << "{\n  \"kind\": \"named_pair\",\n  \"name\": \""
                           << json_escape(value.name) << "\",\n  \"first\": " << value.first
                           << ",\n  \"second\": " << value.second << "\n}";
                }
                else if constexpr (std::is_same_v<ValueType, NamedTaylorParameter>)
                {
                    stream << "{\n  \"kind\": \"named_taylor\",\n  \"name\": \""
                           << json_escape(value.name) << "\",\n  \"nbar\": " << value.nbar
                           << ",\n  \"sll\": " << value.sll << ",\n  \"norm\": "
                           << (value.norm ? "true" : "false") << "\n}";
                }
                else
                {
                    stream << "{\n  \"kind\": \"explicit_array\",\n  \"values\": "
                           << real_signal_to_json(value) << "\n}";
                }
                return stream.str();
            },
            window);
    }

    std::string build_case_spec_json(const FilteringCase &test_case)
    {
        std::ostringstream stream;
        stream << "{\n"
               << "  \"id\": \"" << json_escape(test_case.id) << "\",\n"
               << "  \"category\": \"" << json_escape(test_case.category) << "\"";
        const auto append_path = [&](const char *key, const fs::path &path) {
            if (!path.empty())
            {
                stream << ",\n  \"" << key << "\": \"" << json_escape(relative_path_string(path))
                       << "\"";
            }
        };
        const auto append_shape = [&](const char *key, const Shape &shape) {
            if (!shape.empty())
            {
                stream << ",\n  \"" << key << "\": " << shape_to_json(shape);
            }
        };
        append_path("x_file", test_case.x_file);
        append_path("b_file", test_case.b_file);
        append_path("a_file", test_case.a_file);
        append_path("h_file", test_case.h_file);
        append_path("sos_file", test_case.sos_file);
        append_path("zi_file", test_case.zi_file);
        append_path("t_file", test_case.t_file);
        append_path("data_file", test_case.data_file);
        append_shape("x_shape", test_case.x_shape);
        append_shape("zi_shape", test_case.zi_shape);
        append_shape("sos_shape", test_case.sos_shape);
        append_shape("data_shape", test_case.data_shape);
        append_shape("n_shape", test_case.n_shape);
        append_shape("mysize", test_case.mysize);
        if (!test_case.bp.empty())
        {
            stream << ",\n  \"bp\": " << index_vector_to_json(test_case.bp);
        }
        stream << ",\n  \"axis\": " << test_case.axis
               << ",\n  \"up\": " << test_case.up
               << ",\n  \"down\": " << test_case.down
               << ",\n  \"q\": " << test_case.q
               << ",\n  \"n\": " << test_case.n
               << ",\n  \"n_chans\": " << test_case.n_chans
               << ",\n  \"num\": " << test_case.num
               << ",\n  \"padlen\": " << test_case.padlen
               << ",\n  \"irlen\": " << test_case.irlen
               << ",\n  \"noise\": " << test_case.noise
               << ",\n  \"freq\": " << test_case.freq
               << ",\n  \"fs\": " << test_case.fs
               << ",\n  \"zero_phase\": " << (test_case.zero_phase ? "true" : "false")
               << ",\n  \"overwrite_data\": " << (test_case.overwrite_data ? "true" : "false")
               << ",\n  \"padtype\": \"" << json_escape(test_case.padtype) << "\""
               << ",\n  \"method\": \"" << json_escape(test_case.method) << "\""
               << ",\n  \"domain\": \"" << json_escape(test_case.domain) << "\""
               << ",\n  \"type\": \"" << json_escape(test_case.type) << "\""
               << ",\n  \"dtype\": \"" << json_escape(test_case.dtype) << "\""
               << ",\n  \"window\": " << window_spec_to_json(test_case.window)
               << "\n}\n";
        return stream.str();
    }

    void write_output_samples(
        const fs::path &base_dir,
        const std::string &case_id,
        const std::string &backend,
        const OutputBundle &bundle,
        std::vector<Artifact> *artifacts)
    {
        const fs::path output_path = base_dir / (case_id + "__" + backend + "__signal.csv");
        if (bundle.main_complex)
        {
            write_complex_csv(output_path, sample_values(flatten(bundle.complex_output)));
        }
        else
        {
            write_real_csv(output_path, sample_values(flatten(bundle.real_output)));
        }
        if (artifacts != nullptr)
        {
            artifacts->push_back(Artifact{backend + "_signal", output_path});
        }

        if (bundle.has_state)
        {
            const fs::path state_path = base_dir / (case_id + "__" + backend + "__state.csv");
            write_real_csv(state_path, sample_values(flatten(bundle.state)));
            if (artifacts != nullptr)
            {
                artifacts->push_back(Artifact{backend + "_state", state_path});
            }
        }

        if (bundle.has_time)
        {
            const fs::path time_path = base_dir / (case_id + "__" + backend + "__time.csv");
            write_real_csv(time_path, sample_values(bundle.time));
            if (artifacts != nullptr)
            {
                artifacts->push_back(Artifact{backend + "_time", time_path});
            }
        }
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
            return WindowSpec{NamedFloatParameter{get_string(object, "name"), get_optional_number(object, "value", 0.0)}};
        }
        if (kind == "named_pair")
        {
            return WindowSpec{NamedFloatPairParameter{
                get_string(object, "name"),
                get_optional_number(object, "first", 0.0),
                get_optional_number(object, "second", 0.0)}};
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

    ZxGpuWindowSpec to_zx_gpu_window_spec_with_device_array(
        const WindowSpec &spec,
        std::optional<ZxGpuRealSignal> &device_window)
    {
        if (const auto *values = std::get_if<RealSignal>(&spec))
        {
            device_window.emplace(ZxGpuRealSignal::from_host(*values));
            return *device_window;
        }
        return to_zx_gpu_window_spec(spec);
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
        TimingStats stats;
        stats.samples_ms = samples_ms;
        std::vector<float> sorted = samples_ms;
        std::sort(sorted.begin(), sorted.end());
        stats.min_ms = sorted.front();
        stats.max_ms = sorted.back();
        const float sum = std::accumulate(samples_ms.begin(), samples_ms.end(), 0.0);
        stats.mean_ms = sum / static_cast<float>(samples_ms.size());
        stats.median_ms = sorted.size() % 2 == 0
                              ? 0.5 * (sorted[sorted.size() / 2 - 1] + sorted[sorted.size() / 2])
                              : sorted[sorted.size() / 2];
        const std::size_t p95_index = static_cast<std::size_t>(std::ceil(0.95 * sorted.size()) - 1.0);
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
            durations.push_back(std::chrono::duration<float, std::milli>(stop - start).count());
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
            (void)cusignal::zx_gpu_backend::filtering_test_hooks::consume_last_kernel_ms();
        }
        for (int iteration = 0; iteration < options.repeat; ++iteration)
        {
            callable();
            durations.push_back(cusignal::zx_gpu_backend::filtering_test_hooks::consume_last_kernel_ms());
        }
        return summarize_timings(durations);
    }

    class ChannelizePathOverrideReset
    {
    public:
        ~ChannelizePathOverrideReset()
        {
            cusignal::zx_gpu_backend::filtering_test_hooks::set_channelize_poly_path_override(
                kChannelizePathAuto);
        }
    };

    class Firfilter2PathOverrideReset
    {
    public:
        ~Firfilter2PathOverrideReset()
        {
            cusignal::zx_gpu_backend::filtering_test_hooks::set_firfilter2_path_override(
                kFirfilter2PathAuto);
        }
    };

    class ResamplePathOverrideReset
    {
    public:
        ~ResamplePathOverrideReset()
        {
            cusignal::zx_gpu_backend::filtering_test_hooks::set_resample_path_override(
                kResamplePathAuto);
        }
    };

    ComplexSignal make_channelize_probe_input(std::size_t count)
    {
        ComplexSignal input(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            const int real_code = static_cast<int>((index * 17 + 3) % 257) - 128;
            const int imag_code = static_cast<int>((index * 29 + 11) % 251) - 125;
            input[index] = Complex(
                std::ldexp(static_cast<float>(real_code), -9),
                std::ldexp(static_cast<float>(imag_code), -10));
        }
        return input;
    }

    RealSignal make_channelize_probe_taps(std::size_t count)
    {
        RealSignal taps(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            const int code = static_cast<int>((index * 19 + 5) % 101) - 50;
            taps[index] = std::ldexp(static_cast<float>(code), -11);
        }
        return taps;
    }

    ComplexArray run_channelize_probe_path(
        const ZxGpuComplexSignal &input,
        const ZxGpuRealSignal &taps,
        int n_chans,
        int path)
    {
        cusignal::zx_gpu_backend::filtering_test_hooks::set_channelize_poly_path_override(path);
        const auto result = cusignal::zx_gpu_backend::filtering::channelize_poly(
            input,
            taps,
            n_chans);
        cusignal::core::throw_on_zx_gpu_error(
            cudaDeviceSynchronize(),
            "cudaDeviceSynchronize channelize device A/B");
        return result.channels.get();
    }

    bool bitwise_equal_complex_arrays(
        const ComplexArray &lhs,
        const ComplexArray &rhs,
        std::size_t *first_mismatch)
    {
        if (lhs.shape != rhs.shape || lhs.values.size() != rhs.values.size())
        {
            *first_mismatch = 0;
            return false;
        }
        for (std::size_t index = 0; index < lhs.values.size(); ++index)
        {
            std::uint32_t lhs_real = 0;
            std::uint32_t lhs_imag = 0;
            std::uint32_t rhs_real = 0;
            std::uint32_t rhs_imag = 0;
            const float lhs_real_value = lhs.values[index].real();
            const float lhs_imag_value = lhs.values[index].imag();
            const float rhs_real_value = rhs.values[index].real();
            const float rhs_imag_value = rhs.values[index].imag();
            static_assert(sizeof(lhs_real) == sizeof(lhs_real_value), "float32 bit width");
            std::memcpy(&lhs_real, &lhs_real_value, sizeof(lhs_real));
            std::memcpy(&lhs_imag, &lhs_imag_value, sizeof(lhs_imag));
            std::memcpy(&rhs_real, &rhs_real_value, sizeof(rhs_real));
            std::memcpy(&rhs_imag, &rhs_imag_value, sizeof(rhs_imag));
            if (lhs_real != rhs_real || lhs_imag != rhs_imag)
            {
                *first_mismatch = index;
                return false;
            }
        }
        return true;
    }

    struct ChannelizeSweepBatch
    {
        std::size_t points = 0;
        int batch = 0;
        float generic_e2e_ms = 0.0;
        float point_e2e_ms = 0.0;
        float generic_kernel_ms = 0.0;
        float point_kernel_ms = 0.0;
        bool dual_gain = false;
    };

    struct ChannelizePathTimings
    {
        TimingStats e2e;
        TimingStats kernel;
    };

    ChannelizePathTimings benchmark_channelize_probe_path(
        const ZxGpuComplexSignal &input,
        const ZxGpuRealSignal &taps,
        int path,
        const CliOptions &options)
    {
        cusignal::zx_gpu_backend::filtering_test_hooks::set_channelize_poly_path_override(path);
        ChannelizePathTimings timings;
        timings.e2e = benchmark_host_latency(options, [&]() {
            const auto result = cusignal::zx_gpu_backend::filtering::channelize_poly(input, taps, 8);
            (void)result;
            cusignal::core::throw_on_zx_gpu_error(
                cudaDeviceSynchronize(),
                "cudaDeviceSynchronize channelize threshold e2e");
        });
        timings.kernel = benchmark_gpu_kernel_latency(options, [&]() {
            (void)cusignal::zx_gpu_backend::filtering::channelize_poly(input, taps, 8);
        });
        return timings;
    }

    int run_channelize_device_ab_probe()
    {
        ChannelizePathOverrideReset reset;
        std::ofstream report;
        const char *report_path = std::getenv("CUSIGNAL_CHANNELIZE_DEVICE_AB_REPORT");
        if (report_path != nullptr && report_path[0] != '\0')
        {
            report.open(report_path);
            if (!report)
            {
                throw std::runtime_error("failed to open channelize device A/B report");
            }
        }

        std::size_t checked_cases = 0;
        std::size_t checked_outputs = 0;
        const auto check_case = [&](int n_chans,
                                    std::size_t points,
                                    std::size_t remainder,
                                    std::size_t tap_count) {
            const ComplexSignal host_input =
                make_channelize_probe_input(points * static_cast<std::size_t>(n_chans) + remainder);
            const RealSignal host_taps = make_channelize_probe_taps(tap_count);
            const ZxGpuComplexSignal input = ZxGpuComplexSignal::from_host(host_input);
            const ZxGpuRealSignal taps = ZxGpuRealSignal::from_host(host_taps);
            const ComplexArray generic = run_channelize_probe_path(
                input, taps, n_chans, kChannelizePathGeneric);
            const ComplexArray point = run_channelize_probe_path(
                input, taps, n_chans, kChannelizePathPoint);
            const ComplexArray automatic = run_channelize_probe_path(
                input, taps, n_chans, kChannelizePathAuto);

            std::size_t first_mismatch = 0;
            if (!bitwise_equal_complex_arrays(generic, point, &first_mismatch))
            {
                std::ostringstream message;
                message << "generic/point mismatch: channels=" << n_chans
                        << " points=" << points << " remainder=" << remainder
                        << " taps=" << tap_count << " index=" << first_mismatch;
                throw std::runtime_error(message.str());
            }
            const ComplexArray &expected_auto =
                n_chans == 8 && points >= 256 ? point : generic;
            if (!bitwise_equal_complex_arrays(automatic, expected_auto, &first_mismatch))
            {
                std::ostringstream message;
                message << "automatic path mismatch: channels=" << n_chans
                        << " points=" << points << " remainder=" << remainder
                        << " taps=" << tap_count << " index=" << first_mismatch;
                throw std::runtime_error(message.str());
            }
            ++checked_cases;
            checked_outputs += generic.values.size();
        };

        const std::array<std::size_t, 5> tap_counts = {1, 8, 97, 104, 105};
        for (const std::size_t points : {std::size_t{255}, std::size_t{256}, std::size_t{257}})
        {
            for (std::size_t remainder = 0; remainder < 8; ++remainder)
            {
                for (const std::size_t tap_count : tap_counts)
                {
                    check_case(8, points, remainder, tap_count);
                }
            }
        }
        for (const std::size_t points : {
                 std::size_t{512}, std::size_t{1024}, std::size_t{4096},
                 std::size_t{16384}, std::size_t{131072}})
        {
            check_case(8, points, points % 8, 97);
        }
        check_case(4, 257, 3, 97);

        const bool correctness_only =
            std::getenv("CUSIGNAL_CHANNELIZE_DEVICE_AB_CORRECTNESS_ONLY") != nullptr;
        if (correctness_only)
        {
            if (report)
            {
                report << "summary\tpass\tchecked_cases\t" << checked_cases
                       << "\tchecked_complex_outputs\t" << checked_outputs
                       << "\tthreshold\tnot_run\n";
            }
            std::cout << "[channelize-device-ab] PASS checked_cases=" << checked_cases
                      << " checked_complex_outputs=" << checked_outputs
                      << " threshold=not_run\n";
            return 0;
        }

        const std::array<std::size_t, 8> sweep_points = {
            255, 256, 257, 512, 1024, 4096, 16384, 131072};
        std::vector<ChannelizeSweepBatch> sweep;
        CliOptions timing_options;
        timing_options.warmup = 2;
        timing_options.repeat = 10;
        for (const std::size_t points : sweep_points)
        {
            const ZxGpuComplexSignal input = ZxGpuComplexSignal::from_host(
                make_channelize_probe_input(points * 8));
            const ZxGpuRealSignal taps = ZxGpuRealSignal::from_host(
                make_channelize_probe_taps(97));
            for (int batch = 1; batch <= 5; ++batch)
            {
                ChannelizePathTimings generic;
                ChannelizePathTimings point;
                if (batch % 2 == 1)
                {
                    generic = benchmark_channelize_probe_path(
                        input, taps, kChannelizePathGeneric, timing_options);
                    point = benchmark_channelize_probe_path(
                        input, taps, kChannelizePathPoint, timing_options);
                }
                else
                {
                    point = benchmark_channelize_probe_path(
                        input, taps, kChannelizePathPoint, timing_options);
                    generic = benchmark_channelize_probe_path(
                        input, taps, kChannelizePathGeneric, timing_options);
                }
                sweep.push_back(ChannelizeSweepBatch{
                    points,
                    batch,
                    generic.e2e.median_ms,
                    point.e2e.median_ms,
                    generic.kernel.median_ms,
                    point.kernel.median_ms,
                    point.e2e.median_ms <=
                            generic.e2e.median_ms * (1.0f - kChannelizeSweepMinGain) &&
                        point.kernel.median_ms <=
                            generic.kernel.median_ms * (1.0f - kChannelizeSweepMinGain)});
            }
        }

        std::map<std::size_t, int> gain_batches;
        for (const ChannelizeSweepBatch &row : sweep)
        {
            if (row.dual_gain)
            {
                ++gain_batches[row.points];
            }
        }
        std::size_t crossover = 0;
        for (std::size_t index = 1; index + 1 < sweep_points.size(); ++index)
        {
            const std::size_t points = sweep_points[index];
            const std::size_t next_points = sweep_points[index + 1];
            if (points >= 256 && gain_batches[points] >= 4 && gain_batches[next_points] >= 4)
            {
                crossover = points;
                break;
            }
        }
        bool all_routed_sizes_ok = true;
        for (const std::size_t points : sweep_points)
        {
            if (points >= 256 && gain_batches[points] < 4)
            {
                all_routed_sizes_ok = false;
            }
        }
        const bool threshold_ok = crossover == 256 && all_routed_sizes_ok;

        if (report)
        {
            report << "points\tbatch\tgeneric_e2e_ms\tpoint_e2e_ms\t"
                      "generic_kernel_ms\tpoint_kernel_ms\tdual_gain\n";
            for (const ChannelizeSweepBatch &row : sweep)
            {
                report << row.points << '\t' << row.batch << '\t'
                       << row.generic_e2e_ms << '\t' << row.point_e2e_ms << '\t'
                       << row.generic_kernel_ms << '\t' << row.point_kernel_ms << '\t'
                       << (row.dual_gain ? "true" : "false") << '\n';
            }
            report << "summary\t" << (threshold_ok ? "pass" : "fail")
                   << "\tchecked_cases\t" << checked_cases
                   << "\tchecked_complex_outputs\t" << checked_outputs
                   << "\tcrossover\t" << crossover
                   << "\tall_routed_sizes_ok\t" << (all_routed_sizes_ok ? "true" : "false")
                   << "\tmin_gain\t" << kChannelizeSweepMinGain << '\n';
        }
        std::cout << "[channelize-device-ab] " << (threshold_ok ? "PASS" : "FAIL")
                  << " checked_cases=" << checked_cases
                  << " checked_complex_outputs=" << checked_outputs
                  << " crossover=" << crossover << '\n';
        return threshold_ok ? 0 : 1;
    }

    RealSignal make_firfilter2_probe_taps(std::size_t count)
    {
        RealSignal taps(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            const int code = static_cast<int>((index * 23 + 7) % 67) - 33;
            taps[index] = std::ldexp(static_cast<float>(code), -10);
        }
        return taps;
    }

    RealArray run_firfilter2_probe_path(
        const ZxGpuRealSignal &taps,
        const ZxGpuRealArray &input,
        int axis,
        const std::string &padtype,
        int padlen,
        int path,
        int *observed_path)
    {
        cusignal::zx_gpu_backend::filtering_test_hooks::set_firfilter2_path_override(path);
        const ZxGpuRealArray result = cusignal::zx_gpu_backend::filtering::firfilter2(
            taps, input, axis, padtype, padlen, "pad", -1);
        cusignal::core::throw_on_zx_gpu_error(
            cudaDeviceSynchronize(),
            "cudaDeviceSynchronize firfilter2 device A/B");
        *observed_path =
            cusignal::zx_gpu_backend::filtering_test_hooks::consume_last_firfilter2_path();
        return result.get();
    }

    bool bitwise_equal_real_arrays(
        const RealArray &lhs,
        const RealArray &rhs,
        std::size_t *first_mismatch)
    {
        if (lhs.shape != rhs.shape || lhs.values.size() != rhs.values.size())
        {
            *first_mismatch = 0;
            return false;
        }
        for (std::size_t index = 0; index < lhs.values.size(); ++index)
        {
            std::uint32_t lhs_bits = 0;
            std::uint32_t rhs_bits = 0;
            static_assert(sizeof(lhs_bits) == sizeof(lhs.values[index]), "float32 bit width");
            std::memcpy(&lhs_bits, &lhs.values[index], sizeof(lhs_bits));
            std::memcpy(&rhs_bits, &rhs.values[index], sizeof(rhs_bits));
            if (lhs_bits != rhs_bits)
            {
                *first_mismatch = index;
                return false;
            }
        }
        return true;
    }

    bool firfilter2_auto_uses_direct(const Shape &shape, int axis, std::size_t tap_count)
    {
        const int normalized_axis = axis < 0 ? axis + static_cast<int>(shape.size()) : axis;
        std::size_t axis_stride = 1;
        for (std::size_t dimension = static_cast<std::size_t>(normalized_axis) + 1;
             dimension < shape.size();
             ++dimension)
        {
            axis_stride *= shape[dimension];
        }
        const std::size_t axis_size = shape[static_cast<std::size_t>(normalized_axis)];
        const std::size_t line_count = shape_size(shape) / axis_size;
        return tap_count == kFirfilter2DirectTaps &&
               line_count == 1 &&
               axis_stride == 1 &&
               axis_size >= kFirfilter2DirectMinAxisSize;
    }

    struct Firfilter2PathTimings
    {
        TimingStats e2e;
        TimingStats kernel;
    };

    Firfilter2PathTimings benchmark_firfilter2_probe_path(
        const ZxGpuRealSignal &taps,
        const ZxGpuRealArray &input,
        int path,
        const CliOptions &options)
    {
        cusignal::zx_gpu_backend::filtering_test_hooks::set_firfilter2_path_override(path);
        Firfilter2PathTimings timings;
        timings.e2e = benchmark_host_latency(options, [&]() {
            const auto result = cusignal::zx_gpu_backend::filtering::firfilter2(
                taps, input, 0, "odd", -1, "pad", -1);
            (void)result;
            cusignal::core::throw_on_zx_gpu_error(
                cudaDeviceSynchronize(),
                "cudaDeviceSynchronize firfilter2 threshold e2e");
        });
        timings.kernel = benchmark_gpu_kernel_latency(options, [&]() {
            (void)cusignal::zx_gpu_backend::filtering::firfilter2(
                taps, input, 0, "odd", -1, "pad", -1);
        });
        return timings;
    }

    struct Firfilter2SweepBatch
    {
        std::size_t axis_size = 0;
        int batch = 0;
        float generic_e2e_ms = 0.0f;
        float direct_e2e_ms = 0.0f;
        float generic_kernel_ms = 0.0f;
        float direct_kernel_ms = 0.0f;
        bool dual_gain = false;
    };

    int run_firfilter2_device_ab_probe()
    {
        Firfilter2PathOverrideReset reset;
        std::ofstream report;
        std::ofstream route_report;
        std::ofstream summary_report;
        const char *report_path = std::getenv("CUSIGNAL_FIRFILTER2_DEVICE_AB_REPORT");
        if (report_path != nullptr && report_path[0] != '\0')
        {
            report.open(report_path);
            route_report.open(std::string(report_path) + ".routes.tsv");
            summary_report.open(std::string(report_path) + ".summary.tsv");
            if (!report || !route_report || !summary_report)
            {
                throw std::runtime_error("failed to open firfilter2 device A/B report");
            }
            route_report << "case\tshape\taxis\ttaps\tpadtype\tpadlen\t"
                            "observed_path\texpected_path\n";
            summary_report << "checked_cases\tchecked_float_outputs\tconfigured_threshold\t"
                              "observed_crossover\troute_threshold_pass\t"
                              "all_routed_sizes_gain_pass\tsweep_min_gain\twarmup\trepeat\t"
                              "batches\tprobe_pass\n";
        }

        struct CorrectnessCase
        {
            Shape shape;
            int axis;
            std::size_t tap_count;
            std::string padtype;
            int padlen;
        };
        const std::vector<CorrectnessCase> cases = {
            {Shape{1024}, 0, 1, "none", -1},
            {Shape{1024}, 0, 2, "odd", -1},
            {Shape{1024}, 0, 3, "even", 5},
            {Shape{1024}, 0, 31, "constant", -1},
            {Shape{1024}, 0, 256, "odd", -1},
            {Shape{3, 257}, 1, 31, "odd", -1},
            {Shape{257, 4}, 0, 31, "even", 17},
            {Shape{2, 257, 3}, 1, 31, "constant", -1},
            {Shape{65535}, 0, 31, "odd", -1},
            {Shape{65536}, 0, 31, "odd", -1},
            {Shape{1, 65536}, -1, 31, "odd", 0},
            {Shape{65537}, 0, 31, "odd", -1},
            {Shape{1048576}, 0, 31, "odd", -1},
        };

        std::size_t checked_cases = 0;
        std::size_t checked_outputs = 0;
        std::size_t observed_crossover = 0;
        for (const CorrectnessCase &test_case : cases)
        {
            const ZxGpuRealArray input = ZxGpuRealArray::from_host(
                make_generated_real_array(test_case.shape, 0.75f, 0.1f));
            const ZxGpuRealSignal taps = ZxGpuRealSignal::from_host(
                make_firfilter2_probe_taps(test_case.tap_count));
            int generic_path = kFirfilter2PathAuto;
            int direct_path = kFirfilter2PathAuto;
            int automatic_path = kFirfilter2PathAuto;
            const RealArray generic = run_firfilter2_probe_path(
                taps,
                input,
                test_case.axis,
                test_case.padtype,
                test_case.padlen,
                kFirfilter2PathGeneric,
                &generic_path);
            const RealArray direct = run_firfilter2_probe_path(
                taps,
                input,
                test_case.axis,
                test_case.padtype,
                test_case.padlen,
                kFirfilter2PathDirect,
                &direct_path);
            const RealArray automatic = run_firfilter2_probe_path(
                taps,
                input,
                test_case.axis,
                test_case.padtype,
                test_case.padlen,
                kFirfilter2PathAuto,
                &automatic_path);

            const int expected_automatic_path =
                firfilter2_auto_uses_direct(test_case.shape, test_case.axis, test_case.tap_count)
                    ? kFirfilter2PathDirect
                    : kFirfilter2PathGeneric;
            if (generic_path != kFirfilter2PathGeneric ||
                direct_path != kFirfilter2PathDirect ||
                automatic_path != expected_automatic_path)
            {
                std::ostringstream message;
                message << "path selection mismatch: generic=" << generic_path
                        << " direct=" << direct_path
                        << " automatic=" << automatic_path
                        << " expected_auto=" << expected_automatic_path;
                throw std::runtime_error(message.str());
            }
            const int normalized_axis =
                test_case.axis < 0
                    ? test_case.axis + static_cast<int>(test_case.shape.size())
                    : test_case.axis;
            const std::size_t axis_size =
                test_case.shape[static_cast<std::size_t>(normalized_axis)];
            if (automatic_path == kFirfilter2PathDirect &&
                (observed_crossover == 0 || axis_size < observed_crossover))
            {
                observed_crossover = axis_size;
            }
            if (route_report)
            {
                std::ostringstream shape_text;
                for (std::size_t index = 0; index < test_case.shape.size(); ++index)
                {
                    if (index != 0)
                    {
                        shape_text << 'x';
                    }
                    shape_text << test_case.shape[index];
                }
                route_report << checked_cases + 1 << '\t' << shape_text.str() << '\t'
                             << test_case.axis << '\t' << test_case.tap_count << '\t'
                             << test_case.padtype << '\t' << test_case.padlen << '\t'
                             << automatic_path << '\t' << expected_automatic_path << '\n';
            }

            std::size_t first_mismatch = 0;
            if (!bitwise_equal_real_arrays(generic, direct, &first_mismatch))
            {
                std::ostringstream message;
                message << "generic/direct mismatch: shape=";
                for (const std::size_t dimension : test_case.shape)
                {
                    message << dimension << 'x';
                }
                message << " axis=" << test_case.axis
                        << " taps=" << test_case.tap_count
                        << " padtype=" << test_case.padtype
                        << " padlen=" << test_case.padlen
                        << " index=" << first_mismatch;
                throw std::runtime_error(message.str());
            }
            const RealArray &expected_auto =
                expected_automatic_path == kFirfilter2PathDirect ? direct : generic;
            if (!bitwise_equal_real_arrays(automatic, expected_auto, &first_mismatch))
            {
                std::ostringstream message;
                message << "automatic path mismatch: axis=" << test_case.axis
                        << " taps=" << test_case.tap_count
                        << " index=" << first_mismatch;
                throw std::runtime_error(message.str());
            }
            ++checked_cases;
            checked_outputs += generic.values.size();
        }
        const bool route_threshold_ok =
            observed_crossover == kFirfilter2DirectMinAxisSize;

        const bool correctness_only =
            std::getenv("CUSIGNAL_FIRFILTER2_DEVICE_AB_CORRECTNESS_ONLY") != nullptr;
        if (correctness_only)
        {
            if (summary_report)
            {
                summary_report << checked_cases << '\t' << checked_outputs << '\t'
                               << kFirfilter2DirectMinAxisSize << '\t'
                               << observed_crossover << '\t'
                               << (route_threshold_ok ? "true" : "false")
                               << "\tnot_run\t" << kFirfilter2SweepMinGain
                               << "\t0\t0\t0\t"
                               << (route_threshold_ok ? "true" : "false") << '\n';
            }
            std::cout << "[firfilter2-device-ab] "
                      << (route_threshold_ok ? "PASS" : "FAIL")
                      << " checked_cases=" << checked_cases
                      << " checked_float_outputs=" << checked_outputs
                      << " observed_crossover=" << observed_crossover
                      << " sweep=not_run\n";
            return route_threshold_ok ? 0 : 1;
        }

        const std::array<std::size_t, 5> sweep_sizes = {
            65535, 65536, 65537, 262144, 1048576};
        std::vector<Firfilter2SweepBatch> sweep;
        CliOptions timing_options;
        timing_options.warmup = 2;
        timing_options.repeat = 10;
        const ZxGpuRealSignal taps = ZxGpuRealSignal::from_host(
            make_firfilter2_probe_taps(kFirfilter2DirectTaps));
        for (const std::size_t axis_size : sweep_sizes)
        {
            const ZxGpuRealArray input = ZxGpuRealArray::from_host(
                make_generated_real_array(Shape{axis_size}, 0.75f, 0.1f));
            for (int batch = 1; batch <= 5; ++batch)
            {
                Firfilter2PathTimings generic;
                Firfilter2PathTimings direct;
                if (batch % 2 == 1)
                {
                    generic = benchmark_firfilter2_probe_path(
                        taps, input, kFirfilter2PathGeneric, timing_options);
                    direct = benchmark_firfilter2_probe_path(
                        taps, input, kFirfilter2PathDirect, timing_options);
                }
                else
                {
                    direct = benchmark_firfilter2_probe_path(
                        taps, input, kFirfilter2PathDirect, timing_options);
                    generic = benchmark_firfilter2_probe_path(
                        taps, input, kFirfilter2PathGeneric, timing_options);
                }
                sweep.push_back(Firfilter2SweepBatch{
                    axis_size,
                    batch,
                    generic.e2e.median_ms,
                    direct.e2e.median_ms,
                    generic.kernel.median_ms,
                    direct.kernel.median_ms,
                    direct.e2e.median_ms <=
                            generic.e2e.median_ms * (1.0f - kFirfilter2SweepMinGain) &&
                        direct.kernel.median_ms <=
                            generic.kernel.median_ms * (1.0f - kFirfilter2SweepMinGain)});
            }
        }

        std::map<std::size_t, int> gain_batches;
        for (const Firfilter2SweepBatch &row : sweep)
        {
            if (row.dual_gain)
            {
                ++gain_batches[row.axis_size];
            }
        }
        bool all_routed_sizes_ok = true;
        for (const std::size_t axis_size : sweep_sizes)
        {
            if (axis_size >= kFirfilter2DirectMinAxisSize && gain_batches[axis_size] < 4)
            {
                all_routed_sizes_ok = false;
            }
        }
        const bool sweep_gain_ok = gain_batches[kFirfilter2DirectMinAxisSize] >= 4 &&
                                   gain_batches[kFirfilter2DirectMinAxisSize + 1] >= 4 &&
                                   all_routed_sizes_ok;
        const bool probe_ok = route_threshold_ok && sweep_gain_ok;

        if (report)
        {
            report << "axis_size\tbatch\tgeneric_e2e_ms\tdirect_e2e_ms\t"
                      "generic_kernel_ms\tdirect_kernel_ms\tdual_gain\n";
            for (const Firfilter2SweepBatch &row : sweep)
            {
                report << row.axis_size << '\t' << row.batch << '\t'
                       << row.generic_e2e_ms << '\t' << row.direct_e2e_ms << '\t'
                       << row.generic_kernel_ms << '\t' << row.direct_kernel_ms << '\t'
                       << (row.dual_gain ? "true" : "false") << '\n';
            }
        }
        if (summary_report)
        {
            summary_report << checked_cases << '\t' << checked_outputs << '\t'
                           << kFirfilter2DirectMinAxisSize << '\t'
                           << observed_crossover << '\t'
                           << (route_threshold_ok ? "true" : "false") << '\t'
                           << (all_routed_sizes_ok ? "true" : "false") << '\t'
                           << kFirfilter2SweepMinGain << '\t'
                           << timing_options.warmup << '\t' << timing_options.repeat
                           << "\t5\t" << (probe_ok ? "true" : "false") << '\n';
        }
        std::cout << "[firfilter2-device-ab] " << (probe_ok ? "PASS" : "FAIL")
                  << " checked_cases=" << checked_cases
                  << " checked_float_outputs=" << checked_outputs
                  << " configured_threshold=" << kFirfilter2DirectMinAxisSize
                  << " observed_crossover=" << observed_crossover
                  << " sweep_gain=" << (sweep_gain_ok ? "pass" : "fail") << '\n';
        return probe_ok ? 0 : 1;
    }

    RealSignal make_resample_probe_window(std::size_t size)
    {
        RealSignal window(size);
        for (std::size_t index = 0; index < size; ++index)
        {
            const int code = static_cast<int>((index * 37 + 11) % 127) - 63;
            window[index] = static_cast<float>(code) * (1.0f / 256.0f);
        }
        return window;
    }

    RealArray run_resample_probe_path(
        const ZxGpuRealArray &input,
        int output_size,
        int axis,
        const ZxGpuWindowSpec &window,
        const std::string &domain,
        int path,
        int *observed_path,
        std::size_t trace_case = 0,
        const char *trace_path = nullptr)
    {
        const bool trace = trace_case != 0 && trace_path != nullptr;
        const auto trace_stage = [&](const char *stage) {
            if (trace)
            {
                std::cerr << "[resample-device-ab-trace] case=" << trace_case
                          << " path=" << trace_path << " stage=" << stage << std::endl;
            }
        };
        trace_stage("before_call");
        cusignal::zx_gpu_backend::filtering_test_hooks::set_resample_path_override(path);
        const ZxGpuRealArray result = cusignal::zx_gpu_backend::filtering::resample(
            input, output_size, axis, window, domain);
        trace_stage("after_resample");
        cusignal::core::throw_on_zx_gpu_error(
            cudaDeviceSynchronize(),
            "cudaDeviceSynchronize resample device A/B");
        trace_stage("after_device_sync");
        *observed_path =
            cusignal::zx_gpu_backend::filtering_test_hooks::consume_last_resample_path();
        const RealArray host_result = result.get();
        trace_stage("after_get");
        return host_result;
    }

    struct ResamplePathTimings
    {
        TimingStats e2e;
        TimingStats kernel;
    };

    ResamplePathTimings benchmark_resample_probe_path(
        const ZxGpuRealArray &input,
        int output_size,
        int path,
        const CliOptions &options)
    {
        cusignal::zx_gpu_backend::filtering_test_hooks::set_resample_path_override(path);
        ResamplePathTimings timings;
        timings.e2e = benchmark_host_latency(options, [&]() {
            const auto result = cusignal::zx_gpu_backend::filtering::resample(
                input, output_size, 0, std::string("hann"), "time");
            (void)result;
            cusignal::core::throw_on_zx_gpu_error(
                cudaDeviceSynchronize(),
                "cudaDeviceSynchronize resample threshold e2e");
        });
        if (cusignal::zx_gpu_backend::filtering_test_hooks::consume_last_resample_path() != path)
        {
            throw std::runtime_error("resample E2E benchmark path mismatch");
        }
        timings.kernel = benchmark_gpu_kernel_latency(options, [&]() {
            (void)cusignal::zx_gpu_backend::filtering::resample(
                input, output_size, 0, std::string("hann"), "time");
        });
        if (cusignal::zx_gpu_backend::filtering_test_hooks::consume_last_resample_path() != path)
        {
            throw std::runtime_error("resample kernel benchmark path mismatch");
        }
        return timings;
    }

    bool resample_auto_uses_windowed_pack(
        const Shape &shape,
        int output_size,
        int axis,
        const ZxGpuWindowSpec &window,
        const std::string &domain)
    {
        return cusignal::zx_gpu_backend::filtering_test_hooks::
            resample_auto_uses_windowed_pack(
                shape, output_size, axis, window, domain);
    }

    struct ResampleAutoRouteCase
    {
        Shape shape;
        int output_size;
        int axis;
        std::string window;
        std::string domain;
        bool expected;
    };

    const std::vector<ResampleAutoRouteCase> &resample_auto_route_cases()
    {
        static const std::vector<ResampleAutoRouteCase> cases = {
            {Shape{1048576}, 1572864, 0, "hann", "time", true},
            {Shape{1, 1048576}, 1572864, -1, "hann", "time", true},
            {Shape{1048576}, 1572863, 0, "hann", "time", false},
            {Shape{1048576}, 1572865, 0, "hann", "time", false},
            {Shape{1048575}, 1572864, 0, "hann", "time", false},
            {Shape{1048577}, 1572864, 0, "hann", "time", false},
            {Shape{1048576}, 1572864, 0, "hann", "freq", false},
            {Shape{1048576}, 1572864, 0, "hamming", "time", false},
            {Shape{2, 1048576}, 1572864, 1, "hann", "time", false},
            {Shape{1048576, 2}, 1572864, 0, "hann", "time", false},
        };
        return cases;
    }

    std::size_t validate_resample_auto_route_cases(std::ostream *route_report)
    {
        const auto &cases = resample_auto_route_cases();
        for (std::size_t route_index = 0; route_index < cases.size(); ++route_index)
        {
            const ResampleAutoRouteCase &route_case = cases[route_index];
            const bool observed = resample_auto_uses_windowed_pack(
                route_case.shape,
                route_case.output_size,
                route_case.axis,
                ZxGpuWindowSpec{route_case.window},
                route_case.domain);
            if (observed != route_case.expected)
            {
                std::ostringstream message;
                message << "resample host auto-route mismatch: case=" << route_index + 1
                        << " observed=" << observed
                        << " expected=" << route_case.expected;
                throw std::runtime_error(message.str());
            }
            if (route_report != nullptr)
            {
                std::ostringstream shape_text;
                for (std::size_t index = 0; index < route_case.shape.size(); ++index)
                {
                    if (index != 0)
                    {
                        shape_text << 'x';
                    }
                    shape_text << route_case.shape[index];
                }
                *route_report << "auto_" << route_index + 1 << '\t' << shape_text.str() << '\t'
                              << route_case.axis << '\t' << route_case.output_size << '\t'
                              << route_case.window << '\t' << route_case.domain << '\t'
                              << (observed ? kResamplePathWindowedPack : kResamplePathGeneric)
                              << '\t'
                              << (route_case.expected ? kResamplePathWindowedPack
                                                      : kResamplePathGeneric)
                              << '\n';
            }
        }
        return cases.size();
    }

    int run_resample_auto_route_host_probe()
    {
        const std::size_t checked_cases = validate_resample_auto_route_cases(nullptr);
        std::cout << "[resample-auto-route-host] PASS checked_cases=" << checked_cases
                  << " device_arrays=0 resample_calls=0\n";
        return 0;
    }

    struct ResampleSweepBatch
    {
        std::size_t input_size = 0;
        std::size_t output_size = 0;
        int batch = 0;
        float pack_e2e_ms = 0.0f;
        float windowed_e2e_ms = 0.0f;
        float pack_kernel_ms = 0.0f;
        float windowed_kernel_ms = 0.0f;
        bool dual_gain = false;
    };

    int run_resample_device_ab_probe()
    {
        ResamplePathOverrideReset reset;
        std::ofstream report;
        std::ofstream route_report;
        std::ofstream summary_report;
        const char *report_path = std::getenv("CUSIGNAL_RESAMPLE_DEVICE_AB_REPORT");
        if (report_path != nullptr && report_path[0] != '\0')
        {
            report.open(report_path);
            route_report.open(std::string(report_path) + ".routes.tsv");
            summary_report.open(std::string(report_path) + ".summary.tsv");
            if (!report || !route_report || !summary_report)
            {
                throw std::runtime_error("failed to open resample device A/B report");
            }
            report << "input_size\toutput_size\tbatch\tpack_e2e_ms\twindowed_e2e_ms\t"
                      "pack_kernel_ms\twindowed_kernel_ms\tdual_gain\n";
            route_report << "case\tshape\taxis\toutput_size\twindow\tdomain\t"
                            "observed_path\texpected_path\n";
            summary_report << "checked_cases\tchecked_float_outputs\tinvalid_window_checks\t"
                              "all_routes_pass\t"
                              "main_size_gain_pass\tsweep_min_gain\twarmup\trepeat\t"
                              "batches\tprobe_pass\n";
        }

        struct CorrectnessCase
        {
            Shape shape;
            int output_size;
            int axis;
            std::string window;
            std::string domain;
        };
        const std::vector<CorrectnessCase> cases = {
            {Shape{1}, 2, 0, "", "time"},
            {Shape{2}, 1, 0, "", "time"},
            {Shape{2}, 3, 0, "hann", "time"},
            {Shape{3}, 2, 0, "hann", "time"},
            {Shape{7}, 7, 0, "", "time"},
            {Shape{8}, 8, 0, "hann", "time"},
            {Shape{7}, 11, 0, "hann", "time"},
            {Shape{8}, 12, 0, "hann", "time"},
            {Shape{11}, 7, 0, "hann", "time"},
            {Shape{12}, 8, 0, "hann", "time"},
            {Shape{9}, 13, 0, "explicit_host", "time"},
            {Shape{8}, 12, 0, "explicit_host", "time"},
            {Shape{12}, 8, 0, "explicit_host", "time"},
            {Shape{8}, 12, 0, "explicit_device", "time"},
            {Shape{12}, 8, 0, "explicit_device", "time"},
            {Shape{8}, 12, 0, "hamming", "time"},
            {Shape{3, 8}, 12, 1, "hann", "time"},
            {Shape{8, 3}, 12, 0, "hann", "time"},
            {Shape{2, 7, 3}, 11, 1, "hann", "time"},
            {Shape{12}, 20, -1, "hann", "freq"},
            {Shape{12}, 18, -1, "hann", "time"},
            {Shape{1023}, 1535, 0, "hann", "time"},
            {Shape{1024}, 1536, 0, "hann", "time"},
            {Shape{1025}, 1537, 0, "hann", "time"},
            {Shape{1048576}, 1572864, 0, "hann", "time"},
            {Shape{1, 1048576}, 1572864, -1, "hann", "time"},
            {Shape{1048576}, 1572864, 0, "hann", "freq"},
            {Shape{1048576}, 1572864, 0, "hamming", "time"},
            {Shape{2, 1048576}, 1572864, 1, "hann", "time"},
            {Shape{1048576, 2}, 1572864, 0, "hann", "time"},
            {Shape{1572864}, 1048576, 0, "hann", "time"},
        };

        const bool trace = std::getenv("CUSIGNAL_RESAMPLE_DEVICE_AB_TRACE") != nullptr;
        std::size_t selected_case = 0;
        if (const char *case_text = std::getenv("CUSIGNAL_RESAMPLE_DEVICE_AB_CASE");
            case_text != nullptr && case_text[0] != '\0')
        {
            char *end = nullptr;
            const unsigned long long parsed = std::strtoull(case_text, &end, 10);
            if (end == case_text || *end != '\0' || parsed == 0 || parsed > cases.size())
            {
                throw std::invalid_argument(
                    "CUSIGNAL_RESAMPLE_DEVICE_AB_CASE must select an existing one-based case");
            }
            selected_case = static_cast<std::size_t>(parsed);
        }

        std::size_t checked_cases = 0;
        std::size_t checked_outputs = 0;
        bool all_routes_pass = true;
        const std::size_t auto_route_checks = validate_resample_auto_route_cases(
            route_report ? static_cast<std::ostream *>(&route_report) : nullptr);
        for (std::size_t case_index = 0; case_index < cases.size(); ++case_index)
        {
            const std::size_t case_number = case_index + 1;
            if (selected_case != 0 && selected_case != case_number)
            {
                continue;
            }
            const CorrectnessCase &test_case = cases[case_index];
            if (trace)
            {
                std::cerr << "[resample-device-ab-trace] case=" << case_number
                          << " stage=case_begin" << std::endl;
            }
            const ZxGpuRealArray input = ZxGpuRealArray::from_host(
                make_generated_real_array(test_case.shape, 0.95f, 0.0f));
            const int normalized_axis =
                test_case.axis < 0
                    ? test_case.axis + static_cast<int>(test_case.shape.size())
                    : test_case.axis;
            ZxGpuWindowSpec window_spec = std::string(test_case.window);
            std::optional<ZxGpuRealSignal> device_window;
            if (test_case.window == "explicit_host")
            {
                window_spec = make_resample_probe_window(
                    test_case.shape[static_cast<std::size_t>(normalized_axis)]);
            }
            else if (test_case.window == "explicit_device")
            {
                device_window.emplace(ZxGpuRealSignal::from_host(
                    make_resample_probe_window(
                        test_case.shape[static_cast<std::size_t>(normalized_axis)])));
                window_spec = *device_window;
            }
            int generic_path = kResamplePathAuto;
            int fused_path = kResamplePathAuto;
            int windowed_path = kResamplePathAuto;
            int automatic_path = kResamplePathAuto;
            const auto run_traced_path = [&](int path, const char *path_name, int *observed_path) {
                RealArray result = run_resample_probe_path(
                    input,
                    test_case.output_size,
                    test_case.axis,
                    window_spec,
                    test_case.domain,
                    path,
                    observed_path,
                    trace ? case_number : 0,
                    trace ? path_name : nullptr);
                if (trace)
                {
                    std::cerr << "[resample-device-ab-trace] case=" << case_number
                              << " path=" << path_name << " stage=path_end observed="
                              << *observed_path << std::endl;
                }
                return result;
            };
            const RealArray generic =
                run_traced_path(kResamplePathGeneric, "generic", &generic_path);
            const RealArray fused =
                run_traced_path(kResamplePathFused, "pack", &fused_path);
            const RealArray windowed = run_traced_path(
                kResamplePathWindowedPack, "windowed_pack", &windowed_path);
            const RealArray automatic =
                run_traced_path(kResamplePathAuto, "auto", &automatic_path);
            const int expected_automatic_path = resample_auto_uses_windowed_pack(
                                                    test_case.shape,
                                                    test_case.output_size,
                                                    test_case.axis,
                                                    window_spec,
                                                    test_case.domain)
                                                    ? kResamplePathWindowedPack
                                                    : kResamplePathGeneric;
            if (generic_path != kResamplePathGeneric ||
                fused_path != kResamplePathFused ||
                windowed_path != kResamplePathWindowedPack ||
                automatic_path != expected_automatic_path)
            {
                std::ostringstream message;
                message << "resample path selection mismatch: generic=" << generic_path
                        << " fused=" << fused_path
                        << " windowed=" << windowed_path
                        << " automatic=" << automatic_path;
                throw std::runtime_error(message.str());
            }
            all_routes_pass = all_routes_pass && automatic_path == expected_automatic_path;

            std::size_t first_mismatch = 0;
            if (!bitwise_equal_real_arrays(generic, fused, &first_mismatch))
            {
                std::ostringstream message;
                message << "resample generic/fused mismatch: input_size="
                        << test_case.shape[static_cast<std::size_t>(
                               test_case.axis < 0
                                   ? test_case.axis + static_cast<int>(test_case.shape.size())
                                   : test_case.axis)]
                        << " output_size=" << test_case.output_size
                        << " axis=" << test_case.axis
                        << " index=" << first_mismatch;
                throw std::runtime_error(message.str());
            }
            if (!bitwise_equal_real_arrays(fused, windowed, &first_mismatch))
            {
                std::ostringstream message;
                message << "resample pack/windowed-pack mismatch: output_size="
                        << test_case.output_size
                        << " axis=" << test_case.axis
                        << " window=" << test_case.window
                        << " index=" << first_mismatch;
                throw std::runtime_error(message.str());
            }
            const RealArray &expected_auto =
                expected_automatic_path == kResamplePathWindowedPack ? windowed : generic;
            if (!bitwise_equal_real_arrays(automatic, expected_auto, &first_mismatch))
            {
                std::ostringstream message;
                message << "resample automatic path mismatch: output_size="
                        << test_case.output_size << " index=" << first_mismatch;
                throw std::runtime_error(message.str());
            }
            if (route_report)
            {
                std::ostringstream shape_text;
                for (std::size_t index = 0; index < test_case.shape.size(); ++index)
                {
                    if (index != 0)
                    {
                        shape_text << 'x';
                    }
                    shape_text << test_case.shape[index];
                }
                route_report << case_number << '\t' << shape_text.str() << '\t'
                             << test_case.axis << '\t' << test_case.output_size << '\t'
                             << (test_case.window.empty() ? "none" : test_case.window) << '\t'
                             << test_case.domain << '\t' << automatic_path << '\t'
                             << expected_automatic_path << '\n';
            }
            ++checked_cases;
            checked_outputs += generic.values.size();
            if (trace)
            {
                std::cerr << "[resample-device-ab-trace] case=" << case_number
                          << " stage=case_end" << std::endl;
            }
        }

        if (selected_case != 0)
        {
            std::cout << "[resample-device-ab] " << (all_routes_pass ? "PASS" : "FAIL")
                      << " selected_case=" << selected_case
                      << " checked_cases=" << checked_cases
                      << " checked_float_outputs=" << checked_outputs
                      << " auto_route_checks=" << auto_route_checks
                      << " invalid_window_checks=not_run sweep=not_run\n";
            return all_routes_pass ? 0 : 1;
        }

        std::size_t invalid_window_checks = 0;
        const ZxGpuRealArray invalid_input = ZxGpuRealArray::from_host(
            make_generated_real_array(Shape{8}, 0.95f, 0.0f));
        const auto expect_invalid_window = [&](const ZxGpuWindowSpec &window_spec, const char *label) {
            if (trace)
            {
                std::cerr << "[resample-device-ab-trace] invalid_window=" << label
                          << " stage=begin" << std::endl;
            }
            cusignal::zx_gpu_backend::filtering_test_hooks::set_resample_path_override(
                kResamplePathWindowedPack);
            try
            {
                (void)cusignal::zx_gpu_backend::filtering::resample(
                    invalid_input, 12, 0, window_spec, "time");
                cusignal::core::throw_on_zx_gpu_error(
                    cudaDeviceSynchronize(),
                    "cudaDeviceSynchronize resample invalid window");
            }
            catch (const std::invalid_argument &)
            {
                ++invalid_window_checks;
                if (trace)
                {
                    std::cerr << "[resample-device-ab-trace] invalid_window=" << label
                              << " stage=pass" << std::endl;
                }
                return;
            }
            throw std::runtime_error(std::string("resample invalid window did not throw: ") + label);
        };
        expect_invalid_window(RealSignal{}, "empty host window");
        expect_invalid_window(ZxGpuRealSignal{}, "empty device window");
        expect_invalid_window(make_resample_probe_window(7), "wrong host window length");
        expect_invalid_window(
            ZxGpuRealSignal::from_host(make_resample_probe_window(7)),
            "wrong device window length");

        const bool correctness_only =
            std::getenv("CUSIGNAL_RESAMPLE_DEVICE_AB_CORRECTNESS_ONLY") != nullptr;
        if (correctness_only)
        {
            if (summary_report)
            {
                summary_report << checked_cases << '\t' << checked_outputs << '\t'
                               << invalid_window_checks << '\t'
                               << (all_routes_pass ? "true" : "false")
                               << "\tnot_run\t" << kResampleSweepMinGain
                               << "\t0\t0\t0\t" << (all_routes_pass ? "true" : "false") << '\n';
            }
            std::cout << "[resample-device-ab] " << (all_routes_pass ? "PASS" : "FAIL")
                      << " checked_cases=" << checked_cases
                      << " checked_float_outputs=" << checked_outputs
                      << " auto_route_checks=" << auto_route_checks
                      << " invalid_window_checks=" << invalid_window_checks
                      << " sweep=not_run\n";
            return all_routes_pass ? 0 : 1;
        }

        const std::array<std::size_t, 5> sweep_sizes = {
            1024, 16384, 65536, 262144, 1048576};
        std::vector<ResampleSweepBatch> sweep;
        CliOptions timing_options;
        timing_options.warmup = 2;
        timing_options.repeat = 10;
        for (const std::size_t input_size : sweep_sizes)
        {
            const std::size_t output_size = input_size + input_size / 2;
            const ZxGpuRealArray input = ZxGpuRealArray::from_host(
                make_generated_real_array(Shape{input_size}, 0.95f, 0.0f));
            for (int batch = 1; batch <= 5; ++batch)
            {
                ResamplePathTimings pack;
                ResamplePathTimings windowed;
                if (batch % 2 == 1)
                {
                    pack = benchmark_resample_probe_path(
                        input, static_cast<int>(output_size), kResamplePathFused, timing_options);
                    windowed = benchmark_resample_probe_path(
                        input, static_cast<int>(output_size), kResamplePathWindowedPack, timing_options);
                }
                else
                {
                    windowed = benchmark_resample_probe_path(
                        input, static_cast<int>(output_size), kResamplePathWindowedPack, timing_options);
                    pack = benchmark_resample_probe_path(
                        input, static_cast<int>(output_size), kResamplePathFused, timing_options);
                }
                sweep.push_back(ResampleSweepBatch{
                    input_size,
                    output_size,
                    batch,
                    pack.e2e.median_ms,
                    windowed.e2e.median_ms,
                    pack.kernel.median_ms,
                    windowed.kernel.median_ms,
                    windowed.e2e.median_ms <=
                            pack.e2e.median_ms * (1.0f - kResampleSweepMinGain) &&
                        windowed.kernel.median_ms <=
                            pack.kernel.median_ms * (1.0f - kResampleSweepMinGain)});
            }
        }

        std::map<std::size_t, int> gain_batches;
        for (const ResampleSweepBatch &row : sweep)
        {
            if (row.dual_gain)
            {
                ++gain_batches[row.input_size];
            }
        }
        const bool main_size_gain_pass =
            gain_batches[kResampleFusedInputSize] >= 4;
        const bool probe_ok = all_routes_pass && main_size_gain_pass;
        if (report)
        {
            for (const ResampleSweepBatch &row : sweep)
            {
                report << row.input_size << '\t' << row.output_size << '\t' << row.batch << '\t'
                       << row.pack_e2e_ms << '\t' << row.windowed_e2e_ms << '\t'
                       << row.pack_kernel_ms << '\t' << row.windowed_kernel_ms << '\t'
                       << (row.dual_gain ? "true" : "false") << '\n';
            }
        }
        if (summary_report)
        {
            summary_report << checked_cases << '\t' << checked_outputs << '\t'
                           << invalid_window_checks << '\t'
                           << (all_routes_pass ? "true" : "false") << '\t'
                           << (main_size_gain_pass ? "true" : "false") << '\t'
                           << kResampleSweepMinGain << '\t'
                           << timing_options.warmup << '\t' << timing_options.repeat
                           << "\t5\t" << (probe_ok ? "true" : "false") << '\n';
        }
        std::cout << "[resample-device-ab] " << (probe_ok ? "PASS" : "FAIL")
                  << " checked_cases=" << checked_cases
                  << " checked_float_outputs=" << checked_outputs
                  << " auto_route_checks=" << auto_route_checks
                  << " invalid_window_checks=" << invalid_window_checks
                  << " main_size_gain=" << (main_size_gain_pass ? "pass" : "fail") << '\n';
        return probe_ok ? 0 : 1;
    }

    float median_speedup(const std::optional<TimingStats> &lhs, const std::optional<TimingStats> &rhs)
    {
        if (!lhs.has_value() || !rhs.has_value() || rhs->median_ms <= 0.0)
        {
            return 0.0;
        }
        return lhs->median_ms / rhs->median_ms;
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

    std::vector<FilteringCase> load_cases(const fs::path &manifest_path, const std::string &category)
    {
        std::vector<FilteringCase> cases;
        const JsonValue manifest = cusignal_test::json::parse(read_text_file(manifest_path));
        const JsonObject &root = as_object(manifest);
        const JsonArray &case_array = as_array(root.at(category == "accuracy" ? "accuracy_cases" : "perf_cases"));
        const fs::path base = manifest_path.parent_path();
        const std::string op = manifest_path.parent_path().filename().string();
        for (const JsonValue &item : case_array)
        {
            const JsonObject &object = as_object(item);
            FilteringCase test_case;
            test_case.id = get_string(object, "id");
            test_case.category = category;
            test_case.axis = get_optional_int(object, "axis", -1); // 处理轴
            test_case.up = get_optional_int(object, "up", 1); // 上采样倍数
            test_case.down = get_optional_int(object, "down", 1); // 下采样倍数
            test_case.q = get_optional_int(object, "q", 1); // 抽取倍数
            test_case.n = get_optional_int(object, "n", 0); // 滤波阶数或 FFT 长度
            test_case.n_chans = get_optional_int(object, "n_chans", 0); // channelize_poly 的通道数
            test_case.filter_order = get_optional_int(object, "filter_order", 0); // lfilter_zi 性能缩放阶数
            test_case.x_count = get_optional_int(object, "x_count", 0); // channelize_poly 性能缩放输入长度
            test_case.h_count = get_optional_int(object, "h_count", 0); // channelize_poly 性能缩放 tap 长度
            test_case.num = get_optional_int(object, "num", 0); // resample 输出长度
            test_case.padlen = get_optional_int(object, "padlen", -1); // filtfilt 填充长度
            test_case.irlen = get_optional_int(object, "irlen", -1); // filtfilt 冲激响应长度
            test_case.noise = get_optional_number(object, "noise", -1.0); // wiener 噪声功率
            test_case.freq = get_optional_number(object, "freq", 0.0); // freq_shift 频率
            test_case.fs = get_optional_number(object, "fs", 2.0); // 采样频率
            test_case.zero_phase = get_optional_bool(object, "zero_phase", true); // 启用零相位分支
            test_case.overwrite_data = get_optional_bool(object, "overwrite_data", false); // 原地 detrend 开关
            test_case.padtype = get_optional_string(object, "padtype").value_or("odd"); // 边界扩展模式
            test_case.method = get_optional_string(object, "method").value_or("pad"); // filtfilt 方法
            test_case.domain = get_optional_string(object, "domain").value_or("time"); // resample 域
            test_case.type = get_optional_string(object, "type").value_or("linear"); // detrend 模式
            test_case.input_kind = get_optional_string(object, "input_kind").value_or("real"); // 输入数据类型族
            test_case.dtype = get_optional_string(object, "dtype").value_or("float32"); // dtype 兼容性标签
            test_case.atol = get_optional_number(object, "atol", 0.0); // 绝对误差容限
            test_case.rtol = get_optional_number(object, "rtol", 0.0); // 相对误差容限
            if (const auto iter = object.find("x_shape"); iter != object.end()) test_case.x_shape = json_array_to_shape(iter->second);
            else if (const auto iter = object.find("input_shape"); iter != object.end()) test_case.x_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("zi_shape"); iter != object.end()) test_case.zi_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("sos_shape"); iter != object.end()) test_case.sos_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("data_shape"); iter != object.end()) test_case.data_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("expected_signal_shape"); iter != object.end()) test_case.expected_output_shape = json_array_to_shape(iter->second);
            else if (const auto iter = object.find("expected_output_shape"); iter != object.end()) test_case.expected_output_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("expected_state_shape"); iter != object.end()) test_case.expected_state_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("n_shape"); iter != object.end()) test_case.n_shape = json_array_to_shape(iter->second);
            if (const auto iter = object.find("mysize"); iter != object.end()) test_case.mysize = json_array_to_shape(iter->second);
            if (const auto iter = object.find("bp"); iter != object.end()) test_case.bp = json_array_to_indices(iter->second);
            if (const auto iter = object.find("window"); iter != object.end()) test_case.window = parse_window_spec(iter->second);
            if (auto v = get_optional_string(object, "x_file")) test_case.x_file = base / *v;
            else if (auto v = get_optional_string(object, "input_file")) test_case.x_file = base / *v;
            if (auto v = get_optional_string(object, "b_file")) test_case.b_file = base / *v;
            if (auto v = get_optional_string(object, "a_file")) test_case.a_file = base / *v;
            if (auto v = get_optional_string(object, "h_file")) test_case.h_file = base / *v;
            if (auto v = get_optional_string(object, "sos_file")) test_case.sos_file = base / *v;
            if (auto v = get_optional_string(object, "zi_file")) test_case.zi_file = base / *v;
            if (auto v = get_optional_string(object, "t_file")) test_case.t_file = base / *v;
            if (auto v = get_optional_string(object, "data_file")) test_case.data_file = base / *v;
            if (auto v = get_optional_string(object, "expected_signal_file")) test_case.expected_output_file = base / *v;
            else if (auto v = get_optional_string(object, "expected_output_file")) test_case.expected_output_file = base / *v;
            if (auto v = get_optional_string(object, "expected_state_file")) test_case.expected_state_file = base / *v;
            if (auto v = get_optional_string(object, "expected_time_file")) test_case.expected_time_file = base / *v;
            if (category == "perf")
            {
                populate_perf_inputs(op, test_case);
            }
            cases.push_back(std::move(test_case));
        }
        return cases;
    }

    DeviceOutputBundle materialize_like(const OutputBundle &) = delete;

    OutputBundle materialize(const DeviceOutputBundle &device)
    {
        OutputBundle host;
        host.main_complex = device.main_complex;
        if (device.main_complex)
        {
            host.complex_output = device.complex_output.get();
        }
        else
        {
            host.real_output = device.real_output.get();
        }
        host.has_state = device.has_state;
        if (device.has_state)
        {
            host.state = device.state.get();
        }
        host.has_time = device.has_time;
        if (device.has_time)
        {
            host.time = device.time.get();
        }
        return host;
    }

    std::size_t main_size(const OutputBundle &bundle)
    {
        return bundle.main_complex ? bundle.complex_output.values.size() : bundle.real_output.values.size();
    }

    OutputBundle make_real_output(const RealArray &output)
    {
        OutputBundle bundle;
        bundle.real_output = output;
        return bundle;
    }

    OutputBundle make_complex_output(const ComplexArray &output)
    {
        OutputBundle bundle;
        bundle.main_complex = true;
        bundle.complex_output = output;
        return bundle;
    }

    DeviceOutputBundle make_real_output(const ZxGpuRealArray &output)
    {
        DeviceOutputBundle bundle;
        bundle.real_output = output;
        return bundle;
    }

    DeviceOutputBundle make_complex_output(const ZxGpuComplexArray &output)
    {
        DeviceOutputBundle bundle;
        bundle.main_complex = true;
        bundle.complex_output = output;
        return bundle;
    }

    RealArray load_real_array(const fs::path &path, const Shape &shape)
    {
        return make_real_array_from_flat(shape, read_real_csv(path));
    }

    ComplexArray load_complex_array(const fs::path &path, const Shape &shape)
    {
        return make_complex_array_from_flat(shape, read_complex_csv(path));
    }

    const RealArray &get_x_real(const FilteringCase &test_case)
    {
        thread_local RealArray buffer;
        if (test_case.generated_real_x.has_value())
        {
            buffer = *test_case.generated_real_x;
        }
        else
        {
            buffer = load_real_array(test_case.x_file, test_case.x_shape);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    const ComplexArray &get_x_complex(const FilteringCase &test_case)
    {
        if (test_case.generated_complex_x.has_value())
        {
            return *test_case.generated_complex_x;
        }
        thread_local ComplexArray buffer;
        buffer = load_complex_array(test_case.x_file, test_case.x_shape);
        return buffer;
    }

    const RealSignal &get_b_signal(const FilteringCase &test_case)
    {
        thread_local RealSignal buffer;
        if (test_case.generated_b.has_value())
        {
            buffer = *test_case.generated_b;
        }
        else
        {
            buffer = read_real_csv(test_case.b_file);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    const RealSignal &get_a_signal(const FilteringCase &test_case)
    {
        thread_local RealSignal buffer;
        if (test_case.generated_a.has_value())
        {
            buffer = *test_case.generated_a;
        }
        else
        {
            buffer = read_real_csv(test_case.a_file);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    const RealSignal &get_h_signal(const FilteringCase &test_case)
    {
        thread_local RealSignal buffer;
        if (test_case.generated_h.has_value())
        {
            buffer = *test_case.generated_h;
        }
        else
        {
            buffer = read_real_csv(test_case.h_file);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    const RealArray &get_sos_array(const FilteringCase &test_case)
    {
        thread_local RealArray buffer;
        if (test_case.generated_sos.has_value())
        {
            buffer = *test_case.generated_sos;
        }
        else
        {
            buffer = load_real_array(test_case.sos_file, test_case.sos_shape);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    const RealArray &get_zi_array(const FilteringCase &test_case)
    {
        thread_local RealArray buffer;
        if (test_case.generated_zi.has_value())
        {
            buffer = *test_case.generated_zi;
        }
        else
        {
            buffer = load_real_array(test_case.zi_file, test_case.zi_shape);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    const RealSignal &get_t_signal(const FilteringCase &test_case)
    {
        thread_local RealSignal buffer;
        if (test_case.generated_t.has_value())
        {
            buffer = *test_case.generated_t;
        }
        else
        {
            buffer = read_real_csv(test_case.t_file);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    const RealArray &get_data_array(const FilteringCase &test_case)
    {
        thread_local RealArray buffer;
        if (test_case.generated_data.has_value())
        {
            buffer = *test_case.generated_data;
        }
        else
        {
            buffer = load_real_array(test_case.data_file, test_case.data_shape);
        }
        buffer = apply_dtype_quantization(buffer, test_case.dtype);
        return buffer;
    }

    void write_input_artifacts(const FilteringCase &test_case, std::vector<Artifact> *artifacts)
    {
        const auto write_real_input = [&](const std::string &role, const fs::path &path, const RealSignal &values) {
            if (path.empty())
            {
                return;
            }
            write_real_csv(path, values);
            if (artifacts != nullptr)
            {
                artifacts->push_back(Artifact{role, path});
            }
        };
        const auto write_complex_input =
            [&](const std::string &role, const fs::path &path, const ComplexSignal &values) {
                if (path.empty())
                {
                    return;
                }
                write_complex_csv(path, values);
                if (artifacts != nullptr)
                {
                    artifacts->push_back(Artifact{role, path});
                }
            };

        if (test_case.generated_real_x.has_value())
        {
            write_real_input("input_x", test_case.x_file, flatten(*test_case.generated_real_x));
        }
        if (test_case.generated_complex_x.has_value())
        {
            write_complex_input("input_x", test_case.x_file, flatten(*test_case.generated_complex_x));
        }
        if (test_case.generated_b.has_value())
        {
            write_real_input("input_b", test_case.b_file, *test_case.generated_b);
        }
        if (test_case.generated_a.has_value())
        {
            write_real_input("input_a", test_case.a_file, *test_case.generated_a);
        }
        if (test_case.generated_h.has_value())
        {
            write_real_input("input_h", test_case.h_file, *test_case.generated_h);
        }
        if (test_case.generated_sos.has_value())
        {
            write_real_input("input_sos", test_case.sos_file, flatten(*test_case.generated_sos));
        }
        if (test_case.generated_zi.has_value())
        {
            write_real_input("input_zi", test_case.zi_file, flatten(*test_case.generated_zi));
        }
        if (test_case.generated_t.has_value())
        {
            write_real_input("input_t", test_case.t_file, *test_case.generated_t);
        }
        if (test_case.generated_data.has_value())
        {
            write_real_input("input_data", test_case.data_file, flatten(*test_case.generated_data));
        }
    }

    OutputBundle expected_bundle_for(const std::string &op, const FilteringCase &test_case)
    {
        if (op == "firfilter" && test_case.input_kind == "complex")
        {
            return make_complex_output(load_complex_array(test_case.expected_output_file, test_case.expected_output_shape));
        }
        if (op == "hilbert" || op == "hilbert2" || op == "freq_shift" || op == "channelize_poly")
        {
            return make_complex_output(load_complex_array(test_case.expected_output_file, test_case.expected_output_shape));
        }
        return make_real_output(load_real_array(test_case.expected_output_file, test_case.expected_output_shape));
    }

    Runner resolve_runner(const std::string &op)
    {
        using namespace cusignal;
        if (op == "wiener")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(cpu::filtering::wiener(get_x_real(c), c.mysize, c.noise));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(zx_gpu_backend::filtering::wiener(get_x_real(c), c.mysize, c.noise));
                }};
        }
        if (op == "firfilter")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    if (c.input_kind == "complex")
                    {
                        if (!c.zi_file.empty())
                        {
                            throw std::runtime_error("firfilter complex input does not support zi accuracy cases");
                        }
                        return make_complex_output(cpu::filtering::firfilter(get_b_signal(c), get_x_complex(c), c.axis));
                    }
                    if (!c.zi_file.empty())
                    {
                        const auto result = cpu::filtering::firfilter(
                            get_b_signal(c), get_x_real(c), c.axis, get_zi_array(c));
                        OutputBundle bundle = make_real_output(result.output);
                        bundle.has_state = true;
                        bundle.state = result.final_state;
                        return bundle;
                    }
                    return make_real_output(cpu::filtering::firfilter(get_b_signal(c), get_x_real(c), c.axis));
                },
                [](const FilteringCase &c)
                {
                    if (c.input_kind == "complex")
                    {
                        if (!c.zi_file.empty())
                        {
                            throw std::runtime_error("firfilter complex input does not support zi accuracy cases");
                        }
                        return make_complex_output(zx_gpu_backend::filtering::firfilter(get_b_signal(c), get_x_complex(c), c.axis));
                    }
                    if (!c.zi_file.empty())
                    {
                        const auto result = zx_gpu_backend::filtering::firfilter(
                            get_b_signal(c), get_x_real(c), c.axis, get_zi_array(c));
                        DeviceOutputBundle bundle = make_real_output(result.output);
                        bundle.has_state = true;
                        bundle.state = result.final_state;
                        return bundle;
                    }
                    return make_real_output(zx_gpu_backend::filtering::firfilter(get_b_signal(c), get_x_real(c), c.axis));
                }};
        }
        if (op == "lfilter")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    if (!c.zi_file.empty())
                    {
                        const auto result = cpu::filtering::lfilter(
                            get_b_signal(c), get_a_signal(c), get_x_real(c), c.axis, get_zi_array(c));
                        OutputBundle bundle = make_real_output(result.output);
                        bundle.has_state = true;
                        bundle.state = result.final_state;
                        return bundle;
                    }
                    return make_real_output(cpu::filtering::lfilter(get_b_signal(c), get_a_signal(c), get_x_real(c), c.axis));
                },
                [](const FilteringCase &c)
                {
                    if (!c.zi_file.empty())
                    {
                        const auto result = zx_gpu_backend::filtering::lfilter(
                            get_b_signal(c), get_a_signal(c), get_x_real(c), c.axis, get_zi_array(c));
                        DeviceOutputBundle bundle = make_real_output(result.output);
                        bundle.has_state = true;
                        bundle.state = result.final_state;
                        return bundle;
                    }
                    return make_real_output(zx_gpu_backend::filtering::lfilter(get_b_signal(c), get_a_signal(c), get_x_real(c), c.axis));
                }};
        }
        if (op == "lfilter_zi")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(make_real_array_from_flat(
                        Shape{get_a_signal(c).size() > get_b_signal(c).size()
                                  ? get_a_signal(c).size() - 1
                                  : get_b_signal(c).size() - 1},
                        cpu::filtering::lfilter_zi(get_b_signal(c), get_a_signal(c))));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(ZxGpuRealArray::from_host(make_real_array_from_flat(
                        Shape{get_a_signal(c).size() > get_b_signal(c).size()
                                  ? get_a_signal(c).size() - 1
                                  : get_b_signal(c).size() - 1},
                        zx_gpu_backend::filtering::lfilter_zi(get_b_signal(c), get_a_signal(c)).get())));
                }};
        }
        if (op == "firfilter_zi")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    const RealSignal output = cpu::filtering::firfilter_zi(get_b_signal(c));
                    return make_real_output(make_real_array_from_flat(Shape{output.size()}, output));
                },
                [](const FilteringCase &c)
                {
                    const RealSignal output = zx_gpu_backend::filtering::firfilter_zi(get_b_signal(c)).get();
                    return make_real_output(ZxGpuRealArray::from_host(make_real_array_from_flat(Shape{output.size()}, output)));
                }};
        }
        if (op == "firfilter2")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(
                        cpu::filtering::firfilter2(get_b_signal(c), get_x_real(c), c.axis, c.padtype, c.padlen, c.method, c.irlen));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(
                        zx_gpu_backend::filtering::firfilter2(get_b_signal(c), get_x_real(c), c.axis, c.padtype, c.padlen, c.method, c.irlen));
                }};
        }
        if (op == "filtfilt")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(
                        cpu::filtering::filtfilt(get_b_signal(c), get_a_signal(c), get_x_real(c), c.axis, c.padtype, c.padlen, c.method, c.irlen));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(
                        zx_gpu_backend::filtering::filtfilt(get_b_signal(c), get_a_signal(c), get_x_real(c), c.axis, c.padtype, c.padlen, c.method, c.irlen));
                }};
        }
        if (op == "sosfilt")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    if (!c.zi_file.empty())
                    {
                        const auto result = cpu::filtering::sosfilt(
                            get_sos_array(c), get_x_real(c), c.axis, get_zi_array(c));
                        OutputBundle bundle = make_real_output(result.output);
                        bundle.has_state = true;
                        bundle.state = result.final_state;
                        return bundle;
                    }
                    return make_real_output(cpu::filtering::sosfilt(get_sos_array(c), get_x_real(c), c.axis));
                },
                [](const FilteringCase &c)
                {
                    if (!c.zi_file.empty())
                    {
                        const auto result = zx_gpu_backend::filtering::sosfilt(
                            get_sos_array(c), get_x_real(c), c.axis, get_zi_array(c));
                        DeviceOutputBundle bundle = make_real_output(result.output);
                        bundle.has_state = true;
                        bundle.state = result.final_state;
                        return bundle;
                    }
                    return make_real_output(zx_gpu_backend::filtering::sosfilt(get_sos_array(c), get_x_real(c), c.axis));
                }};
        }
        if (op == "hilbert")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_complex_output(cpu::filtering::hilbert(get_x_real(c), c.n, c.axis));
                },
                [](const FilteringCase &c)
                {
                    return make_complex_output(zx_gpu_backend::filtering::hilbert(get_x_real(c), c.n, c.axis));
                }};
        }
        if (op == "hilbert2")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_complex_output(cpu::filtering::hilbert2(get_x_real(c), c.n_shape));
                },
                [](const FilteringCase &c)
                {
                    return make_complex_output(zx_gpu_backend::filtering::hilbert2(get_x_real(c), c.n_shape));
                }};
        }
        if (op == "detrend")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(cpu::filtering::detrend(get_data_array(c), c.axis, c.type, c.bp, c.overwrite_data));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(zx_gpu_backend::filtering::detrend(get_data_array(c), c.axis, c.type, c.bp, c.overwrite_data));
                }};
        }
        if (op == "freq_shift")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_complex_output(cpu::filtering::freq_shift(get_x_complex(c), c.freq, c.fs));
                },
                [](const FilteringCase &c)
                {
                    return make_complex_output(zx_gpu_backend::filtering::freq_shift(get_x_complex(c), c.freq, c.fs));
                }};
        }
        if (op == "channelize_poly")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    const auto result = cpu::filtering::channelize_poly(flatten(get_x_complex(c)), get_h_signal(c), c.n_chans);
                    return make_complex_output(result.channels);
                },
                [](const FilteringCase &c)
                {
                    const auto result = zx_gpu_backend::filtering::channelize_poly(flatten(get_x_complex(c)), get_h_signal(c), c.n_chans);
                    return make_complex_output(result.channels);
                }};
        }
        if (op == "decimate")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(cpu::filtering::decimate(get_x_real(c), c.q, c.n, c.axis, c.zero_phase));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(zx_gpu_backend::filtering::decimate(get_x_real(c), c.q, c.n, c.axis, c.zero_phase));
                }};
        }
        if (op == "resample")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    if (!c.t_file.empty())
                    {
                        const auto result = cpu::filtering::resample(get_x_real(c), c.num, get_t_signal(c), c.axis, c.window, c.domain);
                        OutputBundle bundle = make_real_output(result.output);
                        bundle.has_time = true;
                        bundle.time = result.time;
                        return bundle;
                    }
                    return make_real_output(cpu::filtering::resample(get_x_real(c), c.num, c.axis, c.window, c.domain));
                },
                [](const FilteringCase &c)
                {
                    if (!c.t_file.empty())
                    {
                        const auto result = zx_gpu_backend::filtering::resample(get_x_real(c), c.num, get_t_signal(c), c.axis, to_zx_gpu_window_spec(c.window), c.domain);
                        DeviceOutputBundle bundle = make_real_output(result.output);
                        bundle.has_time = true;
                        bundle.time = result.time;
                        return bundle;
                    }
                    return make_real_output(zx_gpu_backend::filtering::resample(get_x_real(c), c.num, c.axis, to_zx_gpu_window_spec(c.window), c.domain));
                }};
        }
        if (op == "resample_poly")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(cpu::filtering::resample_poly(get_x_real(c), c.up, c.down, c.axis, c.window));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(zx_gpu_backend::filtering::resample_poly(get_x_real(c), c.up, c.down, c.axis, to_zx_gpu_window_spec(c.window)));
                }};
        }
        if (op == "upfirdn")
        {
            return Runner{
                [](const FilteringCase &c)
                {
                    return make_real_output(cpu::filtering::upfirdn(get_h_signal(c), get_x_real(c), c.up, c.down, c.axis));
                },
                [](const FilteringCase &c)
                {
                    return make_real_output(zx_gpu_backend::filtering::upfirdn(get_h_signal(c), get_x_real(c), c.up, c.down, c.axis));
                }};
        }
        throw std::runtime_error("unsupported filtering operator: " + op);
    }

    ErrorMetrics output_error(const OutputBundle &lhs, const OutputBundle &rhs, float mixed_atol = 1.0e-5f)
    {
        if (lhs.main_complex != rhs.main_complex)
        {
            throw std::runtime_error("main output kind mismatch");
        }
        return lhs.main_complex ? compute_error_metrics(flatten(lhs.complex_output), flatten(rhs.complex_output), mixed_atol)
                                : compute_error_metrics(flatten(lhs.real_output), flatten(rhs.real_output), mixed_atol);
    }

    CaseReport evaluate_firfilter_complex_shared_output_contract(
        std::size_t tap_count,
        const char *case_id)
    {
        CaseReport report;
        report.case_id = case_id;
        report.category = "accuracy";

        const RealSignal taps = make_lowpass_like_taps(tap_count);
        const ComplexArray input = make_generated_complex_array(Shape{3, 2305}, 0.75f);
        const ComplexArray cpu_output = cusignal::cpu::filtering::firfilter(taps, input, -1);
        const ZxGpuRealSignal taps_device = ZxGpuRealSignal::from_host(taps);
        const ZxGpuComplexArray input_device = ZxGpuComplexArray::from_host(input);
        const ComplexArray gpu_output =
            cusignal::zx_gpu_backend::filtering::firfilter(taps_device, input_device, -1).get();

        report.samples = cpu_output.values.size();
        report.cpu_gpu_error =
            compute_error_metrics(flatten(cpu_output), flatten(gpu_output), 1.0e-5f);
        report.pass = report.cpu_gpu_error.max_abs_error <= 5.0e-5f &&
            report.cpu_gpu_error.mixed_error <= 1.0e-4f;
        if (!report.pass)
        {
            report.note = "complex FIR shared-output contract mismatch";
        }
        std::cout << "[filtering/firfilter] " << case_id << '='
                  << (report.pass ? "PASS" : "FAIL")
                  << " max_abs=" << report.cpu_gpu_error.max_abs_error
                  << " mixed=" << report.cpu_gpu_error.mixed_error << '\n';
        return report;
    }

    bool output_within_tolerance(const OutputBundle &lhs, const OutputBundle &rhs, float atol, float rtol)
    {
        if (lhs.main_complex != rhs.main_complex)
        {
            return false;
        }
        return lhs.main_complex ? within_tolerance(flatten(lhs.complex_output), flatten(rhs.complex_output), atol, rtol)
                                : within_tolerance(flatten(lhs.real_output), flatten(rhs.real_output), atol, rtol);
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

    std::size_t infer_case_samples(const FilteringCase &test_case)
    {
        if (const std::size_t expected = shape_size(test_case.expected_output_shape); expected != 0)
        {
            return expected;
        }
        if (const std::size_t x = shape_size(test_case.x_shape); x != 0)
        {
            return x;
        }
        if (const std::size_t data = shape_size(test_case.data_shape); data != 0)
        {
            return data;
        }
        return 0;
    }

    CaseReport make_failed_case_report(const FilteringCase &test_case, const std::string &message)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;
        report.samples = infer_case_samples(test_case);
        report.pass = false;
        report.note = message;
        report.cpu_gpu_error.exact_match = false;
        report.cpu_gpu_error.first_mismatch_index = report.samples > 0 ? 0 : -1;
        report.cpu_gpu_error.compared_samples = report.samples;
        return report;
    }

    OperatorSummary summarize_cases(const std::string &op, const std::vector<CaseReport> &reports)
    {
        OperatorSummary summary;
        summary.operator_name = op;
        float ref_abs = 0.0;
        float ref_rel = 0.0;
        float ref_mixed = 0.0;
        float ref_rmse = 0.0;
        bool have_ref = false;
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
            if (report.category == "accuracy") ++summary.accuracy_cases;
            else ++summary.perf_cases;
            summary.cpu_gpu_error.max_abs_error = std::max(summary.cpu_gpu_error.max_abs_error, report.cpu_gpu_error.max_abs_error);
            summary.cpu_gpu_error.max_rel_error = std::max(summary.cpu_gpu_error.max_rel_error, report.cpu_gpu_error.max_rel_error);
            summary.cpu_gpu_error.mixed_error = std::max(summary.cpu_gpu_error.mixed_error, report.cpu_gpu_error.mixed_error);
            summary.cpu_gpu_error.rmse = std::max(summary.cpu_gpu_error.rmse, report.cpu_gpu_error.rmse);
            if (report.cpu_reference_error.has_value())
            {
                have_ref = true;
                ref_abs = std::max(ref_abs, report.cpu_reference_error->max_abs_error);
                ref_rel = std::max(ref_rel, report.cpu_reference_error->max_rel_error);
                ref_mixed = std::max(ref_mixed, report.cpu_reference_error->mixed_error);
                ref_rmse = std::max(ref_rmse, report.cpu_reference_error->rmse);
            }
            if (report.cpu_perf.has_value()) cpu_perf.push_back(report.cpu_perf->median_ms);
            if (report.gpu_e2e_perf.has_value()) gpu_e2e_perf.push_back(report.gpu_e2e_perf->median_ms);
            if (cusignal_test::report::valid_timing(report.gpu_kernel_perf)) gpu_kernel_perf.push_back(report.gpu_kernel_perf->median_ms);
        }
        if (have_ref)
        {
            summary.reference_error = ErrorMetrics{};
            summary.reference_error->max_abs_error = ref_abs;
            summary.reference_error->max_rel_error = ref_rel;
            summary.reference_error->mixed_error = ref_mixed;
            summary.reference_error->rmse = ref_rmse;
        }
        if (!cpu_perf.empty()) summary.cpu_perf = summarize_timings(cpu_perf);
        if (!gpu_e2e_perf.empty()) summary.gpu_e2e_perf = summarize_timings(gpu_e2e_perf);
        if (!gpu_kernel_perf.empty()) summary.gpu_kernel_perf = summarize_timings(gpu_kernel_perf);
        return summary;
    }

    void write_operator_reports(
        const std::string &op,
        const CliOptions &options,
        const std::vector<CaseReport> &reports)
    {
        const OperatorSummary summary = summarize_cases(op, reports);
        cusignal_test::report::write_operator_report(
            "filtering",
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
        cusignal_test::report::update_module_reports("filtering", module_report_root());
    }

    void print_terminal_summary(const std::string &op, const OperatorSummary &summary)
    {
        std::cout << "[filtering/" << op << "] " << (summary.pass ? "PASS" : "FAIL")
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
            std::cout << "gpu_perf_ms   : e2e_median=" << format_fixed(summary.gpu_e2e_perf->median_ms)
                      << "  kernel_median=" << (cusignal_test::report::valid_timing(summary.gpu_kernel_perf) ? format_fixed(summary.gpu_kernel_perf->median_ms) : "n/a")
                      << "  p95=" << format_fixed(summary.gpu_e2e_perf->p95_ms)
                      << "  e2e_speedup=" << format_fixed(median_speedup(summary.cpu_perf, summary.gpu_e2e_perf)) << "x"
                      << "  kernel_speedup=" << (cusignal_test::report::valid_timing(summary.gpu_kernel_perf) ? format_fixed(median_speedup(summary.cpu_perf, summary.gpu_kernel_perf)) + "x" : "n/a")
                      << '\n';
        }
        else
        {
            std::cout << "gpu_perf_ms   : not_run (accuracy-only; use perf/full case set for timing)\n";
        }
        std::cout << "reports       : data/.reports_staging/unit/filtering/" << op << "/latest_summary.md\n";
    }

    CaseReport evaluate_accuracy_case(const std::string &op, const FilteringCase &test_case, const Runner &runner)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;
        const OutputBundle cpu_output =
            apply_dtype_quantization(runner.cpu(test_case), test_case.dtype);
        const OutputBundle gpu_output =
            apply_dtype_quantization(materialize(runner.gpu(test_case)), test_case.dtype);
        const OutputBundle expected =
            apply_dtype_quantization(expected_bundle_for(op, test_case), test_case.dtype);
        report.samples = main_size(cpu_output);
        report.cpu_gpu_error = output_error(cpu_output, gpu_output, test_case.atol);
        report.cpu_reference_error = output_error(cpu_output, expected, test_case.atol);
        report.gpu_reference_error = output_error(gpu_output, expected, test_case.atol);
        report.pass = output_within_tolerance(cpu_output, expected, test_case.atol, test_case.rtol) &&
                      output_within_tolerance(gpu_output, expected, test_case.atol, test_case.rtol);
        if (test_case.expected_state_file != fs::path())
        {
            const RealArray expected_state = apply_dtype_quantization(
                load_real_array(test_case.expected_state_file, test_case.expected_state_shape),
                test_case.dtype);
            if (!cpu_output.has_state || !gpu_output.has_state ||
                !within_tolerance(flatten(cpu_output.state), flatten(expected_state), test_case.atol, test_case.rtol) ||
                !within_tolerance(flatten(gpu_output.state), flatten(expected_state), test_case.atol, test_case.rtol))
            {
                report.pass = false;
                report.note = "state mismatch";
            }
        }
        if (test_case.expected_time_file != fs::path())
        {
            const RealSignal expected_time = apply_dtype_quantization(
                read_real_csv(test_case.expected_time_file),
                test_case.dtype);
            if (!cpu_output.has_time || !gpu_output.has_time ||
                !within_tolerance(cpu_output.time, expected_time, test_case.atol, test_case.rtol) ||
                !within_tolerance(gpu_output.time, expected_time, test_case.atol, test_case.rtol))
            {
                report.pass = false;
                report.note = "time mismatch";
            }
        }
        return report;
    }

    CaseReport evaluate_perf_case(const std::string &op, const FilteringCase &test_case, const Runner &runner, const CliOptions &options)
    {
        CaseReport report;
        report.case_id = test_case.id;
        report.category = test_case.category;
        std::optional<ZxGpuRealArray> detrend_device_data;
        if (op == "detrend")
        {
            const RealArray data = get_data_array(test_case);
            report.samples = data.values.size();
            detrend_device_data.emplace(ZxGpuRealArray::from_host(data));
        }
        std::optional<ZxGpuComplexArray> freq_shift_x;
        if (op == "freq_shift")
        {
            const ComplexArray x = get_x_complex(test_case);
            report.samples = x.values.size();
            freq_shift_x.emplace(ZxGpuComplexArray::from_host(x));
        }
        std::optional<ZxGpuComplexSignal> channelize_x;
        std::optional<ZxGpuRealSignal> channelize_h;
        if (op == "channelize_poly")
        {
            const ComplexSignal x = flatten(get_x_complex(test_case));
            const RealSignal h = get_h_signal(test_case);
            report.samples = x.size();
            channelize_x.emplace(ZxGpuComplexSignal::from_host(x));
            channelize_h.emplace(ZxGpuRealSignal::from_host(h));
        }
        std::optional<ZxGpuRealArray> filtering_x;
        std::optional<ZxGpuRealSignal> filtering_b;
        std::optional<ZxGpuRealSignal> filtering_h;
        std::optional<ZxGpuRealArray> filtering_sos;
        std::optional<ZxGpuRealArray> filtering_zi;
        if (op == "firfilter" || op == "firfilter2" || op == "decimate" ||
            op == "hilbert" || op == "hilbert2" || op == "wiener" ||
            op == "resample" || op == "resample_poly")
        {
            const RealArray x = get_x_real(test_case);
            report.samples = x.values.size();
            filtering_x.emplace(ZxGpuRealArray::from_host(x));
        }
        if (op == "firfilter" || op == "firfilter2")
        {
            filtering_b.emplace(ZxGpuRealSignal::from_host(get_b_signal(test_case)));
        }
        if (op == "firfilter" && !test_case.zi_file.empty())
        {
            filtering_zi.emplace(ZxGpuRealArray::from_host(get_zi_array(test_case)));
        }
        if (op == "sosfilt")
        {
            const RealArray x = get_x_real(test_case);
            report.samples = x.values.size();
            filtering_x.emplace(ZxGpuRealArray::from_host(x));
            filtering_sos.emplace(ZxGpuRealArray::from_host(get_sos_array(test_case)));
            if (!test_case.zi_file.empty())
            {
                filtering_zi.emplace(ZxGpuRealArray::from_host(get_zi_array(test_case)));
            }
        }
        if (op == "upfirdn")
        {
            const RealArray x = get_x_real(test_case);
            report.samples = x.values.size();
            filtering_x.emplace(ZxGpuRealArray::from_host(x));
            filtering_h.emplace(ZxGpuRealSignal::from_host(get_h_signal(test_case)));
        }
        std::optional<ZxGpuRealSignal> filtering_t;
        std::optional<ZxGpuRealSignal> filtering_window_signal;
        ZxGpuWindowSpec filtering_window = to_zx_gpu_window_spec_with_device_array(
            test_case.window,
            filtering_window_signal);
        if (op == "resample" && !test_case.t_file.empty())
        {
            filtering_t.emplace(ZxGpuRealSignal::from_host(get_t_signal(test_case)));
        }
        auto run_gpu_perf = [&]() -> DeviceOutputBundle {
            if (detrend_device_data.has_value())
            {
                return make_real_output(cusignal::zx_gpu_backend::filtering::detrend(
                    *detrend_device_data,
                    test_case.axis,
                    test_case.type,
                    test_case.bp,
                    test_case.overwrite_data));
            }
            if (freq_shift_x.has_value())
            {
                return make_complex_output(cusignal::zx_gpu_backend::filtering::freq_shift(
                    *freq_shift_x,
                    test_case.freq,
                    test_case.fs));
            }
            if (channelize_x.has_value() && channelize_h.has_value())
            {
                const auto result = cusignal::zx_gpu_backend::filtering::channelize_poly(
                    *channelize_x,
                    *channelize_h,
                    test_case.n_chans);
                return make_complex_output(result.channels);
            }
            if (op == "firfilter" && filtering_b.has_value() && filtering_x.has_value())
            {
                if (filtering_zi.has_value())
                {
                    const auto result = cusignal::zx_gpu_backend::filtering::firfilter(
                        *filtering_b,
                        *filtering_x,
                        test_case.axis,
                        *filtering_zi);
                    DeviceOutputBundle bundle = make_real_output(result.output);
                    bundle.has_state = true;
                    bundle.state = result.final_state;
                    return bundle;
                }
                return make_real_output(cusignal::zx_gpu_backend::filtering::firfilter(
                    *filtering_b,
                    *filtering_x,
                    test_case.axis));
            }
            if (op == "firfilter2" && filtering_b.has_value() && filtering_x.has_value())
            {
                return make_real_output(cusignal::zx_gpu_backend::filtering::firfilter2(
                    *filtering_b,
                    *filtering_x,
                    test_case.axis,
                    test_case.padtype,
                    test_case.padlen,
                    test_case.method,
                    test_case.irlen));
            }
            if (op == "sosfilt" && filtering_sos.has_value() && filtering_x.has_value())
            {
                if (filtering_zi.has_value())
                {
                    const auto result = cusignal::zx_gpu_backend::filtering::sosfilt(
                        *filtering_sos,
                        *filtering_x,
                        test_case.axis,
                        *filtering_zi);
                    DeviceOutputBundle bundle = make_real_output(result.output);
                    bundle.has_state = true;
                    bundle.state = result.final_state;
                    return bundle;
                }
                return make_real_output(cusignal::zx_gpu_backend::filtering::sosfilt(
                    *filtering_sos,
                    *filtering_x,
                    test_case.axis));
            }
            if (op == "upfirdn" && filtering_h.has_value() && filtering_x.has_value())
            {
                return make_real_output(cusignal::zx_gpu_backend::filtering::upfirdn(
                    *filtering_h,
                    *filtering_x,
                    test_case.up,
                    test_case.down,
                    test_case.axis));
            }
            if (op == "decimate" && filtering_x.has_value())
            {
                return make_real_output(cusignal::zx_gpu_backend::filtering::decimate(
                    *filtering_x,
                    test_case.q,
                    test_case.n,
                    test_case.axis,
                    test_case.zero_phase));
            }
            if (op == "wiener" && filtering_x.has_value())
            {
                return make_real_output(cusignal::zx_gpu_backend::filtering::wiener(
                    *filtering_x,
                    test_case.mysize,
                    test_case.noise));
            }
            if (op == "resample" && filtering_x.has_value())
            {
                if (filtering_t.has_value())
                {
                    const auto result = cusignal::zx_gpu_backend::filtering::resample(
                        *filtering_x,
                        test_case.num,
                        *filtering_t,
                        test_case.axis,
                        filtering_window,
                        test_case.domain);
                    DeviceOutputBundle bundle = make_real_output(result.output);
                    bundle.has_time = true;
                    bundle.time = result.time;
                    return bundle;
                }
                return make_real_output(cusignal::zx_gpu_backend::filtering::resample(
                    *filtering_x,
                    test_case.num,
                    test_case.axis,
                    filtering_window,
                    test_case.domain));
            }
            if (op == "resample_poly" && filtering_x.has_value())
            {
                return make_real_output(cusignal::zx_gpu_backend::filtering::resample_poly(
                    *filtering_x,
                    test_case.up,
                    test_case.down,
                    test_case.axis,
                    filtering_window));
            }
            if (op == "hilbert" && filtering_x.has_value())
            {
                return make_complex_output(cusignal::zx_gpu_backend::filtering::hilbert(
                    *filtering_x,
                    test_case.n,
                    test_case.axis));
            }
            if (op == "hilbert2" && filtering_x.has_value())
            {
                return make_complex_output(cusignal::zx_gpu_backend::filtering::hilbert2(
                    *filtering_x,
                    test_case.n_shape));
            }
            return runner.gpu(test_case);
        };

        auto run_gpu_e2e = [&]() -> OutputBundle {
            // Refresh every host-backed operand before each E2E sample.  The
            // kernel benchmark deliberately uses the already prepared device
            // operands in run_gpu_perf() so its CUDA-event value is kernel-only.
            if (detrend_device_data.has_value())
                detrend_device_data->copy_from(get_data_array(test_case));
            if (freq_shift_x.has_value())
                freq_shift_x->copy_from(get_x_complex(test_case));
            if (channelize_x.has_value())
            {
                channelize_x->copy_from(flatten(get_x_complex(test_case)));
                channelize_h->copy_from(get_h_signal(test_case));
            }
            if (filtering_x.has_value())
                filtering_x->copy_from(get_x_real(test_case));
            if (filtering_b.has_value())
                filtering_b->copy_from(get_b_signal(test_case));
            if (filtering_sos.has_value())
                filtering_sos->copy_from(get_sos_array(test_case));
            if (filtering_zi.has_value())
                filtering_zi->copy_from(get_zi_array(test_case));
            if (filtering_h.has_value())
                filtering_h->copy_from(get_h_signal(test_case));
            if (filtering_t.has_value())
                filtering_t->copy_from(get_t_signal(test_case));
            if (const auto *window_values = std::get_if<RealSignal>(&test_case.window))
            {
                filtering_window_signal.reset();
                filtering_window = to_zx_gpu_window_spec_with_device_array(
                    *window_values, filtering_window_signal);
            }
            return materialize(run_gpu_perf());
        };

        OutputBundle gpu_output;
        if (!options.gpu_only_perf)
        {
            gpu_output = materialize(run_gpu_perf());
            report.samples = main_size(gpu_output);
        }
        else if (report.samples == 0)
        {
            report.samples = infer_case_samples(test_case);
        }
        if (!options.gpu_only_perf)
        {
            const OutputBundle cpu_output = runner.cpu(test_case);
            report.cpu_gpu_error = output_error(cpu_output, gpu_output, test_case.atol);
        }
        report.pass = true;
        if (!options.gpu_only_perf)
        {
            report.cpu_perf = benchmark_host_latency(options, [&]() { (void)runner.cpu(test_case); });
        }
        report.gpu_e2e_perf = benchmark_host_latency(options, [&]() {
            (void)run_gpu_e2e();
            cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize gpu e2e");
        });
        report.gpu_kernel_perf = benchmark_gpu_kernel_latency(options, [&]() { (void)run_gpu_perf(); });
        if (options.emit_report)
        {
            if (!options.gpu_only_perf)
            {
                const fs::path gen_root = generated_root(op);
                write_input_artifacts(test_case, &report.artifacts);
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

    int run_filtering_operator_tests(const std::string &op, int argc, char **argv)
    {
        const CliOptions options = parse_cli(argc, argv);
        const Runner runner = resolve_runner(op);
        std::vector<CaseReport> reports;
        if (include_accuracy_cases(options))
        {
            const auto accuracy_cases = load_cases(reference_root(op) / "manifest.json", "accuracy");
            for (const FilteringCase &test_case : accuracy_cases)
            {
                try
                {
                    reports.push_back(evaluate_accuracy_case(op, test_case, runner));
                }
                catch (const std::exception &error)
                {
                    std::cerr << "[filtering/" << op << "] accuracy case " << test_case.id
                              << " failed before report emission: " << error.what() << '\n';
                    reports.push_back(make_failed_case_report(test_case, error.what()));
                }
            }
            if (op == "firfilter")
            {
                const auto append_shared_output_contract = [&](std::size_t tap_count, const char *case_id)
                {
                    try
                    {
                        reports.push_back(evaluate_firfilter_complex_shared_output_contract(tap_count, case_id));
                    }
                    catch (const std::exception &error)
                    {
                        CaseReport report;
                        report.case_id = case_id;
                        report.category = "accuracy";
                        report.pass = false;
                        report.note = error.what();
                        reports.push_back(std::move(report));
                    }
                };
                append_shared_output_contract(193, "complex64_shared_quad_output");
                append_shared_output_contract(257, "complex64_shared_dual_output");
            }
        }
        if (include_perf_cases(options))
        {
            const auto perf_cases = load_cases(generated_root(op) / "manifest.json", "perf");
            for (const FilteringCase &test_case : perf_cases)
            {
                try
                {
                    reports.push_back(evaluate_perf_case(op, test_case, runner, options));
                }
                catch (const std::exception &error)
                {
                    std::cerr << "[filtering/" << op << "] perf case " << test_case.id
                              << " failed before report emission: " << error.what() << '\n';
                    reports.push_back(make_failed_case_report(test_case, error.what()));
                }
            }
        }
        write_operator_reports(op, options, reports);
        update_module_reports();
        const OperatorSummary summary = summarize_cases(op, reports);
        print_terminal_summary(op, summary);
        return summary.pass ? 0 : 1;
    }
} // namespace

int run_wiener_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("wiener", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_firfilter_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("firfilter", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_lfilter_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("lfilter", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_firfilter_zi_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("firfilter_zi", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_lfilter_zi_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("lfilter_zi", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_firfilter2_tests(int argc, char **argv)
{
    try
    {
        if (std::getenv("CUSIGNAL_FIRFILTER2_DEVICE_AB") != nullptr)
        {
            return run_firfilter2_device_ab_probe();
        }
        return run_filtering_operator_tests("firfilter2", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_filtfilt_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("filtfilt", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_sosfilt_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("sosfilt", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_hilbert_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("hilbert", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_hilbert2_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("hilbert2", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_detrend_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("detrend", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_freq_shift_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("freq_shift", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_channelize_poly_tests(int argc, char **argv)
{
    try
    {
        if (std::getenv("CUSIGNAL_CHANNELIZE_DEVICE_AB") != nullptr)
        {
            return run_channelize_device_ab_probe();
        }
        return run_filtering_operator_tests("channelize_poly", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_decimate_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("decimate", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_resample_tests(int argc, char **argv)
{
    try
    {
        if (std::getenv("CUSIGNAL_RESAMPLE_AUTO_ROUTE_HOST_PROBE") != nullptr)
        {
            return run_resample_auto_route_host_probe();
        }
        if (std::getenv("CUSIGNAL_RESAMPLE_DEVICE_AB") != nullptr)
        {
            return run_resample_device_ab_probe();
        }
        return run_filtering_operator_tests("resample", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_resample_poly_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("resample_poly", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}

int run_upfirdn_tests(int argc, char **argv)
{
    try
    {
        return run_filtering_operator_tests("upfirdn", argc, argv);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[filtering] ERROR: " << error.what() << '\n';
        return 1;
    }
}
