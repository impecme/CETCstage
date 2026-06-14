#include "cusignal/filter_design/filter_design.hpp"

#include <fftw3.h>

#include <algorithm>
#include <cmath>
#include <complex>
#include <numeric>
#include <stdexcept>
#include <vector>

#include "cusignal/windows/windows.hpp"

#include "../common/filter_design_detail.hpp"

namespace
{
    namespace detail = cusignal::filter_design_detail;

    template <typename T>
    float sort_magnitude(const T &value)
    {
        return std::abs(value);
    }

    template <typename T>
    bool magnitude_less_with_tolerance(const T &lhs, const T &rhs)
    {
        const float lhs_mag = sort_magnitude(lhs);
        const float rhs_mag = sort_magnitude(rhs);
        const float scale = std::max({1.0f, lhs_mag, rhs_mag});
        const float tolerance = 1e-12f * scale;
        if (std::fabs(lhs_mag - rhs_mag) <= tolerance)
        {
            return false;
        }
        return lhs_mag < rhs_mag;
    }

    cusignal::core::RealSignal make_window(
        cusignal::core::WindowSpec window,
        int numtaps)
    {
        detail::validate_window_length(window, numtaps);
        return cusignal::cpu::windows::get_window(window, numtaps, false);
    }

    std::vector<std::complex<float>> build_irfft_spectrum(
        const std::vector<std::complex<float>> &half_spectrum)
    {
        const std::size_t size = half_spectrum.size() < 2 ? 1 : 2 * (half_spectrum.size() - 1);
        std::vector<std::complex<float>> full_spectrum(size, std::complex<float>(0.0, 0.0));
        for (std::size_t index = 0; index < half_spectrum.size(); ++index)
        {
            full_spectrum[index] = half_spectrum[index];
        }
        for (std::size_t index = 1; index + 1 < half_spectrum.size(); ++index)
        {
            full_spectrum[size - index] = std::conj(half_spectrum[index]);
        }
        return full_spectrum;
    }

