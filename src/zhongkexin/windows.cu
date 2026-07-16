#include "cusignal/windows/windows.hpp"

#include <cuda_runtime.h>
#include <cufft.h>

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "../common/windows_detail.hpp"

namespace
{
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    using cusignal::core::NamedFloatPairParameter;
    using cusignal::core::NamedFloatParameter;
    using cusignal::core::NamedTaylorParameter;
    using cusignal::core::RealSignal;
    namespace detail = cusignal::windows_detail;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0;

    bool needs_parameter(const std::string &canonical_name)
    {
        return canonical_name == "chebwin" || canonical_name == "gaussian" ||
               canonical_name == "general_gaussian" || canonical_name == "general_hamming" ||
               canonical_name == "kaiser" || canonical_name == "taylor" ||
               canonical_name == "tukey" || canonical_name == "exponential";
    }

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
    class DeviceBuffer
    {
    public:
        DeviceBuffer() = default;

        ~DeviceBuffer()
        {
            release();
        }

        DeviceBuffer(const DeviceBuffer &) = delete;
        DeviceBuffer &operator=(const DeviceBuffer &) = delete;

        void reserve(std::size_t size)
        {
            if (size <= size_)
            {
                return;
            }

            release();
            size_ = size;
            if (size_ == 0)
            {
                return;
            }
            throw_on_zx_gpu_error(cudaMalloc(&data_, size_ * sizeof(T)), "cudaMalloc");
        }

        void copy_from_host(const T *host, std::size_t count, const char *what)
        {
            if (count == 0)
            {
                return;
            }
            reserve(count);
            throw_on_zx_gpu_error(
                cudaMemcpy(data_, host, count * sizeof(T), cudaMemcpyHostToDevice),
                what);
        }

        std::vector<T> copy_to_host(std::size_t count, const char *what) const
        {
            std::vector<T> host(count);
            if (count == 0)
            {
                return host;
            }
            throw_on_zx_gpu_error(
                cudaMemcpy(host.data(), data_, count * sizeof(T), cudaMemcpyDeviceToHost),
                what);
            return host;
        }

        T *get()
        {
            return data_;
        }

        const T *get() const
        {
            return data_;
        }

    private:
        void release()
        {
            if (data_ != nullptr)
            {
                cudaFree(data_);
                data_ = nullptr;
            }
            size_ = 0;
        }

        T *data_ = nullptr;
        std::size_t size_ = 0;
    };

    struct WindowWorkspace
    {
        DeviceBuffer<float> output;
        DeviceBuffer<float> coefficients;
        DeviceBuffer<float> max_value;
        DeviceBuffer<float> reduce_block_max;
        DeviceBuffer<cufftComplex> spectrum;
        DeviceBuffer<cufftComplex> spectrum_template;
        DeviceBuffer<float> chebwin_final_template;
        cufftHandle chebwin_plan = 0;
        int chebwin_plan_size = 0;
        int chebwin_template_size = 0;
        float chebwin_template_at = 0.0f;
        bool chebwin_template_sym = false;
        bool chebwin_template_valid = false;
        int chebwin_final_size = 0;
        float chebwin_final_at = 0.0f;
        bool chebwin_final_sym = false;
        bool chebwin_final_valid = false;
        std::size_t reduce_storage_bytes = 0;
        std::size_t reduce_item_count = 0;

        ~WindowWorkspace()
        {
            if (chebwin_plan != 0)
            {
                cufftDestroy(chebwin_plan);
            }
        }

        void ensure_plan(int size)
        {
            if (chebwin_plan != 0 && chebwin_plan_size == size)
            {
                return;
            }
            if (chebwin_plan != 0)
            {
                throw_on_cufft_error(cufftDestroy(chebwin_plan), "cufftDestroy");
                chebwin_plan = 0;
                chebwin_plan_size = 0;
            }
            throw_on_cufft_error(cufftPlan1d(&chebwin_plan, size, CUFFT_C2C, 1), "cufftPlan1d");
            chebwin_plan_size = size;
        }

