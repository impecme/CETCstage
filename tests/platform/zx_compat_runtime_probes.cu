#include <cuda_runtime_api.h>
#include <cublas_v2.h>
#include <cudnn.h>
#include <cufft.h>
#include <curand.h>
#include <cusolverDn.h>
#include <cusparse.h>

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
    cudaEvent_t begin = nullptr;
    cudaEvent_t end = nullptr;
    if (!check_cuda(cudaMalloc(reinterpret_cast<void **>(&device_values), count * sizeof(float)), "cudaMalloc") ||
        !check_cuda(cudaMemcpy(device_values, input.data(), count * sizeof(float), cudaMemcpyHostToDevice), "cudaMemcpy H2D") ||
        !check_cuda(cudaMemset(device_values + 4, 0, 4 * sizeof(float)), "cudaMemset") ||
        !check_cuda(cudaEventCreate(&begin), "cudaEventCreate(begin)") ||
        !check_cuda(cudaEventCreate(&end), "cudaEventCreate(end)") ||
        !check_cuda(cudaEventRecord(begin), "cudaEventRecord(begin)") ||
        !check_cuda(cudaEventRecord(end), "cudaEventRecord(end)") ||
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

    cufftHandle fft = 0;
    cufftComplex *fft_values = nullptr;
    cublasHandle_t blas = nullptr;
    cusolverDnHandle_t solver = nullptr;
    cudnnHandle_t dnn = nullptr;
    cusparseHandle_t sparse = nullptr;
    curandGenerator_t random = nullptr;
    if (!check_cuda(cudaMalloc(reinterpret_cast<void **>(&fft_values), count * sizeof(cufftComplex)), "cudaMalloc(fft)") ||
        !check_cuda(cudaMemset(fft_values, 0, count * sizeof(cufftComplex)), "cudaMemset(fft)") ||
        cufftPlan1d(&fft, count, CUFFT_C2C, 1) != CUFFT_SUCCESS ||
        cufftExecC2C(fft, fft_values, fft_values, CUFFT_FORWARD) != CUFFT_SUCCESS ||
        cublasCreate(&blas) != CUBLAS_STATUS_SUCCESS ||
        cusolverDnCreate(&solver) != CUSOLVER_STATUS_SUCCESS ||
        cudnnCreate(&dnn) != CUDNN_STATUS_SUCCESS ||
        cusparseCreate(&sparse) != CUSPARSE_STATUS_SUCCESS ||
        curandCreateGenerator(&random, CURAND_RNG_PSEUDO_XORWOW) != CURAND_STATUS_SUCCESS)
        return 1;
    cufftDestroy(fft);
    cudaFree(fft_values);
    cublasDestroy(blas);
    cusolverDnDestroy(solver);
    cudnnDestroy(dnn);
    cusparseDestroy(sparse);
    curandDestroyGenerator(random);

    cudaEventDestroy(begin);
    cudaEventDestroy(end);
    cudaFree(device_values);
    std::cout << "[zx/compat] PASS device=" << device
              << " total_mib=" << total_bytes / (1024 * 1024)
              << " runtime=passed fft=passed blas=passed dnn=passed"
              << " solver=passed sparse=passed rand=passed\n";
    return 0;
}
