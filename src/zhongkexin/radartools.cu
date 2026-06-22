#include "cusignal/radartools/radartools.hpp"

#include <cublas_v2.h>
#include <cuda_runtime.h>
#include <cufft.h>
#include <cusolverDn.h>

#include <algorithm>
#include <cmath>
#include <complex>
#include <stdexcept>
#include <utility>
#include <vector>

#include "cusignal/core/helpers.hpp"
#include "cusignal/windows/windows.hpp"

#include "../common/radartools_detail.hpp"

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
    using cusignal::core::RealArrayLike;
    namespace detail = cusignal::radartools_detail;

    constexpr int kThreadsPerBlock = 256;
    constexpr int kCfarFftWindowThreshold = 256;
    constexpr int kCfarFftMinSize = 4096;
    constexpr int kCfarSmall2dFootprint = 256;
    thread_local float g_last_kernel_ms = 0.0;

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

    void throw_on_cublas_error(cublasStatus_t status, const char *what)
    {
        if (status == CUBLAS_STATUS_SUCCESS)
        {
            return;
        }
        throw std::runtime_error(std::string(what) + ": cuBLAS error code " + std::to_string(static_cast<int>(status)));
    }

    void throw_on_cusolver_error(cusolverStatus_t status, const char *what)
    {
        if (status == CUSOLVER_STATUS_SUCCESS)
        {
            return;
        }
        throw std::runtime_error(std::string(what) + ": cuSOLVER error code " + std::to_string(static_cast<int>(status)));
    }

    void check_kernel_launch(const char *what)
    {
        throw_on_zx_gpu_error(cudaGetLastError(), what);
    }

    template <typename T>
    class DeviceBuffer
    {
    public:
        DeviceBuffer() = default;

        ~DeviceBuffer()
        {
            release();
        }

        DeviceBuffer(const DeviceBuffer &) = delete;
        DeviceBuffer &operator=(const DeviceBuffer &) = delete;

        void reserve(std::size_t size)
        {
            if (size <= capacity_)
            {
                return;
            }
            release();
            if (size == 0)
            {
                return;
            }
            throw_on_zx_gpu_error(cudaMalloc(&data_, size * sizeof(T)), "cudaMalloc");
            capacity_ = size;
        }

        void zero(std::size_t size)
        {
            if (size == 0)
            {
                return;
            }
            reserve(size);
            throw_on_zx_gpu_error(cudaMemset(data_, 0, size * sizeof(T)), "cudaMemset");
        }

        T *get()
        {
            return data_;
        }

        const T *get() const
        {
            return data_;
        }

    private:
        void release()
        {
            if (data_ != nullptr)
            {
                cudaFree(data_);
                data_ = nullptr;
            }
            capacity_ = 0;
        }

        T *data_ = nullptr;
        std::size_t capacity_ = 0;
    };

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

    struct PulseWorkspace
    {
        ZxGpuComplexArray x_storage;
        ZxGpuComplexSignal templ_storage;
        DeviceBuffer<cufftComplex> template_fft;
        DeviceBuffer<cufftComplex> doppler_transposed;
        GenericPlan plan;
    };

    struct AmbgfunWorkspace
    {
        ZxGpuComplexSignal x_storage;
        ZxGpuComplexSignal y_storage;
        DeviceBuffer<cufftComplex> x_buffer;
        DeviceBuffer<cufftComplex> y_buffer;
        DeviceBuffer<cufftComplex> matrix_buffer;
        const void *normalized_x_ptr = nullptr;
        const void *normalized_y_ptr = nullptr;
        std::size_t normalized_x_size = 0;
        std::size_t normalized_y_size = 0;
        bool normalized_cache_valid = false;
        GenericPlan plan;
    };

    struct CfarWorkspace
    {
        ZxGpuRealArray array_storage;
        DeviceBuffer<float> row_prefix;
        DeviceBuffer<float> integral;
        DeviceBuffer<cufftComplex> fft_signal;
        DeviceBuffer<cufftComplex> fft_kernel;
        GenericPlan fft_plan;
    };

    __global__ void fftshift_rows_kernel(
        const float2 *input,
        float2 *output,
        std::size_t rows,
        std::size_t cols)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = rows * cols;
        if (index >= total)
            return;
        const std::size_t row = index / cols;
        const std::size_t col = index % cols;
        const std::size_t shifted_row = (row + rows / 2) % rows;
        output[shifted_row * cols + col] = input[index];
    }

    __global__ void power_map_kernel(const float2 *input, float *output, std::size_t size)
    {
        const std::size_t index = static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
            return;
        const float2 value = input[index];
        output[index] = value.x * value.x + value.y * value.y;
    }

    __global__ void detect_peak_kernel(
        const float *power,
        const float *detections,
        std::size_t rows,
        std::size_t cols,
        int nfft,
        float prf,
        cusignal::radartools_api::DetectionSummary *result)
    {
        if (blockIdx.x != 0 || threadIdx.x != 0)
            return;
        cusignal::radartools_api::DetectionSummary local;
        const std::size_t size = rows * cols;
        for (std::size_t index = 0; index < size; ++index)
        {
            if (detections[index] <= 0.5f || (local.found && power[index] <= local.power))
                continue;
            local.found = true;
            local.power = power[index];
            local.range_bin = static_cast<int>(index % cols);
            local.doppler_bin = static_cast<int>(index / cols);
        }
        if (local.found)
        {
            local.doppler_hz = static_cast<float>(local.doppler_bin - nfft / 2) *
                prf / static_cast<float>(nfft);
        }
        *result = local;
    }

    struct BeamformerWorkspace
    {
        ZxGpuComplexArray x_storage;
        ZxGpuComplexArray sv_storage;
        DeviceBuffer<cuComplex> centered;
        DeviceBuffer<cuComplex> covariance;
        DeviceBuffer<cuComplex> rhs;
        DeviceBuffer<cuComplex> means;
        DeviceBuffer<cuComplex> work;
        DeviceBuffer<int> ipiv;
        DeviceBuffer<int> info;
        cublasHandle_t cublas = nullptr;
        cusolverDnHandle_t cusolver = nullptr;

        ~BeamformerWorkspace()
        {
            if (cublas != nullptr)
            {
                cublasDestroy(cublas);
            }
            if (cusolver != nullptr)
            {
                cusolverDnDestroy(cusolver);
            }
        }

        void ensure_handles()
        {
            if (cublas == nullptr)
            {
                throw_on_cublas_error(cublasCreate(&cublas), "cublasCreate");
            }
            if (cusolver == nullptr)
            {
                throw_on_cusolver_error(cusolverDnCreate(&cusolver), "cusolverDnCreate");
            }
        }
    };

    struct TaskPipelineWorkspace
    {
        ZxGpuComplexArray complex_storage;
        ZxGpuRealArray power_storage;
        ZxGpuRealArray detections_storage;
        DeviceBuffer<cusignal::radartools_api::DetectionSummary> detection_result;
    };

    struct RadartoolsWorkspace
    {
        PulseWorkspace pulse;
        AmbgfunWorkspace ambgfun;
        CfarWorkspace cfar;
        BeamformerWorkspace beamformer;
        TaskPipelineWorkspace task_pipeline;
    };

    thread_local RadartoolsWorkspace g_workspace;

    int block_count(std::size_t size)
    {
        return size == 0 ? 0 : static_cast<int>((size + kThreadsPerBlock - 1) / kThreadsPerBlock);
    }

    __device__ inline float2 make_complex(float real, float imag)
    {
        return float2{real, imag};
    }

    __device__ inline float2 complex_conj(float2 value)
    {
        return make_complex(value.x, -value.y);
    }

    __device__ inline float2 complex_mul(float2 lhs, float2 rhs)
    {
        return make_complex(lhs.x * rhs.x - lhs.y * rhs.y, lhs.x * rhs.y + lhs.y * rhs.x);
    }

    __global__ void pack_template_kernel(
        const float2 *templ,
        const float *window,
        std::size_t templ_size,
        bool use_window,
        cufftComplex *output,
        int nfft)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= static_cast<std::size_t>(nfft))
        {
            return;
        }
        if (index < templ_size)
        {
            float2 value = templ[index];
            if (use_window)
            {
                value.x *= window[index];
                value.y *= window[index];
            }
            output[index].x = value.x;
            output[index].y = value.y;
        }
        else
        {
            output[index].x = 0.0;
            output[index].y = 0.0;
        }
    }

    __global__ void pack_pulse_rows_kernel(
        const float2 *input,
        std::size_t pulses,
        std::size_t samples,
        int nfft,
        float2 *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = pulses * static_cast<std::size_t>(nfft);
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / static_cast<std::size_t>(nfft);
        const std::size_t col = flat % static_cast<std::size_t>(nfft);
        if (col < samples)
        {
            output[flat] = input[row * samples + col];
        }
        else
        {
            output[flat] = make_complex(0.0, 0.0);
        }
    }

    __global__ void multiply_conj_template_kernel(
        float2 *values,
        const cufftComplex *templ_fft,
        std::size_t total,
        int nfft)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= total)
        {
            return;
        }
        const std::size_t col = index % static_cast<std::size_t>(nfft);
        const float2 lhs = values[index];
        const float2 rhs = make_complex(templ_fft[col].x, templ_fft[col].y);
        values[index] = complex_mul(lhs, complex_conj(rhs));
    }

    __global__ void scale_complex_kernel(float2 *values, std::size_t size, float scale)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            values[index].x *= scale;
            values[index].y *= scale;
        }
    }

    __global__ void pack_pulse_doppler_kernel(
        const float2 *input,
        std::size_t pulses,
        std::size_t samples,
        int padded_pulses,
        const float *window,
        bool use_window,
        cufftComplex *transposed)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = pulses * samples;
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / samples;
        const std::size_t col = flat % samples;
        if (row >= static_cast<std::size_t>(padded_pulses))
        {
            return;
        }
        float2 value = input[row * samples + col];
        if (use_window)
        {
            value.x *= window[row];
            value.y *= window[row];
        }
        transposed[col * static_cast<std::size_t>(padded_pulses) + row].x = value.x;
        transposed[col * static_cast<std::size_t>(padded_pulses) + row].y = value.y;
    }

    __global__ void zero_complex_rows_kernel(
        cufftComplex *buffer,
        std::size_t rows,
        std::size_t cols,
        std::size_t padded_cols)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = rows * padded_cols;
        if (flat >= total)
        {
            return;
        }
        const std::size_t col = flat % padded_cols;
        if (col >= cols)
        {
            buffer[flat].x = 0.0;
            buffer[flat].y = 0.0;
        }
    }

    __global__ void transpose_doppler_output_kernel(
        const cufftComplex *transposed,
        std::size_t samples,
        int nfft,
        float2 *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(nfft) * samples;
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / samples;
        const std::size_t col = flat % samples;
        const cufftComplex value = transposed[col * static_cast<std::size_t>(nfft) + row];
        output[flat] = make_complex(value.x, value.y);
    }

    __global__ void copy_scale_complex_kernel(
        const float2 *input,
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

    __global__ void build_shifted_matrix_kernel(
        const float2 *xnorm,
        const float2 *ynorm,
        std::size_t xlen,
        std::size_t ylen,
        std::size_t rows,
        int nfreq,
        cufftComplex *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = rows * static_cast<std::size_t>(nfreq);
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / static_cast<std::size_t>(nfreq);
        const std::size_t col = flat % static_cast<std::size_t>(nfreq);
        if (col < ylen)
        {
            const long long x_index =
                static_cast<long long>(col) - static_cast<long long>(xlen - 1) +
                static_cast<long long>(row);
            if (x_index >= 0 && x_index < static_cast<long long>(xlen))
            {
                const float2 a = ynorm[col];
                const float2 b = xnorm[static_cast<std::size_t>(x_index)];
                const float2 value = complex_mul(a, complex_conj(b));
                output[flat].x = value.x;
                output[flat].y = value.y;
                return;
            }
        }
        output[flat].x = 0.0;
        output[flat].y = 0.0;
    }

    __global__ void build_shifted_matrix_tile_kernel(
        const float2 *xnorm,
        const float2 *ynorm,
        std::size_t xlen,
        std::size_t ylen,
        std::size_t row_offset,
        std::size_t tile_rows,
        int nfreq,
        cufftComplex *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = tile_rows * static_cast<std::size_t>(nfreq);
        if (flat >= total)
        {
            return;
        }
        const std::size_t local_row = flat / static_cast<std::size_t>(nfreq);
        const std::size_t row = row_offset + local_row;
        const std::size_t col = flat % static_cast<std::size_t>(nfreq);
        if (col < ylen)
        {
            const long long x_index =
                static_cast<long long>(col) - static_cast<long long>(xlen - 1) +
                static_cast<long long>(row);
            if (x_index >= 0 && x_index < static_cast<long long>(xlen))
            {
                const float2 a = ynorm[col];
                const float2 b = xnorm[static_cast<std::size_t>(x_index)];
                const float2 value = complex_mul(a, complex_conj(b));
                output[flat].x = value.x;
                output[flat].y = value.y;
                return;
            }
        }
        output[flat].x = 0.0;
        output[flat].y = 0.0;
    }

    __global__ void extract_surface_kernel(
        const cufftComplex *input,
        std::size_t rows,
        int nfreq,
        float *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = rows * static_cast<std::size_t>(nfreq);
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / static_cast<std::size_t>(nfreq);
        const std::size_t col = flat % static_cast<std::size_t>(nfreq);
        std::size_t shifted = col + static_cast<std::size_t>(nfreq / 2);
        if (shifted >= static_cast<std::size_t>(nfreq))
        {
            shifted -= static_cast<std::size_t>(nfreq);
        }
        const cufftComplex value = input[row * static_cast<std::size_t>(nfreq) + shifted];
        output[flat] = sqrtf(fmaf(value.x, value.x, value.y * value.y));
    }

    __global__ void extract_surface_tile_kernel(
        const cufftComplex *input,
        std::size_t row_offset,
        std::size_t tile_rows,
        int nfreq,
        float *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = tile_rows * static_cast<std::size_t>(nfreq);
        if (flat >= total)
        {
            return;
        }
        const std::size_t local_row = flat / static_cast<std::size_t>(nfreq);
        const std::size_t col = flat % static_cast<std::size_t>(nfreq);
        std::size_t shifted = col + static_cast<std::size_t>(nfreq / 2);
        if (shifted >= static_cast<std::size_t>(nfreq))
        {
            shifted -= static_cast<std::size_t>(nfreq);
        }
        const cufftComplex value = input[local_row * static_cast<std::size_t>(nfreq) + shifted];
        output[(row_offset + local_row) * static_cast<std::size_t>(nfreq) + col] =
            sqrtf(fmaf(value.x, value.x, value.y * value.y));
    }

    __global__ void build_doppler_axis_kernel(float *axis, int nfreq, float fs)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < static_cast<std::size_t>(nfreq))
        {
            axis[index] = -0.5 * fs + fs * static_cast<float>(index) / static_cast<float>(nfreq);
        }
    }

    __global__ void build_delay_axis_kernel(float *axis, std::size_t xlen, std::size_t ylen, float fs)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t size = xlen + ylen - 1;
        if (index < size)
        {
            axis[index] =
                static_cast<float>(static_cast<long long>(index) - static_cast<long long>(xlen - 1)) / fs;
        }
    }

    __global__ void apply_frequency_phase_kernel(
        cufftComplex *spectrum,
        int nfreq,
        float fs,
        float cut_value)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= static_cast<std::size_t>(nfreq))
        {
            return;
        }
        const float freq = -0.5 * fs + fs * static_cast<float>(index) / static_cast<float>(nfreq);
        const float angle = 2.0 * detail::kPi * freq * cut_value;
        const float2 phase = make_complex(cos(angle), sin(angle));
        const float2 value = make_complex(spectrum[index].x, spectrum[index].y);
        const float2 result = complex_mul(value, phase);
        spectrum[index].x = result.x;
        spectrum[index].y = result.y;
    }

    __global__ void pack_signal_kernel(
        const float2 *input,
        std::size_t input_size,
        cufftComplex *output,
        int output_size)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= static_cast<std::size_t>(output_size))
        {
            return;
        }
        if (index < input_size)
        {
            output[index].x = input[index].x;
            output[index].y = input[index].y;
        }
        else
        {
            output[index].x = 0.0;
            output[index].y = 0.0;
        }
    }

    __global__ void multiply_with_conj_kernel(
        const cufftComplex *lhs,
        const cufftComplex *rhs,
        cufftComplex *output,
        std::size_t size)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const float2 a = make_complex(lhs[index].x, lhs[index].y);
        const float2 b = make_complex(rhs[index].x, rhs[index].y);
        const float2 value = complex_mul(a, complex_conj(b));
        output[index].x = value.x;
        output[index].y = value.y;
    }

    __global__ void modulate_and_pack_kernel(
        const float2 *input,
        std::size_t input_size,
        float fs,
        float cut_value,
        cufftComplex *output,
        int output_size)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= static_cast<std::size_t>(output_size))
        {
            return;
        }
        if (index < input_size)
        {
            const float angle = 2.0 * detail::kPi * cut_value * (static_cast<float>(index) / fs);
            const float2 phase = make_complex(cos(angle), sin(angle));
            const float2 value = complex_mul(input[index], phase);
            output[index].x = value.x;
            output[index].y = value.y;
        }
        else
        {
            output[index].x = 0.0;
            output[index].y = 0.0;
        }
    }

    __global__ void extract_cut_kernel(
        const cufftComplex *input,
        int size,
        bool use_ifftshift,
        float scale,
        float *output)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= static_cast<std::size_t>(size))
        {
            return;
        }
        const std::size_t shift = use_ifftshift
                                      ? static_cast<std::size_t>(size / 2)
                                      : static_cast<std::size_t>((size + 1) / 2);
        const std::size_t source = (index + shift) % static_cast<std::size_t>(size);
        const cufftComplex value = input[source];
        output[index] = std::sqrt(value.x * value.x + value.y * value.y) * scale;
    }

    __global__ void conjugate_matrix_kernel(cufftComplex *values, std::size_t size)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            values[index].y = -values[index].y;
        }
    }

    __global__ void cfar_1d_kernel(
        const float *array,
        std::size_t size,
        int guard_cells,
        int reference_cells,
        float alpha,
        float *threshold,
        float *detections)
    {
        const std::size_t valid = size - static_cast<std::size_t>(2 * (guard_cells + reference_cells));
        const std::size_t offset =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (offset >= valid)
        {
            return;
        }
        const std::size_t index = offset + static_cast<std::size_t>(guard_cells + reference_cells);
        float reference_sum = 0.0;
        for (int delta = -reference_cells - guard_cells; delta <= reference_cells + guard_cells; ++delta)
        {
            if (std::abs(delta) <= guard_cells)
            {
                continue;
            }
            reference_sum += array[index + static_cast<std::ptrdiff_t>(delta)];
        }
        const float t = alpha * reference_sum / static_cast<float>(2 * reference_cells);
        threshold[index] = t;
        detections[index] = array[index] - t > 0.0 ? 1.0 : 0.0;
    }

    __global__ void cfar_pack_fft_inputs_kernel(
        const float *array,
        std::size_t size,
        int guard_cells,
        int reference_cells,
        int nfft,
        cufftComplex *signal,
        cufftComplex *kernel)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= nfft)
        {
            return;
        }
        signal[index] = index < static_cast<int>(size)
                            ? make_cuFloatComplex(array[index], 0.0f)
                            : make_cuFloatComplex(0.0f, 0.0f);

        const int center = guard_cells + reference_cells;
        const int width = 2 * center + 1;
        float tap = 0.0f;
        if (index < width)
        {
            const int delta = index - center;
            tap = std::abs(delta) > guard_cells ? 1.0f : 0.0f;
        }
        kernel[index] = make_cuFloatComplex(tap, 0.0f);
    }

    __global__ void multiply_fft_kernel(
        cufftComplex *lhs,
        const cufftComplex *rhs,
        int size)
    {
        const int index = static_cast<int>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const cufftComplex a = lhs[index];
        const cufftComplex b = rhs[index];
        lhs[index] = make_cuFloatComplex(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
    }

    __global__ void cfar_1d_fft_threshold_kernel(
        const float *array,
        const cufftComplex *convolution,
        std::size_t size,
        int guard_cells,
        int reference_cells,
        float alpha,
        float scale,
        float *threshold,
        float *detections)
    {
        const std::size_t center = static_cast<std::size_t>(guard_cells + reference_cells);
        const std::size_t valid = size - 2 * center;
        const std::size_t offset =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (offset >= valid)
        {
            return;
        }
        const std::size_t index = offset + center;
        const float reference_sum = convolution[index + center].x * scale;
        const float t = alpha * reference_sum / static_cast<float>(2 * reference_cells);
        threshold[index] = t;
        detections[index] = array[index] - t > 0.0f ? 1.0f : 0.0f;
    }

    __global__ void cfar_2d_kernel(
        const float *array,
        std::size_t rows,
        std::size_t cols,
        int gcx,
        int gcy,
        int rcx,
        int rcy,
        float alpha,
        int cells,
        float *threshold,
        float *detections)
    {
        const std::size_t valid_rows = rows - static_cast<std::size_t>(2 * (gcx + rcx));
        const std::size_t valid_cols = cols - static_cast<std::size_t>(2 * (gcy + rcy));
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = valid_rows * valid_cols;
        if (flat >= total)
        {
            return;
        }
        const std::size_t local_row = flat / valid_cols;
        const std::size_t local_col = flat % valid_cols;
        const std::size_t row = local_row + static_cast<std::size_t>(gcx + rcx);
        const std::size_t col = local_col + static_cast<std::size_t>(gcy + rcy);
        float reference_sum = 0.0;
        for (int dr = -rcx - gcx; dr <= rcx + gcx; ++dr)
        {
            for (int dc = -rcy - gcy; dc <= rcy + gcy; ++dc)
            {
                if (std::abs(dr) <= gcx && std::abs(dc) <= gcy)
                {
                    continue;
                }
                const std::size_t rr = row + static_cast<std::ptrdiff_t>(dr);
                const std::size_t cc = col + static_cast<std::ptrdiff_t>(dc);
                reference_sum += array[rr * cols + cc];
            }
        }
        const float t = alpha * reference_sum / static_cast<float>(cells);
        const std::size_t index = row * cols + col;
        threshold[index] = t;
        detections[index] = array[index] - t > 0.0 ? 1.0 : 0.0;
    }

    __global__ void cfar_2d_row_prefix_kernel(
        const float *array,
        std::size_t rows,
        std::size_t cols,
        float *row_prefix)
    {
        const std::size_t row = static_cast<std::size_t>(blockIdx.x);
        if (row >= rows || threadIdx.x != 0)
        {
            return;
        }
        const std::size_t stride = cols + 1;
        float running = 0.0f;
        row_prefix[row * stride] = 0.0f;
        for (std::size_t col = 0; col < cols; ++col)
        {
            running += array[row * cols + col];
            row_prefix[row * stride + col + 1] = running;
        }
    }

    __global__ void cfar_2d_integral_column_kernel(
        const float *row_prefix,
        std::size_t rows,
        std::size_t cols,
        float *integral)
    {
        const std::size_t col =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (col > cols)
        {
            return;
        }
        const std::size_t stride = cols + 1;
        float running = 0.0f;
        integral[col] = 0.0f;
        for (std::size_t row = 0; row < rows; ++row)
        {
            running += row_prefix[row * stride + col];
            integral[(row + 1) * stride + col] = running;
        }
    }

    __device__ float cfar_integral_rect_sum(
        const float *integral,
        std::size_t stride,
        int top,
        int left,
        int bottom,
        int right)
    {
        const std::size_t t = static_cast<std::size_t>(top);
        const std::size_t l = static_cast<std::size_t>(left);
        const std::size_t b = static_cast<std::size_t>(bottom);
        const std::size_t r = static_cast<std::size_t>(right);
        return integral[b * stride + r] - integral[t * stride + r] -
               integral[b * stride + l] + integral[t * stride + l];
    }

    __global__ void cfar_2d_integral_threshold_kernel(
        const float *array,
        const float *integral,
        std::size_t rows,
        std::size_t cols,
        int gcx,
        int gcy,
        int rcx,
        int rcy,
        float alpha,
        int cells,
        float *threshold,
        float *detections)
    {
        const std::size_t valid_rows = rows - static_cast<std::size_t>(2 * (gcx + rcx));
        const std::size_t valid_cols = cols - static_cast<std::size_t>(2 * (gcy + rcy));
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = valid_rows * valid_cols;
        if (flat >= total)
        {
            return;
        }
        const std::size_t local_row = flat / valid_cols;
        const std::size_t local_col = flat % valid_cols;
        const int row = static_cast<int>(local_row) + gcx + rcx;
        const int col = static_cast<int>(local_col) + gcy + rcy;
        const std::size_t stride = cols + 1;
        const float outer = cfar_integral_rect_sum(
            integral,
            stride,
            row - gcx - rcx,
            col - gcy - rcy,
            row + gcx + rcx + 1,
            col + gcy + rcy + 1);
        const float inner = cfar_integral_rect_sum(
            integral,
            stride,
            row - gcx,
            col - gcy,
            row + gcx + 1,
            col + gcy + 1);
        const float t = alpha * (outer - inner) / static_cast<float>(cells);
        const std::size_t index = static_cast<std::size_t>(row) * cols + static_cast<std::size_t>(col);
        threshold[index] = t;
        detections[index] = array[index] - t > 0.0f ? 1.0f : 0.0f;
    }

    __global__ void row_mean_kernel(
        const float2 *input,
        std::size_t sensors,
        std::size_t snapshots,
        cuComplex *means)
    {
        const std::size_t row =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (row >= sensors)
        {
            return;
        }
        float2 accum = make_complex(0.0, 0.0);
        const std::size_t base = row * snapshots;
        for (std::size_t col = 0; col < snapshots; ++col)
        {
            const float2 value = input[base + col];
            accum.x += value.x;
            accum.y += value.y;
        }
        const float scale = 1.0 / static_cast<float>(snapshots);
        means[row] = make_cuComplex(accum.x * scale, accum.y * scale);
    }

    __global__ void center_matrix_kernel(
        const float2 *input,
        const cuComplex *means,
        std::size_t sensors,
        std::size_t snapshots,
        cuComplex *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = sensors * snapshots;
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / snapshots;
        const float2 value = input[flat];
        const cuComplex mean = means[row];
        output[flat] = make_cuComplex(value.x - cuCrealf(mean), value.y - cuCimagf(mean));
    }

    __global__ void transpose_square_to_column_major_kernel(
        const float2 *input,
        int size,
        cuComplex *output)
    {
        const std::size_t flat =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        const std::size_t total = static_cast<std::size_t>(size) * static_cast<std::size_t>(size);
        if (flat >= total)
        {
            return;
        }
        const std::size_t row = flat / static_cast<std::size_t>(size);
        const std::size_t col = flat % static_cast<std::size_t>(size);
        const float2 value = input[row * static_cast<std::size_t>(size) + col];
        output[col * static_cast<std::size_t>(size) + row] = make_cuComplex(value.x, value.y);
    }

    __global__ void copy_vector_to_cucomplex_kernel(
        const float2 *input,
        std::size_t size,
        cuComplex *output)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index < size)
        {
            output[index] = make_cuComplex(input[index].x, input[index].y);
        }
    }

    __global__ void scale_solution_kernel(
        const cuComplex *input,
        std::size_t size,
        cuComplex denom,
        float2 *output)
    {
        const std::size_t index =
            static_cast<std::size_t>(blockIdx.x) * blockDim.x + threadIdx.x;
        if (index >= size)
        {
            return;
        }
        const cuComplex value = cuCdivf(input[index], denom);
        output[index] = make_complex(cuCrealf(value), cuCimagf(value));
    }

    const ZxGpuRealSignal resolve_window_signal(
        ZxGpuWindowSpec window,
        int size)
    {
        if (detail::window_disabled(window))
        {
            return {};
        }
        return cusignal::zx_gpu_backend::windows::get_window(std::move(window), size, false);
    }
} // namespace

