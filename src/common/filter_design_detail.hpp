#pragma once

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>
#include <functional>
#include <limits>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace filter_design_detail
    {
        constexpr float kPi = 3.14159265358979323846;

        enum class Firwin2Type
        {
            TypeI = 1,
            TypeII = 2,
            TypeIII = 3,
            TypeIV = 4
        };

        inline void ensure_numtaps(int numtaps)
        {
            if (numtaps <= 0)
            {
                throw std::invalid_argument("numtaps must be positive");
            }
        }

        inline float resolved_fs(float nyq, float fs)
        {
            return nyq > 0.0 ? 2.0 * nyq : fs;
        }

        inline void ensure_positive(float value, const std::string &name)
        {
            if (!(value > 0.0))
            {
                throw std::invalid_argument(name + " must be > 0");
            }
        }

        inline std::vector<float> normalize_cutoff(
            const core::RealSignal &cutoff,
            float nyq)
        {
            if (cutoff.empty())
            {
                throw std::invalid_argument("At least one cutoff frequency must be given.");
            }

            std::vector<float> normalized(cutoff.size(), 0.0);
            for (std::size_t index = 0; index < cutoff.size(); ++index)
            {
                normalized[index] = cutoff[index] / nyq;
            }

            const auto minimum = *std::min_element(normalized.begin(), normalized.end());
            const auto maximum = *std::max_element(normalized.begin(), normalized.end());
            if (minimum <= 0.0 || maximum >= 1.0)
            {
                throw std::invalid_argument(
                    "Invalid cutoff frequency: frequencies must be greater than 0 and less than fs/2.");
            }

            for (std::size_t index = 1; index < normalized.size(); ++index)
            {
                if (normalized[index] <= normalized[index - 1])
                {
                    throw std::invalid_argument(
                        "Invalid cutoff frequencies: the frequencies must be strictly increasing.");
                }
            }
            return normalized;
        }

        inline bool normalize_pass_zero(
            const core::PassZeroSpec &pass_zero,
            std::size_t cutoff_size)
        {
            if (const auto *flag = std::get_if<bool>(&pass_zero))
            {
                return *flag;
            }

            const std::string mode = std::get<std::string>(pass_zero);
            if (mode == "bandstop" || mode == "lowpass")
            {
                if (mode == "lowpass" && cutoff_size != 1)
                {
                    throw std::invalid_argument(
                        "cutoff must have one element if pass_zero==\"lowpass\"");
                }
                if (mode == "bandstop" && cutoff_size <= 1)
                {
                    throw std::invalid_argument(
                        "cutoff must have at least two elements if pass_zero==\"bandstop\"");
                }
                return true;
            }
            if (mode == "bandpass" || mode == "highpass")
            {
                if (mode == "highpass" && cutoff_size != 1)
                {
                    throw std::invalid_argument(
                        "cutoff must have one element if pass_zero==\"highpass\"");
                }
                if (mode == "bandpass" && cutoff_size <= 1)
                {
                    throw std::invalid_argument(
                        "cutoff must have at least two elements if pass_zero==\"bandpass\"");
                }
                return false;
            }
            throw std::invalid_argument(
                "pass_zero must be one of True, False, 'bandpass', 'lowpass', 'highpass', 'bandstop'");
        }

        inline std::vector<std::pair<float, float>> build_bands(
            const std::vector<float> &normalized_cutoff,
            bool pass_zero)
        {
            const bool pass_nyquist = (normalized_cutoff.size() % 2 == 0) == pass_zero;
            std::vector<float> edges;
            if (pass_zero)
            {
                edges.push_back(0.0);
            }
            edges.insert(edges.end(), normalized_cutoff.begin(), normalized_cutoff.end());
            if (pass_nyquist)
            {
                edges.push_back(1.0);
            }

            std::vector<std::pair<float, float>> bands;
            bands.reserve(edges.size() / 2);
            for (std::size_t index = 0; index + 1 < edges.size(); index += 2)
            {
                bands.emplace_back(edges[index], edges[index + 1]);
            }
            return bands;
        }

        inline void validate_firwin_even_nyquist(
            int numtaps,
            const std::vector<float> &normalized_cutoff,
            bool pass_zero)
        {
            const bool pass_nyquist = (normalized_cutoff.size() % 2 == 0) == pass_zero;
            if (pass_nyquist && numtaps % 2 == 0)
            {
                throw std::invalid_argument(
                    "A filter with an even number of coefficients must have zero response at the Nyquist frequency.");
            }
        }

        inline core::WindowSpec to_host_window_spec(const core::ZxGpuWindowSpec &window)
        {
            if (const auto *value = std::get_if<std::string>(&window))
            {
                return *value;
            }
            if (const auto *value = std::get_if<float>(&window))
            {
                return *value;
            }
            if (const auto *value = std::get_if<core::NamedFloatParameter>(&window))
            {
                return *value;
            }
            if (const auto *value = std::get_if<core::NamedFloatPairParameter>(&window))
            {
                return *value;
            }
            if (const auto *value = std::get_if<core::NamedTaylorParameter>(&window))
            {
                return *value;
            }
            if (const auto *value = std::get_if<core::RealSignal>(&window))
            {
                return *value;
            }
            return std::get<core::ZxGpuRealSignal>(window).get();
        }

        inline void validate_window_length(const core::WindowSpec &window, int numtaps)
        {
            if (const auto *values = std::get_if<core::RealSignal>(&window))
            {
                if (values->size() != static_cast<std::size_t>(numtaps))
                {
                    throw std::invalid_argument("window array must have length numtaps");
                }
            }
        }

        inline void validate_window_length(const core::ZxGpuWindowSpec &window, int numtaps)
        {
            if (const auto *values = std::get_if<core::RealSignal>(&window))
            {
                if (values->size() != static_cast<std::size_t>(numtaps))
                {
                    throw std::invalid_argument("window array must have length numtaps");
                }
                return;
            }
            if (const auto *values = std::get_if<core::ZxGpuRealSignal>(&window))
            {
                if (values->size() != static_cast<std::size_t>(numtaps))
                {
                    throw std::invalid_argument("window array must have length numtaps");
                }
            }
        }

        inline float sinc(float value)
        {
            if (std::abs(value) < 1e-14)
            {
                return 1.0;
            }
            return std::sin(kPi * value) / (kPi * value);
        }

        inline std::vector<float> design_firwin_taps(
            int numtaps,
            const std::vector<std::pair<float, float>> &bands)
        {
            const float alpha = 0.5 * static_cast<float>(numtaps - 1);
            std::vector<float> taps(static_cast<std::size_t>(numtaps), 0.0);
            for (int index = 0; index < numtaps; ++index)
            {
                const float m = static_cast<float>(index) - alpha;
                float value = 0.0;
                for (const auto &[left, right] : bands)
                {
                    value += right * sinc(right * m);
                    value -= left * sinc(left * m);
                }
                taps[static_cast<std::size_t>(index)] = value;
            }
            return taps;
        }

        inline float scale_frequency_for_bands(
            const std::vector<std::pair<float, float>> &bands)
        {
            const float left = bands.front().first;
            const float right = bands.front().second;
            if (left == 0.0)
            {
                return 0.0;
            }
            if (right == 1.0)
            {
                return 1.0;
            }
            return 0.5 * (left + right);
        }

        inline float scale_response(
            const std::vector<float> &taps,
            float normalized_frequency)
        {
            const float alpha = 0.5 * static_cast<float>(taps.size() - 1);
            float sum = 0.0;
            for (std::size_t index = 0; index < taps.size(); ++index)
            {
                const float m = static_cast<float>(index) - alpha;
                sum += taps[index] * std::cos(kPi * m * normalized_frequency);
            }
            return sum;
        }

        inline Firwin2Type determine_firwin2_type(int numtaps, bool antisymmetric)
        {
            ensure_numtaps(numtaps);
            if (antisymmetric)
            {
                return (numtaps % 2 == 0) ? Firwin2Type::TypeIV : Firwin2Type::TypeIII;
            }
            return (numtaps % 2 == 0) ? Firwin2Type::TypeII : Firwin2Type::TypeI;
        }

        inline int default_nfreqs(int numtaps)
        {
            int value = 1;
            while (value < numtaps)
            {
                value <<= 1;
            }
            return value + 1;
        }

        inline std::vector<float> prepare_freq_grid(
            const core::RealSignal &freq,
            const core::RealSignal &gain,
            float fs)
        {
            (void)gain;
            if (freq.size() != gain.size())
            {
                throw std::invalid_argument("freq and gain must be of same length.");
            }
            if (freq.empty())
            {
                throw std::invalid_argument("freq must not be empty");
            }
            const float nyq = 0.5 * fs;
            if (freq.front() != 0.0 || freq.back() != nyq)
            {
                throw std::invalid_argument("freq must start with 0 and end with fs/2.");
            }
            std::vector<float> deltas(freq.size() - 1, 0.0);
            for (std::size_t index = 1; index < freq.size(); ++index)
            {
                deltas[index - 1] = freq[index] - freq[index - 1];
                if (deltas[index - 1] < 0.0)
                {
                    throw std::invalid_argument("The values in freq must be nondecreasing.");
                }
            }
            if (freq.size() > 2)
            {
                for (std::size_t index = 0; index + 1 < deltas.size(); ++index)
                {
                    if (deltas[index] + deltas[index + 1] == 0.0)
                    {
                        throw std::invalid_argument(
                            "A value in freq must not occur more than twice.");
                    }
                }
            }
            if (freq.size() > 1 && freq[1] == 0.0)
            {
                throw std::invalid_argument("Value 0 must not be repeated in freq");
            }
            if (freq.size() > 1 && freq[freq.size() - 2] == nyq)
            {
                throw std::invalid_argument("Value fs/2 must not be repeated in freq");
            }
            return deltas;
        }

        inline void validate_firwin2_gain_constraints(
            Firwin2Type type,
            const core::RealSignal &gain)
        {
            if (gain.empty())
            {
                throw std::invalid_argument("gain must not be empty");
            }
            switch (type)
            {
            case Firwin2Type::TypeII:
                if (gain.back() != 0.0)
                {
                    throw std::invalid_argument(
                        "A Type II filter must have zero gain at the Nyquist frequency.");
                }
                break;
            case Firwin2Type::TypeIII:
                if (gain.front() != 0.0 || gain.back() != 0.0)
                {
                    throw std::invalid_argument(
                        "A Type III filter must have zero gain at zero and Nyquist frequencies.");
                }
                break;
            case Firwin2Type::TypeIV:
                if (gain.front() != 0.0)
                {
                    throw std::invalid_argument(
                        "A Type IV filter must have zero gain at zero frequency.");
                }
                break;
            default:
                break;
            }
        }

        inline std::vector<float> tweak_repeated_freq(
            const core::RealSignal &freq,
            float fs)
        {
            std::vector<float> adjusted(freq.begin(), freq.end());
            const float nyq = 0.5 * fs;
            const float eps = std::numeric_limits<float>::epsilon() * nyq;
            for (std::size_t index = 0; index + 1 < adjusted.size(); ++index)
            {
                if (adjusted[index] == adjusted[index + 1])
                {
                    adjusted[index] -= eps;
                    adjusted[index + 1] += eps;
                }
            }
            for (std::size_t index = 1; index < adjusted.size(); ++index)
            {
                if (adjusted[index] <= adjusted[index - 1])
                {
                    throw std::invalid_argument(
                        "freq cannot contain numbers that are too close to a repeated value");
                }
            }
            return adjusted;
        }

        inline std::vector<float> interpolate_linear(
            const std::vector<float> &x,
            const std::vector<float> &xp,
            const core::RealSignal &fp)
        {
            std::vector<float> values(x.size(), 0.0);
            std::size_t segment = 0;
            for (std::size_t index = 0; index < x.size(); ++index)
            {
                const float query = x[index];
                while (segment + 1 < xp.size() && xp[segment + 1] < query)
                {
                    ++segment;
                }

                if (query <= xp.front())
                {
                    values[index] = fp.front();
                    continue;
                }
                if (query >= xp.back())
                {
                    values[index] = fp.back();
                    continue;
                }

                const float left = xp[segment];
                const float right = xp[segment + 1];
                const float t = (query - left) / (right - left);
                values[index] = (1.0 - t) * fp[segment] + t * fp[segment + 1];
            }
            return values;
        }

        inline std::vector<float> firwin2_mesh(int nfreqs, float fs)
        {
            const float nyq = 0.5 * fs;
            std::vector<float> mesh(static_cast<std::size_t>(nfreqs), 0.0);
            if (nfreqs <= 1)
            {
                return mesh;
            }
            for (int index = 0; index < nfreqs; ++index)
            {
                mesh[static_cast<std::size_t>(index)] =
                    nyq * static_cast<float>(index) / static_cast<float>(nfreqs - 1);
            }
            return mesh;
        }

        inline std::vector<std::complex<float>> firwin2_shifted_response(
            int numtaps,
            const std::vector<float> &mesh,
            const std::vector<float> &gain,
            float fs,
            Firwin2Type type)
        {
            const float nyq = 0.5 * fs;
            std::vector<std::complex<float>> spectrum(mesh.size());
            const std::complex<float> j(0.0, 1.0);
            for (std::size_t index = 0; index < mesh.size(); ++index)
            {
                const float angle =
                    -0.5 * static_cast<float>(numtaps - 1) * kPi * mesh[index] / nyq;
                std::complex<float> shift = std::exp(j * angle);
                if (type == Firwin2Type::TypeIII || type == Firwin2Type::TypeIV)
                {
                    shift *= j;
                }
                spectrum[index] = gain[index] * shift;
            }
            return spectrum;
        }

        inline core::RealSignal resolve_host_window(
            const core::WindowSpec &window,
            int numtaps,
            const std::function<core::RealSignal(core::WindowSpec, int)> &window_loader)
        {
            validate_window_length(window, numtaps);
            return window_loader(window, numtaps);
        }

    } // namespace filter_design_detail
} // namespace cusignal
