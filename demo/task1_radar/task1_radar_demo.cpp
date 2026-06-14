#include "task1_radar_cuda.hpp"

#include <cuda_runtime_api.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <optional>
#include <random>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include <sys/resource.h>
#include <unistd.h>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"
#include "cusignal/radartools/radartools.hpp"
#include "cusignal/waveforms/waveforms.hpp"

namespace cusignal_demo::task1_radar
{
    namespace fs = std::filesystem;

    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
    using cusignal::radartools_api::AmbgfunSurfaceResult;
    using cusignal::radartools_api::CudaAmbgfunSurfaceResult;

    struct ScenarioConfig
    {
        int scale_level = 3;                     // 任务级规模档位，默认 L3 保持历史场景。
        float fs = 1.0e6f;                       // 采样率，单位 Hz，决定快时间采样间隔。
        int num_pulses = 64;                     // 脉冲数，也就是慢时间维长度；增大可提升多普勒分辨率。
        int samples_per_pulse = 256;             // 每个脉冲的快时间采样点数；增大可提升距离向规模。
        int template_length = 64;                // 发射 chirp 模板长度；必须不大于 samples_per_pulse。
        float prf = 2000.0f;                     // 脉冲重复频率，单位 Hz，用于多普勒轴换算。
        int delay_samples = 48;                  // 注入目标的距离延迟，单位为采样点。
        float doppler_hz = 125.0f;               // 注入目标的多普勒频移，单位 Hz。
        float target_amplitude = 1.0f;           // 注入目标幅度，越大目标越容易被检测。
        float snr_db = 20.0f;                    // 信噪比，单位 dB，用于生成接收噪声。
        unsigned int seed = 20260414u;           // 随机种子，固定后可复现实验输入。
        float chirp_f0 = 5.0e4f;                 // chirp 起始频率，单位 Hz。
        float chirp_f1 = 2.0e5f;                 // chirp 终止频率，单位 Hz。
        bool pulse_compression_normalize = true; // 脉冲压缩是否归一化模板能量。
        std::string pulse_compression_window;    // 脉冲压缩窗函数；空字符串表示不加窗。
        std::string pulse_doppler_window = "hann"; // 多普勒处理窗函数。
        int pulse_compression_nfft = 256;        // 脉冲压缩 FFT 点数，建议不小于 samples_per_pulse。
        int pulse_doppler_nfft = 64;             // 多普勒 FFT 点数，建议不小于 num_pulses。
        Shape cfar_guard_cells{2, 2};            // CA-CFAR 保护单元数，格式为 {距离向, 多普勒向}。
        Shape cfar_reference_cells{8, 8};        // CA-CFAR 参考单元数，格式为 {距离向, 多普勒向}。
        float cfar_pfa = 1.0e-3f;                // CA-CFAR 虚警概率，用于计算门限因子。
    };

    struct ErrorMetrics
    {
        float mixed_error = 0.0f;
        float max_abs = 0.0f;
        float max_rel = 0.0f;
        float rmse = 0.0f;
    };

    constexpr float kMixedErrorAtol = 1.0e-5f;
    constexpr float kMixedErrorScale = 1.0e-2f;

    struct StageTiming
    {
        std::string name;
        float cpu_ms = 0.0;
        float gpu_ms = 0.0;
    };

    struct DemoOptions
    {
        int repeat = 1;
        int scale_level = 3;
        bool invalid_input_checks = false;
        bool skip_timing_validation = false;
    };

    struct ResourceSnapshot
    {
        double rss_current_mib = 0.0;
        double rss_peak_mib = 0.0;
        double cuda_free_mib = 0.0;
        double cuda_total_mib = 0.0;
        int cuda_device = -1;
        std::string cuda_device_name = "unknown";
    };

    struct ValidationCheck
    {
        std::string name;
        bool pass = false;
        double value = 0.0;
        double limit = 0.0;
        std::string detail;
    };

    struct ValidationResult
    {
        bool pass = true;
        std::vector<ValidationCheck> checks;
    };

    struct ValidationThresholds
    {
        float gpu_total_baseline_ms = 0.80f;
        float gpu_total_multiplier = 1.25f;
        float gpu_total_hard_limit_ms = 1.0f;
        float pulse_compression_mixed = 1.0e-4f;
        float pulse_doppler_mixed = 1.0e-4f;
        float cfar_threshold_mixed = 5.0e-3f;
        float ambgfun_surface_mixed = 1.0e-4f;
        float timing_relative_jitter = 0.35f;
        float cuda_free_drift_mib = 32.0f;
        float rss_current_drift_mib = 64.0f;
    };

    long long scale_value(const ScenarioConfig &config)
    {
        return static_cast<long long>(config.num_pulses) *
            static_cast<long long>(config.samples_per_pulse);
    }

    ScenarioConfig scenario_for_scale_level(int scale_level)
    {
        if (scale_level < 1 || scale_level > 6)
        {
            throw std::invalid_argument("scale_level must be in [1, 6]");
        }
        ScenarioConfig config;
        config.scale_level = scale_level;
        switch (scale_level)
        {
        case 1:
            config.num_pulses = 32;
            config.samples_per_pulse = 128;
            config.template_length = 32;
            config.pulse_compression_nfft = 128;
            config.pulse_doppler_nfft = 32;
            break;
        case 2:
            config.num_pulses = 48;
            config.samples_per_pulse = 256;
            config.template_length = 64;
            config.pulse_compression_nfft = 256;
            config.pulse_doppler_nfft = 64;
            break;
        case 3:
            break;
        case 4:
            config.num_pulses = 96;
            config.samples_per_pulse = 512;
            config.template_length = 128;
            config.pulse_compression_nfft = 512;
            config.pulse_doppler_nfft = 128;
            break;
        case 5:
            config.num_pulses = 128;
            config.samples_per_pulse = 1024;
            config.template_length = 256;
            config.pulse_compression_nfft = 1024;
            config.pulse_doppler_nfft = 128;
            break;
        case 6:
            config.num_pulses = 192;
            config.samples_per_pulse = 1536;
            config.template_length = 384;
            config.pulse_compression_nfft = 2048;
            config.pulse_doppler_nfft = 256;
            break;
        default:
            break;
        }
        config.delay_samples = std::max(1, config.samples_per_pulse * 3 / 16);
        return config;
    }

    ValidationThresholds thresholds_for_scale_level(int scale_level)
    {
        ValidationThresholds thresholds;
        switch (scale_level)
        {
        case 1:
            thresholds.gpu_total_baseline_ms = 8.0f;
            thresholds.gpu_total_hard_limit_ms = 10.0f;
            break;
        case 2:
            thresholds.gpu_total_baseline_ms = 4.0f;
            thresholds.gpu_total_hard_limit_ms = 5.0f;
            break;
        case 3:
            break;
        case 4:
            thresholds.gpu_total_baseline_ms = 8.0f;
            thresholds.gpu_total_hard_limit_ms = 10.0f;
            thresholds.cfar_threshold_mixed = 5.0e-2f;
            break;
        case 5:
            thresholds.gpu_total_baseline_ms = 24.0f;
            thresholds.gpu_total_hard_limit_ms = 30.0f;
            thresholds.pulse_doppler_mixed = 3.0e-4f;
            thresholds.cfar_threshold_mixed = 1.0e-1f;
            break;
        case 6:
            thresholds.gpu_total_baseline_ms = 60.0f;
            thresholds.gpu_total_hard_limit_ms = 75.0f;
            thresholds.pulse_doppler_mixed = 5.0e-4f;
            thresholds.cfar_threshold_mixed = 5.0e-1f;
            break;
        default:
            throw std::invalid_argument("scale_level must be in [1, 6]");
        }
        return thresholds;
    }

    struct DetectionSummary
    {
        bool found = false;
        int range_bin = -1;
        int doppler_bin = -1;
        float doppler_hz = 0.0f;
        float power = 0.0f;
    };

    struct CpuArtifacts
    {
        ComplexSignal tx_template;
        ComplexArray rx_matrix;
        ComplexArray pulse_compression;
        ComplexArray pulse_doppler;
        RealArray range_doppler_power;
        RealArray cfar_threshold;
        RealArray cfar_detections;
        AmbgfunSurfaceResult ambgfun;
    };

    struct GpuArtifacts
    {
        cusignal::core::CudaComplexArray pulse_compression;
        cusignal::core::CudaComplexArray pulse_doppler;
        cusignal::core::CudaRealArray range_doppler_power;
        cusignal::core::CudaRealArray cfar_threshold;
        cusignal::core::CudaRealArray cfar_detections;
        CudaAmbgfunSurfaceResult ambgfun;
    };

