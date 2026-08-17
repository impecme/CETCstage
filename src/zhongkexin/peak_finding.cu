#include "cusignal/peak_finding/peak_finding.hpp"

#include <cuda_runtime.h>

#include <cstdint>
#include <limits>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/benchmark_input_protocol.hpp"

#include "../common/peak_finding_detail.hpp"
#include "../common/zx_execution_context.hpp"
#include "../common/zx_tile_policy.hpp"

namespace
{
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::IndexVector;
    using cusignal::peak_finding_api::ZxGpuExtremaResult;
    namespace tile = cusignal::zx_tile;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0f;

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

    template <typename T>
    class LegacyDeviceBuffer
    {
    public:
        LegacyDeviceBuffer() = default;
        LegacyDeviceBuffer(const LegacyDeviceBuffer &) = delete;
        LegacyDeviceBuffer &operator=(const LegacyDeviceBuffer &) = delete;

        ~LegacyDeviceBuffer()
        {
            reset();
        }

        void reserve(std::size_t count)
        {
            if (count <= capacity_)
            {
                return;
            }
            reset();
            if (count != 0)
            {
                cusignal::core::throw_on_zx_gpu_error(
                    cudaMalloc(reinterpret_cast<void **>(&data_), count * sizeof(T)),
                    "cudaMalloc");
                capacity_ = count;
            }
        }

        void reset() noexcept
        {
            if (data_ != nullptr)
            {
                (void)cudaFree(data_);
                data_ = nullptr;
            }
            capacity_ = 0;
        }

        T *get() { return data_; }
        const T *get() const { return data_; }

    private:
        T *data_ = nullptr;
        std::size_t capacity_ = 0;
    };

    template <typename T>
    class DeviceBuffer
    {
    public:
        void set_optimized(bool optimized)
        {
            if (optimized_ == optimized)
            {
                return;
            }
            cached_.reset();
            legacy_.reset();
            optimized_ = optimized;
        }

        void reserve(std::size_t count)
        {
            if (optimized_)
            {
                cached_.reserve(count);
            }
            else
            {
                legacy_.reserve(count);
            }
        }

        T *get()
        {
            return optimized_ ? cached_.get() : legacy_.get();
        }

        const T *get() const
        {
            return optimized_ ? cached_.get() : legacy_.get();
        }

    private:
        bool optimized_ = false;
        cusignal::zx_execution::ReusableDeviceBuffer<T> cached_;
        LegacyDeviceBuffer<T> legacy_;
    };

    struct PeakFindingWorkspace
    {
        ZxGpuRealArray data_storage;
        ZxGpuIndexSignal shape_storage;
        ZxGpuIndexSignal strides_storage;
        ZxGpuIndexSignal flat_hits_storage;
        std::vector<ZxGpuIndexSignal> axis_outputs;
        DeviceBuffer<unsigned char> mask_storage;
        DeviceBuffer<int> hit_count_storage;
        DeviceBuffer<int *> axis_pointer_buffer;
        cusignal::core::Shape cached_shape;
        std::vector<std::size_t> cached_strides;
        bool metadata_valid = false;

        void configure_buffers(bool optimized)
        {
            mask_storage.set_optimized(optimized);
            hit_count_storage.set_optimized(optimized);
            axis_pointer_buffer.set_optimized(optimized);
        }
    };

    thread_local PeakFindingWorkspace g_workspace;

    int block_count(std::size_t count)
    {
        return count == 0
            ? 0
            : static_cast<int>(tile::ceil_div(count, static_cast<std::size_t>(tile::linear_shape(count).threads)));
    }

