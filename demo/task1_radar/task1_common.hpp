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
#include <utility>
#include <vector>

#include <cuda_runtime_api.h>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"
#include "cusignal/radartools/radartools.hpp"

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
    using DetectionSummary = cusignal::radartools_api::DetectionSummary;
    using cusignal_demo::report::ErrorMetrics;
    using StageTiming = cusignal_demo::report::StageTiming;

    struct ScenarioConfig
    {
        int scale_level = 3;
        bool unified_scale_protocol = false;
        int warmup_runs = 0;
        float fs = 1.0e6f;
        int num_pulses = 64;
        int samples_per_pulse = 256;
        int template_length = 64;
        float prf = 2000.0f;
        int delay_samples = 48;
        float doppler_hz = 125.0f;
        float target_amplitude = 1.0f;
        float snr_db = 20.0f;
        unsigned int seed = 20260414u;
        float chirp_f0 = 5.0e4f;
        float chirp_f1 = 2.0e5f;
        bool pulse_compression_normalize = true;
        std::string pulse_compression_window;
        std::string pulse_doppler_window = "hann";
        int pulse_compression_nfft = 256;
        int pulse_doppler_nfft = 64;
        Shape cfar_guard_cells{2, 2};
        Shape cfar_reference_cells{8, 8};
        float cfar_pfa = 1.0e-3f;
    };

    struct DemoOptions
    {
        int warmup = 0;
        int repeat = 1;
        int scale_level = 6;
        bool all_scale_levels = false;
        std::optional<int> num_pulses;
        std::optional<int> samples_per_pulse;
        std::optional<int> template_length;
        std::optional<int> pulse_compression_nfft;
        std::optional<int> pulse_doppler_nfft;
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
        float gpu_total_baseline_ms = 0.80f;
        float gpu_total_multiplier = 1.25f;
        float gpu_total_hard_limit_ms = 1.0f;
        float pulse_compression_mixed = 1.0e-4f;
        float pulse_doppler_mixed = 1.0e-4f;
        float cfar_threshold_mixed = 5.0e-3f;
        // The ZQ500 ambiguity surface path is float32; the observed maximum
        // relative discrepancy is below 2e-4 while max_abs remains below 6e-6.
        float ambgfun_surface_mixed = 2.0e-4f;
        float timing_relative_jitter = 0.35f;
        float gpu_free_drift_mib = 32.0f;
        float rss_current_drift_mib = 64.0f;
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

    struct HostGpuArtifacts
    {
        ComplexArray pulse_compression;
        ComplexArray pulse_doppler;
        RealArray range_doppler_power;
        RealArray cfar_threshold;
        RealArray cfar_detections;
        AmbgfunSurfaceResult ambgfun;
    };

    struct GpuTaskInputs
    {
        cusignal::core::ZxGpuComplexSignal tx_template;
        cusignal::core::ZxGpuComplexArray rx_matrix;
    };

    struct TaskInputs
    {
        ComplexSignal tx_template;
        ComplexArray rx_matrix;
    };

    struct CpuTaskRun
    {
        TaskInputs inputs;
        CpuArtifacts artifacts;
        DetectionSummary detection;
        std::vector<StageTiming> timings;
        // Canonical registered public-operator timings. Task stages and
        // private helpers remain in `timings` and are never counted here.
        std::vector<StageTiming> operator_timings;
    };

    struct CpuValidationRun
    {
        CpuArtifacts artifacts;
        DetectionSummary detection;
    };

    struct GpuTaskRun
    {
        TaskInputs host_inputs;
        HostGpuArtifacts artifacts;
        DetectionSummary detection;
        std::vector<StageTiming> timings;
        std::vector<StageTiming> operator_timings;
        float validation_input_d2h_ms = 0.0f;
    };

    struct GpuValidationRun
    {
        HostGpuArtifacts artifacts;
        DetectionSummary detection;
        std::vector<StageTiming> timings;
    };

    struct DemoRunResult
    {
        TaskInputs task_inputs;
        CpuArtifacts cpu;
        HostGpuArtifacts gpu;
        DetectionSummary expected_detection;
        DetectionSummary cpu_detection;
        DetectionSummary gpu_detection;
        HostGpuArtifacts gpu_operator_validation;
        std::vector<StageTiming> stage_timings;
        std::vector<StageTiming> operator_timings;
        ErrorMetrics input_template_error;
        ErrorMetrics input_rx_error;
        ErrorMetrics pulse_compression_error;
        ErrorMetrics pulse_doppler_error;
        ErrorMetrics cfar_threshold_error;
        ErrorMetrics ambgfun_error;
        ErrorMetrics pulse_compression_e2e_error;
        ErrorMetrics pulse_doppler_e2e_error;
        ErrorMetrics cfar_threshold_e2e_error;
        ErrorMetrics ambgfun_e2e_error;
        float validation_input_d2h_ms = 0.0f;
        float cpu_total_ms = 0.0f;
        float gpu_total_ms = 0.0f;
        // Median of the per-repeat sum of CUDA-event stage timings.  This is
        // deliberately kept separate from the sum of per-stage medians.
        float gpu_kernel_total_ms = 0.0f;
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

    bool environment_flag_enabled(const char *name);
    ResourceSnapshot capture_resource_snapshot();
    float gpu_kernel_total_ms(const std::vector<StageTiming> &timings);

#if defined(__CUDACC__)
#define CUSIGNAL_TASK1_HOST_DEVICE __host__ __device__
#else
#define CUSIGNAL_TASK1_HOST_DEVICE
#endif

    namespace detail
    {
        CUSIGNAL_TASK1_HOST_DEVICE inline std::uint64_t task1_mix64(std::uint64_t value)
        {
            value ^= value >> 30U;
            value *= 0xbf58476d1ce4e5b9ULL;
            value ^= value >> 27U;
            value *= 0x94d049bb133111ebULL;
            value ^= value >> 31U;
            return value;
        }

        CUSIGNAL_TASK1_HOST_DEVICE inline float task1_uniform01(
            unsigned int seed,
            std::uint64_t sample_index)
        {
            const std::uint32_t bits = static_cast<std::uint32_t>(
                task1_mix64(static_cast<std::uint64_t>(seed) + sample_index * 0x9e3779b97f4a7c15ULL) >> 40U);
            return (static_cast<float>(bits) + 0.5f) / 16777216.0f;
        }

        CUSIGNAL_TASK1_HOST_DEVICE inline float task1_normal(
            unsigned int seed,
            std::uint64_t sample_index)
        {
            constexpr float two_pi = 6.28318530717958647692f;
            const float u1 = task1_uniform01(seed, sample_index * 2U);
            const float u2 = task1_uniform01(seed, sample_index * 2U + 1U);
            return sqrtf(-2.0f * logf(u1)) * cosf(two_pi * u2);
        }
    }

#undef CUSIGNAL_TASK1_HOST_DEVICE

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
