#include "task2_features_zx_gpu.hpp"

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
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

#include <sys/resource.h>
#include <unistd.h>

#include "cusignal/bsplines/bsplines.hpp"
#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"
#include "cusignal/correlate/correlate.hpp"
#include "cusignal/demod/demod.hpp"
#include "cusignal/estimation/estimation.hpp"
#include "cusignal/filter_design/filter_design.hpp"
#include "cusignal/filtering/filtering.hpp"
#include "cusignal/peak_finding/peak_finding.hpp"
#include "cusignal/spectral/spectral.hpp"
#include "cusignal/waveforms/waveforms.hpp"
#include "cusignal/wavelets/wavelets.hpp"

namespace cusignal_demo::task2_features
{
    namespace fs = std::filesystem;

    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
    using cusignal::spectral_api::ZxGpuSpectrogramResult;
    using cusignal::spectral_api::SpectrogramResult;
    using cusignal::waveforms_api::IEnvWaveform;

    struct ScenarioConfig
    {
        int scale_level = 3;             // 任务级规模档位，默认 L3 保持历史场景。
        float fs = 1.0e6f;               // 采样率，单位 Hz，决定每帧快时间采样间隔。
        int num_frames = 48;             // 帧数，也就是批处理时间步数；增大可放大整体任务规模。
        int samples_per_frame = 1024;    // 每帧采样点数；增大可放大滤波、解调、谱分析输入长度。
        int template_length = 256;       // 目标模板长度；必须不大于 samples_per_frame。
        int target_start_sample_0 = 220; // 第 0 帧目标起始采样点。
        int target_step_per_frame = 3;   // 目标每帧平移的采样点数，用于生成运动轨迹。
        int interferer_start_sample = 640; // 干扰信号起始采样点。
        int interferer_length = 256;       // 干扰信号长度；需满足起点 + 长度不超过 samples_per_frame。
        float target_amplitude = 1.0f;     // 目标信号幅度。
        float interferer_amplitude = 0.45f; // 干扰信号幅度。
        float snr_db = 12.0f;              // 信噪比，单位 dB，用于生成噪声。
        unsigned int seed = 20260414u;     // 随机种子，固定后可复现实验输入。
        float chirp_f0 = 7.0e4f;           // 目标 chirp 起始频率，单位 Hz。
        float chirp_f1 = 1.8e5f;           // 目标 chirp 终止频率，单位 Hz。
        float gausspulse_fc = 1.2e5f;      // 高斯脉冲中心频率，单位 Hz。
        float interferer_f0 = 9.0e4f;      // 干扰 chirp 起始频率，单位 Hz。
        float interferer_f1 = 1.45e5f;     // 干扰 chirp 终止频率，单位 Hz。
        int representative_frame_index = 24; // 可视化和样例输出使用的代表帧索引。
        int filter_numtaps = 129;          // FIR 带通滤波器 taps 数；越大过渡带越窄、计算量越高。
        float filter_low = 6.0e4f;         // 带通滤波低截止频率，单位 Hz。
        float filter_high = 2.2e5f;        // 带通滤波高截止频率，单位 Hz。
        int spectrogram_nperseg = 128;     // spectrogram 每个 STFT 分段长度。
        int spectrogram_noverlap = 96;     // spectrogram 相邻分段重叠长度；必须小于 nperseg。
        int spectrogram_nfft = 256;        // spectrogram FFT 点数，建议不小于 nperseg。
        int peak_order = 8;                // 峰值搜索邻域半径，越大越抑制局部噪声峰。
        float kalman_rmse_tolerance = 2.0f; // Kalman 轨迹 RMSE 容忍阈值，单位为采样点。
    };

    struct ErrorMetrics
    {
        float mixed_error = 0.0f;
        float max_abs = 0.0f;
        float max_rel = 0.0f;
        float rmse = 0.0f;
    };

