#include "cusignal/radartools/radartools.hpp"

#include <fftw3.h>

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <vector>

#include "cusignal/windows/windows.hpp"

#include "../common/radartools_detail.hpp"

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    namespace detail = cusignal::radartools_detail;

    class FftwBuffer
    {
    public:
        explicit FftwBuffer(int size)
            : size_(size),
              data_(reinterpret_cast<fftw_complex *>(fftw_malloc(sizeof(fftw_complex) * static_cast<std::size_t>(size))))
        {
            if (data_ == nullptr)
            {
                throw std::bad_alloc();
            }
            for (int index = 0; index < size_; ++index)
            {
                data_[index][0] = 0.0;
                data_[index][1] = 0.0;
            }
        }

        ~FftwBuffer()
        {
            if (data_ != nullptr)
            {
                fftw_free(data_);
            }
        }

        FftwBuffer(const FftwBuffer &) = delete;
        FftwBuffer &operator=(const FftwBuffer &) = delete;

        fftw_complex *data()
        {
            return data_;
        }

        const fftw_complex *data() const
        {
            return data_;
        }

        int size() const
        {
            return size_;
        }

    private:
        int size_ = 0;
        fftw_complex *data_ = nullptr;
    };

    void copy_to_fftw(const ComplexSignal &input, FftwBuffer &buffer)
    {
        const std::size_t limit = std::min(input.size(), static_cast<std::size_t>(buffer.size()));
        for (int index = 0; index < buffer.size(); ++index)
        {
            buffer.data()[index][0] = 0.0;
            buffer.data()[index][1] = 0.0;
        }
        for (std::size_t index = 0; index < limit; ++index)
        {
            buffer.data()[static_cast<int>(index)][0] = input[index].real();
            buffer.data()[static_cast<int>(index)][1] = input[index].imag();
        }
    }

    ComplexSignal read_from_fftw(const FftwBuffer &buffer, bool scale_inverse)
    {
        ComplexSignal output(static_cast<std::size_t>(buffer.size()), Complex(0.0, 0.0));
        const float scale = scale_inverse ? 1.0 / static_cast<float>(buffer.size()) : 1.0;
        for (int index = 0; index < buffer.size(); ++index)
        {
            output[static_cast<std::size_t>(index)] =
                Complex(buffer.data()[index][0] * scale, buffer.data()[index][1] * scale);
        }
        return output;
    }

    ComplexSignal fft_host(const ComplexSignal &input, int nfft)
    {
        FftwBuffer buffer(nfft);
        copy_to_fftw(input, buffer);
        fftw_plan plan =
            fftw_plan_dft_1d(nfft, buffer.data(), buffer.data(), FFTW_FORWARD, FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("fftw_plan_dft_1d failed");
        }
        fftw_execute(plan);
        fftw_destroy_plan(plan);
        return read_from_fftw(buffer, false);
    }

    ComplexSignal ifft_host(const ComplexSignal &input, int nfft)
    {
        FftwBuffer buffer(nfft);
        copy_to_fftw(input, buffer);
        fftw_plan plan =
            fftw_plan_dft_1d(nfft, buffer.data(), buffer.data(), FFTW_BACKWARD, FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("fftw_plan_dft_1d failed");
        }
        fftw_execute(plan);
        fftw_destroy_plan(plan);
        return read_from_fftw(buffer, true);
    }

    ComplexSignal multiply_conjugate(
        const ComplexSignal &lhs,
        const ComplexSignal &rhs)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::invalid_argument("frequency-domain vectors must have the same length");
        }
        ComplexSignal output(lhs.size(), Complex(0.0, 0.0));
        for (std::size_t index = 0; index < lhs.size(); ++index)
        {
            output[index] = lhs[index] * std::conj(rhs[index]);
        }
        return output;
    }

    RealSignal abs_fftshift(const ComplexSignal &input)
    {
        const std::size_t size = input.size();
        const std::size_t shift = (size + 1) / 2;
        RealSignal output(size, 0.0);
        for (std::size_t index = 0; index < size; ++index)
        {
            output[index] = std::abs(input[(index + shift) % size]);
        }
        return output;
    }

    RealSignal abs_ifftshift(const ComplexSignal &input)
    {
        const std::size_t size = input.size();
        const std::size_t shift = size / 2;
        RealSignal output(size, 0.0);
        for (std::size_t index = 0; index < size; ++index)
        {
            output[index] = std::abs(input[(index + shift) % size]);
        }
        return output;
    }

    std::size_t product(const cusignal::core::Shape &shape)
    {
        return cusignal::core::shape_product(shape);
    }
} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace radartools
        {

            core::ComplexArray fftshift_rows(const core::ComplexArray &input)
            {
                detail::ensure_rank(input, 2, "input");
                const std::size_t rows = input.shape[0];
                const std::size_t cols = input.shape[1];
                core::ComplexArray output = core::make_complex_array(input.shape, core::Complex(0.0f, 0.0f));
                for (std::size_t row = 0; row < rows; ++row)
                {
                    const std::size_t shifted_row = (row + rows / 2) % rows;
                    std::copy_n(
                        input.values.begin() + static_cast<std::ptrdiff_t>(row * cols),
                        cols,
                        output.values.begin() + static_cast<std::ptrdiff_t>(shifted_row * cols));
                }
                return output;
            }

            core::RealArray power_map(const core::ComplexArray &input)
            {
                core::RealArray output = core::make_real_array(input.shape);
                for (std::size_t index = 0; index < input.values.size(); ++index)
                    output.values[index] = std::norm(input.values[index]);
                return output;
            }

            radartools_api::DetectionSummary detect_peak(
                const core::RealArray &power,
                const core::RealArray &detections,
                int nfft,
                float prf)
            {
                detail::ensure_rank(power, 2, "power");
                if (detections.shape != power.shape)
                    throw std::invalid_argument("power and detections shape mismatch");
                if (nfft <= 0 || !(prf > 0.0f))
                    throw std::invalid_argument("nfft and prf must be positive");
                radartools_api::DetectionSummary result;
                for (std::size_t index = 0; index < power.values.size(); ++index)
                {
                    if (detections.values[index] <= 0.5f ||
                        (result.found && power.values[index] <= result.power))
                        continue;
                    result.found = true;
                    result.power = power.values[index];
                    result.range_bin = static_cast<int>(index % power.shape[1]);
                    result.doppler_bin = static_cast<int>(index / power.shape[1]);
                }
                if (result.found)
                {
                    result.doppler_hz = static_cast<float>(result.doppler_bin - nfft / 2) *
                        prf / static_cast<float>(nfft);
                }
                return result;
            }

            core::ComplexArray pulse_compression(
                const core::ComplexArray &x,
                const core::ComplexSignal &templ,
                bool normalize,
                core::WindowSpec window,
                int nfft)
            {
                detail::ensure_rank(x, 2, "x");
                if (templ.empty())
                {
                    throw std::invalid_argument("templ must not be empty");
                }

                const std::size_t num_pulses = x.shape[0];
                const std::size_t samples_per_pulse = x.shape[1];
                const int resolved_nfft =
                    nfft > 0 ? nfft : static_cast<int>(samples_per_pulse);

                ComplexSignal templ_work = templ;
                if (!detail::window_disabled(window))
                {
                    templ_work = detail::apply_window(
                        templ_work,
                        cpu::windows::get_window(window, static_cast<int>(templ_work.size()), false));
                }
                if (normalize)
                {
                    templ_work = detail::normalize_l2(templ_work);
                }
                const ComplexSignal templ_fft = fft_host(templ_work, resolved_nfft);

                core::ComplexArray output =
                    core::make_complex_array(core::Shape{num_pulses, static_cast<std::size_t>(resolved_nfft)});
                for (std::size_t pulse = 0; pulse < num_pulses; ++pulse)
                {
                    ComplexSignal row(samples_per_pulse, Complex(0.0, 0.0));
                    const std::size_t base = pulse * samples_per_pulse;
                    for (std::size_t sample = 0; sample < samples_per_pulse; ++sample)
                    {
                        row[sample] = x.values[base + sample];
                    }
                    const ComplexSignal fft_row = fft_host(row, resolved_nfft);
                    const ComplexSignal compressed =
                        ifft_host(multiply_conjugate(fft_row, templ_fft), resolved_nfft);
                    const std::size_t out_base = pulse * static_cast<std::size_t>(resolved_nfft);
                    for (int sample = 0; sample < resolved_nfft; ++sample)
                    {
                        output.values[out_base + static_cast<std::size_t>(sample)] =
                            compressed[static_cast<std::size_t>(sample)];
                    }
                }
                return output;
            }

            core::ComplexArray pulse_doppler(
                const core::ComplexArray &x,
                core::WindowSpec window,
                int nfft)
            {
                detail::ensure_rank(x, 2, "x");
                const std::size_t num_pulses = x.shape[0];
                const std::size_t samples_per_pulse = x.shape[1];
                const int resolved_nfft =
                    nfft > 0 ? nfft : static_cast<int>(num_pulses);

                RealSignal window_values;
                if (!detail::window_disabled(window))
                {
                    window_values =
                        cpu::windows::get_window(window, static_cast<int>(num_pulses), false);
                }

                core::ComplexArray output =
                    core::make_complex_array(core::Shape{static_cast<std::size_t>(resolved_nfft), samples_per_pulse});
                for (std::size_t column = 0; column < samples_per_pulse; ++column)
                {
                    ComplexSignal line(num_pulses, Complex(0.0, 0.0));
                    for (std::size_t pulse = 0; pulse < num_pulses; ++pulse)
                    {
                        Complex value = x.values[pulse * samples_per_pulse + column];
                        if (!window_values.empty())
                        {
                            value *= window_values[pulse];
                        }
                        line[pulse] = value;
                    }
                    const ComplexSignal spectrum = fft_host(line, resolved_nfft);
                    for (int row = 0; row < resolved_nfft; ++row)
                    {
                        output.values[static_cast<std::size_t>(row) * samples_per_pulse + column] =
                            spectrum[static_cast<std::size_t>(row)];
                    }
                }
                return output;
            }

            radartools_api::AmbgfunResult ambgfun(
                const core::ComplexSignal &x,
                float fs,
                float prf,
                const std::string &cut,
                float cut_value)
            {
                return ambgfun(x, x, fs, prf, cut, cut_value);
            }

            radartools_api::AmbgfunResult ambgfun(
                const core::ComplexSignal &x,
                const core::ComplexSignal &y,
                float fs,
                float prf,
                const std::string &cut,
                float cut_value)
            {
                detail::ensure_positive(fs, "fs");
                detail::ensure_positive(prf, "prf");
                if (x.empty() || y.empty())
                {
                    throw std::invalid_argument("ambgfun inputs must not be empty");
                }

                const std::string normalized_cut = detail::normalize_cut(cut);
                const ComplexSignal xnorm = detail::normalize_l2(x);
                const ComplexSignal ynorm = detail::normalize_l2(y);
                const std::size_t xlen = xnorm.size();
                const std::size_t ylen = ynorm.size();
                const int len_seq = static_cast<int>(xlen + ylen);
                const int nfreq = detail::next_power_of_two(len_seq - 1);

                if (normalized_cut == "2d")
                {
                    const std::size_t rows = xlen + ylen - 1;
                    core::RealArray values =
                        core::make_real_array(core::Shape{rows, static_cast<std::size_t>(nfreq)});
                    for (std::size_t row = 0; row < rows; ++row)
                    {
                        ComplexSignal shifted(static_cast<std::size_t>(nfreq), Complex(0.0, 0.0));
                        for (std::size_t col = 0; col < ylen; ++col)
                        {
                            const long long x_index =
                                static_cast<long long>(col) - static_cast<long long>(xlen - 1) +
                                static_cast<long long>(row);
                            if (x_index >= 0 && x_index < static_cast<long long>(xlen))
                            {
                                shifted[col] = ynorm[col] * std::conj(xnorm[static_cast<std::size_t>(x_index)]);
                            }
                        }
                        const ComplexSignal ifft_row = ifft_host(shifted, nfreq);
                        const RealSignal shifted_abs = abs_fftshift(ifft_row);
                        for (int col = 0; col < nfreq; ++col)
                        {
                            values.values[row * static_cast<std::size_t>(nfreq) + static_cast<std::size_t>(col)] =
                                shifted_abs[static_cast<std::size_t>(col)] * static_cast<float>(nfreq);
                        }
                    }

                    radartools_api::AmbgfunSurfaceResult result;
                    result.values = std::move(values);
                    result.delay_axis = detail::build_delay_axis(xlen, ylen, fs);
                    result.doppler_axis = detail::build_doppler_axis(static_cast<std::size_t>(nfreq), fs);
                    return result;
                }

                if (normalized_cut == "delay")
                {
                    const RealSignal axis = detail::build_doppler_axis(static_cast<std::size_t>(nfreq), fs);
                    ComplexSignal xfft = fft_host(xnorm, nfreq);
                    for (int index = 0; index < nfreq; ++index)
                    {
                        const float angle = 2.0 * detail::kPi * axis[static_cast<std::size_t>(index)] * cut_value;
                        xfft[static_cast<std::size_t>(index)] *= Complex(std::cos(angle), std::sin(angle));
                    }
                    ComplexSignal xshift = ifft_host(xfft, nfreq);
                    ComplexSignal ynorm_pad(static_cast<std::size_t>(nfreq), Complex(0.0, 0.0));
                    std::copy(ynorm.begin(), ynorm.end(), ynorm_pad.begin());
                    for (int index = 0; index < nfreq; ++index)
                    {
                        ynorm_pad[static_cast<std::size_t>(index)] *=
                            std::conj(xshift[static_cast<std::size_t>(index)]);
                    }
                    const ComplexSignal ifft_values = ifft_host(ynorm_pad, nfreq);
                    radartools_api::AmbgfunCutResult result;
                    result.values = abs_ifftshift(ifft_values);
                    for (float &value : result.values)
                    {
                        value *= static_cast<float>(nfreq);
                    }
                    result.axis = axis;
                    return result;
                }

                const std::size_t output_size = xlen + ylen - 1;
                ComplexSignal xmod(output_size, Complex(0.0, 0.0));
                for (std::size_t index = 0; index < xlen; ++index)
                {
                    const float angle = 2.0 * detail::kPi * cut_value *
                                         (static_cast<float>(index) / fs);
                    xmod[index] = xnorm[index] * Complex(std::cos(angle), std::sin(angle));
                }
                ComplexSignal ypad(output_size, Complex(0.0, 0.0));
                std::copy(ynorm.begin(), ynorm.end(), ypad.begin());
                const ComplexSignal ffty = fft_host(ypad, static_cast<int>(output_size));
                const ComplexSignal fftx = fft_host(xmod, static_cast<int>(output_size));
                const ComplexSignal ifft_values =
                    ifft_host(multiply_conjugate(ffty, fftx), static_cast<int>(output_size));

                radartools_api::AmbgfunCutResult result;
                result.values = abs_fftshift(ifft_values);
                result.axis = detail::build_delay_axis(xlen, ylen, fs);
                return result;
            }

            float cfar_alpha(float pfa, int cells)
            {
                detail::ensure_probability(pfa);
                if (cells <= 0)
                {
                    throw std::invalid_argument("cells must be > 0");
                }
                return static_cast<float>(cells) * (std::pow(pfa, -1.0f / static_cast<float>(cells)) - 1.0f);
            }

            radartools_api::CfarResult ca_cfar(
                const core::RealArray &array,
                int guard_cells,
                int reference_cells,
                float pfa)
            {
                detail::ensure_rank(array, 1, "array");
                if (guard_cells < 0 || reference_cells < 1)
                {
                    throw std::invalid_argument("guard_cells/reference_cells are invalid");
                }
                const std::size_t size = array.shape[0];
                if (size <= static_cast<std::size_t>(2 * (guard_cells + reference_cells)))
                {
                    throw std::invalid_argument("Array too small for given parameters");
                }

                const float alpha = cfar_alpha(pfa, 2 * reference_cells);
                std::vector<float> prefix(size + 1, 0.0);
                for (std::size_t index = 0; index < size; ++index)
                {
                    prefix[index + 1] = prefix[index] + array.values[index];
                }

                radartools_api::CfarResult result;
                result.threshold = core::make_real_array_like(array);
                result.detections = core::make_real_array_like(array);
                for (std::size_t index = static_cast<std::size_t>(guard_cells + reference_cells);
                     index + static_cast<std::size_t>(guard_cells + reference_cells) < size;
                     ++index)
                {
                    const std::size_t left = index - static_cast<std::size_t>(guard_cells + reference_cells);
                    const std::size_t right = index + static_cast<std::size_t>(guard_cells + reference_cells) + 1;
                    const std::size_t inner_left = index - static_cast<std::size_t>(guard_cells);
                    const std::size_t inner_right = index + static_cast<std::size_t>(guard_cells) + 1;
                    const float outer_sum = prefix[right] - prefix[left];
                    const float guard_sum = prefix[inner_right] - prefix[inner_left];
                    const float threshold = alpha * (outer_sum - guard_sum) /
                                             static_cast<float>(2 * reference_cells);
                    result.threshold.values[index] = threshold;
                    result.detections.values[index] =
                        array.values[index] - threshold > 0.0 ? 1.0 : 0.0;
                }
                return result;
            }

            radartools_api::CfarResult ca_cfar(
                const core::RealArray &array,
                const core::Shape &guard_cells,
                const core::Shape &reference_cells,
                float pfa)
            {
                detail::ensure_rank(array, 2, "array");
                if (guard_cells.size() != 2 || reference_cells.size() != 2)
                {
                    throw std::invalid_argument("guard_cells/reference_cells must each have rank 2");
                }
                const int gcx = static_cast<int>(guard_cells[0]);
                const int gcy = static_cast<int>(guard_cells[1]);
                const int rcx = static_cast<int>(reference_cells[0]);
                const int rcy = static_cast<int>(reference_cells[1]);
                if (gcx < 0 || gcy < 0 || rcx < 1 || rcy < 1)
                {
                    throw std::invalid_argument("guard/reference cells are invalid");
                }
                const std::size_t rows = array.shape[0];
                const std::size_t cols = array.shape[1];
                if (rows <= static_cast<std::size_t>(2 * (gcx + rcx)))
                {
                    throw std::invalid_argument("Array first dimension too small for given parameters.");
                }
                if (cols <= static_cast<std::size_t>(2 * (gcy + rcy)))
                {
                    throw std::invalid_argument("Array second dimension too small for given parameters.");
                }

                const int cells = 2 * rcx * (2 * rcy + 2 * gcy + 1) +
                                  2 * (2 * gcx + 1) * rcy;
                const float alpha = cfar_alpha(pfa, cells);

                std::vector<float> integral((rows + 1) * (cols + 1), 0.0);
                for (std::size_t row = 0; row < rows; ++row)
                {
                    float row_sum = 0.0;
                    for (std::size_t col = 0; col < cols; ++col)
                    {
                        row_sum += array.values[row * cols + col];
                        integral[(row + 1) * (cols + 1) + (col + 1)] =
                            integral[row * (cols + 1) + (col + 1)] + row_sum;
                    }
                }

                const auto rect_sum = [&](int top, int left, int bottom, int right) {
                    const std::size_t t = static_cast<std::size_t>(top);
                    const std::size_t l = static_cast<std::size_t>(left);
                    const std::size_t b = static_cast<std::size_t>(bottom);
                    const std::size_t r = static_cast<std::size_t>(right);
                    return integral[b * (cols + 1) + r] - integral[t * (cols + 1) + r] -
                           integral[b * (cols + 1) + l] + integral[t * (cols + 1) + l];
                };

                radartools_api::CfarResult result;
                result.threshold = core::make_real_array_like(array);
                result.detections = core::make_real_array_like(array);
                for (int row = rcx + gcx; row < static_cast<int>(rows) - rcx - gcx; ++row)
                {
                    for (int col = rcy + gcy; col < static_cast<int>(cols) - rcy - gcy; ++col)
                    {
                        const float outer = rect_sum(
                            row - gcx - rcx,
                            col - gcy - rcy,
                            row + gcx + rcx + 1,
                            col + gcy + rcy + 1);
                        const float inner = rect_sum(
                            row - gcx,
                            col - gcy,
                            row + gcx + 1,
                            col + gcy + 1);
                        const float threshold = alpha * (outer - inner) / static_cast<float>(cells);
                        const std::size_t index = static_cast<std::size_t>(row) * cols + static_cast<std::size_t>(col);
                        result.threshold.values[index] = threshold;
                        result.detections.values[index] =
                            array.values[index] - threshold > 0.0 ? 1.0 : 0.0;
                    }
                }
                return result;
            }

            core::ComplexArray mvdr(
                const core::ComplexArray &x,
                const core::ComplexArray &sv,
                bool calc_cov)
            {
                if (sv.empty())
                {
                    throw std::invalid_argument("sv must not be empty");
                }

                const std::size_t sensors = sv.size();
                ComplexArray covariance;
                if (calc_cov)
                {
                    detail::ensure_rank(x, 2, "x");
                    if (x.shape[0] != sensors)
                    {
                        throw std::invalid_argument("Steering Vector and input data do not align");
                    }
                    covariance = detail::covariance_matrix(x);
                }
                else
                {
                    detail::ensure_rank(x, 2, "x");
                    if (x.shape[0] != x.shape[1])
                    {
                        throw std::invalid_argument("x must be a square covariance matrix when calc_cov is false");
                    }
                    if (x.shape[0] != sensors)
                    {
                        throw std::invalid_argument("Steering Vector and input data do not align");
                    }
                    covariance = x;
                }

                ComplexSignal steering = sv.values;
                const ComplexSignal wb = detail::solve_linear_system(covariance, steering);
                const Complex denom = detail::conjugate_dot(steering, wb);
                if (std::abs(denom) == 0.0)
                {
                    throw std::invalid_argument("mvdr denominator is zero");
                }

                ComplexArray output = core::make_complex_array(sv.shape);
                for (std::size_t index = 0; index < sensors; ++index)
                {
                    output.values[index] = wb[index] / denom;
                }
                return output;
            }

        } // namespace radartools
    } // namespace cpu
} // namespace cusignal
