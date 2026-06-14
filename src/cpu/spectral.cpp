#include "cusignal/spectral/spectral.hpp"

#include <fftw3.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/windows/windows.hpp"

#include "../common/spectral_detail.hpp"

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArray;
    using cusignal::core::ComplexSignal;
    using cusignal::core::DetrendSpec;
    using cusignal::core::RealArray;
    using cusignal::core::RealSignal;
    using cusignal::core::Shape;
    namespace detail = cusignal::spectral_detail;

    constexpr float kPi = 3.141592653589793238462643383279502884;
    constexpr int kVectorStrengthReductionBlock = 256;
    constexpr float kVectorStrengthPhaseFloor = 1.0e-5f;

    float vectorstrength_angle(float event, float period)
    {
        const float turns = event / period;
        const float wrapped = turns - std::floor(turns);
        return 2.0f * kPi * wrapped;
    }

    void vectorstrength_sincos_poly(float angle, float &s, float &c)
    {
        constexpr float two_pi = 2.0f * kPi;
        constexpr float half_pi = 0.5f * kPi;
        if (angle > kPi)
        {
            angle -= two_pi;
        }
        float cos_sign = 1.0f;
        if (angle > half_pi)
        {
            angle = kPi - angle;
            cos_sign = -1.0f;
        }
        else if (angle < -half_pi)
        {
            angle = -kPi - angle;
            cos_sign = -1.0f;
        }
        const float x2 = angle * angle;
        const float x4 = x2 * x2;
        const float x6 = x4 * x2;
        const float x8 = x4 * x4;
        s = angle * (1.0f - x2 * (1.0f / 6.0f) + x4 * (1.0f / 120.0f) -
                     x6 * (1.0f / 5040.0f) + x8 * (1.0f / 362880.0f));
        c = cos_sign * (1.0f - x2 * 0.5f + x4 * (1.0f / 24.0f) -
                        x6 * (1.0f / 720.0f) + x8 * (1.0f / 40320.0f));
    }

    void kahan_add(float value, float &sum, float &compensation)
    {
        const float corrected = value - compensation;
        const float next = sum + corrected;
        compensation = (next - sum) - corrected;
        sum = next;
    }

    std::pair<float, float> vectorstrength_pairwise_like_cuda(
        const RealSignal &events,
        float period)
    {
        const int event_count = static_cast<int>(events.size());
        const int blocks_per_period = std::max(
            1,
            std::min(
                65535,
                (event_count + kVectorStrengthReductionBlock - 1) / kVectorStrengthReductionBlock));
        std::vector<float> partial_real(static_cast<std::size_t>(blocks_per_period), 0.0f);
        std::vector<float> partial_imag(static_cast<std::size_t>(blocks_per_period), 0.0f);
        for (int tile = 0; tile < blocks_per_period; ++tile)
        {
            std::array<float, kVectorStrengthReductionBlock> real_cache{};
            std::array<float, kVectorStrengthReductionBlock> imag_cache{};
            for (int tid = 0; tid < kVectorStrengthReductionBlock; ++tid)
            {
                float sum_real = 0.0f;
                float sum_imag = 0.0f;
                float sum_real_c = 0.0f;
                float sum_imag_c = 0.0f;
                for (int sample = tile * kVectorStrengthReductionBlock + tid;
                     sample < event_count;
                     sample += blocks_per_period * kVectorStrengthReductionBlock)
                {
                    const float angle = vectorstrength_angle(events[static_cast<std::size_t>(sample)], period);
                    float s = 0.0f;
                    float c = 0.0f;
                    vectorstrength_sincos_poly(angle, s, c);
                    kahan_add(c, sum_real, sum_real_c);
                    kahan_add(s, sum_imag, sum_imag_c);
                }
                real_cache[static_cast<std::size_t>(tid)] = sum_real;
                imag_cache[static_cast<std::size_t>(tid)] = sum_imag;
            }
            for (int stride = kVectorStrengthReductionBlock / 2; stride > 0; stride >>= 1)
            {
                for (int tid = 0; tid < stride; ++tid)
                {
                    real_cache[static_cast<std::size_t>(tid)] +=
                        real_cache[static_cast<std::size_t>(tid + stride)];
                    imag_cache[static_cast<std::size_t>(tid)] +=
                        imag_cache[static_cast<std::size_t>(tid + stride)];
                }
            }
            partial_real[static_cast<std::size_t>(tile)] = real_cache[0];
            partial_imag[static_cast<std::size_t>(tile)] = imag_cache[0];
        }

        std::array<float, kVectorStrengthReductionBlock> real_cache{};
        std::array<float, kVectorStrengthReductionBlock> imag_cache{};
        for (int tid = 0; tid < kVectorStrengthReductionBlock; ++tid)
        {
            float sum_real = 0.0f;
            float sum_imag = 0.0f;
            float sum_real_c = 0.0f;
            float sum_imag_c = 0.0f;
            for (int tile = tid; tile < blocks_per_period; tile += kVectorStrengthReductionBlock)
            {
                kahan_add(partial_real[static_cast<std::size_t>(tile)], sum_real, sum_real_c);
                kahan_add(partial_imag[static_cast<std::size_t>(tile)], sum_imag, sum_imag_c);
            }
            real_cache[static_cast<std::size_t>(tid)] = sum_real;
            imag_cache[static_cast<std::size_t>(tid)] = sum_imag;
        }
        for (int stride = kVectorStrengthReductionBlock / 2; stride > 0; stride >>= 1)
        {
            for (int tid = 0; tid < stride; ++tid)
            {
                real_cache[static_cast<std::size_t>(tid)] +=
                    real_cache[static_cast<std::size_t>(tid + stride)];
                imag_cache[static_cast<std::size_t>(tid)] +=
                    imag_cache[static_cast<std::size_t>(tid + stride)];
            }
        }
        float sum_real = real_cache[0];
        float sum_imag = imag_cache[0];
        if (event_count > 0)
        {
            const float scale = 1.0f / static_cast<float>(event_count);
            sum_real *= scale;
            sum_imag *= scale;
        }
        const float strength = std::hypot(sum_real, sum_imag);
        const float phase = strength < kVectorStrengthPhaseFloor ? 0.0f : std::atan2(sum_imag, sum_real);
        return {strength, phase};
    }

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
            zero();
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

        int size() const
        {
            return size_;
        }

        void zero()
        {
            for (int index = 0; index < size_; ++index)
            {
                data_[index][0] = 0.0;
                data_[index][1] = 0.0;
            }
        }

    private:
        int size_ = 0;
        fftw_complex *data_ = nullptr;
    };

    struct PreparedWindow
    {
        RealSignal values;
        int nperseg = 0;
    };

    struct SegmentFftResult
    {
        std::vector<ComplexSignal> spectra;
        RealSignal times;
        std::size_t freq_count = 0;
    };

    PreparedWindow resolve_window(
        const cusignal::core::WindowSpec &window,
        int nperseg,
        std::size_t input_length,
        int default_nperseg)
    {
        PreparedWindow prepared;
        if (const auto *explicit_values = std::get_if<RealSignal>(&window))
        {
            if (explicit_values->empty())
            {
                throw std::invalid_argument("window array must not be empty");
            }
            if (input_length < explicit_values->size())
            {
                throw std::invalid_argument("window is longer than input signal");
            }
            if (nperseg <= 0)
            {
                nperseg = static_cast<int>(explicit_values->size());
            }
            else if (static_cast<std::size_t>(nperseg) != explicit_values->size())
            {
                throw std::invalid_argument("value specified for nperseg is different from length of window");
            }
            prepared.values = *explicit_values;
            prepared.nperseg = nperseg;
            return prepared;
        }

        if (nperseg <= 0)
        {
            nperseg = default_nperseg;
        }
        if (nperseg > static_cast<int>(input_length))
        {
            nperseg = static_cast<int>(input_length);
        }
        prepared.values = cusignal::cpu::windows::get_window(window, nperseg, true);
        prepared.nperseg = nperseg;
        return prepared;
    }

    ComplexSignal fft_complex(const ComplexSignal &input, int nfft)
    {
        FftwBuffer buffer(nfft);
        const std::size_t limit = std::min(input.size(), static_cast<std::size_t>(nfft));
        for (std::size_t index = 0; index < limit; ++index)
        {
            buffer.data()[static_cast<int>(index)][0] = input[index].real();
            buffer.data()[static_cast<int>(index)][1] = input[index].imag();
        }
        fftw_plan plan =
            fftw_plan_dft_1d(nfft, buffer.data(), buffer.data(), FFTW_FORWARD, FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("fftw_plan_dft_1d failed");
        }
        fftw_execute(plan);
        fftw_destroy_plan(plan);
        ComplexSignal output(static_cast<std::size_t>(nfft), Complex(0.0, 0.0));
        for (int index = 0; index < nfft; ++index)
        {
            output[static_cast<std::size_t>(index)] =
                Complex(buffer.data()[index][0], buffer.data()[index][1]);
        }
        return output;
    }

    ComplexSignal ifft_complex(const ComplexSignal &input, int nfft)
    {
        FftwBuffer buffer(nfft);
        const std::size_t limit = std::min(input.size(), static_cast<std::size_t>(nfft));
        for (std::size_t index = 0; index < limit; ++index)
        {
            buffer.data()[static_cast<int>(index)][0] = input[index].real();
            buffer.data()[static_cast<int>(index)][1] = input[index].imag();
        }
        fftw_plan plan =
            fftw_plan_dft_1d(nfft, buffer.data(), buffer.data(), FFTW_BACKWARD, FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("fftw_plan_dft_1d failed");
        }
        fftw_execute(plan);
        fftw_destroy_plan(plan);
        ComplexSignal output(static_cast<std::size_t>(nfft), Complex(0.0, 0.0));
        const float scale = 1.0 / static_cast<float>(nfft);
        for (int index = 0; index < nfft; ++index)
        {
            output[static_cast<std::size_t>(index)] =
                Complex(buffer.data()[index][0] * scale, buffer.data()[index][1] * scale);
        }
        return output;
    }

    ComplexSignal fft_real_segment(const RealSignal &segment, int nfft)
    {
        ComplexSignal complex_segment(segment.size(), Complex(0.0, 0.0));
        for (std::size_t index = 0; index < segment.size(); ++index)
        {
            complex_segment[index] = Complex(segment[index], 0.0);
        }
        return fft_complex(complex_segment, nfft);
    }

    ComplexSignal slice_spectrum(const ComplexSignal &fft_values, bool onesided)
    {
        if (!onesided)
        {
            return fft_values;
        }
        return ComplexSignal(
            fft_values.begin(),
            fft_values.begin() + static_cast<long long>(fft_values.size() / 2 + 1));
    }

    RealSignal truncate_line_if_needed(const RealSignal &line, int nfft, int &resolved_nfft)
    {
        if (nfft > 0 && static_cast<std::size_t>(nfft) < line.size())
        {
            resolved_nfft = nfft;
            return RealSignal(line.begin(), line.begin() + nfft);
        }
        resolved_nfft = nfft > 0 ? nfft : static_cast<int>(line.size());
        return line;
    }

    std::vector<RealSignal> split_segments(const RealSignal &line, int nperseg, int step)
    {
        if (line.size() < static_cast<std::size_t>(nperseg))
        {
            return {};
        }
        const std::size_t count =
            1 + (line.size() - static_cast<std::size_t>(nperseg)) / static_cast<std::size_t>(step);
        std::vector<RealSignal> segments;
        segments.reserve(count);
        for (std::size_t index = 0; index < count; ++index)
        {
            const std::size_t start = index * static_cast<std::size_t>(step);
            segments.emplace_back(
                line.begin() + static_cast<long long>(start),
                line.begin() + static_cast<long long>(start + static_cast<std::size_t>(nperseg)));
        }
        return segments;
    }

    SegmentFftResult compute_segment_ffts(
        RealSignal line,
        const RealSignal &window,
        const detail::SegmentConfig &config,
        const DetrendSpec &detrend,
        bool onesided,
        bool boundary_enabled,
        bool padded)
    {
        if (boundary_enabled)
        {
            line = detail::extend_line(line, config.nperseg / 2, "zeros");
        }
        if (padded)
        {
            detail::pad_line_to_segments(line, config.nperseg, config.step);
        }
        SegmentFftResult result;
        result.freq_count = detail::frequency_count(config.nfft, onesided);
        result.times = detail::segment_times(
            line.size(),
            config.nperseg,
            config.step,
            1.0,
            boundary_enabled);
        const std::vector<RealSignal> segments = split_segments(line, config.nperseg, config.step);
        result.times.resize(segments.size());
        for (std::size_t segment_index = 0; segment_index < segments.size(); ++segment_index)
        {
            RealSignal segment = detail::detrend_line(segments[segment_index], detrend);
            for (int sample = 0; sample < config.nperseg; ++sample)
            {
                segment[static_cast<std::size_t>(sample)] *= window[static_cast<std::size_t>(sample)];
            }
            result.spectra.push_back(slice_spectrum(fft_real_segment(segment, config.nfft), onesided));
        }
        return result;
    }

    SegmentFftResult compute_segment_ffts_with_times(
        RealSignal line,
        const RealSignal &window,
        const detail::SegmentConfig &config,
        const DetrendSpec &detrend,
        bool onesided,
        float fs,
        const std::string &boundary,
        bool padded)
    {
        if (boundary != "none")
        {
            line = detail::extend_line(line, config.nperseg / 2, boundary);
        }
        if (padded)
        {
            detail::pad_line_to_segments(line, config.nperseg, config.step);
        }
        SegmentFftResult result;
        result.freq_count = detail::frequency_count(config.nfft, onesided);
        result.times = detail::segment_times(
            line.size(),
            config.nperseg,
            config.step,
            fs,
            boundary != "none");
        const std::vector<RealSignal> segments = split_segments(line, config.nperseg, config.step);
        result.times.resize(segments.size());
        for (std::size_t segment_index = 0; segment_index < segments.size(); ++segment_index)
        {
            RealSignal segment = detail::detrend_line(segments[segment_index], detrend);
            for (int sample = 0; sample < config.nperseg; ++sample)
            {
                segment[static_cast<std::size_t>(sample)] *= window[static_cast<std::size_t>(sample)];
            }
            result.spectra.push_back(slice_spectrum(fft_real_segment(segment, config.nfft), onesided));
        }
        return result;
    }

    ComplexSignal apply_stft_scale(const ComplexSignal &values, float scale)
    {
        ComplexSignal scaled = values;
        for (Complex &value : scaled)
        {
            value *= scale;
        }
        return scaled;
    }

    RealSignal psd_from_fft(
        const ComplexSignal &values,
        float scale,
        bool onesided,
        int nfft)
    {
        RealSignal psd(values.size(), 0.0);
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            psd[index] = std::norm(values[index]) * scale;
        }
        if (onesided)
        {
            if (nfft % 2 == 0)
            {
                for (std::size_t index = 1; index + 1 < psd.size(); ++index)
                {
                    psd[index] *= 2.0;
                }
            }
            else
            {
                for (std::size_t index = 1; index < psd.size(); ++index)
                {
                    psd[index] *= 2.0;
                }
            }
        }
        return psd;
    }

    ComplexSignal cross_from_fft(
        const ComplexSignal &x,
        const ComplexSignal &y,
        float scale,
        bool onesided,
        int nfft)
    {
        ComplexSignal cross(x.size(), Complex(0.0f, 0.0f));
        for (std::size_t index = 0; index < x.size(); ++index)
        {
            cross[index] = std::conj(x[index]) * y[index] * scale;
        }
        if (onesided)
        {
            if (nfft % 2 == 0)
            {
                for (std::size_t index = 1; index + 1 < cross.size(); ++index)
                {
                    cross[index] *= 2.0;
                }
            }
            else
            {
                for (std::size_t index = 1; index < cross.size(); ++index)
                {
                    cross[index] *= 2.0;
                }
            }
        }
        return cross;
    }

    RealSignal mean_real_segments(const std::vector<RealSignal> &segments)
    {
        if (segments.empty())
        {
            return {};
        }
        RealSignal mean(segments.front().size(), 0.0);
        for (const RealSignal &segment : segments)
        {
            for (std::size_t index = 0; index < segment.size(); ++index)
            {
                mean[index] += segment[index];
            }
        }
        const float scale = 1.0f / static_cast<float>(segments.size());
        for (float &value : mean)
        {
            value *= scale;
        }
        return mean;
    }

    ComplexSignal mean_complex_segments(const std::vector<ComplexSignal> &segments)
    {
        if (segments.empty())
        {
            return {};
        }
        ComplexSignal mean(segments.front().size(), Complex(0.0, 0.0));
        for (const ComplexSignal &segment : segments)
        {
            for (std::size_t index = 0; index < segment.size(); ++index)
            {
                mean[index] += segment[index];
            }
        }
        const float scale = 1.0 / static_cast<float>(segments.size());
        for (Complex &value : mean)
        {
            value *= scale;
        }
        return mean;
    }

    RealSignal median_real_segments(const std::vector<RealSignal> &segments)
    {
        if (segments.empty())
        {
            return {};
        }
        RealSignal median(segments.front().size(), 0.0);
        std::vector<float> scratch(segments.size(), 0.0);
        const float bias = detail::median_bias(static_cast<int>(segments.size()));
        for (std::size_t index = 0; index < median.size(); ++index)
        {
            for (std::size_t seg = 0; seg < segments.size(); ++seg)
            {
                scratch[seg] = segments[seg][index];
            }
            const auto middle = scratch.begin() + static_cast<long long>(scratch.size() / 2);
            std::nth_element(scratch.begin(), middle, scratch.end());
            float value = *middle;
            if (scratch.size() % 2 == 0)
            {
                const auto max_lower = std::max_element(scratch.begin(), middle);
                value = 0.5 * (value + *max_lower);
            }
            median[index] = value / bias;
        }
        return median;
    }

    ComplexSignal median_complex_segments(const std::vector<ComplexSignal> &segments)
    {
        if (segments.empty())
        {
            return {};
        }
        ComplexSignal median(segments.front().size(), Complex(0.0, 0.0));
        std::vector<float> real_scratch(segments.size(), 0.0);
        std::vector<float> imag_scratch(segments.size(), 0.0);
        const float bias = detail::median_bias(static_cast<int>(segments.size()));
        for (std::size_t index = 0; index < median.size(); ++index)
        {
            for (std::size_t seg = 0; seg < segments.size(); ++seg)
            {
                real_scratch[seg] = segments[seg][index].real();
                imag_scratch[seg] = segments[seg][index].imag();
            }
            auto compute_median = [](std::vector<float> &scratch) {
                const auto middle = scratch.begin() + static_cast<long long>(scratch.size() / 2);
                std::nth_element(scratch.begin(), middle, scratch.end());
                float value = *middle;
                if (scratch.size() % 2 == 0)
                {
                    const auto max_lower = std::max_element(scratch.begin(), middle);
                    value = 0.5 * (value + *max_lower);
                }
                return value;
            };
            median[index] =
                Complex(compute_median(real_scratch) / bias, compute_median(imag_scratch) / bias);
        }
        return median;
    }

    Shape spectrogram_shape(const Shape &input_shape, int axis, std::size_t freq_count, std::size_t time_count)
    {
        Shape shape = cusignal::core::replace_axis_size(input_shape, axis, freq_count);
        shape.push_back(time_count);
        return shape;
    }

    template <typename SignalType>
    void ensure_same_length(
        const SignalType &lhs,
        const SignalType &rhs,
        const std::string &name)
    {
        if (lhs.size() != rhs.size())
        {
            throw std::invalid_argument(name + " inputs must have the same length");
        }
    }

    int resolve_istft_nperseg(std::size_t freq_bins, bool input_onesided, int nperseg)
    {
        if (nperseg > 0)
        {
            return nperseg;
        }
        if (input_onesided)
        {
            return 2 * (static_cast<int>(freq_bins) - 1);
        }
        return static_cast<int>(freq_bins);
    }

    int resolve_istft_nfft(std::size_t freq_bins, bool input_onesided, int nperseg, int nfft)
    {
        const int default_n = input_onesided
                                  ? 2 * (static_cast<int>(freq_bins) - 1)
                                  : static_cast<int>(freq_bins);
        if (nfft > 0)
        {
            if (nfft < nperseg)
            {
                throw std::invalid_argument("nfft must be greater than or equal to nperseg.");
            }
            return nfft;
        }
        if (input_onesided && nperseg == default_n + 1)
        {
            return nperseg;
        }
        return default_n;
    }

    ComplexSignal expand_onesided_spectrum(const ComplexSignal &onesided, int nfft)
    {
        ComplexSignal full(static_cast<std::size_t>(nfft), Complex(0.0, 0.0));
        const std::size_t freq_count = onesided.size();
        for (std::size_t index = 0; index < freq_count; ++index)
        {
            full[index] = onesided[index];
        }
        const std::size_t upper = nfft % 2 == 0 ? freq_count - 1 : freq_count;
        for (std::size_t index = 1; index < upper; ++index)
        {
            full[static_cast<std::size_t>(nfft) - index] = std::conj(onesided[index]);
        }
        return full;
    }
} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace spectral
        {
            core::RealSignal lombscargle(
                const core::RealSignal &x,
                const core::RealSignal &y,
                const core::RealSignal &freqs,
                bool precenter,
                bool normalize)
            {
                ensure_same_length(x, y, "lombscargle");
                if (freqs.empty())
                {
                    return {};
                }
                RealSignal centered = y;
                if (precenter && !centered.empty())
                {
                    const float mean =
                        std::accumulate(centered.begin(), centered.end(), 0.0) /
                        static_cast<float>(centered.size());
                    for (float &value : centered)
                    {
                        value -= mean;
                    }
                }
                const float y_dot = std::inner_product(
                    centered.begin(), centered.end(), centered.begin(), 0.0);
                RealSignal output(freqs.size(), 0.0);
                for (std::size_t freq_index = 0; freq_index < freqs.size(); ++freq_index)
                {
                    const float w = freqs[freq_index];
                    float xc = 0.0;
                    float xs = 0.0;
                    float cc = 0.0;
                    float ss = 0.0;
                    for (std::size_t sample = 0; sample < x.size(); ++sample)
                    {
                        const float angle = w * x[sample];
                        const float c = std::cos(angle);
                        const float s = std::sin(angle);
                        xc += centered[sample] * c;
                        xs += centered[sample] * s;
                        cc += c * c;
                        ss += s * s;
                    }
                    const float power =
                        0.5 * ((cc > 0.0 ? (xc * xc) / cc : 0.0) + (ss > 0.0 ? (xs * xs) / ss : 0.0));
                    output[freq_index] = normalize && y_dot > 0.0 ? (2.0 * power / y_dot) : power;
                }
                return output;
            }

            spectral_api::RealSpectrumResult periodogram(
                const core::RealArray &x,
                float fs,
                core::WindowSpec window,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis)
            {
                (void)detail::normalize_scaling(scaling);
                const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape, axis);
                if (input_plan.axis_size == 0)
                {
                    return {core::make_real_signal(0), core::make_real_array(core::replace_axis_size(x.shape, axis, 0))};
                }

                spectral_api::RealSpectrumResult result;
                bool initialized = false;
                detail::AxisPlan output_plan;

                for (std::size_t line_index = 0; line_index < input_plan.line_count; ++line_index)
                {
                    const RealSignal original_line = detail::extract_line(x, input_plan, line_index);
                    int resolved_nfft = 0;
                    RealSignal line = truncate_line_if_needed(original_line, nfft, resolved_nfft);
                    const PreparedWindow prepared =
                        resolve_window(window, resolved_nfft == static_cast<int>(line.size()) ? resolved_nfft : 0, line.size(), static_cast<int>(line.size()));
                    detail::SegmentConfig config;
                    config.nperseg = prepared.nperseg;
                    config.noverlap = 0;
                    config.nfft = resolved_nfft > 0 ? resolved_nfft : prepared.nperseg;
                    config.step = config.nperseg;
                    const SegmentFftResult fft_result = compute_segment_ffts(line, prepared.values, config, detrend, return_onesided, false, false);
                    const float scale =
                        scaling == "density" ? detail::density_scale(prepared.values, fs) : detail::spectrum_scale(prepared.values);
                    const RealSignal spectrum =
                        fft_result.spectra.empty()
                            ? RealSignal(detail::frequency_count(config.nfft, return_onesided), 0.0)
                            : psd_from_fft(fft_result.spectra.front(), scale, return_onesided, config.nfft);

                    if (!initialized)
                    {
                        result.frequencies = detail::frequency_axis(config.nfft, fs, return_onesided);
                        result.values = core::make_real_array(
                            core::replace_axis_size(x.shape, axis, result.frequencies.size()));
                        output_plan = detail::make_axis_plan(result.values.shape, axis);
                        initialized = true;
                    }
                    detail::store_line(result.values, output_plan, line_index, spectrum);
                }
                return result;
            }

            spectral_api::RealSpectrumResult welch(
                const core::RealArray &x,
                float fs,
                core::WindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis,
                const std::string &average)
            {
                (void)detail::normalize_scaling(scaling);
                const std::string avg = detail::normalize_average(average);
                const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape, axis);
                const PreparedWindow prepared = resolve_window(window, nperseg, input_plan.axis_size, 256);
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    input_plan.axis_size,
                    prepared.nperseg,
                    noverlap,
                    nfft,
                    prepared.nperseg,
                    prepared.nperseg / 2);

                spectral_api::RealSpectrumResult result;
                result.frequencies = detail::frequency_axis(config.nfft, fs, return_onesided);
                result.values = core::make_real_array(
                    core::replace_axis_size(x.shape, axis, result.frequencies.size()));
                const detail::AxisPlan output_plan = detail::make_axis_plan(result.values.shape, axis);
                const float scale =
                    scaling == "density" ? detail::density_scale(prepared.values, fs) : detail::spectrum_scale(prepared.values);

                for (std::size_t line_index = 0; line_index < input_plan.line_count; ++line_index)
                {
                    const RealSignal line = detail::extract_line(x, input_plan, line_index);
                    const SegmentFftResult fft_result =
                        compute_segment_ffts(line, prepared.values, config, detrend, return_onesided, false, false);
                    std::vector<RealSignal> spectra;
                    spectra.reserve(fft_result.spectra.size());
                    for (const ComplexSignal &segment_fft : fft_result.spectra)
                    {
                        spectra.push_back(psd_from_fft(segment_fft, scale, return_onesided, config.nfft));
                    }
                    const RealSignal averaged =
                        avg == "median" ? median_real_segments(spectra) : mean_real_segments(spectra);
                    detail::store_line(result.values, output_plan, line_index, averaged);
                }
                return result;
            }

            spectral_api::ComplexSpectrumResult csd(
                const core::RealArray &x,
                const core::RealArray &y,
                float fs,
                core::WindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis,
                const std::string &average)
            {
                (void)detail::normalize_scaling(scaling);
                const std::string avg = detail::normalize_average(average);
                if (x.shape != y.shape)
                {
                    throw std::invalid_argument("x and y must have the same shape");
                }
                const detail::AxisPlan x_plan = detail::make_axis_plan(x.shape, axis);
                const detail::AxisPlan y_plan = detail::make_axis_plan(y.shape, axis);
                const PreparedWindow prepared = resolve_window(window, nperseg, x_plan.axis_size, 256);
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    x_plan.axis_size,
                    prepared.nperseg,
                    noverlap,
                    nfft,
                    prepared.nperseg,
                    prepared.nperseg / 2);

                spectral_api::ComplexSpectrumResult result;
                result.frequencies = detail::frequency_axis(config.nfft, fs, return_onesided);
                result.values = core::make_complex_array(
                    core::replace_axis_size(x.shape, axis, result.frequencies.size()));
                const detail::AxisPlan output_plan = detail::make_axis_plan(result.values.shape, axis);
                const float scale =
                    scaling == "density" ? detail::density_scale(prepared.values, fs) : detail::spectrum_scale(prepared.values);

                for (std::size_t line_index = 0; line_index < x_plan.line_count; ++line_index)
                {
                    const RealSignal x_line = detail::extract_line(x, x_plan, line_index);
                    const RealSignal y_line = detail::extract_line(y, y_plan, line_index);
                    const SegmentFftResult x_fft =
                        compute_segment_ffts(x_line, prepared.values, config, detrend, return_onesided, false, false);
                    const SegmentFftResult y_fft =
                        compute_segment_ffts(y_line, prepared.values, config, detrend, return_onesided, false, false);

                    std::vector<ComplexSignal> spectra;
                    const std::size_t count = std::min(x_fft.spectra.size(), y_fft.spectra.size());
                    spectra.reserve(count);
                    for (std::size_t segment = 0; segment < count; ++segment)
                    {
                        spectra.push_back(cross_from_fft(
                            x_fft.spectra[segment],
                            y_fft.spectra[segment],
                            scale,
                            return_onesided,
                            config.nfft));
                    }
                    const ComplexSignal averaged =
                        avg == "median" ? median_complex_segments(spectra) : mean_complex_segments(spectra);
                    detail::store_complex_line(result.values, output_plan, line_index, averaged);
                }
                return result;
            }

            spectral_api::SpectrogramResult spectrogram(
                const core::RealArray &x,
                float fs,
                core::WindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis,
                const std::string &mode)
            {
                const std::string normalized_mode = detail::normalize_mode(mode);
                (void)detail::normalize_scaling(scaling);
                const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape, axis);
                const PreparedWindow prepared = resolve_window(window, nperseg, input_plan.axis_size, 256);
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    input_plan.axis_size,
                    prepared.nperseg,
                    noverlap,
                    nfft,
                    prepared.nperseg,
                    prepared.nperseg / 8);

                const bool stft_mode = normalized_mode != "psd";
                const float scale =
                    stft_mode
                        ? std::sqrt(scaling == "density" ? detail::density_scale(prepared.values, fs)
                                                         : detail::spectrum_scale(prepared.values))
                        : (scaling == "density" ? detail::density_scale(prepared.values, fs)
                                                : detail::spectrum_scale(prepared.values));

                spectral_api::SpectrogramResult result;
                result.frequencies = detail::frequency_axis(config.nfft, fs, return_onesided);
                std::size_t time_count = 0;
                detail::AxisPlan output_plan;
                bool initialized = false;
                const std::size_t normalized_axis = cusignal::core::normalize_axis(axis, x.shape.size());

                for (std::size_t line_index = 0; line_index < input_plan.line_count; ++line_index)
                {
                    const RealSignal line = detail::extract_line(x, input_plan, line_index);
                    const SegmentFftResult fft_result =
                        compute_segment_ffts_with_times(
                            line,
                            prepared.values,
                            config,
                            detrend,
                            return_onesided,
                            fs,
                            "none",
                            false);
                    if (!initialized)
                    {
                        result.times = fft_result.times;
                        time_count = result.times.size();
                        const Shape output_shape =
                            spectrogram_shape(x.shape, axis, result.frequencies.size(), time_count);
                        if (normalized_mode == "complex")
                        {
                            result.values = core::make_complex_array(output_shape);
                        }
                        else
                        {
                            result.values = core::make_real_array(output_shape);
                        }
                        output_plan = detail::make_axis_plan(output_shape, static_cast<int>(normalized_axis));
                        initialized = true;
                    }

                    for (std::size_t time_index = 0; time_index < fft_result.spectra.size(); ++time_index)
                    {
                        const std::size_t combined_index = line_index + input_plan.line_count * time_index;
                        if (normalized_mode == "psd")
                        {
                            auto &values = std::get<RealArray>(result.values);
                            detail::store_line(
                                values,
                                output_plan,
                                combined_index,
                                psd_from_fft(fft_result.spectra[time_index], scale, return_onesided, config.nfft));
                        }
                        else
                        {
                            ComplexSignal complex_values =
                                apply_stft_scale(fft_result.spectra[time_index], scale);
                            if (normalized_mode == "complex")
                            {
                                auto &values = std::get<ComplexArray>(result.values);
                                detail::store_complex_line(values, output_plan, combined_index, complex_values);
                            }
                            else
                            {
                                RealSignal real_values(complex_values.size(), 0.0);
                                if (normalized_mode == "magnitude")
                                {
                                    for (std::size_t index = 0; index < complex_values.size(); ++index)
                                    {
                                        real_values[index] = std::abs(complex_values[index]);
                                    }
                                }
                                else
                                {
                                    for (std::size_t index = 0; index < complex_values.size(); ++index)
                                    {
                                        real_values[index] = std::arg(complex_values[index]);
                                    }
                                    if (normalized_mode == "phase")
                                    {
                                        real_values = detail::unwrap_phase(std::move(real_values));
                                    }
                                }
                                auto &values = std::get<RealArray>(result.values);
                                detail::store_line(values, output_plan, combined_index, real_values);
                            }
                        }
                    }
                }
                if (!initialized)
                {
                    result.times = {};
                    result.values = core::make_real_array(Shape{result.frequencies.size(), 0});
                }
                return result;
            }

            spectral_api::StftResult stft(
                const core::RealArray &x,
                float fs,
                core::WindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &boundary,
                bool padded,
                int axis)
            {
                (void)detail::normalize_boundary(boundary);
                const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape, axis);
                const PreparedWindow prepared = resolve_window(window, nperseg, input_plan.axis_size, 256);
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    input_plan.axis_size,
                    prepared.nperseg,
                    noverlap,
                    nfft,
                    prepared.nperseg,
                    prepared.nperseg / 2);
                const float scale = std::sqrt(detail::spectrum_scale(prepared.values));

                spectral_api::StftResult result;
                result.frequencies = detail::frequency_axis(config.nfft, fs, return_onesided);
                std::size_t time_count = 0;
                detail::AxisPlan output_plan;
                bool initialized = false;
                const std::size_t normalized_axis = cusignal::core::normalize_axis(axis, x.shape.size());

                for (std::size_t line_index = 0; line_index < input_plan.line_count; ++line_index)
                {
                    const RealSignal line = detail::extract_line(x, input_plan, line_index);
                    const SegmentFftResult fft_result =
                        compute_segment_ffts_with_times(
                            line,
                            prepared.values,
                            config,
                            detrend,
                            return_onesided,
                            fs,
                            boundary,
                            padded);
                    if (!initialized)
                    {
                        result.times = fft_result.times;
                        time_count = result.times.size();
                        const Shape output_shape =
                            spectrogram_shape(x.shape, axis, result.frequencies.size(), time_count);
                        result.values = core::make_complex_array(output_shape);
                        output_plan = detail::make_axis_plan(output_shape, static_cast<int>(normalized_axis));
                        initialized = true;
                    }
                    for (std::size_t time_index = 0; time_index < fft_result.spectra.size(); ++time_index)
                    {
                        const std::size_t combined_index = line_index + input_plan.line_count * time_index;
                        detail::store_complex_line(
                            result.values,
                            output_plan,
                            combined_index,
                            apply_stft_scale(fft_result.spectra[time_index], scale));
                    }
                }
                if (!initialized)
                {
                    result.values = core::make_complex_array(Shape{result.frequencies.size(), 0});
                }
                return result;
            }

            spectral_api::IstftResult istft(
                const core::ComplexArray &zxx,
                float fs,
                core::WindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                bool input_onesided,
                bool boundary,
                int time_axis,
                int freq_axis)
            {
                const std::size_t rank = zxx.rank();
                const std::size_t normalized_time = core::normalize_axis(time_axis, rank);
                const std::size_t normalized_freq = core::normalize_axis(freq_axis, rank);
                if (rank < 2 || normalized_time != rank - 1 || normalized_freq != rank - 2)
                {
                    throw std::invalid_argument("istft currently requires freq_axis=-2 and time_axis=-1");
                }

                const std::size_t freq_bins = zxx.shape[normalized_freq];
                const std::size_t segment_count = zxx.shape[normalized_time];
                const int resolved_nperseg = resolve_istft_nperseg(freq_bins, input_onesided, nperseg);
                const int resolved_nfft = resolve_istft_nfft(freq_bins, input_onesided, resolved_nperseg, nfft);
                const int resolved_noverlap = noverlap < 0 ? resolved_nperseg / 2 : noverlap;
                if (resolved_noverlap >= resolved_nperseg)
                {
                    throw std::invalid_argument("noverlap must be less than nperseg.");
                }
                const int step = resolved_nperseg - resolved_noverlap;
                PreparedWindow prepared = resolve_window(window, resolved_nperseg, resolved_nperseg, resolved_nperseg);

                const Shape outer_shape(zxx.shape.begin(), zxx.shape.end() - 2);
                const std::size_t outer_count = outer_shape.empty() ? 1 : core::shape_product(outer_shape);
                const std::size_t spectrum_size = freq_bins * segment_count;
                const std::size_t output_length =
                    static_cast<std::size_t>(resolved_nperseg) + (segment_count - 1) * static_cast<std::size_t>(step);
                const std::size_t final_length =
                    boundary ? output_length - static_cast<std::size_t>(resolved_nperseg) : output_length;
                Shape output_shape = outer_shape;
                output_shape.push_back(final_length);
                spectral_api::IstftResult result;
                result.signal = core::make_real_array(output_shape);
                result.times = core::make_real_signal(final_length);

                for (std::size_t index = 0; index < final_length; ++index)
                {
                    result.times[index] = static_cast<float>(index) / fs;
                }

                for (std::size_t outer = 0; outer < outer_count; ++outer)
                {
                    const std::size_t outer_base = outer * spectrum_size;
                    RealSignal accum(output_length, 0.0);
                    RealSignal norm(output_length, 0.0);
                    for (std::size_t segment = 0; segment < segment_count; ++segment)
                    {
                        ComplexSignal spectrum(freq_bins, Complex(0.0, 0.0));
                        for (std::size_t freq = 0; freq < freq_bins; ++freq)
                        {
                            spectrum[freq] = zxx.values[outer_base + freq * segment_count + segment];
                        }
                        ComplexSignal full = input_onesided ? expand_onesided_spectrum(spectrum, resolved_nfft) : spectrum;
                        ComplexSignal segment_time = ifft_complex(full, resolved_nfft);
                        const float window_sum =
                            std::accumulate(prepared.values.begin(), prepared.values.end(), 0.0);
                        const std::size_t start = segment * static_cast<std::size_t>(step);
                        for (int sample = 0; sample < resolved_nperseg; ++sample)
                        {
                            const float value =
                                segment_time[static_cast<std::size_t>(sample)].real() *
                                window_sum * prepared.values[static_cast<std::size_t>(sample)];
                            accum[start + static_cast<std::size_t>(sample)] += value;
                            norm[start + static_cast<std::size_t>(sample)] +=
                                prepared.values[static_cast<std::size_t>(sample)] *
                                prepared.values[static_cast<std::size_t>(sample)];
                        }
                    }

                    const std::size_t trim = boundary ? static_cast<std::size_t>(resolved_nperseg / 2) : 0;
                    for (std::size_t index = 0; index < final_length; ++index)
                    {
                        const std::size_t src = index + trim;
                        const float denom = norm[src] > 1e-10 ? norm[src] : 1.0;
                        result.signal.values[outer * final_length + index] = accum[src] / denom;
                    }
                }
                return result;
            }

            spectral_api::RealSpectrumResult coherence(
                const core::RealArray &x,
                const core::RealArray &y,
                float fs,
                core::WindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                int axis)
            {
                if (x.shape != y.shape)
                {
                    throw std::invalid_argument("x and y must have the same shape");
                }
                spectral_api::RealSpectrumResult pxx =
                    welch(x, fs, window, nperseg, noverlap, nfft, detrend, true, "density", axis, "mean");
                spectral_api::RealSpectrumResult pyy =
                    welch(y, fs, window, nperseg, noverlap, nfft, detrend, true, "density", axis, "mean");
                spectral_api::ComplexSpectrumResult pxy =
                    csd(x, y, fs, window, nperseg, noverlap, nfft, detrend, true, "density", axis, "mean");
                spectral_api::RealSpectrumResult result;
                result.frequencies = pxx.frequencies;
                result.values = core::make_real_array(pxx.values.shape);
                for (std::size_t index = 0; index < result.values.size(); ++index)
                {
                    const float denom = pxx.values.values[index] * pyy.values.values[index];
                    result.values.values[index] =
                        denom > 0.0 ? std::norm(pxy.values.values[index]) / denom : 0.0;
                }
                return result;
            }

            spectral_api::VectorStrengthResult vectorstrength(
                const core::RealSignal &events,
                float period)
            {
                if (!(period > 0.0))
                {
                    throw std::invalid_argument("period must be > 0");
                }
                spectral_api::VectorStrengthResult result;
                result.strength = core::make_real_signal(1);
                result.phase = core::make_real_signal(1);
                if (events.size() >= 4096)
                {
                    const auto pairwise = vectorstrength_pairwise_like_cuda(events, period);
                    result.strength[0] = pairwise.first;
                    result.phase[0] = pairwise.second;
                    return result;
                }
                float sum_real = 0.0f;
                float sum_imag = 0.0f;
                for (float event : events)
                {
                    const float angle = vectorstrength_angle(event, period);
                    float s = 0.0f;
                    float c = 0.0f;
                    vectorstrength_sincos_poly(angle, s, c);
                    sum_real += c;
                    sum_imag += s;
                }
                if (!events.empty())
                {
                    const float scale = 1.0f / static_cast<float>(events.size());
                    sum_real *= scale;
                    sum_imag *= scale;
                }
                result.strength[0] = std::hypot(sum_real, sum_imag);
                result.phase[0] = result.strength[0] < kVectorStrengthPhaseFloor
                                      ? 0.0f
                                      : std::atan2(sum_imag, sum_real);
                return result;
            }

            spectral_api::VectorStrengthResult vectorstrength(
                const core::RealSignal &events,
                const core::RealSignal &period)
            {
                if (period.empty())
                {
                    throw std::invalid_argument("period must not be empty");
                }
                spectral_api::VectorStrengthResult result;
                result.strength = core::make_real_signal(period.size());
                result.phase = core::make_real_signal(period.size());
                for (std::size_t index = 0; index < period.size(); ++index)
                {
                    if (!(period[index] > 0.0))
                    {
                        throw std::invalid_argument("period entries must be > 0");
                    }
                    const spectral_api::VectorStrengthResult single = vectorstrength(events, period[index]);
                    result.strength[index] = single.strength[0];
                    result.phase[index] = single.phase[0];
                }
                return result;
            }
        } // namespace spectral
    } // namespace cpu
} // namespace cusignal