    constexpr float kMixedErrorAtol = 1.0e-5f;
    constexpr float kDefaultMixedScale = 1.0e-2f;
    constexpr float kSpectralMixedScale = 1.0e-1f;

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
        double gpu_free_mib = 0.0;
        double gpu_total_mib = 0.0;
        int gpu_device = -1;
        std::string gpu_device_name = "unknown";
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
        float gpu_total_baseline_ms = 60.0f;
        float gpu_total_multiplier = 1.25f;
        float gpu_total_hard_limit_ms = 75.0f;
        float filtered_mixed = 1.0e-4f;
        float correlate_mixed = 1.0e-4f;
        float spectrogram_mixed = 1.0e-4f;
        float cwt_mixed = 1.0e-4f;
        float feature_score_mixed = 1.0e-4f;
        float timing_relative_jitter = 0.35f;
        float gpu_free_drift_mib = 32.0f;
        float rss_current_drift_mib = 64.0f;
    };

    long long scale_value(const ScenarioConfig &config)
    {
        return static_cast<long long>(config.num_frames) *
            static_cast<long long>(config.samples_per_frame);
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
            config.num_frames = 16;
            config.samples_per_frame = 512;
            config.template_length = 128;
            config.filter_numtaps = 65;
            config.spectrogram_nperseg = 64;
            config.spectrogram_noverlap = 48;
            config.spectrogram_nfft = 128;
            break;
        case 2:
            config.num_frames = 32;
            config.samples_per_frame = 768;
            config.template_length = 192;
            config.filter_numtaps = 97;
            config.spectrogram_nperseg = 96;
            config.spectrogram_noverlap = 72;
            config.spectrogram_nfft = 128;
            break;
        case 3:
            break;
        case 4:
            config.num_frames = 64;
            config.samples_per_frame = 1536;
            config.template_length = 384;
            config.filter_numtaps = 161;
            config.spectrogram_nperseg = 192;
            config.spectrogram_noverlap = 144;
            config.spectrogram_nfft = 256;
            break;
        case 5:
            config.num_frames = 80;
            config.samples_per_frame = 2048;
            config.template_length = 512;
            config.filter_numtaps = 193;
            config.spectrogram_nperseg = 256;
            config.spectrogram_noverlap = 192;
            config.spectrogram_nfft = 512;
            break;
        case 6:
            config.num_frames = 96;
            config.samples_per_frame = 3072;
            config.template_length = 768;
            config.filter_numtaps = 257;
            config.spectrogram_nperseg = 384;
            config.spectrogram_noverlap = 288;
            config.spectrogram_nfft = 512;
            break;
        default:
            break;
        }
        config.target_start_sample_0 = std::max(1, config.samples_per_frame * 55 / 256);
        config.interferer_start_sample = config.samples_per_frame * 5 / 8;
        config.interferer_length = config.template_length;
        config.representative_frame_index = config.num_frames / 2;
        return config;
    }

    ValidationThresholds thresholds_for_scale_level(int scale_level)
    {
        ValidationThresholds thresholds;
        switch (scale_level)
        {
        case 1:
            thresholds.gpu_total_baseline_ms = 30.0f;
            thresholds.gpu_total_hard_limit_ms = 40.0f;
            break;
        case 2:
            thresholds.gpu_total_baseline_ms = 50.0f;
            thresholds.gpu_total_hard_limit_ms = 65.0f;
            break;
        case 3:
            break;
        case 4:
            thresholds.gpu_total_baseline_ms = 160.0f;
            thresholds.gpu_total_hard_limit_ms = 200.0f;
            break;
        case 5:
            thresholds.gpu_total_baseline_ms = 360.0f;
            thresholds.gpu_total_hard_limit_ms = 450.0f;
            break;
        case 6:
            thresholds.gpu_total_baseline_ms = 720.0f;
            thresholds.gpu_total_hard_limit_ms = 900.0f;
            break;
        default:
            throw std::invalid_argument("scale_level must be in [1, 6]");
        }
#if defined(CUSIGNAL_PLATFORM_ZHONGKEXIN)
        if (scale_level == 1)
        {
            thresholds.gpu_total_baseline_ms = 40.0f;
            thresholds.gpu_total_hard_limit_ms = 50.0f;
        }
        else if (scale_level == 2)
        {
            thresholds.gpu_total_baseline_ms = 70.0f;
            thresholds.gpu_total_hard_limit_ms = 90.0f;
        }
        else if (scale_level == 3)
        {
            thresholds.gpu_total_baseline_ms = 120.0f;
            thresholds.gpu_total_hard_limit_ms = 150.0f;
        }
#endif
        return thresholds;
    }

    struct CpuArtifacts
    {
        ComplexSignal target_template;
        ComplexArray rx_frames;
        RealSignal truth_track;
        ComplexArray filtered;
        RealArray correlate_scores;
        RealArray spectrogram_values;
        RealSignal spectrogram_freqs;
        RealSignal spectrogram_times;
        ComplexArray cwt_values;
        RealArray feature_scores;
        RealSignal peak_track;
        RealSignal kalman_track;
    };

    struct GpuArtifacts
    {
        ZxGpuComplexArray filtered;
        ZxGpuRealArray correlate_scores;
        ZxGpuRealArray spectrogram_values;
        ZxGpuRealSignal spectrogram_freqs;
        ZxGpuRealSignal spectrogram_times;
        ZxGpuComplexArray cwt_values;
        ZxGpuRealArray feature_scores;
        ZxGpuRealSignal peak_track;
        ZxGpuRealSignal kalman_track;
    };

    struct HostGpuArtifacts
    {
        ComplexArray filtered;
        RealArray correlate_scores;
        RealArray spectrogram_values;
        RealSignal spectrogram_freqs;
        RealSignal spectrogram_times;
        ComplexArray cwt_values;
        RealArray feature_scores;
        RealSignal peak_track;
        RealSignal kalman_track;
    };

    struct DemoRunResult
    {
        CpuArtifacts cpu;
        HostGpuArtifacts gpu;
        std::vector<StageTiming> stage_timings;
        ErrorMetrics filtered_error;
        ErrorMetrics correlate_error;
        ErrorMetrics spectrogram_error;
        ErrorMetrics cwt_error;
        ErrorMetrics feature_score_error;
        ErrorMetrics kalman_error;
        float cpu_total_ms = 0.0f;
        float gpu_total_ms = 0.0f;
        bool cpu_gpu_track_match = false;
        bool gpu_matches_truth = false;
    };

    struct IterationSummary
    {
        int index = 0;
        bool pass = false;
        bool business_numeric_pass = false;
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
        return repo_root() / "data" / "generated" / "demo" / "task2_features";
    }

    fs::path report_root()
    {
        return repo_root() / "data" / "reports" / "demo" / "task2_features";
    }

    bool is_finite_positive(float value)
    {
        return std::isfinite(value) && value > 0.0f;
    }

    void validate_config(const ScenarioConfig &config)
    {
        if (!is_finite_positive(config.fs)) throw std::invalid_argument("fs must be finite and > 0");
        if (config.num_frames <= 0) throw std::invalid_argument("num_frames must be > 0");
        if (config.samples_per_frame <= 0) throw std::invalid_argument("samples_per_frame must be > 0");
        if (config.template_length <= 0) throw std::invalid_argument("template_length must be > 0");
        if (config.template_length > config.samples_per_frame)
            throw std::invalid_argument("template_length must be <= samples_per_frame");
        if (config.target_start_sample_0 < 0)
            throw std::invalid_argument("target_start_sample_0 must be >= 0");
        if (config.target_step_per_frame < 0)
            throw std::invalid_argument("target_step_per_frame must be >= 0");
        const int final_target_start =
            config.target_start_sample_0 + (config.num_frames - 1) * config.target_step_per_frame;
        if (final_target_start + config.template_length > config.samples_per_frame)
            throw std::invalid_argument("target trajectory must fit samples_per_frame");
        if (config.interferer_start_sample < 0 || config.interferer_length <= 0 ||
            config.interferer_start_sample + config.interferer_length > config.samples_per_frame)
            throw std::invalid_argument("interferer_start_sample/interferer_length must fit samples_per_frame");
        if (!is_finite_positive(config.target_amplitude))
            throw std::invalid_argument("target_amplitude must be finite and > 0");
        if (!std::isfinite(config.interferer_amplitude) || config.interferer_amplitude < 0.0f)
            throw std::invalid_argument("interferer_amplitude must be finite and >= 0");
        if (!std::isfinite(config.snr_db)) throw std::invalid_argument("snr_db must be finite");
        if (!is_finite_positive(config.chirp_f0) || !is_finite_positive(config.chirp_f1) ||
            config.chirp_f1 <= config.chirp_f0 || config.chirp_f1 >= 0.5f * config.fs)
            throw std::invalid_argument("chirp_f0/chirp_f1 must be finite, increasing, and below Nyquist");
        if (!is_finite_positive(config.gausspulse_fc) || config.gausspulse_fc >= 0.5f * config.fs)
            throw std::invalid_argument("gausspulse_fc must be finite and below Nyquist");
        if (!is_finite_positive(config.interferer_f0) || !is_finite_positive(config.interferer_f1) ||
            config.interferer_f1 <= config.interferer_f0 || config.interferer_f1 >= 0.5f * config.fs)
            throw std::invalid_argument("interferer_f0/interferer_f1 must be finite, increasing, and below Nyquist");
        if (config.representative_frame_index < 0 || config.representative_frame_index >= config.num_frames)
            throw std::invalid_argument("representative_frame_index must be within num_frames");
        if (config.filter_numtaps <= 0 || config.filter_numtaps % 2 == 0)
            throw std::invalid_argument("filter_numtaps must be a positive odd number");
        if (!is_finite_positive(config.filter_low) || !is_finite_positive(config.filter_high) ||
            config.filter_low >= config.filter_high || config.filter_high >= 0.5f * config.fs)
            throw std::invalid_argument("filter_low/filter_high must form a valid band below Nyquist");
        if (config.spectrogram_nperseg <= 0 || config.spectrogram_noverlap < 0 || config.spectrogram_nfft <= 0)
            throw std::invalid_argument("spectrogram_nperseg/noverlap/nfft must be positive");
        if (config.spectrogram_noverlap >= config.spectrogram_nperseg ||
            config.spectrogram_nperseg > config.spectrogram_nfft ||
            config.spectrogram_nperseg > config.samples_per_frame)
            throw std::invalid_argument("spectrogram requires noverlap < nperseg <= nfft and nperseg <= samples_per_frame");
        if (config.peak_order < 1) throw std::invalid_argument("peak_order must be >= 1");
        if (!is_finite_positive(config.kalman_rmse_tolerance))
            throw std::invalid_argument("kalman_rmse_tolerance must be finite and > 0");
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
            snapshot.gpu_device = device;
            cudaDeviceProp prop{};
            if (cudaGetDeviceProperties(&prop, device) == cudaSuccess)
            {
                snapshot.gpu_device_name = prop.name;
            }
        }
        std::size_t free_bytes = 0;
        std::size_t total_bytes = 0;
        if (cudaMemGetInfo(&free_bytes, &total_bytes) == cudaSuccess)
        {
            snapshot.gpu_free_mib = static_cast<double>(free_bytes) / (1024.0 * 1024.0);
            snapshot.gpu_total_mib = static_cast<double>(total_bytes) / (1024.0 * 1024.0);
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
                std::cout << "usage: task2_features_demo [--repeat N] [--scale-level 1..6] [--invalid-input-checks] "
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
        stream << child << "\"gpu_free_mib\": " << snapshot.gpu_free_mib << ",\n";
        stream << child << "\"gpu_total_mib\": " << snapshot.gpu_total_mib << ",\n";
        stream << child << "\"gpu_device\": " << snapshot.gpu_device << ",\n";
        stream << child << "\"gpu_device_name\": \"" << json_escape(snapshot.gpu_device_name) << "\"\n";
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
        stream << child << "\"gpu_free_delta_mib\": " << (after.gpu_free_mib - before.gpu_free_mib) << ",\n";
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
                   << ", \"business_numeric_pass\": " << bool_json(iteration.business_numeric_pass)
                   << ", \"cpu_total_ms\": " << iteration.cpu_total_ms
                   << ", \"gpu_total_ms\": " << iteration.gpu_total_ms
                   << ", \"gpu_free_mib\": " << iteration.resource_after.gpu_free_mib
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
            return values;
        }
        const float step = (stop - start) / static_cast<float>(count - 1);
        for (int index = 0; index < count; ++index)
        {
            values[static_cast<std::size_t>(index)] = start + step * static_cast<float>(index);
        }
        return values;
    }

    RealSignal even_range(float start, float stop, float step)
    {
        RealSignal values;
        for (float value = start; value <= stop + 1.0e-6f; value += step)
        {
            values.push_back(value);
        }
        return values;
    }

    ComplexArray as_complex_array(const ComplexSignal &signal)
    {
        return cusignal::core::as_complex_array(signal);
    }

    RealArray as_real_array(const RealSignal &signal)
    {
        return cusignal::core::as_real_array(signal);
    }

    RealSignal extract_real_signal(const ComplexSignal &input)
    {
        RealSignal output(input.size(), 0.0f);
        for (std::size_t index = 0; index < input.size(); ++index)
        {
            output[index] = input[index].real();
        }
        return output;
    }

    RealSignal extract_imag_signal(const ComplexSignal &input)
    {
        RealSignal output(input.size(), 0.0f);
        for (std::size_t index = 0; index < input.size(); ++index)
        {
            output[index] = input[index].imag();
        }
        return output;
    }

    ComplexSignal combine_complex_signal(const RealSignal &real_part, const RealSignal &imag_part)
    {
        if (real_part.size() != imag_part.size())
        {
            throw std::invalid_argument("real/imag signal size mismatch");
        }
        ComplexSignal output(real_part.size(), Complex(0.0f, 0.0f));
        for (std::size_t index = 0; index < real_part.size(); ++index)
        {
            output[index] = Complex(real_part[index], imag_part[index]);
        }
        return output;
    }

    ComplexSignal extract_row_complex_signal(const ComplexArray &input, int row_index)
    {
        if (input.shape.size() != 2)
        {
            throw std::invalid_argument("extract_row_complex_signal expects rank-2 input");
        }
        const std::size_t cols = input.shape[1];
        ComplexSignal output(cols, Complex(0.0f, 0.0f));
        const std::size_t offset = static_cast<std::size_t>(row_index) * cols;
        for (std::size_t col = 0; col < cols; ++col)
        {
            output[col] = input.values[offset + col];
        }
        return output;
    }

    void store_row_real(RealArray &output, const RealSignal &row, int row_index)
    {
        if (output.shape.size() != 2 || output.shape[1] != row.size())
        {
            throw std::invalid_argument("store_row_real shape mismatch");
        }
        const std::size_t offset = static_cast<std::size_t>(row_index) * output.shape[1];
        for (std::size_t col = 0; col < row.size(); ++col)
        {
            output.values[offset + col] = row[col];
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

    float mixed_error_for_sample(float abs_error, float expected_norm, float reference_scale, float scale_factor)
    {
        const float effective_atol = std::max(kMixedErrorAtol, scale_factor * reference_scale);
        return expected_norm <= effective_atol ? abs_error : abs_error / expected_norm;
    }

    ErrorMetrics compute_real_error(const RealSignal &lhs, const RealSignal &rhs, float scale_factor = kDefaultMixedScale)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::invalid_argument("real signal size mismatch");
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
            metrics.mixed_error =
                std::max(metrics.mixed_error, mixed_error_for_sample(diff, expected_norm, reference_scale, scale_factor));
            squared += static_cast<float>(diff) * static_cast<float>(diff);
        }
        metrics.rmse = static_cast<float>(std::sqrt(squared / static_cast<float>(lhs.size())));
        return metrics;
    }

    ErrorMetrics compute_complex_error(const ComplexSignal &lhs, const ComplexSignal &rhs, float scale_factor = kDefaultMixedScale)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::invalid_argument("complex signal size mismatch");
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
            metrics.mixed_error =
                std::max(metrics.mixed_error, mixed_error_for_sample(diff, expected_norm, reference_scale, scale_factor));
            squared += static_cast<float>(diff) * static_cast<float>(diff);
        }
        metrics.rmse = static_cast<float>(std::sqrt(squared / static_cast<float>(lhs.size())));
        return metrics;
    }

    template <typename T>
    ErrorMetrics compute_real_array_error(
        const cusignal::core::Tensor<T> &lhs,
        const cusignal::core::Tensor<T> &rhs,
        float scale_factor = kDefaultMixedScale)
    {
        if (lhs.shape != rhs.shape)
        {
            throw std::invalid_argument("tensor shape mismatch");
        }
        if constexpr (std::is_same_v<T, float>)
        {
            return compute_real_error(lhs.values, rhs.values, scale_factor);
        }
        else
        {
            return compute_complex_error(lhs.values, rhs.values, scale_factor);
        }
    }

    ValidationResult validate_single_run(
        const DemoRunResult &run,
        const ValidationThresholds &thresholds,
        bool invalid_input_checks_passed,
        float kalman_rmse_tolerance,
        bool skip_timing_validation)
    {
        ValidationResult validation;
        add_check(
            validation,
            "cpu_gpu_track_match",
            run.cpu_gpu_track_match,
            run.cpu_gpu_track_match ? 1.0 : 0.0,
            1.0,
            "CPU/GPU peak tracks must match within task tolerance");
        add_check(
            validation,
            "gpu_matches_truth_within_tolerance",
            run.gpu_matches_truth,
            run.gpu_matches_truth ? 1.0 : 0.0,
            1.0,
            "GPU Kalman track must match truth within RMSE tolerance");
        add_check(
            validation,
            "kalman_rmse",
            run.kalman_error.rmse <= kalman_rmse_tolerance,
            run.kalman_error.rmse,
            kalman_rmse_tolerance,
            "Kalman RMSE is the business-level track error gate");
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
            "filtered_mixed_error",
            run.filtered_error.mixed_error <= thresholds.filtered_mixed,
            run.filtered_error.mixed_error,
            thresholds.filtered_mixed,
            "filtered CPU/GPU mixed error");
        add_check(
            validation,
            "correlate_mixed_error",
            run.correlate_error.mixed_error <= thresholds.correlate_mixed,
            run.correlate_error.mixed_error,
            thresholds.correlate_mixed,
            "correlate CPU/GPU mixed error");
        add_check(
            validation,
            "spectrogram_mixed_error",
            run.spectrogram_error.mixed_error <= thresholds.spectrogram_mixed,
            run.spectrogram_error.mixed_error,
            thresholds.spectrogram_mixed,
            "spectrogram CPU/GPU mixed error");
        add_check(
            validation,
            "cwt_mixed_error",
            run.cwt_error.mixed_error <= thresholds.cwt_mixed,
            run.cwt_error.mixed_error,
            thresholds.cwt_mixed,
            "CWT CPU/GPU mixed error");
        add_check(
            validation,
            "feature_score_mixed_error",
            run.feature_score_error.mixed_error <= thresholds.feature_score_mixed,
            run.feature_score_error.mixed_error,
            thresholds.feature_score_mixed,
            "feature score CPU/GPU mixed error");
        add_check(
            validation,
            "invalid_input_checks",
            invalid_input_checks_passed,
            invalid_input_checks_passed ? 1.0 : 0.0,
            1.0,
            "invalid configuration matrix must raise std::invalid_argument with field names");
        return validation;
    }

    bool validation_pass_excluding_timing(const ValidationResult &validation)
    {
        for (const ValidationCheck &check : validation.checks)
        {
            if (check.name == "gpu_total_ms")
            {
                continue;
            }
            if (!check.pass)
            {
                return false;
            }
        }
        return true;
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
            all_iterations_pass = all_iterations_pass && iteration.business_numeric_pass;
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
            const double gpu_free_drop = first.gpu_free_mib - last.gpu_free_mib;
            const double rss_growth = last.rss_current_mib - first.rss_current_mib;
            add_check(
                validation,
                "gpu_free_memory_drift_mib",
                gpu_free_drop <= thresholds.gpu_free_drift_mib,
                gpu_free_drop,
                thresholds.gpu_free_drift_mib,
                "final GPU free memory must not drop materially after repeats");
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
            config.num_frames = 0;
            results.push_back(expect_invalid_config("num_frames_zero", "num_frames", config));
        }
        {
            ScenarioConfig config = base;
            config.template_length = base.samples_per_frame + 1;
            results.push_back(expect_invalid_config("template_too_long", "template_length", config));
        }
        {
            ScenarioConfig config = base;
            config.target_step_per_frame = 100;
            results.push_back(expect_invalid_config("target_trajectory_out_of_bounds", "target trajectory", config));
        }
        {
            ScenarioConfig config = base;
            config.spectrogram_noverlap = base.spectrogram_nperseg;
            results.push_back(expect_invalid_config("spectrogram_overlap_invalid", "spectrogram", config));
        }
        {
            ScenarioConfig config = base;
            config.filter_high = 0.5f * base.fs;
            results.push_back(expect_invalid_config("filter_band_invalid", "filter_low/filter_high", config));
        }
        {
            ScenarioConfig config = base;
            config.kalman_rmse_tolerance = 0.0f;
            results.push_back(expect_invalid_config("kalman_tolerance_invalid", "kalman_rmse_tolerance", config));
        }
        return std::all_of(results.begin(), results.end(), [](bool value) { return value; });
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
        cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
        const auto end = std::chrono::steady_clock::now();
        const float elapsed_ms = std::chrono::duration<float, std::milli>(end - start).count();
        return std::make_pair(std::move(value), elapsed_ms);
    }

    float sum_positive(const RealSignal &values)
    {
        float sum = 0.0f;
        for (float value : values)
        {
            sum += value;
        }
        return sum;
    }

    RealSignal normalize_nonnegative_cpu(const RealSignal &values)
    {
        RealSignal output(values.size(), 0.0f);
        float max_value = 0.0f;
        for (float value : values)
        {
            max_value = std::max(max_value, value);
        }
        if (max_value <= 1.0e-12f)
        {
            return output;
        }
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output[index] = values[index] / max_value;
        }
        return output;
    }

    RealSignal pad_last_value_cpu(const RealSignal &values, std::size_t target_len)
    {
        RealSignal output(target_len, 0.0f);
        if (values.empty())
        {
            return output;
        }
        for (std::size_t index = 0; index < target_len; ++index)
        {
            output[index] = values[index < values.size() ? index : (values.size() - 1)];
        }
        return output;
    }

    RealSignal spectrogram_band_score_cpu(
        const RealArray &values,
        const RealSignal &freqs,
        const RealSignal &times,
        int sample_count,
        float band_low,
        float band_high,
        float fs)
    {
        if (values.shape.size() != 2 || values.shape[0] != freqs.size() || values.shape[1] != times.size())
        {
            throw std::invalid_argument("spectrogram_band_score_cpu shape mismatch");
        }
        const std::size_t freq_count = values.shape[0];
        const std::size_t time_count = values.shape[1];
        RealSignal time_energy(time_count, 0.0f);
        for (std::size_t time_index = 0; time_index < time_count; ++time_index)
        {
            float sum = 0.0f;
            for (std::size_t freq_index = 0; freq_index < freq_count; ++freq_index)
            {
                if (freqs[freq_index] >= band_low && freqs[freq_index] <= band_high)
                {
                    sum += values.values[freq_index * time_count + time_index];
                }
            }
            time_energy[time_index] = sum;
        }

        RealSignal output(static_cast<std::size_t>(sample_count), 0.0f);
        for (int sample = 0; sample < sample_count; ++sample)
        {
            const float target_time = static_cast<float>(sample) / fs;
            std::size_t best_index = 0;
            float best_distance = std::fabs(times[0] - target_time);
            for (std::size_t time_index = 1; time_index < time_count; ++time_index)
            {
                const float distance = std::fabs(times[time_index] - target_time);
                if (distance < best_distance)
                {
                    best_distance = distance;
                    best_index = time_index;
                }
            }
            output[static_cast<std::size_t>(sample)] = time_energy[best_index];
        }
        return output;
    }

    RealSignal cwt_max_score_cpu(const ComplexArray &values)
    {
        if (values.shape.size() != 2)
        {
            throw std::invalid_argument("cwt_max_score_cpu expects rank-2 input");
        }
        const std::size_t widths = values.shape[0];
        const std::size_t samples = values.shape[1];
        RealSignal output(samples, 0.0f);
        for (std::size_t sample = 0; sample < samples; ++sample)
        {
            float best = 0.0f;
            for (std::size_t width_index = 0; width_index < widths; ++width_index)
            {
                best = std::max(best, std::abs(values.values[width_index * samples + sample]));
            }
            output[sample] = best;
        }
        return output;
    }

    RealSignal smooth_with_weights_cpu(const RealSignal &input, const RealSignal &weights)
    {
        RealSignal output(input.size(), 0.0f);
        if (input.empty() || weights.empty())
        {
            return output;
        }
        const int radius = static_cast<int>(weights.size() / 2);
        for (std::size_t index = 0; index < input.size(); ++index)
        {
            float sum = 0.0f;
            for (std::size_t weight_index = 0; weight_index < weights.size(); ++weight_index)
            {
                int sample_index = static_cast<int>(index) + static_cast<int>(weight_index) - radius;
                sample_index = std::max(0, std::min(sample_index, static_cast<int>(input.size()) - 1));
                sum += weights[weight_index] * input[static_cast<std::size_t>(sample_index)];
            }
            output[index] = sum;
        }
        return output;
    }

    int argmax_cpu(const RealSignal &values)
    {
        if (values.empty())
        {
            return 0;
        }
        return static_cast<int>(std::distance(values.begin(), std::max_element(values.begin(), values.end())));
    }

    int select_peak_cpu(const RealSignal &score, int order)
    {
        const auto extrema = cusignal::cpu::peak_finding::argrelmax(as_real_array(score), 0, order, "clip");
        if (extrema.indices.empty() || extrema.indices[0].empty())
        {
            return argmax_cpu(score);
        }
        int best_index = extrema.indices[0][0];
        float best_value = score[static_cast<std::size_t>(best_index)];
        for (int candidate : extrema.indices[0])
        {
            if (score[static_cast<std::size_t>(candidate)] > best_value)
            {
                best_value = score[static_cast<std::size_t>(candidate)];
                best_index = candidate;
            }
        }
        return best_index;
    }

    RealSignal build_bspline_weights_cpu()
    {
        const RealSignal offsets{-2.0f, -1.0f, 0.0f, 1.0f, 2.0f};
        const RealArray weights_array = cusignal::cpu::bsplines::cubic(as_real_array(offsets));
        RealSignal weights = weights_array.values;
        const float sum = sum_positive(weights);
        if (sum <= 1.0e-12f)
        {
            throw std::runtime_error("invalid bspline weights");
        }
        for (float &value : weights)
        {
            value /= sum;
        }
        return weights;
    }

    ZxGpuRealSignal build_bspline_weights_gpu()
    {
        const RealSignal offsets{-2.0f, -1.0f, 0.0f, 1.0f, 2.0f};
        const ZxGpuRealArray weights_array = cusignal::zx_gpu_backend::bsplines::cubic(as_real_array(offsets));
        RealSignal weights = weights_array.get().values;
        const float sum = sum_positive(weights);
        if (sum <= 1.0e-12f)
        {
            throw std::runtime_error("invalid gpu bspline weights");
        }
        for (float &value : weights)
        {
            value /= sum;
        }
        return ZxGpuRealSignal::from_host(weights);
    }

    ComplexSignal build_target_template(const ScenarioConfig &config)
    {
        const float t1 = static_cast<float>(config.template_length - 1) / config.fs;
        const RealSignal t = linspace(0.0f, t1, config.template_length);
        const RealSignal env_time = linspace(-0.5f * t1, 0.5f * t1, config.template_length);
        const auto chirp_result = cusignal::cpu::waveforms::chirp(
            t,
            config.chirp_f0,
            t1,
            config.chirp_f1,
            "linear",
            0.0f,
            true,
            "complex");
        if (!std::holds_alternative<ComplexSignal>(chirp_result))
        {
            throw std::runtime_error("chirp did not return complex output");
        }
        const auto gauss_result = cusignal::cpu::waveforms::gausspulse(
            env_time,
            config.gausspulse_fc,
            0.5f,
            -6.0f,
            -40.0f,
            false,
            true);
        if (!std::holds_alternative<IEnvWaveform>(gauss_result))
        {
            throw std::runtime_error("gausspulse did not return envelope output");
        }

        ComplexSignal templ = std::get<ComplexSignal>(chirp_result);
        const RealSignal envelope = std::get<IEnvWaveform>(gauss_result).envelope;
        float max_mag = 0.0f;
        for (std::size_t index = 0; index < templ.size(); ++index)
        {
            templ[index] *= envelope[index];
            max_mag = std::max(max_mag, std::abs(templ[index]));
        }
        if (max_mag <= 1.0e-12f)
        {
            throw std::runtime_error("target template magnitude collapsed to zero");
        }
        for (Complex &value : templ)
        {
            value /= max_mag;
        }
        return templ;
    }

    ComplexSignal build_interferer_signal(const ScenarioConfig &config)
    {
        const float two_pi = 2.0f * 3.14159265358979323846f;
        RealSignal phase(config.interferer_length, 0.0f);
        RealSignal phase_alt(config.interferer_length, 0.0f);
        for (int index = 0; index < config.interferer_length; ++index)
        {
            const float time = static_cast<float>(index) / config.fs;
            phase[static_cast<std::size_t>(index)] = two_pi * config.interferer_f0 * time;
            phase_alt[static_cast<std::size_t>(index)] = two_pi * config.interferer_f1 * time;
        }
        const RealSignal saw = cusignal::cpu::waveforms::sawtooth(phase, 0.7f);
        const RealSignal sq = cusignal::cpu::waveforms::square(phase_alt, 0.35f);
        ComplexSignal output(static_cast<std::size_t>(config.interferer_length), Complex(0.0f, 0.0f));
        for (int index = 0; index < config.interferer_length; ++index)
        {
            const float real_value = 0.7f * saw[static_cast<std::size_t>(index)] +
                0.3f * sq[static_cast<std::size_t>(index)];
            const float imag_value = 0.25f * sq[static_cast<std::size_t>(index)];
            output[static_cast<std::size_t>(index)] = config.interferer_amplitude * Complex(real_value, imag_value);
        }
        return output;
    }

    ComplexArray simulate_frames(
        const ScenarioConfig &config,
        const ComplexSignal &target_template,
        const ComplexSignal &interferer_signal,
        bool include_interference,
        bool include_noise)
    {
        ComplexArray frames = cusignal::core::make_complex_array(
            Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)},
            Complex(0.0f, 0.0f));
        const float linear_snr = std::pow(10.0f, config.snr_db / 10.0f);
        const float sigma = include_noise ? (config.target_amplitude / std::sqrt(2.0f * linear_snr)) : 0.0f;
        std::mt19937 rng(config.seed);
        std::normal_distribution<float> noise_dist(0.0f, sigma);

        for (int frame = 0; frame < config.num_frames; ++frame)
        {
            const int target_start = config.target_start_sample_0 + frame * config.target_step_per_frame;
            for (int sample = 0; sample < config.samples_per_frame; ++sample)
            {
                Complex value(
                    include_noise ? noise_dist(rng) : 0.0f,
                    include_noise ? noise_dist(rng) : 0.0f);

                const int templ_index = sample - target_start;
                if (templ_index >= 0 && templ_index < static_cast<int>(target_template.size()))
                {
                    value += config.target_amplitude * target_template[static_cast<std::size_t>(templ_index)];
                }

                if (include_interference)
                {
                    const int interferer_index = sample - config.interferer_start_sample;
                    if (interferer_index >= 0 && interferer_index < static_cast<int>(interferer_signal.size()))
                    {
                        value += interferer_signal[static_cast<std::size_t>(interferer_index)];
                    }
                }

                frames.values[static_cast<std::size_t>(frame) * static_cast<std::size_t>(config.samples_per_frame) +
                    static_cast<std::size_t>(sample)] = value;
            }
        }
        return frames;
    }

    RealSignal build_filter_taps_cpu(const ScenarioConfig &config)
    {
        const RealSignal cutoff{config.filter_low, config.filter_high};
        return cusignal::cpu::filter_design::firwin(
            config.filter_numtaps,
            cutoff,
            -1.0f,
            cusignal::core::NamedFloatParameter{"kaiser", 8.0f},
            std::string("bandpass"),
            true,
            -1.0f,
            config.fs);
    }

    ZxGpuRealSignal build_filter_taps_gpu(const ScenarioConfig &config)
    {
        const RealSignal cutoff{config.filter_low, config.filter_high};
        return cusignal::zx_gpu_backend::filter_design::firwin(
            config.filter_numtaps,
            cutoff,
            -1.0f,
            cusignal::core::NamedFloatParameter{"kaiser", 8.0f},
            std::string("bandpass"),
            true,
            -1.0f,
            config.fs);
    }

    ComplexArray filter_complex_frames_cpu(
        const RealSignal &taps,
        const ComplexArray &input)
    {
        if (input.shape.size() != 2)
        {
            throw std::invalid_argument("filter_complex_frames_cpu expects rank-2 input");
        }
        RealArray real_part = cusignal::core::make_real_array(input.shape, 0.0f);
        RealArray imag_part = cusignal::core::make_real_array(input.shape, 0.0f);
        for (std::size_t index = 0; index < input.values.size(); ++index)
        {
            real_part.values[index] = input.values[index].real();
            imag_part.values[index] = input.values[index].imag();
        }
        const RealArray filtered_real = cusignal::cpu::filtering::firfilter(taps, real_part, -1);
        const RealArray filtered_imag = cusignal::cpu::filtering::firfilter(taps, imag_part, -1);
        ComplexArray output = cusignal::core::make_complex_array(input.shape, Complex(0.0f, 0.0f));
        for (std::size_t index = 0; index < input.values.size(); ++index)
        {
            output.values[index] = Complex(filtered_real.values[index], filtered_imag.values[index]);
        }
        return output;
    }

    struct FrameCpuResult
    {
        RealSignal correlate_score;
        RealSignal feature_score;
        SpectrogramResult spectrogram;
        ComplexArray cwt_values;
        int peak_index = 0;
    };

    FrameCpuResult process_frame_cpu(
        const ScenarioConfig &config,
        const ComplexSignal &frame,
        const ComplexSignal &target_template,
        const RealSignal &widths,
        const RealSignal &bspline_weights,
        float &demod_ms,
        float &correlate_ms,
        float &spectrogram_ms,
        float &cwt_ms,
        float &fusion_ms)
    {
        FrameCpuResult result;
        const RealSignal real_frame = extract_real_signal(frame);

        auto [demod_array, demod_elapsed] = measure_cpu_ms([&]() {
            return cusignal::cpu::demod::fm_demod(as_complex_array(frame), -1);
        });
        demod_ms += demod_elapsed;
        const RealSignal demod_score = normalize_nonnegative_cpu(
            pad_last_value_cpu(demod_array.values, frame.size()));

        auto [corr_array, corr_elapsed] = measure_cpu_ms([&]() {
            return cusignal::cpu::correlate::correlate(
                as_complex_array(frame),
                as_complex_array(target_template),
                "same",
                "fft");
        });
        correlate_ms += corr_elapsed;
        result.correlate_score = normalize_nonnegative_cpu(magnitude_signal(corr_array.values));

        auto [spectrogram_result, spectrogram_elapsed] = measure_cpu_ms([&]() {
            return cusignal::cpu::spectral::spectrogram(
                as_real_array(real_frame),
                config.fs,
                std::string("hann"),
                config.spectrogram_nperseg,
                config.spectrogram_noverlap,
                config.spectrogram_nfft,
                std::string("constant"),
                true,
                "spectrum",
                -1,
                "magnitude");
        });
        spectrogram_ms += spectrogram_elapsed;
        if (!std::holds_alternative<RealArray>(spectrogram_result.values))
        {
            throw std::runtime_error("spectrogram did not return real values");
        }
        result.spectrogram = std::move(spectrogram_result);
        const RealSignal spectrogram_score = normalize_nonnegative_cpu(
            spectrogram_band_score_cpu(
                std::get<RealArray>(result.spectrogram.values),
                result.spectrogram.frequencies,
                result.spectrogram.times,
                config.samples_per_frame,
                config.filter_low,
                config.filter_high,
                config.fs));

        auto [cwt_values, cwt_elapsed] = measure_cpu_ms([&]() {
            return cusignal::cpu::wavelets::cwt(real_frame, "morlet2", widths);
        });
        cwt_ms += cwt_elapsed;
        result.cwt_values = std::move(cwt_values);
        const RealSignal wavelet_score = normalize_nonnegative_cpu(cwt_max_score_cpu(result.cwt_values));

        auto [fused_signal, fusion_elapsed] = measure_cpu_ms([&]() {
            RealSignal fused(frame.size(), 0.0f);
            for (std::size_t index = 0; index < fused.size(); ++index)
            {
                fused[index] =
                    0.45f * result.correlate_score[index] +
                    0.20f * demod_score[index] +
                    0.20f * wavelet_score[index] +
                    0.15f * spectrogram_score[index];
            }
            return smooth_with_weights_cpu(fused, bspline_weights);
        });
        fusion_ms += fusion_elapsed;
        result.feature_score = std::move(fused_signal);
        result.peak_index = select_peak_cpu(result.feature_score, config.peak_order);
        return result;
    }

    std::pair<CpuArtifacts, std::vector<StageTiming>> run_cpu_pipeline(
        const ScenarioConfig &config,
        const ComplexSignal &target_template,
        const ComplexArray &rx_frames,
        const RealSignal &truth_track)
    {
        CpuArtifacts artifacts;
        artifacts.target_template = target_template;
        artifacts.rx_frames = rx_frames;
        artifacts.truth_track = truth_track;

        std::vector<StageTiming> timings;
        const RealSignal widths = even_range(4.0f, 32.0f, 2.0f);
        const RealSignal bspline_weights = build_bspline_weights_cpu();
        const RealSignal taps = build_filter_taps_cpu(config);

        auto [filtered, filter_ms] = measure_cpu_ms([&]() {
            return filter_complex_frames_cpu(taps, rx_frames);
        });
        artifacts.filtered = std::move(filtered);
        timings.push_back({"filter", filter_ms, 0.0});

        artifacts.correlate_scores = cusignal::core::make_real_array(
            Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)},
            0.0f);
        artifacts.feature_scores = cusignal::core::make_real_array(
            Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)},
            0.0f);
        artifacts.peak_track = RealSignal(static_cast<std::size_t>(config.num_frames), 0.0f);

        float demod_ms = 0.0;
        float correlate_ms = 0.0;
        float spectrogram_ms = 0.0;
        float cwt_ms = 0.0;
        float fusion_ms = 0.0;

        for (int frame = 0; frame < config.num_frames; ++frame)
        {
            const ComplexSignal frame_signal = extract_row_complex_signal(artifacts.filtered, frame);
            const FrameCpuResult frame_result = process_frame_cpu(
                config,
                frame_signal,
                artifacts.target_template,
                widths,
                bspline_weights,
                demod_ms,
                correlate_ms,
                spectrogram_ms,
                cwt_ms,
                fusion_ms);

            store_row_real(artifacts.correlate_scores, frame_result.correlate_score, frame);
            store_row_real(artifacts.feature_scores, frame_result.feature_score, frame);
            artifacts.peak_track[static_cast<std::size_t>(frame)] = static_cast<float>(frame_result.peak_index);
            if (frame == config.representative_frame_index)
            {
                artifacts.spectrogram_values = std::get<RealArray>(frame_result.spectrogram.values);
                artifacts.spectrogram_freqs = frame_result.spectrogram.frequencies;
                artifacts.spectrogram_times = frame_result.spectrogram.times;
                artifacts.cwt_values = frame_result.cwt_values;
            }
        }

        timings.push_back({"demod", demod_ms, 0.0});
        timings.push_back({"correlate", correlate_ms, 0.0});
        timings.push_back({"spectrogram", spectrogram_ms, 0.0});
        timings.push_back({"cwt", cwt_ms, 0.0});
        timings.push_back({"feature_fusion", fusion_ms, 0.0});

        auto [kalman_track, kalman_ms] = measure_cpu_ms([&]() {
            cusignal::cpu::estimation::KalmanFilter filter(2, 1, 0, 1, "float32");
            filter.F = cusignal::core::make_real_array(Shape{1, 2, 2}, 0.0f);
            filter.F.values = {1.0f, 1.0f, 0.0f, 1.0f};
            filter.H = cusignal::core::make_real_array(Shape{1, 1, 2}, 0.0f);
            filter.H.values = {1.0f, 0.0f};
            filter.Q = cusignal::core::make_real_array(Shape{1, 2, 2}, 0.0f);
            filter.Q.values = {0.25f, 0.0f, 0.0f, 0.05f};
            filter.R = cusignal::core::make_real_array(Shape{1, 1, 1}, 0.0f);
            filter.R.values = {4.0f};
            filter.P = cusignal::core::make_real_array(Shape{1, 2, 2}, 0.0f);
            filter.P.values = {25.0f, 0.0f, 0.0f, 4.0f};
            filter.x = cusignal::core::make_real_array(Shape{1, 2, 1}, 0.0f);
            filter.x.values = {artifacts.peak_track[0], 0.0f};

            RealSignal kalman(static_cast<std::size_t>(config.num_frames), 0.0f);
            kalman[0] = artifacts.peak_track[0];
            for (int frame = 1; frame < config.num_frames; ++frame)
            {
                filter.predict();
                RealArray measurement = cusignal::core::make_real_array(Shape{1, 1, 1}, 0.0f);
                measurement.values[0] = artifacts.peak_track[static_cast<std::size_t>(frame)];
                filter.update(measurement);
                kalman[static_cast<std::size_t>(frame)] = filter.x.values[0];
            }
            return kalman;
        });
        artifacts.kalman_track = std::move(kalman_track);
        timings.push_back({"kalman", kalman_ms, 0.0});
        return std::make_pair(std::move(artifacts), std::move(timings));
    }

    std::pair<GpuArtifacts, std::vector<StageTiming>> run_gpu_pipeline(
        const ScenarioConfig &config,
        const ComplexSignal &target_template,
        const ComplexArray &rx_frames)
    {
        GpuArtifacts artifacts;
        std::vector<StageTiming> timings;
        const RealSignal widths = even_range(4.0f, 32.0f, 2.0f);
        const ZxGpuRealSignal widths_device = ZxGpuRealSignal::from_host(widths);
        const ZxGpuRealSignal bspline_weights = build_bspline_weights_gpu();
        const ZxGpuRealSignal taps = build_filter_taps_gpu(config);
        const ZxGpuComplexArray template_device = ZxGpuComplexArray::from_host(as_complex_array(target_template));

        ZxGpuComplexArray rx_device;
        ZxGpuRealArray filtered_real;
        ZxGpuRealArray filtered_imag;

        auto [filtered_complex, filter_ms] = measure_gpu_ms([&]() {
            rx_device = ZxGpuComplexArray::from_host(rx_frames);
            const ZxGpuRealArray real_part = extract_real_part_zx_gpu(rx_device);
            const ZxGpuRealArray imag_part = extract_imag_part_zx_gpu(rx_device);
            filtered_real = cusignal::zx_gpu_backend::filtering::firfilter(taps, real_part, -1);
            filtered_imag = cusignal::zx_gpu_backend::filtering::firfilter(taps, imag_part, -1);
            return combine_complex_zx_gpu(filtered_real, filtered_imag);
        });
        artifacts.filtered = std::move(filtered_complex);
        timings.push_back({"filter", 0.0, filter_ms});

        artifacts.correlate_scores = cusignal::core::make_zx_gpu_real_array(
            Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)},
            0.0f);
        artifacts.feature_scores = cusignal::core::make_zx_gpu_real_array(
            Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)},
            0.0f);
        artifacts.peak_track = cusignal::core::make_zx_gpu_real_signal(static_cast<std::size_t>(config.num_frames), 0.0f);
        ZxGpuRealArray wavelet_scores = cusignal::core::make_zx_gpu_real_array(
            Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)},
            0.0f);
        ZxGpuRealArray spectrogram_scores = cusignal::core::make_zx_gpu_real_array(
            Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)},
            0.0f);

        auto demod_scores_measured = measure_gpu_ms([&]() {
            return batched_demod_score_zx_gpu(artifacts.filtered);
        });
        auto demod_scores = std::move(demod_scores_measured.first);
        const float demod_ms = demod_scores_measured.second;
        float correlate_ms = 0.0;
        float spectrogram_ms = 0.0;
        float cwt_ms = 0.0;
        float fusion_ms = 0.0;

        for (int frame = 0; frame < config.num_frames; ++frame)
        {
            const ZxGpuComplexArray frame_complex = extract_row_complex_zx_gpu(artifacts.filtered, frame);
            const ZxGpuRealArray frame_real = extract_row_real_zx_gpu(filtered_real, frame);
            const ZxGpuRealSignal frame_real_signal = extract_row_real_signal_zx_gpu(filtered_real, frame);

            auto [corr_score, corr_elapsed] = measure_gpu_ms([&]() {
                const ZxGpuComplexArray corr = cusignal::zx_gpu_backend::correlate::correlate(
                    frame_complex,
                    template_device,
                    "same",
                    "fft");
                return normalize_nonnegative_zx_gpu(complex_abs_zx_gpu(corr));
            });
            correlate_ms += corr_elapsed;
            store_row_real_zx_gpu(corr_score, artifacts.correlate_scores, frame);

            auto spectrogram_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::spectral::spectrogram(
                    frame_real,
                    config.fs,
                    std::string("hann"),
                    config.spectrogram_nperseg,
                    config.spectrogram_noverlap,
                    config.spectrogram_nfft,
                    std::string("constant"),
                    true,
                    "spectrum",
                    -1,
                    "magnitude");
            });
            auto spectrogram_result = std::move(spectrogram_measured.first);
            const float spectrogram_elapsed = spectrogram_measured.second;
            spectrogram_ms += spectrogram_elapsed;
            if (!std::holds_alternative<ZxGpuRealArray>(spectrogram_result.values))
            {
                throw std::runtime_error("gpu spectrogram did not return real values");
            }

            auto [spectrogram_score, spectrogram_score_elapsed] = measure_gpu_ms([&]() {
                return normalize_nonnegative_zx_gpu(spectrogram_band_score_zx_gpu(
                    std::get<ZxGpuRealArray>(spectrogram_result.values),
                    spectrogram_result.frequencies,
                    spectrogram_result.times,
                    config.samples_per_frame,
                    config.filter_low,
                    config.filter_high,
                    config.fs));
            });
            spectrogram_ms += spectrogram_score_elapsed;
            store_row_real_zx_gpu(spectrogram_score, spectrogram_scores, frame);

            auto cwt_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::wavelets::cwt(frame_real_signal, "morlet2", widths_device);
            });
            auto cwt_values = std::move(cwt_measured.first);
            const float cwt_elapsed_frame = cwt_measured.second;
            cwt_ms += cwt_elapsed_frame;

            auto [wavelet_score, wavelet_reduce_elapsed] = measure_gpu_ms([&]() {
                return normalize_nonnegative_zx_gpu(cwt_max_score_zx_gpu(cwt_values));
            });
            cwt_ms += wavelet_reduce_elapsed;
            store_row_real_zx_gpu(wavelet_score, wavelet_scores, frame);

            if (frame == config.representative_frame_index)
            {
                artifacts.spectrogram_values = std::get<ZxGpuRealArray>(spectrogram_result.values);
                artifacts.spectrogram_freqs = spectrogram_result.frequencies;
                artifacts.spectrogram_times = spectrogram_result.times;
                artifacts.cwt_values = cwt_values;
            }
        }

        auto [fusion_done, fusion_elapsed] = measure_gpu_ms([&]() {
            fuse_feature_scores_zx_gpu(
                artifacts.correlate_scores,
                demod_scores,
                wavelet_scores,
                spectrogram_scores,
                bspline_weights,
                config.peak_order,
                artifacts.feature_scores,
                artifacts.peak_track);
            return 0;
        });
        (void)fusion_done;
        fusion_ms += fusion_elapsed;

        timings.push_back({"demod", 0.0, demod_ms});
        timings.push_back({"correlate", 0.0, correlate_ms});
        timings.push_back({"spectrogram", 0.0, spectrogram_ms});
        timings.push_back({"cwt", 0.0, cwt_ms});
        timings.push_back({"feature_fusion", 0.0, fusion_ms});

        auto [kalman_track, kalman_ms] = measure_gpu_ms([&]() {
            return kalman_track_from_peaks_zx_gpu(artifacts.peak_track);
        });
        artifacts.kalman_track = std::move(kalman_track);
        timings.push_back({"kalman", 0.0, kalman_ms});

        return std::make_pair(std::move(artifacts), std::move(timings));
    }

    HostGpuArtifacts materialize_gpu_artifacts(const GpuArtifacts &gpu)
    {
        HostGpuArtifacts host;
        host.filtered = gpu.filtered.get();
        host.correlate_scores = gpu.correlate_scores.get();
        host.spectrogram_values = gpu.spectrogram_values.get();
        host.spectrogram_freqs = gpu.spectrogram_freqs.get();
        host.spectrogram_times = gpu.spectrogram_times.get();
        host.cwt_values = gpu.cwt_values.get();
        host.feature_scores = gpu.feature_scores.get();
        host.peak_track = gpu.peak_track.get();
        host.kalman_track = gpu.kalman_track.get();
        return host;
    }

    RealSignal compute_truth_track(
        const ScenarioConfig &config,
        const ComplexSignal &target_template)
    {
        const ComplexSignal interferer_signal = build_interferer_signal(config);
        const ComplexArray target_only = simulate_frames(
            config,
            target_template,
            interferer_signal,
            false,
            false);
        const RealSignal widths = even_range(4.0f, 32.0f, 2.0f);
        const RealSignal bspline_weights = build_bspline_weights_cpu();
        const RealSignal taps = build_filter_taps_cpu(config);
        const ComplexArray filtered = filter_complex_frames_cpu(taps, target_only);

        RealSignal truth(static_cast<std::size_t>(config.num_frames), 0.0f);
        float demod_ms = 0.0;
        float correlate_ms = 0.0;
        float spectrogram_ms = 0.0;
        float cwt_ms = 0.0;
        float fusion_ms = 0.0;
        for (int frame = 0; frame < config.num_frames; ++frame)
        {
            const ComplexSignal frame_signal = extract_row_complex_signal(filtered, frame);
            const FrameCpuResult frame_result = process_frame_cpu(
                config,
                frame_signal,
                target_template,
                widths,
                bspline_weights,
                demod_ms,
                correlate_ms,
                spectrogram_ms,
                cwt_ms,
                fusion_ms);
            truth[static_cast<std::size_t>(frame)] = static_cast<float>(frame_result.peak_index);
        }
        return truth;
    }

    void write_generated_inputs(
        const ScenarioConfig &config,
        const ComplexSignal &target_template,
        const ComplexArray &rx_frames,
        const RealSignal &truth_track)
    {
        const fs::path input_dir = generated_root() / "input";
        fs::create_directories(input_dir);
        write_complex_csv(input_dir / "target_template.csv", target_template);
        write_complex_csv(input_dir / "rx_frames.csv", rx_frames.values);
        write_real_csv(input_dir / "truth_track.csv", truth_track);

        std::ostringstream scenario;
        scenario << "{\n";
        scenario << "  \"version\": \"V3.2\",\n";
        scenario << "  \"scale_level\": " << config.scale_level << ",\n";
        scenario << "  \"scale_value\": " << scale_value(config) << ",\n";
        scenario << "  \"fs\": " << config.fs << ",\n";
        scenario << "  \"num_frames\": " << config.num_frames << ",\n";
        scenario << "  \"samples_per_frame\": " << config.samples_per_frame << ",\n";
        scenario << "  \"template_length\": " << config.template_length << ",\n";
        scenario << "  \"target_start_sample_0\": " << config.target_start_sample_0 << ",\n";
        scenario << "  \"target_step_per_frame\": " << config.target_step_per_frame << ",\n";
        scenario << "  \"interferer_start_sample\": " << config.interferer_start_sample << ",\n";
        scenario << "  \"interferer_length\": " << config.interferer_length << ",\n";
        scenario << "  \"target_amplitude\": " << config.target_amplitude << ",\n";
        scenario << "  \"interferer_amplitude\": " << config.interferer_amplitude << ",\n";
        scenario << "  \"snr_db\": " << config.snr_db << ",\n";
        scenario << "  \"seed\": " << config.seed << ",\n";
        scenario << "  \"chirp_f0\": " << config.chirp_f0 << ",\n";
        scenario << "  \"chirp_f1\": " << config.chirp_f1 << ",\n";
        scenario << "  \"gausspulse_fc\": " << config.gausspulse_fc << ",\n";
        scenario << "  \"interferer_f0\": " << config.interferer_f0 << ",\n";
        scenario << "  \"interferer_f1\": " << config.interferer_f1 << ",\n";
        scenario << "  \"representative_frame_index\": " << config.representative_frame_index << ",\n";
        scenario << "  \"filter_numtaps\": " << config.filter_numtaps << ",\n";
        scenario << "  \"filter_low\": " << config.filter_low << ",\n";
        scenario << "  \"filter_high\": " << config.filter_high << ",\n";
        scenario << "  \"spectrogram_nperseg\": " << config.spectrogram_nperseg << ",\n";
        scenario << "  \"spectrogram_noverlap\": " << config.spectrogram_noverlap << ",\n";
        scenario << "  \"spectrogram_nfft\": " << config.spectrogram_nfft << ",\n";
        scenario << "  \"cwt_widths\": " << shape_json(Shape{4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32}) << ",\n";
        scenario << "  \"peak_order\": " << config.peak_order << ",\n";
        scenario << "  \"kalman_rmse_tolerance\": " << config.kalman_rmse_tolerance << ",\n";
        scenario << "  \"rx_shape\": " << shape_json(rx_frames.shape) << "\n";
        scenario << "}\n";
        write_text_file(input_dir / "scenario.json", scenario.str());
    }

    void write_output_samples(
        const CpuArtifacts &cpu,
        const HostGpuArtifacts &gpu)
    {
        const fs::path output_dir = generated_root() / "output_samples";
        fs::create_directories(output_dir);

        write_complex_csv(output_dir / "filtered__cpu__values.csv", cpu.filtered.values);
        write_complex_csv(output_dir / "filtered__gpu__values.csv", gpu.filtered.values);
        write_real_csv(output_dir / "correlate__cpu__values.csv", cpu.correlate_scores.values);
        write_real_csv(output_dir / "correlate__gpu__values.csv", gpu.correlate_scores.values);
        write_real_csv(output_dir / "spectrogram__cpu__values.csv", cpu.spectrogram_values.values);
        write_real_csv(output_dir / "spectrogram__gpu__values.csv", gpu.spectrogram_values.values);
        write_real_csv(output_dir / "spectrogram_freqs__cpu__values.csv", cpu.spectrogram_freqs);
        write_real_csv(output_dir / "spectrogram_freqs__gpu__values.csv", gpu.spectrogram_freqs);
        write_real_csv(output_dir / "spectrogram_times__cpu__values.csv", cpu.spectrogram_times);
        write_real_csv(output_dir / "spectrogram_times__gpu__values.csv", gpu.spectrogram_times);
        write_complex_csv(output_dir / "cwt__cpu__values.csv", cpu.cwt_values.values);
        write_complex_csv(output_dir / "cwt__gpu__values.csv", gpu.cwt_values.values);
        write_real_csv(output_dir / "feature_score__cpu__values.csv", cpu.feature_scores.values);
        write_real_csv(output_dir / "feature_score__gpu__values.csv", gpu.feature_scores.values);
        write_real_csv(output_dir / "peak_track__cpu__values.csv", cpu.peak_track);
        write_real_csv(output_dir / "peak_track__gpu__values.csv", gpu.peak_track);
        write_real_csv(output_dir / "kalman_track__cpu__values.csv", cpu.kalman_track);
        write_real_csv(output_dir / "kalman_track__gpu__values.csv", gpu.kalman_track);
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

    bool tracks_match(const RealSignal &lhs, const RealSignal &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            return false;
        }
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            if (std::fabs(lhs[index] - rhs[index]) > 0.5f)
            {
                return false;
            }
        }
        return true;
    }

    std::string build_summary_markdown(
        const ScenarioConfig &config,
        const CpuArtifacts &cpu,
        const HostGpuArtifacts &gpu,
        const std::vector<StageTiming> &timings,
        const ErrorMetrics &filtered_error,
        const ErrorMetrics &correlate_error,
        const ErrorMetrics &spectrogram_error,
        const ErrorMetrics &cwt_error,
        const ErrorMetrics &feature_score_error,
        const ErrorMetrics &kalman_error,
        float cpu_total_ms,
        float gpu_total_ms,
        bool cpu_gpu_track_match,
        bool gpu_matches_truth,
        const ValidationResult &validation,
        const ResourceSnapshot &resource_before,
        const ResourceSnapshot &resource_after,
        const std::vector<IterationSummary> &iterations)
    {
        std::ostringstream stream;
        stream << "# Task 2 Feature Localization Demo\n\n";
        stream << "## Scenario\n\n";
        stream << "- scale_level: `L" << config.scale_level << "`\n";
        stream << "- scale_value: `" << scale_value(config) << "`\n";
        stream << "- fs: `" << config.fs << "`\n";
        stream << "- num_frames: `" << config.num_frames << "`\n";
        stream << "- samples_per_frame: `" << config.samples_per_frame << "`\n";
        stream << "- template_length: `" << config.template_length << "`\n";
        stream << "- target_start_sample_0: `" << config.target_start_sample_0 << "`\n";
        stream << "- target_step_per_frame: `" << config.target_step_per_frame << "`\n";
        stream << "- interferer_start_sample: `" << config.interferer_start_sample << "`\n";
        stream << "- snr_db: `" << config.snr_db << "`\n\n";
        stream << "## Consistency\n\n";
        stream << "- cpu_gpu_track_match: `" << (cpu_gpu_track_match ? "true" : "false") << "`\n";
        stream << "- gpu_matches_truth_within_tolerance: `" << (gpu_matches_truth ? "true" : "false") << "`\n";
        stream << "- gpu_kalman_rmse: `" << std::fixed << std::setprecision(4) << kalman_error.rmse << "` samples\n\n";
        stream << "## Error\n\n";
        stream << std::scientific << std::setprecision(6);
        stream << "| field | mixed_error | max_abs | max_rel | rmse |\n";
        stream << "| --- | ---: | ---: | ---: | ---: |\n";
        stream << "| filtered | " << filtered_error.mixed_error << " | " << filtered_error.max_abs << " | "
               << filtered_error.max_rel << " | " << filtered_error.rmse << " |\n";
        stream << "| correlate | " << correlate_error.mixed_error << " | " << correlate_error.max_abs << " | "
               << correlate_error.max_rel << " | " << correlate_error.rmse << " |\n";
        stream << "| spectrogram | " << spectrogram_error.mixed_error << " | " << spectrogram_error.max_abs << " | "
               << spectrogram_error.max_rel << " | " << spectrogram_error.rmse << " |\n";
        stream << "| cwt | " << cwt_error.mixed_error << " | " << cwt_error.max_abs << " | "
               << cwt_error.max_rel << " | " << cwt_error.rmse << " |\n";
        stream << "| feature_score | " << feature_score_error.mixed_error << " | " << feature_score_error.max_abs << " | "
               << feature_score_error.max_rel << " | " << feature_score_error.rmse << " |\n";
        stream << "| kalman_track | " << kalman_error.mixed_error << " | " << kalman_error.max_abs << " | "
               << kalman_error.max_rel << " | " << kalman_error.rmse << " |\n\n";
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
        stream << "- gpu_free_delta_mib: `" << std::setprecision(3)
               << (resource_after.gpu_free_mib - resource_before.gpu_free_mib) << "`\n";
        stream << "- rss_current_delta_mib: `"
               << (resource_after.rss_current_mib - resource_before.rss_current_mib) << "`\n\n";
        stream << "## Artifacts\n\n";
        stream << "- inputs: `data/generated/demo/task2_features/input/`\n";
        stream << "- samples: `data/generated/demo/task2_features/output_samples/`\n";
        stream << "- metrics: `data/reports/demo/task2_features/latest_metrics.json`\n";
        stream << "- timings: `data/reports/demo/task2_features/latest_stage_timings.csv`\n";
        stream << "- figures: run `python3 demo/task2_features/visualize_task2.py`\n";
        return stream.str();
    }

    std::string build_metrics_json(
        const ScenarioConfig &config,
        const CpuArtifacts &cpu,
        const HostGpuArtifacts &gpu,
        const std::vector<StageTiming> &timings,
        const ErrorMetrics &filtered_error,
        const ErrorMetrics &correlate_error,
        const ErrorMetrics &spectrogram_error,
        const ErrorMetrics &cwt_error,
        const ErrorMetrics &feature_score_error,
        const ErrorMetrics &kalman_error,
        float cpu_total_ms,
        float gpu_total_ms,
        bool cpu_gpu_track_match,
        bool gpu_matches_truth,
        const ValidationResult &validation,
        const ResourceSnapshot &resource_before,
        const ResourceSnapshot &resource_after,
        const std::vector<IterationSummary> &iterations)
    {
        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"version\": \"V3.2\",\n";
        stream << "  \"scenario\": {\n";
        stream << "    \"scale_level\": " << config.scale_level << ",\n";
        stream << "    \"scale_value\": " << scale_value(config) << ",\n";
        stream << "    \"fs\": " << config.fs << ",\n";
        stream << "    \"num_frames\": " << config.num_frames << ",\n";
        stream << "    \"samples_per_frame\": " << config.samples_per_frame << ",\n";
        stream << "    \"rx_shape\": " << shape_json(cpu.rx_frames.shape) << ",\n";
        stream << "    \"template_length\": " << config.template_length << ",\n";
        stream << "    \"target_start_sample_0\": " << config.target_start_sample_0 << ",\n";
        stream << "    \"target_step_per_frame\": " << config.target_step_per_frame << ",\n";
        stream << "    \"interferer_start_sample\": " << config.interferer_start_sample << ",\n";
        stream << "    \"interferer_length\": " << config.interferer_length << ",\n";
        stream << "    \"target_amplitude\": " << config.target_amplitude << ",\n";
        stream << "    \"interferer_amplitude\": " << config.interferer_amplitude << ",\n";
        stream << "    \"snr_db\": " << config.snr_db << ",\n";
        stream << "    \"seed\": " << config.seed << ",\n";
        stream << "    \"representative_frame_index\": " << config.representative_frame_index << ",\n";
        stream << "    \"filter_numtaps\": " << config.filter_numtaps << ",\n";
        stream << "    \"filter_band_hz\": [" << config.filter_low << ", " << config.filter_high << "],\n";
        stream << "    \"spectrogram_nperseg\": " << config.spectrogram_nperseg << ",\n";
        stream << "    \"spectrogram_noverlap\": " << config.spectrogram_noverlap << ",\n";
        stream << "    \"spectrogram_nfft\": " << config.spectrogram_nfft << ",\n";
        stream << "    \"peak_order\": " << config.peak_order << ",\n";
        stream << "    \"kalman_rmse_tolerance\": " << config.kalman_rmse_tolerance << "\n";
        stream << "  },\n";
        stream << "  \"shapes\": {\n";
        stream << "    \"rx_frames\": " << shape_json(cpu.rx_frames.shape) << ",\n";
        stream << "    \"filtered\": " << shape_json(cpu.filtered.shape) << ",\n";
        stream << "    \"correlate\": " << shape_json(cpu.correlate_scores.shape) << ",\n";
        stream << "    \"spectrogram\": " << shape_json(cpu.spectrogram_values.shape) << ",\n";
        stream << "    \"cwt\": " << shape_json(cpu.cwt_values.shape) << ",\n";
        stream << "    \"feature_score\": " << shape_json(cpu.feature_scores.shape) << ",\n";
        stream << "    \"peak_track\": " << shape_json(Shape{cpu.peak_track.size()}) << ",\n";
        stream << "    \"kalman_track\": " << shape_json(Shape{cpu.kalman_track.size()}) << "\n";
        stream << "  },\n";
        auto write_error = [&](const char *name, const ErrorMetrics &metrics, bool trailing_comma) {
            stream << "  \"" << name << "\": {\n";
            stream << "    \"mixed_error\": " << metrics.mixed_error << ",\n";
            stream << "    \"max_abs\": " << metrics.max_abs << ",\n";
            stream << "    \"max_rel\": " << metrics.max_rel << ",\n";
            stream << "    \"rmse\": " << metrics.rmse << "\n";
            stream << "  }" << (trailing_comma ? ",\n" : "\n");
        };
        write_error("filtered_error", filtered_error, true);
        write_error("correlate_error", correlate_error, true);
        write_error("spectrogram_error", spectrogram_error, true);
        write_error("cwt_error", cwt_error, true);
        write_error("feature_score_error", feature_score_error, true);
        write_error("kalman_track_error", kalman_error, true);
        stream << "  \"timings\": {\n";
        for (std::size_t index = 0; index < timings.size(); ++index)
        {
            const StageTiming &timing = timings[index];
            stream << "    \"" << json_escape(timing.name) << "\": {\"cpu_ms\": " << timing.cpu_ms
                   << ", \"gpu_ms\": " << timing.gpu_ms << "},\n";
        }
        stream << "    \"total\": {\"cpu_ms\": " << cpu_total_ms << ", \"gpu_ms\": " << gpu_total_ms << "}\n";
        stream << "  },\n";
        auto write_signal = [&](const char *name, const RealSignal &values, bool trailing_comma) {
            stream << "  \"" << name << "\": [";
            for (std::size_t index = 0; index < values.size(); ++index)
            {
                if (index != 0)
                {
                    stream << ", ";
                }
                stream << values[index];
            }
            stream << "]" << (trailing_comma ? ",\n" : "\n");
        };
        write_signal("truth_track", cpu.truth_track, true);
        write_signal("cpu_peak_track", cpu.peak_track, true);
        write_signal("gpu_peak_track", gpu.peak_track, true);
        write_signal("cpu_kalman_track", cpu.kalman_track, true);
        write_signal("gpu_kalman_track", gpu.kalman_track, true);
        stream << "  \"consistency\": {\n";
        stream << "    \"cpu_gpu_track_match\": " << bool_json(cpu_gpu_track_match) << ",\n";
        stream << "    \"gpu_matches_truth_within_tolerance\": " << bool_json(gpu_matches_truth) << "\n";
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
        const ComplexSignal target_template = build_target_template(config);
        const ComplexSignal interferer_signal = build_interferer_signal(config);
        const ComplexArray rx_frames = simulate_frames(
            config,
            target_template,
            interferer_signal,
            true,
            true);
        const RealSignal truth_track = compute_truth_track(config, target_template);

        const auto [cpu, cpu_timings] = run_cpu_pipeline(config, target_template, rx_frames, truth_track);
        const auto [gpu_device, gpu_timings] = run_gpu_pipeline(config, target_template, rx_frames);
        const HostGpuArtifacts gpu = materialize_gpu_artifacts(gpu_device);

        if (cpu_timings.size() != gpu_timings.size())
        {
            throw std::runtime_error("cpu/gpu timing stage count mismatch");
        }
        std::vector<StageTiming> stage_timings = cpu_timings;
        for (std::size_t index = 0; index < stage_timings.size(); ++index)
        {
            stage_timings[index].gpu_ms = gpu_timings[index].gpu_ms;
        }

        float cpu_total_ms = 0.0;
        float gpu_total_ms = 0.0;
        for (const StageTiming &timing : stage_timings)
        {
            cpu_total_ms += timing.cpu_ms;
            gpu_total_ms += timing.gpu_ms;
        }

        const ErrorMetrics filtered_error = compute_real_array_error(cpu.filtered, gpu.filtered);
        const ErrorMetrics correlate_error = compute_real_array_error(cpu.correlate_scores, gpu.correlate_scores);
        const ErrorMetrics spectrogram_error =
            compute_real_array_error(cpu.spectrogram_values, gpu.spectrogram_values, kSpectralMixedScale);
        const ErrorMetrics cwt_error = compute_real_array_error(cpu.cwt_values, gpu.cwt_values, kSpectralMixedScale);
        const ErrorMetrics feature_score_error = compute_real_array_error(cpu.feature_scores, gpu.feature_scores);
        const ErrorMetrics kalman_error = compute_real_error(cpu.truth_track, gpu.kalman_track);

        const bool cpu_gpu_track_match = tracks_match(cpu.peak_track, gpu.peak_track);
        const bool gpu_matches_truth = kalman_error.rmse <= config.kalman_rmse_tolerance;

        DemoRunResult result;
        result.cpu = std::move(cpu);
        result.gpu = std::move(gpu);
        result.stage_timings = std::move(stage_timings);
        result.filtered_error = filtered_error;
        result.correlate_error = correlate_error;
        result.spectrogram_error = spectrogram_error;
        result.cwt_error = cwt_error;
        result.feature_score_error = feature_score_error;
        result.kalman_error = kalman_error;
        result.cpu_total_ms = cpu_total_ms;
        result.gpu_total_ms = gpu_total_ms;
        result.cpu_gpu_track_match = cpu_gpu_track_match;
        result.gpu_matches_truth = gpu_matches_truth;
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
            ValidationResult current_validation =
                validate_single_run(
                    current,
                    thresholds,
                    invalid_checks_passed,
                    config.kalman_rmse_tolerance,
                    options.skip_timing_validation);
            cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
            IterationSummary summary;
            summary.index = iteration + 1;
            summary.pass = current_validation.pass;
            summary.business_numeric_pass = validation_pass_excluding_timing(current_validation);
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

        write_generated_inputs(config, final_run.cpu.target_template, final_run.cpu.rx_frames, final_run.cpu.truth_track);
        write_output_samples(final_run.cpu, final_run.gpu);
        write_stage_timings_csv(final_run.stage_timings, final_run.cpu_total_ms, final_run.gpu_total_ms);
        write_text_file(
            report_root() / "latest_summary.md",
            build_summary_markdown(
                config,
                final_run.cpu,
                final_run.gpu,
                final_run.stage_timings,
                final_run.filtered_error,
                final_run.correlate_error,
                final_run.spectrogram_error,
                final_run.cwt_error,
                final_run.feature_score_error,
                final_run.kalman_error,
                final_run.cpu_total_ms,
                final_run.gpu_total_ms,
                final_run.cpu_gpu_track_match,
                final_run.gpu_matches_truth,
                final_validation,
                resource_before,
                resource_after,
                iterations));
        write_text_file(
            report_root() / "latest_metrics.json",
            build_metrics_json(
                config,
                final_run.cpu,
                final_run.gpu,
                final_run.stage_timings,
                final_run.filtered_error,
                final_run.correlate_error,
                final_run.spectrogram_error,
                final_run.cwt_error,
                final_run.feature_score_error,
                final_run.kalman_error,
                final_run.cpu_total_ms,
                final_run.gpu_total_ms,
                final_run.cpu_gpu_track_match,
                final_run.gpu_matches_truth,
                final_validation,
                resource_before,
                resource_after,
                iterations));

        cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");

        if (!final_validation.pass)
        {
            for (const ValidationCheck &check : final_validation.checks)
            {
                if (!check.pass)
                {
                    std::cerr << "[task2_features] validation failed: " << check.name
                              << " value=" << check.value << " limit=" << check.limit
                              << " detail=" << check.detail << '\n';
                }
            }
            return 1;
        }

        std::cout << "[task2_features] PASS"
                  << " repeat=" << options.repeat
                  << " scale_level=L" << config.scale_level
                  << " invalid_input_checks=" << bool_json(options.invalid_input_checks)
                  << " skip_timing_validation=" << bool_json(options.skip_timing_validation) << '\n';
        std::cout << "reports       : "
                  << (report_root() / "latest_summary.md").lexically_relative(repo_root()).string() << '\n';
        std::cout << "visualization : python3 demo/task2_features/visualize_task2.py\n";
        return 0;
    }
}

int main(int argc, char **argv)
{
    try
    {
        const auto options = cusignal_demo::task2_features::parse_options(argc, argv);
        return cusignal_demo::task2_features::run(options);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[task2_features] ERROR: " << error.what() << '\n';
        return 1;
    }
}
