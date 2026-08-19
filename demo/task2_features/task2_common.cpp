#include "task2_common.hpp"

#include "../../src/common/zx_tile_policy.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <initializer_list>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>

#include <sys/resource.h>
#include <unistd.h>

namespace cusignal_demo::task2_features
{
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
            config.num_frames = 128;
            config.samples_per_frame = 3072;
            config.template_length = 1024;
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

    // Formal-PPT scale protocol: retain the L6 feature-extraction/tracking
    // path (including the B=8-friendly frame multiples) and vary only frame
    // count.  Keeping 3072 samples/frame preserves the same template and
    // spectrogram configuration at every level.
    ScenarioConfig unified_scenario_for_scale_level(int scale_level)
    {
        if (scale_level < 1 || scale_level > 6)
        {
            throw std::invalid_argument("scale_level must be in [1, 6]");
        }
        ScenarioConfig config = scenario_for_scale_level(6);
        config.scale_level = scale_level;
        config.unified_scale_protocol = true;
        switch (scale_level)
        {
        case 1: config.num_frames = 8; break;
        case 2: config.num_frames = 16; break;
        case 3: config.num_frames = 32; break;
        case 4: config.num_frames = 64; break;
        case 5: config.num_frames = 96; break;
        case 6: break;
        default: break;
        }
        config.target_start_sample_0 = std::max(1, config.samples_per_frame * 55 / 256);
        config.interferer_start_sample = config.samples_per_frame * 5 / 8;
        config.interferer_length = config.template_length;
        config.representative_frame_index = config.num_frames / 2;
        return config;
    }

