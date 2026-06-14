#include "cusignal/windows/windows.hpp"

#include <fftw3.h>

#include <algorithm>
#include <stdexcept>
#include <string>
#include <vector>

#include "../common/windows_detail.hpp"

namespace
{
    using cusignal::core::NamedFloatPairParameter;
    using cusignal::core::NamedFloatParameter;
    using cusignal::core::NamedTaylorParameter;
    using cusignal::core::RealSignal;
    namespace detail = cusignal::windows_detail;

    bool needs_parameter(const std::string &canonical_name)
    {
        return canonical_name == "chebwin" || canonical_name == "gaussian" ||
               canonical_name == "general_gaussian" || canonical_name == "general_hamming" ||
               canonical_name == "kaiser" || canonical_name == "taylor" ||
               canonical_name == "tukey" || canonical_name == "exponential";
    }

    RealSignal fftw_forward_real(const cusignal::core::ComplexSignal &input)
    {
        std::vector<fftw_complex> fft_input(input.size());
        std::vector<fftw_complex> fft_output(input.size());
        for (std::size_t index = 0; index < input.size(); ++index)
        {
            fft_input[index][0] = input[index].real();
            fft_input[index][1] = input[index].imag();
        }

        fftw_plan plan = fftw_plan_dft_1d(
            static_cast<int>(input.size()),
            fft_input.data(),
            fft_output.data(),
            FFTW_FORWARD,
            FFTW_ESTIMATE);
        if (plan == nullptr)
        {
            throw std::runtime_error("failed to create FFTW plan for chebwin");
        }

        fftw_execute(plan);
        fftw_destroy_plan(plan);

        RealSignal output(input.size(), 0.0);
        for (std::size_t index = 0; index < output.size(); ++index)
        {
            output[index] = fft_output[index][0];
        }
        return output;
    }
} // namespace

namespace cusignal
{
    namespace cpu
    {
        namespace windows
        {

            core::RealSignal get_window(core::WindowSpec window, int nx, bool fftbins)
            {
                detail::validate_size(nx);
                const bool sym = !fftbins;

                if (std::holds_alternative<core::RealSignal>(window))
                {
                    const core::RealSignal &values = std::get<core::RealSignal>(window);
                    if (values.size() != static_cast<std::size_t>(nx))
                    {
                        throw std::invalid_argument("window array must have length nx");
                    }
                    return values;
                }

                if (std::holds_alternative<float>(window))
                {
                    return kaiser(nx, std::get<float>(window), sym);
                }

                if (std::holds_alternative<NamedFloatParameter>(window))
                {
                    const NamedFloatParameter &spec = std::get<NamedFloatParameter>(window);
                    const std::string canonical_name = detail::canonical_window_name(spec.name);
                    if (canonical_name == "kaiser")
                    {
                        return kaiser(nx, spec.value, sym);
                    }
                    if (canonical_name == "tukey")
                    {
                        return tukey(nx, spec.value, sym);
                    }
                    if (canonical_name == "gaussian")
                    {
                        return gaussian(nx, spec.value, sym);
                    }
                    if (canonical_name == "general_hamming")
                    {
                        return general_hamming(nx, spec.value, sym);
                    }
                    if (canonical_name == "chebwin")
                    {
                        return chebwin(nx, spec.value, sym);
                    }
                    if (canonical_name == "exponential")
                    {
                        return exponential(nx, spec.value, sym);
                    }
                    throw std::invalid_argument("window spec name does not accept a single parameter");
                }

                if (std::holds_alternative<NamedFloatPairParameter>(window))
                {
                    const NamedFloatPairParameter &spec =
                        std::get<NamedFloatPairParameter>(window);
                    const std::string canonical_name = detail::canonical_window_name(spec.name);
                    if (canonical_name == "general_gaussian")
                    {
                        return general_gaussian(nx, spec.first, spec.second, sym);
                    }
                    if (canonical_name == "exponential")
                    {
                        return exponential(nx, spec.first, spec.second, sym);
                    }
                    throw std::invalid_argument("window spec name does not accept a pair of parameters");
                }

                if (std::holds_alternative<NamedTaylorParameter>(window))
                {
                    const NamedTaylorParameter &spec =
                        std::get<NamedTaylorParameter>(window);
                    const std::string canonical_name = detail::canonical_window_name(spec.name);
                    if (canonical_name != "taylor")
                    {
                        throw std::invalid_argument("window spec name does not accept Taylor parameters");
                    }
                    return taylor(nx, spec.nbar, spec.sll, spec.norm, sym);
                }

                const std::string canonical_name =
                    detail::canonical_window_name(std::get<std::string>(window));
                if (needs_parameter(canonical_name))
                {
                    throw std::invalid_argument("window requires explicit parameters");
                }
                if (canonical_name == "boxcar")
                {
                    return boxcar(nx, sym);
                }
                if (canonical_name == "barthann")
                {
                    return barthann(nx, sym);
                }
                if (canonical_name == "bartlett")
                {
                    return bartlett(nx, sym);
                }
                if (canonical_name == "blackman")
                {
                    return blackman(nx, sym);
                }
                if (canonical_name == "blackmanharris")
                {
                    return blackmanharris(nx, sym);
                }
                if (canonical_name == "bohman")
                {
                    return bohman(nx, sym);
                }
                if (canonical_name == "cosine")
                {
                    return cosine(nx, sym);
                }
                if (canonical_name == "flattop")
                {
                    return flattop(nx, sym);
                }
                if (canonical_name == "hamming")
                {
                    return hamming(nx, sym);
                }
                if (canonical_name == "hann")
                {
                    return hann(nx, sym);
                }
                if (canonical_name == "nuttall")
                {
                    return nuttall(nx, sym);
                }
                if (canonical_name == "parzen")
                {
                    return parzen(nx, sym);
                }
                if (canonical_name == "triang")
                {
                    return triang(nx, sym);
                }

                throw std::invalid_argument("window name is not supported yet");
            }

