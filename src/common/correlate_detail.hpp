#pragma once

#include <algorithm>
#include <complex>
#include <cstddef>
#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal::correlate_detail
{
    using core::Complex;
    using core::ComplexArray;
    using core::ComplexSignal;
    using core::RealArray;
    using core::RealSignal;
    using core::Shape;

    inline std::string normalize_mode(const std::string &mode)
    {
        if (mode == "full" || mode == "same" || mode == "valid")
        {
            return mode;
        }
        throw std::invalid_argument("mode must be one of full/same/valid");
    }

    inline std::string normalize_method(const std::string &method)
    {
        if (method == "auto" || method == "direct" || method == "fft")
        {
            return method;
        }
        throw std::invalid_argument("method must be one of auto/direct/fft");
    }

    inline std::string normalize_boundary(const std::string &boundary)
    {
        if (boundary == "fill" || boundary == "wrap" || boundary == "symm")
        {
            return boundary;
        }
        throw std::invalid_argument("boundary must be one of fill/wrap/symm");
    }

    inline void ensure_same_rank(const Shape &left, const Shape &right)
    {
        if (left.size() != right.size())
        {
            throw std::invalid_argument("input ranks must match");
        }
    }

    inline void ensure_valid_compatible(const Shape &left, const Shape &right)
    {
        bool left_ok = true;
        bool right_ok = true;
        for (std::size_t axis = 0; axis < left.size(); ++axis)
        {
            left_ok = left_ok && left[axis] >= right[axis];
            right_ok = right_ok && right[axis] >= left[axis];
        }
        if (!(left_ok || right_ok))
        {
            throw std::invalid_argument(
                "For valid mode, one input must be at least as large as the other in every dimension");
        }
    }

    inline Shape full_shape(const Shape &left, const Shape &right)
    {
        ensure_same_rank(left, right);
        Shape shape(left.size(), 0);
        for (std::size_t axis = 0; axis < left.size(); ++axis)
        {
            shape[axis] = left[axis] + right[axis] - 1;
        }
        return shape;
    }

    inline Shape output_shape(
        const Shape &left,
        const Shape &right,
        const std::string &mode)
    {
        const std::string normalized_mode = normalize_mode(mode);
        ensure_same_rank(left, right);
        if (normalized_mode == "full")
        {
            return full_shape(left, right);
        }
        if (normalized_mode == "same")
        {
            return left;
        }

        ensure_valid_compatible(left, right);
        Shape shape(left.size(), 0);
        for (std::size_t axis = 0; axis < left.size(); ++axis)
        {
            const std::size_t larger = std::max(left[axis], right[axis]);
            const std::size_t smaller = std::min(left[axis], right[axis]);
            shape[axis] = larger - smaller + 1;
        }
        return shape;
    }

    inline Shape crop_start(
        const Shape &left,
        const Shape &right,
        const std::string &mode)
    {
        const std::string normalized_mode = normalize_mode(mode);
        const Shape full = full_shape(left, right);
        Shape start(left.size(), 0);
        if (normalized_mode == "full")
        {
            return start;
        }
        if (normalized_mode == "same")
        {
            for (std::size_t axis = 0; axis < full.size(); ++axis)
            {
                start[axis] = full[axis] / 2 - left[axis] / 2;
            }
            return start;
        }
        ensure_valid_compatible(left, right);
        for (std::size_t axis = 0; axis < full.size(); ++axis)
        {
            start[axis] = std::min(left[axis], right[axis]) - 1;
        }
        return start;
    }

    inline std::vector<std::size_t> compute_strides(const Shape &shape)
    {
        std::vector<std::size_t> strides(shape.size(), 1);
        for (std::size_t index = shape.size(); index-- > 1;)
        {
            strides[index - 1] = strides[index] * shape[index];
        }
        return strides;
    }

    inline std::vector<std::size_t> unravel_index(
        std::size_t flat_index,
        const Shape &shape,
        const std::vector<std::size_t> &strides)
    {
        std::vector<std::size_t> coords(shape.size(), 0);
        for (std::size_t axis = 0; axis < shape.size(); ++axis)
        {
            coords[axis] = flat_index / strides[axis];
            flat_index %= strides[axis];
        }
        return coords;
    }

    inline std::size_t ravel_index(
        const std::vector<std::size_t> &coords,
        const std::vector<std::size_t> &strides)
    {
        std::size_t flat_index = 0;
        for (std::size_t axis = 0; axis < coords.size(); ++axis)
        {
            flat_index += coords[axis] * strides[axis];
        }
        return flat_index;
    }

    inline bool should_use_direct_1d(
        const Shape &left,
        const Shape &right,
        const std::string &method)
    {
        const std::string normalized_method = normalize_method(method);
        if (normalized_method == "direct")
        {
            return true;
        }
        if (normalized_method == "fft")
        {
            return false;
        }
        return left.size() == 1 && right.size() == 1 &&
               left.front() * right.front() <= 4096;
    }

    template <typename T>
    inline std::vector<Complex> as_complex_vector(const std::vector<T> &values)
    {
        std::vector<Complex> converted(values.size(), Complex(0.0f, 0.0f));
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            converted[index] = static_cast<Complex>(values[index]);
        }
        return converted;
    }

    inline std::vector<Complex> as_complex_vector(const ComplexSignal &values)
    {
        std::vector<Complex> converted(values.size(), Complex(0.0f, 0.0f));
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            converted[index] = values[index];
        }
        return converted;
    }

    template <typename T>
    inline std::vector<Complex> direct_correlate_1d(
        const std::vector<T> &left,
        const std::vector<T> &right)
    {
        const std::size_t n1 = left.size();
        const std::size_t n2 = right.size();
        std::vector<Complex> output(
            n1 + n2 - 1,
            Complex(0.0f, 0.0f));
        for (std::size_t out_index = 0; out_index < output.size(); ++out_index)
        {
            const long long lag =
                static_cast<long long>(out_index) - static_cast<long long>(n2 - 1);
            Complex accum(0.0f, 0.0f);
            for (std::size_t index = 0; index < n1; ++index)
            {
                const long long right_index =
                    static_cast<long long>(index) - lag;
                if (right_index < 0 || right_index >= static_cast<long long>(n2))
                {
                    continue;
                }
                accum += static_cast<Complex>(left[index]) *
                         std::conj(static_cast<Complex>(right[static_cast<std::size_t>(right_index)]));
            }
            output[out_index] = accum;
        }
        return output;
    }

    inline std::vector<Complex> direct_correlate_1d(
        const ComplexSignal &left,
        const ComplexSignal &right)
    {
        const std::size_t n1 = left.size();
        const std::size_t n2 = right.size();
        std::vector<Complex> output(
            n1 + n2 - 1,
            Complex(0.0f, 0.0f));
        for (std::size_t out_index = 0; out_index < output.size(); ++out_index)
        {
            const long long lag =
                static_cast<long long>(out_index) - static_cast<long long>(n2 - 1);
            Complex accum(0.0f, 0.0f);
            for (std::size_t index = 0; index < n1; ++index)
            {
                const long long right_index =
                    static_cast<long long>(index) - lag;
                if (right_index < 0 || right_index >= static_cast<long long>(n2))
                {
                    continue;
                }
                const Complex left_value = left[index];
                const Complex right_value = right[static_cast<std::size_t>(right_index)];
                accum += left_value * std::conj(right_value);
            }
            output[out_index] = accum;
        }
        return output;
    }

    inline std::vector<Complex> crop_1d(
        const std::vector<Complex> &full,
        std::size_t left_size,
        std::size_t right_size,
        const std::string &mode)
    {
        const Shape left{left_size};
        const Shape right{right_size};
        const Shape out_shape = output_shape(left, right, mode);
        const Shape start = crop_start(left, right, mode);
        return std::vector<Complex>(
            full.begin() + static_cast<long long>(start.front()),
            full.begin() + static_cast<long long>(start.front() + out_shape.front()));
    }
} // namespace cusignal::correlate_detail
