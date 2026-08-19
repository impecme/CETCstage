#include "task2_common.hpp"
#include "task2_features_zx_gpu.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <initializer_list>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>

#include <cuda_runtime_api.h>

#include "cusignal/bsplines/bsplines.hpp"
#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"
#include "cusignal/correlate/correlate.hpp"
#include "cusignal/demod/demod.hpp"
#include "cusignal/filter_design/filter_design.hpp"
#include "cusignal/filtering/filtering.hpp"
#include "cusignal/spectral/spectral.hpp"
#include "cusignal/wavelets/wavelets.hpp"
#include "cusignal/windows/windows.hpp"
#include "cusignal/waveforms/waveforms.hpp"
#include "../../src/common/zx_tile_policy.hpp"

namespace cusignal_demo::task2_features
{
    namespace
    {
        constexpr int kThreadsPerBlock = 256;
        using cusignal::core::ZxGpuComplexArray;
        using cusignal::core::ZxGpuComplexSignal;
        using cusignal::core::ZxGpuRealArray;
        using cusignal::core::ZxGpuRealSignal;
        namespace tile = cusignal::zx_tile;

        struct GpuPipelineInputs
        {
            RealSignal widths_host;
            ZxGpuRealSignal widths;
            ZxGpuRealSignal bspline_weights;
            ZxGpuRealSignal taps;
            ZxGpuComplexArray target_template;
            ZxGpuComplexArray rx_frames;
        };

        struct GpuArtifacts
        {
            ZxGpuComplexArray filtered;
            ZxGpuRealArray demod_scores;
            ZxGpuRealArray correlate_scores;
            ZxGpuRealArray spectrogram_values;
            ZxGpuRealSignal spectrogram_freqs;
            ZxGpuRealSignal spectrogram_times;
            ZxGpuComplexArray cwt_values;
            ZxGpuRealArray feature_scores;
            ZxGpuRealSignal peak_track;
            ZxGpuRealSignal measurement_values;
            ZxGpuRealSignal kalman_track;
        };

        std::size_t block_count(std::size_t size, int threads)
        {
            return size == 0 ? 0 : (size + static_cast<std::size_t>(threads) - 1U) /
                static_cast<std::size_t>(threads);
        }

        tile::TaskTuningKey task_tuning_key(const ScenarioConfig &config)
        {
            return tile::make_task_key(
                tile::TaskScope::Task2Features,
                "task2_features",
                config.scale_level,
                {static_cast<std::size_t>(config.num_frames),
                 static_cast<std::size_t>(config.samples_per_frame),
                 static_cast<std::size_t>(config.template_length),
                 static_cast<std::size_t>(config.filter_numtaps),
                 static_cast<std::size_t>(config.spectrogram_nperseg),
                 static_cast<std::size_t>(config.spectrogram_nfft)},
                6,
                {static_cast<std::uint64_t>(config.spectrogram_noverlap),
                 static_cast<std::uint64_t>(config.peak_order),
                 static_cast<std::uint64_t>(config.representative_frame_index),
                 0, 0, 0, 0, 0, 0, 0},
                3,
                1);
        }

