#include "cusignal/demod/demod.hpp"

#include <cmath>

#include "cusignal/core/helpers.hpp"

#include "../common/demod_detail.hpp"
#include "../common/filtering_detail.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace demod
        {

            core::RealArray fm_demod(const core::ComplexArray &x, int axis)
            {
                namespace detail = cusignal::demod_detail;
                namespace axis_detail = cusignal::filtering_detail;

                const std::size_t normalized_axis = core::normalize_axis(axis, x.rank());
                const std::size_t axis_length = x.shape[normalized_axis];
                core::RealArray output =
                    core::make_real_array(core::replace_axis_size(
                        x.shape,
                        static_cast<int>(normalized_axis),
                        axis_length == 0 ? 0 : axis_length - 1));
                if (x.empty() || axis_length < 2)
                {
                    return output;
                }

                const axis_detail::AxisPlan input_plan =
                    axis_detail::make_axis_plan(x.shape, static_cast<int>(normalized_axis));
                const axis_detail::AxisPlan output_plan =
                    axis_detail::make_axis_plan(output.shape, static_cast<int>(normalized_axis));

                for (std::size_t line_index = 0; line_index < input_plan.line_count; ++line_index)
                {
                    const std::size_t input_base =
                        axis_detail::line_base_offset(input_plan, line_index);
                    const std::size_t output_base =
                        axis_detail::line_base_offset(output_plan, line_index);
                    for (std::size_t index = 0; index + 1 < input_plan.axis_size; ++index)
                    {
                        const core::Complex &current =
                            x.values[input_base + index * input_plan.axis_stride];
                        const core::Complex &next =
                            x.values[input_base + (index + 1) * input_plan.axis_stride];
                        output.values[output_base + index * output_plan.axis_stride] =
                            detail::wrapped_phase_difference(
                                current.real(), current.imag(), next.real(), next.imag());
                    }
                }
                return output;
            }

        } // namespace demod
    } // namespace cpu
} // namespace cusignal
