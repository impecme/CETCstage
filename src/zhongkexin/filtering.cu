#include "cusignal/filtering/filtering.hpp"

#include <cuda_runtime.h>
#include <cufft.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstddef>
#include <numeric>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/core/benchmark_input_protocol.hpp"
#include "cusignal/filter_design/filter_design.hpp"
#include "cusignal/windows/windows.hpp"

#include "../common/filtering_detail.hpp"
#include "../common/zx_execution_context.hpp"
#include "../common/zx_tile_policy.hpp"

namespace
{
    namespace core = cusignal::core;
    namespace cpu_filtering = cusignal::cpu::filtering;
    namespace detail = cusignal::filtering_detail;
    namespace tile = cusignal::zx_tile;

    using core::Complex;
    using core::ComplexArray;
    using core::ComplexSignal;
    using core::ZxGpuComplexArray;
    using core::ZxGpuComplexSignal;
    using core::ZxGpuRealArray;
    using core::ZxGpuRealSignal;
    using core::ZxGpuWindowSpec;
    using core::RealArray;
    using core::RealSignal;
    using core::Shape;

    constexpr int kThreadsPerBlock = 256;
    constexpr int kMaxFilterOrder = 256;
    constexpr std::size_t kComplexFirQuadMaxTaps = 193;
    // ZQ500 rejects the shared FIR grid once the row dimension reaches the
    // first square2d level above 512.  Keep the tiled path within the
    // runtime-probed safe range; larger batches use the legacy grid path.
    constexpr std::size_t kMaxSharedFirLines = 512;
    constexpr int kMaxLfilterZiOrder = 512;
    constexpr int kMaxSosSections = 64;
    constexpr int kMaxRank = 8;
    constexpr int kWienerTileSize = 16;
    constexpr std::size_t kMaxWienerTiledWindow = 31;
    constexpr int kChannelizeSharedChannels = 8;
    constexpr std::size_t kChannelizePointMinPoints = 256;
    constexpr int kChannelizePathAuto = -1;
    constexpr int kChannelizePathGeneric = 0;
    constexpr int kChannelizePathPoint = 1;
    constexpr std::size_t kFirfilter2DirectTaps = 31;
    constexpr std::size_t kFirfilter2DirectMinAxisSize = 65536;
    constexpr int kFirfilter2PathAuto = -1;
    constexpr int kFirfilter2PathGeneric = 0;
    constexpr int kFirfilter2PathDirect = 1;
    constexpr int kResamplePathAuto = -1;
    constexpr int kResamplePathGeneric = 0;
    constexpr int kResamplePathFused = 1;
    constexpr int kResamplePathWindowedPack = 2;
    constexpr int kResampleWindowNone = 0;
    constexpr int kResampleWindowDirect = 1;
    constexpr int kResampleWindowFftshift = 2;
    constexpr std::size_t kResampleFusedInputSize = 1048576;
    constexpr int kResampleFusedOutputSize = 1572864;
    constexpr float kPi = 3.141592653589793238462643383279502884;

