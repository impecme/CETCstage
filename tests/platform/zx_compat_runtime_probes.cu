#include <cuda_runtime_api.h>
#include <cublas_v2.h>
#include <cudnn.h>
#include <cufft.h>
#include <curand.h>
#include <cusolverDn.h>
#include <cusparse.h>

#include <chrono>
#include <cmath>
#include <iostream>
#include <vector>

namespace
{
    bool check_cuda(cudaError_t status, const char *name)
    {
        if (status == cudaSuccess)
            return true;
        std::cerr << name << " failed: " << cudaGetErrorString(status) << '\n';
        return false;
    }
}

int main()
{
    int device = -1;
    cudaDeviceProp properties{};
    std::size_t free_bytes = 0;
    std::size_t total_bytes = 0;
    if (!check_cuda(cudaGetDevice(&device), "cudaGetDevice") ||
        !check_cuda(cudaGetDeviceProperties(&properties, device), "cudaGetDeviceProperties") ||
        !check_cuda(cudaMemGetInfo(&free_bytes, &total_bytes), "cudaMemGetInfo"))
        return 1;

    constexpr int count = 8;
    const std::vector<float> input{0.0f, 1.0f, 2.0f, 3.0f, 4.0f, 5.0f, 6.0f, 7.0f};
    std::vector<float> output(count, -1.0f);
    float *device_values = nullptr;
    cudaStream_t stream = nullptr;
    cudaEvent_t begin = nullptr;
    cudaEvent_t end = nullptr;
    float *pinned_input = nullptr;
    float *pinned_output = nullptr;
    int host_alloc_status = -1;
    int async_h2d_status = -1;
    int async_d2h_status = -1;
    int pinned_sync_status = -1;
    bool pinned_copy_supported = false;
    if (!check_cuda(cudaMalloc(reinterpret_cast<void **>(&device_values), count * sizeof(float)), "cudaMalloc") ||
        !check_cuda(cudaMemcpy(device_values, input.data(), count * sizeof(float), cudaMemcpyHostToDevice), "cudaMemcpy H2D") ||
        !check_cuda(cudaMemset(device_values + 4, 0, 4 * sizeof(float)), "cudaMemset") ||
        !check_cuda(cudaStreamCreate(&stream), "cudaStreamCreate") ||
        !check_cuda(cudaEventCreate(&begin), "cudaEventCreate(begin)") ||
        !check_cuda(cudaEventCreate(&end), "cudaEventCreate(end)") ||
        !check_cuda(cudaEventRecord(begin, stream), "cudaEventRecord(begin)") ||
        !check_cuda(cudaMemsetAsync(device_values + 4, 0, 4 * sizeof(float), stream), "cudaMemsetAsync") ||
        !check_cuda(cudaEventRecord(end, stream), "cudaEventRecord(end)") ||
        !check_cuda(cudaEventSynchronize(end), "cudaEventSynchronize") ||
        !check_cuda(cudaMemcpy(output.data(), device_values, count * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy D2H"))
        return 1;

    float elapsed_ms = -1.0f;
    if (!check_cuda(cudaEventElapsedTime(&elapsed_ms, begin, end), "cudaEventElapsedTime"))
        return 1;
    for (int index = 0; index < count; ++index)
    {
        const float expected = index < 4 ? input[index] : 0.0f;
        if (std::fabs(output[index] - expected) > 1.0e-6f)
            return 1;
    }

    // Capability probe only.  The production path remains synchronous unless
    // a later benchmark explicitly proves that a pinned staging path helps the
    // complete operator E2E time.
    host_alloc_status = static_cast<int>(cudaHostAlloc(
        reinterpret_cast<void **>(&pinned_input),
        count * sizeof(float),
        cudaHostAllocDefault));
    if (host_alloc_status == static_cast<int>(cudaSuccess))
    {
        host_alloc_status = static_cast<int>(cudaHostAlloc(
            reinterpret_cast<void **>(&pinned_output),
            count * sizeof(float),
            cudaHostAllocDefault));
    }
    if (host_alloc_status == static_cast<int>(cudaSuccess))
    {
        for (int index = 0; index < count; ++index)
        {
            pinned_input[index] = static_cast<float>(index + 10);
            pinned_output[index] = -1.0f;
        }
        async_h2d_status = static_cast<int>(cudaMemcpyAsync(
            device_values,
            pinned_input,
            count * sizeof(float),
            cudaMemcpyHostToDevice,
            stream));
        pinned_sync_status = static_cast<int>(cudaStreamSynchronize(stream));
        async_d2h_status = static_cast<int>(cudaMemcpyAsync(
            pinned_output,
            device_values,
            count * sizeof(float),
            cudaMemcpyDeviceToHost,
            stream));
        if (async_d2h_status == static_cast<int>(cudaSuccess))
        {
            pinned_sync_status = static_cast<int>(cudaStreamSynchronize(stream));
        }
        pinned_copy_supported =
            async_h2d_status == static_cast<int>(cudaSuccess) &&
            async_d2h_status == static_cast<int>(cudaSuccess) &&
            pinned_sync_status == static_cast<int>(cudaSuccess);
        if (pinned_copy_supported)
        {
            for (int index = 0; index < count; ++index)
            {
                if (std::fabs(pinned_output[index] - pinned_input[index]) > 1.0e-6f)
                {
                    pinned_copy_supported = false;
                    break;
                }
            }
        }
    }
    if (pinned_output != nullptr)
    {
        cudaFreeHost(pinned_output);
    }
    if (pinned_input != nullptr)
    {
        cudaFreeHost(pinned_input);
    }

    cufftHandle fft = 0;
    cufftHandle fft_batch = 0;
    cufftHandle fft_many = 0;
    cufftComplex *fft_values = nullptr;
    cublasHandle_t blas = nullptr;
    cusolverDnHandle_t solver = nullptr;
    cudnnHandle_t dnn = nullptr;
    cusparseHandle_t sparse = nullptr;
    curandGenerator_t random = nullptr;
    const auto plan_begin = std::chrono::steady_clock::now();
    const cufftResult plan_status = cufftPlan1d(&fft, count, CUFFT_C2C, 1);
    const auto plan_single_end = std::chrono::steady_clock::now();
    const cufftResult batch_plan_status = cufftPlan1d(&fft_batch, count, CUFFT_C2C, 8);
    const auto plan_batch_end = std::chrono::steady_clock::now();
    int transform_size[1] = {count};
    int input_embed[1] = {count};
    int output_embed[1] = {count};
    const cufftResult plan_many_status = cufftPlanMany(
        &fft_many,
        1,
        transform_size,
        input_embed,
        8,
        1,
        output_embed,
        8,
        1,
        CUFFT_C2C,
        8);
    const bool plan_many_supported = plan_many_status == CUFFT_SUCCESS;
    bool plan_many_advanced_supported = plan_many_supported;
    int plan_many_set_stream_status = -1;
    int plan_many_exec_status = -1;
    int plan_many_numeric_status = -1;
    std::size_t single_workspace_bytes = 0;
    std::size_t batch_workspace_bytes = 0;
    if (!check_cuda(cudaMalloc(reinterpret_cast<void **>(&fft_values), count * 8 * sizeof(cufftComplex)), "cudaMalloc(fft)") ||
        !check_cuda(cudaMemset(fft_values, 0, count * 8 * sizeof(cufftComplex)), "cudaMemset(fft)") ||
        plan_status != CUFFT_SUCCESS ||
        batch_plan_status != CUFFT_SUCCESS ||
        cufftSetStream(fft, stream) != CUFFT_SUCCESS ||
        cufftSetStream(fft_batch, stream) != CUFFT_SUCCESS ||
        cufftGetSize(fft, &single_workspace_bytes) != CUFFT_SUCCESS ||
        cufftGetSize(fft_batch, &batch_workspace_bytes) != CUFFT_SUCCESS ||
        cufftExecC2C(fft, fft_values, fft_values, CUFFT_FORWARD) != CUFFT_SUCCESS ||
        cufftExecC2C(fft_batch, fft_values, fft_values, CUFFT_FORWARD) != CUFFT_SUCCESS ||
        !check_cuda(cudaStreamSynchronize(stream), "cudaStreamSynchronize") ||
        cublasCreate(&blas) != CUBLAS_STATUS_SUCCESS ||
        cusolverDnCreate(&solver) != CUSOLVER_STATUS_SUCCESS ||
        cudnnCreate(&dnn) != CUDNN_STATUS_SUCCESS ||
        cusparseCreate(&sparse) != CUSPARSE_STATUS_SUCCESS ||
        curandCreateGenerator(&random, CURAND_RNG_PSEUDO_XORWOW) != CURAND_STATUS_SUCCESS)
        return 1;
    if (plan_many_supported)
    {
        const cufftResult set_stream_status = cufftSetStream(fft_many, stream);
        plan_many_set_stream_status = static_cast<int>(set_stream_status);
        if (set_stream_status != CUFFT_SUCCESS)
        {
            plan_many_advanced_supported = false;
        }
        else
        {
            std::vector<cufftComplex> advanced_input(count * 8);
            for (cufftComplex &value : advanced_input)
            {
                value.x = 0.0f;
                value.y = 0.0f;
            }
            for (int batch = 0; batch < 8; ++batch)
            {
                advanced_input[batch].x = 1.0f;
            }
            if (!check_cuda(
                    cudaMemcpy(
                        fft_values,
                        advanced_input.data(),
                        advanced_input.size() * sizeof(cufftComplex),
                        cudaMemcpyHostToDevice),
                    "cudaMemcpy PlanMany H2D"))
                return 1;
            const cufftResult exec_status =
                cufftExecC2C(fft_many, fft_values, fft_values, CUFFT_FORWARD);
            plan_many_exec_status = static_cast<int>(exec_status);
            if (exec_status != CUFFT_SUCCESS ||
                !check_cuda(cudaStreamSynchronize(stream), "cudaStreamSynchronize(PlanMany)"))
            {
                plan_many_advanced_supported = false;
            }
            else
            {
                std::vector<cufftComplex> advanced_output(count * 8);
                if (!check_cuda(
                        cudaMemcpy(
                            advanced_output.data(),
                            fft_values,
                            advanced_output.size() * sizeof(cufftComplex),
                            cudaMemcpyDeviceToHost),
                        "cudaMemcpy PlanMany D2H"))
                    return 1;
                bool numeric_ok = true;
                for (int batch = 0; batch < 8; ++batch)
                {
                    for (int index = 0; index < count; ++index)
                    {
                        const cufftComplex value = advanced_output[batch + index * 8];
                        if (std::fabs(value.x - 1.0f) > 1.0e-4f ||
                            std::fabs(value.y) > 1.0e-4f)
                        {
                            numeric_ok = false;
                        }
                    }
                }
                plan_many_numeric_status = numeric_ok ? 0 : 1;
                plan_many_advanced_supported = numeric_ok;
            }
        }
    }
    cufftDestroy(fft);
    cufftDestroy(fft_batch);
    if (fft_many != 0)
    {
        cufftDestroy(fft_many);
    }
    cudaFree(fft_values);
    cublasDestroy(blas);
    cusolverDnDestroy(solver);
    cudnnDestroy(dnn);
    cusparseDestroy(sparse);
    curandDestroyGenerator(random);

    const double single_plan_ms =
        std::chrono::duration<double, std::milli>(plan_single_end - plan_begin).count();
    const double batch_plan_ms =
        std::chrono::duration<double, std::milli>(plan_batch_end - plan_single_end).count();
    cudaGraph_t graph = nullptr;
    cudaGraphExec_t graph_exec = nullptr;
    bool graph_supported = false;
    int graph_capture_begin_status = -1;
    int graph_capture_work_status = -1;
    int graph_capture_end_status = -1;
    int graph_instantiate_status = -1;
    int graph_launch_status = -1;
    int graph_sync_status = -1;
    const cudaError_t capture_begin = cudaStreamBeginCapture(stream, cudaStreamCaptureModeGlobal);
    graph_capture_begin_status = static_cast<int>(capture_begin);
    if (capture_begin == cudaSuccess)
    {
        const cudaError_t capture_work = cudaMemsetAsync(device_values, 0, count * sizeof(float), stream);
        graph_capture_work_status = static_cast<int>(capture_work);
        const cudaError_t capture_end = cudaStreamEndCapture(stream, &graph);
        graph_capture_end_status = static_cast<int>(capture_end);
        if (capture_work == cudaSuccess && capture_end == cudaSuccess && graph != nullptr)
        {
            const cudaError_t instantiate_status =
                cudaGraphInstantiate(&graph_exec, graph, nullptr, nullptr, 0);
            graph_instantiate_status = static_cast<int>(instantiate_status);
            if (instantiate_status == cudaSuccess)
            {
                const cudaError_t launch_status = cudaGraphLaunch(graph_exec, stream);
                graph_launch_status = static_cast<int>(launch_status);
                if (launch_status == cudaSuccess)
                {
                    const cudaError_t sync_status = cudaStreamSynchronize(stream);
                    graph_sync_status = static_cast<int>(sync_status);
                    graph_supported = sync_status == cudaSuccess;
                }
            }
        }
    }
    cudaGetLastError();
    if (graph_exec != nullptr)
    {
        cudaGraphExecDestroy(graph_exec);
    }
    if (graph != nullptr)
    {
        cudaGraphDestroy(graph);
    }
    cudaEventDestroy(begin);
    cudaEventDestroy(end);
    cudaStreamDestroy(stream);
    cudaFree(device_values);
    std::cout << "[zx/compat] PASS device=" << device
              << " name=" << properties.name
              << " total_mib=" << total_bytes / (1024 * 1024)
              << " concurrent_kernels=" << properties.concurrentKernels
              << " async_engines=" << properties.asyncEngineCount
              << " single_plan_ms=" << single_plan_ms
              << " batch8_plan_ms=" << batch_plan_ms
              << " plan_many=" << (plan_many_supported ? "supported" : "unsupported")
              << " plan_many_status=" << static_cast<int>(plan_many_status)
              << " plan_many_advanced="
              << (plan_many_advanced_supported ? "passed" : "failed")
              << " pinned_async="
              << (pinned_copy_supported ? "passed" : "failed")
              << " host_alloc_status=" << host_alloc_status
              << " async_h2d_status=" << async_h2d_status
              << " async_d2h_status=" << async_d2h_status
              << " pinned_sync_status=" << pinned_sync_status
              << " plan_many_set_stream_status=" << plan_many_set_stream_status
              << " plan_many_exec_status=" << plan_many_exec_status
              << " plan_many_numeric_status=" << plan_many_numeric_status
              << " single_workspace_bytes=" << single_workspace_bytes
              << " batch8_workspace_bytes=" << batch_workspace_bytes
              << " nondefault_stream=passed cufft_set_stream=passed"
              << " graph=" << (graph_supported ? "supported" : "unsupported")
              << " graph_capture_begin_status=" << graph_capture_begin_status
              << " graph_capture_work_status=" << graph_capture_work_status
              << " graph_capture_end_status=" << graph_capture_end_status
              << " graph_instantiate_status=" << graph_instantiate_status
              << " graph_launch_status=" << graph_launch_status
              << " graph_sync_status=" << graph_sync_status
              << " runtime=passed fft=passed blas=passed dnn=passed"
              << " solver=passed sparse=passed rand=passed\n";
    return 0;
}
