#include "task2_common.hpp"

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <utility>
#include <variant>

#include "cusignal/bsplines/bsplines.hpp"
#include "cusignal/correlate/correlate.hpp"
#include "cusignal/demod/demod.hpp"
#include "cusignal/estimation/estimation.hpp"
#include "cusignal/filter_design/filter_design.hpp"
#include "cusignal/filtering/filtering.hpp"
#include "cusignal/peak_finding/peak_finding.hpp"
#include "cusignal/spectral/spectral.hpp"
#include "cusignal/windows/windows.hpp"
#include "cusignal/waveforms/waveforms.hpp"
#include "cusignal/wavelets/wavelets.hpp"

namespace cusignal_demo::task2_features
{
    using cusignal::spectral_api::SpectrogramResult;
    using cusignal::waveforms_api::IEnvWaveform;

    namespace
    {
        // Keep the CPU stabilization rule identical to the GPU helper layer.
        // These values are part of the task's existing demodulation semantics.
        constexpr float kTaskDemodSmallPhaseLimit = 0.05f;
        constexpr float kTaskDemodMinPowerRatio = 1.0f / 65536.0f;

        RealSignal extract_real_signal(const ComplexSignal &input)
        {
            RealSignal output(input.size(), 0.0f);
            for (std::size_t index = 0; index < input.size(); ++index)
                output[index] = input[index].real();
            return output;
        }

        float sum_positive(const RealSignal &values)
        {
            float sum = 0.0f;
            for (float value : values)
                sum += value;
            return sum;
        }

        RealSignal normalize_nonnegative_cpu(const RealSignal &values)
        {
            RealSignal output(values.size(), 0.0f);
            float maximum = 0.0f;
            for (float value : values)
                maximum = std::max(maximum, value);
            if (maximum <= 1.0e-12f)
                return output;
            for (std::size_t index = 0; index < values.size(); ++index)
                output[index] = values[index] / maximum;
            return output;
        }

        RealSignal pad_last_value_cpu(const RealSignal &values, std::size_t target_len)
        {
            RealSignal output(target_len, 0.0f);
            if (values.empty())
                return output;
            for (std::size_t index = 0; index < target_len; ++index)
                output[index] = values[index < values.size() ? index : values.size() - 1U];
            return output;
        }

