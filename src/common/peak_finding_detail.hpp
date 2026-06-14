#pragma once

#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal::peak_finding_detail
{
    using core::RealArray;
    using core::Shape;

    inline std::string normalize_mode(const std::string &mode)
    {
        if (mode == "clip" || mode == "wrap")
        {
            return mode;
        }
        throw std::invalid_argument("mode must be clip or wrap");
    }

    inline std::string normalize_comparator(const std::string &comparator)
    {
        if (comparator == "greater" || comparator == "less")
        {
            return comparator;
        }
        throw std::invalid_argument("comparator must be greater or less");
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

    struct AxisPlan
    {
        Shape shape;
        std::vector<std::size_t> strides;
        std::size_t axis = 0;
        std::size_t axis_size = 0;
        std::size_t axis_stride = 0;
        std::size_t line_count = 0;
    };

    inline AxisPlan make_axis_plan(const Shape &shape, int axis)
    {
        AxisPlan plan;
        plan.shape = shape;
        plan.axis = core::normalize_axis(axis, shape.size());
        plan.axis_size = shape[plan.axis];
        plan.strides = compute_strides(shape);
        plan.axis_stride = plan.strides[plan.axis];
        plan.line_count = core::shape_product(shape) / std::max<std::size_t>(plan.axis_size, 1);
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
            const std::size_t coord = line_index % plan.shape[dim];
            line_index /= plan.shape[dim];
            offset += coord * plan.strides[dim];
        }
        return offset;
    }
} // namespace cusignal::peak_finding_detail