    struct HostGpuArtifacts
    {
        ComplexArray pulse_compression;
        ComplexArray pulse_doppler;
        RealArray range_doppler_power;
        RealArray cfar_threshold;
        RealArray cfar_detections;
        AmbgfunSurfaceResult ambgfun;
    };

    struct DemoRunResult
    {
        CpuArtifacts cpu;
        HostGpuArtifacts gpu;
        DetectionSummary expected_detection;
        DetectionSummary cpu_detection;
        DetectionSummary gpu_detection;
        std::vector<StageTiming> stage_timings;
        ErrorMetrics pulse_compression_error;
        ErrorMetrics pulse_doppler_error;
        ErrorMetrics cfar_threshold_error;
        ErrorMetrics ambgfun_error;
        float cpu_total_ms = 0.0f;
        float gpu_total_ms = 0.0f;
    };

    struct IterationSummary
    {
        int index = 0;
        bool pass = false;
        float cpu_total_ms = 0.0f;
        float gpu_total_ms = 0.0f;
        ResourceSnapshot resource_after;
    };

    fs::path repo_root()
    {
        return fs::path(CUSIGNAL_SOURCE_DIR);
    }

    fs::path generated_root()
    {
        return repo_root() / "data" / "generated" / "demo" / "task1_radar";
    }

    fs::path report_root()
    {
        return repo_root() / "data" / "reports" / "demo" / "task1_radar";
    }

    bool is_finite_positive(float value)
    {
        return std::isfinite(value) && value > 0.0f;
    }

    bool is_supported_window(const std::string &window)
    {
        return window.empty() || window == "hann" || window == "hamming" || window == "blackman" ||
            window == "boxcar";
    }

    void validate_config(const ScenarioConfig &config)
    {
        if (!is_finite_positive(config.fs)) throw std::invalid_argument("fs must be finite and > 0");
        if (!is_finite_positive(config.prf)) throw std::invalid_argument("prf must be finite and > 0");
        if (config.num_pulses <= 0) throw std::invalid_argument("num_pulses must be > 0");
        if (config.samples_per_pulse <= 0) throw std::invalid_argument("samples_per_pulse must be > 0");
        if (config.template_length <= 0) throw std::invalid_argument("template_length must be > 0");
        if (config.template_length > config.samples_per_pulse)
            throw std::invalid_argument("template_length must be <= samples_per_pulse");
        if (config.delay_samples < 0 ||
            config.delay_samples + config.template_length > config.samples_per_pulse)
            throw std::invalid_argument("delay_samples plus template_length must fit samples_per_pulse");
        if (!std::isfinite(config.doppler_hz) || std::fabs(config.doppler_hz) >= 0.5f * config.prf)
            throw std::invalid_argument("doppler_hz must be finite and within PRF Nyquist range");
        if (!is_finite_positive(config.target_amplitude))
            throw std::invalid_argument("target_amplitude must be finite and > 0");
        if (!std::isfinite(config.snr_db)) throw std::invalid_argument("snr_db must be finite");
        if (!is_finite_positive(config.chirp_f0) || !is_finite_positive(config.chirp_f1) ||
            config.chirp_f1 <= config.chirp_f0 || config.chirp_f1 >= 0.5f * config.fs)
            throw std::invalid_argument("chirp_f0/chirp_f1 must be finite, increasing, and below Nyquist");
        if (!is_supported_window(config.pulse_compression_window))
            throw std::invalid_argument("pulse_compression_window is not supported");
        if (!is_supported_window(config.pulse_doppler_window))
            throw std::invalid_argument("pulse_doppler_window is not supported");
        if (config.pulse_compression_nfft < config.samples_per_pulse)
            throw std::invalid_argument("pulse_compression_nfft must be >= samples_per_pulse");
        if (config.pulse_doppler_nfft < config.num_pulses)
            throw std::invalid_argument("pulse_doppler_nfft must be >= num_pulses");
        if (config.cfar_guard_cells.size() != 2 || config.cfar_reference_cells.size() != 2)
            throw std::invalid_argument("cfar_guard_cells/cfar_reference_cells must be rank-2");
        for (std::size_t dim = 0; dim < 2; ++dim)
        {
            if (config.cfar_reference_cells[dim] == 0)
                throw std::invalid_argument("cfar_reference_cells entries must be > 0");
            const std::size_t guard = config.cfar_guard_cells[dim];
            const std::size_t reference = config.cfar_reference_cells[dim];
            const std::size_t extent = dim == 0 ? static_cast<std::size_t>(config.pulse_doppler_nfft)
                                                : static_cast<std::size_t>(config.pulse_compression_nfft);
            if (2 * (guard + reference) + 1 >= extent)
                throw std::invalid_argument("cfar_guard_cells/cfar_reference_cells window exceeds data extent");
        }
        if (!std::isfinite(config.cfar_pfa) || config.cfar_pfa <= 0.0f || config.cfar_pfa >= 1.0f)
            throw std::invalid_argument("cfar_pfa must be in (0, 1)");
    }

    double read_current_rss_mib()
    {
        std::ifstream statm("/proc/self/statm");
        long pages = 0;
        long resident = 0;
        if (statm >> pages >> resident)
        {
            const long page_size = sysconf(_SC_PAGESIZE);
            if (page_size > 0)
            {
                return static_cast<double>(resident) * static_cast<double>(page_size) / (1024.0 * 1024.0);
            }
        }
        struct rusage usage;
        if (getrusage(RUSAGE_SELF, &usage) == 0)
        {
            return static_cast<double>(usage.ru_maxrss) / 1024.0;
        }
        return 0.0;
    }

    double read_peak_rss_mib()
    {
        struct rusage usage;
        if (getrusage(RUSAGE_SELF, &usage) == 0)
        {
            return static_cast<double>(usage.ru_maxrss) / 1024.0;
        }
        return 0.0;
    }

    ResourceSnapshot capture_resource_snapshot()
    {
        ResourceSnapshot snapshot;
        snapshot.rss_current_mib = read_current_rss_mib();
        snapshot.rss_peak_mib = read_peak_rss_mib();
        int device = -1;
        if (cudaGetDevice(&device) == cudaSuccess)
        {
            snapshot.cuda_device = device;
            cudaDeviceProp prop{};
            if (cudaGetDeviceProperties(&prop, device) == cudaSuccess)
            {
                snapshot.cuda_device_name = prop.name;
            }
        }
        std::size_t free_bytes = 0;
        std::size_t total_bytes = 0;
        if (cudaMemGetInfo(&free_bytes, &total_bytes) == cudaSuccess)
        {
            snapshot.cuda_free_mib = static_cast<double>(free_bytes) / (1024.0 * 1024.0);
            snapshot.cuda_total_mib = static_cast<double>(total_bytes) / (1024.0 * 1024.0);
        }
        return snapshot;
    }

    DemoOptions parse_options(int argc, char **argv)
    {
        DemoOptions options;
        for (int index = 1; index < argc; ++index)
        {
            const std::string arg = argv[index];
            if (arg == "--repeat")
            {
                if (index + 1 >= argc)
                {
                    throw std::invalid_argument("--repeat requires a positive integer");
                }
                options.repeat = std::atoi(argv[++index]);
                if (options.repeat < 1)
                {
                    throw std::invalid_argument("--repeat must be >= 1");
                }
            }
            else if (arg == "--scale-level")
            {
                if (index + 1 >= argc)
                {
                    throw std::invalid_argument("--scale-level requires a value in [1, 6]");
                }
                options.scale_level = std::atoi(argv[++index]);
                if (options.scale_level < 1 || options.scale_level > 6)
                {
                    throw std::invalid_argument("--scale-level must be in [1, 6]");
                }
            }
            else if (arg == "--invalid-input-checks")
            {
                options.invalid_input_checks = true;
            }
            else if (arg == "--skip-timing-validation")
            {
                options.skip_timing_validation = true;
            }
            else if (arg == "--help" || arg == "-h")
            {
                std::cout << "usage: task1_radar_demo [--repeat N] [--scale-level 1..6] [--invalid-input-checks] "
                             "[--skip-timing-validation]\n";
                std::exit(0);
            }
            else
            {
                throw std::invalid_argument("unknown argument: " + arg);
            }
        }
        return options;
    }

