#include "cusignal/bsplines/bsplines.hpp"

#include <cuda_runtime.h>

#include "cusignal/core/helpers.hpp"

#include "../common/bsplines_detail.hpp"

namespace
{
    using cusignal::core::CudaRealArray;
    namespace detail = cusignal::bsplines_detail;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0;

    void check_kernel_launch(const char *what)
    {
        cusignal::core::throw_on_cuda_error(cudaGetLastError(), what);
    }

    class ScopedCudaEvents
    {
    public:
        ScopedCudaEvents()
        {
            cusignal::core::throw_on_cuda_error(
                cudaEventCreate(&start_), "cudaEventCreate(start)");
            cusignal::core::throw_on_cuda_error(
                cudaEventCreate(&stop_), "cudaEventCreate(stop)");
        }

        ~ScopedCudaEvents()
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

        template <typename Callable>
        float measure(Callable callable)
        {
            cusignal::core::throw_on_cuda_error(
                cudaEventRecord(start_), "cudaEventRecord(start)");
            callable();
            cusignal::core::throw_on_cuda_error(
                cudaEventRecord(stop_), "cudaEventRecord(stop)");
            cusignal::core::throw_on_cuda_error(
                cudaEventSynchronize(stop_), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            cusignal::core::throw_on_cuda_error(
                cudaEventElapsedTime(&elapsed_ms, start_, stop_),
                "cudaEventElapsedTime");
            return elapsed_ms;
        }

    private:
        cudaEvent_t start_ = nullptr;
        cudaEvent_t stop_ = nullptr;
    };

    struct BsplinesWorkspace
    {
        CudaRealArray input_storage;
    };

    thread_local BsplinesWorkspace g_workspace;

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    __global__ void cubic_kernel(const float *input, float *output, std::size_t count)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                                  static_cast<std::size_t>(threadIdx.x);
        if (index >= count)
        {
            return;
        }
        output[index] = detail::cubic_value(input[index]);
    }

    __global__ void quadratic_kernel(const float *input, float *output, std::size_t count)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                                  static_cast<std::size_t>(threadIdx.x);
        if (index >= count)
        {
            return;
        }
        output[index] = detail::quadratic_value(input[index]);
    }

    __global__ void gauss_spline_kernel(
        const float *input,
        float *output,
        std::size_t count,
        int n)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                                  static_cast<std::size_t>(threadIdx.x);
        if (index >= count)
        {
            return;
        }
        output[index] = detail::gauss_spline_value(input[index], n);
    }

    template <typename LaunchFn>
    CudaRealArray launch_pointwise(const CudaRealArray &input, LaunchFn launch)
    {
        if (input.empty())
        {
            g_last_kernel_ms = 0.0;
            return CudaRealArray(input.shape(), false);
        }

        CudaRealArray output(input.shape(), false);
        ScopedCudaEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            launch(input.data(), output.data(), input.size());
            check_kernel_launch("bsplines_kernel");
        }));
        return output;
    }
} // namespace

namespace cusignal
{
    namespace cuda_backend
    {
        namespace bsplines
        {

            core::CudaRealArray cubic(const core::RealArrayLike &x)
            {
                const core::CudaRealArray &input =
                    core::as_device_array(x, g_workspace.input_storage);
                return launch_pointwise(
                    input,
                    [](const float *in, float *out, std::size_t count) {
                        cubic_kernel<<<block_count(count), kThreadsPerBlock>>>(in, out, count);
                    });
            }

            core::CudaRealArray gauss_spline(const core::RealArrayLike &x, int n)
            {
                detail::ensure_non_negative_order(n);
                const core::CudaRealArray &input =
                    core::as_device_array(x, g_workspace.input_storage);
                return launch_pointwise(
                    input,
                    [n](const float *in, float *out, std::size_t count) {
                        gauss_spline_kernel<<<block_count(count), kThreadsPerBlock>>>(
                            in, out, count, n);
                    });
            }

            core::CudaRealArray quadratic(const core::RealArrayLike &x)
            {
                const core::CudaRealArray &input =
                    core::as_device_array(x, g_workspace.input_storage);
                return launch_pointwise(
                    input,
                    [](const float *in, float *out, std::size_t count) {
                        quadratic_kernel<<<block_count(count), kThreadsPerBlock>>>(
                            in, out, count);
                    });
            }

        } // namespace bsplines

        namespace bsplines_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0;
                return value;
            }
        } // namespace bsplines_test_hooks
    } // namespace cuda_backend
} // namespace cusignal