        void ensure_reduce_storage(std::size_t item_count)
        {
            max_value.reserve(1);
            if (item_count == reduce_item_count && reduce_storage_bytes != 0)
            {
                return;
            }

            const std::size_t block_items =
                item_count == 0 ? 0 : (item_count + kThreadsPerBlock - 1) / kThreadsPerBlock;
            reduce_block_max.reserve(block_items);
            reduce_storage_bytes = block_items * sizeof(float);
            reduce_item_count = item_count;
        }
    };

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    class ScopedZxGpuEvents
    {
    public:
        ScopedZxGpuEvents()
        {
            throw_on_zx_gpu_error(cudaEventCreate(&start_), "cudaEventCreate(start)");
            throw_on_zx_gpu_error(cudaEventCreate(&stop_), "cudaEventCreate(stop)");
        }

        ~ScopedZxGpuEvents()
        {
            if (start_ != nullptr)
            {
                cudaEventDestroy(start_);
            }
            if (stop_ != nullptr)
            {
                cudaEventDestroy(stop_);
            }
        }

        ScopedZxGpuEvents(const ScopedZxGpuEvents &) = delete;
        ScopedZxGpuEvents &operator=(const ScopedZxGpuEvents &) = delete;

        template <typename Callable>
        float measure(Callable callable)
        {
            throw_on_zx_gpu_error(cudaEventRecord(start_), "cudaEventRecord(start)");
            callable();
            throw_on_zx_gpu_error(cudaEventRecord(stop_), "cudaEventRecord(stop)");
            throw_on_zx_gpu_error(cudaEventSynchronize(stop_), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            throw_on_zx_gpu_error(
                cudaEventElapsedTime(&elapsed_ms, start_, stop_),
                "cudaEventElapsedTime");
            return elapsed_ms;
        }

    private:
        cudaEvent_t start_ = nullptr;
        cudaEvent_t stop_ = nullptr;
    };

    __device__ float general_cosine_value_fast(
        int index,
        int size,
        const float *coefficients,
        int coefficient_count)
    {
        constexpr float kPiF = 3.14159265358979323846f;
        if (size <= 1)
        {
            return 1.0f;
        }

        const float delta = (2.0f * kPiF) / static_cast<float>(size - 1);
        const float angle = -kPiF + delta * static_cast<float>(index);
        float value = 0.0f;
        for (int coefficient_index = 0; coefficient_index < coefficient_count; ++coefficient_index)
        {
            value += coefficients[coefficient_index] *
                     cosf(static_cast<float>(coefficient_index) * angle);
        }
        return value;
    }

    __device__ float taylor_value_fast(
        int index,
        int size,
        int nbar,
        const float *coefficients,
        int coefficient_count,
        float scale)
    {
        constexpr float kPiF = 3.14159265358979323846f;
        const float angle =
            (2.0f * kPiF / static_cast<float>(size)) *
            (static_cast<float>(index) - static_cast<float>(size) * 0.5f + 0.5f);

        float value = 1.0f;
        for (int coefficient_index = 0; coefficient_index < coefficient_count; ++coefficient_index)
        {
            const int harmonic = coefficient_index + 1;
            if (harmonic >= nbar)
            {
                break;
            }
            value += 2.0f * coefficients[coefficient_index] *
                     cosf(angle * static_cast<float>(harmonic));
        }
        return value * scale;
    }

    __device__ float compute_window_value(
        detail::KernelOp op,
        int index,
        int size,
        const float *coefficients,
        int coefficient_count,
        float parameter0,
        float parameter1,
        float parameter2,
        int int_parameter)
    {
        switch (op)
        {
        case detail::KernelOp::kBoxcar:
            return 1.0;
        case detail::KernelOp::kGeneralCosine:
            return general_cosine_value_fast(index, size, coefficients, coefficient_count);
        case detail::KernelOp::kTriang:
            return detail::triang_value(index, size);
        case detail::KernelOp::kBartlett:
            return detail::bartlett_value(index, size);
        case detail::KernelOp::kParzen:
            return detail::parzen_value(index, size);
        case detail::KernelOp::kBohman:
            return detail::bohman_value(index, size);
        case detail::KernelOp::kBarthann:
            return detail::barthann_value(index, size);
        case detail::KernelOp::kCosine:
            return detail::cosine_value(index, size);
        case detail::KernelOp::kTukey:
            return detail::tukey_value(index, size, parameter0);
        case detail::KernelOp::kKaiser:
            return detail::kaiser_value(index, size, parameter0);
        case detail::KernelOp::kGaussian:
            return detail::gaussian_value(index, size, parameter0);
        case detail::KernelOp::kGeneralGaussian:
            return detail::general_gaussian_value(index, size, parameter0, parameter1);
        case detail::KernelOp::kExponential:
            return detail::exponential_value(index, parameter0, parameter1);
        case detail::KernelOp::kTaylor:
            return taylor_value_fast(
                index,
                size,
                int_parameter,
                coefficients,
                coefficient_count,
                parameter0);
        }
        return parameter2;
    }

    __global__ void fill_window_kernel(
        detail::KernelOp op,
        int size,
        const float *coefficients,
        int coefficient_count,
        float parameter0,
        float parameter1,
        float parameter2,
        int int_parameter,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        output[static_cast<std::size_t>(index)] = compute_window_value(
            op,
            index,
            size,
            coefficients,
            coefficient_count,
            parameter0,
            parameter1,
            parameter2,
                int_parameter);
    }

    __global__ void fill_kaiser_symmetric_kernel(
        int output_size,
        int effective_size,
        float beta,
        float inv_i0_beta,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        const int half_count = (effective_size + 1) / 2;
        if (index >= half_count)
        {
            return;
        }

        float value = 1.0f;
        if (effective_size > 1)
        {
            const float alpha = 0.5f * static_cast<float>(effective_size - 1);
            const float temp = (static_cast<float>(index) - alpha) / alpha;
            const float inside = fmaxf(0.0f, 1.0f - temp * temp);
            value = detail::bessel_i0(beta * sqrtf(inside)) * inv_i0_beta;
        }

        if (index < output_size)
        {
            output[static_cast<std::size_t>(index)] = value;
        }
        const int mirror_index = effective_size - 1 - index;
        if (mirror_index != index && mirror_index < output_size)
        {
            output[static_cast<std::size_t>(mirror_index)] = value;
        }
    }

    __global__ void fill_constant_kernel(float *output, std::size_t size, float value)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        output[index] = value;
    }

    __global__ void copy_window_output_kernel(
        const float *source,
        std::size_t size,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        output[index] = source[index];
    }

    __device__ inline float triang_fast_value(int index, int effective_size)
    {
        const int midpoint = effective_size / 2;
        const bool odd = (effective_size & 1) != 0;
        const int n = index < midpoint ? index + 1 : effective_size - index;
        if (odd)
        {
            return 2.0f * static_cast<float>(n) /
                   (static_cast<float>(effective_size) + 1.0f);
        }
        return (2.0f * static_cast<float>(n) - 1.0f) /
               static_cast<float>(effective_size);
    }

