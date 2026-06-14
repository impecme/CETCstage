#include "cusignal/waveforms/waveforms.hpp"

#include <cuda_runtime.h>

#include <complex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "../common/waveforms_detail.hpp"

namespace
{
    using cusignal::core::CudaComplexSignal;
    using cusignal::core::CudaRealSignal;
    using cusignal::core::RealSignal;

    constexpr int kThreadsPerBlock = 256;

    void throw_on_cuda_error(cudaError_t status, const char *what)
    {
        if (status != cudaSuccess)
        {
            throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
        }
    }

    void check_kernel_launch(const char *what)
    {
        throw_on_cuda_error(cudaGetLastError(), what);
    }

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    struct ChirpWorkspace
    {
        CudaRealSignal t;
    };

    struct GausspulseWorkspace
    {
        CudaRealSignal t;
    };

    struct ScalarWaveWorkspace
    {
        CudaRealSignal t;
        CudaRealSignal param;
    };

    __global__ void chirp_linear_real_kernel(
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

        const float phase = cusignal::waveforms_detail::linear_phase(t[index], f0, t1, f1);
        output[index] = cos(phase + phi);
    }

    __global__ void chirp_linear_complex_kernel(
        const float *t,
        std::size_t size,
        float f0,
        float t1,
        float f1,
        float phi,
        float2 *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float angle =
            cusignal::waveforms_detail::linear_phase(t[index], f0, t1, f1) + phi;
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

        signal[index] = cusignal::waveforms_detail::gausspulse_signal(t[index], a, fc);
        if (quadrature != nullptr)
        {
            quadrature[index] = cusignal::waveforms_detail::gausspulse_quadrature(t[index], a, fc);
        }
        if (envelope != nullptr)
        {
            envelope[index] = cusignal::waveforms_detail::gausspulse_envelope(t[index], a);
        }
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
} // namespace

namespace cusignal
{
    namespace cuda_backend
    {
        namespace waveforms
        {

            waveforms_api::CudaChirpResult chirp(
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
                const core::CudaRealSignal &t_device = core::as_device_signal(t, workspace.t);

                if (t_device.empty())
                {
                    if (normalized_type == "complex")
                    {
                        return core::CudaComplexSignal{};
                    }
                    return core::CudaRealSignal{};
                }

                const float phi_radians = degrees_to_radians(phi);
                const std::size_t size = t_device.size();
                const int blocks = block_count(size);

                if (normalized_type == "complex")
                {
                    core::CudaComplexSignal complex_output(size);
                    chirp_linear_complex_kernel<<<blocks, kThreadsPerBlock>>>(
                        t_device.data(),
                        size,
                        f0,
                        t1,
                        f1,
                        phi_radians,
                        complex_output.data());
                    check_kernel_launch("chirp_linear_complex_kernel");
                    return complex_output;
                }

                core::CudaRealSignal output(size);
                if (is_linear_method(normalized_method))
                {
                    chirp_linear_real_kernel<<<blocks, kThreadsPerBlock>>>(
                        t_device.data(),
                        size,
                        f0,
                        t1,
                        f1,
                        phi_radians,
                        output.data());
                    check_kernel_launch("chirp_linear_real_kernel");
                }
                else if (is_quadratic_method(normalized_method))
                {
                    chirp_quadratic_kernel<<<blocks, kThreadsPerBlock>>>(
                        t_device.data(),
                        size,
                        f0,
                        t1,
                        f1,
                        phi_radians,
                        vertex_zero,
                        output.data());
                    check_kernel_launch("chirp_quadratic_kernel");
                }
                else if (is_logarithmic_method(normalized_method))
                {
                    chirp_logarithmic_kernel<<<blocks, kThreadsPerBlock>>>(
                        t_device.data(),
                        size,
                        f0,
                        t1,
                        f1,
                        phi_radians,
                        output.data());
                    check_kernel_launch("chirp_logarithmic_kernel");
                }
                else
                {
                    chirp_hyperbolic_kernel<<<blocks, kThreadsPerBlock>>>(
                        t_device.data(),
                        size,
                        f0,
                        t1,
                        f1,
                        phi_radians,
                        output.data());
                    check_kernel_launch("chirp_hyperbolic_kernel");
                }

                return output;
            }

