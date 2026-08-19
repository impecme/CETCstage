#include "task1_common.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"
#include "cusignal/radartools/radartools.hpp"
#include "cusignal/waveforms/waveforms.hpp"
#include "../../src/common/zx_tile_policy.hpp"

namespace cusignal_demo::task1_radar
{
    namespace
    {
        constexpr int kThreadsPerBlock = 256;
        using cusignal::core::ZxGpuComplexArray;
        using cusignal::core::ZxGpuComplexSignal;
        using cusignal::core::ZxGpuRealSignal;
        using ZxGpuAmbgfunSurfaceResult = cusignal::radartools_api::ZxGpuAmbgfunSurfaceResult;
        namespace tile = cusignal::zx_tile;

        std::size_t block_count(std::size_t size, int threads)
        {
            return size == 0 ? 0 : (size + static_cast<std::size_t>(threads) - 1U) /
                static_cast<std::size_t>(threads);
        }

        tile::TaskTuningKey task_tuning_key(const ScenarioConfig &config)
        {
            return tile::make_task_key(
                tile::TaskScope::Task1Radar,
                "task1_radar",
                config.scale_level,
                {static_cast<std::size_t>(config.num_pulses),
                 static_cast<std::size_t>(config.samples_per_pulse),
                 static_cast<std::size_t>(config.template_length),
                 static_cast<std::size_t>(config.pulse_doppler_nfft), 0, 0},
                4,
                {static_cast<std::uint64_t>(config.delay_samples),
                 static_cast<std::uint64_t>(config.pulse_compression_nfft),
                 static_cast<std::uint64_t>(config.pulse_doppler_nfft),
                 tile::stable_string_hash(config.pulse_compression_window),
                 tile::stable_string_hash(config.pulse_doppler_window), 0, 0, 0, 0, 0},
                5,
                1);
        }

