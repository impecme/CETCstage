#pragma once

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <string>
#include <variant>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal::radartools_detail
{
    constexpr float kPi = 3.141592653589793238462643383279502884;

    inline void ensure_positive(float value, const std::string &name)
    {
        if (!(value > 0.0))
        {
            throw std::invalid_argument(name + " must be > 0");
        }
    }

    inline void ensure_probability(float pfa)
    {
        if (!(pfa > 0.0 && pfa < 1.0))
        {
            throw std::invalid_argument("pfa must be in (0, 1)");
        }
    }

    template <typename ArrayType>
    inline void ensure_rank(const ArrayType &array, std::size_t rank, const char *name)
    {
        if (array.rank() != rank)
        {
            throw std::invalid_argument(std::string(name) + " must have the expected rank");
        }
    }

    inline std::string normalize_cut(const std::string &cut)
    {
        if (cut == "2d" || cut == "delay" || cut == "doppler")
        {
            return cut;
        }
        throw std::invalid_argument("cut must be 2d/delay/doppler");
    }

    inline bool window_disabled(const core::WindowSpec &window)
    {
        if (const auto *name = std::get_if<std::string>(&window))
        {
            return name->empty();
        }
        return false;
    }

    inline bool window_disabled(const core::CudaWindowSpec &window)
    {
        if (const auto *name = std::get_if<std::string>(&window))
        {
            return name->empty();
        }
        return false;
    }

    inline int next_power_of_two(int value)
    {
        int result = 1;
        while (result < value)
        {
            result <<= 1;
        }
        return result;
    }

    inline core::RealSignal build_delay_axis(std::size_t xlen, std::size_t ylen, float fs)
    {
        core::RealSignal axis(xlen + ylen - 1, 0.0);
        const float scale = 1.0 / fs;
        const long long origin = static_cast<long long>(xlen) - 1;
        for (std::size_t index = 0; index < axis.size(); ++index)
        {
            axis[index] = static_cast<float>(static_cast<long long>(index) - origin) * scale;
        }
        return axis;
    }

    inline core::RealSignal build_doppler_axis(std::size_t nfreq, float fs)
    {
        core::RealSignal axis(nfreq, 0.0);
        const float start = -0.5 * fs;
        const float step = fs / static_cast<float>(nfreq);
        for (std::size_t index = 0; index < nfreq; ++index)
        {
            axis[index] = start + step * static_cast<float>(index);
        }
        return axis;
    }

    inline core::ComplexSignal normalize_l2(const core::ComplexSignal &signal)
    {
        if (signal.empty())
        {
            throw std::invalid_argument("signal must not be empty");
        }
        float norm_sq = 0.0;
        for (const core::Complex &value : signal)
        {
            norm_sq += std::norm(value);
        }
        if (!(norm_sq > 0.0))
        {
            throw std::invalid_argument("signal norm must be > 0");
        }
        const float inv_norm = 1.0 / std::sqrt(norm_sq);
        core::ComplexSignal normalized(signal.size(), core::Complex(0.0, 0.0));
        for (std::size_t index = 0; index < signal.size(); ++index)
        {
            normalized[index] = signal[index] * inv_norm;
        }
        return normalized;
    }

    inline core::ComplexSignal apply_window(
        const core::ComplexSignal &values,
        const core::RealSignal &window)
    {
        if (values.size() != window.size())
        {
            throw std::invalid_argument("window must have the same length as data");
        }
        core::ComplexSignal output(values.size(), core::Complex(0.0, 0.0));
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            output[index] = values[index] * window[index];
        }
        return output;
    }

    inline core::Complex conjugate_dot(
        const core::ComplexSignal &lhs,
        const core::ComplexSignal &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::invalid_argument("dot inputs must have the same size");
        }
        core::Complex result(0.0, 0.0);
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            result += std::conj(lhs[index]) * rhs[index];
        }
        return result;
    }

    inline core::ComplexArray covariance_matrix(const core::ComplexArray &x)
    {
        ensure_rank(x, 2, "x");
        const std::size_t sensors = x.shape[0];
        const std::size_t snapshots = x.shape[1];
        if (sensors == 0 || snapshots == 0)
        {
            throw std::invalid_argument("x must not be empty");
        }
        if (sensors > snapshots)
        {
            throw std::invalid_argument(
                "Matrix has more sensors than samples. Consider transposing and remember cuSignal is row-major, unlike MATLAB");
        }
        if (snapshots < 2)
        {
            throw std::invalid_argument("calc_cov requires at least two snapshots");
        }

        core::ComplexArray cov = core::make_complex_array(core::Shape{sensors, sensors});
        std::vector<core::Complex> means(sensors, core::Complex(0.0, 0.0));
        for (std::size_t sensor = 0; sensor < sensors; ++sensor)
        {
            core::Complex sum(0.0, 0.0);
            const std::size_t base = sensor * snapshots;
            for (std::size_t sample = 0; sample < snapshots; ++sample)
            {
                sum += x.values[base + sample];
            }
            means[sensor] = sum / static_cast<float>(snapshots);
        }

        const float scale = 1.0 / static_cast<float>(snapshots - 1);
        for (std::size_t row = 0; row < sensors; ++row)
        {
            for (std::size_t col = 0; col < sensors; ++col)
            {
                core::Complex accum(0.0, 0.0);
                const std::size_t row_base = row * snapshots;
                const std::size_t col_base = col * snapshots;
                for (std::size_t sample = 0; sample < snapshots; ++sample)
                {
                    const core::Complex row_value = x.values[row_base + sample] - means[row];
                    const core::Complex col_value = x.values[col_base + sample] - means[col];
                    accum += row_value * std::conj(col_value);
                }
                cov.values[row * sensors + col] = accum * scale;
            }
        }
        return cov;
    }

    inline core::ComplexSignal solve_linear_system(
        const core::ComplexArray &matrix,
        const core::ComplexSignal &rhs)
    {
        ensure_rank(matrix, 2, "matrix");
        if (matrix.shape[0] != matrix.shape[1])
        {
            throw std::invalid_argument("matrix must be square");
        }
        const std::size_t n = matrix.shape[0];
        if (rhs.size() != n)
        {
            throw std::invalid_argument("rhs size must match matrix dimension");
        }

        std::vector<core::Complex> a = matrix.values;
        core::ComplexSignal b = rhs;

        for (std::size_t pivot = 0; pivot < n; ++pivot)
        {
            std::size_t max_row = pivot;
            float max_norm = std::abs(a[pivot * n + pivot]);
            for (std::size_t row = pivot + 1; row < n; ++row)
            {
                const float candidate = std::abs(a[row * n + pivot]);
                if (candidate > max_norm)
                {
                    max_norm = candidate;
                    max_row = row;
                }
            }
            if (!(max_norm > 0.0))
            {
                throw std::invalid_argument("matrix is singular");
            }
            if (max_row != pivot)
            {
                for (std::size_t col = pivot; col < n; ++col)
                {
                    std::swap(a[pivot * n + col], a[max_row * n + col]);
                }
                std::swap(b[pivot], b[max_row]);
            }

            const core::Complex diag = a[pivot * n + pivot];
            for (std::size_t row = pivot + 1; row < n; ++row)
            {
                const core::Complex factor = a[row * n + pivot] / diag;
                a[row * n + pivot] = core::Complex(0.0, 0.0);
                for (std::size_t col = pivot + 1; col < n; ++col)
                {
                    a[row * n + col] -= factor * a[pivot * n + col];
                }
                b[row] -= factor * b[pivot];
            }
        }

        core::ComplexSignal x(n, core::Complex(0.0, 0.0));
        for (std::ptrdiff_t row = static_cast<std::ptrdiff_t>(n) - 1; row >= 0; --row)
        {
            core::Complex value = b[static_cast<std::size_t>(row)];
            for (std::size_t col = static_cast<std::size_t>(row) + 1; col < n; ++col)
            {
                value -= a[static_cast<std::size_t>(row) * n + col] * x[col];
            }
            x[static_cast<std::size_t>(row)] = value / a[static_cast<std::size_t>(row) * n + static_cast<std::size_t>(row)];
        }
        return x;
    }
} // namespace cusignal::radartools_detail