    __global__ void fill_triang_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }

        output[static_cast<std::size_t>(index)] =
            triang_fast_value(index, effective_size);
    }

    __global__ void fill_triang_symmetric_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        const int half_count = (effective_size + 1) / 2;
        if (index >= half_count)
        {
            return;
        }

        const float value = triang_fast_value(index, effective_size);
        if (index < output_size)
        {
            output[static_cast<std::size_t>(index)] = value;
        }
        const int mirror_index = effective_size - 1 - index;
        if (mirror_index != index && mirror_index < output_size)
        {
            output[static_cast<std::size_t>(mirror_index)] = value;
        }
    }

    __device__ inline float parzen_fast_value(
        int index,
        int effective_size)
    {
        const float half = 0.5f * static_cast<float>(effective_size);
        const float n = fabsf(
            static_cast<float>(index) - 0.5f * static_cast<float>(effective_size - 1));
        const float ratio = n / half;
        if (ratio <= 0.5f)
        {
            return 1.0f - 6.0f * ratio * ratio + 6.0f * ratio * ratio * ratio;
        }
        if (ratio <= 1.0f)
        {
            const float inner = 1.0f - ratio;
            return 2.0f * inner * inner * inner;
        }
        return 0.0f;
    }

    __global__ void fill_parzen_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        if (effective_size <= 1)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
            return;
        }

        output[static_cast<std::size_t>(index)] =
            parzen_fast_value(index, effective_size);
    }

    __global__ void fill_parzen_symmetric_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        const int half_count = (effective_size + 1) / 2;
        if (index >= half_count)
        {
            return;
        }

        const float value = parzen_fast_value(index, effective_size);
        if (index < output_size)
        {
            output[static_cast<std::size_t>(index)] = value;
        }
        const int mirror_index = effective_size - 1 - index;
        if (mirror_index != index && mirror_index < output_size)
        {
            output[static_cast<std::size_t>(mirror_index)] = value;
        }
    }

    __global__ void fill_boxcar_fast_kernel(int output_size, float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < output_size)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
        }
    }

    __global__ void fill_cosine_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        constexpr float kPiF = 3.14159265358979323846f;
        output[static_cast<std::size_t>(index)] =
            sinf(kPiF * (static_cast<float>(index) + 0.5f) / static_cast<float>(effective_size));
    }

    __global__ void fill_bartlett_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        if (effective_size <= 1)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
            return;
        }

        const float normalized =
            static_cast<float>(index) / static_cast<float>(effective_size - 1);
        const float value = index <= (effective_size - 1) / 2
                                ? 2.0f * normalized
                                : 2.0f - 2.0f * normalized;
        output[static_cast<std::size_t>(index)] = value;
    }

    __global__ void fill_barthann_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        if (effective_size <= 1)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
            return;
        }

        constexpr float kPiF = 3.14159265358979323846f;
        const float factor =
            fabsf(static_cast<float>(index) / static_cast<float>(effective_size - 1) - 0.5f);
        output[static_cast<std::size_t>(index)] =
            0.62f - 0.48f * factor + 0.38f * cosf(2.0f * kPiF * factor);
    }

    __global__ void fill_bohman_fast_kernel(
        int output_size,
        int effective_size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        if (effective_size <= 1)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
            return;
        }
        if (index == 0 || index == effective_size - 1)
        {
            output[static_cast<std::size_t>(index)] = 0.0f;
            return;
        }

        constexpr float kPiF = 3.14159265358979323846f;
        const float factor =
            fabsf((2.0f * static_cast<float>(index) /
                   static_cast<float>(effective_size - 1)) -
                  1.0f);
        output[static_cast<std::size_t>(index)] =
            (1.0f - factor) * cosf(kPiF * factor) + sinf(kPiF * factor) / kPiF;
    }

    __global__ void fill_tukey_fast_kernel(
        int output_size,
        int effective_size,
        float alpha,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        if (effective_size <= 1 || alpha <= 0.0f)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
            return;
        }

        constexpr float kPiF = 3.14159265358979323846f;
        if (alpha >= 1.0f)
        {
            const float delta = (2.0f * kPiF) / static_cast<float>(effective_size - 1);
            const float angle = -kPiF + delta * static_cast<float>(index);
            output[static_cast<std::size_t>(index)] = 0.5f + 0.5f * cosf(angle);
            return;
        }

        const float normalized =
            static_cast<float>(index) / static_cast<float>(effective_size - 1);
        const float edge = alpha * 0.5f;
        float value = 1.0f;
        if (normalized < edge)
        {
            value = 0.5f * (1.0f + cosf(kPiF * ((2.0f * normalized / alpha) - 1.0f)));
        }
        else if (normalized > (1.0f - edge))
        {
            value = 0.5f *
                    (1.0f + cosf(kPiF * ((2.0f * normalized / alpha) -
                                         (2.0f / alpha) + 1.0f)));
        }
        output[static_cast<std::size_t>(index)] = value;
    }

    __global__ void fill_gaussian_fast_kernel(
        int output_size,
        int effective_size,
        float stddev,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }

        const float n =
            static_cast<float>(index) - 0.5f * static_cast<float>(effective_size - 1);
        const float sigma2 = 2.0f * stddev * stddev;
        output[static_cast<std::size_t>(index)] = expf(-(n * n) / sigma2);
    }

    __global__ void fill_exponential_fast_kernel(
        int output_size,
        float center,
        float tau,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }

        output[static_cast<std::size_t>(index)] =
            expf(-fabsf(static_cast<float>(index) - center) / tau);
    }

    __global__ void fill_general_cosine_two_coeff_fast_kernel(
        int output_size,
        int effective_size,
        float coefficient0,
        float coefficient1,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        if (effective_size <= 1)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
            return;
        }

        constexpr float kPiF = 3.14159265358979323846f;
        const float delta = (2.0f * kPiF) / static_cast<float>(effective_size - 1);
        const float angle = -kPiF + delta * static_cast<float>(index);
        output[static_cast<std::size_t>(index)] = coefficient0 + coefficient1 * cosf(angle);
    }

    __global__ void fill_hamming_exact_pair_kernel(
        int output_size,
        int effective_size,
        float coefficient0,
        float coefficient1,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        const int half_count = (effective_size + 1) / 2;
        if (index >= half_count)
        {
            return;
        }

        constexpr float kPiF = 3.14159265358979323846f;
        const float delta = (2.0f * kPiF) / static_cast<float>(effective_size - 1);
        const float left_angle = -kPiF + delta * static_cast<float>(index);
        const float left_value = coefficient0 + coefficient1 * cosf(left_angle);
        if (index < output_size)
        {
            output[static_cast<std::size_t>(index)] = left_value;
        }

        const int mirror_index = effective_size - 1 - index;
        if (mirror_index != index && mirror_index < output_size)
        {
            const float right_angle =
                -kPiF + delta * static_cast<float>(mirror_index);
            output[static_cast<std::size_t>(mirror_index)] =
                right_angle == -left_angle
                    ? left_value
                    : coefficient0 + coefficient1 * cosf(right_angle);
        }
    }

    __global__ void fill_general_cosine_fixed_coeff_fast_kernel(
        int output_size,
        int effective_size,
        int coefficient_count,
        float coefficient0,
        float coefficient1,
        float coefficient2,
        float coefficient3,
        float coefficient4,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }
        if (effective_size <= 1)
        {
            output[static_cast<std::size_t>(index)] = 1.0f;
            return;
        }

        constexpr float kPiF = 3.14159265358979323846f;
        const float delta = (2.0f * kPiF) / static_cast<float>(effective_size - 1);
        const float angle = -kPiF + delta * static_cast<float>(index);
        float value = coefficient0;
        if (coefficient_count > 1)
        {
            const float cosine = cosf(angle);
            float previous_harmonic = 1.0f;
            float harmonic = cosine;
            value += coefficient1 * harmonic;
            if (coefficient_count > 2)
            {
                const float next_harmonic =
                    2.0f * cosine * harmonic - previous_harmonic;
                previous_harmonic = harmonic;
                harmonic = next_harmonic;
                value += coefficient2 * harmonic;
            }
            if (coefficient_count > 3)
            {
                const float next_harmonic =
                    2.0f * cosine * harmonic - previous_harmonic;
                previous_harmonic = harmonic;
                harmonic = next_harmonic;
                value += coefficient3 * harmonic;
            }
            if (coefficient_count > 4)
            {
                const float next_harmonic =
                    2.0f * cosine * harmonic - previous_harmonic;
                value += coefficient4 * next_harmonic;
            }
        }
        output[static_cast<std::size_t>(index)] = value;
    }

    __device__ inline float general_gaussian_value(
        int index,
        int effective_size,
        float sig,
        int power_mode)
    {
        const float center = 0.5f * static_cast<float>(effective_size - 1);
        const float x = fabsf((static_cast<float>(index) - center) / sig);
        const float x2 = x * x;
        float powered = x2;
        switch (power_mode)
        {
        case 1:
            powered = x;
            break;
        case 2:
            powered = x2;
            break;
        case 3:
            powered = x2 * x;
            break;
        case 35:
            powered = x2 * x * sqrtf(x);
            break;
        case 4:
            powered = x2 * x2;
            break;
        default:
            break;
        }
        return expf(-0.5f * powered);
    }

    __global__ void fill_general_gaussian_fast_kernel(
        int output_size,
        int effective_size,
        float sig,
        int power_mode,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }

        output[static_cast<std::size_t>(index)] =
            general_gaussian_value(index, effective_size, sig, power_mode);
    }

    __global__ void fill_general_gaussian_symmetric_fast_kernel(
        int output_size,
        int effective_size,
        float sig,
        int power_mode,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        const int half_count = (effective_size + 1) / 2;
        if (index >= half_count)
        {
            return;
        }

        const float value =
            general_gaussian_value(index, effective_size, sig, power_mode);
        if (index < output_size)
        {
            output[static_cast<std::size_t>(index)] = value;
        }
        const int mirror_index = effective_size - 1 - index;
        if (mirror_index != index && mirror_index < output_size)
        {
            output[static_cast<std::size_t>(mirror_index)] = value;
        }
    }

    __global__ void fill_taylor_fixed_coeff_fast_kernel(
        int output_size,
        int effective_size,
        int coefficient_count,
        float coefficient0,
        float coefficient1,
        float coefficient2,
        float coefficient3,
        float coefficient4,
        float coefficient5,
        float coefficient6,
        float coefficient7,
        float scale,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }

        constexpr float kPiF = 3.14159265358979323846f;
        const float angle =
            (2.0f * kPiF / static_cast<float>(effective_size)) *
            (static_cast<float>(index) - static_cast<float>(effective_size) * 0.5f + 0.5f);
        float value = 1.0f;
        const float cosine = cosf(angle);
        float previous_harmonic = 1.0f;
        float harmonic = cosine;
        if (coefficient_count > 0)
        {
            value += 2.0f * coefficient0 * harmonic;
        }
        if (coefficient_count > 1)
        {
            const float next_harmonic = 2.0f * cosine * harmonic - previous_harmonic;
            previous_harmonic = harmonic;
            harmonic = next_harmonic;
            value += 2.0f * coefficient1 * harmonic;
        }
        if (coefficient_count > 2)
        {
            const float next_harmonic = 2.0f * cosine * harmonic - previous_harmonic;
            previous_harmonic = harmonic;
            harmonic = next_harmonic;
            value += 2.0f * coefficient2 * harmonic;
        }
        if (coefficient_count > 3)
        {
            const float next_harmonic = 2.0f * cosine * harmonic - previous_harmonic;
            previous_harmonic = harmonic;
            harmonic = next_harmonic;
            value += 2.0f * coefficient3 * harmonic;
        }
        if (coefficient_count > 4)
        {
            const float next_harmonic = 2.0f * cosine * harmonic - previous_harmonic;
            previous_harmonic = harmonic;
            harmonic = next_harmonic;
            value += 2.0f * coefficient4 * harmonic;
        }
        if (coefficient_count > 5)
        {
            const float next_harmonic = 2.0f * cosine * harmonic - previous_harmonic;
            previous_harmonic = harmonic;
            harmonic = next_harmonic;
            value += 2.0f * coefficient5 * harmonic;
        }
        if (coefficient_count > 6)
        {
            const float next_harmonic = 2.0f * cosine * harmonic - previous_harmonic;
            previous_harmonic = harmonic;
            harmonic = next_harmonic;
            value += 2.0f * coefficient6 * harmonic;
        }
        if (coefficient_count > 7)
        {
            const float next_harmonic = 2.0f * cosine * harmonic - previous_harmonic;
            harmonic = next_harmonic;
            value += 2.0f * coefficient7 * harmonic;
        }
        output[static_cast<std::size_t>(index)] = value * scale;
    }

    __global__ void build_chebwin_frequency_response_kernel(
        cufftComplex *values,
        int size,
        float at)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float order = static_cast<float>(size - 1);
        const float beta = static_cast<float>(
            cosh(acosh(pow(10.0, fabs(static_cast<double>(at)) / 20.0)) /
                 static_cast<double>(order)));
        const bool odd = (size & 1) != 0;
        const float step = detail::kPi / static_cast<float>(size);
        const float x = beta * cosf(static_cast<float>(index) * step);

        float real = 0.0f;
        if (x > 1.0f)
        {
            real = coshf(order * acoshf(x));
        }
        else if (x < -1.0f)
        {
            real = (odd ? 1.0f : -1.0f) * coshf(order * acoshf(-x));
        }
        else
        {
            real = cosf(order * acosf(x));
        }

        if (odd)
        {
            values[index] = cufftComplex{real, 0.0f};
        }
        else
        {
            const float phase = step * static_cast<float>(index);
            values[index] = cufftComplex{
                real * cosf(phase),
                real * sinf(phase)};
        }
    }

    __global__ void rebuild_chebwin_from_fft_kernel(
        const cufftComplex *values,
        int size,
        float *output)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const bool odd = (size & 1) != 0;
        int source_index = 0;
        if (odd)
        {
            const int half = (size + 1) / 2;
            source_index = index < (half - 1) ? (half - 1 - index) : (index - (half - 1));
        }
        else
        {
            const int half = size / 2 + 1;
            source_index = index < (half - 1) ? (half - 1 - index) : (1 + index - (half - 1));
        }

        output[static_cast<std::size_t>(index)] = values[source_index].x;
    }

    __global__ void normalize_window_kernel(
        float *values,
        std::size_t size,
        const float *max_value)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }

        const float scale = max_value[0] > 0.0 ? max_value[0] : 1.0;
        values[index] /= scale;
    }

    __global__ void reduce_max_stage1_kernel(
        const float *values,
        std::size_t size,
        float *block_max)
    {
        __shared__ float shared[kThreadsPerBlock];
        const unsigned int tid = threadIdx.x;
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + tid;
        shared[tid] = index < size ? values[index] : -3.402823466e+38F;
        __syncthreads();

        for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                shared[tid] = fmaxf(shared[tid], shared[tid + stride]);
            }
            __syncthreads();
        }
        if (tid == 0)
        {
            block_max[blockIdx.x] = shared[0];
        }
    }

    __global__ void reduce_max_stage2_kernel(
        const float *block_max,
        std::size_t block_count_value,
        float *max_value)
    {
        __shared__ float shared[kThreadsPerBlock];
        const unsigned int tid = threadIdx.x;
        float value = -3.402823466e+38F;
        for (std::size_t index = tid; index < block_count_value; index += blockDim.x)
        {
            value = fmaxf(value, block_max[index]);
        }
        shared[tid] = value;
        __syncthreads();

        for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                shared[tid] = fmaxf(shared[tid], shared[tid + stride]);
            }
            __syncthreads();
        }
        if (tid == 0)
        {
            max_value[0] = shared[0];
        }
    }

    void reduce_max_window(WindowWorkspace &workspace, std::size_t item_count)
    {
        const int blocks = block_count(item_count);
        reduce_max_stage1_kernel<<<blocks, kThreadsPerBlock>>>(
            workspace.output.get(),
            item_count,
            workspace.reduce_block_max.get());
        check_kernel_launch("reduce_max_stage1_kernel");
        reduce_max_stage2_kernel<<<1, kThreadsPerBlock>>>(
            workspace.reduce_block_max.get(),
            static_cast<std::size_t>(blocks),
            workspace.max_value.get());
        check_kernel_launch("reduce_max_stage2_kernel");
    }

    ZxGpuRealSignal make_trivial_window_signal(int size)
    {
        g_last_kernel_ms = 0.0;
        if (size <= 0)
        {
            return {};
        }

        ZxGpuRealSignal result(static_cast<std::size_t>(size));
        fill_constant_kernel<<<1, 1>>>(result.data(), static_cast<std::size_t>(size), 1.0);
        check_kernel_launch("fill_constant_kernel");
        return result;
    }

    ZxGpuRealSignal launch_window_kernel_impl(
        detail::KernelOp op,
        int size,
        bool sym,
        const RealSignal *host_coefficients,
        const float *device_coefficients,
        int coefficient_count,
        float parameter0 = 0.0,
        float parameter1 = 0.0,
        float parameter2 = 0.0,
        int int_parameter = 0)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        static thread_local WindowWorkspace workspace;
        workspace.output.reserve(static_cast<std::size_t>(extended.size));
        ZxGpuRealSignal result(static_cast<std::size_t>(size));

        const float *resolved_coefficients = device_coefficients;
        int resolved_count = coefficient_count;
        if (host_coefficients != nullptr && !host_coefficients->empty())
        {
            workspace.coefficients.copy_from_host(
                host_coefficients->data(),
                host_coefficients->size(),
                "cudaMemcpy H2D window coefficients");
            resolved_coefficients = workspace.coefficients.get();
            resolved_count = static_cast<int>(host_coefficients->size());
        }

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_window_kernel<<<block_count(static_cast<std::size_t>(extended.size)), kThreadsPerBlock>>>(
                op,
                extended.size,
                resolved_coefficients,
                resolved_count,
                parameter0,
                parameter1,
                parameter2,
                int_parameter,
                workspace.output.get());
            check_kernel_launch("fill_window_kernel");

            copy_window_output_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                workspace.output.get(),
                static_cast<std::size_t>(size),
                result.data());
            check_kernel_launch("copy_window_output_kernel");
        }));

        return result;
    }

    ZxGpuRealSignal launch_window_kernel(
        detail::KernelOp op,
        int size,
        bool sym,
        float parameter0 = 0.0,
        float parameter1 = 0.0,
        float parameter2 = 0.0,
        int int_parameter = 0)
    {
        return launch_window_kernel_impl(
            op,
            size,
            sym,
            nullptr,
            nullptr,
            0,
            parameter0,
            parameter1,
            parameter2,
            int_parameter);
    }

    ZxGpuRealSignal triang_fast(int size, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            constexpr int kSymmetricKernelThreshold = 2 * kThreadsPerBlock;
            if (extended.size >= kSymmetricKernelThreshold)
            {
                const std::size_t half_count =
                    static_cast<std::size_t>((extended.size + 1) / 2);
                fill_triang_symmetric_fast_kernel<<<
                    block_count(half_count),
                    kThreadsPerBlock>>>(
                    size,
                    extended.size,
                    result.data());
                check_kernel_launch("fill_triang_symmetric_fast_kernel");
            }
            else
            {
                fill_triang_fast_kernel<<<
                    block_count(static_cast<std::size_t>(size)),
                    kThreadsPerBlock>>>(
                    size,
                    extended.size,
                    result.data());
                check_kernel_launch("fill_triang_fast_kernel");
            }
        }));
        return result;
    }

    ZxGpuRealSignal parzen_fast(int size, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            constexpr int kMaxExactFloatInteger = 1 << 24;
            if (extended.size - 1 <= kMaxExactFloatInteger)
            {
                const std::size_t half_count =
                    static_cast<std::size_t>((extended.size + 1) / 2);
                fill_parzen_symmetric_fast_kernel<<<
                    block_count(half_count),
                    kThreadsPerBlock>>>(
                    size,
                    extended.size,
                    result.data());
                check_kernel_launch("fill_parzen_symmetric_fast_kernel");
            }
            else
            {
                fill_parzen_fast_kernel<<<
                    block_count(static_cast<std::size_t>(size)),
                    kThreadsPerBlock>>>(
                    size,
                    extended.size,
                    result.data());
                check_kernel_launch("fill_parzen_fast_kernel");
            }
        }));
        return result;
    }

    ZxGpuRealSignal boxcar_fast(int size)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_boxcar_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                result.data());
            check_kernel_launch("fill_boxcar_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal cosine_fast(int size, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_cosine_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                extended.size,
                result.data());
            check_kernel_launch("fill_cosine_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal bartlett_fast(int size, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_bartlett_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                extended.size,
                result.data());
            check_kernel_launch("fill_bartlett_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal barthann_fast(int size, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_barthann_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                extended.size,
                result.data());
            check_kernel_launch("fill_barthann_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal bohman_fast(int size, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_bohman_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                extended.size,
                result.data());
            check_kernel_launch("fill_bohman_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal tukey_fast(int size, float alpha, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_tukey_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                extended.size,
                alpha,
                result.data());
            check_kernel_launch("fill_tukey_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal gaussian_fast(int size, float stddev, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_gaussian_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                extended.size,
                stddev,
                result.data());
            check_kernel_launch("fill_gaussian_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal exponential_fast(int size, float center, float tau)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_exponential_fast_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                size,
                center,
                tau,
                result.data());
            check_kernel_launch("fill_exponential_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal general_cosine_two_coeff_fast(
        int size,
        bool sym,
        float coefficient0,
        float coefficient1)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_general_cosine_two_coeff_fast_kernel<<<
                block_count(static_cast<std::size_t>(size)),
                kThreadsPerBlock>>>(
                size,
                extended.size,
                coefficient0,
                coefficient1,
                result.data());
            check_kernel_launch("fill_general_cosine_two_coeff_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal hamming_exact_pair_fast(int size, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        constexpr float kAlpha = 0.54f;
        const float coefficient1 = 1.0f - kAlpha;
        if (extended.size - 1 > (1 << 24))
        {
            return general_cosine_two_coeff_fast(
                size,
                sym,
                kAlpha,
                coefficient1);
        }

        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            const std::size_t half_count =
                static_cast<std::size_t>((extended.size + 1) / 2);
            fill_hamming_exact_pair_kernel<<<
                block_count(half_count),
                kThreadsPerBlock>>>(
                size,
                extended.size,
                kAlpha,
                coefficient1,
                result.data());
            check_kernel_launch("fill_hamming_exact_pair_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal general_cosine_fixed_coeff_fast(
        int size,
        bool sym,
        const RealSignal &coefficients)
    {
        const std::size_t coefficient_count = coefficients.size();
        if (coefficient_count == 0 || coefficient_count > 5)
        {
            return launch_window_kernel_impl(
                detail::KernelOp::kGeneralCosine,
                size,
                sym,
                &coefficients,
                nullptr,
                0);
        }
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        const float coefficient0 = coefficients[0];
        const float coefficient1 = coefficient_count > 1 ? coefficients[1] : 0.0f;
        const float coefficient2 = coefficient_count > 2 ? coefficients[2] : 0.0f;
        const float coefficient3 = coefficient_count > 3 ? coefficients[3] : 0.0f;
        const float coefficient4 = coefficient_count > 4 ? coefficients[4] : 0.0f;

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_general_cosine_fixed_coeff_fast_kernel<<<
                block_count(static_cast<std::size_t>(size)),
                kThreadsPerBlock>>>(
                size,
                extended.size,
                static_cast<int>(coefficient_count),
                coefficient0,
                coefficient1,
                coefficient2,
                coefficient3,
                coefficient4,
                result.data());
            check_kernel_launch("fill_general_cosine_fixed_coeff_fast_kernel");
        }));
        return result;
    }

    int general_gaussian_power_mode(float p)
    {
        if (p == 0.5f)
        {
            return 1;
        }
        if (p == 1.0f)
        {
            return 2;
        }
        if (p == 1.5f)
        {
            return 3;
        }
        if (p == 1.75f)
        {
            return 35;
        }
        if (p == 2.0f)
        {
            return 4;
        }
        return 0;
    }

    ZxGpuRealSignal kaiser_with_symmetric_kernel(int size, float beta, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        const float i0_beta = detail::bessel_i0(beta);
        const float inv_i0_beta = i0_beta != 0.0f ? 1.0f / i0_beta : 1.0f;

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            const std::size_t half_count =
                static_cast<std::size_t>((extended.size + 1) / 2);
            fill_kaiser_symmetric_kernel<<<block_count(half_count), kThreadsPerBlock>>>(
                size,
                extended.size,
                beta,
                inv_i0_beta,
                result.data());
            check_kernel_launch("fill_kaiser_symmetric_kernel");
        }));

        return result;
    }

    ZxGpuRealSignal launch_window_kernel(
        detail::KernelOp op,
        int size,
        bool sym,
        const RealSignal &coefficients,
        float parameter0 = 0.0,
        float parameter1 = 0.0,
        float parameter2 = 0.0,
        int int_parameter = 0)
    {
        return launch_window_kernel_impl(
            op,
            size,
            sym,
            &coefficients,
            nullptr,
            0,
            parameter0,
            parameter1,
            parameter2,
            int_parameter);
    }

    ZxGpuRealSignal launch_window_kernel(
        detail::KernelOp op,
        int size,
        bool sym,
        const float *device_coefficients,
        int coefficient_count,
        float parameter0 = 0.0,
        float parameter1 = 0.0,
        float parameter2 = 0.0,
        int int_parameter = 0)
    {
        return launch_window_kernel_impl(
            op,
            size,
            sym,
            nullptr,
            device_coefficients,
            coefficient_count,
            parameter0,
            parameter1,
            parameter2,
            int_parameter);
    }

    ZxGpuRealSignal general_gaussian_fast(int size, float p, float sig, bool sym)
    {
        const int power_mode = general_gaussian_power_mode(p);
        if (power_mode == 0)
        {
            return launch_window_kernel(
                detail::KernelOp::kGeneralGaussian,
                size,
                sym,
                p,
                sig);
        }
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            constexpr int kMaxExactFloatInteger = 1 << 24;
            if (extended.size - 1 <= kMaxExactFloatInteger)
            {
                const std::size_t half_count =
                    static_cast<std::size_t>((extended.size + 1) / 2);
                fill_general_gaussian_symmetric_fast_kernel<<<
                    block_count(half_count),
                    kThreadsPerBlock>>>(
                    size,
                    extended.size,
                    sig,
                    power_mode,
                    result.data());
                check_kernel_launch("fill_general_gaussian_symmetric_fast_kernel");
            }
            else
            {
                fill_general_gaussian_fast_kernel<<<
                    block_count(static_cast<std::size_t>(size)),
                    kThreadsPerBlock>>>(
                    size,
                    extended.size,
                    sig,
                    power_mode,
                    result.data());
                check_kernel_launch("fill_general_gaussian_fast_kernel");
            }
        }));
        return result;
    }

    ZxGpuRealSignal taylor_fixed_coeff_fast(
        int size,
        bool sym,
        const RealSignal &coefficients,
        float scale,
        int nbar)
    {
        const std::size_t coefficient_count = coefficients.size();
        if (coefficient_count > 8)
        {
            return launch_window_kernel_impl(
                detail::KernelOp::kTaylor,
                size,
                sym,
                &coefficients,
                nullptr,
                0,
                scale,
                0.0f,
                0.0f,
                nbar);
        }
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        const float coefficient0 = coefficient_count > 0 ? coefficients[0] : 0.0f;
        const float coefficient1 = coefficient_count > 1 ? coefficients[1] : 0.0f;
        const float coefficient2 = coefficient_count > 2 ? coefficients[2] : 0.0f;
        const float coefficient3 = coefficient_count > 3 ? coefficients[3] : 0.0f;
        const float coefficient4 = coefficient_count > 4 ? coefficients[4] : 0.0f;
        const float coefficient5 = coefficient_count > 5 ? coefficients[5] : 0.0f;
        const float coefficient6 = coefficient_count > 6 ? coefficients[6] : 0.0f;
        const float coefficient7 = coefficient_count > 7 ? coefficients[7] : 0.0f;

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            fill_taylor_fixed_coeff_fast_kernel<<<
                block_count(static_cast<std::size_t>(size)),
                kThreadsPerBlock>>>(
                size,
                extended.size,
                static_cast<int>(coefficient_count),
                coefficient0,
                coefficient1,
                coefficient2,
                coefficient3,
                coefficient4,
                coefficient5,
                coefficient6,
                coefficient7,
                scale,
                result.data());
            check_kernel_launch("fill_taylor_fixed_coeff_fast_kernel");
        }));
        return result;
    }

    ZxGpuRealSignal chebwin_with_cufft(int size, float at, bool sym)
    {
        if (detail::len_guard(size))
        {
            return make_trivial_window_signal(size);
        }
        if (!(at > 0.0f))
        {
            throw std::invalid_argument("at must be > 0");
        }

        const detail::ExtendedLength extended = detail::extend(size, sym);
        static thread_local WindowWorkspace workspace;
        ZxGpuRealSignal result(static_cast<std::size_t>(size), false);
        if (workspace.chebwin_final_valid &&
            workspace.chebwin_final_size == size &&
            workspace.chebwin_final_at == at &&
            workspace.chebwin_final_sym == sym)
        {
            ScopedZxGpuEvents events;
            g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                throw_on_zx_gpu_error(
                    cudaMemcpy(
                        result.data(),
                        workspace.chebwin_final_template.get(),
                        static_cast<std::size_t>(size) * sizeof(float),
                        cudaMemcpyDeviceToDevice),
                    "cudaMemcpy D2D chebwin final template");
            }));
            return result;
        }

        workspace.ensure_plan(extended.size);
        workspace.output.reserve(static_cast<std::size_t>(extended.size));
        workspace.ensure_reduce_storage(static_cast<std::size_t>(extended.size));
        workspace.spectrum.reserve(static_cast<std::size_t>(extended.size));
        workspace.spectrum_template.reserve(static_cast<std::size_t>(extended.size));
        workspace.chebwin_final_template.reserve(static_cast<std::size_t>(size));
        if (!workspace.chebwin_template_valid ||
            workspace.chebwin_template_size != extended.size ||
            workspace.chebwin_template_at != at ||
            workspace.chebwin_template_sym != sym)
        {
            build_chebwin_frequency_response_kernel<<<
                block_count(static_cast<std::size_t>(extended.size)),
                kThreadsPerBlock>>>(
                workspace.spectrum_template.get(),
                extended.size,
                at);
            check_kernel_launch("build_chebwin_frequency_response_kernel");
            workspace.chebwin_template_size = extended.size;
            workspace.chebwin_template_at = at;
            workspace.chebwin_template_sym = sym;
            workspace.chebwin_template_valid = true;
        }

        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            throw_on_zx_gpu_error(
                cudaMemcpy(
                    workspace.spectrum.get(),
                    workspace.spectrum_template.get(),
                    static_cast<std::size_t>(extended.size) * sizeof(cufftComplex),
                    cudaMemcpyDeviceToDevice),
                "cudaMemcpy D2D chebwin spectrum");

            throw_on_cufft_error(
                cufftExecC2C(
                    workspace.chebwin_plan,
                    workspace.spectrum.get(),
                    workspace.spectrum.get(),
                    CUFFT_FORWARD),
                "cufftExecC2C");

            rebuild_chebwin_from_fft_kernel<<<block_count(static_cast<std::size_t>(extended.size)), kThreadsPerBlock>>>(
                workspace.spectrum.get(),
                extended.size,
                workspace.output.get());
            check_kernel_launch("rebuild_chebwin_from_fft_kernel");

            reduce_max_window(workspace, static_cast<std::size_t>(extended.size));

            normalize_window_kernel<<<block_count(static_cast<std::size_t>(extended.size)), kThreadsPerBlock>>>(
                workspace.output.get(),
                static_cast<std::size_t>(extended.size),
                workspace.max_value.get());
            check_kernel_launch("normalize_window_kernel");

            copy_window_output_kernel<<<block_count(static_cast<std::size_t>(size)), kThreadsPerBlock>>>(
                workspace.output.get(),
                static_cast<std::size_t>(size),
                result.data());
            check_kernel_launch("copy_window_output_kernel chebwin");

            throw_on_zx_gpu_error(
                cudaMemcpy(
                    workspace.chebwin_final_template.get(),
                    result.data(),
                    static_cast<std::size_t>(size) * sizeof(float),
                    cudaMemcpyDeviceToDevice),
                "cudaMemcpy D2D chebwin final cache");
        }));
        workspace.chebwin_final_size = size;
        workspace.chebwin_final_at = at;
        workspace.chebwin_final_sym = sym;
        workspace.chebwin_final_valid = true;

        return result;
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace windows
        {
            core::ZxGpuRealSignal get_window(core::ZxGpuWindowSpec window, int nx, bool fftbins)
            {
                detail::validate_size(nx);
                const bool sym = !fftbins;

                if (std::holds_alternative<core::ZxGpuRealSignal>(window))
                {
                    const core::ZxGpuRealSignal &values = std::get<core::ZxGpuRealSignal>(window);
                    if (values.size() != static_cast<std::size_t>(nx))
                    {
                        throw std::invalid_argument("window array must have length nx");
                    }
                    g_last_kernel_ms = 0.0;
                    return values;
                }

                if (std::holds_alternative<core::RealSignal>(window))
                {
                    const core::RealSignal &values = std::get<core::RealSignal>(window);
                    if (values.size() != static_cast<std::size_t>(nx))
                    {
                        throw std::invalid_argument("window array must have length nx");
                    }
                    g_last_kernel_ms = 0.0;
                    return core::ZxGpuRealSignal::from_host(values);
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

            core::ZxGpuRealSignal barthann(int size, bool sym)
            {
                return barthann_fast(size, sym);
            }

            core::ZxGpuRealSignal bartlett(int size, bool sym)
            {
                return bartlett_fast(size, sym);
            }

            core::ZxGpuRealSignal blackman(int size, bool sym)
            {
                return general_cosine(size, core::RealSignal{0.42, 0.50, 0.08}, sym);
            }

            core::ZxGpuRealSignal blackmanharris(int size, bool sym)
            {
                return general_cosine(
                    size,
                    core::RealSignal{0.35875, 0.48829, 0.14128, 0.01168},
                    sym);
            }

            core::ZxGpuRealSignal bohman(int size, bool sym)
            {
                return bohman_fast(size, sym);
            }

            core::ZxGpuRealSignal boxcar(int size, bool sym)
            {
                (void)sym;
                return boxcar_fast(size);
            }

            core::ZxGpuRealSignal chebwin(int size, float at, bool sym)
            {
                return chebwin_with_cufft(size, at, sym);
            }

            core::ZxGpuRealSignal cosine(int size, bool sym)
            {
                return cosine_fast(size, sym);
            }

            core::ZxGpuRealSignal exponential(int size, float tau, bool sym)
            {
                if (!(tau > 0.0))
                {
                    throw std::invalid_argument("tau must be > 0");
                }
                const detail::ExtendedLength extended = detail::extend(size, sym);
                const float center = 0.5 * static_cast<float>(extended.size - 1);
                return exponential_fast(size, center, tau);
            }

            core::ZxGpuRealSignal exponential(int size, float center, float tau, bool sym)
            {
                if (!(tau > 0.0))
                {
                    throw std::invalid_argument("tau must be > 0");
                }
                if (sym)
                {
                    throw std::invalid_argument("explicit center is only supported for periodic exponential windows");
                }
                return exponential_fast(size, center, tau);
            }

            core::ZxGpuRealSignal flattop(int size, bool sym)
            {
                return general_cosine(
                    size,
                    core::RealSignal{
                        0.21557895,
                        0.41663158,
                        0.277263158,
                        0.083578947,
                        0.006947368},
                    sym);
            }

            core::ZxGpuRealSignal gaussian(int size, float std, bool sym)
            {
                if (!(std > 0.0))
                {
                    throw std::invalid_argument("std must be > 0");
                }
                return gaussian_fast(size, std, sym);
            }

            core::ZxGpuRealSignal general_cosine(int size, const core::RealSignalLike &a, bool sym)
            {
                if (const auto *device_coefficients = std::get_if<core::ZxGpuRealSignal>(&a))
                {
                    if (device_coefficients->empty())
                    {
                        throw std::invalid_argument("coefficients must not be empty");
                    }
                    return launch_window_kernel(
                        detail::KernelOp::kGeneralCosine,
                        size,
                        sym,
                        device_coefficients->data(),
                        static_cast<int>(device_coefficients->size()));
                }

                const core::RealSignal &coefficients = std::get<core::RealSignal>(a);
                detail::ensure_non_empty_coefficients(coefficients);
                if (coefficients.size() == 2)
                {
                    return general_cosine_two_coeff_fast(
                        size,
                        sym,
                        coefficients[0],
                        coefficients[1]);
                }
                return general_cosine_fixed_coeff_fast(size, sym, coefficients);
            }

            core::ZxGpuRealSignal general_gaussian(int size, float p, float sig, bool sym)
            {
                if (!(p > 0.0))
                {
                    throw std::invalid_argument("p must be > 0");
                }
                if (!(sig > 0.0))
                {
                    throw std::invalid_argument("sig must be > 0");
                }
                return general_gaussian_fast(size, p, sig, sym);
            }

            core::ZxGpuRealSignal general_hamming(int size, float alpha, bool sym)
            {
                return general_cosine_two_coeff_fast(size, sym, alpha, 1.0f - alpha);
            }

            core::ZxGpuRealSignal hamming(int size, bool sym)
            {
                return hamming_exact_pair_fast(size, sym);
            }

            core::ZxGpuRealSignal hann(int size, bool sym)
            {
                return general_hamming(size, 0.5f, sym);
            }

            core::ZxGpuRealSignal kaiser(int size, float beta, bool sym)
            {
                return kaiser_with_symmetric_kernel(size, beta, sym);
            }

            core::ZxGpuRealSignal nuttall(int size, bool sym)
            {
                return general_cosine(
                    size,
                    core::RealSignal{0.3635819, 0.4891775, 0.1365995, 0.0106411},
                    sym);
            }

            core::ZxGpuRealSignal parzen(int size, bool sym)
            {
                return parzen_fast(size, sym);
            }

            core::ZxGpuRealSignal taylor(int size, int nbar, float sll, bool norm, bool sym)
            {
                const RealSignal coefficients = detail::build_taylor_coefficients(nbar, sll);
                const detail::ExtendedLength extended = detail::extend(size, sym);
                const float scale = detail::taylor_scale(
                    extended.size,
                    nbar,
                    coefficients,
                    norm);
                return taylor_fixed_coeff_fast(size, sym, coefficients, scale, nbar);
            }

            core::ZxGpuRealSignal triang(int size, bool sym)
            {
                return triang_fast(size, sym);
            }

            core::ZxGpuRealSignal tukey(int size, float alpha, bool sym)
            {
                return tukey_fast(size, alpha, sym);
            }

        } // namespace windows

        namespace windows_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0;
                return value;
            }
        } // namespace windows_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
