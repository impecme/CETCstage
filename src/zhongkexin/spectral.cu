#include "cusignal/spectral/spectral.hpp"

#include <cuda_runtime.h>
#include <cufft.h>

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstring>
#include <functional>
#include <numeric>
#include <stdexcept>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/windows/windows.hpp"

#include "../common/spectral_detail.hpp"
#include "../common/zx_execution_context.hpp"
#include "../common/zx_tile_policy.hpp"

namespace
{
    using cusignal::core::Complex;
    using cusignal::core::ComplexArrayLike;
    using cusignal::core::ComplexSignalLike;
    using cusignal::core::ZxGpuComplexArray;
    using cusignal::core::ZxGpuComplexSignal;
    using cusignal::core::ZxGpuRealArray;
    using cusignal::core::ZxGpuRealSignal;
    using cusignal::core::ZxGpuWindowSpec;
    using cusignal::core::DetrendSpec;
    using cusignal::core::RealArrayLike;
    using cusignal::core::RealSignal;
    using cusignal::core::RealSignalLike;
    using cusignal::core::Shape;
    namespace detail = cusignal::spectral_detail;
    namespace tile = cusignal::zx_tile;

    constexpr int kThreadsPerBlock = 256;
    constexpr float kPi = 3.141592653589793238462643383279502884;
    constexpr float kVectorStrengthPhaseFloor = 1.0e-5f;
    constexpr int kVectorStrengthMaxBlocksPerPeriod = 1024;
    constexpr int kVectorStrengthPairMinBlocksPerPeriod = 256;
    constexpr int kPeriodogramCacheAuto = -1;
    constexpr int kPeriodogramCacheBypass = 0;
    constexpr int kPeriodogramCacheEnabled = 1;
    constexpr int kPeriodogramCacheStateBypass = 0;
    constexpr int kPeriodogramCacheStateMiss = 1;
    constexpr int kPeriodogramCacheStateHit = 2;
    constexpr int kWelchCacheAuto = -1;
    constexpr int kWelchCacheBypass = 0;
    constexpr int kWelchCacheEnabled = 1;
    constexpr int kWelchCacheStateBypass = 0;
    constexpr int kWelchCacheStateMiss = 1;
    constexpr int kWelchCacheStateHit = 2;
    constexpr int kIstftCacheAuto = -1;
    constexpr int kIstftCacheBypass = 0;
    constexpr int kIstftCacheEnabled = 1;
    constexpr int kIstftCacheStateBypass = 0;
    constexpr int kIstftCacheStateMiss = 1;
    constexpr int kIstftCacheStateHit = 2;
    thread_local float g_last_kernel_ms = 0.0;
    thread_local int g_periodogram_cache_override = kPeriodogramCacheAuto;
    thread_local int g_last_periodogram_cache_state = kPeriodogramCacheStateBypass;
    thread_local bool g_periodogram_cache_reset_requested = false;
    thread_local int g_welch_cache_override = kWelchCacheAuto;
    thread_local int g_last_welch_cache_state = kWelchCacheStateBypass;
    thread_local bool g_welch_cache_reset_requested = false;
    thread_local int g_istft_cache_override = kIstftCacheAuto;
    thread_local int g_last_istft_cache_state = kIstftCacheStateBypass;
    thread_local bool g_istft_cache_reset_requested = false;

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
        throw std::runtime_error(std::string(what) + ": cuFFT error code " + std::to_string(static_cast<int>(status)));
    }

    void check_kernel_launch(const char *what)
    {
        throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

    template <typename T>
    using DeviceBuffer = cusignal::zx_execution::ReusableDeviceBuffer<T>;

    struct GenericPlan
    {
        cufftHandle handle = 0;
        int size = 0;
        int batch = 0;

        ~GenericPlan()
        {
            if (handle != 0)
            {
                cufftDestroy(handle);
            }
        }

        void ensure(int n, int b)
        {
            if (handle != 0 && size == n && batch == b)
            {
                return;
            }
            if (handle != 0)
            {
                throw_on_cufft_error(cufftDestroy(handle), "cufftDestroy");
                handle = 0;
                size = 0;
                batch = 0;
            }
            throw_on_cufft_error(cufftPlan1d(&handle, n, CUFFT_C2C, b), "cufftPlan1d");
            size = n;
            batch = b;
        }
    };

    struct RealForwardPlan
    {
        cufftHandle handle = 0;
        int size = 0;
        int batch = 0;

        ~RealForwardPlan()
        {
            if (handle != 0)
            {
                cufftDestroy(handle);
            }
        }

        void ensure(int n, int b)
        {
            if (handle != 0 && size == n && batch == b)
            {
                return;
            }
            if (handle != 0)
            {
                throw_on_cufft_error(cufftDestroy(handle), "cufftDestroy");
                handle = 0;
                size = 0;
                batch = 0;
            }
            throw_on_cufft_error(cufftPlan1d(&handle, n, CUFFT_R2C, b), "cufftPlan1d(R2C)");
            size = n;
            batch = b;
        }
    };

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

    struct SpectralWorkspace
    {
        ZxGpuRealArray x_storage;
        ZxGpuRealArray y_storage;
        ZxGpuComplexArray z_storage;
        ZxGpuRealSignal x_signal_storage;
        ZxGpuRealSignal y_signal_storage;
        ZxGpuRealSignal period_storage;
        ZxGpuRealSignal freq_storage;
        DeviceBuffer<cufftComplex> fft_x;
        DeviceBuffer<cufftComplex> fft_y;
        DeviceBuffer<cufftComplex> fft_full;
        DeviceBuffer<float> real_fft_x;
        DeviceBuffer<float> real_fft_y;
        DeviceBuffer<cufftComplex> rfft_x;
        DeviceBuffer<cufftComplex> rfft_y;
        DeviceBuffer<float> real_scratch;
        DeviceBuffer<float> norm_scratch;
        DeviceBuffer<float> reduction_scratch_a;
        DeviceBuffer<float> reduction_scratch_b;
        ZxGpuRealSignal periodogram_window_storage;
        std::string periodogram_window_key;
        float periodogram_window_scale = 0.0f;
        bool periodogram_window_valid = false;
        ZxGpuRealSignal csd_window_storage;
        std::string csd_window_key;
        float csd_window_scale = 0.0f;
        bool csd_window_valid = false;
        ZxGpuRealSignal segment_window_storage;
        std::string segment_window_key;
        float segment_window_scale = 0.0f;
        bool segment_window_valid = false;
        ZxGpuRealSignal frequency_axis_storage;
        std::string frequency_axis_key;
        bool frequency_axis_valid = false;
        ZxGpuRealSignal time_axis_storage;
        std::string time_axis_key;
        bool time_axis_valid = false;
        RealSignal vectorstrength_period_cache;
        bool vectorstrength_period_cache_valid = false;
        GenericPlan forward_plan;
        GenericPlan inverse_plan;
        RealForwardPlan real_forward_plan;
    };

    inline int block_count(std::size_t count)
    {
        return count == 0 ? 0 : static_cast<int>((count + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    std::string float_cache_key(float value)
    {
        static_assert(sizeof(float) == sizeof(std::uint32_t), "float32 cache key");
        std::uint32_t bits = 0;
        std::memcpy(&bits, &value, sizeof(bits));
        return std::to_string(bits);
    }

    bool build_csd_window_cache_key(
        const ZxGpuWindowSpec &window,
        int size,
        float fs,
        const std::string &scaling,
        std::string &key)
    {
        key = "size=" + std::to_string(size) +
              ";fs=" + float_cache_key(fs) +
              ";scaling=" + scaling + ";";
        if (const auto *name = std::get_if<std::string>(&window))
        {
            key += "name=" + *name;
            return true;
        }
        if (const auto *value = std::get_if<float>(&window))
        {
            key += "scalar=" + float_cache_key(*value);
            return true;
        }
        if (const auto *value = std::get_if<cusignal::core::NamedFloatParameter>(&window))
        {
            key += "named1=" + value->name + ":" + float_cache_key(value->value);
            return true;
        }
        if (const auto *value = std::get_if<cusignal::core::NamedFloatPairParameter>(&window))
        {
            key += "named2=" + value->name + ":" +
                   float_cache_key(value->first) + ":" +
                   float_cache_key(value->second);
            return true;
        }
        if (const auto *value = std::get_if<cusignal::core::NamedTaylorParameter>(&window))
        {
            key += "taylor=" + value->name + ":" +
                   std::to_string(value->nbar) + ":" +
                   float_cache_key(value->sll) + ":" +
                   (value->norm ? "1" : "0");
            return true;
        }
        return false;
    }

    const ZxGpuRealSignal &cached_frequency_axis(
        SpectralWorkspace &workspace,
        int nfft,
        float fs,
        bool onesided)
    {
        const std::string key =
            "nfft=" + std::to_string(nfft) +
            ";fs=" + float_cache_key(fs) +
            ";onesided=" + (onesided ? std::string("1") : std::string("0"));
        if (!workspace.frequency_axis_valid || workspace.frequency_axis_key != key)
        {
            workspace.frequency_axis_storage = ZxGpuRealSignal::from_host(
                detail::frequency_axis(nfft, fs, onesided));
            workspace.frequency_axis_key = key;
            workspace.frequency_axis_valid = true;
        }
        return workspace.frequency_axis_storage;
    }

    const ZxGpuRealSignal &cached_segment_times(
        SpectralWorkspace &workspace,
        std::size_t input_size,
        int nperseg,
        int step,
        float fs,
        bool boundary)
    {
        const std::string key =
            "input=" + std::to_string(input_size) +
            ";nperseg=" + std::to_string(nperseg) +
            ";step=" + std::to_string(step) +
            ";fs=" + float_cache_key(fs) +
            ";boundary=" + (boundary ? std::string("1") : std::string("0"));
        if (!workspace.time_axis_valid || workspace.time_axis_key != key)
        {
            workspace.time_axis_storage = ZxGpuRealSignal::from_host(
                detail::segment_times(input_size, nperseg, step, fs, boundary));
            workspace.time_axis_key = key;
            workspace.time_axis_valid = true;
        }
        return workspace.time_axis_storage;
    }

    const ZxGpuRealSignal &cached_sample_times(
        SpectralWorkspace &workspace,
        std::size_t output_size,
        float fs,
        bool *cache_hit)
    {
        const std::string key =
            "output=" + std::to_string(output_size) +
            ";fs=" + float_cache_key(fs);
        *cache_hit =
            workspace.time_axis_valid && workspace.time_axis_key == key;
        if (!*cache_hit)
        {
            RealSignal times(output_size, 0.0);
            for (std::size_t index = 0; index < output_size; ++index)
            {
                times[index] = static_cast<float>(index) / fs;
            }
            workspace.time_axis_storage =
                ZxGpuRealSignal::from_host(times);
            workspace.time_axis_key = key;
            workspace.time_axis_valid = true;
        }
        return workspace.time_axis_storage;
    }

    __device__ void kahan_add(float value, float &sum, float &compensation)
    {
        const float corrected = value - compensation;
        const float next = sum + corrected;
        compensation = (next - sum) - corrected;
        sum = next;
    }

    __device__ float vectorstrength_angle(float event, float period)
    {
        const float turns = event / period;
        const float wrapped = turns - floorf(turns);
        return 2.0f * kPi * wrapped;
    }

    __device__ void vectorstrength_sincos_poly(float angle, float &s, float &c)
    {
        constexpr float two_pi = 2.0f * kPi;
        constexpr float half_pi = 0.5f * kPi;
        if (angle > kPi)
        {
            angle -= two_pi;
        }
        float cos_sign = 1.0f;
        if (angle > half_pi)
        {
            angle = kPi - angle;
            cos_sign = -1.0f;
        }
        else if (angle < -half_pi)
        {
            angle = -kPi - angle;
            cos_sign = -1.0f;
        }
        const float x2 = angle * angle;
        const float x4 = x2 * x2;
        const float x6 = x4 * x2;
        const float x8 = x4 * x4;
        s = angle * (1.0f - x2 * (1.0f / 6.0f) + x4 * (1.0f / 120.0f) -
                     x6 * (1.0f / 5040.0f) + x8 * (1.0f / 362880.0f));
        c = cos_sign * (1.0f - x2 * 0.5f + x4 * (1.0f / 24.0f) -
                        x6 * (1.0f / 720.0f) + x8 * (1.0f / 40320.0f));
    }

    __device__ void lombscargle_sincos_fast(float angle, float &s, float &c)
    {
        constexpr float two_pi = 2.0f * kPi;
        angle -= floorf(angle / two_pi) * two_pi;
        vectorstrength_sincos_poly(angle, s, c);
    }

    inline int boundary_mode_code(const std::string &boundary)
    {
        if (boundary == "none")
        {
            return 0;
        }
        if (boundary == "zeros")
        {
            return 1;
        }
        if (boundary == "constant")
        {
            return 2;
        }
        if (boundary == "even")
        {
            return 3;
        }
        return 4;
    }

    inline int detrend_mode_code(const DetrendSpec &detrend)
    {
        if (detail::detrend_disabled(detrend))
        {
            return 0;
        }
        const std::string type = detail::detrend_type(detrend);
        if (type == "constant")
        {
            return 1;
        }
        if (type == "linear")
        {
            return 2;
        }
        return 0;
    }

    inline std::size_t line_count_last_axis(const cusignal::core::Shape &shape)
    {
        if (shape.empty())
        {
            return 0;
        }
        return cusignal::core::shape_product(shape) / shape.back();
    }

    __device__ float read_boundary_value(
        const float *line,
        int line_len,
        int raw_index,
        int boundary_mode)
    {
        if (raw_index >= 0 && raw_index < line_len)
        {
            return line[raw_index];
        }
        if (boundary_mode == 1)
        {
            return 0.0;
        }
        if (boundary_mode == 2)
        {
            return raw_index < 0 ? line[0] : line[line_len - 1];
        }
        if (boundary_mode == 3)
        {
            if (raw_index < 0)
            {
                return line[-raw_index];
            }
            return line[2 * line_len - 2 - raw_index];
        }
        if (boundary_mode == 4)
        {
            if (raw_index < 0)
            {
                return 2.0 * line[0] - line[-raw_index];
            }
            return 2.0 * line[line_len - 1] - line[2 * line_len - 2 - raw_index];
        }
        return 0.0;
    }

    __global__ void lombscargle_sum_kernel(
        const float *values,
        int sample_count,
        float *partials)
    {
        __shared__ float cache[kThreadsPerBlock];
        float sum = 0.0f;
        for (int index = blockIdx.x * blockDim.x + threadIdx.x;
             index < sample_count;
             index += gridDim.x * blockDim.x)
        {
            sum += values[index];
        }
        cache[threadIdx.x] = sum;
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
            partials[blockIdx.x] = cache[0];
        }
    }

    __global__ void lombscargle_dot_kernel(
        const float *values,
        int sample_count,
        const float *mean,
        bool precenter,
        float *partials)
    {
        __shared__ float cache[kThreadsPerBlock];
        const float center = precenter ? mean[0] : 0.0f;
        float sum = 0.0f;
        for (int index = blockIdx.x * blockDim.x + threadIdx.x;
             index < sample_count;
             index += gridDim.x * blockDim.x)
        {
            const float value = values[index] - center;
            sum = fmaf(value, value, sum);
        }
        cache[threadIdx.x] = sum;
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
            partials[blockIdx.x] = cache[0];
        }
    }

    __global__ void lombscargle_finalize_sum_kernel(
        const float *partials,
        int partial_count,
        float scale,
        float *output)
    {
        __shared__ float cache[kThreadsPerBlock];
        float sum = 0.0f;
        for (int index = threadIdx.x; index < partial_count; index += blockDim.x)
        {
            sum += partials[index];
        }
        cache[threadIdx.x] = sum;
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
            output[0] = cache[0] * scale;
        }
    }

    __global__ void lombscargle_parallel_kernel(
        const float *x,
        const float *y,
        const float *freqs,
        int sample_count,
        int freq_count,
        const float *y_mean,
        const float *y_dot,
        bool precenter,
        bool normalize,
        float *output)
    {
        const int freq_index = blockIdx.x;
        if (freq_index >= freq_count)
        {
            return;
        }

        __shared__ float xc_cache[kThreadsPerBlock];
        __shared__ float xs_cache[kThreadsPerBlock];
        __shared__ float cc_cache[kThreadsPerBlock];
        __shared__ float ss_cache[kThreadsPerBlock];

        const float w = freqs[freq_index];
        const float center = precenter ? y_mean[0] : 0.0f;
        float xc = 0.0f;
        float xs = 0.0f;
        float cc = 0.0f;
        float ss = 0.0f;
        for (int sample = threadIdx.x; sample < sample_count; sample += blockDim.x)
        {
            float s = 0.0f;
            float c = 0.0f;
            lombscargle_sincos_fast(w * x[sample], s, c);
            const float y_value = y[sample] - center;
            xc = fmaf(y_value, c, xc);
            xs = fmaf(y_value, s, xs);
            cc = fmaf(c, c, cc);
            ss = fmaf(s, s, ss);
        }

        xc_cache[threadIdx.x] = xc;
        xs_cache[threadIdx.x] = xs;
        cc_cache[threadIdx.x] = cc;
        ss_cache[threadIdx.x] = ss;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                xc_cache[threadIdx.x] += xc_cache[threadIdx.x + stride];
                xs_cache[threadIdx.x] += xs_cache[threadIdx.x + stride];
                cc_cache[threadIdx.x] += cc_cache[threadIdx.x + stride];
                ss_cache[threadIdx.x] += ss_cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x != 0)
        {
            return;
        }

        const float xc_sum = xc_cache[0];
        const float xs_sum = xs_cache[0];
        const float cc_sum = cc_cache[0];
        const float ss_sum = ss_cache[0];
        const float power =
            0.5f * ((cc_sum > 0.0f ? (xc_sum * xc_sum) / cc_sum : 0.0f) +
                    (ss_sum > 0.0f ? (xs_sum * xs_sum) / ss_sum : 0.0f));
        const float dot = normalize ? y_dot[0] : 0.0f;
        output[freq_index] = normalize && dot > 0.0f ? (2.0f * power / dot) : power;
    }

    __global__ void lombscargle_parallel_pair_kernel(
        const float *x,
        const float *y,
        const float *freqs,
        int sample_count,
        int freq_count,
        const float *y_mean,
        const float *y_dot,
        bool precenter,
        bool normalize,
        float *output)
    {
        const int freq_index0 = 2 * static_cast<int>(blockIdx.x);
        if (freq_index0 >= freq_count)
        {
            return;
        }
        const int freq_index1 = freq_index0 + 1;
        const bool has_second = freq_index1 < freq_count;

        __shared__ float xc0_cache[kThreadsPerBlock];
        __shared__ float xs0_cache[kThreadsPerBlock];
        __shared__ float cc0_cache[kThreadsPerBlock];
        __shared__ float ss0_cache[kThreadsPerBlock];
        __shared__ float xc1_cache[kThreadsPerBlock];
        __shared__ float xs1_cache[kThreadsPerBlock];
        __shared__ float cc1_cache[kThreadsPerBlock];
        __shared__ float ss1_cache[kThreadsPerBlock];

        const float w0 = freqs[freq_index0];
        const float w1 = has_second ? freqs[freq_index1] : 0.0f;
        const float center = precenter ? y_mean[0] : 0.0f;
        float xc0 = 0.0f;
        float xs0 = 0.0f;
        float cc0 = 0.0f;
        float ss0 = 0.0f;
        float xc1 = 0.0f;
        float xs1 = 0.0f;
        float cc1 = 0.0f;
        float ss1 = 0.0f;
        for (int sample = threadIdx.x; sample < sample_count; sample += blockDim.x)
        {
            const float x_value = x[sample];
            const float y_value = y[sample] - center;
            float s0 = 0.0f;
            float c0 = 0.0f;
            lombscargle_sincos_fast(w0 * x_value, s0, c0);
            xc0 = fmaf(y_value, c0, xc0);
            xs0 = fmaf(y_value, s0, xs0);
            cc0 = fmaf(c0, c0, cc0);
            ss0 = fmaf(s0, s0, ss0);

            if (has_second)
            {
                float s1 = 0.0f;
                float c1 = 0.0f;
                lombscargle_sincos_fast(w1 * x_value, s1, c1);
                xc1 = fmaf(y_value, c1, xc1);
                xs1 = fmaf(y_value, s1, xs1);
                cc1 = fmaf(c1, c1, cc1);
                ss1 = fmaf(s1, s1, ss1);
            }
        }

        xc0_cache[threadIdx.x] = xc0;
        xs0_cache[threadIdx.x] = xs0;
        cc0_cache[threadIdx.x] = cc0;
        ss0_cache[threadIdx.x] = ss0;
        xc1_cache[threadIdx.x] = xc1;
        xs1_cache[threadIdx.x] = xs1;
        cc1_cache[threadIdx.x] = cc1;
        ss1_cache[threadIdx.x] = ss1;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride >= 64; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                xc0_cache[threadIdx.x] += xc0_cache[threadIdx.x + stride];
                xs0_cache[threadIdx.x] += xs0_cache[threadIdx.x + stride];
                cc0_cache[threadIdx.x] += cc0_cache[threadIdx.x + stride];
                ss0_cache[threadIdx.x] += ss0_cache[threadIdx.x + stride];
                xc1_cache[threadIdx.x] += xc1_cache[threadIdx.x + stride];
                xs1_cache[threadIdx.x] += xs1_cache[threadIdx.x + stride];
                cc1_cache[threadIdx.x] += cc1_cache[threadIdx.x + stride];
                ss1_cache[threadIdx.x] += ss1_cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x < 32)
        {
            for (int stride = 32; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    xc0_cache[threadIdx.x] += xc0_cache[threadIdx.x + stride];
                    xs0_cache[threadIdx.x] += xs0_cache[threadIdx.x + stride];
                    cc0_cache[threadIdx.x] += cc0_cache[threadIdx.x + stride];
                    ss0_cache[threadIdx.x] += ss0_cache[threadIdx.x + stride];
                    xc1_cache[threadIdx.x] += xc1_cache[threadIdx.x + stride];
                    xs1_cache[threadIdx.x] += xs1_cache[threadIdx.x + stride];
                    cc1_cache[threadIdx.x] += cc1_cache[threadIdx.x + stride];
                    ss1_cache[threadIdx.x] += ss1_cache[threadIdx.x + stride];
                }
                __syncwarp();
            }
        }
        if (threadIdx.x != 0)
        {
            return;
        }

        const float power0 =
            0.5f * ((cc0_cache[0] > 0.0f ? (xc0_cache[0] * xc0_cache[0]) / cc0_cache[0] : 0.0f) +
                    (ss0_cache[0] > 0.0f ? (xs0_cache[0] * xs0_cache[0]) / ss0_cache[0] : 0.0f));
        const float dot = normalize ? y_dot[0] : 0.0f;
        output[freq_index0] = normalize && dot > 0.0f ? (2.0f * power0 / dot) : power0;

        if (has_second)
        {
            const float power1 =
                0.5f * ((cc1_cache[0] > 0.0f ? (xc1_cache[0] * xc1_cache[0]) / cc1_cache[0] : 0.0f) +
                        (ss1_cache[0] > 0.0f ? (xs1_cache[0] * xs1_cache[0]) / ss1_cache[0] : 0.0f));
            output[freq_index1] =
                normalize && dot > 0.0f ? (2.0f * power1 / dot) : power1;
        }
    }

    __global__ void vectorstrength_partial_kernel(
        const float *events,
        int event_count,
        const float *periods,
        int period_count,
        int blocks_per_period,
        float *partial_real,
        float *partial_imag)
    {
        const int period_index = blockIdx.x;
        const int tile_index = blockIdx.y;
        if (period_index >= period_count)
        {
            return;
        }

        __shared__ float real_cache[kThreadsPerBlock];
        __shared__ float imag_cache[kThreadsPerBlock];

        const float period = periods[period_index];
        float sum_real = 0.0f;
        float sum_imag = 0.0f;
        float sum_real_c = 0.0f;
        float sum_imag_c = 0.0f;
        for (int sample = tile_index * blockDim.x + threadIdx.x;
             sample < event_count;
             sample += blocks_per_period * blockDim.x)
        {
            const float angle = vectorstrength_angle(events[sample], period);
            float s = 0.0f;
            float c = 0.0f;
            vectorstrength_sincos_poly(angle, s, c);
            kahan_add(c, sum_real, sum_real_c);
            kahan_add(s, sum_imag, sum_imag_c);
        }

        real_cache[threadIdx.x] = sum_real;
        imag_cache[threadIdx.x] = sum_imag;
        __syncthreads();

        for (int stride = blockDim.x / 2; stride >= 64; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                real_cache[threadIdx.x] += real_cache[threadIdx.x + stride];
                imag_cache[threadIdx.x] += imag_cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x < 32)
        {
            for (int stride = 32; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    real_cache[threadIdx.x] += real_cache[threadIdx.x + stride];
                    imag_cache[threadIdx.x] += imag_cache[threadIdx.x + stride];
                }
                __syncwarp();
            }
        }

        if (threadIdx.x == 0)
        {
            const int offset = period_index * blocks_per_period + tile_index;
            partial_real[offset] = real_cache[0];
            partial_imag[offset] = imag_cache[0];
        }
    }

    __global__ void vectorstrength_partial_pair_kernel(
        const float *events,
        int event_count,
        const float *periods,
        int blocks_per_period,
        float *partial_real,
        float *partial_imag)
    {
        const int first_period_index = blockIdx.x * 2;
        const int second_period_index = first_period_index + 1;
        const int tile_index = blockIdx.y;

        __shared__ float first_real_cache[kThreadsPerBlock];
        __shared__ float first_imag_cache[kThreadsPerBlock];
        __shared__ float second_real_cache[kThreadsPerBlock];
        __shared__ float second_imag_cache[kThreadsPerBlock];

        const float first_period = periods[first_period_index];
        const float second_period = periods[second_period_index];
        float first_sum_real = 0.0f;
        float first_sum_imag = 0.0f;
        float first_sum_real_c = 0.0f;
        float first_sum_imag_c = 0.0f;
        float second_sum_real = 0.0f;
        float second_sum_imag = 0.0f;
        float second_sum_real_c = 0.0f;
        float second_sum_imag_c = 0.0f;
        for (int sample = tile_index * blockDim.x + threadIdx.x;
             sample < event_count;
             sample += blocks_per_period * blockDim.x)
        {
            const float event = events[sample];
            float s = 0.0f;
            float c = 0.0f;
            vectorstrength_sincos_poly(vectorstrength_angle(event, first_period), s, c);
            kahan_add(c, first_sum_real, first_sum_real_c);
            kahan_add(s, first_sum_imag, first_sum_imag_c);

            vectorstrength_sincos_poly(vectorstrength_angle(event, second_period), s, c);
            kahan_add(c, second_sum_real, second_sum_real_c);
            kahan_add(s, second_sum_imag, second_sum_imag_c);
        }

        first_real_cache[threadIdx.x] = first_sum_real;
        first_imag_cache[threadIdx.x] = first_sum_imag;
        second_real_cache[threadIdx.x] = second_sum_real;
        second_imag_cache[threadIdx.x] = second_sum_imag;
        __syncthreads();

        for (int stride = blockDim.x / 2; stride >= 64; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                first_real_cache[threadIdx.x] += first_real_cache[threadIdx.x + stride];
                first_imag_cache[threadIdx.x] += first_imag_cache[threadIdx.x + stride];
                second_real_cache[threadIdx.x] += second_real_cache[threadIdx.x + stride];
                second_imag_cache[threadIdx.x] += second_imag_cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        if (threadIdx.x < 32)
        {
            for (int stride = 32; stride > 0; stride >>= 1)
            {
                if (threadIdx.x < stride)
                {
                    first_real_cache[threadIdx.x] += first_real_cache[threadIdx.x + stride];
                    first_imag_cache[threadIdx.x] += first_imag_cache[threadIdx.x + stride];
                    second_real_cache[threadIdx.x] += second_real_cache[threadIdx.x + stride];
                    second_imag_cache[threadIdx.x] += second_imag_cache[threadIdx.x + stride];
                }
                __syncwarp();
            }
        }

        if (threadIdx.x == 0)
        {
            const int first_offset = first_period_index * blocks_per_period + tile_index;
            const int second_offset = second_period_index * blocks_per_period + tile_index;
            partial_real[first_offset] = first_real_cache[0];
            partial_imag[first_offset] = first_imag_cache[0];
            partial_real[second_offset] = second_real_cache[0];
            partial_imag[second_offset] = second_imag_cache[0];
        }
    }

    __global__ void vectorstrength_finalize_kernel(
        const float *partial_real,
        const float *partial_imag,
        int event_count,
        int blocks_per_period,
        float *strength,
        float *phase)
    {
        const int period_index = blockIdx.x;
        __shared__ float real_cache[kThreadsPerBlock];
        __shared__ float imag_cache[kThreadsPerBlock];

        float sum_real = 0.0f;
        float sum_imag = 0.0f;
        float sum_real_c = 0.0f;
        float sum_imag_c = 0.0f;
        for (int tile = threadIdx.x; tile < blocks_per_period; tile += blockDim.x)
        {
            const int offset = period_index * blocks_per_period + tile;
            kahan_add(partial_real[offset], sum_real, sum_real_c);
            kahan_add(partial_imag[offset], sum_imag, sum_imag_c);
        }

        real_cache[threadIdx.x] = sum_real;
        imag_cache[threadIdx.x] = sum_imag;
        __syncthreads();

        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                real_cache[threadIdx.x] += real_cache[threadIdx.x + stride];
                imag_cache[threadIdx.x] += imag_cache[threadIdx.x + stride];
            }
            __syncthreads();
        }

        if (threadIdx.x != 0)
        {
            return;
        }
        sum_real = real_cache[0];
        sum_imag = imag_cache[0];
        if (event_count > 0)
        {
            const float scale = 1.0f / static_cast<float>(event_count);
            sum_real *= scale;
            sum_imag *= scale;
        }
        const float out_strength = hypotf(sum_real, sum_imag);
        strength[period_index] = out_strength;
        phase[period_index] = out_strength < kVectorStrengthPhaseFloor
                                  ? 0.0f
                                  : atan2f(sum_imag, sum_real);
    }

    __global__ void prepare_segments_kernel(
        const float *x,
        int line_count,
        int line_len,
        int nseg,
        int nperseg,
        int step,
        int nfft,
        int boundary_mode,
        int boundary_len,
        const float *window,
        int detrend_mode,
        cufftComplex *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(line_count) * nseg * nfft;
        if (index >= total)
        {
            return;
        }

        const int sample = static_cast<int>(index % static_cast<std::size_t>(nfft));
        const int seg = static_cast<int>((index / static_cast<std::size_t>(nfft)) % static_cast<std::size_t>(nseg));
        const int line = static_cast<int>(index / (static_cast<std::size_t>(nfft) * static_cast<std::size_t>(nseg)));
        cufftComplex value{0.0, 0.0};

        if (sample < nperseg)
        {
            const float *line_ptr = x + static_cast<std::size_t>(line) * static_cast<std::size_t>(line_len);
            const int raw_index = seg * step + sample - boundary_len;
            float trend = 0.0;
            if (detrend_mode != 0)
            {
                float sum_x = 0.0;
                float sum_x2 = 0.0;
                float sum_y = 0.0;
                float sum_xy = 0.0;
                for (int local = 0; local < nperseg; ++local)
                {
                    const float y_value =
                        read_boundary_value(line_ptr, line_len, seg * step + local - boundary_len, boundary_mode);
                    if (detrend_mode == 1)
                    {
                        sum_y += y_value;
                    }
                    else
                    {
                        const float x_value = static_cast<float>(local);
                        sum_x += x_value;
                        sum_x2 += x_value * x_value;
                        sum_y += y_value;
                        sum_xy += x_value * y_value;
                    }
                }
                if (detrend_mode == 1)
                {
                    trend = sum_y / static_cast<float>(nperseg);
                }
                else
                {
                    const float n = static_cast<float>(nperseg);
                    const float denom = n * sum_x2 - sum_x * sum_x;
                    const float slope =
                        fabs(denom) < 1e-14 ? 0.0 : (n * sum_xy - sum_x * sum_y) / denom;
                    const float intercept = (sum_y - slope * sum_x) / n;
                    trend = intercept + slope * static_cast<float>(sample);
                }
            }

            const float raw =
                read_boundary_value(line_ptr, line_len, raw_index, boundary_mode) - trend;
            value.x = raw * window[sample];
        }
        output[index] = value;
    }

    __global__ void prepare_segments_real_kernel(
        const float *x,
        int line_count,
        int line_len,
        int nseg,
        int nperseg,
        int step,
        int nfft,
        int boundary_mode,
        int boundary_len,
        const float *window,
        int detrend_mode,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(line_count) * nseg * nfft;
        if (index >= total)
        {
            return;
        }

        const int sample = static_cast<int>(index % static_cast<std::size_t>(nfft));
        const int seg = static_cast<int>((index / static_cast<std::size_t>(nfft)) % static_cast<std::size_t>(nseg));
        const int line = static_cast<int>(index / (static_cast<std::size_t>(nfft) * static_cast<std::size_t>(nseg)));
        float value = 0.0f;

        if (sample < nperseg)
        {
            const float *line_ptr = x + static_cast<std::size_t>(line) * static_cast<std::size_t>(line_len);
            const int raw_index = seg * step + sample - boundary_len;
            float trend = 0.0f;
            if (detrend_mode != 0)
            {
                float sum_x = 0.0f;
                float sum_x2 = 0.0f;
                float sum_y = 0.0f;
                float sum_xy = 0.0f;
                for (int local = 0; local < nperseg; ++local)
                {
                    const float y_value =
                        read_boundary_value(line_ptr, line_len, seg * step + local - boundary_len, boundary_mode);
                    if (detrend_mode == 1)
                    {
                        sum_y += y_value;
                    }
                    else
                    {
                        const float x_value = static_cast<float>(local);
                        sum_x += x_value;
                        sum_x2 += x_value * x_value;
                        sum_y += y_value;
                        sum_xy += x_value * y_value;
                    }
                }
                if (detrend_mode == 1)
                {
                    trend = sum_y / static_cast<float>(nperseg);
                }
                else
                {
                    const float n = static_cast<float>(nperseg);
                    const float denom = n * sum_x2 - sum_x * sum_x;
                    const float slope =
                        fabs(denom) < 1e-14f ? 0.0f : (n * sum_xy - sum_x * sum_y) / denom;
                    const float intercept = (sum_y - slope * sum_x) / n;
                    trend = intercept + slope * static_cast<float>(sample);
                }
            }

            const float raw =
                read_boundary_value(line_ptr, line_len, raw_index, boundary_mode) - trend;
            value = raw * window[sample];
        }
        output[index] = value;
    }

    __global__ void prepare_segments_real_constant_kernel(
        const float *x,
        int line_count,
        int line_len,
        int nseg,
        int nperseg,
        int step,
        int nfft,
        const float *window,
        float *output)
    {
        const int segment_index = blockIdx.x;
        const int total_segments = line_count * nseg;
        if (segment_index >= total_segments)
        {
            return;
        }

        const int seg = segment_index % nseg;
        const int line = segment_index / nseg;
        const float *line_ptr = x + static_cast<std::size_t>(line) * static_cast<std::size_t>(line_len);

        __shared__ float sum_cache[kThreadsPerBlock];
        float sum = 0.0f;
        for (int local = threadIdx.x; local < nperseg; local += blockDim.x)
        {
            sum += line_ptr[seg * step + local];
        }
        sum_cache[threadIdx.x] = sum;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                sum_cache[threadIdx.x] += sum_cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        const float mean = sum_cache[0] / static_cast<float>(nperseg);

        const std::size_t base =
            static_cast<std::size_t>(segment_index) * static_cast<std::size_t>(nfft);
        for (int sample = threadIdx.x; sample < nfft; sample += blockDim.x)
        {
            float value = 0.0f;
            if (sample < nperseg)
            {
                value = (line_ptr[seg * step + sample] - mean) * window[sample];
            }
            output[base + static_cast<std::size_t>(sample)] = value;
        }
    }

    __global__ void prepare_segments_complex_constant_kernel(
        const float *x,
        int line_count,
        int line_len,
        int nseg,
        int nperseg,
        int step,
        int nfft,
        const float *window,
        cufftComplex *output)
    {
        const int segment_index = blockIdx.x;
        const int total_segments = line_count * nseg;
        if (segment_index >= total_segments)
        {
            return;
        }

        const int seg = segment_index % nseg;
        const int line = segment_index / nseg;
        const float *line_ptr = x + static_cast<std::size_t>(line) * static_cast<std::size_t>(line_len);

        __shared__ float sum_cache[kThreadsPerBlock];
        float sum = 0.0f;
        for (int local = threadIdx.x; local < nperseg; local += blockDim.x)
        {
            sum += line_ptr[seg * step + local];
        }
        sum_cache[threadIdx.x] = sum;
        __syncthreads();
        for (int stride = blockDim.x / 2; stride > 0; stride >>= 1)
        {
            if (threadIdx.x < stride)
            {
                sum_cache[threadIdx.x] += sum_cache[threadIdx.x + stride];
            }
            __syncthreads();
        }
        const float mean = sum_cache[0] / static_cast<float>(nperseg);

        const std::size_t base =
            static_cast<std::size_t>(segment_index) * static_cast<std::size_t>(nfft);
        for (int sample = threadIdx.x; sample < nfft; sample += blockDim.x)
        {
            float value = 0.0f;
            if (sample < nperseg)
            {
                value = (line_ptr[seg * step + sample] - mean) * window[sample];
            }
            output[base + static_cast<std::size_t>(sample)] = cufftComplex{value, 0.0f};
        }
    }

    __global__ void average_cross_kernel(
        const cufftComplex *x_fft,
        const cufftComplex *y_fft,
        int line_count,
        int nseg,
        int nfft,
        int freq_count,
        float scale,
        bool onesided,
        bool same_data,
        bool output_real,
        int average_mode,
        float *real_output,
        cufftComplex *complex_output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(line_count) * static_cast<std::size_t>(freq_count);
        if (index >= total)
        {
            return;
        }
        const int freq = static_cast<int>(index % static_cast<std::size_t>(freq_count));
        const int line = static_cast<int>(index / static_cast<std::size_t>(freq_count));

        if (average_mode != 0)
        {
            // median is currently approximated by mean in CUDA path
        }

        float accum_real = 0.0;
        float accum_imag = 0.0;
        for (int seg = 0; seg < nseg; ++seg)
        {
            const std::size_t base =
                (static_cast<std::size_t>(line) * nseg + seg) * static_cast<std::size_t>(nfft) +
                static_cast<std::size_t>(freq);
            const cufftComplex x_value = x_fft[base];
            const cufftComplex y_value = same_data ? x_value : y_fft[base];
            float real = (x_value.x * y_value.x + x_value.y * y_value.y) * scale;
            float imag = (-x_value.y * y_value.x + x_value.x * y_value.y) * scale;
            if (onesided)
            {
                const bool two_bin =
                    (nfft % 2 == 0) ? (freq > 0 && freq + 1 < freq_count) : (freq > 0);
                if (two_bin)
                {
                    real *= 2.0;
                    imag *= 2.0;
                }
            }
            accum_real += real;
            accum_imag += imag;
        }
        accum_real /= static_cast<float>(nseg);
        accum_imag /= static_cast<float>(nseg);
        if (output_real)
        {
            real_output[index] = accum_real;
        }
        else
        {
            complex_output[index] = cufftComplex{accum_real, accum_imag};
        }
    }

    __global__ void average_cross_r2c_kernel(
        const cufftComplex *x_fft,
        const cufftComplex *y_fft,
        int line_count,
        int nseg,
        int nfft,
        int freq_count,
        float scale,
        int average_mode,
        cufftComplex *complex_output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(line_count) * static_cast<std::size_t>(freq_count);
        if (index >= total)
        {
            return;
        }
        const int freq = static_cast<int>(index % static_cast<std::size_t>(freq_count));
        const int line = static_cast<int>(index / static_cast<std::size_t>(freq_count));
        const int rfft_bins = nfft / 2 + 1;

        if (average_mode != 0)
        {
            // median is currently approximated by mean in CUDA path
        }

        float accum_real = 0.0f;
        float accum_imag = 0.0f;
        for (int seg = 0; seg < nseg; ++seg)
        {
            const std::size_t base =
                (static_cast<std::size_t>(line) * nseg + seg) * static_cast<std::size_t>(rfft_bins) +
                static_cast<std::size_t>(freq);
            const cufftComplex x_value = x_fft[base];
            const cufftComplex y_value = y_fft[base];
            float real = (x_value.x * y_value.x + x_value.y * y_value.y) * scale;
            float imag = (-x_value.y * y_value.x + x_value.x * y_value.y) * scale;
            const bool two_bin =
                (nfft % 2 == 0) ? (freq > 0 && freq + 1 < freq_count) : (freq > 0);
            if (two_bin)
            {
                real *= 2.0f;
                imag *= 2.0f;
            }
            accum_real += real;
            accum_imag += imag;
        }
        complex_output[index] = cufftComplex{
            accum_real / static_cast<float>(nseg),
            accum_imag / static_cast<float>(nseg)};
    }

    __global__ void spectrogram_psd_kernel(
        const cufftComplex *fft_values,
        int line_count,
        int nseg,
        int nfft,
        int freq_count,
        float scale,
        bool onesided,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total =
            static_cast<std::size_t>(line_count) * static_cast<std::size_t>(nseg) * static_cast<std::size_t>(freq_count);
        if (index >= total)
        {
            return;
        }
        const int freq = static_cast<int>(index % static_cast<std::size_t>(freq_count));
        const int seg = static_cast<int>((index / static_cast<std::size_t>(freq_count)) % static_cast<std::size_t>(nseg));
        const int line = static_cast<int>(index / (static_cast<std::size_t>(freq_count) * static_cast<std::size_t>(nseg)));
        const std::size_t base =
            (static_cast<std::size_t>(line) * nseg + seg) * static_cast<std::size_t>(nfft) +
            static_cast<std::size_t>(freq);
        const cufftComplex value = fft_values[base];
        float psd = (value.x * value.x + value.y * value.y) * scale;
        if (onesided)
        {
            const bool two_bin =
                (nfft % 2 == 0) ? (freq > 0 && freq + 1 < freq_count) : (freq > 0);
            if (two_bin)
            {
                psd *= 2.0;
            }
        }
        const std::size_t out_index =
            (static_cast<std::size_t>(line) * static_cast<std::size_t>(freq_count) + static_cast<std::size_t>(freq)) *
                static_cast<std::size_t>(nseg) +
            static_cast<std::size_t>(seg);
        output[out_index] = psd;
    }

    __global__ void spectrogram_psd_r2c_kernel(
        const cufftComplex *fft_values,
        int line_count,
        int nseg,
        int nfft,
        int freq_count,
        float scale,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total =
            static_cast<std::size_t>(line_count) * static_cast<std::size_t>(nseg) * static_cast<std::size_t>(freq_count);
        if (index >= total)
        {
            return;
        }
        const int freq = static_cast<int>(index % static_cast<std::size_t>(freq_count));
        const int seg = static_cast<int>((index / static_cast<std::size_t>(freq_count)) % static_cast<std::size_t>(nseg));
        const int line = static_cast<int>(index / (static_cast<std::size_t>(freq_count) * static_cast<std::size_t>(nseg)));
        const int rfft_bins = nfft / 2 + 1;
        const std::size_t base =
            (static_cast<std::size_t>(line) * nseg + seg) * static_cast<std::size_t>(rfft_bins) +
            static_cast<std::size_t>(freq);
        const cufftComplex value = fft_values[base];
        float psd = fmaf(value.x, value.x, value.y * value.y) * scale;
        const bool two_bin =
            (nfft % 2 == 0) ? (freq > 0 && freq + 1 < freq_count) : (freq > 0);
        if (two_bin)
        {
            psd *= 2.0f;
        }
        const std::size_t out_index =
            (static_cast<std::size_t>(line) * static_cast<std::size_t>(freq_count) + static_cast<std::size_t>(freq)) *
                static_cast<std::size_t>(nseg) +
            static_cast<std::size_t>(seg);
        output[out_index] = psd;
    }

    __global__ void spectrogram_magnitude_r2c_kernel(
        const cufftComplex *fft_values,
        int line_count,
        int nseg,
        int nfft,
        int freq_count,
        float scale,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total =
            static_cast<std::size_t>(line_count) * static_cast<std::size_t>(nseg) * static_cast<std::size_t>(freq_count);
        if (index >= total)
        {
            return;
        }
        const int freq = static_cast<int>(index % static_cast<std::size_t>(freq_count));
        const int seg = static_cast<int>((index / static_cast<std::size_t>(freq_count)) % static_cast<std::size_t>(nseg));
        const int line = static_cast<int>(index / (static_cast<std::size_t>(freq_count) * static_cast<std::size_t>(nseg)));
        const int rfft_bins = nfft / 2 + 1;
        const std::size_t base =
            (static_cast<std::size_t>(line) * nseg + seg) * static_cast<std::size_t>(rfft_bins) +
            static_cast<std::size_t>(freq);
        const cufftComplex value = fft_values[base];
        const std::size_t out_index =
            (static_cast<std::size_t>(line) * static_cast<std::size_t>(freq_count) + static_cast<std::size_t>(freq)) *
                static_cast<std::size_t>(nseg) +
            static_cast<std::size_t>(seg);
        output[out_index] = hypotf(value.x, value.y) * scale;
    }

    __global__ void spectrogram_complex_kernel(
        const cufftComplex *fft_values,
        int line_count,
        int nseg,
        int nfft,
        int freq_count,
        float scale,
        cufftComplex *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total =
            static_cast<std::size_t>(line_count) * static_cast<std::size_t>(nseg) * static_cast<std::size_t>(freq_count);
        if (index >= total)
        {
            return;
        }
        const int freq = static_cast<int>(index % static_cast<std::size_t>(freq_count));
        const int seg = static_cast<int>((index / static_cast<std::size_t>(freq_count)) % static_cast<std::size_t>(nseg));
        const int line = static_cast<int>(index / (static_cast<std::size_t>(freq_count) * static_cast<std::size_t>(nseg)));
        const std::size_t base =
            (static_cast<std::size_t>(line) * nseg + seg) * static_cast<std::size_t>(nfft) +
            static_cast<std::size_t>(freq);
        const cufftComplex value = fft_values[base];
        const std::size_t out_index =
            (static_cast<std::size_t>(line) * static_cast<std::size_t>(freq_count) + static_cast<std::size_t>(freq)) *
                static_cast<std::size_t>(nseg) +
            static_cast<std::size_t>(seg);
        output[out_index] = cufftComplex{value.x * scale, value.y * scale};
    }

    __global__ void complex_to_mode_kernel(
        const cufftComplex *input,
        std::size_t count,
        int mode,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        const cufftComplex value = input[index];
        if (mode == 0)
        {
            output[index] = hypot(value.x, value.y);
        }
        else
        {
            output[index] = atan2(value.y, value.x);
        }
    }

    __global__ void unwrap_phase_kernel(
        float *values,
        int line_count,
        int freq_count,
        int time_count)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(line_count) * static_cast<std::size_t>(time_count);
        if (index >= total)
        {
            return;
        }
        const int time = static_cast<int>(index % static_cast<std::size_t>(time_count));
        const int line = static_cast<int>(index / static_cast<std::size_t>(time_count));
        std::size_t base =
            (static_cast<std::size_t>(line) * static_cast<std::size_t>(freq_count)) * static_cast<std::size_t>(time_count) +
            static_cast<std::size_t>(time);
        float previous = values[base];
        for (int freq = 1; freq < freq_count; ++freq)
        {
            base += static_cast<std::size_t>(time_count);
            float current = values[base];
            float delta = current - previous;
            while (delta > kPi)
            {
                current -= 2.0 * kPi;
                delta = current - previous;
            }
            while (delta < -kPi)
            {
                current += 2.0 * kPi;
                delta = current - previous;
            }
            values[base] = current;
            previous = current;
        }
    }

    __global__ void coherence_kernel(
        const float *pxx,
        const float *pyy,
        const cufftComplex *pxy,
        std::size_t count,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= count)
        {
            return;
        }
        const float denom = pxx[index] * pyy[index];
        if (denom <= 0.0)
        {
            output[index] = 0.0;
            return;
        }
        const cufftComplex value = pxy[index];
        output[index] = (value.x * value.x + value.y * value.y) / denom;
    }

    __global__ void coherence_from_fft_kernel(
        const cufftComplex *x_fft,
        const cufftComplex *y_fft,
        int line_count,
        int nseg,
        int nfft,
        int freq_count,
        float scale,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(line_count) * static_cast<std::size_t>(freq_count);
        if (index >= total)
        {
            return;
        }

        const int freq = static_cast<int>(index % static_cast<std::size_t>(freq_count));
        const int line = static_cast<int>(index / static_cast<std::size_t>(freq_count));
        const bool two_bin =
            (nfft % 2 == 0) ? (freq > 0 && freq + 1 < freq_count) : (freq > 0);
        const float bin_scale = two_bin ? 2.0f * scale : scale;

        float pxx = 0.0f;
        float pyy = 0.0f;
        float pxy_real = 0.0f;
        float pxy_imag = 0.0f;
        for (int seg = 0; seg < nseg; ++seg)
        {
            const std::size_t base =
                (static_cast<std::size_t>(line) * nseg + seg) * static_cast<std::size_t>(nfft) +
                static_cast<std::size_t>(freq);
            const cufftComplex x_value = x_fft[base];
            const cufftComplex y_value = y_fft[base];
            pxx += (x_value.x * x_value.x + x_value.y * x_value.y) * bin_scale;
            pyy += (y_value.x * y_value.x + y_value.y * y_value.y) * bin_scale;
            pxy_real += (x_value.x * y_value.x + x_value.y * y_value.y) * bin_scale;
            pxy_imag += (-x_value.y * y_value.x + x_value.x * y_value.y) * bin_scale;
        }

        const float inv_nseg = 1.0f / static_cast<float>(nseg);
        pxx *= inv_nseg;
        pyy *= inv_nseg;
        pxy_real *= inv_nseg;
        pxy_imag *= inv_nseg;
        const float denom = pxx * pyy;
        output[index] = denom <= 0.0f ? 0.0f : (pxy_real * pxy_real + pxy_imag * pxy_imag) / denom;
    }

    __global__ void expand_onesided_kernel(
        const cufftComplex *input,
        int outer_count,
        int time_count,
        int freq_count,
        int nfft,
        cufftComplex *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total =
            static_cast<std::size_t>(outer_count) * static_cast<std::size_t>(time_count) * static_cast<std::size_t>(nfft);
        if (index >= total)
        {
            return;
        }
        const int sample = static_cast<int>(index % static_cast<std::size_t>(nfft));
        const int seg = static_cast<int>((index / static_cast<std::size_t>(nfft)) % static_cast<std::size_t>(time_count));
        const int outer = static_cast<int>(index / (static_cast<std::size_t>(nfft) * static_cast<std::size_t>(time_count)));
        cufftComplex value{0.0, 0.0};
        const std::size_t base_in =
            (static_cast<std::size_t>(outer) * static_cast<std::size_t>(freq_count)) * static_cast<std::size_t>(time_count) +
            static_cast<std::size_t>(seg);
        if (sample < freq_count)
        {
            value = input[base_in + static_cast<std::size_t>(sample) * static_cast<std::size_t>(time_count)];
        }
        else
        {
            const int mirror = nfft - sample;
            if (mirror > 0 && mirror < freq_count)
            {
                const cufftComplex reflected =
                    input[base_in + static_cast<std::size_t>(mirror) * static_cast<std::size_t>(time_count)];
                value = cufftComplex{reflected.x, -reflected.y};
            }
        }
        output[index] = value;
    }

    __global__ void copy_twosided_kernel(
        const cufftComplex *input,
        std::size_t count,
        cufftComplex *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < count)
        {
            output[index] = input[index];
        }
    }

    __global__ void overlap_add_kernel(
        const cufftComplex *ifft_segments,
        int outer_count,
        int time_count,
        int nfft,
        int nperseg,
        int step,
        float window_sum,
        const float *window,
        int trim,
        int final_length,
        float *output)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(outer_count) * static_cast<std::size_t>(final_length);
        if (index >= total)
        {
            return;
        }
        const int sample = static_cast<int>(index % static_cast<std::size_t>(final_length));
        const int outer = static_cast<int>(index / static_cast<std::size_t>(final_length));
        const int target = sample + trim;
        float accum = 0.0;
        float norm = 0.0;
        for (int seg = 0; seg < time_count; ++seg)
        {
            const int local = target - seg * step;
            if (local < 0 || local >= nperseg)
            {
                continue;
            }
            const std::size_t base =
                (static_cast<std::size_t>(outer) * static_cast<std::size_t>(time_count) + static_cast<std::size_t>(seg)) *
                    static_cast<std::size_t>(nfft) +
                static_cast<std::size_t>(local);
            const float win = window[local];
            accum += (ifft_segments[base].x / static_cast<float>(nfft)) * window_sum * win;
            norm += win * win;
        }
        output[index] = norm > 1e-10 ? (accum / norm) : accum;
    }

    void require_last_axis(const ZxGpuRealArray &x, int axis)
    {
        if (cusignal::core::normalize_axis(axis, x.rank()) != x.rank() - 1)
        {
            throw std::invalid_argument("CUDA spectral currently requires axis=-1");
        }
    }

    std::size_t total_segments(std::size_t line_count, std::size_t nseg)
    {
        return line_count * nseg;
    }

    void measure_gpu_compute(ScopedZxGpuEvents &events, const std::function<void()> &callable)
    {
        g_last_kernel_ms = events.measure(callable);
    }

    int resolve_istft_nperseg(std::size_t freq_bins, bool input_onesided, int nperseg)
    {
        if (nperseg > 0)
        {
            return nperseg;
        }
        return input_onesided ? 2 * (static_cast<int>(freq_bins) - 1) : static_cast<int>(freq_bins);
    }

    int resolve_istft_nfft(std::size_t freq_bins, bool input_onesided, int nperseg, int nfft)
    {
        const int default_n =
            input_onesided ? 2 * (static_cast<int>(freq_bins) - 1) : static_cast<int>(freq_bins);
        if (nfft > 0)
        {
            if (nfft < nperseg)
            {
                throw std::invalid_argument("nfft must be greater than or equal to nperseg.");
            }
            return nfft;
        }
        if (input_onesided && nperseg == default_n + 1)
        {
            return nperseg;
        }
        return default_n;
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace spectral
        {
            core::ZxGpuRealSignal lombscargle(
                const core::RealSignalLike &x,
                const core::RealSignalLike &y,
                const core::RealSignalLike &freqs,
                bool precenter,
                bool normalize)
            {
                thread_local SpectralWorkspace workspace;
                const core::ZxGpuRealSignal &x_device = core::as_device_signal(x, workspace.x_signal_storage);
                const core::ZxGpuRealSignal &y_device = core::as_device_signal(y, workspace.y_signal_storage);
                const core::ZxGpuRealSignal &freqs_device = core::as_device_signal(freqs, workspace.freq_storage);
                if (x_device.size() != y_device.size())
                {
                    throw std::invalid_argument("lombscargle inputs must have the same length");
                }

                if (x_device.empty() || freqs_device.empty())
                {
                    g_last_kernel_ms = 0.0f;
                    return core::make_zx_gpu_real_signal(freqs_device.size());
                }

                const int sample_count = static_cast<int>(x_device.size());
                const int freq_count = static_cast<int>(freqs_device.size());
                const int partial_count =
                    std::min(kVectorStrengthMaxBlocksPerPeriod, block_count(x_device.size()));
                workspace.real_scratch.reserve(2);
                workspace.reduction_scratch_a.reserve(static_cast<std::size_t>(partial_count));
                workspace.reduction_scratch_b.reserve(static_cast<std::size_t>(partial_count));

                core::ZxGpuRealSignal output(freqs_device.size(), false);
                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    if (precenter)
                    {
                        lombscargle_sum_kernel<<<partial_count, kThreadsPerBlock>>>(
                            y_device.data(),
                            sample_count,
                            workspace.reduction_scratch_a.get());
                        check_kernel_launch("lombscargle_sum_kernel");
                        lombscargle_finalize_sum_kernel<<<1, kThreadsPerBlock>>>(
                            workspace.reduction_scratch_a.get(),
                            partial_count,
                            1.0f / static_cast<float>(sample_count),
                            workspace.real_scratch.get());
                        check_kernel_launch("lombscargle_finalize_mean_kernel");
                    }
                    if (normalize)
                    {
                        lombscargle_dot_kernel<<<partial_count, kThreadsPerBlock>>>(
                            y_device.data(),
                            sample_count,
                            workspace.real_scratch.get(),
                            precenter,
                            workspace.reduction_scratch_b.get());
                        check_kernel_launch("lombscargle_dot_kernel");
                        lombscargle_finalize_sum_kernel<<<1, kThreadsPerBlock>>>(
                            workspace.reduction_scratch_b.get(),
                            partial_count,
                            1.0f,
                            workspace.real_scratch.get() + 1);
                        check_kernel_launch("lombscargle_finalize_dot_kernel");
                    }

                    if (tile::optimized_path() && sample_count >= 1024 && freq_count >= 1024)
                    {
                        const int pair_block_count = (freq_count + 1) / 2;
                        lombscargle_parallel_pair_kernel<<<pair_block_count, kThreadsPerBlock>>>(
                            x_device.data(),
                            y_device.data(),
                            freqs_device.data(),
                            sample_count,
                            freq_count,
                            workspace.real_scratch.get(),
                            workspace.real_scratch.get() + 1,
                            precenter,
                            normalize,
                            output.data());
                        check_kernel_launch("lombscargle_parallel_pair_kernel");
                    }
                    else
                    {
                        lombscargle_parallel_kernel<<<freq_count, kThreadsPerBlock>>>(
                            x_device.data(),
                            y_device.data(),
                            freqs_device.data(),
                            sample_count,
                            freq_count,
                            workspace.real_scratch.get(),
                            workspace.real_scratch.get() + 1,
                            precenter,
                            normalize,
                            output.data());
                        check_kernel_launch("lombscargle_parallel_kernel");
                    }
                });
                return output;
            }

            spectral_api::ZxGpuRealSpectrumResult periodogram(
                const core::RealArrayLike &x,
                float fs,
                core::ZxGpuWindowSpec window,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis)
            {
                thread_local SpectralWorkspace workspace;
                if (g_periodogram_cache_reset_requested)
                {
                    workspace.periodogram_window_valid = false;
                    workspace.frequency_axis_valid = false;
                    g_periodogram_cache_reset_requested = false;
                }
                g_last_periodogram_cache_state = kPeriodogramCacheStateBypass;
                const core::ZxGpuRealArray &x_device = core::as_device_array(x, workspace.x_storage);
                require_last_axis(x_device, axis);
                const std::size_t line_len = x_device.shape().back();
                const std::size_t line_count = line_count_last_axis(x_device.shape());
                const int resolved_nfft =
                    nfft > 0 ? nfft : static_cast<int>(line_len);
                const int effective_len =
                    (nfft > 0 && static_cast<std::size_t>(nfft) < line_len) ? nfft : static_cast<int>(line_len);
                std::string window_cache_key;
                const bool cacheable_window =
                    build_csd_window_cache_key(
                        window,
                        effective_len,
                        fs,
                        scaling,
                        window_cache_key);
                const bool use_window_cache =
                    tile::optimized_path() &&
                    cacheable_window &&
                    g_periodogram_cache_override != kPeriodogramCacheBypass;
                core::ZxGpuRealSignal transient_window;
                const core::ZxGpuRealSignal *window_values = nullptr;
                float scale = 0.0f;
                if (use_window_cache &&
                    workspace.periodogram_window_valid &&
                    workspace.periodogram_window_key == window_cache_key)
                {
                    window_values = &workspace.periodogram_window_storage;
                    scale = workspace.periodogram_window_scale;
                    g_last_periodogram_cache_state = kPeriodogramCacheStateHit;
                }
                else
                {
                    transient_window =
                        zx_gpu_backend::windows::get_window(window, effective_len, true);
                    const RealSignal window_host = transient_window.get();
                    scale = scaling == "density" ? detail::density_scale(window_host, fs)
                                                 : detail::spectrum_scale(window_host);
                    if (use_window_cache)
                    {
                        workspace.periodogram_window_storage = std::move(transient_window);
                        workspace.periodogram_window_key = window_cache_key;
                        workspace.periodogram_window_scale = scale;
                        workspace.periodogram_window_valid = true;
                        window_values = &workspace.periodogram_window_storage;
                        g_last_periodogram_cache_state = kPeriodogramCacheStateMiss;
                    }
                    else
                    {
                        window_values = &transient_window;
                    }
                }
                const detail::SegmentConfig config{
                    effective_len,
                    0,
                    resolved_nfft > 0 ? resolved_nfft : effective_len,
                    effective_len,
                    return_onesided};
                const std::size_t nseg = 1;
                const std::size_t total_fft = total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft);
                const bool use_r2c = return_onesided;
                const std::size_t freq_count = detail::frequency_count(config.nfft, return_onesided);
                if (use_r2c)
                {
                    const std::size_t rfft_count =
                        total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft / 2 + 1);
                    workspace.real_fft_x.reserve(total_fft);
                    workspace.rfft_x.reserve(rfft_count);
                }
                else
                {
                    workspace.fft_x.reserve(total_fft);
                }
                core::ZxGpuRealArray values =
                    core::make_zx_gpu_real_array(core::replace_axis_size(x_device.shape(), axis, freq_count));
                const int detrend_code = detrend_mode_code(detrend);

                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    if (use_r2c)
                    {
                        if (detrend_code == 1)
                        {
                            prepare_segments_real_constant_kernel<<<
                                static_cast<int>(line_count * nseg),
                                kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                window_values->data(),
                                workspace.real_fft_x.get());
                            check_kernel_launch("prepare_segments_real_constant_kernel(periodogram)");
                        }
                        else
                        {
                            prepare_segments_real_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                0,
                                0,
                                window_values->data(),
                                detrend_code,
                                workspace.real_fft_x.get());
                            check_kernel_launch("prepare_segments_real_kernel(periodogram)");
                        }
                        workspace.real_forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                        throw_on_cufft_error(
                            cufftExecR2C(workspace.real_forward_plan.handle, workspace.real_fft_x.get(), workspace.rfft_x.get()),
                            "cufftExecR2C(periodogram)");
                        spectrogram_psd_r2c_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                            workspace.rfft_x.get(),
                            static_cast<int>(line_count),
                            static_cast<int>(nseg),
                            config.nfft,
                            static_cast<int>(freq_count),
                            scale,
                            values.data());
                        check_kernel_launch("spectrogram_psd_r2c_kernel(periodogram)");
                    }
                    else
                    {
                        prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                            x_device.data(),
                            static_cast<int>(line_count),
                            static_cast<int>(line_len),
                            static_cast<int>(nseg),
                            config.nperseg,
                            config.step,
                            config.nfft,
                            0,
                            0,
                            window_values->data(),
                            detrend_code,
                            workspace.fft_x.get());
                        check_kernel_launch("prepare_segments_kernel(periodogram)");
                        workspace.forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                        throw_on_cufft_error(
                            cufftExecC2C(workspace.forward_plan.handle, workspace.fft_x.get(), workspace.fft_x.get(), CUFFT_FORWARD),
                            "cufftExecC2C(periodogram)");
                        average_cross_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                            workspace.fft_x.get(),
                            nullptr,
                            static_cast<int>(line_count),
                            static_cast<int>(nseg),
                            config.nfft,
                            static_cast<int>(freq_count),
                            scale,
                            return_onesided,
                            true,
                            true,
                            0,
                            values.data(),
                            nullptr);
                        check_kernel_launch("average_cross_kernel(periodogram)");
                    }
                });

                spectral_api::ZxGpuRealSpectrumResult result;
                if (g_periodogram_cache_override == kPeriodogramCacheBypass)
                {
                    result.frequencies = core::ZxGpuRealSignal::from_host(
                        detail::frequency_axis(config.nfft, fs, return_onesided));
                }
                else
                {
                    result.frequencies =
                        cached_frequency_axis(workspace, config.nfft, fs, return_onesided);
                }
                result.values = std::move(values);
                return result;
            }

            spectral_api::ZxGpuRealSpectrumResult welch(
                const core::RealArrayLike &x,
                float fs,
                core::ZxGpuWindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis,
                const std::string &average)
            {
                thread_local SpectralWorkspace workspace;
                if (g_welch_cache_reset_requested)
                {
                    workspace.segment_window_valid = false;
                    workspace.frequency_axis_valid = false;
                    g_welch_cache_reset_requested = false;
                }
                g_last_welch_cache_state = kWelchCacheStateBypass;
                const core::ZxGpuRealArray &x_device = core::as_device_array(x, workspace.x_storage);
                require_last_axis(x_device, axis);
                const std::string avg = detail::normalize_average(average);
                const std::size_t line_len = x_device.shape().back();
                const std::size_t line_count = line_count_last_axis(x_device.shape());
                const int window_size =
                    nperseg > 0 ? std::min<int>(nperseg, static_cast<int>(line_len))
                                : std::min<int>(256, static_cast<int>(line_len));
                std::string window_cache_key;
                const bool cacheable_window =
                    build_csd_window_cache_key(
                        window,
                        window_size,
                        fs,
                        scaling,
                        window_cache_key);
                const bool use_window_cache =
                    tile::optimized_path() &&
                    cacheable_window &&
                    g_welch_cache_override != kWelchCacheBypass;
                core::ZxGpuRealSignal transient_window;
                const core::ZxGpuRealSignal *window_values = nullptr;
                float scale = 0.0f;
                if (use_window_cache &&
                    workspace.segment_window_valid &&
                    workspace.segment_window_key == window_cache_key)
                {
                    window_values = &workspace.segment_window_storage;
                    scale = workspace.segment_window_scale;
                    g_last_welch_cache_state = kWelchCacheStateHit;
                }
                else
                {
                    transient_window =
                        zx_gpu_backend::windows::get_window(window, window_size, true);
                    const RealSignal window_host = transient_window.get();
                    scale = scaling == "density" ? detail::density_scale(window_host, fs)
                                                 : detail::spectrum_scale(window_host);
                    if (use_window_cache)
                    {
                        workspace.segment_window_storage = std::move(transient_window);
                        workspace.segment_window_key = window_cache_key;
                        workspace.segment_window_scale = scale;
                        workspace.segment_window_valid = true;
                        window_values = &workspace.segment_window_storage;
                        g_last_welch_cache_state = kWelchCacheStateMiss;
                    }
                    else
                    {
                        window_values = &transient_window;
                    }
                }
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    line_len,
                    static_cast<int>(window_values->size()),
                    noverlap,
                    nfft,
                    static_cast<int>(window_values->size()),
                    static_cast<int>(window_values->size()) / 2);
                const std::size_t nseg =
                    1 + (line_len - static_cast<std::size_t>(config.nperseg)) / static_cast<std::size_t>(config.step);
                const std::size_t total_fft = total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft);
                workspace.fft_x.reserve(total_fft);
                core::ZxGpuRealArray values =
                    core::make_zx_gpu_real_array(core::replace_axis_size(x_device.shape(), axis, detail::frequency_count(config.nfft, return_onesided)));
                const int detrend_code = detrend_mode_code(detrend);

                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    if (detrend_code == 1)
                    {
                        const int segment_count = static_cast<int>(line_count * nseg);
                        prepare_segments_complex_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                            x_device.data(),
                            static_cast<int>(line_count),
                            static_cast<int>(line_len),
                            static_cast<int>(nseg),
                            config.nperseg,
                            config.step,
                            config.nfft,
                            window_values->data(),
                            workspace.fft_x.get());
                        check_kernel_launch("prepare_segments_complex_constant_kernel(welch)");
                    }
                    else
                    {
                        prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                            x_device.data(),
                            static_cast<int>(line_count),
                            static_cast<int>(line_len),
                            static_cast<int>(nseg),
                            config.nperseg,
                            config.step,
                            config.nfft,
                            0,
                            0,
                            window_values->data(),
                            detrend_code,
                            workspace.fft_x.get());
                        check_kernel_launch("prepare_segments_kernel(welch)");
                    }
                    workspace.forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                    throw_on_cufft_error(
                        cufftExecC2C(workspace.forward_plan.handle, workspace.fft_x.get(), workspace.fft_x.get(), CUFFT_FORWARD),
                        "cufftExecC2C(welch)");
                    average_cross_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                        workspace.fft_x.get(),
                        nullptr,
                        static_cast<int>(line_count),
                        static_cast<int>(nseg),
                        config.nfft,
                        static_cast<int>(detail::frequency_count(config.nfft, return_onesided)),
                        scale,
                        return_onesided,
                        true,
                        true,
                        avg == "mean" ? 0 : 1,
                        values.data(),
                        nullptr);
                    check_kernel_launch("average_cross_kernel(welch)");
                });

                spectral_api::ZxGpuRealSpectrumResult result;
                if (g_welch_cache_override == kWelchCacheBypass)
                {
                    result.frequencies = core::ZxGpuRealSignal::from_host(
                        detail::frequency_axis(config.nfft, fs, return_onesided));
                }
                else
                {
                    result.frequencies =
                        cached_frequency_axis(workspace, config.nfft, fs, return_onesided);
                }
                result.values = std::move(values);
                return result;
            }

            spectral_api::ZxGpuComplexSpectrumResult csd(
                const core::RealArrayLike &x,
                const core::RealArrayLike &y,
                float fs,
                core::ZxGpuWindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis,
                const std::string &average)
            {
                thread_local SpectralWorkspace workspace;
                const core::ZxGpuRealArray &x_device = core::as_device_array(x, workspace.x_storage);
                const core::ZxGpuRealArray &y_device = core::as_device_array(y, workspace.y_storage);
                require_last_axis(x_device, axis);
                require_last_axis(y_device, axis);
                if (x_device.shape() != y_device.shape())
                {
                    throw std::invalid_argument("x and y must have the same shape");
                }
                const std::string avg = detail::normalize_average(average);
                const std::size_t line_len = x_device.shape().back();
                const std::size_t line_count = line_count_last_axis(x_device.shape());
                const int window_size =
                    nperseg > 0 ? std::min<int>(nperseg, static_cast<int>(line_len)) : std::min<int>(256, static_cast<int>(line_len));
                std::string window_cache_key;
                const bool cacheable_window =
                    build_csd_window_cache_key(window, window_size, fs, scaling, window_cache_key);
                core::ZxGpuRealSignal transient_window;
                const core::ZxGpuRealSignal *window_values = nullptr;
                float scale = 0.0f;
                if (cacheable_window &&
                    workspace.csd_window_valid &&
                    workspace.csd_window_key == window_cache_key)
                {
                    window_values = &workspace.csd_window_storage;
                    scale = workspace.csd_window_scale;
                }
                else
                {
                    transient_window = zx_gpu_backend::windows::get_window(window, window_size, true);
                    const RealSignal window_host = transient_window.get();
                    scale = scaling == "density" ? detail::density_scale(window_host, fs)
                                                 : detail::spectrum_scale(window_host);
                    if (cacheable_window)
                    {
                        workspace.csd_window_storage = std::move(transient_window);
                        workspace.csd_window_key = window_cache_key;
                        workspace.csd_window_scale = scale;
                        workspace.csd_window_valid = true;
                        window_values = &workspace.csd_window_storage;
                    }
                    else
                    {
                        window_values = &transient_window;
                    }
                }
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    line_len,
                    static_cast<int>(window_values->size()),
                    noverlap,
                    nfft,
                    static_cast<int>(window_values->size()),
                    static_cast<int>(window_values->size()) / 2);
                const std::size_t nseg =
                    1 + (line_len - static_cast<std::size_t>(config.nperseg)) / static_cast<std::size_t>(config.step);
                const std::size_t total_fft = total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft);
                const std::size_t freq_count = detail::frequency_count(config.nfft, return_onesided);
                bool use_r2c = return_onesided;
