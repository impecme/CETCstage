#pragma once

#include <cmath>
#include <stdexcept>

#ifdef __CUDACC__
#define CUSIGNAL_BSPLINES_HD __host__ __device__
#else
#define CUSIGNAL_BSPLINES_HD
#endif

namespace cusignal
{
    namespace bsplines_detail
    {
        constexpr float kPi = 3.14159265358979323846;

        CUSIGNAL_BSPLINES_HD inline float cubic_value(float x)
        {
            const float ax = fabs(x);
            if (ax < 1.0)
            {
                return 2.0 / 3.0 - 0.5 * ax * ax * (2.0 - ax);
            }
            if (ax < 2.0)
            {
                const float term = 2.0 - ax;
                return term * term * term / 6.0;
            }
            return 0.0;
        }

        CUSIGNAL_BSPLINES_HD inline float quadratic_value(float x)
        {
            const float ax = fabs(x);
            if (ax < 0.5)
            {
                return 0.75 - ax * ax;
            }
            if (ax < 1.5)
            {
                const float term = ax - 1.5;
                return 0.5 * term * term;
            }
            return 0.0;
        }

        CUSIGNAL_BSPLINES_HD inline float gauss_spline_sigma_squared(int n)
        {
            return static_cast<float>(n + 1) / 12.0;
        }

        CUSIGNAL_BSPLINES_HD inline float gauss_spline_value(float x, int n)
        {
            const float sigma_squared = gauss_spline_sigma_squared(n);
            const float inv_sigma_factor = 0.5 / sigma_squared;
            return exp(-(x * x) * inv_sigma_factor) /
                   sqrt(2.0 * kPi * sigma_squared);
        }

        inline void ensure_non_negative_order(int n)
        {
            if (n < 0)
            {
                throw std::invalid_argument("n must be non-negative");
            }
        }

    } // namespace bsplines_detail
} // namespace cusignal