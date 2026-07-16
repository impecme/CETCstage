#pragma once

#include <algorithm>
#include <cctype>
#include <cmath>
#include <complex>
#include <cstddef>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"
#include "cusignal/waveforms/waveforms.hpp"

#ifdef __CUDACC__
#define CUSIGNAL_WAVEFORMS_HD __host__ __device__
#else
#define CUSIGNAL_WAVEFORMS_HD
#endif

namespace cusignal
{
    namespace waveforms_detail
    {
        constexpr float kPi = 3.14159265358979323846f;

        CUSIGNAL_WAVEFORMS_HD inline float positive_periodic_mod(float t)
        {
            const float period = 2.0f * kPi;
            float value = ::fmodf(t, period);
            if (value < 0.0)
            {
                value += period;
            }
            return value;
        }

        CUSIGNAL_WAVEFORMS_HD inline float linear_phase_from_beta(
            float t,
            float f0,
            float beta)
        {
            return 2.0f * kPi * (f0 * t + 0.5f * beta * t * t);
        }

        CUSIGNAL_WAVEFORMS_HD inline float linear_phase(
            float t,
            float f0,
            float t1,
            float f1)
        {
            return linear_phase_from_beta(t, f0, (f1 - f0) / t1);
        }

        CUSIGNAL_WAVEFORMS_HD inline float quadratic_phase(
            float t,
            float f0,
            float t1,
            float f1,
            bool vertex_zero)
        {
            const float beta = (f1 - f0) / (t1 * t1);
            if (vertex_zero)
            {
                return 2.0f * kPi * (f0 * t + beta * (t * t * t) / 3.0f);
            }

            const float delta = t1 - t;
            return 2.0f * kPi *
                   (f1 * t + beta * ((delta * delta * delta) - (t1 * t1 * t1)) / 3.0f);
        }

        CUSIGNAL_WAVEFORMS_HD inline float logarithmic_phase(
            float t,
            float f0,
            float t1,
            float f1)
        {
            if (f0 == f1)
            {
                return 2.0f * kPi * f0 * t;
            }

            const float ratio = f1 / f0;
            const float beta = t1 / ::logf(ratio);
            return 2.0f * kPi * beta * f0 * (::powf(ratio, t / t1) - 1.0f);
        }

        CUSIGNAL_WAVEFORMS_HD inline float hyperbolic_phase(
            float t,
            float f0,
            float t1,
            float f1)
        {
            if (f0 == f1)
            {
                return 2.0f * kPi * f0 * t;
            }

            const float singularity = -f1 * t1 / (f0 - f1);
            return 2.0f * kPi * (-singularity * f0) *
                   ::logf(::fabsf(1.0f - t / singularity));
        }

        CUSIGNAL_WAVEFORMS_HD inline float sawtooth_value(float t, float width)
        {
            const float tmod = positive_periodic_mod(t);

            if (width == 0.0f)
            {
                return (kPi - tmod) / kPi;
            }
            if (width == 1.0f)
            {
                return tmod / kPi - 1.0f;
            }
            if (tmod < (width * 2.0f * kPi))
            {
                return tmod / (kPi * width) - 1.0f;
            }
            return (kPi * (width + 1.0f) - tmod) / (kPi * (1.0f - width));
        }

        CUSIGNAL_WAVEFORMS_HD inline float square_value(float t, float duty)
        {
            const float tmod = positive_periodic_mod(t);
            return tmod < (duty * 2.0f * kPi) ? 1.0f : -1.0f;
        }

        inline void ensure_float32(const std::string &dtype)
        {
            if (dtype != "float32")
            {
                throw std::logic_error("waveforms only supports dtype=float32");
            }
        }

        inline void ensure_finite(float value, const std::string &name)
        {
            if (!std::isfinite(value))
            {
                throw std::invalid_argument(name + " must be finite");
            }
        }

        inline void ensure_probability(float value, const std::string &name)
        {
            ensure_finite(value, name);
            if (value < 0.0f || value > 1.0f)
            {
                throw std::invalid_argument(name + " must be in [0, 1]");
            }
        }

