#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <numeric>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace filtering_detail
    {
        using core::Complex;
        using core::ComplexArray;
        using core::ComplexSignal;
        using core::IndexVector;
        using core::RealArray;
        using core::RealSignal;
        using core::Shape;

        struct AxisPlan
        {
            Shape shape;
            std::vector<std::size_t> strides;
            std::size_t axis = 0;
            std::size_t axis_size = 0;
            std::size_t axis_stride = 0;
            std::size_t line_count = 0;
        };

        struct FilterLineResult
        {
            RealSignal output;
            RealSignal final_state;
        };

        inline std::string normalize_padtype(const std::string &padtype)
        {
            if (padtype == "odd" || padtype == "even" || padtype == "constant" ||
                padtype == "none")
            {
                return padtype;
            }
            throw std::invalid_argument("padtype must be odd/even/constant/none");
        }

        inline std::string normalize_method(const std::string &method)
        {
            if (method == "pad" || method == "gust")
            {
                return method;
            }
            throw std::invalid_argument("method must be pad or gust");
        }

        inline std::string normalize_domain(const std::string &domain)
        {
            if (domain == "time" || domain == "freq")
            {
                return domain;
            }
            throw std::invalid_argument("domain must be time or freq");
        }

        inline std::string normalize_trend_type(const std::string &type)
        {
            if (type == "linear" || type == "l" || type == "constant" || type == "c")
            {
                return type;
            }
            throw std::invalid_argument("type must be linear/l/constant/c");
        }

        inline void ensure_positive_int(int value, const std::string &name)
        {
            if (value <= 0)
            {
                throw std::invalid_argument(name + " must be > 0");
            }
        }

        inline void validate_window_spec(const core::WindowSpec &window)
        {
            if (const auto *values = std::get_if<RealSignal>(&window))
            {
                if (values->empty())
                {
                    throw std::invalid_argument("window array must not be empty");
                }
            }
        }

        inline std::size_t decimated_size(std::size_t input_size, int factor)
        {
            return factor > 0 ? input_size / static_cast<std::size_t>(factor) : input_size;
        }

        inline std::size_t upfirdn_size(std::size_t input_size, std::size_t h_size, int up, int down)
        {
            if (input_size == 0 || h_size == 0)
            {
                return 0;
            }
            const std::size_t numer =
                (input_size - 1) * static_cast<std::size_t>(up) + h_size - 1;
            return numer / static_cast<std::size_t>(down) + 1;
        }

        inline std::size_t resampled_size(std::size_t input_size, int up, int down)
        {
            if (input_size == 0)
            {
                return 0;
            }
            const std::size_t numer = input_size * static_cast<std::size_t>(up);
            return numer / static_cast<std::size_t>(down) +
                   ((numer % static_cast<std::size_t>(down)) != 0 ? 1 : 0);
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

        inline AxisPlan make_axis_plan(const Shape &shape, int axis)
        {
            AxisPlan plan;
            plan.shape = shape;
            plan.axis = core::normalize_axis(axis, shape.size());
            plan.axis_size = shape[plan.axis];
            plan.strides = compute_strides(shape);
            plan.axis_stride = plan.strides[plan.axis];
            plan.line_count = core::shape_product(shape) / plan.axis_size;
            return plan;
        }

        inline std::size_t line_base_offset(const AxisPlan &plan, std::size_t line_index)
        {
            std::size_t offset = 0;
            for (std::size_t dim = 0; dim < plan.shape.size(); ++dim)
            {
                if (dim == plan.axis)
                {
                    continue;
                }
                const std::size_t dim_size = plan.shape[dim];
                const std::size_t coord = line_index % dim_size;
                line_index /= dim_size;
                offset += coord * plan.strides[dim];
            }
            return offset;
        }

        inline RealSignal extract_line(const RealArray &array, const AxisPlan &plan, std::size_t line_index)
        {
            const std::size_t base = line_base_offset(plan, line_index);
            RealSignal line(plan.axis_size, 0.0);
            for (std::size_t index = 0; index < plan.axis_size; ++index)
            {
                line[index] = array.values[base + index * plan.axis_stride];
            }
            return line;
        }

        inline void store_line(
            RealArray &array,
            const AxisPlan &plan,
            std::size_t line_index,
            const RealSignal &line)
        {
            const std::size_t base = line_base_offset(plan, line_index);
            for (std::size_t index = 0; index < plan.axis_size; ++index)
            {
                array.values[base + index * plan.axis_stride] = line[index];
            }
        }

        inline ComplexSignal extract_complex_line(
            const ComplexArray &array,
            const AxisPlan &plan,
            std::size_t line_index)
        {
            const std::size_t base = line_base_offset(plan, line_index);
            ComplexSignal line(plan.axis_size, Complex(0.0, 0.0));
            for (std::size_t index = 0; index < plan.axis_size; ++index)
            {
                line[index] = array.values[base + index * plan.axis_stride];
            }
            return line;
        }

        inline void store_complex_line(
            ComplexArray &array,
            const AxisPlan &plan,
            std::size_t line_index,
            const ComplexSignal &line)
        {
            const std::size_t base = line_base_offset(plan, line_index);
            for (std::size_t index = 0; index < plan.axis_size; ++index)
            {
                array.values[base + index * plan.axis_stride] = line[index];
            }
        }

        inline Shape state_shape_for_filter(const Shape &shape, int axis, std::size_t state_size)
        {
            Shape result = shape;
            result[core::normalize_axis(axis, result.size())] = state_size;
            return result;
        }

        inline RealSignal extract_state_line(
            const RealArray &state,
            const Shape &signal_shape,
            int axis,
            std::size_t state_size,
            std::size_t line_index)
        {
            if (state.shape != state_shape_for_filter(signal_shape, axis, state_size))
            {
                throw std::invalid_argument("zi has invalid shape for filter state");
            }
            return extract_line(state, make_axis_plan(state.shape, axis), line_index);
        }

        inline void store_state_line(
            RealArray &state,
            const Shape &signal_shape,
            int axis,
            std::size_t state_size,
            std::size_t line_index,
            const RealSignal &line)
        {
            store_line(state, make_axis_plan(state.shape, axis), line_index, line);
        }

        inline std::vector<float> normalize_coefficients(
            const RealSignal &coeffs,
            std::size_t size)
        {
            std::vector<float> normalized(size, 0.0);
            for (std::size_t index = 0; index < coeffs.size(); ++index)
            {
                normalized[index] = coeffs[index];
            }
            return normalized;
        }

        inline FilterLineResult lfilter_line(
            const RealSignal &b,
            const RealSignal &a,
            const RealSignal &input,
            const RealSignal *zi = nullptr)
        {
            if (a.empty())
            {
                throw std::invalid_argument("a must not be empty");
            }
            if (a[0] == 0.0)
            {
                throw std::invalid_argument("a[0] must not be zero");
            }

            const std::size_t order = std::max(b.size(), a.size()) - 1;
            std::vector<float> b_norm = normalize_coefficients(b, order + 1);
            std::vector<float> a_norm = normalize_coefficients(a, order + 1);
            const float a0 = a_norm[0];
            for (float &value : b_norm)
            {
                value /= a0;
            }
            for (float &value : a_norm)
            {
                value /= a0;
            }

            RealSignal state(order, 0.0);
            if (zi != nullptr)
            {
                if (zi->size() != order)
                {
                    throw std::invalid_argument("zi has invalid length for filter order");
                }
                state = *zi;
            }

            RealSignal output(input.size(), 0.0);
            if (order == 0)
            {
                for (std::size_t index = 0; index < input.size(); ++index)
                {
                    output[index] = b_norm[0] * input[index];
                }
                return {output, state};
            }

            for (std::size_t index = 0; index < input.size(); ++index)
            {
                const float x_n = input[index];
                const float y_n = b_norm[0] * x_n + state[0];
                for (std::size_t state_index = 0; state_index + 1 < order; ++state_index)
                {
                    state[state_index] =
                        state[state_index + 1] + b_norm[state_index + 1] * x_n -
                        a_norm[state_index + 1] * y_n;
                }
                state[order - 1] = b_norm[order] * x_n - a_norm[order] * y_n;
                output[index] = y_n;
            }
            return {output, state};
        }

        inline std::vector<float> solve_linear_system(
            std::vector<std::vector<float>> matrix,
            std::vector<float> rhs)
        {
            const std::size_t n = matrix.size();
            for (std::size_t row = 0; row < n; ++row)
            {
                matrix[row].push_back(rhs[row]);
            }

            for (std::size_t pivot = 0; pivot < n; ++pivot)
            {
                std::size_t best = pivot;
                for (std::size_t row = pivot + 1; row < n; ++row)
                {
                    if (std::abs(matrix[row][pivot]) > std::abs(matrix[best][pivot]))
                    {
                        best = row;
                    }
                }
                if (std::abs(matrix[best][pivot]) < 1e-14)
                {
                    throw std::runtime_error("singular linear system");
                }
                std::swap(matrix[pivot], matrix[best]);
                const float divisor = matrix[pivot][pivot];
                for (std::size_t column = pivot; column <= n; ++column)
                {
                    matrix[pivot][column] /= divisor;
                }
                for (std::size_t row = 0; row < n; ++row)
                {
                    if (row == pivot)
                    {
                        continue;
                    }
                    const float factor = matrix[row][pivot];
                    for (std::size_t column = pivot; column <= n; ++column)
                    {
                        matrix[row][column] -= factor * matrix[pivot][column];
                    }
                }
            }

            std::vector<float> solution(n, 0.0);
            for (std::size_t row = 0; row < n; ++row)
            {
                solution[row] = matrix[row][n];
            }
            return solution;
        }

        inline std::vector<float> least_squares(
            const std::vector<std::vector<float>> &matrix,
            const std::vector<float> &rhs)
        {
            if (matrix.empty())
            {
                return {};
            }
            const std::size_t rows = matrix.size();
            const std::size_t cols = matrix.front().size();
            std::vector<std::vector<float>> normal(cols, std::vector<float>(cols, 0.0));
            std::vector<float> normal_rhs(cols, 0.0);
            for (std::size_t row = 0; row < rows; ++row)
            {
                for (std::size_t i = 0; i < cols; ++i)
                {
                    normal_rhs[i] += matrix[row][i] * rhs[row];
                    for (std::size_t j = 0; j < cols; ++j)
                    {
                        normal[i][j] += matrix[row][i] * matrix[row][j];
                    }
                }
            }
            return solve_linear_system(std::move(normal), std::move(normal_rhs));
        }

        inline RealSignal lfilter_zi(const RealSignal &b, const RealSignal &a)
        {
            if (b.empty())
            {
                throw std::invalid_argument("b must not be empty");
            }
            if (a.empty())
            {
                throw std::invalid_argument("a must not be empty");
            }

            std::size_t first_nonzero = 0;
            while (first_nonzero + 1 < a.size() && a[first_nonzero] == 0.0)
            {
                ++first_nonzero;
            }
            if (a[first_nonzero] == 0.0)
            {
                throw std::invalid_argument("There must be at least one nonzero a coefficient.");
            }

            RealSignal a_norm(a.begin() + static_cast<long long>(first_nonzero), a.end());
            RealSignal b_norm = b;
            if (a_norm[0] != 1.0)
            {
                const float a0 = a_norm[0];
                for (float &value : a_norm)
                {
                    value /= a0;
                }
                for (float &value : b_norm)
                {
                    value /= a0;
                }
            }

            const std::size_t n = std::max(a_norm.size(), b_norm.size());
            a_norm.resize(n, 0.0);
            b_norm.resize(n, 0.0);
            if (n <= 1)
            {
                return {};
            }

            std::vector<std::vector<float>> matrix(n - 1, std::vector<float>(n - 1, 0.0));
            for (std::size_t row = 0; row < n - 1; ++row)
            {
                matrix[row][row] = 1.0;
                matrix[row][0] += a_norm[row + 1];
                if (row + 1 < n - 1)
                {
                    matrix[row][row + 1] = -1.0;
                }
            }

            std::vector<float> rhs(n - 1, 0.0);
            for (std::size_t index = 0; index < n - 1; ++index)
            {
                rhs[index] = b_norm[index + 1] - a_norm[index + 1] * b_norm[0];
            }
            return solve_linear_system(std::move(matrix), std::move(rhs));
        }

        inline RealSignal firfilter_zi(const RealSignal &b)
        {
            return lfilter_zi(b, RealSignal{1.0});
        }

        inline RealSignal pad_line(
            const RealSignal &line,
            const std::string &padtype,
            std::size_t edge)
        {
            if (padtype == "none" || edge == 0)
            {
                return line;
            }
            if (edge > line.size() - 1)
            {
                throw std::invalid_argument("padlen is too large for the input length");
            }

            RealSignal padded;
            padded.reserve(line.size() + 2 * edge);
            if (padtype == "even")
            {
                for (std::size_t index = 0; index < edge; ++index)
                {
                    padded.push_back(line[edge - index]);
                }
            }
            else if (padtype == "odd")
            {
                for (std::size_t index = 0; index < edge; ++index)
                {
                    padded.push_back(2.0 * line.front() - line[edge - index]);
                }
            }
            else if (padtype == "constant")
            {
                padded.insert(padded.end(), edge, line.front());
            }
            else
            {
                throw std::invalid_argument("unsupported padtype");
            }

            padded.insert(padded.end(), line.begin(), line.end());

            if (padtype == "even")
            {
                for (std::size_t index = 0; index < edge; ++index)
                {
                    padded.push_back(line[line.size() - 2 - index]);
                }
            }
            else if (padtype == "odd")
            {
                for (std::size_t index = 0; index < edge; ++index)
                {
                    padded.push_back(2.0 * line.back() - line[line.size() - 2 - index]);
                }
            }
            else
            {
                padded.insert(padded.end(), edge, line.back());
            }
            return padded;
        }

        inline RealSignal reverse_line(const RealSignal &line)
        {
            return RealSignal(line.rbegin(), line.rend());
        }

        inline RealSignal filtfilt_pad_line(
            const RealSignal &b,
            const RealSignal &a,
            const RealSignal &line,
            const std::string &padtype,
            int padlen)
        {
            const std::string normalized_pad = padtype == "none" ? "none" : normalize_padtype(padtype);
            const std::size_t edge = padlen < 0
                                         ? 3 * (std::max(a.size(), b.size()) - 1)
                                         : static_cast<std::size_t>(padlen);
            if (normalized_pad == "none" && edge == 0)
            {
                const FilterLineResult forward = lfilter_line(b, a, line);
                const FilterLineResult backward = lfilter_line(b, a, reverse_line(forward.output));
                return reverse_line(backward.output);
            }

            if (line.size() <= edge)
            {
                throw std::invalid_argument("The length of the input vector x must be greater than padlen.");
            }
            const RealSignal extended = pad_line(line, normalized_pad, edge);
            const RealSignal zi = lfilter_zi(b, a);
            RealSignal scaled_zi = zi;
            for (float &value : scaled_zi)
            {
                value *= extended.front();
            }
            const FilterLineResult forward = lfilter_line(b, a, extended, &scaled_zi);

            RealSignal backward_zi = zi;
            for (float &value : backward_zi)
            {
                value *= forward.output.back();
            }
            const FilterLineResult backward =
                lfilter_line(b, a, reverse_line(forward.output), &backward_zi);
            RealSignal filtered = reverse_line(backward.output);
            return RealSignal(
                filtered.begin() + static_cast<long long>(edge),
                filtered.end() - static_cast<long long>(edge));
        }

        inline std::vector<std::vector<float>> reverse_rows(
            const std::vector<std::vector<float>> &matrix)
        {
            return std::vector<std::vector<float>>(matrix.rbegin(), matrix.rend());
        }

        inline std::vector<std::vector<float>> filter_columns(
            const RealSignal &b,
            const RealSignal &a,
            const std::vector<std::vector<float>> &matrix)
        {
            if (matrix.empty())
            {
                return {};
            }
            const std::size_t rows = matrix.size();
            const std::size_t cols = matrix.front().size();
            std::vector<std::vector<float>> result(rows, std::vector<float>(cols, 0.0));
            for (std::size_t column = 0; column < cols; ++column)
            {
                RealSignal input(rows, 0.0);
                for (std::size_t row = 0; row < rows; ++row)
                {
                    input[row] = matrix[row][column];
                }
                const FilterLineResult filtered = lfilter_line(b, a, input);
                for (std::size_t row = 0; row < rows; ++row)
                {
                    result[row][column] = filtered.output[row];
                }
            }
            return result;
        }

        inline RealSignal filtfilt_gust_line(
            const RealSignal &b,
            const RealSignal &a,
            const RealSignal &line,
            int irlen)
        {
            const std::size_t order = std::max(b.size(), a.size()) - 1;
            if (order == 0)
            {
                const float scale = (b[0] / a[0]) * (b[0] / a[0]);
                RealSignal y = line;
                for (float &value : y)
                {
                    value *= scale;
                }
                return y;
            }

            const std::size_t n = line.size();
            const std::size_t m = (irlen <= 0 || n <= 2 * static_cast<std::size_t>(irlen))
                                      ? n
                                      : static_cast<std::size_t>(irlen);

            std::vector<std::vector<float>> obs(m, std::vector<float>(order, 0.0));
            RealSignal zi(order, 0.0);
            zi[0] = 1.0;
            const FilterLineResult obs0 = lfilter_line(b, a, RealSignal(m, 0.0), &zi);
            for (std::size_t row = 0; row < m; ++row)
            {
                obs[row][0] = obs0.output[row];
            }
            for (std::size_t column = 1; column < order; ++column)
            {
                for (std::size_t row = column; row < m; ++row)
                {
                    obs[row][column] = obs[row - column][0];
                }
            }

            const std::vector<std::vector<float>> obsr = reverse_rows(obs);
            const std::vector<std::vector<float>> s = filter_columns(b, a, reverse_rows(obs));
            const std::vector<std::vector<float>> sr = reverse_rows(s);

            std::vector<std::vector<float>> M;
            if (m == n)
            {
                M.assign(m, std::vector<float>(2 * order, 0.0));
                for (std::size_t row = 0; row < m; ++row)
                {
                    for (std::size_t column = 0; column < order; ++column)
                    {
                        M[row][column] = sr[row][column] - obs[row][column];
                        M[row][order + column] = obsr[row][column] - s[row][column];
                    }
                }
            }
            else
            {
                M.assign(2 * m, std::vector<float>(2 * order, 0.0));
                for (std::size_t row = 0; row < m; ++row)
                {
                    for (std::size_t column = 0; column < order; ++column)
                    {
                        M[row][column] = sr[row][column] - obs[row][column];
                        M[m + row][order + column] = obsr[row][column] - s[row][column];
                    }
                }
            }

            const FilterLineResult y_f = lfilter_line(b, a, line);
            const RealSignal y_fb = reverse_line(lfilter_line(b, a, reverse_line(y_f.output)).output);
            const RealSignal y_b = reverse_line(lfilter_line(b, a, reverse_line(line)).output);
            const RealSignal y_bf = lfilter_line(b, a, y_b).output;

            RealSignal delta;
            if (m == n)
            {
                delta.resize(n, 0.0);
                for (std::size_t index = 0; index < n; ++index)
                {
                    delta[index] = y_bf[index] - y_fb[index];
                }
            }
            else
            {
                delta.resize(2 * m, 0.0);
                for (std::size_t index = 0; index < m; ++index)
                {
                    delta[index] = y_bf[index] - y_fb[index];
                    delta[m + index] = y_bf[n - m + index] - y_fb[n - m + index];
                }
            }

            const std::vector<float> ic_opt = least_squares(M, delta);

            std::vector<std::vector<float>> W;
            if (m == n)
            {
                W.assign(m, std::vector<float>(2 * order, 0.0));
                for (std::size_t row = 0; row < m; ++row)
                {
                    for (std::size_t column = 0; column < order; ++column)
                    {
                        W[row][column] = sr[row][column];
                        W[row][order + column] = obsr[row][column];
                    }
                }
            }
            else
            {
                W.assign(2 * m, std::vector<float>(2 * order, 0.0));
                for (std::size_t row = 0; row < m; ++row)
                {
                    for (std::size_t column = 0; column < order; ++column)
                    {
                        W[row][column] = sr[row][column];
                        W[m + row][order + column] = obsr[row][column];
                    }
                }
            }

            RealSignal wic(W.size(), 0.0);
            for (std::size_t row = 0; row < W.size(); ++row)
            {
                float value = 0.0;
                for (std::size_t column = 0; column < ic_opt.size(); ++column)
                {
                    value += W[row][column] * ic_opt[column];
                }
                wic[row] = value;
            }

            RealSignal y_opt = y_fb;
            if (m == n)
            {
                for (std::size_t index = 0; index < n; ++index)
                {
                    y_opt[index] += wic[index];
                }
            }
            else
            {
                for (std::size_t index = 0; index < m; ++index)
                {
                    y_opt[index] += wic[index];
                    y_opt[n - m + index] += wic[m + index];
                }
            }
            return y_opt;
        }

        inline std::vector<std::array<float, 6>> parse_sos(const RealArray &sos)
        {
            if (sos.rank() != 2 || sos.shape[1] != 6)
            {
                throw std::invalid_argument("sos must have shape [n_sections, 6]");
            }
            std::vector<std::array<float, 6>> sections(sos.shape[0]);
            for (std::size_t section = 0; section < sos.shape[0]; ++section)
            {
                for (std::size_t column = 0; column < 6; ++column)
                {
                    sections[section][column] = sos.values[section * 6 + column];
                }
            }
            return sections;
        }

        inline Shape sos_state_shape(const Shape &signal_shape, int axis, std::size_t n_sections)
        {
            Shape shape;
            shape.push_back(n_sections);
            shape.insert(shape.end(), signal_shape.begin(), signal_shape.end());
            shape[1 + core::normalize_axis(axis, signal_shape.size())] = 2;
            return shape;
        }

        inline RealSignal extract_sos_state_line(
            const RealArray &zi,
            const Shape &signal_shape,
            int axis,
            std::size_t n_sections,
            std::size_t line_index)
        {
            if (zi.shape != sos_state_shape(signal_shape, axis, n_sections))
            {
                throw std::invalid_argument("zi has invalid shape for sosfilt");
            }
            const std::size_t normalized_axis = core::normalize_axis(axis, signal_shape.size());
            RealSignal state(n_sections * 2, 0.0);
            const std::vector<std::size_t> signal_strides = compute_strides(signal_shape);
            std::size_t remainder = line_index;
            std::vector<std::size_t> coords(signal_shape.size(), 0);
            for (std::size_t dim = 0; dim < signal_shape.size(); ++dim)
            {
                if (dim == normalized_axis)
                {
                    continue;
                }
                coords[dim] = remainder % signal_shape[dim];
                remainder /= signal_shape[dim];
            }

            const Shape zi_shape = zi.shape;
            const std::vector<std::size_t> zi_strides = compute_strides(zi_shape);
            for (std::size_t section = 0; section < n_sections; ++section)
            {
                for (std::size_t state_index = 0; state_index < 2; ++state_index)
                {
                    std::size_t offset = section * zi_strides[0];
                    for (std::size_t dim = 0; dim < signal_shape.size(); ++dim)
                    {
                        const std::size_t coord = (dim == normalized_axis) ? state_index : coords[dim];
                        offset += coord * zi_strides[dim + 1];
                    }
                    state[section * 2 + state_index] = zi.values[offset];
                }
            }
            return state;
        }

        inline void store_sos_state_line(
            RealArray &zf,
            const Shape &signal_shape,
            int axis,
            std::size_t n_sections,
            std::size_t line_index,
            const RealSignal &state)
        {
            const std::size_t normalized_axis = core::normalize_axis(axis, signal_shape.size());
            std::size_t remainder = line_index;
            std::vector<std::size_t> coords(signal_shape.size(), 0);
            for (std::size_t dim = 0; dim < signal_shape.size(); ++dim)
            {
                if (dim == normalized_axis)
                {
                    continue;
                }
                coords[dim] = remainder % signal_shape[dim];
                remainder /= signal_shape[dim];
            }

            const std::vector<std::size_t> zf_strides = compute_strides(zf.shape);
            for (std::size_t section = 0; section < n_sections; ++section)
            {
                for (std::size_t state_index = 0; state_index < 2; ++state_index)
                {
                    std::size_t offset = section * zf_strides[0];
                    for (std::size_t dim = 0; dim < signal_shape.size(); ++dim)
                    {
                        const std::size_t coord = (dim == normalized_axis) ? state_index : coords[dim];
                        offset += coord * zf_strides[dim + 1];
                    }
                    zf.values[offset] = state[section * 2 + state_index];
                }
            }
        }

        inline FilterLineResult sosfilt_line(
            const std::vector<std::array<float, 6>> &sections,
            const RealSignal &input,
            const RealSignal *zi = nullptr)
        {
            RealSignal output = input;
            RealSignal final_state(sections.size() * 2, 0.0);
            if (zi != nullptr)
            {
                if (zi->size() != final_state.size())
                {
                    throw std::invalid_argument("zi has invalid length for sosfilt");
                }
                final_state = *zi;
            }

            for (std::size_t section = 0; section < sections.size(); ++section)
            {
                const auto &s = sections[section];
                const float b0 = s[0];
                const float b1 = s[1];
                const float b2 = s[2];
                const float a0 = s[3];
                const float a1 = s[4];
                const float a2 = s[5];
                if (a0 == 0.0)
                {
                    throw std::invalid_argument("sos section a0 must not be zero");
                }
                float z0 = final_state[section * 2];
                float z1 = final_state[section * 2 + 1];
                for (std::size_t index = 0; index < output.size(); ++index)
                {
                    const float x_n = output[index];
                    const float y_n = (b0 / a0) * x_n + z0;
                    z0 = z1 + (b1 / a0) * x_n - (a1 / a0) * y_n;
                    z1 = (b2 / a0) * x_n - (a2 / a0) * y_n;
                    output[index] = y_n;
                }
                final_state[section * 2] = z0;
                final_state[section * 2 + 1] = z1;
            }
            return {output, final_state};
        }

        inline RealSignal sosfilt_zi(const std::vector<std::array<float, 6>> &sections)
        {
            RealSignal zi(sections.size() * 2, 0.0);
            float scale = 1.0;
            for (std::size_t section = 0; section < sections.size(); ++section)
            {
                RealSignal b = {sections[section][0], sections[section][1], sections[section][2]};
                RealSignal a = {sections[section][3], sections[section][4], sections[section][5]};
                const RealSignal section_zi = lfilter_zi(b, a);
                zi[section * 2] = scale * section_zi[0];
                zi[section * 2 + 1] = scale * section_zi[1];
                const float numerator = b[0] + b[1] + b[2];
                const float denominator = a[0] + a[1] + a[2];
                scale *= numerator / denominator;
            }
            return zi;
        }

    } // namespace filtering_detail
} // namespace cusignal
