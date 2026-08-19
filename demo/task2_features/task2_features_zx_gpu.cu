#include "task2_features_zx_gpu.hpp"

#include <cuda_runtime_api.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <numeric>
#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"
#include "../../src/common/demod_detail.hpp"
#include "../../src/common/wavelets_detail.hpp"
#include "../../src/common/zx_tile_policy.hpp"

namespace cusignal_demo::task2_features
{
    namespace
    {
        namespace wavelets_detail = cusignal::wavelets_detail;
        namespace demod_detail = cusignal::demod_detail;
        using cusignal::core::ZxGpuComplexArray;
        using cusignal::core::ZxGpuIndexSignal;
        using cusignal::core::ZxGpuRealArray;
        using cusignal::core::ZxGpuRealSignal;
        using cusignal::core::RealSignal;
        using cusignal::core::Shape;
        namespace tile = cusignal::zx_tile;

        constexpr int kThreadsPerBlock = 256;
        constexpr std::size_t kTask2FixedFftMinRows = 48;
        constexpr std::size_t kTask2FixedFftMinCols = 1024;
        constexpr std::size_t kTask2FixedFftMaxSize = 4096;
        constexpr float kTask2Pi = 3.14159265358979323846f;

        struct Task2Workspace
        {
            ZxGpuRealArray real_storage;
            ZxGpuRealArray imag_storage;
            ZxGpuComplexArray complex_storage;
            ZxGpuRealArray temp_storage_a;
            ZxGpuRealArray temp_storage_b;
            ZxGpuRealSignal temp_signal;
            ZxGpuIndexSignal temp_index;
            ZxGpuRealArray direct_cos_table;
            ZxGpuRealArray direct_sin_table;
            std::vector<float> cached_direct_window;
            int cached_direct_nperseg = 0;
            int cached_direct_nfft = 0;
            int cached_direct_low_bin = -1;
            int cached_direct_high_bin = -1;
            float cached_direct_fs = 0.0f;
            float cached_direct_scale = 0.0f;
            bool direct_spectrogram_table_valid = false;
            ZxGpuIndexSignal cwt_kernel_sizes;
            ZxGpuIndexSignal cwt_kernel_starts;
            ZxGpuIndexSignal cwt_kernel_offsets;
            ZxGpuRealSignal cwt_kernel_real;
            ZxGpuRealSignal cwt_kernel_imag;
            std::vector<float> cached_cwt_widths;
            std::size_t cached_cwt_sample_count = 0;
            std::size_t cached_cwt_max_kernel_size = 0;
            bool cached_cwt_kernel_symmetric = false;
            bool cwt_kernel_table_valid = false;
            ZxGpuComplexArray fixed_fft_input;
            ZxGpuComplexArray fixed_fft_output;
            ZxGpuComplexArray fixed_fft_twiddles;
            int cached_fixed_fft_size = 0;
            const void *cached_fixed_fft_filtered_data = nullptr;
            std::size_t cached_fixed_fft_filtered_rows = 0;
            std::size_t cached_fixed_fft_filtered_cols = 0;
            int cached_fixed_fft_filtered_size = 0;
            bool fixed_fft_filtered_spectrum_valid = false;
        };

        thread_local Task2Workspace g_workspace;

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


        std::size_t block_count(std::size_t total)
        {
            const std::size_t threads = static_cast<std::size_t>(tile::task_threads());
            return total == 0 ? 0 : (total + threads - 1) / threads;
        }

        bool environment_flag_enabled(const char *name)
        {
            const char *value = std::getenv(name);
            if (value == nullptr)
            {
                return false;
            }
            const std::string token(value);
            return token == "1" || token == "true" || token == "TRUE" ||
                token == "on" || token == "ON";
        }

        bool task2_fixed_fft_filter_disabled()
        {
            static const bool disabled =
                environment_flag_enabled("CUSIGNAL_TASK2_DISABLE_FIXED_FFT_FILTER");
            return disabled;
        }

        bool task2_fixed_fft_correlate_disabled()
        {
            static const bool disabled =
                environment_flag_enabled("CUSIGNAL_TASK2_DISABLE_FIXED_FFT_CORRELATE");
            return disabled;
        }

        bool task2_fixed_fft_spectrogram_disabled()
        {
            static const bool disabled =
                environment_flag_enabled("CUSIGNAL_TASK2_DISABLE_FIXED_FFT_SPECTROGRAM");
            return disabled;
        }

        bool task2_cwt_symmetry_enabled()
        {
            static const bool enabled =
                environment_flag_enabled("CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY");
            return enabled;
        }

        bool is_power_of_two(int value)
        {
            return value > 0 && (value & (value - 1)) == 0;
        }

        int task2_fixed_fft_size(std::size_t full_size)
        {
            std::size_t fft_size = 1;
            while (fft_size < full_size)
            {
                fft_size *= 2;
            }
            if (fft_size > kTask2FixedFftMaxSize)
            {
                throw std::invalid_argument("Task2 fixed FFT size exceeds supported range");
            }
            return static_cast<int>(fft_size);
        }

        int exact_log2(int value)
        {
            int result = 0;
            while (value > 1)
            {
                value >>= 1;
                ++result;
            }
            return result;
        }

        void ensure_task2_fixed_fft_workspace(int fft_size, std::size_t batch)
        {
            const std::size_t fft_size_u = static_cast<std::size_t>(fft_size);
            const void *old_input = g_workspace.fixed_fft_input.data();
            const void *old_output = g_workspace.fixed_fft_output.data();
            g_workspace.fixed_fft_input.resize(Shape{batch, fft_size_u}, false);
            g_workspace.fixed_fft_output.resize(Shape{batch, fft_size_u}, false);
            if (old_input != g_workspace.fixed_fft_input.data() ||
                old_output != g_workspace.fixed_fft_output.data())
            {
                g_workspace.fixed_fft_filtered_spectrum_valid = false;
            }
            if (g_workspace.cached_fixed_fft_size == fft_size)
            {
                return;
            }

            std::vector<float2> twiddles(fft_size_u / 2);
            for (std::size_t index = 0; index < twiddles.size(); ++index)
            {
                const float angle =
                    -2.0f * kTask2Pi * static_cast<float>(index) / static_cast<float>(fft_size);
                twiddles[index] = make_float2(std::cos(angle), std::sin(angle));
            }
            g_workspace.fixed_fft_twiddles.resize(Shape{twiddles.size()}, false);
            throw_on_zx_gpu_error(
                cudaMemcpy(
                    g_workspace.fixed_fft_twiddles.data(),
                    twiddles.data(),
                    twiddles.size() * sizeof(float2),
                    cudaMemcpyHostToDevice),
                "cudaMemcpy H2D(Task2 fixed FFT twiddles)");
            g_workspace.cached_fixed_fft_size = fft_size;
        }

        __device__ unsigned int reverse_low_bits(unsigned int value, int bit_count)
        {
            unsigned int reversed = 0;
            for (int bit = 0; bit < bit_count; ++bit)
            {
                reversed = (reversed << 1U) | ((value >> bit) & 1U);
            }
            return reversed;
        }

        __global__ void task2_fixed_radix2_fft_kernel(
            const float2 *input,
            float2 *output,
            const float2 *twiddles,
            int fft_size,
            int log2_size,
            int inverse)
        {
            extern __shared__ float2 shared_values[];
            const std::size_t offset =
                static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(fft_size);

            for (int index = static_cast<int>(threadIdx.x);
                 index < fft_size;
                 index += static_cast<int>(blockDim.x))
            {
                const unsigned int reversed =
                    reverse_low_bits(static_cast<unsigned int>(index), log2_size);
                shared_values[reversed] = input[offset + static_cast<std::size_t>(index)];
            }
            __syncthreads();

            int length = 2;
            for (int stage = 0; stage < log2_size; ++stage, length <<= 1)
            {
                const int half = length >> 1;
                const int twiddle_step = fft_size / length;
                for (int pair = static_cast<int>(threadIdx.x);
                     pair < fft_size / 2;
                     pair += static_cast<int>(blockDim.x))
                {
                    const int group = pair / half;
                    const int inner = pair - group * half;
                    const int first = group * length + inner;
                    const int second = first + half;
                    float2 twiddle = twiddles[inner * twiddle_step];
                    if (inverse != 0)
                    {
                        twiddle.y = -twiddle.y;
                    }
                    const float2 lhs = shared_values[first];
                    const float2 rhs = shared_values[second];
                    const float2 product = make_float2(
                        fmaf(-twiddle.y, rhs.y, twiddle.x * rhs.x),
                        fmaf(twiddle.y, rhs.x, twiddle.x * rhs.y));
                    shared_values[first] = make_float2(lhs.x + product.x, lhs.y + product.y);
                    shared_values[second] = make_float2(lhs.x - product.x, lhs.y - product.y);
                }
                __syncthreads();
            }

            const float scale = inverse != 0 ? 1.0f / static_cast<float>(fft_size) : 1.0f;
            for (int index = static_cast<int>(threadIdx.x);
                 index < fft_size;
                 index += static_cast<int>(blockDim.x))
            {
                const float2 value = shared_values[index];
                output[offset + static_cast<std::size_t>(index)] =
                    make_float2(value.x * scale, value.y * scale);
            }
        }

        void launch_task2_fixed_fft(
            const float2 *input,
            float2 *output,
            int fft_size,
            std::size_t batch,
            bool inverse)
        {
            task2_fixed_radix2_fft_kernel<<<
                static_cast<unsigned int>(batch),
                kThreadsPerBlock,
                static_cast<std::size_t>(fft_size) * sizeof(float2)>>>(
                input,
                output,
                reinterpret_cast<const float2 *>(g_workspace.fixed_fft_twiddles.data()),
                fft_size,
                exact_log2(fft_size),
                inverse ? 1 : 0);
            check_kernel_launch(
                inverse ? "task2_fixed_radix2_fft_kernel inverse"
                        : "task2_fixed_radix2_fft_kernel forward");
        }