        void stabilize_demod_phase_cpu(const ComplexSignal &frame, RealSignal &demod)
        {
            if (frame.size() != demod.size() + 1U)
                throw std::invalid_argument("stabilize_demod_phase_cpu size mismatch");
            for (std::size_t index = 0; index < demod.size(); ++index)
            {
                if (std::fabs(demod[index]) > kTaskDemodSmallPhaseLimit)
                    continue;
                const float current_power = std::norm(frame[index]);
                const float next_power = std::norm(frame[index + 1U]);
                const float maximum = std::max(current_power, next_power);
                if (maximum > 0.0f && std::min(current_power, next_power) <= kTaskDemodMinPowerRatio * maximum)
                    demod[index] = 0.0f;
            }
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
                throw std::invalid_argument("spectrogram_band_score_cpu shape mismatch");
            const std::size_t freq_count = values.shape[0];
            const std::size_t time_count = values.shape[1];
            RealSignal time_energy(time_count, 0.0f);
            for (std::size_t time_index = 0; time_index < time_count; ++time_index)
            {
                float sum = 0.0f;
                for (std::size_t freq_index = 0; freq_index < freq_count; ++freq_index)
                {
                    if (freqs[freq_index] >= band_low && freqs[freq_index] <= band_high)
                        sum += values.values[freq_index * time_count + time_index];
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
                throw std::invalid_argument("cwt_max_score_cpu expects rank-2 input");
            const std::size_t widths = values.shape[0];
            const std::size_t samples = values.shape[1];
            RealSignal output(samples, 0.0f);
            for (std::size_t sample = 0; sample < samples; ++sample)
            {
                float best = 0.0f;
                for (std::size_t width = 0; width < widths; ++width)
                    best = std::max(best, std::abs(values.values[width * samples + sample]));
                output[sample] = best;
            }
            return output;
        }

        RealSignal smooth_with_weights_cpu(const RealSignal &input, const RealSignal &weights)
        {
            RealSignal output(input.size(), 0.0f);
            if (input.empty() || weights.empty())
                return output;
            const int radius = static_cast<int>(weights.size() / 2U);
            for (std::size_t index = 0; index < input.size(); ++index)
            {
                float sum = 0.0f;
                for (std::size_t weight = 0; weight < weights.size(); ++weight)
                {
                    int sample = static_cast<int>(index) + static_cast<int>(weight) - radius;
                    sample = std::max(0, std::min(sample, static_cast<int>(input.size()) - 1));
                    sum += weights[weight] * input[static_cast<std::size_t>(sample)];
                }
                output[index] = sum;
            }
            return output;
        }

        int argmax_cpu(const RealSignal &values)
        {
            if (values.empty())
                return 0;
            return static_cast<int>(std::distance(values.begin(), std::max_element(values.begin(), values.end())));
        }

        int select_peak_cpu(const RealSignal &score, int order)
        {
            const auto extrema = cusignal::cpu::peak_finding::argrelmax(as_real_array(score), 0, order, "clip");
            if (extrema.indices.empty() || extrema.indices[0].empty())
                return argmax_cpu(score);
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

        RealSignal build_bspline_weights_cpu(std::vector<StageTiming> *operator_timings)
        {
            const RealSignal offsets{-2.0f, -1.0f, 0.0f, 1.0f, 2.0f};
            auto measured = measure_cpu_ms([&]() {
                return cusignal::cpu::bsplines::cubic(as_real_array(offsets)).values;
            });
            if (operator_timings != nullptr)
                operator_timings->push_back({"bsplines/cubic", measured.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            RealSignal weights = std::move(measured.first);
            const float sum = sum_positive(weights);
            if (sum <= 1.0e-12f)
                throw std::runtime_error("invalid bspline weights");
            for (float &value : weights)
                value /= sum;
            return weights;
        }

        ComplexSignal build_target_template(
            const ScenarioConfig &config,
            std::vector<StageTiming> *operator_timings)
        {
            const float t1 = static_cast<float>(config.template_length - 1) / config.fs;
            const RealSignal time = linspace(0.0f, t1, config.template_length);
            const RealSignal env_time = linspace(-0.5f * t1, 0.5f * t1, config.template_length);
            auto chirp_measured = measure_cpu_ms([&]() {
                return cusignal::cpu::waveforms::chirp(
                    time, config.chirp_f0, t1, config.chirp_f1, "linear", 0.0f, true, "complex");
            });
            const auto &chirp_result = chirp_measured.first;
            if (operator_timings != nullptr)
                operator_timings->push_back({"waveforms/chirp", chirp_measured.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            if (!std::holds_alternative<ComplexSignal>(chirp_result))
                throw std::runtime_error("chirp did not return complex output");
            auto gauss_measured = measure_cpu_ms([&]() {
                return cusignal::cpu::waveforms::gausspulse(
                    env_time, config.gausspulse_fc, 0.5f, -6.0f, -40.0f, false, true);
            });
            const auto &gauss_result = gauss_measured.first;
            if (operator_timings != nullptr)
                operator_timings->push_back({"waveforms/gausspulse", gauss_measured.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            if (!std::holds_alternative<IEnvWaveform>(gauss_result))
                throw std::runtime_error("gausspulse did not return envelope output");

            ComplexSignal output = std::get<ComplexSignal>(chirp_result);
            const RealSignal &envelope = std::get<IEnvWaveform>(gauss_result).envelope;
            float max_mag = 0.0f;
            for (std::size_t index = 0; index < output.size(); ++index)
            {
                output[index] *= envelope[index];
                max_mag = std::max(max_mag, std::abs(output[index]));
            }
            if (max_mag <= 1.0e-12f)
                throw std::runtime_error("target template magnitude collapsed to zero");
            for (Complex &value : output)
                value /= max_mag;
            return output;
        }

        ComplexSignal build_interferer_signal(
            const ScenarioConfig &config,
            std::vector<StageTiming> *operator_timings)
        {
            constexpr float two_pi = 6.28318530717958647692f;
            RealSignal phase(static_cast<std::size_t>(config.interferer_length), 0.0f);
            RealSignal phase_alt(static_cast<std::size_t>(config.interferer_length), 0.0f);
            for (int index = 0; index < config.interferer_length; ++index)
            {
                const float time = static_cast<float>(index) / config.fs;
                phase[static_cast<std::size_t>(index)] = two_pi * config.interferer_f0 * time;
                phase_alt[static_cast<std::size_t>(index)] = two_pi * config.interferer_f1 * time;
            }
            auto saw_measured = measure_cpu_ms([&]() {
                return cusignal::cpu::waveforms::sawtooth(phase, 0.7f);
            });
            auto square_measured = measure_cpu_ms([&]() {
                return cusignal::cpu::waveforms::square(phase_alt, 0.35f);
            });
            if (operator_timings != nullptr)
            {
                operator_timings->push_back({"waveforms/sawtooth", saw_measured.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
                operator_timings->push_back({"waveforms/square", square_measured.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            }
            const RealSignal saw = std::move(saw_measured.first);
            const RealSignal square = std::move(square_measured.first);
            ComplexSignal output(static_cast<std::size_t>(config.interferer_length), Complex(0.0f, 0.0f));
            for (int index = 0; index < config.interferer_length; ++index)
            {
                const float real_value = 0.7f * saw[static_cast<std::size_t>(index)] +
                    0.3f * square[static_cast<std::size_t>(index)];
                const float imag_value = 0.25f * square[static_cast<std::size_t>(index)];
                output[static_cast<std::size_t>(index)] =
                    config.interferer_amplitude * Complex(real_value, imag_value);
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
                Shape{static_cast<std::size_t>(config.num_frames),
                      static_cast<std::size_t>(config.samples_per_frame)},
                Complex(0.0f, 0.0f));
            const float linear_snr = std::pow(10.0f, config.snr_db / 10.0f);
            const float sigma = include_noise
                ? config.target_amplitude / std::sqrt(2.0f * linear_snr)
                : 0.0f;
            for (int frame = 0; frame < config.num_frames; ++frame)
            {
                const int target_start = config.target_start_sample_0 + frame * config.target_step_per_frame;
                for (int sample = 0; sample < config.samples_per_frame; ++sample)
                {
                    const std::uint64_t linear_index =
                        static_cast<std::uint64_t>(frame) * static_cast<std::uint64_t>(config.samples_per_frame) +
                        static_cast<std::uint64_t>(sample);
                    Complex value(0.0f, 0.0f);
                    if (include_noise)
                    {
                        value = Complex(
                            sigma * detail::task2_normal(config.seed, linear_index * 2U),
                            sigma * detail::task2_normal(config.seed, linear_index * 2U + 1U));
                    }
                    const int template_index = sample - target_start;
                    if (template_index >= 0 && template_index < static_cast<int>(target_template.size()))
                        value += config.target_amplitude * target_template[static_cast<std::size_t>(template_index)];
                    if (include_interference)
                    {
                        const int interferer_index = sample - config.interferer_start_sample;
                        if (interferer_index >= 0 && interferer_index < static_cast<int>(interferer_signal.size()))
                            value += interferer_signal[static_cast<std::size_t>(interferer_index)];
                    }
                    frames.values[static_cast<std::size_t>(linear_index)] = value;
                }
            }
            return frames;
        }

        RealSignal build_filter_taps_cpu(
            const ScenarioConfig &config,
            std::vector<StageTiming> *operator_timings)
        {
            const RealSignal cutoff{config.filter_low, config.filter_high};
            auto measured = measure_cpu_ms([&]() {
                return cusignal::cpu::filter_design::firwin(
                    config.filter_numtaps, cutoff, -1.0f,
                    cusignal::core::NamedFloatParameter{"kaiser", 8.0f},
                    std::string("bandpass"), true, -1.0f, config.fs);
            });
            if (operator_timings != nullptr)
                operator_timings->push_back({"filter_design/firwin", measured.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            return std::move(measured.first);
        }

        RealSignal compute_truth_track(const ScenarioConfig &config, const ComplexSignal &target_template);

        struct CpuPipelineInputs
        {
            RealSignal widths;
            RealSignal bspline_weights;
            RealSignal taps;
        };

        struct FrameCpuResult
        {
            RealSignal demod_score;
            RealSignal correlate_score;
            RealSignal feature_score;
            SpectrogramResult spectrogram;
            ComplexArray cwt_values;
            int peak_index = 0;
        };

        ComplexArray filter_complex_frames_cpu(const RealSignal &taps, const ComplexArray &input)
        {
            return cusignal::cpu::filtering::firfilter(taps, input, -1);
        }

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
            float &fusion_ms,
            float &argrelmax_ms,
            const RealSignal &window)
        {
            FrameCpuResult result;
            const RealSignal real_frame = extract_real_signal(frame);
            auto demod = measure_cpu_ms([&]() {
                return cusignal::cpu::demod::fm_demod(as_complex_array(frame), -1);
            });
            demod_ms += demod.second;
            stabilize_demod_phase_cpu(frame, demod.first.values);
            result.demod_score = normalize_nonnegative_cpu(pad_last_value_cpu(demod.first.values, frame.size()));

            auto correlate = measure_cpu_ms([&]() {
                return cusignal::cpu::correlate::correlate(
                    as_complex_array(frame), as_complex_array(target_template), "same", "fft");
            });
            correlate_ms += correlate.second;
            result.correlate_score = normalize_nonnegative_cpu(magnitude_signal(correlate.first.values));

            auto spectrogram = measure_cpu_ms([&]() {
                return cusignal::cpu::spectral::spectrogram(
                    as_real_array(real_frame), config.fs, window,
                    config.spectrogram_nperseg, config.spectrogram_noverlap,
                    config.spectrogram_nfft, std::string("constant"), true,
                    "spectrum", -1, "magnitude");
            });
            spectrogram_ms += spectrogram.second;
            if (!std::holds_alternative<RealArray>(spectrogram.first.values))
                throw std::runtime_error("spectrogram did not return real values");
            result.spectrogram = std::move(spectrogram.first);
            const RealSignal spectrogram_score = normalize_nonnegative_cpu(
                spectrogram_band_score_cpu(
                    std::get<RealArray>(result.spectrogram.values), result.spectrogram.frequencies,
                    result.spectrogram.times, config.samples_per_frame,
                    config.filter_low, config.filter_high, config.fs));

            auto cwt = measure_cpu_ms([&]() {
                return cusignal::cpu::wavelets::cwt(real_frame, "morlet2", widths);
            });
            cwt_ms += cwt.second;
            result.cwt_values = std::move(cwt.first);
            const RealSignal wavelet_score = normalize_nonnegative_cpu(cwt_max_score_cpu(result.cwt_values));

            auto fusion = measure_cpu_ms([&]() {
                RealSignal fused(frame.size(), 0.0f);
                for (std::size_t index = 0; index < fused.size(); ++index)
                {
                    fused[index] = 0.45f * result.correlate_score[index] +
                        0.20f * result.demod_score[index] +
                        0.20f * wavelet_score[index] + 0.15f * spectrogram_score[index];
                }
                return smooth_with_weights_cpu(fused, bspline_weights);
            });
            fusion_ms += fusion.second;
            result.feature_score = std::move(fusion.first);
            auto peak = measure_cpu_ms([&]() {
                return select_peak_cpu(result.feature_score, config.peak_order);
            });
            argrelmax_ms += peak.second;
            result.peak_index = peak.first;
            return result;
        }

        std::pair<CpuArtifacts, std::vector<StageTiming>> run_cpu_pipeline(
            const ScenarioConfig &config,
            const ComplexSignal &target_template,
            const ComplexArray &rx_frames,
            const RealSignal &truth_track,
            const CpuPipelineInputs &inputs,
            std::vector<StageTiming> *operator_timings)
        {
            CpuArtifacts artifacts;
            artifacts.target_template = target_template;
            artifacts.rx_frames = rx_frames;
            artifacts.truth_track = truth_track;
            std::vector<StageTiming> timings;

            auto filtered = measure_cpu_ms([&]() { return filter_complex_frames_cpu(inputs.taps, rx_frames); });
            artifacts.filtered = std::move(filtered.first);
            timings.push_back({"filter", filtered.second, 0.0f});
            if (operator_timings != nullptr)
                operator_timings->push_back({"filtering/firfilter", filtered.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            artifacts.demod_scores = cusignal::core::make_real_array(
                Shape{static_cast<std::size_t>(config.num_frames), static_cast<std::size_t>(config.samples_per_frame)}, 0.0f);
            artifacts.correlate_scores = artifacts.demod_scores;
            artifacts.feature_scores = artifacts.demod_scores;
            artifacts.peak_track = RealSignal(static_cast<std::size_t>(config.num_frames), 0.0f);

            float demod_ms = 0.0f, correlate_ms = 0.0f, spectrogram_ms = 0.0f,
                  cwt_ms = 0.0f, fusion_ms = 0.0f, argrelmax_ms = 0.0f;
            auto window_measured = measure_cpu_ms([&]() {
                return cusignal::cpu::windows::get_window(
                    std::string("hann"), config.spectrogram_nperseg, true);
            });
            const RealSignal window = std::move(window_measured.first);
            // Window construction is part of the spectrogram stage, but is
            // kept separate from the public spectral/spectrogram row.
            const float window_stage_ms = window_measured.second;
            if (operator_timings != nullptr)
                operator_timings->push_back({"windows/get_window", window_measured.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            for (int frame = 0; frame < config.num_frames; ++frame)
            {
                const ComplexSignal frame_signal = extract_row_complex_signal(artifacts.filtered, frame);
                const FrameCpuResult frame_result = process_frame_cpu(
                    config, frame_signal, artifacts.target_template, inputs.widths,
                    inputs.bspline_weights, demod_ms, correlate_ms, spectrogram_ms, cwt_ms,
                    fusion_ms, argrelmax_ms, window);
                store_row_real(artifacts.demod_scores, frame_result.demod_score, frame);
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
            timings.push_back({"demod", demod_ms, 0.0f});
            timings.push_back({"correlate", correlate_ms, 0.0f});
            timings.push_back({"spectrogram", spectrogram_ms + window_stage_ms, 0.0f});
            timings.push_back({"cwt", cwt_ms, 0.0f});
            timings.push_back({"feature_fusion", fusion_ms, 0.0f});
            if (operator_timings != nullptr)
            {
                operator_timings->push_back({"demod/fm_demod", demod_ms, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
                operator_timings->push_back({"correlate/correlate", correlate_ms, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
                operator_timings->push_back({"spectral/spectrogram", spectrogram_ms, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
                operator_timings->push_back({"wavelets/cwt", cwt_ms, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
                operator_timings->push_back({"peak_finding/argrelmax", argrelmax_ms, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            }

            auto measurements = measure_cpu_ms([&]() { return artifacts.peak_track; });
            artifacts.measurement_values = std::move(measurements.first);
            timings.push_back({"measurement_conversion", measurements.second, 0.0f});

            auto kalman = measure_cpu_ms([&]() {
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
                filter.x.values = {artifacts.measurement_values[0], 0.0f};
                RealSignal output(static_cast<std::size_t>(config.num_frames), 0.0f);
                output[0] = artifacts.measurement_values[0];
                for (int frame = 1; frame < config.num_frames; ++frame)
                {
                    filter.predict();
                    RealArray measurement = cusignal::core::make_real_array(Shape{1, 1, 1}, 0.0f);
                    measurement.values[0] = artifacts.measurement_values[static_cast<std::size_t>(frame)];
                    filter.update(measurement);
                    output[static_cast<std::size_t>(frame)] = filter.x.values[0];
                }
                return output;
            });
            artifacts.kalman_track = std::move(kalman.first);
            timings.push_back({"kalman", kalman.second, 0.0f});
            if (operator_timings != nullptr)
                operator_timings->push_back({"estimation/kalman_filter", kalman.second, 0.0f,
                                             std::numeric_limits<float>::quiet_NaN()});
            return std::make_pair(std::move(artifacts), std::move(timings));
        }

        CpuPipelineInputs build_cpu_pipeline_inputs(
            const ScenarioConfig &config,
            std::vector<StageTiming> *operator_timings)
        {
            CpuPipelineInputs inputs;
            inputs.widths = even_range(4.0f, 32.0f, 2.0f);
            inputs.bspline_weights = build_bspline_weights_cpu(operator_timings);
            inputs.taps = build_filter_taps_cpu(config, operator_timings);
            return inputs;
        }

        RealSignal compute_truth_track(const ScenarioConfig &config, const ComplexSignal &target_template)
        {
            (void)target_template;
            RealSignal truth(static_cast<std::size_t>(config.num_frames), 0.0f);
            for (int frame = 0; frame < config.num_frames; ++frame)
            {
                const int target_start = config.target_start_sample_0 +
                    frame * config.target_step_per_frame;
                const int matched_filter_offset = static_cast<int>(config.template_length / 2);
                const int filter_group_delay = (config.filter_numtaps - 1) / 2;
                truth[static_cast<std::size_t>(frame)] = static_cast<float>(
                    target_start + matched_filter_offset + filter_group_delay);
            }
            return truth;
        }
    }

    TaskInputs build_cpu_task_inputs(
        const ScenarioConfig &config,
        bool include_noise,
        std::vector<StageTiming> *operator_timings)
    {
        TaskInputs inputs;
        inputs.target_template = build_target_template(config, operator_timings);
        inputs.rx_frames = simulate_frames(
            config, inputs.target_template, build_interferer_signal(config, operator_timings), true, include_noise);
        inputs.truth_track = compute_truth_track(config, inputs.target_template);
        return inputs;
    }

    CpuTaskRun run_cpu_task(const ScenarioConfig &config)
    {
        CpuTaskRun result;
        auto input = measure_cpu_ms([&]() {
            return build_cpu_task_inputs(config, true, &result.operator_timings);
        });
        result.inputs = std::move(input.first);
        result.timings.push_back({"input_construction", input.second, 0.0f});
        auto parameters = measure_cpu_ms([&]() {
            return build_cpu_pipeline_inputs(config, &result.operator_timings);
        });
        auto pipeline = run_cpu_pipeline(
            config, result.inputs.target_template, result.inputs.rx_frames,
            result.inputs.truth_track, parameters.first, &result.operator_timings);
        result.artifacts = std::move(pipeline.first);
        result.timings.insert(result.timings.end(), pipeline.second.begin(), pipeline.second.end());
        // Pipeline parameters are part of CPU input preparation, not filter
        // execution. Keep the CPU/GPU stage boundaries symmetric.
        result.timings.front().cpu_ms += parameters.second;
        result.timings.push_back({"final_output", 0.0f, 0.0f});
        return result;
    }

    CpuValidationRun run_cpu_validation(const ScenarioConfig &config, const TaskInputs &inputs)
    {
        const CpuPipelineInputs parameters = build_cpu_pipeline_inputs(config, nullptr);
        auto pipeline = run_cpu_pipeline(
            config, inputs.target_template, inputs.rx_frames, inputs.truth_track, parameters, nullptr);
        CpuValidationRun result;
        result.artifacts = std::move(pipeline.first);
        return result;
    }
}
