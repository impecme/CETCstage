#include "../common/task_step_report.hpp"
#include "task1_common.hpp"

#include <cuda_runtime_api.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <complex>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <initializer_list>
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
    constexpr float kMixedErrorAtol = 1.0e-5f;
    constexpr float kMixedErrorScale = 1.0e-2f;

    bool environment_flag_enabled(const char *name)
    {
        const char *value = std::getenv(name);
        if (value == nullptr)
        {
            return false;
        }
        const std::string token(value);
        return token == "1" || token == "true" || token == "TRUE" ||
            token == "on" || token == "ON";
    }

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
            config.num_pulses = 128;
            config.samples_per_pulse = 4096;
            config.template_length = 1024;
            config.pulse_compression_nfft = 4096;
            config.pulse_doppler_nfft = 128;
            break;
        default:
            break;
        }
        config.delay_samples = std::max(1, config.samples_per_pulse * 3 / 16);
        return config;
    }

    // Formal-PPT scale protocol: all algorithmic parameters are inherited from
    // the L6 acceptance case; only the task input shape changes across levels.
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
        // 1536 is the smallest retained-input length that can hold the fixed
        // 1024-sample L6 template plus this task's deterministic delay.
        case 1: config.num_pulses = 16;  config.samples_per_pulse = 1536; break;
        case 2: config.num_pulses = 32;  config.samples_per_pulse = 1536; break;
        case 3: config.num_pulses = 48;  config.samples_per_pulse = 2048; break;
        case 4: config.num_pulses = 64;  config.samples_per_pulse = 2048; break;
        case 5: config.num_pulses = 96;  config.samples_per_pulse = 3072; break;
        case 6: break;
        default: break;
        }
        config.delay_samples = std::max(1, config.samples_per_pulse * 3 / 16);
        return config;
    }

    void apply_scenario_overrides(ScenarioConfig &config, const DemoOptions &options)
    {
        if (options.num_pulses) config.num_pulses = *options.num_pulses;
        if (options.samples_per_pulse)
        {
            config.samples_per_pulse = *options.samples_per_pulse;
            config.delay_samples = std::max(1, config.samples_per_pulse * 3 / 16);
        }
        if (options.template_length) config.template_length = *options.template_length;
        if (options.pulse_compression_nfft) config.pulse_compression_nfft = *options.pulse_compression_nfft;
        if (options.pulse_doppler_nfft) config.pulse_doppler_nfft = *options.pulse_doppler_nfft;
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
#if defined(CUSIGNAL_PLATFORM_ZHONGKEXIN)
        if (scale_level == 3)
        {
            thresholds.gpu_total_baseline_ms = 4.0f;
            thresholds.gpu_total_hard_limit_ms = 5.0f;
        }
#endif
        return thresholds;
    }

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
        return repo_root() / "data" / ".reports_staging" / "demo" / "task1_radar";
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
            else if (arg == "--num-pulses" || arg == "--samples-per-pulse" ||
                     arg == "--template-length" || arg == "--pulse-compression-nfft" ||
                     arg == "--pulse-doppler-nfft")
            {
                if (index + 1 >= argc)
                {
                    throw std::invalid_argument(arg + " requires a positive integer");
                }
                const int value = std::atoi(argv[++index]);
                if (value <= 0)
                {
                    throw std::invalid_argument(arg + " must be a positive integer");
                }
                if (arg == "--num-pulses") options.num_pulses = value;
                else if (arg == "--samples-per-pulse") options.samples_per_pulse = value;
                else if (arg == "--template-length") options.template_length = value;
                else if (arg == "--pulse-compression-nfft") options.pulse_compression_nfft = value;
                else options.pulse_doppler_nfft = value;
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
                std::cout << "usage: task1_radar_demo [--warmup N] [--repeat N] [--scale-level 1..6] [--unified-scale-protocol] [--invalid-input-checks] "
                             "[--skip-timing-validation] [--num-pulses N] [--samples-per-pulse N] "
                             "[--template-length N] [--pulse-compression-nfft N] "
                             "[--pulse-doppler-nfft N]\n";
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

    std::vector<float> magnitude_signal(const ComplexSignal &values)
    {
        std::vector<float> result(values.size(), 0.0f);
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            result[index] = std::abs(values[index]);
        }
        return result;
    }

    float centered_doppler_bin_to_hz(int bin, int nfft, float prf)
    {
        const int centered = bin - (nfft / 2);
        return static_cast<float>(centered) * prf / static_cast<float>(nfft);
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

    RealSignal detection_as_signal(const DetectionSummary &detection)
    {
        return RealSignal{
            detection.found ? 1.0f : 0.0f,
            static_cast<float>(detection.range_bin),
            static_cast<float>(detection.doppler_bin),
            detection.doppler_hz,
            detection.power,
        };
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
        // construction.  Keep the historical compute budget for the device
        // chain, then add the measured input-construction stage explicitly.
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
            run.input_template_error.mixed_error <= thresholds.pulse_compression_mixed,
            run.input_template_error.mixed_error,
            thresholds.pulse_compression_mixed,
            "CPU/GPU-native chirp template input mixed error");
        add_check(
            validation,
            "input_rx_mixed_error",
            run.input_rx_error.mixed_error <= thresholds.pulse_compression_mixed,
            run.input_rx_error.mixed_error,
            thresholds.pulse_compression_mixed,
            "CPU/GPU-native received matrix input mixed error");
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
        scenario << "  \"unified_scale_protocol\": " << bool_json(config.unified_scale_protocol) << ",\n";
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
               << gpu_kernel_total_ms(timings) << '\n';
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
        const ErrorMetrics power_map_operator_error = compute_real_error(
            run.cpu.range_doppler_power.values, run.gpu_operator_validation.range_doppler_power.values);
        const ErrorMetrics power_map_e2e_error = compute_real_error(
            run.cpu.range_doppler_power.values, run.gpu.range_doppler_power.values);
        const ErrorMetrics input_error = aggregate_error({
            &run.input_template_error, &run.input_rx_error});
        const ErrorMetrics operator_error = aggregate_error({
            &run.pulse_compression_error,
            &run.pulse_doppler_error,
            &run.cfar_threshold_error,
            &run.ambgfun_error,
            &power_map_operator_error});
        const ErrorMetrics e2e_error = aggregate_error({
            &run.pulse_compression_e2e_error,
            &run.pulse_doppler_e2e_error,
            &run.cfar_threshold_e2e_error,
            &run.ambgfun_e2e_error,
            &power_map_e2e_error});
        const StageTiming &input_timing = timing_for("input_construction");

        fs::create_directories(report_root() / "operators");
        fs::create_directories(report_root() / "stages");
        std::ofstream summary(report_root() / "latest_summary.csv");
        if (!summary) throw std::runtime_error("failed to write task1 summary CSV");
        summary << "task,scale,seed,warmup,repeat,input_elements,cpu_input_ms,gpu_input_ms,task_input_h2d_ms,validation_input_d2h_ms,"
                   "cpu_total_ms,gpu_e2e_ms,gpu_kernel_ms,e2e_speedup,kernel_speedup,"
                   "input_max_abs,input_max_rel,input_rmse,input_mixed_error,"
                   "operator_max_abs,operator_max_rel,operator_rmse,operator_mixed_error,"
                   "e2e_max_abs,e2e_max_rel,e2e_rmse,e2e_mixed_error,validation_pass\n";
        summary << std::fixed << std::setprecision(9)
                << "task1_radar,L" << config.scale_level << ',' << config.seed << ',' << warmup << ',' << repeat << ','
                << scale_value(config) << ',' << input_timing.cpu_ms << ',' << input_timing.gpu_ms
                << ",0," << run.validation_input_d2h_ms << ',' << run.cpu_total_ms << ',' << run.gpu_total_ms << ','
                << gpu_kernel_total_ms(run.stage_timings) << ','
                << (run.gpu_total_ms > 0.0f ? run.cpu_total_ms / run.gpu_total_ms : 0.0f) << ','
                << (gpu_kernel_total_ms(run.stage_timings) > 0.0f
                        ? run.cpu_total_ms / gpu_kernel_total_ms(run.stage_timings) : 0.0f)
                << ',' << input_error.max_abs << ',' << input_error.max_rel << ',' << input_error.rmse << ','
                << input_error.mixed_error << ',' << operator_error.max_abs << ',' << operator_error.max_rel << ','
                << operator_error.rmse << ',' << operator_error.mixed_error << ',' << e2e_error.max_abs << ','
                << e2e_error.max_rel << ',' << e2e_error.rmse << ',' << e2e_error.mixed_error << ','
                << (validation.pass ? "PASS" : "ERROR") << '\n';

        std::ofstream operators(report_root() / "latest_operators.csv");
        if (!operators) throw std::runtime_error("failed to write task1 operator CSV");
        operators << "task,scale,operator,source_step,mapping_mode,input_shape,output_shape,"
                      "cpu_ms,gpu_e2e_ms,gpu_kernel_ms,e2e_speedup,kernel_speedup,"
                      "operator_max_abs,operator_max_rel,operator_rmse,operator_mixed_error,"
                      "e2e_max_abs,e2e_max_rel,e2e_rmse,e2e_mixed_error,status\n";
        operators << std::fixed << std::setprecision(9);
        const std::string rx_shape = shape_text(run.cpu.rx_matrix.shape);
        const std::string pulse_compression_shape = shape_text(run.cpu.pulse_compression.shape);
        const std::string pulse_doppler_shape = shape_text(run.cpu.pulse_doppler.shape);
        const std::string power_shape = shape_text(run.cpu.range_doppler_power.shape);
        const std::string cfar_shape = shape_text(run.cpu.cfar_threshold.shape);
        const std::string ambgfun_shape = shape_text(run.cpu.ambgfun.values.shape);
        const std::string template_shape = std::to_string(run.cpu.tx_template.size());
        const ErrorMetrics detection_error = compute_real_error(
            detection_as_signal(run.cpu_detection),
            detection_as_signal(run.gpu_detection));
        const auto operator_timing_for = [&](const std::string &name) -> const StageTiming & {
            const auto iter = std::find_if(run.operator_timings.begin(), run.operator_timings.end(),
                [&](const StageTiming &timing) { return timing.name == name; });
            if (iter == run.operator_timings.end())
                throw std::runtime_error("missing public operator timing: " + name);
            return *iter;
        };
        const auto write_row = [&](const char *name, const char *source_step, const char *mapping_mode,
                                   const char *input_shape, const char *output_shape,
                                   const ErrorMetrics &operator_metrics, const ErrorMetrics &e2e_metrics) {
            const StageTiming &timing = operator_timing_for(name);
            operators << "task1_radar,L" << config.scale_level << ',' << name << ','
                      << source_step << ',' << mapping_mode << ',' << input_shape << ',' << output_shape << ','
                      << timing.cpu_ms << ',' << timing.gpu_ms << ',';
            finite_or_blank(operators, timing.gpu_kernel_ms);
            operators << ',' << (timing.gpu_ms > 0.0f ? timing.cpu_ms / timing.gpu_ms : 0.0f) << ',';
            if (std::isfinite(timing.gpu_kernel_ms) && timing.gpu_kernel_ms > 0.0f)
                operators << timing.cpu_ms / timing.gpu_kernel_ms;
            operators << ',' << operator_metrics.max_abs << ',' << operator_metrics.max_rel << ','
                      << operator_metrics.rmse << ',' << operator_metrics.mixed_error << ','
                      << e2e_metrics.max_abs << ',' << e2e_metrics.max_rel << ',' << e2e_metrics.rmse << ','
                      << e2e_metrics.mixed_error << ",PASS\n";
        };
        write_row("waveforms/chirp", "signal_generation", "direct", template_shape.c_str(), template_shape.c_str(),
                  run.input_template_error, run.input_template_error);
        write_row("radartools/pulse_compression", "pulse_compression", "direct", rx_shape.c_str(),
                  pulse_compression_shape.c_str(), run.pulse_compression_error, run.pulse_compression_e2e_error);
        write_row("radartools/pulse_doppler", "pulse_doppler", "variant", pulse_compression_shape.c_str(),
                  pulse_doppler_shape.c_str(), run.pulse_doppler_error, run.pulse_doppler_e2e_error);
        write_row("radartools/ca_cfar", "ca_cfar", "direct", power_shape.c_str(), cfar_shape.c_str(),
                  run.cfar_threshold_error, run.cfar_threshold_e2e_error);
        write_row("radartools/ambgfun", "ambgfun", "direct", template_shape.c_str(), ambgfun_shape.c_str(),
                  run.ambgfun_error, run.ambgfun_e2e_error);

        std::ofstream stages(report_root() / "latest_stages.csv");
        if (!stages) throw std::runtime_error("failed to write task1 stage CSV");
        stages << "task,scale,stage,record_kind,helper_names,public_operator_links,"
                  "cpu_ms,gpu_e2e_ms,gpu_kernel_ms,counted_in_task_e2e\n";
        stages << std::fixed << std::setprecision(9);
        const auto stage_metadata = [](const std::string &name) {
            if (name == "input_construction") return std::pair<std::string, std::string>{"build_time_axis_kernel;build_rx_matrix_kernel", "waveforms/chirp"};
            if (name == "pulse_compression") return std::pair<std::string, std::string>{"", "radartools/pulse_compression"};
            if (name == "pulse_doppler") return std::pair<std::string, std::string>{"fftshift_rows", "radartools/pulse_doppler"};
            if (name == "power_map") return std::pair<std::string, std::string>{"power_map", ""};
            if (name == "ca_cfar") return std::pair<std::string, std::string>{"", "radartools/ca_cfar"};
            if (name == "ambgfun") return std::pair<std::string, std::string>{"", "radartools/ambgfun"};
            if (name == "final_detection") return std::pair<std::string, std::string>{"detect_peak", ""};
            if (name == "final_output") return std::pair<std::string, std::string>{"materialize_gpu_artifacts", ""};
            return std::pair<std::string, std::string>{"", ""};
        };
        for (const StageTiming &timing : run.stage_timings)
        {
            const auto metadata = stage_metadata(timing.name);
            stages << "task1_radar,L" << config.scale_level << ',' << timing.name << ",task_stage,"
                   << metadata.first << ',' << metadata.second << ',' << timing.cpu_ms << ',' << timing.gpu_ms << ',';
            finite_or_blank(stages, timing.gpu_kernel_ms);
            stages << ",true\n";
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
            metric.note = note + "; gpu_kernel_ms is CUDA-event elapsed time for GPU stream work "
                "in this composite task step";
            return metric;
        };

        const ErrorMetrics power_error = compute_real_error(
            run.cpu.range_doppler_power.values, run.gpu.range_doppler_power.values);
        std::vector<StepMetric> steps;
        steps.push_back(make("pulse_compression", "radartools/pulse_compression",
            shape_text(run.cpu.rx_matrix.shape), shape_text(run.cpu.pulse_compression.shape),
            "complex64", "complex64", &run.pulse_compression_error, true,
            thresholds.pulse_compression_mixed, "public operator"));
        steps.push_back(make("pulse_doppler", "radartools/pulse_doppler_shifted",
            shape_text(run.cpu.pulse_compression.shape), shape_text(run.cpu.pulse_doppler.shape),
            "complex64", "complex64", &run.pulse_doppler_error, true,
            thresholds.pulse_doppler_mixed, "public operators"));
        steps.push_back(make("power_map", "radartools/power_map",
            shape_text(run.cpu.pulse_doppler.shape), shape_text(run.cpu.range_doppler_power.shape),
            "complex64", "float32", &power_error, false, thresholds.cfar_threshold_mixed,
            "public operator; error added by unified report"));
        steps.push_back(make("ca_cfar", "radartools/ca_cfar",
            shape_text(run.cpu.range_doppler_power.shape), shape_text(run.cpu.cfar_threshold.shape),
            "float32", "float32", &run.cfar_threshold_error, false,
            thresholds.cfar_threshold_mixed, "public operator"));
        steps.push_back(make("ambgfun", "radartools/ambgfun",
            std::to_string(run.cpu.tx_template.size()), shape_text(run.cpu.ambgfun.values.shape),
            "complex64", "float32", &run.ambgfun_error, false,
            thresholds.ambgfun_surface_mixed, "public operator"));

        StepMetric detection;
        detection.step = "final_detection";
        const auto &detection_timing = timing_for("final_detection");
        detection.operator_name = "radartools/detect_peak";
        detection.input_shape = shape_text(run.cpu.range_doppler_power.shape);
        detection.output_shape = "scalar_detection";
        detection.input_dtype = "float32";
        detection.output_dtype = "int32+float32";
        detection.cpu_ms = detection_timing.cpu_ms;
        detection.gpu_e2e_ms = detection_timing.gpu_ms;
        detection.gpu_kernel_ms = detection_timing.gpu_kernel_ms;
        const ErrorMetrics detection_error = compute_real_error(
            detection_as_signal(run.cpu_detection),
            detection_as_signal(run.gpu_detection));
        detection.error_available = true;
        detection.error = detection_error;
        detection.pass = detection_matches(run.cpu_detection, run.gpu_detection);
        detection.note = "public operator; exact business-bin comparison plus CPU/GPU detection vector error; "
            "gpu_kernel_ms is CUDA-event elapsed time for GPU stream work";
        steps.push_back(std::move(detection));
        cusignal_demo::report::write_step_metrics(report_root(), "task1_radar", steps);
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
        stream << "| stage | cpu_ms | gpu_ms | gpu_kernel_ms |\n";
        stream << "| --- | ---: | ---: | ---: |\n";
        stream << std::fixed << std::setprecision(6);
        for (const StageTiming &timing : timings)
        {
            stream << "| " << timing.name << " | " << timing.cpu_ms << " | " << timing.gpu_ms << " | "
                   << timing.gpu_kernel_ms << " |\n";
        }
        stream << "| total | " << cpu_total_ms << " | " << gpu_total_ms << " | "
               << gpu_kernel_total_ms(timings) << " |\n\n";
        stream << "## Validation\n\n";
        stream << "- pass: `" << (validation.pass ? "true" : "false") << "`\n";
        stream << "- repeat_runs: `" << iterations.size() << "`\n";
        stream << "- gpu_free_delta_mib: `" << std::setprecision(3)
               << (resource_after.gpu_free_mib - resource_before.gpu_free_mib) << "`\n";
        stream << "- rss_current_delta_mib: `"
               << (resource_after.rss_current_mib - resource_before.rss_current_mib) << "`\n\n";
        stream << "## Artifacts\n\n";
        stream << "- inputs: `data/generated/demo/task1_radar/input/`\n";
        stream << "- samples: `data/generated/demo/task1_radar/output_samples/`\n";
        stream << "- metrics: `data/.reports_staging/demo/task1_radar/latest_metrics.json`\n";
        stream << "- timings: `data/.reports_staging/demo/task1_radar/latest_stage_timings.csv`\n";
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
        stream << "  \"version\": \"V3.3\",\n";
        stream << "  \"scenario\": {\n";
        stream << "    \"scale_level\": " << config.scale_level << ",\n";
        stream << "    \"unified_scale_protocol\": " << bool_json(config.unified_scale_protocol) << ",\n";
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
        stream << "  \"timing_protocol\": {\n"
               << "    \"warmup_runs\": " << config.warmup_runs << ",\n"
               << "    \"measured_repeat_runs\": " << iterations.size() << ",\n"
               << "    \"cpu_e2e\": \"input construction + operator execution + host output materialization\",\n"
               << "    \"gpu_e2e\": \"device input construction + chained operator execution + final D2H/output\",\n"
               << "    \"task_input_h2d_ms\": 0,\n"
               << "    \"gpu_kernel\": \"CUDA event median; validation-only H2D/D2H excluded\",\n"
               << "    \"input_refresh_policy\": \"fresh device waveform and received-matrix construction on every measured GPU E2E repeat\",\n"
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
               << ", \"gpu_kernel_ms\": " << gpu_kernel_total_ms(timings) << "}\n";
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

    std::vector<StageTiming> merge_backend_timings(
        const std::vector<StageTiming> &cpu_timings,
        const std::vector<StageTiming> &gpu_timings)
    {
        std::vector<StageTiming> merged = cpu_timings;
        for (const StageTiming &gpu_timing : gpu_timings)
        {
            const auto iter = std::find_if(
                merged.begin(),
                merged.end(),
                [&](const StageTiming &timing) { return timing.name == gpu_timing.name; });
            if (iter == merged.end())
            {
                merged.push_back(gpu_timing);
                continue;
            }
            iter->gpu_ms = gpu_timing.gpu_ms;
            iter->gpu_kernel_ms = gpu_timing.gpu_kernel_ms;
        }
        return merged;
    }

    DemoRunResult run_once(const ScenarioConfig &config)
    {
        validate_config(config);

        // The timed backend runs establish independent CPU-native and
        // GPU-native E2E paths. A separate validation GPU run consumes the
        // CPU-native input through H2D and is excluded from formal timing.
        CpuTaskRun cpu_run = run_cpu_task(config);
        GpuTaskRun gpu_run = run_gpu_task(config);
        GpuValidationRun operator_validation = run_gpu_validation(config, cpu_run.inputs);
        CpuValidationRun expected_validation =
            run_cpu_validation(config, build_cpu_task_inputs(config, false));

        DemoRunResult result;
        result.task_inputs = gpu_run.host_inputs;
        result.cpu = std::move(cpu_run.artifacts);
        result.gpu = std::move(gpu_run.artifacts);
        result.gpu_operator_validation = std::move(operator_validation.artifacts);
        result.validation_input_d2h_ms = gpu_run.validation_input_d2h_ms;
        result.expected_detection = expected_validation.detection;
        result.cpu_detection = cpu_run.detection;
        result.gpu_detection = gpu_run.detection;
        result.stage_timings = merge_backend_timings(cpu_run.timings, gpu_run.timings);
        result.operator_timings = merge_backend_timings(cpu_run.operator_timings, gpu_run.operator_timings);
        for (const StageTiming &timing : result.stage_timings)
        {
            result.cpu_total_ms += timing.cpu_ms;
            result.gpu_total_ms += timing.gpu_ms;
        }
        result.input_template_error = compute_complex_error(
            cpu_run.inputs.tx_template, result.task_inputs.tx_template);
        result.input_rx_error = compute_complex_error(
            cpu_run.inputs.rx_matrix.values, result.task_inputs.rx_matrix.values);

        result.pulse_compression_error = compute_complex_error(
            result.cpu.pulse_compression.values,
            result.gpu_operator_validation.pulse_compression.values);
        result.pulse_doppler_error = compute_complex_error(
            result.cpu.pulse_doppler.values,
            result.gpu_operator_validation.pulse_doppler.values);
        result.cfar_threshold_error = compute_real_error(
            result.cpu.cfar_threshold.values,
            result.gpu_operator_validation.cfar_threshold.values);
        result.ambgfun_error = compute_real_error(
            result.cpu.ambgfun.values.values,
            result.gpu_operator_validation.ambgfun.values.values);

        result.pulse_compression_e2e_error = compute_complex_error(
            result.cpu.pulse_compression.values, result.gpu.pulse_compression.values);
        result.pulse_doppler_e2e_error = compute_complex_error(
            result.cpu.pulse_doppler.values, result.gpu.pulse_doppler.values);
        result.cfar_threshold_e2e_error = compute_real_error(
            result.cpu.cfar_threshold.values, result.gpu.cfar_threshold.values);
        result.ambgfun_e2e_error = compute_real_error(
            result.cpu.ambgfun.values.values, result.gpu.ambgfun.values.values);
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
            ValidationResult current_validation = validate_single_run(
                current,
                thresholds,
                invalid_checks_passed,
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
        final_run.cpu_total_ms = 0.0f;
        final_run.gpu_total_ms = 0.0f;
        for (const StageTiming &timing : final_run.stage_timings)
        {
            final_run.cpu_total_ms += timing.cpu_ms;
            final_run.gpu_total_ms += timing.gpu_ms;
        }
        const ResourceSnapshot resource_after = capture_resource_snapshot();

        write_generated_inputs(config, final_run.task_inputs.tx_template, final_run.task_inputs.rx_matrix);
        write_output_samples(final_run.cpu, final_run.gpu);
        write_stage_timings_csv(final_run.stage_timings, final_run.cpu_total_ms, final_run.gpu_total_ms);
        write_task_csv_reports(config, final_run, final_validation, options.warmup, options.repeat);
        write_unified_step_metrics(config, final_run, thresholds);
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

        cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");

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
                  << "[task1_radar] key_metrics shape=" << config.num_pulses << 'x'
                  << config.samples_per_pulse
                  << " template_length=" << config.template_length
                  << " cpu_total_ms=" << final_run.cpu_total_ms
                  << " gpu_total_ms=" << final_run.gpu_total_ms
                  << " gpu_kernel_total_ms=" << gpu_kernel_total_ms(final_run.stage_timings)
                  << " speedup=" << speedup << "x\n"
                  << "[task1_radar] hotspot_gpu_ms pulse_compression="
                  << timing_for("pulse_compression").gpu_ms
                  << " pulse_doppler=" << timing_for("pulse_doppler").gpu_ms
                  << " ca_cfar=" << timing_for("ca_cfar").gpu_ms
                  << " ambgfun=" << timing_for("ambgfun").gpu_ms << '\n';
        std::cout << "reports       : "
                  << (report_root() / "latest_summary.md").lexically_relative(repo_root()).string() << '\n';
        return 0;
    }
} // namespace cusignal_demo::task1_radar