        inline void ensure_vector_parameter(
            const core::RealSignal &t,
            const core::RealSignal &parameter,
            const std::string &name)
        {
            if (t.size() != parameter.size())
            {
                throw std::invalid_argument(name + " must have the same length as t");
            }

            for (std::size_t index = 0; index < parameter.size(); ++index)
            {
                if (!std::isfinite(parameter[index]) || parameter[index] < 0.0f ||
                    parameter[index] > 1.0f)
                {
                    std::ostringstream stream;
                    stream << name << "[" << index << "] must be in [0, 1]";
                    throw std::invalid_argument(stream.str());
                }
            }
        }

        inline std::string normalize_token(const std::string &token)
        {
            std::string normalized = token;
            std::transform(
                normalized.begin(),
                normalized.end(),
                normalized.begin(),
                [](unsigned char value) { return static_cast<char>(std::tolower(value)); });
            return normalized;
        }

        inline bool is_linear_method(const std::string &method)
        {
            return method == "linear" || method == "lin" || method == "li";
        }

        inline bool is_quadratic_method(const std::string &method)
        {
            return method == "quadratic" || method == "quad" || method == "q";
        }

        inline bool is_logarithmic_method(const std::string &method)
        {
            return method == "logarithmic" || method == "log" || method == "lo";
        }

        inline bool is_hyperbolic_method(const std::string &method)
        {
            return method == "hyperbolic" || method == "hyp";
        }

        inline std::string validate_chirp_method(const std::string &method)
        {
            const std::string normalized = normalize_token(method);
            if (is_linear_method(normalized) || is_quadratic_method(normalized) ||
                is_logarithmic_method(normalized) || is_hyperbolic_method(normalized))
            {
                return normalized;
            }

            throw std::invalid_argument(
                "method must be one of linear/quadratic/logarithmic/hyperbolic aliases");
        }

        inline std::string validate_chirp_type(const std::string &type)
        {
            const std::string normalized = normalize_token(type);
            if (normalized != "real" && normalized != "complex")
            {
                throw std::invalid_argument("type must be either real or complex");
            }
            return normalized;
        }

        inline void validate_chirp_inputs(
            float f0,
            float t1,
            float f1,
            float phi,
            const std::string &method,
            const std::string &type)
        {
            ensure_finite(f0, "f0");
            ensure_finite(t1, "t1");
            ensure_finite(f1, "f1");
            ensure_finite(phi, "phi");

            if (t1 == 0.0f)
            {
                throw std::invalid_argument("t1 must be non-zero");
            }
            if (type == "complex" && !is_linear_method(method))
            {
                throw std::invalid_argument("complex chirp output is only supported for linear chirps");
            }
            if (is_logarithmic_method(method) &&
                (f0 == 0.0f || f1 == 0.0f || (f0 * f1) <= 0.0f))
            {
                throw std::invalid_argument(
                    "logarithmic chirp requires f0 and f1 to be non-zero with the same sign");
            }
            if (is_hyperbolic_method(method) && (f0 == 0.0f || f1 == 0.0f))
            {
                throw std::invalid_argument(
                    "hyperbolic chirp requires f0 and f1 to be non-zero");
            }
        }

        inline void validate_gausspulse_inputs(float fc, float bw, float bwr)
        {
            ensure_finite(fc, "fc");
            ensure_finite(bw, "bw");
            ensure_finite(bwr, "bwr");

            if (fc < 0.0f)
            {
                throw std::invalid_argument("fc must be >= 0");
            }
            if (bw <= 0.0f)
            {
                throw std::invalid_argument("bw must be > 0");
            }
            if (bwr >= 0.0f)
            {
                throw std::invalid_argument("bwr must be < 0 dB");
            }
        }

        inline float degrees_to_radians(float phi)
        {
            return phi * kPi / 180.0f;
        }

        inline float compute_gausspulse_a(float fc, float bw, float bwr)
        {
            validate_gausspulse_inputs(fc, bw, bwr);
            const float ref = ::powf(10.0f, bwr / 20.0f);
            const float band = kPi * fc * bw;
            return -(band * band) / (4.0f * ::logf(ref));
        }