        void check_kernel_launch(const char *what)
        {
            cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), what);
        }

        __global__ void build_time_axis_kernel(float *output, std::size_t size, float step)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
            if (index < size)
                output[index] = step * static_cast<float>(index);
        }

        __global__ void build_rx_matrix_kernel(
            const float2 *templ,
            std::size_t template_length,
            int num_pulses,
            int samples_per_pulse,
            int delay_samples,
            float target_amplitude,
            float doppler_hz,
            float prf,
            float noise_sigma,
            unsigned int seed,
            float2 *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
            const std::size_t total = static_cast<std::size_t>(num_pulses) *
                static_cast<std::size_t>(samples_per_pulse);
            if (index >= total)
                return;

            const int pulse = static_cast<int>(index / static_cast<std::size_t>(samples_per_pulse));
            const int sample = static_cast<int>(index % static_cast<std::size_t>(samples_per_pulse));
            const float phase = 6.28318530717958647692f * doppler_hz * static_cast<float>(pulse) / prf;
            float sine = 0.0f;
            float cosine = 0.0f;
            sincosf(phase, &sine, &cosine);

            float real = noise_sigma * detail::task1_normal(seed, index * 2U);
            float imag = noise_sigma * detail::task1_normal(seed, index * 2U + 1U);
            const int template_index = sample - delay_samples;
            if (template_index >= 0 && static_cast<std::size_t>(template_index) < template_length)
            {
                const float2 value = templ[static_cast<std::size_t>(template_index)];
                real += target_amplitude * (value.x * cosine - value.y * sine);
                imag += target_amplitude * (value.x * sine + value.y * cosine);
            }
            output[index] = make_float2(real, imag);
        }

        GpuTaskInputs build_gpu_task_inputs_device(
            const ScenarioConfig &config,
            bool include_noise,
            StageTiming *chirp_timing = nullptr)
        {
            GpuTaskInputs inputs;
            ZxGpuRealSignal time(static_cast<std::size_t>(config.template_length), false);
            const int threads = tile::task_threads();
            build_time_axis_kernel<<<block_count(time.size(), threads), threads>>>(
                time.data(), time.size(), 1.0f / config.fs);
            check_kernel_launch("task1 build time axis");

            const cusignal::core::RealSignalLike time_like = time;
            auto waveform_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::waveforms::chirp(
                    time_like,
                    config.chirp_f0,
                    static_cast<float>(config.template_length - 1) / config.fs,
                    config.chirp_f1,
                    "linear",
                    0.0f,
                    true,
                    "complex");
            });
            const auto &waveform = waveform_measured.first;
            if (chirp_timing != nullptr)
            {
                *chirp_timing = {"waveforms/chirp", 0.0f, waveform_measured.second,
                                 waveform_measured.kernel_ms};
            }
            if (!std::holds_alternative<ZxGpuComplexSignal>(waveform))
                throw std::runtime_error("GPU chirp did not return complex output");
            inputs.tx_template = std::get<ZxGpuComplexSignal>(waveform);

            inputs.rx_matrix = ZxGpuComplexArray(
                Shape{static_cast<std::size_t>(config.num_pulses),
                      static_cast<std::size_t>(config.samples_per_pulse)},
                false);
            const float linear_snr = std::pow(10.0f, config.snr_db / 10.0f);
            const float noise_sigma = include_noise
                ? config.target_amplitude / std::sqrt(2.0f * linear_snr)
                : 0.0f;
            build_rx_matrix_kernel<<<block_count(inputs.rx_matrix.size(), threads), threads>>>(
                reinterpret_cast<const float2 *>(inputs.tx_template.data()),
                inputs.tx_template.size(),
                config.num_pulses,
                config.samples_per_pulse,
                config.delay_samples,
                config.target_amplitude,
                config.doppler_hz,
                config.prf,
                noise_sigma,
                config.seed,
                reinterpret_cast<float2 *>(inputs.rx_matrix.data()));
            check_kernel_launch("task1 build rx matrix");
            return inputs;
        }

        TaskInputs materialize_gpu_inputs(const GpuTaskInputs &inputs)
        {
            TaskInputs host;
            host.tx_template = inputs.tx_template.get();
            host.rx_matrix = inputs.rx_matrix.get();
            return host;
        }

        GpuTaskInputs upload_validation_inputs(const TaskInputs &host_inputs)
        {
            GpuTaskInputs inputs;
            inputs.tx_template = ZxGpuComplexSignal(host_inputs.tx_template);
            inputs.rx_matrix = ZxGpuComplexArray(host_inputs.rx_matrix);
            return inputs;
        }

        struct GpuArtifacts
        {
            ZxGpuComplexArray pulse_compression;
            ZxGpuComplexArray pulse_doppler;
            cusignal::core::ZxGpuRealArray range_doppler_power;
            cusignal::core::ZxGpuRealArray cfar_threshold;
            cusignal::core::ZxGpuRealArray cfar_detections;
            ZxGpuAmbgfunSurfaceResult ambgfun;
        };

        std::pair<GpuArtifacts, std::vector<StageTiming>> run_gpu_pipeline(
            const ScenarioConfig &config,
            const GpuTaskInputs &inputs)
        {
            std::vector<StageTiming> timings;
            GpuArtifacts artifacts;

            auto pulse = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::radartools::pulse_compression(
                    inputs.rx_matrix,
                    inputs.tx_template,
                    config.pulse_compression_normalize,
                    config.pulse_compression_window,
                    config.pulse_compression_nfft);
            });
            timings.push_back({"pulse_compression", 0.0f, pulse.second, pulse.kernel_ms});
            artifacts.pulse_compression = std::move(pulse.first);

            auto doppler = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::radartools::pulse_doppler_shifted(
                    artifacts.pulse_compression,
                    config.pulse_doppler_window,
                    config.pulse_doppler_nfft);
            });
            timings.push_back({"pulse_doppler", 0.0f, doppler.second, doppler.kernel_ms});
            artifacts.pulse_doppler = std::move(doppler.first);

            auto power = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::radartools::power_map(artifacts.pulse_doppler);
            });
            timings.push_back({"power_map", 0.0f, power.second, power.kernel_ms});
            artifacts.range_doppler_power = std::move(power.first);

            auto cfar = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::radartools::ca_cfar(
                    artifacts.range_doppler_power,
                    config.cfar_guard_cells,
                    config.cfar_reference_cells,
                    config.cfar_pfa);
            });
            timings.push_back({"ca_cfar", 0.0f, cfar.second, cfar.kernel_ms});
            artifacts.cfar_threshold = std::move(cfar.first.threshold);
            artifacts.cfar_detections = std::move(cfar.first.detections);

            auto ambgfun = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::radartools::ambgfun(
                    inputs.tx_template,
                    config.fs,
                    config.prf,
                    "2d",
                    0.0f);
            });
            timings.push_back({"ambgfun", 0.0f, ambgfun.second, ambgfun.kernel_ms});
            artifacts.ambgfun = std::get<ZxGpuAmbgfunSurfaceResult>(std::move(ambgfun.first));
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

    }

    void warmup_gpu_task(const ScenarioConfig &config)
    {
        const tile::TaskPolicyDecision task_tuning = tile::select_task(task_tuning_key(config));
        const tile::ScopedTaskPolicy task_scope(task_tuning);
        const GpuTaskInputs inputs = build_gpu_task_inputs_device(config, true);
        auto pipeline = run_gpu_pipeline(config, inputs);
        GpuArtifacts &artifacts = pipeline.first;
        auto detection = measure_gpu_ms([&]() {
            return cusignal::zx_gpu_backend::radartools::detect_peak(
                artifacts.range_doppler_power,
                artifacts.cfar_detections,
                config.pulse_doppler_nfft,
                config.prf);
        });
        (void)detection.first;
        cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "task1 warmup synchronize");
    }

    GpuTaskRun run_gpu_task(const ScenarioConfig &config)
    {
        const tile::TaskPolicyDecision task_tuning = tile::select_task(task_tuning_key(config));
        const tile::ScopedTaskPolicy task_scope(task_tuning);
        GpuTaskRun result;
        const bool trace_storage_reuse = environment_flag_enabled("CUSIGNAL_TASK1_TRACE_STORAGE_REUSE");
        const auto cache_before = cusignal::core::device_storage_cache_stats_snapshot();

        // Formal GPU E2E starts from a fresh device-generated input. Warmup is
        // performed by the caller, outside the measured repeat loop. No task
        // input is constructed on the host or copied H2D.
        StageTiming chirp_timing;
        auto input_measured = measure_gpu_ms([&]() {
            return build_gpu_task_inputs_device(config, true, &chirp_timing);
        });
        GpuTaskInputs inputs = std::move(input_measured.first);
        result.timings.push_back({"input_construction", 0.0f, input_measured.second,
                                  input_measured.kernel_ms});
        result.timings.push_back({"h2d", 0.0f, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});
        result.operator_timings.push_back(chirp_timing);

        auto pipeline = run_gpu_pipeline(config, inputs);
        GpuArtifacts gpu = std::move(pipeline.first);
        for (StageTiming &timing : pipeline.second)
        {
            result.timings.push_back(std::move(timing));
            if (result.timings.back().name == "pulse_compression")
                result.operator_timings.push_back({"radartools/pulse_compression", 0.0f,
                                                   result.timings.back().gpu_ms,
                                                   result.timings.back().gpu_kernel_ms});
            else if (result.timings.back().name == "pulse_doppler")
                result.operator_timings.push_back({"radartools/pulse_doppler", 0.0f,
                                                   result.timings.back().gpu_ms,
                                                   result.timings.back().gpu_kernel_ms});
            else if (result.timings.back().name == "ca_cfar")
                result.operator_timings.push_back({"radartools/ca_cfar", 0.0f,
                                                   result.timings.back().gpu_ms,
                                                   result.timings.back().gpu_kernel_ms});
            else if (result.timings.back().name == "ambgfun")
                result.operator_timings.push_back({"radartools/ambgfun", 0.0f,
                                                   result.timings.back().gpu_ms,
                                                   result.timings.back().gpu_kernel_ms});
        }

        auto detection_measured = measure_gpu_ms([&]() {
            return cusignal::zx_gpu_backend::radartools::detect_peak(
                gpu.range_doppler_power,
                gpu.cfar_detections,
                config.pulse_doppler_nfft,
                config.prf);
        });
        auto detection_host = measure_cpu_ms([&]() {
            return detection_measured.first.get();
        });
        result.detection = std::move(detection_host.first);
        result.timings.push_back({
            "final_detection",
            0.0f,
            detection_measured.second + detection_host.second,
            detection_measured.kernel_ms});

        auto output = measure_cpu_ms([&]() {
            return materialize_gpu_artifacts(gpu);
        });
        result.artifacts = std::move(output.first);
        auto validation_input = measure_cpu_ms([&]() { return materialize_gpu_inputs(inputs); });
        result.host_inputs = std::move(validation_input.first);
        result.validation_input_d2h_ms = validation_input.second;
        result.timings.push_back({"final_output", 0.0f, output.second,
                                  std::numeric_limits<float>::quiet_NaN()});

        if (trace_storage_reuse)
        {
            const auto cache_after_measured = cusignal::core::device_storage_cache_stats_snapshot();
            std::cerr << "[task1] cache_hits=" << cache_before.cache_hits << ','
                      << cache_after_measured.cache_hits
                      << " allocation_calls=" << cache_before.allocation_calls << ','
                      << cache_after_measured.allocation_calls
                      << " cached_bytes=" << cache_before.cached_bytes << ','
                      << cache_after_measured.cached_bytes << '\n';
        }
        return result;
    }

    GpuValidationRun run_gpu_validation(const ScenarioConfig &config, const TaskInputs &host_inputs)
    {
        const tile::TaskPolicyDecision task_tuning = tile::select_task(task_tuning_key(config));
        const tile::ScopedTaskPolicy task_scope(task_tuning);
        GpuValidationRun result;
        auto upload = measure_cpu_ms([&]() { return upload_validation_inputs(host_inputs); });
        GpuTaskInputs inputs = std::move(upload.first);
        result.timings.push_back({"validation_h2d", 0.0f, upload.second,
                                  std::numeric_limits<float>::quiet_NaN()});

        auto pipeline = run_gpu_pipeline(config, inputs);
        GpuArtifacts artifacts = std::move(pipeline.first);
        result.timings.insert(result.timings.end(), pipeline.second.begin(), pipeline.second.end());

        auto detection = measure_gpu_ms([&]() {
            return cusignal::zx_gpu_backend::radartools::detect_peak(
                artifacts.range_doppler_power,
                artifacts.cfar_detections,
                config.pulse_doppler_nfft,
                config.prf);
        });
        result.detection = detection.first.get();
        result.timings.push_back({"validation_detection", 0.0f, detection.second, detection.kernel_ms});
        auto output = measure_cpu_ms([&]() { return materialize_gpu_artifacts(artifacts); });
        result.artifacts = std::move(output.first);
        result.timings.push_back({"validation_d2h", 0.0f, output.second,
                                  std::numeric_limits<float>::quiet_NaN()});
        return result;
    }
}
