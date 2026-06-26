#include "cusignal/wavelets/wavelets.hpp"

#include <cuda_runtime.h>
#include <algorithm>
#include <string>
#include <variant>
#include <vector>

#include "cusignal/core/helpers.hpp"

#include "../common/wavelets_detail.hpp"

namespace
{
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuIndexSignal;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::RealSignal;
    namespace detail = cusignal::wavelets_detail;

    constexpr int kThreadsPerBlock = 256;
    thread_local float g_last_kernel_ms = 0.0;

    void check_kernel_launch(const char *what)
    {
        cusignal::core::throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

    class ScopedZxGpuEvents
    {
    public:
        ScopedZxGpuEvents()
        {
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventCreate(&start_), "cudaEventCreate(start)");
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventCreate(&stop_), "cudaEventCreate(stop)");
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
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventRecord(start_), "cudaEventRecord(start)");
            callable();
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventRecord(stop_), "cudaEventRecord(stop)");
            cusignal::core::throw_on_zx_gpu_error(
                cudaEventSynchronize(stop_), "cudaEventSynchronize(stop)");
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

    struct WaveletsWorkspace
    {
        ZxGpuRealSignal hk_storage;
        ZxGpuRealSignal data_storage;
        ZxGpuRealSignal widths_storage;
        ZxGpuIndexSignal kernel_sizes_storage;
        ZxGpuIndexSignal kernel_starts_storage;
        ZxGpuIndexSignal kernel_offsets_storage;
        ZxGpuRealSignal kernel_real_storage;
        ZxGpuRealSignal kernel_imag_storage;
        std::string cwt_cache_wavelet;
        std::size_t cwt_cache_data_count = 0;
        std::size_t cwt_cache_max_kernel_size = 0;
        RealSignal cwt_cache_widths;
        bool cwt_cache_valid = false;
    };

    thread_local WaveletsWorkspace g_workspace;

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    std::size_t to_size(int value)
    {
        return value > 0 ? static_cast<std::size_t>(value) : 0;
    }

    __device__ inline float2 make_complex(float real, float imag)
    {
        return float2{real, imag};
    }

    __global__ void qmf_kernel(const float *input, float *output, std::size_t count)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        const float sign = (index % 2 == 0) ? 1.0 : -1.0;
        output[index] = input[count - 1 - index] * sign;
    }

    __global__ void morlet_kernel(
        float2 *output,
        std::size_t count,
        float w,
        float start,
        float step,
        float correction,
        bool complete)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        const float x = start + step * static_cast<float>(index);
        const float gaussian = expf(-0.5f * x * x) * detail::kPiNegQuarter;
        const float phase = w * x;
        output[index] = make_complex(
            (cosf(phase) - (complete ? correction : 0.0f)) * gaussian,
            sinf(phase) * gaussian);
    }

    __global__ void ricker_kernel(
        float *output,
        std::size_t count,
        float amplitude,
        float inv_a_sq,
        float inv_two_a_sq)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        const float x = detail::centered_coordinate(index, count);
        const float xsq = x * x;
        output[index] =
            amplitude * (1.0f - xsq * inv_a_sq) * expf(-xsq * inv_two_a_sq);
    }

    __global__ void morlet2_kernel(
        float2 *output,
        std::size_t count,
        float inv_s,
        float amplitude,
        float w)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        const float x = detail::centered_coordinate(index, count) * inv_s;
        const float scaled = amplitude * expf(-0.5f * x * x);
        const float phase = w * x;
        output[index] = make_complex(cosf(phase) * scaled, sinf(phase) * scaled);
    }

    __global__ void cwt_kernel(
        const float *data,
        std::size_t width_count,
        std::size_t data_count,
        const int *kernel_sizes,
        const int *kernel_starts,
        const int *kernel_offsets,
        const float *kernel_real,
        const float *kernel_imag,
        float2 *output)
    {
        const std::size_t flat_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = width_count * data_count;
        if (flat_index >= total)
        {
            return;
        }

        const std::size_t width_index = flat_index / data_count;
        const std::size_t sample_index = flat_index % data_count;
        const int kernel_size = kernel_sizes[width_index];
        if (kernel_size <= 0 || data_count == 0)
        {
            output[flat_index] = make_complex(0.0, 0.0);
            return;
        }

        const int start = kernel_starts[width_index];
        const int kernel_offset = kernel_offsets[width_index];

        float real = 0.0;
        float imag = 0.0;
        for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
        {
            const long x_index =
                static_cast<long>(sample_index) + static_cast<long>(start) -
                static_cast<long>(kernel_index);
            if (x_index < 0 || x_index >= static_cast<long>(data_count))
            {
                continue;
            }

            const float sample = data[static_cast<std::size_t>(x_index)];
            const std::size_t table_index = static_cast<std::size_t>(kernel_offset + kernel_index);
            real = fmaf(sample, kernel_real[table_index], real);
            imag = fmaf(sample, kernel_imag[table_index], imag);
        }
        output[flat_index] = make_complex(real, imag);
    }

    __global__ void cwt_ricker_real_kernel(
        const float *data,
        std::size_t width_count,
        std::size_t data_count,
        const int *kernel_sizes,
        const int *kernel_starts,
        const int *kernel_offsets,
        const float *kernel_real,
        float2 *output)
    {
        const std::size_t flat_index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = width_count * data_count;
        if (flat_index >= total)
        {
            return;
        }

        const std::size_t width_index = flat_index / data_count;
        const std::size_t sample_index = flat_index % data_count;
        const int kernel_size = kernel_sizes[width_index];
        if (kernel_size <= 0 || data_count == 0)
        {
            output[flat_index] = make_complex(0.0f, 0.0f);
            return;
        }

        const int start = kernel_starts[width_index];
        const int kernel_offset = kernel_offsets[width_index];
        float real = 0.0f;
        for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
        {
            const long x_index =
                static_cast<long>(sample_index) + static_cast<long>(start) -
                static_cast<long>(kernel_index);
            if (x_index < 0 || x_index >= static_cast<long>(data_count))
            {
                continue;
            }

            const float sample = data[static_cast<std::size_t>(x_index)];
            const std::size_t table_index = static_cast<std::size_t>(kernel_offset + kernel_index);
            real = fmaf(sample, kernel_real[table_index], real);
        }
        output[flat_index] = make_complex(real, 0.0f);
    }

    __global__ void cwt_ricker_shared_kernel(
        const float *data,
        std::size_t data_count,
        const int *kernel_sizes,
        const int *kernel_starts,
        const int *kernel_offsets,
        const float *kernel_real,
        float2 *output)
    {
        const std::size_t width_index = static_cast<std::size_t>(blockIdx.y);
        const std::size_t tile_start = static_cast<std::size_t>(blockIdx.x) * blockDim.x;
        const int kernel_size = kernel_sizes[width_index];
        if (kernel_size <= 0 || data_count == 0)
        {
            return;
        }

        extern __shared__ float tile_data[];
        const int start = kernel_starts[width_index];
        const long base =
            static_cast<long>(tile_start) + static_cast<long>(start) -
            static_cast<long>(kernel_size - 1);
        const int shared_count = blockDim.x + kernel_size - 1;
        for (int local_index = threadIdx.x; local_index < shared_count; local_index += blockDim.x)
        {
            const long global_index = base + local_index;
            tile_data[local_index] =
                (global_index >= 0 && global_index < static_cast<long>(data_count))
                    ? data[static_cast<std::size_t>(global_index)]
                    : 0.0f;
        }
        __syncthreads();

        const std::size_t sample_index = tile_start + threadIdx.x;
        if (sample_index >= data_count)
        {
            return;
        }

        const int kernel_offset = kernel_offsets[width_index];
        float real = 0.0f;
        for (int kernel_index = 0; kernel_index < kernel_size; ++kernel_index)
        {
            const int shared_index = threadIdx.x + kernel_size - 1 - kernel_index;
            const std::size_t table_index = static_cast<std::size_t>(kernel_offset + kernel_index);
            real = fmaf(tile_data[shared_index], kernel_real[table_index], real);
        }
        output[width_index * data_count + sample_index] = make_complex(real, 0.0f);
    }

} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace wavelets
        {

            core::ZxGpuRealSignal qmf(const core::RealSignalLike &hk)
            {
                const core::ZxGpuRealSignal &hk_device =
                    core::as_device_signal(hk, g_workspace.hk_storage);
                if (hk_device.empty())
                {
                    g_last_kernel_ms = 0.0;
                    return ZxGpuRealSignal();
                }

                ZxGpuRealSignal output(hk_device.size());
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    qmf_kernel<<<block_count(hk_device.size()), kThreadsPerBlock>>>(
                        hk_device.data(),
                        output.data(),
                        hk_device.size());
                    check_kernel_launch("qmf_kernel");
                }));
                return output;
            }

            core::ZxGpuComplexSignal morlet(int points, float w, float s, bool complete)
            {
                detail::ensure_non_negative_points(points);
                detail::ensure_positive(s, "s");

                const std::size_t count = to_size(points);
                if (count == 0)
                {
                    g_last_kernel_ms = 0.0;
                    return ZxGpuComplexSignal();
                }

                ZxGpuComplexSignal output(count);
                const float start = count <= 1 ? 0.0f : -s * detail::kTwoPi;
                const float step =
                    count <= 1 ? 0.0f : (2.0f * s * detail::kTwoPi) / static_cast<float>(count - 1);
                const float correction = expf(-0.5f * w * w);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    morlet_kernel<<<block_count(count), kThreadsPerBlock>>>(
                        reinterpret_cast<float2 *>(output.data()),
                        count,
                        w,
                        start,
                        step,
                        correction,
                        complete);
                    check_kernel_launch("morlet_kernel");
                }));
                return output;
            }

            core::ZxGpuRealSignal ricker(int points, float a)
            {
                detail::ensure_non_negative_points(points);
                detail::ensure_positive(a, "a");

                const std::size_t count = to_size(points);
                if (count == 0)
                {
                    g_last_kernel_ms = 0.0;
                    return ZxGpuRealSignal();
                }

                ZxGpuRealSignal output(count);
                const float a_sq = a * a;
                const float amplitude =
                    2.0f / (std::sqrt(3.0f * a) * std::pow(detail::kPi, 0.25f));
                const float inv_a_sq = 1.0f / a_sq;
                const float inv_two_a_sq = 0.5f / a_sq;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    ricker_kernel<<<block_count(count), kThreadsPerBlock>>>(
                        output.data(),
                        count,
                        amplitude,
                        inv_a_sq,
                        inv_two_a_sq);
                    check_kernel_launch("ricker_kernel");
                }));
                return output;
            }

            core::ZxGpuComplexSignal morlet2(int points, float s, float w)
            {
                detail::ensure_non_negative_points(points);
                detail::ensure_positive(s, "s");

                const std::size_t count = to_size(points);
                if (count == 0)
                {
                    g_last_kernel_ms = 0.0;
                    return ZxGpuComplexSignal();
                }

                ZxGpuComplexSignal output(count);
                const float inv_s = 1.0f / s;
                const float amplitude = std::sqrt(inv_s) * detail::kPiNegQuarter;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    morlet2_kernel<<<block_count(count), kThreadsPerBlock>>>(
                        reinterpret_cast<float2 *>(output.data()),
                        count,
                        inv_s,
                        amplitude,
                        w);
                    check_kernel_launch("morlet2_kernel");
                }));
                return output;
            }

            core::ZxGpuComplexArray cwt(
                const core::RealSignalLike &data,
                const std::string &wavelet,
                const core::RealSignalLike &widths)
            {
                detail::ensure_supported_wavelet(wavelet);

                const core::ZxGpuRealSignal &data_device =
                    core::as_device_signal(data, g_workspace.data_storage);

                RealSignal host_widths;
                const core::ZxGpuRealSignal *widths_device = nullptr;
                if (const auto *host = std::get_if<RealSignal>(&widths))
                {
                    host_widths = *host;
                    detail::ensure_non_empty_widths(host_widths.size());
                    detail::ensure_positive_widths(host_widths);
                    g_workspace.widths_storage.copy_from(host_widths);
                    widths_device = &g_workspace.widths_storage;
                }
                else
                {
                    const auto &device = std::get<core::ZxGpuRealSignal>(widths);
                    detail::ensure_non_empty_widths(device.size());
                    host_widths = device.get();
                    widths_device = &device;
                }
                detail::ensure_positive_widths(host_widths);

                if (!g_workspace.cwt_cache_valid ||
                    g_workspace.cwt_cache_wavelet != wavelet ||
                    g_workspace.cwt_cache_data_count != data_device.size() ||
                    g_workspace.cwt_cache_widths != host_widths)
                {
                    const detail::CwtKernelTable kernel_table =
                        detail::build_cwt_kernel_table(host_widths, data_device.size(), wavelet);
                    g_workspace.cwt_cache_max_kernel_size =
                        kernel_table.kernel_sizes.empty()
                            ? 0
                            : static_cast<std::size_t>(*std::max_element(
                                  kernel_table.kernel_sizes.begin(),
                                  kernel_table.kernel_sizes.end()));
                    g_workspace.kernel_sizes_storage = ZxGpuIndexSignal::from_host(kernel_table.kernel_sizes);
                    g_workspace.kernel_starts_storage = ZxGpuIndexSignal::from_host(kernel_table.kernel_starts);
                    g_workspace.kernel_offsets_storage = ZxGpuIndexSignal::from_host(kernel_table.kernel_offsets);
                    g_workspace.kernel_real_storage = ZxGpuRealSignal::from_host(kernel_table.kernel_real);
                    g_workspace.kernel_imag_storage = ZxGpuRealSignal::from_host(kernel_table.kernel_imag);
                    g_workspace.cwt_cache_wavelet = wavelet;
                    g_workspace.cwt_cache_data_count = data_device.size();
                    g_workspace.cwt_cache_widths = host_widths;
                    g_workspace.cwt_cache_valid = true;
                }

                const core::Shape output_shape{widths_device->size(), data_device.size()};
                if (data_device.size() == 0)
                {
                    g_last_kernel_ms = 0.0;
                    return ZxGpuComplexArray(output_shape, false);
                }

                ZxGpuComplexArray output(output_shape, false);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    constexpr std::size_t kMaxSharedKernelSize = 2048;
                    if (wavelet == "ricker" &&
                        g_workspace.cwt_cache_max_kernel_size > 0 &&
                        g_workspace.cwt_cache_max_kernel_size <= kMaxSharedKernelSize)
                    {
                        const std::size_t shared_bytes =
                            (static_cast<std::size_t>(kThreadsPerBlock) +
                             g_workspace.cwt_cache_max_kernel_size - 1) *
                            sizeof(float);
                        const dim3 grid(
                            static_cast<unsigned int>(block_count(data_device.size())),
                            static_cast<unsigned int>(widths_device->size()));
                        cwt_ricker_shared_kernel<<<grid, kThreadsPerBlock, shared_bytes>>>(
                            data_device.data(),
                            data_device.size(),
                            g_workspace.kernel_sizes_storage.data(),
                            g_workspace.kernel_starts_storage.data(),
                            g_workspace.kernel_offsets_storage.data(),
                            g_workspace.kernel_real_storage.data(),
                            reinterpret_cast<float2 *>(output.data()));
                        check_kernel_launch("cwt_ricker_shared_kernel");
                    }
                    else if (wavelet == "ricker")
                    {
                        cwt_ricker_real_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                            data_device.data(),
                            widths_device->size(),
                            data_device.size(),
                            g_workspace.kernel_sizes_storage.data(),
                            g_workspace.kernel_starts_storage.data(),
                            g_workspace.kernel_offsets_storage.data(),
                            g_workspace.kernel_real_storage.data(),
                            reinterpret_cast<float2 *>(output.data()));
                        check_kernel_launch("cwt_ricker_real_kernel");
                    }
                    else
                    {
                        cwt_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                            data_device.data(),
                            widths_device->size(),
                            data_device.size(),
                            g_workspace.kernel_sizes_storage.data(),
                            g_workspace.kernel_starts_storage.data(),
                            g_workspace.kernel_offsets_storage.data(),
                            g_workspace.kernel_real_storage.data(),
                            g_workspace.kernel_imag_storage.data(),
                            reinterpret_cast<float2 *>(output.data()));
                        check_kernel_launch("cwt_kernel");
                    }
                }));
                return output;
            }

        } // namespace wavelets

        namespace wavelets_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0;
                return value;
            }
        } // namespace wavelets_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