            core::RealSignal barthann(int size, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [](int index, int full_size)
                    { return detail::barthann_value(index, full_size); });
            }

            core::RealSignal bartlett(int size, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [](int index, int full_size)
                    { return detail::bartlett_value(index, full_size); });
            }

            core::RealSignal blackman(int size, bool sym)
            {
                const float coefficients[3] = {0.42, 0.50, 0.08};
                return detail::make_window_host(
                    size,
                    sym,
                    [&coefficients](int index, int full_size)
                    { return detail::general_cosine_value(index, full_size, coefficients, 3); });
            }

            core::RealSignal blackmanharris(int size, bool sym)
            {
                const float coefficients[4] = {0.35875, 0.48829, 0.14128, 0.01168};
                return detail::make_window_host(
                    size,
                    sym,
                    [&coefficients](int index, int full_size)
                    { return detail::general_cosine_value(index, full_size, coefficients, 4); });
            }

            core::RealSignal bohman(int size, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [](int index, int full_size)
                    { return detail::bohman_value(index, full_size); });
            }

            core::RealSignal boxcar(int size, bool sym)
            {
                (void)sym;
                detail::validate_size(size);
                return core::make_real_signal(static_cast<std::size_t>(size), 1.0);
            }

            core::RealSignal chebwin(int size, float at, bool sym)
            {
                if (detail::len_guard(size))
                {
                    return core::make_real_signal(static_cast<std::size_t>(size), 1.0);
                }

                const detail::ExtendedLength extended = detail::extend(size, sym);
                const core::ComplexSignal p =
                    detail::build_chebwin_frequency_response(extended.size, at);
                RealSignal fft_output = fftw_forward_real(p);
                core::ComplexSignal fft_complex(fft_output.size(), core::Complex(0.0, 0.0));
                for (std::size_t index = 0; index < fft_output.size(); ++index)
                {
                    fft_complex[index] = core::Complex(fft_output[index], 0.0);
                }

                return detail::truncate(
                    detail::rebuild_chebwin_from_fft(fft_complex),
                    extended.needs_truncation);
            }

            core::RealSignal cosine(int size, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [](int index, int full_size)
                    {
                        return detail::cosine_value(index, full_size);
                    });
            }

            core::RealSignal exponential(int size, float tau, bool sym)
            {
                if (!(tau > 0.0))
                {
                    throw std::invalid_argument("tau must be > 0");
                }
                return detail::make_window_host(
                    size,
                    sym,
                    [tau](int index, int full_size)
                    {
                        const float center = 0.5 * static_cast<float>(full_size - 1);
                        return detail::exponential_value(index, center, tau);
                    });
            }

            core::RealSignal exponential(int size, float center, float tau, bool sym)
            {
                if (!(tau > 0.0))
                {
                    throw std::invalid_argument("tau must be > 0");
                }
                if (sym)
                {
                    throw std::invalid_argument("explicit center is only supported for periodic exponential windows");
                }
                return detail::make_window_host(
                    size,
                    sym,
                    [center, tau](int index, int full_size)
                    {
                        (void)full_size;
                        return detail::exponential_value(index, center, tau);
                    });
            }

            core::RealSignal flattop(int size, bool sym)
            {
                const float coefficients[5] = {
                    0.21557895,
                    0.41663158,
                    0.277263158,
                    0.083578947,
                    0.006947368,
                };
                return detail::make_window_host(
                    size,
                    sym,
                    [&coefficients](int index, int full_size)
                    { return detail::general_cosine_value(index, full_size, coefficients, 5); });
            }

            core::RealSignal gaussian(int size, float std, bool sym)
            {
                if (!(std > 0.0))
                {
                    throw std::invalid_argument("std must be > 0");
                }
                return detail::make_window_host(
                    size,
                    sym,
                    [std](int index, int full_size)
                    { return detail::gaussian_value(index, full_size, std); });
            }

            core::RealSignal general_cosine(int size, const core::RealSignal &a, bool sym)
            {
                detail::ensure_non_empty_coefficients(a);
                return detail::make_window_host(
                    size,
                    sym,
                    [&a](int index, int full_size)
                    {
                        return detail::general_cosine_value(
                            index,
                            full_size,
                            a.data(),
                            static_cast<int>(a.size()));
                    });
            }

            core::RealSignal general_gaussian(int size, float p, float sig, bool sym)
            {
                if (!(p > 0.0))
                {
                    throw std::invalid_argument("p must be > 0");
                }
                if (!(sig > 0.0))
                {
                    throw std::invalid_argument("sig must be > 0");
                }
                return detail::make_window_host(
                    size,
                    sym,
                    [p, sig](int index, int full_size)
                    { return detail::general_gaussian_value(index, full_size, p, sig); });
            }

            core::RealSignal general_hamming(int size, float alpha, bool sym)
            {
                const float coefficients[2] = {alpha, 1.0f - alpha};
                return detail::make_window_host(
                    size,
                    sym,
                    [&coefficients](int index, int full_size)
                    { return detail::general_cosine_value(index, full_size, coefficients, 2); });
            }

            core::RealSignal hamming(int size, bool sym)
            {
                return general_hamming(size, 0.54, sym);
            }

            core::RealSignal hann(int size, bool sym)
            {
                return general_hamming(size, 0.5, sym);
            }

            core::RealSignal kaiser(int size, float beta, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [beta](int index, int full_size)
                    { return detail::kaiser_value(index, full_size, beta); });
            }

            core::RealSignal nuttall(int size, bool sym)
            {
                const float coefficients[4] = {0.3635819, 0.4891775, 0.1365995, 0.0106411};
                return detail::make_window_host(
                    size,
                    sym,
                    [&coefficients](int index, int full_size)
                    { return detail::general_cosine_value(index, full_size, coefficients, 4); });
            }

            core::RealSignal parzen(int size, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [](int index, int full_size)
                    { return detail::parzen_value(index, full_size); });
            }

            core::RealSignal taylor(int size, int nbar, float sll, bool norm, bool sym)
            {
                const core::RealSignal coefficients = detail::build_taylor_coefficients(nbar, sll);
                const detail::ExtendedLength extended = detail::extend(size, sym);
                const float scale = detail::taylor_scale(
                    extended.size,
                    nbar,
                    coefficients,
                    norm);
                return detail::make_window_host(
                    size,
                    sym,
                    [nbar, scale, &coefficients](int index, int full_size)
                    {
                        return detail::taylor_value(
                            index,
                            full_size,
                            nbar,
                            coefficients.data(),
                            static_cast<int>(coefficients.size()),
                            scale);
                    });
            }

            core::RealSignal triang(int size, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [](int index, int full_size)
                    { return detail::triang_value(index, full_size); });
            }

            core::RealSignal tukey(int size, float alpha, bool sym)
            {
                return detail::make_window_host(
                    size,
                    sym,
                    [alpha](int index, int full_size)
                    { return detail::tukey_value(index, full_size, alpha); });
            }

        } // namespace windows
    } // namespace cpu
} // namespace cusignal