    thread_local float g_last_kernel_ms = 0.0;
    thread_local int g_channelize_path_override = kChannelizePathAuto;
    thread_local int g_firfilter2_path_override = kFirfilter2PathAuto;
    thread_local int g_last_firfilter2_path = kFirfilter2PathGeneric;
    thread_local int g_resample_path_override = kResamplePathAuto;
    thread_local int g_last_resample_path = kResamplePathGeneric;

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
    using DeviceBuffer = cusignal::zx_execution::ReusableDeviceBuffer<T>;

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
                throw_on_zx_gpu_error(cudaEventCreate(&start), "cudaEventCreate(start)");
                throw_on_zx_gpu_error(cudaEventCreate(&stop), "cudaEventCreate(stop)");
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
            throw_on_zx_gpu_error(
                cudaEventRecord(g_timing_events.start), "cudaEventRecord(start)");
            callable();
            throw_on_zx_gpu_error(
                cudaEventRecord(g_timing_events.stop), "cudaEventRecord(stop)");
            throw_on_zx_gpu_error(
                cudaEventSynchronize(g_timing_events.stop), "cudaEventSynchronize(stop)");
            float elapsed_ms = 0.0f;
            throw_on_zx_gpu_error(
                cudaEventElapsedTime(
                    &elapsed_ms, g_timing_events.start, g_timing_events.stop),
                "cudaEventElapsedTime");
            return elapsed_ms;
        }
    };

    struct LineBasesCache
    {
        Shape shape;
        int axis = 0;
        std::vector<std::size_t> bases;
        bool valid = false;
    };

    struct FilteringWorkspace
    {
        ZxGpuRealSignal real_signal_a;
        ZxGpuRealSignal real_signal_b;
        ZxGpuRealSignal real_signal_c;
        ZxGpuRealSignal real_signal_d;
        ZxGpuRealSignal real_signal_e;
        ZxGpuComplexSignal complex_signal_a;
        ZxGpuComplexSignal complex_signal_b;
        ZxGpuComplexSignal complex_signal_c;
        ZxGpuRealArray real_array_a;
        ZxGpuRealArray real_array_b;
        ZxGpuRealArray real_array_c;
        ZxGpuRealArray real_array_d;
        ZxGpuRealArray real_array_e;
        ZxGpuComplexArray complex_array_a;
        ZxGpuComplexArray complex_array_b;
        DeviceBuffer<std::size_t> size_buffer_a;
        DeviceBuffer<std::size_t> size_buffer_b;
        DeviceBuffer<std::size_t> size_buffer_c;
        DeviceBuffer<std::size_t> size_buffer_d;
        DeviceBuffer<std::size_t> wiener_shape_buffer;
        DeviceBuffer<std::size_t> wiener_stride_buffer;
        DeviceBuffer<std::size_t> wiener_mysize_buffer;
        DeviceBuffer<int> int_buffer_a;
        DeviceBuffer<int> int_buffer_b;
        DeviceBuffer<float> scalar_buffer_a;
        DeviceBuffer<float> scalar_buffer_b;
        DeviceBuffer<float> matrix_buffer;
        DeviceBuffer<float> reduction_buffer_a;
        DeviceBuffer<float> reduction_buffer_b;
        core::Shape cached_detrend_shape;
        std::vector<std::size_t> cached_detrend_line_bases;
        core::IndexVector cached_detrend_breaks;
        std::size_t cached_detrend_axis = 0;
        bool detrend_line_bases_valid = false;
        bool detrend_breaks_valid = false;
        RealSignal cached_channelize_taps;
        std::size_t cached_channelize_padded_size = 0;
        int cached_channelize_n_chans = 0;
        bool channelize_taps_valid = false;
        LineBasesCache line_bases_cache_a;
        LineBasesCache line_bases_cache_b;
        LineBasesCache line_bases_cache_c;
        LineBasesCache line_bases_cache_d;
        ZxGpuRealSignal unit_signal;
        bool unit_signal_valid = false;
        ZxGpuRealSignal decimate_taps;
        int cached_decimate_q = 0;
        int cached_decimate_order = -1;
        bool decimate_taps_valid = false;
        core::Shape cached_wiener_shape;
        core::Shape cached_wiener_mysize;
        bool wiener_metadata_valid = false;
        ZxGpuRealSignal resample_window;
        std::string resample_window_key;
        bool resample_window_valid = false;
        ZxGpuRealSignal resample_poly_filter;
        std::string resample_poly_filter_key;
        std::size_t resample_poly_n_pre_remove = 0;
        bool resample_poly_filter_valid = false;
        cufftHandle plan1d_a = 0;
        int plan1d_a_size = 0;
        cufftHandle plan1d_b = 0;
        int plan1d_b_size = 0;
        cufftHandle plan2d = 0;
        int plan2d_rows = 0;
        int plan2d_cols = 0;

        ~FilteringWorkspace()
        {
            if (plan1d_a != 0)
            {
                cufftDestroy(plan1d_a);
            }
            if (plan1d_b != 0)
            {
                cufftDestroy(plan1d_b);
            }
            if (plan2d != 0)
            {
                cufftDestroy(plan2d);
            }
        }

        void ensure_plan1d_a(int size)
        {
            if (plan1d_a != 0 && plan1d_a_size == size)
            {
                return;
            }
            if (plan1d_a != 0)
            {
                throw_on_cufft_error(cufftDestroy(plan1d_a), "cufftDestroy(plan1d_a)");
            }
            throw_on_cufft_error(cufftPlan1d(&plan1d_a, size, CUFFT_C2C, 1), "cufftPlan1d(plan1d_a)");
            plan1d_a_size = size;
        }

        void ensure_plan1d_b(int size)
        {
            if (plan1d_b != 0 && plan1d_b_size == size)
            {
                return;
            }
            if (plan1d_b != 0)
            {
                throw_on_cufft_error(cufftDestroy(plan1d_b), "cufftDestroy(plan1d_b)");
            }
            throw_on_cufft_error(cufftPlan1d(&plan1d_b, size, CUFFT_C2C, 1), "cufftPlan1d(plan1d_b)");
            plan1d_b_size = size;
        }

        void ensure_plan2d(int rows, int cols)
        {
            if (plan2d != 0 && plan2d_rows == rows && plan2d_cols == cols)
            {
                return;
            }
            if (plan2d != 0)
            {
                throw_on_cufft_error(cufftDestroy(plan2d), "cufftDestroy(plan2d)");
            }
            throw_on_cufft_error(cufftPlan2d(&plan2d, rows, cols, CUFFT_C2C), "cufftPlan2d");
            plan2d_rows = rows;
            plan2d_cols = cols;
        }
    };

    thread_local FilteringWorkspace g_workspace;

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    __device__ void kahan_add(float value, float &sum, float &compensation)
    {
        const float corrected = value - compensation;
        const float next = sum + corrected;
        compensation = (next - sum) - corrected;
        sum = next;
    }

    const Shape &shape_of(const core::RealArrayLike &tensor)
    {
        if (const auto *host = std::get_if<RealArray>(&tensor))
        {
            return host->shape;
        }
        return std::get<ZxGpuRealArray>(tensor).shape();
    }

    std::size_t signal_size(const core::RealSignalLike &signal)
    {
        if (const auto *host = std::get_if<RealSignal>(&signal))
        {
            return host->size();
        }
        return std::get<ZxGpuRealSignal>(signal).size();
    }

    int pad_mode_from_string(const std::string &padtype)
    {
        if (padtype == "none")
        {
            return 0;
        }
        if (padtype == "odd")
        {
            return 1;
        }
        if (padtype == "even")
        {
            return 2;
        }
        return 3;
    }

    std::vector<std::size_t> compute_line_bases(const Shape &shape, int axis)
    {
        const detail::AxisPlan plan = detail::make_axis_plan(shape, axis);
        std::vector<std::size_t> bases(plan.line_count, 0);
        for (std::size_t line = 0; line < plan.line_count; ++line)
        {
            bases[line] = detail::line_base_offset(plan, line);
        }
        return bases;
    }

    void upload_size_vector(
        const std::vector<std::size_t> &values,
        DeviceBuffer<std::size_t> &buffer,
        const char *what)
    {
        buffer.copy_from_host(values.data(), values.size(), what);
    }

    const std::size_t *upload_line_bases_cached(
        const Shape &shape,
        int axis,
        DeviceBuffer<std::size_t> &buffer,
        LineBasesCache &cache,
        const char *what)
    {
        const int normalized_axis = static_cast<int>(core::normalize_axis(axis, shape.size()));
        if (!cache.valid || cache.shape != shape || cache.axis != normalized_axis)
        {
            cache.shape = shape;
            cache.axis = normalized_axis;
            cache.bases = compute_line_bases(shape, normalized_axis);
            upload_size_vector(cache.bases, buffer, what);
            cache.valid = true;
        }
        return buffer.get();
    }

    const ZxGpuRealSignal *explicit_window_signal(const ZxGpuWindowSpec &window, ZxGpuRealSignal &storage)
    {
        if (const auto *host = std::get_if<RealSignal>(&window))
        {
            storage.copy_from(*host);
            return &storage;
        }
        if (const auto *device = std::get_if<ZxGpuRealSignal>(&window))
        {
            return device;
        }
        return nullptr;
    }

    const ZxGpuRealSignal &make_unit_signal()
    {
        if (!g_workspace.unit_signal_valid)
        {
            g_workspace.unit_signal.copy_from(RealSignal{1.0});
            g_workspace.unit_signal_valid = true;
        }
        return g_workspace.unit_signal;
    }

    std::pair<float, float> first_two_time_values(const core::RealSignalLike &signal)
    {
        if (const auto *host = std::get_if<RealSignal>(&signal))
        {
            return {(*host)[0], (*host)[1]};
        }
        std::array<float, 2> values{0.0, 0.0};
        throw_on_zx_gpu_error(
            cudaMemcpy(values.data(), std::get<ZxGpuRealSignal>(signal).data(), 2 * sizeof(float), cudaMemcpyDeviceToHost),
            "cudaMemcpy D2H(time_preview)");
        return {values[0], values[1]};
    }

    RealArray to_host_array(const core::RealArrayLike &tensor)
    {
        if (const auto *host = std::get_if<RealArray>(&tensor))
        {
            return *host;
        }
        return std::get<ZxGpuRealArray>(tensor).get();
    }

    RealSignal to_host_signal(const core::RealSignalLike &signal)
    {
        if (const auto *host = std::get_if<RealSignal>(&signal))
        {
            return *host;
        }
        return std::get<ZxGpuRealSignal>(signal).get();
    }

    core::WindowSpec to_host_window_spec(const core::ZxGpuWindowSpec &window)
    {
        if (const auto *value = std::get_if<std::string>(&window))
        {
            return *value;
        }
        if (const auto *value = std::get_if<float>(&window))
        {
            return *value;
        }
        if (const auto *value = std::get_if<core::NamedFloatParameter>(&window))
        {
            return *value;
        }
        if (const auto *value = std::get_if<core::NamedFloatPairParameter>(&window))
        {
            return *value;
        }
        if (const auto *value = std::get_if<core::NamedTaylorParameter>(&window))
        {
            return *value;
        }
        if (const auto *value = std::get_if<RealSignal>(&window))
        {
            return *value;
        }
        return std::get<ZxGpuRealSignal>(window).get();
    }

    void validate_zx_gpu_window_spec(const core::ZxGpuWindowSpec &window)
    {
        if (const auto *values = std::get_if<RealSignal>(&window))
        {
            if (values->empty())
            {
                throw std::invalid_argument("window array must not be empty");
            }
        }
        else if (const auto *values = std::get_if<ZxGpuRealSignal>(&window))
        {
            if (values->empty())
            {
                throw std::invalid_argument("window array must not be empty");
            }
        }
    }

    bool build_zx_gpu_window_cache_key(
        const ZxGpuWindowSpec &window,
        int size,
        std::string &key)
    {
        key = "size=" + std::to_string(size) + ";";
        if (const auto *name = std::get_if<std::string>(&window))
        {
            if (name->empty())
            {
                return false;
            }
            key += "name=" + *name;
            return true;
        }
        if (const auto *value = std::get_if<float>(&window))
        {
            key += "scalar=" + std::to_string(*value);
            return true;
        }
        if (const auto *value = std::get_if<core::NamedFloatParameter>(&window))
        {
            key += "named1=" + value->name + ":" + std::to_string(value->value);
            return true;
        }
        if (const auto *value = std::get_if<core::NamedFloatPairParameter>(&window))
        {
            key += "named2=" + value->name + ":" +
                   std::to_string(value->first) + ":" +
                   std::to_string(value->second);
            return true;
        }
        if (const auto *value = std::get_if<core::NamedTaylorParameter>(&window))
        {
            key += "taylor=" + value->name + ":" +
                   std::to_string(value->nbar) + ":" +
                   std::to_string(value->sll) + ":" +
                   (value->norm ? "1" : "0");
            return true;
        }
        return false;
    }

    __device__ inline float2 make_complex(float real, float imag)
    {
        return float2{real, imag};
    }

    __device__ inline float2 complex_add(float2 lhs, float2 rhs)
    {
        return make_complex(lhs.x + rhs.x, lhs.y + rhs.y);
    }

    __device__ inline float2 complex_mul(float2 lhs, float2 rhs)
    {
        return make_complex(lhs.x * rhs.x - lhs.y * rhs.y, lhs.x * rhs.y + lhs.y * rhs.x);
    }

    __device__ inline float rn_madd(float acc, float lhs, float rhs)
    {
        return __fadd_rn(acc, __fmul_rn(lhs, rhs));
    }

    __global__ void gather_real_line_to_complex_kernel(
        const float *input,
        const std::size_t *line_bases,
        std::size_t axis_stride,
        std::size_t line_index,
        std::size_t input_size,
        std::size_t target_size,
        cufftComplex *output)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= target_size)
        {
            return;
        }
        const std::size_t base = line_bases[line_index];
        if (index < input_size)
        {
            output[index] = make_complex(input[base + index * axis_stride], 0.0);
        }
        else
        {
            output[index] = make_complex(0.0, 0.0);
        }
    }

    __global__ void gather_spectrum_line_kernel(
        const float *input,
        const std::size_t *line_bases,
        std::size_t axis_stride,
        std::size_t line_index,
        std::size_t axis_size,
        cufftComplex *output)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < axis_size)
        {
            const std::size_t base = line_bases[line_index];
            output[index] = make_complex(input[base + index * axis_stride], 0.0);
        }
    }

    __global__ void scatter_real_line_from_complex_kernel(
        const cufftComplex *input,
        float *output,
        const std::size_t *line_bases,
        std::size_t axis_stride,
        std::size_t line_index,
        std::size_t size,
        float scale)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            const std::size_t base = line_bases[line_index];
            output[base + index * axis_stride] = input[index].x * scale;
        }
    }

    __global__ void scatter_complex_line_kernel(
        const cufftComplex *input,
        float2 *output,
        const std::size_t *line_bases,
        std::size_t axis_stride,
        std::size_t line_index,
        std::size_t size,
        float scale)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            const std::size_t base = line_bases[line_index];
            output[base + index * axis_stride] =
                make_complex(input[index].x * scale, input[index].y * scale);
        }
    }

    __global__ void apply_hilbert_mask_kernel(cufftComplex *spectrum, int n)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index >= n)
        {
            return;
        }
        if (n % 2 == 0)
        {
            if (index == 0 || index == n / 2)
            {
                return;
            }
            if (index < n / 2)
            {
                spectrum[index].x *= 2.0;
                spectrum[index].y *= 2.0;
            }
            else
            {
                spectrum[index] = make_complex(0.0, 0.0);
            }
            return;
        }

        if (index == 0)
        {
            return;
        }
        if (index < (n + 1) / 2)
        {
            spectrum[index].x *= 2.0;
            spectrum[index].y *= 2.0;
        }
        else
        {
            spectrum[index] = make_complex(0.0, 0.0);
        }
    }

    __global__ void apply_window_direct_kernel(
        cufftComplex *spectrum,
        const float *window,
        int size)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index < size)
        {
            spectrum[index].x *= window[index];
            spectrum[index].y *= window[index];
        }
    }

    __global__ void apply_window_fftshift_kernel(
        cufftComplex *spectrum,
        const float *window,
        int size)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index < size)
        {
            const int half = size / 2;
            const float value = window[(index + half) % size];
            spectrum[index].x *= value;
            spectrum[index].y *= value;
        }
    }

    __global__ void zero_complex_kernel(cufftComplex *values, int size)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index < size)
        {
            values[index] = make_complex(0.0, 0.0);
        }
    }

    __global__ void resample_copy_low_kernel(
        cufftComplex *output,
        const cufftComplex *input,
        int m2)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index < m2)
        {
            output[index] = input[index];
        }
    }

    __global__ void resample_copy_high_kernel(
        cufftComplex *output,
        int output_size,
        const cufftComplex *input,
        int input_size,
        int count)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index < count)
        {
            output[output_size - count + index] = input[input_size - count + index];
        }
    }

    __global__ void resample_adjust_nyquist_kernel(
        cufftComplex *output,
        const cufftComplex *input,
        int input_size,
        int output_size,
        int m)
    {
        if (blockIdx.x != 0 || threadIdx.x != 0 || (m % 2) != 0)
        {
            return;
        }
        if (output_size < input_size)
        {
            const int index = output_size - m / 2;
            output[index].x += input[input_size - m / 2].x;
            output[index].y += input[input_size - m / 2].y;
        }
        else if (input_size < output_size)
        {
            const int index = m / 2;
            output[index].x *= 0.5;
            output[index].y *= 0.5;
            output[output_size - m / 2] = output[index];
        }
    }

    __device__ cufftComplex load_resample_spectrum_value(
        const cufftComplex *input,
        int input_size,
        int input_index,
        const float *window,
        int window_mode)
    {
        cufftComplex value = input[input_index];
        if (window_mode != kResampleWindowNone)
        {
            const int window_index =
                window_mode == kResampleWindowFftshift
                    ? (input_index + input_size / 2) % input_size
                    : input_index;
            value.x = __fmul_rn(value.x, window[window_index]);
            value.y = __fmul_rn(value.y, window[window_index]);
        }
        return value;
    }

    __global__ void resample_pack_spectrum_kernel(
        cufftComplex *output,
        int output_size,
        const cufftComplex *input,
        int input_size,
        const float *window,
        int window_mode)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index >= output_size)
        {
            return;
        }

        const int m = input_size < output_size ? input_size : output_size;
        const int m2 = m / 2 + 1;
        const int high_count = m - m2;
        cufftComplex value = make_complex(0.0, 0.0);
        if (index < m2)
        {
            value = load_resample_spectrum_value(
                input, input_size, index, window, window_mode);
        }
        else if (index >= output_size - high_count)
        {
            value = load_resample_spectrum_value(
                input,
                input_size,
                input_size - output_size + index,
                window,
                window_mode);
        }

        if ((m % 2) == 0 && output_size < input_size && index == output_size - m / 2)
        {
            const cufftComplex other = load_resample_spectrum_value(
                input,
                input_size,
                input_size - m / 2,
                window,
                window_mode);
            value.x = __fadd_rn(value.x, other.x);
            value.y = __fadd_rn(value.y, other.y);
        }
        else if ((m % 2) == 0 && input_size < output_size &&
                 (index == m / 2 || index == output_size - m / 2))
        {
            value = load_resample_spectrum_value(
                input, input_size, m / 2, window, window_mode);
            value.x = __fmul_rn(value.x, 0.5f);
            value.y = __fmul_rn(value.y, 0.5f);
        }
        output[index] = value;
    }

    __global__ void scale_real_signal_kernel(float *values, std::size_t size, float scale)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            values[index] *= scale;
        }
    }

    __global__ void generate_time_axis_kernel(float *values, std::size_t size, float start, float step)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            values[index] = start + step * static_cast<float>(index);
        }
    }

    __global__ void freq_shift_kernel(const float2 *input, float2 *output, std::size_t size, float freq, float fs)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float angle = 2.0 * kPi * freq * (static_cast<float>(index) / fs);
        const float2 phase = make_complex(cos(angle), sin(angle));
        output[index] = complex_mul(input[index], phase);
    }

    __global__ void wiener_local_stats_kernel(
        const float *input,
        std::size_t total,
        const std::size_t *shape,
        const std::size_t *strides,
        const std::size_t *mysize,
        std::size_t rank,
        float window_volume,
        float *local_mean,
        float *local_variance)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (flat >= total)
        {
            return;
        }

        std::size_t center[kMaxRank];
        std::size_t start[kMaxRank];
        std::size_t stop[kMaxRank];
        std::size_t coords[kMaxRank];

        std::size_t remainder = flat;
        for (std::size_t dim = 0; dim < rank; ++dim)
        {
            center[dim] = remainder / strides[dim];
            remainder %= strides[dim];
            const std::size_t half = mysize[dim] / 2;
            start[dim] = center[dim] > half ? center[dim] - half : 0;
            const std::size_t upper = center[dim] + half;
            stop[dim] = upper < shape[dim] ? upper : (shape[dim] - 1);
            coords[dim] = start[dim];
        }

        float sum = 0.0;
        float sum_sq = 0.0;
        bool done = false;
        while (!done)
        {
            std::size_t offset = 0;
            for (std::size_t dim = 0; dim < rank; ++dim)
            {
                offset += coords[dim] * strides[dim];
            }
            const float value = input[offset];
            sum += value;
            sum_sq += value * value;

            done = true;
            for (int dim_signed = static_cast<int>(rank) - 1; dim_signed >= 0; --dim_signed)
            {
                const std::size_t dim = static_cast<std::size_t>(dim_signed);
                if (coords[dim] < stop[dim])
                {
                    ++coords[dim];
                    for (std::size_t reset = dim + 1; reset < rank; ++reset)
                    {
                        coords[reset] = start[reset];
                    }
                    done = false;
                    break;
                }
            }
        }

        const float mean = sum / window_volume;
        local_mean[flat] = mean;
        local_variance[flat] = sum_sq / window_volume - mean * mean;
    }

    __global__ void wiener_local_stats_2d_tiled_kernel(
        const float *input,
        std::size_t rows,
        std::size_t cols,
        std::size_t window_rows,
        std::size_t window_cols,
        float window_volume,
        float *local_mean,
        float *local_variance)
    {
        extern __shared__ float tile[];
        const std::size_t half_rows = window_rows / 2;
        const std::size_t half_cols = window_cols / 2;
        const std::size_t tile_rows = static_cast<std::size_t>(blockDim.y) + 2 * half_rows;
        const std::size_t tile_cols = static_cast<std::size_t>(blockDim.x) + 2 * half_cols;
        const std::size_t tile_size = tile_rows * tile_cols;
        const std::size_t thread_index =
            static_cast<std::size_t>(threadIdx.y) * blockDim.x + threadIdx.x;
        const std::size_t thread_count = static_cast<std::size_t>(blockDim.x) * blockDim.y;
        const std::size_t block_row = static_cast<std::size_t>(blockIdx.y) * blockDim.y;
        const std::size_t block_col = static_cast<std::size_t>(blockIdx.x) * blockDim.x;

        for (std::size_t index = thread_index; index < tile_size; index += thread_count)
        {
            const std::size_t tile_row = index / tile_cols;
            const std::size_t tile_col = index - tile_row * tile_cols;
            const long long input_row = static_cast<long long>(block_row + tile_row) -
                                        static_cast<long long>(half_rows);
            const long long input_col = static_cast<long long>(block_col + tile_col) -
                                        static_cast<long long>(half_cols);
            float value = 0.0f;
            if (input_row >= 0 && input_col >= 0 &&
                static_cast<std::size_t>(input_row) < rows &&
                static_cast<std::size_t>(input_col) < cols)
            {
                value = input[static_cast<std::size_t>(input_row) * cols +
                              static_cast<std::size_t>(input_col)];
            }
            tile[index] = value;
        }
        __syncthreads();

        const std::size_t output_row = block_row + threadIdx.y;
        const std::size_t output_col = block_col + threadIdx.x;
        if (output_row >= rows || output_col >= cols)
        {
            return;
        }

        float sum = 0.0f;
        float sum_sq = 0.0f;
        for (std::size_t row = 0; row <= 2 * half_rows; ++row)
        {
            const std::size_t tile_offset =
                (static_cast<std::size_t>(threadIdx.y) + row) * tile_cols + threadIdx.x;
            for (std::size_t col = 0; col <= 2 * half_cols; ++col)
            {
                const float value = tile[tile_offset + col];
                sum += value;
                sum_sq += value * value;
            }
        }

        const std::size_t flat = output_row * cols + output_col;
        const float mean = sum / window_volume;
        local_mean[flat] = mean;
        local_variance[flat] = sum_sq / window_volume - mean * mean;
    }

    __global__ void sum_values_block_kernel(const float *input, std::size_t size, float *block_sums)
    {
        __shared__ float cache[kThreadsPerBlock];
        const std::size_t tid = static_cast<std::size_t>(threadIdx.x);
        float local = 0.0f;
        float compensation = 0.0f;
        for (std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + tid;
             index < size;
             index += static_cast<std::size_t>(gridDim.x) * blockDim.x)
        {
            const float corrected = input[index] - compensation;
            const float next = local + corrected;
            compensation = (next - local) - corrected;
            local = next;
        }
        cache[tid] = local;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                cache[threadIdx.x] += cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x == 0)
        {
            block_sums[blockIdx.x] = cache[0];
        }
    }

    __global__ void sum_values_finalize_kernel(const float *block_sums, std::size_t block_count, float *sum)
    {
        __shared__ float cache[kThreadsPerBlock];
        const std::size_t tid = static_cast<std::size_t>(threadIdx.x);
        float local = 0.0f;
        float compensation = 0.0f;
        for (std::size_t index = tid; index < block_count; index += blockDim.x)
        {
            const float corrected = block_sums[index] - compensation;
            const float next = local + corrected;
            compensation = (next - local) - corrected;
            local = next;
        }
        cache[tid] = local;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                cache[threadIdx.x] += cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x == 0)
        {
            *sum = cache[0];
        }
    }

    __global__ void wiener_apply_kernel(
        const float *input,
        const float *local_mean,
        const float *local_variance,
        float *output,
        std::size_t size,
        float noise)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float mean = local_mean[index];
        const float variance = local_variance[index];
        if (variance < noise || variance <= 0.0)
        {
            output[index] = mean;
        }
        else
        {
            output[index] = mean + (1.0 - noise / variance) * (input[index] - mean);
        }
    }

    __global__ void wiener_apply_auto_noise_kernel(
        const float *input,
        const float *local_mean,
        const float *local_variance,
        const float *noise_sum,
        float *output,
        std::size_t size)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float noise = noise_sum[0] / static_cast<float>(size);
        const float mean = local_mean[index];
        const float variance = local_variance[index];
        if (variance < noise || variance <= 0.0)
        {
            output[index] = mean;
        }
        else
        {
            output[index] = mean + (1.0 - noise / variance) * (input[index] - mean);
        }
    }

    __global__ void detrend_constant_kernel(
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output)
    {
        const std::size_t line =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (line >= line_count)
        {
            return;
        }
        const std::size_t base = line_bases[line];
        float mean = 0.0;
        for (std::size_t index = 0; index < axis_size; ++index)
        {
            mean += input[base + index * axis_stride];
        }
        mean /= static_cast<float>(axis_size);
        for (std::size_t index = 0; index < axis_size; ++index)
        {
            output[base + index * axis_stride] = input[base + index * axis_stride] - mean;
        }
    }

    __global__ void detrend_linear_kernel(
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        const int *breaks,
        int break_count,
        float *output)
    {
        const std::size_t line =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (line >= line_count)
        {
            return;
        }
        const std::size_t base = line_bases[line];
        for (std::size_t index = 0; index < axis_size; ++index)
        {
            output[base + index * axis_stride] = input[base + index * axis_stride];
        }

        for (int segment = 0; segment + 1 < break_count; ++segment)
        {
            const int begin = breaks[segment];
            const int end = breaks[segment + 1];
            const int count = end - begin;
            if (count <= 0)
            {
                continue;
            }

            float sum_t = 0.0;
            float sum_t2 = 0.0;
            float sum_y = 0.0;
            float sum_ty = 0.0;
            for (int index = 0; index < count; ++index)
            {
                const float t = static_cast<float>(index + 1) / static_cast<float>(count);
                const float y = input[base + static_cast<std::size_t>(begin + index) * axis_stride];
                sum_t += t;
                sum_t2 += t * t;
                sum_y += y;
                sum_ty += t * y;
            }
            const float det = static_cast<float>(count) * sum_t2 - sum_t * sum_t;
            const float slope = (static_cast<float>(count) * sum_ty - sum_t * sum_y) / det;
            const float intercept = (sum_y - slope * sum_t) / static_cast<float>(count);
            for (int index = 0; index < count; ++index)
            {
                const float t = static_cast<float>(index + 1) / static_cast<float>(count);
                output[base + static_cast<std::size_t>(begin + index) * axis_stride] -=
                    intercept + slope * t;
            }
        }
    }

    __global__ void detrend_constant_parallel_kernel(
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output)
    {
        const std::size_t line = static_cast<std::size_t>(blockIdx.x);
        if (line >= line_count)
        {
            return;
        }

        __shared__ float sums[kThreadsPerBlock];
        const int tid = threadIdx.x;
        const std::size_t base = line_bases[line];
        float local = 0.0f;
        for (std::size_t index = static_cast<std::size_t>(tid); index < axis_size; index += blockDim.x)
        {
            local += input[base + index * axis_stride];
        }
        sums[tid] = local;
        __syncthreads();

        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                sums[tid] += sums[tid + stride];
            }
            __syncthreads();
        }
        const float mean = sums[0] / static_cast<float>(axis_size);

        for (std::size_t index = static_cast<std::size_t>(tid); index < axis_size; index += blockDim.x)
        {
            const std::size_t offset = base + index * axis_stride;
            output[offset] = input[offset] - mean;
        }
    }

    __global__ void detrend_linear_parallel_kernel(
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_stride,
        const int *breaks,
        int break_count,
        float *output)
    {
        const int segment_count = break_count - 1;
        if (segment_count <= 0)
        {
            return;
        }

        const std::size_t task = static_cast<std::size_t>(blockIdx.x);
        const std::size_t line = task / static_cast<std::size_t>(segment_count);
        const int segment = static_cast<int>(task % static_cast<std::size_t>(segment_count));
        if (line >= line_count)
        {
            return;
        }

        const int begin = breaks[segment];
        const int end = breaks[segment + 1];
        const int count = end - begin;
        if (count <= 0)
        {
            return;
        }

        __shared__ float sum_y[kThreadsPerBlock];
        __shared__ float sum_ty[kThreadsPerBlock];
        __shared__ float sum_t[kThreadsPerBlock];
        __shared__ float sum_t2[kThreadsPerBlock];
        const int tid = threadIdx.x;
        const std::size_t base = line_bases[line];
        float local_y = 0.0f;
        float local_ty = 0.0f;
        float local_t = 0.0f;
        float local_t2 = 0.0f;
        float local_y_c = 0.0f;
        float local_ty_c = 0.0f;
        float local_t_c = 0.0f;
        float local_t2_c = 0.0f;
        for (int index = tid; index < count; index += blockDim.x)
        {
            const float t = static_cast<float>(index + 1) / static_cast<float>(count);
            const float y = input[base + static_cast<std::size_t>(begin + index) * axis_stride];
            kahan_add(y, local_y, local_y_c);
            kahan_add(t * y, local_ty, local_ty_c);
            kahan_add(t, local_t, local_t_c);
            kahan_add(t * t, local_t2, local_t2_c);
        }
        sum_y[tid] = local_y;
        sum_ty[tid] = local_ty;
        sum_t[tid] = local_t;
        sum_t2[tid] = local_t2;
        __syncthreads();

        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                sum_y[tid] += sum_y[tid + stride];
                sum_ty[tid] += sum_ty[tid + stride];
                sum_t[tid] += sum_t[tid + stride];
                sum_t2[tid] += sum_t2[tid + stride];
            }
            __syncthreads();
        }

        const float n = static_cast<float>(count);
        const float det = n * sum_t2[0] - sum_t[0] * sum_t[0];
        const float slope = (n * sum_ty[0] - sum_t[0] * sum_y[0]) / det;
        const float intercept = (sum_y[0] - slope * sum_t[0]) / n;

        for (int index = tid; index < count; index += blockDim.x)
        {
            const float t = static_cast<float>(index + 1) / n;
            const std::size_t offset = base + static_cast<std::size_t>(begin + index) * axis_stride;
            output[offset] = input[offset] - (intercept + slope * t);
        }
    }

    __global__ void detrend_constant_partials_kernel(
        const float *input,
        std::size_t axis_size,
        float *partial_sum_y)
    {
        __shared__ float sum_y[kThreadsPerBlock];
        const int tid = threadIdx.x;
        float local_y = 0.0f;
        float local_y_c = 0.0f;
        for (std::size_t index =
                 static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(tid);
             index < axis_size;
             index += static_cast<std::size_t>(gridDim.x) * blockDim.x)
        {
            kahan_add(input[index], local_y, local_y_c);
        }
        sum_y[tid] = local_y;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                sum_y[tid] += sum_y[tid + stride];
            }
            __syncthreads();
        }
        if (tid == 0)
        {
            partial_sum_y[blockIdx.x] = sum_y[0];
        }
    }

    __global__ void detrend_constant_mean_kernel(
        const float *partial_sum_y,
        int partial_count,
        std::size_t axis_size,
        float *coefficients)
    {
        __shared__ float sum_y[kThreadsPerBlock];
        const int tid = threadIdx.x;
        float local_y = 0.0f;
        float local_y_c = 0.0f;
        for (int index = tid; index < partial_count; index += blockDim.x)
        {
            kahan_add(partial_sum_y[index], local_y, local_y_c);
        }
        sum_y[tid] = local_y;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                sum_y[tid] += sum_y[tid + stride];
            }
            __syncthreads();
        }
        if (tid == 0)
        {
            coefficients[0] = sum_y[0] / static_cast<float>(axis_size);
        }
    }

    __global__ void detrend_constant_apply_kernel(
        const float *input,
        std::size_t axis_size,
        const float *coefficients,
        float *output)
    {
        const float mean = coefficients[0];
        for (std::size_t index =
                 static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(threadIdx.x);
             index < axis_size;
             index += static_cast<std::size_t>(gridDim.x) * blockDim.x)
        {
            output[index] = input[index] - mean;
        }
    }

    __global__ void detrend_linear_partials_kernel(
        const float *input,
        std::size_t axis_size,
        float *partial_sum_y,
        float *partial_sum_ty)
    {
        __shared__ float sum_y[kThreadsPerBlock];
        __shared__ float sum_ty[kThreadsPerBlock];
        const int tid = threadIdx.x;
        const float n = static_cast<float>(axis_size);
        float local_y = 0.0f;
        float local_ty = 0.0f;
        float local_y_c = 0.0f;
        float local_ty_c = 0.0f;
        for (std::size_t index =
                 static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(tid);
             index < axis_size;
             index += static_cast<std::size_t>(gridDim.x) * blockDim.x)
        {
            const float t = static_cast<float>(index + 1) / n;
            const float y = input[index];
            kahan_add(y, local_y, local_y_c);
            kahan_add(t * y, local_ty, local_ty_c);
        }
        sum_y[tid] = local_y;
        sum_ty[tid] = local_ty;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                sum_y[tid] += sum_y[tid + stride];
                sum_ty[tid] += sum_ty[tid + stride];
            }
            __syncthreads();
        }
        if (tid == 0)
        {
            partial_sum_y[blockIdx.x] = sum_y[0];
            partial_sum_ty[blockIdx.x] = sum_ty[0];
        }
    }

    __global__ void detrend_linear_coefficients_kernel(
        const float *partial_sum_y,
        const float *partial_sum_ty,
        int partial_count,
        std::size_t axis_size,
        float *coefficients)
    {
        __shared__ float sum_y[kThreadsPerBlock];
        __shared__ float sum_ty[kThreadsPerBlock];
        const int tid = threadIdx.x;
        float local_y = 0.0f;
        float local_ty = 0.0f;
        float local_y_c = 0.0f;
        float local_ty_c = 0.0f;
        for (int index = tid; index < partial_count; index += blockDim.x)
        {
            kahan_add(partial_sum_y[index], local_y, local_y_c);
            kahan_add(partial_sum_ty[index], local_ty, local_ty_c);
        }
        sum_y[tid] = local_y;
        sum_ty[tid] = local_ty;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (tid < stride)
            {
                sum_y[tid] += sum_y[tid + stride];
                sum_ty[tid] += sum_ty[tid + stride];
            }
            __syncthreads();
        }
        if (tid == 0)
        {
            const float n = static_cast<float>(axis_size);
            const float sum_t = (n + 1.0f) * 0.5f;
            const float sum_t2 = ((n + 1.0f) * (2.0f * n + 1.0f)) / (6.0f * n);
            const float det = n * sum_t2 - sum_t * sum_t;
            const float slope = (n * sum_ty[0] - sum_t * sum_y[0]) / det;
            const float intercept = (sum_y[0] - slope * sum_t) / n;
            coefficients[0] = slope;
            coefficients[1] = intercept;
        }
    }

    __global__ void detrend_linear_apply_kernel(
        const float *input,
        std::size_t axis_size,
        const float *coefficients,
        float *output)
    {
        const float slope = coefficients[0];
        const float intercept = coefficients[1];
        const float n = static_cast<float>(axis_size);
        for (std::size_t index =
                 static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(threadIdx.x);
             index < axis_size;
             index += static_cast<std::size_t>(gridDim.x) * blockDim.x)
        {
            const float t = static_cast<float>(index + 1) / n;
            output[index] = input[index] - (intercept + slope * t);
        }
    }

    __global__ void lfilter_line_kernel(
        const float *b,
        std::size_t b_size,
        const float *a,
        std::size_t a_size,
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output,
        const float *zi,
        const std::size_t *zi_bases,
        std::size_t zi_axis_stride,
        const float *zi_template,
        bool scale_template_with_first,
        float *zf,
        const std::size_t *zf_bases,
        std::size_t zf_axis_stride)
    {
        const std::size_t line =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (line >= line_count)
        {
            return;
        }

        const std::size_t order = (b_size > a_size ? b_size : a_size) - 1;
        if (order > kMaxFilterOrder)
        {
            return;
        }

        const float a0 = a_size == 0 ? 1.0 : a[0];
        const std::size_t base = line_bases[line];
        float state[kMaxFilterOrder];
        for (std::size_t index = 0; index < order; ++index)
        {
            state[index] = 0.0;
        }

        if (zi != nullptr && zi_bases != nullptr)
        {
            const std::size_t zi_base = zi_bases[line];
            for (std::size_t index = 0; index < order; ++index)
            {
                state[index] = zi[zi_base + index * zi_axis_stride];
            }
        }
        else if (zi_template != nullptr)
        {
            const float scale =
                scale_template_with_first && axis_size != 0 ? input[base] : 1.0;
            for (std::size_t index = 0; index < order; ++index)
            {
                state[index] = zi_template[index] * scale;
            }
        }

        if (order == 0)
        {
            const float b0 = b_size == 0 ? 0.0 : b[0] / a0;
            for (std::size_t index = 0; index < axis_size; ++index)
            {
                output[base + index * axis_stride] = b0 * input[base + index * axis_stride];
            }
            return;
        }

        for (std::size_t index = 0; index < axis_size; ++index)
        {
            const float x_n = input[base + index * axis_stride];
            const float y_n = (b_size == 0 ? 0.0 : (b[0] / a0) * x_n) + state[0];
            for (std::size_t state_index = 0; state_index + 1 < order; ++state_index)
            {
                const float b_term =
                    (state_index + 1 < b_size ? b[state_index + 1] / a0 : 0.0) * x_n;
                const float a_term =
                    (state_index + 1 < a_size ? a[state_index + 1] / a0 : 0.0) * y_n;
                state[state_index] = state[state_index + 1] + b_term - a_term;
            }
            const float b_last = (order < b_size ? b[order] / a0 : 0.0) * x_n;
            const float a_last = (order < a_size ? a[order] / a0 : 0.0) * y_n;
            state[order - 1] = b_last - a_last;
            output[base + index * axis_stride] = y_n;
        }

        if (zf != nullptr && zf_bases != nullptr)
        {
            const std::size_t zf_base = zf_bases[line];
            for (std::size_t index = 0; index < order; ++index)
            {
                zf[zf_base + index * zf_axis_stride] = state[index];
            }
        }
    }

    __global__ void fir_filter_clamped_lines_kernel(
        const float *b,
        std::size_t b_size,
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * axis_size;
        if (flat >= total)
        {
            return;
        }

        const std::size_t line = flat / axis_size;
        const std::size_t index = flat % axis_size;
        const std::size_t base = line_bases[line];
        float value = 0.0f;
        for (std::size_t tap = 0; tap < b_size; ++tap)
        {
            const std::size_t source = index >= tap ? index - tap : 0;
            value += b[tap] * input[base + source * axis_stride];
        }
        output[base + index * axis_stride] = value;
    }

    __global__ void fir_filter_reverse_clamped_crop_lines_kernel(
        const float *b,
        std::size_t b_size,
        const float *forward,
        const std::size_t *padded_line_bases,
        std::size_t padded_axis_size,
        std::size_t padded_axis_stride,
        float *output,
        const std::size_t *output_line_bases,
        std::size_t output_axis_size,
        std::size_t output_axis_stride,
        std::size_t line_count,
        std::size_t edge)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * output_axis_size;
        if (flat >= total)
        {
            return;
        }

        const std::size_t line = flat / output_axis_size;
        const std::size_t index = flat % output_axis_size;
        const std::size_t padded_base = padded_line_bases[line];
        const std::size_t output_base = output_line_bases[line];
        const std::size_t padded_index = edge + index;
        float value = 0.0f;
        for (std::size_t tap = 0; tap < b_size; ++tap)
        {
            const std::size_t unclamped_source = padded_index + tap;
            const std::size_t source =
                unclamped_source < padded_axis_size ? unclamped_source : padded_axis_size - 1;
            value += b[tap] * forward[padded_base + source * padded_axis_stride];
        }
        output[output_base + index * output_axis_stride] = value;
    }

    __global__ void fir_filter_zero_lines_kernel(
        const float *b,
        std::size_t b_size,
        const float *a,
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output)
    {
        __shared__ float taps[kMaxFilterOrder + 1];
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            taps[tap] = b[tap] / a[0];
        }
        __syncthreads();

        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * axis_size;
        if (flat >= total)
        {
            return;
        }

        const std::size_t line = flat / axis_size;
        const std::size_t index = flat % axis_size;
        const std::size_t base = line_bases[line];
        float value = 0.0f;
        const std::size_t tap_limit = min(b_size, index + 1);
        for (std::size_t tap = 0; tap < tap_limit; ++tap)
        {
            value += taps[tap] * input[base + (index - tap) * axis_stride];
        }
        output[base + index * axis_stride] = value;
    }

    __global__ void fir_filter_zero_lines_shared_dual_kernel(
        const float *b,
        std::size_t b_size,
        float a0,
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output)
    {
        extern __shared__ float real_fir_shared_bytes[];
        const std::size_t outputs_per_block = 2 * static_cast<std::size_t>(blockDim.x);
        const std::size_t input_tile_size = outputs_per_block + b_size - 1;
        float *shared_input = real_fir_shared_bytes;
        float *shared_taps = shared_input + input_tile_size;

        const std::size_t line = static_cast<std::size_t>(blockIdx.y);
        if (line >= line_count)
        {
            return;
        }
        const std::size_t block_start =
            static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
        const std::size_t base = line_bases[line];
        const long input_start =
            static_cast<long>(block_start) - static_cast<long>(b_size - 1);
        for (std::size_t local = threadIdx.x; local < input_tile_size; local += blockDim.x)
        {
            const long index = input_start + static_cast<long>(local);
            shared_input[local] = index >= 0 && index < static_cast<long>(axis_size)
                ? input[base + static_cast<std::size_t>(index) * axis_stride]
                : 0.0f;
        }
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            shared_taps[tap] = b[tap] / a0;
        }
        __syncthreads();

        const std::size_t index0 = block_start + static_cast<std::size_t>(threadIdx.x);
        if (index0 >= axis_size)
        {
            return;
        }
        const std::size_t index1 = index0 + static_cast<std::size_t>(blockDim.x);
        const std::size_t tap_limit0 = min(b_size, index0 + 1);
        const std::size_t tap_limit1 = index1 < axis_size ? min(b_size, index1 + 1) : 0;
        const std::size_t shared_index0 =
            static_cast<std::size_t>(threadIdx.x) + b_size - 1;
        float value0 = 0.0f;
        float value1 = 0.0f;
        for (std::size_t tap = 0; tap < tap_limit0; ++tap)
        {
            const float coefficient = shared_taps[tap];
            value0 += coefficient * shared_input[shared_index0 - tap];
            value1 += coefficient * shared_input[shared_index0 + blockDim.x - tap];
        }
        for (std::size_t tap = tap_limit0; tap < tap_limit1; ++tap)
        {
            value1 += shared_taps[tap] * shared_input[shared_index0 + blockDim.x - tap];
        }
        output[base + index0 * axis_stride] = value0;
        if (index1 < axis_size)
        {
            output[base + index1 * axis_stride] = value1;
        }
    }

    template <int OutputsPerThread>
    __global__ void fir_filter_zero_lines_shared_multi_kernel(
        const float *b,
        std::size_t b_size,
        float a0,
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output)
    {
        extern __shared__ float real_fir_shared_bytes[];
        const std::size_t outputs_per_block =
            static_cast<std::size_t>(OutputsPerThread) * static_cast<std::size_t>(blockDim.x);
        const std::size_t input_tile_size = outputs_per_block + b_size - 1;
        float *shared_input = real_fir_shared_bytes;
        float *shared_taps = shared_input + input_tile_size;

        const std::size_t line = static_cast<std::size_t>(blockIdx.y);
        if (line >= line_count)
        {
            return;
        }
        const std::size_t block_start =
            static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
        const std::size_t base = line_bases[line];
        const long input_start =
            static_cast<long>(block_start) - static_cast<long>(b_size - 1);
        for (std::size_t local = threadIdx.x; local < input_tile_size; local += blockDim.x)
        {
            const long index = input_start + static_cast<long>(local);
            shared_input[local] = index >= 0 && index < static_cast<long>(axis_size)
                ? input[base + static_cast<std::size_t>(index) * axis_stride]
                : 0.0f;
        }
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            shared_taps[tap] = b[tap] / a0;
        }
        __syncthreads();

        const std::size_t first_index = block_start + static_cast<std::size_t>(threadIdx.x);
        const std::size_t first_shared =
            static_cast<std::size_t>(threadIdx.x) + b_size - 1;
        for (int output_index = 0; output_index < OutputsPerThread; ++output_index)
        {
            const std::size_t index =
                first_index + static_cast<std::size_t>(output_index) * blockDim.x;
            if (index >= axis_size)
            {
                continue;
            }
            const std::size_t tap_limit = min(b_size, index + 1);
            float value = 0.0f;
            const std::size_t shared_index =
                first_shared + static_cast<std::size_t>(output_index) * blockDim.x;
            for (std::size_t tap = 0; tap < tap_limit; ++tap)
            {
                value += shared_taps[tap] * shared_input[shared_index - tap];
            }
            output[base + index * axis_stride] = value;
        }
    }

    __global__ void complex_fir_filter_zero_lines_kernel(
        const float *b,
        std::size_t b_size,
        const float2 *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float2 *output)
    {
        __shared__ float taps[kMaxFilterOrder + 1];
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            taps[tap] = b[tap];
        }
        __syncthreads();

        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * axis_size;
        if (flat >= total)
        {
            return;
        }

        const std::size_t line = flat / axis_size;
        const std::size_t index = flat % axis_size;
        const std::size_t base = line_bases[line];
        float2 value = make_float2(0.0f, 0.0f);
        const std::size_t tap_limit = min(b_size, index + 1);
        for (std::size_t tap = 0; tap < tap_limit; ++tap)
        {
            const float2 sample = input[base + (index - tap) * axis_stride];
            value.x += taps[tap] * sample.x;
            value.y += taps[tap] * sample.y;
        }
        output[base + index * axis_stride] = value;
    }

    __global__ void complex_fir_filter_zero_lines_shared_kernel(
        const float *b,
        std::size_t b_size,
        const float2 *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float2 *output)
    {
        extern __shared__ unsigned char shared_bytes[];
        float2 *shared_input = reinterpret_cast<float2 *>(shared_bytes);
        const std::size_t input_tile_size =
            static_cast<std::size_t>(blockDim.x) + b_size - 1;
        float *shared_taps = reinterpret_cast<float *>(shared_input + input_tile_size);

        const std::size_t line = static_cast<std::size_t>(blockIdx.y);
        if (line >= line_count)
        {
            return;
        }
        const std::size_t block_start =
            static_cast<std::size_t>(blockIdx.x) * static_cast<std::size_t>(blockDim.x);
        const std::size_t base = line_bases[line];
        const long input_start =
            static_cast<long>(block_start) - static_cast<long>(b_size - 1);
        for (std::size_t local = threadIdx.x; local < input_tile_size; local += blockDim.x)
        {
            const long index = input_start + static_cast<long>(local);
            shared_input[local] = index >= 0 && index < static_cast<long>(axis_size)
                ? input[base + static_cast<std::size_t>(index) * axis_stride]
                : make_float2(0.0f, 0.0f);
        }
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            shared_taps[tap] = b[tap];
        }
        __syncthreads();

        const std::size_t index = block_start + static_cast<std::size_t>(threadIdx.x);
        if (index >= axis_size)
        {
            return;
        }
        const std::size_t tap_limit = min(b_size, index + 1);
        float2 value = make_float2(0.0f, 0.0f);
        for (std::size_t tap = 0; tap < tap_limit; ++tap)
        {
            const float2 sample =
                shared_input[static_cast<std::size_t>(threadIdx.x) + b_size - 1 - tap];
            value.x += shared_taps[tap] * sample.x;
            value.y += shared_taps[tap] * sample.y;
        }
        output[base + index * axis_stride] = value;
    }

    __global__ void complex_fir_filter_zero_lines_shared_dual_kernel(
        const float *b,
        std::size_t b_size,
        const float2 *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float2 *output)
    {
        extern __shared__ unsigned char shared_bytes[];
        float2 *shared_input = reinterpret_cast<float2 *>(shared_bytes);
        const std::size_t outputs_per_block = 2 * static_cast<std::size_t>(blockDim.x);
        const std::size_t input_tile_size = outputs_per_block + b_size - 1;
        float *shared_taps = reinterpret_cast<float *>(shared_input + input_tile_size);

        const std::size_t line = static_cast<std::size_t>(blockIdx.y);
        if (line >= line_count)
        {
            return;
        }
        const std::size_t block_start =
            static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
        const std::size_t base = line_bases[line];
        const long input_start =
            static_cast<long>(block_start) - static_cast<long>(b_size - 1);
        for (std::size_t local = threadIdx.x; local < input_tile_size; local += blockDim.x)
        {
            const long index = input_start + static_cast<long>(local);
            shared_input[local] = index >= 0 && index < static_cast<long>(axis_size)
                ? input[base + static_cast<std::size_t>(index) * axis_stride]
                : make_float2(0.0f, 0.0f);
        }
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            shared_taps[tap] = b[tap];
        }
        __syncthreads();

        const std::size_t index0 = block_start + static_cast<std::size_t>(threadIdx.x);
        if (index0 >= axis_size)
        {
            return;
        }
        const std::size_t index1 = index0 + static_cast<std::size_t>(blockDim.x);
        const std::size_t tap_limit0 = min(b_size, index0 + 1);
        const std::size_t tap_limit1 = index1 < axis_size ? min(b_size, index1 + 1) : 0;
        float2 value0 = make_float2(0.0f, 0.0f);
        float2 value1 = make_float2(0.0f, 0.0f);
        const std::size_t shared_index0 =
            static_cast<std::size_t>(threadIdx.x) + b_size - 1;
        for (std::size_t tap = 0; tap < tap_limit0; ++tap)
        {
            const float coefficient = shared_taps[tap];
            const float2 sample0 = shared_input[shared_index0 - tap];
            const float2 sample1 = shared_input[shared_index0 + blockDim.x - tap];
            value0.x += coefficient * sample0.x;
            value0.y += coefficient * sample0.y;
            value1.x += coefficient * sample1.x;
            value1.y += coefficient * sample1.y;
        }
        for (std::size_t tap = tap_limit0; tap < tap_limit1; ++tap)
        {
            const float coefficient = shared_taps[tap];
            const float2 sample1 = shared_input[shared_index0 + blockDim.x - tap];
            value1.x += coefficient * sample1.x;
            value1.y += coefficient * sample1.y;
        }
        output[base + index0 * axis_stride] = value0;
        if (index1 < axis_size)
        {
            output[base + index1 * axis_stride] = value1;
        }
    }

    __global__ void complex_fir_filter_zero_lines_shared_quad_kernel(
        const float *b,
        std::size_t b_size,
        const float2 *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float2 *output)
    {
        extern __shared__ unsigned char shared_bytes[];
        float2 *shared_input = reinterpret_cast<float2 *>(shared_bytes);
        const std::size_t outputs_per_block = 4 * static_cast<std::size_t>(blockDim.x);
        const std::size_t input_tile_size = outputs_per_block + b_size - 1;
        float *shared_taps = reinterpret_cast<float *>(shared_input + input_tile_size);

        const std::size_t line = static_cast<std::size_t>(blockIdx.y);
        if (line >= line_count)
        {
            return;
        }
        const std::size_t block_start =
            static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
        const std::size_t base = line_bases[line];
        const long input_start =
            static_cast<long>(block_start) - static_cast<long>(b_size - 1);
        for (std::size_t local = threadIdx.x; local < input_tile_size; local += blockDim.x)
        {
            const long index = input_start + static_cast<long>(local);
            shared_input[local] = index >= 0 && index < static_cast<long>(axis_size)
                ? input[base + static_cast<std::size_t>(index) * axis_stride]
                : make_float2(0.0f, 0.0f);
        }
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            shared_taps[tap] = b[tap];
        }
        __syncthreads();

        const std::size_t index0 = block_start + static_cast<std::size_t>(threadIdx.x);
        if (index0 >= axis_size)
        {
            return;
        }
        const std::size_t index1 = index0 + static_cast<std::size_t>(blockDim.x);
        const std::size_t index2 = index1 + static_cast<std::size_t>(blockDim.x);
        const std::size_t index3 = index2 + static_cast<std::size_t>(blockDim.x);
        const std::size_t tap_limit0 = min(b_size, index0 + 1);
        float2 value0 = make_float2(0.0f, 0.0f);
        float2 value1 = make_float2(0.0f, 0.0f);
        float2 value2 = make_float2(0.0f, 0.0f);
        float2 value3 = make_float2(0.0f, 0.0f);
        const std::size_t shared_index0 =
            static_cast<std::size_t>(threadIdx.x) + b_size - 1;
        for (std::size_t tap = 0; tap < tap_limit0; ++tap)
        {
            const float coefficient = shared_taps[tap];
            const float2 sample0 = shared_input[shared_index0 - tap];
            const float2 sample1 = shared_input[shared_index0 + blockDim.x - tap];
            const float2 sample2 = shared_input[shared_index0 + 2 * blockDim.x - tap];
            const float2 sample3 = shared_input[shared_index0 + 3 * blockDim.x - tap];
            value0.x += coefficient * sample0.x;
            value0.y += coefficient * sample0.y;
            value1.x += coefficient * sample1.x;
            value1.y += coefficient * sample1.y;
            value2.x += coefficient * sample2.x;
            value2.y += coefficient * sample2.y;
            value3.x += coefficient * sample3.x;
            value3.y += coefficient * sample3.y;
        }
        for (std::size_t tap = tap_limit0; tap < b_size; ++tap)
        {
            const float coefficient = shared_taps[tap];
            const float2 sample1 = shared_input[shared_index0 + blockDim.x - tap];
            const float2 sample2 = shared_input[shared_index0 + 2 * blockDim.x - tap];
            const float2 sample3 = shared_input[shared_index0 + 3 * blockDim.x - tap];
            value1.x += coefficient * sample1.x;
            value1.y += coefficient * sample1.y;
            value2.x += coefficient * sample2.x;
            value2.y += coefficient * sample2.y;
            value3.x += coefficient * sample3.x;
            value3.y += coefficient * sample3.y;
        }
        output[base + index0 * axis_stride] = value0;
        if (index1 < axis_size)
        {
            output[base + index1 * axis_stride] = value1;
        }
        if (index2 < axis_size)
        {
            output[base + index2 * axis_stride] = value2;
        }
        if (index3 < axis_size)
        {
            output[base + index3 * axis_stride] = value3;
        }
    }

    template <int OutputsPerThread>
    __global__ void complex_fir_filter_zero_lines_shared_multi_kernel(
        const float *b,
        std::size_t b_size,
        const float2 *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float2 *output)
    {
        extern __shared__ unsigned char shared_bytes[];
        float2 *shared_input = reinterpret_cast<float2 *>(shared_bytes);
        const std::size_t outputs_per_block =
            static_cast<std::size_t>(OutputsPerThread) * static_cast<std::size_t>(blockDim.x);
        const std::size_t input_tile_size = outputs_per_block + b_size - 1;
        float *shared_taps = reinterpret_cast<float *>(shared_input + input_tile_size);

        const std::size_t line = static_cast<std::size_t>(blockIdx.y);
        if (line >= line_count)
        {
            return;
        }
        const std::size_t block_start =
            static_cast<std::size_t>(blockIdx.x) * outputs_per_block;
        const std::size_t base = line_bases[line];
        const long input_start =
            static_cast<long>(block_start) - static_cast<long>(b_size - 1);
        for (std::size_t local = threadIdx.x; local < input_tile_size; local += blockDim.x)
        {
            const long index = input_start + static_cast<long>(local);
            shared_input[local] = index >= 0 && index < static_cast<long>(axis_size)
                ? input[base + static_cast<std::size_t>(index) * axis_stride]
                : make_float2(0.0f, 0.0f);
        }
        for (std::size_t tap = threadIdx.x; tap < b_size; tap += blockDim.x)
        {
            shared_taps[tap] = b[tap];
        }
        __syncthreads();

        const std::size_t first_index = block_start + static_cast<std::size_t>(threadIdx.x);
        const std::size_t first_shared =
            static_cast<std::size_t>(threadIdx.x) + b_size - 1;
        for (int output_index = 0; output_index < OutputsPerThread; ++output_index)
        {
            const std::size_t index =
                first_index + static_cast<std::size_t>(output_index) * blockDim.x;
            if (index >= axis_size)
            {
                continue;
            }
            const std::size_t tap_limit = min(b_size, index + 1);
            float2 value = make_float2(0.0f, 0.0f);
            const std::size_t shared_index =
                first_shared + static_cast<std::size_t>(output_index) * blockDim.x;
            for (std::size_t tap = 0; tap < tap_limit; ++tap)
            {
                const float coefficient = shared_taps[tap];
                const float2 sample = shared_input[shared_index - tap];
                value.x += coefficient * sample.x;
                value.y += coefficient * sample.y;
            }
            output[base + index * axis_stride] = value;
        }
    }

    __global__ void build_single_sos_from_ba_kernel(
        const float *b,
        std::size_t b_size,
        const float *a,
        std::size_t a_size,
        float *sos)
    {
        if (blockIdx.x != 0 || threadIdx.x != 0)
        {
            return;
        }
        sos[0] = b_size > 0 ? b[0] : 0.0f;
        sos[1] = b_size > 1 ? b[1] : 0.0f;
        sos[2] = b_size > 2 ? b[2] : 0.0f;
        sos[3] = a_size > 0 ? a[0] : 1.0f;
        sos[4] = a_size > 1 ? a[1] : 0.0f;
        sos[5] = a_size > 2 ? a[2] : 0.0f;
    }

    __global__ void sosfilt_line_kernel(
        const float *sos,
        std::size_t n_sections,
        const float *input,
        const std::size_t *line_bases,
        std::size_t line_count,
        std::size_t axis_size,
        std::size_t axis_stride,
        float *output,
        const float *zi,
        const std::size_t *zi_line_bases,
        const std::size_t *zi_section_bases,
        std::size_t zi_axis_stride,
        float *zf,
        const std::size_t *zf_line_bases,
        const std::size_t *zf_section_bases,
        std::size_t zf_axis_stride)
    {
        const std::size_t line =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (line >= line_count)
        {
            return;
        }
        if (n_sections > kMaxSosSections)
        {
            return;
        }

        const std::size_t base = line_bases[line];
        for (std::size_t index = 0; index < axis_size; ++index)
        {
            output[base + index * axis_stride] = input[base + index * axis_stride];
        }

        float state[kMaxSosSections * 2];
        for (std::size_t section = 0; section < n_sections; ++section)
        {
            state[section * 2] = 0.0;
            state[section * 2 + 1] = 0.0;
        }
        if (zi != nullptr && zi_line_bases != nullptr && zi_section_bases != nullptr)
        {
            const std::size_t line_base = zi_line_bases[line];
            for (std::size_t section = 0; section < n_sections; ++section)
            {
                const std::size_t section_base = zi_section_bases[section] + line_base;
                state[section * 2] = zi[section_base];
                state[section * 2 + 1] = zi[section_base + zi_axis_stride];
            }
        }

        for (std::size_t section = 0; section < n_sections; ++section)
        {
            const float *s = sos + section * 6;
            const float b0 = s[0];
            const float b1 = s[1];
            const float b2 = s[2];
            const float a0 = s[3];
            const float a1 = s[4];
            const float a2 = s[5];
            float z0 = state[section * 2];
            float z1 = state[section * 2 + 1];
            for (std::size_t index = 0; index < axis_size; ++index)
            {
                const std::size_t offset = base + index * axis_stride;
                const float x_n = output[offset];
                const float y_n = (b0 / a0) * x_n + z0;
                z0 = z1 + (b1 / a0) * x_n - (a1 / a0) * y_n;
                z1 = (b2 / a0) * x_n - (a2 / a0) * y_n;
                output[offset] = y_n;
            }
            state[section * 2] = z0;
            state[section * 2 + 1] = z1;
        }

        if (zf != nullptr && zf_line_bases != nullptr && zf_section_bases != nullptr)
        {
            const std::size_t line_base = zf_line_bases[line];
            for (std::size_t section = 0; section < n_sections; ++section)
            {
                const std::size_t section_base = zf_section_bases[section] + line_base;
                zf[section_base] = state[section * 2];
                zf[section_base + zf_axis_stride] = state[section * 2 + 1];
            }
        }
    }

    __device__ inline void sos_coefficients(
        const float *s,
        float &c0,
        float &p,
        float &q,
        float &d0,
        float &d1)
    {
        const float a0 = s[3];
        c0 = s[0] / a0;
        const float c1 = s[1] / a0;
        const float c2 = s[2] / a0;
        p = -s[4] / a0;
        q = -s[5] / a0;
        d0 = c1 + p * c0;
        d1 = c2 + q * c0;
    }

    struct SosAffineTransform
    {
        float m00;
        float m01;
        float m10;
        float m11;
        float v0;
        float v1;
    };

    __device__ inline SosAffineTransform sos_identity_transform()
    {
        return SosAffineTransform{1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f};
    }

    __device__ inline SosAffineTransform sos_compose_after(
        const SosAffineTransform &after,
        const SosAffineTransform &before)
    {
        return SosAffineTransform{
            after.m00 * before.m00 + after.m01 * before.m10,
            after.m00 * before.m01 + after.m01 * before.m11,
            after.m10 * before.m00 + after.m11 * before.m10,
            after.m10 * before.m01 + after.m11 * before.m11,
            after.m00 * before.v0 + after.m01 * before.v1 + after.v0,
            after.m10 * before.v0 + after.m11 * before.v1 + after.v1};
    }

    __global__ void sosfilt_prefix_tiles_kernel(
        const float *sos,
        std::size_t section,
        const float *input,
        std::size_t axis_size,
        float *output,
        float *sample_prefix_matrices,
        float *tile_transforms)
    {
        __shared__ SosAffineTransform scan[kThreadsPerBlock];

        float c0 = 0.0f;
        float p = 0.0f;
        float q = 0.0f;
        float d0 = 0.0f;
        float d1 = 0.0f;
        sos_coefficients(sos + section * 6, c0, p, q, d0, d1);

        const int tid = threadIdx.x;
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + static_cast<std::size_t>(tid);
        const bool valid = index < axis_size;
        const float x_n = valid ? input[index] : 0.0f;

        scan[tid] = valid
                        ? SosAffineTransform{p, 1.0f, q, 0.0f, d0 * x_n, d1 * x_n}
                        : sos_identity_transform();
        __syncthreads();

        for (int offset = 1; offset < blockDim.x; offset <<= 1)
        {
            SosAffineTransform previous = sos_identity_transform();
            if (tid >= offset)
            {
                previous = scan[tid - offset];
            }
            __syncthreads();
            if (tid >= offset)
            {
                scan[tid] = sos_compose_after(scan[tid], previous);
            }
            __syncthreads();
        }

        SosAffineTransform exclusive = sos_identity_transform();
        if (tid > 0)
        {
            exclusive = scan[tid - 1];
        }

        if (valid)
        {
            const std::size_t matrix_out = index * 2;
            sample_prefix_matrices[matrix_out + 0] = exclusive.m00;
            sample_prefix_matrices[matrix_out + 1] = exclusive.m01;
            output[index] = c0 * x_n + exclusive.v0;
        }

        if (tid == blockDim.x - 1)
        {
            const std::size_t tile_out = static_cast<std::size_t>(blockIdx.x) * 6;
            const SosAffineTransform tile = scan[tid];
            tile_transforms[tile_out + 0] = tile.m00;
            tile_transforms[tile_out + 1] = tile.m01;
            tile_transforms[tile_out + 2] = tile.m10;
            tile_transforms[tile_out + 3] = tile.m11;
            tile_transforms[tile_out + 4] = tile.v0;
            tile_transforms[tile_out + 5] = tile.v1;
        }
    }

    __device__ inline SosAffineTransform sos_load_transform(const float *values, std::size_t index)
    {
        const std::size_t in = index * 6;
        return SosAffineTransform{
            values[in + 0],
            values[in + 1],
            values[in + 2],
            values[in + 3],
            values[in + 4],
            values[in + 5]};
    }

    __device__ inline void sos_store_transform(float *values, std::size_t index, const SosAffineTransform &transform)
    {
        const std::size_t out = index * 6;
        values[out + 0] = transform.m00;
        values[out + 1] = transform.m01;
        values[out + 2] = transform.m10;
        values[out + 3] = transform.m11;
        values[out + 4] = transform.v0;
        values[out + 5] = transform.v1;
    }

    __global__ void sosfilt_scan_tile_transform_blocks_kernel(
        const float *tile_transforms,
        int tile_count,
        float *tile_prefix_transforms,
        float *block_transforms)
    {
        __shared__ SosAffineTransform scan[kThreadsPerBlock];

        const int tid = threadIdx.x;
        const int tile = blockIdx.x * blockDim.x + tid;
        scan[tid] = tile < tile_count
                        ? sos_load_transform(tile_transforms, static_cast<std::size_t>(tile))
                        : sos_identity_transform();
        __syncthreads();

        for (int offset = 1; offset < blockDim.x; offset <<= 1)
        {
            SosAffineTransform previous = sos_identity_transform();
            if (tid >= offset)
            {
                previous = scan[tid - offset];
            }
            __syncthreads();
            if (tid >= offset)
            {
                scan[tid] = sos_compose_after(scan[tid], previous);
            }
            __syncthreads();
        }

        if (tile < tile_count)
        {
            const SosAffineTransform exclusive =
                tid == 0 ? sos_identity_transform() : scan[tid - 1];
            sos_store_transform(tile_prefix_transforms, static_cast<std::size_t>(tile), exclusive);
        }
        if (tid == blockDim.x - 1)
        {
            sos_store_transform(block_transforms, static_cast<std::size_t>(blockIdx.x), scan[tid]);
        }
    }

    __global__ void sosfilt_scan_block_transforms_kernel(
        const float *block_transforms,
        int block_count,
        float *block_initial_states,
        const float *initial_state,
        const float *scale_input)
    {
        if (blockIdx.x != 0 || threadIdx.x != 0)
        {
            return;
        }

        const float scale = scale_input != nullptr ? scale_input[0] : 1.0f;
        float z0 = initial_state != nullptr ? initial_state[0] * scale : 0.0f;
        float z1 = initial_state != nullptr ? initial_state[1] * scale : 0.0f;
        for (int block = 0; block < block_count; ++block)
        {
            block_initial_states[static_cast<std::size_t>(block) * 2] = z0;
            block_initial_states[static_cast<std::size_t>(block) * 2 + 1] = z1;
            const SosAffineTransform transform =
                sos_load_transform(block_transforms, static_cast<std::size_t>(block));
            const float next_z0 = transform.m00 * z0 + transform.m01 * z1 + transform.v0;
            const float next_z1 = transform.m10 * z0 + transform.m11 * z1 + transform.v1;
            z0 = next_z0;
            z1 = next_z1;
        }
    }

    __global__ void sosfilt_apply_block_prefix_to_samples_kernel(
        const float *tile_prefix_transforms,
        const float *block_initial_states,
        const float *sample_prefix_matrices,
        std::size_t axis_size,
        float *output)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= axis_size)
        {
            return;
        }

        const std::size_t tile = index / static_cast<std::size_t>(kThreadsPerBlock);
        const std::size_t block = tile / static_cast<std::size_t>(kThreadsPerBlock);
        const float block_z0 = block_initial_states[block * 2];
        const float block_z1 = block_initial_states[block * 2 + 1];
        const SosAffineTransform prefix = sos_load_transform(tile_prefix_transforms, tile);
        const float z0 = prefix.m00 * block_z0 + prefix.m01 * block_z1 + prefix.v0;
        const float z1 = prefix.m10 * block_z0 + prefix.m11 * block_z1 + prefix.v1;
        const std::size_t matrix_in = index * 2;
        output[index] += sample_prefix_matrices[matrix_in + 0] * z0 +
                         sample_prefix_matrices[matrix_in + 1] * z1;
    }

    __global__ void solve_lfilter_zi_kernel(
        const float *b,
        std::size_t b_size,
        const float *a,
        std::size_t a_size,
        float *output,
        float *matrix,
        float *rhs)
    {
        __shared__ float a_norm[kMaxLfilterZiOrder + 1];
        __shared__ float b_norm[kMaxLfilterZiOrder + 1];
        __shared__ std::size_t first_nonzero;
        __shared__ std::size_t normalized_a_size;
        __shared__ std::size_t n;
        __shared__ std::size_t order;
        __shared__ int unity_feedback;

        if (threadIdx.x == 0)
        {
            first_nonzero = 0;
            while (first_nonzero + 1 < a_size && a[first_nonzero] == 0.0)
            {
                ++first_nonzero;
            }
            normalized_a_size = a_size - first_nonzero;
            n = normalized_a_size > b_size ? normalized_a_size : b_size;
            order = n > 0 ? n - 1 : 0;
        }
        __syncthreads();

        if (n <= 1)
        {
            return;
        }

        for (std::size_t index = threadIdx.x; index < n; index += blockDim.x)
        {
            a_norm[index] = index < normalized_a_size ? a[first_nonzero + index] : 0.0f;
            b_norm[index] = index < b_size ? b[index] : 0.0f;
        }
        __syncthreads();

        const float a0 = a_norm[0];
        if (a0 != 1.0f)
        {
            for (std::size_t index = threadIdx.x; index < n; index += blockDim.x)
            {
                a_norm[index] /= a0;
                b_norm[index] /= a0;
            }
        }
        __syncthreads();

        if (threadIdx.x == 0)
        {
            unity_feedback = 1;
            for (std::size_t index = 1; index < n; ++index)
            {
                if (a_norm[index] != 0.0f)
                {
                    unity_feedback = 0;
                    break;
                }
            }
        }
        __syncthreads();

        if (unity_feedback != 0)
        {
            for (std::size_t row = threadIdx.x; row < order; row += blockDim.x)
            {
                float sum = 0.0f;
                for (std::size_t column = row + 1; column < n; ++column)
                {
                    sum += b_norm[column];
                }
                output[row] = sum;
            }
            return;
        }

        if (blockIdx.x != 0 || threadIdx.x != 0)
        {
            return;
        }

        for (std::size_t row = 0; row < order; ++row)
        {
            for (std::size_t column = 0; column < order; ++column)
            {
                matrix[row * order + column] = 0.0;
            }
            matrix[row * order + row] = 1.0;
            matrix[row * order] += a_norm[row + 1];
            if (row + 1 < order)
            {
                matrix[row * order + row + 1] = -1.0;
            }
            rhs[row] = b_norm[row + 1] - a_norm[row + 1] * b_norm[0];
        }

        for (std::size_t pivot = 0; pivot < order; ++pivot)
        {
            std::size_t best = pivot;
            for (std::size_t row = pivot + 1; row < order; ++row)
            {
                if (fabs(matrix[row * order + pivot]) > fabs(matrix[best * order + pivot]))
                {
                    best = row;
                }
            }
            if (best != pivot)
            {
                for (std::size_t column = 0; column < order; ++column)
                {
                    const float tmp = matrix[pivot * order + column];
                    matrix[pivot * order + column] = matrix[best * order + column];
                    matrix[best * order + column] = tmp;
                }
                const float rhs_tmp = rhs[pivot];
                rhs[pivot] = rhs[best];
                rhs[best] = rhs_tmp;
            }

            const float divisor = matrix[pivot * order + pivot];
            for (std::size_t column = pivot; column < order; ++column)
            {
                matrix[pivot * order + column] /= divisor;
            }
            rhs[pivot] /= divisor;

            for (std::size_t row = 0; row < order; ++row)
            {
                if (row == pivot)
                {
                    continue;
                }
                const float factor = matrix[row * order + pivot];
                for (std::size_t column = pivot; column < order; ++column)
                {
                    matrix[row * order + column] -= factor * matrix[pivot * order + column];
                }
                rhs[row] -= factor * rhs[pivot];
            }
        }

        for (std::size_t row = 0; row < order; ++row)
        {
            output[row] = rhs[row];
        }
    }

    __global__ void pad_lines_kernel(
        const float *input,
        const std::size_t *input_bases,
        std::size_t input_axis_size,
        std::size_t input_axis_stride,
        float *output,
        const std::size_t *output_bases,
        std::size_t output_axis_size,
        std::size_t output_axis_stride,
        std::size_t line_count,
        std::size_t edge,
        int pad_mode)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * output_axis_size;
        if (flat >= total)
        {
            return;
        }
        const std::size_t line = flat / output_axis_size;
        const std::size_t index = flat % output_axis_size;
        const std::size_t in_base = input_bases[line];
        const std::size_t out_base = output_bases[line];

        float value = 0.0;
        if (pad_mode == 0 || edge == 0)
        {
            const std::size_t source = index;
            value = input[in_base + source * input_axis_stride];
        }
        else if (index < edge)
        {
            const std::size_t source = edge - index;
            if (pad_mode == 2)
            {
                value = input[in_base + source * input_axis_stride];
            }
            else if (pad_mode == 1)
            {
                value = 2.0 * input[in_base] - input[in_base + source * input_axis_stride];
            }
            else
            {
                value = input[in_base];
            }
        }
        else if (index < edge + input_axis_size)
        {
            const std::size_t source = index - edge;
            value = input[in_base + source * input_axis_stride];
        }
        else
        {
            const std::size_t offset = index - edge - input_axis_size;
            const std::size_t source = input_axis_size - 2 - offset;
            if (pad_mode == 2)
            {
                value = input[in_base + source * input_axis_stride];
            }
            else if (pad_mode == 1)
            {
                value = 2.0 * input[in_base + (input_axis_size - 1) * input_axis_stride] -
                        input[in_base + source * input_axis_stride];
            }
            else
            {
                value = input[in_base + (input_axis_size - 1) * input_axis_stride];
            }
        }
        output[out_base + index * output_axis_stride] = value;
    }

    __global__ void reverse_lines_kernel(
        const float *input,
        const std::size_t *input_bases,
        std::size_t input_axis_size,
        std::size_t input_axis_stride,
        float *output,
        const std::size_t *output_bases,
        std::size_t output_axis_stride,
        std::size_t line_count)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * input_axis_size;
        if (flat >= total)
        {
            return;
        }
        const std::size_t line = flat / input_axis_size;
        const std::size_t index = flat % input_axis_size;
        output[output_bases[line] + index * output_axis_stride] =
            input[input_bases[line] + (input_axis_size - 1 - index) * input_axis_stride];
    }

    __global__ void crop_lines_kernel(
        const float *input,
        const std::size_t *input_bases,
        std::size_t input_axis_stride,
        float *output,
        const std::size_t *output_bases,
        std::size_t output_axis_size,
        std::size_t output_axis_stride,
        std::size_t line_count,
        std::size_t edge)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * output_axis_size;
        if (flat >= total)
        {
            return;
        }
        const std::size_t line = flat / output_axis_size;
        const std::size_t index = flat % output_axis_size;
        output[output_bases[line] + index * output_axis_stride] =
            input[input_bases[line] + (index + edge) * input_axis_stride];
    }

    __global__ void subsample_lines_kernel(
        const float *input,
        const std::size_t *input_bases,
        std::size_t input_axis_stride,
        float *output,
        const std::size_t *output_bases,
        std::size_t output_axis_size,
        std::size_t output_axis_stride,
        std::size_t line_count,
        std::size_t offset,
        std::size_t step)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * output_axis_size;
        if (flat >= total)
        {
            return;
        }
        const std::size_t line = flat / output_axis_size;
        const std::size_t index = flat % output_axis_size;
        output[output_bases[line] + index * output_axis_stride] =
            input[input_bases[line] + (offset + index * step) * input_axis_stride];
    }

    __global__ void copy_signal_segment_kernel(
        float *output,
        std::size_t output_size,
        std::size_t offset,
        const float *input,
        std::size_t input_size)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < input_size && index + offset < output_size)
        {
            output[index + offset] = input[index];
        }
    }

    __global__ void copy_scaled_signal_segment_kernel(
        float *output,
        std::size_t output_size,
        std::size_t offset,
        const float *input,
        std::size_t input_size,
        float scale)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < input_size && index + offset < output_size)
        {
            output[index + offset] = input[index] * scale;
        }
    }

    __global__ void upfirdn_kernel(
        const float *h,
        std::size_t h_size,
        const float *input,
        const std::size_t *input_bases,
        std::size_t input_axis_size,
        std::size_t input_axis_stride,
        float *output,
        const std::size_t *output_bases,
        std::size_t output_axis_size,
        std::size_t output_axis_stride,
        std::size_t line_count,
        int up,
        int down)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = line_count * output_axis_size;
        if (flat >= total)
        {
            return;
        }
        const std::size_t line = flat / output_axis_size;
        const std::size_t out_index = flat % output_axis_size;
        const std::size_t in_base = input_bases[line];
        const std::size_t out_base = output_bases[line];
        const long long conv_index = static_cast<long long>(out_index) * down;
        float value = 0.0;
        const long long max_tap = static_cast<long long>(h_size) - 1;
        const long long tap_limit = max_tap < conv_index ? max_tap : conv_index;
        const long long tap_start = conv_index % up;
        for (long long tap = tap_start; tap <= tap_limit; tap += up)
        {
            const long long input_index = (conv_index - tap) / up;
            if (input_index >= 0 && input_index < static_cast<long long>(input_axis_size))
            {
                value += h[static_cast<std::size_t>(tap)] *
                         input[in_base + static_cast<std::size_t>(input_index) * input_axis_stride];
            }
        }
        output[out_base + out_index * output_axis_stride] = value;
    }

    __global__ void channelize_poly_kernel(
        const float2 *x,
        std::size_t x_size,
        const float *h,
        std::size_t h_size,
        int n_chans,
        std::size_t n_pts,
        float2 *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = n_pts * static_cast<std::size_t>(n_chans);
        if (flat >= total)
        {
            return;
        }

        const std::size_t point = flat / static_cast<std::size_t>(n_chans);
        const std::size_t channel = flat % static_cast<std::size_t>(n_chans);
        const std::size_t taps_per_phase = h_size / static_cast<std::size_t>(n_chans);

        float2 sum = make_complex(0.0, 0.0);
        for (std::size_t phase = 0; phase < static_cast<std::size_t>(n_chans); ++phase)
        {
            float2 accum = make_complex(0.0, 0.0);
            for (std::size_t tap = 0; tap < taps_per_phase; ++tap)
            {
                const long long sample_index =
                    static_cast<long long>(point * static_cast<std::size_t>(n_chans) + phase) -
                    static_cast<long long>(tap * static_cast<std::size_t>(n_chans));
                if (sample_index >= 0 && sample_index < static_cast<long long>(x_size))
                {
                    const float coeff = h[tap * static_cast<std::size_t>(n_chans) + phase];
                    const float2 sample = x[static_cast<std::size_t>(sample_index)];
                    accum.x = rn_madd(accum.x, sample.x, coeff);
                    accum.y = rn_madd(accum.y, sample.y, coeff);
                }
            }
            const float angle =
                -2.0 * kPi * static_cast<float>(channel * phase) / static_cast<float>(n_chans);
            const float2 twiddle = make_complex(cos(angle), sin(angle));
            const float real_part =
                __fsub_rn(__fmul_rn(accum.x, twiddle.x), __fmul_rn(accum.y, twiddle.y));
            const float imag_part =
                __fadd_rn(__fmul_rn(accum.x, twiddle.y), __fmul_rn(accum.y, twiddle.x));
            sum.x = __fadd_rn(sum.x, real_part);
            sum.y = __fadd_rn(sum.y, imag_part);
        }
        output[flat] = sum;
    }

    __global__ void channelize_poly_channels8_point_kernel(
        const float2 *x,
        std::size_t x_size,
        const float *h,
        std::size_t h_size,
        std::size_t n_pts,
        float2 *output)
    {
        constexpr std::size_t channels =
            static_cast<std::size_t>(kChannelizeSharedChannels);
        __shared__ float2 twiddles[kChannelizeSharedChannels * kChannelizeSharedChannels];

        const std::size_t twiddle_index = threadIdx.x;
        if (twiddle_index < channels * channels)
        {
            const std::size_t channel = twiddle_index / channels;
            const std::size_t phase = twiddle_index % channels;
            const float angle =
                -2.0 * kPi * static_cast<float>(channel * phase) /
                static_cast<float>(channels);
            twiddles[twiddle_index] = make_complex(cos(angle), sin(angle));
        }
        __syncthreads();

        const std::size_t point =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (point >= n_pts)
        {
            return;
        }

        float2 sums[kChannelizeSharedChannels];
#pragma unroll
        for (int channel = 0; channel < kChannelizeSharedChannels; ++channel)
        {
            sums[channel] = make_complex(0.0, 0.0);
        }

        const std::size_t taps_per_phase = h_size / channels;
        for (std::size_t phase = 0; phase < channels; ++phase)
        {
            float2 accum = make_complex(0.0, 0.0);
            for (std::size_t tap = 0; tap < taps_per_phase; ++tap)
            {
                const long long sample_index =
                    static_cast<long long>(point * channels + phase) -
                    static_cast<long long>(tap * channels);
                if (sample_index >= 0 && sample_index < static_cast<long long>(x_size))
                {
                    const float coeff = h[tap * channels + phase];
                    const float2 sample = x[static_cast<std::size_t>(sample_index)];
                    accum.x = rn_madd(accum.x, sample.x, coeff);
                    accum.y = rn_madd(accum.y, sample.y, coeff);
                }
            }

#pragma unroll
            for (int channel = 0; channel < kChannelizeSharedChannels; ++channel)
            {
                const float2 twiddle =
                    twiddles[static_cast<std::size_t>(channel) * channels + phase];
                const float real_part =
                    __fsub_rn(__fmul_rn(accum.x, twiddle.x), __fmul_rn(accum.y, twiddle.y));
                const float imag_part =
                    __fadd_rn(__fmul_rn(accum.x, twiddle.y), __fmul_rn(accum.y, twiddle.x));
                sums[channel].x = __fadd_rn(sums[channel].x, real_part);
                sums[channel].y = __fadd_rn(sums[channel].y, imag_part);
            }
        }

#pragma unroll
        for (int channel = 0; channel < kChannelizeSharedChannels; ++channel)
        {
            output[point * channels + static_cast<std::size_t>(channel)] = sums[channel];
        }
    }

    __global__ void pack_real_array_to_complex_kernel(
        const float *input,
        std::size_t input_rows,
        std::size_t input_cols,
        int output_rows,
        int output_cols,
        cufftComplex *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(output_rows) * static_cast<std::size_t>(output_cols);
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / static_cast<std::size_t>(output_cols);
        const std::size_t col = flat % static_cast<std::size_t>(output_cols);
        if (row < input_rows && col < input_cols)
        {
            output[flat] = make_complex(input[row * input_cols + col], 0.0);
        }
        else
        {
            output[flat] = make_complex(0.0, 0.0);
        }
    }

    __global__ void apply_hilbert2_mask_kernel(
        cufftComplex *spectrum,
        int rows,
        int cols)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(rows) * static_cast<std::size_t>(cols);
        if (flat >= total)
        {
            return;
        }
        const int row = static_cast<int>(flat / static_cast<std::size_t>(cols));
        const int col = static_cast<int>(flat % static_cast<std::size_t>(cols));
        const int k0 = (rows + 1) / 2;
        const int k1 = (cols + 1) / 2;
        if (row >= k0 || col >= k1)
        {
            spectrum[flat] = make_complex(0.0, 0.0);
            return;
        }
        float scale = 1.0;
        if (row >= 1 && row < k0)
        {
            scale *= 2.0;
        }
        if (col >= 1 && col < k1)
        {
            scale *= 2.0;
        }
        spectrum[flat].x *= scale;
        spectrum[flat].y *= scale;
    }

    __global__ void copy_complex_buffer_kernel(
        const cufftComplex *input,
        float2 *output,
        std::size_t size,
        float scale)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            output[index] = make_complex(input[index].x * scale, input[index].y * scale);
        }
    }

    ZxGpuRealSignal lfilter_zi_impl(const ZxGpuRealSignal &b, const ZxGpuRealSignal &a)
    {
        const std::size_t normalized_a_size = a.size();
        const std::size_t n = std::max(b.size(), normalized_a_size);
        if (n == 0)
        {
            throw std::invalid_argument("a must not be empty");
        }
        const std::size_t order = n - 1;
        if (order > kMaxLfilterZiOrder)
        {
            throw std::invalid_argument("filter order exceeds CUDA zi solver limit");
        }
        if (order == 0)
        {
            return ZxGpuRealSignal{};
        }

        ZxGpuRealSignal output(order, true);
        g_workspace.matrix_buffer.reserve(order * order);
        g_workspace.scalar_buffer_a.reserve(order);
        solve_lfilter_zi_kernel<<<1, kThreadsPerBlock>>>(
            b.data(),
            b.size(),
            a.data(),
            a.size(),
            output.data(),
            g_workspace.matrix_buffer.get(),
            g_workspace.scalar_buffer_a.get());
        check_kernel_launch("solve_lfilter_zi_kernel");
        return output;
    }

    ZxGpuRealArray sosfilt_prefix_scan_impl(
        const ZxGpuRealArray &sos,
        const ZxGpuRealArray &x,
        const detail::AxisPlan &plan,
        const float *initial_state = nullptr,
        const float *scale_input = nullptr);

    ZxGpuRealArray lfilter_impl(
        const ZxGpuRealSignal &b,
        const ZxGpuRealSignal &a,
        const ZxGpuRealArray &x,
        int axis,
        const ZxGpuRealArray *zi,
        ZxGpuRealArray *final_state,
        const char *operator_id = nullptr)
    {
        const detail::AxisPlan plan = detail::make_axis_plan(x.shape(), axis);
        const std::size_t order = std::max(b.size(), a.size()) - 1;
        if (order > kMaxFilterOrder)
        {
            throw std::invalid_argument("filter order exceeds CUDA lfilter limit");
        }
        tile::PolicyDecision tuning;
        if (operator_id != nullptr)
        {
            tuning = tile::select(
                tile::make_fir_filter_key(
                    operator_id,
                    plan.line_count,
                    plan.axis_size,
                    0,
                    order,
                    axis,
                    b.size(),
                    a.size(),
                    zi != nullptr || final_state != nullptr,
                    plan.axis_stride));
        }
        else
        {
            tuning.config = tile::candidate_config(
                tile::static_candidate(tile::OperatorFamily::FirFilter));
        }
        const tile::ScopedPolicy policy_scope(tuning);

        if (zi == nullptr &&
            final_state == nullptr &&
            tile::optimized_path() &&
            order <= 2 &&
            b.size() <= 3 &&
            a.size() <= 3)
        {
            const detail::AxisPlan plan = detail::make_axis_plan(x.shape(), axis);
            if (plan.line_count == 1 &&
                plan.axis_stride == 1 &&
                plan.axis_size >= 1024)
            {
                g_workspace.real_array_e.resize(Shape{1, 6}, false);
                build_single_sos_from_ba_kernel<<<1, 1>>>(
                    b.data(),
                    b.size(),
                    a.data(),
                    a.size(),
                    g_workspace.real_array_e.data());
                check_kernel_launch("build_single_sos_from_ba_kernel");
                return sosfilt_prefix_scan_impl(g_workspace.real_array_e, x, plan);
            }
        }

        const std::size_t *line_bases = upload_line_bases_cached(
            x.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(line_bases)");

        ZxGpuRealArray output(x.shape(), false);

        if (zi == nullptr &&
            final_state == nullptr &&
            a.size() == 1 &&
            b.size() <= static_cast<std::size_t>(kMaxFilterOrder + 1))
        {
            if (tile::optimized_path() &&
                plan.axis_stride == 1 &&
                plan.axis_size >= 1024 &&
                plan.line_count <= kMaxSharedFirLines)
            {
                const int plan_variant = tuning.config.plan_variant;
                const int outputs_per_thread = plan_variant == 0 ? 2 : plan_variant;
                const std::size_t kOutputsPerBlock =
                    static_cast<std::size_t>(outputs_per_thread) *
                    static_cast<std::size_t>(kThreadsPerBlock);
                const dim3 grid(
                    static_cast<unsigned int>(tile::ceil_div(plan.axis_size, kOutputsPerBlock)),
                    static_cast<unsigned int>(plan.line_count));
                const std::size_t shared_bytes =
                    (kOutputsPerBlock + b.size() - 1) * sizeof(float) + b.size() * sizeof(float);
                if (plan_variant == 0)
                {
                    fir_filter_zero_lines_shared_dual_kernel<<<grid, kThreadsPerBlock, shared_bytes>>>(
                        b.data(),
                        b.size(),
                        a.data()[0],
                        x.data(),
                        line_bases,
                        plan.line_count,
                        plan.axis_size,
                        plan.axis_stride,
                        output.data());
                    check_kernel_launch("fir_filter_zero_lines_shared_dual_kernel");
                }
                else if (plan_variant == 1)
                {
                    fir_filter_zero_lines_shared_multi_kernel<1><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        b.data(), b.size(), a.data()[0], x.data(), line_bases,
                        plan.line_count, plan.axis_size, plan.axis_stride, output.data());
                    check_kernel_launch("fir_filter_zero_lines_shared_multi_kernel<1>");
                }
                else if (plan_variant == 2)
                {
                    fir_filter_zero_lines_shared_multi_kernel<2><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        b.data(), b.size(), a.data()[0], x.data(), line_bases,
                        plan.line_count, plan.axis_size, plan.axis_stride, output.data());
                    check_kernel_launch("fir_filter_zero_lines_shared_multi_kernel<2>");
                }
                else if (plan_variant == 4)
                {
                    fir_filter_zero_lines_shared_multi_kernel<4><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        b.data(), b.size(), a.data()[0], x.data(), line_bases,
                        plan.line_count, plan.axis_size, plan.axis_stride, output.data());
                    check_kernel_launch("fir_filter_zero_lines_shared_multi_kernel<4>");
                }
                else
                {
                    fir_filter_zero_lines_shared_multi_kernel<8><<<grid, kThreadsPerBlock, shared_bytes>>>(
                        b.data(), b.size(), a.data()[0], x.data(), line_bases,
                        plan.line_count, plan.axis_size, plan.axis_stride, output.data());
                    check_kernel_launch("fir_filter_zero_lines_shared_multi_kernel<8>");
                }
            }
            else
            {
                fir_filter_zero_lines_kernel<<<
                    block_count(plan.line_count * plan.axis_size),
                    kThreadsPerBlock>>>(
                    b.data(),
                    b.size(),
                    a.data(),
                    x.data(),
                    line_bases,
                    plan.line_count,
                    plan.axis_size,
                    plan.axis_stride,
                    output.data());
                check_kernel_launch("fir_filter_zero_lines_kernel");
            }
            return output;
        }

        const std::size_t *zi_bases = nullptr;
        std::size_t zi_axis_stride = 1;
        const std::size_t *zf_bases = nullptr;
        std::size_t zf_axis_stride = 1;
        if (zi != nullptr)
        {
            if (zi->shape() != detail::state_shape_for_filter(x.shape(), axis, order))
            {
                throw std::invalid_argument("zi has invalid shape for filter state");
            }
            const detail::AxisPlan zi_plan = detail::make_axis_plan(zi->shape(), axis);
            zi_bases = upload_line_bases_cached(
                zi->shape(),
                axis,
                g_workspace.size_buffer_b,
                g_workspace.line_bases_cache_b,
                "cudaMemcpy H2D(zi_bases)");
            zi_axis_stride = zi_plan.axis_stride;
        }

        if (final_state != nullptr)
        {
            *final_state = ZxGpuRealArray(detail::state_shape_for_filter(x.shape(), axis, order), false);
            const detail::AxisPlan zf_plan = detail::make_axis_plan(final_state->shape(), axis);
            zf_bases = upload_line_bases_cached(
                final_state->shape(),
                axis,
                g_workspace.size_buffer_c,
                g_workspace.line_bases_cache_c,
                "cudaMemcpy H2D(zf_bases)");
            zf_axis_stride = zf_plan.axis_stride;
        }

        lfilter_line_kernel<<<block_count(plan.line_count), kThreadsPerBlock>>>(
            b.data(),
            b.size(),
            a.data(),
            a.size(),
            x.data(),
            line_bases,
            plan.line_count,
            plan.axis_size,
            plan.axis_stride,
            output.data(),
            zi != nullptr ? zi->data() : nullptr,
            zi_bases,
            zi_axis_stride,
            nullptr,
            false,
            final_state != nullptr ? final_state->data() : nullptr,
            zf_bases,
            zf_axis_stride);
        check_kernel_launch("lfilter_line_kernel");
        return output;
    }

    ZxGpuRealArray sosfilt_prefix_scan_impl(
        const ZxGpuRealArray &sos,
        const ZxGpuRealArray &x,
        const detail::AxisPlan &plan,
        const float *initial_state,
        const float *scale_input)
    {
        const int tile_count = block_count(plan.axis_size);
        const int tile_scan_block_count = block_count(static_cast<std::size_t>(tile_count));
        const std::size_t n_sections = sos.shape()[0];

        ZxGpuRealArray output(x.shape(), false);
        g_workspace.matrix_buffer.reserve(plan.axis_size * 2);
        g_workspace.scalar_buffer_a.reserve(static_cast<std::size_t>(tile_count) * 6);
        g_workspace.real_signal_a.resize(static_cast<std::size_t>(tile_count) * 6);
        g_workspace.real_signal_b.resize(static_cast<std::size_t>(tile_scan_block_count) * 6);
        g_workspace.real_signal_c.resize(static_cast<std::size_t>(tile_scan_block_count) * 2);

        const float *section_input = x.data();
        for (std::size_t section = 0; section < n_sections; ++section)
        {
            sosfilt_prefix_tiles_kernel<<<tile_count, kThreadsPerBlock>>>(
                sos.data(),
                section,
                section_input,
                plan.axis_size,
                output.data(),
                g_workspace.matrix_buffer.get(),
                g_workspace.scalar_buffer_a.get());
            check_kernel_launch("sosfilt_prefix_tiles_kernel");

            sosfilt_scan_tile_transform_blocks_kernel<<<tile_scan_block_count, kThreadsPerBlock>>>(
                g_workspace.scalar_buffer_a.get(),
                tile_count,
                g_workspace.real_signal_a.data(),
                g_workspace.real_signal_b.data());
            check_kernel_launch("sosfilt_scan_tile_transform_blocks_kernel");

            sosfilt_scan_block_transforms_kernel<<<1, 1>>>(
                g_workspace.real_signal_b.data(),
                tile_scan_block_count,
                g_workspace.real_signal_c.data(),
                initial_state,
                scale_input);
            check_kernel_launch("sosfilt_scan_block_transforms_kernel");

            sosfilt_apply_block_prefix_to_samples_kernel<<<tile_count, kThreadsPerBlock>>>(
                g_workspace.real_signal_a.data(),
                g_workspace.real_signal_c.data(),
                g_workspace.matrix_buffer.get(),
                plan.axis_size,
                output.data());
            check_kernel_launch("sosfilt_apply_block_prefix_to_samples_kernel");

            section_input = output.data();
        }
        return output;
    }

    ZxGpuRealArray sosfilt_impl(
        const ZxGpuRealArray &sos,
        const ZxGpuRealArray &x,
        int axis,
        const ZxGpuRealArray *zi,
        ZxGpuRealArray *final_state)
    {
        if (sos.rank() != 2 || sos.shape()[1] != 6)
        {
            throw std::invalid_argument("sos must have shape [n_sections, 6]");
        }
        const std::size_t n_sections = sos.shape()[0];
        if (n_sections > kMaxSosSections)
        {
            throw std::invalid_argument("sos section count exceeds CUDA sosfilt limit");
        }

        const detail::AxisPlan plan = detail::make_axis_plan(x.shape(), axis);
        if (zi == nullptr &&
            final_state == nullptr &&
            tile::optimized_path() &&
            plan.line_count == 1 &&
            plan.axis_stride == 1 &&
            plan.axis_size >= 1024)
        {
            return sosfilt_prefix_scan_impl(sos, x, plan);
        }

        const std::size_t *line_bases = upload_line_bases_cached(
            x.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(line_bases)");
        ZxGpuRealArray output(x.shape(), false);

        const std::size_t *zi_line_bases = nullptr;
        const std::size_t *zi_section_bases = nullptr;
        std::size_t zi_axis_stride = 1;
        const std::size_t *zf_line_bases = nullptr;
        const std::size_t *zf_section_bases = nullptr;
        std::size_t zf_axis_stride = 1;

        if (zi != nullptr)
        {
            if (zi->shape() != detail::sos_state_shape(x.shape(), axis, n_sections))
            {
                throw std::invalid_argument("zi has invalid shape for sosfilt");
            }
            Shape line_shape = x.shape();
            line_shape[core::normalize_axis(axis, line_shape.size())] = 1;
            std::vector<std::size_t> section_bases(n_sections, 0);
            const std::vector<std::size_t> zi_strides = detail::compute_strides(zi->shape());
            for (std::size_t section = 0; section < n_sections; ++section)
            {
                section_bases[section] = section * zi_strides[0];
            }
            zi_line_bases = upload_line_bases_cached(
                line_shape,
                axis,
                g_workspace.size_buffer_b,
                g_workspace.line_bases_cache_b,
                "cudaMemcpy H2D(sos_zi_line_bases)");
            upload_size_vector(section_bases, g_workspace.size_buffer_c, "cudaMemcpy H2D(sos_zi_section_bases)");
            zi_section_bases = g_workspace.size_buffer_c.get();
            zi_axis_stride = zi_strides[1 + core::normalize_axis(axis, x.rank())];
        }

        if (final_state != nullptr)
        {
            *final_state = ZxGpuRealArray(detail::sos_state_shape(x.shape(), axis, n_sections), false);
            Shape line_shape = x.shape();
            line_shape[core::normalize_axis(axis, line_shape.size())] = 1;
            std::vector<std::size_t> section_bases(n_sections, 0);
            const std::vector<std::size_t> zf_strides = detail::compute_strides(final_state->shape());
            for (std::size_t section = 0; section < n_sections; ++section)
            {
                section_bases[section] = section * zf_strides[0];
            }
            zf_line_bases = upload_line_bases_cached(
                line_shape,
                axis,
                g_workspace.size_buffer_d,
                g_workspace.line_bases_cache_d,
                "cudaMemcpy H2D(sos_zf_line_bases)");
            upload_size_vector(section_bases, g_workspace.size_buffer_c, "cudaMemcpy H2D(sos_zf_section_bases)");
            zf_section_bases = g_workspace.size_buffer_c.get();
            zf_axis_stride = zf_strides[1 + core::normalize_axis(axis, x.rank())];
        }

        sosfilt_line_kernel<<<block_count(plan.line_count), kThreadsPerBlock>>>(
            sos.data(),
            n_sections,
            x.data(),
            line_bases,
            plan.line_count,
            plan.axis_size,
            plan.axis_stride,
            output.data(),
            zi != nullptr ? zi->data() : nullptr,
            zi_line_bases,
            zi_section_bases,
            zi_axis_stride,
            final_state != nullptr ? final_state->data() : nullptr,
            zf_line_bases,
            zf_section_bases,
            zf_axis_stride);
        check_kernel_launch("sosfilt_line_kernel");
        return output;
    }

    ZxGpuRealArray pad_and_filtfilt_impl(
        const ZxGpuRealSignal &b,
        const ZxGpuRealSignal &a,
        const ZxGpuRealArray &x,
        int axis,
        const std::string &padtype,
        int padlen)
    {
        const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape(), axis);
        std::size_t edge = padtype == "none"
                               ? 0
                               : (padlen < 0 ? 3 * (std::max(a.size(), b.size()) - 1)
                                             : static_cast<std::size_t>(padlen));
        if (edge != 0 && input_plan.axis_size <= edge)
        {
            throw std::invalid_argument("The length of the input vector x must be greater than padlen.");
        }

        const int mode = pad_mode_from_string(detail::normalize_padtype(padtype));
        const Shape padded_shape = core::replace_axis_size(x.shape(), axis, input_plan.axis_size + 2 * edge);
        const detail::AxisPlan padded_plan = detail::make_axis_plan(padded_shape, axis);
        const std::size_t *input_bases = upload_line_bases_cached(
            x.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(input_bases)");
        const std::size_t *padded_bases = upload_line_bases_cached(
            padded_shape,
            axis,
            g_workspace.size_buffer_b,
            g_workspace.line_bases_cache_b,
            "cudaMemcpy H2D(padded_bases)");

        ZxGpuRealArray padded(padded_shape, false);
        pad_lines_kernel<<<block_count(padded_plan.line_count * padded_plan.axis_size), kThreadsPerBlock>>>(
            x.data(),
            input_bases,
            input_plan.axis_size,
            input_plan.axis_stride,
            padded.data(),
            padded_bases,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            padded_plan.line_count,
            edge,
            mode);
        check_kernel_launch("pad_lines_kernel");

        const ZxGpuRealSignal zi_template = lfilter_zi_impl(b, a);
        const std::size_t order = std::max(b.size(), a.size()) - 1;
        const bool use_sos_prefix_scan =
            order == 2 &&
            b.size() <= 3 &&
            a.size() <= 3 &&
            padded_plan.line_count == 1 &&
            padded_plan.axis_stride == 1 &&
            padded_plan.axis_size >= 1024;
        if (use_sos_prefix_scan)
        {
            g_workspace.real_array_e.resize(Shape{1, 6}, false);
            build_single_sos_from_ba_kernel<<<1, 1>>>(
                b.data(),
                b.size(),
                a.data(),
                a.size(),
                g_workspace.real_array_e.data());
            check_kernel_launch("build_single_sos_from_ba_kernel(filtfilt)");
        }

        ZxGpuRealArray forward(padded_shape, false);
        if (use_sos_prefix_scan)
        {
            forward = sosfilt_prefix_scan_impl(
                g_workspace.real_array_e,
                padded,
                padded_plan,
                zi_template.data(),
                padded.data());
        }
        else
        {
            lfilter_line_kernel<<<block_count(padded_plan.line_count), kThreadsPerBlock>>>(
                b.data(),
                b.size(),
                a.data(),
                a.size(),
                padded.data(),
                padded_bases,
                padded_plan.line_count,
                padded_plan.axis_size,
                padded_plan.axis_stride,
                forward.data(),
                nullptr,
                nullptr,
                1,
                zi_template.empty() ? nullptr : zi_template.data(),
                true,
                nullptr,
                nullptr,
                1);
            check_kernel_launch("lfilter_line_kernel forward");
        }

        ZxGpuRealArray reversed(padded_shape, false);
        reverse_lines_kernel<<<block_count(padded_plan.line_count * padded_plan.axis_size), kThreadsPerBlock>>>(
            forward.data(),
            padded_bases,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            reversed.data(),
            padded_bases,
            padded_plan.axis_stride,
            padded_plan.line_count);
        check_kernel_launch("reverse_lines_kernel forward");

        ZxGpuRealArray backward(padded_shape, false);
        if (use_sos_prefix_scan)
        {
            backward = sosfilt_prefix_scan_impl(
                g_workspace.real_array_e,
                reversed,
                padded_plan,
                zi_template.data(),
                reversed.data());
        }
        else
        {
            lfilter_line_kernel<<<block_count(padded_plan.line_count), kThreadsPerBlock>>>(
                b.data(),
                b.size(),
                a.data(),
                a.size(),
                reversed.data(),
                padded_bases,
                padded_plan.line_count,
                padded_plan.axis_size,
                padded_plan.axis_stride,
                backward.data(),
                nullptr,
                nullptr,
                1,
                zi_template.empty() ? nullptr : zi_template.data(),
                true,
                nullptr,
                nullptr,
                1);
            check_kernel_launch("lfilter_line_kernel backward");
        }

        reverse_lines_kernel<<<block_count(padded_plan.line_count * padded_plan.axis_size), kThreadsPerBlock>>>(
            backward.data(),
            padded_bases,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            reversed.data(),
            padded_bases,
            padded_plan.axis_stride,
            padded_plan.line_count);
        check_kernel_launch("reverse_lines_kernel final");

        if (edge == 0)
        {
            return reversed;
        }

        ZxGpuRealArray output(x.shape(), false);
        crop_lines_kernel<<<block_count(input_plan.line_count * input_plan.axis_size), kThreadsPerBlock>>>(
            reversed.data(),
            padded_bases,
            padded_plan.axis_stride,
            output.data(),
            input_bases,
            input_plan.axis_size,
            input_plan.axis_stride,
            input_plan.line_count,
            edge);
        check_kernel_launch("crop_lines_kernel");
        return output;
    }

    ZxGpuRealArray pad_and_firfiltfilt_impl(
        const ZxGpuRealSignal &b,
        const ZxGpuRealArray &x,
        int axis,
        const std::string &padtype,
        int padlen)
    {
        const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape(), axis);
        const std::size_t edge = padtype == "none"
                                     ? 0
                                     : (padlen < 0 ? 3 * (b.size() - 1)
                                                   : static_cast<std::size_t>(padlen));
        if (edge != 0 && input_plan.axis_size <= edge)
        {
            throw std::invalid_argument("The length of the input vector x must be greater than padlen.");
        }

        const int mode = pad_mode_from_string(detail::normalize_padtype(padtype));
        const Shape padded_shape = core::replace_axis_size(x.shape(), axis, input_plan.axis_size + 2 * edge);
        const detail::AxisPlan padded_plan = detail::make_axis_plan(padded_shape, axis);
        const std::size_t *input_bases = upload_line_bases_cached(
            x.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(input_bases)");
        const std::size_t *padded_bases = upload_line_bases_cached(
            padded_shape,
            axis,
            g_workspace.size_buffer_b,
            g_workspace.line_bases_cache_b,
            "cudaMemcpy H2D(padded_bases)");

        ZxGpuRealArray padded(padded_shape, false);
        pad_lines_kernel<<<block_count(padded_plan.line_count * padded_plan.axis_size), kThreadsPerBlock>>>(
            x.data(),
            input_bases,
            input_plan.axis_size,
            input_plan.axis_stride,
            padded.data(),
            padded_bases,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            padded_plan.line_count,
            edge,
            mode);
        check_kernel_launch("pad_lines_kernel(fir)");

        ZxGpuRealArray forward(padded_shape, false);
        fir_filter_clamped_lines_kernel<<<
            block_count(padded_plan.line_count * padded_plan.axis_size),
            kThreadsPerBlock>>>(
            b.data(),
            b.size(),
            padded.data(),
            padded_bases,
            padded_plan.line_count,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            forward.data());
        check_kernel_launch("fir_filter_clamped_lines_kernel forward");

        const bool use_direct_reverse =
            g_firfilter2_path_override == kFirfilter2PathDirect ||
            (g_firfilter2_path_override == kFirfilter2PathAuto &&
             b.size() == kFirfilter2DirectTaps &&
             input_plan.line_count == 1 &&
             input_plan.axis_stride == 1 &&
             input_plan.axis_size >= kFirfilter2DirectMinAxisSize);
        g_last_firfilter2_path =
            use_direct_reverse ? kFirfilter2PathDirect : kFirfilter2PathGeneric;
        if (use_direct_reverse)
        {
            ZxGpuRealArray output(x.shape(), false);
            fir_filter_reverse_clamped_crop_lines_kernel<<<
                block_count(input_plan.line_count * input_plan.axis_size),
                kThreadsPerBlock>>>(
                b.data(),
                b.size(),
                forward.data(),
                padded_bases,
                padded_plan.axis_size,
                padded_plan.axis_stride,
                output.data(),
                input_bases,
                input_plan.axis_size,
                input_plan.axis_stride,
                input_plan.line_count,
                edge);
            check_kernel_launch("fir_filter_reverse_clamped_crop_lines_kernel");
            return output;
        }

        ZxGpuRealArray reversed(padded_shape, false);
        reverse_lines_kernel<<<block_count(padded_plan.line_count * padded_plan.axis_size), kThreadsPerBlock>>>(
            forward.data(),
            padded_bases,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            reversed.data(),
            padded_bases,
            padded_plan.axis_stride,
            padded_plan.line_count);
        check_kernel_launch("reverse_lines_kernel forward(fir)");

        ZxGpuRealArray backward(padded_shape, false);
        fir_filter_clamped_lines_kernel<<<
            block_count(padded_plan.line_count * padded_plan.axis_size),
            kThreadsPerBlock>>>(
            b.data(),
            b.size(),
            reversed.data(),
            padded_bases,
            padded_plan.line_count,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            backward.data());
        check_kernel_launch("fir_filter_clamped_lines_kernel backward");

        reverse_lines_kernel<<<block_count(padded_plan.line_count * padded_plan.axis_size), kThreadsPerBlock>>>(
            backward.data(),
            padded_bases,
            padded_plan.axis_size,
            padded_plan.axis_stride,
            reversed.data(),
            padded_bases,
            padded_plan.axis_stride,
            padded_plan.line_count);
        check_kernel_launch("reverse_lines_kernel final(fir)");

        if (edge == 0)
        {
            return reversed;
        }

        ZxGpuRealArray output(x.shape(), false);
        crop_lines_kernel<<<block_count(input_plan.line_count * input_plan.axis_size), kThreadsPerBlock>>>(
            reversed.data(),
            padded_bases,
            padded_plan.axis_stride,
            output.data(),
            input_bases,
            input_plan.axis_size,
            input_plan.axis_stride,
            input_plan.line_count,
            edge);
        check_kernel_launch("crop_lines_kernel(fir)");
        return output;
    }

    ZxGpuComplexArray hilbert_impl(const ZxGpuRealArray &x, int n, int axis)
    {
        const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape(), axis);
        const int target = n > 0 ? n : static_cast<int>(input_plan.axis_size);
        const Shape output_shape = core::replace_axis_size(x.shape(), axis, static_cast<std::size_t>(target));
        const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
        const std::size_t *input_bases = upload_line_bases_cached(
            x.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(input_bases)");
        const std::size_t *output_bases = upload_line_bases_cached(
            output_shape,
            axis,
            g_workspace.size_buffer_b,
            g_workspace.line_bases_cache_b,
            "cudaMemcpy H2D(output_bases)");

        ZxGpuComplexArray output(output_shape, false);
        g_workspace.ensure_plan1d_a(static_cast<int>(target));
        g_workspace.complex_signal_a.resize(static_cast<std::size_t>(target));

        for (std::size_t line = 0; line < input_plan.line_count; ++line)
        {
            gather_real_line_to_complex_kernel<<<block_count(static_cast<std::size_t>(target)), kThreadsPerBlock>>>(
                x.data(),
                input_bases,
                input_plan.axis_stride,
                line,
                input_plan.axis_size,
                static_cast<std::size_t>(target),
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()));
            check_kernel_launch("gather_real_line_to_complex_kernel");

            throw_on_cufft_error(
                cufftExecC2C(
                    g_workspace.plan1d_a,
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    CUFFT_FORWARD),
                "cufftExecC2C(hilbert forward)");

            apply_hilbert_mask_kernel<<<block_count(static_cast<std::size_t>(target)), kThreadsPerBlock>>>(
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                target);
            check_kernel_launch("apply_hilbert_mask_kernel");

            throw_on_cufft_error(
                cufftExecC2C(
                    g_workspace.plan1d_a,
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    CUFFT_INVERSE),
                "cufftExecC2C(hilbert inverse)");

            scatter_complex_line_kernel<<<block_count(static_cast<std::size_t>(target)), kThreadsPerBlock>>>(
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                output.data(),
                output_bases,
                output_plan.axis_stride,
                line,
                static_cast<std::size_t>(target),
                1.0 / static_cast<float>(target));
            check_kernel_launch("scatter_complex_line_kernel");
        }
        return output;
    }

    ZxGpuComplexArray hilbert2_impl(const ZxGpuRealArray &x, const Shape &n)
    {
        if (x.rank() != 2)
        {
            throw std::invalid_argument("x must be rank-2 for hilbert2");
        }
        const Shape target = n.empty() ? x.shape() : n;
        if (target.size() != 2)
        {
            throw std::invalid_argument("n must be empty or hold exactly two dimensions");
        }

        const int rows = static_cast<int>(target[0]);
        const int cols = static_cast<int>(target[1]);
        g_workspace.ensure_plan2d(rows, cols);
        g_workspace.complex_signal_a.resize(static_cast<std::size_t>(rows) * static_cast<std::size_t>(cols));

        pack_real_array_to_complex_kernel<<<block_count(g_workspace.complex_signal_a.size()), kThreadsPerBlock>>>(
            x.data(),
            x.shape()[0],
            x.shape()[1],
            rows,
            cols,
            reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()));
        check_kernel_launch("pack_real_array_to_complex_kernel");

        throw_on_cufft_error(
            cufftExecC2C(
                g_workspace.plan2d,
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                CUFFT_FORWARD),
            "cufftExecC2C(hilbert2 forward)");

        apply_hilbert2_mask_kernel<<<block_count(g_workspace.complex_signal_a.size()), kThreadsPerBlock>>>(
            reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
            rows,
            cols);
        check_kernel_launch("apply_hilbert2_mask_kernel");

        throw_on_cufft_error(
            cufftExecC2C(
                g_workspace.plan2d,
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                CUFFT_INVERSE),
            "cufftExecC2C(hilbert2 inverse)");

        ZxGpuComplexArray output(target, false);
        copy_complex_buffer_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
            reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
            output.data(),
            output.size(),
            1.0 / static_cast<float>(rows * cols));
        check_kernel_launch("copy_complex_buffer_kernel");
        return output;
    }

    bool should_use_resample_windowed_pack(
        const detail::AxisPlan &input_plan,
        int output_size,
        const ZxGpuWindowSpec &window,
        const std::string &resolved_domain)
    {
        const auto *window_name = std::get_if<std::string>(&window);
        return resolved_domain == "time" &&
            window_name != nullptr && *window_name == "hann" &&
            input_plan.line_count == 1 && input_plan.axis_stride == 1 &&
            input_plan.axis_size == kResampleFusedInputSize &&
            output_size == kResampleFusedOutputSize;
    }

    ZxGpuRealArray resample_impl(
        const ZxGpuRealArray &x,
        int num,
        int axis,
        ZxGpuWindowSpec window,
        const std::string &domain)
    {
        validate_zx_gpu_window_spec(window);
        const std::string resolved_domain = detail::normalize_domain(domain);
        const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape(), axis);
        const Shape output_shape = core::replace_axis_size(x.shape(), axis, static_cast<std::size_t>(num));
        const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
        const std::size_t *input_bases = upload_line_bases_cached(
            x.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(input_bases)");
        const std::size_t *output_bases = upload_line_bases_cached(
            output_shape,
            axis,
            g_workspace.size_buffer_b,
            g_workspace.line_bases_cache_b,
            "cudaMemcpy H2D(output_bases)");

        ZxGpuRealArray output(output_shape, false);
        g_workspace.ensure_plan1d_a(static_cast<int>(input_plan.axis_size));
        g_workspace.ensure_plan1d_b(num);
        g_workspace.complex_signal_a.resize(input_plan.axis_size);
        g_workspace.complex_signal_b.resize(static_cast<std::size_t>(num));

        ZxGpuRealSignal window_storage;
        const ZxGpuRealSignal *explicit_window = explicit_window_signal(window, window_storage);
        const ZxGpuRealSignal *frequency_window = explicit_window;
        if (frequency_window == nullptr)
        {
            std::string window_cache_key;
            const bool cacheable_window =
                build_zx_gpu_window_cache_key(window, static_cast<int>(input_plan.axis_size), window_cache_key);
            if (cacheable_window)
            {
                if (!g_workspace.resample_window_valid ||
                    g_workspace.resample_window_key != window_cache_key)
                {
                    g_workspace.resample_window = cusignal::zx_gpu_backend::windows::get_window(
                        window,
                        static_cast<int>(input_plan.axis_size),
                        true);
                    g_workspace.resample_window_key = window_cache_key;
                    g_workspace.resample_window_valid = true;
                }
                frequency_window = &g_workspace.resample_window;
            }
        }

        const bool auto_uses_windowed_pack = should_use_resample_windowed_pack(
            input_plan, num, window, resolved_domain);
        if (explicit_window != nullptr && explicit_window->size() != input_plan.axis_size)
        {
            throw std::invalid_argument("window array length must equal axis length");
        }
        const float *pack_window = nullptr;
        int pack_window_mode = kResampleWindowNone;
        if (explicit_window != nullptr && explicit_window->size() != 0)
        {
            pack_window = explicit_window->data();
            pack_window_mode = kResampleWindowDirect;
        }
        else if (frequency_window != nullptr && frequency_window->size() != 0)
        {
            pack_window = frequency_window->data();
            pack_window_mode = kResampleWindowFftshift;
        }

        for (std::size_t line = 0; line < input_plan.line_count; ++line)
        {
            if (resolved_domain == "time")
            {
                gather_real_line_to_complex_kernel<<<block_count(input_plan.axis_size), kThreadsPerBlock>>>(
                    x.data(),
                    input_bases,
                    input_plan.axis_stride,
                    line,
                    input_plan.axis_size,
                    input_plan.axis_size,
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()));
                check_kernel_launch("gather_real_line_to_complex_kernel");

                throw_on_cufft_error(
                    cufftExecC2C(
                        g_workspace.plan1d_a,
                        reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                        reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                        CUFFT_FORWARD),
                    "cufftExecC2C(resample forward)");
            }
            else
            {
                gather_spectrum_line_kernel<<<block_count(input_plan.axis_size), kThreadsPerBlock>>>(
                    x.data(),
                    input_bases,
                    input_plan.axis_stride,
                    line,
                    input_plan.axis_size,
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()));
                check_kernel_launch("gather_spectrum_line_kernel");
            }

            const bool use_windowed_pack =
                tile::optimized_path() &&
                (g_resample_path_override == kResamplePathWindowedPack ||
                 (g_resample_path_override == kResamplePathAuto && auto_uses_windowed_pack));
            if (!use_windowed_pack && explicit_window != nullptr && explicit_window->size() != 0)
            {
                apply_window_direct_kernel<<<block_count(input_plan.axis_size), kThreadsPerBlock>>>(
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    explicit_window->data(),
                    static_cast<int>(input_plan.axis_size));
                check_kernel_launch("apply_window_direct_kernel");
            }
            else if (!use_windowed_pack && frequency_window != nullptr && frequency_window->size() != 0)
            {
                apply_window_fftshift_kernel<<<block_count(input_plan.axis_size), kThreadsPerBlock>>>(
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    frequency_window->data(),
                    static_cast<int>(input_plan.axis_size));
                check_kernel_launch("apply_window_fftshift_kernel");
            }

            const int n_x = static_cast<int>(input_plan.axis_size);
            const int m = std::min(num, n_x);
            const int m2 = m / 2 + 1;
            const bool use_fused_pack =
                tile::optimized_path() &&
                (use_windowed_pack ||
                 g_resample_path_override == kResamplePathFused ||
                 (g_resample_path_override == kResamplePathAuto && auto_uses_windowed_pack));
            g_last_resample_path =
                use_windowed_pack
                    ? kResamplePathWindowedPack
                    : (use_fused_pack ? kResamplePathFused : kResamplePathGeneric);
            if (use_fused_pack)
            {
                resample_pack_spectrum_kernel<<<block_count(static_cast<std::size_t>(num)), kThreadsPerBlock>>>(
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                    num,
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    n_x,
                    use_windowed_pack ? pack_window : nullptr,
                    use_windowed_pack ? pack_window_mode : kResampleWindowNone);
                check_kernel_launch("resample_pack_spectrum_kernel");
            }
            else
            {
                zero_complex_kernel<<<block_count(static_cast<std::size_t>(num)), kThreadsPerBlock>>>(
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                    num);
                check_kernel_launch("zero_complex_kernel");

                resample_copy_low_kernel<<<block_count(static_cast<std::size_t>(m2)), kThreadsPerBlock>>>(
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    m2);
                check_kernel_launch("resample_copy_low_kernel");

                if (m2 < m)
                {
                    resample_copy_high_kernel<<<block_count(static_cast<std::size_t>(m - m2)), kThreadsPerBlock>>>(
                        reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                        num,
                        reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                        n_x,
                        m - m2);
                    check_kernel_launch("resample_copy_high_kernel");
                }

                resample_adjust_nyquist_kernel<<<1, 1>>>(
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_a.data()),
                    n_x,
                    num,
                    m);
                check_kernel_launch("resample_adjust_nyquist_kernel");
            }

            throw_on_cufft_error(
                cufftExecC2C(
                    g_workspace.plan1d_b,
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                    reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                    CUFFT_INVERSE),
                "cufftExecC2C(resample inverse)");

            scatter_real_line_from_complex_kernel<<<block_count(static_cast<std::size_t>(num)), kThreadsPerBlock>>>(
                reinterpret_cast<cufftComplex *>(g_workspace.complex_signal_b.data()),
                output.data(),
                output_bases,
                output_plan.axis_stride,
                line,
                static_cast<std::size_t>(num),
                1.0f / static_cast<float>(n_x));
            check_kernel_launch("scatter_real_line_from_complex_kernel");
        }

        return output;
    }

    ZxGpuRealArray upfirdn_impl(
        const ZxGpuRealSignal &h,
        const ZxGpuRealArray &x,
        int up,
        int down,
        int axis)
    {
        detail::ensure_positive_int(up, "up");
        detail::ensure_positive_int(down, "down");
        const detail::AxisPlan input_plan = detail::make_axis_plan(x.shape(), axis);
        const Shape output_shape =
            core::replace_axis_size(x.shape(), axis, detail::upfirdn_size(input_plan.axis_size, h.size(), up, down));
        const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
        const std::size_t *input_bases = upload_line_bases_cached(
            x.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(input_bases)");
        const std::size_t *output_bases = upload_line_bases_cached(
            output_shape,
            axis,
            g_workspace.size_buffer_b,
            g_workspace.line_bases_cache_b,
            "cudaMemcpy H2D(output_bases)");
        ZxGpuRealArray output(output_shape, false);
        upfirdn_kernel<<<block_count(output_plan.line_count * output_plan.axis_size), kThreadsPerBlock>>>(
            h.data(),
            h.size(),
            x.data(),
            input_bases,
            input_plan.axis_size,
            input_plan.axis_stride,
            output.data(),
            output_bases,
            output_plan.axis_size,
            output_plan.axis_stride,
            output_plan.line_count,
            up,
            down);
        check_kernel_launch("upfirdn_kernel");
        return output;
    }

    ZxGpuRealArray resample_poly_impl(
        const ZxGpuRealArray &x,
        int up,
        int down,
        int axis,
        ZxGpuWindowSpec window)
    {
        detail::ensure_positive_int(up, "up");
        detail::ensure_positive_int(down, "down");
        const int g = std::gcd(up, down);
        up /= g;
        down /= g;
        if (up == 1 && down == 1)
        {
            return x;
        }

        const std::size_t input_size = core::axis_size(x, axis);
        const std::size_t output_size = detail::resampled_size(input_size, up, down);

        ZxGpuRealSignal explicit_storage;
        const ZxGpuRealSignal *padded_filter = nullptr;
        std::size_t n_pre_remove = 0;
        ZxGpuRealSignal local_padded_filter;
        if (const ZxGpuRealSignal *explicit_filter = explicit_window_signal(window, explicit_storage))
        {
            const std::size_t half_len = explicit_filter->empty() ? 0 : (explicit_filter->size() - 1) / 2;
            std::size_t n_pre_pad =
                static_cast<std::size_t>(down) - (half_len % static_cast<std::size_t>(down));
            std::size_t n_post_pad = 0;
            n_pre_remove = (half_len + n_pre_pad) / static_cast<std::size_t>(down);
            while (detail::upfirdn_size(input_size, explicit_filter->size() + n_pre_pad + n_post_pad, up, down) <
                   output_size + n_pre_remove)
            {
                ++n_post_pad;
            }
            local_padded_filter.resize(explicit_filter->size() + n_pre_pad + n_post_pad, true);
            copy_scaled_signal_segment_kernel<<<block_count(explicit_filter->size()), kThreadsPerBlock>>>(
                local_padded_filter.data(),
                local_padded_filter.size(),
                n_pre_pad,
                explicit_filter->data(),
                explicit_filter->size(),
                static_cast<float>(up));
            check_kernel_launch("copy_scaled_signal_segment_kernel(resample_poly explicit)");
            padded_filter = &local_padded_filter;
        }
        else
        {
            const int max_rate = std::max(up, down);
            const std::size_t half_len = static_cast<std::size_t>(10 * max_rate);
            const std::size_t filter_size = 2 * half_len + 1;
            std::size_t n_pre_pad =
                static_cast<std::size_t>(down) - (half_len % static_cast<std::size_t>(down));
            std::size_t n_post_pad = 0;
            n_pre_remove = (half_len + n_pre_pad) / static_cast<std::size_t>(down);
            while (detail::upfirdn_size(input_size, filter_size + n_pre_pad + n_post_pad, up, down) <
                   output_size + n_pre_remove)
            {
                ++n_post_pad;
            }
            std::string window_key;
            const bool cacheable_window =
                build_zx_gpu_window_cache_key(window, static_cast<int>(filter_size), window_key);
            const std::string filter_key =
                "up=" + std::to_string(up) +
                ";down=" + std::to_string(down) +
                ";input=" + std::to_string(input_size) +
                ";pre=" + std::to_string(n_pre_pad) +
                ";post=" + std::to_string(n_post_pad) +
                ";" + window_key;
            if (!cacheable_window ||
                !g_workspace.resample_poly_filter_valid ||
                g_workspace.resample_poly_filter_key != filter_key)
            {
                const ZxGpuRealSignal h = cusignal::zx_gpu_backend::filter_design::firwin(
                    static_cast<int>(filter_size),
                    1.0 / static_cast<float>(max_rate),
                    -1.0,
                    window);
                g_workspace.resample_poly_filter.resize(filter_size + n_pre_pad + n_post_pad, true);
                copy_scaled_signal_segment_kernel<<<block_count(h.size()), kThreadsPerBlock>>>(
                    g_workspace.resample_poly_filter.data(),
                    g_workspace.resample_poly_filter.size(),
                    n_pre_pad,
                    h.data(),
                    h.size(),
                    static_cast<float>(up));
                check_kernel_launch("copy_scaled_signal_segment_kernel(resample_poly)");
                if (cacheable_window)
                {
                    g_workspace.resample_poly_filter_key = filter_key;
                    g_workspace.resample_poly_n_pre_remove = n_pre_remove;
                    g_workspace.resample_poly_filter_valid = true;
                }
                else
                {
                    g_workspace.resample_poly_filter_valid = false;
                }
            }
            else
            {
                n_pre_remove = g_workspace.resample_poly_n_pre_remove;
            }
            padded_filter = &g_workspace.resample_poly_filter;
        }

        const ZxGpuRealArray filtered = upfirdn_impl(*padded_filter, x, up, down, axis);
        const detail::AxisPlan filtered_plan = detail::make_axis_plan(filtered.shape(), axis);
        const Shape output_shape = core::replace_axis_size(x.shape(), axis, output_size);
        const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
        const std::size_t *filtered_bases = upload_line_bases_cached(
            filtered.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(filtered_bases)");
        const std::size_t *output_bases = upload_line_bases_cached(
            output_shape,
            axis,
            g_workspace.size_buffer_b,
            g_workspace.line_bases_cache_b,
            "cudaMemcpy H2D(output_bases)");
        ZxGpuRealArray output(output_shape, false);
        crop_lines_kernel<<<block_count(output_plan.line_count * output_plan.axis_size), kThreadsPerBlock>>>(
            filtered.data(),
            filtered_bases,
            filtered_plan.axis_stride,
            output.data(),
            output_bases,
            output_plan.axis_size,
            output_plan.axis_stride,
            output_plan.line_count,
            n_pre_remove);
        check_kernel_launch("crop_lines_kernel(resample_poly)");
        return output;
    }

    ZxGpuRealArray decimate_impl(
        const ZxGpuRealArray &x,
        int q,
        int n,
        int axis,
        bool zero_phase)
    {
        detail::ensure_positive_int(q, "q");
        const int order = n < 0 ? 20 * q : n;
        if (!g_workspace.decimate_taps_valid ||
            g_workspace.cached_decimate_q != q ||
            g_workspace.cached_decimate_order != order)
        {
            g_workspace.decimate_taps =
                cusignal::zx_gpu_backend::filter_design::firwin(order + 1, 1.0 / static_cast<float>(q));
            g_workspace.cached_decimate_q = q;
            g_workspace.cached_decimate_order = order;
            g_workspace.decimate_taps_valid = true;
        }
        const ZxGpuRealSignal &taps = g_workspace.decimate_taps;

        if (zero_phase)
        {
            const ZxGpuRealArray filtered = upfirdn_impl(taps, x, 1, q, axis);
            const detail::AxisPlan filtered_plan = detail::make_axis_plan(filtered.shape(), axis);
            const std::size_t output_size =
                detail::resampled_size(core::axis_size(x, axis), 1, q);
            const Shape output_shape =
                core::replace_axis_size(x.shape(), axis, output_size);
            const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
            const std::size_t *filtered_bases = upload_line_bases_cached(
                filtered.shape(),
                axis,
                g_workspace.size_buffer_a,
                g_workspace.line_bases_cache_a,
                "cudaMemcpy H2D(filtered_bases)");
            const std::size_t *output_bases = upload_line_bases_cached(
                output_shape,
                axis,
                g_workspace.size_buffer_b,
                g_workspace.line_bases_cache_b,
                "cudaMemcpy H2D(output_bases)");
            ZxGpuRealArray output(output_shape, false);
            const std::size_t delay =
                (static_cast<std::size_t>(order) / 2) / static_cast<std::size_t>(q);
            crop_lines_kernel<<<block_count(output_plan.line_count * output_plan.axis_size), kThreadsPerBlock>>>(
                filtered.data(),
                filtered_bases,
                filtered_plan.axis_stride,
                output.data(),
                output_bases,
                output_plan.axis_size,
                output_plan.axis_stride,
                output_plan.line_count,
                delay);
            check_kernel_launch("crop_lines_kernel(decimate_zero_phase)");
            return output;
        }

        const ZxGpuRealSignal &one = make_unit_signal();
        const ZxGpuRealArray filtered = lfilter_impl(taps, one, x, axis, nullptr, nullptr);
        const detail::AxisPlan filtered_plan = detail::make_axis_plan(filtered.shape(), axis);
        const Shape output_shape =
            core::replace_axis_size(filtered.shape(), axis, detail::decimated_size(filtered_plan.axis_size, q));
        const detail::AxisPlan output_plan = detail::make_axis_plan(output_shape, axis);
        const std::size_t *filtered_bases = upload_line_bases_cached(
            filtered.shape(),
            axis,
            g_workspace.size_buffer_a,
            g_workspace.line_bases_cache_a,
            "cudaMemcpy H2D(filtered_bases)");
        const std::size_t *output_bases = upload_line_bases_cached(
            output_shape,
            axis,
            g_workspace.size_buffer_b,
            g_workspace.line_bases_cache_b,
            "cudaMemcpy H2D(output_bases)");
        ZxGpuRealArray output(output_shape, false);
        subsample_lines_kernel<<<block_count(output_plan.line_count * output_plan.axis_size), kThreadsPerBlock>>>(
            filtered.data(),
            filtered_bases,
            filtered_plan.axis_stride,
            output.data(),
            output_bases,
            output_plan.axis_size,
            output_plan.axis_stride,
            output_plan.line_count,
            0,
            static_cast<std::size_t>(q));
        check_kernel_launch("subsample_lines_kernel");
        return output;
    }

} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace filtering
        {

            core::ZxGpuRealArray wiener(const core::RealArrayLike &image)
            {
                return wiener(image, core::Shape(shape_of(image).size(), 3), -1.0);
            }

            core::ZxGpuRealArray wiener(
                const core::RealArrayLike &image,
                int mysize,
                float noise)
            {
                detail::ensure_positive_int(mysize, "mysize");
                return wiener(image, core::Shape(shape_of(image).size(), static_cast<std::size_t>(mysize)), noise);
            }

            core::ZxGpuRealArray wiener(
                const core::RealArrayLike &image,
                const core::Shape &mysize,
                float noise)
            {
                if (mysize.empty())
                {
                    throw std::invalid_argument("mysize must not be empty");
                }
                const core::ZxGpuRealArray &image_device = core::as_device_array(image, g_workspace.real_array_a);
                if (mysize.size() != image_device.rank())
                {
                    throw std::invalid_argument("mysize rank must match image rank");
                }
                if (image_device.rank() > kMaxRank)
                {
                    throw std::invalid_argument("wiener rank exceeds CUDA implementation limit");
                }

                ZxGpuRealArray output(image_device.shape(), false);
                g_workspace.real_array_b.resize(image_device.shape(), false);
                g_workspace.real_array_c.resize(image_device.shape(), false);
                if (!g_workspace.wiener_metadata_valid ||
                    g_workspace.cached_wiener_shape != image_device.shape() ||
                    g_workspace.cached_wiener_mysize != mysize)
                {
                    const std::vector<std::size_t> strides = detail::compute_strides(image_device.shape());
                    upload_size_vector(image_device.shape(), g_workspace.wiener_shape_buffer, "cudaMemcpy H2D(shape)");
                    upload_size_vector(strides, g_workspace.wiener_stride_buffer, "cudaMemcpy H2D(strides)");
                    upload_size_vector(mysize, g_workspace.wiener_mysize_buffer, "cudaMemcpy H2D(mysize)");
                    g_workspace.cached_wiener_shape = image_device.shape();
                    g_workspace.cached_wiener_mysize = mysize;
                    g_workspace.wiener_metadata_valid = true;
                }
                g_workspace.scalar_buffer_a.zero(1, "cudaMemset(noise_sum)");
                const float window_volume = static_cast<float>(core::shape_product(mysize));

                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    const bool use_2d_tiled_stats =
                        tile::optimized_path() &&
                        image_device.rank() == 2 &&
                        mysize[0] % 2 == 1 &&
                        mysize[1] % 2 == 1 &&
                        mysize[0] <= kMaxWienerTiledWindow &&
                        mysize[1] <= kMaxWienerTiledWindow;
                    if (use_2d_tiled_stats)
                    {
                        const dim3 threads(kWienerTileSize, kWienerTileSize);
                        const dim3 blocks(
                            static_cast<unsigned int>((image_device.shape()[1] + kWienerTileSize - 1) /
                                                      kWienerTileSize),
                            static_cast<unsigned int>((image_device.shape()[0] + kWienerTileSize - 1) /
                                                      kWienerTileSize));
                        const std::size_t shared_rows = kWienerTileSize + 2 * (mysize[0] / 2);
                        const std::size_t shared_cols = kWienerTileSize + 2 * (mysize[1] / 2);
                        const std::size_t shared_bytes = shared_rows * shared_cols * sizeof(float);
                        wiener_local_stats_2d_tiled_kernel<<<blocks, threads, shared_bytes>>>(
                            image_device.data(),
                            image_device.shape()[0],
                            image_device.shape()[1],
                            mysize[0],
                            mysize[1],
                            window_volume,
                            g_workspace.real_array_b.data(),
                            g_workspace.real_array_c.data());
                        check_kernel_launch("wiener_local_stats_2d_tiled_kernel");
                    }
                    else
                    {
                        wiener_local_stats_kernel<<<block_count(image_device.size()), kThreadsPerBlock>>>(
                            image_device.data(),
                            image_device.size(),
                            g_workspace.wiener_shape_buffer.get(),
                            g_workspace.wiener_stride_buffer.get(),
                            g_workspace.wiener_mysize_buffer.get(),
                            image_device.rank(),
                            window_volume,
                            g_workspace.real_array_b.data(),
                            g_workspace.real_array_c.data());
                        check_kernel_launch("wiener_local_stats_kernel");
                    }

                    float resolved_noise = noise;
                    if (noise < 0.0)
                    {
                        const int variance_blocks = block_count(image_device.size());
                        g_workspace.reduction_buffer_a.reserve(static_cast<std::size_t>(variance_blocks));
                        sum_values_block_kernel<<<variance_blocks, kThreadsPerBlock>>>(
                            g_workspace.real_array_c.data(),
                            image_device.size(),
                            g_workspace.reduction_buffer_a.get());
                        check_kernel_launch("sum_values_block_kernel(wiener)");
                        sum_values_finalize_kernel<<<1, kThreadsPerBlock>>>(
                            g_workspace.reduction_buffer_a.get(),
                            static_cast<std::size_t>(variance_blocks),
                            g_workspace.scalar_buffer_a.get());
                        check_kernel_launch("sum_values_finalize_kernel(wiener)");
#ifdef CUSIGNAL_PLATFORM_ZHONGKEXIN
                        float variance_sum = 0.0f;
                        throw_on_zx_gpu_error(
                            cudaMemcpy(
                                &variance_sum,
                                g_workspace.scalar_buffer_a.get(),
                                sizeof(float),
                                cudaMemcpyDeviceToHost),
                            "cudaMemcpy D2H(wiener noise)");
                        resolved_noise = variance_sum / static_cast<float>(image_device.size());
#endif
                    }

#ifdef CUSIGNAL_PLATFORM_ZHONGKEXIN
                    wiener_apply_kernel<<<block_count(image_device.size()), kThreadsPerBlock>>>(
                        image_device.data(),
                        g_workspace.real_array_b.data(),
                        g_workspace.real_array_c.data(),
                        output.data(),
                        image_device.size(),
                        resolved_noise);
                    check_kernel_launch("wiener_apply_kernel(auto-noise)");
#else
                    if (noise < 0.0)
                    {
                        wiener_apply_auto_noise_kernel<<<block_count(image_device.size()), kThreadsPerBlock>>>(
                            image_device.data(),
                            g_workspace.real_array_b.data(),
                            g_workspace.real_array_c.data(),
                            g_workspace.scalar_buffer_a.get(),
                            output.data(),
                            image_device.size());
                        check_kernel_launch("wiener_apply_auto_noise_kernel");
                    }
                    else
                    {
                        wiener_apply_kernel<<<block_count(image_device.size()), kThreadsPerBlock>>>(
                            image_device.data(),
                            g_workspace.real_array_b.data(),
                            g_workspace.real_array_c.data(),
                            output.data(),
                            image_device.size(),
                            noise);
                        check_kernel_launch("wiener_apply_kernel");
                    }
#endif
                }));
                return output;
            }

            core::ZxGpuRealArray firfilter(
                const core::RealSignalLike &b,
                const core::RealArrayLike &x,
                int axis)
            {
                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                const ZxGpuRealSignal &one = make_unit_signal();
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = lfilter_impl(
                        b_device, one, x_device, axis, nullptr, nullptr, "filtering/firfilter");
                }));
                return output;
            }

            core::ZxGpuComplexArray firfilter(
                const core::RealSignalLike &b,
                const core::ComplexArrayLike &x,
                int axis)
            {
                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuComplexArray &x_device = core::as_device_array(x, g_workspace.complex_array_a);
                ZxGpuComplexArray output = core::make_zx_gpu_complex_array(x_device.shape());
                if (x_device.empty())
                {
                    g_last_kernel_ms = 0.0f;
                    return output;
                }
                if (b_device.size() > static_cast<std::size_t>(kMaxFilterOrder + 1))
                {
                    throw std::invalid_argument("filter order exceeds CUDA complex firfilter limit");
                }

                const detail::AxisPlan plan = detail::make_axis_plan(x_device.shape(), axis);
                const tile::PolicyDecision tuning = tile::select(
                    tile::make_fir_filter_key(
                        "filtering/firfilter",
                        plan.line_count,
                        plan.axis_size,
                        1,
                        b_device.size() == 0 ? 0 : b_device.size() - 1,
                        axis,
                        b_device.size(),
                        1,
                        false,
                        plan.axis_stride));
                const tile::ScopedPolicy policy_scope(tuning);
                const std::size_t *line_bases = upload_line_bases_cached(
                    x_device.shape(),
                    axis,
                    g_workspace.size_buffer_a,
                    g_workspace.line_bases_cache_a,
                    "cudaMemcpy H2D(complex_fir_line_bases)");

                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    if (tile::optimized_path() &&
                        plan.axis_stride == 1 && plan.axis_size >= 2048 &&
                        plan.line_count <= kMaxSharedFirLines)
                    {
                        const int plan_variant = tuning.config.plan_variant;
                        const bool use_quad_output =
                            plan_variant == 0 && b_device.size() <= kComplexFirQuadMaxTaps;
                        const int outputs_per_thread =
                            plan_variant == 0 ? (use_quad_output ? 4 : 2) : plan_variant;
                        const std::size_t outputs_per_block =
                            static_cast<std::size_t>(outputs_per_thread) *
                            static_cast<std::size_t>(kThreadsPerBlock);
                        const dim3 grid(
                            static_cast<unsigned int>(
                                (plan.axis_size + outputs_per_block - 1) / outputs_per_block),
                            static_cast<unsigned int>(plan.line_count));
                        const std::size_t shared_size =
                            (outputs_per_block + b_device.size() - 1) * sizeof(float2) +
                            b_device.size() * sizeof(float);
                        if (plan_variant == 0 && use_quad_output)
                        {
                            complex_fir_filter_zero_lines_shared_quad_kernel<<<grid, kThreadsPerBlock, shared_size>>>(
                                b_device.data(),
                                b_device.size(),
                                reinterpret_cast<const float2 *>(x_device.data()),
                                line_bases,
                                plan.line_count,
                                plan.axis_size,
                                plan.axis_stride,
                                reinterpret_cast<float2 *>(output.data()));
                            check_kernel_launch("complex_fir_filter_zero_lines_shared_quad_kernel");
                        }
                        else if (plan_variant == 0)
                        {
                            complex_fir_filter_zero_lines_shared_dual_kernel<<<grid, kThreadsPerBlock, shared_size>>>(
                                b_device.data(),
                                b_device.size(),
                                reinterpret_cast<const float2 *>(x_device.data()),
                                line_bases,
                                plan.line_count,
                                plan.axis_size,
                                plan.axis_stride,
                                reinterpret_cast<float2 *>(output.data()));
                            check_kernel_launch("complex_fir_filter_zero_lines_shared_dual_kernel");
                        }
                        else if (plan_variant == 1)
                        {
                            complex_fir_filter_zero_lines_shared_multi_kernel<1>
                                <<<grid, kThreadsPerBlock, shared_size>>>(
                                    b_device.data(),
                                    b_device.size(),
                                    reinterpret_cast<const float2 *>(x_device.data()),
                                    line_bases,
                                    plan.line_count,
                                    plan.axis_size,
                                    plan.axis_stride,
                                    reinterpret_cast<float2 *>(output.data()));
                            check_kernel_launch("complex_fir_filter_zero_lines_shared_multi_kernel<1>");
                        }
                        else if (plan_variant == 2)
                        {
                            complex_fir_filter_zero_lines_shared_multi_kernel<2>
                                <<<grid, kThreadsPerBlock, shared_size>>>(
                                    b_device.data(),
                                    b_device.size(),
                                    reinterpret_cast<const float2 *>(x_device.data()),
                                    line_bases,
                                    plan.line_count,
                                    plan.axis_size,
                                    plan.axis_stride,
                                    reinterpret_cast<float2 *>(output.data()));
                            check_kernel_launch("complex_fir_filter_zero_lines_shared_multi_kernel<2>");
                        }
                        else if (plan_variant == 4)
                        {
                            complex_fir_filter_zero_lines_shared_multi_kernel<4>
                                <<<grid, kThreadsPerBlock, shared_size>>>(
                                    b_device.data(),
                                    b_device.size(),
                                    reinterpret_cast<const float2 *>(x_device.data()),
                                    line_bases,
                                    plan.line_count,
                                    plan.axis_size,
                                    plan.axis_stride,
                                    reinterpret_cast<float2 *>(output.data()));
                            check_kernel_launch("complex_fir_filter_zero_lines_shared_multi_kernel<4>");
                        }
                        else
                        {
                            complex_fir_filter_zero_lines_shared_multi_kernel<8>
                                <<<grid, kThreadsPerBlock, shared_size>>>(
                                    b_device.data(),
                                    b_device.size(),
                                    reinterpret_cast<const float2 *>(x_device.data()),
                                    line_bases,
                                    plan.line_count,
                                    plan.axis_size,
                                    plan.axis_stride,
                                    reinterpret_cast<float2 *>(output.data()));
                            check_kernel_launch("complex_fir_filter_zero_lines_shared_multi_kernel<8>");
                        }
                    }
                    else if (tile::optimized_path() &&
                             plan.axis_stride == 1 && plan.axis_size >= 1024 &&
                             plan.line_count <= kMaxSharedFirLines)
                    {
                        const dim3 grid(
                            static_cast<unsigned int>(block_count(plan.axis_size)),
                            static_cast<unsigned int>(plan.line_count));
                        const std::size_t shared_size =
                            (static_cast<std::size_t>(kThreadsPerBlock) + b_device.size() - 1) * sizeof(float2) +
                            b_device.size() * sizeof(float);
                        complex_fir_filter_zero_lines_shared_kernel<<<grid, kThreadsPerBlock, shared_size>>>(
                            b_device.data(),
                            b_device.size(),
                            reinterpret_cast<const float2 *>(x_device.data()),
                            line_bases,
                            plan.line_count,
                            plan.axis_size,
                            plan.axis_stride,
                            reinterpret_cast<float2 *>(output.data()));
                        check_kernel_launch("complex_fir_filter_zero_lines_shared_kernel");
                    }
                    else
                    {
                        complex_fir_filter_zero_lines_kernel<<<
                            block_count(plan.line_count * plan.axis_size),
                            kThreadsPerBlock>>>(
                            b_device.data(),
                            b_device.size(),
                            reinterpret_cast<const float2 *>(x_device.data()),
                            line_bases,
                            plan.line_count,
                            plan.axis_size,
                            plan.axis_stride,
                            reinterpret_cast<float2 *>(output.data()));
                        check_kernel_launch("complex_fir_filter_zero_lines_kernel");
                    }
                }));
                return output;
            }

            filtering_api::ZxGpuFilterStateResult firfilter(
                const core::RealSignalLike &b,
                const core::RealArrayLike &x,
                int axis,
                const core::RealArrayLike &zi)
            {
                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                const ZxGpuRealArray &zi_device = core::as_device_array(zi, g_workspace.real_array_b);
                const ZxGpuRealSignal &one = make_unit_signal();
                filtering_api::ZxGpuFilterStateResult result;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    result.output = lfilter_impl(
                        b_device,
                        one,
                        x_device,
                        axis,
                        &zi_device,
                        &result.final_state,
                        "filtering/firfilter");
                }));
                return result;
            }

            core::ZxGpuRealArray lfilter(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a,
                const core::RealArrayLike &x,
                int axis)
            {
                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealSignal &a_device = core::as_device_signal(a, g_workspace.real_signal_b);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = lfilter_impl(
                        b_device, a_device, x_device, axis, nullptr, nullptr, "filtering/lfilter");
                }));
                return output;
            }

            filtering_api::ZxGpuFilterStateResult lfilter(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a,
                const core::RealArrayLike &x,
                int axis,
                const core::RealArrayLike &zi)
            {
                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealSignal &a_device = core::as_device_signal(a, g_workspace.real_signal_b);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                const ZxGpuRealArray &zi_device = core::as_device_array(zi, g_workspace.real_array_b);
                filtering_api::ZxGpuFilterStateResult result;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    result.output = lfilter_impl(
                        b_device,
                        a_device,
                        x_device,
                        axis,
                        &zi_device,
                        &result.final_state,
                        "filtering/lfilter");
                }));
                return result;
            }

            core::ZxGpuRealSignal lfilter_zi(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a)
            {
                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealSignal &a_device = core::as_device_signal(a, g_workspace.real_signal_b);
                ScopedZxGpuEvents events;
                ZxGpuRealSignal output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = lfilter_zi_impl(b_device, a_device);
                }));
                return output;
            }

            core::ZxGpuRealSignal firfilter_zi(const core::RealSignalLike &b)
            {
                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealSignal &one = make_unit_signal();
                ScopedZxGpuEvents events;
                ZxGpuRealSignal output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = lfilter_zi_impl(b_device, one);
                }));
                return output;
            }

            core::ZxGpuRealArray firfilter2(
                const core::RealSignalLike &b,
                const core::RealArrayLike &x,
                int axis,
                const std::string &padtype,
                int padlen,
                const std::string &method,
                int irlen)
            {
                (void)irlen;
                const std::string normalized_method = detail::normalize_method(method);
                if (normalized_method == "gust")
                {
                    g_last_kernel_ms = 0.0;
                    return ZxGpuRealArray::from_host(
                        cpu_filtering::firfilter2(
                            to_host_signal(b),
                            to_host_array(x),
                            axis,
                            padtype,
                            padlen,
                            method,
                            irlen));
                }

                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                const ZxGpuRealSignal &one = make_unit_signal();
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    if (b_device.size() <= static_cast<std::size_t>(kMaxFilterOrder))
                    {
                        output = pad_and_firfiltfilt_impl(
                            b_device,
                            x_device,
                            axis,
                            detail::normalize_padtype(padtype),
                            padlen);
                    }
                    else
                    {
                        g_last_firfilter2_path = kFirfilter2PathGeneric;
                        output = pad_and_filtfilt_impl(
                            b_device,
                            one,
                            x_device,
                            axis,
                            detail::normalize_padtype(padtype),
                            padlen);
                    }
                }));
                return output;
            }

            core::ZxGpuRealArray filtfilt(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a,
                const core::RealArrayLike &x,
                int axis,
                const std::string &padtype,
                int padlen,
                const std::string &method,
                int irlen)
            {
                (void)irlen;
                const std::string normalized_method = detail::normalize_method(method);
                if (normalized_method == "gust")
                {
                    g_last_kernel_ms = 0.0;
                    return ZxGpuRealArray::from_host(
                        cpu_filtering::filtfilt(
                            to_host_signal(b),
                            to_host_signal(a),
                            to_host_array(x),
                            axis,
                            padtype,
                            padlen,
                            method,
                            irlen));
                }

                const ZxGpuRealSignal &b_device = core::as_device_signal(b, g_workspace.real_signal_a);
                const ZxGpuRealSignal &a_device = core::as_device_signal(a, g_workspace.real_signal_b);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = pad_and_filtfilt_impl(
                        b_device,
                        a_device,
                        x_device,
                        axis,
                        detail::normalize_padtype(padtype),
                        padlen);
                }));
                return output;
            }

            core::ZxGpuRealArray sosfilt(
                const core::RealArrayLike &sos,
                const core::RealArrayLike &x,
                int axis)
            {
                const ZxGpuRealArray &sos_device = core::as_device_array(sos, g_workspace.real_array_a);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_b);
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = sosfilt_impl(sos_device, x_device, axis, nullptr, nullptr);
                }));
                return output;
            }

            filtering_api::ZxGpuFilterStateResult sosfilt(
                const core::RealArrayLike &sos,
                const core::RealArrayLike &x,
                int axis,
                const core::RealArrayLike &zi)
            {
                const ZxGpuRealArray &sos_device = core::as_device_array(sos, g_workspace.real_array_a);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_b);
                const ZxGpuRealArray &zi_device = core::as_device_array(zi, g_workspace.real_array_c);
                filtering_api::ZxGpuFilterStateResult result;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    result.output = sosfilt_impl(sos_device, x_device, axis, &zi_device, &result.final_state);
                }));
                return result;
            }

            core::ZxGpuComplexArray hilbert(
                const core::RealArrayLike &x,
                int n,
                int axis)
            {
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuComplexArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = hilbert_impl(x_device, n, axis);
                }));
                return output;
            }

            core::ZxGpuComplexArray hilbert2(const core::RealArrayLike &x, const core::Shape &n)
            {
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuComplexArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = hilbert2_impl(x_device, n);
                }));
                return output;
            }

            core::ZxGpuRealArray detrend(
                const core::RealArrayLike &data,
                int axis,
                const std::string &type,
                const core::IndexVector &bp,
                bool overwrite_data)
            {
                (void)overwrite_data;
                const std::string trend = detail::normalize_trend_type(type);
                const ZxGpuRealArray &data_device = core::as_device_array(data, g_workspace.real_array_a);
                const detail::AxisPlan plan = detail::make_axis_plan(data_device.shape(), axis);
                const std::vector<std::size_t> line_bases = compute_line_bases(data_device.shape(), axis);
                if (!g_workspace.detrend_line_bases_valid ||
                    g_workspace.cached_detrend_shape != data_device.shape() ||
                    g_workspace.cached_detrend_axis != plan.axis ||
                    g_workspace.cached_detrend_line_bases != line_bases)
                {
                    upload_size_vector(line_bases, g_workspace.size_buffer_a, "cudaMemcpy H2D(line_bases)");
                    g_workspace.cached_detrend_shape = data_device.shape();
                    g_workspace.cached_detrend_axis = plan.axis;
                    g_workspace.cached_detrend_line_bases = line_bases;
                    g_workspace.detrend_line_bases_valid = true;
                    g_workspace.detrend_breaks_valid = false;
                }
                ZxGpuRealArray output(data_device.shape(), true);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    if (trend == "constant" || trend == "c")
                    {
                        if (plan.line_count == 1 &&
                            plan.axis_stride == 1 &&
                            plan.axis_size >= 4096)
                        {
                            const int grid_blocks = block_count(plan.axis_size);
                            g_workspace.reduction_buffer_a.reserve(static_cast<std::size_t>(grid_blocks) + 1);
                            float *coefficients = g_workspace.reduction_buffer_a.get() + grid_blocks;
                            detrend_constant_partials_kernel<<<grid_blocks, kThreadsPerBlock>>>(
                                data_device.data(),
                                plan.axis_size,
                                g_workspace.reduction_buffer_a.get());
                            check_kernel_launch("detrend_constant_partials_kernel");
                            detrend_constant_mean_kernel<<<1, kThreadsPerBlock>>>(
                                g_workspace.reduction_buffer_a.get(),
                                grid_blocks,
                                plan.axis_size,
                                coefficients);
                            check_kernel_launch("detrend_constant_mean_kernel");
                            detrend_constant_apply_kernel<<<grid_blocks, kThreadsPerBlock>>>(
                                data_device.data(),
                                plan.axis_size,
                                coefficients,
                                output.data());
                            check_kernel_launch("detrend_constant_apply_kernel");
                        }
                        else if (plan.axis_size >= 1024)
                        {
                            detrend_constant_parallel_kernel<<<static_cast<unsigned int>(plan.line_count), kThreadsPerBlock>>>(
                                data_device.data(),
                                g_workspace.size_buffer_a.get(),
                                plan.line_count,
                                plan.axis_size,
                                plan.axis_stride,
                                output.data());
                            check_kernel_launch("detrend_constant_parallel_kernel");
                        }
                        else
                        {
                            detrend_constant_kernel<<<block_count(plan.line_count), kThreadsPerBlock>>>(
                                data_device.data(),
                                g_workspace.size_buffer_a.get(),
                                plan.line_count,
                                plan.axis_size,
                                plan.axis_stride,
                                output.data());
                            check_kernel_launch("detrend_constant_kernel");
                        }
                        return;
                    }

                    core::IndexVector breaks = bp;
                    breaks.push_back(0);
                    breaks.push_back(static_cast<int>(plan.axis_size));
                    std::sort(breaks.begin(), breaks.end());
                    breaks.erase(std::unique(breaks.begin(), breaks.end()), breaks.end());
                    if (breaks.back() != static_cast<int>(plan.axis_size))
                    {
                        throw std::invalid_argument("Breakpoints must be less than length of data along given axis.");
                    }
                    if (!g_workspace.detrend_breaks_valid ||
                        g_workspace.cached_detrend_breaks != breaks)
                    {
                        g_workspace.int_buffer_a.copy_from_host(
                            breaks.data(),
                            breaks.size(),
                            "cudaMemcpy H2D(breakpoints)");
                        g_workspace.cached_detrend_breaks = breaks;
                        g_workspace.detrend_breaks_valid = true;
                    }
                    if (plan.line_count == 1 &&
                        plan.axis_stride == 1 &&
                        breaks.size() == 2 &&
                        plan.axis_size >= 4096)
                    {
                        const int grid_blocks = block_count(plan.axis_size);
                        g_workspace.reduction_buffer_a.reserve(static_cast<std::size_t>(grid_blocks) + 2);
                        g_workspace.reduction_buffer_b.reserve(static_cast<std::size_t>(grid_blocks));
                        float *partial_sum_y = g_workspace.reduction_buffer_a.get();
                        float *coefficients = g_workspace.reduction_buffer_a.get() + grid_blocks;
                        float *partial_sum_ty = g_workspace.reduction_buffer_b.get();
                        detrend_linear_partials_kernel<<<grid_blocks, kThreadsPerBlock>>>(
                            data_device.data(),
                            plan.axis_size,
                            partial_sum_y,
                            partial_sum_ty);
                        check_kernel_launch("detrend_linear_partials_kernel");
                        detrend_linear_coefficients_kernel<<<1, kThreadsPerBlock>>>(
                            partial_sum_y,
                            partial_sum_ty,
                            grid_blocks,
                            plan.axis_size,
                            coefficients);
                        check_kernel_launch("detrend_linear_coefficients_kernel");
                        detrend_linear_apply_kernel<<<grid_blocks, kThreadsPerBlock>>>(
                            data_device.data(),
                            plan.axis_size,
                            coefficients,
                            output.data());
                        check_kernel_launch("detrend_linear_apply_kernel");
                    }
                    else if (plan.axis_size >= 1024)
                    {
                        const std::size_t segment_count = breaks.size() - 1;
                        detrend_linear_parallel_kernel<<<
                            static_cast<unsigned int>(plan.line_count * segment_count),
                            kThreadsPerBlock>>>(
                            data_device.data(),
                            g_workspace.size_buffer_a.get(),
                            plan.line_count,
                            plan.axis_stride,
                            g_workspace.int_buffer_a.get(),
                            static_cast<int>(breaks.size()),
                            output.data());
                        check_kernel_launch("detrend_linear_parallel_kernel");
                    }
                    else
                    {
                        detrend_linear_kernel<<<block_count(plan.line_count), kThreadsPerBlock>>>(
                            data_device.data(),
                            g_workspace.size_buffer_a.get(),
                            plan.line_count,
                            plan.axis_size,
                            plan.axis_stride,
                            g_workspace.int_buffer_a.get(),
                            static_cast<int>(breaks.size()),
                            output.data());
                        check_kernel_launch("detrend_linear_kernel");
                    }
                }));
                return output;
            }

            core::ZxGpuComplexArray freq_shift(
                const core::ComplexArrayLike &x,
                float freq,
                float fs)
            {
                if (!(fs > 0.0))
                {
                    throw std::invalid_argument("fs must be > 0");
                }
                const ZxGpuComplexArray &x_device = core::as_device_array(x, g_workspace.complex_array_a);
                ZxGpuComplexArray output(x_device.shape(), false);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    freq_shift_kernel<<<block_count(x_device.size()), kThreadsPerBlock>>>(
                        x_device.data(),
                        output.data(),
                        x_device.size(),
                        freq,
                        fs);
                    check_kernel_launch("freq_shift_kernel");
                }));
                return output;
            }

            filtering_api::ZxGpuChannelizerResult channelize_poly(
                const core::ComplexSignalLike &x,
                const core::RealSignalLike &h,
                int n_chans)
            {
                detail::ensure_positive_int(n_chans, "n_chans");
                const ZxGpuComplexSignal &x_device = core::as_device_signal(x, g_workspace.complex_signal_a);
                const std::size_t channels = static_cast<std::size_t>(n_chans);
                const std::size_t n_pts = x_device.size() / channels;
                const RealSignal *host_h = std::get_if<RealSignal>(&h);
                const ZxGpuRealSignal *h_input = nullptr;
                bool padded_taps_ready = false;
                if (host_h != nullptr &&
                    g_workspace.channelize_taps_valid &&
                    g_workspace.cached_channelize_n_chans == n_chans &&
                    g_workspace.cached_channelize_taps == *host_h)
                {
                    padded_taps_ready = true;
                }
                else
                {
                    h_input = &core::as_device_signal(h, g_workspace.real_signal_a);
                }
                std::size_t padded_h_size =
                    padded_taps_ready ? g_workspace.cached_channelize_padded_size : h_input->size();
                if (padded_h_size % channels != 0)
                {
                    padded_h_size = ((padded_h_size + channels - 1) / channels) * channels;
                }
                if (!padded_taps_ready)
                {
                    g_workspace.real_signal_b.resize(padded_h_size, true);
                    copy_signal_segment_kernel<<<block_count(h_input->size()), kThreadsPerBlock>>>(
                        g_workspace.real_signal_b.data(),
                        padded_h_size,
                        0,
                        h_input->data(),
                        h_input->size());
                    check_kernel_launch("copy_signal_segment_kernel(channelize_poly)");
                    if (host_h != nullptr)
                    {
                        g_workspace.cached_channelize_taps = *host_h;
                        g_workspace.cached_channelize_padded_size = padded_h_size;
                        g_workspace.cached_channelize_n_chans = n_chans;
                        g_workspace.channelize_taps_valid = true;
                    }
                    else
                    {
                        g_workspace.channelize_taps_valid = false;
                    }
                }

                filtering_api::ZxGpuChannelizerResult result;
                result.channels = ZxGpuComplexArray(Shape{n_pts, channels}, false);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    const bool use_point_kernel =
                        n_chans == kChannelizeSharedChannels &&
                        (g_channelize_path_override == kChannelizePathPoint ||
                         (g_channelize_path_override == kChannelizePathAuto &&
                          n_pts >= kChannelizePointMinPoints));
                    if (use_point_kernel)
                    {
                        channelize_poly_channels8_point_kernel<<<block_count(n_pts), kThreadsPerBlock>>>(
                            x_device.data(),
                            x_device.size(),
                            g_workspace.real_signal_b.data(),
                            padded_h_size,
                            n_pts,
                            result.channels.data());
                        check_kernel_launch("channelize_poly_channels8_point_kernel");
                    }
                    else
                    {
                        channelize_poly_kernel<<<block_count(result.channels.size()), kThreadsPerBlock>>>(
                            x_device.data(),
                            x_device.size(),
                            g_workspace.real_signal_b.data(),
                            padded_h_size,
                            n_chans,
                            n_pts,
                            result.channels.data());
                        check_kernel_launch("channelize_poly_kernel");
                    }
                }));
                return result;
            }

            core::ZxGpuRealArray decimate(
                const core::RealArrayLike &x,
                int q,
                int n,
                int axis,
                bool zero_phase)
            {
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = decimate_impl(x_device, q, n, axis, zero_phase);
                }));
                return output;
            }

            core::ZxGpuRealArray resample(
                const core::RealArrayLike &x,
                int num,
                int axis,
                core::ZxGpuWindowSpec window,
                const std::string &domain)
            {
                detail::ensure_positive_int(num, "num");
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = resample_impl(x_device, num, axis, window, domain);
                }));
                return output;
            }

            filtering_api::ZxGpuResampleResult resample(
                const core::RealArrayLike &x,
                int num,
                const core::RealSignalLike &t,
                int axis,
                core::ZxGpuWindowSpec window,
                const std::string &domain)
            {
                const Shape &shape = shape_of(x);
                if (signal_size(t) < 2)
                {
                    throw std::invalid_argument("t must contain at least two samples");
                }
                filtering_api::ZxGpuResampleResult result;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    result.output = resample(x, num, axis, window, domain);
                    const auto [t0, t1] = first_two_time_values(t);
                    const float step =
                        (t1 - t0) * static_cast<float>(shape[core::normalize_axis(axis, shape.size())]) /
                        static_cast<float>(num);
                    result.time = ZxGpuRealSignal(static_cast<std::size_t>(num), true);
                    generate_time_axis_kernel<<<block_count(static_cast<std::size_t>(num)), kThreadsPerBlock>>>(
                        result.time.data(),
                        static_cast<std::size_t>(num),
                        t0,
                        step);
                    check_kernel_launch("generate_time_axis_kernel");
                }));
                return result;
            }

            core::ZxGpuRealArray resample_poly(
                const core::RealArrayLike &x,
                int up,
                int down,
                int axis,
                core::ZxGpuWindowSpec window)
            {
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = resample_poly_impl(x_device, up, down, axis, window);
                }));
                return output;
            }

            core::ZxGpuRealArray upfirdn(
                const core::RealSignalLike &h,
                const core::RealArrayLike &x,
                int up,
                int down,
                int axis)
            {
                const ZxGpuRealSignal &h_device = core::as_device_signal(h, g_workspace.real_signal_a);
                const ZxGpuRealArray &x_device = core::as_device_array(x, g_workspace.real_array_a);
                ScopedZxGpuEvents events;
                ZxGpuRealArray output;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    output = upfirdn_impl(h_device, x_device, up, down, axis);
                }));
                return output;
            }

        } // namespace filtering

        namespace filtering_test_hooks
        {
            bool resample_auto_uses_windowed_pack(
                const core::Shape &shape,
                int output_size,
                int axis,
                const core::ZxGpuWindowSpec &window,
                const std::string &domain)
            {
                validate_zx_gpu_window_spec(window);
                const detail::AxisPlan input_plan = detail::make_axis_plan(shape, axis);
                return should_use_resample_windowed_pack(
                    input_plan,
                    output_size,
                    window,
                    detail::normalize_domain(domain));
            }

            int consume_last_resample_path()
            {
                const int value = g_last_resample_path;
                g_last_resample_path = kResamplePathGeneric;
                return value;
            }

            void set_resample_path_override(int path)
            {
                if (path != kResamplePathAuto &&
                    path != kResamplePathGeneric &&
                    path != kResamplePathFused &&
                    path != kResamplePathWindowedPack)
                {
                    throw std::invalid_argument("resample test path must be -1, 0, 1, or 2");
                }
                g_resample_path_override = path;
            }

            int consume_last_firfilter2_path()
            {
                const int value = g_last_firfilter2_path;
                g_last_firfilter2_path = kFirfilter2PathGeneric;
                return value;
            }

            void set_firfilter2_path_override(int path)
            {
                if (path != kFirfilter2PathAuto &&
                    path != kFirfilter2PathGeneric &&
                    path != kFirfilter2PathDirect)
                {
                    throw std::invalid_argument("firfilter2 test path must be -1, 0, or 1");
                }
                g_firfilter2_path_override = path;
            }

            void set_channelize_poly_path_override(int path)
            {
                if (path != kChannelizePathAuto &&
                    path != kChannelizePathGeneric &&
                    path != kChannelizePathPoint)
                {
                    throw std::invalid_argument("channelize_poly test path must be -1, 0, or 1");
                }
                g_channelize_path_override = path;
            }

            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0;
                return value;
            }
        } // namespace filtering_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
