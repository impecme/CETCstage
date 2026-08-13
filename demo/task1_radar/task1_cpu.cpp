#include "task1_common.hpp"

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <variant>

#include "cusignal/core/helpers.hpp"
#include "cusignal/radartools/radartools.hpp"
#include "cusignal/waveforms/waveforms.hpp"

namespace cusignal_demo::task1_radar
{
    namespace
    {
        constexpr float kTwoPi = 6.28318530717958647692f;

        RealSignal build_cpu_time_axis(const ScenarioConfig &config)
        {
            RealSignal values(static_cast<std::size_t>(config.template_length), 0.0f);
            const float step = 1.0f / config.fs;
            for (int index = 0; index < config.template_length; ++index)
            {
                values[static_cast<std::size_t>(index)] = step * static_cast<float>(index);
            }
            return values;
        }

        ComplexSignal build_cpu_template(const ScenarioConfig &config)
        {
            const float t1 = static_cast<float>(config.template_length - 1) / config.fs;
            const RealSignal t = build_cpu_time_axis(config);
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
                throw std::runtime_error("CPU chirp did not return complex output");
            return std::get<ComplexSignal>(result);
        }

        ComplexArray build_cpu_rx_matrix(
            const ScenarioConfig &config,
            const ComplexSignal &templ,
            bool include_noise)
        {
            ComplexArray rx = cusignal::core::make_complex_array(
                Shape{static_cast<std::size_t>(config.num_pulses),
                      static_cast<std::size_t>(config.samples_per_pulse)},
                Complex(0.0f, 0.0f));

            const float linear_snr = std::pow(10.0f, config.snr_db / 10.0f);
            const float sigma = include_noise
                ? config.target_amplitude / std::sqrt(2.0f * linear_snr)
                : 0.0f;
            for (int pulse = 0; pulse < config.num_pulses; ++pulse)
            {
                const float phase = kTwoPi * config.doppler_hz * static_cast<float>(pulse) / config.prf;
                const Complex doppler_phase = std::polar(1.0f, phase);
                for (int sample = 0; sample < config.samples_per_pulse; ++sample)
                {
                    const std::uint64_t linear_index =
                        static_cast<std::uint64_t>(pulse) *
                        static_cast<std::uint64_t>(config.samples_per_pulse) +
                        static_cast<std::uint64_t>(sample);
                    Complex value(0.0f, 0.0f);
                    if (include_noise)
                    {
                        value = Complex(
                            sigma * detail::task1_normal(config.seed, linear_index * 2U),
                            sigma * detail::task1_normal(config.seed, linear_index * 2U + 1U));
                    }

                    const int template_index = sample - config.delay_samples;
                    if (template_index >= 0 && template_index < static_cast<int>(templ.size()))
                    {
                        value += config.target_amplitude *
                            templ[static_cast<std::size_t>(template_index)] * doppler_phase;
                    }
                    rx.values[static_cast<std::size_t>(linear_index)] = value;
                }
            }
            return rx;
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
            artifacts.pulse_doppler = cusignal::cpu::radartools::fftshift_rows(artifacts.pulse_doppler);
            artifacts.range_doppler_power = cusignal::cpu::radartools::power_map(artifacts.pulse_doppler);
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

        DetectionSummary detect_cpu(const ScenarioConfig &config, const CpuArtifacts &artifacts)
        {
            return cusignal::cpu::radartools::detect_peak(
                artifacts.range_doppler_power,
                artifacts.cfar_detections,
                config.pulse_doppler_nfft,
                config.prf);
        }

        HostGpuArtifacts copy_cpu_artifacts(const CpuArtifacts &artifacts)
        {
            HostGpuArtifacts output;
            output.pulse_compression = artifacts.pulse_compression;
            output.pulse_doppler = artifacts.pulse_doppler;
            output.range_doppler_power = artifacts.range_doppler_power;
            output.cfar_threshold = artifacts.cfar_threshold;
            output.cfar_detections = artifacts.cfar_detections;
            output.ambgfun = artifacts.ambgfun;
            return output;
        }
    }

    TaskInputs build_cpu_task_inputs(const ScenarioConfig &config, bool include_noise)
    {
        TaskInputs inputs;
        inputs.tx_template = build_cpu_template(config);
        inputs.rx_matrix = build_cpu_rx_matrix(config, inputs.tx_template, include_noise);
        return inputs;
    }

