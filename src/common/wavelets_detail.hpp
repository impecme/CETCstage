#pragma once

#include <algorithm>
#include <cstddef>
#include <cmath>
#include <stdexcept>
#include <string>
#include <vector>

#ifdef __CUDACC__
#define CUSIGNAL_WAVELETS_HD __host__ __device__
#else
#define CUSIGNAL_WAVELETS_HD
#endif

namespace cusignal
{
    namespace wavelets_detail
    {
        constexpr float kPi = 3.141592653589793238462643383279502884;
        constexpr float kTwoPi = 2.0 * kPi;
        constexpr float kPiNegQuarter = 0.751125544464942482858703004776227693;

        struct ComplexParts
        {
            float real = 0.0;
            float imag = 0.0;
        };

        struct CwtKernelTable
        {
            std::vector<int> kernel_sizes;
            std::vector<int> kernel_starts;
            std::vector<int> kernel_offsets;
            std::vector<float> kernel_real;
            std::vector<float> kernel_imag;
        };

        inline void ensure_non_negative_points(int points)
        {
            if (points < 0)
            {
                throw std::invalid_argument("points must be >= 0");
            }
        }

        inline void ensure_positive(float value, const char *name)
        {
            if (!(value > 0.0))
            {
                throw std::invalid_argument(std::string(name) + " must be > 0");
            }
        }

        inline void ensure_non_empty_widths(std::size_t count)
        {
            if (count == 0)
            {
                throw std::invalid_argument("widths must not be empty");
            }
        }

        inline void ensure_supported_wavelet(const std::string &wavelet)
        {
            if (wavelet != "ricker" && wavelet != "morlet2")
            {
                throw std::invalid_argument("wavelet must be ricker or morlet2");
            }
        }

        inline void ensure_positive_widths(const std::vector<float> &widths)
        {
            for (float width : widths)
            {
                if (!(width > 0.0) || static_cast<int>(width) <= 0)
                {
                    throw std::invalid_argument("widths must be > 0 and produce positive integral widths");
                }
            }
        }

        CUSIGNAL_WAVELETS_HD inline float centered_coordinate(std::size_t index, std::size_t points)
        {
            return static_cast<float>(index) - (static_cast<float>(points) - 1.0) * 0.5;
        }

        CUSIGNAL_WAVELETS_HD inline float morlet_coordinate(
            std::size_t index,
            std::size_t points,
            float s)
        {
            if (points <= 1)
            {
                return 0.0;
            }
            const float start = -s * kTwoPi;
            const float stop = s * kTwoPi;
            const float step = (stop - start) / static_cast<float>(points - 1);
            return start + step * static_cast<float>(index);
        }

        CUSIGNAL_WAVELETS_HD inline ComplexParts morlet_value(
            std::size_t index,
            std::size_t points,
            float w,
            float s,
            bool complete)
        {
            const float x = morlet_coordinate(index, points, s);
            const float gaussian = std::exp(-0.5 * x * x) * kPiNegQuarter;
            const float correction = complete ? std::exp(-0.5 * w * w) : 0.0;
            return ComplexParts{
                (std::cos(w * x) - correction) * gaussian,
                std::sin(w * x) * gaussian};
        }

        CUSIGNAL_WAVELETS_HD inline float ricker_value(
            std::size_t index,
            std::size_t points,
            float a)
        {
            const float x = centered_coordinate(index, points);
            const float xsq = x * x;
            const float a_sq = a * a;
            const float amplitude =
                2.0 / (std::sqrt(3.0 * a) * std::pow(kPi, 0.25));
            return amplitude * (1.0 - xsq / a_sq) * std::exp(-xsq / (2.0 * a_sq));
        }

        CUSIGNAL_WAVELETS_HD inline ComplexParts morlet2_value(
            std::size_t index,
            std::size_t points,
            float s,
            float w)
        {
            const float x = centered_coordinate(index, points) / s;
            const float amplitude = std::sqrt(1.0 / s) * kPiNegQuarter * std::exp(-0.5 * x * x);
            return ComplexParts{
                std::cos(w * x) * amplitude,
                std::sin(w * x) * amplitude};
        }

        CUSIGNAL_WAVELETS_HD inline ComplexParts reverse_conjugated_ricker(
            std::size_t kernel_index,
            std::size_t kernel_size,
            float width)
        {
            return ComplexParts{
                ricker_value(kernel_size - 1 - kernel_index, kernel_size, width),
                0.0};
        }

        CUSIGNAL_WAVELETS_HD inline ComplexParts reverse_conjugated_morlet2(
            std::size_t kernel_index,
            std::size_t kernel_size,
            float width,
            float w = 5.0)
        {
            const ComplexParts value =
                morlet2_value(kernel_size - 1 - kernel_index, kernel_size, width, w);
            return ComplexParts{value.real, -value.imag};
        }

        inline CwtKernelTable build_cwt_kernel_table(
            const std::vector<float> &widths,
            std::size_t data_count,
            const std::string &wavelet)
        {
            ensure_supported_wavelet(wavelet);
            ensure_non_empty_widths(widths.size());
            ensure_positive_widths(widths);

            CwtKernelTable table;
            table.kernel_sizes.resize(widths.size(), 0);
            table.kernel_starts.resize(widths.size(), 0);
            table.kernel_offsets.resize(widths.size() + 1, 0);

            std::size_t kernel_total = 0;
            for (std::size_t row = 0; row < widths.size(); ++row)
            {
                table.kernel_offsets[row] = static_cast<int>(kernel_total);

                const int integral_width = static_cast<int>(widths[row]);
                if (integral_width <= 0 || data_count == 0)
                {
                    continue;
                }

                const std::size_t kernel_size = std::min<std::size_t>(
                    static_cast<std::size_t>(10 * integral_width),
                    data_count);
                table.kernel_sizes[row] = static_cast<int>(kernel_size);
                table.kernel_starts[row] = static_cast<int>((kernel_size - 1) / 2);
                kernel_total += kernel_size;
            }
            table.kernel_offsets[widths.size()] = static_cast<int>(kernel_total);

            table.kernel_real.resize(kernel_total, 0.0f);
            table.kernel_imag.resize(kernel_total, 0.0f);

            const bool use_ricker = (wavelet == "ricker");
            for (std::size_t row = 0; row < widths.size(); ++row)
            {
                const int kernel_size = table.kernel_sizes[row];
                if (kernel_size <= 0)
                {
                    continue;
                }

                const int kernel_offset = table.kernel_offsets[row];
                for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
                {
                    const ComplexParts wavelet_value = use_ricker
                        ? reverse_conjugated_ricker(
                              static_cast<std::size_t>(kernel_index),
                              static_cast<std::size_t>(kernel_size),
                              widths[row])
                        : reverse_conjugated_morlet2(
                              static_cast<std::size_t>(kernel_index),
                              static_cast<std::size_t>(kernel_size),
                              widths[row]);
                    table.kernel_real[static_cast<std::size_t>(kernel_offset + kernel_index)] = wavelet_value.real;
                    table.kernel_imag[static_cast<std::size_t>(kernel_offset + kernel_index)] = wavelet_value.imag;
                }
            }

            return table;
        }

    } // namespace wavelets_detail
} // namespace cusignal
