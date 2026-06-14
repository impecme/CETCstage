#include "cusignal/bsplines/bsplines.hpp"

#include "cusignal/core/helpers.hpp"

#include "../common/bsplines_detail.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace bsplines
        {
            namespace detail = cusignal::bsplines_detail;

            core::RealArray cubic(const core::RealArray &x)
            {
                core::RealArray output = core::make_real_array_like(x);
                output.values.resize(x.values.size());
                for (std::size_t index = 0; index < x.values.size(); ++index)
                {
                    output.values[index] = detail::cubic_value(x.values[index]);
                }
                return output;
            }

            core::RealArray gauss_spline(const core::RealArray &x, int n)
            {
                detail::ensure_non_negative_order(n);

                core::RealArray output = core::make_real_array_like(x);
                output.values.resize(x.values.size());
                for (std::size_t index = 0; index < x.values.size(); ++index)
                {
                    output.values[index] = detail::gauss_spline_value(x.values[index], n);
                }
                return output;
            }

            core::RealArray quadratic(const core::RealArray &x)
            {
                core::RealArray output = core::make_real_array_like(x);
                output.values.resize(x.values.size());
                for (std::size_t index = 0; index < x.values.size(); ++index)
                {
                    output.values[index] = detail::quadratic_value(x.values[index]);
                }
                return output;
            }

        } // namespace bsplines
    } // namespace cpu
} // namespace cusignal
