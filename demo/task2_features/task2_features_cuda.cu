#include "task2_features_cuda.hpp"

#include <cuda_runtime_api.h>

#include <algorithm>
#include <stdexcept>
#include <string>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/types.hpp"

namespace cusignal_demo::task2_features
{
    namespace
    {
        using cusignal::core::CudaComplexArray;
        using cusignal::core::CudaIndexSignal;
        using cusignal::core::CudaRealArray;
        using cusignal::core::CudaRealSignal;
        using cusignal::core::Shape;

        constexpr int kThreadsPerBlock = 256;

        struct Task2Workspace
        {
            CudaRealArray real_storage;
            CudaRealArray imag_storage;
            CudaComplexArray complex_storage;
            CudaRealArray temp_storage_a;
            CudaRealArray temp_storage_b;
            CudaRealSignal temp_signal;
            CudaIndexSignal temp_index;
        };

        thread_local Task2Workspace g_workspace;

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

        std::size_t block_count(std::size_t total)
        {
            return total == 0 ? 0 : (total + static_cast<std::size_t>(kThreadsPerBlock) - 1) /
                static_cast<std::size_t>(kThreadsPerBlock);
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
                    const float real = next.x * current.x + next.y * current.y;
                    const float imag = next.y * current.x - next.x * current.y;
                    value = atan2f(imag, real);
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
    } // namespace

    CudaRealArray extract_real_part_cuda(const CudaComplexArray &input)
    {
        CudaRealArray output = cusignal::core::make_cuda_real_array(input.shape());
        if (!input.empty())
        {
            extract_real_part_kernel<<<block_count(input.size()), kThreadsPerBlock>>>(
                reinterpret_cast<const float2 *>(input.data()),
                output.data(),
                input.size());
            check_kernel_launch("extract_real_part_kernel");
        }
        return output;
    }

    CudaRealArray extract_imag_part_cuda(const CudaComplexArray &input)
    {
        CudaRealArray output = cusignal::core::make_cuda_real_array(input.shape());
        if (!input.empty())
        {
            extract_imag_part_kernel<<<block_count(input.size()), kThreadsPerBlock>>>(
                reinterpret_cast<const float2 *>(input.data()),
                output.data(),
                input.size());
            check_kernel_launch("extract_imag_part_kernel");
        }
        return output;
    }

    CudaComplexArray combine_complex_cuda(
        const CudaRealArray &real_part,
        const CudaRealArray &imag_part)
    {
        if (real_part.shape() != imag_part.shape())
        {
            throw std::invalid_argument("real/imag shape mismatch");
        }
        CudaComplexArray output = cusignal::core::make_cuda_complex_array(real_part.shape());
        if (!real_part.empty())
        {
            combine_complex_kernel<<<block_count(real_part.size()), kThreadsPerBlock>>>(
                real_part.data(),
                imag_part.data(),
                reinterpret_cast<float2 *>(output.data()),
                real_part.size());
            check_kernel_launch("combine_complex_kernel");
        }
        return output;
    }

