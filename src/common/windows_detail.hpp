#pragma once

#include <algorithm>
#include <cctype>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

#ifdef __CUDACC__
#define CUSIGNAL_WINDOWS_HD __host__ __device__
#else
#define CUSIGNAL_WINDOWS_HD
#endif

namespace cusignal
{
    namespace windows_detail
    {
        constexpr float kPi = 3.14159265358979323846;

        struct ExtendedLength
        {
            int size = 0;
            bool needs_truncation = false;
        };

        enum class KernelOp
        {
            kBoxcar = 0,
            kGeneralCosine = 1,
            kTriang = 2,
            kBartlett = 3,
            kParzen = 4,
            kBohman = 5,
            kBarthann = 6,
            kCosine = 7,
            kTukey = 8,
            kKaiser = 9,
            kGaussian = 10,
            kGeneralGaussian = 11,
            kExponential = 12,
            kTaylor = 13,
        };

        inline void validate_size(int size)
        {
            if (size < 0)
            {
                throw std::invalid_argument("size must be >= 0");
            }
        }

        inline bool len_guard(int size)
        {
            validate_size(size);
            return size <= 1;
        }

        inline ExtendedLength extend(int size, bool sym)
        {
            validate_size(size);
            if (sym)
            {
                return ExtendedLength{size, false};
            }
            return ExtendedLength{size + 1, true};
        }

        inline core::RealSignal truncate(core::RealSignal values, bool needed)
        {
            if (needed && !values.empty())
            {
                values.pop_back();
            }
            return values;
        }

        template <typename Evaluator>
        inline core::RealSignal make_window_host(int size, bool sym, Evaluator &&evaluator)
        {
            if (len_guard(size))
            {
                return core::make_real_signal(static_cast<std::size_t>(size), 1.0);
            }

            const ExtendedLength extended = extend(size, sym);
            core::RealSignal values(static_cast<std::size_t>(extended.size), 0.0);
            for (int index = 0; index < extended.size; ++index)
            {
                values[static_cast<std::size_t>(index)] = evaluator(index, extended.size);
            }
            return truncate(std::move(values), extended.needs_truncation);
        }

        inline std::string normalize_token(const std::string &token)
        {
            std::string normalized;
            normalized.reserve(token.size());
            for (char value : token)
            {
                char current = static_cast<char>(std::tolower(static_cast<unsigned char>(value)));
                normalized.push_back(current == '_' ? ' ' : current);
            }
            return normalized;
        }

        inline std::string canonical_window_name(const std::string &name)
        {
            const std::string normalized = normalize_token(name);
            if (normalized.empty() || normalized == "boxcar" || normalized == "box" ||
                normalized == "ones" || normalized == "rect" ||
                normalized == "rectangular")
            {
                return "boxcar";
            }
            if (normalized == "barthann" || normalized == "brthan" || normalized == "bth")
            {
                return "barthann";
            }
            if (normalized == "bartlett" || normalized == "bart" || normalized == "brt")
            {
                return "bartlett";
            }
            if (normalized == "blackman" || normalized == "black" || normalized == "blk")
            {
                return "blackman";
            }
            if (normalized == "blackmanharris" || normalized == "blackharr" ||
                normalized == "bkh")
            {
                return "blackmanharris";
            }
            if (normalized == "bohman" || normalized == "bman" || normalized == "bmn")
            {
                return "bohman";
            }
            if (normalized == "chebwin" || normalized == "cheb")
            {
                return "chebwin";
            }
            if (normalized == "cosine" || normalized == "halfcosine")
            {
                return "cosine";
            }
            if (normalized == "exponential" || normalized == "poisson")
            {
                return "exponential";
            }
            if (normalized == "flattop" || normalized == "flat" || normalized == "flt")
            {
                return "flattop";
            }
            if (normalized == "gaussian" || normalized == "gauss" || normalized == "gss")
            {
                return "gaussian";
            }
            if (normalized == "general gaussian" || normalized == "general gauss" ||
                normalized == "ggs")
            {
                return "general_gaussian";
            }
            if (normalized == "general hamming")
            {
                return "general_hamming";
            }
            if (normalized == "hamming" || normalized == "hamm" || normalized == "ham")
            {
                return "hamming";
            }
            if (normalized == "hanning" || normalized == "hann" || normalized == "han")
            {
                return "hann";
            }
            if (normalized == "kaiser" || normalized == "ksr")
            {
                return "kaiser";
            }
            if (normalized == "nuttall" || normalized == "nutl" || normalized == "nut")
            {
                return "nuttall";
            }
            if (normalized == "parzen" || normalized == "parz" || normalized == "par")
            {
                return "parzen";
            }
            if (normalized == "triangle" || normalized == "triang" || normalized == "tri")
            {
                return "triang";
            }
            if (normalized == "tukey" || normalized == "tuk")
            {
                return "tukey";
            }
            if (normalized == "taylor")
            {
                return "taylor";
            }
            throw std::invalid_argument("unknown window type");
        }