    void apply_scenario_overrides(ScenarioConfig &config, const DemoOptions &options)
    {
        if (options.num_frames)
        {
            config.num_frames = *options.num_frames;
            config.representative_frame_index = config.num_frames / 2;
        }
        if (options.samples_per_frame)
        {
            config.samples_per_frame = *options.samples_per_frame;
            config.target_start_sample_0 = std::max(1, config.samples_per_frame * 55 / 256);
            config.interferer_start_sample = config.samples_per_frame * 5 / 8;
        }
        if (options.template_length)
        {
            config.template_length = *options.template_length;
            config.interferer_length = config.template_length;
        }
        if (options.filter_numtaps) config.filter_numtaps = *options.filter_numtaps;
        if (options.spectrogram_nperseg) config.spectrogram_nperseg = *options.spectrogram_nperseg;
        if (options.spectrogram_noverlap) config.spectrogram_noverlap = *options.spectrogram_noverlap;
        if (options.spectrogram_nfft) config.spectrogram_nfft = *options.spectrogram_nfft;
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
    HostGpuArtifacts copy_host_artifacts(const CpuArtifacts &cpu)
    {
        HostGpuArtifacts host;
        host.filtered = cpu.filtered;
        host.demod_scores = cpu.demod_scores;
        host.correlate_scores = cpu.correlate_scores;
        host.spectrogram_values = cpu.spectrogram_values;
        host.spectrogram_freqs = cpu.spectrogram_freqs;
        host.spectrogram_times = cpu.spectrogram_times;
        host.cwt_values = cpu.cwt_values;
        host.feature_scores = cpu.feature_scores;
        host.peak_track = cpu.peak_track;
        host.measurement_values = cpu.measurement_values;
        host.kalman_track = cpu.kalman_track;
        return host;
    }

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
        return repo_root() / "data" / ".reports_staging" / "demo" / "task2_features";
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
            if (arg == "--warmup")
            {
                if (index + 1 >= argc)
                {
                    throw std::invalid_argument("--warmup requires a non-negative integer");
                }
                options.warmup = std::atoi(argv[++index]);
                if (options.warmup < 0)
                {
                    throw std::invalid_argument("--warmup must be >= 0");
                }
            }
            else if (arg == "--repeat")
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
            else if (arg == "--num-frames" || arg == "--samples-per-frame" ||
                     arg == "--template-length" || arg == "--filter-numtaps" ||
                     arg == "--spectrogram-nperseg" || arg == "--spectrogram-noverlap" ||
                     arg == "--spectrogram-nfft")
            {
                if (index + 1 >= argc)
                {
                    throw std::invalid_argument(arg + " requires a positive integer");
                }
                const int value = std::atoi(argv[++index]);
                if (value < 0 || (arg != "--spectrogram-noverlap" && value == 0))
                {
                    throw std::invalid_argument(arg + " must be a non-negative integer; zero is allowed only for --spectrogram-noverlap");
                }
                if (arg == "--num-frames") options.num_frames = value;
                else if (arg == "--samples-per-frame") options.samples_per_frame = value;
                else if (arg == "--template-length") options.template_length = value;
                else if (arg == "--filter-numtaps") options.filter_numtaps = value;
                else if (arg == "--spectrogram-nperseg") options.spectrogram_nperseg = value;
                else if (arg == "--spectrogram-noverlap") options.spectrogram_noverlap = value;
                else options.spectrogram_nfft = value;
            }
            else if (arg == "--invalid-input-checks")
            {
                options.invalid_input_checks = true;
            }
            else if (arg == "--unified-scale-protocol")
            {
                options.unified_scale_protocol = true;
            }
            else if (arg == "--skip-timing-validation")
            {
                options.skip_timing_validation = true;
            }
            else if (arg == "--help" || arg == "-h")
            {
                std::cout << "usage: task2_features_demo [--warmup N] [--repeat N] [--scale-level 1..6] [--unified-scale-protocol] [--invalid-input-checks] "
                             "[--skip-timing-validation] [--num-frames N] [--samples-per-frame N] "
                             "[--template-length N] [--filter-numtaps N] [--spectrogram-nperseg N] "
                             "[--spectrogram-noverlap N] [--spectrogram-nfft N]\n";
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

    std::string resource_usage_json(
        const ResourceSnapshot &before,
        const ResourceSnapshot &after,
        int indent = 2)
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
                   << ", \"gpu_kernel_total_ms\": " << iteration.gpu_kernel_total_ms
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

    ErrorMetrics compute_real_error(const RealSignal &lhs, const RealSignal &rhs, float scale_factor)
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

    ErrorMetrics compute_complex_error(const ComplexSignal &lhs, const ComplexSignal &rhs, float scale_factor)
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
            metrics.real_max_abs = std::isfinite(metrics.real_max_abs)
                ? std::max(metrics.real_max_abs, std::fabs(lhs[index].real() - rhs[index].real()))
                : std::fabs(lhs[index].real() - rhs[index].real());
            metrics.imag_max_abs = std::isfinite(metrics.imag_max_abs)
                ? std::max(metrics.imag_max_abs, std::fabs(lhs[index].imag() - rhs[index].imag()))
                : std::fabs(lhs[index].imag() - rhs[index].imag());
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
        const double compute_budget = std::min<double>(scaled_limit, thresholds.gpu_total_hard_limit_ms);
        double input_construction_ms = 0.0;
        for (const StageTiming &timing : run.stage_timings)
        {
            if (timing.name == "input_construction")
            {
                input_construction_ms = timing.gpu_ms;
                break;
            }
        }
        // The reported GPU total is complete E2E and includes device input
        // construction. Keep the compute budget for the device chain, then
        // add the measured input-construction stage explicitly.
        const double gpu_limit = input_construction_ms + compute_budget;
        add_check(
            validation,
            "gpu_total_ms",
            skip_timing_validation || run.gpu_total_ms <= gpu_limit,
            run.gpu_total_ms,
            gpu_limit,
            skip_timing_validation ? "GPU timing validation skipped for sanitizer run"
                                   : "GPU E2E must stay within measured input construction plus compute budget");
        add_check(
            validation,
            "input_template_mixed_error",
            run.input_template_error.mixed_error <= thresholds.input_mixed,
            run.input_template_error.mixed_error,
            thresholds.input_mixed,
            "CPU/GPU-native target template input mixed error");
        add_check(
            validation,
            "input_rx_mixed_error",
            run.input_rx_error.mixed_error <= thresholds.input_mixed,
            run.input_rx_error.mixed_error,
            thresholds.input_mixed,
            "CPU/GPU-native received frames input mixed error");
        add_check(
            validation,
            "filtered_mixed_error",
            run.filtered_error.mixed_error <= thresholds.filtered_mixed,
            run.filtered_error.mixed_error,
            thresholds.filtered_mixed,
            "filtered CPU/GPU mixed error");
        add_check(
            validation,
            "demod_mixed_error",
            run.demod_error.mixed_error <= thresholds.demod_score_mixed,
            run.demod_error.mixed_error,
            thresholds.demod_score_mixed,
            "demod score CPU/GPU mixed error");
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
            "measurement_mixed_error",
            run.measurement_error.mixed_error <= thresholds.feature_score_mixed,
            run.measurement_error.mixed_error,
            thresholds.feature_score_mixed,
            "measurement conversion CPU/GPU mixed error");
        add_check(
            validation,
            "kalman_cpu_gpu_rmse",
            run.kalman_cpu_gpu_error.rmse <= kalman_rmse_tolerance,
            run.kalman_cpu_gpu_error.rmse,
            kalman_rmse_tolerance,
            "Kalman CPU/GPU track RMSE");
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
    float gpu_kernel_total_ms(const std::vector<StageTiming> &timings)
    {
        float total_ms = 0.0f;
        for (const StageTiming &timing : timings)
        {
            if (std::isfinite(timing.gpu_kernel_ms))
                total_ms += timing.gpu_kernel_ms;
        }
        return total_ms;
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
        scenario << "  \"version\": \"V3.3\",\n";
        scenario << "  \"scale_level\": " << config.scale_level << ",\n";
        scenario << "  \"unified_scale_protocol\": " << bool_json(config.unified_scale_protocol) << ",\n";
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
        write_real_csv(output_dir / "demod__cpu__values.csv", cpu.demod_scores.values);
        write_real_csv(output_dir / "demod__gpu__values.csv", gpu.demod_scores.values);
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
        write_real_csv(output_dir / "measurement__cpu__values.csv", cpu.measurement_values);
        write_real_csv(output_dir / "measurement__gpu__values.csv", gpu.measurement_values);
        write_real_csv(output_dir / "kalman_track__cpu__values.csv", cpu.kalman_track);
        write_real_csv(output_dir / "kalman_track__gpu__values.csv", gpu.kalman_track);
    }

    void write_stage_timings_csv(
        const std::vector<StageTiming> &timings,
        float cpu_total_ms,
        float gpu_total_ms,
        float gpu_kernel_total_ms_value)
    {
        const fs::path path = report_root() / "latest_stage_timings.csv";
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write CSV file: " + path.string());
        }
        output << "stage,cpu_ms,gpu_ms,gpu_kernel_ms\n";
        output << std::fixed << std::setprecision(6);
        for (const StageTiming &timing : timings)
        {
            output << timing.name << ',' << timing.cpu_ms << ',' << timing.gpu_ms << ',';
            if (std::isfinite(timing.gpu_kernel_ms))
                output << timing.gpu_kernel_ms;
            output << '\n';
        }
        output << "total," << cpu_total_ms << ',' << gpu_total_ms << ','
               << gpu_kernel_total_ms_value << '\n';
    }