#ifdef CUSIGNAL_PLATFORM_ZHONGKEXIN
                // ZQ500 dlfft R2C CSD currently diverges from the CPU/reference
                // path. The C2C path keeps correctness and still returns the
                // requested one-sided bins through average_cross_kernel.
                use_r2c = false;
#endif
                if (use_r2c)
                {
                    const std::size_t rfft_count =
                        total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft / 2 + 1);
                    workspace.real_fft_x.reserve(total_fft);
                    workspace.real_fft_y.reserve(total_fft);
                    workspace.rfft_x.reserve(rfft_count);
                    workspace.rfft_y.reserve(rfft_count);
                }
                else
                {
                    workspace.fft_x.reserve(total_fft);
                    workspace.fft_y.reserve(total_fft);
                }
                core::ZxGpuComplexArray values(
                    core::replace_axis_size(x_device.shape(), axis, freq_count),
                    false);
                const int detrend_code = detrend_mode_code(detrend);

                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    if (use_r2c)
                    {
                        if (detrend_code == 1)
                        {
                            const int segment_count = static_cast<int>(line_count * nseg);
                            prepare_segments_real_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                window_values->data(),
                                workspace.real_fft_x.get());
                            prepare_segments_real_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                                y_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                window_values->data(),
                                workspace.real_fft_y.get());
                            check_kernel_launch("prepare_segments_real_constant_kernel(csd)");
                        }
                        else
                        {
                            prepare_segments_real_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                0,
                                0,
                                window_values->data(),
                                detrend_code,
                                workspace.real_fft_x.get());
                            prepare_segments_real_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                                y_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                0,
                                0,
                                window_values->data(),
                                detrend_code,
                                workspace.real_fft_y.get());
                            check_kernel_launch("prepare_segments_real_kernel(csd)");
                        }
                        workspace.real_forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                        throw_on_cufft_error(
                            cufftExecR2C(workspace.real_forward_plan.handle, workspace.real_fft_x.get(), workspace.rfft_x.get()),
                            "cufftExecR2C(csd/x)");
                        throw_on_cufft_error(
                            cufftExecR2C(workspace.real_forward_plan.handle, workspace.real_fft_y.get(), workspace.rfft_y.get()),
                            "cufftExecR2C(csd/y)");
                        average_cross_r2c_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                            workspace.rfft_x.get(),
                            workspace.rfft_y.get(),
                            static_cast<int>(line_count),
                            static_cast<int>(nseg),
                            config.nfft,
                            static_cast<int>(freq_count),
                            scale,
                            avg == "mean" ? 0 : 1,
                            reinterpret_cast<cufftComplex *>(values.data()));
                        check_kernel_launch("average_cross_r2c_kernel(csd)");
                    }
                    else
                    {
                        if (detrend_code == 1)
                        {
                            const int segment_count = static_cast<int>(line_count * nseg);
                            prepare_segments_complex_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                window_values->data(),
                                workspace.fft_x.get());
                            prepare_segments_complex_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                                y_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                window_values->data(),
                                workspace.fft_y.get());
                            check_kernel_launch("prepare_segments_complex_constant_kernel(csd)");
                        }
                        else
                        {
                            prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                0,
                                0,
                                window_values->data(),
                                detrend_code,
                                workspace.fft_x.get());
                            prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                                y_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                0,
                                0,
                                window_values->data(),
                                detrend_code,
                                workspace.fft_y.get());
                            check_kernel_launch("prepare_segments_kernel(csd)");
                        }
                        workspace.forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                        throw_on_cufft_error(
                            cufftExecC2C(workspace.forward_plan.handle, workspace.fft_x.get(), workspace.fft_x.get(), CUFFT_FORWARD),
                            "cufftExecC2C(csd/x)");
                        throw_on_cufft_error(
                            cufftExecC2C(workspace.forward_plan.handle, workspace.fft_y.get(), workspace.fft_y.get(), CUFFT_FORWARD),
                            "cufftExecC2C(csd/y)");
                        average_cross_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                            workspace.fft_x.get(),
                            workspace.fft_y.get(),
                            static_cast<int>(line_count),
                            static_cast<int>(nseg),
                            config.nfft,
                            static_cast<int>(freq_count),
                            scale,
                            return_onesided,
                            false,
                            false,
                            avg == "mean" ? 0 : 1,
                            nullptr,
                            reinterpret_cast<cufftComplex *>(values.data()));
                        check_kernel_launch("average_cross_kernel(csd)");
                    }
                });

                spectral_api::ZxGpuComplexSpectrumResult result;
                result.frequencies = cached_frequency_axis(workspace, config.nfft, fs, return_onesided);
                result.values = std::move(values);
                return result;
            }

            spectral_api::ZxGpuSpectrogramResult spectrogram(
                const core::RealArrayLike &x,
                float fs,
                core::ZxGpuWindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &scaling,
                int axis,
                const std::string &mode)
            {
                thread_local SpectralWorkspace workspace;
                const core::ZxGpuRealArray &x_device = core::as_device_array(x, workspace.x_storage);
                require_last_axis(x_device, axis);

                const std::string normalized_mode = detail::normalize_mode(mode);
                const std::size_t line_len = x_device.shape().back();
                const std::size_t line_count = line_count_last_axis(x_device.shape());
                const int window_len =
                    nperseg > 0 ? std::min<int>(nperseg, static_cast<int>(line_len)) : std::min<int>(256, static_cast<int>(line_len));
                std::string window_cache_key;
                const bool cacheable_window =
                    build_csd_window_cache_key(window, window_len, fs, scaling + ":" + normalized_mode, window_cache_key);
                core::ZxGpuRealSignal transient_window;
                const core::ZxGpuRealSignal *window_values = nullptr;
                float base_scale = 0.0f;
                if (cacheable_window &&
                    workspace.segment_window_valid &&
                    workspace.segment_window_key == window_cache_key)
                {
                    window_values = &workspace.segment_window_storage;
                    base_scale = workspace.segment_window_scale;
                }
                else
                {
                    transient_window = zx_gpu_backend::windows::get_window(window, window_len, true);
                    const RealSignal window_host = transient_window.get();
                    base_scale =
                        scaling == "density" ? detail::density_scale(window_host, fs)
                                             : detail::spectrum_scale(window_host);
                    if (cacheable_window)
                    {
                        workspace.segment_window_storage = std::move(transient_window);
                        workspace.segment_window_key = window_cache_key;
                        workspace.segment_window_scale = base_scale;
                        workspace.segment_window_valid = true;
                        window_values = &workspace.segment_window_storage;
                    }
                    else
                    {
                        window_values = &transient_window;
                    }
                }
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    line_len,
                    static_cast<int>(window_values->size()),
                    noverlap,
                    nfft,
                    static_cast<int>(window_values->size()),
                    static_cast<int>(window_values->size()) / 8);
                const std::size_t nseg =
                    1 + (line_len - static_cast<std::size_t>(config.nperseg)) / static_cast<std::size_t>(config.step);
                const std::size_t total_fft = total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft);
                bool use_r2c_psd = return_onesided && normalized_mode == "psd";