    CpuTaskRun run_cpu_task(const ScenarioConfig &config)
    {
        CpuTaskRun result;
        auto chirp_measured = measure_cpu_ms([&]() {
            return build_cpu_template(config);
        });
        result.operator_timings.push_back({"waveforms/chirp", chirp_measured.second, 0.0f,
                                           std::numeric_limits<float>::quiet_NaN()});
        auto rx_measured = measure_cpu_ms([&]() {
            return build_cpu_rx_matrix(config, chirp_measured.first, true);
        });
        result.inputs.tx_template = std::move(chirp_measured.first);
        result.inputs.rx_matrix = std::move(rx_measured.first);
        result.timings.push_back({"input_construction", chirp_measured.second + rx_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        CpuArtifacts artifacts;
        artifacts.tx_template = result.inputs.tx_template;
        artifacts.rx_matrix = result.inputs.rx_matrix;

        auto pulse_measured = measure_cpu_ms([&]() {
            return cusignal::cpu::radartools::pulse_compression(
                artifacts.rx_matrix,
                artifacts.tx_template,
                config.pulse_compression_normalize,
                config.pulse_compression_window,
                config.pulse_compression_nfft);
        });
        artifacts.pulse_compression = std::move(pulse_measured.first);
        result.operator_timings.push_back({"radartools/pulse_compression", pulse_measured.second, 0.0f,
                                           std::numeric_limits<float>::quiet_NaN()});
        result.timings.push_back({"pulse_compression", pulse_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        auto doppler_measured = measure_cpu_ms([&]() {
            return cusignal::cpu::radartools::fftshift_rows(
                cusignal::cpu::radartools::pulse_doppler(
                    artifacts.pulse_compression,
                    config.pulse_doppler_window,
                    config.pulse_doppler_nfft));
        });
        artifacts.pulse_doppler = std::move(doppler_measured.first);
        result.operator_timings.push_back({"radartools/pulse_doppler", doppler_measured.second, 0.0f,
                                           std::numeric_limits<float>::quiet_NaN()});
        result.timings.push_back({"pulse_doppler", doppler_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        auto power_measured = measure_cpu_ms([&]() {
            return cusignal::cpu::radartools::power_map(artifacts.pulse_doppler);
        });
        artifacts.range_doppler_power = std::move(power_measured.first);
        result.timings.push_back({"power_map", power_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        auto cfar_measured = measure_cpu_ms([&]() {
            return cusignal::cpu::radartools::ca_cfar(
                artifacts.range_doppler_power,
                config.cfar_guard_cells,
                config.cfar_reference_cells,
                config.cfar_pfa);
        });
        artifacts.cfar_threshold = std::move(cfar_measured.first.threshold);
        artifacts.cfar_detections = std::move(cfar_measured.first.detections);
        result.operator_timings.push_back({"radartools/ca_cfar", cfar_measured.second, 0.0f,
                                           std::numeric_limits<float>::quiet_NaN()});
        result.timings.push_back({"ca_cfar", cfar_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        auto ambg_measured = measure_cpu_ms([&]() {
            return std::get<AmbgfunSurfaceResult>(cusignal::cpu::radartools::ambgfun(
                artifacts.tx_template,
                config.fs,
                config.prf,
                "2d",
                0.0f));
        });
        artifacts.ambgfun = std::move(ambg_measured.first);
        result.operator_timings.push_back({"radartools/ambgfun", ambg_measured.second, 0.0f,
                                           std::numeric_limits<float>::quiet_NaN()});
        result.timings.push_back({"ambgfun", ambg_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        auto detection_measured = measure_cpu_ms([&]() {
            return detect_cpu(config, artifacts);
        });
        result.detection = std::move(detection_measured.first);
        result.timings.push_back({"final_detection", detection_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});

        auto output_measured = measure_cpu_ms([&]() {
            return copy_cpu_artifacts(artifacts);
        });
        (void)output_measured.first;
        result.timings.push_back({"final_output", output_measured.second, 0.0f,
                                  std::numeric_limits<float>::quiet_NaN()});
        result.artifacts = std::move(artifacts);
        return result;
    }

    CpuValidationRun run_cpu_validation(const ScenarioConfig &config, const TaskInputs &inputs)
    {
        CpuValidationRun result;
        result.artifacts = run_cpu_pipeline_from_input(config, inputs.tx_template, inputs.rx_matrix);
        result.detection = detect_cpu(config, result.artifacts);
        return result;
    }
}
