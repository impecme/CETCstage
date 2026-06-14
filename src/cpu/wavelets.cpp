#include "cusignal/wavelets/wavelets.hpp"

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstddef>
#include <vector>

#include "cusignal/core/helpers.hpp"

#include "../common/wavelets_detail.hpp"

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::RealSignal;
    namespace detail = cusignal::wavelets_detail;

    std::size_t to_size(int value)
    {
        return value > 0 ? static_cast<std::size_t>(value) : 0;
    }

    ComplexSignal compute_cwt(
        const RealSignal &data,
        const std::string &wavelet,
        const RealSignal &widths)
    {
        const detail::CwtKernelTable kernel_table =
            detail::build_cwt_kernel_table(widths, data.size(), wavelet);

        const std::size_t signal_size = data.size();
        ComplexSignal values(widths.size() * signal_size, Complex(0.0, 0.0));
        if (signal_size == 0)
        {
            return values;
        }

        for (std::size_t row = 0; row < widths.size(); ++row)
        {
            const int kernel_size = kernel_table.kernel_sizes[row];
            const int start = kernel_table.kernel_starts[row];
            const int kernel_offset = kernel_table.kernel_offsets[row];
            if (kernel_size <= 0)
            {
                continue;
            }

            for (std::size_t col = 0; col < signal_size; ++col)
            {
                float real = 0.0f;
                float imag = 0.0f;
                for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
                {
                    const long x_index =
                        static_cast<long>(col) + static_cast<long>(start) -
                        static_cast<long>(kernel_index);
                    if (x_index < 0 || x_index >= static_cast<long>(signal_size))
                    {
                        continue;
                    }

                    const float sample = static_cast<float>(data[static_cast<std::size_t>(x_index)]);
                    const std::size_t table_index =
                        static_cast<std::size_t>(kernel_offset + kernel_index);
                    real = std::fmaf(sample, kernel_table.kernel_real[table_index], real);
                    imag = std::fmaf(sample, kernel_table.kernel_imag[table_index], imag);
                }
                values[row * signal_size + col] = Complex(real, imag);
            }
        }
        return values;
    }
} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace wavelets
        {

            core::RealSignal qmf(const core::RealSignal &hk)
            {
                RealSignal output(hk.size(), 0.0);
                for (std::size_t index = 0; index < hk.size(); ++index)
                {
                    const float sign = (index % 2 == 0) ? 1.0 : -1.0;
                    output[index] = hk[hk.size() - 1 - index] * sign;
                }
                return output;
            }

            core::ComplexSignal morlet(int points, float w, float s, bool complete)
            {
                detail::ensure_non_negative_points(points);
                detail::ensure_positive(s, "s");

                ComplexSignal output(to_size(points), Complex(0.0, 0.0));
                for (std::size_t index = 0; index < output.size(); ++index)
                {
                    const detail::ComplexParts value =
                        detail::morlet_value(index, output.size(), w, s, complete);
                    output[index] = Complex(value.real, value.imag);
                }
                return output;
            }

            core::RealSignal ricker(int points, float a)
            {
                detail::ensure_non_negative_points(points);
                detail::ensure_positive(a, "a");

                RealSignal output(to_size(points), 0.0);
                for (std::size_t index = 0; index < output.size(); ++index)
                {
                    output[index] = detail::ricker_value(index, output.size(), a);
                }
                return output;
            }

            core::ComplexSignal morlet2(int points, float s, float w)
            {
                detail::ensure_non_negative_points(points);
                detail::ensure_positive(s, "s");

                ComplexSignal output(to_size(points), Complex(0.0, 0.0));
                for (std::size_t index = 0; index < output.size(); ++index)
                {
                    const detail::ComplexParts value =
                        detail::morlet2_value(index, output.size(), s, w);
                    output[index] = Complex(value.real, value.imag);
                }
                return output;
            }

            core::ComplexArray cwt(
                const core::RealSignal &data,
                const std::string &wavelet,
                const core::RealSignal &widths)
            {
                ComplexArray output;
                output.shape = {widths.size(), data.size()};
                output.values = compute_cwt(data, wavelet, widths);
                return output;
            }

        } // namespace wavelets
    } // namespace cpu
} // namespace cusignal
