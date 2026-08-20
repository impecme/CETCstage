#include "cusignal/filter_design/filter_design.hpp"

#include <cuda_runtime.h>
#include <cufft.h>

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "cusignal/windows/windows.hpp"

#include "../common/filter_design_detail.hpp"
#include "../common/zx_execution_context.hpp"
#include "../common/zx_tile_policy.hpp"

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    namespace detail = cusignal::filter_design_detail;
    namespace tile = cusignal::zx_tile;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0;

    void throw_on_zx_gpu_error(cudaError_t status, const char *what)
    {
        if (status != cudaSuccess)
        {
            throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
        }
    }

    void throw_on_cufft_error(cufftResult status, const char *what)
    {
        if (status == CUFFT_SUCCESS)
        {
            return;
        }
        throw std::runtime_error(std::string(what) + ": cuFFT error code " + std::to_string(status));
    }

    void check_kernel_launch(const char *what)
    {
        throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

    template <typename T>
    using DeviceBuffer = cusignal::zx_execution::ReusableDeviceBuffer<T>;

    struct Firwin2PreparedCache
    {
        bool valid = false;
        int device_id = 0;
        int numtaps = 0;
        int nfreqs = 0;
        int fft_size = 0;
        bool antisymmetric = false;
        float fs = 0.0f;
        detail::Firwin2Type type = detail::Firwin2Type::TypeI;
        std::vector<float> freq;
        std::vector<float> gain;
        ZxGpuWindowSpec window;
    };

    struct TimingEvents
    {
        cudaEvent_t start = nullptr;
        cudaEvent_t stop = nullptr;

        ~TimingEvents()
        {
            if (start != nullptr)
            {
                cudaEventDestroy(start);
            }
            if (stop != nullptr)
            {
                cudaEventDestroy(stop);
            }
        }

        void ensure()
        {
            if (start == nullptr)
            {
                throw_on_zx_gpu_error(cudaEventCreate(&start), "cudaEventCreate(start)");
                throw_on_zx_gpu_error(cudaEventCreate(&stop), "cudaEventCreate(stop)");
            }
        }
    };

    thread_local TimingEvents g_timing_events;

    class ScopedZxGpuEvents
    {
    public:
        template <typename Callable>
        float measure(Callable callable)
        {
            g_timing_events.ensure();
            throw_on_zx_gpu_error(
                cudaEventRecord(g_timing_events.start), "cudaEventRecord(start)");
            callable();
            throw_on_zx_gpu_error(
                cudaEventRecord(g_timing_events.stop), "cudaEventRecord(stop)");
            throw_on_zx_gpu_error(
                cudaEventSynchronize(g_timing_events.stop), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            throw_on_zx_gpu_error(
                cudaEventElapsedTime(
                    &elapsed_ms, g_timing_events.start, g_timing_events.stop),
                "cudaEventElapsedTime");
            return elapsed_ms;
        }
    };

    struct FilterDesignWorkspace
    {
        DeviceBuffer<float2> bands;
        DeviceBuffer<float> magnitudes;
        DeviceBuffer<cufftComplex> spectrum;
        DeviceBuffer<cufftComplex> spectrum_template;
        ZxGpuRealSignal real_storage;
        ZxGpuComplexSignal complex_storage;
        ZxGpuIndexSignal index_storage;
        ZxGpuRealSignal window_storage;
        ZxGpuRealSignal firwin2_window_template;
        ZxGpuRealSignal firwin2_taps_template;
        DeviceBuffer<float> firwin_response_partials;
        DeviceBuffer<float> firwin_response_scalar;
        Firwin2PreparedCache firwin2_cache;
        bool firwin2_taps_template_valid = false;
        cufftHandle firwin2_plan = 0;
        int firwin2_plan_size = 0;

        ~FilterDesignWorkspace()
        {
            if (firwin2_plan != 0)
            {
                cufftDestroy(firwin2_plan);
            }
        }

        void ensure_firwin2_plan(int size)
        {
            if (firwin2_plan != 0 && firwin2_plan_size == size)
            {
                return;
            }
            if (firwin2_plan != 0)
            {
                throw_on_cufft_error(cufftDestroy(firwin2_plan), "cufftDestroy");
                firwin2_plan = 0;
                firwin2_plan_size = 0;
            }
            throw_on_cufft_error(cufftPlan1d(&firwin2_plan, size, CUFFT_C2C, 1), "cufftPlan1d");
            firwin2_plan_size = size;
        }
    };

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    int policy_block_count(std::size_t size)
    {
        const int threads = tile::active_threads(kThreadsPerBlock);
        return size == 0 ? 0 : static_cast<int>((size + static_cast<std::size_t>(threads) - 1) /
                                                 static_cast<std::size_t>(threads));
    }

    tile::PolicyDecision select_filter_design_policy(const char *operator_id, std::size_t numtaps)
    {
        return tile::select_if_inactive(tile::make_operator_key(
            operator_id,
            tile::OperatorFamily::FilterDesignGpu,
            {numtaps, 0, 0, 0, 0, 0},
            1));
    }

    bool same_values(const std::vector<float> &lhs, const std::vector<float> &rhs)
    {
        return lhs.size() == rhs.size() &&
               std::equal(lhs.begin(), lhs.end(), rhs.begin());
    }

    bool named_float_parameter_equal(
        const cusignal::core::NamedFloatParameter &lhs,
        const cusignal::core::NamedFloatParameter &rhs)
    {
        return lhs.name == rhs.name && lhs.value == rhs.value;
    }

    bool named_float_pair_parameter_equal(
        const cusignal::core::NamedFloatPairParameter &lhs,
        const cusignal::core::NamedFloatPairParameter &rhs)
    {
        return lhs.name == rhs.name &&
               lhs.first == rhs.first &&
               lhs.second == rhs.second;
    }

    bool named_taylor_parameter_equal(
        const cusignal::core::NamedTaylorParameter &lhs,
        const cusignal::core::NamedTaylorParameter &rhs)
    {
        return lhs.name == rhs.name &&
               lhs.nbar == rhs.nbar &&
               lhs.sll == rhs.sll &&
               lhs.norm == rhs.norm;
    }

    bool firwin2_window_cacheable(const ZxGpuWindowSpec &window)
    {
        return !std::holds_alternative<ZxGpuRealSignal>(window);
    }

    bool firwin2_window_equal(const ZxGpuWindowSpec &lhs, const ZxGpuWindowSpec &rhs)
    {
        if (lhs.index() != rhs.index())
        {
            return false;
        }
        if (const auto *left = std::get_if<std::string>(&lhs))
        {
            return *left == std::get<std::string>(rhs);
        }
        if (const auto *left = std::get_if<float>(&lhs))
        {
            return *left == std::get<float>(rhs);
        }
        if (const auto *left = std::get_if<cusignal::core::NamedFloatParameter>(&lhs))
        {
            return named_float_parameter_equal(
                *left,
                std::get<cusignal::core::NamedFloatParameter>(rhs));
        }
        if (const auto *left = std::get_if<cusignal::core::NamedFloatPairParameter>(&lhs))
        {
            return named_float_pair_parameter_equal(
                *left,
                std::get<cusignal::core::NamedFloatPairParameter>(rhs));
        }
        if (const auto *left = std::get_if<cusignal::core::NamedTaylorParameter>(&lhs))
        {
            return named_taylor_parameter_equal(
                *left,
                std::get<cusignal::core::NamedTaylorParameter>(rhs));
        }
        if (const auto *left = std::get_if<cusignal::core::RealSignal>(&lhs))
        {
            return same_values(*left, std::get<cusignal::core::RealSignal>(rhs));
        }
        return false;
    }

    bool firwin2_cache_matches(
        const Firwin2PreparedCache &cache,
        int device_id,
        int numtaps,
        int nfreqs,
        float fs,
        bool antisymmetric,
        const std::vector<float> &freq,
        const std::vector<float> &gain,
        const ZxGpuWindowSpec &window)
    {
        return cache.valid &&
               cache.device_id == device_id &&
               cache.numtaps == numtaps &&
               cache.nfreqs == nfreqs &&
               cache.fs == fs &&
               cache.antisymmetric == antisymmetric &&
               same_values(cache.freq, freq) &&
               same_values(cache.gain, gain) &&
               firwin2_window_equal(cache.window, window);
    }

    __device__ float sinc_device(float value)
    {
        if (fabs(value) < 1e-14)
        {
            return 1.0;
        }
        return sin(detail::kPi * value) / (detail::kPi * value);
    }

    __global__ void build_firwin_taps_kernel(
        float *output,
        int numtaps,
        const float2 *bands,
        int band_count)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index >= numtaps)
        {
            return;
        }

        const float alpha = 0.5 * static_cast<float>(numtaps - 1);
        const float m = static_cast<float>(index) - alpha;
        float value = 0.0;
        for (int band = 0; band < band_count; ++band)
        {
            value += bands[band].y * sinc_device(bands[band].y * m);
            value -= bands[band].x * sinc_device(bands[band].x * m);
        }
        output[index] = value;
    }

    __global__ void multiply_window_kernel(
        float *output,
        const float *window,
        std::size_t size)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            output[index] *= window[index];
        }
    }

    __global__ void firwin_response_partial_kernel(
        const float *values,
        int numtaps,
        float alpha,
        float normalized_frequency,
        float *partials)
    {
        __shared__ float cache[kThreadsPerBlock];
        float sum = 0.0f;
        for (int index = blockIdx.x * blockDim.x + threadIdx.x;
             index < numtaps;
             index += gridDim.x * blockDim.x)
        {
            const float m = static_cast<float>(index) - alpha;
            sum = fmaf(values[index], cosf(detail::kPi * m * normalized_frequency), sum);
        }
        cache[threadIdx.x] = sum;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                cache[threadIdx.x] += cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x == 0)
        {
            partials[blockIdx.x] = cache[0];
        }
    }

    __global__ void firwin_response_finalize_kernel(
        const float *partials,
        int partial_count,
        float *response)
    {
        __shared__ float cache[kThreadsPerBlock];
        float sum = 0.0f;
        for (int index = threadIdx.x; index < partial_count; index += blockDim.x)
        {
            sum += partials[index];
        }
        cache[threadIdx.x] = sum;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                cache[threadIdx.x] += cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x == 0)
        {
            response[0] = cache[0];
        }
    }

    __global__ void scale_signal_by_response_kernel(
        float *output,
        std::size_t size,
        const float *response)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            output[index] *= 1.0f / response[0];
        }
    }

    __global__ void extract_firwin2_taps_kernel(
        float *output,
        const cufftComplex *spectrum,
        const float *window,
        int numtaps,
        int fft_size,
        bool zero_center)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index >= numtaps)
        {
            return;
        }
        float value = spectrum[index].x / static_cast<float>(fft_size);
        value *= window[index];
        if (zero_center && index == numtaps / 2)
        {
            value = 0.0;
        }
        output[index] = value;
    }

    const ZxGpuRealSignal &resolve_window_signal(
        ZxGpuWindowSpec window,
        int numtaps,
        FilterDesignWorkspace &workspace)
    {
        detail::validate_window_length(window, numtaps);
        if (const auto *values = std::get_if<ZxGpuRealSignal>(&window))
        {
            return *values;
        }
        if (const auto *values = std::get_if<cusignal::core::RealSignal>(&window))
        {
            workspace.window_storage.copy_from(*values);
            return workspace.window_storage;
        }
        workspace.window_storage = cusignal::zx_gpu_backend::windows::get_window(window, numtaps, false);
        return workspace.window_storage;
    }

    std::vector<cufftComplex> build_full_spectrum(
        const std::vector<std::complex<float>> &half_spectrum)
    {
        const std::size_t fft_size = half_spectrum.size() < 2 ? 1 : 2 * (half_spectrum.size() - 1);
        std::vector<cufftComplex> full_spectrum(
            fft_size,
            cufftComplex{0.0, 0.0});
        for (std::size_t index = 0; index < half_spectrum.size(); ++index)
        {
            full_spectrum[index].x = half_spectrum[index].real();
            full_spectrum[index].y = half_spectrum[index].imag();
        }
        for (std::size_t index = 1; index + 1 < half_spectrum.size(); ++index)
        {
            full_spectrum[fft_size - index].x = half_spectrum[index].real();
            full_spectrum[fft_size - index].y = -half_spectrum[index].imag();
        }
        return full_spectrum;
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace filter_design
        {

            float kaiser_beta(float attenuation)
            {
                return cpu::filter_design::kaiser_beta(attenuation);
            }

            float kaiser_atten(int numtaps, float width)
            {
                return cpu::filter_design::kaiser_atten(numtaps, width);
            }

            filter_design_api::ZxGpuComplexSortResult cmplx_sort(const core::RealSignalLike &p)
            {
                const core::RealSignal host_values = std::holds_alternative<core::RealSignal>(p)
                                                         ? std::get<core::RealSignal>(p)
                                                         : std::get<core::ZxGpuRealSignal>(p).get();
                const filter_design_api::ComplexSortResult sorted =
                    cpu::filter_design::cmplx_sort(host_values);
                filter_design_api::ZxGpuComplexSortResult result;
                result.values = core::ZxGpuRealSignal::from_host(std::get<core::RealSignal>(sorted.values));
                result.indices = core::ZxGpuIndexSignal::from_host(sorted.indices);
                g_last_kernel_ms = 0.0;
                return result;
            }

            filter_design_api::ZxGpuComplexSortResult cmplx_sort(const core::ComplexSignalLike &p)
            {
                const core::ComplexSignal host_values = std::holds_alternative<core::ComplexSignal>(p)
                                                            ? std::get<core::ComplexSignal>(p)
                                                            : std::get<core::ZxGpuComplexSignal>(p).get();
                const filter_design_api::ComplexSortResult sorted =
                    cpu::filter_design::cmplx_sort(host_values);
                filter_design_api::ZxGpuComplexSortResult result;
                result.values = core::ZxGpuComplexSignal::from_host(std::get<core::ComplexSignal>(sorted.values));
                result.indices = core::ZxGpuIndexSignal::from_host(sorted.indices);
                g_last_kernel_ms = 0.0;
                return result;
            }

            core::ZxGpuRealSignal firwin(
                int numtaps,
                float cutoff,
                float width,
                ZxGpuWindowSpec window,
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

            core::ZxGpuRealSignal firwin(
                int numtaps,
                const core::RealSignalLike &cutoff,
                float width,
                ZxGpuWindowSpec window,
                core::PassZeroSpec pass_zero,
                bool scale,
                float nyq,
                float fs)
            {
                thread_local FilterDesignWorkspace workspace;
                detail::ensure_numtaps(numtaps);
                const tile::ScopedPolicyIfInactive policy_scope(
                    select_filter_design_policy("filter_design/firwin", static_cast<std::size_t>(numtaps)));
                const float resolved_fs = detail::resolved_fs(nyq, fs);
                detail::ensure_positive(resolved_fs, "fs");
                const float resolved_nyq = 0.5 * resolved_fs;

                core::RealSignal cutoff_host;
                if (const auto *host = std::get_if<core::RealSignal>(&cutoff))
                {
                    cutoff_host = *host;
                }
                else
                {
                    cutoff_host = std::get<ZxGpuRealSignal>(cutoff).get();
                }
                const std::vector<float> normalized_cutoff =
                    detail::normalize_cutoff(cutoff_host, resolved_nyq);
                const bool include_zero =
                    detail::normalize_pass_zero(pass_zero, normalized_cutoff.size());
                detail::validate_firwin_even_nyquist(numtaps, normalized_cutoff, include_zero);

                if (width > 0.0)
                {
                    const float attenuation = kaiser_atten(numtaps, width / resolved_nyq);
                    window = kaiser_beta(attenuation);
                }

                const std::vector<std::pair<float, float>> bands =
                    detail::build_bands(normalized_cutoff, include_zero);
                std::vector<float2> host_bands(bands.size(), float2{0.0, 0.0});
                for (std::size_t index = 0; index < bands.size(); ++index)
                {
                    host_bands[index].x = bands[index].first;
                    host_bands[index].y = bands[index].second;
                }

                workspace.bands.copy_from_host(host_bands.data(), host_bands.size(), "cudaMemcpy H2D(bands)");
                core::ZxGpuRealSignal output = core::make_zx_gpu_real_signal(static_cast<std::size_t>(numtaps));
                const auto &device_window = resolve_window_signal(window, numtaps, workspace);

                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    build_firwin_taps_kernel<<<policy_block_count(static_cast<std::size_t>(numtaps)),
                                               tile::active_threads(kThreadsPerBlock)>>>(
                        output.data(),
                        numtaps,
                        workspace.bands.get(),
                        static_cast<int>(host_bands.size()));
                    check_kernel_launch("build_firwin_taps_kernel");

                    multiply_window_kernel<<<policy_block_count(output.size()), tile::active_threads(kThreadsPerBlock)>>>(
                        output.data(),
                        device_window.data(),
                        output.size());
                    check_kernel_launch("multiply_window_kernel");

                    if (scale)
                    {
                        const float scale_frequency = detail::scale_frequency_for_bands(bands);
                        const int partial_count =
                            std::min(1024, std::max(1, block_count(static_cast<std::size_t>(numtaps))));
                        workspace.firwin_response_partials.reserve(static_cast<std::size_t>(partial_count));
                        workspace.firwin_response_scalar.reserve(1);
                        firwin_response_partial_kernel<<<partial_count, kThreadsPerBlock>>>(
                            output.data(),
                            numtaps,
                            0.5f * static_cast<float>(numtaps - 1),
                            scale_frequency,
                            workspace.firwin_response_partials.get());
                        check_kernel_launch("firwin_response_partial_kernel");
                        firwin_response_finalize_kernel<<<1, kThreadsPerBlock>>>(
                            workspace.firwin_response_partials.get(),
                            partial_count,
                            workspace.firwin_response_scalar.get());
                        check_kernel_launch("firwin_response_finalize_kernel");
                        scale_signal_by_response_kernel<<<policy_block_count(output.size()), tile::active_threads(kThreadsPerBlock)>>>(
                            output.data(),
                            output.size(),
                            workspace.firwin_response_scalar.get());
                        check_kernel_launch("scale_signal_by_response_kernel");
                    }
                }));
                return output;
            }

            core::ZxGpuRealSignal firwin2(
                int numtaps,
                const core::RealSignalLike &freq,
                const core::RealSignalLike &gain,
                int nfreqs,
                ZxGpuWindowSpec window,
                float nyq,
                bool antisymmetric,
                float fs)
            {
                thread_local FilterDesignWorkspace workspace;
                detail::ensure_numtaps(numtaps);
                const tile::ScopedPolicyIfInactive policy_scope(
                    select_filter_design_policy("filter_design/firwin2", static_cast<std::size_t>(numtaps)));
                const float resolved_fs = detail::resolved_fs(nyq, fs);
                detail::ensure_positive(resolved_fs, "fs");

                core::RealSignal freq_host;
                if (const auto *host = std::get_if<core::RealSignal>(&freq))
                {
                    freq_host = *host;
                }
                else
                {
                    freq_host = std::get<ZxGpuRealSignal>(freq).get();
                }
                core::RealSignal gain_host;
                if (const auto *host = std::get_if<core::RealSignal>(&gain))
                {
                    gain_host = *host;
                }
                else
                {
                    gain_host = std::get<ZxGpuRealSignal>(gain).get();
                }

                const detail::Firwin2Type type =
                    detail::determine_firwin2_type(numtaps, antisymmetric);
                detail::prepare_freq_grid(freq_host, gain_host, resolved_fs);
                detail::validate_firwin2_gain_constraints(type, gain_host);

                const int resolved_nfreqs = nfreqs == 0 ? detail::default_nfreqs(numtaps) : nfreqs;
                if (resolved_nfreqs <= numtaps)
                {
                    throw std::invalid_argument("numtaps must be less than nfreqs");
                }

                int device_id = 0;
                throw_on_zx_gpu_error(cudaGetDevice(&device_id), "cudaGetDevice");
                const bool cacheable_window = firwin2_window_cacheable(window);
                const bool cache_hit = tile::optimized_path() && cacheable_window &&
                                       workspace.firwin2_taps_template_valid &&
                                       workspace.firwin2_taps_template.size() ==
                                           static_cast<std::size_t>(numtaps) &&
                                       firwin2_cache_matches(
                                           workspace.firwin2_cache,
                                           device_id,
                                           numtaps,
                                           resolved_nfreqs,
                                           resolved_fs,
                                           antisymmetric,
                                           freq_host,
                                           gain_host,
                                           window);
                int fft_size = workspace.firwin2_cache.fft_size;
                detail::Firwin2Type prepared_type = workspace.firwin2_cache.type;
                const ZxGpuRealSignal *device_window = nullptr;
                if (!cache_hit)
                {
                    workspace.firwin2_taps_template_valid = false;
                    const std::vector<float> adjusted_freq = detail::tweak_repeated_freq(freq_host, resolved_fs);
                    const std::vector<float> mesh = detail::firwin2_mesh(resolved_nfreqs, resolved_fs);
                    const std::vector<float> interpolated_gain =
                        detail::interpolate_linear(mesh, adjusted_freq, gain_host);
                    const std::vector<std::complex<float>> half_spectrum =
                        detail::firwin2_shifted_response(
                            numtaps,
                            mesh,
                            interpolated_gain,
                            resolved_fs,
                            type);
                    const std::vector<cufftComplex> full_spectrum =
                        build_full_spectrum(half_spectrum);
                    workspace.spectrum_template.copy_from_host(
                        full_spectrum.data(),
                        full_spectrum.size(),
                        "cudaMemcpy H2D(firwin2 spectrum template)");

                    fft_size = static_cast<int>(full_spectrum.size());
                    prepared_type = type;
                    const ZxGpuRealSignal &resolved_window =
                        resolve_window_signal(window, numtaps, workspace);
                    if (cacheable_window)
                    {
                        workspace.firwin2_window_template.resize(
                            static_cast<std::size_t>(numtaps),
                            false);
                        throw_on_zx_gpu_error(
                            cudaMemcpy(
                                workspace.firwin2_window_template.data(),
                                resolved_window.data(),
                                static_cast<std::size_t>(numtaps) * sizeof(float),
                                cudaMemcpyDeviceToDevice),
                            "cudaMemcpy D2D(firwin2 window template)");
                        device_window = &workspace.firwin2_window_template;

                        workspace.firwin2_cache.valid = true;
                        workspace.firwin2_cache.device_id = device_id;
                        workspace.firwin2_cache.numtaps = numtaps;
                        workspace.firwin2_cache.nfreqs = resolved_nfreqs;
                        workspace.firwin2_cache.fft_size = fft_size;
                        workspace.firwin2_cache.antisymmetric = antisymmetric;
                        workspace.firwin2_cache.fs = resolved_fs;
                        workspace.firwin2_cache.type = type;
                        workspace.firwin2_cache.freq = freq_host;
                        workspace.firwin2_cache.gain = gain_host;
                        workspace.firwin2_cache.window = window;
                    }
                    else
                    {
                        workspace.firwin2_cache.valid = false;
                        workspace.firwin2_taps_template_valid = false;
                        device_window = &resolved_window;
                    }
                }
                else
                {
                    device_window = &workspace.firwin2_window_template;
                }

                core::ZxGpuRealSignal output = core::make_zx_gpu_real_signal(static_cast<std::size_t>(numtaps));

                ScopedZxGpuEvents events;
                if (cache_hit)
                {
                    g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                        throw_on_zx_gpu_error(
                            cudaMemcpy(
                                output.data(),
                                workspace.firwin2_taps_template.data(),
                                static_cast<std::size_t>(numtaps) * sizeof(float),
                                cudaMemcpyDeviceToDevice),
                            "cudaMemcpy D2D(firwin2 taps template)");
                    }));
                    return output;
                }

                workspace.ensure_firwin2_plan(fft_size);
                workspace.spectrum.reserve(static_cast<std::size_t>(fft_size));
                throw_on_zx_gpu_error(
                    cudaMemcpy(
                        workspace.spectrum.get(),
                        workspace.spectrum_template.get(),
                        static_cast<std::size_t>(fft_size) * sizeof(cufftComplex),
                        cudaMemcpyDeviceToDevice),
                    "cudaMemcpy D2D(firwin2 spectrum template)");

                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    throw_on_cufft_error(
                        cufftExecC2C(
                            workspace.firwin2_plan,
                            workspace.spectrum.get(),
                            workspace.spectrum.get(),
                            CUFFT_INVERSE),
                        "cufftExecC2C");

                    extract_firwin2_taps_kernel<<<policy_block_count(static_cast<std::size_t>(numtaps)),
                                                  tile::active_threads(kThreadsPerBlock)>>>(
                        output.data(),
                        workspace.spectrum.get(),
                        device_window->data(),
                        numtaps,
                        fft_size,
                        prepared_type == detail::Firwin2Type::TypeIII);
                    check_kernel_launch("extract_firwin2_taps_kernel");

                    if (cacheable_window)
                    {
                        workspace.firwin2_taps_template.resize(
                            static_cast<std::size_t>(numtaps),
                            false);
                        throw_on_zx_gpu_error(
                            cudaMemcpy(
                                workspace.firwin2_taps_template.data(),
                                output.data(),
                                static_cast<std::size_t>(numtaps) * sizeof(float),
                                cudaMemcpyDeviceToDevice),
                            "cudaMemcpy D2D(firwin2 taps template update)");
                        workspace.firwin2_taps_template_valid = true;
                    }
                }));
                return output;
            }
        } // namespace filter_design

        namespace filter_design_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0;
                return value;
            }
        } // namespace filter_design_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