    void write_task_csv_reports(
        const ScenarioConfig &config,
        const DemoRunResult &run,
        const ValidationResult &validation,
        int warmup,
        int repeat)
    {
        const auto timing_for = [&](const std::string &name) -> const StageTiming & {
            const auto iter = std::find_if(run.stage_timings.begin(), run.stage_timings.end(),
                [&](const StageTiming &timing) { return timing.name == name; });
            if (iter == run.stage_timings.end())
                throw std::runtime_error("missing stage timing: " + name);
            return *iter;
        };
        const auto shape_text = [](const Shape &shape) {
            std::ostringstream stream;
            for (std::size_t index = 0; index < shape.size(); ++index)
            {
                if (index != 0) stream << 'x';
                stream << shape[index];
            }
            return stream.str();
        };
        const auto finite_or_blank = [](std::ostream &output, float value) {
            if (std::isfinite(value)) output << value;
        };
        const auto aggregate_error = [](std::initializer_list<const ErrorMetrics *> errors) {
            ErrorMetrics result;
            for (const ErrorMetrics *error : errors)
            {
                result.max_abs = std::max(result.max_abs, error->max_abs);
                result.max_rel = std::max(result.max_rel, error->max_rel);
                result.rmse = std::max(result.rmse, error->rmse);
                result.mixed_error = std::max(result.mixed_error, error->mixed_error);
            }
            return result;
        };
        const ErrorMetrics input_error = aggregate_error({
            &run.input_template_error, &run.input_rx_error});
        const ErrorMetrics operator_error = aggregate_error({
            &run.filtered_error, &run.demod_error, &run.correlate_error,
            &run.spectrogram_error, &run.cwt_error, &run.feature_score_error,
            &run.measurement_error, &run.kalman_cpu_gpu_error});
        const ErrorMetrics e2e_error = aggregate_error({
            &run.filtered_e2e_error, &run.demod_e2e_error, &run.correlate_e2e_error,
            &run.spectrogram_e2e_error, &run.cwt_e2e_error, &run.feature_score_e2e_error,
            &run.measurement_e2e_error, &run.kalman_e2e_error});
        const StageTiming &input_timing = timing_for("input_construction");
        const auto &task_tuning = cusignal::zx_tile::task_policy_trace_snapshot();
        const auto csv_field = [](const std::string &value) {
            std::string escaped = value;
            std::size_t position = 0;
            while ((position = escaped.find('"', position)) != std::string::npos)
            {
                escaped.insert(position, 1, '"');
                position += 2;
            }
            return std::string("\"") + escaped + "\"";
        };

        fs::create_directories(report_root() / "operators");
        fs::create_directories(report_root() / "stages");
        std::ofstream summary(report_root() / "latest_summary.csv");
        if (!summary) throw std::runtime_error("failed to write task2 summary CSV");
        summary << "task,scale,seed,warmup,repeat,input_elements,cpu_input_ms,gpu_input_ms,task_input_h2d_ms,validation_input_d2h_ms,"
                   "cpu_total_ms,gpu_e2e_ms,gpu_kernel_ms,e2e_speedup,kernel_speedup,"
                   "input_max_abs,input_max_rel,input_rmse,input_mixed_error,"
                   "operator_max_abs,operator_max_rel,operator_rmse,operator_mixed_error,"
                   "e2e_max_abs,e2e_max_rel,e2e_rmse,e2e_mixed_error,validation_pass,"
                   "task_tuning_registry_version,task_tuning_key,task_tuning_candidate,"
                   "task_tuning_source,task_tuning_reason,task_tuning_threads,task_tuning_route,"
                   "task_tuning_workspace_bytes,task_tuning_workspace_peak_bytes,task_tuning_device_id,"
                   "task_tuning_device_name,task_tuning_runtime_version,task_tuning_compute_major,"
                   "task_tuning_compute_minor,task_tuning_total_global_mem,task_tuning_device_target\n";
        summary << std::fixed << std::setprecision(9)
                << "task2_features,L" << config.scale_level << ',' << config.seed << ',' << warmup << ',' << repeat << ','
                << (static_cast<long long>(config.num_frames) * config.samples_per_frame) << ','
                << input_timing.cpu_ms << ',' << input_timing.gpu_ms << ",0," << run.validation_input_d2h_ms
                << ',' << run.cpu_total_ms << ',' << run.gpu_total_ms << ',' << run.gpu_kernel_total_ms << ','
                << (run.gpu_total_ms > 0.0f ? run.cpu_total_ms / run.gpu_total_ms : 0.0f) << ','
                << (run.gpu_kernel_total_ms > 0.0f
                        ? run.cpu_total_ms / run.gpu_kernel_total_ms : 0.0f)
                << ',' << input_error.max_abs << ',' << input_error.max_rel << ',' << input_error.rmse << ','
                << input_error.mixed_error << ',' << operator_error.max_abs << ',' << operator_error.max_rel << ','
                << operator_error.rmse << ',' << operator_error.mixed_error << ',' << e2e_error.max_abs << ','
                << e2e_error.max_rel << ',' << e2e_error.rmse << ',' << e2e_error.mixed_error << ','
                << (validation.pass ? "PASS" : "ERROR") << ','
                << cusignal::zx_tile::kRegistryVersion << ','
                << csv_field(task_tuning.key) << ',' << csv_field(task_tuning.candidate) << ','
                << csv_field(task_tuning.source) << ',' << csv_field(task_tuning.reason) << ','
                << task_tuning.config.threads << ',' << task_tuning.config.route << ','
                << task_tuning.config.workspace_bytes << ',' << task_tuning.config.workspace_peak_bytes << ','
                << task_tuning.device.id << ',' << csv_field(task_tuning.device.name) << ','
                << task_tuning.device.runtime_version << ',' << task_tuning.device.compute_major << ','
                << task_tuning.device.compute_minor << ',' << task_tuning.device.total_global_mem << ','
                << csv_field(task_tuning.device.target) << '\n';

        std::ofstream operators(report_root() / "latest_operators.csv");
        if (!operators) throw std::runtime_error("failed to write task2 operator CSV");
        operators << "task,scale,operator,source_step,mapping_mode,input_shape,output_shape,"
                      "cpu_ms,gpu_e2e_ms,gpu_kernel_ms,e2e_speedup,kernel_speedup,"
                      "operator_max_abs,operator_max_rel,operator_rmse,operator_mixed_error,"
                      "e2e_max_abs,e2e_max_rel,e2e_rmse,e2e_mixed_error,status\n";
        operators << std::fixed << std::setprecision(9);
        const auto operator_timing_for = [&](const std::string &name) -> const StageTiming & {
            const auto iter = std::find_if(run.operator_timings.begin(), run.operator_timings.end(),
                [&](const StageTiming &timing) { return timing.name == name; });
            if (iter == run.operator_timings.end())
                throw std::runtime_error("missing public operator timing: " + name);
            return *iter;
        };
        const auto write_row = [&](const char *name, const char *source_step, const char *mapping_mode,
                                   const std::string &input_shape, const std::string &output_shape,
                                   const ErrorMetrics &operator_metrics, const ErrorMetrics &e2e_metrics) {
            const StageTiming &timing = operator_timing_for(name);
            operators << "task2_features,L" << config.scale_level << ',' << name << ','
                      << source_step << ',' << mapping_mode << ',' << input_shape << ',' << output_shape << ','
                      << timing.cpu_ms << ','
                      << timing.gpu_ms << ',';
            finite_or_blank(operators, timing.gpu_kernel_ms);
            operators << ',' << (timing.gpu_ms > 0.0f ? timing.cpu_ms / timing.gpu_ms : 0.0f) << ',';
            if (std::isfinite(timing.gpu_kernel_ms) && timing.gpu_kernel_ms > 0.0f)
                operators << timing.cpu_ms / timing.gpu_kernel_ms;
            operators << ',' << operator_metrics.max_abs << ',' << operator_metrics.max_rel << ','
                      << operator_metrics.rmse << ',' << operator_metrics.mixed_error << ','
                      << e2e_metrics.max_abs << ',' << e2e_metrics.max_rel << ',' << e2e_metrics.rmse << ','
                      << e2e_metrics.mixed_error << ",PASS\n";
        };
        const std::string frame_shape = shape_text(run.cpu.rx_frames.shape);
        const std::string filtered_shape = shape_text(run.cpu.filtered.shape);
        const std::string score_shape = shape_text(run.cpu.demod_scores.shape);
        const std::string spectrogram_shape = shape_text(run.cpu.spectrogram_values.shape);
        const std::string cwt_shape = shape_text(run.cpu.cwt_values.shape);
        const std::string track_shape = std::to_string(run.cpu.peak_track.size());
        write_row("waveforms/chirp", "signal_generation", "direct", std::to_string(run.cpu.target_template.size()),
                  std::to_string(run.cpu.target_template.size()), run.input_template_error, run.input_template_error);
        write_row("waveforms/gausspulse", "signal_generation", "direct", std::to_string(run.cpu.target_template.size()),
                  std::to_string(run.cpu.target_template.size()), run.input_template_error, run.input_template_error);
        write_row("waveforms/sawtooth", "signal_generation", "direct", std::to_string(run.cpu.rx_frames.size()),
                  std::to_string(run.cpu.rx_frames.size()), run.input_rx_error, run.input_rx_error);
        write_row("waveforms/square", "signal_generation", "direct", std::to_string(run.cpu.rx_frames.size()),
                  std::to_string(run.cpu.rx_frames.size()), run.input_rx_error, run.input_rx_error);
        write_row("bsplines/cubic", "feature_fusion", "private_equivalent", "5", "5", run.feature_score_error, run.feature_score_error);
        write_row("filter_design/firwin", "filter", "direct", "2", std::to_string(run.cpu.filtered.shape.back()),
                  run.filtered_error, run.filtered_e2e_error);
        write_row("filtering/firfilter", "filter", "direct", frame_shape, filtered_shape,
                  run.filtered_error, run.filtered_e2e_error);
        write_row("demod/fm_demod", "demod", "private_equivalent", filtered_shape, score_shape,
                  run.demod_error, run.demod_e2e_error);
        write_row("correlate/correlate", "correlate", "private_equivalent", filtered_shape, score_shape,
                  run.correlate_error, run.correlate_e2e_error);
        write_row("windows/get_window", "spectrogram", "direct", "scalar", std::to_string(config.spectrogram_nperseg),
                  run.spectrogram_error, run.spectrogram_e2e_error);
        write_row("spectral/spectrogram", "spectrogram", "private_equivalent", filtered_shape, spectrogram_shape,
                  run.spectrogram_error, run.spectrogram_e2e_error);
        write_row("wavelets/cwt", "cwt", "private_equivalent", filtered_shape, cwt_shape,
                  run.cwt_error, run.cwt_e2e_error);
        write_row("peak_finding/argrelmax", "feature_fusion", "private_equivalent", score_shape, track_shape,
                  run.feature_score_error, run.feature_score_e2e_error);
        write_row("estimation/kalman_filter", "kalman", "private_equivalent", track_shape, track_shape,
                  run.kalman_cpu_gpu_error, run.kalman_e2e_error);

        std::ofstream stages(report_root() / "latest_stages.csv");
        if (!stages) throw std::runtime_error("failed to write task2 stage CSV");
        stages << "task,scale,stage,record_kind,helper_names,public_operator_links,"
                  "cpu_ms,gpu_e2e_ms,gpu_kernel_ms,counted_in_task_e2e\n";
        stages << std::fixed << std::setprecision(9);
        const auto stage_metadata = [](const std::string &name) {
            if (name == "input_construction") return std::pair<std::string, std::string>{"build_target_template_kernel;build_rx_frames_kernel", "waveforms/chirp;waveforms/gausspulse;waveforms/sawtooth;waveforms/square"};
            if (name == "filter") return std::pair<std::string, std::string>{"extract_real_part_zx_gpu", "filtering/firfilter;filter_design/firwin"};
            if (name == "demod") return std::pair<std::string, std::string>{"batched_demod_score_zx_gpu", "demod/fm_demod"};
            if (name == "correlate") return std::pair<std::string, std::string>{"batched_correlate_score_zx_gpu;normalize_rows_nonnegative_zx_gpu", "correlate/correlate"};
            if (name == "spectrogram") return std::pair<std::string, std::string>{"direct_spectrogram_band_score_zx_gpu;normalize_rows_nonnegative_zx_gpu", "spectral/spectrogram;windows/get_window"};
            if (name == "cwt") return std::pair<std::string, std::string>{"batched_cwt_max_score_zx_gpu;normalize_rows_nonnegative_zx_gpu", "wavelets/cwt"};
            if (name == "feature_fusion") return std::pair<std::string, std::string>{"fuse_feature_scores_zx_gpu;row_peak_track_kernel", "bsplines/cubic;peak_finding/argrelmax"};
            if (name == "measurement_conversion") return std::pair<std::string, std::string>{"copy_measurement_track_zx_gpu", ""};
            if (name == "kalman") return std::pair<std::string, std::string>{"kalman_track_from_peaks_zx_gpu", "estimation/kalman_filter"};
            if (name == "final_output") return std::pair<std::string, std::string>{"materialize_gpu_artifacts", ""};
            return std::pair<std::string, std::string>{"", ""};
        };
        for (const StageTiming &timing : run.stage_timings)
        {
            const auto metadata = stage_metadata(timing.name);
            stages << "task2_features,L" << config.scale_level << ',' << timing.name << ",task_stage,"
                   << metadata.first << ',' << metadata.second << ',' << timing.cpu_ms << ',' << timing.gpu_ms << ',';
            finite_or_blank(stages, timing.gpu_kernel_ms);
            stages << ",true\n";
        }
    }

