#pragma once

#include <cmath>
#include <stdexcept>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal::demod_detail
{
    using core::Complex;
    using core::ComplexArray;
    using core::RealArray;
    using core::RealSignal;

    constexpr float kPi = 3.141592653589793238462643383279502884f;
    constexpr float kTwoPi = 2.0f * kPi;

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