        CUSIGNAL_WINDOWS_HD inline float abs_value(float value)
        {
            return value < 0.0f ? -value : value;
        }

        CUSIGNAL_WINDOWS_HD inline float bessel_i0(float x)
        {
            const float ax = abs_value(x);
            const float half_x = 0.5f * ax;
            const float y = half_x * half_x;

            float sum = 1.0;
            float term = 1.0;
            for (int order = 1; order < 256; ++order)
            {
                const float denominator = static_cast<float>(order) * static_cast<float>(order);
                term *= y / denominator;
                sum += term;
                if (term <= sum * 1.0e-16f)
                {
                    break;
                }
            }
            return sum;
        }

        CUSIGNAL_WINDOWS_HD inline float general_cosine_value(
            int index,
            int size,
            const float *coefficients,
            int count)
        {
            if (size <= 1)
            {
                return 1.0;
            }

            const float delta = (2.0 * kPi) / static_cast<float>(size - 1);
            const float angle = -kPi + delta * static_cast<float>(index);

            float value = 0.0;
            for (int coefficient_index = 0; coefficient_index < count; ++coefficient_index)
            {
                value += coefficients[coefficient_index] *
                         cos(static_cast<float>(coefficient_index) * angle);
            }
            return value;
        }

        CUSIGNAL_WINDOWS_HD inline float triang_value(int index, int size)
        {
            const int midpoint = size / 2;
            const bool odd = (size & 1) != 0;
            const int n = index < midpoint ? index + 1 : size - index;
            if (odd)
            {
                return 2.0 * static_cast<float>(n) / (static_cast<float>(size) + 1.0);
            }
            return (2.0 * static_cast<float>(n) - 1.0) / static_cast<float>(size);
        }

        CUSIGNAL_WINDOWS_HD inline float bartlett_value(int index, int size)
        {
            if (size <= 1)
            {
                return 1.0;
            }
            const float normalized = static_cast<float>(index) / static_cast<float>(size - 1);
            if (index <= (size - 1) / 2)
            {
                return 2.0 * normalized;
            }
            return 2.0 - 2.0 * normalized;
        }

        CUSIGNAL_WINDOWS_HD inline float cosine_value(int index, int size)
        {
            return sin(kPi * (static_cast<float>(index) + 0.5) / static_cast<float>(size));
        }

        CUSIGNAL_WINDOWS_HD inline float parzen_value(int index, int size)
        {
            if (size <= 1)
            {
                return 1.0;
            }

            const float half = 0.5 * static_cast<float>(size);
            const float n = abs_value(static_cast<float>(index) - 0.5f * static_cast<float>(size - 1));
            const float ratio = n / half;
            const float threshold = 0.5;
            if (ratio <= threshold)
            {
                return 1.0 - 6.0 * ratio * ratio + 6.0 * ratio * ratio * ratio;
            }

            if (ratio <= 1.0)
            {
                const float inner = 1.0 - ratio;
                return 2.0 * inner * inner * inner;
            }
            return 0.0;
        }

        CUSIGNAL_WINDOWS_HD inline float bohman_value(int index, int size)
        {
            if (size <= 1)
            {
                return 1.0;
            }
            if (index == 0 || index == size - 1)
            {
                return 0.0;
            }
            const float factor =
                abs_value((2.0f * static_cast<float>(index) / static_cast<float>(size - 1)) - 1.0f);
            return (1.0f - factor) * cosf(kPi * factor) + sinf(kPi * factor) / kPi;
        }