#ifdef CUSIGNAL_PLATFORM_ZHONGKEXIN
                // ZQ500 dlfft R2C spectrogram PSD currently diverges from the CPU/reference
                // path, while the C2C spectrogram path matches within the existing tolerance.
                use_r2c_psd = false;
#endif
                bool use_r2c_magnitude = return_onesided && normalized_mode == "magnitude";
#ifdef CUSIGNAL_PLATFORM_ZHONGKEXIN
                // ZQ500 dlfft R2C magnitude produced Task2-level numerical divergence and
                // lower throughput than the C2C path during V5.3-04 validation.
                use_r2c_magnitude = false;
#endif
                if (use_r2c_psd || use_r2c_magnitude)
                {
                    const std::size_t rfft_count =
                        total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft / 2 + 1);
                    workspace.real_fft_x.reserve(total_fft);
                    workspace.rfft_x.reserve(rfft_count);
                }
                else
                {
                    workspace.fft_x.reserve(total_fft);
                }
                const float scale = normalized_mode == "psd" ? base_scale : std::sqrt(base_scale);
                const std::size_t freq_count = detail::frequency_count(config.nfft, return_onesided);
                const Shape output_shape = core::replace_axis_size(x_device.shape(), axis, freq_count);
                Shape time_shape = output_shape;
                time_shape.push_back(nseg);

                spectral_api::ZxGpuSpectrogramResult result;
                result.frequencies = cached_frequency_axis(workspace, config.nfft, fs, return_onesided);
                result.times = cached_segment_times(workspace, line_len, config.nperseg, config.step, fs, false);

                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    const int detrend_code = detrend_mode_code(detrend);
                    if (use_r2c_psd || use_r2c_magnitude)
                    {
                        if (detrend_code == 1)
                        {
                            const int segment_count = static_cast<int>(line_count * nseg);
                            prepare_segments_real_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                window_values->data(),
                                workspace.real_fft_x.get());
                            check_kernel_launch("prepare_segments_real_constant_kernel(spectrogram)");
                        }
                        else
                        {
                            prepare_segments_real_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                0,
                                0,
                                window_values->data(),
                                detrend_code,
                                workspace.real_fft_x.get());
                            check_kernel_launch("prepare_segments_real_kernel(spectrogram)");
                        }
                        workspace.real_forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                        throw_on_cufft_error(
                            cufftExecR2C(workspace.real_forward_plan.handle, workspace.real_fft_x.get(), workspace.rfft_x.get()),
                            "cufftExecR2C(spectrogram)");
                        ZxGpuRealArray values(time_shape, false);
                        if (use_r2c_psd)
                        {
                            spectrogram_psd_r2c_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                                workspace.rfft_x.get(),
                                static_cast<int>(line_count),
                                static_cast<int>(nseg),
                                config.nfft,
                                static_cast<int>(freq_count),
                                scale,
                                values.data());
                            check_kernel_launch("spectrogram_psd_r2c_kernel");
                        }
                        else
                        {
                            spectrogram_magnitude_r2c_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                                workspace.rfft_x.get(),
                                static_cast<int>(line_count),
                                static_cast<int>(nseg),
                                config.nfft,
                                static_cast<int>(freq_count),
                                scale,
                                values.data());
                            check_kernel_launch("spectrogram_magnitude_r2c_kernel");
                        }
                        result.values = std::move(values);
                    }
                    else
                    {
                        if (detrend_code == 1)
                        {
                            const int segment_count = static_cast<int>(line_count * nseg);
                            prepare_segments_complex_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                window_values->data(),
                                workspace.fft_x.get());
                            check_kernel_launch("prepare_segments_complex_constant_kernel(spectrogram)");
                        }
                        else
                        {
                            prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                                x_device.data(),
                                static_cast<int>(line_count),
                                static_cast<int>(line_len),
                                static_cast<int>(nseg),
                                config.nperseg,
                                config.step,
                                config.nfft,
                                0,
                                0,
                                window_values->data(),
                                detrend_code,
                                workspace.fft_x.get());
                            check_kernel_launch("prepare_segments_kernel(spectrogram)");
                        }
                        workspace.forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                        throw_on_cufft_error(
                            cufftExecC2C(workspace.forward_plan.handle, workspace.fft_x.get(), workspace.fft_x.get(), CUFFT_FORWARD),
                            "cufftExecC2C(spectrogram)");
                        if (normalized_mode == "psd")
                        {
                            ZxGpuRealArray values(time_shape, false);
                            spectrogram_psd_kernel<<<block_count(values.size()), kThreadsPerBlock>>>(
                                workspace.fft_x.get(),
                                static_cast<int>(line_count),
                                static_cast<int>(nseg),
                                config.nfft,
                                static_cast<int>(freq_count),
                                scale,
                                return_onesided,
                                values.data());
                            check_kernel_launch("spectrogram_psd_kernel");
                            result.values = std::move(values);
                        }
                        else
                        {
                            ZxGpuComplexArray complex_values(time_shape, false);
                            spectrogram_complex_kernel<<<block_count(complex_values.size()), kThreadsPerBlock>>>(
                                workspace.fft_x.get(),
                                static_cast<int>(line_count),
                                static_cast<int>(nseg),
                                config.nfft,
                                static_cast<int>(freq_count),
                                scale,
                                reinterpret_cast<cufftComplex *>(complex_values.data()));
                            check_kernel_launch("spectrogram_complex_kernel");
                            if (normalized_mode == "complex")
                            {
                                result.values = std::move(complex_values);
                            }
                            else
                            {
                                ZxGpuRealArray real_values(time_shape, false);
                                const int mode_code = normalized_mode == "magnitude" ? 0 : 1;
                                complex_to_mode_kernel<<<block_count(real_values.size()), kThreadsPerBlock>>>(
                                    reinterpret_cast<const cufftComplex *>(complex_values.data()),
                                    real_values.size(),
                                    mode_code,
                                    real_values.data());
                                check_kernel_launch("complex_to_mode_kernel");
                                if (normalized_mode == "phase")
                                {
                                    unwrap_phase_kernel<<<block_count(line_count * nseg), kThreadsPerBlock>>>(
                                        real_values.data(),
                                        static_cast<int>(line_count),
                                        static_cast<int>(freq_count),
                                        static_cast<int>(nseg));
                                    check_kernel_launch("unwrap_phase_kernel");
                                }
                                result.values = std::move(real_values);
                            }
                        }
                    }
                });
                return result;
            }

            spectral_api::ZxGpuStftResult stft(
                const core::RealArrayLike &x,
                float fs,
                core::ZxGpuWindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                bool return_onesided,
                const std::string &boundary,
                bool padded,
                int axis)
            {
                thread_local SpectralWorkspace workspace;
                const core::ZxGpuRealArray &x_device = core::as_device_array(x, workspace.x_storage);
                require_last_axis(x_device, axis);
                const std::string normalized_boundary = detail::normalize_boundary(boundary);
                const std::size_t line_len = x_device.shape().back();
                const std::size_t line_count = line_count_last_axis(x_device.shape());
                const int window_len = nperseg > 0 ? nperseg : 256;
                const int resolved_window_len =
                    std::min<int>(window_len, static_cast<int>(line_len == 0 ? 1 : line_len));
                std::string window_cache_key;
                const bool cacheable_window =
                    build_csd_window_cache_key(window, resolved_window_len, fs, "stft", window_cache_key);
                core::ZxGpuRealSignal transient_window;
                const core::ZxGpuRealSignal *window_values = nullptr;
                float spectrum_scale = 0.0f;
                if (cacheable_window &&
                    workspace.segment_window_valid &&
                    workspace.segment_window_key == window_cache_key)
                {
                    window_values = &workspace.segment_window_storage;
                    spectrum_scale = workspace.segment_window_scale;
                }
                else
                {
                    transient_window = zx_gpu_backend::windows::get_window(window, resolved_window_len, true);
                    const RealSignal window_host = transient_window.get();
                    spectrum_scale = detail::spectrum_scale(window_host);
                    if (cacheable_window)
                    {
                        workspace.segment_window_storage = std::move(transient_window);
                        workspace.segment_window_key = window_cache_key;
                        workspace.segment_window_scale = spectrum_scale;
                        workspace.segment_window_valid = true;
                        window_values = &workspace.segment_window_storage;
                    }
                    else
                    {
                        window_values = &transient_window;
                    }
                }
                const detail::SegmentConfig config = detail::resolve_segment_config(
                    line_len,
                    static_cast<int>(window_values->size()),
                    noverlap,
                    nfft,
                    static_cast<int>(window_values->size()),
                    static_cast<int>(window_values->size()) / 2);
                const std::size_t boundary_len =
                    normalized_boundary == "none" ? 0 : static_cast<std::size_t>(config.nperseg / 2);
                std::size_t working_len = line_len + boundary_len * 2;
                if (padded)
                {
                    std::size_t nadd =
                        ((-(static_cast<long long>(working_len) - config.nperseg) % config.step) + config.step) % config.step;
                    nadd %= static_cast<std::size_t>(config.nperseg);
                    working_len += nadd;
                }
                const std::size_t nseg =
                    1 + (working_len - static_cast<std::size_t>(config.nperseg)) / static_cast<std::size_t>(config.step);
                const std::size_t total_fft = total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft);
                workspace.fft_x.reserve(total_fft);
                const float scale = std::sqrt(spectrum_scale);
                const std::size_t freq_count = detail::frequency_count(config.nfft, return_onesided);
                Shape output_shape = core::replace_axis_size(x_device.shape(), axis, freq_count);
                output_shape.push_back(nseg);

                spectral_api::ZxGpuStftResult result;
                result.frequencies = cached_frequency_axis(workspace, config.nfft, fs, return_onesided);
                result.times = cached_segment_times(
                    workspace,
                    working_len,
                    config.nperseg,
                    config.step,
                    fs,
                    normalized_boundary != "none");
                result.values = ZxGpuComplexArray(output_shape, false);

                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                        x_device.data(),
                        static_cast<int>(line_count),
                        static_cast<int>(line_len),
                        static_cast<int>(nseg),
                        config.nperseg,
                        config.step,
                        config.nfft,
                        boundary_mode_code(normalized_boundary),
                        static_cast<int>(boundary_len),
                        window_values->data(),
                        detrend_mode_code(detrend),
                        workspace.fft_x.get());
                    check_kernel_launch("prepare_segments_kernel(stft)");
                    workspace.forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                    throw_on_cufft_error(
                        cufftExecC2C(workspace.forward_plan.handle, workspace.fft_x.get(), workspace.fft_x.get(), CUFFT_FORWARD),
                        "cufftExecC2C(stft)");
                    spectrogram_complex_kernel<<<block_count(result.values.size()), kThreadsPerBlock>>>(
                        workspace.fft_x.get(),
                        static_cast<int>(line_count),
                        static_cast<int>(nseg),
                        config.nfft,
                        static_cast<int>(freq_count),
                        scale,
                        reinterpret_cast<cufftComplex *>(result.values.data()));
                    check_kernel_launch("spectrogram_complex_kernel(stft)");
                });
                return result;
            }

            spectral_api::ZxGpuIstftResult istft(
                const core::ComplexArrayLike &zxx,
                float fs,
                core::ZxGpuWindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                bool input_onesided,
                bool boundary,
                int time_axis,
                int freq_axis)
            {
                thread_local SpectralWorkspace workspace;
                if (g_istft_cache_reset_requested)
                {
                    workspace.segment_window_valid = false;
                    workspace.time_axis_valid = false;
                    g_istft_cache_reset_requested = false;
                }
                g_last_istft_cache_state = kIstftCacheStateBypass;
                const core::ZxGpuComplexArray &z_device = core::as_device_array(zxx, workspace.z_storage);
                const std::size_t rank = z_device.rank();
                const std::size_t normalized_time = core::normalize_axis(time_axis, rank);
                const std::size_t normalized_freq = core::normalize_axis(freq_axis, rank);
                if (rank < 2 || normalized_time != rank - 1 || normalized_freq != rank - 2)
                {
                    throw std::invalid_argument("CUDA istft currently requires freq_axis=-2 and time_axis=-1");
                }
                const std::size_t freq_bins = z_device.shape()[normalized_freq];
                const std::size_t time_count = z_device.shape()[normalized_time];
                const Shape outer_shape(z_device.shape().begin(), z_device.shape().end() - 2);
                const std::size_t outer_count = outer_shape.empty() ? 1 : core::shape_product(outer_shape);
                const int resolved_nperseg = resolve_istft_nperseg(freq_bins, input_onesided, nperseg);
                const int resolved_nfft = resolve_istft_nfft(freq_bins, input_onesided, resolved_nperseg, nfft);
                const int resolved_noverlap = noverlap < 0 ? resolved_nperseg / 2 : noverlap;
                if (resolved_noverlap >= resolved_nperseg)
                {
                    throw std::invalid_argument("noverlap must be less than nperseg.");
                }
                const int step = resolved_nperseg - resolved_noverlap;
                std::string window_cache_key;
                const bool cacheable_window =
                    build_csd_window_cache_key(
                        window,
                        resolved_nperseg,
                        0.0f,
                        "istft",
                        window_cache_key);
                const bool use_setup_cache =
                    tile::optimized_path() &&
                    cacheable_window &&
                    g_istft_cache_override != kIstftCacheBypass;
                core::ZxGpuRealSignal transient_window;
                const core::ZxGpuRealSignal *window_values = nullptr;
                float window_sum = 0.0f;
                bool window_cache_hit = false;
                if (use_setup_cache &&
                    workspace.segment_window_valid &&
                    workspace.segment_window_key == window_cache_key)
                {
                    window_values = &workspace.segment_window_storage;
                    window_sum = workspace.segment_window_scale;
                    window_cache_hit = true;
                }
                else
                {
                    transient_window =
                        zx_gpu_backend::windows::get_window(
                            window,
                            resolved_nperseg,
                            true);
                    const RealSignal window_host = transient_window.get();
                    window_sum =
                        std::accumulate(
                            window_host.begin(),
                            window_host.end(),
                            0.0);
                    if (use_setup_cache)
                    {
                        workspace.segment_window_storage =
                            std::move(transient_window);
                        workspace.segment_window_key = window_cache_key;
                        workspace.segment_window_scale = window_sum;
                        workspace.segment_window_valid = true;
                        window_values = &workspace.segment_window_storage;
                    }
                    else
                    {
                        window_values = &transient_window;
                    }
                }
                const std::size_t spectrum_count = outer_count * time_count * static_cast<std::size_t>(resolved_nfft);
                workspace.fft_full.zero(spectrum_count);
                const std::size_t final_length = boundary
                                                     ? static_cast<std::size_t>(resolved_nperseg + (time_count - 1) * step - resolved_nperseg)
                                                     : static_cast<std::size_t>(resolved_nperseg + (time_count - 1) * step);
                spectral_api::ZxGpuIstftResult result;
                Shape output_shape = outer_shape;
                output_shape.push_back(final_length);
                result.signal = core::make_zx_gpu_real_array(output_shape);
                if (use_setup_cache)
                {
                    bool time_cache_hit = false;
                    result.times =
                        cached_sample_times(
                            workspace,
                            final_length,
                            fs,
                            &time_cache_hit);
                    g_last_istft_cache_state =
                        window_cache_hit && time_cache_hit
                            ? kIstftCacheStateHit
                            : kIstftCacheStateMiss;
                }
                else
                {
                    result.times = core::ZxGpuRealSignal::from_host([&]() {
                        RealSignal times(final_length, 0.0);
                        for (std::size_t index = 0; index < final_length; ++index)
                        {
                            times[index] = static_cast<float>(index) / fs;
                        }
                        return times;
                    }());
                }

                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    if (input_onesided)
                    {
                        expand_onesided_kernel<<<block_count(spectrum_count), kThreadsPerBlock>>>(
                            reinterpret_cast<const cufftComplex *>(z_device.data()),
                            static_cast<int>(outer_count),
                            static_cast<int>(time_count),
                            static_cast<int>(freq_bins),
                            resolved_nfft,
                            workspace.fft_full.get());
                        check_kernel_launch("expand_onesided_kernel");
                    }
                    else
                    {
                        copy_twosided_kernel<<<block_count(z_device.size()), kThreadsPerBlock>>>(
                            reinterpret_cast<const cufftComplex *>(z_device.data()),
                            z_device.size(),
                            workspace.fft_full.get());
                        check_kernel_launch("copy_twosided_kernel");
                    }
                    workspace.inverse_plan.ensure(resolved_nfft, static_cast<int>(outer_count * time_count));
                    throw_on_cufft_error(
                        cufftExecC2C(workspace.inverse_plan.handle, workspace.fft_full.get(), workspace.fft_full.get(), CUFFT_INVERSE),
                        "cufftExecC2C(istft)");
                    overlap_add_kernel<<<block_count(result.signal.size()), kThreadsPerBlock>>>(
                        workspace.fft_full.get(),
                        static_cast<int>(outer_count),
                        static_cast<int>(time_count),
                        resolved_nfft,
                        resolved_nperseg,
                        step,
                        window_sum,
                        window_values->data(),
                        boundary ? resolved_nperseg / 2 : 0,
                        static_cast<int>(final_length),
                        result.signal.data());
                    check_kernel_launch("overlap_add_kernel");
                });
                return result;
            }

            spectral_api::ZxGpuRealSpectrumResult coherence(
                const core::RealArrayLike &x,
                const core::RealArrayLike &y,
                float fs,
                core::ZxGpuWindowSpec window,
                int nperseg,
                int noverlap,
                int nfft,
                core::DetrendSpec detrend,
                int axis)
            {
                thread_local SpectralWorkspace workspace;
                const core::ZxGpuRealArray &x_device = core::as_device_array(x, workspace.x_storage);
                const core::ZxGpuRealArray &y_device = core::as_device_array(y, workspace.y_storage);
                require_last_axis(x_device, axis);
                require_last_axis(y_device, axis);
                if (x_device.shape() != y_device.shape())
                {
                    throw std::invalid_argument("x and y must have the same shape");
                }

                const std::size_t line_len = x_device.shape().back();
                const std::size_t line_count = line_count_last_axis(x_device.shape());
                const int window_size =
                    nperseg > 0 ? std::min<int>(nperseg, static_cast<int>(line_len)) : std::min<int>(256, static_cast<int>(line_len));
                std::string window_cache_key;
                const bool cacheable_window =
                    build_csd_window_cache_key(window, window_size, fs, "density", window_cache_key);
                core::ZxGpuRealSignal transient_window;
                const core::ZxGpuRealSignal *window_values = nullptr;
                float scale = 0.0f;
                if (cacheable_window &&
                    workspace.csd_window_valid &&
                    workspace.csd_window_key == window_cache_key)
                {
                    window_values = &workspace.csd_window_storage;
                    scale = workspace.csd_window_scale;
                }
                else
                {
                    transient_window = zx_gpu_backend::windows::get_window(window, window_size, true);
                    const RealSignal window_host = transient_window.get();
                    scale = detail::density_scale(window_host, fs);
                    if (cacheable_window)
                    {
                        workspace.csd_window_storage = std::move(transient_window);
                        workspace.csd_window_key = window_cache_key;
                        workspace.csd_window_scale = scale;
                        workspace.csd_window_valid = true;
                        window_values = &workspace.csd_window_storage;
                    }
                    else
                    {
                        window_values = &transient_window;
                    }
                }

                const detail::SegmentConfig config = detail::resolve_segment_config(
                    line_len,
                    static_cast<int>(window_values->size()),
                    noverlap,
                    nfft,
                    static_cast<int>(window_values->size()),
                    static_cast<int>(window_values->size()) / 2);
                const std::size_t nseg =
                    1 + (line_len - static_cast<std::size_t>(config.nperseg)) / static_cast<std::size_t>(config.step);
                const std::size_t total_fft = total_segments(line_count, nseg) * static_cast<std::size_t>(config.nfft);
                const std::size_t freq_count = detail::frequency_count(config.nfft, true);
                workspace.fft_x.reserve(total_fft);
                workspace.fft_y.reserve(total_fft);

                spectral_api::ZxGpuRealSpectrumResult result;
                result.frequencies = cached_frequency_axis(workspace, config.nfft, fs, true);
                result.values = core::make_zx_gpu_real_array(core::replace_axis_size(x_device.shape(), axis, freq_count));
                const int detrend_code = detrend_mode_code(detrend);
                ScopedZxGpuEvents events;
                measure_gpu_compute(events, [&]() {
                    if (detrend_code == 1)
                    {
                        const int segment_count = static_cast<int>(line_count * nseg);
                        prepare_segments_complex_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                            x_device.data(),
                            static_cast<int>(line_count),
                            static_cast<int>(line_len),
                            static_cast<int>(nseg),
                            config.nperseg,
                            config.step,
                            config.nfft,
                            window_values->data(),
                            workspace.fft_x.get());
                        prepare_segments_complex_constant_kernel<<<segment_count, kThreadsPerBlock>>>(
                            y_device.data(),
                            static_cast<int>(line_count),
                            static_cast<int>(line_len),
                            static_cast<int>(nseg),
                            config.nperseg,
                            config.step,
                            config.nfft,
                            window_values->data(),
                            workspace.fft_y.get());
                        check_kernel_launch("prepare_segments_complex_constant_kernel(coherence)");
                    }
                    else
                    {
                        prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                            x_device.data(),
                            static_cast<int>(line_count),
                            static_cast<int>(line_len),
                            static_cast<int>(nseg),
                            config.nperseg,
                            config.step,
                            config.nfft,
                            0,
                            0,
                            window_values->data(),
                            detrend_code,
                            workspace.fft_x.get());
                        prepare_segments_kernel<<<block_count(total_fft), kThreadsPerBlock>>>(
                            y_device.data(),
                            static_cast<int>(line_count),
                            static_cast<int>(line_len),
                            static_cast<int>(nseg),
                            config.nperseg,
                            config.step,
                            config.nfft,
                            0,
                            0,
                            window_values->data(),
                            detrend_code,
                            workspace.fft_y.get());
                        check_kernel_launch("prepare_segments_kernel(coherence)");
                    }
                    workspace.forward_plan.ensure(config.nfft, static_cast<int>(line_count * nseg));
                    throw_on_cufft_error(
                        cufftExecC2C(workspace.forward_plan.handle, workspace.fft_x.get(), workspace.fft_x.get(), CUFFT_FORWARD),
                        "cufftExecC2C(coherence/x)");
                    throw_on_cufft_error(
                        cufftExecC2C(workspace.forward_plan.handle, workspace.fft_y.get(), workspace.fft_y.get(), CUFFT_FORWARD),
                        "cufftExecC2C(coherence/y)");
                    coherence_from_fft_kernel<<<block_count(result.values.size()), kThreadsPerBlock>>>(
                        workspace.fft_x.get(),
                        workspace.fft_y.get(),
                        static_cast<int>(line_count),
                        static_cast<int>(nseg),
                        config.nfft,
                        static_cast<int>(freq_count),
                        scale,
                        result.values.data());
                    check_kernel_launch("coherence_from_fft_kernel");
                });
                return result;
            }

            spectral_api::ZxGpuVectorStrengthResult vectorstrength(
                const core::RealSignalLike &events,
                float period)
            {
                if (!(period > 0.0))
                {
                    throw std::invalid_argument("period must be > 0");
                }
                thread_local SpectralWorkspace workspace;
                const core::ZxGpuRealSignal &events_device = core::as_device_signal(events, workspace.x_signal_storage);
                RealSignal period_host{period};
                workspace.period_storage.copy_from(period_host);
                spectral_api::ZxGpuVectorStrengthResult result;
                result.strength = core::ZxGpuRealSignal(1, false);
                result.phase = core::ZxGpuRealSignal(1, false);
                ScopedZxGpuEvents events_timer;
                measure_gpu_compute(events_timer, [&]() {
                    const int event_count = static_cast<int>(events_device.size());
                    const int blocks_per_period =
                        std::max(1, std::min(kVectorStrengthMaxBlocksPerPeriod, block_count(events_device.size())));
                    workspace.reduction_scratch_a.reserve(static_cast<std::size_t>(blocks_per_period));
                    workspace.reduction_scratch_b.reserve(static_cast<std::size_t>(blocks_per_period));
                    vectorstrength_partial_kernel<<<dim3(1, blocks_per_period), kThreadsPerBlock>>>(
                        events_device.data(),
                        event_count,
                        workspace.period_storage.data(),
                        1,
                        blocks_per_period,
                        workspace.reduction_scratch_a.get(),
                        workspace.reduction_scratch_b.get());
                    check_kernel_launch("vectorstrength_partial_kernel(scalar)");
                    vectorstrength_finalize_kernel<<<1, kThreadsPerBlock>>>(
                        workspace.reduction_scratch_a.get(),
                        workspace.reduction_scratch_b.get(),
                        event_count,
                        blocks_per_period,
                        result.strength.data(),
                        result.phase.data());
                    check_kernel_launch("vectorstrength_finalize_kernel(scalar)");
                });
                return result;
            }

            spectral_api::ZxGpuVectorStrengthResult vectorstrength(
                const core::RealSignalLike &events,
                const core::RealSignalLike &period)
            {
                thread_local SpectralWorkspace workspace;
                const core::ZxGpuRealSignal &events_device = core::as_device_signal(events, workspace.x_signal_storage);
                RealSignal host_periods;
                const core::ZxGpuRealSignal *period_device = nullptr;
                if (const auto *host = std::get_if<RealSignal>(&period))
                {
                    host_periods = *host;
                    if (host_periods.empty())
                    {
                        throw std::invalid_argument("period must not be empty");
                    }
                    for (float value : host_periods)
                    {
                        if (!(value > 0.0))
                        {
                            throw std::invalid_argument("period entries must be > 0");
                        }
                    }
                    if (!workspace.vectorstrength_period_cache_valid ||
                        workspace.vectorstrength_period_cache != host_periods)
                    {
                        workspace.period_storage.copy_from(host_periods);
                        workspace.vectorstrength_period_cache = host_periods;
                        workspace.vectorstrength_period_cache_valid = true;
                    }
                    period_device = &workspace.period_storage;
                }
                else
                {
                    const auto &device = std::get<core::ZxGpuRealSignal>(period);
                    period_device = &device;
                }
                if (period_device->empty())
                {
                    throw std::invalid_argument("period must not be empty");
                }
                if (host_periods.empty())
                {
                    host_periods = period_device->get();
                    for (float value : host_periods)
                    {
                        if (!(value > 0.0))
                        {
                            throw std::invalid_argument("period entries must be > 0");
                        }
                    }
                }
                spectral_api::ZxGpuVectorStrengthResult result;
                result.strength = core::ZxGpuRealSignal(period_device->size(), false);
                result.phase = core::ZxGpuRealSignal(period_device->size(), false);
                ScopedZxGpuEvents events_timer;
                measure_gpu_compute(events_timer, [&]() {
                    const int event_count = static_cast<int>(events_device.size());
                    const int period_count = static_cast<int>(period_device->size());
                    const int blocks_per_period =
                        std::max(1, std::min(kVectorStrengthMaxBlocksPerPeriod, block_count(events_device.size())));
                    const std::size_t partial_count =
                        static_cast<std::size_t>(period_count) *
                        static_cast<std::size_t>(blocks_per_period);
                    workspace.reduction_scratch_a.reserve(partial_count);
                    workspace.reduction_scratch_b.reserve(partial_count);
                    const bool use_pair_kernel =
                        period_count >= 2 &&
                        blocks_per_period >= kVectorStrengthPairMinBlocksPerPeriod;
                    if (use_pair_kernel)
                    {
                        const int pair_count = period_count / 2;
                        vectorstrength_partial_pair_kernel<<<
                            dim3(pair_count, blocks_per_period),
                            kThreadsPerBlock>>>(
                            events_device.data(),
                            event_count,
                            period_device->data(),
                            blocks_per_period,
                            workspace.reduction_scratch_a.get(),
                            workspace.reduction_scratch_b.get());
                        check_kernel_launch("vectorstrength_partial_pair_kernel(vector)");
                        if (period_count % 2 != 0)
                        {
                            const std::size_t final_period_offset =
                                static_cast<std::size_t>(pair_count * 2) *
                                static_cast<std::size_t>(blocks_per_period);
                            vectorstrength_partial_kernel<<<
                                dim3(1, blocks_per_period),
                                kThreadsPerBlock>>>(
                                events_device.data(),
                                event_count,
                                period_device->data() + pair_count * 2,
                                1,
                                blocks_per_period,
                                workspace.reduction_scratch_a.get() + final_period_offset,
                                workspace.reduction_scratch_b.get() + final_period_offset);
                            check_kernel_launch("vectorstrength_partial_kernel(vector_tail)");
                        }
                    }
                    else
                    {
                        vectorstrength_partial_kernel<<<dim3(period_count, blocks_per_period), kThreadsPerBlock>>>(
                            events_device.data(),
                            event_count,
                            period_device->data(),
                            period_count,
                            blocks_per_period,
                            workspace.reduction_scratch_a.get(),
                            workspace.reduction_scratch_b.get());
                        check_kernel_launch("vectorstrength_partial_kernel(vector)");
                    }
                    vectorstrength_finalize_kernel<<<period_count, kThreadsPerBlock>>>(
                        workspace.reduction_scratch_a.get(),
                        workspace.reduction_scratch_b.get(),
                        event_count,
                        blocks_per_period,
                        result.strength.data(),
                        result.phase.data());
                    check_kernel_launch("vectorstrength_finalize_kernel(vector)");
                });
                return result;
            }
        } // namespace spectral

        namespace spectral_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0;
                return value;
            }

            int consume_last_periodogram_cache_state()
            {
                const int value = g_last_periodogram_cache_state;
                g_last_periodogram_cache_state = kPeriodogramCacheStateBypass;
                return value;
            }

            void set_periodogram_cache_override(int mode)
            {
                if (mode != kPeriodogramCacheAuto &&
                    mode != kPeriodogramCacheBypass &&
                    mode != kPeriodogramCacheEnabled)
                {
                    throw std::invalid_argument("invalid periodogram cache override");
                }
                g_periodogram_cache_override = mode;
            }

            void reset_periodogram_cache()
            {
                g_periodogram_cache_reset_requested = true;
                g_last_periodogram_cache_state = kPeriodogramCacheStateBypass;
            }

            int consume_last_welch_cache_state()
            {
                const int value = g_last_welch_cache_state;
                g_last_welch_cache_state = kWelchCacheStateBypass;
                return value;
            }

            void set_welch_cache_override(int mode)
            {
                if (mode != kWelchCacheAuto &&
                    mode != kWelchCacheBypass &&
                    mode != kWelchCacheEnabled)
                {
                    throw std::invalid_argument("invalid welch cache override");
                }
                g_welch_cache_override = mode;
            }

            void reset_welch_cache()
            {
                g_welch_cache_reset_requested = true;
                g_last_welch_cache_state = kWelchCacheStateBypass;
            }

            int consume_last_istft_cache_state()
            {
                const int value = g_last_istft_cache_state;
                g_last_istft_cache_state = kIstftCacheStateBypass;
                return value;
            }

            void set_istft_cache_override(int mode)
            {
                if (mode != kIstftCacheAuto &&
                    mode != kIstftCacheBypass &&
                    mode != kIstftCacheEnabled)
                {
                    throw std::invalid_argument("invalid istft cache override");
                }
                g_istft_cache_override = mode;
            }

            void reset_istft_cache()
            {
                g_istft_cache_reset_requested = true;
                g_last_istft_cache_state = kIstftCacheStateBypass;
            }
        } // namespace spectral_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