    void write_spectrogram_breakdown_csv(const std::vector<StageTiming> &timings)
    {
        const fs::path path = report_root() / "latest_spectrogram_breakdown.csv";
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write CSV file: " + path.string());
        }
        output << "substage,cpu_ms,gpu_ms,counted_in_pipeline\n";
        output << std::fixed << std::setprecision(6);
        float total = 0.0f;
        for (const StageTiming &timing : timings)
        {
            const bool counted = timing.name.rfind("validation_", 0) != 0;
            output << timing.name << ',' << timing.cpu_ms << ',' << timing.gpu_ms << ','
                   << (counted ? "true" : "false") << '\n';
            if (counted)
            {
                total += timing.gpu_ms;
            }
        }
        output << "pipeline_total,0.000000," << total << ",true\n";
    }

    void write_gpu_validation_timings_csv(const std::vector<StageTiming> &timings)
    {
        const fs::path path = report_root() / "latest_gpu_validation_timings.csv";
        fs::create_directories(path.parent_path());
        std::ofstream output(path);
        if (!output)
        {
            throw std::runtime_error("failed to write CSV file: " + path.string());
        }
        output << "substage,gpu_ms,counted_in_pipeline\n";
        output << std::fixed << std::setprecision(6);
        for (const StageTiming &timing : timings)
        {
            const bool counted = timing.name == "representative_spectrogram" ||
                                 timing.name == "representative_cwt";
            output << timing.name << ',' << timing.gpu_ms << ','
                   << (counted ? "true" : "false") << '\n';
        }
    }

    void write_unified_step_metrics(
        const ScenarioConfig &config,
        const DemoRunResult &run,
        const ValidationThresholds &thresholds)
    {
        using cusignal_demo::report::StepMetric;
        const auto timing_for = [&](const std::string &name) -> const StageTiming & {
            const auto iter = std::find_if(run.stage_timings.begin(), run.stage_timings.end(),
                [&](const StageTiming &timing) { return timing.name == name; });
            if (iter == run.stage_timings.end())
                throw std::runtime_error("missing stage timing: " + name);
            return *iter;
        };
        const auto shape_text = [](const Shape &shape) {
            std::ostringstream stream;
            for (std::size_t index = 0; index < shape.size(); ++index)
            {
                if (index)
                    stream << 'x';
                stream << shape[index];
            }
            return stream.str();
        };
        const auto make = [&](const std::string &name, const std::string &op,
                              const std::string &input_shape, const std::string &output_shape,
                              const std::string &input_dtype, const std::string &output_dtype,
                              const ErrorMetrics *error, bool complex_error, float limit,
                              const std::string &note) {
            const auto &timing = timing_for(name);
            StepMetric metric;
            metric.step = name;
            metric.operator_name = op;
            metric.input_shape = input_shape;
            metric.output_shape = output_shape;
            metric.input_dtype = input_dtype;
            metric.output_dtype = output_dtype;
            metric.cpu_ms = timing.cpu_ms;
            metric.gpu_e2e_ms = timing.gpu_ms;
            metric.gpu_kernel_ms = timing.gpu_kernel_ms;
            metric.error_available = error != nullptr;
            metric.complex_error = complex_error;
            if (error)
                metric.error = *error;
            metric.pass = error && error->mixed_error <= limit;
            metric.note = note;
            if (timing.gpu_ms == 0.0f && timing.gpu_kernel_ms == 0.0f)
                metric.note += "; this data handoff invokes no CUDA work";
            else
                metric.note += "; gpu_kernel_ms is CUDA-event elapsed time for GPU stream work "
                    "in this composite task step";
            return metric;
        };

        const std::string frame_shape = std::to_string(config.num_frames) + "x" +
            std::to_string(config.samples_per_frame);
        std::vector<StepMetric> steps;
        steps.push_back(make("filter", "filter_design/firwin + filtering/firfilter public complex64 path",
            frame_shape, shape_text(run.cpu.filtered.shape), "complex64", "complex64",
            &run.filtered_error, true, thresholds.filtered_mixed, "public complex64 filtering step"));
        steps.push_back(make("demod", "demod/fm_demod + private batched score",
            shape_text(run.cpu.filtered.shape), frame_shape, "complex64", "float32",
            &run.demod_error, false, thresholds.demod_score_mixed,
            "CPU/GPU demod score error; phase values use a 5e-2 mixed absolute floor"));
        steps.push_back(make("correlate", "correlate/correlate + private normalization",
            shape_text(run.cpu.filtered.shape), shape_text(run.cpu.correlate_scores.shape),
            "complex64", "float32", &run.correlate_error, false,
            thresholds.correlate_mixed, "mixed public/private step"));
        steps.push_back(make("spectrogram", "spectral/spectrogram + private band score",
            frame_shape, shape_text(run.cpu.spectrogram_values.shape), "float32", "float32",
            &run.spectrogram_error, false, thresholds.spectrogram_mixed,
            "representative-frame error; stage timing covers all frames"));
        steps.push_back(make("cwt", "wavelets/cwt + private scale reduction",
            frame_shape, shape_text(run.cpu.cwt_values.shape), "float32", "complex64",
            &run.cwt_error, true, thresholds.cwt_mixed,
            "representative-frame error; stage timing covers all frames"));
        steps.push_back(make("feature_fusion", "private weighted fusion + peak selection",
            frame_shape, shape_text(run.cpu.feature_scores.shape), "float32", "float32",
            &run.feature_score_error, false, thresholds.feature_score_mixed,
            "private step"));

        steps.push_back(make("measurement_conversion", "estimation measurement helper",
            std::to_string(config.num_frames), std::to_string(config.num_frames),
            "float32", "float32", &run.measurement_error, false,
            thresholds.feature_score_mixed, "CPU/GPU measurement track conversion error"));

        auto kalman_metric = make("kalman", "estimation/kalman_filter + private GPU pipeline",
            std::to_string(config.num_frames), std::to_string(config.num_frames),
            "float32", "float32", &run.kalman_cpu_gpu_error, false, config.kalman_rmse_tolerance,
            "CPU/GPU Kalman track error; task validation also checks GPU track to truth");
        kalman_metric.pass = run.kalman_cpu_gpu_error.rmse <= config.kalman_rmse_tolerance;
        steps.push_back(std::move(kalman_metric));
        cusignal_demo::report::write_step_metrics(report_root(), "task2_features", steps);
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
        float gpu_kernel_total_ms_value,
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
        stream << "| stage | cpu_ms | gpu_ms | gpu_kernel_ms |\n";
        stream << "| --- | ---: | ---: | ---: |\n";
        stream << std::fixed << std::setprecision(6);
        for (const StageTiming &timing : timings)
        {
            stream << "| " << timing.name << " | " << timing.cpu_ms << " | " << timing.gpu_ms << " | "
                   << timing.gpu_kernel_ms << " |\n";
        }
        stream << "| total | " << cpu_total_ms << " | " << gpu_total_ms << " | "
               << gpu_kernel_total_ms_value << " |\n\n";
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
        stream << "- metrics: `data/.reports_staging/demo/task2_features/latest_metrics.json`\n";
        stream << "- timings: `data/.reports_staging/demo/task2_features/latest_stage_timings.csv`\n";
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
        float gpu_kernel_total_ms_value,
        bool cpu_gpu_track_match,
        bool gpu_matches_truth,
        const ValidationResult &validation,
        const ResourceSnapshot &resource_before,
        const ResourceSnapshot &resource_after,
        const std::vector<IterationSummary> &iterations)
    {
        std::ostringstream stream;
        stream << "{\n";
        stream << "  \"version\": \"V3.3\",\n";
        stream << "  \"scenario\": {\n";
        stream << "    \"scale_level\": " << config.scale_level << ",\n";
        stream << "    \"unified_scale_protocol\": " << bool_json(config.unified_scale_protocol) << ",\n";
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
        stream << "  \"timing_protocol\": {\n"
               << "    \"warmup_runs\": " << config.warmup_runs << ",\n"
               << "    \"measured_repeat_runs\": " << iterations.size() << ",\n"
               << "    \"cpu_e2e\": \"input construction + operator execution + host output materialization\",\n"
               << "    \"gpu_e2e\": \"device waveform/input construction + chained operator execution + final D2H/output\",\n"
               << "    \"task_input_h2d_ms\": 0,\n"
               << "    \"gpu_kernel\": \"median of per-repeat CUDA-event stage totals; validation-only H2D/D2H excluded\",\n"
               << "    \"input_refresh_policy\": \"warmup and every measured repeat regenerate deterministic device inputs from the same seed/config; prior input values are not reused\",\n"
               << "    \"workspace_reuse_policy\": \"device allocation capacity and FFT plan may be reused; input values may not\"\n"
               << "  },\n";
        stream << "  \"timings\": {\n";
        for (std::size_t index = 0; index < timings.size(); ++index)
        {
            const StageTiming &timing = timings[index];
            stream << "    \"" << json_escape(timing.name) << "\": {\"cpu_ms\": " << timing.cpu_ms
                   << ", \"gpu_ms\": " << timing.gpu_ms << ", \"gpu_kernel_ms\": ";
            cusignal_demo::report::write_optional(stream, timing.gpu_kernel_ms);
            stream << "},\n";
        }
        stream << "    \"total\": {\"cpu_ms\": " << cpu_total_ms << ", \"gpu_ms\": " << gpu_total_ms
               << ", \"gpu_kernel_ms\": " << gpu_kernel_total_ms_value << "}\n";
        stream << "  },\n";
        stream << "  \"speedup_definition\": {\"e2e\": \"median(per_repeat_cpu_e2e_ms) / median(per_repeat_gpu_e2e_ms)\", "
               << "\"kernel\": \"median(per_repeat_cpu_e2e_ms) / median(per_repeat_gpu_kernel_total_ms)\"},\n";
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

        CpuTaskRun cpu_timed = run_cpu_task(config);
        GpuTaskRun gpu_timed = run_gpu_task(config);
        GpuValidationRun operator_validation = run_gpu_validation(config, cpu_timed.inputs);

        DemoRunResult result;
        result.cpu = std::move(cpu_timed.artifacts);
        result.gpu = std::move(gpu_timed.artifacts);
        result.gpu_operator_validation = std::move(operator_validation.artifacts);
        result.validation_input_d2h_ms = gpu_timed.validation_input_d2h_ms;

        result.input_template_error = compute_complex_error(
            cpu_timed.inputs.target_template, gpu_timed.host_inputs.target_template);
        result.input_rx_error = compute_complex_error(
            cpu_timed.inputs.rx_frames.values, gpu_timed.host_inputs.rx_frames.values);

        result.stage_timings = cpu_timed.timings;
        result.operator_timings = cpu_timed.operator_timings;
        for (const StageTiming &gpu_timing : gpu_timed.timings)
        {
            const auto existing = std::find_if(
                result.stage_timings.begin(),
                result.stage_timings.end(),
                [&](const StageTiming &timing) { return timing.name == gpu_timing.name; });
            if (existing == result.stage_timings.end())
            {
                if (gpu_timing.name == "h2d")
                {
                    const auto input_end = std::find_if(
                        result.stage_timings.begin(),
                        result.stage_timings.end(),
                        [](const StageTiming &timing) {
                            return timing.name == "input_construction";
                        });
                    if (input_end != result.stage_timings.end())
                        result.stage_timings.insert(input_end + 1, gpu_timing);
                    else
                        result.stage_timings.push_back(gpu_timing);
                }
                else
                {
                    result.stage_timings.push_back(gpu_timing);
                }
            }
            else
            {
                existing->gpu_ms = gpu_timing.gpu_ms;
                existing->gpu_kernel_ms = gpu_timing.gpu_kernel_ms;
            }
        }
        for (const StageTiming &gpu_timing : gpu_timed.operator_timings)
        {
            const auto existing = std::find_if(
                result.operator_timings.begin(), result.operator_timings.end(),
                [&](const StageTiming &timing) { return timing.name == gpu_timing.name; });
            if (existing == result.operator_timings.end())
                result.operator_timings.push_back(gpu_timing);
            else
            {
                existing->gpu_ms = gpu_timing.gpu_ms;
                existing->gpu_kernel_ms = gpu_timing.gpu_kernel_ms;
            }
        }

        result.filtered_error = compute_real_array_error(
            result.cpu.filtered, result.gpu_operator_validation.filtered);
        result.demod_error = compute_real_array_error(
            result.cpu.demod_scores, result.gpu_operator_validation.demod_scores, kDemodMixedScale);
        result.correlate_error = compute_real_array_error(
            result.cpu.correlate_scores, result.gpu_operator_validation.correlate_scores);
        result.spectrogram_error = compute_real_array_error(
            result.cpu.spectrogram_values, result.gpu_operator_validation.spectrogram_values, kSpectralMixedScale);
        result.cwt_error = compute_real_array_error(
            result.cpu.cwt_values, result.gpu_operator_validation.cwt_values, kSpectralMixedScale);
        result.feature_score_error = compute_real_array_error(
            result.cpu.feature_scores, result.gpu_operator_validation.feature_scores);
        result.measurement_error = compute_real_error(
            result.cpu.measurement_values, result.gpu_operator_validation.measurement_values);
        result.kalman_error = compute_real_error(
            result.cpu.truth_track, result.gpu_operator_validation.kalman_track);
        result.kalman_cpu_gpu_error = compute_real_error(
            result.cpu.kalman_track, result.gpu_operator_validation.kalman_track);

        result.filtered_e2e_error = compute_real_array_error(result.cpu.filtered, result.gpu.filtered);
        result.demod_e2e_error = compute_real_array_error(
            result.cpu.demod_scores, result.gpu.demod_scores, kDemodMixedScale);
        result.correlate_e2e_error = compute_real_array_error(result.cpu.correlate_scores, result.gpu.correlate_scores);
        result.spectrogram_e2e_error = compute_real_array_error(
            result.cpu.spectrogram_values, result.gpu.spectrogram_values, kSpectralMixedScale);
        result.cwt_e2e_error = compute_real_array_error(
            result.cpu.cwt_values, result.gpu.cwt_values, kSpectralMixedScale);
        result.feature_score_e2e_error = compute_real_array_error(result.cpu.feature_scores, result.gpu.feature_scores);
        result.measurement_e2e_error = compute_real_error(
            result.cpu.measurement_values, result.gpu.measurement_values);
        result.kalman_e2e_error = compute_real_error(result.cpu.truth_track, result.gpu.kalman_track);
        result.cpu_gpu_track_match = tracks_match(result.cpu.peak_track, result.gpu.peak_track);
        result.gpu_matches_truth = result.kalman_error.rmse <= config.kalman_rmse_tolerance;

        for (const StageTiming &timing : result.stage_timings)
        {
            result.cpu_total_ms += timing.cpu_ms;
            result.gpu_total_ms += timing.gpu_ms;
        }
        result.gpu_kernel_total_ms = gpu_kernel_total_ms(result.stage_timings);
        return result;
    }

    int run(const DemoOptions &options)
    {
        ScenarioConfig config = options.unified_scale_protocol
            ? unified_scenario_for_scale_level(options.scale_level)
            : scenario_for_scale_level(options.scale_level);
        apply_scenario_overrides(config, options);
        config.warmup_runs = options.warmup;
        validate_config(config);
        // Unified levels share L6's correctness and timing gate so the curve
        // cannot silently relax validation as the input size changes.
        const ValidationThresholds thresholds = thresholds_for_scale_level(
            config.unified_scale_protocol ? 6 : config.scale_level);
        const bool invalid_checks_passed = options.invalid_input_checks ? run_invalid_input_checks() : true;
        for (int warmup = 0; warmup < options.warmup; ++warmup)
        {
            warmup_gpu_task(config);
        }
        const ResourceSnapshot resource_before = capture_resource_snapshot();

        DemoRunResult final_run;
        ValidationResult final_validation;
        std::vector<IterationSummary> iterations;
        std::vector<std::vector<StageTiming>> repeat_stage_timings;
        repeat_stage_timings.reserve(static_cast<std::size_t>(options.repeat));
        std::vector<std::vector<StageTiming>> repeat_operator_timings;
        repeat_operator_timings.reserve(static_cast<std::size_t>(options.repeat));
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
            summary.gpu_kernel_total_ms = gpu_kernel_total_ms(current.stage_timings);
            summary.resource_after = capture_resource_snapshot();
            iterations.push_back(summary);
            repeat_stage_timings.push_back(current.stage_timings);
            repeat_operator_timings.push_back(current.operator_timings);
            if (iteration + 1 == options.repeat)
            {
                final_validation = std::move(current_validation);
                final_run = std::move(current);
            }
        }
        append_repeat_validation(final_validation, iterations, thresholds, options.skip_timing_validation);
        // Persist medians across all measured repeats instead of the last run.
        final_run.stage_timings = cusignal_demo::report::median_stage_timings(repeat_stage_timings);
        final_run.operator_timings = cusignal_demo::report::median_stage_timings(repeat_operator_timings);
        // Task E2E is the median of complete per-repeat totals.  Summing
        // medians of individual stages can select different repeat samples
        // and therefore is not a valid end-to-end statistic.
        std::vector<double> cpu_totals;
        std::vector<double> gpu_totals;
        std::vector<double> gpu_kernel_totals;
        cpu_totals.reserve(iterations.size());
        gpu_totals.reserve(iterations.size());
        gpu_kernel_totals.reserve(iterations.size());
        for (const IterationSummary &iteration : iterations)
        {
            cpu_totals.push_back(iteration.cpu_total_ms);
            gpu_totals.push_back(iteration.gpu_total_ms);
            gpu_kernel_totals.push_back(iteration.gpu_kernel_total_ms);
        }
        final_run.cpu_total_ms = static_cast<float>(median_value(std::move(cpu_totals)));
        final_run.gpu_total_ms = static_cast<float>(median_value(std::move(gpu_totals)));
        final_run.gpu_kernel_total_ms = static_cast<float>(median_value(std::move(gpu_kernel_totals)));
        const ResourceSnapshot resource_after = capture_resource_snapshot();

        write_generated_inputs(config, final_run.cpu.target_template, final_run.cpu.rx_frames, final_run.cpu.truth_track);
        write_output_samples(final_run.cpu, final_run.gpu);
        write_stage_timings_csv(
            final_run.stage_timings,
            final_run.cpu_total_ms,
            final_run.gpu_total_ms,
            final_run.gpu_kernel_total_ms);
        write_task_csv_reports(config, final_run, final_validation, options.warmup, options.repeat);
        write_unified_step_metrics(config, final_run, thresholds);
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
                final_run.gpu_kernel_total_ms,
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
                final_run.gpu_kernel_total_ms,
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
        const auto timing_for = [&](const std::string &name) -> const StageTiming & {
            const auto iter = std::find_if(
                final_run.stage_timings.begin(), final_run.stage_timings.end(),
                [&](const StageTiming &timing) { return timing.name == name; });
            if (iter == final_run.stage_timings.end())
            {
                throw std::runtime_error("missing stage timing: " + name);
            }
            return *iter;
        };
        const float speedup = final_run.gpu_total_ms > 0.0f
            ? final_run.cpu_total_ms / final_run.gpu_total_ms
            : 0.0f;
        std::cout << std::fixed << std::setprecision(3)
                  << "[task2_features] key_metrics shape=" << config.num_frames << 'x'
                  << config.samples_per_frame
                  << " template_length=" << config.template_length
                  << " cpu_total_ms=" << final_run.cpu_total_ms
                  << " gpu_total_ms=" << final_run.gpu_total_ms
                  << " gpu_kernel_total_ms=" << final_run.gpu_kernel_total_ms
                  << " e2e_speedup=" << speedup << "x\n"
                  << "[task2_features] hotspot_gpu_ms filter=" << timing_for("filter").gpu_ms
                  << " correlate=" << timing_for("correlate").gpu_ms
                  << " spectrogram=" << timing_for("spectrogram").gpu_ms
                  << " cwt=" << timing_for("cwt").gpu_ms << '\n';
        std::cout << "reports       : "
                  << (report_root() / "latest_summary.md").lexically_relative(repo_root()).string() << '\n';
        return 0;
    }
}