        inline float compute_gausspulse_cutoff(float fc, float bw, float bwr, float tpr)
        {
            ensure_finite(tpr, "tpr");
            if (tpr >= 0.0f)
            {
                throw std::invalid_argument("tpr must be < 0 dB when requesting cutoff");
            }

            const float a = compute_gausspulse_a(fc, bw, bwr);
            if (a == 0.0f)
            {
                return std::numeric_limits<float>::infinity();
            }

            const float tref = ::powf(10.0f, tpr / 20.0f);
            return ::sqrtf(-::logf(tref) / a);
        }

        CUSIGNAL_WAVEFORMS_HD inline float gausspulse_envelope(float t, float a)
        {
            return ::expf(-a * t * t);
        }

        CUSIGNAL_WAVEFORMS_HD inline float gausspulse_signal(float t, float a, float fc)
        {
            const float envelope = gausspulse_envelope(t, a);
            const float angle = 2.0f * kPi * fc * t;
            return envelope * ::cosf(angle);
        }

        CUSIGNAL_WAVEFORMS_HD inline float gausspulse_quadrature(float t, float a, float fc)
        {
            const float envelope = gausspulse_envelope(t, a);
            const float angle = 2.0f * kPi * fc * t;
            return envelope * ::sinf(angle);
        }

        template <bool ReturnQuadrature, bool ReturnEnvelope>
        CUSIGNAL_WAVEFORMS_HD inline void gausspulse_components(
            float t,
            float a,
            float fc,
            float *signal,
            float *quadrature,
            float *envelope)
        {
            const float envelope_value = gausspulse_envelope(t, a);
            const float angle = 2.0f * kPi * fc * t;
            *signal = envelope_value * ::cosf(angle);
            if constexpr (ReturnQuadrature)
            {
                *quadrature = envelope_value * ::sinf(angle);
            }
            if constexpr (ReturnEnvelope)
            {
                *envelope = envelope_value;
            }
        }

        inline void validate_1d_index(std::size_t size, std::size_t index)
        {
            if (size == 0)
            {
                if (index != 0)
                {
                    throw std::out_of_range("index is out of range for empty signal");
                }
                return;
            }

            if (index >= size)
            {
                throw std::out_of_range("index is out of range for signal");
            }
        }

        inline core::Shape origin_index(const core::Shape &shape)
        {
            return core::Shape(shape.size(), 0);
        }

        inline core::Shape repeated_index(const core::Shape &shape, std::size_t index)
        {
            return core::Shape(shape.size(), index);
        }

        inline core::Shape mid_index(const core::Shape &shape)
        {
            core::Shape index(shape.size(), 0);
            for (std::size_t axis = 0; axis < shape.size(); ++axis)
            {
                index[axis] = shape[axis] / 2;
            }
            return index;
        }

        inline void validate_shape_index(const core::Shape &shape, const core::Shape &index)
        {
            if (shape.size() != index.size())
            {
                throw std::invalid_argument("index rank must match shape rank");
            }

            for (std::size_t axis = 0; axis < shape.size(); ++axis)
            {
                if (shape[axis] == 0)
                {
                    if (index[axis] != 0)
                    {
                        std::ostringstream stream;
                        stream << "index[" << axis << "] is out of range for empty axis";
                        throw std::out_of_range(stream.str());
                    }
                    continue;
                }
                if (index[axis] >= shape[axis])
                {
                    std::ostringstream stream;
                    stream << "index[" << axis << "] is out of range for shape[" << axis << "]";
                    throw std::out_of_range(stream.str());
                }
            }
        }

        inline std::size_t flatten_index(const core::Shape &shape, const core::Shape &index)
        {
            std::size_t flat = 0;
            std::size_t stride = 1;

            for (std::size_t offset = shape.size(); offset > 0; --offset)
            {
                const std::size_t axis = offset - 1;
                flat += index[axis] * stride;
                stride *= shape[axis];
            }

            return flat;
        }

        inline waveforms_api::NdRealSignal make_nd_impulse(
            const core::Shape &shape,
            const core::Shape &index)
        {
            waveforms_api::NdRealSignal result;
            result.shape = shape;
            result.values = core::make_real_signal(core::shape_product(shape), 0.0);
            if (!result.values.empty())
            {
                result.values[flatten_index(shape, index)] = 1.0;
            }
            return result;
        }

    } // namespace waveforms_detail
} // namespace cusignal

#undef CUSIGNAL_WAVEFORMS_HD
