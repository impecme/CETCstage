#include "cusignal/peak_finding/peak_finding.hpp"

#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include <limits>
#include <vector>

#include "cusignal/core/helpers.hpp"

#include "../common/peak_finding_detail.hpp"

namespace
{
    using cusignal::core::CudaIndexSignal;
    using cusignal::core::CudaRealArray;
    using cusignal::core::IndexVector;
    using cusignal::peak_finding_api::CudaExtremaResult;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0f;

    class ScopedCudaEvents
    {
    public:
        ScopedCudaEvents()
        {
            cusignal::core::throw_on_cuda_error(cudaEventCreate(&start_), "cudaEventCreate(start)");
            cusignal::core::throw_on_cuda_error(cudaEventCreate(&stop_), "cudaEventCreate(stop)");
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
            cusignal::core::throw_on_cuda_error(cudaEventRecord(start_), "cudaEventRecord(start)");
            callable();
            cusignal::core::throw_on_cuda_error(cudaEventRecord(stop_), "cudaEventRecord(stop)");
            cusignal::core::throw_on_cuda_error(cudaEventSynchronize(stop_), "cudaEventSynchronize(stop)");
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

    template <typename T>
    class DeviceBuffer
    {
    public:
        ~DeviceBuffer()
        {
            if (data_ != nullptr)
            {
                cudaFree(data_);
            }
        }

        void reserve(std::size_t count)
        {
            if (count <= capacity_)
            {
                return;
            }
            if (data_ != nullptr)
            {
                cudaFree(data_);
            }
            data_ = nullptr;
            capacity_ = 0;
            if (count != 0)
            {
                cusignal::core::throw_on_cuda_error(
                    cudaMalloc(reinterpret_cast<void **>(&data_), count * sizeof(T)),
                    "cudaMalloc");
                capacity_ = count;
            }
        }

        T *get() { return data_; }
        const T *get() const { return data_; }

    private:
        T *data_ = nullptr;
        std::size_t capacity_ = 0;
    };

    struct PeakFindingWorkspace
    {
        CudaRealArray data_storage;
        CudaIndexSignal shape_storage;
        CudaIndexSignal strides_storage;
        CudaIndexSignal flat_hits_storage;
        std::vector<CudaIndexSignal> axis_outputs;
        DeviceBuffer<unsigned char> mask_storage;
        DeviceBuffer<unsigned char> select_temp_storage;
        DeviceBuffer<int> hit_count_storage;
        DeviceBuffer<int *> axis_pointer_buffer;
        cusignal::core::Shape cached_shape;
        std::vector<std::size_t> cached_strides;
        bool metadata_valid = false;
    };

    thread_local PeakFindingWorkspace g_workspace;

    int block_count(std::size_t count)
    {
        return count == 0 ? 0 : static_cast<int>((count + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    void check_kernel_launch(const char *what)
    {
        cusignal::core::throw_on_cuda_error(cudaGetLastError(), what);
    }

    __device__ bool compare_value(float lhs, float rhs, int comparator_code)
    {
        return comparator_code == 0 ? (lhs > rhs) : (lhs < rhs);
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

    __global__ void extrema_mask_kernel(
        const float *data,
        int rank,
        const int *shape,
        const int *strides,
        int axis,
        int order,
        int comparator_code,
        int mode_code,
        std::size_t axis_size,
        std::size_t axis_stride,
        std::size_t line_count,
        unsigned char *mask)
    {
        const std::size_t flat_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * axis_size;
        if (flat_index >= total)
        {
            return;
        }
        const std::size_t line_index = flat_index / axis_size;
        const std::size_t axis_index = flat_index % axis_size;
        const std::size_t base =
            line_base_offset_device(shape, strides, rank, axis, line_index);
        const std::size_t current = base + axis_index * axis_stride;
        const float center = data[current];
        bool is_extrema = true;
        for (int shift = 1; shift <= order && is_extrema; ++shift)
        {
            long long plus = static_cast<long long>(axis_index) + shift;
            long long minus = static_cast<long long>(axis_index) - shift;
            if (mode_code == 0)
            {
                plus = min(
                    max(plus, 0LL),
                    static_cast<long long>(axis_size - 1));
                minus = min(
                    max(minus, 0LL),
                    static_cast<long long>(axis_size - 1));
            }
            else
            {
                plus = (plus % static_cast<long long>(axis_size) +
                        static_cast<long long>(axis_size)) %
                       static_cast<long long>(axis_size);
                minus = (minus % static_cast<long long>(axis_size) +
                         static_cast<long long>(axis_size)) %
                        static_cast<long long>(axis_size);
            }
            const float plus_value =
                data[base + static_cast<std::size_t>(plus) * axis_stride];
            const float minus_value =
                data[base + static_cast<std::size_t>(minus) * axis_stride];
            is_extrema = compare_value(center, plus_value, comparator_code) &&
                         compare_value(center, minus_value, comparator_code);
        }
        mask[current] = is_extrema ? 1 : 0;
    }

    __global__ void flat_to_axis_indices_kernel(
        const int *flat_indices,
        std::size_t hit_count,
        int rank,
        const int *shape,
        const int *strides,
        int **axis_outputs)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= hit_count)
        {
            return;
        }
        int remaining = flat_indices[index];
        for (int dim = 0; dim < rank; ++dim)
        {
            const int stride = strides[dim];
            const int coord = remaining / stride;
            remaining %= stride;
            axis_outputs[dim][index] = coord;
        }
    }
} // namespace

namespace cusignal
{
    namespace cuda_backend
    {
        namespace peak_finding
        {

            CudaExtremaResult argrelextrema(
                const core::RealArrayLike &data,
                const std::string &comparator,
                int axis,
                int order,
                const std::string &mode)
            {
                namespace detail = cusignal::peak_finding_detail;
                const std::string normalized_comparator =
                    detail::normalize_comparator(comparator);
                const std::string normalized_mode = detail::normalize_mode(mode);
                if (order < 1)
                {
                    throw std::invalid_argument("order must be >= 1");
                }

                const CudaRealArray &device_data = core::as_device_array(data, g_workspace.data_storage);
                const detail::AxisPlan plan = detail::make_axis_plan(device_data.shape(), axis);
                const std::size_t total = device_data.size();
                if (total > static_cast<std::size_t>(std::numeric_limits<int>::max()))
                {
                    throw std::invalid_argument("argrelextrema input is too large for int index output");
                }
                g_workspace.mask_storage.reserve(total);
                g_workspace.hit_count_storage.reserve(1);

                if (!g_workspace.metadata_valid ||
                    g_workspace.cached_shape != plan.shape ||
                    g_workspace.cached_strides != plan.strides)
                {
                    IndexVector shape_vector(device_data.rank(), 0);
                    IndexVector stride_vector(device_data.rank(), 0);
                    for (std::size_t dim = 0; dim < device_data.rank(); ++dim)
                    {
                        shape_vector[dim] = static_cast<int>(plan.shape[dim]);
                        stride_vector[dim] = static_cast<int>(plan.strides[dim]);
                    }
                    g_workspace.shape_storage.copy_from(shape_vector);
                    g_workspace.strides_storage.copy_from(stride_vector);
                    g_workspace.cached_shape = plan.shape;
                    g_workspace.cached_strides = plan.strides;
                    g_workspace.metadata_valid = true;
                }

                ScopedCudaEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    extrema_mask_kernel<<<block_count(total), kThreadsPerBlock>>>(
                        device_data.data(),
                        static_cast<int>(device_data.rank()),
                        g_workspace.shape_storage.data(),
                        g_workspace.strides_storage.data(),
                        static_cast<int>(plan.axis),
                        order,
                        normalized_comparator == "greater" ? 0 : 1,
                        normalized_mode == "clip" ? 0 : 1,
                        plan.axis_size,
                        plan.axis_stride,
                        plan.line_count,
                        g_workspace.mask_storage.get());
                    check_kernel_launch("extrema_mask_kernel");

                    g_workspace.flat_hits_storage.resize(total, false);
                    cub::CountingInputIterator<int> counting_begin(0);
                    std::size_t temp_storage_bytes = 0;
                    cusignal::core::throw_on_cuda_error(
                        cub::DeviceSelect::Flagged(
                            nullptr,
                            temp_storage_bytes,
                            counting_begin,
                            g_workspace.mask_storage.get(),
                            g_workspace.flat_hits_storage.data(),
                            g_workspace.hit_count_storage.get(),
                            static_cast<int>(total)),
                        "cub::DeviceSelect::Flagged(size_query)");
                    g_workspace.select_temp_storage.reserve(temp_storage_bytes);
                    cusignal::core::throw_on_cuda_error(
                        cub::DeviceSelect::Flagged(
                            g_workspace.select_temp_storage.get(),
                            temp_storage_bytes,
                            counting_begin,
                            g_workspace.mask_storage.get(),
                            g_workspace.flat_hits_storage.data(),
                            g_workspace.hit_count_storage.get(),
                            static_cast<int>(total)),
                        "cub::DeviceSelect::Flagged");
                    int hit_count_device = 0;
                    cusignal::core::throw_on_cuda_error(
                        cudaMemcpy(
                            &hit_count_device,
                            g_workspace.hit_count_storage.get(),
                            sizeof(int),
                            cudaMemcpyDeviceToHost),
                        "cudaMemcpy D2H(hit_count)");
                    const std::size_t hit_count = static_cast<std::size_t>(hit_count_device);
                    g_workspace.flat_hits_storage.resize(hit_count, false);

                    if (g_workspace.axis_outputs.size() != device_data.rank())
                    {
                        g_workspace.axis_outputs.resize(device_data.rank());
                    }
                    std::vector<int *> axis_output_ptrs(device_data.rank(), nullptr);
                    for (std::size_t dim = 0; dim < device_data.rank(); ++dim)
                    {
                        g_workspace.axis_outputs[dim].resize(hit_count, false);
                        axis_output_ptrs[dim] = g_workspace.axis_outputs[dim].data();
                    }

                    g_workspace.axis_pointer_buffer.reserve(axis_output_ptrs.size());
                    if (!axis_output_ptrs.empty())
                    {
                        cusignal::core::throw_on_cuda_error(
                            cudaMemcpy(
                                g_workspace.axis_pointer_buffer.get(),
                                axis_output_ptrs.data(),
                                axis_output_ptrs.size() * sizeof(int *),
                                cudaMemcpyHostToDevice),
                            "cudaMemcpy H2D");
                    }
                    if (hit_count != 0)
                    {
                        flat_to_axis_indices_kernel<<<block_count(hit_count), kThreadsPerBlock>>>(
                            g_workspace.flat_hits_storage.data(),
                            hit_count,
                            static_cast<int>(device_data.rank()),
                            g_workspace.shape_storage.data(),
                            g_workspace.strides_storage.data(),
                            g_workspace.axis_pointer_buffer.get());
                        check_kernel_launch("flat_to_axis_indices_kernel");
                    }
                });

                CudaExtremaResult result;
                result.indices = g_workspace.axis_outputs;
                return result;
            }

            CudaExtremaResult argrelmin(
                const core::RealArrayLike &data,
                int axis,
                int order,
                const std::string &mode)
            {
                return argrelextrema(data, "less", axis, order, mode);
            }

            CudaExtremaResult argrelmax(
                const core::RealArrayLike &data,
                int axis,
                int order,
                const std::string &mode)
            {
                return argrelextrema(data, "greater", axis, order, mode);
            }

        } // namespace peak_finding

        namespace peak_finding_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0f;
                return value;
            }
        } // namespace peak_finding_test_hooks
    } // namespace cuda_backend
} // namespace cusignal
