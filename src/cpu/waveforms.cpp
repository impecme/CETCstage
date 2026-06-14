#include "cusignal/waveforms/waveforms.hpp"

#include <complex>

#include "../common/waveforms_detail.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace waveforms
        {

            waveforms_api::ChirpResult chirp(
                const core::RealSignal &t,
                float f0,
                float t1,
                float f1,
                const std::string &method,
                float phi,
                bool vertex_zero,
                const std::string &type)
            {
                using namespace waveforms_detail;

                const std::string normalized_method = validate_chirp_method(method);
                const std::string normalized_type = validate_chirp_type(type);
                validate_chirp_inputs(f0, t1, f1, phi, normalized_method, normalized_type);
                const float phi_radians = degrees_to_radians(phi);

                if (normalized_type == "complex")
                {
                    core::ComplexSignal output = core::make_complex_signal(t.size());
                    for (std::size_t index = 0; index < t.size(); ++index)
                    {
                        const float angle =
                            linear_phase(t[index], f0, t1, f1) + phi_radians;
                        output[index] = std::polar(1.0f, angle);
                    }
                    return output;
                }

                core::RealSignal output = core::make_real_signal(t.size());
                for (std::size_t index = 0; index < t.size(); ++index)
                {
                    float phase = 0.0;
                    if (is_linear_method(normalized_method))
                    {
                        phase = linear_phase(t[index], f0, t1, f1);
                    }
                    else if (is_quadratic_method(normalized_method))
                    {
                        phase = quadratic_phase(t[index], f0, t1, f1, vertex_zero);
                    }
                    else if (is_logarithmic_method(normalized_method))
                    {
                        phase = logarithmic_phase(t[index], f0, t1, f1);
                    }
                    else
                    {
                        phase = hyperbolic_phase(t[index], f0, t1, f1);
                    }

                    output[index] = std::cos(phase + phi_radians);
                }
                return output;
            }

            waveforms_api::GausspulseResult gausspulse(
                const core::RealSignal &t,
                float fc,
                float bw,
                float bwr,
                float tpr,
                bool retquad,
                bool retenv)
            {
                using namespace waveforms_detail;

                ensure_finite(tpr, "tpr");
                const float a = compute_gausspulse_a(fc, bw, bwr);
                core::RealSignal signal = core::make_real_signal(t.size());
                core::RealSignal quadrature = retquad ? core::make_real_signal(t.size())
                                                      : core::RealSignal{};
                core::RealSignal envelope = retenv ? core::make_real_signal(t.size())
                                                   : core::RealSignal{};

                for (std::size_t index = 0; index < t.size(); ++index)
                {
                    signal[index] = gausspulse_signal(t[index], a, fc);
                    if (retquad)
                    {
                        quadrature[index] = gausspulse_quadrature(t[index], a, fc);
                    }
                    if (retenv)
                    {
                        envelope[index] = gausspulse_envelope(t[index], a);
                    }
                }

                if (retquad && retenv)
                {
                    core::WaveformBundle result;
                    result.signal = signal;
                    result.quadrature = quadrature;
                    result.envelope = envelope;
                    return result;
                }

                if (retquad)
                {
                    waveforms_api::IqWaveform result;
                    result.signal = signal;
                    result.quadrature = quadrature;
                    return result;
                }

                if (retenv)
                {
                    waveforms_api::IEnvWaveform result;
                    result.signal = signal;
                    result.envelope = envelope;
                    return result;
                }

                return signal;
            }

            float gausspulse(
                const std::string &t,
                float fc,
                float bw,
                float bwr,
                float tpr)
            {
                using namespace waveforms_detail;

                if (normalize_token(t) != "cutoff")
                {
                    throw std::invalid_argument("If t is a string, it must be cutoff");
                }

                return compute_gausspulse_cutoff(fc, bw, bwr, tpr);
            }

            core::RealSignal sawtooth(const core::RealSignal &t, float width)
            {
                using namespace waveforms_detail;

                ensure_probability(width, "width");
                core::RealSignal output = core::make_real_signal(t.size());
                for (std::size_t index = 0; index < t.size(); ++index)
                {
                    output[index] = sawtooth_value(t[index], width);
                }
                return output;
            }

            core::RealSignal sawtooth(const core::RealSignal &t, const core::RealSignal &width)
            {
                using namespace waveforms_detail;

                ensure_vector_parameter(t, width, "width");
                core::RealSignal output = core::make_real_signal(t.size());
                for (std::size_t index = 0; index < t.size(); ++index)
                {
                    output[index] = sawtooth_value(t[index], width[index]);
                }
                return output;
            }

            core::RealSignal square(const core::RealSignal &t, float duty)
            {
                using namespace waveforms_detail;

                ensure_probability(duty, "duty");
                core::RealSignal output = core::make_real_signal(t.size());
                for (std::size_t index = 0; index < t.size(); ++index)
                {
                    output[index] = square_value(t[index], duty);
                }
                return output;
            }

            core::RealSignal square(const core::RealSignal &t, const core::RealSignal &duty)
            {
                using namespace waveforms_detail;

                ensure_vector_parameter(t, duty, "duty");
                core::RealSignal output = core::make_real_signal(t.size());
                for (std::size_t index = 0; index < t.size(); ++index)
                {
                    output[index] = square_value(t[index], duty[index]);
                }
                return output;
            }

            core::RealSignal unit_impulse(
                std::size_t size,
                std::size_t index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                validate_1d_index(size, index);

                core::RealSignal signal = core::make_real_signal(size);
                if (!signal.empty())
                {
                    signal[index] = 1.0f;
                }
                return signal;
            }

            core::RealSignal unit_impulse(
                std::size_t size,
                const std::string &index_spec,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);

                if (normalize_token(index_spec) != "mid")
                {
                    throw std::invalid_argument("index_spec must be mid");
                }

                return unit_impulse(size, size / 2, dtype);
            }

            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                return make_nd_impulse(shape, origin_index(shape));
            }

            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                std::size_t index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                const core::Shape nd_index = repeated_index(shape, index);
                validate_shape_index(shape, nd_index);
                return make_nd_impulse(shape, nd_index);
            }

            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                const core::Shape &index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                validate_shape_index(shape, index);
                return make_nd_impulse(shape, index);
            }

            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                const char *index_spec,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);

                if (index_spec == nullptr)
                {
                    throw std::invalid_argument("index_spec must not be null");
                }
                if (normalize_token(index_spec) != "mid")
                {
                    throw std::invalid_argument("index_spec must be mid");
                }

                return make_nd_impulse(shape, mid_index(shape));
            }

        } // namespace waveforms
    } // namespace cpu
} // namespace cusignal
