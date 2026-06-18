#include "cusignal/filtering/filtering.hpp"

#include <fftw3.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <numeric>
#include <stdexcept>
#include <vector>

#include "cusignal/filter_design/filter_design.hpp"
#include "cusignal/windows/windows.hpp"

#include "../common/filtering_detail.hpp"

namespace
{
    namespace detail = cusignal::filtering_detail;
    namespace core = cusignal::core;
    namespace filtering_api = cusignal::filtering_api;
    namespace cpu = cusignal::cpu;

    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::IndexVector;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;

    constexpr float kPi = 3.141592653589793238462643383279502884;
    constexpr int kDetrendReductionBlock = 256;

    void detrend_linear_pairwise_like_zx_gpu(RealSignal &values)
    {
        const int count = static_cast<int>(values.size());
        const int block_count = (count + kDetrendReductionBlock - 1) / kDetrendReductionBlock;
        std::vector<float> partial_sum_y(static_cast<std::size_t>(block_count), 0.0f);
        std::vector<float> partial_sum_ty(static_cast<std::size_t>(block_count), 0.0f);
        std::vector<float> partial_sum_t(static_cast<std::size_t>(block_count), 0.0f);
        std::vector<float> partial_sum_t2(static_cast<std::size_t>(block_count), 0.0f);
        const float n = static_cast<float>(count);
        for (int block = 0; block < block_count; ++block)
        {
            std::array<float, kDetrendReductionBlock> sum_y{};
            std::array<float, kDetrendReductionBlock> sum_ty{};
            std::array<float, kDetrendReductionBlock> sum_t{};
            std::array<float, kDetrendReductionBlock> sum_t2{};
            for (int tid = 0; tid < kDetrendReductionBlock; ++tid)
            {
                for (int index = block * kDetrendReductionBlock + tid;
                     index < count;
                     index += block_count * kDetrendReductionBlock)
                {
                    const float t = static_cast<float>(index + 1) / n;
                    const float y = values[static_cast<std::size_t>(index)];
                    sum_y[static_cast<std::size_t>(tid)] += y;
                    sum_ty[static_cast<std::size_t>(tid)] += t * y;
                    sum_t[static_cast<std::size_t>(tid)] += t;
                    sum_t2[static_cast<std::size_t>(tid)] += t * t;
                }
            }
            for (int stride = kDetrendReductionBlock / 2; stride > 0; stride >>= 1)
            {
                for (int tid = 0; tid < stride; ++tid)
                {
                    sum_y[static_cast<std::size_t>(tid)] += sum_y[static_cast<std::size_t>(tid + stride)];
                    sum_ty[static_cast<std::size_t>(tid)] += sum_ty[static_cast<std::size_t>(tid + stride)];
                    sum_t[static_cast<std::size_t>(tid)] += sum_t[static_cast<std::size_t>(tid + stride)];
                    sum_t2[static_cast<std::size_t>(tid)] += sum_t2[static_cast<std::size_t>(tid + stride)];
                }
            }
            partial_sum_y[static_cast<std::size_t>(block)] = sum_y[0];
            partial_sum_ty[static_cast<std::size_t>(block)] = sum_ty[0];
            partial_sum_t[static_cast<std::size_t>(block)] = sum_t[0];
            partial_sum_t2[static_cast<std::size_t>(block)] = sum_t2[0];
        }

        std::array<float, kDetrendReductionBlock> sum_y{};
        std::array<float, kDetrendReductionBlock> sum_ty{};
        std::array<float, kDetrendReductionBlock> sum_t{};
        std::array<float, kDetrendReductionBlock> sum_t2{};
        for (int tid = 0; tid < kDetrendReductionBlock; ++tid)
        {
            for (int index = tid; index < block_count; index += kDetrendReductionBlock)
            {
                sum_y[static_cast<std::size_t>(tid)] += partial_sum_y[static_cast<std::size_t>(index)];
                sum_ty[static_cast<std::size_t>(tid)] += partial_sum_ty[static_cast<std::size_t>(index)];
                sum_t[static_cast<std::size_t>(tid)] += partial_sum_t[static_cast<std::size_t>(index)];
                sum_t2[static_cast<std::size_t>(tid)] += partial_sum_t2[static_cast<std::size_t>(index)];
            }
        }
        for (int stride = kDetrendReductionBlock / 2; stride > 0; stride >>= 1)
        {
            for (int tid = 0; tid < stride; ++tid)
            {
                sum_y[static_cast<std::size_t>(tid)] += sum_y[static_cast<std::size_t>(tid + stride)];
                sum_ty[static_cast<std::size_t>(tid)] += sum_ty[static_cast<std::size_t>(tid + stride)];
                sum_t[static_cast<std::size_t>(tid)] += sum_t[static_cast<std::size_t>(tid + stride)];
                sum_t2[static_cast<std::size_t>(tid)] += sum_t2[static_cast<std::size_t>(tid + stride)];
            }
        }
        const float det = n * sum_t2[0] - sum_t[0] * sum_t[0];
        const float slope = (n * sum_ty[0] - sum_t[0] * sum_y[0]) / det;
        const float intercept = (sum_y[0] - slope * sum_t[0]) / n;
        for (int index = 0; index < count; ++index)
        {
            const float t = static_cast<float>(index + 1) / n;
            values[static_cast<std::size_t>(index)] -= intercept + slope * t;
        }
    }