        __global__ void extract_real_part_kernel(
            const float2 *input,
            float *output,
            std::size_t element_count)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index < element_count)
            {
                output[index] = input[index].x;
            }
        }

        __global__ void extract_imag_part_kernel(
            const float2 *input,
            float *output,
            std::size_t element_count)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index < element_count)
            {
                output[index] = input[index].y;
            }
        }

        __global__ void combine_complex_kernel(
            const float *real_part,
            const float *imag_part,
            float2 *output,
            std::size_t element_count)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index < element_count)
            {
                output[index] = make_float2(real_part[index], imag_part[index]);
            }
        }

        __global__ void complex_firfilter_kernel(
            const float2 *input,
            const float *taps,
            std::size_t rows,
            std::size_t cols,
            std::size_t tap_count,
            float2 *output,
            float *real_output)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = rows * cols;
            if (flat >= total)
            {
                return;
            }

            const std::size_t row = flat / cols;
            const std::size_t col = flat % cols;
            const std::size_t row_offset = row * cols;
            const std::size_t tap_limit = min(tap_count, col + 1);
            float real = 0.0f;
            float imag = 0.0f;
            for (std::size_t tap = 0; tap < tap_limit; ++tap)
            {
                const float2 value = input[row_offset + col - tap];
                const float coeff = taps[tap];
                real = fmaf(coeff, value.x, real);
                imag = fmaf(coeff, value.y, imag);
            }
            output[flat] = make_float2(real, imag);
            real_output[flat] = real;
        }

        __global__ void extract_row_complex_kernel(
            const float2 *input,
            std::size_t rows,
            std::size_t cols,
            int row_index,
            float2 *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index >= cols)
            {
                return;
            }
            if (row_index < 0 || static_cast<std::size_t>(row_index) >= rows)
            {
                return;
            }
            output[index] = input[static_cast<std::size_t>(row_index) * cols + index];
        }

        __global__ void extract_row_real_kernel(
            const float *input,
            std::size_t rows,
            std::size_t cols,
            int row_index,
            float *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index >= cols)
            {
                return;
            }
            if (row_index < 0 || static_cast<std::size_t>(row_index) >= rows)
            {
                return;
            }
            output[index] = input[static_cast<std::size_t>(row_index) * cols + index];
        }

        __global__ void extract_frame_real_3d_kernel(
            const float *input,
            std::size_t frames,
            std::size_t rows,
            std::size_t cols,
            int frame_index,
            float *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t frame_size = rows * cols;
            if (index >= frame_size)
            {
                return;
            }
            if (frame_index < 0 || static_cast<std::size_t>(frame_index) >= frames)
            {
                return;
            }
            output[index] = input[static_cast<std::size_t>(frame_index) * frame_size + index];
        }

        __global__ void store_row_real_kernel(
            const float *row,
            std::size_t cols,
            int row_index,
            float *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index >= cols)
            {
                return;
            }
            output[static_cast<std::size_t>(row_index) * cols + index] = row[index];
        }

        __global__ void complex_abs_kernel(
            const float2 *input,
            float *output,
            std::size_t element_count)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index < element_count)
            {
                const float2 value = input[index];
                output[index] = sqrtf(value.x * value.x + value.y * value.y);
            }
        }

        __global__ void pad_last_value_kernel(
            const float *input,
            std::size_t input_size,
            float *output,
            std::size_t target_size)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index >= target_size)
            {
                return;
            }
            if (input_size == 0)
            {
                output[index] = 0.0f;
                return;
            }
            output[index] = input[index < input_size ? index : (input_size - 1)];
        }

        __global__ void max_reduce_kernel(
            const float *input,
            std::size_t size,
            float *output)
        {
            __shared__ float shared[kThreadsPerBlock];
            const unsigned int tid = threadIdx.x;
            float local_max = 0.0f;
            for (std::size_t index = tid; index < size; index += blockDim.x)
            {
                local_max = fmaxf(local_max, input[index]);
            }
            shared[tid] = local_max;
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
                output[0] = shared[0];
            }
        }

        __global__ void normalize_kernel(
            const float *input,
            std::size_t size,
            const float *max_value,
            float *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index < size)
            {
                const float scale = max_value[0] > 1.0e-12f ? (1.0f / max_value[0]) : 0.0f;
                output[index] = input[index] * scale;
            }
        }

        __global__ void normalize_rows_kernel(
            const float *input,
            std::size_t rows,
            std::size_t cols,
            float *output)
        {
            __shared__ float shared[kThreadsPerBlock];
            const std::size_t row = static_cast<std::size_t>(blockIdx.x);
            const unsigned int tid = threadIdx.x;
            if (row >= rows)
            {
                return;
            }

            const std::size_t row_offset = row * cols;
            float local_max = 0.0f;
            for (std::size_t col = tid; col < cols; col += blockDim.x)
            {
                local_max = fmaxf(local_max, input[row_offset + col]);
            }
            shared[tid] = local_max;
            __syncthreads();

            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (tid < stride)
                {
                    shared[tid] = fmaxf(shared[tid], shared[tid + stride]);
                }
                __syncthreads();
            }

            const float scale = shared[0] > 1.0e-12f ? (1.0f / shared[0]) : 0.0f;
            for (std::size_t col = tid; col < cols; col += blockDim.x)
            {
                output[row_offset + col] = input[row_offset + col] * scale;
            }
        }

        __global__ void batched_demod_score_kernel(
            const float2 *input,
            std::size_t rows,
            std::size_t cols,
            float *output)
        {
            __shared__ float shared[kThreadsPerBlock];
            const std::size_t row = static_cast<std::size_t>(blockIdx.x);
            const unsigned int tid = threadIdx.x;
            if (row >= rows)
            {
                return;
            }

            float local_max = 0.0f;
            const std::size_t row_offset = row * cols;
            for (std::size_t col = tid; col < cols; col += blockDim.x)
            {
                float value = 0.0f;
                if (cols >= 2)
                {
                    const std::size_t source_col = col < cols - 1 ? col : cols - 2;
                    const float2 current = input[row_offset + source_col];
                    const float2 next = input[row_offset + source_col + 1];
                    value = demod_detail::wrapped_phase_difference(
                        current.x, current.y, next.x, next.y);
                    if (fabsf(value) <= kTaskDemodSmallPhaseLimit)
                    {
                        const float current_power = fmaf(current.x, current.x, current.y * current.y);
                        const float next_power = fmaf(next.x, next.x, next.y * next.y);
                        const float max_power = fmaxf(current_power, next_power);
                        if (max_power > 0.0f &&
                            fminf(current_power, next_power) <= kTaskDemodMinPowerRatio * max_power)
                        {
                            value = 0.0f;
                        }
                    }
                }
                output[row_offset + col] = value;
                local_max = fmaxf(local_max, value);
            }

            shared[tid] = local_max;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (tid < stride)
                {
                    shared[tid] = fmaxf(shared[tid], shared[tid + stride]);
                }
                __syncthreads();
            }

            const float scale = shared[0] > 1.0e-12f ? (1.0f / shared[0]) : 0.0f;
            for (std::size_t col = tid; col < cols; col += blockDim.x)
            {
                output[row_offset + col] *= scale;
            }
        }

        __global__ void batched_correlate_score_kernel(
            const float2 *frames,
            const float2 *templ,
            std::size_t rows,
            std::size_t cols,
            std::size_t templ_len,
            int crop_start,
            float *output)
        {
            __shared__ float shared_real[kThreadsPerBlock];
            __shared__ float shared_imag[kThreadsPerBlock];

            const std::size_t flat = static_cast<std::size_t>(blockIdx.x);
            const std::size_t row = flat / cols;
            const std::size_t col = flat % cols;
            if (row >= rows)
            {
                return;
            }

            float real = 0.0f;
            float imag = 0.0f;
            const float2 *frame = frames + row * cols;
            for (std::size_t k = threadIdx.x; k < templ_len; k += blockDim.x)
            {
                const long long input_index =
                    static_cast<long long>(col) +
                    static_cast<long long>(crop_start) +
                    static_cast<long long>(k) -
                    static_cast<long long>(templ_len - 1);
                if (input_index < 0 || input_index >= static_cast<long long>(cols))
                {
                    continue;
                }
                const float2 lhs = frame[static_cast<std::size_t>(input_index)];
                const float2 rhs = templ[k];
                real += lhs.x * rhs.x + lhs.y * rhs.y;
                imag += lhs.y * rhs.x - lhs.x * rhs.y;
            }

            shared_real[threadIdx.x] = real;
            shared_imag[threadIdx.x] = imag;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared_real[threadIdx.x] += shared_real[threadIdx.x + stride];
                    shared_imag[threadIdx.x] += shared_imag[threadIdx.x + stride];
                }
                __syncthreads();
            }
            if (threadIdx.x == 0)
            {
                output[flat] = hypotf(shared_real[0], shared_imag[0]);
            }
        }

        __global__ void batched_correlate_score_tiled_kernel(
            const float2 *frames,
            const float2 *templ,
            std::size_t rows,
            std::size_t cols,
            std::size_t templ_len,
            int crop_start,
            float *output)
        {
            extern __shared__ float2 shared_values[];
            float2 *shared_input = shared_values;
            const std::size_t outputs_per_block =
                2 * static_cast<std::size_t>(blockDim.x);
            float2 *shared_template = shared_input + outputs_per_block + templ_len - 1;

            const std::size_t row = static_cast<std::size_t>(blockIdx.y);
            if (row >= rows)
            {
                return;
            }

            const std::size_t block_start =
                static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
            const std::size_t input_tile_size = outputs_per_block + templ_len - 1;
            const long long input_start =
                static_cast<long long>(block_start) + static_cast<long long>(crop_start) -
                static_cast<long long>(templ_len - 1);
            const float2 *frame = frames + row * cols;
            for (std::size_t index = threadIdx.x; index < input_tile_size; index += blockDim.x)
            {
                const long long input_index = input_start + static_cast<long long>(index);
                shared_input[index] = input_index >= 0 && input_index < static_cast<long long>(cols)
                    ? frame[static_cast<std::size_t>(input_index)]
                    : make_float2(0.0f, 0.0f);
            }
            for (std::size_t index = threadIdx.x; index < templ_len; index += blockDim.x)
            {
                shared_template[index] = templ[index];
            }
            __syncthreads();

            const std::size_t col0 = block_start + static_cast<std::size_t>(threadIdx.x);
            if (col0 >= cols)
            {
                return;
            }
            const std::size_t col1 = col0 + static_cast<std::size_t>(blockDim.x);

            float real0 = 0.0f;
            float imag0 = 0.0f;
            float real1 = 0.0f;
            float imag1 = 0.0f;
            for (std::size_t k = 0; k < templ_len; ++k)
            {
                const float2 rhs = shared_template[k];
                const std::size_t shared_index = static_cast<std::size_t>(threadIdx.x) + k;
                const float2 lhs0 = shared_input[shared_index];
                const float2 lhs1 = shared_input[shared_index + blockDim.x];
                real0 = fmaf(lhs0.x, rhs.x, real0);
                real0 = fmaf(lhs0.y, rhs.y, real0);
                imag0 = fmaf(lhs0.y, rhs.x, imag0);
                imag0 = fmaf(-lhs0.x, rhs.y, imag0);
                real1 = fmaf(lhs1.x, rhs.x, real1);
                real1 = fmaf(lhs1.y, rhs.y, real1);
                imag1 = fmaf(lhs1.y, rhs.x, imag1);
                imag1 = fmaf(-lhs1.x, rhs.y, imag1);
            }
            output[row * cols + col0] = hypotf(real0, imag0);
            if (col1 < cols)
            {
                output[row * cols + col1] = hypotf(real1, imag1);
            }
        }

        __global__ void pack_task2_filter_fft_kernel(
            const float2 *input,
            const float *taps,
            std::size_t rows,
            std::size_t cols,
            std::size_t tap_count,
            std::size_t fft_size,
            float2 *storage)
        {
            const std::size_t flat =
                static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = (rows + 1) * fft_size;
            if (flat >= total)
            {
                return;
            }
            const std::size_t batch = flat / fft_size;
            const std::size_t index = flat % fft_size;
            if (batch < rows)
            {
                storage[flat] = index < cols
                    ? input[batch * cols + index]
                    : make_float2(0.0f, 0.0f);
            }
            else
            {
                storage[flat] = index < tap_count
                    ? make_float2(taps[index], 0.0f)
                    : make_float2(0.0f, 0.0f);
            }
        }

        __global__ void multiply_task2_fft_kernel(
            const float2 *spectra,
            std::size_t rows,
            std::size_t fft_size,
            float2 *products)
        {
            const std::size_t flat =
                static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = rows * fft_size;
            if (flat >= total)
            {
                return;
            }
            const std::size_t frequency = flat % fft_size;
            const float2 lhs = spectra[flat];
            const float2 rhs = spectra[rows * fft_size + frequency];
            products[flat] = make_float2(
                lhs.x * rhs.x - lhs.y * rhs.y,
                lhs.x * rhs.y + lhs.y * rhs.x);
        }

        __global__ void extract_task2_filter_fft_kernel(
            const float2 *storage,
            std::size_t rows,
            std::size_t cols,
            std::size_t fft_size,
            float2 *output,
            float *real_output)
        {
            const std::size_t flat =
                static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = rows * cols;
            if (flat >= total)
            {
                return;
            }
            const std::size_t row = flat / cols;
            const std::size_t col = flat % cols;
            const float2 value = storage[row * fft_size + col];
            output[flat] = value;
            real_output[flat] = value.x;
        }

        __global__ void pack_task2_correlate_fft_kernel(
            const float2 *frames,
            const float2 *templ,
            std::size_t rows,
            std::size_t cols,
            std::size_t templ_len,
            std::size_t fft_size,
            float2 *storage)
        {
            const std::size_t flat =
                static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = (rows + 1) * fft_size;
            if (flat >= total)
            {
                return;
            }
            const std::size_t batch = flat / fft_size;
            const std::size_t index = flat % fft_size;
            if (batch < rows)
            {
                storage[flat] = index < cols
                    ? frames[batch * cols + index]
                    : make_float2(0.0f, 0.0f);
            }
            else if (index < templ_len)
            {
                const float2 value = templ[templ_len - 1 - index];
                storage[flat] = make_float2(value.x, -value.y);
            }
            else
            {
                storage[flat] = make_float2(0.0f, 0.0f);
            }
        }

        __global__ void pack_task2_correlate_template_fft_kernel(
            const float2 *templ,
            std::size_t templ_len,
            std::size_t fft_size,
            float2 *storage)
        {
            const std::size_t index =
                static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                static_cast<std::size_t>(threadIdx.x);
            if (index >= fft_size)
            {
                return;
            }
            if (index < templ_len)
            {
                const float2 value = templ[templ_len - 1 - index];
                storage[index] = make_float2(value.x, -value.y);
            }
            else
            {
                storage[index] = make_float2(0.0f, 0.0f);
            }
        }

        __global__ void extract_task2_correlate_fft_kernel(
            const float2 *storage,
            std::size_t rows,
            std::size_t cols,
            std::size_t fft_size,
            std::size_t crop_start,
            float *output)
        {
            const std::size_t flat =
                static_cast<std::size_t>(blockIdx.x) * blockDim.x +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = rows * cols;
            if (flat >= total)
            {
                return;
            }
            const std::size_t row = flat / cols;
            const std::size_t col = flat % cols;
            const float2 value = storage[row * fft_size + crop_start + col];
            output[flat] = hypotf(value.x, value.y);
        }

        __global__ void pack_task2_spectrogram_fft_kernel(
            const float *frames,
            const float *window,
            std::size_t sample_count,
            int nperseg,
            int step,
            int nseg,
            int nfft,
            float2 *storage)
        {
            __shared__ float shared_sum[kThreadsPerBlock];
            const std::size_t segment_flat = static_cast<std::size_t>(blockIdx.x);
            const int seg = static_cast<int>(
                segment_flat % static_cast<std::size_t>(nseg));
            const std::size_t frame =
                segment_flat / static_cast<std::size_t>(nseg);
            const float *frame_ptr = frames + frame * sample_count;
            const int start = seg * step;

            float local_sum = 0.0f;
            for (int sample = static_cast<int>(threadIdx.x);
                 sample < nperseg;
                 sample += static_cast<int>(blockDim.x))
            {
                local_sum += frame_ptr[static_cast<std::size_t>(start + sample)];
            }
            shared_sum[threadIdx.x] = local_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared_sum[threadIdx.x] += shared_sum[threadIdx.x + stride];
                }
                __syncthreads();
            }
            const float mean = shared_sum[0] / static_cast<float>(nperseg);
            const std::size_t output_offset =
                segment_flat * static_cast<std::size_t>(nfft);
            for (int sample = static_cast<int>(threadIdx.x);
                 sample < nfft;
                 sample += static_cast<int>(blockDim.x))
            {
                const float value = sample < nperseg
                    ? (frame_ptr[static_cast<std::size_t>(start + sample)] - mean) *
                        window[static_cast<std::size_t>(sample)]
                    : 0.0f;
                storage[output_offset + static_cast<std::size_t>(sample)] =
                    make_float2(value, 0.0f);
            }
        }

        __global__ void reduce_task2_spectrogram_fft_kernel(
            const float2 *spectra,
            std::size_t segment_count,
            int nfft,
            int low_bin,
            int high_bin,
            float scale,
            float *time_energy)
        {
            __shared__ float shared_sum[kThreadsPerBlock];
            const std::size_t segment = static_cast<std::size_t>(blockIdx.x);
            if (segment >= segment_count)
            {
                return;
            }
            const float2 *segment_spectrum =
                spectra + segment * static_cast<std::size_t>(nfft);
            float local_sum = 0.0f;
            for (int bin = low_bin + static_cast<int>(threadIdx.x);
                 bin <= high_bin;
                 bin += static_cast<int>(blockDim.x))
            {
                const float2 value = segment_spectrum[static_cast<std::size_t>(bin)];
                local_sum += hypotf(value.x, value.y);
            }
            shared_sum[threadIdx.x] = local_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared_sum[threadIdx.x] += shared_sum[threadIdx.x + stride];
                }
                __syncthreads();
            }
            if (threadIdx.x == 0)
            {
                time_energy[segment] = shared_sum[0] * scale;
            }
        }

        __global__ void spectrogram_band_energy_kernel(
            const float *values,
            const float *freqs,
            std::size_t freq_count,
            std::size_t time_count,
            float band_low,
            float band_high,
            float *output)
        {
            const std::size_t time_index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (time_index >= time_count)
            {
                return;
            }

            float sum = 0.0f;
            for (std::size_t freq_index = 0; freq_index < freq_count; ++freq_index)
            {
                const float freq = freqs[freq_index];
                if (freq >= band_low && freq <= band_high)
                {
                    sum += values[freq_index * time_count + time_index];
                }
            }
            output[time_index] = sum;
        }

        __global__ void map_time_energy_kernel(
            const float *time_energy,
            const float *times,
            std::size_t time_count,
            int sample_count,
            float fs,
            float *output)
        {
            const std::size_t sample = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (sample >= static_cast<std::size_t>(sample_count))
            {
                return;
            }

            const float target_time = static_cast<float>(sample) / fs;
            std::size_t best_index = 0;
            float best_distance = fabsf(times[0] - target_time);
            for (std::size_t time_index = 1; time_index < time_count; ++time_index)
            {
                const float distance = fabsf(times[time_index] - target_time);
                if (distance < best_distance)
                {
                    best_distance = distance;
                    best_index = time_index;
                }
            }
            output[sample] = time_energy[best_index];
        }

        __global__ void batched_spectrogram_band_score_kernel(
            const float *values,
            const float *freqs,
            const float *times,
            std::size_t frames,
            std::size_t freq_count,
            std::size_t time_count,
            int sample_count,
            float band_low,
            float band_high,
            float fs,
            float *output)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = frames * static_cast<std::size_t>(sample_count);
            if (flat >= total)
            {
                return;
            }

            const std::size_t frame = flat / static_cast<std::size_t>(sample_count);
            const std::size_t sample = flat % static_cast<std::size_t>(sample_count);
            const float target_time = static_cast<float>(sample) / fs;
            std::size_t best_time = 0;
            float best_distance = fabsf(times[0] - target_time);
            for (std::size_t time_index = 1; time_index < time_count; ++time_index)
            {
                const float distance = fabsf(times[time_index] - target_time);
                if (distance < best_distance)
                {
                    best_distance = distance;
                    best_time = time_index;
                }
            }

            float sum = 0.0f;
            const std::size_t frame_offset = frame * freq_count * time_count;
            for (std::size_t freq_index = 0; freq_index < freq_count; ++freq_index)
            {
                const float freq = freqs[freq_index];
                if (freq >= band_low && freq <= band_high)
                {
                    sum += values[frame_offset + freq_index * time_count + best_time];
                }
            }
            output[flat] = sum;
        }

        __global__ void direct_spectrogram_band_energy_kernel(
            const float *frames,
            const float *cos_table,
            const float *sin_table,
            std::size_t frame_count,
            std::size_t sample_count,
            int nperseg,
            int step,
            int nseg,
            int band_bin_count,
            float scale,
            float *time_energy)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = frame_count * static_cast<std::size_t>(nseg);
            if (flat >= total)
            {
                return;
            }

            const std::size_t frame = flat / static_cast<std::size_t>(nseg);
            const int seg = static_cast<int>(flat % static_cast<std::size_t>(nseg));
            const float *frame_ptr = frames + frame * sample_count;
            float mean = 0.0f;
            const int start = seg * step;
            for (int sample = 0; sample < nperseg; ++sample)
            {
                mean += frame_ptr[static_cast<std::size_t>(start + sample)];
            }
            mean /= static_cast<float>(nperseg);

            float band_sum = 0.0f;
            for (int bin = 0; bin < band_bin_count; ++bin)
            {
                float real = 0.0f;
                float imag = 0.0f;
                const std::size_t table_offset = static_cast<std::size_t>(bin) * static_cast<std::size_t>(nperseg);
                for (int sample = 0; sample < nperseg; ++sample)
                {
                    const float value = frame_ptr[static_cast<std::size_t>(start + sample)] - mean;
                    real += value * cos_table[table_offset + static_cast<std::size_t>(sample)];
                    imag += value * sin_table[table_offset + static_cast<std::size_t>(sample)];
                }
                band_sum += hypotf(real, imag) * scale;
            }
            time_energy[flat] = band_sum;
        }

        __global__ void map_batched_time_energy_kernel(
            const float *time_energy,
            std::size_t frame_count,
            int nseg,
            int nperseg,
            int step,
            int sample_count,
            float fs,
            float *output)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = frame_count * static_cast<std::size_t>(sample_count);
            if (flat >= total)
            {
                return;
            }

            const std::size_t frame = flat / static_cast<std::size_t>(sample_count);
            const int sample = static_cast<int>(flat % static_cast<std::size_t>(sample_count));
            const float target_time = static_cast<float>(sample) / fs;
            int best_index = 0;
            float best_distance = fabsf(
                (0.5f * static_cast<float>(nperseg)) / fs - target_time);
            for (int time_index = 1; time_index < nseg; ++time_index)
            {
                const float segment_time =
                    (0.5f * static_cast<float>(nperseg) +
                     static_cast<float>(time_index * step)) / fs;
                const float distance = fabsf(segment_time - target_time);
                if (distance < best_distance)
                {
                    best_distance = distance;
                    best_index = time_index;
                }
            }
            output[flat] = time_energy[frame * static_cast<std::size_t>(nseg) + static_cast<std::size_t>(best_index)];
        }

        __global__ void direct_spectrogram_bin_energy_kernel(
            const float *frames,
            const float *cos_table,
            const float *sin_table,
            std::size_t sample_count,
            int nperseg,
            int step,
            int nseg,
            int band_bin_count,
            float scale,
            float *bin_energy)
        {
            __shared__ float shared_real[kThreadsPerBlock];
            __shared__ float shared_imag[kThreadsPerBlock];
            __shared__ float shared_sum[kThreadsPerBlock];

            const std::size_t block = static_cast<std::size_t>(blockIdx.x);
            const int bin = static_cast<int>(block % static_cast<std::size_t>(band_bin_count));
            const std::size_t segment_flat = block / static_cast<std::size_t>(band_bin_count);
            const int seg = static_cast<int>(segment_flat % static_cast<std::size_t>(nseg));
            const std::size_t frame = segment_flat / static_cast<std::size_t>(nseg);
            const float *frame_ptr = frames + frame * sample_count;
            const int start = seg * step;

            float local_sum = 0.0f;
            for (int sample = threadIdx.x; sample < nperseg; sample += blockDim.x)
            {
                local_sum += frame_ptr[static_cast<std::size_t>(start + sample)];
            }
            shared_sum[threadIdx.x] = local_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared_sum[threadIdx.x] += shared_sum[threadIdx.x + stride];
                }
                __syncthreads();
            }
            const float mean = shared_sum[0] / static_cast<float>(nperseg);

            float real = 0.0f;
            float imag = 0.0f;
            const std::size_t table_offset = static_cast<std::size_t>(bin) * static_cast<std::size_t>(nperseg);
            for (int sample = threadIdx.x; sample < nperseg; sample += blockDim.x)
            {
                const float value = frame_ptr[static_cast<std::size_t>(start + sample)] - mean;
                real += value * cos_table[table_offset + static_cast<std::size_t>(sample)];
                imag += value * sin_table[table_offset + static_cast<std::size_t>(sample)];
            }
            shared_real[threadIdx.x] = real;
            shared_imag[threadIdx.x] = imag;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared_real[threadIdx.x] += shared_real[threadIdx.x + stride];
                    shared_imag[threadIdx.x] += shared_imag[threadIdx.x + stride];
                }
                __syncthreads();
            }
            if (threadIdx.x == 0)
            {
                bin_energy[block] = hypotf(shared_real[0], shared_imag[0]) * scale;
            }
        }

        __global__ void reduce_spectrogram_band_bins_kernel(
            const float *bin_energy,
            std::size_t segment_count,
            int band_bin_count,
            float *time_energy)
        {
            __shared__ float shared[kThreadsPerBlock];
            const std::size_t segment = static_cast<std::size_t>(blockIdx.x);
            if (segment >= segment_count)
            {
                return;
            }

            float sum = 0.0f;
            for (int bin = threadIdx.x; bin < band_bin_count; bin += blockDim.x)
            {
                sum += bin_energy[segment * static_cast<std::size_t>(band_bin_count) + static_cast<std::size_t>(bin)];
            }
            shared[threadIdx.x] = sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared[threadIdx.x] += shared[threadIdx.x + stride];
                }
                __syncthreads();
            }
            if (threadIdx.x == 0)
            {
                time_energy[segment] = shared[0];
            }
        }

        __global__ void direct_spectrogram_segment_energy_kernel(
            const float *frames,
            const float *cos_table,
            const float *sin_table,
            std::size_t sample_count,
            int nperseg,
            int step,
            int nseg,
            int band_bin_count,
            float scale,
            float *time_energy)
        {
            __shared__ float shared[kThreadsPerBlock];
            __shared__ float shared_bin_energy[512];

            const std::size_t segment_flat = static_cast<std::size_t>(blockIdx.x);
            const int seg = static_cast<int>(segment_flat % static_cast<std::size_t>(nseg));
            const std::size_t frame = segment_flat / static_cast<std::size_t>(nseg);
            const float *frame_ptr = frames + frame * sample_count;
            const int start = seg * step;

            float mean_sum = 0.0f;
            for (int sample = threadIdx.x; sample < nperseg; sample += blockDim.x)
            {
                mean_sum += frame_ptr[static_cast<std::size_t>(start + sample)];
            }
            shared[threadIdx.x] = mean_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared[threadIdx.x] += shared[threadIdx.x + stride];
                }
                __syncthreads();
            }
            const float mean = shared[0] / static_cast<float>(nperseg);

            for (int bin = threadIdx.x; bin < band_bin_count; bin += blockDim.x)
            {
                float real = 0.0f;
                float imag = 0.0f;
                const std::size_t table_offset = static_cast<std::size_t>(bin) * static_cast<std::size_t>(nperseg);
                for (int sample = 0; sample < nperseg; ++sample)
                {
                    const float value = frame_ptr[static_cast<std::size_t>(start + sample)] - mean;
                    real += value * cos_table[table_offset + static_cast<std::size_t>(sample)];
                    imag += value * sin_table[table_offset + static_cast<std::size_t>(sample)];
                }
                shared_bin_energy[bin] = hypotf(real, imag) * scale;
            }
            __syncthreads();

            float local_sum = 0.0f;
            for (int bin = threadIdx.x; bin < band_bin_count; bin += blockDim.x)
            {
                local_sum += shared_bin_energy[bin];
            }
            shared[threadIdx.x] = local_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared[threadIdx.x] += shared[threadIdx.x + stride];
                }
                __syncthreads();
            }
            if (threadIdx.x == 0)
            {
                time_energy[segment_flat] = shared[0];
            }
        }

        __global__ void direct_spectrogram_segment_energy_large_kernel(
            const float *frames,
            const float *cos_table,
            const float *sin_table,
            std::size_t sample_count,
            int nperseg,
            int step,
            int nseg,
            int band_bin_count,
            float scale,
            float *time_energy)
        {
            __shared__ float shared[kThreadsPerBlock];
            __shared__ float shared_real[512];
            __shared__ float shared_imag[512];

            const std::size_t segment_flat = static_cast<std::size_t>(blockIdx.x);
            const int seg = static_cast<int>(segment_flat % static_cast<std::size_t>(nseg));
            const std::size_t frame = segment_flat / static_cast<std::size_t>(nseg);
            const float *frame_ptr = frames + frame * sample_count;
            const int start = seg * step;

            float mean_sum = 0.0f;
            for (int sample = threadIdx.x; sample < nperseg; sample += blockDim.x)
            {
                mean_sum += frame_ptr[static_cast<std::size_t>(start + sample)];
            }
            shared[threadIdx.x] = mean_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared[threadIdx.x] += shared[threadIdx.x + stride];
                }
                __syncthreads();
            }
            const float mean = shared[0] / static_cast<float>(nperseg);

            for (int bin = threadIdx.x; bin < band_bin_count; bin += blockDim.x)
            {
                shared_real[bin] = 0.0f;
                shared_imag[bin] = 0.0f;
            }
            __syncthreads();

            const int total_terms = band_bin_count * nperseg;
            for (int term = threadIdx.x; term < total_terms; term += blockDim.x)
            {
                const int bin = term / nperseg;
                const int sample = term % nperseg;
                const std::size_t table_index =
                    static_cast<std::size_t>(bin) * static_cast<std::size_t>(nperseg) +
                    static_cast<std::size_t>(sample);
                const float value = frame_ptr[static_cast<std::size_t>(start + sample)] - mean;
                atomicAdd(&shared_real[bin], value * cos_table[table_index]);
                atomicAdd(&shared_imag[bin], value * sin_table[table_index]);
            }
            __syncthreads();

            float local_sum = 0.0f;
            for (int bin = threadIdx.x; bin < band_bin_count; bin += blockDim.x)
            {
                local_sum += hypotf(shared_real[bin], shared_imag[bin]) * scale;
            }
            shared[threadIdx.x] = local_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared[threadIdx.x] += shared[threadIdx.x + stride];
                }
                __syncthreads();
            }
            if (threadIdx.x == 0)
            {
                time_energy[segment_flat] = shared[0];
            }
        }

        __global__ void direct_spectrogram_segment_energy_grouped_kernel(
            const float *frames,
            const float *cos_table,
            const float *sin_table,
            std::size_t sample_count,
            int nperseg,
            int step,
            int nseg,
            int band_bin_count,
            float scale,
            float *time_energy)
        {
            constexpr int kBinGroupSize = 8;
            constexpr int kBinGroupsPerBlock = kThreadsPerBlock / kBinGroupSize;
            __shared__ float shared[kThreadsPerBlock];
            __shared__ float shared_bin_energy[512];

            const std::size_t segment_flat = static_cast<std::size_t>(blockIdx.x);
            const int seg = static_cast<int>(segment_flat % static_cast<std::size_t>(nseg));
            const std::size_t frame = segment_flat / static_cast<std::size_t>(nseg);
            const float *frame_ptr = frames + frame * sample_count;
            const int start = seg * step;

            float mean_sum = 0.0f;
            for (int sample = threadIdx.x; sample < nperseg; sample += blockDim.x)
            {
                mean_sum += frame_ptr[static_cast<std::size_t>(start + sample)];
            }
            shared[threadIdx.x] = mean_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared[threadIdx.x] += shared[threadIdx.x + stride];
                }
                __syncthreads();
            }
            const float mean = shared[0] / static_cast<float>(nperseg);

            const int lane = threadIdx.x % kBinGroupSize;
            const int group = threadIdx.x / kBinGroupSize;
            for (int bin_base = 0; bin_base < band_bin_count; bin_base += kBinGroupsPerBlock)
            {
                const int bin = bin_base + group;
                float real = 0.0f;
                float imag = 0.0f;
                if (bin < band_bin_count)
                {
                    const std::size_t table_offset =
                        static_cast<std::size_t>(bin) * static_cast<std::size_t>(nperseg);
                    for (int sample = lane; sample < nperseg; sample += kBinGroupSize)
                    {
                        const float value = frame_ptr[static_cast<std::size_t>(start + sample)] - mean;
                        real += value * cos_table[table_offset + static_cast<std::size_t>(sample)];
                        imag += value * sin_table[table_offset + static_cast<std::size_t>(sample)];
                    }
                }
                for (int offset = kBinGroupSize / 2; offset > 0; offset >>= 1)
                {
                    real += __shfl_down_sync(0xffffffffu, real, offset, kBinGroupSize);
                    imag += __shfl_down_sync(0xffffffffu, imag, offset, kBinGroupSize);
                }
                if (lane == 0 && bin < band_bin_count)
                {
                    shared_bin_energy[bin] = hypotf(real, imag) * scale;
                }
            }
            __syncthreads();

            float local_sum = 0.0f;
            for (int bin = threadIdx.x; bin < band_bin_count; bin += blockDim.x)
            {
                local_sum += shared_bin_energy[bin];
            }
            shared[threadIdx.x] = local_sum;
            __syncthreads();
            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    shared[threadIdx.x] += shared[threadIdx.x + stride];
                }
                __syncthreads();
            }
            if (threadIdx.x == 0)
            {
                time_energy[segment_flat] = shared[0];
            }
        }

        __global__ void cwt_max_kernel(
            const float2 *values,
            std::size_t widths,
            std::size_t samples,
            float *output)
        {
            const std::size_t sample = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (sample >= samples)
            {
                return;
            }

            float best = 0.0f;
            for (std::size_t width_index = 0; width_index < widths; ++width_index)
            {
                const float2 value = values[width_index * samples + sample];
                const float magnitude = sqrtf(value.x * value.x + value.y * value.y);
                best = fmaxf(best, magnitude);
            }
            output[sample] = best;
        }

        __global__ void batched_cwt_kernel(
            const float *frames,
            std::size_t frame_count,
            std::size_t sample_count,
            std::size_t width_count,
            const int *kernel_sizes,
            const int *kernel_starts,
            const int *kernel_offsets,
            const float *kernel_real,
            const float *kernel_imag,
            float2 *output)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = frame_count * width_count * sample_count;
            if (flat >= total)
            {
                return;
            }

            const std::size_t sample = flat % sample_count;
            const std::size_t width_index = (flat / sample_count) % width_count;
            const std::size_t frame = flat / (sample_count * width_count);
            const int kernel_size = kernel_sizes[width_index];
            if (kernel_size <= 0 || sample_count == 0)
            {
                output[flat] = make_float2(0.0f, 0.0f);
                return;
            }

            const int start = kernel_starts[width_index];
            const int kernel_offset = kernel_offsets[width_index];
            const float *frame_ptr = frames + frame * sample_count;
            float real = 0.0f;
            float imag = 0.0f;
            for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
            {
                const long sample_index =
                    static_cast<long>(sample) + static_cast<long>(start) -
                    static_cast<long>(kernel_index);
                if (sample_index < 0 || sample_index >= static_cast<long>(sample_count))
                {
                    continue;
                }
                const float value = frame_ptr[static_cast<std::size_t>(sample_index)];
                const std::size_t table_index = static_cast<std::size_t>(kernel_offset + kernel_index);
                real = fmaf(value, kernel_real[table_index], real);
                imag = fmaf(value, kernel_imag[table_index], imag);
            }
            output[flat] = make_float2(real, imag);
        }

        __global__ void batched_cwt_max_kernel(
            const float2 *values,
            std::size_t frame_count,
            std::size_t width_count,
            std::size_t sample_count,
            float *output)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = frame_count * sample_count;
            if (flat >= total)
            {
                return;
            }

            const std::size_t frame = flat / sample_count;
            const std::size_t sample = flat % sample_count;
            const std::size_t frame_offset = frame * width_count * sample_count;
            float best = 0.0f;
            for (std::size_t width_index = 0; width_index < width_count; ++width_index)
            {
                const float2 value = values[frame_offset + width_index * sample_count + sample];
                best = fmaxf(best, hypotf(value.x, value.y));
            }
            output[flat] = best;
        }

        __global__ void batched_cwt_max_score_fused_kernel(
            const float *frames,
            std::size_t frame_count,
            std::size_t sample_count,
            std::size_t width_count,
            const int *kernel_sizes,
            const int *kernel_starts,
            const int *kernel_offsets,
            const float *kernel_real,
            const float *kernel_imag,
            float *output)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = frame_count * sample_count;
            if (flat >= total)
            {
                return;
            }

            const std::size_t frame = flat / sample_count;
            const std::size_t sample = flat % sample_count;
            const float *frame_ptr = frames + frame * sample_count;
            float best_sq = 0.0f;
            for (std::size_t width_index = 0; width_index < width_count; ++width_index)
            {
                const int kernel_size = kernel_sizes[width_index];
                if (kernel_size <= 0)
                {
                    continue;
                }
                const int start = kernel_starts[width_index];
                const int kernel_offset = kernel_offsets[width_index];
                float real = 0.0f;
                float imag = 0.0f;
                for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
                {
                    const long sample_index =
                        static_cast<long>(sample) + static_cast<long>(start) -
                        static_cast<long>(kernel_index);
                    if (sample_index < 0 || sample_index >= static_cast<long>(sample_count))
                    {
                        continue;
                    }
                    const float value = frame_ptr[static_cast<std::size_t>(sample_index)];
                    const std::size_t table_index = static_cast<std::size_t>(kernel_offset + kernel_index);
                    real = fmaf(value, kernel_real[table_index], real);
                    imag = fmaf(value, kernel_imag[table_index], imag);
                }
                best_sq = fmaxf(best_sq, fmaf(real, real, imag * imag));
            }
            output[flat] = sqrtf(best_sq);
        }

        template <bool UseSymmetricPairs>
        __global__ void batched_cwt_max_score_shared_kernel(
            const float *frames,
            std::size_t frame_count,
            std::size_t sample_count,
            std::size_t width_count,
            const int *kernel_sizes,
            const int *kernel_starts,
            const int *kernel_offsets,
            const float *kernel_real,
            const float *kernel_imag,
            float *output)
        {
            const std::size_t frame = static_cast<std::size_t>(blockIdx.y);
            const std::size_t outputs_per_block =
                2 * static_cast<std::size_t>(blockDim.x);
            const std::size_t tile_start =
                static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
            if (frame >= frame_count)
            {
                return;
            }

            extern __shared__ float tile_data[];
            const std::size_t sample0 = tile_start + threadIdx.x;
            const std::size_t sample1 = sample0 + static_cast<std::size_t>(blockDim.x);
            const float *frame_ptr = frames + frame * sample_count;
            float best_sq0 = 0.0f;
            float best_sq1 = 0.0f;
            for (std::size_t width_index = 0; width_index < width_count; ++width_index)
            {
                const int kernel_size = kernel_sizes[width_index];
                if (kernel_size <= 0)
                {
                    continue;
                }

                const int start = kernel_starts[width_index];
                const long tile_base =
                    static_cast<long>(tile_start) + static_cast<long>(start) -
                    static_cast<long>(kernel_size - 1);
                const std::size_t tile_size =
                    outputs_per_block +
                    static_cast<std::size_t>(kernel_size) - 1;
                for (std::size_t local_index = threadIdx.x;
                     local_index < tile_size;
                     local_index += blockDim.x)
                {
                    const long global_index = tile_base + static_cast<long>(local_index);
                    tile_data[local_index] =
                        global_index >= 0 && global_index < static_cast<long>(sample_count)
                        ? frame_ptr[static_cast<std::size_t>(global_index)]
                        : 0.0f;
                }
                __syncthreads();

                if (sample0 < sample_count)
                {
                    const int kernel_offset = kernel_offsets[width_index];
                    float real0 = 0.0f;
                    float imag0 = 0.0f;
                    float real1 = 0.0f;
                    float imag1 = 0.0f;
                    if constexpr (UseSymmetricPairs)
                    {
                        const int pair_count = kernel_size / 2;
                        for (int kernel_index = 0; kernel_index < pair_count; ++kernel_index)
                        {
                            const std::size_t shared_index_left =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_size - 1 - kernel_index);
                            const std::size_t shared_index_right =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_index);
                            const std::size_t table_index =
                                static_cast<std::size_t>(kernel_offset + kernel_index);
                            const float coeff_real = kernel_real[table_index];
                            const float coeff_imag = kernel_imag[table_index];
                            const float value0_left = tile_data[shared_index_left];
                            const float value0_right = tile_data[shared_index_right];
                            const float value1_left = tile_data[shared_index_left + blockDim.x];
                            const float value1_right = tile_data[shared_index_right + blockDim.x];
                            real0 = fmaf(value0_left + value0_right, coeff_real, real0);
                            imag0 = fmaf(value0_left - value0_right, coeff_imag, imag0);
                            real1 = fmaf(value1_left + value1_right, coeff_real, real1);
                            imag1 = fmaf(value1_left - value1_right, coeff_imag, imag1);
                        }
                        if ((kernel_size & 1) != 0)
                        {
                            const int kernel_index = pair_count;
                            const std::size_t shared_index =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_size - 1 - kernel_index);
                            const std::size_t table_index =
                                static_cast<std::size_t>(kernel_offset + kernel_index);
                            const float coeff_real = kernel_real[table_index];
                            const float coeff_imag = kernel_imag[table_index];
                            const float value0 = tile_data[shared_index];
                            const float value1 = tile_data[shared_index + blockDim.x];
                            real0 = fmaf(value0, coeff_real, real0);
                            imag0 = fmaf(value0, coeff_imag, imag0);
                            real1 = fmaf(value1, coeff_real, real1);
                            imag1 = fmaf(value1, coeff_imag, imag1);
                        }
                    }
                    else
                    {
                        for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
                        {
                            const std::size_t shared_index0 =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_size - 1 - kernel_index);
                            const std::size_t table_index =
                                static_cast<std::size_t>(kernel_offset + kernel_index);
                            const float coeff_real = kernel_real[table_index];
                            const float coeff_imag = kernel_imag[table_index];
                            const float value0 = tile_data[shared_index0];
                            const float value1 = tile_data[shared_index0 + blockDim.x];
                            real0 = fmaf(value0, coeff_real, real0);
                            imag0 = fmaf(value0, coeff_imag, imag0);
                            real1 = fmaf(value1, coeff_real, real1);
                            imag1 = fmaf(value1, coeff_imag, imag1);
                        }
                    }
                    best_sq0 = fmaxf(best_sq0, fmaf(real0, real0, imag0 * imag0));
                    best_sq1 = fmaxf(best_sq1, fmaf(real1, real1, imag1 * imag1));
                }
                __syncthreads();
            }

            if (sample0 < sample_count)
            {
                output[frame * sample_count + sample0] = sqrtf(best_sq0);
            }
            if (sample1 < sample_count)
            {
                output[frame * sample_count + sample1] = sqrtf(best_sq1);
            }
        }

        template <bool UseSymmetricPairs>
        __global__ void batched_cwt_max_score_shared_quad_kernel(
            const float *frames,
            std::size_t frame_count,
            std::size_t sample_count,
            std::size_t width_count,
            const int *kernel_sizes,
            const int *kernel_starts,
            const int *kernel_offsets,
            const float *kernel_real,
            const float *kernel_imag,
            float *output)
        {
            const std::size_t frame = static_cast<std::size_t>(blockIdx.y);
            const std::size_t outputs_per_block =
                4 * static_cast<std::size_t>(blockDim.x);
            const std::size_t tile_start =
                static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
            if (frame >= frame_count)
            {
                return;
            }

            extern __shared__ float tile_data[];
            const std::size_t sample0 = tile_start + threadIdx.x;
            const std::size_t sample1 = sample0 + static_cast<std::size_t>(blockDim.x);
            const std::size_t sample2 = sample1 + static_cast<std::size_t>(blockDim.x);
            const std::size_t sample3 = sample2 + static_cast<std::size_t>(blockDim.x);
            const float *frame_ptr = frames + frame * sample_count;
            float best_sq0 = 0.0f;
            float best_sq1 = 0.0f;
            float best_sq2 = 0.0f;
            float best_sq3 = 0.0f;
            for (std::size_t width_index = 0; width_index < width_count; ++width_index)
            {
                const int kernel_size = kernel_sizes[width_index];
                if (kernel_size <= 0)
                {
                    continue;
                }

                const int start = kernel_starts[width_index];
                const long tile_base =
                    static_cast<long>(tile_start) + static_cast<long>(start) -
                    static_cast<long>(kernel_size - 1);
                const std::size_t tile_size =
                    outputs_per_block +
                    static_cast<std::size_t>(kernel_size) - 1;
                for (std::size_t local_index = threadIdx.x;
                     local_index < tile_size;
                     local_index += blockDim.x)
                {
                    const long global_index = tile_base + static_cast<long>(local_index);
                    tile_data[local_index] =
                        global_index >= 0 && global_index < static_cast<long>(sample_count)
                        ? frame_ptr[static_cast<std::size_t>(global_index)]
                        : 0.0f;
                }
                __syncthreads();

                if (sample0 < sample_count)
                {
                    const int kernel_offset = kernel_offsets[width_index];
                    float real0 = 0.0f;
                    float imag0 = 0.0f;
                    float real1 = 0.0f;
                    float imag1 = 0.0f;
                    float real2 = 0.0f;
                    float imag2 = 0.0f;
                    float real3 = 0.0f;
                    float imag3 = 0.0f;
                    if constexpr (UseSymmetricPairs)
                    {
                        const int pair_count = kernel_size / 2;
                        for (int kernel_index = 0; kernel_index < pair_count; ++kernel_index)
                        {
                            const std::size_t shared_index_left =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_size - 1 - kernel_index);
                            const std::size_t shared_index_right =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_index);
                            const std::size_t table_index =
                                static_cast<std::size_t>(kernel_offset + kernel_index);
                            const float coeff_real = kernel_real[table_index];
                            const float coeff_imag = kernel_imag[table_index];
                            const float value0_left = tile_data[shared_index_left];
                            const float value0_right = tile_data[shared_index_right];
                            const float value1_left = tile_data[shared_index_left + blockDim.x];
                            const float value1_right = tile_data[shared_index_right + blockDim.x];
                            const float value2_left = tile_data[shared_index_left + 2 * blockDim.x];
                            const float value2_right = tile_data[shared_index_right + 2 * blockDim.x];
                            const float value3_left = tile_data[shared_index_left + 3 * blockDim.x];
                            const float value3_right = tile_data[shared_index_right + 3 * blockDim.x];
                            real0 = fmaf(value0_left + value0_right, coeff_real, real0);
                            imag0 = fmaf(value0_left - value0_right, coeff_imag, imag0);
                            real1 = fmaf(value1_left + value1_right, coeff_real, real1);
                            imag1 = fmaf(value1_left - value1_right, coeff_imag, imag1);
                            real2 = fmaf(value2_left + value2_right, coeff_real, real2);
                            imag2 = fmaf(value2_left - value2_right, coeff_imag, imag2);
                            real3 = fmaf(value3_left + value3_right, coeff_real, real3);
                            imag3 = fmaf(value3_left - value3_right, coeff_imag, imag3);
                        }
                        if ((kernel_size & 1) != 0)
                        {
                            const int kernel_index = pair_count;
                            const std::size_t shared_index =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_size - 1 - kernel_index);
                            const std::size_t table_index =
                                static_cast<std::size_t>(kernel_offset + kernel_index);
                            const float coeff_real = kernel_real[table_index];
                            const float coeff_imag = kernel_imag[table_index];
                            const float value0 = tile_data[shared_index];
                            const float value1 = tile_data[shared_index + blockDim.x];
                            const float value2 = tile_data[shared_index + 2 * blockDim.x];
                            const float value3 = tile_data[shared_index + 3 * blockDim.x];
                            real0 = fmaf(value0, coeff_real, real0);
                            imag0 = fmaf(value0, coeff_imag, imag0);
                            real1 = fmaf(value1, coeff_real, real1);
                            imag1 = fmaf(value1, coeff_imag, imag1);
                            real2 = fmaf(value2, coeff_real, real2);
                            imag2 = fmaf(value2, coeff_imag, imag2);
                            real3 = fmaf(value3, coeff_real, real3);
                            imag3 = fmaf(value3, coeff_imag, imag3);
                        }
                    }
                    else
                    {
                        for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
                        {
                            const std::size_t shared_index0 =
                                static_cast<std::size_t>(threadIdx.x) +
                                static_cast<std::size_t>(kernel_size - 1 - kernel_index);
                            const std::size_t table_index =
                                static_cast<std::size_t>(kernel_offset + kernel_index);
                            const float coeff_real = kernel_real[table_index];
                            const float coeff_imag = kernel_imag[table_index];
                            const float value0 = tile_data[shared_index0];
                            const float value1 = tile_data[shared_index0 + blockDim.x];
                            const float value2 = tile_data[shared_index0 + 2 * blockDim.x];
                            const float value3 = tile_data[shared_index0 + 3 * blockDim.x];
                            real0 = fmaf(value0, coeff_real, real0);
                            imag0 = fmaf(value0, coeff_imag, imag0);
                            real1 = fmaf(value1, coeff_real, real1);
                            imag1 = fmaf(value1, coeff_imag, imag1);
                            real2 = fmaf(value2, coeff_real, real2);
                            imag2 = fmaf(value2, coeff_imag, imag2);
                            real3 = fmaf(value3, coeff_real, real3);
                            imag3 = fmaf(value3, coeff_imag, imag3);
                        }
                    }
                    best_sq0 = fmaxf(best_sq0, fmaf(real0, real0, imag0 * imag0));
                    best_sq1 = fmaxf(best_sq1, fmaf(real1, real1, imag1 * imag1));
                    best_sq2 = fmaxf(best_sq2, fmaf(real2, real2, imag2 * imag2));
                    best_sq3 = fmaxf(best_sq3, fmaf(real3, real3, imag3 * imag3));
                }
                __syncthreads();
            }

            if (sample0 < sample_count)
            {
                output[frame * sample_count + sample0] = sqrtf(best_sq0);
            }
            if (sample1 < sample_count)
            {
                output[frame * sample_count + sample1] = sqrtf(best_sq1);
            }
            if (sample2 < sample_count)
            {
                output[frame * sample_count + sample2] = sqrtf(best_sq2);
            }
            if (sample3 < sample_count)
            {
                output[frame * sample_count + sample3] = sqrtf(best_sq3);
            }
        }

        __global__ void weighted_sum_kernel(
            const float *corr_score,
            const float *demod_score,
            const float *wavelet_score,
            const float *spectrogram_score,
            float corr_weight,
            float demod_weight,
            float wavelet_weight,
            float spectrogram_weight,
            std::size_t size,
            float *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index < size)
            {
                output[index] =
                    corr_weight * corr_score[index] +
                    demod_weight * demod_score[index] +
                    wavelet_weight * wavelet_score[index] +
                    spectrogram_weight * spectrogram_score[index];
            }
        }

        __global__ void smooth_kernel(
            const float *input,
            std::size_t size,
            const float *weights,
            std::size_t weight_count,
            float *output)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index >= size)
            {
                return;
            }

            const int radius = static_cast<int>(weight_count / 2);
            float sum = 0.0f;
            for (std::size_t weight_index = 0; weight_index < weight_count; ++weight_index)
            {
                int sample_index = static_cast<int>(index) + static_cast<int>(weight_index) - radius;
                sample_index = max(0, min(sample_index, static_cast<int>(size) - 1));
                sum += weights[weight_index] * input[static_cast<std::size_t>(sample_index)];
            }
            output[index] = sum;
        }

        __device__ float weighted_feature_value(
            const float *corr_score,
            const float *demod_score,
            const float *wavelet_score,
            const float *spectrogram_score,
            std::size_t offset)
        {
            return 0.45f * corr_score[offset] +
                0.20f * demod_score[offset] +
                0.20f * wavelet_score[offset] +
                0.15f * spectrogram_score[offset];
        }

        __global__ void fused_feature_smooth_kernel(
            const float *corr_score,
            const float *demod_score,
            const float *wavelet_score,
            const float *spectrogram_score,
            const float *weights,
            std::size_t weight_count,
            std::size_t rows,
            std::size_t cols,
            float *feature_score)
        {
            const std::size_t flat = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            const std::size_t total = rows * cols;
            if (flat >= total)
            {
                return;
            }

            const std::size_t row = flat / cols;
            const std::size_t col = flat % cols;
            const int radius = static_cast<int>(weight_count / 2);
            float sum = 0.0f;
            for (std::size_t weight_index = 0; weight_index < weight_count; ++weight_index)
            {
                int sample_index = static_cast<int>(col) + static_cast<int>(weight_index) - radius;
                sample_index = max(0, min(sample_index, static_cast<int>(cols) - 1));
                const std::size_t source = row * cols + static_cast<std::size_t>(sample_index);
                sum += weights[weight_index] *
                    weighted_feature_value(corr_score, demod_score, wavelet_score, spectrogram_score, source);
            }
            feature_score[flat] = sum;
        }

        __device__ bool is_clip_argrelmax(
            const float *score,
            std::size_t row_offset,
            std::size_t col,
            std::size_t cols,
            int order)
        {
            const float center = score[row_offset + col];
            for (int shift = 1; shift <= order; ++shift)
            {
                const long long plus_raw = static_cast<long long>(col) + shift;
                const long long minus_raw = static_cast<long long>(col) - shift;
                const std::size_t plus = static_cast<std::size_t>(
                    min(max(plus_raw, 0LL), static_cast<long long>(cols - 1)));
                const std::size_t minus = static_cast<std::size_t>(
                    min(max(minus_raw, 0LL), static_cast<long long>(cols - 1)));
                if (!(center > score[row_offset + plus] && center > score[row_offset + minus]))
                {
                    return false;
                }
            }
            return true;
        }

        __global__ void row_peak_track_kernel(
            const float *feature_score,
            std::size_t rows,
            std::size_t cols,
            int order,
            float *peak_track)
        {
            __shared__ float global_value[kThreadsPerBlock];
            __shared__ int global_index[kThreadsPerBlock];
            __shared__ float extrema_value[kThreadsPerBlock];
            __shared__ int extrema_index[kThreadsPerBlock];
            __shared__ int extrema_found[kThreadsPerBlock];

            const std::size_t row = static_cast<std::size_t>(blockIdx.x);
            const unsigned int tid = threadIdx.x;
            if (row >= rows)
            {
                return;
            }

            const std::size_t row_offset = row * cols;
            float best_global = -1.0e30f;
            int best_global_index = 0;
            float best_extrema = -1.0e30f;
            int best_extrema_index = 0;
            int found_extrema = 0;

            for (std::size_t col = tid; col < cols; col += blockDim.x)
            {
                const float value = feature_score[row_offset + col];
                if (value > best_global)
                {
                    best_global = value;
                    best_global_index = static_cast<int>(col);
                }
                if (is_clip_argrelmax(feature_score, row_offset, col, cols, order))
                {
                    if (!found_extrema || value > best_extrema)
                    {
                        best_extrema = value;
                        best_extrema_index = static_cast<int>(col);
                        found_extrema = 1;
                    }
                }
            }

            global_value[tid] = best_global;
            global_index[tid] = best_global_index;
            extrema_value[tid] = best_extrema;
            extrema_index[tid] = best_extrema_index;
            extrema_found[tid] = found_extrema;
            __syncthreads();

            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (tid < stride)
                {
                    if (global_value[tid + stride] > global_value[tid])
                    {
                        global_value[tid] = global_value[tid + stride];
                        global_index[tid] = global_index[tid + stride];
                    }
                    if (extrema_found[tid + stride] &&
                        (!extrema_found[tid] || extrema_value[tid + stride] > extrema_value[tid]))
                    {
                        extrema_found[tid] = 1;
                        extrema_value[tid] = extrema_value[tid + stride];
                        extrema_index[tid] = extrema_index[tid + stride];
                    }
                }
                __syncthreads();
            }

            if (tid == 0)
            {
                peak_track[row] = static_cast<float>(
                    extrema_found[0] ? extrema_index[0] : global_index[0]);
            }
        }

        __global__ void kalman_track_from_peaks_kernel(
            const float *peak_track,
            std::size_t frame_count,
            float *kalman_track)
        {
            if (threadIdx.x != 0 || blockIdx.x != 0 || frame_count == 0)
            {
                return;
            }

            float x0 = peak_track[0];
            float x1 = 0.0f;
            float p00 = 25.0f;
            float p01 = 0.0f;
            float p10 = 0.0f;
            float p11 = 4.0f;
            kalman_track[0] = x0;

            for (std::size_t frame = 1; frame < frame_count; ++frame)
            {
                const float pred_x0 = x0 + x1;
                const float pred_x1 = x1;
                const float pred_p00 = p00 + p10 + p01 + p11 + 0.25f;
                const float pred_p01 = p01 + p11;
                const float pred_p10 = p10 + p11;
                const float pred_p11 = p11 + 0.05f;

                const float innovation = peak_track[frame] - pred_x0;
                const float inv_s = 1.0f / (pred_p00 + 4.0f);
                const float k0 = pred_p00 * inv_s;
                const float k1 = pred_p10 * inv_s;

                x0 = pred_x0 + k0 * innovation;
                x1 = pred_x1 + k1 * innovation;
                p00 = (1.0f - k0) * pred_p00;
                p01 = (1.0f - k0) * pred_p01;
                p10 = -k1 * pred_p00 + pred_p10;
                p11 = -k1 * pred_p01 + pred_p11;
                kalman_track[frame] = x0;
            }
        }

        __global__ void copy_measurement_track_kernel(
            const float *peak_track,
            std::size_t frame_count,
            float *measurement_track)
        {
            const std::size_t index = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (index < frame_count)
            {
                measurement_track[index] = peak_track[index];
            }
        }

        __global__ void argmax_all_kernel(
            const float *score,
            std::size_t size,
            int *index_out)
        {
            __shared__ float shared_value[kThreadsPerBlock];
            __shared__ int shared_index[kThreadsPerBlock];
            const unsigned int tid = threadIdx.x;
            float best_value = -1.0e30f;
            int best_index = 0;
            for (std::size_t index = tid; index < size; index += blockDim.x)
            {
                const float value = score[index];
                if (value > best_value)
                {
                    best_value = value;
                    best_index = static_cast<int>(index);
                }
            }
            shared_value[tid] = best_value;
            shared_index[tid] = best_index;
            __syncthreads();

            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (tid < stride)
                {
                    if (shared_value[tid + stride] > shared_value[tid])
                    {
                        shared_value[tid] = shared_value[tid + stride];
                        shared_index[tid] = shared_index[tid + stride];
                    }
                }
                __syncthreads();
            }

            if (tid == 0)
            {
                index_out[0] = shared_index[0];
            }
        }

        __global__ void argmax_candidates_kernel(
            const float *score,
            const int *candidates,
            std::size_t candidate_count,
            int *index_out)
        {
            __shared__ float shared_value[kThreadsPerBlock];
            __shared__ int shared_index[kThreadsPerBlock];
            const unsigned int tid = threadIdx.x;
            float best_value = -1.0e30f;
            int best_index = 0;
            for (std::size_t index = tid; index < candidate_count; index += blockDim.x)
            {
                const int candidate = candidates[index];
                const float value = score[static_cast<std::size_t>(candidate)];
                if (value > best_value)
                {
                    best_value = value;
                    best_index = candidate;
                }
            }
            shared_value[tid] = best_value;
            shared_index[tid] = best_index;
            __syncthreads();

            for (unsigned int stride = blockDim.x / 2; stride > 0; stride >>= 1)
            {
                if (tid < stride)
                {
                    if (shared_value[tid + stride] > shared_value[tid])
                    {
                        shared_value[tid] = shared_value[tid + stride];
                        shared_index[tid] = shared_index[tid + stride];
                    }
                }
                __syncthreads();
            }

            if (tid == 0)
            {
                index_out[0] = shared_index[0];
            }
        }

        __global__ void index_to_measurement_kernel(
            const int *index,
            float *measurement)
        {
            measurement[0] = static_cast<float>(index[0]);
        }

        __global__ void initialize_state_from_index_kernel(
            const int *index,
            float *state,
            std::size_t state_size)
        {
            const std::size_t offset = static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x) +
                static_cast<std::size_t>(threadIdx.x);
            if (offset >= state_size)
            {
                return;
            }
            state[offset] = (offset == 0) ? static_cast<float>(index[0]) : 0.0f;
        }

        __global__ void write_index_to_track_kernel(
            const int *index,
            float *track,
            int frame_index)
        {
            track[static_cast<std::size_t>(frame_index)] = static_cast<float>(index[0]);
        }

        __global__ void write_state_position_to_track_kernel(
            const float *state,
            float *track,
            int frame_index)
        {
            track[static_cast<std::size_t>(frame_index)] = state[0];
        }

        bool same_values(const std::vector<float> &lhs, const std::vector<float> &rhs)
        {
            return lhs.size() == rhs.size() &&
                std::equal(lhs.begin(), lhs.end(), rhs.begin());
        }

        float prepare_direct_spectrogram_tables(
            const ZxGpuRealSignal &window,
            int nperseg,
            int nfft,
            int low_bin,
            int high_bin,
            float fs)
        {
            const std::vector<float> host_window = window.get();
            const bool cache_hit =
                g_workspace.direct_spectrogram_table_valid &&
                g_workspace.cached_direct_nperseg == nperseg &&
                g_workspace.cached_direct_nfft == nfft &&
                g_workspace.cached_direct_low_bin == low_bin &&
                g_workspace.cached_direct_high_bin == high_bin &&
                g_workspace.cached_direct_fs == fs &&
                same_values(g_workspace.cached_direct_window, host_window);
            if (cache_hit)
            {
                return g_workspace.cached_direct_scale;
            }

            const float window_sum = host_window.empty()
                ? 0.0f
                : std::accumulate(host_window.begin(), host_window.end(), 0.0f);
            const float scale = std::fabs(window_sum) > 1.0e-12f ? (1.0f / std::fabs(window_sum)) : 0.0f;
            const int band_bin_count = high_bin - low_bin + 1;
            std::vector<float> cos_table(static_cast<std::size_t>(band_bin_count) * static_cast<std::size_t>(nperseg));
            std::vector<float> sin_table(cos_table.size());
            for (int bin_index = 0; bin_index < band_bin_count; ++bin_index)
            {
                const int bin = low_bin + bin_index;
                const std::size_t table_offset = static_cast<std::size_t>(bin_index) * static_cast<std::size_t>(nperseg);
                for (int sample = 0; sample < nperseg; ++sample)
                {
                    const float angle =
                        -2.0f * 3.14159265358979323846f *
                        static_cast<float>(bin * sample) / static_cast<float>(nfft);
                    const float win = host_window[static_cast<std::size_t>(sample)];
                    cos_table[table_offset + static_cast<std::size_t>(sample)] = win * std::cos(angle);
                    sin_table[table_offset + static_cast<std::size_t>(sample)] = win * std::sin(angle);
                }
            }

            g_workspace.direct_cos_table = ZxGpuRealArray::from_host(
                {Shape{static_cast<std::size_t>(band_bin_count), static_cast<std::size_t>(nperseg)},
                 std::move(cos_table)});
            g_workspace.direct_sin_table = ZxGpuRealArray::from_host(
                {Shape{static_cast<std::size_t>(band_bin_count), static_cast<std::size_t>(nperseg)},
                 std::move(sin_table)});
            g_workspace.cached_direct_window = std::move(host_window);
            g_workspace.cached_direct_nperseg = nperseg;
            g_workspace.cached_direct_nfft = nfft;
            g_workspace.cached_direct_low_bin = low_bin;
            g_workspace.cached_direct_high_bin = high_bin;
            g_workspace.cached_direct_fs = fs;
            g_workspace.cached_direct_scale = scale;
            g_workspace.direct_spectrogram_table_valid = true;
            return scale;
        }

        void prepare_cwt_kernel_table(
            const RealSignal &widths,
            std::size_t sample_count)
        {
            const bool cache_hit =
                g_workspace.cwt_kernel_table_valid &&
                g_workspace.cached_cwt_sample_count == sample_count &&
                same_values(g_workspace.cached_cwt_widths, widths);
            if (cache_hit)
            {
                return;
            }

            const wavelets_detail::CwtKernelTable kernel_table =
                wavelets_detail::build_cwt_kernel_table(widths, sample_count, "morlet2");
            g_workspace.cached_cwt_max_kernel_size = kernel_table.kernel_sizes.empty()
                ? 0
                : static_cast<std::size_t>(*std::max_element(
                      kernel_table.kernel_sizes.begin(),
                      kernel_table.kernel_sizes.end()));
            g_workspace.cached_cwt_kernel_symmetric = true;
            for (std::size_t width_index = 0;
                 width_index < kernel_table.kernel_sizes.size() &&
                 g_workspace.cached_cwt_kernel_symmetric;
                 ++width_index)
            {
                const int kernel_size = kernel_table.kernel_sizes[width_index];
                const int kernel_offset = kernel_table.kernel_offsets[width_index];
                for (int kernel_index = 0; kernel_index < kernel_size / 2; ++kernel_index)
                {
                    const int mirror_index = kernel_size - 1 - kernel_index;
                    const std::size_t table_index =
                        static_cast<std::size_t>(kernel_offset + kernel_index);
                    const std::size_t mirror_table_index =
                        static_cast<std::size_t>(kernel_offset + mirror_index);
                    if (kernel_table.kernel_real[table_index] !=
                            kernel_table.kernel_real[mirror_table_index] ||
                        kernel_table.kernel_imag[table_index] !=
                            -kernel_table.kernel_imag[mirror_table_index])
                    {
                        g_workspace.cached_cwt_kernel_symmetric = false;
                        break;
                    }
                }
            }
            g_workspace.cwt_kernel_sizes = ZxGpuIndexSignal::from_host(kernel_table.kernel_sizes);
            g_workspace.cwt_kernel_starts = ZxGpuIndexSignal::from_host(kernel_table.kernel_starts);
            g_workspace.cwt_kernel_offsets = ZxGpuIndexSignal::from_host(kernel_table.kernel_offsets);
            g_workspace.cwt_kernel_real = ZxGpuRealSignal::from_host(kernel_table.kernel_real);
            g_workspace.cwt_kernel_imag = ZxGpuRealSignal::from_host(kernel_table.kernel_imag);
            g_workspace.cached_cwt_widths = widths;
            g_workspace.cached_cwt_sample_count = sample_count;
            g_workspace.cwt_kernel_table_valid = true;
        }
    } // namespace

    ZxGpuRealArray extract_real_part_zx_gpu(const ZxGpuComplexArray &input)
    {
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (!input.empty())
        {
            extract_real_part_kernel<<<block_count(input.size()), tile::task_threads()>>>(
                reinterpret_cast<const float2 *>(input.data()),
                output.data(),
                input.size());
            check_kernel_launch("extract_real_part_kernel");
        }
        return output;
    }

    ZxGpuRealArray extract_imag_part_zx_gpu(const ZxGpuComplexArray &input)
    {
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (!input.empty())
        {
            extract_imag_part_kernel<<<block_count(input.size()), tile::task_threads()>>>(
                reinterpret_cast<const float2 *>(input.data()),
                output.data(),
                input.size());
            check_kernel_launch("extract_imag_part_kernel");
        }
        return output;
    }

    ZxGpuComplexArray combine_complex_zx_gpu(
        const ZxGpuRealArray &real_part,
        const ZxGpuRealArray &imag_part)
    {
        if (real_part.shape() != imag_part.shape())
        {
            throw std::invalid_argument("real/imag shape mismatch");
        }
        ZxGpuComplexArray output = cusignal::core::make_zx_gpu_complex_array(real_part.shape());
        if (!real_part.empty())
        {
            combine_complex_kernel<<<block_count(real_part.size()), tile::task_threads()>>>(
                real_part.data(),
                imag_part.data(),
                reinterpret_cast<float2 *>(output.data()),
                real_part.size());
            check_kernel_launch("combine_complex_kernel");
        }
        return output;
    }

    ZxGpuComplexArray complex_firfilter_zx_gpu(
        const ZxGpuComplexArray &input,
        const ZxGpuRealSignal &taps,
        ZxGpuRealArray &real_output)
    {
        g_workspace.fixed_fft_filtered_spectrum_valid = false;
        if (input.rank() != 2)
        {
            throw std::invalid_argument("complex_firfilter_zx_gpu expects rank-2 input");
        }
        if (taps.empty())
        {
            throw std::invalid_argument("complex_firfilter_zx_gpu requires non-empty taps");
        }
        ZxGpuComplexArray output = cusignal::core::make_zx_gpu_complex_array(input.shape());
        real_output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (!input.empty())
        {
            const std::size_t rows = input.shape()[0];
            const std::size_t cols = input.shape()[1];
            const int fft_size = task2_fixed_fft_size(cols + taps.size() - 1);
            const std::size_t fft_size_u = static_cast<std::size_t>(fft_size);
            ensure_task2_fixed_fft_workspace(fft_size, rows + 1);
            float2 *fft_input =
                reinterpret_cast<float2 *>(g_workspace.fixed_fft_input.data());
            float2 *fft_output =
                reinterpret_cast<float2 *>(g_workspace.fixed_fft_output.data());
            pack_task2_filter_fft_kernel<<<
                block_count((rows + 1) * fft_size_u),
                tile::task_threads()>>>(
                reinterpret_cast<const float2 *>(input.data()),
                taps.data(),
                rows,
                cols,
                taps.size(),
                fft_size_u,
                fft_input);
            check_kernel_launch("pack_task2_filter_fft_kernel");
            launch_task2_fixed_fft(fft_input, fft_output, fft_size, rows + 1, false);
            multiply_task2_fft_kernel<<<
                block_count(rows * fft_size_u),
                tile::task_threads()>>>(
                fft_output,
                rows,
                fft_size_u,
                fft_input);
            check_kernel_launch("multiply_task2_fft_kernel filter");
            launch_task2_fixed_fft(fft_input, fft_output, fft_size, rows, true);
            extract_task2_filter_fft_kernel<<<
                block_count(output.size()),
                tile::task_threads()>>>(
                fft_output,
                rows,
                cols,
                fft_size_u,
                reinterpret_cast<float2 *>(output.data()),
                real_output.data());
            check_kernel_launch("extract_task2_filter_fft_kernel");
            g_workspace.cached_fixed_fft_filtered_data = output.data();
            g_workspace.cached_fixed_fft_filtered_rows = rows;
            g_workspace.cached_fixed_fft_filtered_cols = cols;
            g_workspace.cached_fixed_fft_filtered_size = fft_size;
            g_workspace.fixed_fft_filtered_spectrum_valid = true;
        }
        return output;
    }

    bool task2_fixed_fft_filter_enabled_zx_gpu()
    {
        return environment_flag_enabled("CUSIGNAL_TASK2_ENABLE_FIXED_FFT_FILTER") &&
            !task2_fixed_fft_filter_disabled() && tile::task_route() != 1;
    }

    ZxGpuComplexArray extract_row_complex_zx_gpu(const ZxGpuComplexArray &input, int row_index)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("extract_row_complex_zx_gpu expects rank-2 input");
        }
        ZxGpuComplexArray output = cusignal::core::make_zx_gpu_complex_array(Shape{input.shape()[1]});
        extract_row_complex_kernel<<<block_count(input.shape()[1]), tile::task_threads()>>>(
            reinterpret_cast<const float2 *>(input.data()),
            input.shape()[0],
            input.shape()[1],
            row_index,
            reinterpret_cast<float2 *>(output.data()));
        check_kernel_launch("extract_row_complex_kernel");
        return output;
    }

    ZxGpuRealArray extract_row_real_zx_gpu(const ZxGpuRealArray &input, int row_index)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("extract_row_real_zx_gpu expects rank-2 input");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(Shape{input.shape()[1]});
        extract_row_real_kernel<<<block_count(input.shape()[1]), tile::task_threads()>>>(
            input.data(),
            input.shape()[0],
            input.shape()[1],
            row_index,
            output.data());
        check_kernel_launch("extract_row_real_kernel");
        return output;
    }

    ZxGpuRealSignal extract_row_real_signal_zx_gpu(const ZxGpuRealArray &input, int row_index)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("extract_row_real_signal_zx_gpu expects rank-2 input");
        }
        ZxGpuRealSignal output(input.shape()[1], false);
        extract_row_real_kernel<<<block_count(input.shape()[1]), tile::task_threads()>>>(
            input.data(),
            input.shape()[0],
            input.shape()[1],
            row_index,
            output.data());
        check_kernel_launch("extract_row_real_signal_kernel");
        return output;
    }

    ZxGpuRealArray extract_frame_real_3d_zx_gpu(const ZxGpuRealArray &input, int frame_index)
    {
        if (input.rank() != 3)
        {
            throw std::invalid_argument("extract_frame_real_3d_zx_gpu expects rank-3 input");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(Shape{input.shape()[1], input.shape()[2]});
        extract_frame_real_3d_kernel<<<block_count(output.size()), tile::task_threads()>>>(
            input.data(),
            input.shape()[0],
            input.shape()[1],
            input.shape()[2],
            frame_index,
            output.data());
        check_kernel_launch("extract_frame_real_3d_kernel");
        return output;
    }

    void store_row_real_zx_gpu(
        const ZxGpuRealArray &row,
        ZxGpuRealArray &output,
        int row_index)
    {
        if (row.rank() != 1 || output.rank() != 2)
        {
            throw std::invalid_argument("store_row_real_zx_gpu expects rank-1 row and rank-2 output");
        }
        if (row.shape()[0] != output.shape()[1])
        {
            throw std::invalid_argument("store_row_real_zx_gpu column mismatch");
        }
        if (row_index < 0 || static_cast<std::size_t>(row_index) >= output.shape()[0])
        {
            throw std::invalid_argument("store_row_real_zx_gpu row index out of range");
        }
        store_row_real_kernel<<<block_count(row.shape()[0]), tile::task_threads()>>>(
            row.data(),
            row.shape()[0],
            row_index,
            output.data());
        check_kernel_launch("store_row_real_kernel");
    }

    ZxGpuRealArray complex_abs_zx_gpu(const ZxGpuComplexArray &input)
    {
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (!input.empty())
        {
            complex_abs_kernel<<<block_count(input.size()), tile::task_threads()>>>(
                reinterpret_cast<const float2 *>(input.data()),
                output.data(),
                input.size());
            check_kernel_launch("complex_abs_kernel");
        }
        return output;
    }

    ZxGpuRealArray pad_last_value_zx_gpu(const ZxGpuRealArray &input, std::size_t target_len)
    {
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(Shape{target_len});
        pad_last_value_kernel<<<block_count(target_len), tile::task_threads()>>>(
            input.data(),
            input.size(),
            output.data(),
            target_len);
        check_kernel_launch("pad_last_value_kernel");
        return output;
    }

    ZxGpuRealArray normalize_nonnegative_zx_gpu(const ZxGpuRealArray &input)
    {
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (input.empty())
        {
            return output;
        }

        g_workspace.temp_signal.resize(1, false);
        max_reduce_kernel<<<1, tile::task_threads()>>>(input.data(), input.size(), g_workspace.temp_signal.data());
        check_kernel_launch("max_reduce_kernel");
        normalize_kernel<<<block_count(input.size()), tile::task_threads()>>>(
            input.data(),
            input.size(),
            g_workspace.temp_signal.data(),
            output.data());
        check_kernel_launch("normalize_kernel");
        return output;
    }

    ZxGpuRealArray normalize_rows_nonnegative_zx_gpu(const ZxGpuRealArray &input)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("normalize_rows_nonnegative_zx_gpu expects rank-2 input");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (!input.empty())
        {
            normalize_rows_kernel<<<input.shape()[0], tile::task_threads()>>>(
                input.data(),
                input.shape()[0],
                input.shape()[1],
                output.data());
            check_kernel_launch("normalize_rows_kernel");
        }
        return output;
    }

    ZxGpuRealArray batched_demod_score_zx_gpu(const ZxGpuComplexArray &input)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("batched_demod_score_zx_gpu expects rank-2 input");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        if (!input.empty())
        {
            batched_demod_score_kernel<<<input.shape()[0], tile::task_threads()>>>(
                reinterpret_cast<const float2 *>(input.data()),
                input.shape()[0],
                input.shape()[1],
                output.data());
            check_kernel_launch("batched_demod_score_kernel");
        }
        return output;
    }

    ZxGpuRealArray batched_correlate_score_zx_gpu(
        const ZxGpuComplexArray &frames,
        const ZxGpuComplexArray &templ)
    {
        if (frames.rank() != 2 || templ.rank() != 1)
        {
            throw std::invalid_argument("batched_correlate_score_zx_gpu expects rank-2 frames and rank-1 template");
        }
        if (templ.empty())
        {
            throw std::invalid_argument("batched_correlate_score_zx_gpu requires non-empty template");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(frames.shape());
        if (output.empty())
        {
            return output;
        }
        const std::size_t cols = frames.shape()[1];
        const std::size_t templ_len = templ.shape()[0];
        const std::size_t full_size = cols + templ_len - 1;
        const int crop_start = static_cast<int>(full_size / 2 - cols / 2);
        const std::size_t rows = frames.shape()[0];
        if (tile::task_route() != 1 && !task2_fixed_fft_correlate_disabled() &&
            rows >= kTask2FixedFftMinRows &&
            cols >= kTask2FixedFftMinCols &&
            templ_len >= 256)
        {
            const int fft_size = task2_fixed_fft_size(full_size);
            const std::size_t fft_size_u = static_cast<std::size_t>(fft_size);
            ensure_task2_fixed_fft_workspace(fft_size, rows + 1);
            float2 *fft_input =
                reinterpret_cast<float2 *>(g_workspace.fixed_fft_input.data());
            float2 *fft_output =
                reinterpret_cast<float2 *>(g_workspace.fixed_fft_output.data());
            const bool reuse_filtered_spectrum =
                g_workspace.fixed_fft_filtered_spectrum_valid &&
                g_workspace.cached_fixed_fft_filtered_data == frames.data() &&
                g_workspace.cached_fixed_fft_filtered_rows == rows &&
                g_workspace.cached_fixed_fft_filtered_cols == cols &&
                g_workspace.cached_fixed_fft_filtered_size == fft_size;
            const float2 *inverse_output = nullptr;
            if (reuse_filtered_spectrum)
            {
                float2 *template_time = fft_output + rows * fft_size_u;
                float2 *template_spectrum = fft_input + rows * fft_size_u;
                pack_task2_correlate_template_fft_kernel<<<
                    block_count(fft_size_u),
                    tile::task_threads()>>>(
                    reinterpret_cast<const float2 *>(templ.data()),
                    templ_len,
                    fft_size_u,
                    template_time);
                check_kernel_launch("pack_task2_correlate_template_fft_kernel");
                launch_task2_fixed_fft(
                    template_time,
                    template_spectrum,
                    fft_size,
                    1,
                    false);
                multiply_task2_fft_kernel<<<
                    block_count(rows * fft_size_u),
                    tile::task_threads()>>>(
                    fft_input,
                    rows,
                    fft_size_u,
                    fft_output);
                check_kernel_launch("multiply_task2_fft_kernel correlate cached");
                launch_task2_fixed_fft(fft_output, fft_input, fft_size, rows, true);
                inverse_output = fft_input;
            }
            else
            {
                pack_task2_correlate_fft_kernel<<<
                    block_count((rows + 1) * fft_size_u),
                    tile::task_threads()>>>(
                    reinterpret_cast<const float2 *>(frames.data()),
                    reinterpret_cast<const float2 *>(templ.data()),
                    rows,
                    cols,
                    templ_len,
                    fft_size_u,
                    fft_input);
                check_kernel_launch("pack_task2_correlate_fft_kernel");
                launch_task2_fixed_fft(fft_input, fft_output, fft_size, rows + 1, false);
                multiply_task2_fft_kernel<<<
                    block_count(rows * fft_size_u),
                    tile::task_threads()>>>(
                    fft_output,
                    rows,
                    fft_size_u,
                    fft_input);
                check_kernel_launch("multiply_task2_fft_kernel correlate");
                launch_task2_fixed_fft(fft_input, fft_output, fft_size, rows, true);
                inverse_output = fft_output;
            }
            extract_task2_correlate_fft_kernel<<<
                block_count(output.size()),
                tile::task_threads()>>>(
                inverse_output,
                rows,
                cols,
                fft_size_u,
                static_cast<std::size_t>(crop_start),
                output.data());
            check_kernel_launch("extract_task2_correlate_fft_kernel");
            return output;
        }
        if (cols >= 2048)
        {
            constexpr std::size_t kCorrelateOutputsPerBlock =
                2 * static_cast<std::size_t>(kThreadsPerBlock);
            const dim3 grid(
                static_cast<unsigned int>(
                    (cols + kCorrelateOutputsPerBlock - 1) / kCorrelateOutputsPerBlock),
                static_cast<unsigned int>(rows));
            const std::size_t shared_bytes =
                (kCorrelateOutputsPerBlock + 2 * templ_len - 1) * sizeof(float2);
            batched_correlate_score_tiled_kernel<<<grid, kThreadsPerBlock, shared_bytes>>>(
                reinterpret_cast<const float2 *>(frames.data()),
                reinterpret_cast<const float2 *>(templ.data()),
                rows,
                cols,
                templ_len,
                crop_start,
                output.data());
            check_kernel_launch("batched_correlate_score_tiled_kernel");
        }
        else
        {
            batched_correlate_score_kernel<<<output.size(), tile::task_threads()>>>(
                reinterpret_cast<const float2 *>(frames.data()),
                reinterpret_cast<const float2 *>(templ.data()),
                rows,
                cols,
                templ_len,
                crop_start,
                output.data());
            check_kernel_launch("batched_correlate_score_kernel");
        }
        return output;
    }

    ZxGpuRealArray spectrogram_band_score_zx_gpu(
        const ZxGpuRealArray &values,
        const ZxGpuRealSignal &freqs,
        const ZxGpuRealSignal &times,
        int sample_count,
        float band_low,
        float band_high,
        float fs)
    {
        if (values.rank() != 2)
        {
            throw std::invalid_argument("spectrogram values must be rank-2");
        }
        const std::size_t freq_count = values.shape()[0];
        const std::size_t time_count = values.shape()[1];
        g_workspace.temp_storage_a.resize(Shape{time_count}, false);
        spectrogram_band_energy_kernel<<<block_count(time_count), tile::task_threads()>>>(
            values.data(),
            freqs.data(),
            freq_count,
            time_count,
            band_low,
            band_high,
            g_workspace.temp_storage_a.data());
        check_kernel_launch("spectrogram_band_energy_kernel");

        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(Shape{static_cast<std::size_t>(sample_count)});
        map_time_energy_kernel<<<block_count(static_cast<std::size_t>(sample_count)), tile::task_threads()>>>(
            g_workspace.temp_storage_a.data(),
            times.data(),
            time_count,
            sample_count,
            fs,
            output.data());
        check_kernel_launch("map_time_energy_kernel");
        return output;
    }

    ZxGpuRealArray batched_spectrogram_band_score_zx_gpu(
        const ZxGpuRealArray &values,
        const ZxGpuRealSignal &freqs,
        const ZxGpuRealSignal &times,
        int sample_count,
        float band_low,
        float band_high,
        float fs)
    {
        if (values.rank() != 3)
        {
            throw std::invalid_argument("batched_spectrogram_band_score_zx_gpu expects rank-3 values");
        }
        const std::size_t frames = values.shape()[0];
        const std::size_t freq_count = values.shape()[1];
        const std::size_t time_count = values.shape()[2];
        if (freqs.size() != freq_count || times.size() != time_count)
        {
            throw std::invalid_argument("batched_spectrogram_band_score_zx_gpu shape mismatch");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(
            Shape{frames, static_cast<std::size_t>(sample_count)});
        if (!output.empty())
        {
            batched_spectrogram_band_score_kernel<<<block_count(output.size()), tile::task_threads()>>>(
                values.data(),
                freqs.data(),
                times.data(),
                frames,
                freq_count,
                time_count,
                sample_count,
                band_low,
                band_high,
                fs,
                output.data());
            check_kernel_launch("batched_spectrogram_band_score_kernel");
        }
        return output;
    }

    ZxGpuRealArray direct_spectrogram_band_score_zx_gpu(
        const ZxGpuRealArray &frames,
        const ZxGpuRealSignal &window,
        int nperseg,
        int noverlap,
        int nfft,
        float band_low,
        float band_high,
        float fs)
    {
        if (frames.rank() != 2)
        {
            throw std::invalid_argument("direct_spectrogram_band_score_zx_gpu expects rank-2 frames");
        }
        if (nperseg <= 0 || noverlap < 0 || nfft < nperseg || noverlap >= nperseg)
        {
            throw std::invalid_argument("direct_spectrogram_band_score_zx_gpu invalid segment config");
        }
        if (window.size() != static_cast<std::size_t>(nperseg))
        {
            throw std::invalid_argument("direct_spectrogram_band_score_zx_gpu window size mismatch");
        }
        const std::size_t frame_count = frames.shape()[0];
        const std::size_t sample_count = frames.shape()[1];
        if (sample_count < static_cast<std::size_t>(nperseg))
        {
            throw std::invalid_argument("direct_spectrogram_band_score_zx_gpu nperseg exceeds frame length");
        }
        const int step = nperseg - noverlap;
        const int nseg = 1 + static_cast<int>((sample_count - static_cast<std::size_t>(nperseg)) /
                                              static_cast<std::size_t>(step));
        const int max_bin = nfft / 2;
        const int low_bin = std::max(0, static_cast<int>(std::ceil(band_low * static_cast<float>(nfft) / fs)));
        const int high_bin = std::min(max_bin, static_cast<int>(std::floor(band_high * static_cast<float>(nfft) / fs)));
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(Shape{frame_count, sample_count});
        if (output.empty() || low_bin > high_bin)
        {
            return output;
        }

        const std::size_t segment_count =
            frame_count * static_cast<std::size_t>(nseg);
        if (tile::task_route() != 1 && !task2_fixed_fft_spectrogram_disabled() &&
            frame_count >= kTask2FixedFftMinRows &&
            nfft >= 256 &&
            is_power_of_two(nfft) &&
            nfft <= static_cast<int>(kTask2FixedFftMaxSize))
        {
            const std::vector<float> host_window = window.get();
            const float window_sum = std::accumulate(
                host_window.begin(),
                host_window.end(),
                0.0f);
            const float scale = std::fabs(window_sum) > 1.0e-12f
                ? 1.0f / std::fabs(window_sum)
                : 0.0f;
            ensure_task2_fixed_fft_workspace(nfft, segment_count);
            float2 *fft_input =
                reinterpret_cast<float2 *>(g_workspace.fixed_fft_input.data());
            float2 *fft_output =
                reinterpret_cast<float2 *>(g_workspace.fixed_fft_output.data());
            pack_task2_spectrogram_fft_kernel<<<
                static_cast<unsigned int>(segment_count),
                tile::task_threads()>>>(
                frames.data(),
                window.data(),
                sample_count,
                nperseg,
                step,
                nseg,
                nfft,
                fft_input);
            check_kernel_launch("pack_task2_spectrogram_fft_kernel");
            launch_task2_fixed_fft(
                fft_input,
                fft_output,
                nfft,
                segment_count,
                false);
            g_workspace.temp_storage_a.resize(
                Shape{frame_count, static_cast<std::size_t>(nseg)},
                false);
            reduce_task2_spectrogram_fft_kernel<<<
                static_cast<unsigned int>(segment_count),
                tile::task_threads()>>>(
                fft_output,
                segment_count,
                nfft,
                low_bin,
                high_bin,
                scale,
                g_workspace.temp_storage_a.data());
            check_kernel_launch("reduce_task2_spectrogram_fft_kernel");
            map_batched_time_energy_kernel<<<
                block_count(output.size()),
                tile::task_threads()>>>(
                g_workspace.temp_storage_a.data(),
                frame_count,
                nseg,
                nperseg,
                step,
                static_cast<int>(sample_count),
                fs,
                output.data());
            check_kernel_launch("map_batched_time_energy_kernel fixed FFT");
            return output;
        }

        const int band_bin_count = high_bin - low_bin + 1;
        const float scale = prepare_direct_spectrogram_tables(window, nperseg, nfft, low_bin, high_bin, fs);
        g_workspace.temp_storage_a.resize(Shape{frame_count, static_cast<std::size_t>(nseg)}, false);
        if (nperseg >= 256)
        {
            direct_spectrogram_segment_energy_grouped_kernel<<<g_workspace.temp_storage_a.size(), tile::task_threads()>>>(
                frames.data(),
                g_workspace.direct_cos_table.data(),
                g_workspace.direct_sin_table.data(),
                sample_count,
                nperseg,
                step,
                nseg,
                band_bin_count,
                scale,
                g_workspace.temp_storage_a.data());
            check_kernel_launch("direct_spectrogram_segment_energy_grouped_kernel");
        }
        else
        {
            direct_spectrogram_segment_energy_kernel<<<g_workspace.temp_storage_a.size(), tile::task_threads()>>>(
                frames.data(),
                g_workspace.direct_cos_table.data(),
                g_workspace.direct_sin_table.data(),
                sample_count,
                nperseg,
                step,
                nseg,
                band_bin_count,
                scale,
                g_workspace.temp_storage_a.data());
            check_kernel_launch("direct_spectrogram_segment_energy_kernel");
        }

        map_batched_time_energy_kernel<<<block_count(output.size()), tile::task_threads()>>>(
            g_workspace.temp_storage_a.data(),
            frame_count,
            nseg,
            nperseg,
            step,
            static_cast<int>(sample_count),
            fs,
            output.data());
        check_kernel_launch("map_batched_time_energy_kernel");
        return output;
    }

    ZxGpuRealArray batched_cwt_max_score_zx_gpu(
        const ZxGpuRealArray &frames,
        const RealSignal &widths)
    {
        if (frames.rank() != 2)
        {
            throw std::invalid_argument("batched_cwt_max_score_zx_gpu expects rank-2 frames");
        }
        wavelets_detail::ensure_non_empty_widths(widths.size());
        wavelets_detail::ensure_positive_widths(widths);
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(frames.shape());
        if (output.empty())
        {
            return output;
        }

        const std::size_t frame_count = frames.shape()[0];
        const std::size_t sample_count = frames.shape()[1];
        const std::size_t width_count = widths.size();
        prepare_cwt_kernel_table(widths, sample_count);
        const bool use_symmetric_pairs =
            g_workspace.cached_cwt_kernel_symmetric &&
            task2_cwt_symmetry_enabled();

        constexpr std::size_t kMaxSharedCwtKernelSize = 2048;
        if (g_workspace.cached_cwt_max_kernel_size > 0 &&
            g_workspace.cached_cwt_max_kernel_size <= kMaxSharedCwtKernelSize)
        {
            if (sample_count >= 2048)
            {
                constexpr std::size_t kCwtOutputsPerBlock =
                    4 * static_cast<std::size_t>(kThreadsPerBlock);
                const std::size_t shared_bytes =
                    (kCwtOutputsPerBlock +
                     g_workspace.cached_cwt_max_kernel_size - 1) * sizeof(float);
                const dim3 grid(
                    static_cast<unsigned int>(
                        (sample_count + kCwtOutputsPerBlock - 1) / kCwtOutputsPerBlock),
                    static_cast<unsigned int>(frame_count));
                if (use_symmetric_pairs)
                {
                    batched_cwt_max_score_shared_quad_kernel<true><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        frames.data(),
                        frame_count,
                        sample_count,
                        width_count,
                        g_workspace.cwt_kernel_sizes.data(),
                        g_workspace.cwt_kernel_starts.data(),
                        g_workspace.cwt_kernel_offsets.data(),
                        g_workspace.cwt_kernel_real.data(),
                        g_workspace.cwt_kernel_imag.data(),
                        output.data());
                    check_kernel_launch("batched_cwt_max_score_shared_quad_kernel<true>");
                }
                else
                {
                    batched_cwt_max_score_shared_quad_kernel<false><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        frames.data(),
                        frame_count,
                        sample_count,
                        width_count,
                        g_workspace.cwt_kernel_sizes.data(),
                        g_workspace.cwt_kernel_starts.data(),
                        g_workspace.cwt_kernel_offsets.data(),
                        g_workspace.cwt_kernel_real.data(),
                        g_workspace.cwt_kernel_imag.data(),
                        output.data());
                    check_kernel_launch("batched_cwt_max_score_shared_quad_kernel<false>");
                }
            }
            else
            {
                constexpr std::size_t kCwtOutputsPerBlock =
                    2 * static_cast<std::size_t>(kThreadsPerBlock);
                const std::size_t shared_bytes =
                    (kCwtOutputsPerBlock +
                     g_workspace.cached_cwt_max_kernel_size - 1) * sizeof(float);
                const dim3 grid(
                    static_cast<unsigned int>(
                        (sample_count + kCwtOutputsPerBlock - 1) / kCwtOutputsPerBlock),
                    static_cast<unsigned int>(frame_count));
                if (use_symmetric_pairs)
                {
                    batched_cwt_max_score_shared_kernel<true><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        frames.data(),
                        frame_count,
                        sample_count,
                        width_count,
                        g_workspace.cwt_kernel_sizes.data(),
                        g_workspace.cwt_kernel_starts.data(),
                        g_workspace.cwt_kernel_offsets.data(),
                        g_workspace.cwt_kernel_real.data(),
                        g_workspace.cwt_kernel_imag.data(),
                        output.data());
                    check_kernel_launch("batched_cwt_max_score_shared_kernel<true>");
                }
                else
                {
                    batched_cwt_max_score_shared_kernel<false><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        frames.data(),
                        frame_count,
                        sample_count,
                        width_count,
                        g_workspace.cwt_kernel_sizes.data(),
                        g_workspace.cwt_kernel_starts.data(),
                        g_workspace.cwt_kernel_offsets.data(),
                        g_workspace.cwt_kernel_real.data(),
                        g_workspace.cwt_kernel_imag.data(),
                        output.data());
                    check_kernel_launch("batched_cwt_max_score_shared_kernel<false>");
                }
            }
        }
        else
        {
            batched_cwt_max_score_fused_kernel<<<block_count(output.size()), tile::task_threads()>>>(
                frames.data(),
                frame_count,
                sample_count,
                width_count,
                g_workspace.cwt_kernel_sizes.data(),
                g_workspace.cwt_kernel_starts.data(),
                g_workspace.cwt_kernel_offsets.data(),
                g_workspace.cwt_kernel_real.data(),
                g_workspace.cwt_kernel_imag.data(),
                output.data());
            check_kernel_launch("batched_cwt_max_score_fused_kernel");
        }
        return output;
    }

    ZxGpuRealArray cwt_max_score_zx_gpu(const ZxGpuComplexArray &values)
    {
        if (values.rank() != 2)
        {
            throw std::invalid_argument("cwt values must be rank-2");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(Shape{values.shape()[1]});
        cwt_max_kernel<<<block_count(values.shape()[1]), tile::task_threads()>>>(
            reinterpret_cast<const float2 *>(values.data()),
            values.shape()[0],
            values.shape()[1],
            output.data());
        check_kernel_launch("cwt_max_kernel");
        return output;
    }

    ZxGpuRealArray weighted_sum_zx_gpu(
        const ZxGpuRealArray &corr_score,
        const ZxGpuRealArray &demod_score,
        const ZxGpuRealArray &wavelet_score,
        const ZxGpuRealArray &spectrogram_score,
        float corr_weight,
        float demod_weight,
        float wavelet_weight,
        float spectrogram_weight)
    {
        if (corr_score.shape() != demod_score.shape() ||
            corr_score.shape() != wavelet_score.shape() ||
            corr_score.shape() != spectrogram_score.shape())
        {
            throw std::invalid_argument("weighted_sum_zx_gpu input shape mismatch");
        }
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(corr_score.shape());
        weighted_sum_kernel<<<block_count(corr_score.size()), tile::task_threads()>>>(
            corr_score.data(),
            demod_score.data(),
            wavelet_score.data(),
            spectrogram_score.data(),
            corr_weight,
            demod_weight,
            wavelet_weight,
            spectrogram_weight,
            corr_score.size(),
            output.data());
        check_kernel_launch("weighted_sum_kernel");
        return output;
    }

    ZxGpuRealArray smooth_with_weights_zx_gpu(const ZxGpuRealArray &input, const ZxGpuRealSignal &weights)
    {
        ZxGpuRealArray output = cusignal::core::make_zx_gpu_real_array(input.shape());
        smooth_kernel<<<block_count(input.size()), tile::task_threads()>>>(
            input.data(),
            input.size(),
            weights.data(),
            weights.size(),
            output.data());
        check_kernel_launch("smooth_kernel");
        return output;
    }

    void fuse_feature_scores_zx_gpu(
        const ZxGpuRealArray &corr_score,
        const ZxGpuRealArray &demod_score,
        const ZxGpuRealArray &wavelet_score,
        const ZxGpuRealArray &spectrogram_score,
        const ZxGpuRealSignal &weights,
        int peak_order,
        ZxGpuRealArray &feature_scores,
        ZxGpuRealSignal &peak_track,
        FusionKernelTiming *kernel_timing)
    {
        if (corr_score.rank() != 2)
        {
            throw std::invalid_argument("fuse_feature_scores_zx_gpu expects rank-2 scores");
        }
        if (corr_score.shape() != demod_score.shape() ||
            corr_score.shape() != wavelet_score.shape() ||
            corr_score.shape() != spectrogram_score.shape())
        {
            throw std::invalid_argument("fuse_feature_scores_zx_gpu input shape mismatch");
        }
        if (weights.empty())
        {
            throw std::invalid_argument("fuse_feature_scores_zx_gpu requires non-empty weights");
        }
        if (peak_order < 1)
        {
            throw std::invalid_argument("fuse_feature_scores_zx_gpu peak_order must be >= 1");
        }

        const std::size_t rows = corr_score.shape()[0];
        const std::size_t cols = corr_score.shape()[1];
        feature_scores.resize(corr_score.shape(), false);
        peak_track.resize(rows, false);
        if (corr_score.empty())
        {
            return;
        }

        const auto timed_launch = [](auto &&launch, const char *what) {
            cudaEvent_t start = nullptr;
            cudaEvent_t stop = nullptr;
            throw_on_zx_gpu_error(cudaEventCreate(&start), "cudaEventCreate(fusion start)");
            try
            {
                throw_on_zx_gpu_error(cudaEventCreate(&stop), "cudaEventCreate(fusion stop)");
                throw_on_zx_gpu_error(cudaEventRecord(start), "cudaEventRecord(fusion start)");
                launch();
                check_kernel_launch(what);
                throw_on_zx_gpu_error(cudaEventRecord(stop), "cudaEventRecord(fusion stop)");
                throw_on_zx_gpu_error(cudaEventSynchronize(stop), "cudaEventSynchronize(fusion stop)");
                float elapsed = 0.0f;
                throw_on_zx_gpu_error(cudaEventElapsedTime(&elapsed, start, stop), "cudaEventElapsedTime(fusion)");
                (void)cudaEventDestroy(stop);
                (void)cudaEventDestroy(start);
                return elapsed;
            }
            catch (...)
            {
                if (stop != nullptr) (void)cudaEventDestroy(stop);
                if (start != nullptr) (void)cudaEventDestroy(start);
                throw;
            }
        };
        const float smooth_ms = timed_launch([&]() {
            fused_feature_smooth_kernel<<<block_count(corr_score.size()), tile::task_threads()>>>(
                corr_score.data(), demod_score.data(), wavelet_score.data(), spectrogram_score.data(),
                weights.data(), weights.size(), rows, cols, feature_scores.data());
        }, "fused_feature_smooth_kernel");
        const float peak_ms = timed_launch([&]() {
            row_peak_track_kernel<<<rows, tile::task_threads()>>>(
                feature_scores.data(), rows, cols, peak_order, peak_track.data());
        }, "row_peak_track_kernel");
        if (kernel_timing != nullptr)
        {
            kernel_timing->smooth_ms = smooth_ms;
            kernel_timing->peak_ms = peak_ms;
        }
    }

    ZxGpuRealSignal kalman_track_from_peaks_zx_gpu(const ZxGpuRealSignal &peak_track)
    {
        ZxGpuRealSignal output(peak_track.size(), false);
        if (!peak_track.empty())
        {
            kalman_track_from_peaks_kernel<<<1, 1>>>(
                peak_track.data(),
                peak_track.size(),
                output.data());
            check_kernel_launch("kalman_track_from_peaks_kernel");
        }
        return output;
    }

    ZxGpuRealSignal copy_measurement_track_zx_gpu(const ZxGpuRealSignal &peak_track)
    {
        ZxGpuRealSignal output = cusignal::core::make_zx_gpu_real_signal(peak_track.size(), 0.0f);
        if (!peak_track.empty())
        {
            copy_measurement_track_kernel<<<block_count(peak_track.size()), tile::task_threads()>>>(
                peak_track.data(),
                peak_track.size(),
                output.data());
            check_kernel_launch("copy_measurement_track_kernel");
        }
        return output;
    }

    ZxGpuIndexSignal argmax_all_zx_gpu(const ZxGpuRealArray &score)
    {
        ZxGpuIndexSignal output(1, false);
        argmax_all_kernel<<<1, tile::task_threads()>>>(score.data(), score.size(), output.data());
        check_kernel_launch("argmax_all_kernel");
        return output;
    }

    ZxGpuIndexSignal argmax_from_candidates_zx_gpu(
        const ZxGpuRealArray &score,
        const ZxGpuIndexSignal &candidates)
    {
        if (candidates.empty())
        {
            return argmax_all_zx_gpu(score);
        }
        ZxGpuIndexSignal output(1, false);
        argmax_candidates_kernel<<<1, tile::task_threads()>>>(
            score.data(),
            candidates.data(),
            candidates.size(),
            output.data());
        check_kernel_launch("argmax_candidates_kernel");
        return output;
    }

    ZxGpuRealArray index_to_measurement_zx_gpu(const ZxGpuIndexSignal &index)
    {
        ZxGpuRealArray measurement = cusignal::core::make_zx_gpu_real_array(Shape{1, 1, 1});
        index_to_measurement_kernel<<<1, 1>>>(index.data(), measurement.data());
        check_kernel_launch("index_to_measurement_kernel");
        return measurement;
    }

    void initialize_state_from_index_zx_gpu(
        const ZxGpuIndexSignal &index,
        ZxGpuRealArray &state)
    {
        if (state.empty())
        {
            throw std::invalid_argument("initialize_state_from_index_zx_gpu requires non-empty state");
        }
        initialize_state_from_index_kernel<<<block_count(state.size()), tile::task_threads()>>>(
            index.data(),
            state.data(),
            state.size());
        check_kernel_launch("initialize_state_from_index_kernel");
    }

    void write_index_to_track_zx_gpu(
        const ZxGpuIndexSignal &index,
        ZxGpuRealSignal &track,
        int frame_index)
    {
        write_index_to_track_kernel<<<1, 1>>>(index.data(), track.data(), frame_index);
        check_kernel_launch("write_index_to_track_kernel");
    }

    void write_state_position_to_track_zx_gpu(
        const ZxGpuRealArray &state,
        ZxGpuRealSignal &track,
        int frame_index)
    {
        write_state_position_to_track_kernel<<<1, 1>>>(state.data(), track.data(), frame_index);
        check_kernel_launch("write_state_position_to_track_kernel");
    }
}
