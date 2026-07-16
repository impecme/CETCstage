#pragma once

#include <cmath>
#include <stdexcept>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

#ifdef __CUDACC__
#define CUSIGNAL_DEMOD_HD __host__ __device__
#else
#define CUSIGNAL_DEMOD_HD
#endif

namespace cusignal::demod_detail
{
    using core::Complex;
    using core::ComplexArray;
    using core::RealArray;
    using core::RealSignal;

    constexpr float kPi = 3.141592653589793238462643383279502884f;
    constexpr float kTwoPi = 2.0f * kPi;
    constexpr float kSafeProductScaleMin = 0x1.0p-50f;
    constexpr float kSafeProductScaleMax = 0x1.0p+50f;

    CUSIGNAL_DEMOD_HD inline float wrap_phase_difference(float delta)
    {
        if (delta > kPi)
        {
            return delta - kTwoPi;
        }
        if (delta < -kPi)
        {
            return delta + kTwoPi;
        }
        return delta;
    }

    CUSIGNAL_DEMOD_HD inline bool finite_component(float value)
    {
#if defined(__CUDA_ARCH__)
        return isfinite(value);
#else
        return std::isfinite(value);
#endif
    }

    CUSIGNAL_DEMOD_HD inline float wrapped_phase_difference(
        float current_real,
        float current_imag,
        float next_real,
        float next_imag)
    {
        const float current_scale = fmaxf(fabsf(current_real), fabsf(current_imag));
        const float next_scale = fmaxf(fabsf(next_real), fabsf(next_imag));
        if (!(current_scale > 0.0f) || !(next_scale > 0.0f) ||
            !finite_component(current_scale) || !finite_component(next_scale))
        {
            return wrap_phase_difference(
                atan2f(next_imag, next_real) - atan2f(current_imag, current_real));
        }

        if (current_scale >= kSafeProductScaleMin &&
            current_scale <= kSafeProductScaleMax &&
            next_scale >= kSafeProductScaleMin &&
            next_scale <= kSafeProductScaleMax)
        {
            const float real = next_real * current_real + next_imag * current_imag;
            const float imag = next_imag * current_real - next_real * current_imag;
            return atan2f(imag, real);
        }

        current_real /= current_scale;
        current_imag /= current_scale;
        next_real /= next_scale;
        next_imag /= next_scale;
        const float real = next_real * current_real + next_imag * current_imag;
        const float imag = next_imag * current_real - next_real * current_imag;
        return atan2f(imag, real);
    }

    inline RealSignal unwrap_phase(const RealSignal &phase)
    {
        if (phase.empty())
        {
            return {};
        }
        RealSignal output = phase;
        float offset = 0.0f;
        for (std::size_t index = 1; index < output.size(); ++index)
        {
            const float delta = phase[index] - phase[index - 1];
            if (delta > kPi)
            {
                offset -= kTwoPi;
            }
            else if (delta < -kPi)
            {
                offset += kTwoPi;
            }
            output[index] += offset;
        }
        return output;
    }

    inline RealSignal diff_phase(const RealSignal &phase)
    {
        if (phase.size() < 2)
        {
            return {};
        }
        RealSignal output(phase.size() - 1, 0.0f);
        for (std::size_t index = 0; index + 1 < phase.size(); ++index)
        {
            output[index] = phase[index + 1] - phase[index];
        }
        return output;
    }
} // namespace cusignal::demod_detail
