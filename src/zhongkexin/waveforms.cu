#include "cusignal/waveforms/waveforms.hpp"

#include <cuda_runtime.h>

#include <complex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "../common/waveforms_detail.hpp"
#include "../common/zx_tile_policy.hpp"

namespace
{
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::RealSignal;
    namespace tile = cusignal::zx_tile;

    constexpr int kThreadsPerBlock = 256;

    void throw_on_zx_gpu_error(cudaError_t status, const char *what)
    {
        if (status != cudaSuccess)
        {
            throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
        }
    }

    void check_kernel_launch(const char *what)
    {
        throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

    int block_count(std::size_t size)
    {
        return size == 0
            ? 0
            : static_cast<int>(tile::ceil_div(size, static_cast<std::size_t>(tile::linear_shape(size).threads)));
    }

    int tiled_block_count(std::size_t size, int elements_per_thread, int threads)
    {
        return size == 0
            ? 0
            : static_cast<int>(tile::ceil_div(
                  size,
                  static_cast<std::size_t>(threads) *
                      static_cast<std::size_t>(elements_per_thread)));
    }

    struct ChirpWorkspace
    {
        ZxGpuRealSignal t;
    };

    struct GausspulseWorkspace
    {
        ZxGpuRealSignal t;
    };

    struct ScalarWaveWorkspace
    {
        ZxGpuRealSignal t;
        ZxGpuRealSignal param;
    };

    __global__ void chirp_linear_real_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float beta,
        float phi,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float phase = cusignal::waveforms_detail::linear_phase_from_beta(t[index], f0, beta);
        output[index] = cos(phase + phi);
    }