    std::vector<std::complex<float>> fft_complex(const std::vector<std::complex<float>> &input, int n)
    {
        std::vector<fftw_complex> fft_in(static_cast<std::size_t>(n));
        std::vector<fftw_complex> fft_out(static_cast<std::size_t>(n));
        for (int index = 0; index < n; ++index)
        {
            const std::complex<float> value =
                index < static_cast<int>(input.size()) ? input[static_cast<std::size_t>(index)] : std::complex<float>(0.0, 0.0);
            fft_in[static_cast<std::size_t>(index)][0] = value.real();
            fft_in[static_cast<std::size_t>(index)][1] = value.imag();
        }

        fftw_plan plan = fftw_plan_dft_1d(
            n,
            fft_in.data(),
            fft_out.data(),
            FFTW_FORWARD,
            FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("failed to create FFTW plan");
        }
        fftw_execute(plan);
        fftw_destroy_plan(plan);

        std::vector<std::complex<float>> output(static_cast<std::size_t>(n));
        for (int index = 0; index < n; ++index)
        {
            output[static_cast<std::size_t>(index)] = {
                static_cast<float>(fft_out[static_cast<std::size_t>(index)][0]),
                static_cast<float>(fft_out[static_cast<std::size_t>(index)][1])};
        }
        return output;
    }

    std::vector<std::complex<float>> ifft_complex(const std::vector<std::complex<float>> &input, int n)
    {
        std::vector<fftw_complex> fft_in(static_cast<std::size_t>(n));
        std::vector<fftw_complex> fft_out(static_cast<std::size_t>(n));
        for (int index = 0; index < n; ++index)
        {
            const std::complex<float> value =
                index < static_cast<int>(input.size()) ? input[static_cast<std::size_t>(index)] : std::complex<float>(0.0, 0.0);
            fft_in[static_cast<std::size_t>(index)][0] = value.real();
            fft_in[static_cast<std::size_t>(index)][1] = value.imag();
        }

        fftw_plan plan = fftw_plan_dft_1d(
            n,
            fft_in.data(),
            fft_out.data(),
            FFTW_BACKWARD,
            FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("failed to create FFTW plan");
        }
        fftw_execute(plan);
        fftw_destroy_plan(plan);

        const float scale = 1.0f / static_cast<float>(n);
        std::vector<std::complex<float>> output(static_cast<std::size_t>(n));
        for (int index = 0; index < n; ++index)
        {
            output[static_cast<std::size_t>(index)] = {
                static_cast<float>(fft_out[static_cast<std::size_t>(index)][0]) * scale,
                static_cast<float>(fft_out[static_cast<std::size_t>(index)][1]) * scale};
        }
        return output;
    }

    ComplexArray as_complex_array(const RealArray &x)
    {
        ComplexArray result = cusignal::core::make_complex_array(x.shape);
        for (std::size_t index = 0; index < x.values.size(); ++index)
        {
            result.values[index] = Complex(x.values[index], 0.0);
        }
        return result;
    }

    std::size_t flat_index(const Shape &shape, const std::vector<std::size_t> &coords)
    {
        const std::vector<std::size_t> strides = detail::compute_strides(shape);
        std::size_t offset = 0;
        for (std::size_t index = 0; index < shape.size(); ++index)
        {
            offset += coords[index] * strides[index];
        }
        return offset;
    }

    std::vector<std::size_t> unravel_index(std::size_t flat, const Shape &shape)
    {
        std::vector<std::size_t> coords(shape.size(), 0);
        const std::vector<std::size_t> strides = detail::compute_strides(shape);
        for (std::size_t index = 0; index < shape.size(); ++index)
        {
            coords[index] = flat / strides[index];
            flat %= strides[index];
        }
        return coords;
    }

    RealArray wiener_impl(const RealArray &image, const Shape &mysize, float noise)
    {
        const std::size_t total = image.values.size();
        const float window_volume = static_cast<float>(core::shape_product(mysize));
        std::vector<float> local_mean(total, 0.0);
        std::vector<float> local_variance(total, 0.0);
        for (std::size_t flat = 0; flat < total; ++flat)
        {
            const std::vector<std::size_t> center = unravel_index(flat, image.shape);
            float sum = 0.0;
            float sum_sq = 0.0;

            std::vector<std::size_t> start(center.size(), 0);
            std::vector<std::size_t> stop(center.size(), 0);
            for (std::size_t dim = 0; dim < center.size(); ++dim)
            {
                const std::size_t half = mysize[dim] / 2;
                start[dim] = center[dim] > half ? center[dim] - half : 0;
                stop[dim] = std::min(image.shape[dim] - 1, center[dim] + half);
            }

            std::vector<std::size_t> coords = start;
            bool done = false;
            while (!done)
            {
                const float value = image.values[flat_index(image.shape, coords)];
                sum += value;
                sum_sq += value * value;

                done = true;
                for (std::size_t dim = coords.size(); dim-- > 0;)
                {
                    if (coords[dim] < stop[dim])
                    {
                        ++coords[dim];
                        for (std::size_t reset = dim + 1; reset < coords.size(); ++reset)
                        {
                            coords[reset] = start[reset];
                        }
                        done = false;
                        break;
                    }
                }
            }

            local_mean[flat] = sum / window_volume;
            local_variance[flat] =
                sum_sq / window_volume - local_mean[flat] * local_mean[flat];
        }

        const float estimated_noise =
            noise < 0.0
                ? std::accumulate(local_variance.begin(), local_variance.end(), 0.0) /
                      static_cast<float>(local_variance.size())
                : noise;

        RealArray output = cusignal::core::make_real_array(image.shape);
        for (std::size_t flat = 0; flat < total; ++flat)
        {
            const float mean = local_mean[flat];
            const float variance = local_variance[flat];
            const float local_noise = estimated_noise;
            if (variance < local_noise || variance <= 0.0)
            {
                output.values[flat] = mean;
            }
            else
            {
                output.values[flat] =
                    mean + (1.0 - local_noise / variance) * (image.values[flat] - mean);
            }
        }
        return output;
    }

