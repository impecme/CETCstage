#include "cusignal/correlate/correlate.hpp"

#include <cuda_runtime.h>

#include <algorithm>
#include <stdexcept>
#include <string>
#include <vector>

#include "cusignal/core/helpers.hpp"

#include "../common/correlate_detail.hpp"

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::IndexVector;
    using cusignal::core::Shape;
    namespace detail = cusignal::correlate_detail;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0f;

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

        template <typename Callable>
        float measure(Callable callable)
        {
            throw_on_zx_gpu_error(cudaEventRecord(start_), "cudaEventRecord(start)");
            callable();
            throw_on_zx_gpu_error(cudaEventRecord(stop_), "cudaEventRecord(stop)");
            throw_on_zx_gpu_error(cudaEventSynchronize(stop_), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            throw_on_zx_gpu_error(cudaEventElapsedTime(&elapsed_ms, start_, stop_), "cudaEventElapsedTime");
            return elapsed_ms;
        }

    private:
        cudaEvent_t start_ = nullptr;
        cudaEvent_t stop_ = nullptr;
    };

    struct CorrelateWorkspace
    {
        ZxGpuRealArray real_left_storage;
        ZxGpuRealArray real_right_storage;
        ZxGpuComplexArray complex_left_storage;
        ZxGpuComplexArray complex_right_storage;
        ZxGpuIndexSignal left_shape_storage;
        ZxGpuIndexSignal right_shape_storage;
        ZxGpuIndexSignal left_strides_storage;
        ZxGpuIndexSignal right_strides_storage;
        ZxGpuIndexSignal output_shape_storage;
        ZxGpuIndexSignal output_strides_storage;
        ZxGpuIndexSignal start_storage;
    };

    thread_local CorrelateWorkspace g_workspace;

    int block_count(std::size_t count)
    {
        return count == 0 ? 0 : static_cast<int>((count + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    template <typename SizeContainer>
    IndexVector to_index_vector(const SizeContainer &values)
    {
        IndexVector result(values.size(), 0);
        for (std::size_t index = 0; index < values.size(); ++index)
        {
            result[index] = static_cast<int>(values[index]);
        }
        return result;
    }

    inline void upload_shape_metadata(
        const Shape &left_shape,
        const Shape &right_shape,
        const Shape &output_shape,
        const Shape &start)
    {
        g_workspace.left_shape_storage.copy_from(to_index_vector(left_shape));
        g_workspace.right_shape_storage.copy_from(to_index_vector(right_shape));
        g_workspace.left_strides_storage.copy_from(to_index_vector(detail::compute_strides(left_shape)));
        g_workspace.right_strides_storage.copy_from(to_index_vector(detail::compute_strides(right_shape)));
        g_workspace.output_shape_storage.copy_from(to_index_vector(output_shape));
        g_workspace.output_strides_storage.copy_from(to_index_vector(detail::compute_strides(output_shape)));
        g_workspace.start_storage.copy_from(to_index_vector(start));
    }

    __device__ inline float2 complex_mul(float2 lhs, float2 rhs)
    {
        return float2{
            lhs.x * rhs.x - lhs.y * rhs.y,
            lhs.x * rhs.y + lhs.y * rhs.x};
    }

    __device__ inline float2 complex_conj(float2 value)
    {
        return float2{value.x, -value.y};
    }

    __device__ inline float2 complex_add(float2 lhs, float2 rhs)
    {
        return float2{lhs.x + rhs.x, lhs.y + rhs.y};
    }

    __device__ inline std::size_t wrap_index_device(long long index, int size)
    {
        const long long mod = index % static_cast<long long>(size);
        return static_cast<std::size_t>(mod < 0 ? mod + static_cast<long long>(size) : mod);
    }

    __device__ inline std::size_t symmetric_index_device(long long index, int size)
    {
        if (size <= 1)
        {
            return 0;
        }
        const long long period = 2LL * static_cast<long long>(size);
        while (index < 0 || index >= static_cast<long long>(size))
        {
            if (index < 0)
            {
                index = -index - 1;
            }
            else
            {
                index = period - index - 1;
            }
        }
        return static_cast<std::size_t>(index);
    }

    __global__ void correlate_nd_real_kernel(
        float *output,
        const float *left,
        const float *right,
        std::size_t output_size,
        std::size_t right_size,
        int rank,
        const int *left_shape,
        const int *right_shape,
        const int *left_strides,
        const int *right_strides,
        const int *output_shape,
        const int *output_strides,
        const int *start)
    {
        const std::size_t out_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(threadIdx.x);
        if (out_index >= output_size)
        {
            return;
        }

        float accum = 0.0f;
        for (std::size_t kernel_index = 0; kernel_index < right_size; ++kernel_index)
        {
            std::size_t tmp_out = out_index;
            std::size_t tmp_kernel = kernel_index;
            bool in_bounds = true;
            std::size_t input_flat = 0;
            for (int axis = 0; axis < rank; ++axis)
            {
                const int out_coord = static_cast<int>(tmp_out / static_cast<std::size_t>(output_strides[axis]));
                tmp_out %= static_cast<std::size_t>(output_strides[axis]);
                const int kernel_coord = static_cast<int>(tmp_kernel / static_cast<std::size_t>(right_strides[axis]));
                tmp_kernel %= static_cast<std::size_t>(right_strides[axis]);
                const long long full_coord =
                    static_cast<long long>(out_coord) + static_cast<long long>(start[axis]);
                const long long input_coord =
                    full_coord + static_cast<long long>(kernel_coord) -
                    static_cast<long long>(right_shape[axis] - 1);
                if (input_coord < 0 || input_coord >= static_cast<long long>(left_shape[axis]))
                {
                    in_bounds = false;
                    break;
                }
                input_flat +=
                    static_cast<std::size_t>(input_coord) * static_cast<std::size_t>(left_strides[axis]);
            }
            if (in_bounds)
            {
                accum += left[input_flat] * right[kernel_index];
            }
        }
        output[out_index] = accum;
    }

    __global__ void correlate_nd_complex_kernel(
        float2 *output,
        const float2 *left,
        const float2 *right,
        std::size_t output_size,
        std::size_t right_size,
        int rank,
        const int *left_shape,
        const int *right_shape,
        const int *left_strides,
        const int *right_strides,
        const int *output_shape,
        const int *output_strides,
        const int *start)
    {
        const std::size_t out_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(threadIdx.x);
        if (out_index >= output_size)
        {
            return;
        }

        float2 accum{0.0f, 0.0f};
        for (std::size_t kernel_index = 0; kernel_index < right_size; ++kernel_index)
        {
            std::size_t tmp_out = out_index;
            std::size_t tmp_kernel = kernel_index;
            bool in_bounds = true;
            std::size_t input_flat = 0;
            for (int axis = 0; axis < rank; ++axis)
            {
                const int out_coord = static_cast<int>(tmp_out / static_cast<std::size_t>(output_strides[axis]));
                tmp_out %= static_cast<std::size_t>(output_strides[axis]);
                const int kernel_coord = static_cast<int>(tmp_kernel / static_cast<std::size_t>(right_strides[axis]));
                tmp_kernel %= static_cast<std::size_t>(right_strides[axis]);
                const long long full_coord =
                    static_cast<long long>(out_coord) + static_cast<long long>(start[axis]);
                const long long input_coord =
                    full_coord + static_cast<long long>(kernel_coord) -
                    static_cast<long long>(right_shape[axis] - 1);
                if (input_coord < 0 || input_coord >= static_cast<long long>(left_shape[axis]))
                {
                    in_bounds = false;
                    break;
                }
                input_flat +=
                    static_cast<std::size_t>(input_coord) * static_cast<std::size_t>(left_strides[axis]);
            }
            if (in_bounds)
            {
                accum = complex_add(accum, complex_mul(left[input_flat], complex_conj(right[kernel_index])));
            }
        }
        output[out_index] = accum;
    }

    __global__ void correlate2d_real_kernel(
        float *output,
        const float *left,
        const float *right,
        int out_rows,
        int out_cols,
        int rows1,
        int cols1,
        int rows2,
        int cols2,
        int start_row,
        int start_col,
        int boundary_mode,
        float fillvalue)
    {
        const std::size_t flat_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(threadIdx.x);
        const std::size_t output_size = static_cast<std::size_t>(out_rows) * static_cast<std::size_t>(out_cols);
        if (flat_index >= output_size)
        {
            return;
        }

        const int row = static_cast<int>(flat_index / static_cast<std::size_t>(out_cols));
        const int col = static_cast<int>(flat_index % static_cast<std::size_t>(out_cols));
        const long long full_row = static_cast<long long>(row + start_row);
        const long long full_col = static_cast<long long>(col + start_col);
        float accum = 0.0f;

        for (int kr = 0; kr < rows2; ++kr)
        {
            for (int kc = 0; kc < cols2; ++kc)
            {
                const long long input_row = full_row + kr - (rows2 - 1);
                const long long input_col = full_col + kc - (cols2 - 1);
                float sample = 0.0f;
                if (input_row >= 0 && input_row < rows1 && input_col >= 0 && input_col < cols1)
                {
                    sample = left[static_cast<std::size_t>(input_row) * static_cast<std::size_t>(cols1) +
                                  static_cast<std::size_t>(input_col)];
                }
                else if (boundary_mode == 0)
                {
                    sample = fillvalue;
                }
                else if (boundary_mode == 1)
                {
                    const std::size_t rr = wrap_index_device(input_row, rows1);
                    const std::size_t cc = wrap_index_device(input_col, cols1);
                    sample = left[rr * static_cast<std::size_t>(cols1) + cc];
                }
                else
                {
                    const std::size_t rr = symmetric_index_device(input_row, rows1);
                    const std::size_t cc = symmetric_index_device(input_col, cols1);
                    sample = left[rr * static_cast<std::size_t>(cols1) + cc];
                }
                accum += sample * right[static_cast<std::size_t>(kr) * static_cast<std::size_t>(cols2) +
                                        static_cast<std::size_t>(kc)];
            }
        }

        output[flat_index] = accum;
    }

    __global__ void correlate2d_complex_kernel(
        float2 *output,
        const float2 *left,
        const float2 *right,
        int out_rows,
        int out_cols,
        int rows1,
        int cols1,
        int rows2,
        int cols2,
        int start_row,
        int start_col,
        int boundary_mode,
        float fillvalue)
    {
        const std::size_t flat_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(threadIdx.x);
        const std::size_t output_size = static_cast<std::size_t>(out_rows) * static_cast<std::size_t>(out_cols);
        if (flat_index >= output_size)
        {
            return;
        }

        const int row = static_cast<int>(flat_index / static_cast<std::size_t>(out_cols));
        const int col = static_cast<int>(flat_index % static_cast<std::size_t>(out_cols));
        const long long full_row = static_cast<long long>(row + start_row);
        const long long full_col = static_cast<long long>(col + start_col);
        float2 accum{0.0f, 0.0f};

        for (int kr = 0; kr < rows2; ++kr)
        {
            for (int kc = 0; kc < cols2; ++kc)
            {
                const long long input_row = full_row + kr - (rows2 - 1);
                const long long input_col = full_col + kc - (cols2 - 1);
                float2 sample{0.0f, 0.0f};
                if (input_row >= 0 && input_row < rows1 && input_col >= 0 && input_col < cols1)
                {
                    sample = left[static_cast<std::size_t>(input_row) * static_cast<std::size_t>(cols1) +
                                  static_cast<std::size_t>(input_col)];
                }
                else if (boundary_mode == 0)
                {
                    sample = float2{fillvalue, 0.0f};
                }
                else if (boundary_mode == 1)
                {
                    const std::size_t rr = wrap_index_device(input_row, rows1);
                    const std::size_t cc = wrap_index_device(input_col, cols1);
                    sample = left[rr * static_cast<std::size_t>(cols1) + cc];
                }
                else
                {
                    const std::size_t rr = symmetric_index_device(input_row, rows1);
                    const std::size_t cc = symmetric_index_device(input_col, cols1);
                    sample = left[rr * static_cast<std::size_t>(cols1) + cc];
                }
                const float2 kernel =
                    complex_conj(right[static_cast<std::size_t>(kr) * static_cast<std::size_t>(cols2) +
                                       static_cast<std::size_t>(kc)]);
                accum = complex_add(accum, complex_mul(sample, kernel));
            }
        }

        output[flat_index] = accum;
    }

    __global__ void correlation_lags_kernel(int *output, int count, int start)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        output[index] = start + index;
    }

    template <typename ArrayLike>
    inline void ensure_direct_rank_1(const ArrayLike &in1, const ArrayLike &in2, const std::string &method)
    {
        const std::string normalized_method = detail::normalize_method(method);
        if (normalized_method == "direct" &&
            (in1.rank() != 1 || in2.rank() != 1))
        {
            throw std::invalid_argument("direct correlate only supports 1D inputs");
        }
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace correlate
        {
            core::ZxGpuRealArray correlate(
                const core::RealArrayLike &in1,
                const core::RealArrayLike &in2,
                const std::string &mode,
                const std::string &method)
            {
                const ZxGpuRealArray &left = core::as_device_array(in1, g_workspace.real_left_storage);
                const ZxGpuRealArray &right = core::as_device_array(in2, g_workspace.real_right_storage);
                detail::ensure_same_rank(left.shape(), right.shape());
                const std::string normalized_mode = detail::normalize_mode(mode);
                ensure_direct_rank_1(left, right, method);
                if (normalized_mode == "valid")
                {
                    detail::ensure_valid_compatible(left.shape(), right.shape());
                }

                const Shape output_shape = detail::output_shape(left.shape(), right.shape(), normalized_mode);
                const Shape start = detail::crop_start(left.shape(), right.shape(), normalized_mode);
                ZxGpuRealArray output(output_shape, true);
                if (output.size() == 0)
                {
                    g_last_kernel_ms = 0.0f;
                    return output;
                }

                upload_shape_metadata(left.shape(), right.shape(), output_shape, start);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    correlate_nd_real_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        output.data(),
                        left.data(),
                        right.data(),
                        output.size(),
                        right.size(),
                        static_cast<int>(left.rank()),
                        g_workspace.left_shape_storage.data(),
                        g_workspace.right_shape_storage.data(),
                        g_workspace.left_strides_storage.data(),
                        g_workspace.right_strides_storage.data(),
                        g_workspace.output_shape_storage.data(),
                        g_workspace.output_strides_storage.data(),
                        g_workspace.start_storage.data());
                    check_kernel_launch("correlate_nd_real_kernel");
                });
                return output;
            }

            core::ZxGpuComplexArray correlate(
                const core::ComplexArrayLike &in1,
                const core::ComplexArrayLike &in2,
                const std::string &mode,
                const std::string &method)
            {
                const ZxGpuComplexArray &left = core::as_device_array(in1, g_workspace.complex_left_storage);
                const ZxGpuComplexArray &right = core::as_device_array(in2, g_workspace.complex_right_storage);
                detail::ensure_same_rank(left.shape(), right.shape());
                const std::string normalized_mode = detail::normalize_mode(mode);
                ensure_direct_rank_1(left, right, method);
                if (normalized_mode == "valid")
                {
                    detail::ensure_valid_compatible(left.shape(), right.shape());
                }

                const Shape output_shape = detail::output_shape(left.shape(), right.shape(), normalized_mode);
                const Shape start = detail::crop_start(left.shape(), right.shape(), normalized_mode);
                ZxGpuComplexArray output(output_shape, true);
                if (output.size() == 0)
                {
                    g_last_kernel_ms = 0.0f;
                    return output;
                }

                upload_shape_metadata(left.shape(), right.shape(), output_shape, start);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    correlate_nd_complex_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        output.data(),
                        left.data(),
                        right.data(),
                        output.size(),
                        right.size(),
                        static_cast<int>(left.rank()),
                        g_workspace.left_shape_storage.data(),
                        g_workspace.right_shape_storage.data(),
                        g_workspace.left_strides_storage.data(),
                        g_workspace.right_strides_storage.data(),
                        g_workspace.output_shape_storage.data(),
                        g_workspace.output_strides_storage.data(),
                        g_workspace.start_storage.data());
                    check_kernel_launch("correlate_nd_complex_kernel");
                });
                return output;
            }

            core::ZxGpuRealArray correlate2d(
                const core::RealArrayLike &in1,
                const core::RealArrayLike &in2,
                const std::string &mode,
                const std::string &boundary,
                float fillvalue)
            {
                const ZxGpuRealArray &left = core::as_device_array(in1, g_workspace.real_left_storage);
                const ZxGpuRealArray &right = core::as_device_array(in2, g_workspace.real_right_storage);
                if (left.rank() != 2 || right.rank() != 2)
                {
                    throw std::invalid_argument("correlate2d inputs must both be rank-2");
                }
                const std::string normalized_mode = detail::normalize_mode(mode);
                const std::string normalized_boundary = detail::normalize_boundary(boundary);
                if (normalized_mode == "valid")
                {
                    detail::ensure_valid_compatible(left.shape(), right.shape());
                }

                const Shape output_shape = detail::output_shape(left.shape(), right.shape(), normalized_mode);
                const Shape start = detail::crop_start(left.shape(), right.shape(), normalized_mode);
                ZxGpuRealArray output(output_shape, true);
                if (output.size() == 0)
                {
                    g_last_kernel_ms = 0.0f;
                    return output;
                }

                int boundary_mode = 0;
                if (normalized_boundary == "wrap")
                {
                    boundary_mode = 1;
                }
                else if (normalized_boundary == "symm")
                {
                    boundary_mode = 2;
                }

                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    correlate2d_real_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        output.data(),
                        left.data(),
                        right.data(),
                        static_cast<int>(output_shape[0]),
                        static_cast<int>(output_shape[1]),
                        static_cast<int>(left.shape()[0]),
                        static_cast<int>(left.shape()[1]),
                        static_cast<int>(right.shape()[0]),
                        static_cast<int>(right.shape()[1]),
                        static_cast<int>(start[0]),
                        static_cast<int>(start[1]),
                        boundary_mode,
                        fillvalue);
                    check_kernel_launch("correlate2d_real_kernel");
                });
                return output;
            }

            core::ZxGpuComplexArray correlate2d(
                const core::ComplexArrayLike &in1,
                const core::ComplexArrayLike &in2,
                const std::string &mode,
                const std::string &boundary,
                float fillvalue)
            {
                const ZxGpuComplexArray &left = core::as_device_array(in1, g_workspace.complex_left_storage);
                const ZxGpuComplexArray &right = core::as_device_array(in2, g_workspace.complex_right_storage);
                if (left.rank() != 2 || right.rank() != 2)
                {
                    throw std::invalid_argument("correlate2d inputs must both be rank-2");
                }
                const std::string normalized_mode = detail::normalize_mode(mode);
                const std::string normalized_boundary = detail::normalize_boundary(boundary);
                if (normalized_mode == "valid")
                {
                    detail::ensure_valid_compatible(left.shape(), right.shape());
                }

                const Shape output_shape = detail::output_shape(left.shape(), right.shape(), normalized_mode);
                const Shape start = detail::crop_start(left.shape(), right.shape(), normalized_mode);
                ZxGpuComplexArray output(output_shape, true);
                if (output.size() == 0)
                {
                    g_last_kernel_ms = 0.0f;
                    return output;
                }

                int boundary_mode = 0;
                if (normalized_boundary == "wrap")
                {
                    boundary_mode = 1;
                }
                else if (normalized_boundary == "symm")
                {
                    boundary_mode = 2;
                }

                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    correlate2d_complex_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        output.data(),
                        left.data(),
                        right.data(),
                        static_cast<int>(output_shape[0]),
                        static_cast<int>(output_shape[1]),
                        static_cast<int>(left.shape()[0]),
                        static_cast<int>(left.shape()[1]),
                        static_cast<int>(right.shape()[0]),
                        static_cast<int>(right.shape()[1]),
                        static_cast<int>(start[0]),
                        static_cast<int>(start[1]),
                        boundary_mode,
                        fillvalue);
                    check_kernel_launch("correlate2d_complex_kernel");
                });
                return output;
            }

            core::ZxGpuIndexSignal correlation_lags(
                int in1_len,
                int in2_len,
                const std::string &mode)
            {
                if (in1_len <= 0 || in2_len <= 0)
                {
                    throw std::invalid_argument("input lengths must be positive");
                }
                const std::string normalized_mode = detail::normalize_mode(mode);
                int count = 0;
                int start = 0;
                if (normalized_mode == "full")
                {
                    count = in1_len + in2_len - 1;
                    start = -(in2_len - 1);
                }
                else if (normalized_mode == "same")
                {
                    count = in1_len;
                    start = -((in2_len - 1));
                    const int full_size = in1_len + in2_len - 1;
                    start += (full_size - in1_len) / 2;
                }
                else
                {
                    const int lag_bound = in1_len - in2_len;
                    count = std::abs(lag_bound) + 1;
                    start = lag_bound >= 0 ? 0 : lag_bound;
                }

                ZxGpuIndexSignal output(static_cast<std::size_t>(count), true);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    correlation_lags_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        output.data(),
                        count,
                        start);
                    check_kernel_launch("correlation_lags_kernel");
                });
                return output;
            }

        } // namespace correlate

        namespace correlate_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0f;
                return value;
            }
        } // namespace correlate_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