        CUSIGNAL_WINDOWS_HD inline float barthann_value(int index, int size)
        {
            if (size <= 1)
            {
                return 1.0;
            }
            const float factor =
                abs_value(static_cast<float>(index) / static_cast<float>(size - 1) - 0.5f);
            return 0.62f - 0.48f * factor + 0.38f * cosf(2.0f * kPi * factor);
        }

        CUSIGNAL_WINDOWS_HD inline float tukey_value(int index, int size, float alpha)
        {
            if (size <= 1)
            {
                return 1.0;
            }
            if (alpha <= 0.0)
            {
                return 1.0;
            }
            if (alpha >= 1.0)
            {
                const float coefficients[2] = {0.5, 0.5};
                return general_cosine_value(index, size, coefficients, 2);
            }

            const float normalized = static_cast<float>(index) / static_cast<float>(size - 1);
            const float edge = alpha / 2.0;
            if (normalized < edge)
            {
                return 0.5f * (1.0f + cosf(kPi * ((2.0f * normalized / alpha) - 1.0f)));
            }
            if (normalized <= (1.0 - edge))
            {
                return 1.0;
            }
            return 0.5f *
                   (1.0f + cosf(kPi * ((2.0f * normalized / alpha) - (2.0f / alpha) + 1.0f)));
        }

        CUSIGNAL_WINDOWS_HD inline float kaiser_value(int index, int size, float beta)
        {
            if (size <= 1)
            {
                return 1.0;
            }
            const float alpha = 0.5 * static_cast<float>(size - 1);
            const float temp = (static_cast<float>(index) - alpha) / alpha;
            const float inside = 1.0f - temp * temp;
            const float argument = beta * sqrtf(inside > 0.0f ? inside : 0.0f);
            return bessel_i0(argument) / bessel_i0(beta);
        }

        CUSIGNAL_WINDOWS_HD inline float gaussian_value(int index, int size, float std)
        {
            const float n = static_cast<float>(index) - 0.5 * static_cast<float>(size - 1);
            const float sigma2 = 2.0f * std * std;
            return expf(-(n * n) / sigma2);
        }

        CUSIGNAL_WINDOWS_HD inline float general_gaussian_value(
            int index,
            int size,
            float p,
            float sig)
        {
            const float n = static_cast<float>(index) - 0.5 * static_cast<float>(size - 1);
            return expf(-0.5f * powf(abs_value(n / sig), 2.0f * p));
        }

        CUSIGNAL_WINDOWS_HD inline float exponential_value(
            int index,
            float center,
            float tau)
        {
            return expf(-abs_value(static_cast<float>(index) - center) / tau);
        }

        CUSIGNAL_WINDOWS_HD inline float taylor_value(
            int index,
            int size,
            int nbar,
            const float *coefficients,
            int coefficient_count,
            float scale)
        {
            const float angle =
                (2.0 * kPi / static_cast<float>(size)) *
                (static_cast<float>(index) - static_cast<float>(size) / 2.0 + 0.5);

            float value = 1.0;
            for (int coefficient_index = 0; coefficient_index < coefficient_count; ++coefficient_index)
            {
                const int harmonic = coefficient_index + 1;
                if (harmonic >= nbar)
                {
                    break;
                }
                value += 2.0 * coefficients[coefficient_index] *
                         cos(angle * static_cast<float>(harmonic));
            }
            return value * scale;
        }

        inline void ensure_non_empty_coefficients(const core::RealSignal &coefficients)
        {
            if (coefficients.empty())
            {
                throw std::invalid_argument("coefficients must not be empty");
            }
        }

