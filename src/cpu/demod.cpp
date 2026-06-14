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
                    const core::ComplexSignal line =
                        axis_detail::extract_complex_line(x, input_plan, line_index);
                    core::RealSignal phase(line.size(), 0.0f);
                    for (std::size_t index = 0; index < line.size(); ++index)
                    {
                        phase[index] = std::atan2(line[index].imag(), line[index].real());
                    }
                    const core::RealSignal unwrapped = detail::unwrap_phase(phase);
                    const core::RealSignal diffed = detail::diff_phase(unwrapped);
                    axis_detail::store_line(output, output_plan, line_index, diffed);
                }
                return output;
            }

        } // namespace demod
    } // namespace cpu
} // namespace cusignal
