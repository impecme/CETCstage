#include "cusignal/demod/demod.hpp"

#include <cuda_runtime.h>

#include <vector>

#include "cusignal/core/helpers.hpp"

#include "../common/demod_detail.hpp"

namespace
{
    using cusignal::core::ComplexArrayLike;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::IndexVector;

    namespace demod_detail = cusignal::demod_detail;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0f;

    class ScopedZxGpuEvents
    {
    public:
        ScopedZxGpuEvents()
        {
            cusignal::core::throw_on_zx_gpu_error(cudaEventCreate(&start_), "cudaEventCreate(start)");
            cusignal::core::throw_on_zx_gpu_error(cudaEventCreate(&stop_), "cudaEventCreate(stop)");
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

        template <typename Callable>
        float measure(Callable callable)
        {
            cusignal::core::throw_on_zx_gpu_error(cudaEventRecord(start_), "cudaEventRecord(start)");
            callable();
            cusignal::core::throw_on_zx_gpu_error(cudaEventRecord(stop_), "cudaEventRecord(stop)");
            cusignal::core::throw_on_zx_gpu_error(cudaEventSynchronize(stop_), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventElapsedTime(&elapsed_ms, start_, stop_),
                "cudaEventElapsedTime");
            return elapsed_ms;
        }

    private:
        cudaEvent_t start_ = nullptr;
        cudaEvent_t stop_ = nullptr;
    };

    struct DemodWorkspace
    {
        ZxGpuComplexArray x_storage;
        ZxGpuRealArray phase_storage;
        ZxGpuRealArray unwrap_storage;
        ZxGpuIndexSignal shape_storage;
        ZxGpuIndexSignal strides_storage;
        ZxGpuIndexSignal output_shape_storage;
        ZxGpuIndexSignal output_strides_storage;
        cusignal::core::Shape cached_input_shape;
        cusignal::core::Shape cached_output_shape;
        std::vector<std::size_t> cached_input_strides;
        std::vector<std::size_t> cached_output_strides;
        std::size_t cached_axis = static_cast<std::size_t>(-1);
        bool metadata_valid = false;
    };

    thread_local DemodWorkspace g_workspace;