    filtering_api::FilterStateResult apply_lfilter_nd(
        const RealSignal &b,
        const RealSignal &a,
        const RealArray &x,
        int axis,
        const RealArray *zi)
    {
        const detail::AxisPlan plan = detail::make_axis_plan(x.shape, axis);
        filtering_api::FilterStateResult result;
        result.output = cusignal::core::make_real_array(x.shape);

        const std::size_t order = std::max(b.size(), a.size()) - 1;
        if (zi != nullptr)
        {
            result.final_state = cusignal::core::make_real_array(
                detail::state_shape_for_filter(x.shape, axis, order));
        }

        for (std::size_t line = 0; line < plan.line_count; ++line)
        {
            const RealSignal input = detail::extract_line(x, plan, line);
            RealSignal state;
            if (zi != nullptr)
            {
                state = detail::extract_state_line(*zi, x.shape, axis, order, line);
            }
            const detail::FilterLineResult filtered =
                detail::lfilter_line(b, a, input, zi != nullptr ? &state : nullptr);
            detail::store_line(result.output, plan, line, filtered.output);
            if (zi != nullptr)
            {
                detail::store_state_line(result.final_state, x.shape, axis, order, line, filtered.final_state);
            }
        }
        return result;
    }

    RealArray apply_filtfilt_nd(
        const RealSignal &b,
        const RealSignal &a,
        const RealArray &x,
        int axis,
        const std::string &padtype,
        int padlen,
        const std::string &method,
        int irlen)
    {
        const detail::AxisPlan plan = detail::make_axis_plan(x.shape, axis);
        RealArray output = cusignal::core::make_real_array(x.shape);
        for (std::size_t line = 0; line < plan.line_count; ++line)
        {
            const RealSignal input = detail::extract_line(x, plan, line);
            RealSignal filtered;
            if (method == "gust")
            {
                filtered = detail::filtfilt_gust_line(b, a, input, irlen);
            }
            else
            {
                filtered = detail::filtfilt_pad_line(b, a, input, padtype, padlen);
            }
            detail::store_line(output, plan, line, filtered);
        }
        return output;
    }

    filtering_api::FilterStateResult apply_sosfilt_nd(
        const RealArray &sos,
        const RealArray &x,
        int axis,
        const RealArray *zi)
    {
        const std::vector<std::array<float, 6>> sections = detail::parse_sos(sos);
        const detail::AxisPlan plan = detail::make_axis_plan(x.shape, axis);
        filtering_api::FilterStateResult result;
        result.output = cusignal::core::make_real_array(x.shape);

        if (zi != nullptr)
        {
            result.final_state = cusignal::core::make_real_array(
                detail::sos_state_shape(x.shape, axis, sections.size()));
        }

        for (std::size_t line = 0; line < plan.line_count; ++line)
        {
            const RealSignal input = detail::extract_line(x, plan, line);
            RealSignal state;
            if (zi != nullptr)
            {
                state = detail::extract_sos_state_line(*zi, x.shape, axis, sections.size(), line);
            }
            const detail::FilterLineResult filtered =
                detail::sosfilt_line(sections, input, zi != nullptr ? &state : nullptr);
            detail::store_line(result.output, plan, line, filtered.output);
            if (zi != nullptr)
            {
                detail::store_sos_state_line(result.final_state, x.shape, axis, sections.size(), line, filtered.final_state);
            }
        }
        return result;
    }

    ComplexSignal hilbert_line(const RealSignal &input, int n)
    {
        std::vector<std::complex<float>> values(input.size());
        for (std::size_t index = 0; index < input.size(); ++index)
        {
            values[index] = {input[index], 0.0};
        }
        std::vector<std::complex<float>> spectrum = fft_complex(values, n);
        if (n % 2 == 0)
        {
            for (int index = 1; index < n / 2; ++index)
            {
                spectrum[static_cast<std::size_t>(index)] *= 2.0;
            }
            for (int index = n / 2 + 1; index < n; ++index)
            {
                spectrum[static_cast<std::size_t>(index)] = 0.0;
            }
        }
        else
        {
            for (int index = 1; index < (n + 1) / 2; ++index)
            {
                spectrum[static_cast<std::size_t>(index)] *= 2.0;
            }
            for (int index = (n + 1) / 2; index < n; ++index)
            {
                spectrum[static_cast<std::size_t>(index)] = 0.0;
            }
        }
        const std::vector<std::complex<float>> analytic = ifft_complex(spectrum, n);
        ComplexSignal output(static_cast<std::size_t>(n), Complex(0.0, 0.0));
        for (int index = 0; index < n; ++index)
        {
            output[static_cast<std::size_t>(index)] = Complex(analytic[static_cast<std::size_t>(index)].real(), analytic[static_cast<std::size_t>(index)].imag());
        }
        return output;
    }

