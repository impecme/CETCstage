#pragma once

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal::estimation_detail
{
    using core::RealArray;
    using core::RealSignal;
    using core::Shape;

    inline void ensure_dim(const char *name, int value, bool allow_zero = false)
    {
        if (allow_zero ? value < 0 : value < 1)
        {
            throw std::invalid_argument(std::string(name) + " has an invalid value");
        }
    }

    inline void ensure_dtype(const std::string &dtype)
    {
        if (dtype != "float32")
        {
            throw std::invalid_argument("dtype must be float32");
        }
    }

    inline Shape state_vector_shape(int points, int dim)
    {
        return Shape{
            static_cast<std::size_t>(points),
            static_cast<std::size_t>(dim),
            1};
    }

    inline Shape square_matrix_shape(int points, int dim)
    {
        return Shape{
            static_cast<std::size_t>(points),
            static_cast<std::size_t>(dim),
            static_cast<std::size_t>(dim)};
    }

    inline Shape rectangular_matrix_shape(int points, int rows, int cols)
    {
        return Shape{
            static_cast<std::size_t>(points),
            static_cast<std::size_t>(rows),
            static_cast<std::size_t>(cols)};
    }

    inline void fill_identity(RealArray &array, int points, int dim)
    {
        array = core::make_real_array(square_matrix_shape(points, dim), 0.0f);
        const std::size_t matrix_size = static_cast<std::size_t>(dim * dim);
        for (int point = 0; point < points; ++point)
        {
            const std::size_t base = static_cast<std::size_t>(point) * matrix_size;
            for (int diag = 0; diag < dim; ++diag)
            {
                array.values[base + static_cast<std::size_t>(diag * dim + diag)] = 1.0f;
            }
        }
    }

    inline void validate_control_shape(
        const RealArray &control,
        int points,
        int dim_u)
    {
        if (control.shape != state_vector_shape(points, dim_u))
        {
            throw std::invalid_argument("control has invalid shape");
        }
    }

    inline void validate_measurement_shape(
        const RealArray &measurement,
        int points,
        int dim_z)
    {
        if (measurement.shape != state_vector_shape(points, dim_z))
        {
            throw std::invalid_argument("measurement has invalid shape");
        }
    }

    inline void validate_member_shape(
        const RealArray &array,
        const Shape &expected,
        const std::string &name)
    {
        if (array.shape != expected)
        {
            throw std::invalid_argument(name + " has invalid shape");
        }
    }

    inline std::size_t matrix_offset(int point, int rows, int cols)
    {
        return static_cast<std::size_t>(point) * static_cast<std::size_t>(rows * cols);
    }

    inline std::size_t vector_offset(int point, int dim)
    {
        return static_cast<std::size_t>(point) * static_cast<std::size_t>(dim);
    }

    inline void invert_matrix_in_place(std::vector<float> &matrix, int n)
    {
        std::vector<float> identity(static_cast<std::size_t>(n * n), 0.0f);
        for (int diag = 0; diag < n; ++diag)
        {
            identity[static_cast<std::size_t>(diag * n + diag)] = 1.0f;
        }

        for (int pivot = 0; pivot < n; ++pivot)
        {
            int pivot_row = pivot;
            float max_abs = std::fabs(matrix[static_cast<std::size_t>(pivot * n + pivot)]);
            for (int row = pivot + 1; row < n; ++row)
            {
                const float candidate =
                    std::fabs(matrix[static_cast<std::size_t>(row * n + pivot)]);
                if (candidate > max_abs)
                {
                    max_abs = candidate;
                    pivot_row = row;
                }
            }
            if (!(max_abs > 0.0f))
            {
                throw std::invalid_argument("matrix is singular");
            }
            if (pivot_row != pivot)
            {
                for (int col = 0; col < n; ++col)
                {
                    std::swap(
                        matrix[static_cast<std::size_t>(pivot * n + col)],
                        matrix[static_cast<std::size_t>(pivot_row * n + col)]);
                    std::swap(
                        identity[static_cast<std::size_t>(pivot * n + col)],
                        identity[static_cast<std::size_t>(pivot_row * n + col)]);
                }
            }

            const float diag = matrix[static_cast<std::size_t>(pivot * n + pivot)];
            for (int col = 0; col < n; ++col)
            {
                matrix[static_cast<std::size_t>(pivot * n + col)] /= diag;
                identity[static_cast<std::size_t>(pivot * n + col)] /= diag;
            }
            for (int row = 0; row < n; ++row)
            {
                if (row == pivot)
                {
                    continue;
                }
                const float factor = matrix[static_cast<std::size_t>(row * n + pivot)];
                if (factor == 0.0f)
                {
                    continue;
                }
                for (int col = 0; col < n; ++col)
                {
                    matrix[static_cast<std::size_t>(row * n + col)] -=
                        factor * matrix[static_cast<std::size_t>(pivot * n + col)];
                    identity[static_cast<std::size_t>(row * n + col)] -=
                        factor * identity[static_cast<std::size_t>(pivot * n + col)];
                }
            }
        }
        matrix = std::move(identity);
    }
} // namespace cusignal::estimation_detail