    int block_count(std::size_t count)
    {
        return count == 0 ? 0 : static_cast<int>((count + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    void check_kernel_launch(const char *what)
    {
        cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

    __device__ std::size_t line_base_offset_device(
        const int *shape,
        const int *strides,
        int rank,
        int axis,
        std::size_t line_index)
    {
        std::size_t offset = 0;
        for (int dim = 0; dim < rank; ++dim)
        {
            if (dim == axis)
            {
                continue;
            }
            const std::size_t dim_size = static_cast<std::size_t>(shape[dim]);
            const std::size_t coord = line_index % dim_size;
            line_index /= dim_size;
            offset += coord * static_cast<std::size_t>(strides[dim]);
        }
        return offset;
    }

    __global__ void angle_kernel(
        const float2 *input,
        std::size_t count,
        float *phase)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        const float2 value = input[index];
        phase[index] = atan2f(value.y, value.x);
    }

    __global__ void unwrap_kernel(
        const float *phase,
        int rank,
        const int *shape,
        const int *strides,
        int axis,
        std::size_t axis_size,
        std::size_t axis_stride,
        std::size_t line_count,
        float *output)
    {
        const std::size_t line_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (line_index >= line_count)
        {
            return;
        }
        const std::size_t base =
            line_base_offset_device(shape, strides, rank, axis, line_index);
        if (axis_size == 0)
        {
            return;
        }
        output[base] = phase[base];
        float offset = 0.0f;
        for (std::size_t index = 1; index < axis_size; ++index)
        {
            const std::size_t current = base + index * axis_stride;
            const std::size_t previous = current - axis_stride;
            const float delta = phase[current] - phase[previous];
            if (delta > 3.14159265358979323846f)
            {
                offset -= 6.28318530717958647692f;
            }
            else if (delta < -3.14159265358979323846f)
            {
                offset += 6.28318530717958647692f;
            }
            output[current] = phase[current] + offset;
        }
    }

    __global__ void diff_kernel(
        const float *input,
        int input_rank,
        const int *input_shape,
        const int *input_strides,
        int output_rank,
        const int *output_shape,
        const int *output_strides,
        int axis,
        std::size_t axis_size,
        std::size_t axis_stride,
        std::size_t line_count,
        float *output)
    {
        const std::size_t line_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (line_index >= line_count || axis_size < 2)
        {
            return;
        }
        const std::size_t base =
            line_base_offset_device(input_shape, input_strides, input_rank, axis, line_index);
        const std::size_t output_base =
            line_base_offset_device(output_shape, output_strides, output_rank, axis, line_index);
        for (std::size_t index = 0; index + 1 < axis_size; ++index)
        {
            const std::size_t current = base + index * axis_stride;
            const std::size_t output_index =
                output_base + index * static_cast<std::size_t>(output_strides[axis]);
            output[output_index] = input[current + axis_stride] - input[current];
        }
    }

    __global__ void fm_demod_phase_difference_kernel(
        const float2 *input,
        int input_rank,
        const int *input_shape,
        const int *input_strides,
        int output_rank,
        const int *output_shape,
        const int *output_strides,
        int axis,
        std::size_t axis_size,
        std::size_t axis_stride,
        std::size_t line_count,
        float *output)
    {
        const std::size_t output_axis_size = axis_size - 1;
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * output_axis_size;
        if (flat >= total)
        {
            return;
        }

        const std::size_t line_index = flat / output_axis_size;
        const std::size_t axis_index = flat % output_axis_size;
        const std::size_t input_base =
            line_base_offset_device(input_shape, input_strides, input_rank, axis, line_index);
        const std::size_t output_base =
            line_base_offset_device(output_shape, output_strides, output_rank, axis, line_index);
        const float2 current = input[input_base + axis_index * axis_stride];
        const float2 next = input[input_base + (axis_index + 1) * axis_stride];
        output[output_base + axis_index * static_cast<std::size_t>(output_strides[axis])] =
            demod_detail::wrapped_phase_difference(
                current.x, current.y, next.x, next.y);
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace demod
        {

            core::ZxGpuRealArray fm_demod(const core::ComplexArrayLike &x, int axis)
            {
                const ZxGpuComplexArray &device_x = core::as_device_array(x, g_workspace.x_storage);
                const std::size_t normalized_axis = core::normalize_axis(axis, device_x.rank());
                const std::size_t axis_length = device_x.shape()[normalized_axis];
                ZxGpuRealArray output = core::make_zx_gpu_real_array(
                    core::replace_axis_size(
                        device_x.shape(),
                        static_cast<int>(normalized_axis),
                        axis_length == 0 ? 0 : axis_length - 1));
                if (device_x.empty() || axis_length < 2)
                {
                    g_last_kernel_ms = 0.0f;
                    return output;
                }

                const std::vector<std::size_t> host_strides = [](
                    const core::Shape &shape) {
                    std::vector<std::size_t> strides(shape.size(), 1);
                    for (std::size_t index = shape.size(); index-- > 1;)
                    {
                        strides[index - 1] = strides[index] * shape[index];
                    }
                    return strides;
                }(device_x.shape());
                const std::vector<std::size_t> output_strides = [](
                    const core::Shape &shape) {
                    std::vector<std::size_t> strides(shape.size(), 1);
                    for (std::size_t index = shape.size(); index-- > 1;)
                    {
                        strides[index - 1] = strides[index] * shape[index];
                    }
                    return strides;
                }(output.shape());
                if (!g_workspace.metadata_valid ||
                    g_workspace.cached_input_shape != device_x.shape() ||
                    g_workspace.cached_output_shape != output.shape() ||
                    g_workspace.cached_input_strides != host_strides ||
                    g_workspace.cached_output_strides != output_strides ||
                    g_workspace.cached_axis != normalized_axis)
                {
                    IndexVector shape_vector(device_x.rank(), 0);
                    IndexVector stride_vector(device_x.rank(), 0);
                    IndexVector output_shape_vector(output.rank(), 0);
                    IndexVector output_stride_vector(output.rank(), 0);
                    for (std::size_t index = 0; index < device_x.rank(); ++index)
                    {
                        shape_vector[index] = static_cast<int>(device_x.shape()[index]);
                        stride_vector[index] = static_cast<int>(host_strides[index]);
                        output_shape_vector[index] = static_cast<int>(output.shape()[index]);
                        output_stride_vector[index] = static_cast<int>(output_strides[index]);
                    }
                    g_workspace.shape_storage.copy_from(shape_vector);
                    g_workspace.strides_storage.copy_from(stride_vector);
                    g_workspace.output_shape_storage.copy_from(output_shape_vector);
                    g_workspace.output_strides_storage.copy_from(output_stride_vector);
                    g_workspace.cached_input_shape = device_x.shape();
                    g_workspace.cached_output_shape = output.shape();
                    g_workspace.cached_input_strides = host_strides;
                    g_workspace.cached_output_strides = output_strides;
                    g_workspace.cached_axis = normalized_axis;
                    g_workspace.metadata_valid = true;
                }

                const std::size_t line_count =
                    core::shape_product(device_x.shape()) / axis_length;
                const std::size_t axis_stride = host_strides[normalized_axis];

                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    fm_demod_phase_difference_kernel<<<
                        block_count(line_count * (axis_length - 1)),
                        kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(device_x.data()),
                        static_cast<int>(device_x.rank()),
                        g_workspace.shape_storage.data(),
                        g_workspace.strides_storage.data(),
                        static_cast<int>(output.rank()),
                        g_workspace.output_shape_storage.data(),
                        g_workspace.output_strides_storage.data(),
                        static_cast<int>(normalized_axis),
                        axis_length,
                        axis_stride,
                        line_count,
                        output.data());
                    check_kernel_launch("fm_demod_phase_difference_kernel");
                });
                return output;
            }

        } // namespace demod

        namespace demod_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0f;
                return value;
            }
        } // namespace demod_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
