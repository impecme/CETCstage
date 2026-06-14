#include "cusignal/correlate/correlate.hpp"

#include <algorithm>
#include <complex>
#include <stdexcept>
#include <vector>

#include "../common/correlate_detail.hpp"

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::RealArray;
    using cusignal::core::Shape;
    namespace detail = cusignal::correlate_detail;

    template <typename ArrayType, typename ValueType, typename AccumulatorType, typename KernelValueFn>
    ArrayType correlate_nd_impl(
        const ArrayType &in1,
        const ArrayType &in2,
        const std::string &mode,
        KernelValueFn kernel_value)
    {
        detail::ensure_same_rank(in1.shape, in2.shape);
        const std::string normalized_mode = detail::normalize_mode(mode);
        if (normalized_mode == "valid")
        {
            detail::ensure_valid_compatible(in1.shape, in2.shape);
        }

        const Shape output_shape = detail::output_shape(in1.shape, in2.shape, normalized_mode);
        const Shape start = detail::crop_start(in1.shape, in2.shape, normalized_mode);
        ArrayType output;
        output.shape = output_shape;
        output.values.assign(cusignal::core::shape_product(output_shape), ValueType{});
        if (output.values.empty())
        {
            return output;
        }

        const std::vector<std::size_t> in1_strides = detail::compute_strides(in1.shape);
        const std::vector<std::size_t> in2_strides = detail::compute_strides(in2.shape);
        const std::vector<std::size_t> out_strides = detail::compute_strides(output_shape);

        for (std::size_t out_index = 0; out_index < output.values.size(); ++out_index)
        {
            const std::vector<std::size_t> out_coords =
                detail::unravel_index(out_index, output_shape, out_strides);
            AccumulatorType accum = AccumulatorType{};

            for (std::size_t kernel_index = 0; kernel_index < in2.values.size(); ++kernel_index)
            {
                const std::vector<std::size_t> kernel_coords =
                    detail::unravel_index(kernel_index, in2.shape, in2_strides);
                bool in_bounds = true;
                std::size_t input_flat = 0;
                for (std::size_t axis = 0; axis < output_shape.size(); ++axis)
                {
                    const long long full_coord =
                        static_cast<long long>(out_coords[axis] + start[axis]);
                    const long long input_coord =
                        full_coord + static_cast<long long>(kernel_coords[axis]) -
                        static_cast<long long>(in2.shape[axis] - 1);
                    if (input_coord < 0 ||
                        input_coord >= static_cast<long long>(in1.shape[axis]))
                    {
                        in_bounds = false;
                        break;
                    }
                    input_flat +=
                        static_cast<std::size_t>(input_coord) * in1_strides[axis];
                }
                if (!in_bounds)
                {
                    continue;
                }

                accum +=
                    static_cast<AccumulatorType>(in1.values[input_flat]) * kernel_value(in2.values[kernel_index]);
            }

            output.values[out_index] = static_cast<ValueType>(accum);
        }

        return output;
    }

    inline std::size_t symmetric_index(long long index, std::size_t size)
    {
        if (size == 0)
        {
            return 0;
        }
        if (size == 1)
        {
            return 0;
        }
        const long long period = 2LL * static_cast<long long>(size);
        while (index < 0 || index >= static_cast<long long>(size))
        {
            if (index < 0)
            {
                index = -index - 1;
            }
            else
            {
                index = period - index - 1;
            }
        }
        return static_cast<std::size_t>(index);
    }

    inline std::size_t wrapped_index(long long index, std::size_t size)
    {
        const long long mod = index % static_cast<long long>(size);
        return static_cast<std::size_t>(mod < 0 ? mod + static_cast<long long>(size) : mod);
    }

    template <typename ArrayType, typename ValueType, typename AccumulatorType, typename FillType, typename KernelValueFn>
    ArrayType correlate2d_impl(
        const ArrayType &in1,
        const ArrayType &in2,
        const std::string &mode,
        const std::string &boundary,
        const FillType &fillvalue,
        KernelValueFn kernel_value)
    {
        if (in1.rank() != 2 || in2.rank() != 2)
        {
            throw std::invalid_argument("correlate2d inputs must both be rank-2");
        }

        const std::string normalized_mode = detail::normalize_mode(mode);
        const std::string normalized_boundary = detail::normalize_boundary(boundary);
        if (normalized_mode == "valid")
        {
            detail::ensure_valid_compatible(in1.shape, in2.shape);
        }

        const Shape output_shape = detail::output_shape(in1.shape, in2.shape, normalized_mode);
        const Shape start = detail::crop_start(in1.shape, in2.shape, normalized_mode);
        ArrayType output;
        output.shape = output_shape;
        output.values.assign(cusignal::core::shape_product(output_shape), ValueType{});
        if (output.values.empty())
        {
            return output;
        }

        const std::size_t rows1 = in1.shape[0];
        const std::size_t cols1 = in1.shape[1];
        const std::size_t rows2 = in2.shape[0];
        const std::size_t cols2 = in2.shape[1];
        const std::size_t out_rows = output_shape[0];
        const std::size_t out_cols = output_shape[1];

        for (std::size_t row = 0; row < out_rows; ++row)
        {
            for (std::size_t col = 0; col < out_cols; ++col)
            {
                const long long full_row = static_cast<long long>(row + start[0]);
                const long long full_col = static_cast<long long>(col + start[1]);
                AccumulatorType accum = AccumulatorType{};
                for (std::size_t kr = 0; kr < rows2; ++kr)
                {
                    for (std::size_t kc = 0; kc < cols2; ++kc)
                    {
                        const long long input_row =
                            full_row + static_cast<long long>(kr) - static_cast<long long>(rows2 - 1);
                        const long long input_col =
                            full_col + static_cast<long long>(kc) - static_cast<long long>(cols2 - 1);

                        ValueType sample{};
                        if (input_row >= 0 &&
                            input_row < static_cast<long long>(rows1) &&
                            input_col >= 0 &&
                            input_col < static_cast<long long>(cols1))
                        {
                            sample = in1.values[static_cast<std::size_t>(input_row) * cols1 +
                                                static_cast<std::size_t>(input_col)];
                        }
                        else if (normalized_boundary == "fill")
                        {
                            sample = static_cast<ValueType>(fillvalue);
                        }
                        else if (normalized_boundary == "wrap")
                        {
                            const std::size_t rr = wrapped_index(input_row, rows1);
                            const std::size_t cc = wrapped_index(input_col, cols1);
                            sample = in1.values[rr * cols1 + cc];
                        }
                        else
                        {
                            const std::size_t rr = symmetric_index(input_row, rows1);
                            const std::size_t cc = symmetric_index(input_col, cols1);
                            sample = in1.values[rr * cols1 + cc];
                        }

                        accum +=
                            static_cast<AccumulatorType>(sample) *
                            kernel_value(in2.values[kr * cols2 + kc]);
                    }
                }
                output.values[row * out_cols + col] = static_cast<ValueType>(accum);
            }
        }

        return output;
    }

    cusignal::core::IndexVector correlation_lags_impl(
        int in1_len,
        int in2_len,
        const std::string &mode)
    {
        if (in1_len <= 0 || in2_len <= 0)
        {
            throw std::invalid_argument("input lengths must be positive");
        }
        const std::string normalized_mode = detail::normalize_mode(mode);
        cusignal::core::IndexVector full(static_cast<std::size_t>(in1_len + in2_len - 1), 0);
        const int base = -(in2_len - 1);
        for (std::size_t index = 0; index < full.size(); ++index)
        {
            full[index] = base + static_cast<int>(index);
        }

        if (normalized_mode == "full")
        {
            return full;
        }

        if (normalized_mode == "same")
        {
            const int start = (static_cast<int>(full.size()) - in1_len) / 2;
            return cusignal::core::IndexVector(
                full.begin() + start,
                full.begin() + start + in1_len);
        }

        const int lag_bound = in1_len - in2_len;
        if (lag_bound >= 0)
        {
            cusignal::core::IndexVector valid(static_cast<std::size_t>(lag_bound + 1), 0);
            for (int index = 0; index <= lag_bound; ++index)
            {
                valid[static_cast<std::size_t>(index)] = index;
            }
            return valid;
        }

        cusignal::core::IndexVector valid(static_cast<std::size_t>(-lag_bound + 1), 0);
        for (int index = 0; index <= -lag_bound; ++index)
        {
            valid[static_cast<std::size_t>(index)] = lag_bound + index;
        }
        return valid;
    }
} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace correlate
        {

            core::RealArray correlate(
                const core::RealArray &in1,
                const core::RealArray &in2,
                const std::string &mode,
                const std::string &method)
            {
                detail::normalize_method(method);
                if (detail::normalize_method(method) == "direct" &&
                    (in1.rank() != 1 || in2.rank() != 1))
                {
                    throw std::invalid_argument("direct correlate only supports 1D inputs");
                }
                return correlate_nd_impl<RealArray, float, float>(
                    in1,
                    in2,
                    mode,
                    [](float value) { return value; });
            }

            core::ComplexArray correlate(
                const core::ComplexArray &in1,
                const core::ComplexArray &in2,
                const std::string &mode,
                const std::string &method)
            {
                detail::normalize_method(method);
                if (detail::normalize_method(method) == "direct" &&
                    (in1.rank() != 1 || in2.rank() != 1))
                {
                    throw std::invalid_argument("direct correlate only supports 1D inputs");
                }
                return correlate_nd_impl<ComplexArray, Complex, Complex>(
                    in1,
                    in2,
                    mode,
                    [](const Complex &value) { return std::conj(value); });
            }

            core::RealArray correlate2d(
                const core::RealArray &in1,
                const core::RealArray &in2,
                const std::string &mode,
                const std::string &boundary,
                float fillvalue)
            {
                return correlate2d_impl<RealArray, float, float>(
                    in1,
                    in2,
                    mode,
                    boundary,
                    fillvalue,
                    [](float value) { return value; });
            }

            core::ComplexArray correlate2d(
                const core::ComplexArray &in1,
                const core::ComplexArray &in2,
                const std::string &mode,
                const std::string &boundary,
                float fillvalue)
            {
                return correlate2d_impl<ComplexArray, Complex, Complex>(
                    in1,
                    in2,
                    mode,
                    boundary,
                    Complex(fillvalue, 0.0f),
                    [](const Complex &value) { return std::conj(value); });
            }

            core::IndexVector correlation_lags(
                int in1_len,
                int in2_len,
                const std::string &mode)
            {
                return correlation_lags_impl(in1_len, in2_len, mode);
            }

        } // namespace correlate
    } // namespace cpu
} // namespace cusignal