        inline core::RealSignal build_taylor_coefficients(int nbar, float sll)
        {
            if (nbar < 2)
            {
                throw std::invalid_argument("nbar must be >= 2");
            }
            if (!(sll > 0.0))
            {
                throw std::invalid_argument("sll must be > 0");
            }

            const float b = pow(10.0, sll / 20.0);
            const float a = acosh(b) / kPi;
            const float s2 = static_cast<float>(nbar * nbar) /
                              (a * a + pow(static_cast<float>(nbar) - 0.5, 2.0));

            core::RealSignal coefficients(static_cast<std::size_t>(nbar - 1), 0.0);
            for (int m = 1; m < nbar; ++m)
            {
                const float m2 = static_cast<float>(m * m);
                float numerator = (m % 2 == 1) ? 1.0 : -1.0;
                for (int n = 1; n < nbar; ++n)
                {
                    numerator *=
                        1.0 - m2 / (s2 * (a * a + pow(static_cast<float>(n) - 0.5, 2.0)));
                }

                float denominator = 2.0;
                for (int n = 1; n < nbar; ++n)
                {
                    if (n == m)
                    {
                        continue;
                    }
                    denominator *= 1.0 - m2 / static_cast<float>(n * n);
                }

                coefficients[static_cast<std::size_t>(m - 1)] = numerator / denominator;
            }
            return coefficients;
        }

        inline float taylor_scale(int size, int nbar, const core::RealSignal &coefficients, bool norm)
        {
            if (!norm)
            {
                return 1.0;
            }

            const float angle =
                (2.0 * kPi / static_cast<float>(size)) *
                (0.5 * static_cast<float>(size - 1) - static_cast<float>(size) / 2.0 + 0.5);

            float value = 1.0;
            const int count = std::min<int>(nbar - 1, static_cast<int>(coefficients.size()));
            for (int index = 0; index < count; ++index)
            {
                value += 2.0 * coefficients[static_cast<std::size_t>(index)] *
                         std::cos(angle * static_cast<float>(index + 1));
            }
            return 1.0 / value;
        }

        inline core::ComplexSignal build_chebwin_frequency_response(int size, float at)
        {
            if (!(at > 0.0))
            {
                throw std::invalid_argument("at must be > 0");
            }

            const float order = static_cast<float>(size - 1);
            const float beta = std::cosh(std::acosh(std::pow(10.0, std::abs(at) / 20.0)) / order);
            const bool odd = (size & 1) != 0;
            const float step = kPi / static_cast<float>(size);

            core::ComplexSignal values(static_cast<std::size_t>(size), core::Complex(0.0, 0.0));
            for (int index = 0; index < size; ++index)
            {
                const float x = beta * std::cos(static_cast<float>(index) * step);
                float real = 0.0;
                if (x > 1.0)
                {
                    real = std::cosh(order * std::acosh(x));
                }
                else if (x < -1.0)
                {
                    real = (odd ? 1.0 : -1.0) * std::cosh(order * std::acosh(-x));
                }
                else
                {
                    real = std::cos(order * std::acos(x));
                }

                if (odd)
                {
                    values[static_cast<std::size_t>(index)] = core::Complex(real, 0.0);
                }
                else
                {
                    const float phase = step * static_cast<float>(index);
                    values[static_cast<std::size_t>(index)] =
                        core::Complex(real * std::cos(phase), real * std::sin(phase));
                }
            }

            return values;
        }

        inline core::RealSignal rebuild_chebwin_from_fft(const core::ComplexSignal &values)
        {
            const int size = static_cast<int>(values.size());
            if (size == 0)
            {
                return {};
            }

            core::RealSignal output;
            if ((size & 1) != 0)
            {
                const int half = (size + 1) / 2;
                output.reserve(static_cast<std::size_t>(size));
                for (int index = half - 1; index >= 1; --index)
                {
                    output.push_back(values[static_cast<std::size_t>(index)].real());
                }
                for (int index = 0; index < half; ++index)
                {
                    output.push_back(values[static_cast<std::size_t>(index)].real());
                }
            }
            else
            {
                const int half = size / 2 + 1;
                output.reserve(static_cast<std::size_t>(size));
                for (int index = half - 1; index >= 1; --index)
                {
                    output.push_back(values[static_cast<std::size_t>(index)].real());
                }
                for (int index = 1; index < half; ++index)
                {
                    output.push_back(values[static_cast<std::size_t>(index)].real());
                }
            }

            const float max_value = *std::max_element(output.begin(), output.end());
            for (float &value : output)
            {
                value /= max_value;
            }
            return output;
        }
    } // namespace windows_detail
} // namespace cusignal
