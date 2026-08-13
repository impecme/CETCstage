#pragma once

#include "../common/task_step_report.hpp"

#include <chrono>
#include <cmath>
#include <complex>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <optional>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

#include <cuda_runtime_api.h>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal_demo::task2_features
{
    namespace fs = std::filesystem;

    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::ZxGpuRealSignal;
    using ErrorMetrics = cusignal_demo::report::ErrorMetrics;
    using StageTiming = cusignal_demo::report::StageTiming;

    constexpr float kMixedErrorAtol = 1.0e-5f;
    constexpr float kDefaultMixedScale = 1.0e-2f;
    constexpr float kSpectralMixedScale = 1.0e-1f;
    // FM demodulation is a phase difference. Near zero, a small upstream
    // complex64 filter difference is best judged with an absolute floor tied
    // to the task's phase-stabilization band.
    constexpr float kDemodMixedScale = 5.0e-2f;

    struct ScenarioConfig
    {
        int scale_level = 3;
        bool unified_scale_protocol = false;
        int warmup_runs = 0;
        float fs = 1.0e6f;
        int num_frames = 48;
        int samples_per_frame = 1024;
        int template_length = 256;
        int target_start_sample_0 = 220;
        int target_step_per_frame = 3;
        int interferer_start_sample = 640;
        int interferer_length = 256;
        float target_amplitude = 1.0f;
        float interferer_amplitude = 0.45f;
        float snr_db = 12.0f;
        unsigned int seed = 20260414u;
        float chirp_f0 = 7.0e4f;
        float chirp_f1 = 1.8e5f;
        float gausspulse_fc = 1.2e5f;
        float interferer_f0 = 9.0e4f;
        float interferer_f1 = 1.45e5f;
        int representative_frame_index = 24;
        int filter_numtaps = 129;
        float filter_low = 6.0e4f;
        float filter_high = 2.2e5f;
        int spectrogram_nperseg = 128;
        int spectrogram_noverlap = 96;
        int spectrogram_nfft = 256;
        int peak_order = 8;
        float kalman_rmse_tolerance = 2.0f;
    };

    struct DemoOptions
    {
        int warmup = 0;
        int repeat = 1;
        int scale_level = 6;
        std::optional<int> num_frames;
        std::optional<int> samples_per_frame;
        std::optional<int> template_length;
        std::optional<int> filter_numtaps;
        std::optional<int> spectrogram_nperseg;
        std::optional<int> spectrogram_noverlap;
        std::optional<int> spectrogram_nfft;
        bool unified_scale_protocol = false;
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
        // CPU/GPU waveform implementations use separate float32 math paths;
        // native input comparison is therefore slightly looser than operator
        // output comparison while remaining below 3e-4.
        float input_mixed = 3.0e-4f;
        float filtered_mixed = 1.0e-4f;
        float demod_score_mixed = 5.0e-4f;
        float correlate_mixed = 1.0e-4f;
        float spectrogram_mixed = 1.0e-4f;
        float cwt_mixed = 1.0e-4f;
        float feature_score_mixed = 1.0e-4f;
        float timing_relative_jitter = 0.35f;
        float gpu_free_drift_mib = 32.0f;
        float rss_current_drift_mib = 64.0f;
    };

    struct CpuArtifacts
    {
        ComplexSignal target_template;
        ComplexArray rx_frames;
        RealSignal truth_track;
        ComplexArray filtered;
        RealArray demod_scores;
        RealArray correlate_scores;
        RealArray spectrogram_values;
        RealSignal spectrogram_freqs;
        RealSignal spectrogram_times;
        ComplexArray cwt_values;
        RealArray feature_scores;
        RealSignal peak_track;
        RealSignal measurement_values;
        RealSignal kalman_track;
    };

    struct HostGpuArtifacts
    {
        ComplexArray filtered;
        RealArray demod_scores;
        RealArray correlate_scores;
        RealArray spectrogram_values;
        RealSignal spectrogram_freqs;
        RealSignal spectrogram_times;
        ComplexArray cwt_values;
        RealArray feature_scores;
        RealSignal peak_track;
        RealSignal measurement_values;
        RealSignal kalman_track;
    };

    struct TaskInputs
    {
        ComplexSignal target_template;
        ComplexArray rx_frames;
        RealSignal truth_track;
    };

    struct CpuTaskRun
    {
        TaskInputs inputs;
        CpuArtifacts artifacts;
        std::vector<StageTiming> timings;
        // Registered public operators only; task stages/helpers stay in
        // `timings` and are emitted to stages/*.csv.
        std::vector<StageTiming> operator_timings;
    };

    struct CpuValidationRun
    {
        CpuArtifacts artifacts;
    };

    struct GpuTaskRun
    {
        TaskInputs host_inputs;
        HostGpuArtifacts artifacts;
        std::vector<StageTiming> timings;
        std::vector<StageTiming> operator_timings;
        float validation_input_d2h_ms = 0.0f;
    };

    struct GpuValidationRun
    {
        HostGpuArtifacts artifacts;
        std::vector<StageTiming> timings;
    };

    struct DemoRunResult
    {
        CpuArtifacts cpu;
        HostGpuArtifacts gpu;
        HostGpuArtifacts gpu_operator_validation;
        std::vector<StageTiming> stage_timings;
        std::vector<StageTiming> operator_timings;
        ErrorMetrics input_template_error;
        ErrorMetrics input_rx_error;
        ErrorMetrics filtered_error;
        ErrorMetrics demod_error;
        ErrorMetrics correlate_error;
        ErrorMetrics spectrogram_error;
        ErrorMetrics cwt_error;
        ErrorMetrics feature_score_error;
        ErrorMetrics measurement_error;
        ErrorMetrics kalman_error;
        ErrorMetrics kalman_cpu_gpu_error;
        ErrorMetrics filtered_e2e_error;
        ErrorMetrics demod_e2e_error;
        ErrorMetrics correlate_e2e_error;
        ErrorMetrics spectrogram_e2e_error;
        ErrorMetrics cwt_e2e_error;
        ErrorMetrics feature_score_e2e_error;
        ErrorMetrics measurement_e2e_error;
        ErrorMetrics kalman_e2e_error;
        float validation_input_d2h_ms = 0.0f;
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
        float gpu_kernel_total_ms = 0.0f;
        ResourceSnapshot resource_after;
    };

    long long scale_value(const ScenarioConfig &config);
    ScenarioConfig scenario_for_scale_level(int scale_level);
    ScenarioConfig unified_scenario_for_scale_level(int scale_level);
    void apply_scenario_overrides(ScenarioConfig &config, const DemoOptions &options);
    ValidationThresholds thresholds_for_scale_level(int scale_level);
    void validate_config(const ScenarioConfig &config);

    DemoOptions parse_options(int argc, char **argv);
    int run(const DemoOptions &options);

    CpuTaskRun run_cpu_task(const ScenarioConfig &config);
    CpuValidationRun run_cpu_validation(const ScenarioConfig &config, const TaskInputs &inputs);
    TaskInputs build_cpu_task_inputs(const ScenarioConfig &config, bool include_noise = true);
    GpuTaskRun run_gpu_task(const ScenarioConfig &config);
    void warmup_gpu_task(const ScenarioConfig &config);
    GpuValidationRun run_gpu_validation(const ScenarioConfig &config, const TaskInputs &inputs);

    fs::path repo_root();
    fs::path generated_root();
    fs::path report_root();
    bool environment_flag_enabled(const char *name);
    ResourceSnapshot capture_resource_snapshot();
    float gpu_kernel_total_ms(const std::vector<StageTiming> &timings);

    RealSignal linspace(float start, float stop, int count);
    RealSignal even_range(float start, float stop, float step);
    ComplexArray as_complex_array(const ComplexSignal &signal);
    RealArray as_real_array(const RealSignal &signal);
    ComplexSignal extract_row_complex_signal(const ComplexArray &input, int row_index);
    void store_row_real(RealArray &output, const RealSignal &row, int row_index);
    std::vector<float> magnitude_signal(const ComplexSignal &values);
    ErrorMetrics compute_real_error(const RealSignal &lhs, const RealSignal &rhs,
                                    float scale_factor = kDefaultMixedScale);
    ErrorMetrics compute_complex_error(const ComplexSignal &lhs, const ComplexSignal &rhs,
                                       float scale_factor = kDefaultMixedScale);

    template <typename T>
    ErrorMetrics compute_real_array_error(
        const cusignal::core::Tensor<T> &lhs,
        const cusignal::core::Tensor<T> &rhs,
        float scale_factor = kDefaultMixedScale)
    {
        if (lhs.shape != rhs.shape)
            throw std::invalid_argument("tensor shape mismatch");
        if constexpr (std::is_same_v<T, float>)
            return compute_real_error(lhs.values, rhs.values, scale_factor);
        else
            return compute_complex_error(lhs.values, rhs.values, scale_factor);
    }

    HostGpuArtifacts copy_host_artifacts(const CpuArtifacts &cpu);
    void write_spectrogram_breakdown_csv(const std::vector<StageTiming> &timings);
    void write_gpu_validation_timings_csv(const std::vector<StageTiming> &timings);

#if defined(__CUDACC__)
#define CUSIGNAL_TASK2_HOST_DEVICE __host__ __device__
#else
#define CUSIGNAL_TASK2_HOST_DEVICE
#endif

    namespace detail
    {
        CUSIGNAL_TASK2_HOST_DEVICE inline std::uint64_t task2_mix64(std::uint64_t value)
        {
            value ^= value >> 30U;
            value *= 0xbf58476d1ce4e5b9ULL;
            value ^= value >> 27U;
            value *= 0x94d049bb133111ebULL;
            value ^= value >> 31U;
            return value;
        }

        CUSIGNAL_TASK2_HOST_DEVICE inline float task2_uniform01(
            unsigned int seed,
            std::uint64_t sample_index)
        {
            const std::uint32_t bits = static_cast<std::uint32_t>(
                task2_mix64(static_cast<std::uint64_t>(seed) +
                            sample_index * 0x9e3779b97f4a7c15ULL) >> 40U);
            return (static_cast<float>(bits) + 0.5f) / 16777216.0f;
        }

        CUSIGNAL_TASK2_HOST_DEVICE inline float task2_normal(
            unsigned int seed,
            std::uint64_t sample_index)
        {
            constexpr float two_pi = 6.28318530717958647692f;
            const float u1 = task2_uniform01(seed, sample_index * 2U);
            const float u2 = task2_uniform01(seed, sample_index * 2U + 1U);
            return sqrtf(-2.0f * logf(u1)) * cosf(two_pi * u2);
        }
    }

#undef CUSIGNAL_TASK2_HOST_DEVICE

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
        cudaEvent_t start_event = nullptr;
        cudaEvent_t stop_event = nullptr;
        cusignal::core::throw_on_zx_gpu_error(cudaEventCreate(&start_event), "cudaEventCreate(start)");
        try
        {
            cusignal::core::throw_on_zx_gpu_error(cudaEventCreate(&stop_event), "cudaEventCreate(stop)");
            cusignal::core::throw_on_zx_gpu_error(cudaEventRecord(start_event), "cudaEventRecord(start)");
        }
        catch (...)
        {
            (void)cudaEventDestroy(start_event);
            throw;
        }

        const auto start = std::chrono::steady_clock::now();
        try
        {
            auto value = fn();
            cusignal::core::throw_on_zx_gpu_error(cudaEventRecord(stop_event), "cudaEventRecord(stop)");
            cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize");
            float kernel_ms = 0.0f;
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventElapsedTime(&kernel_ms, start_event, stop_event),
                "cudaEventElapsedTime");
            const auto end = std::chrono::steady_clock::now();
            const float elapsed_ms = std::chrono::duration<float, std::milli>(end - start).count();
            (void)cudaEventDestroy(stop_event);
            (void)cudaEventDestroy(start_event);
            return cusignal_demo::report::GpuMeasurement<decltype(value)>{
                std::move(value), elapsed_ms, kernel_ms};
        }
        catch (...)
        {
            if (stop_event != nullptr)
                (void)cudaEventDestroy(stop_event);
            (void)cudaEventDestroy(start_event);
            throw;
        }
    }
}