    void check_kernel_launch(const char *what)
    {
        cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), what);
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

    // For a contiguous last axis, use one block per row and keep the row base
    // in the block's address calculation.  This is the reduction/epilogue
    // half of the CUTLASS-style row tile: every thread evaluates a register
    // tile of extrema flags, while the existing compact stage preserves the
    // public variable-length output contract.
    __global__ void extrema_mask_contiguous_row_tile_kernel(
        const float *data,
        std::size_t axis_size,
        std::size_t line_count,
        int order,
        int comparator_code,
        int mode_code,
        unsigned char *mask,
        int elements_per_thread)
    {
        const std::size_t line = static_cast<std::size_t>(blockIdx.x);
        if (line >= line_count)
        {
            return;
        }
        const std::size_t base = line * axis_size;
        for (std::size_t tile_begin = 0;
             tile_begin < axis_size;
             tile_begin += blockDim.x * static_cast<std::size_t>(elements_per_thread))
        {
            for (int item = 0; item < elements_per_thread; ++item)
            {
                const std::size_t axis_index =
                    tile_begin + static_cast<std::size_t>(threadIdx.x) +
                    static_cast<std::size_t>(item) * blockDim.x;
                if (axis_index >= axis_size)
                {
                    continue;
                }

                const std::size_t current = base + axis_index;
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
                    const float plus_value = data[base + static_cast<std::size_t>(plus)];
                    const float minus_value = data[base + static_cast<std::size_t>(minus)];
                    is_extrema = compare_value(center, plus_value, comparator_code) &&
                                 compare_value(center, minus_value, comparator_code);
                }
                mask[current] = is_extrema ? 1 : 0;
            }
        }
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

    __global__ void compact_flagged_indices_kernel(
        const unsigned char *mask,
        std::size_t total,
        int *flat_indices,
        int *hit_count)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= total || mask[index] == 0)
        {
            return;
        }
        const int output_index = atomicAdd(hit_count, 1);
        flat_indices[output_index] = static_cast<int>(index);
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace peak_finding
        {

            namespace
            {
                ZxGpuExtremaResult argrelextrema_impl(
                    const core::RealArrayLike &data,
                    const std::string &comparator,
                    int axis,
                    int order,
                    const std::string &mode,
                    const char *operator_id)
                {
                    namespace detail = cusignal::peak_finding_detail;
                    const std::string normalized_comparator =
                        detail::normalize_comparator(comparator);
                    const std::string normalized_mode = detail::normalize_mode(mode);
                    if (order < 1)
                    {
                        throw std::invalid_argument("order must be >= 1");
                    }

                    const ZxGpuRealArray &device_data = core::as_device_array(data, g_workspace.data_storage);
                    const detail::AxisPlan plan = detail::make_axis_plan(device_data.shape(), axis);
                    const std::size_t total = device_data.size();
                    if (total > static_cast<std::size_t>(std::numeric_limits<int>::max()))
                    {
                        throw std::invalid_argument("argrelextrema input is too large for int index output");
                    }
                    const tile::PolicyDecision tuning = tile::select(
                        tile::make_row_operator_key(
                            operator_id,
                            plan.line_count,
                            plan.axis_size,
                            0,
                            static_cast<std::uint64_t>(plan.axis + 1),
                            static_cast<std::uint64_t>(order)));
                    const tile::ScopedPolicy policy_scope(tuning);
                // The shared DeviceStorage path amortizes allocator overhead
                // for large masks, while the legacy direct buffer remains the
                // lower-overhead route for tiny workloads where cache bookkeeping
                // costs more than the allocation itself.
                    constexpr std::size_t kCachedBufferMinElements = 1U << 17;
                    g_workspace.configure_buffers(
                        tile::optimized_path() && total >= kCachedBufferMinElements);
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

                    ScopedZxGpuEvents events;
                    g_last_kernel_ms = events.measure([&]() {
                    const bool contiguous_last_axis =
                        plan.axis + 1 == device_data.rank() && plan.axis_stride == 1;
                    const bool use_row_tile =
                        tile::optimized_path() &&
                        contiguous_last_axis &&
                        plan.axis_size >= 128 &&
                        plan.line_count <= static_cast<std::size_t>(std::numeric_limits<int>::max());
                    if (use_row_tile)
                    {
                        const int elements_per_thread =
                            tile::row_shape(plan.axis_size, plan.line_count).elements_per_thread;
                        extrema_mask_contiguous_row_tile_kernel<<<
                            static_cast<int>(plan.line_count),
                            kThreadsPerBlock>>>(
                            device_data.data(),
                            plan.axis_size,
                            plan.line_count,
                            order,
                            normalized_comparator == "greater" ? 0 : 1,
                            normalized_mode == "clip" ? 0 : 1,
                            g_workspace.mask_storage.get(),
                            elements_per_thread);
                        check_kernel_launch("extrema_mask_contiguous_row_tile_kernel");
                    }
                    else
                    {
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
                    }

                    g_workspace.flat_hits_storage.resize(total, false);
                    cusignal::core::throw_on_zx_gpu_error(
                        cudaMemset(g_workspace.hit_count_storage.get(), 0, sizeof(int)),
                        "cudaMemset hit_count");
                    compact_flagged_indices_kernel<<<block_count(total), kThreadsPerBlock>>>(
                        g_workspace.mask_storage.get(),
                        total,
                        g_workspace.flat_hits_storage.data(),
                        g_workspace.hit_count_storage.get());
                    check_kernel_launch("compact_flagged_indices_kernel");
                    int hit_count_device = 0;
                    cusignal::core::throw_on_zx_gpu_error(
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
                        cusignal::core::benchmark::note_host_to_device(
                            axis_output_ptrs.size() * sizeof(int *));
                        cusignal::core::throw_on_zx_gpu_error(
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

                    ZxGpuExtremaResult result;
                    result.indices = g_workspace.axis_outputs;
                    return result;
                }
            } // namespace

            ZxGpuExtremaResult argrelextrema(
                const core::RealArrayLike &data,
                const std::string &comparator,
                int axis,
                int order,
                const std::string &mode)
            {
                return argrelextrema_impl(
                    data,
                    comparator,
                    axis,
                    order,
                    mode,
                    "peak_finding/argrelextrema");
            }

            ZxGpuExtremaResult argrelmin(
                const core::RealArrayLike &data,
                int axis,
                int order,
                const std::string &mode)
            {
                return argrelextrema_impl(
                    data,
                    "less",
                    axis,
                    order,
                    mode,
                    "peak_finding/argrelmin");
            }

            ZxGpuExtremaResult argrelmax(
                const core::RealArrayLike &data,
                int axis,
                int order,
                const std::string &mode)
            {
                return argrelextrema_impl(
                    data,
                    "greater",
                    axis,
                    order,
                    mode,
                    "peak_finding/argrelmax");
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
    } // namespace zx_gpu_backend
} // namespace cusignal
