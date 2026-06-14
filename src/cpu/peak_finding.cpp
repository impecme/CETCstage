#include "cusignal/peak_finding/peak_finding.hpp"

#include <algorithm>
#include <vector>

#include "cusignal/core/helpers.hpp"

#include "../common/peak_finding_detail.hpp"

namespace
{
    bool compare_value(float lhs, float rhs, const std::string &comparator)
    {
        return comparator == "greater" ? (lhs > rhs) : (lhs < rhs);
    }
} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace peak_finding
        {

            peak_finding_api::ExtremaResult argrelextrema(
                const core::RealArray &data,
                const std::string &comparator,
                int axis,
                int order,
                const std::string &mode)
            {
                namespace detail = cusignal::peak_finding_detail;
                const std::string normalized_comparator =
                    detail::normalize_comparator(comparator);
                const std::string normalized_mode = detail::normalize_mode(mode);
                if (order < 1)
                {
                    throw std::invalid_argument("order must be >= 1");
                }

                const detail::AxisPlan plan = detail::make_axis_plan(data.shape, axis);
                std::vector<unsigned char> mask(data.size(), 0);
                for (std::size_t line_index = 0; line_index < plan.line_count; ++line_index)
                {
                    const std::size_t base = detail::line_base_offset(plan, line_index);
                    for (std::size_t index = 0; index < plan.axis_size; ++index)
                    {
                        const std::size_t current = base + index * plan.axis_stride;
                        const float center = data.values[current];
                        bool is_extrema = true;
                        for (int shift = 1; shift <= order && is_extrema; ++shift)
                        {
                            long long plus = static_cast<long long>(index) + shift;
                            long long minus = static_cast<long long>(index) - shift;
                            if (normalized_mode == "clip")
                            {
                                plus = std::min<long long>(
                                    std::max<long long>(plus, 0),
                                    static_cast<long long>(plan.axis_size - 1));
                                minus = std::min<long long>(
                                    std::max<long long>(minus, 0),
                                    static_cast<long long>(plan.axis_size - 1));
                            }
                            else
                            {
                                plus = (plus % static_cast<long long>(plan.axis_size) +
                                        static_cast<long long>(plan.axis_size)) %
                                       static_cast<long long>(plan.axis_size);
                                minus = (minus % static_cast<long long>(plan.axis_size) +
                                         static_cast<long long>(plan.axis_size)) %
                                        static_cast<long long>(plan.axis_size);
                            }
                            const float plus_value =
                                data.values[base + static_cast<std::size_t>(plus) * plan.axis_stride];
                            const float minus_value =
                                data.values[base + static_cast<std::size_t>(minus) * plan.axis_stride];
                            is_extrema = compare_value(center, plus_value, normalized_comparator) &&
                                         compare_value(center, minus_value, normalized_comparator);
                        }
                        if (is_extrema)
                        {
                            mask[current] = 1;
                        }
                    }
                }

                peak_finding_api::ExtremaResult result;
                result.indices.assign(data.rank(), core::IndexVector{});
                const std::vector<std::size_t> strides =
                    detail::compute_strides(data.shape);
                for (std::size_t flat_index = 0; flat_index < mask.size(); ++flat_index)
                {
                    if (mask[flat_index] == 0)
                    {
                        continue;
                    }
                    std::size_t remaining = flat_index;
                    for (std::size_t dim = 0; dim < data.rank(); ++dim)
                    {
                        const int coord = static_cast<int>(remaining / strides[dim]);
                        remaining %= strides[dim];
                        result.indices[dim].push_back(coord);
                    }
                }
                return result;
            }

            peak_finding_api::ExtremaResult argrelmin(
                const core::RealArray &data,
                int axis,
                int order,
                const std::string &mode)
            {
                return argrelextrema(data, "less", axis, order, mode);
            }

            peak_finding_api::ExtremaResult argrelmax(
                const core::RealArray &data,
                int axis,
                int order,
                const std::string &mode)
            {
                return argrelextrema(data, "greater", axis, order, mode);
            }

        } // namespace peak_finding
    } // namespace cpu
} // namespace cusignal