        void check_kernel_launch(const char *what)
        {
            cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), what);
        }

        __global__ void fill_widths_kernel(float *output, std::size_t size, float start, float step)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
            if (index < size)
                output[index] = start + step * static_cast<float>(index);
        }

        __global__ void fill_cutoff_kernel(float *output, float low, float high)
        {
            if (threadIdx.x == 0 && blockIdx.x == 0)
            {
                output[0] = low;
                output[1] = high;
            }
        }

        __global__ void build_time_axis_kernel(
            float *output,
            std::size_t size,
            float start,
            float step)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
            if (index < size)
                output[index] = start + step * static_cast<float>(index);
        }

        __global__ void build_target_template_kernel(
            const float2 *chirp,
            const float *envelope,
            std::size_t size,
            float2 *output)
        {
            if (blockIdx.x != 0 || threadIdx.x != 0)
                return;
            float maximum = 0.0f;
            for (std::size_t index = 0; index < size; ++index)
            {
                const float2 value = chirp[index];
                maximum = fmaxf(maximum, envelope[index] * sqrtf(value.x * value.x + value.y * value.y));
            }
            maximum = maximum > 1.0e-12f ? maximum : 1.0f;
            for (std::size_t index = 0; index < size; ++index)
            {
                const float2 value = chirp[index];
                const float scale = envelope[index] / maximum;
                output[index] = make_float2(value.x * scale, value.y * scale);
            }
        }

        __global__ void build_interferer_phase_kernel(
            float *phase,
            float *phase_alt,
            std::size_t size,
            float fs,
            float f0,
            float f1)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
            if (index >= size)
                return;
            const float time = static_cast<float>(index) / fs;
            phase[index] = 6.28318530717958647692f * f0 * time;
            phase_alt[index] = 6.28318530717958647692f * f1 * time;
        }

        __global__ void combine_interferer_kernel(
            const float *saw,
            const float *square,
            std::size_t size,
            float amplitude,
            float2 *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
            if (index >= size)
                return;
            output[index] = make_float2(
                amplitude * (0.7f * saw[index] + 0.3f * square[index]),
                amplitude * (0.25f * square[index]));
        }

        __global__ void build_rx_frames_kernel(
            const float2 *target_template,
            std::size_t template_length,
            const float2 *interferer,
            std::size_t interferer_length,
            int num_frames,
            int samples_per_frame,
            int target_start_sample_0,
            int target_step_per_frame,
            int interferer_start_sample,
            float target_amplitude,
            float noise_sigma,
            unsigned int seed,
            float2 *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
            const std::size_t total = static_cast<std::size_t>(num_frames) *
                static_cast<std::size_t>(samples_per_frame);
            if (index >= total)
                return;
            const int frame = static_cast<int>(index / static_cast<std::size_t>(samples_per_frame));
            const int sample = static_cast<int>(index % static_cast<std::size_t>(samples_per_frame));
            float real = noise_sigma * detail::task2_normal(seed, index * 2U);
            float imag = noise_sigma * detail::task2_normal(seed, index * 2U + 1U);
            const int target_index = sample - (target_start_sample_0 + frame * target_step_per_frame);
            if (target_index >= 0 && static_cast<std::size_t>(target_index) < template_length)
            {
                const float2 value = target_template[static_cast<std::size_t>(target_index)];
                real += target_amplitude * value.x;
                imag += target_amplitude * value.y;
            }
            const int interferer_index = sample - interferer_start_sample;
            if (interferer_index >= 0 && static_cast<std::size_t>(interferer_index) < interferer_length)
            {
                const float2 value = interferer[static_cast<std::size_t>(interferer_index)];
                real += value.x;
                imag += value.y;
            }
            output[index] = make_float2(real, imag);
        }

        GpuPipelineInputs build_gpu_pipeline_parameters_device(
            const ScenarioConfig &config,
            std::vector<StageTiming> *operator_timings = nullptr);

        void build_gpu_signal_inputs_device(
            const ScenarioConfig &config,
            GpuPipelineInputs &inputs,
            std::vector<StageTiming> *operator_timings = nullptr)
        {
            const float template_step = 1.0f / config.fs;
            const float template_t1 = static_cast<float>(config.template_length - 1) / config.fs;
            ZxGpuRealSignal time(static_cast<std::size_t>(config.template_length), false);
            ZxGpuRealSignal env_time(static_cast<std::size_t>(config.template_length), false);
            build_time_axis_kernel<<<block_count(time.size(), tile::task_threads()), tile::task_threads()>>>(
                time.data(), time.size(), 0.0f, template_step);
            build_time_axis_kernel<<<block_count(env_time.size(), tile::task_threads()), tile::task_threads()>>>(
                env_time.data(), env_time.size(), -0.5f * template_t1, template_step);
            check_kernel_launch("task2 build target time axes");

            const cusignal::core::RealSignalLike time_like = time;
            const cusignal::core::RealSignalLike env_time_like = env_time;
            auto chirp_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::waveforms::chirp(
                    time_like, config.chirp_f0, template_t1, config.chirp_f1,
                    "linear", 0.0f, true, "complex");
            });
            auto gauss_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::waveforms::gausspulse(
                    env_time_like, config.gausspulse_fc, 0.5f, -6.0f, -40.0f, false, true);
            });
            const auto &chirp = chirp_measured.first;
            const auto &gauss = gauss_measured.first;
            if (operator_timings != nullptr)
            {
                operator_timings->push_back({"waveforms/chirp", 0.0f, chirp_measured.second,
                                             chirp_measured.kernel_ms});
                operator_timings->push_back({"waveforms/gausspulse", 0.0f, gauss_measured.second,
                                             gauss_measured.kernel_ms});
            }
            if (!std::holds_alternative<ZxGpuComplexSignal>(chirp) ||
                !std::holds_alternative<cusignal::waveforms_api::ZxGpuIEnvWaveform>(gauss))
                throw std::runtime_error("GPU target waveform returned an unexpected type");
            const ZxGpuComplexSignal chirp_signal = std::get<ZxGpuComplexSignal>(chirp);
            const ZxGpuRealSignal envelope =
                std::get<cusignal::waveforms_api::ZxGpuIEnvWaveform>(gauss).envelope;
            inputs.target_template = ZxGpuComplexArray(
                Shape{static_cast<std::size_t>(config.template_length)}, false);
            build_target_template_kernel<<<1, 1>>>(
                reinterpret_cast<const float2 *>(chirp_signal.data()),
                envelope.data(),
                envelope.size(),
                reinterpret_cast<float2 *>(inputs.target_template.data()));
            check_kernel_launch("task2 build target template");

            ZxGpuRealSignal phase(static_cast<std::size_t>(config.interferer_length), false);
            ZxGpuRealSignal phase_alt(static_cast<std::size_t>(config.interferer_length), false);
            build_interferer_phase_kernel<<<block_count(phase.size(), tile::task_threads()), tile::task_threads()>>>(
                phase.data(), phase_alt.data(), phase.size(), config.fs,
                config.interferer_f0, config.interferer_f1);
            check_kernel_launch("task2 build interferer phases");
            const cusignal::core::RealSignalLike phase_like = phase;
            const cusignal::core::RealSignalLike phase_alt_like = phase_alt;
            auto saw_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::waveforms::sawtooth(phase_like, 0.7f);
            });
            auto square_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::waveforms::square(phase_alt_like, 0.35f);
            });
            if (operator_timings != nullptr)
            {
                operator_timings->push_back({"waveforms/sawtooth", 0.0f, saw_measured.second,
                                             saw_measured.kernel_ms});
                operator_timings->push_back({"waveforms/square", 0.0f, square_measured.second,
                                             square_measured.kernel_ms});
            }
            const ZxGpuRealSignal saw = std::move(saw_measured.first);
            const ZxGpuRealSignal square = std::move(square_measured.first);
            ZxGpuComplexSignal interferer(static_cast<std::size_t>(config.interferer_length), false);
            combine_interferer_kernel<<<block_count(interferer.size(), tile::task_threads()), tile::task_threads()>>>(
                saw.data(), square.data(), interferer.size(), config.interferer_amplitude,
                reinterpret_cast<float2 *>(interferer.data()));
            check_kernel_launch("task2 build interferer");

            inputs.rx_frames = ZxGpuComplexArray(
                Shape{static_cast<std::size_t>(config.num_frames),
                      static_cast<std::size_t>(config.samples_per_frame)}, false);
            const float linear_snr = std::pow(10.0f, config.snr_db / 10.0f);
            const float noise_sigma = config.target_amplitude / std::sqrt(2.0f * linear_snr);
            build_rx_frames_kernel<<<block_count(inputs.rx_frames.size(), tile::task_threads()), tile::task_threads()>>>(
                reinterpret_cast<const float2 *>(inputs.target_template.data()),
                inputs.target_template.size(),
                reinterpret_cast<const float2 *>(interferer.data()),
                interferer.size(),
                config.num_frames,
                config.samples_per_frame,
                config.target_start_sample_0,
                config.target_step_per_frame,
                config.interferer_start_sample,
                config.target_amplitude,
                noise_sigma,
                config.seed,
                reinterpret_cast<float2 *>(inputs.rx_frames.data()));
            check_kernel_launch("task2 build rx frames");
        }

        TaskInputs materialize_gpu_inputs(const GpuPipelineInputs &inputs)
        {
            TaskInputs host;
            host.target_template = inputs.target_template.get().values;
            host.rx_frames = inputs.rx_frames.get();
            return host;
        }

        __global__ void normalize_weights_kernel(
            const float *input,
            float *output,
            std::size_t size)
        {
            if (blockIdx.x != 0 || threadIdx.x != 0)
                return;
            float sum = 0.0f;
            for (std::size_t index = 0; index < size; ++index)
                sum += input[index];
            const float scale = sum > 1.0e-12f ? sum : 1.0f;
            for (std::size_t index = 0; index < size; ++index)
                output[index] = input[index] / scale;
        }

        GpuPipelineInputs build_gpu_pipeline_parameters_device(
            const ScenarioConfig &config,
            std::vector<StageTiming> *operator_timings)
        {
            GpuPipelineInputs inputs;
            inputs.widths_host = even_range(4.0f, 32.0f, 2.0f);
            inputs.widths = ZxGpuRealSignal(inputs.widths_host.size(), false);
            fill_widths_kernel<<<block_count(inputs.widths.size(), tile::task_threads()), tile::task_threads()>>>(
                inputs.widths.data(), inputs.widths.size(), 4.0f, 2.0f);
            check_kernel_launch("task2 fill widths");

            ZxGpuRealArray offsets(Shape{5}, false);
            fill_widths_kernel<<<1, 5>>>(offsets.data(), offsets.size(), -2.0f, 1.0f);
            check_kernel_launch("task2 fill bspline offsets");
            const cusignal::core::RealArrayLike offsets_like(offsets);
            auto bspline_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::bsplines::cubic(offsets_like);
            });
            const ZxGpuRealArray weights_array = std::move(bspline_measured.first);
            if (operator_timings != nullptr)
                operator_timings->push_back({"bsplines/cubic", 0.0f, bspline_measured.second,
                                             bspline_measured.kernel_ms});
            inputs.bspline_weights = ZxGpuRealSignal(weights_array.size(), false);
            normalize_weights_kernel<<<1, 1>>>(
                weights_array.data(), inputs.bspline_weights.data(), weights_array.size());
            check_kernel_launch("task2 normalize bspline weights");

            ZxGpuRealSignal cutoff(2, false);
            fill_cutoff_kernel<<<1, 1>>>(cutoff.data(), config.filter_low, config.filter_high);
            check_kernel_launch("task2 fill filter cutoff");
            const cusignal::core::RealSignalLike cutoff_like(cutoff);
            auto firwin_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::filter_design::firwin(
                    config.filter_numtaps, cutoff_like, -1.0f,
                    cusignal::core::NamedFloatParameter{"kaiser", 8.0f},
                    std::string("bandpass"), true, -1.0f, config.fs);
            });
            inputs.taps = std::move(firwin_measured.first);
            if (operator_timings != nullptr)
                operator_timings->push_back({"filter_design/firwin", 0.0f, firwin_measured.second,
                                             firwin_measured.kernel_ms});

            return inputs;
        }

        GpuPipelineInputs upload_gpu_task_inputs(
            GpuPipelineInputs inputs,
            const TaskInputs &host_inputs)
        {
            inputs.target_template = ZxGpuComplexArray(as_complex_array(host_inputs.target_template));
            inputs.rx_frames = ZxGpuComplexArray(host_inputs.rx_frames);
            return inputs;
        }

        std::pair<GpuArtifacts, std::vector<StageTiming>> run_gpu_pipeline(
            const ScenarioConfig &config,
            const GpuPipelineInputs &inputs,
            std::vector<StageTiming> *operator_timings = nullptr)
        {
            GpuArtifacts artifacts;
            std::vector<StageTiming> timings;
            const auto sum_kernel = [](std::initializer_list<float> samples) {
                float total = 0.0f;
                for (const float sample : samples)
                {
                    if (!std::isfinite(sample) || sample <= 0.0f)
                        return std::numeric_limits<float>::quiet_NaN();
                    total += sample;
                }
                return total;
            };
            ZxGpuRealArray filtered_real;
            auto filtered = measure_gpu_ms([&]() {
                if (config.num_frames >= 48 && config.samples_per_frame >= 1024 &&
                    config.filter_numtaps >= 129 && task2_fixed_fft_filter_enabled_zx_gpu())
                {
                    return complex_firfilter_zx_gpu(inputs.rx_frames, inputs.taps, filtered_real);
                }
                ZxGpuComplexArray result = cusignal::zx_gpu_backend::filtering::firfilter(
                    inputs.taps, inputs.rx_frames, -1);
                filtered_real = extract_real_part_zx_gpu(result);
                return result;
            });
            artifacts.filtered = std::move(filtered.first);
            timings.push_back({"filter", 0.0f, filtered.second, filtered.kernel_ms});
            if (operator_timings != nullptr)
                operator_timings->push_back({"filtering/firfilter", 0.0f, filtered.second,
                                             filtered.kernel_ms});

            const Shape frame_shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)};
            artifacts.correlate_scores = cusignal::core::make_zx_gpu_real_array(frame_shape, 0.0f);
            artifacts.feature_scores = cusignal::core::make_zx_gpu_real_array(frame_shape, 0.0f);
            artifacts.peak_track = cusignal::core::make_zx_gpu_real_signal(static_cast<std::size_t>(config.num_frames), 0.0f);
            ZxGpuRealArray wavelet_scores = cusignal::core::make_zx_gpu_real_array(frame_shape, 0.0f);
            ZxGpuRealArray spectrogram_scores = cusignal::core::make_zx_gpu_real_array(frame_shape, 0.0f);

            auto demod = measure_gpu_ms([&]() { return batched_demod_score_zx_gpu(artifacts.filtered); });
            artifacts.demod_scores = std::move(demod.first);
            auto raw_corr = measure_gpu_ms([&]() {
                return batched_correlate_score_zx_gpu(artifacts.filtered, inputs.target_template);
            });
            auto norm_corr = measure_gpu_ms([&]() { return normalize_rows_nonnegative_zx_gpu(raw_corr.first); });
            artifacts.correlate_scores = std::move(norm_corr.first);
            const float correlate_ms = raw_corr.second + norm_corr.second;
            const float correlate_kernel_ms = sum_kernel({raw_corr.kernel_ms, norm_corr.kernel_ms});

            auto window_measured = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::windows::get_window(
                    std::string("hann"), config.spectrogram_nperseg, true);
            });
            const ZxGpuRealSignal window = std::move(window_measured.first);

            auto raw_spectrogram = measure_gpu_ms([&]() {
                return direct_spectrogram_band_score_zx_gpu(
                    filtered_real, window, config.spectrogram_nperseg,
                    config.spectrogram_noverlap, config.spectrogram_nfft,
                    config.filter_low, config.filter_high, config.fs);
            });
            auto norm_spectrogram = measure_gpu_ms([&]() {
                return normalize_rows_nonnegative_zx_gpu(raw_spectrogram.first);
            });
            spectrogram_scores = std::move(norm_spectrogram.first);
            std::vector<StageTiming> spectrogram_breakdown{
                {"direct_band_score", 0.0f, raw_spectrogram.second},
                {"row_normalize", 0.0f, norm_spectrogram.second}};

            const ZxGpuRealArray representative_frame_real = extract_row_real_zx_gpu(
                filtered_real, config.representative_frame_index);
            auto representative_spectrogram = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::spectral::spectrogram(
                    representative_frame_real, config.fs, window,
                    config.spectrogram_nperseg, config.spectrogram_noverlap,
                    config.spectrogram_nfft, std::string("constant"), true,
                    "spectrum", -1, "magnitude");
            });
            auto spectrogram_result = std::move(representative_spectrogram.first);
            if (!std::holds_alternative<ZxGpuRealArray>(spectrogram_result.values))
                throw std::runtime_error("gpu spectrogram did not return real values");
            artifacts.spectrogram_values = std::get<ZxGpuRealArray>(spectrogram_result.values);
            artifacts.spectrogram_freqs = spectrogram_result.frequencies;
            artifacts.spectrogram_times = spectrogram_result.times;

            auto raw_cwt = measure_gpu_ms([&]() {
                return batched_cwt_max_score_zx_gpu(filtered_real, inputs.widths_host);
            });
            auto norm_cwt = measure_gpu_ms([&]() { return normalize_rows_nonnegative_zx_gpu(raw_cwt.first); });
            wavelet_scores = std::move(norm_cwt.first);
            const ZxGpuRealSignal representative_cwt = extract_row_real_signal_zx_gpu(
                filtered_real, config.representative_frame_index);
            auto representative_cwt_result = measure_gpu_ms([&]() {
                return cusignal::zx_gpu_backend::wavelets::cwt(representative_cwt, "morlet2", inputs.widths);
            });
            artifacts.cwt_values = std::move(representative_cwt_result.first);

            auto fusion = measure_gpu_ms([&]() {
                FusionKernelTiming kernel_timing;
                fuse_feature_scores_zx_gpu(
                    artifacts.correlate_scores, artifacts.demod_scores, wavelet_scores,
                    spectrogram_scores, inputs.bspline_weights, config.peak_order,
                    artifacts.feature_scores, artifacts.peak_track, &kernel_timing);
                if (operator_timings != nullptr)
                {
                    operator_timings->push_back({"peak_finding/argrelmax", 0.0f,
                                                 kernel_timing.peak_ms, kernel_timing.peak_ms});
                }
                return 0;
            });

            timings.push_back({"demod", 0.0f, demod.second, demod.kernel_ms});
            // The task stage remains a separate aggregate; the public rows
            // below point only to the actual registered API/variant work.
            timings.push_back({"correlate", 0.0f, correlate_ms, correlate_kernel_ms});
            timings.push_back({"spectrogram", 0.0f,
                               window_measured.second + raw_spectrogram.second + norm_spectrogram.second,
                               sum_kernel({window_measured.kernel_ms, raw_spectrogram.kernel_ms,
                                           norm_spectrogram.kernel_ms})});
            spectrogram_breakdown.push_back(
                {"representative_spectrogram", 0.0f, representative_spectrogram.second});
            write_spectrogram_breakdown_csv(spectrogram_breakdown);
            write_gpu_validation_timings_csv({
                {"representative_spectrogram", 0.0f, representative_spectrogram.second},
                {"representative_cwt", 0.0f, representative_cwt_result.second}});
            timings.push_back({"cwt", 0.0f,
                               raw_cwt.second + norm_cwt.second,
                               sum_kernel({raw_cwt.kernel_ms, norm_cwt.kernel_ms})});
            timings.push_back({"feature_fusion", 0.0f, fusion.second, fusion.kernel_ms});

            if (operator_timings != nullptr)
            {
                operator_timings->push_back({"demod/fm_demod", 0.0f, demod.second, demod.kernel_ms});
                operator_timings->push_back({"correlate/correlate", 0.0f, correlate_ms, correlate_kernel_ms});
                operator_timings->push_back({"windows/get_window", 0.0f, window_measured.second,
                                             window_measured.kernel_ms});
                operator_timings->push_back({"spectral/spectrogram", 0.0f,
                                             raw_spectrogram.second + norm_spectrogram.second,
                                             sum_kernel({raw_spectrogram.kernel_ms, norm_spectrogram.kernel_ms})});
                operator_timings->push_back({"wavelets/cwt", 0.0f,
                                             raw_cwt.second + norm_cwt.second,
                                             sum_kernel({raw_cwt.kernel_ms, norm_cwt.kernel_ms})});
            }

            // Keep public operator rows separate from the helper-only stage
            // timings. Representative spectrogram/CWT calls are validation
            // probes and are intentionally excluded from formal E2E timing.

            auto measurement = measure_gpu_ms([&]() {
                return copy_measurement_track_zx_gpu(artifacts.peak_track);
            });
            artifacts.measurement_values = std::move(measurement.first);
            timings.push_back({"measurement_conversion", 0.0f, measurement.second, measurement.kernel_ms});

            auto kalman = measure_gpu_ms([&]() {
                return kalman_track_from_peaks_zx_gpu(artifacts.measurement_values);
            });
            artifacts.kalman_track = std::move(kalman.first);
            timings.push_back({"kalman", 0.0f, kalman.second, kalman.kernel_ms});
            if (operator_timings != nullptr)
                operator_timings->push_back({"estimation/kalman_filter", 0.0f,
                                             kalman.second, kalman.kernel_ms});
            return std::make_pair(std::move(artifacts), std::move(timings));
        }

        HostGpuArtifacts materialize_gpu_artifacts(const GpuArtifacts &gpu)
        {
            HostGpuArtifacts output;
            output.filtered = gpu.filtered.get();
            output.demod_scores = gpu.demod_scores.get();
            output.correlate_scores = gpu.correlate_scores.get();
            output.spectrogram_values = gpu.spectrogram_values.get();
            output.spectrogram_freqs = gpu.spectrogram_freqs.get();
            output.spectrogram_times = gpu.spectrogram_times.get();
            output.cwt_values = gpu.cwt_values.get();
            output.feature_scores = gpu.feature_scores.get();
            output.peak_track = gpu.peak_track.get();
            output.measurement_values = gpu.measurement_values.get();
            output.kalman_track = gpu.kalman_track.get();
            return output;
        }
    }

    void warmup_gpu_task(const ScenarioConfig &config)
    {
        const tile::TaskPolicyDecision task_tuning = tile::select_task(task_tuning_key(config));
        const tile::ScopedTaskPolicy task_scope(task_tuning);
        GpuPipelineInputs inputs = build_gpu_pipeline_parameters_device(config);
        build_gpu_signal_inputs_device(config, inputs);
        auto warmup = run_gpu_pipeline(config, inputs);
        (void)warmup;
        cusignal::core::throw_on_zx_gpu_error(cudaDeviceSynchronize(), "task2 warmup synchronize");
    }

    GpuTaskRun run_gpu_task(const ScenarioConfig &config)
    {
        const tile::TaskPolicyDecision task_tuning = tile::select_task(task_tuning_key(config));
        const tile::ScopedTaskPolicy task_scope(task_tuning);
        GpuTaskRun result;

        // Formal GPU E2E starts from a fresh device-generated input. Warmup is
        // performed by the caller, outside the measured repeat loop. No task
        // input is constructed on the host or copied H2D.
        auto parameters = measure_gpu_ms([&]() {
            return build_gpu_pipeline_parameters_device(config, &result.operator_timings);
        });
        GpuPipelineInputs device_inputs = std::move(parameters.first);
        auto input_measured = measure_gpu_ms([&]() {
            build_gpu_signal_inputs_device(config, device_inputs, &result.operator_timings);
            return 0;
        });
        result.timings.push_back({"input_construction", 0.0f, input_measured.second,
                                  input_measured.kernel_ms});
        result.timings.push_back({"h2d", 0.0f, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        // Parameter preparation is part of input construction, not filter
        // execution. Keep one stage so task E2E and per-stage reports have the
        // same accounting boundary.
        result.timings.front().gpu_ms += parameters.second;
        if (std::isfinite(parameters.kernel_ms))
        {
            if (!std::isfinite(result.timings.front().gpu_kernel_ms))
                result.timings.front().gpu_kernel_ms = 0.0f;
            result.timings.front().gpu_kernel_ms += parameters.kernel_ms;
        }

        auto pipeline = run_gpu_pipeline(config, device_inputs, &result.operator_timings);
        GpuArtifacts artifacts = std::move(pipeline.first);
        result.timings.insert(result.timings.end(), pipeline.second.begin(), pipeline.second.end());

        auto output = measure_cpu_ms([&]() { return materialize_gpu_artifacts(artifacts); });
        result.artifacts = std::move(output.first);
        auto validation_input = measure_cpu_ms([&]() { return materialize_gpu_inputs(device_inputs); });
        result.host_inputs = std::move(validation_input.first);
        result.validation_input_d2h_ms = validation_input.second;
        result.timings.push_back({"final_output", 0.0f, output.second,
                                  std::numeric_limits<float>::quiet_NaN()});
        return result;
    }

    GpuValidationRun run_gpu_validation(const ScenarioConfig &config, const TaskInputs &host_inputs)
    {
        const tile::TaskPolicyDecision task_tuning = tile::select_task(task_tuning_key(config));
        const tile::ScopedTaskPolicy task_scope(task_tuning);
        GpuValidationRun result;
        auto parameters = measure_cpu_ms([&]() {
            return build_gpu_pipeline_parameters_device(config);
        });
        auto upload = measure_cpu_ms([&]() {
            return upload_gpu_task_inputs(std::move(parameters.first), host_inputs);
        });
        GpuPipelineInputs device_inputs = std::move(upload.first);
        result.timings.push_back({"validation_h2d", 0.0f, parameters.second + upload.second,
                                  std::numeric_limits<float>::quiet_NaN()});
        auto pipeline = run_gpu_pipeline(config, device_inputs);
        GpuArtifacts artifacts = std::move(pipeline.first);
        result.timings.insert(result.timings.end(), pipeline.second.begin(), pipeline.second.end());
        auto output = measure_cpu_ms([&]() { return materialize_gpu_artifacts(artifacts); });
        result.artifacts = std::move(output.first);
        result.timings.push_back({"validation_d2h", 0.0f, output.second,
                                  std::numeric_limits<float>::quiet_NaN()});
        return result;
    }
}