    __global__ void chirp_linear_complex_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float beta,
        float phi,
        float2 *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float angle =
            cusignal::waveforms_detail::linear_phase_from_beta(t[index], f0, beta) + phi;
        output[index] = float2{cos(angle), sin(angle)};
    }

    __global__ void chirp_quadratic_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        bool vertex_zero,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float phase =
            cusignal::waveforms_detail::quadratic_phase(t[index], f0, t1, f1, vertex_zero);
        output[index] = cos(phase + phi);
    }

    __global__ void chirp_logarithmic_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float phase = cusignal::waveforms_detail::logarithmic_phase(t[index], f0, t1, f1);
        output[index] = cos(phase + phi);
    }

    __global__ void chirp_hyperbolic_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float phase = cusignal::waveforms_detail::hyperbolic_phase(t[index], f0, t1, f1);
        output[index] = cos(phase + phi);
    }

    template <bool ReturnQuadrature, bool ReturnEnvelope>
    __global__ void gausspulse_kernel(
        const float *t,
        std::size_t size,
        float a,
        float fc,
        float *signal,
        float *quadrature,
        float *envelope)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        cusignal::waveforms_detail::gausspulse_components<ReturnQuadrature, ReturnEnvelope>(
            t[index],
            a,
            fc,
            signal + index,
            ReturnQuadrature ? quadrature + index : nullptr,
            ReturnEnvelope ? envelope + index : nullptr);
    }

    __global__ void sawtooth_scalar_kernel(
        const float *t,
        std::size_t size,
        float width,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        output[index] = cusignal::waveforms_detail::sawtooth_value(t[index], width);
    }

    __global__ void sawtooth_vector_kernel(
        const float *t,
        const float *width,
        std::size_t size,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        output[index] = cusignal::waveforms_detail::sawtooth_value(t[index], width[index]);
    }

    __global__ void square_scalar_kernel(
        const float *t,
        std::size_t size,
        float duty,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        output[index] = cusignal::waveforms_detail::square_value(t[index], duty);
    }

    __global__ void square_vector_kernel(
        const float *t,
        const float *duty,
        std::size_t size,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        output[index] = cusignal::waveforms_detail::square_value(t[index], duty[index]);
    }

    __global__ void set_impulse_kernel(float *output, std::size_t flat_index)
    {
        output[flat_index] = 1.0;
    }

    // Pointwise waveform production has no cross-element dependency.  The
    // optimized route therefore follows CUTLASS' linear tile mapping: one
    // block owns a contiguous tile and each thread evaluates a few register
    // elements.  The one-element kernels above remain the legacy path.
    __global__ void chirp_real_tiled_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        bool vertex_zero,
        int method_code,
        float *output,
        int elements_per_thread)
    {
        const std::size_t tile_begin =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x *
            static_cast<std::size_t>(elements_per_thread);
        const float beta = (f1 - f0) / t1;
        for (int item = 0; item < elements_per_thread; ++item)
        {
            const std::size_t index =
                tile_begin + static_cast<std::size_t>(threadIdx.x) +
                static_cast<std::size_t>(item) * blockDim.x;
            if (index >= size)
            {
                continue;
            }
            const float time = t[index];
            float phase = 0.0f;
            if (method_code == 0)
            {
                phase = cusignal::waveforms_detail::linear_phase_from_beta(time, f0, beta);
            }
            else if (method_code == 1)
            {
                phase = cusignal::waveforms_detail::quadratic_phase(
                    time, f0, t1, f1, vertex_zero);
            }
            else if (method_code == 2)
            {
                phase = cusignal::waveforms_detail::logarithmic_phase(
                    time, f0, t1, f1);
            }
            else
            {
                phase = cusignal::waveforms_detail::hyperbolic_phase(
                    time, f0, t1, f1);
            }
            output[index] = cos(phase + phi);
        }
    }

    __global__ void chirp_complex_tiled_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float beta,
        float phi,
        float2 *output,
        int elements_per_thread)
    {
        const std::size_t tile_begin =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x *
            static_cast<std::size_t>(elements_per_thread);
        for (int item = 0; item < elements_per_thread; ++item)
        {
            const std::size_t index =
                tile_begin + static_cast<std::size_t>(threadIdx.x) +
                static_cast<std::size_t>(item) * blockDim.x;
            if (index >= size)
            {
                continue;
            }
            const float angle =
                cusignal::waveforms_detail::linear_phase_from_beta(t[index], f0, beta) + phi;
            output[index] = float2{cos(angle), sin(angle)};
        }
    }

    template <bool ReturnQuadrature, bool ReturnEnvelope>
    __global__ void gausspulse_tiled_kernel(
        const float *t,
        std::size_t size,
        float a,
        float fc,
        float *signal,
        float *quadrature,
        float *envelope,
        int elements_per_thread)
    {
        const std::size_t tile_begin =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x *
            static_cast<std::size_t>(elements_per_thread);
        for (int item = 0; item < elements_per_thread; ++item)
        {
            const std::size_t index =
                tile_begin + static_cast<std::size_t>(threadIdx.x) +
                static_cast<std::size_t>(item) * blockDim.x;
            if (index >= size)
            {
                continue;
            }
            cusignal::waveforms_detail::gausspulse_components<ReturnQuadrature, ReturnEnvelope>(
                t[index],
                a,
                fc,
                signal + index,
                ReturnQuadrature ? quadrature + index : nullptr,
                ReturnEnvelope ? envelope + index : nullptr);
        }
    }

    __global__ void sawtooth_tiled_scalar_kernel(
        const float *t,
        std::size_t size,
        float width,
        float *output,
        int elements_per_thread)
    {
        const std::size_t tile_begin =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x *
            static_cast<std::size_t>(elements_per_thread);
        for (int item = 0; item < elements_per_thread; ++item)
        {
            const std::size_t index =
                tile_begin + static_cast<std::size_t>(threadIdx.x) +
                static_cast<std::size_t>(item) * blockDim.x;
            if (index < size)
            {
                output[index] = cusignal::waveforms_detail::sawtooth_value(t[index], width);
            }
        }
    }

    __global__ void sawtooth_tiled_vector_kernel(
        const float *t,
        const float *width,
        std::size_t size,
        float *output,
        int elements_per_thread)
    {
        const std::size_t tile_begin =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x *
            static_cast<std::size_t>(elements_per_thread);
        for (int item = 0; item < elements_per_thread; ++item)
        {
            const std::size_t index =
                tile_begin + static_cast<std::size_t>(threadIdx.x) +
                static_cast<std::size_t>(item) * blockDim.x;
            if (index < size)
            {
                output[index] =
                    cusignal::waveforms_detail::sawtooth_value(t[index], width[index]);
            }
        }
    }

    __global__ void square_tiled_scalar_kernel(
        const float *t,
        std::size_t size,
        float duty,
        float *output,
        int elements_per_thread)
    {
        const std::size_t tile_begin =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x *
            static_cast<std::size_t>(elements_per_thread);
        for (int item = 0; item < elements_per_thread; ++item)
        {
            const std::size_t index =
                tile_begin + static_cast<std::size_t>(threadIdx.x) +
                static_cast<std::size_t>(item) * blockDim.x;
            if (index < size)
            {
                output[index] = cusignal::waveforms_detail::square_value(t[index], duty);
            }
        }
    }

    __global__ void square_tiled_vector_kernel(
        const float *t,
        const float *duty,
        std::size_t size,
        float *output,
        int elements_per_thread)
    {
        const std::size_t tile_begin =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x *
            static_cast<std::size_t>(elements_per_thread);
        for (int item = 0; item < elements_per_thread; ++item)
        {
            const std::size_t index =
                tile_begin + static_cast<std::size_t>(threadIdx.x) +
                static_cast<std::size_t>(item) * blockDim.x;
            if (index < size)
            {
                output[index] = cusignal::waveforms_detail::square_value(t[index], duty[index]);
            }
        }
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace waveforms
        {

            waveforms_api::ZxGpuChirpResult chirp(
                const core::RealSignalLike &t,
                float f0,
                float t1,
                float f1,
                const std::string &method,
                float phi,
                bool vertex_zero,
                const std::string &type)
            {
                using namespace waveforms_detail;

                const std::string normalized_method = validate_chirp_method(method);
                const std::string normalized_type = validate_chirp_type(type);
                validate_chirp_inputs(f0, t1, f1, phi, normalized_method, normalized_type);

                static thread_local ChirpWorkspace workspace;
                const core::ZxGpuRealSignal &t_device = core::as_device_signal(t, workspace.t);

                if (t_device.empty())
                {
                    if (normalized_type == "complex")
                    {
                        return core::ZxGpuComplexSignal{};
                    }
                    return core::ZxGpuRealSignal{};
                }

                const float phi_radians = degrees_to_radians(phi);
                const std::size_t size = t_device.size();
                const tile::PolicyDecision tuning = tile::select(
                    tile::make_linear_operator_key(
                        "waveforms/chirp",
                        size,
                        normalized_type == "complex" ? 1 : 0,
                        tile::stable_string_hash(normalized_method),
                        tile::stable_string_hash(normalized_type)));
                const tile::ScopedPolicy policy_scope(tuning);
                const int launch_threads = tuning.config.tile.threads;
                const bool use_tiled = tile::optimized_path() && size >= 4096;
                const int elements_per_thread =
                    use_tiled ? tile::linear_shape(size).elements_per_thread : 1;
                const int blocks = use_tiled
                                       ? tiled_block_count(size, elements_per_thread, launch_threads)
                                       : block_count(size);

                if (normalized_type == "complex")
                {
                    const float linear_beta = (f1 - f0) / t1;
                    core::ZxGpuComplexSignal complex_output(size);
                    if (use_tiled)
                    {
                        chirp_complex_tiled_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            linear_beta,
                            phi_radians,
                            complex_output.data(),
                            elements_per_thread);
                    }
                    else
                    {
                        chirp_linear_complex_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            linear_beta,
                            phi_radians,
                            complex_output.data());
                    }
                    check_kernel_launch("chirp_linear_complex_kernel");
                    return complex_output;
                }

                core::ZxGpuRealSignal output(size);
                if (is_linear_method(normalized_method))
                {
                    const float linear_beta = (f1 - f0) / t1;
                    if (use_tiled)
                    {
                        chirp_real_tiled_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            t1,
                            f1,
                            phi_radians,
                            vertex_zero,
                            0,
                            output.data(),
                            elements_per_thread);
                    }
                    else
                    {
                        chirp_linear_real_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            linear_beta,
                            phi_radians,
                            output.data());
                    }
                    check_kernel_launch("chirp_linear_real_kernel");
                }
                else if (is_quadratic_method(normalized_method))
                {
                    if (use_tiled)
                    {
                        chirp_real_tiled_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            t1,
                            f1,
                            phi_radians,
                            vertex_zero,
                            1,
                            output.data(),
                            elements_per_thread);
                    }
                    else
                    {
                        chirp_quadratic_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            t1,
                            f1,
                            phi_radians,
                            vertex_zero,
                            output.data());
                    }
                    check_kernel_launch("chirp_quadratic_kernel");
                }
                else if (is_logarithmic_method(normalized_method))
                {
                    if (use_tiled)
                    {
                        chirp_real_tiled_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            t1,
                            f1,
                            phi_radians,
                            vertex_zero,
                            2,
                            output.data(),
                            elements_per_thread);
                    }
                    else
                    {
                        chirp_logarithmic_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            t1,
                            f1,
                            phi_radians,
                            output.data());
                    }
                    check_kernel_launch("chirp_logarithmic_kernel");
                }
                else
                {
                    if (use_tiled)
                    {
                        chirp_real_tiled_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            t1,
                            f1,
                            phi_radians,
                            vertex_zero,
                            3,
                            output.data(),
                            elements_per_thread);
                    }
                    else
                    {
                        chirp_hyperbolic_kernel<<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            f0,
                            t1,
                            f1,
                            phi_radians,
                            output.data());
                    }
                    check_kernel_launch("chirp_hyperbolic_kernel");
                }

                return output;
            }

            waveforms_api::ZxGpuGausspulseResult gausspulse(
                const core::RealSignalLike &t,
                float fc,
                float bw,
                float bwr,
                float tpr,
                bool retquad,
                bool retenv)
            {
                using namespace waveforms_detail;

                ensure_finite(tpr, "tpr");
                const float a = compute_gausspulse_a(fc, bw, bwr);
                static thread_local GausspulseWorkspace workspace;
                const core::ZxGpuRealSignal &t_device = core::as_device_signal(t, workspace.t);
                const std::size_t size = t_device.size();

                if (size == 0)
                {
                    if (retquad && retenv)
                    {
                        return core::ZxGpuWaveformBundle{};
                    }
                    if (retquad)
                    {
                        return waveforms_api::ZxGpuIqWaveform{};
                    }
                    if (retenv)
                    {
                        return waveforms_api::ZxGpuIEnvWaveform{};
                    }
                    return core::ZxGpuRealSignal{};
                }

                core::ZxGpuRealSignal signal(size);
                core::ZxGpuRealSignal quadrature = retquad ? core::ZxGpuRealSignal(size) : core::ZxGpuRealSignal{};
                core::ZxGpuRealSignal envelope = retenv ? core::ZxGpuRealSignal(size) : core::ZxGpuRealSignal{};
                const tile::PolicyDecision tuning = tile::select(
                    tile::make_linear_operator_key(
                        "waveforms/gausspulse",
                        size,
                        0,
                        retquad ? 1ULL : 0ULL,
                        retenv ? 1ULL : 0ULL));
                const tile::ScopedPolicy policy_scope(tuning);
                const int launch_threads = tuning.config.tile.threads;
                const bool use_tiled = tile::optimized_path() && size >= 4096;
                const int elements_per_thread =
                    use_tiled ? tile::linear_shape(size).elements_per_thread : 1;
                const int blocks = use_tiled
                                       ? tiled_block_count(size, elements_per_thread, launch_threads)
                                       : block_count(size);

                if (retquad && retenv)
                {
                    if (use_tiled)
                    {
                        gausspulse_tiled_kernel<true, true><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            quadrature.data(),
                            envelope.data(),
                            elements_per_thread);
                    }
                    else
                    {
                        gausspulse_kernel<true, true><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            quadrature.data(),
                            envelope.data());
                    }
                }
                else if (retquad)
                {
                    if (use_tiled)
                    {
                        gausspulse_tiled_kernel<true, false><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            quadrature.data(),
                            nullptr,
                            elements_per_thread);
                    }
                    else
                    {
                        gausspulse_kernel<true, false><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            quadrature.data(),
                            nullptr);
                    }
                }
                else if (retenv)
                {
                    if (use_tiled)
                    {
                        gausspulse_tiled_kernel<false, true><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            nullptr,
                            envelope.data(),
                            elements_per_thread);
                    }
                    else
                    {
                        gausspulse_kernel<false, true><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            nullptr,
                            envelope.data());
                    }
                }
                else
                {
                    if (use_tiled)
                    {
                        gausspulse_tiled_kernel<false, false><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            nullptr,
                            nullptr,
                            elements_per_thread);
                    }
                    else
                    {
                        gausspulse_kernel<false, false><<<blocks, launch_threads>>>(
                            t_device.data(),
                            size,
                            a,
                            fc,
                            signal.data(),
                            nullptr,
                            nullptr);
                    }
                }
                check_kernel_launch("gausspulse_kernel");

                if (retquad && retenv)
                {
                    core::ZxGpuWaveformBundle result;
                    result.signal = std::move(signal);
                    result.quadrature = std::move(quadrature);
                    result.envelope = std::move(envelope);
                    return result;
                }
                if (retquad)
                {
                    waveforms_api::ZxGpuIqWaveform result;
                    result.signal = std::move(signal);
                    result.quadrature = std::move(quadrature);
                    return result;
                }
                if (retenv)
                {
                    waveforms_api::ZxGpuIEnvWaveform result;
                    result.signal = std::move(signal);
                    result.envelope = std::move(envelope);
                    return result;
                }
                return signal;
            }

            float gausspulse(
                const std::string &t,
                float fc,
                float bw,
                float bwr,
                float tpr)
            {
                using namespace waveforms_detail;

                if (normalize_token(t) != "cutoff")
                {
                    throw std::invalid_argument("If t is a string, it must be cutoff");
                }
                return compute_gausspulse_cutoff(fc, bw, bwr, tpr);
            }

            core::ZxGpuRealSignal sawtooth(const core::RealSignalLike &t, float width)
            {
                using namespace waveforms_detail;

                ensure_probability(width, "width");
                static thread_local ScalarWaveWorkspace workspace;
                const core::ZxGpuRealSignal &t_device = core::as_device_signal(t, workspace.t);
                if (t_device.empty())
                {
                    return core::ZxGpuRealSignal{};
                }

                core::ZxGpuRealSignal output(t_device.size());
                const tile::PolicyDecision tuning = tile::select(
                    tile::make_linear_operator_key("waveforms/sawtooth", t_device.size(), 0, 1));
                const tile::ScopedPolicy policy_scope(tuning);
                const int launch_threads = tuning.config.tile.threads;
                const bool use_tiled = tile::optimized_path() && t_device.size() >= 4096;
                const int elements_per_thread =
                    use_tiled ? tile::linear_shape(t_device.size()).elements_per_thread : 1;
                const int blocks = use_tiled
                                       ? tiled_block_count(t_device.size(), elements_per_thread, launch_threads)
                                       : block_count(t_device.size());
                if (use_tiled)
                {
                    sawtooth_tiled_scalar_kernel<<<blocks, launch_threads>>>(
                        t_device.data(),
                        t_device.size(),
                        width,
                        output.data(),
                        elements_per_thread);
                }
                else
                {
                    sawtooth_scalar_kernel<<<blocks, launch_threads>>>(
                        t_device.data(), t_device.size(), width, output.data());
                }
                check_kernel_launch("sawtooth_scalar_kernel");
                return output;
            }

            core::ZxGpuRealSignal sawtooth(
                const core::RealSignalLike &t,
                const core::RealSignalLike &width)
            {
                using namespace waveforms_detail;

                if (const auto *host_t = std::get_if<core::RealSignal>(&t))
                {
                    if (const auto *host_width = std::get_if<core::RealSignal>(&width))
                    {
                        ensure_vector_parameter(*host_t, *host_width, "width");
                    }
                }

                static thread_local ScalarWaveWorkspace workspace;
                const core::ZxGpuRealSignal &t_device = core::as_device_signal(t, workspace.t);
                const core::ZxGpuRealSignal &width_device =
                    core::as_device_signal(width, workspace.param);
                if (t_device.size() != width_device.size())
                {
                    throw std::invalid_argument("width must have the same length as t");
                }
                if (t_device.empty())
                {
                    return core::ZxGpuRealSignal{};
                }

                core::ZxGpuRealSignal output(t_device.size());
                const tile::PolicyDecision tuning = tile::select(
                    tile::make_linear_operator_key("waveforms/sawtooth", t_device.size(), 0, 2));
                const tile::ScopedPolicy policy_scope(tuning);
                const int launch_threads = tuning.config.tile.threads;
                const bool use_tiled = tile::optimized_path() && t_device.size() >= 4096;
                const int elements_per_thread =
                    use_tiled ? tile::linear_shape(t_device.size()).elements_per_thread : 1;
                const int blocks = use_tiled
                                       ? tiled_block_count(t_device.size(), elements_per_thread, launch_threads)
                                       : block_count(t_device.size());
                if (use_tiled)
                {
                    sawtooth_tiled_vector_kernel<<<blocks, launch_threads>>>(
                        t_device.data(),
                        width_device.data(),
                        t_device.size(),
                        output.data(),
                        elements_per_thread);
                }
                else
                {
                    sawtooth_vector_kernel<<<blocks, launch_threads>>>(
                        t_device.data(),
                        width_device.data(),
                        t_device.size(),
                        output.data());
                }
                check_kernel_launch("sawtooth_vector_kernel");
                return output;
            }

            core::ZxGpuRealSignal square(const core::RealSignalLike &t, float duty)
            {
                using namespace waveforms_detail;

                ensure_probability(duty, "duty");
                static thread_local ScalarWaveWorkspace workspace;
                const core::ZxGpuRealSignal &t_device = core::as_device_signal(t, workspace.t);
                if (t_device.empty())
                {
                    return core::ZxGpuRealSignal{};
                }

                core::ZxGpuRealSignal output(t_device.size());
                const tile::PolicyDecision tuning = tile::select(
                    tile::make_linear_operator_key("waveforms/square", t_device.size(), 0, 1));
                const tile::ScopedPolicy policy_scope(tuning);
                const int launch_threads = tuning.config.tile.threads;
                const bool use_tiled = tile::optimized_path() && t_device.size() >= 4096;
                const int elements_per_thread =
                    use_tiled ? tile::linear_shape(t_device.size()).elements_per_thread : 1;
                const int blocks = use_tiled
                                       ? tiled_block_count(t_device.size(), elements_per_thread, launch_threads)
                                       : block_count(t_device.size());
                if (use_tiled)
                {
                    square_tiled_scalar_kernel<<<blocks, launch_threads>>>(
                        t_device.data(),
                        t_device.size(),
                        duty,
                        output.data(),
                        elements_per_thread);
                }
                else
                {
                    square_scalar_kernel<<<blocks, launch_threads>>>(
                        t_device.data(), t_device.size(), duty, output.data());
                }
                check_kernel_launch("square_scalar_kernel");
                return output;
            }

            core::ZxGpuRealSignal square(
                const core::RealSignalLike &t,
                const core::RealSignalLike &duty)
            {
                using namespace waveforms_detail;

                if (const auto *host_t = std::get_if<core::RealSignal>(&t))
                {
                    if (const auto *host_duty = std::get_if<core::RealSignal>(&duty))
                    {
                        ensure_vector_parameter(*host_t, *host_duty, "duty");
                    }
                }

                static thread_local ScalarWaveWorkspace workspace;
                const core::ZxGpuRealSignal &t_device = core::as_device_signal(t, workspace.t);
                const core::ZxGpuRealSignal &duty_device =
                    core::as_device_signal(duty, workspace.param);
                if (t_device.size() != duty_device.size())
                {
                    throw std::invalid_argument("duty must have the same length as t");
                }
                if (t_device.empty())
                {
                    return core::ZxGpuRealSignal{};
                }

                core::ZxGpuRealSignal output(t_device.size());
                const tile::PolicyDecision tuning = tile::select(
                    tile::make_linear_operator_key("waveforms/square", t_device.size(), 0, 2));
                const tile::ScopedPolicy policy_scope(tuning);
                const int launch_threads = tuning.config.tile.threads;
                const bool use_tiled = tile::optimized_path() && t_device.size() >= 4096;
                const int elements_per_thread =
                    use_tiled ? tile::linear_shape(t_device.size()).elements_per_thread : 1;
                const int blocks = use_tiled
                                       ? tiled_block_count(t_device.size(), elements_per_thread, launch_threads)
                                       : block_count(t_device.size());
                if (use_tiled)
                {
                    square_tiled_vector_kernel<<<blocks, launch_threads>>>(
                        t_device.data(),
                        duty_device.data(),
                        t_device.size(),
                        output.data(),
                        elements_per_thread);
                }
                else
                {
                    square_vector_kernel<<<blocks, launch_threads>>>(
                        t_device.data(),
                        duty_device.data(),
                        t_device.size(),
                        output.data());
                }
                check_kernel_launch("square_vector_kernel");
                return output;
            }

            core::ZxGpuRealSignal unit_impulse(
                std::size_t size,
                std::size_t index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                validate_1d_index(size, index);

                if (size == 0)
                {
                    return core::ZxGpuRealSignal{};
                }

                core::ZxGpuRealSignal signal(size, true);
                set_impulse_kernel<<<1, 1>>>(signal.data(), index);
                check_kernel_launch("set_impulse_kernel");
                return signal;
            }

            core::ZxGpuRealSignal unit_impulse(
                std::size_t size,
                const std::string &index_spec,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                if (normalize_token(index_spec) != "mid")
                {
                    throw std::invalid_argument("index_spec must be mid");
                }
                return unit_impulse(size, size / 2, dtype);
            }

            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                const core::Shape origin = origin_index(shape);
                return unit_impulse(shape, origin, dtype);
            }

            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                std::size_t index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                const core::Shape nd_index = repeated_index(shape, index);
                validate_shape_index(shape, nd_index);

                const std::size_t element_count = core::shape_product(shape);
                waveforms_api::ZxGpuNdRealSignal result;
                result.shape = shape;
                result.values = core::make_zx_gpu_real_signal(element_count, 0.0);
                if (element_count == 0)
                {
                    return result;
                }

                set_impulse_kernel<<<1, 1>>>(
                    result.values.data(), flatten_index(shape, nd_index));
                check_kernel_launch("set_impulse_kernel nd");
                return result;
            }

            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                const core::Shape &index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                validate_shape_index(shape, index);

                const std::size_t element_count = core::shape_product(shape);
                waveforms_api::ZxGpuNdRealSignal result;
                result.shape = shape;
                result.values = core::make_zx_gpu_real_signal(element_count, 0.0);
                if (element_count == 0)
                {
                    return result;
                }

                set_impulse_kernel<<<1, 1>>>(
                    result.values.data(), flatten_index(shape, index));
                check_kernel_launch("set_impulse_kernel explicit nd");
                return result;
            }

            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                const char *index_spec,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                if (index_spec == nullptr)
                {
                    throw std::invalid_argument("index_spec must not be null");
                }
                if (normalize_token(index_spec) != "mid")
                {
                    throw std::invalid_argument("index_spec must be mid");
                }

                return unit_impulse(shape, mid_index(shape), dtype);
            }

        } // namespace waveforms
    } // namespace zx_gpu_backend
} // namespace cusignal