    std::string json_escape(const std::string &value)
    {
        std::ostringstream stream;
        for (char ch : value)
        {
            switch (ch)
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
                stream << ch;
                break;
            }
        }
        return stream.str();
    }

    std::string bool_json(bool value)
    {
        return value ? "true" : "false";
    }

    std::string shape_json(const Shape &shape)
    {
        std::ostringstream stream;
        stream << '[';
        for (std::size_t index = 0; index < shape.size(); ++index)
        {
            if (index != 0)
            {
                stream << ", ";
            }
            stream << shape[index];
        }
        stream << ']';
        return stream.str();
    }

    template <typename T>
    std::string number_string(T value, int precision = 9)
    {
        std::ostringstream stream;
        stream << std::setprecision(precision) << value;
        return stream.str();
    }

    void add_check(
        ValidationResult &result,
        const std::string &name,
        bool pass,
        double value,
        double limit,
        const std::string &detail)
    {
        result.pass = result.pass && pass;
        result.checks.push_back(ValidationCheck{name, pass, value, limit, detail});
    }

    std::string validation_json(const ValidationResult &validation, int indent = 2)
    {
        const std::string pad(static_cast<std::size_t>(indent), ' ');
        const std::string child(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << pad << "\"validation\": {\n";
        stream << child << "\"pass\": " << bool_json(validation.pass) << ",\n";
        stream << child << "\"checks\": [\n";
        for (std::size_t index = 0; index < validation.checks.size(); ++index)
        {
            const ValidationCheck &check = validation.checks[index];
            stream << child << "  {\"name\": \"" << json_escape(check.name) << "\", "
                   << "\"pass\": " << bool_json(check.pass) << ", "
                   << "\"value\": " << check.value << ", "
                   << "\"limit\": " << check.limit << ", "
                   << "\"detail\": \"" << json_escape(check.detail) << "\"}"
                   << (index + 1 == validation.checks.size() ? "\n" : ",\n");
        }
        stream << child << "]\n";
        stream << pad << "}";
        return stream.str();
    }

    std::string resource_snapshot_json(const ResourceSnapshot &snapshot, int indent)
    {
        const std::string pad(static_cast<std::size_t>(indent), ' ');
        const std::string child(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << pad << "{\n";
        stream << child << "\"rss_current_mib\": " << snapshot.rss_current_mib << ",\n";
        stream << child << "\"rss_peak_mib\": " << snapshot.rss_peak_mib << ",\n";
        stream << child << "\"cuda_free_mib\": " << snapshot.cuda_free_mib << ",\n";
        stream << child << "\"cuda_total_mib\": " << snapshot.cuda_total_mib << ",\n";
        stream << child << "\"cuda_device\": " << snapshot.cuda_device << ",\n";
        stream << child << "\"cuda_device_name\": \"" << json_escape(snapshot.cuda_device_name) << "\"\n";
        stream << pad << "}";
        return stream.str();
    }

    std::string resource_usage_json(const ResourceSnapshot &before, const ResourceSnapshot &after, int indent = 2)
    {
        const std::string pad(static_cast<std::size_t>(indent), ' ');
        const std::string child(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << pad << "\"resource_usage\": {\n";
        stream << child << "\"before\": " << resource_snapshot_json(before, indent + 2) << ",\n";
        stream << child << "\"after\": " << resource_snapshot_json(after, indent + 2) << ",\n";
        stream << child << "\"cuda_free_delta_mib\": " << (after.cuda_free_mib - before.cuda_free_mib) << ",\n";
        stream << child << "\"rss_current_delta_mib\": " << (after.rss_current_mib - before.rss_current_mib) << "\n";
        stream << pad << "}";
        return stream.str();
    }

    std::string iteration_summaries_json(const std::vector<IterationSummary> &iterations, int indent = 2)
    {
        const std::string pad(static_cast<std::size_t>(indent), ' ');
        const std::string child(static_cast<std::size_t>(indent + 2), ' ');
        std::ostringstream stream;
        stream << pad << "\"repeat_runs\": [\n";
        for (std::size_t index = 0; index < iterations.size(); ++index)
        {
            const IterationSummary &iteration = iterations[index];
            stream << child << "{\"index\": " << iteration.index
                   << ", \"pass\": " << bool_json(iteration.pass)
                   << ", \"cpu_total_ms\": " << iteration.cpu_total_ms
                   << ", \"gpu_total_ms\": " << iteration.gpu_total_ms
                   << ", \"cuda_free_mib\": " << iteration.resource_after.cuda_free_mib
                   << ", \"rss_current_mib\": " << iteration.resource_after.rss_current_mib
                   << "}" << (index + 1 == iterations.size() ? "\n" : ",\n");
        }
        stream << pad << "]";
        return stream.str();
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

    std::vector<float> magnitude_signal(const ComplexSignal &values)
    {
        std::vector<float> result(values.size(), 0.0f);
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            result[index] = std::abs(values[index]);
        }
        return result;
    }

    RealSignal linspace(float start, float stop, int count)
    {
        RealSignal values;
        if (count <= 0)
        {
            return values;
        }
        values.resize(static_cast<std::size_t>(count), start);
        if (count == 1)
        {
            values[0] = start;
            return values;
        }
        const float step = (stop - start) / static_cast<float>(count - 1);
        for (int index = 0; index < count; ++index)
        {
            values[static_cast<std::size_t>(index)] = start + step * static_cast<float>(index);
        }
        return values;
    }

    ComplexSignal build_template(const ScenarioConfig &config)
    {
        const float t1 = static_cast<float>(config.template_length - 1) / config.fs;
        const RealSignal t = linspace(0.0f, t1, config.template_length);
        const auto result = cusignal::cpu::waveforms::chirp(
            t,
            config.chirp_f0,
            t1,
            config.chirp_f1,
            "linear",
            0.0f,
            true,
            "complex");
        if (!std::holds_alternative<ComplexSignal>(result))
        {
            throw std::runtime_error("chirp did not return complex output");
        }
        return std::get<ComplexSignal>(result);
    }

    ComplexArray simulate_rx_matrix(const ScenarioConfig &config, const ComplexSignal &templ, bool include_noise = true)
    {
        ComplexArray rx = cusignal::core::make_complex_array(
            Shape{static_cast<std::size_t>(config.num_pulses), static_cast<std::size_t>(config.samples_per_pulse)},
            Complex(0.0f, 0.0f));

        const float linear_snr = std::pow(10.0f, config.snr_db / 10.0f);
        const float sigma = include_noise ? (config.target_amplitude / std::sqrt(2.0f * linear_snr)) : 0.0f;

        std::mt19937 rng(config.seed);
        std::normal_distribution<float> noise_dist(0.0f, sigma);
        const float two_pi = 2.0f * 3.14159265358979323846f;

        for (int pulse = 0; pulse < config.num_pulses; ++pulse)
        {
            const float phase = two_pi * config.doppler_hz * static_cast<float>(pulse) / config.prf;
            const Complex doppler_phase = std::polar(1.0f, phase);
            for (int sample = 0; sample < config.samples_per_pulse; ++sample)
            {
                Complex value(
                    include_noise ? noise_dist(rng) : 0.0f,
                    include_noise ? noise_dist(rng) : 0.0f);
                const int templ_index = sample - config.delay_samples;
                if (templ_index >= 0 && templ_index < static_cast<int>(templ.size()))
                {
                    value += config.target_amplitude * templ[static_cast<std::size_t>(templ_index)] * doppler_phase;
                }
                rx.values[static_cast<std::size_t>(pulse) * static_cast<std::size_t>(config.samples_per_pulse) +
                          static_cast<std::size_t>(sample)] = value;
            }
        }
        return rx;
    }

    RealArray power_map_cpu(const ComplexArray &input)
    {
        RealArray output = cusignal::core::make_real_array(input.shape);
        for (std::size_t index = 0; index < input.values.size(); ++index)
        {
            output.values[index] = std::norm(input.values[index]);
        }
        return output;
    }

    ComplexArray fftshift_rows_complex_cpu(const ComplexArray &input)
    {
        if (input.shape.size() != 2)
        {
            throw std::invalid_argument("fftshift_rows_complex_cpu expects rank-2 input");
        }

        const std::size_t rows = input.shape[0];
        const std::size_t cols = input.shape[1];
        ComplexArray output = cusignal::core::make_complex_array(input.shape, Complex(0.0f, 0.0f));
        for (std::size_t row = 0; row < rows; ++row)
        {
            const std::size_t shifted_row = (row + rows / 2) % rows;
            const std::size_t src_base = row * cols;
            const std::size_t dst_base = shifted_row * cols;
            for (std::size_t col = 0; col < cols; ++col)
            {
                output.values[dst_base + col] = input.values[src_base + col];
            }
        }
        return output;
    }

    float centered_doppler_bin_to_hz(int bin, int nfft, float prf)
    {
        const int centered = bin - (nfft / 2);
        return static_cast<float>(centered) * prf / static_cast<float>(nfft);
    }

    DetectionSummary detect_peak(
        const RealArray &power,
        const RealArray &detections,
        int nfft,
        float prf)
    {
        if (power.shape.size() != 2 || detections.shape != power.shape)
        {
            throw std::invalid_argument("power/detections shape mismatch");
        }

        const std::size_t rows = power.shape[0];
        const std::size_t cols = power.shape[1];
        DetectionSummary summary;
        float best_power = -1.0f;
        for (std::size_t row = 0; row < rows; ++row)
        {
            for (std::size_t col = 0; col < cols; ++col)
            {
                const std::size_t index = row * cols + col;
                if (detections.values[index] <= 0.5f)
                {
                    continue;
                }
                if (power.values[index] > best_power)
                {
                    best_power = power.values[index];
                    summary.found = true;
                    summary.range_bin = static_cast<int>(col);
                    summary.doppler_bin = static_cast<int>(row);
                    summary.doppler_hz = centered_doppler_bin_to_hz(summary.doppler_bin, nfft, prf);
                    summary.power = power.values[index];
                }
            }
        }
        return summary;
    }

    DetectionSummary strongest_bin(
        const RealArray &power,
        int nfft,
        float prf)
    {
        if (power.shape.size() != 2)
        {
            throw std::invalid_argument("power must be 2D");
        }

        const std::size_t rows = power.shape[0];
        const std::size_t cols = power.shape[1];
        DetectionSummary summary;
        float best_power = -1.0f;
        for (std::size_t row = 0; row < rows; ++row)
        {
            for (std::size_t col = 0; col < cols; ++col)
            {
                const std::size_t index = row * cols + col;
                if (power.values[index] > best_power)
                {
                    best_power = power.values[index];
                    summary.found = true;
                    summary.range_bin = static_cast<int>(col);
                    summary.doppler_bin = static_cast<int>(row);
                    summary.doppler_hz = centered_doppler_bin_to_hz(summary.doppler_bin, nfft, prf);
                    summary.power = power.values[index];
                }
            }
        }
        return summary;
    }

    template <typename Fn>
    auto measure_cpu_ms(Fn &&fn)
    {
        const auto start = std::chrono::steady_clock::now();
        auto value = fn();
        const auto end = std::chrono::steady_clock::now();
        const float elapsed_ms = std::chrono::duration<float, std::milli>(end - start).count();
        return std::make_pair(std::move(value), elapsed_ms);
    }

    template <typename Fn>
    auto measure_gpu_ms(Fn &&fn)
    {
        const auto start = std::chrono::steady_clock::now();
        auto value = fn();
        cusignal::core::throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
        const auto end = std::chrono::steady_clock::now();
        const float elapsed_ms = std::chrono::duration<float, std::milli>(end - start).count();
        return std::make_pair(std::move(value), elapsed_ms);
    }

    float mixed_error_for_sample(float abs_error, float expected_norm, float reference_scale)
    {
        const float effective_atol = std::max(kMixedErrorAtol, kMixedErrorScale * reference_scale);
        return expected_norm <= effective_atol ? abs_error : abs_error / expected_norm;
    }

    ErrorMetrics compute_real_error(const RealSignal &lhs, const RealSignal &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::invalid_argument("real signals must have the same size");
        }
        ErrorMetrics metrics;
        if (lhs.empty())
        {
            return metrics;
        }

        float reference_scale = 0.0f;
        for (const float value : lhs)
        {
            reference_scale = std::max(reference_scale, std::fabs(value));
        }

        float squared = 0.0f;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float diff = std::fabs(lhs[index] - rhs[index]);
            const float expected_norm = std::fabs(lhs[index]);
            const float denom = std::max(expected_norm, 1.0e-12f);
            metrics.max_abs = std::max(metrics.max_abs, diff);
            metrics.max_rel = std::max(metrics.max_rel, diff / denom);
            metrics.mixed_error = std::max(metrics.mixed_error, mixed_error_for_sample(diff, expected_norm, reference_scale));
            squared += static_cast<float>(diff) * static_cast<float>(diff);
        }
        metrics.rmse = static_cast<float>(std::sqrt(squared / static_cast<float>(lhs.size())));
        return metrics;
    }

    ErrorMetrics compute_complex_error(const ComplexSignal &lhs, const ComplexSignal &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::invalid_argument("complex signals must have the same size");
        }
        ErrorMetrics metrics;
        if (lhs.empty())
        {
            return metrics;
        }

        float reference_scale = 0.0f;
        for (const Complex &value : lhs)
        {
            reference_scale = std::max(reference_scale, std::abs(value));
        }

        float squared = 0.0f;
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            const float diff = std::abs(lhs[index] - rhs[index]);
            const float expected_norm = std::abs(lhs[index]);
            const float denom = std::max(expected_norm, 1.0e-12f);
            metrics.max_abs = std::max(metrics.max_abs, diff);
            metrics.max_rel = std::max(metrics.max_rel, diff / denom);
            metrics.mixed_error = std::max(metrics.mixed_error, mixed_error_for_sample(diff, expected_norm, reference_scale));
            squared += static_cast<float>(diff) * static_cast<float>(diff);
        }
        metrics.rmse = static_cast<float>(std::sqrt(squared / static_cast<float>(lhs.size())));
        return metrics;
    }

    bool detection_matches(const DetectionSummary &lhs, const DetectionSummary &rhs)
    {
        return lhs.found == rhs.found && lhs.range_bin == rhs.range_bin && lhs.doppler_bin == rhs.doppler_bin;
    }

    ValidationResult validate_single_run(
        const DemoRunResult &run,
        const ValidationThresholds &thresholds,
        bool invalid_input_checks_passed,
        bool skip_timing_validation)
    {
        ValidationResult validation;
        add_check(
            validation,
            "cpu_gpu_detection_match",
            detection_matches(run.cpu_detection, run.gpu_detection),
            detection_matches(run.cpu_detection, run.gpu_detection) ? 1.0 : 0.0,
            1.0,
            "CPU/GPU detection bins must match");
        const bool expected_match = run.gpu_detection.found &&
            run.gpu_detection.range_bin == run.expected_detection.range_bin &&
            run.gpu_detection.doppler_bin == run.expected_detection.doppler_bin;
        add_check(
            validation,
            "gpu_matches_expected_detection",
            expected_match,
            expected_match ? 1.0 : 0.0,
            1.0,
            "GPU detection must match injected target bin");
        const double scaled_limit = thresholds.gpu_total_baseline_ms * thresholds.gpu_total_multiplier;
        const double gpu_limit = std::min<double>(scaled_limit, thresholds.gpu_total_hard_limit_ms);
        add_check(
            validation,
            "gpu_total_ms",
            skip_timing_validation || run.gpu_total_ms <= gpu_limit,
            run.gpu_total_ms,
            gpu_limit,
            skip_timing_validation ? "GPU timing validation skipped for sanitizer run"
                                   : "GPU total time must stay within baseline multiplier and hard limit");
        add_check(
            validation,
            "pulse_compression_mixed_error",
            run.pulse_compression_error.mixed_error <= thresholds.pulse_compression_mixed,
            run.pulse_compression_error.mixed_error,
            thresholds.pulse_compression_mixed,
            "pulse compression CPU/GPU mixed error");
        add_check(
            validation,
            "pulse_doppler_mixed_error",
            run.pulse_doppler_error.mixed_error <= thresholds.pulse_doppler_mixed,
            run.pulse_doppler_error.mixed_error,
            thresholds.pulse_doppler_mixed,
            "pulse doppler CPU/GPU mixed error");
        add_check(
            validation,
            "cfar_threshold_mixed_error",
            run.cfar_threshold_error.mixed_error <= thresholds.cfar_threshold_mixed,
            run.cfar_threshold_error.mixed_error,
            thresholds.cfar_threshold_mixed,
            "CFAR threshold mixed error uses task-level intermediate tolerance");
        add_check(
            validation,
            "ambgfun_surface_mixed_error",
            run.ambgfun_error.mixed_error <= thresholds.ambgfun_surface_mixed,
            run.ambgfun_error.mixed_error,
            thresholds.ambgfun_surface_mixed,
            "ambiguity surface CPU/GPU mixed error");
        add_check(
            validation,
            "invalid_input_checks",
            invalid_input_checks_passed,
            invalid_input_checks_passed ? 1.0 : 0.0,
            1.0,
            "invalid configuration matrix must raise std::invalid_argument with field names");
        return validation;
    }

    double median_value(std::vector<double> values)
    {
        if (values.empty())
        {
            return 0.0;
        }
        std::sort(values.begin(), values.end());
        const std::size_t mid = values.size() / 2;
        if (values.size() % 2 == 1)
        {
            return values[mid];
        }
        return 0.5 * (values[mid - 1] + values[mid]);
    }

    void append_repeat_validation(
        ValidationResult &validation,
        const std::vector<IterationSummary> &iterations,
        const ValidationThresholds &thresholds,
        bool skip_timing_validation)
    {
        bool all_iterations_pass = true;
        std::vector<double> gpu_totals;
        const std::size_t timing_start = iterations.size() > 2 ? 1 : 0;
        for (std::size_t index = 0; index < iterations.size(); ++index)
        {
            const IterationSummary &iteration = iterations[index];
            all_iterations_pass = all_iterations_pass && iteration.pass;
            if (index >= timing_start)
            {
                gpu_totals.push_back(iteration.gpu_total_ms);
            }
        }
        add_check(
            validation,
            "repeat_business_consistency",
            all_iterations_pass,
            all_iterations_pass ? 1.0 : 0.0,
            1.0,
            "all repeat iterations must pass business and numeric checks");

        const double median = median_value(gpu_totals);
        double max_relative_jitter = 0.0;
        if (median > 0.0)
        {
            for (double value : gpu_totals)
            {
                max_relative_jitter = std::max(max_relative_jitter, std::fabs(value - median) / median);
            }
        }
        add_check(
            validation,
            "gpu_total_stability",
            skip_timing_validation || max_relative_jitter <= thresholds.timing_relative_jitter,
            max_relative_jitter,
            thresholds.timing_relative_jitter,
            skip_timing_validation ? "GPU timing stability skipped for sanitizer run"
                                   : "GPU total time relative jitter across repeats");

        if (!iterations.empty())
        {
            const ResourceSnapshot &first = iterations.front().resource_after;
            const ResourceSnapshot &last = iterations.back().resource_after;
            const double cuda_free_drop = first.cuda_free_mib - last.cuda_free_mib;
            const double rss_growth = last.rss_current_mib - first.rss_current_mib;
            add_check(
                validation,
                "cuda_free_memory_drift_mib",
                cuda_free_drop <= thresholds.cuda_free_drift_mib,
                cuda_free_drop,
                thresholds.cuda_free_drift_mib,
                "final CUDA free memory must not drop materially after repeats");
            add_check(
                validation,
                "rss_current_drift_mib",
                rss_growth <= thresholds.rss_current_drift_mib,
                rss_growth,
                thresholds.rss_current_drift_mib,
                "process current RSS must not grow materially after repeats");
        }
    }

    bool expect_invalid_config(
        const std::string &case_name,
        const std::string &expected_field,
        const ScenarioConfig &config)
    {
        try
        {
            validate_config(config);
        }
        catch (const std::invalid_argument &error)
        {
            const std::string message = error.what();
            if (message.find(expected_field) != std::string::npos)
            {
                return true;
            }
            throw std::runtime_error(
                "invalid input check " + case_name + " produced unclear error: " + message);
        }
        throw std::runtime_error("invalid input check " + case_name + " did not fail");
    }

    bool run_invalid_input_checks()
    {
        const ScenarioConfig base;
        validate_config(base);
        std::vector<bool> results;
        {
            ScenarioConfig config = base;
            config.samples_per_pulse = 0;
            results.push_back(expect_invalid_config("samples_per_pulse_zero", "samples_per_pulse", config));
        }
        {
            ScenarioConfig config = base;
            config.template_length = base.samples_per_pulse + 1;
            results.push_back(expect_invalid_config("template_too_long", "template_length", config));
        }
        {
            ScenarioConfig config = base;
            config.pulse_doppler_nfft = base.num_pulses - 1;
            results.push_back(expect_invalid_config("doppler_nfft_too_small", "pulse_doppler_nfft", config));
        }
        {
            ScenarioConfig config = base;
            config.cfar_pfa = 1.0f;
            results.push_back(expect_invalid_config("cfar_pfa_invalid", "cfar_pfa", config));
        }
        {
            ScenarioConfig config = base;
            config.pulse_doppler_window = "not_a_window";
            results.push_back(expect_invalid_config("window_invalid", "pulse_doppler_window", config));
        }
        return std::all_of(results.begin(), results.end(), [](bool value) { return value; });
    }

    CpuArtifacts run_cpu_pipeline_from_input(
        const ScenarioConfig &config,
        const ComplexSignal &tx_template,
        const ComplexArray &rx_matrix)
    {
        CpuArtifacts artifacts;
        artifacts.tx_template = tx_template;
        artifacts.rx_matrix = rx_matrix;
        artifacts.pulse_compression = cusignal::cpu::radartools::pulse_compression(
            artifacts.rx_matrix,
            artifacts.tx_template,
            config.pulse_compression_normalize,
            config.pulse_compression_window,
            config.pulse_compression_nfft);
        artifacts.pulse_doppler = cusignal::cpu::radartools::pulse_doppler(
            artifacts.pulse_compression,
            config.pulse_doppler_window,
            config.pulse_doppler_nfft);
        artifacts.pulse_doppler = fftshift_rows_complex_cpu(artifacts.pulse_doppler);
        artifacts.range_doppler_power = power_map_cpu(artifacts.pulse_doppler);
        const auto cfar = cusignal::cpu::radartools::ca_cfar(
            artifacts.range_doppler_power,
            config.cfar_guard_cells,
            config.cfar_reference_cells,
            config.cfar_pfa);
        artifacts.cfar_threshold = cfar.threshold;
        artifacts.cfar_detections = cfar.detections;
        const auto ambg = cusignal::cpu::radartools::ambgfun(
            artifacts.tx_template,
            config.fs,
            config.prf,
            "2d",
            0.0f);
        artifacts.ambgfun = std::get<AmbgfunSurfaceResult>(ambg);
        return artifacts;
    }

    CpuArtifacts run_cpu_pipeline(const ScenarioConfig &config)
    {
        const ComplexSignal tx_template = build_template(config);
        const ComplexArray rx_matrix = simulate_rx_matrix(config, tx_template, true);
        return run_cpu_pipeline_from_input(config, tx_template, rx_matrix);
    }

    std::pair<GpuArtifacts, std::vector<StageTiming>> run_gpu_pipeline(
        const ScenarioConfig &config,
        const ComplexArray &rx_matrix,
        const ComplexSignal &tx_template)
    {
        std::vector<StageTiming> timings;
        GpuArtifacts artifacts;

        auto [pulse_compression, pulse_compression_ms] = measure_gpu_ms([&]() {
            return cusignal::cuda_backend::radartools::pulse_compression(
                rx_matrix,
                tx_template,
                config.pulse_compression_normalize,
                config.pulse_compression_window,
                config.pulse_compression_nfft);
        });
        timings.push_back({"pulse_compression", 0.0, pulse_compression_ms});
        artifacts.pulse_compression = std::move(pulse_compression);

        auto [pulse_doppler, pulse_doppler_ms] = measure_gpu_ms([&]() {
            auto shifted = cusignal::cuda_backend::radartools::pulse_doppler(
                artifacts.pulse_compression,
                config.pulse_doppler_window,
                config.pulse_doppler_nfft);
            return fftshift_rows_complex_cuda(shifted);
        });
        timings.push_back({"pulse_doppler", 0.0, pulse_doppler_ms});
        artifacts.pulse_doppler = std::move(pulse_doppler);

        auto [range_doppler_power, power_ms] = measure_gpu_ms([&]() {
            return power_map_cuda(artifacts.pulse_doppler);
        });
        timings.push_back({"power_map", 0.0, power_ms});
        artifacts.range_doppler_power = std::move(range_doppler_power);

        auto [cfar, cfar_ms] = measure_gpu_ms([&]() {
            return cusignal::cuda_backend::radartools::ca_cfar(
                artifacts.range_doppler_power,
                config.cfar_guard_cells,
                config.cfar_reference_cells,
                config.cfar_pfa);
        });
        timings.push_back({"ca_cfar", 0.0, cfar_ms});
        artifacts.cfar_threshold = std::move(cfar.threshold);
        artifacts.cfar_detections = std::move(cfar.detections);

        auto [ambgfun, ambgfun_ms] = measure_gpu_ms([&]() {
            return cusignal::cuda_backend::radartools::ambgfun(
                tx_template,
                config.fs,
                config.prf,
                "2d",
                0.0f);
        });
        timings.push_back({"ambgfun", 0.0, ambgfun_ms});
        artifacts.ambgfun = std::get<CudaAmbgfunSurfaceResult>(std::move(ambgfun));

        return std::make_pair(std::move(artifacts), std::move(timings));
    }

    HostGpuArtifacts materialize_gpu_artifacts(const GpuArtifacts &gpu)
    {
        HostGpuArtifacts host;
        host.pulse_compression = gpu.pulse_compression.get();
        host.pulse_doppler = gpu.pulse_doppler.get();
        host.range_doppler_power = gpu.range_doppler_power.get();
        host.cfar_threshold = gpu.cfar_threshold.get();
        host.cfar_detections = gpu.cfar_detections.get();
        host.ambgfun.values = gpu.ambgfun.values.get();
        host.ambgfun.delay_axis = gpu.ambgfun.delay_axis.get();
        host.ambgfun.doppler_axis = gpu.ambgfun.doppler_axis.get();
        return host;
    }

    void write_generated_inputs(
        const ScenarioConfig &config,
        const ComplexSignal &tx_template,
        const ComplexArray &rx_matrix)
    {
        const fs::path input_dir = generated_root() / "input";
        fs::create_directories(input_dir);

        write_complex_csv(input_dir / "tx_template.csv", tx_template);
        write_complex_csv(input_dir / "rx_matrix.csv", rx_matrix.values);

        std::ostringstream scenario;
        scenario << "{\n";
        scenario << "  \"scale_level\": " << config.scale_level << ",\n";
        scenario << "  \"scale_value\": " << scale_value(config) << ",\n";
        scenario << "  \"fs\": " << config.fs << ",\n";
        scenario << "  \"num_pulses\": " << config.num_pulses << ",\n";
        scenario << "  \"samples_per_pulse\": " << config.samples_per_pulse << ",\n";
        scenario << "  \"template_length\": " << config.template_length << ",\n";
        scenario << "  \"prf\": " << config.prf << ",\n";
        scenario << "  \"delay_samples\": " << config.delay_samples << ",\n";
        scenario << "  \"doppler_hz\": " << config.doppler_hz << ",\n";
        scenario << "  \"target_amplitude\": " << config.target_amplitude << ",\n";
        scenario << "  \"snr_db\": " << config.snr_db << ",\n";
        scenario << "  \"seed\": " << config.seed << ",\n";
        scenario << "  \"chirp_f0\": " << config.chirp_f0 << ",\n";
        scenario << "  \"chirp_f1\": " << config.chirp_f1 << ",\n";
        scenario << "  \"pulse_compression_normalize\": " << bool_json(config.pulse_compression_normalize) << ",\n";
        scenario << "  \"pulse_compression_window\": \"" << json_escape(config.pulse_compression_window) << "\",\n";
        scenario << "  \"pulse_doppler_window\": \"" << json_escape(config.pulse_doppler_window) << "\",\n";
        scenario << "  \"pulse_compression_nfft\": " << config.pulse_compression_nfft << ",\n";
        scenario << "  \"pulse_doppler_nfft\": " << config.pulse_doppler_nfft << ",\n";
        scenario << "  \"cfar_guard_cells\": " << shape_json(config.cfar_guard_cells) << ",\n";
        scenario << "  \"cfar_reference_cells\": " << shape_json(config.cfar_reference_cells) << ",\n";
        scenario << "  \"cfar_pfa\": " << config.cfar_pfa << ",\n";
        scenario << "  \"rx_shape\": " << shape_json(rx_matrix.shape) << "\n";
        scenario << "}\n";
        write_text_file(input_dir / "scenario.json", scenario.str());
    }

    void write_output_samples(
        const CpuArtifacts &cpu,
        const HostGpuArtifacts &gpu)
    {
        const fs::path output_dir = generated_root() / "output_samples";
        fs::create_directories(output_dir);

        write_complex_csv(output_dir / "pulse_compression__cpu__values.csv", cpu.pulse_compression.values);
        write_complex_csv(output_dir / "pulse_compression__gpu__values.csv", gpu.pulse_compression.values);

        write_complex_csv(output_dir / "range_doppler__cpu__values.csv", cpu.pulse_doppler.values);
        write_complex_csv(output_dir / "range_doppler__gpu__values.csv", gpu.pulse_doppler.values);

        write_real_csv(output_dir / "cfar_threshold__cpu__values.csv", cpu.cfar_threshold.values);
        write_real_csv(output_dir / "cfar_threshold__gpu__values.csv", gpu.cfar_threshold.values);

        write_real_csv(output_dir / "cfar_detections__cpu__values.csv", cpu.cfar_detections.values);
        write_real_csv(output_dir / "cfar_detections__gpu__values.csv", gpu.cfar_detections.values);

        write_real_csv(output_dir / "ambgfun_surface__cpu__values.csv", cpu.ambgfun.values.values);
        write_real_csv(output_dir / "ambgfun_surface__gpu__values.csv", gpu.ambgfun.values.values);

        write_real_csv(output_dir / "ambgfun_delay_axis__cpu__values.csv", cpu.ambgfun.delay_axis);
        write_real_csv(output_dir / "ambgfun_delay_axis__gpu__values.csv", gpu.ambgfun.delay_axis);

        write_real_csv(output_dir / "ambgfun_doppler_axis__cpu__values.csv", cpu.ambgfun.doppler_axis);
        write_real_csv(output_dir / "ambgfun_doppler_axis__gpu__values.csv", gpu.ambgfun.doppler_axis);
    }

    void write_stage_timings_csv(
        const std::vector<StageTiming> &timings,
        float cpu_total_ms,
        float gpu_total_ms)
    {
        const fs::path path = report_root() / "latest_stage_timings.csv";
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write CSV file: " + path.string());
        }
        output << "stage,cpu_ms,gpu_ms\n";
        output << std::fixed << std::setprecision(6);
        for (const StageTiming &timing : timings)
        {
            output << timing.name << ',' << timing.cpu_ms << ',' << timing.gpu_ms << '\n';
        }
        output << "total," << cpu_total_ms << ',' << gpu_total_ms << '\n';
    }

    std::string build_summary_markdown(
        const ScenarioConfig &config,
        const DetectionSummary &expected_detection,
        const DetectionSummary &cpu_detection,
        const DetectionSummary &gpu_detection,
        const std::vector<StageTiming> &timings,
        const ErrorMetrics &pulse_compression_error,
        const ErrorMetrics &pulse_doppler_error,
        const ErrorMetrics &cfar_threshold_error,
        const ErrorMetrics &ambgfun_error,
        float cpu_total_ms,
        float gpu_total_ms,
        const ValidationResult &validation,
        const ResourceSnapshot &resource_before,
        const ResourceSnapshot &resource_after,
        const std::vector<IterationSummary> &iterations)
    {
        std::ostringstream stream;
        stream << "# Task 1 Radar Demo\n\n";
        stream << "## Scenario\n\n";
        stream << "- scale_level: `L" << config.scale_level << "`\n";
        stream << "- scale_value: `" << scale_value(config) << "`\n";
        stream << "- fs: `" << config.fs << "`\n";
        stream << "- num_pulses: `" << config.num_pulses << "`\n";
        stream << "- samples_per_pulse: `" << config.samples_per_pulse << "`\n";
        stream << "- template_length: `" << config.template_length << "`\n";
        stream << "- prf: `" << config.prf << "`\n";
        stream << "- delay_samples: `" << config.delay_samples << "`\n";
        stream << "- doppler_hz: `" << config.doppler_hz << "`\n";
        stream << "- snr_db: `" << config.snr_db << "`\n\n";
        stream << "## Detection\n\n";
        stream << "| backend | found | range_bin | doppler_bin | doppler_hz | power |\n";
        stream << "| --- | --- | ---: | ---: | ---: | ---: |\n";
        stream << "| expected | " << (expected_detection.found ? "true" : "false") << " | "
               << expected_detection.range_bin << " | " << expected_detection.doppler_bin << " | "
               << std::fixed << std::setprecision(3) << expected_detection.doppler_hz << " | "
               << expected_detection.power << " |\n";
        stream << "| cpu | " << (cpu_detection.found ? "true" : "false") << " | " << cpu_detection.range_bin
               << " | " << cpu_detection.doppler_bin << " | " << cpu_detection.doppler_hz << " | "
               << cpu_detection.power << " |\n";
        stream << "| gpu | " << (gpu_detection.found ? "true" : "false") << " | " << gpu_detection.range_bin
               << " | " << gpu_detection.doppler_bin << " | " << gpu_detection.doppler_hz << " | "
               << gpu_detection.power << " |\n\n";
        stream << "## Error\n\n";
        stream << std::scientific << std::setprecision(6);
        stream << "| field | mixed_error | max_abs | max_rel | rmse |\n";
        stream << "| --- | ---: | ---: | ---: | ---: |\n";
        stream << "| pulse_compression | " << pulse_compression_error.mixed_error << " | "
               << pulse_compression_error.max_abs << " | " << pulse_compression_error.max_rel << " | "
               << pulse_compression_error.rmse << " |\n";
        stream << "| pulse_doppler | " << pulse_doppler_error.mixed_error << " | "
               << pulse_doppler_error.max_abs << " | " << pulse_doppler_error.max_rel << " | "
               << pulse_doppler_error.rmse << " |\n";
        stream << "| cfar_threshold | " << cfar_threshold_error.mixed_error << " | "
               << cfar_threshold_error.max_abs << " | " << cfar_threshold_error.max_rel << " | "
               << cfar_threshold_error.rmse << " |\n";
        stream << "| ambgfun_surface | " << ambgfun_error.mixed_error << " | "
               << ambgfun_error.max_abs << " | " << ambgfun_error.max_rel << " | "
               << ambgfun_error.rmse << " |\n\n";
        stream << "## Timing\n\n";
        stream << "| stage | cpu_ms | gpu_ms |\n";
        stream << "| --- | ---: | ---: |\n";
        stream << std::fixed << std::setprecision(6);
        for (const StageTiming &timing : timings)
        {
            stream << "| " << timing.name << " | " << timing.cpu_ms << " | " << timing.gpu_ms << " |\n";
        }
        stream << "| total | " << cpu_total_ms << " | " << gpu_total_ms << " |\n\n";
        stream << "## Validation\n\n";
        stream << "- pass: `" << (validation.pass ? "true" : "false") << "`\n";
        stream << "- repeat_runs: `" << iterations.size() << "`\n";
        stream << "- cuda_free_delta_mib: `" << std::setprecision(3)
               << (resource_after.cuda_free_mib - resource_before.cuda_free_mib) << "`\n";
        stream << "- rss_current_delta_mib: `"
               << (resource_after.rss_current_mib - resource_before.rss_current_mib) << "`\n\n";
        stream << "## Artifacts\n\n";
        stream << "- inputs: `data/generated/demo/task1_radar/input/`\n";
        stream << "- samples: `data/generated/demo/task1_radar/output_samples/`\n";
        stream << "- metrics: `data/reports/demo/task1_radar/latest_metrics.json`\n";
        stream << "- timings: `data/reports/demo/task1_radar/latest_stage_timings.csv`\n";
        stream << "- figures: run `python3 demo/task1_radar/visualize_task1.py`\n";
        return stream.str();
    }

    std::string build_metrics_json(
        const ScenarioConfig &config,
        const DetectionSummary &expected_detection,
        const DetectionSummary &cpu_detection,
        const DetectionSummary &gpu_detection,
        const CpuArtifacts &cpu,
        const HostGpuArtifacts &gpu,
        const std::vector<StageTiming> &timings,
        const ErrorMetrics &pulse_compression_error,
        const ErrorMetrics &pulse_doppler_error,
        const ErrorMetrics &cfar_threshold_error,
        const ErrorMetrics &ambgfun_error,
        float cpu_total_ms,
        float gpu_total_ms,
        const ValidationResult &validation,
        const ResourceSnapshot &resource_before,
        const ResourceSnapshot &resource_after,
        const std::vector<IterationSummary> &iterations)
    {
        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"version\": \"V3.1\",\n";
        stream << "  \"scenario\": {\n";
        stream << "    \"scale_level\": " << config.scale_level << ",\n";
        stream << "    \"scale_value\": " << scale_value(config) << ",\n";
        stream << "    \"fs\": " << config.fs << ",\n";
        stream << "    \"num_pulses\": " << config.num_pulses << ",\n";
        stream << "    \"samples_per_pulse\": " << config.samples_per_pulse << ",\n";
        stream << "    \"rx_shape\": " << shape_json(cpu.rx_matrix.shape) << ",\n";
        stream << "    \"template_length\": " << config.template_length << ",\n";
        stream << "    \"prf\": " << config.prf << ",\n";
        stream << "    \"delay_samples\": " << config.delay_samples << ",\n";
        stream << "    \"doppler_hz\": " << config.doppler_hz << ",\n";
        stream << "    \"target_amplitude\": " << config.target_amplitude << ",\n";
        stream << "    \"snr_db\": " << config.snr_db << ",\n";
        stream << "    \"seed\": " << config.seed << ",\n";
        stream << "    \"pulse_compression_nfft\": " << config.pulse_compression_nfft << ",\n";
        stream << "    \"pulse_doppler_nfft\": " << config.pulse_doppler_nfft << ",\n";
        stream << "    \"pulse_compression_normalize\": " << bool_json(config.pulse_compression_normalize) << ",\n";
        stream << "    \"pulse_compression_window\": \"" << json_escape(config.pulse_compression_window) << "\",\n";
        stream << "    \"pulse_doppler_window\": \"" << json_escape(config.pulse_doppler_window) << "\",\n";
        stream << "    \"cfar_guard_cells\": " << shape_json(config.cfar_guard_cells) << ",\n";
        stream << "    \"cfar_reference_cells\": " << shape_json(config.cfar_reference_cells) << ",\n";
        stream << "    \"cfar_pfa\": " << config.cfar_pfa << "\n";
        stream << "  },\n";
        stream << "  \"shapes\": {\n";
        stream << "    \"rx_matrix\": " << shape_json(cpu.rx_matrix.shape) << ",\n";
        stream << "    \"pulse_compression\": " << shape_json(cpu.pulse_compression.shape) << ",\n";
        stream << "    \"range_doppler\": " << shape_json(cpu.pulse_doppler.shape) << ",\n";
        stream << "    \"cfar\": " << shape_json(cpu.cfar_threshold.shape) << ",\n";
        stream << "    \"ambgfun_surface\": " << shape_json(cpu.ambgfun.values.shape) << "\n";
        stream << "  },\n";
        auto write_detection = [&](const char *name, const DetectionSummary &summary, bool trailing_comma) {
            stream << "  \"" << name << "\": {\n";
            stream << "    \"found\": " << bool_json(summary.found) << ",\n";
            stream << "    \"range_bin\": " << summary.range_bin << ",\n";
            stream << "    \"doppler_bin\": " << summary.doppler_bin << ",\n";
            stream << "    \"doppler_hz\": " << summary.doppler_hz << ",\n";
            stream << "    \"power\": " << summary.power << "\n";
            stream << "  }" << (trailing_comma ? ",\n" : "\n");
        };
        stream << "  \"injected_target\": {\n";
        stream << "    \"delay_samples\": " << config.delay_samples << ",\n";
        stream << "    \"doppler_hz\": " << config.doppler_hz << ",\n";
        stream << "    \"target_amplitude\": " << config.target_amplitude << "\n";
        stream << "  },\n";
        write_detection("expected_detection", expected_detection, true);
        write_detection("cpu_detection", cpu_detection, true);
        write_detection("gpu_detection", gpu_detection, true);
        stream << "  \"timings\": {\n";
        for (std::size_t index = 0; index < timings.size(); ++index)
        {
            const StageTiming &timing = timings[index];
            stream << "    \"" << json_escape(timing.name) << "\": {\"cpu_ms\": " << timing.cpu_ms
                   << ", \"gpu_ms\": " << timing.gpu_ms << "},\n";
        }
        stream << "    \"total\": {\"cpu_ms\": " << cpu_total_ms << ", \"gpu_ms\": " << gpu_total_ms << "}\n";
        stream << "  },\n";
        auto write_error = [&](const char *name, const ErrorMetrics &metrics, bool trailing_comma) {
            stream << "  \"" << name << "\": {\n";
            stream << "    \"mixed_error\": " << metrics.mixed_error << ",\n";
            stream << "    \"max_abs\": " << metrics.max_abs << ",\n";
            stream << "    \"max_rel\": " << metrics.max_rel << ",\n";
            stream << "    \"rmse\": " << metrics.rmse << "\n";
            stream << "  }" << (trailing_comma ? ",\n" : "\n");
        };
        write_error("pulse_compression_error", pulse_compression_error, true);
        write_error("pulse_doppler_error", pulse_doppler_error, true);
        write_error("cfar_threshold_error", cfar_threshold_error, true);
        write_error("ambgfun_surface_error", ambgfun_error, true);
        stream << "  \"consistency\": {\n";
        stream << "    \"cpu_gpu_detection_match\": " << bool_json(
            cpu_detection.found == gpu_detection.found &&
            cpu_detection.range_bin == gpu_detection.range_bin &&
            cpu_detection.doppler_bin == gpu_detection.doppler_bin) << ",\n";
        stream << "    \"gpu_matches_expected_detection\": " << bool_json(
            gpu_detection.found &&
            gpu_detection.range_bin == expected_detection.range_bin &&
            gpu_detection.doppler_bin == expected_detection.doppler_bin) << "\n";
        stream << "  },\n";
        stream << validation_json(validation) << ",\n";
        stream << resource_usage_json(resource_before, resource_after) << ",\n";
        stream << iteration_summaries_json(iterations) << "\n";
        stream << "}\n";
        return stream.str();
    }

    DemoRunResult run_once(const ScenarioConfig &config)
    {
        validate_config(config);
        CpuArtifacts cpu = run_cpu_pipeline(config);
        const ComplexArray noiseless_rx = simulate_rx_matrix(config, cpu.tx_template, false);
        const CpuArtifacts noiseless = run_cpu_pipeline_from_input(config, cpu.tx_template, noiseless_rx);

        std::vector<StageTiming> stage_timings;

        auto [pulse_cpu, pulse_cpu_ms] = measure_cpu_ms([&]() {
            return cusignal::cpu::radartools::pulse_compression(
                cpu.rx_matrix,
                cpu.tx_template,
                config.pulse_compression_normalize,
                config.pulse_compression_window,
                config.pulse_compression_nfft);
        });
        auto [doppler_cpu, doppler_cpu_ms] = measure_cpu_ms([&]() {
            return fftshift_rows_complex_cpu(cusignal::cpu::radartools::pulse_doppler(
                pulse_cpu,
                config.pulse_doppler_window,
                config.pulse_doppler_nfft));
        });
        auto [power_cpu, power_cpu_ms] = measure_cpu_ms([&]() {
            return power_map_cpu(doppler_cpu);
        });
        auto [cfar_cpu, cfar_cpu_ms] = measure_cpu_ms([&]() {
            return cusignal::cpu::radartools::ca_cfar(
                power_cpu,
                config.cfar_guard_cells,
                config.cfar_reference_cells,
                config.cfar_pfa);
        });
        auto [ambg_cpu, ambg_cpu_ms] = measure_cpu_ms([&]() {
            return std::get<AmbgfunSurfaceResult>(cusignal::cpu::radartools::ambgfun(
                cpu.tx_template,
                config.fs,
                config.prf,
                "2d",
                0.0f));
        });
        (void)cfar_cpu;
        (void)ambg_cpu;

        const auto [gpu_warmup_device, gpu_warmup_timings] = run_gpu_pipeline(config, cpu.rx_matrix, cpu.tx_template);
        (void)gpu_warmup_device;
        (void)gpu_warmup_timings;
        const auto [gpu_device, gpu_stage_times] = run_gpu_pipeline(config, cpu.rx_matrix, cpu.tx_template);
        HostGpuArtifacts gpu = materialize_gpu_artifacts(gpu_device);

        stage_timings.push_back({"pulse_compression", pulse_cpu_ms, gpu_stage_times[0].gpu_ms});
        stage_timings.push_back({"pulse_doppler", doppler_cpu_ms, gpu_stage_times[1].gpu_ms});
        stage_timings.push_back({"power_map", power_cpu_ms, gpu_stage_times[2].gpu_ms});
        stage_timings.push_back({"ca_cfar", cfar_cpu_ms, gpu_stage_times[3].gpu_ms});
        stage_timings.push_back({"ambgfun", ambg_cpu_ms, gpu_stage_times[4].gpu_ms});

        float cpu_total_ms = 0.0;
        float gpu_total_ms = 0.0;
        for (const StageTiming &timing : stage_timings)
        {
            cpu_total_ms += timing.cpu_ms;
            gpu_total_ms += timing.gpu_ms;
        }

        const DetectionSummary expected_detection =
            strongest_bin(noiseless.range_doppler_power, config.pulse_doppler_nfft, config.prf);
        const DetectionSummary cpu_detection = detect_peak(
            cpu.range_doppler_power,
            cpu.cfar_detections,
            config.pulse_doppler_nfft,
            config.prf);
        const DetectionSummary gpu_detection = detect_peak(
            gpu.range_doppler_power,
            gpu.cfar_detections,
            config.pulse_doppler_nfft,
            config.prf);

        const ErrorMetrics pulse_compression_error =
            compute_complex_error(cpu.pulse_compression.values, gpu.pulse_compression.values);
        const ErrorMetrics pulse_doppler_error =
            compute_complex_error(cpu.pulse_doppler.values, gpu.pulse_doppler.values);
        const ErrorMetrics cfar_threshold_error =
            compute_real_error(cpu.cfar_threshold.values, gpu.cfar_threshold.values);
        const ErrorMetrics ambgfun_error =
            compute_real_error(cpu.ambgfun.values.values, gpu.ambgfun.values.values);

        DemoRunResult result;
        result.cpu = std::move(cpu);
        result.gpu = std::move(gpu);
        result.expected_detection = expected_detection;
        result.cpu_detection = cpu_detection;
        result.gpu_detection = gpu_detection;
        result.stage_timings = std::move(stage_timings);
        result.pulse_compression_error = pulse_compression_error;
        result.pulse_doppler_error = pulse_doppler_error;
        result.cfar_threshold_error = cfar_threshold_error;
        result.ambgfun_error = ambgfun_error;
        result.cpu_total_ms = cpu_total_ms;
        result.gpu_total_ms = gpu_total_ms;
        return result;
    }

    int run(const DemoOptions &options)
    {
        const ScenarioConfig config = scenario_for_scale_level(options.scale_level);
        validate_config(config);
        const ValidationThresholds thresholds = thresholds_for_scale_level(config.scale_level);
        const bool invalid_checks_passed = options.invalid_input_checks ? run_invalid_input_checks() : true;
        const ResourceSnapshot resource_before = capture_resource_snapshot();

        DemoRunResult final_run;
        ValidationResult final_validation;
        std::vector<IterationSummary> iterations;
        for (int iteration = 0; iteration < options.repeat; ++iteration)
        {
            DemoRunResult current = run_once(config);
            ValidationResult current_validation = validate_single_run(
                current,
                thresholds,
                invalid_checks_passed,
                options.skip_timing_validation);
            cusignal::core::throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
            IterationSummary summary;
            summary.index = iteration + 1;
            summary.pass = current_validation.pass;
            summary.cpu_total_ms = current.cpu_total_ms;
            summary.gpu_total_ms = current.gpu_total_ms;
            summary.resource_after = capture_resource_snapshot();
            iterations.push_back(summary);
            if (iteration + 1 == options.repeat)
            {
                final_validation = std::move(current_validation);
                final_run = std::move(current);
            }
        }
        append_repeat_validation(final_validation, iterations, thresholds, options.skip_timing_validation);
        const ResourceSnapshot resource_after = capture_resource_snapshot();

        write_generated_inputs(config, final_run.cpu.tx_template, final_run.cpu.rx_matrix);
        write_output_samples(final_run.cpu, final_run.gpu);
        write_stage_timings_csv(final_run.stage_timings, final_run.cpu_total_ms, final_run.gpu_total_ms);
        write_text_file(
            report_root() / "latest_summary.md",
            build_summary_markdown(
                config,
                final_run.expected_detection,
                final_run.cpu_detection,
                final_run.gpu_detection,
                final_run.stage_timings,
                final_run.pulse_compression_error,
                final_run.pulse_doppler_error,
                final_run.cfar_threshold_error,
                final_run.ambgfun_error,
                final_run.cpu_total_ms,
                final_run.gpu_total_ms,
                final_validation,
                resource_before,
                resource_after,
                iterations));
        write_text_file(
            report_root() / "latest_metrics.json",
            build_metrics_json(
                config,
                final_run.expected_detection,
                final_run.cpu_detection,
                final_run.gpu_detection,
                final_run.cpu,
                final_run.gpu,
                final_run.stage_timings,
                final_run.pulse_compression_error,
                final_run.pulse_doppler_error,
                final_run.cfar_threshold_error,
                final_run.ambgfun_error,
                final_run.cpu_total_ms,
                final_run.gpu_total_ms,
                final_validation,
                resource_before,
                resource_after,
                iterations));

        cusignal::core::throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");

        if (!final_validation.pass)
        {
            for (const ValidationCheck &check : final_validation.checks)
            {
                if (!check.pass)
                {
                    std::cerr << "[task1_radar] validation failed: " << check.name
                              << " value=" << check.value << " limit=" << check.limit
                              << " detail=" << check.detail << '\n';
                }
            }
            return 1;
        }

        std::cout << "[task1_radar] PASS"
                  << " repeat=" << options.repeat
                  << " scale_level=L" << config.scale_level
                  << " invalid_input_checks=" << bool_json(options.invalid_input_checks)
                  << " skip_timing_validation=" << bool_json(options.skip_timing_validation) << '\n';
        std::cout << "reports       : "
                  << (report_root() / "latest_summary.md").lexically_relative(repo_root()).string() << '\n';
        std::cout << "visualization : python3 demo/task1_radar/visualize_task1.py\n";
        return 0;
    }
} // namespace cusignal_demo::task1_radar

int main(int argc, char **argv)
{
    try
    {
        const auto options = cusignal_demo::task1_radar::parse_options(argc, argv);
        return cusignal_demo::task1_radar::run(options);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[task1_radar] ERROR: " << error.what() << '\n';
        return 1;
    }
}