    std::vector<std::complex<float>> fftshift_window(const RealSignal &window)
    {
        std::vector<std::complex<float>> shifted(window.size());
        const std::size_t half = window.size() / 2;
        for (std::size_t index = 0; index < window.size(); ++index)
        {
            shifted[index] = {window[(index + half) % window.size()], 0.0};
        }
        return shifted;
    }

    RealSignal resample_line(
        const RealSignal &input,
        int num,
        core::WindowSpec window,
        const std::string &domain)
    {
        const int n_x = static_cast<int>(input.size());
        std::vector<std::complex<float>> spectrum;
        if (domain == "time")
        {
            std::vector<std::complex<float>> complex_input(input.size());
            for (std::size_t index = 0; index < input.size(); ++index)
            {
                complex_input[index] = {input[index], 0.0};
            }
            spectrum = fft_complex(complex_input, n_x);
        }
        else
        {
            spectrum.resize(input.size());
            for (std::size_t index = 0; index < input.size(); ++index)
            {
                spectrum[index] = {input[index], 0.0};
            }
        }

        if (const auto *window_values = std::get_if<RealSignal>(&window))
        {
            if (!window_values->empty())
            {
                if (window_values->size() != input.size())
                {
                    throw std::invalid_argument("window array length must equal axis length");
                }
                for (std::size_t index = 0; index < spectrum.size(); ++index)
                {
                    spectrum[index] *= (*window_values)[index];
                }
            }
        }
        else if (const auto *window_name = std::get_if<std::string>(&window))
        {
                if (!window_name->empty())
                {
                    const RealSignal spectral_window =
                        cpu::windows::get_window(window, n_x, true);
                    const std::vector<std::complex<float>> shifted = fftshift_window(spectral_window);
                    for (std::size_t index = 0; index < spectrum.size(); ++index)
                    {
                        spectrum[index] *= shifted[index];
                    }
            }
        }

        std::vector<std::complex<float>> Y(static_cast<std::size_t>(num), std::complex<float>(0.0, 0.0));
        const int m = std::min(num, n_x);
        const int m2 = m / 2 + 1;
        for (int index = 0; index < m2; ++index)
        {
            Y[static_cast<std::size_t>(index)] = spectrum[static_cast<std::size_t>(index)];
        }
        if (m2 < m)
        {
            for (int index = 0; index < m - m2; ++index)
            {
                Y[static_cast<std::size_t>(num - (m - m2) + index)] =
                    spectrum[static_cast<std::size_t>(n_x - (m - m2) + index)];
            }
        }
        if (m % 2 == 0)
        {
            if (num < n_x)
            {
                Y[static_cast<std::size_t>(num - m / 2)] += spectrum[static_cast<std::size_t>(n_x - m / 2)];
            }
            else if (n_x < num)
            {
                Y[static_cast<std::size_t>(m / 2)] *= 0.5;
                Y[static_cast<std::size_t>(num - m / 2)] = Y[static_cast<std::size_t>(m / 2)];
            }
        }

        const std::vector<std::complex<float>> y = ifft_complex(Y, num);
        const float scale = static_cast<float>(num) / static_cast<float>(n_x);
        RealSignal output(static_cast<std::size_t>(num), 0.0);
        for (int index = 0; index < num; ++index)
        {
            output[static_cast<std::size_t>(index)] = y[static_cast<std::size_t>(index)].real() * scale;
        }
        return output;
    }

