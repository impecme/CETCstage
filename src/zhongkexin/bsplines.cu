#include "cusignal/bsplines/bsplines.hpp"

#include <cuda_runtime.h>

#include <cmath>
#include <cstdint>

#include "cusignal/core/helpers.hpp"

#include "../common/bsplines_detail.hpp"
#include "../common/zx_tile_policy.hpp"

namespace
{
    using cusignal::core::ZxGpuRealArray;
    namespace detail = cusignal::bsplines_detail;
    namespace tile = cusignal::zx_tile;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0;

    void check_kernel_launch(const char *what)
    {
        cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

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
                cusignal::core::throw_on_zx_gpu_error(
                    cudaEventCreate(&start), "cudaEventCreate(start)");
                cusignal::core::throw_on_zx_gpu_error(
                    cudaEventCreate(&stop), "cudaEventCreate(stop)");
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
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventRecord(g_timing_events.start), "cudaEventRecord(start)");
            callable();
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventRecord(g_timing_events.stop), "cudaEventRecord(stop)");
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventSynchronize(g_timing_events.stop), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventElapsedTime(
                    &elapsed_ms, g_timing_events.start, g_timing_events.stop),
                "cudaEventElapsedTime");
            return elapsed_ms;
        }
    };

    struct BsplinesWorkspace
    {
        ZxGpuRealArray input_storage;
    };

    thread_local BsplinesWorkspace g_workspace;

    int block_count(std::size_t size, int elements_per_thread = 1)
    {
        return size == 0
            ? 0
            : static_cast<int>(tile::ceil_div(
                  size,
                  static_cast<std::size_t>(kThreadsPerBlock) *
                      static_cast<std::size_t>(elements_per_thread)));
    }

    __device__ float cubic_value_fast(float x)
    {
        const float ax = fabsf(x);
        if (ax < 1.0f)
        {
            return (2.0f / 3.0f) - 0.5f * ax * ax * (2.0f - ax);
        }
        if (ax < 2.0f)
        {
            const float term = 2.0f - ax;
            return term * term * term * (1.0f / 6.0f);
        }
        return 0.0f;
    }

    __device__ float quadratic_value_fast(float x)
    {
        const float ax = fabsf(x);
        if (ax < 0.5f)
        {
            return 0.75f - ax * ax;
        }
        if (ax < 1.5f)
        {
            const float term = ax - 1.5f;
            return 0.5f * term * term;
        }
        return 0.0f;
    }

    __global__ void cubic_kernel(const float *input, float *output, std::size_t count)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                                  static_cast<std::size_t>(threadIdx.x);
        if (index >= count)
        {
            return;
        }
        output[index] = cubic_value_fast(input[index]);
    }

    __global__ void cubic_tiled_kernel(
        const float *input,
        float *output,
        std::size_t count,
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
            if (index < count)
            {
                output[index] = cubic_value_fast(input[index]);
            }
        }
    }

    __global__ void quadratic_kernel(const float *input, float *output, std::size_t count)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                                  static_cast<std::size_t>(threadIdx.x);
        if (index >= count)
        {
            return;
        }
        output[index] = quadratic_value_fast(input[index]);
    }

    __global__ void quadratic_tiled_kernel(
        const float *input,
        float *output,
        std::size_t count,
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
            if (index < count)
            {
                output[index] = quadratic_value_fast(input[index]);
            }
        }
    }

    __global__ void gauss_spline_kernel(
        const float *input,
        float *output,
        std::size_t count,
        float inv_sigma_factor,
        float norm_factor)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                                  static_cast<std::size_t>(threadIdx.x);
        if (index >= count)
        {
            return;
        }
        const float x = input[index];
        output[index] = expf(-(x * x) * inv_sigma_factor) * norm_factor;
    }

    __global__ void gauss_spline_tiled_kernel(
        const float *input,
        float *output,
        std::size_t count,
        float inv_sigma_factor,
        float norm_factor,
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
            if (index < count)
            {
                const float x = input[index];
                output[index] = expf(-(x * x) * inv_sigma_factor) * norm_factor;
            }
        }
    }

    template <typename LaunchFn>
    ZxGpuRealArray launch_pointwise(
        const char *operator_id,
        std::uint64_t semantic0,
        const ZxGpuRealArray &input,
        LaunchFn launch)
    {
        if (input.empty())
        {
            g_last_kernel_ms = 0.0;
            return ZxGpuRealArray(input.shape(), false);
        }

        ZxGpuRealArray output(input.shape(), false);
        const tile::PolicyDecision tuning = tile::select(
            tile::make_linear_operator_key(operator_id, input.size(), 0, semantic0));
        const tile::ScopedPolicy policy_scope(tuning);
        const bool use_tiled = tile::optimized_path() && input.size() >= 4096;
        const int elements_per_thread = use_tiled
                                            ? tile::linear_shape(input.size()).elements_per_thread
                                            : 1;
        ScopedZxGpuEvents events;
        g_last_kernel_ms = static_cast<float>(events.measure([&]() {
            launch(
                input.data(),
                output.data(),
                input.size(),
                elements_per_thread,
                block_count(input.size(), elements_per_thread),
                use_tiled);
            check_kernel_launch("bsplines_kernel");
        }));
        return output;
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace bsplines
        {

            core::ZxGpuRealArray cubic(const core::RealArrayLike &x)
            {
                const core::ZxGpuRealArray &input =
                    core::as_device_array(x, g_workspace.input_storage);
                return launch_pointwise(
                    "bsplines/cubic",
                    0,
                    input,
                    [](const float *in,
                       float *out,
                       std::size_t count,
                       int elements_per_thread,
                       int blocks,
                       bool use_tiled) {
                        if (use_tiled)
                        {
                            cubic_tiled_kernel<<<blocks, kThreadsPerBlock>>>(
                                in, out, count, elements_per_thread);
                        }
                        else
                        {
                            cubic_kernel<<<blocks, kThreadsPerBlock>>>(in, out, count);
                        }
                    });
            }

            core::ZxGpuRealArray gauss_spline(const core::RealArrayLike &x, int n)
            {
                detail::ensure_non_negative_order(n);
                const float sigma_squared = detail::gauss_spline_sigma_squared(n);
                const float inv_sigma_factor = 0.5f / sigma_squared;
                const float norm_factor = 1.0f / std::sqrt(2.0f * detail::kPi * sigma_squared);
                const core::ZxGpuRealArray &input =
                    core::as_device_array(x, g_workspace.input_storage);
                return launch_pointwise(
                    "bsplines/gauss_spline",
                    static_cast<std::uint64_t>(n),
                    input,
                    [inv_sigma_factor, norm_factor](const float *in,
                                                     float *out,
                                                     std::size_t count,
                                                     int elements_per_thread,
                                                     int blocks,
                                                     bool use_tiled) {
                        if (use_tiled)
                        {
                            gauss_spline_tiled_kernel<<<blocks, kThreadsPerBlock>>>(
                                in,
                                out,
                                count,
                                inv_sigma_factor,
                                norm_factor,
                                elements_per_thread);
                        }
                        else
                        {
                            gauss_spline_kernel<<<blocks, kThreadsPerBlock>>>(
                                in, out, count, inv_sigma_factor, norm_factor);
                        }
                    });
            }

            core::ZxGpuRealArray quadratic(const core::RealArrayLike &x)
            {
                const core::ZxGpuRealArray &input =
                    core::as_device_array(x, g_workspace.input_storage);
                return launch_pointwise(
                    "bsplines/quadratic",
                    0,
                    input,
                    [](const float *in,
                       float *out,
                       std::size_t count,
                       int elements_per_thread,
                       int blocks,
                       bool use_tiled) {
                        if (use_tiled)
                        {
                            quadratic_tiled_kernel<<<blocks, kThreadsPerBlock>>>(
                                in, out, count, elements_per_thread);
                        }
                        else
                        {
                            quadratic_kernel<<<blocks, kThreadsPerBlock>>>(
                                in, out, count);
                        }
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
    } // namespace zx_gpu_backend
} // namespace cusignal