    cusignal::core::RealSignal irfft_real(
        const std::vector<std::complex<float>> &half_spectrum,
        int numtaps)
    {
        const std::vector<std::complex<float>> full_spectrum = build_irfft_spectrum(half_spectrum);
        std::vector<fftw_complex> input(full_spectrum.size());
        std::vector<fftw_complex> output(full_spectrum.size());
        for (std::size_t index = 0; index < full_spectrum.size(); ++index)
        {
            input[index][0] = full_spectrum[index].real();
            input[index][1] = full_spectrum[index].imag();
        }

        fftw_plan plan = fftw_plan_dft_1d(
            static_cast<int>(full_spectrum.size()),
            input.data(),
            output.data(),
            FFTW_BACKWARD,
            FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("failed to create FFTW plan for firwin2");
        }
        fftw_execute(plan);
        fftw_destroy_plan(plan);

        cusignal::core::RealSignal taps(static_cast<std::size_t>(numtaps), 0.0);
        const float scale = 1.0 / static_cast<float>(full_spectrum.size());
        for (int index = 0; index < numtaps; ++index)
        {
            taps[static_cast<std::size_t>(index)] = output[static_cast<std::size_t>(index)][0] * scale;
        }
        return taps;
    }
} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace filter_design
        {

            float kaiser_beta(float attenuation)
            {
                if (attenuation > 50.0)
                {
                    return 0.1102 * (attenuation - 8.7);
                }
                if (attenuation >= 21.0)
                {
                    const float shifted = attenuation - 21.0;
                    return 0.5842 * std::pow(shifted, 0.4) + 0.07886 * shifted;
                }
                return 0.0;
            }

            float kaiser_atten(int numtaps, float width)
            {
                detail::ensure_numtaps(numtaps);
                detail::ensure_positive(width, "width");
                return 2.285 * (static_cast<float>(numtaps) - 1.0) * detail::kPi * width + 7.95;
            }

            filter_design_api::ComplexSortResult cmplx_sort(const core::RealSignal &p)
            {
                std::vector<int> indices(p.size(), 0);
                std::iota(indices.begin(), indices.end(), 0);
                std::stable_sort(
                    indices.begin(),
                    indices.end(),
                    [&p](int lhs, int rhs)
                    {
                        return magnitude_less_with_tolerance(
                            p[static_cast<std::size_t>(lhs)],
                            p[static_cast<std::size_t>(rhs)]);
                    });

                core::RealSignal sorted(p.size(), 0.0);
                for (std::size_t index = 0; index < indices.size(); ++index)
                {
                    sorted[index] = p[static_cast<std::size_t>(indices[index])];
                }

                filter_design_api::ComplexSortResult result;
                result.values = sorted;
                result.indices = indices;
                return result;
            }

            filter_design_api::ComplexSortResult cmplx_sort(const core::ComplexSignal &p)
            {
                std::vector<int> indices(p.size(), 0);
                std::iota(indices.begin(), indices.end(), 0);
                std::stable_sort(
                    indices.begin(),
                    indices.end(),
                    [&p](int lhs, int rhs)
                    {
                        return magnitude_less_with_tolerance(
                            p[static_cast<std::size_t>(lhs)],
                            p[static_cast<std::size_t>(rhs)]);
                    });

                core::ComplexSignal sorted(p.size(), core::Complex(0.0, 0.0));
                for (std::size_t index = 0; index < indices.size(); ++index)
                {
                    sorted[index] = p[static_cast<std::size_t>(indices[index])];
                }

                filter_design_api::ComplexSortResult result;
                result.values = sorted;
                result.indices = indices;
                return result;
            }

            core::RealSignal firwin(
                int numtaps,
                float cutoff,
                float width,
                core::WindowSpec window,
                core::PassZeroSpec pass_zero,
                bool scale,
                float nyq,
                float fs)
            {
                return firwin(
                    numtaps,
                    core::RealSignal{cutoff},
                    width,
                    std::move(window),
                    std::move(pass_zero),
                    scale,
                    nyq,
                    fs);
            }

            core::RealSignal firwin(
                int numtaps,
                const core::RealSignal &cutoff,
                float width,
                core::WindowSpec window,
                core::PassZeroSpec pass_zero,
                bool scale,
                float nyq,
                float fs)
            {
                detail::ensure_numtaps(numtaps);
                const float resolved_fs = detail::resolved_fs(nyq, fs);
                detail::ensure_positive(resolved_fs, "fs");
                const float resolved_nyq = 0.5 * resolved_fs;
                const std::vector<float> normalized_cutoff =
                    detail::normalize_cutoff(cutoff, resolved_nyq);
                const bool include_zero =
                    detail::normalize_pass_zero(pass_zero, normalized_cutoff.size());
                detail::validate_firwin_even_nyquist(numtaps, normalized_cutoff, include_zero);

                if (width > 0.0)
                {
                    const float attenuation = kaiser_atten(numtaps, width / resolved_nyq);
                    window = kaiser_beta(attenuation);
                }

                core::RealSignal taps =
                    detail::design_firwin_taps(
                        numtaps,
                        detail::build_bands(normalized_cutoff, include_zero));
                const core::RealSignal win = make_window(window, numtaps);
                for (std::size_t index = 0; index < taps.size(); ++index)
                {
                    taps[index] *= win[index];
                }

                if (scale)
                {
                    const float scale_frequency =
                        detail::scale_frequency_for_bands(
                            detail::build_bands(normalized_cutoff, include_zero));
                    const float response = detail::scale_response(taps, scale_frequency);
                    for (float &value : taps)
                    {
                        value /= response;
                    }
                }

                return taps;
            }

            core::RealSignal firwin2(
                int numtaps,
                const core::RealSignal &freq,
                const core::RealSignal &gain,
                int nfreqs,
                core::WindowSpec window,
                float nyq,
                bool antisymmetric,
                float fs)
            {
                detail::ensure_numtaps(numtaps);
                const float resolved_fs = detail::resolved_fs(nyq, fs);
                detail::ensure_positive(resolved_fs, "fs");
                const detail::Firwin2Type type =
                    detail::determine_firwin2_type(numtaps, antisymmetric);
                detail::prepare_freq_grid(freq, gain, resolved_fs);
                detail::validate_firwin2_gain_constraints(type, gain);

                const int resolved_nfreqs = nfreqs == 0 ? detail::default_nfreqs(numtaps) : nfreqs;
                if (resolved_nfreqs <= numtaps)
                {
                    throw std::invalid_argument("numtaps must be less than nfreqs");
                }

                const std::vector<float> adjusted_freq = detail::tweak_repeated_freq(freq, resolved_fs);
                const std::vector<float> mesh = detail::firwin2_mesh(resolved_nfreqs, resolved_fs);
                const std::vector<float> interpolated_gain =
                    detail::interpolate_linear(mesh, adjusted_freq, gain);
                const std::vector<std::complex<float>> half_spectrum =
                    detail::firwin2_shifted_response(
                        numtaps,
                        mesh,
                        interpolated_gain,
                        resolved_fs,
                        type);

                core::RealSignal taps = irfft_real(half_spectrum, numtaps);
                const core::RealSignal win = make_window(window, numtaps);
                for (std::size_t index = 0; index < taps.size(); ++index)
                {
                    taps[index] *= win[index];
                }
                if (type == detail::Firwin2Type::TypeIII)
                {
                    taps[taps.size() / 2] = 0.0;
                }
                return taps;
            }

        } // namespace filter_design
    } // namespace cpu
} // namespace cusignal