namespace cusignal
{
    namespace zx_gpu_backend
    {
        namespace radartools
        {

            core::ZxGpuComplexArray fftshift_rows(const core::ComplexArrayLike &input)
            {
                const ZxGpuComplexArray &device =
                    core::as_device_array(input, g_workspace.task_pipeline.complex_storage);
                detail::ensure_rank(device, 2, "input");
                core::ZxGpuComplexArray output(device.shape(), false);
                if (device.empty())
                    return output;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    fftshift_rows_kernel<<<block_count(device.size()), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(device.data()),
                        reinterpret_cast<float2 *>(output.data()),
                        device.shape()[0],
                        device.shape()[1]);
                    check_kernel_launch("fftshift_rows_kernel");
                });
                return output;
            }

            core::ZxGpuRealArray power_map(const core::ComplexArrayLike &input)
            {
                const ZxGpuComplexArray &device =
                    core::as_device_array(input, g_workspace.task_pipeline.complex_storage);
                core::ZxGpuRealArray output(device.shape(), false);
                if (device.empty())
                    return output;
                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    power_map_kernel<<<block_count(device.size()), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(device.data()), output.data(), device.size());
                    check_kernel_launch("power_map_kernel");
                });
                return output;
            }

            radartools_api::DetectionSummary detect_peak(
                const core::RealArrayLike &power,
                const core::RealArrayLike &detections,
                int nfft,
                float prf)
            {
                const ZxGpuRealArray &power_device =
                    core::as_device_array(power, g_workspace.task_pipeline.power_storage);
                const ZxGpuRealArray &detections_device =
                    core::as_device_array(detections, g_workspace.task_pipeline.detections_storage);
                detail::ensure_rank(power_device, 2, "power");
                if (detections_device.shape() != power_device.shape())
                    throw std::invalid_argument("power and detections shape mismatch");
                if (nfft <= 0 || !(prf > 0.0f))
                    throw std::invalid_argument("nfft and prf must be positive");

                g_workspace.task_pipeline.detection_result.reserve(1);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = events.measure([&]() {
                    detect_peak_kernel<<<1, 1>>>(
                        power_device.data(), detections_device.data(), power_device.shape()[0],
                        power_device.shape()[1], nfft, prf, g_workspace.task_pipeline.detection_result.get());
                    check_kernel_launch("detect_peak_kernel");
                });
                radartools_api::DetectionSummary result;
                throw_on_zx_gpu_error(
                    cudaMemcpy(&result, g_workspace.task_pipeline.detection_result.get(), sizeof(result), cudaMemcpyDeviceToHost),
                    "cudaMemcpy(detect_peak D2H)");
                return result;
            }

            core::ZxGpuComplexArray pulse_compression(
                const core::ComplexArrayLike &x,
                const core::ComplexSignalLike &templ,
                bool normalize,
                core::ZxGpuWindowSpec window,
                int nfft)
            {
                const ZxGpuComplexArray &x_device = core::as_device_array(x, g_workspace.pulse.x_storage);
                const ZxGpuComplexSignal &templ_device = core::as_device_signal(templ, g_workspace.pulse.templ_storage);
                detail::ensure_rank(x_device, 2, "x");
                if (templ_device.empty())
                {
                    throw std::invalid_argument("templ must not be empty");
                }

                const std::size_t num_pulses = x_device.shape()[0];
                const std::size_t samples = x_device.shape()[1];
                const int resolved_nfft = nfft > 0 ? nfft : static_cast<int>(samples);
                ZxGpuComplexArray output(core::Shape{num_pulses, static_cast<std::size_t>(resolved_nfft)}, false);
                const ZxGpuRealSignal window_signal = resolve_window_signal(std::move(window), static_cast<int>(templ_device.size()));
                const bool use_window = !window_signal.empty();

                g_workspace.beamformer.ensure_handles();
                g_workspace.pulse.template_fft.reserve(static_cast<std::size_t>(resolved_nfft));

                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    pack_template_kernel<<<block_count(static_cast<std::size_t>(resolved_nfft)), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(templ_device.data()),
                        use_window ? window_signal.data() : nullptr,
                        templ_device.size(),
                        use_window,
                        g_workspace.pulse.template_fft.get(),
                        resolved_nfft);
                    check_kernel_launch("pack_template_kernel");

                    if (normalize)
                    {
                        float norm = 0.0;
                        throw_on_cublas_error(
                            cublasScnrm2(
                                g_workspace.beamformer.cublas,
                                resolved_nfft,
                                reinterpret_cast<const cuComplex *>(g_workspace.pulse.template_fft.get()),
                                1,
                                &norm),
                            "cublasScnrm2(template)");
                        if (!(norm > 0.0))
                        {
                            throw std::invalid_argument("template norm must be > 0");
                        }
                        scale_complex_kernel<<<block_count(static_cast<std::size_t>(resolved_nfft)), kThreadsPerBlock>>>(
                            reinterpret_cast<float2 *>(g_workspace.pulse.template_fft.get()),
                            static_cast<std::size_t>(resolved_nfft),
                            1.0 / norm);
                        check_kernel_launch("scale_complex_kernel(template)");
                    }

                    g_workspace.pulse.plan.ensure(resolved_nfft, 1);
                    throw_on_cufft_error(
                        cufftExecC2C(
                            g_workspace.pulse.plan.handle,
                            g_workspace.pulse.template_fft.get(),
                            g_workspace.pulse.template_fft.get(),
                            CUFFT_FORWARD),
                        "cufftExecC2C(template forward)");

                    pack_pulse_rows_kernel<<<block_count(num_pulses * static_cast<std::size_t>(resolved_nfft)), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(x_device.data()),
                        num_pulses,
                        samples,
                        resolved_nfft,
                        reinterpret_cast<float2 *>(output.data()));
                    check_kernel_launch("pack_pulse_rows_kernel");

                    g_workspace.pulse.plan.ensure(resolved_nfft, static_cast<int>(num_pulses));
                    throw_on_cufft_error(
                        cufftExecC2C(
                            g_workspace.pulse.plan.handle,
                            reinterpret_cast<cufftComplex *>(output.data()),
                            reinterpret_cast<cufftComplex *>(output.data()),
                            CUFFT_FORWARD),
                        "cufftExecC2C(pulse forward)");

                    multiply_conj_template_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        reinterpret_cast<float2 *>(output.data()),
                        g_workspace.pulse.template_fft.get(),
                        output.size(),
                        resolved_nfft);
                    check_kernel_launch("multiply_conj_template_kernel");

                    throw_on_cufft_error(
                        cufftExecC2C(
                            g_workspace.pulse.plan.handle,
                            reinterpret_cast<cufftComplex *>(output.data()),
                            reinterpret_cast<cufftComplex *>(output.data()),
                            CUFFT_INVERSE),
                        "cufftExecC2C(pulse inverse)");

                    scale_complex_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        reinterpret_cast<float2 *>(output.data()),
                        output.size(),
                        1.0 / static_cast<float>(resolved_nfft));
                    check_kernel_launch("scale_complex_kernel(output)");
                }));

                return output;
            }

            core::ZxGpuComplexArray pulse_doppler(
                const core::ComplexArrayLike &x,
                core::ZxGpuWindowSpec window,
                int nfft)
            {
                const ZxGpuComplexArray &x_device = core::as_device_array(x, g_workspace.pulse.x_storage);
                detail::ensure_rank(x_device, 2, "x");
                const std::size_t pulses = x_device.shape()[0];
                const std::size_t samples = x_device.shape()[1];
                const int resolved_nfft = nfft > 0 ? nfft : static_cast<int>(pulses);
                const ZxGpuRealSignal window_signal = resolve_window_signal(std::move(window), static_cast<int>(pulses));
                const bool use_window = !window_signal.empty();

                ZxGpuComplexArray output = core::make_zx_gpu_complex_array(
                    core::Shape{static_cast<std::size_t>(resolved_nfft), samples});
                g_workspace.pulse.doppler_transposed.reserve(samples * static_cast<std::size_t>(resolved_nfft));

                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    if (static_cast<std::size_t>(resolved_nfft) > pulses)
                    {
                        g_workspace.pulse.doppler_transposed.zero(samples * static_cast<std::size_t>(resolved_nfft));
                    }
                    else
                    {
                        g_workspace.pulse.doppler_transposed.reserve(samples * static_cast<std::size_t>(resolved_nfft));
                    }
                    const std::size_t packed_rows =
                        std::min(pulses, static_cast<std::size_t>(resolved_nfft));
                    pack_pulse_doppler_kernel<<<block_count(packed_rows * samples), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(x_device.data()),
                        pulses,
                        samples,
                        resolved_nfft,
                        use_window ? window_signal.data() : nullptr,
                        use_window,
                        g_workspace.pulse.doppler_transposed.get());
                    check_kernel_launch("pack_pulse_doppler_kernel");

                    g_workspace.pulse.plan.ensure(resolved_nfft, static_cast<int>(samples));
                    throw_on_cufft_error(
                        cufftExecC2C(
                            g_workspace.pulse.plan.handle,
                            g_workspace.pulse.doppler_transposed.get(),
                            g_workspace.pulse.doppler_transposed.get(),
                            CUFFT_FORWARD),
                        "cufftExecC2C(pulse_doppler forward)");

                    transpose_doppler_output_kernel<<<block_count(output.size()), kThreadsPerBlock>>>(
                        g_workspace.pulse.doppler_transposed.get(),
                        samples,
                        resolved_nfft,
                        reinterpret_cast<float2 *>(output.data()));
                    check_kernel_launch("transpose_doppler_output_kernel");
                }));

                return output;
            }

            radartools_api::ZxGpuAmbgfunResult ambgfun(
                const core::ComplexSignalLike &x,
                float fs,
                float prf,
                const std::string &cut,
                float cut_value)
            {
                return ambgfun(x, x, fs, prf, cut, cut_value);
            }

            radartools_api::ZxGpuAmbgfunResult ambgfun(
                const core::ComplexSignalLike &x,
                const core::ComplexSignalLike &y,
                float fs,
                float prf,
                const std::string &cut,
                float cut_value)
            {
                detail::ensure_positive(fs, "fs");
                detail::ensure_positive(prf, "prf");
                const std::string normalized_cut = detail::normalize_cut(cut);
                const ZxGpuComplexSignal &x_device = core::as_device_signal(x, g_workspace.ambgfun.x_storage);
                const ZxGpuComplexSignal &y_device = core::as_device_signal(y, g_workspace.ambgfun.y_storage);
                if (x_device.empty() || y_device.empty())
                {
                    throw std::invalid_argument("ambgfun inputs must not be empty");
                }

                g_workspace.beamformer.ensure_handles();
                const std::size_t xlen = x_device.size();
                const std::size_t ylen = y_device.size();
                const int len_seq = static_cast<int>(xlen + ylen);
                const int nfreq = detail::next_power_of_two(len_seq - 1);

                g_workspace.ambgfun.x_buffer.reserve(std::max<std::size_t>(static_cast<std::size_t>(nfreq), xlen + ylen - 1));
                g_workspace.ambgfun.y_buffer.reserve(std::max<std::size_t>(static_cast<std::size_t>(nfreq), xlen + ylen - 1));

                const bool cacheable_device_inputs =
                    std::holds_alternative<ZxGpuComplexSignal>(x) &&
                    std::holds_alternative<ZxGpuComplexSignal>(y);
                const bool normalized_cache_hit =
                    cacheable_device_inputs &&
                    g_workspace.ambgfun.normalized_cache_valid &&
                    g_workspace.ambgfun.normalized_x_ptr == x_device.data() &&
                    g_workspace.ambgfun.normalized_y_ptr == y_device.data() &&
                    g_workspace.ambgfun.normalized_x_size == xlen &&
                    g_workspace.ambgfun.normalized_y_size == ylen;
                if (!normalized_cache_hit)
                {
                    float x_norm = 0.0;
                    float y_norm = 0.0;
                    throw_on_cublas_error(
                        cublasScnrm2(
                            g_workspace.beamformer.cublas,
                            static_cast<int>(xlen),
                            reinterpret_cast<const cuComplex *>(x_device.data()),
                            1,
                            &x_norm),
                        "cublasScnrm2(x)");
                    throw_on_cublas_error(
                        cublasScnrm2(
                            g_workspace.beamformer.cublas,
                            static_cast<int>(ylen),
                            reinterpret_cast<const cuComplex *>(y_device.data()),
                            1,
                            &y_norm),
                        "cublasScnrm2(y)");
                    if (!(x_norm > 0.0) || !(y_norm > 0.0))
                    {
                        throw std::invalid_argument("ambgfun inputs must have non-zero norm");
                    }

                    copy_scale_complex_kernel<<<block_count(xlen), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(x_device.data()),
                        reinterpret_cast<float2 *>(g_workspace.ambgfun.x_buffer.get()),
                        xlen,
                        1.0 / x_norm);
                    check_kernel_launch("copy_scale_complex_kernel(x)");
                    copy_scale_complex_kernel<<<block_count(ylen), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(y_device.data()),
                        reinterpret_cast<float2 *>(g_workspace.ambgfun.y_buffer.get()),
                        ylen,
                        1.0 / y_norm);
                    check_kernel_launch("copy_scale_complex_kernel(y)");

                    g_workspace.ambgfun.normalized_x_ptr = cacheable_device_inputs ? x_device.data() : nullptr;
                    g_workspace.ambgfun.normalized_y_ptr = cacheable_device_inputs ? y_device.data() : nullptr;
                    g_workspace.ambgfun.normalized_x_size = xlen;
                    g_workspace.ambgfun.normalized_y_size = ylen;
                    g_workspace.ambgfun.normalized_cache_valid = cacheable_device_inputs;
                }

                if (normalized_cut == "2d")
                {
                    const std::size_t rows = xlen + ylen - 1;
                    ZxGpuRealArray output(core::Shape{rows, static_cast<std::size_t>(nfreq)}, false);
                    ZxGpuRealSignal delay_axis(rows, false);
                    ZxGpuRealSignal doppler_axis(static_cast<std::size_t>(nfreq), false);
                    constexpr std::size_t kMinTileComplexElements = 8 * 1024 * 1024;
                    constexpr std::size_t kMaxTileComplexElements = 64 * 1024 * 1024;
                    std::size_t free_bytes = 0;
                    std::size_t total_bytes = 0;
                    throw_on_zx_gpu_error(cudaMemGetInfo(&free_bytes, &total_bytes), "cudaMemGetInfo(ambgfun)");
                    const std::size_t memory_budget_elements =
                        free_bytes / (sizeof(cufftComplex) * 8);
                    const std::size_t adaptive_tile_complex_elements =
                        std::max<std::size_t>(
                            kMinTileComplexElements,
                            std::min<std::size_t>(
                                kMaxTileComplexElements,
                                memory_budget_elements));
                    const std::size_t tile_rows = std::max<std::size_t>(
                        1,
                        std::min<std::size_t>(
                            rows,
                            adaptive_tile_complex_elements /
                                std::max<std::size_t>(1, static_cast<std::size_t>(nfreq))));
                    g_workspace.ambgfun.matrix_buffer.reserve(tile_rows * static_cast<std::size_t>(nfreq));

                    ScopedZxGpuEvents events;
                    g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                        g_workspace.ambgfun.plan.ensure(nfreq, static_cast<int>(tile_rows));
                        for (std::size_t row_offset = 0; row_offset < rows; row_offset += tile_rows)
                        {
                            const std::size_t current_rows = std::min(tile_rows, rows - row_offset);
                            const std::size_t current_elements = current_rows * static_cast<std::size_t>(nfreq);
                            build_shifted_matrix_tile_kernel<<<block_count(current_elements), kThreadsPerBlock>>>(
                                reinterpret_cast<const float2 *>(g_workspace.ambgfun.x_buffer.get()),
                                reinterpret_cast<const float2 *>(g_workspace.ambgfun.y_buffer.get()),
                                xlen,
                                ylen,
                                row_offset,
                                current_rows,
                                nfreq,
                                g_workspace.ambgfun.matrix_buffer.get());
                            check_kernel_launch("build_shifted_matrix_tile_kernel");

                            throw_on_cufft_error(
                                cufftExecC2C(
                                    g_workspace.ambgfun.plan.handle,
                                    g_workspace.ambgfun.matrix_buffer.get(),
                                    g_workspace.ambgfun.matrix_buffer.get(),
                                    CUFFT_INVERSE),
                                "cufftExecC2C(ambgfun 2d tile)");

                            extract_surface_tile_kernel<<<block_count(current_elements), kThreadsPerBlock>>>(
                                g_workspace.ambgfun.matrix_buffer.get(),
                                row_offset,
                                current_rows,
                                nfreq,
                                output.data());
                            check_kernel_launch("extract_surface_tile_kernel");
                        }

                        build_delay_axis_kernel<<<block_count(delay_axis.size()), kThreadsPerBlock>>>(
                            delay_axis.data(), xlen, ylen, fs);
                        check_kernel_launch("build_delay_axis_kernel");
                        build_doppler_axis_kernel<<<block_count(doppler_axis.size()), kThreadsPerBlock>>>(
                            doppler_axis.data(), nfreq, fs);
                        check_kernel_launch("build_doppler_axis_kernel");
                    }));

                    radartools_api::ZxGpuAmbgfunSurfaceResult result;
                    result.values = std::move(output);
                    result.delay_axis = std::move(delay_axis);
                    result.doppler_axis = std::move(doppler_axis);
                    return result;
                }

                if (normalized_cut == "delay")
                {
                    ZxGpuRealSignal values = core::make_zx_gpu_real_signal(static_cast<std::size_t>(nfreq));
                    ZxGpuRealSignal axis = core::make_zx_gpu_real_signal(static_cast<std::size_t>(nfreq));

                    ScopedZxGpuEvents events;
                    g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                        pack_signal_kernel<<<block_count(static_cast<std::size_t>(nfreq)), kThreadsPerBlock>>>(
                            reinterpret_cast<const float2 *>(g_workspace.ambgfun.x_buffer.get()),
                            xlen,
                            g_workspace.ambgfun.x_buffer.get(),
                            nfreq);
                        check_kernel_launch("pack_signal_kernel(x)");
                        pack_signal_kernel<<<block_count(static_cast<std::size_t>(nfreq)), kThreadsPerBlock>>>(
                            reinterpret_cast<const float2 *>(g_workspace.ambgfun.y_buffer.get()),
                            ylen,
                            g_workspace.ambgfun.y_buffer.get(),
                            nfreq);
                        check_kernel_launch("pack_signal_kernel(y)");

                        g_workspace.ambgfun.plan.ensure(nfreq, 1);
                        throw_on_cufft_error(
                            cufftExecC2C(
                                g_workspace.ambgfun.plan.handle,
                                g_workspace.ambgfun.x_buffer.get(),
                                g_workspace.ambgfun.x_buffer.get(),
                                CUFFT_FORWARD),
                            "cufftExecC2C(delay forward)");
                        apply_frequency_phase_kernel<<<block_count(static_cast<std::size_t>(nfreq)), kThreadsPerBlock>>>(
                            g_workspace.ambgfun.x_buffer.get(), nfreq, fs, cut_value);
                        check_kernel_launch("apply_frequency_phase_kernel");
                        throw_on_cufft_error(
                            cufftExecC2C(
                                g_workspace.ambgfun.plan.handle,
                                g_workspace.ambgfun.x_buffer.get(),
                                g_workspace.ambgfun.x_buffer.get(),
                                CUFFT_INVERSE),
                            "cufftExecC2C(delay inverse shift)");
                        scale_complex_kernel<<<block_count(static_cast<std::size_t>(nfreq)), kThreadsPerBlock>>>(
                            reinterpret_cast<float2 *>(g_workspace.ambgfun.x_buffer.get()),
                            static_cast<std::size_t>(nfreq),
                            1.0 / static_cast<float>(nfreq));
                        check_kernel_launch("scale_complex_kernel(delay shift)");

                        multiply_with_conj_kernel<<<block_count(static_cast<std::size_t>(nfreq)), kThreadsPerBlock>>>(
                            g_workspace.ambgfun.y_buffer.get(),
                            g_workspace.ambgfun.x_buffer.get(),
                            g_workspace.ambgfun.y_buffer.get(),
                            static_cast<std::size_t>(nfreq));
                        check_kernel_launch("multiply_with_conj_kernel(delay)");
                        throw_on_cufft_error(
                            cufftExecC2C(
                                g_workspace.ambgfun.plan.handle,
                                g_workspace.ambgfun.y_buffer.get(),
                                g_workspace.ambgfun.y_buffer.get(),
                                CUFFT_INVERSE),
                            "cufftExecC2C(delay final inverse)");

                        extract_cut_kernel<<<block_count(static_cast<std::size_t>(nfreq)), kThreadsPerBlock>>>(
                            g_workspace.ambgfun.y_buffer.get(),
                            nfreq,
                            true,
                            1.0,
                            values.data());
                        check_kernel_launch("extract_cut_kernel(delay)");
                        build_doppler_axis_kernel<<<block_count(axis.size()), kThreadsPerBlock>>>(
                            axis.data(), nfreq, fs);
                        check_kernel_launch("build_doppler_axis_kernel(delay)");
                    }));

                    radartools_api::ZxGpuAmbgfunCutResult result;
                    result.values = std::move(values);
                    result.axis = std::move(axis);
                    return result;
                }

                const int out_size = static_cast<int>(xlen + ylen - 1);
                ZxGpuRealSignal values = core::make_zx_gpu_real_signal(static_cast<std::size_t>(out_size));
                ZxGpuRealSignal axis = core::make_zx_gpu_real_signal(static_cast<std::size_t>(out_size));

                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    modulate_and_pack_kernel<<<block_count(static_cast<std::size_t>(out_size)), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(g_workspace.ambgfun.x_buffer.get()),
                        xlen,
                        fs,
                        cut_value,
                        g_workspace.ambgfun.x_buffer.get(),
                        out_size);
                    check_kernel_launch("modulate_and_pack_kernel");
                    pack_signal_kernel<<<block_count(static_cast<std::size_t>(out_size)), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(g_workspace.ambgfun.y_buffer.get()),
                        ylen,
                        g_workspace.ambgfun.y_buffer.get(),
                        out_size);
                    check_kernel_launch("pack_signal_kernel(doppler)");

                    g_workspace.ambgfun.plan.ensure(out_size, 1);
                    throw_on_cufft_error(
                        cufftExecC2C(
                            g_workspace.ambgfun.plan.handle,
                            g_workspace.ambgfun.x_buffer.get(),
                            g_workspace.ambgfun.x_buffer.get(),
                            CUFFT_FORWARD),
                        "cufftExecC2C(doppler x)");
                    throw_on_cufft_error(
                        cufftExecC2C(
                            g_workspace.ambgfun.plan.handle,
                            g_workspace.ambgfun.y_buffer.get(),
                            g_workspace.ambgfun.y_buffer.get(),
                            CUFFT_FORWARD),
                        "cufftExecC2C(doppler y)");
                    multiply_with_conj_kernel<<<block_count(static_cast<std::size_t>(out_size)), kThreadsPerBlock>>>(
                        g_workspace.ambgfun.y_buffer.get(),
                        g_workspace.ambgfun.x_buffer.get(),
                        g_workspace.ambgfun.y_buffer.get(),
                        static_cast<std::size_t>(out_size));
                    check_kernel_launch("multiply_with_conj_kernel(doppler)");
                    throw_on_cufft_error(
                        cufftExecC2C(
                            g_workspace.ambgfun.plan.handle,
                            g_workspace.ambgfun.y_buffer.get(),
                            g_workspace.ambgfun.y_buffer.get(),
                            CUFFT_INVERSE),
                        "cufftExecC2C(doppler inverse)");
                    extract_cut_kernel<<<block_count(static_cast<std::size_t>(out_size)), kThreadsPerBlock>>>(
                        g_workspace.ambgfun.y_buffer.get(),
                        out_size,
                        false,
                        1.0 / static_cast<float>(out_size),
                        values.data());
                    check_kernel_launch("extract_cut_kernel(doppler)");
                    build_delay_axis_kernel<<<block_count(axis.size()), kThreadsPerBlock>>>(
                        axis.data(), xlen, ylen, fs);
                    check_kernel_launch("build_delay_axis_kernel(doppler)");
                }));

                radartools_api::ZxGpuAmbgfunCutResult result;
                result.values = std::move(values);
                result.axis = std::move(axis);
                return result;
            }

            float cfar_alpha(float pfa, int cells)
            {
                detail::ensure_probability(pfa);
                if (cells <= 0)
                {
                    throw std::invalid_argument("cells must be > 0");
                }
                return static_cast<float>(cells) * (std::pow(pfa, -1.0f / static_cast<float>(cells)) - 1.0f);
            }

            radartools_api::ZxGpuCfarResult ca_cfar(
                const core::RealArrayLike &array,
                int guard_cells,
                int reference_cells,
                float pfa)
            {
                const ZxGpuRealArray &array_device = core::as_device_array(array, g_workspace.cfar.array_storage);
                detail::ensure_rank(array_device, 1, "array");
                if (guard_cells < 0 || reference_cells < 1)
                {
                    throw std::invalid_argument("guard_cells/reference_cells are invalid");
                }
                const std::size_t size = array_device.shape()[0];
                if (size <= static_cast<std::size_t>(2 * (guard_cells + reference_cells)))
                {
                    throw std::invalid_argument("Array too small for given parameters");
                }
                const float alpha = cfar_alpha(pfa, 2 * reference_cells);
                radartools_api::ZxGpuCfarResult result;
                result.threshold = core::make_zx_gpu_real_array_like(array_device);
                result.detections = core::make_zx_gpu_real_array_like(array_device);
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    const int window_width = 2 * (guard_cells + reference_cells) + 1;
                    if (window_width >= kCfarFftWindowThreshold &&
                        size >= static_cast<std::size_t>(kCfarFftMinSize))
                    {
                        const int nfft = detail::next_power_of_two(
                            static_cast<int>(size) + window_width - 1);
                        g_workspace.cfar.fft_signal.reserve(static_cast<std::size_t>(nfft));
                        g_workspace.cfar.fft_kernel.reserve(static_cast<std::size_t>(nfft));
                        g_workspace.cfar.fft_plan.ensure(nfft, 1);
                        cfar_pack_fft_inputs_kernel<<<block_count(static_cast<std::size_t>(nfft)), kThreadsPerBlock>>>(
                            array_device.data(),
                            size,
                            guard_cells,
                            reference_cells,
                            nfft,
                            g_workspace.cfar.fft_signal.get(),
                            g_workspace.cfar.fft_kernel.get());
                        check_kernel_launch("cfar_pack_fft_inputs_kernel");
                        throw_on_cufft_error(
                            cufftExecC2C(
                                g_workspace.cfar.fft_plan.handle,
                                g_workspace.cfar.fft_signal.get(),
                                g_workspace.cfar.fft_signal.get(),
                                CUFFT_FORWARD),
                            "cufftExecC2C(cfar signal forward)");
                        throw_on_cufft_error(
                            cufftExecC2C(
                                g_workspace.cfar.fft_plan.handle,
                                g_workspace.cfar.fft_kernel.get(),
                                g_workspace.cfar.fft_kernel.get(),
                                CUFFT_FORWARD),
                            "cufftExecC2C(cfar kernel forward)");
                        multiply_fft_kernel<<<block_count(static_cast<std::size_t>(nfft)), kThreadsPerBlock>>>(
                            g_workspace.cfar.fft_signal.get(),
                            g_workspace.cfar.fft_kernel.get(),
                            nfft);
                        check_kernel_launch("multiply_fft_kernel(cfar)");
                        throw_on_cufft_error(
                            cufftExecC2C(
                                g_workspace.cfar.fft_plan.handle,
                                g_workspace.cfar.fft_signal.get(),
                                g_workspace.cfar.fft_signal.get(),
                                CUFFT_INVERSE),
                            "cufftExecC2C(cfar inverse)");
                        cfar_1d_fft_threshold_kernel<<<
                            block_count(size - static_cast<std::size_t>(2 * (guard_cells + reference_cells))),
                            kThreadsPerBlock>>>(
                            array_device.data(),
                            g_workspace.cfar.fft_signal.get(),
                            size,
                            guard_cells,
                            reference_cells,
                            alpha,
                            1.0f / static_cast<float>(nfft),
                            result.threshold.data(),
                            result.detections.data());
                        check_kernel_launch("cfar_1d_fft_threshold_kernel");
                    }
                    else
                    {
                        cfar_1d_kernel<<<
                            block_count(size - static_cast<std::size_t>(2 * (guard_cells + reference_cells))),
                            kThreadsPerBlock>>>(
                            array_device.data(),
                            size,
                            guard_cells,
                            reference_cells,
                            alpha,
                            result.threshold.data(),
                            result.detections.data());
                        check_kernel_launch("cfar_1d_kernel");
                    }
                }));
                return result;
            }

            radartools_api::ZxGpuCfarResult ca_cfar(
                const core::RealArrayLike &array,
                const core::Shape &guard_cells,
                const core::Shape &reference_cells,
                float pfa)
            {
                const ZxGpuRealArray &array_device = core::as_device_array(array, g_workspace.cfar.array_storage);
                detail::ensure_rank(array_device, 2, "array");
                if (guard_cells.size() != 2 || reference_cells.size() != 2)
                {
                    throw std::invalid_argument("guard_cells/reference_cells must each have rank 2");
                }
                const int gcx = static_cast<int>(guard_cells[0]);
                const int gcy = static_cast<int>(guard_cells[1]);
                const int rcx = static_cast<int>(reference_cells[0]);
                const int rcy = static_cast<int>(reference_cells[1]);
                if (gcx < 0 || gcy < 0 || rcx < 1 || rcy < 1)
                {
                    throw std::invalid_argument("guard/reference cells are invalid");
                }
                const std::size_t rows = array_device.shape()[0];
                const std::size_t cols = array_device.shape()[1];
                if (rows <= static_cast<std::size_t>(2 * (gcx + rcx)))
                {
                    throw std::invalid_argument("Array first dimension too small for given parameters.");
                }
                if (cols <= static_cast<std::size_t>(2 * (gcy + rcy)))
                {
                    throw std::invalid_argument("Array second dimension too small for given parameters.");
                }
                const int cells = 2 * rcx * (2 * rcy + 2 * gcy + 1) +
                                  2 * (2 * gcx + 1) * rcy;
                const float alpha = cfar_alpha(pfa, cells);
                radartools_api::ZxGpuCfarResult result;
                result.threshold = core::make_zx_gpu_real_array_like(array_device);
                result.detections = core::make_zx_gpu_real_array_like(array_device);
                const std::size_t valid_rows = rows - static_cast<std::size_t>(2 * (gcx + rcx));
                const std::size_t valid_cols = cols - static_cast<std::size_t>(2 * (gcy + rcy));
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    const int footprint = (2 * (gcx + rcx) + 1) * (2 * (gcy + rcy) + 1);
                    if (footprint <= kCfarSmall2dFootprint)
                    {
                        cfar_2d_kernel<<<block_count(valid_rows * valid_cols), kThreadsPerBlock>>>(
                            array_device.data(),
                            rows,
                            cols,
                            gcx,
                            gcy,
                            rcx,
                            rcy,
                            alpha,
                            cells,
                            result.threshold.data(),
                            result.detections.data());
                        check_kernel_launch("cfar_2d_kernel");
                    }
                    else
                    {
                        const std::size_t stride = cols + 1;
                        g_workspace.cfar.row_prefix.reserve(rows * stride);
                        g_workspace.cfar.integral.reserve((rows + 1) * stride);
                        cfar_2d_row_prefix_kernel<<<static_cast<unsigned int>(rows), 1>>>(
                            array_device.data(),
                            rows,
                            cols,
                            g_workspace.cfar.row_prefix.get());
                        check_kernel_launch("cfar_2d_row_prefix_kernel");
                        cfar_2d_integral_column_kernel<<<block_count(stride), kThreadsPerBlock>>>(
                            g_workspace.cfar.row_prefix.get(),
                            rows,
                            cols,
                            g_workspace.cfar.integral.get());
                        check_kernel_launch("cfar_2d_integral_column_kernel");
                        cfar_2d_integral_threshold_kernel<<<block_count(valid_rows * valid_cols), kThreadsPerBlock>>>(
                            array_device.data(),
                            g_workspace.cfar.integral.get(),
                            rows,
                            cols,
                            gcx,
                            gcy,
                            rcx,
                            rcy,
                            alpha,
                            cells,
                            result.threshold.data(),
                            result.detections.data());
                        check_kernel_launch("cfar_2d_integral_threshold_kernel");
                    }
                }));
                return result;
            }

            core::ZxGpuComplexArray mvdr(
                const core::ComplexArrayLike &x,
                const core::ComplexArrayLike &sv,
                bool calc_cov)
            {
                const ZxGpuComplexArray &x_device = core::as_device_array(x, g_workspace.beamformer.x_storage);
                const ZxGpuComplexArray &sv_device = core::as_device_array(sv, g_workspace.beamformer.sv_storage);
                if (sv_device.empty())
                {
                    throw std::invalid_argument("sv must not be empty");
                }

                g_workspace.beamformer.ensure_handles();
                const int sensors = static_cast<int>(sv_device.size());
                if (calc_cov)
                {
                    detail::ensure_rank(x_device, 2, "x");
                    if (x_device.shape()[0] != static_cast<std::size_t>(sensors))
                    {
                        throw std::invalid_argument("Steering Vector and input data do not align");
                    }
                    if (x_device.shape()[0] > x_device.shape()[1])
                    {
                        throw std::invalid_argument(
                            "Matrix has more sensors than samples. Consider transposing and remember cuSignal is row-major, unlike MATLAB");
                    }
                    if (x_device.shape()[1] < 2)
                    {
                        throw std::invalid_argument("calc_cov requires at least two snapshots");
                    }
                }
                else
                {
                    detail::ensure_rank(x_device, 2, "x");
                    if (x_device.shape()[0] != x_device.shape()[1])
                    {
                        throw std::invalid_argument("x must be a square covariance matrix when calc_cov is false");
                    }
                    if (x_device.shape()[0] != static_cast<std::size_t>(sensors))
                    {
                        throw std::invalid_argument("Steering Vector and input data do not align");
                    }
                }

                ZxGpuComplexArray output = core::make_zx_gpu_complex_array(sv_device.shape());
                ScopedZxGpuEvents events;
                g_last_kernel_ms = static_cast<float>(events.measure([&]() {
                    if (calc_cov)
                    {
                        const std::size_t snapshots = x_device.shape()[1];
                        g_workspace.beamformer.means.reserve(static_cast<std::size_t>(sensors));
                        g_workspace.beamformer.centered.reserve(static_cast<std::size_t>(sensors) * snapshots);
                        row_mean_kernel<<<block_count(static_cast<std::size_t>(sensors)), kThreadsPerBlock>>>(
                            reinterpret_cast<const float2 *>(x_device.data()),
                            static_cast<std::size_t>(sensors),
                            snapshots,
                            g_workspace.beamformer.means.get());
                        check_kernel_launch("row_mean_kernel");
                        center_matrix_kernel<<<block_count(static_cast<std::size_t>(sensors) * snapshots), kThreadsPerBlock>>>(
                            reinterpret_cast<const float2 *>(x_device.data()),
                            g_workspace.beamformer.means.get(),
                            static_cast<std::size_t>(sensors),
                            snapshots,
                            g_workspace.beamformer.centered.get());
                        check_kernel_launch("center_matrix_kernel");

                        g_workspace.beamformer.covariance.reserve(static_cast<std::size_t>(sensors) * static_cast<std::size_t>(sensors));
                        const cuComplex alpha = make_cuComplex(
                            1.0 / static_cast<float>(static_cast<int>(snapshots) - 1),
                            0.0);
                        const cuComplex beta = make_cuComplex(0.0, 0.0);
                        throw_on_cublas_error(
                            cublasCgemm(
                                g_workspace.beamformer.cublas,
                                CUBLAS_OP_C,
                                CUBLAS_OP_N,
                                sensors,
                                sensors,
                                static_cast<int>(snapshots),
                                &alpha,
                                g_workspace.beamformer.centered.get(),
                                static_cast<int>(snapshots),
                                g_workspace.beamformer.centered.get(),
                                static_cast<int>(snapshots),
                                &beta,
                                g_workspace.beamformer.covariance.get(),
                                sensors),
                            "cublasCgemm(covariance)");
                        conjugate_matrix_kernel<<<block_count(static_cast<std::size_t>(sensors) * static_cast<std::size_t>(sensors)), kThreadsPerBlock>>>(
                            g_workspace.beamformer.covariance.get(),
                            static_cast<std::size_t>(sensors) * static_cast<std::size_t>(sensors));
                        check_kernel_launch("conjugate_matrix_kernel");
                    }
                    else
                    {
                        g_workspace.beamformer.covariance.reserve(static_cast<std::size_t>(sensors) * static_cast<std::size_t>(sensors));
                        transpose_square_to_column_major_kernel<<<block_count(static_cast<std::size_t>(sensors) * static_cast<std::size_t>(sensors)), kThreadsPerBlock>>>(
                            reinterpret_cast<const float2 *>(x_device.data()),
                            sensors,
                            g_workspace.beamformer.covariance.get());
                        check_kernel_launch("transpose_square_to_column_major_kernel");
                    }

                    g_workspace.beamformer.rhs.reserve(static_cast<std::size_t>(sensors));
                    copy_vector_to_cucomplex_kernel<<<block_count(static_cast<std::size_t>(sensors)), kThreadsPerBlock>>>(
                        reinterpret_cast<const float2 *>(sv_device.data()),
                        static_cast<std::size_t>(sensors),
                        g_workspace.beamformer.rhs.get());
                    check_kernel_launch("copy_vector_to_cucomplex_kernel");

                    int lwork = 0;
                    throw_on_cusolver_error(
                        cusolverDnCgetrf_bufferSize(
                            g_workspace.beamformer.cusolver,
                            sensors,
                            sensors,
                            g_workspace.beamformer.covariance.get(),
                            sensors,
                            &lwork),
                        "cusolverDnCgetrf_bufferSize");
                    g_workspace.beamformer.work.reserve(static_cast<std::size_t>(lwork));
                    g_workspace.beamformer.ipiv.reserve(static_cast<std::size_t>(sensors));
                    g_workspace.beamformer.info.reserve(1);
                    throw_on_cusolver_error(
                        cusolverDnCgetrf(
                            g_workspace.beamformer.cusolver,
                            sensors,
                            sensors,
                            g_workspace.beamformer.covariance.get(),
                            sensors,
                            g_workspace.beamformer.work.get(),
                            g_workspace.beamformer.ipiv.get(),
                            g_workspace.beamformer.info.get()),
                        "cusolverDnCgetrf");
                    int info = 0;
                    throw_on_zx_gpu_error(
                        cudaMemcpy(&info, g_workspace.beamformer.info.get(), sizeof(int), cudaMemcpyDeviceToHost),
                        "cudaMemcpy(info getrf)");
                    if (info != 0)
                    {
                        throw std::runtime_error("cusolverDnCgetrf failed with info=" + std::to_string(info));
                    }
                    throw_on_cusolver_error(
                        cusolverDnCgetrs(
                            g_workspace.beamformer.cusolver,
                            CUBLAS_OP_N,
                            sensors,
                            1,
                            g_workspace.beamformer.covariance.get(),
                            sensors,
                            g_workspace.beamformer.ipiv.get(),
                            g_workspace.beamformer.rhs.get(),
                            sensors,
                            g_workspace.beamformer.info.get()),
                        "cusolverDnCgetrs");
                    throw_on_zx_gpu_error(
                        cudaMemcpy(&info, g_workspace.beamformer.info.get(), sizeof(int), cudaMemcpyDeviceToHost),
                        "cudaMemcpy(info getrs)");
                    if (info != 0)
                    {
                        throw std::runtime_error("cusolverDnCgetrs failed with info=" + std::to_string(info));
                    }

                    cuComplex denom {};
                    throw_on_cublas_error(
                        cublasCdotc(
                            g_workspace.beamformer.cublas,
                            sensors,
                            reinterpret_cast<const cuComplex *>(sv_device.data()),
                            1,
                            g_workspace.beamformer.rhs.get(),
                            1,
                            &denom),
                        "cublasCdotc");
                    if (cuCrealf(denom) == 0.0 && cuCimagf(denom) == 0.0)
                    {
                        throw std::invalid_argument("mvdr denominator is zero");
                    }
                    scale_solution_kernel<<<block_count(static_cast<std::size_t>(sensors)), kThreadsPerBlock>>>(
                        g_workspace.beamformer.rhs.get(),
                        static_cast<std::size_t>(sensors),
                        denom,
                        reinterpret_cast<float2 *>(output.data()));
                    check_kernel_launch("scale_solution_kernel");
                }));

                return output;
            }

        } // namespace radartools

        namespace radartools_test_hooks
        {
            float consume_last_kernel_ms()
            {
                const float value = g_last_kernel_ms;
                g_last_kernel_ms = 0.0;
                return value;
            }
        } // namespace radartools_test_hooks
    } // namespace zx_gpu_backend
} // namespace cusignal
