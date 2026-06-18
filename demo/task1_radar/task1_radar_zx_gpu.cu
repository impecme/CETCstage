#include "task1_radar_zx_gpu.hpp"

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal_demo::task1_radar
{
    namespace
    {
        constexpr int kThreadsPerBlock = 256;

        std::size_t block_count(std::size_t total)
        {
            return total == 0 ? 0 : (total + static_cast<std::size_t>(kThreadsPerBlock) - 1) /
                static_cast<std::size_t>(kThreadsPerBlock);
        }

        __global__ void complex_power_kernel(
            const float2 *input,
            float *output,
            std::size_t element_count)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index >= element_count)
            {
                return;
            }

            const float2 value = input[index];
            output[index] = value.x * value.x + value.y * value.y;
        }

        __global__ void fftshift_rows_complex_kernel(
            const float2 *input,
            float2 *output,
            std::size_t rows,
            std::size_t cols)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = rows * cols;
            if (index >= total)
            {
                return;
            }

            const std::size_t row = index / cols;
            const std::size_t col = index % cols;
            const std::size_t shifted_row = (row + rows / 2) % rows;
            output[shifted_row * cols + col] = input[index];
        }
    } // namespace

    cusignal::core::ZxGpuRealArray power_map_zx_gpu(const cusignal::core::ZxGpuComplexArray &input)
    {
        cusignal::core::ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (input.empty())
        {
            return output;
        }

        complex_power_kernel<<<block_count(input.size()), kThreadsPerBlock>>>(
            reinterpret_cast<const float2 *>(input.data()),
            output.data(),
            input.size());
        cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), "complex_power_kernel");
        return output;
    }

    cusignal::core::ZxGpuComplexArray fftshift_rows_complex_zx_gpu(const cusignal::core::ZxGpuComplexArray &input)
    {
        cusignal::core::ZxGpuComplexArray output = cusignal::core::make_zx_gpu_complex_array(input.shape());
        if (input.empty())
        {
            return output;
        }

        const std::size_t rows = input.shape()[0];
        const std::size_t cols = input.shape()[1];
        fftshift_rows_complex_kernel<<<block_count(input.size()), kThreadsPerBlock>>>(
            reinterpret_cast<const float2 *>(input.data()),
            reinterpret_cast<float2 *>(output.data()),
            rows,
            cols);
        cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), "fftshift_rows_complex_kernel");
        return output;
    }
}
