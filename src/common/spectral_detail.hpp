#pragma once

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstddef>
#include <numeric>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace spectral_detail
    {
        using core::Complex;
        using core::ComplexArray;
        using core::ComplexSignal;
        using core::DetrendSpec;
        using core::RealArray;
        using core::RealSignal;
        using core::Shape;

        constexpr float kPi = 3.14159265358979323846f;

        struct AxisPlan
        {
            Shape shape;
            std::vector<std::size_t> strides;
            std::size_t axis = 0;
            std::size_t axis_size = 0;
            std::size_t axis_stride = 0;
            std::size_t line_count = 0;
        };

        struct SegmentConfig
        {
            int nperseg = 0;
            int noverlap = 0;
            int nfft = 0;
            int step = 0;
            bool return_onesided = true;
        };

        inline std::string normalize_scaling(const std::string &scaling)
        {
            if (scaling == "density" || scaling == "spectrum")
            {
                return scaling;
            }
            throw std::invalid_argument("scaling must be density or spectrum");
        }

        inline std::string normalize_average(const std::string &average)
        {
            if (average == "mean" || average == "median")
            {
                return average;
            }
            throw std::invalid_argument("average must be mean or median");
        }

        inline std::string normalize_mode(const std::string &mode)
        {
            if (mode == "psd" || mode == "complex" || mode == "magnitude" ||
                mode == "angle" || mode == "phase")
            {
                return mode;
            }
            throw std::invalid_argument("mode must be psd/complex/magnitude/angle/phase");
        }

        inline std::string normalize_boundary(const std::string &boundary)
        {
            if (boundary == "even" || boundary == "odd" || boundary == "constant" ||
                boundary == "zeros" || boundary == "none")
            {
                return boundary;
            }
            throw std::invalid_argument("boundary must be even/odd/constant/zeros/none");
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
                const std::size_t dim_size = plan.shape[dim];
                const std::size_t coord = line_index % dim_size;
                line_index /= dim_size;
                offset += coord * plan.strides[dim];
            }
            return offset;
        }

        inline RealSignal extract_line(const RealArray &array, const AxisPlan &plan, std::size_t line_index)
        {
            RealSignal line(plan.axis_size, 0.0);
            const std::size_t base = line_base_offset(plan, line_index);
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

        inline bool detrend_disabled(const DetrendSpec &detrend)
        {
            if (const auto *flag = std::get_if<bool>(&detrend))
            {
                return !(*flag);
            }
            return false;
        }

        inline std::string detrend_type(const DetrendSpec &detrend)
        {
            if (const auto *name = std::get_if<std::string>(&detrend))
            {
                if (*name == "constant" || *name == "c")
                {
                    return "constant";
                }
                if (*name == "linear" || *name == "l")
                {
                    return "linear";
                }
                throw std::invalid_argument("detrend must be constant/c/linear/l or false");
            }
            if (const auto *flag = std::get_if<bool>(&detrend))
            {
                if (!(*flag))
                {
                    return "none";
                }
            }
            throw std::invalid_argument("unsupported detrend specification");
        }

        inline RealSignal detrend_line(RealSignal line, const DetrendSpec &detrend)
        {
            if (line.empty() || detrend_disabled(detrend))
            {
                return line;
            }

            const std::string type = detrend_type(detrend);
            if (type == "none")
            {
                return line;
            }

            if (type == "constant")
            {
                const float mean =
                    std::accumulate(line.begin(), line.end(), 0.0) / static_cast<float>(line.size());
                for (float &value : line)
                {
                    value -= mean;
                }
                return line;
            }

            const float n = static_cast<float>(line.size());
            float sum_x = 0.0;
            float sum_x2 = 0.0;
            float sum_y = 0.0;
            float sum_xy = 0.0;
            for (std::size_t index = 0; index < line.size(); ++index)
            {
                const float x = static_cast<float>(index);
                const float y = line[index];
                sum_x += x;
                sum_x2 += x * x;
                sum_y += y;
                sum_xy += x * y;
            }
            const float denom = n * sum_x2 - sum_x * sum_x;
            const float slope = std::abs(denom) < 1e-14 ? 0.0 : (n * sum_xy - sum_x * sum_y) / denom;
            const float intercept = (sum_y - slope * sum_x) / n;
            for (std::size_t index = 0; index < line.size(); ++index)
            {
                line[index] -= intercept + slope * static_cast<float>(index);
            }
            return line;
        }

        inline RealSignal extend_line(const RealSignal &line, int n, const std::string &boundary)
        {
            if (boundary == "none" || n <= 0)
            {
                return line;
            }
            if (line.empty())
            {
                return {};
            }
            if (static_cast<std::size_t>(n) > line.size() - 1)
            {
                throw std::invalid_argument("boundary extension length is too large");
            }

            RealSignal output;
            output.reserve(line.size() + 2 * static_cast<std::size_t>(n));
            if (boundary == "zeros")
            {
                output.insert(output.end(), static_cast<std::size_t>(n), 0.0);
            }
            else if (boundary == "constant")
            {
                output.insert(output.end(), static_cast<std::size_t>(n), line.front());
            }
            else if (boundary == "even")
            {
                for (int index = n; index > 0; --index)
                {
                    output.push_back(line[static_cast<std::size_t>(index)]);
                }
            }
            else if (boundary == "odd")
            {
                for (int index = n; index > 0; --index)
                {
                    output.push_back(2.0 * line.front() - line[static_cast<std::size_t>(index)]);
                }
            }

            output.insert(output.end(), line.begin(), line.end());

            if (boundary == "zeros")
            {
                output.insert(output.end(), static_cast<std::size_t>(n), 0.0);
            }
            else if (boundary == "constant")
            {
                output.insert(output.end(), static_cast<std::size_t>(n), line.back());
            }
            else if (boundary == "even")
            {
                for (int index = n; index > 0; --index)
                {
                    output.push_back(line[line.size() - 1 - static_cast<std::size_t>(index)]);
                }
            }
            else if (boundary == "odd")
            {
                for (int index = n; index > 0; --index)
                {
                    output.push_back(
                        2.0 * line.back() -
                        line[line.size() - 1 - static_cast<std::size_t>(index)]);
                }
            }
            return output;
        }

        inline void pad_line_to_segments(RealSignal &line, int nperseg, int step)
        {
            if (line.empty())
            {
                return;
            }
            const int remainder = static_cast<int>((line.size() - static_cast<std::size_t>(nperseg)) % static_cast<std::size_t>(step));
            const int nadd = ((-remainder) % step + step) % step;
            const int effective_add = nadd % nperseg;
            line.insert(line.end(), static_cast<std::size_t>(effective_add), 0.0);
        }

        inline SegmentConfig resolve_segment_config(
            std::size_t input_length,
            int nperseg,
            int noverlap,
            int nfft,
            int default_nperseg,
            int default_noverlap)
        {
            if (nperseg <= 0)
            {
                nperseg = default_nperseg;
            }
            if (nperseg > static_cast<int>(input_length))
            {
                nperseg = static_cast<int>(input_length);
            }
            if (nperseg <= 0)
            {
                throw std::invalid_argument("nperseg must be > 0");
            }
            if (nfft <= 0)
            {
                nfft = nperseg;
            }
            if (nfft < nperseg)
            {
                throw std::invalid_argument("nfft must be greater than or equal to nperseg");
            }
            if (noverlap < 0)
            {
                noverlap = default_noverlap;
            }
            if (noverlap >= nperseg)
            {
                throw std::invalid_argument("noverlap must be less than nperseg");
            }
            SegmentConfig config;
            config.nperseg = nperseg;
            config.noverlap = noverlap;
            config.nfft = nfft;
            config.step = nperseg - noverlap;
            return config;
        }

        inline std::size_t frequency_count(int nfft, bool onesided)
        {
            return onesided ? static_cast<std::size_t>(nfft / 2 + 1) : static_cast<std::size_t>(nfft);
        }

        inline RealSignal frequency_axis(int nfft, float fs, bool onesided)
        {
            const std::size_t count = frequency_count(nfft, onesided);
            RealSignal axis(count, 0.0);
            if (onesided)
            {
                for (std::size_t index = 0; index < count; ++index)
                {
                    axis[index] = static_cast<float>(index) * fs / static_cast<float>(nfft);
                }
            }
            else
            {
                for (int index = 0; index < nfft; ++index)
                {
                    const int shifted = index <= nfft / 2 ? index : index - nfft;
                    axis[static_cast<std::size_t>(index)] =
                        static_cast<float>(shifted) * fs / static_cast<float>(nfft);
                }
            }
            return axis;
        }

        inline RealSignal segment_times(
            std::size_t input_length,
            int nperseg,
            int step,
            float fs,
            bool boundary_extended)
        {
            if (input_length < static_cast<std::size_t>(nperseg))
            {
                return {};
            }
            const std::size_t count =
                1 + (input_length - static_cast<std::size_t>(nperseg)) / static_cast<std::size_t>(step);
            RealSignal time(count, 0.0);
            const float half = static_cast<float>(nperseg) / 2.0;
            for (std::size_t index = 0; index < count; ++index)
            {
                time[index] =
                    (half + static_cast<float>(index * static_cast<std::size_t>(step))) / fs;
                if (boundary_extended)
                {
                    time[index] -= half / fs;
                }
            }
            return time;
        }

        inline float density_scale(const RealSignal &window, float fs)
        {
            float power = 0.0;
            for (float value : window)
            {
                power += value * value;
            }
            return 1.0 / (fs * power);
        }

        inline float spectrum_scale(const RealSignal &window)
        {
            const float sum = std::accumulate(window.begin(), window.end(), 0.0);
            return 1.0 / (sum * sum);
        }

        inline float median_bias(int n)
        {
            float bias = 1.0;
            for (int index = 1; index <= (n - 1) / 2; ++index)
            {
                const float ii_2 = 2.0 * static_cast<float>(index);
                bias += 1.0 / (ii_2 + 1.0) - 1.0 / ii_2;
            }
            return bias;
        }

        inline RealSignal unwrap_phase(RealSignal values)
        {
            if (values.empty())
            {
                return values;
            }
            float previous = values.front();
            for (std::size_t index = 1; index < values.size(); ++index)
            {
                float current = values[index];
                float delta = current - previous;
                while (delta > kPi)
                {
                    current -= 2.0f * kPi;
                    delta = current - previous;
                }
                while (delta < -kPi)
                {
                    current += 2.0f * kPi;
                    delta = current - previous;
                }
                values[index] = current;
                previous = current;
            }
            return values;
        }
    } // namespace spectral_detail
} // namespace cusignal