            waveforms_api::CudaGausspulseResult gausspulse(
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
                const core::CudaRealSignal &t_device = core::as_device_signal(t, workspace.t);
                const std::size_t size = t_device.size();

                if (size == 0)
                {
                    if (retquad && retenv)
                    {
                        return core::CudaWaveformBundle{};
                    }
                    if (retquad)
                    {
                        return waveforms_api::CudaIqWaveform{};
                    }
                    if (retenv)
                    {
                        return waveforms_api::CudaIEnvWaveform{};
                    }
                    return core::CudaRealSignal{};
                }

                core::CudaRealSignal signal(size);
                core::CudaRealSignal quadrature = retquad ? core::CudaRealSignal(size) : core::CudaRealSignal{};
                core::CudaRealSignal envelope = retenv ? core::CudaRealSignal(size) : core::CudaRealSignal{};

                gausspulse_kernel<<<block_count(size), kThreadsPerBlock>>>(
                    t_device.data(),
                    size,
                    a,
                    fc,
                    signal.data(),
                    retquad ? quadrature.data() : nullptr,
                    retenv ? envelope.data() : nullptr);
                check_kernel_launch("gausspulse_kernel");

                if (retquad && retenv)
                {
                    core::CudaWaveformBundle result;
                    result.signal = std::move(signal);
                    result.quadrature = std::move(quadrature);
                    result.envelope = std::move(envelope);
                    return result;
                }
                if (retquad)
                {
                    waveforms_api::CudaIqWaveform result;
                    result.signal = std::move(signal);
                    result.quadrature = std::move(quadrature);
                    return result;
                }
                if (retenv)
                {
                    waveforms_api::CudaIEnvWaveform result;
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

            core::CudaRealSignal sawtooth(const core::RealSignalLike &t, float width)
            {
                using namespace waveforms_detail;

                ensure_probability(width, "width");
                static thread_local ScalarWaveWorkspace workspace;
                const core::CudaRealSignal &t_device = core::as_device_signal(t, workspace.t);
                if (t_device.empty())
                {
                    return core::CudaRealSignal{};
                }

                core::CudaRealSignal output(t_device.size());
                sawtooth_scalar_kernel<<<block_count(t_device.size()), kThreadsPerBlock>>>(
                    t_device.data(), t_device.size(), width, output.data());
                check_kernel_launch("sawtooth_scalar_kernel");
                return output;
            }

            core::CudaRealSignal sawtooth(
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
                const core::CudaRealSignal &t_device = core::as_device_signal(t, workspace.t);
                const core::CudaRealSignal &width_device =
                    core::as_device_signal(width, workspace.param);
                if (t_device.size() != width_device.size())
                {
                    throw std::invalid_argument("width must have the same length as t");
                }
                if (t_device.empty())
                {
                    return core::CudaRealSignal{};
                }

                core::CudaRealSignal output(t_device.size());
                sawtooth_vector_kernel<<<block_count(t_device.size()), kThreadsPerBlock>>>(
                    t_device.data(), width_device.data(), t_device.size(), output.data());
                check_kernel_launch("sawtooth_vector_kernel");
                return output;
            }

            core::CudaRealSignal square(const core::RealSignalLike &t, float duty)
            {
                using namespace waveforms_detail;

                ensure_probability(duty, "duty");
                static thread_local ScalarWaveWorkspace workspace;
                const core::CudaRealSignal &t_device = core::as_device_signal(t, workspace.t);
                if (t_device.empty())
                {
                    return core::CudaRealSignal{};
                }

                core::CudaRealSignal output(t_device.size());
                square_scalar_kernel<<<block_count(t_device.size()), kThreadsPerBlock>>>(
                    t_device.data(), t_device.size(), duty, output.data());
                check_kernel_launch("square_scalar_kernel");
                return output;
            }

            core::CudaRealSignal square(
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
                const core::CudaRealSignal &t_device = core::as_device_signal(t, workspace.t);
                const core::CudaRealSignal &duty_device =
                    core::as_device_signal(duty, workspace.param);
                if (t_device.size() != duty_device.size())
                {
                    throw std::invalid_argument("duty must have the same length as t");
                }
                if (t_device.empty())
                {
                    return core::CudaRealSignal{};
                }

                core::CudaRealSignal output(t_device.size());
                square_vector_kernel<<<block_count(t_device.size()), kThreadsPerBlock>>>(
                    t_device.data(), duty_device.data(), t_device.size(), output.data());
                check_kernel_launch("square_vector_kernel");
                return output;
            }

            core::CudaRealSignal unit_impulse(
                std::size_t size,
                std::size_t index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                validate_1d_index(size, index);

                if (size == 0)
                {
                    return core::CudaRealSignal{};
                }

                core::CudaRealSignal signal(size, true);
                set_impulse_kernel<<<1, 1>>>(signal.data(), index);
                check_kernel_launch("set_impulse_kernel");
                return signal;
            }

            core::CudaRealSignal unit_impulse(
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

            waveforms_api::CudaNdRealSignal unit_impulse(
                const core::Shape &shape,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                const core::Shape origin = origin_index(shape);
                return unit_impulse(shape, origin, dtype);
            }

            waveforms_api::CudaNdRealSignal unit_impulse(
                const core::Shape &shape,
                std::size_t index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                const core::Shape nd_index = repeated_index(shape, index);
                validate_shape_index(shape, nd_index);

                const std::size_t element_count = core::shape_product(shape);
                waveforms_api::CudaNdRealSignal result;
                result.shape = shape;
                result.values = core::make_cuda_real_signal(element_count, 0.0);
                if (element_count == 0)
                {
                    return result;
                }

                set_impulse_kernel<<<1, 1>>>(
                    result.values.data(), flatten_index(shape, nd_index));
                check_kernel_launch("set_impulse_kernel nd");
                return result;
            }

            waveforms_api::CudaNdRealSignal unit_impulse(
                const core::Shape &shape,
                const core::Shape &index,
                const std::string &dtype)
            {
                using namespace waveforms_detail;

                ensure_float32(dtype);
                validate_shape_index(shape, index);

                const std::size_t element_count = core::shape_product(shape);
                waveforms_api::CudaNdRealSignal result;
                result.shape = shape;
                result.values = core::make_cuda_real_signal(element_count, 0.0);
                if (element_count == 0)
                {
                    return result;
                }

                set_impulse_kernel<<<1, 1>>>(
                    result.values.data(), flatten_index(shape, index));
                check_kernel_launch("set_impulse_kernel explicit nd");
                return result;
            }

            waveforms_api::CudaNdRealSignal unit_impulse(
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
    } // namespace cuda_backend
} // namespace cusignal