    ComplexSignal dft(const ComplexSignal &input)
    {
        std::vector<std::complex<float>> values(input.size());
        for (std::size_t index = 0; index < input.size(); ++index)
        {
            values[index] = {input[index].real(), input[index].imag()};
        }
        const auto output = fft_complex(values, static_cast<int>(input.size()));
        ComplexSignal result(input.size(), Complex(0.0, 0.0));
        for (std::size_t index = 0; index < input.size(); ++index)
        {
            result[index] = Complex(output[index].real(), output[index].imag());
        }
        return result;
    }

} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace filtering
        {

            core::RealArray wiener(const core::RealArray &image)
            {
                return wiener(image, core::Shape(image.rank(), 3), -1.0);
            }

            core::RealArray wiener(
                const core::RealArray &image,
                int mysize,
                float noise)
            {
                detail::ensure_positive_int(mysize, "mysize");
                return wiener(image, core::Shape(image.rank(), static_cast<std::size_t>(mysize)), noise);
            }

            core::RealArray wiener(
                const core::RealArray &image,
                const core::Shape &mysize,
                float noise)
            {
                if (mysize.empty())
                {
                    throw std::invalid_argument("mysize must not be empty");
                }
                if (mysize.size() != image.rank())
                {
                    throw std::invalid_argument("mysize rank must match image rank");
                }
                return wiener_impl(image, mysize, noise);
            }

            core::RealArray firfilter(
                const core::RealSignal &b,
                const core::RealArray &x,
                int axis)
            {
                return apply_lfilter_nd(b, core::RealSignal{1.0}, x, axis, nullptr).output;
            }

            filtering_api::FilterStateResult firfilter(
                const core::RealSignal &b,
                const core::RealArray &x,
                int axis,
                const core::RealArray &zi)
            {
                return apply_lfilter_nd(b, core::RealSignal{1.0}, x, axis, &zi);
            }

            core::RealArray lfilter(
                const core::RealSignal &b,
                const core::RealSignal &a,
                const core::RealArray &x,
                int axis)
            {
                return apply_lfilter_nd(b, a, x, axis, nullptr).output;
            }

            filtering_api::FilterStateResult lfilter(
                const core::RealSignal &b,
                const core::RealSignal &a,
                const core::RealArray &x,
                int axis,
                const core::RealArray &zi)
            {
                return apply_lfilter_nd(b, a, x, axis, &zi);
            }

            core::RealSignal lfilter_zi(
                const core::RealSignal &b,
                const core::RealSignal &a)
            {
                return detail::lfilter_zi(b, a);
            }

            core::RealSignal firfilter_zi(const core::RealSignal &b)
            {
                return detail::firfilter_zi(b);
            }

            core::RealArray firfilter2(
                const core::RealSignal &b,
                const core::RealArray &x,
                int axis,
                const std::string &padtype,
                int padlen,
                const std::string &method,
                int irlen)
            {
                return apply_filtfilt_nd(
                    b,
                    core::RealSignal{1.0},
                    x,
                    axis,
                    detail::normalize_padtype(padtype),
                    padlen,
                    detail::normalize_method(method),
                    irlen);
            }

            core::RealArray filtfilt(
                const core::RealSignal &b,
                const core::RealSignal &a,
                const core::RealArray &x,
                int axis,
                const std::string &padtype,
                int padlen,
                const std::string &method,
                int irlen)
            {
                return apply_filtfilt_nd(
                    b,
                    a,
                    x,
                    axis,
                    detail::normalize_padtype(padtype),
                    padlen,
                    detail::normalize_method(method),
                    irlen);
            }

            core::RealArray sosfilt(
                const core::RealArray &sos,
                const core::RealArray &x,
                int axis)
            {
                return apply_sosfilt_nd(sos, x, axis, nullptr).output;
            }

            filtering_api::FilterStateResult sosfilt(
                const core::RealArray &sos,
                const core::RealArray &x,
                int axis,
                const core::RealArray &zi)
            {
                return apply_sosfilt_nd(sos, x, axis, &zi);
            }

            core::ComplexArray hilbert(
                const core::RealArray &x,
                int n,
                int axis)
            {
                const detail::AxisPlan plan = detail::make_axis_plan(x.shape, axis);
                const int target = n > 0 ? n : static_cast<int>(plan.axis_size);
                ComplexArray output = core::make_complex_array(core::replace_axis_size(x.shape, axis, static_cast<std::size_t>(target)));
                const detail::AxisPlan output_plan = detail::make_axis_plan(output.shape, axis);
                for (std::size_t line = 0; line < plan.line_count; ++line)
                {
                    const RealSignal input = detail::extract_line(x, plan, line);
                    const ComplexSignal analytic = hilbert_line(input, target);
                    detail::store_complex_line(output, output_plan, line, analytic);
                }
                return output;
            }

            core::ComplexArray hilbert2(const core::RealArray &x, const core::Shape &n)
            {
                if (x.rank() != 2)
                {
                    throw std::invalid_argument("x must be rank-2 for hilbert2");
                }
                Shape target = n.empty() ? x.shape : n;
                if (target.size() != 2)
                {
                    throw std::invalid_argument("n must be empty or hold exactly two dimensions");
                }

                const std::size_t rows = target[0];
                const std::size_t cols = target[1];
                std::vector<fftw_complex> fft_in(rows * cols);
                std::vector<fftw_complex> fft_out(rows * cols);
                for (std::size_t row = 0; row < rows; ++row)
                {
                    for (std::size_t col = 0; col < cols; ++col)
                    {
                        const bool inside = row < x.shape[0] && col < x.shape[1];
                        const float value = inside ? x.values[row * x.shape[1] + col] : 0.0;
                        fft_in[row * cols + col][0] = value;
                        fft_in[row * cols + col][1] = 0.0;
                    }
                }

                fftw_plan plan = fftw_plan_dft_2d(
                    static_cast<int>(rows),
                    static_cast<int>(cols),
                    fft_in.data(),
                    fft_out.data(),
                    FFTW_FORWARD,
                    FFTW_ESTIMATE);
                if (plan == nullptr)
                {
                    throw std::runtime_error("failed to create FFTW plan");
                }
                fftw_execute(plan);
                fftw_destroy_plan(plan);

                const std::size_t k0 = (rows + 1) / 2;
                const std::size_t k1 = (cols + 1) / 2;
                if (k0 > 1)
                {
                    for (std::size_t row = 1; row < k0; ++row)
                    {
                        for (std::size_t col = 0; col < cols; ++col)
                        {
                            fft_out[row * cols + col][0] *= 2.0;
                            fft_out[row * cols + col][1] *= 2.0;
                        }
                    }
                }
                if (k1 > 1)
                {
                    for (std::size_t row = 0; row < rows; ++row)
                    {
                        for (std::size_t col = 1; col < k1; ++col)
                        {
                            fft_out[row * cols + col][0] *= 2.0;
                            fft_out[row * cols + col][1] *= 2.0;
                        }
                    }
                }
                for (std::size_t row = k0; row < rows; ++row)
                {
                    for (std::size_t col = 0; col < cols; ++col)
                    {
                        fft_out[row * cols + col][0] = 0.0;
                        fft_out[row * cols + col][1] = 0.0;
                    }
                }
                for (std::size_t row = 0; row < rows; ++row)
                {
                    for (std::size_t col = k1; col < cols; ++col)
                    {
                        fft_out[row * cols + col][0] = 0.0;
                        fft_out[row * cols + col][1] = 0.0;
                    }
                }

                fftw_plan inverse = fftw_plan_dft_2d(
                    static_cast<int>(rows),
                    static_cast<int>(cols),
                    fft_out.data(),
                    fft_in.data(),
                    FFTW_BACKWARD,
                    FFTW_ESTIMATE);
                if (inverse == nullptr)
                {
                    throw std::runtime_error("failed to create FFTW plan");
                }
                fftw_execute(inverse);
                fftw_destroy_plan(inverse);

                ComplexArray output = core::make_complex_array(target);
                const float scale = 1.0 / static_cast<float>(rows * cols);
                for (std::size_t index = 0; index < rows * cols; ++index)
                {
                    output.values[index] = Complex(fft_in[index][0] * scale, fft_in[index][1] * scale);
                }
                return output;
            }

            core::RealArray detrend(
                const core::RealArray &data,
                int axis,
                const std::string &type,
                const core::IndexVector &bp,
                bool overwrite_data)
            {
                (void)overwrite_data;
                const std::string trend = detail::normalize_trend_type(type);
                const detail::AxisPlan plan = detail::make_axis_plan(data.shape, axis);
                RealArray output = data;
                for (std::size_t line = 0; line < plan.line_count; ++line)
                {
                    RealSignal values = detail::extract_line(data, plan, line);
                    if (trend == "constant" || trend == "c")
                    {
                        const float mean =
                            std::accumulate(values.begin(), values.end(), 0.0f) / static_cast<float>(values.size());
                        for (float &value : values)
                        {
                            value -= mean;
                        }
                    }
                    else
                    {
                        IndexVector breaks = bp;
                        breaks.push_back(0);
                        breaks.push_back(static_cast<int>(values.size()));
                        std::sort(breaks.begin(), breaks.end());
                        breaks.erase(std::unique(breaks.begin(), breaks.end()), breaks.end());
                        if (breaks.back() != static_cast<int>(values.size()))
                        {
                            throw std::invalid_argument("Breakpoints must be less than length of data along given axis.");
                        }
                        if (breaks.size() == 2 && values.size() >= 1024)
                        {
                            detrend_linear_pairwise_like_zx_gpu(values);
                        }
                        else
                        {
                            for (std::size_t segment = 0; segment + 1 < breaks.size(); ++segment)
                            {
                                const int begin = breaks[segment];
                                const int end = breaks[segment + 1];
                                const int count = end - begin;
                                if (count <= 0)
                                {
                                    continue;
                                }
                                float sum_t = 0.0f;
                                float sum_t2 = 0.0f;
                                float sum_y = 0.0f;
                                float sum_ty = 0.0f;
                                for (int index = 0; index < count; ++index)
                                {
                                    const float t = static_cast<float>(index + 1) / static_cast<float>(count);
                                    const float y = values[static_cast<std::size_t>(begin + index)];
                                    sum_t += t;
                                    sum_t2 += t * t;
                                    sum_y += y;
                                    sum_ty += t * y;
                                }
                                const float count_f = static_cast<float>(count);
                                const float det = count_f * sum_t2 - sum_t * sum_t;
                                const float slope = (count_f * sum_ty - sum_t * sum_y) / det;
                                const float intercept = (sum_y - slope * sum_t) / count_f;
                                for (int index = 0; index < count; ++index)
                                {
                                    const float t = static_cast<float>(index + 1) / count_f;
                                    const std::size_t value_index = static_cast<std::size_t>(begin + index);
                                    values[value_index] -= intercept + slope * t;
                                }
                            }
                        }
                    }
                    detail::store_line(output, plan, line, values);
                }
                return output;
            }

            core::ComplexArray freq_shift(
                const core::ComplexArray &x,
                float freq,
                float fs)
            {
                if (!(fs > 0.0))
                {
                    throw std::invalid_argument("fs must be > 0");
                }
                ComplexArray output = core::make_complex_array(x.shape);
                for (std::size_t index = 0; index < x.values.size(); ++index)
                {
                    const float t = static_cast<float>(index) / fs;
                    const Complex phase = std::exp(Complex(0.0, 2.0 * kPi * freq * t));
                    output.values[index] = x.values[index] * phase;
                }
                return output;
            }

            filtering_api::ChannelizerResult channelize_poly(
                const core::ComplexSignal &x,
                const core::RealSignal &h,
                int n_chans)
            {
                detail::ensure_positive_int(n_chans, "n_chans");
                const std::size_t channels = static_cast<std::size_t>(n_chans);
                filtering_api::ChannelizerResult result;
                const std::size_t n_pts = x.size() / channels;
                result.channels = core::make_complex_array(Shape{n_pts, channels});

                RealSignal h_padded = h;
                if (h_padded.size() % channels != 0)
                {
                    h_padded.resize(((h_padded.size() + channels - 1) / channels) * channels, 0.0);
                }
                const std::size_t taps_per_phase = h_padded.size() / channels;

                for (std::size_t point = 0; point < n_pts; ++point)
                {
                    ComplexSignal accum(channels, Complex(0.0, 0.0));
                    for (std::size_t phase = 0; phase < channels; ++phase)
                    {
                        Complex value(0.0, 0.0);
                        for (std::size_t tap = 0; tap < taps_per_phase; ++tap)
                        {
                            const long long sample_index =
                                static_cast<long long>(point * channels + phase) -
                                static_cast<long long>(tap * channels);
                            if (sample_index >= 0 &&
                                sample_index < static_cast<long long>(x.size()))
                            {
                                value += x[static_cast<std::size_t>(sample_index)] *
                                         h_padded[tap * channels + phase];
                            }
                        }
                        accum[phase] = value;
                    }
                    const ComplexSignal spectrum = dft(accum);
                    for (std::size_t channel = 0; channel < channels; ++channel)
                    {
                        result.channels.values[point * channels + channel] = spectrum[channel];
                    }
                }
                return result;
            }

            core::RealArray decimate(
                const core::RealArray &x,
                int q,
                int n,
                int axis,
                bool zero_phase)
            {
                detail::ensure_positive_int(q, "q");
                const int order = n < 0 ? 20 * q : n;
                const RealSignal taps =
                    cpu::filter_design::firwin(order + 1, 1.0 / static_cast<float>(q));
                if (zero_phase)
                {
                    const RealArray filtered = upfirdn(taps, x, 1, q, axis);
                    const detail::AxisPlan filtered_plan = detail::make_axis_plan(filtered.shape, axis);
                    const std::size_t output_size =
                        detail::resampled_size(core::axis_size(x, axis), 1, q);
                    const Shape output_shape =
                        core::replace_axis_size(x.shape, axis, output_size);
                    const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
                    RealArray output = core::make_real_array(output_shape);
                    const std::size_t delay = (static_cast<std::size_t>(order) / 2) / static_cast<std::size_t>(q);
                    for (std::size_t line = 0; line < output_plan.line_count; ++line)
                    {
                        const RealSignal source = detail::extract_line(filtered, filtered_plan, line);
                        RealSignal downsampled(output_plan.axis_size, 0.0);
                        for (std::size_t index = 0; index < output_plan.axis_size; ++index)
                        {
                            const std::size_t source_index = index + delay;
                            if (source_index < source.size())
                            {
                                downsampled[index] = source[source_index];
                            }
                        }
                        detail::store_line(output, output_plan, line, downsampled);
                    }
                    return output;
                }

                const RealArray filtered = firfilter(taps, x, axis);
                const detail::AxisPlan input_plan = detail::make_axis_plan(filtered.shape, axis);
                const Shape output_shape =
                    core::replace_axis_size(filtered.shape, axis, detail::decimated_size(input_plan.axis_size, q));
                const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
                RealArray output = core::make_real_array(output_shape);
                for (std::size_t line = 0; line < output_plan.line_count; ++line)
                {
                    const RealSignal source = detail::extract_line(filtered, input_plan, line);
                    RealSignal downsampled(output_plan.axis_size, 0.0);
                    for (std::size_t index = 0; index < output_plan.axis_size; ++index)
                    {
                        downsampled[index] = source[index * static_cast<std::size_t>(q)];
                    }
                    detail::store_line(output, output_plan, line, downsampled);
                }
                return output;
            }

            core::RealArray resample(
                const core::RealArray &x,
                int num,
                int axis,
                core::WindowSpec window,
                const std::string &domain)
            {
                detail::ensure_positive_int(num, "num");
                detail::validate_window_spec(window);
                const std::string resolved_domain = detail::normalize_domain(domain);
                const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape, axis);
                const Shape output_shape = core::replace_axis_size(x.shape, axis, static_cast<std::size_t>(num));
                const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
                RealArray output = core::make_real_array(output_shape);
                for (std::size_t line = 0; line < input_plan.line_count; ++line)
                {
                    const RealSignal input = detail::extract_line(x, input_plan, line);
                    const RealSignal resampled = resample_line(input, num, window, resolved_domain);
                    detail::store_line(output, output_plan, line, resampled);
                }
                return output;
            }

            filtering_api::ResampleResult resample(
                const core::RealArray &x,
                int num,
                const core::RealSignal &t,
                int axis,
                core::WindowSpec window,
                const std::string &domain)
            {
                if (t.size() < 2)
                {
                    throw std::invalid_argument("t must contain at least two samples");
                }
                filtering_api::ResampleResult result;
                result.output = resample(x, num, axis, window, domain);
                const float step = (t[1] - t[0]) * static_cast<float>(t.size()) / static_cast<float>(num);
                result.time.resize(static_cast<std::size_t>(num), 0.0);
                for (int index = 0; index < num; ++index)
                {
                    result.time[static_cast<std::size_t>(index)] =
                        t[0] + step * static_cast<float>(index);
                }
                return result;
            }

            core::RealArray upfirdn(
                const core::RealSignal &h,
                const core::RealArray &x,
                int up,
                int down,
                int axis)
            {
                detail::ensure_positive_int(up, "up");
                detail::ensure_positive_int(down, "down");
                const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape, axis);
                const Shape output_shape =
                    core::replace_axis_size(
                        x.shape,
                        axis,
                        detail::upfirdn_size(input_plan.axis_size, h.size(), up, down));
                const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
                RealArray output = core::make_real_array(output_shape);

                for (std::size_t line = 0; line < input_plan.line_count; ++line)
                {
                    const RealSignal input = detail::extract_line(x, input_plan, line);
                    const std::size_t up_len = input.size() * static_cast<std::size_t>(up);
                    RealSignal upsampled(up_len, 0.0);
                    for (std::size_t index = 0; index < input.size(); ++index)
                    {
                        upsampled[index * static_cast<std::size_t>(up)] = input[index];
                    }
                    RealSignal convolved(upsampled.size() + h.size() - 1, 0.0);
                    for (std::size_t out_index = 0; out_index < convolved.size(); ++out_index)
                    {
                        float value = 0.0;
                        const std::size_t tap_begin = out_index >= upsampled.size() ? out_index - upsampled.size() + 1 : 0;
                        const std::size_t tap_end = std::min(out_index + 1, h.size());
                        for (std::size_t tap = tap_begin; tap < tap_end; ++tap)
                        {
                            value += h[tap] * upsampled[out_index - tap];
                        }
                        convolved[out_index] = value;
                    }
                    RealSignal downsampled(output_plan.axis_size, 0.0);
                    for (std::size_t index = 0; index < output_plan.axis_size; ++index)
                    {
                        downsampled[index] = convolved[index * static_cast<std::size_t>(down)];
                    }
                    detail::store_line(output, output_plan, line, downsampled);
                }
                return output;
            }

            core::RealArray resample_poly(
                const core::RealArray &x,
                int up,
                int down,
                int axis,
                core::WindowSpec window)
            {
                detail::validate_window_spec(window);
                detail::ensure_positive_int(up, "up");
                detail::ensure_positive_int(down, "down");
                const int g = std::gcd(up, down);
                up /= g;
                down /= g;
                if (up == 1 && down == 1)
                {
                    return x;
                }

                const std::size_t input_size = core::axis_size(x, axis);
                const std::size_t output_size = detail::resampled_size(input_size, up, down);

                RealSignal h;
                std::size_t half_len = 0;
                if (const auto *values = std::get_if<RealSignal>(&window))
                {
                    h = *values;
                    half_len = h.empty() ? 0 : (h.size() - 1) / 2;
                }
                else
                {
                    const int max_rate = std::max(up, down);
                    half_len = static_cast<std::size_t>(10 * max_rate);
                    h = cpu::filter_design::firwin(
                        static_cast<int>(2 * half_len + 1),
                        1.0 / static_cast<float>(max_rate),
                        -1.0,
                        window);
                }

                for (float &value : h)
                {
                    value *= static_cast<float>(up);
                }

                std::size_t n_pre_pad =
                    static_cast<std::size_t>(down) - (half_len % static_cast<std::size_t>(down));
                std::size_t n_post_pad = 0;
                const std::size_t n_pre_remove =
                    (half_len + n_pre_pad) / static_cast<std::size_t>(down);
                while (detail::upfirdn_size(input_size, h.size() + n_pre_pad + n_post_pad, up, down) <
                       output_size + n_pre_remove)
                {
                    ++n_post_pad;
                }

                RealSignal padded_filter(n_pre_pad, 0.0);
                padded_filter.insert(padded_filter.end(), h.begin(), h.end());
                padded_filter.insert(padded_filter.end(), n_post_pad, 0.0);

                const RealArray filtered = upfirdn(padded_filter, x, up, down, axis);
                const detail::AxisPlan filtered_plan = detail::make_axis_plan(filtered.shape, axis);
                const Shape output_shape = core::replace_axis_size(x.shape, axis, output_size);
                const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
                RealArray output = core::make_real_array(output_shape);

                for (std::size_t line = 0; line < output_plan.line_count; ++line)
                {
                    const RealSignal source = detail::extract_line(filtered, filtered_plan, line);
                    RealSignal trimmed(output_size, 0.0);
                    for (std::size_t index = 0; index < output_size; ++index)
                    {
                        trimmed[index] = source[index + n_pre_remove];
                    }
                    detail::store_line(output, output_plan, line, trimmed);
                }
                return output;
            }

        } // namespace filtering
    } // namespace cpu
} // namespace cusignal
