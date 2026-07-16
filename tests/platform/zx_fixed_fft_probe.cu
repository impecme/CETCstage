#include <cuda_runtime.h>
#include <cufft.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
    constexpr int kThreadsPerBlock = 256;
    constexpr float kPi = 3.14159265358979323846f;

    struct Options
    {
        int fft_size = 0;
        int batch = 0;
        int warmup = 2;
        int repeat = 10;
        int profile_repeat = 200;
    };

    struct TimingStats
    {
        double median_ms = 0.0;
        double p95_ms = 0.0;
        double minimum_ms = 0.0;
    };

    struct ErrorStats
    {
        double max_abs = 0.0;
        double rmse = 0.0;
        double relative_rmse = 0.0;
    };

    void throw_on_cuda_error(cudaError_t status, const char *what)
    {
        if (status != cudaSuccess)
        {
            throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
        }
    }

    void throw_on_cufft_error(cufftResult status, const char *what)
    {
        if (status != CUFFT_SUCCESS)
        {
            throw std::runtime_error(
                std::string(what) + ": cufft status " + std::to_string(static_cast<int>(status)));
        }
    }

    int parse_positive_int(const char *text, const char *name)
    {
        char *end = nullptr;
        const long value = std::strtol(text, &end, 10);
        if (end == text || *end != '\0' || value <= 0 || value > 2147483647L)
        {
            throw std::invalid_argument(std::string(name) + " must be a positive integer");
        }
        return static_cast<int>(value);
    }

    bool is_power_of_two(int value)
    {
        return value > 0 && (value & (value - 1)) == 0;
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

    Options parse_options(int argc, char **argv)
    {
        if (argc < 3 || argc > 6)
        {
            throw std::invalid_argument(
                "usage: zx_fixed_fft_probe FFT_SIZE BATCH [WARMUP] [REPEAT] [PROFILE_REPEAT]");
        }
        Options options;
        options.fft_size = parse_positive_int(argv[1], "FFT_SIZE");
        options.batch = parse_positive_int(argv[2], "BATCH");
        if (argc >= 4)
        {
            options.warmup = parse_positive_int(argv[3], "WARMUP");
        }
        if (argc >= 5)
        {
            options.repeat = parse_positive_int(argv[4], "REPEAT");
        }
        if (argc >= 6)
        {
            options.profile_repeat = parse_positive_int(argv[5], "PROFILE_REPEAT");
        }
        if (!is_power_of_two(options.fft_size) || options.fft_size > 4096)
        {
            throw std::invalid_argument("FFT_SIZE must be a power of two not greater than 4096");
        }
        return options;
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

    __global__ void fixed_radix2_fft_kernel(
        const float2 *input,
        float2 *output,
        const float2 *twiddles,
        int fft_size,
        int log2_size,
        int inverse)
    {
        extern __shared__ float2 shared_values[];
        const int batch_index = static_cast<int>(blockIdx.x);
        const std::size_t offset =
            static_cast<std::size_t>(batch_index) * static_cast<std::size_t>(fft_size);

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

    template <typename Fn>
    double measure_once_ms(Fn &&fn)
    {
        throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize before timing");
        const auto start = std::chrono::steady_clock::now();
        fn();
        throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize after timing");
        const auto end = std::chrono::steady_clock::now();
        return std::chrono::duration<double, std::milli>(end - start).count();
    }

    template <typename Fn>
    TimingStats measure_repeated_ms(int warmup, int repeat, Fn &&fn)
    {
        for (int index = 0; index < warmup; ++index)
        {
            fn();
        }
        throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize after warmup");

        std::vector<double> samples;
        samples.reserve(static_cast<std::size_t>(repeat));
        for (int index = 0; index < repeat; ++index)
        {
            samples.push_back(measure_once_ms(fn));
        }
        std::sort(samples.begin(), samples.end());
        const std::size_t median_index = (samples.size() - 1) / 2;
        const std::size_t p95_index =
            std::min(samples.size() - 1, (samples.size() * 95 + 99) / 100 - 1);
        return TimingStats{samples[median_index], samples[p95_index], samples.front()};
    }

    template <typename Fn>
    double profile_loop_ms(int repeat, Fn &&fn)
    {
        const auto start = std::chrono::steady_clock::now();
        for (int index = 0; index < repeat; ++index)
        {
            fn();
        }
        throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize after profile loop");
        const auto end = std::chrono::steady_clock::now();
        return std::chrono::duration<double, std::milli>(end - start).count();
    }

    std::vector<float2> make_input(std::size_t total, int fft_size)
    {
        std::vector<float2> values(total);
        for (std::size_t index = 0; index < total; ++index)
        {
            const std::size_t batch = index / static_cast<std::size_t>(fft_size);
            const std::size_t sample = index % static_cast<std::size_t>(fft_size);
            const float x = static_cast<float>(sample);
            const float b = static_cast<float>(batch % 97U);
            values[index] = make_float2(
                std::sin(0.017f * x + 0.003f * b) + 0.25f * std::cos(0.071f * x),
                std::cos(0.023f * x - 0.005f * b) - 0.20f * std::sin(0.043f * x));
        }
        return values;
    }

    std::vector<float2> make_twiddles(int fft_size)
    {
        std::vector<float2> values(static_cast<std::size_t>(fft_size / 2));
        for (int index = 0; index < fft_size / 2; ++index)
        {
            const float angle =
                -2.0f * kPi * static_cast<float>(index) / static_cast<float>(fft_size);
            values[static_cast<std::size_t>(index)] =
                make_float2(std::cos(angle), std::sin(angle));
        }
        return values;
    }

    ErrorStats compare_values(
        const std::vector<float2> &actual,
        const std::vector<float2> &expected)
    {
        if (actual.size() != expected.size())
        {
            throw std::invalid_argument("comparison size mismatch");
        }
        double max_abs = 0.0;
        long double squared_error = 0.0;
        long double squared_reference = 0.0;
        for (std::size_t index = 0; index < actual.size(); ++index)
        {
            const double real_error =
                static_cast<double>(actual[index].x) - static_cast<double>(expected[index].x);
            const double imag_error =
                static_cast<double>(actual[index].y) - static_cast<double>(expected[index].y);
            const double abs_error = std::hypot(real_error, imag_error);
            max_abs = std::max(max_abs, abs_error);
            squared_error += real_error * real_error + imag_error * imag_error;
            squared_reference +=
                static_cast<double>(expected[index].x) * static_cast<double>(expected[index].x) +
                static_cast<double>(expected[index].y) * static_cast<double>(expected[index].y);
        }
        const long double count = static_cast<long double>(actual.size());
        const double rmse = std::sqrt(static_cast<double>(squared_error / count));
        const double reference_rms =
            std::sqrt(static_cast<double>(squared_reference / count));
        return ErrorStats{
            max_abs,
            rmse,
            rmse / std::max(reference_rms, 1.0e-30)};
    }

    long long epoch_ns()
    {
        return std::chrono::duration_cast<std::chrono::nanoseconds>(
                   std::chrono::system_clock::now().time_since_epoch())
            .count();
    }

    void print_timing(const char *prefix, const TimingStats &stats)
    {
        std::printf(
            "%s_median_ms=%.9f %s_p95_ms=%.9f %s_min_ms=%.9f ",
            prefix,
            stats.median_ms,
            prefix,
            stats.p95_ms,
            prefix,
            stats.minimum_ms);
    }
}

int main(int argc, char **argv)
{
    cufftHandle plan = 0;
    float2 *device_input = nullptr;
    float2 *device_custom = nullptr;
    float2 *device_dlfft = nullptr;
    float2 *device_twiddles = nullptr;

    try
    {
        const Options options = parse_options(argc, argv);
        const int log2_size = exact_log2(options.fft_size);
        const std::size_t total =
            static_cast<std::size_t>(options.fft_size) * static_cast<std::size_t>(options.batch);
        const std::size_t data_bytes = total * sizeof(float2);
        const std::size_t shared_bytes =
            static_cast<std::size_t>(options.fft_size) * sizeof(float2);

        cudaDeviceProp properties{};
        throw_on_cuda_error(cudaGetDeviceProperties(&properties, 0), "cudaGetDeviceProperties");
        if (shared_bytes > properties.sharedMemPerBlock)
        {
            throw std::runtime_error(
                "fixed FFT shared-memory requirement exceeds sharedMemPerBlock");
        }

        std::size_t free_before = 0;
        std::size_t total_memory = 0;
        throw_on_cuda_error(cudaMemGetInfo(&free_before, &total_memory), "cudaMemGetInfo before");

        const std::vector<float2> host_input = make_input(total, options.fft_size);
        const auto custom_setup_start = std::chrono::steady_clock::now();
        const std::vector<float2> host_twiddles = make_twiddles(options.fft_size);
        throw_on_cuda_error(
            cudaMalloc(reinterpret_cast<void **>(&device_input), data_bytes),
            "cudaMalloc input");
        throw_on_cuda_error(
            cudaMalloc(reinterpret_cast<void **>(&device_custom), data_bytes),
            "cudaMalloc custom");
        throw_on_cuda_error(
            cudaMalloc(reinterpret_cast<void **>(&device_dlfft), data_bytes),
            "cudaMalloc dlfft");
        throw_on_cuda_error(
            cudaMalloc(
                reinterpret_cast<void **>(&device_twiddles),
                host_twiddles.size() * sizeof(float2)),
            "cudaMalloc twiddles");
        throw_on_cuda_error(
            cudaMemcpy(device_input, host_input.data(), data_bytes, cudaMemcpyHostToDevice),
            "cudaMemcpy input");
        throw_on_cuda_error(
            cudaMemcpy(
                device_twiddles,
                host_twiddles.data(),
                host_twiddles.size() * sizeof(float2),
                cudaMemcpyHostToDevice),
            "cudaMemcpy twiddles");
        throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize after setup");
        const auto custom_setup_end = std::chrono::steady_clock::now();
        const double custom_setup_ms =
            std::chrono::duration<double, std::milli>(custom_setup_end - custom_setup_start).count();

        const auto launch_custom_forward = [&]() {
            fixed_radix2_fft_kernel<<<options.batch, kThreadsPerBlock, shared_bytes>>>(
                device_input,
                device_custom,
                device_twiddles,
                options.fft_size,
                log2_size,
                0);
            throw_on_cuda_error(cudaGetLastError(), "fixed_radix2_fft_kernel forward");
        };
        const auto launch_custom_inverse = [&]() {
            fixed_radix2_fft_kernel<<<options.batch, kThreadsPerBlock, shared_bytes>>>(
                device_custom,
                device_dlfft,
                device_twiddles,
                options.fft_size,
                log2_size,
                1);
            throw_on_cuda_error(cudaGetLastError(), "fixed_radix2_fft_kernel inverse");
        };

        const double custom_first_forward_ms = measure_once_ms(launch_custom_forward);

        const auto plan_start = std::chrono::steady_clock::now();
        throw_on_cufft_error(
            cufftPlan1d(&plan, options.fft_size, CUFFT_C2C, options.batch),
            "cufftPlan1d");
        const auto plan_end = std::chrono::steady_clock::now();
        const double dlfft_plan_ms =
            std::chrono::duration<double, std::milli>(plan_end - plan_start).count();

        const auto launch_dlfft_forward = [&]() {
            throw_on_cufft_error(
                cufftExecC2C(
                    plan,
                    reinterpret_cast<cufftComplex *>(device_input),
                    reinterpret_cast<cufftComplex *>(device_dlfft),
                    CUFFT_FORWARD),
                "cufftExecC2C forward");
        };
        const auto launch_dlfft_inverse = [&]() {
            throw_on_cufft_error(
                cufftExecC2C(
                    plan,
                    reinterpret_cast<cufftComplex *>(device_custom),
                    reinterpret_cast<cufftComplex *>(device_dlfft),
                    CUFFT_INVERSE),
                "cufftExecC2C inverse");
        };
        const double dlfft_first_forward_ms = measure_once_ms(launch_dlfft_forward);

        std::vector<float2> host_custom(total);
        std::vector<float2> host_dlfft(total);
        throw_on_cuda_error(
            cudaMemcpy(host_custom.data(), device_custom, data_bytes, cudaMemcpyDeviceToHost),
            "cudaMemcpy custom forward");
        throw_on_cuda_error(
            cudaMemcpy(host_dlfft.data(), device_dlfft, data_bytes, cudaMemcpyDeviceToHost),
            "cudaMemcpy dlfft forward");
        const ErrorStats forward_error = compare_values(host_custom, host_dlfft);

        const double custom_first_inverse_ms = measure_once_ms(launch_custom_inverse);
        throw_on_cuda_error(
            cudaMemcpy(host_custom.data(), device_dlfft, data_bytes, cudaMemcpyDeviceToHost),
            "cudaMemcpy custom roundtrip");
        const ErrorStats roundtrip_error = compare_values(host_custom, host_input);

        launch_custom_forward();
        throw_on_cuda_error(cudaDeviceSynchronize(), "cudaDeviceSynchronize before timings");
        const TimingStats custom_forward = measure_repeated_ms(
            options.warmup,
            options.repeat,
            launch_custom_forward);
        const TimingStats custom_inverse = measure_repeated_ms(
            options.warmup,
            options.repeat,
            launch_custom_inverse);
        const TimingStats dlfft_forward = measure_repeated_ms(
            options.warmup,
            options.repeat,
            launch_dlfft_forward);
        const TimingStats dlfft_inverse = measure_repeated_ms(
            options.warmup,
            options.repeat,
            launch_dlfft_inverse);

        std::printf(
            "MARK phase=custom_profile_start epoch_ns=%lld fft_size=%d batch=%d\n",
            epoch_ns(),
            options.fft_size,
            options.batch);
        std::fflush(stdout);
        const double custom_profile_ms =
            profile_loop_ms(options.profile_repeat, launch_custom_forward);
        std::printf(
            "MARK phase=custom_profile_end epoch_ns=%lld fft_size=%d batch=%d\n",
            epoch_ns(),
            options.fft_size,
            options.batch);
        std::printf(
            "MARK phase=dlfft_profile_start epoch_ns=%lld fft_size=%d batch=%d\n",
            epoch_ns(),
            options.fft_size,
            options.batch);
        std::fflush(stdout);
        const double dlfft_profile_ms =
            profile_loop_ms(options.profile_repeat, launch_dlfft_forward);
        std::printf(
            "MARK phase=dlfft_profile_end epoch_ns=%lld fft_size=%d batch=%d\n",
            epoch_ns(),
            options.fft_size,
            options.batch);

        std::size_t free_after = 0;
        throw_on_cuda_error(cudaMemGetInfo(&free_after, &total_memory), "cudaMemGetInfo after");
        const double memory_delta_mib =
            static_cast<double>(free_before - std::min(free_before, free_after)) /
            (1024.0 * 1024.0);

        std::printf(
            "RESULT fft_size=%d batch=%d elements=%zu shared_bytes=%zu "
            "custom_setup_ms=%.9f custom_first_forward_ms=%.9f "
            "custom_first_inverse_ms=%.9f dlfft_plan_ms=%.9f "
            "dlfft_first_forward_ms=%.9f ",
            options.fft_size,
            options.batch,
            total,
            shared_bytes,
            custom_setup_ms,
            custom_first_forward_ms,
            custom_first_inverse_ms,
            dlfft_plan_ms,
            dlfft_first_forward_ms);
        print_timing("custom_forward", custom_forward);
        print_timing("custom_inverse", custom_inverse);
        print_timing("dlfft_forward", dlfft_forward);
        print_timing("dlfft_inverse", dlfft_inverse);
        std::printf(
            "forward_max_abs=%.9e forward_rmse=%.9e forward_relative_rmse=%.9e "
            "roundtrip_max_abs=%.9e roundtrip_rmse=%.9e roundtrip_relative_rmse=%.9e "
            "profile_repeat=%d custom_profile_total_ms=%.9f dlfft_profile_total_ms=%.9f "
            "device_memory_delta_mib=%.3f\n",
            forward_error.max_abs,
            forward_error.rmse,
            forward_error.relative_rmse,
            roundtrip_error.max_abs,
            roundtrip_error.rmse,
            roundtrip_error.relative_rmse,
            options.profile_repeat,
            custom_profile_ms,
            dlfft_profile_ms,
            memory_delta_mib);

        throw_on_cufft_error(cufftDestroy(plan), "cufftDestroy");
        plan = 0;
        throw_on_cuda_error(cudaFree(device_twiddles), "cudaFree twiddles");
        device_twiddles = nullptr;
        throw_on_cuda_error(cudaFree(device_dlfft), "cudaFree dlfft");
        device_dlfft = nullptr;
        throw_on_cuda_error(cudaFree(device_custom), "cudaFree custom");
        device_custom = nullptr;
        throw_on_cuda_error(cudaFree(device_input), "cudaFree input");
        device_input = nullptr;
        return 0;
    }
    catch (const std::exception &error)
    {
        std::fprintf(stderr, "ERROR %s\n", error.what());
        if (plan != 0)
        {
            cufftDestroy(plan);
        }
        if (device_twiddles != nullptr)
        {
            cudaFree(device_twiddles);
        }
        if (device_dlfft != nullptr)
        {
            cudaFree(device_dlfft);
        }
        if (device_custom != nullptr)
        {
            cudaFree(device_custom);
        }
        if (device_input != nullptr)
        {
            cudaFree(device_input);
        }
        return 1;
    }
}