    CudaComplexArray extract_row_complex_cuda(const CudaComplexArray &input, int row_index)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("extract_row_complex_cuda expects rank-2 input");
        }
        CudaComplexArray output = cusignal::core::make_cuda_complex_array(Shape{input.shape()[1]});
        extract_row_complex_kernel<<<block_count(input.shape()[1]), kThreadsPerBlock>>>(
            reinterpret_cast<const float2 *>(input.data()),
            input.shape()[0],
            input.shape()[1],
            row_index,
            reinterpret_cast<float2 *>(output.data()));
        check_kernel_launch("extract_row_complex_kernel");
        return output;
    }

    CudaRealArray extract_row_real_cuda(const CudaRealArray &input, int row_index)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("extract_row_real_cuda expects rank-2 input");
        }
        CudaRealArray output = cusignal::core::make_cuda_real_array(Shape{input.shape()[1]});
        extract_row_real_kernel<<<block_count(input.shape()[1]), kThreadsPerBlock>>>(
            input.data(),
            input.shape()[0],
            input.shape()[1],
            row_index,
            output.data());
        check_kernel_launch("extract_row_real_kernel");
        return output;
    }

    CudaRealSignal extract_row_real_signal_cuda(const CudaRealArray &input, int row_index)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("extract_row_real_signal_cuda expects rank-2 input");
        }
        CudaRealSignal output(input.shape()[1], false);
        extract_row_real_kernel<<<block_count(input.shape()[1]), kThreadsPerBlock>>>(
            input.data(),
            input.shape()[0],
            input.shape()[1],
            row_index,
            output.data());
        check_kernel_launch("extract_row_real_signal_kernel");
        return output;
    }

    void store_row_real_cuda(
        const CudaRealArray &row,
        CudaRealArray &output,
        int row_index)
    {
        if (row.rank() != 1 || output.rank() != 2)
        {
            throw std::invalid_argument("store_row_real_cuda expects rank-1 row and rank-2 output");
        }
        if (row.shape()[0] != output.shape()[1])
        {
            throw std::invalid_argument("store_row_real_cuda column mismatch");
        }
        if (row_index < 0 || static_cast<std::size_t>(row_index) >= output.shape()[0])
        {
            throw std::invalid_argument("store_row_real_cuda row index out of range");
        }
        store_row_real_kernel<<<block_count(row.shape()[0]), kThreadsPerBlock>>>(
            row.data(),
            row.shape()[0],
            row_index,
            output.data());
        check_kernel_launch("store_row_real_kernel");
    }

    CudaRealArray complex_abs_cuda(const CudaComplexArray &input)
    {
        CudaRealArray output = cusignal::core::make_cuda_real_array(input.shape());
        if (!input.empty())
        {
            complex_abs_kernel<<<block_count(input.size()), kThreadsPerBlock>>>(
                reinterpret_cast<const float2 *>(input.data()),
                output.data(),
                input.size());
            check_kernel_launch("complex_abs_kernel");
        }
        return output;
    }

    CudaRealArray pad_last_value_cuda(const CudaRealArray &input, std::size_t target_len)
    {
        CudaRealArray output = cusignal::core::make_cuda_real_array(Shape{target_len});
        pad_last_value_kernel<<<block_count(target_len), kThreadsPerBlock>>>(
            input.data(),
            input.size(),
            output.data(),
            target_len);
        check_kernel_launch("pad_last_value_kernel");
        return output;
    }

    CudaRealArray normalize_nonnegative_cuda(const CudaRealArray &input)
    {
        CudaRealArray output = cusignal::core::make_cuda_real_array(input.shape());
        if (input.empty())
        {
            return output;
        }

        g_workspace.temp_signal.resize(1, false);
        max_reduce_kernel<<<1, kThreadsPerBlock>>>(input.data(), input.size(), g_workspace.temp_signal.data());
        check_kernel_launch("max_reduce_kernel");
        normalize_kernel<<<block_count(input.size()), kThreadsPerBlock>>>(
            input.data(),
            input.size(),
            g_workspace.temp_signal.data(),
            output.data());
        check_kernel_launch("normalize_kernel");
        return output;
    }

    CudaRealArray batched_demod_score_cuda(const CudaComplexArray &input)
    {
        if (input.rank() != 2)
        {
            throw std::invalid_argument("batched_demod_score_cuda expects rank-2 input");
        }
        CudaRealArray output = cusignal::core::make_cuda_real_array(input.shape());
        if (!input.empty())
        {
            batched_demod_score_kernel<<<input.shape()[0], kThreadsPerBlock>>>(
                reinterpret_cast<const float2 *>(input.data()),
                input.shape()[0],
                input.shape()[1],
                output.data());
            check_kernel_launch("batched_demod_score_kernel");
        }
        return output;
    }

    CudaRealArray spectrogram_band_score_cuda(
        const CudaRealArray &values,
        const CudaRealSignal &freqs,
        const CudaRealSignal &times,
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
        spectrogram_band_energy_kernel<<<block_count(time_count), kThreadsPerBlock>>>(
            values.data(),
            freqs.data(),
            freq_count,
            time_count,
            band_low,
            band_high,
            g_workspace.temp_storage_a.data());
        check_kernel_launch("spectrogram_band_energy_kernel");

        CudaRealArray output = cusignal::core::make_cuda_real_array(Shape{static_cast<std::size_t>(sample_count)});
        map_time_energy_kernel<<<block_count(static_cast<std::size_t>(sample_count)), kThreadsPerBlock>>>(
            g_workspace.temp_storage_a.data(),
            times.data(),
            time_count,
            sample_count,
            fs,
            output.data());
        check_kernel_launch("map_time_energy_kernel");
        return output;
    }

    CudaRealArray cwt_max_score_cuda(const CudaComplexArray &values)
    {
        if (values.rank() != 2)
        {
            throw std::invalid_argument("cwt values must be rank-2");
        }
        CudaRealArray output = cusignal::core::make_cuda_real_array(Shape{values.shape()[1]});
        cwt_max_kernel<<<block_count(values.shape()[1]), kThreadsPerBlock>>>(
            reinterpret_cast<const float2 *>(values.data()),
            values.shape()[0],
            values.shape()[1],
            output.data());
        check_kernel_launch("cwt_max_kernel");
        return output;
    }

    CudaRealArray weighted_sum_cuda(
        const CudaRealArray &corr_score,
        const CudaRealArray &demod_score,
        const CudaRealArray &wavelet_score,
        const CudaRealArray &spectrogram_score,
        float corr_weight,
        float demod_weight,
        float wavelet_weight,
        float spectrogram_weight)
    {
        if (corr_score.shape() != demod_score.shape() ||
            corr_score.shape() != wavelet_score.shape() ||
            corr_score.shape() != spectrogram_score.shape())
        {
            throw std::invalid_argument("weighted_sum_cuda input shape mismatch");
        }
        CudaRealArray output = cusignal::core::make_cuda_real_array(corr_score.shape());
        weighted_sum_kernel<<<block_count(corr_score.size()), kThreadsPerBlock>>>(
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

    CudaRealArray smooth_with_weights_cuda(const CudaRealArray &input, const CudaRealSignal &weights)
    {
        CudaRealArray output = cusignal::core::make_cuda_real_array(input.shape());
        smooth_kernel<<<block_count(input.size()), kThreadsPerBlock>>>(
            input.data(),
            input.size(),
            weights.data(),
            weights.size(),
            output.data());
        check_kernel_launch("smooth_kernel");
        return output;
    }

    void fuse_feature_scores_cuda(
        const CudaRealArray &corr_score,
        const CudaRealArray &demod_score,
        const CudaRealArray &wavelet_score,
        const CudaRealArray &spectrogram_score,
        const CudaRealSignal &weights,
        int peak_order,
        CudaRealArray &feature_scores,
        CudaRealSignal &peak_track)
    {
        if (corr_score.rank() != 2)
        {
            throw std::invalid_argument("fuse_feature_scores_cuda expects rank-2 scores");
        }
        if (corr_score.shape() != demod_score.shape() ||
            corr_score.shape() != wavelet_score.shape() ||
            corr_score.shape() != spectrogram_score.shape())
        {
            throw std::invalid_argument("fuse_feature_scores_cuda input shape mismatch");
        }
        if (weights.empty())
        {
            throw std::invalid_argument("fuse_feature_scores_cuda requires non-empty weights");
        }
        if (peak_order < 1)
        {
            throw std::invalid_argument("fuse_feature_scores_cuda peak_order must be >= 1");
        }

        const std::size_t rows = corr_score.shape()[0];
        const std::size_t cols = corr_score.shape()[1];
        feature_scores.resize(corr_score.shape(), false);
        peak_track.resize(rows, false);
        if (corr_score.empty())
        {
            return;
        }

        fused_feature_smooth_kernel<<<block_count(corr_score.size()), kThreadsPerBlock>>>(
            corr_score.data(),
            demod_score.data(),
            wavelet_score.data(),
            spectrogram_score.data(),
            weights.data(),
            weights.size(),
            rows,
            cols,
            feature_scores.data());
        check_kernel_launch("fused_feature_smooth_kernel");

        row_peak_track_kernel<<<rows, kThreadsPerBlock>>>(
            feature_scores.data(),
            rows,
            cols,
            peak_order,
            peak_track.data());
        check_kernel_launch("row_peak_track_kernel");
    }

    CudaRealSignal kalman_track_from_peaks_cuda(const CudaRealSignal &peak_track)
    {
        CudaRealSignal output = cusignal::core::make_cuda_real_signal(peak_track.size(), 0.0f);
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

    CudaIndexSignal argmax_all_cuda(const CudaRealArray &score)
    {
        CudaIndexSignal output(1, false);
        argmax_all_kernel<<<1, kThreadsPerBlock>>>(score.data(), score.size(), output.data());
        check_kernel_launch("argmax_all_kernel");
        return output;
    }

    CudaIndexSignal argmax_from_candidates_cuda(
        const CudaRealArray &score,
        const CudaIndexSignal &candidates)
    {
        if (candidates.empty())
        {
            return argmax_all_cuda(score);
        }
        CudaIndexSignal output(1, false);
        argmax_candidates_kernel<<<1, kThreadsPerBlock>>>(
            score.data(),
            candidates.data(),
            candidates.size(),
            output.data());
        check_kernel_launch("argmax_candidates_kernel");
        return output;
    }

    CudaRealArray index_to_measurement_cuda(const CudaIndexSignal &index)
    {
        CudaRealArray measurement = cusignal::core::make_cuda_real_array(Shape{1, 1, 1});
        index_to_measurement_kernel<<<1, 1>>>(index.data(), measurement.data());
        check_kernel_launch("index_to_measurement_kernel");
        return measurement;
    }

    void initialize_state_from_index_cuda(
        const CudaIndexSignal &index,
        CudaRealArray &state)
    {
        if (state.empty())
        {
            throw std::invalid_argument("initialize_state_from_index_cuda requires non-empty state");
        }
        initialize_state_from_index_kernel<<<block_count(state.size()), kThreadsPerBlock>>>(
            index.data(),
            state.data(),
            state.size());
        check_kernel_launch("initialize_state_from_index_kernel");
    }

    void write_index_to_track_cuda(
        const CudaIndexSignal &index,
        CudaRealSignal &track,
        int frame_index)
    {
        write_index_to_track_kernel<<<1, 1>>>(index.data(), track.data(), frame_index);
        check_kernel_launch("write_index_to_track_kernel");
    }

    void write_state_position_to_track_cuda(
        const CudaRealArray &state,
        CudaRealSignal &track,
        int frame_index)
    {
        write_state_position_to_track_kernel<<<1, 1>>>(state.data(), track.data(), frame_index);
        check_kernel_launch("write_state_position_to_track_kernel");
    }
}
