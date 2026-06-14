#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build-zx-probe"
CUDA_ARCH="${CUDA_ARCH:-80}"
CXX_COMPILER="${CXX:-}"
CUDA_COMPILER="${CUDACXX:-}"

usage() {
  cat <<'USAGE'
Usage: scripts/platform/probe_zhongkexin.sh [options]

Options:
  --build-dir DIR       Probe build directory (default: build-zx-probe)
  --cuda-arch ARCH      CUDA architecture passed to CMake (default: CUDA_ARCH or 80)
  --cxx PATH            Optional C++ compiler
  --cuda PATH           Optional CUDA compiler
  -h, --help            Show this help

Environment:
  CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY     Optional cuFFT-compatible library path
  CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY    Optional cuBLAS-compatible library path
  CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY  Optional cuSOLVER-compatible library path
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --cuda-arch)
      CUDA_ARCH="$2"
      shift 2
      ;;
    --cxx)
      CXX_COMPILER="$2"
      shift 2
      ;;
    --cuda)
      CUDA_COMPILER="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[zx-probe] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${BUILD_DIR}" != /* ]]; then
  BUILD_DIR="${PROJECT_ROOT}/${BUILD_DIR}"
fi

SRC_DIR="${BUILD_DIR}/src"
REPORT="${BUILD_DIR}/probe_report.md"

rm -rf "${BUILD_DIR}"
mkdir -p "${SRC_DIR}"

cat >"${SRC_DIR}/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.18)
project(zhongkexin_cuda_probe LANGUAGES CXX CUDA)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

find_package(CUDAToolkit REQUIRED)

function(zx_probe_require_or_alias target_name cache_library label)
    if(TARGET ${target_name})
        return()
    endif()
    if(DEFINED ${cache_library} AND NOT "${${cache_library}}" STREQUAL "")
        add_library(${target_name} UNKNOWN IMPORTED)
        set_target_properties(${target_name} PROPERTIES
            IMPORTED_LOCATION "${${cache_library}}"
            INTERFACE_INCLUDE_DIRECTORIES "${CUDAToolkit_INCLUDE_DIRS}"
        )
        message(STATUS "Using ${label} compatibility library: ${${cache_library}}")
        return()
    endif()
    message(FATAL_ERROR "${target_name} is unavailable. Set ${cache_library} if the compatibility library has a different CMake target name.")
endfunction()

zx_probe_require_or_alias(CUDA::cufft_static CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY "cuFFT")
zx_probe_require_or_alias(CUDA::cublas CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY "cuBLAS")
zx_probe_require_or_alias(CUDA::cusolver CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY "cuSOLVER")

add_executable(zx_probe probe.cu)
target_link_libraries(zx_probe PRIVATE CUDA::cudart CUDA::cufft_static CUDA::cublas CUDA::cusolver)
CMAKE

cat >"${SRC_DIR}/probe.cu" <<'CU'
#include <cuda_runtime.h>
#include <cufft.h>
#include <cublas_v2.h>
#include <cusolverDn.h>

#include <cmath>
#include <complex>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace
{
    void check(cudaError_t status, const char *what)
    {
        if (status != cudaSuccess)
        {
            throw std::runtime_error(std::string(what) + ": " + cudaGetErrorString(status));
        }
    }

    void check(cufftResult status, const char *what)
    {
        if (status != CUFFT_SUCCESS)
        {
            throw std::runtime_error(std::string(what) + ": cuFFT error " + std::to_string(static_cast<int>(status)));
        }
    }

    void check(cublasStatus_t status, const char *what)
    {
        if (status != CUBLAS_STATUS_SUCCESS)
        {
            throw std::runtime_error(std::string(what) + ": cuBLAS error " + std::to_string(static_cast<int>(status)));
        }
    }

    void check(cusolverStatus_t status, const char *what)
    {
        if (status != CUSOLVER_STATUS_SUCCESS)
        {
            throw std::runtime_error(std::string(what) + ": cuSOLVER error " + std::to_string(static_cast<int>(status)));
        }
    }

    __global__ void add_one_kernel(float *values, int count)
    {
        const int index = blockIdx.x * blockDim.x + threadIdx.x;
        if (index < count)
        {
            values[index] += 1.0f;
        }
    }

    void probe_runtime()
    {
        int device = -1;
        check(cudaGetDevice(&device), "cudaGetDevice");
        cudaDeviceProp prop{};
        check(cudaGetDeviceProperties(&prop, device), "cudaGetDeviceProperties");
        std::size_t free_bytes = 0;
        std::size_t total_bytes = 0;
        check(cudaMemGetInfo(&free_bytes, &total_bytes), "cudaMemGetInfo");

        std::vector<float> host{0.0f, 1.0f, 2.0f, 3.0f};
        float *device_values = nullptr;
        check(cudaMalloc(reinterpret_cast<void **>(&device_values), host.size() * sizeof(float)), "cudaMalloc");
        check(cudaMemcpy(device_values, host.data(), host.size() * sizeof(float), cudaMemcpyHostToDevice), "cudaMemcpy H2D");

        cudaEvent_t start = nullptr;
        cudaEvent_t stop = nullptr;
        check(cudaEventCreate(&start), "cudaEventCreate(start)");
        check(cudaEventCreate(&stop), "cudaEventCreate(stop)");
        check(cudaEventRecord(start), "cudaEventRecord(start)");
        add_one_kernel<<<1, 32>>>(device_values, static_cast<int>(host.size()));
        check(cudaGetLastError(), "add_one_kernel launch");
        check(cudaEventRecord(stop), "cudaEventRecord(stop)");
        check(cudaEventSynchronize(stop), "cudaEventSynchronize(stop)");
        float elapsed_ms = 0.0f;
        check(cudaEventElapsedTime(&elapsed_ms, start, stop), "cudaEventElapsedTime");

        check(cudaMemcpy(host.data(), device_values, host.size() * sizeof(float), cudaMemcpyDeviceToHost), "cudaMemcpy D2H");
        check(cudaFree(device_values), "cudaFree");
        check(cudaEventDestroy(start), "cudaEventDestroy(start)");
        check(cudaEventDestroy(stop), "cudaEventDestroy(stop)");

        if (std::fabs(host[3] - 4.0f) > 1.0e-6f)
        {
            throw std::runtime_error("kernel result mismatch");
        }

        float2 complex_value{1.0f, -2.0f};
        if (complex_value.x != 1.0f || complex_value.y != -2.0f)
        {
            throw std::runtime_error("float2 layout mismatch");
        }

        std::cout << "runtime: pass device=" << device
                  << " name=\"" << prop.name << "\""
                  << " free_mib=" << (free_bytes / 1048576.0)
                  << " total_mib=" << (total_bytes / 1048576.0)
                  << " event_ms=" << elapsed_ms << '\n';
    }

    void probe_cufft()
    {
        cufftHandle plan = 0;
        check(cufftPlan1d(&plan, 4, CUFFT_C2C, 1), "cufftPlan1d");
        cufftComplex *values = nullptr;
        check(cudaMalloc(reinterpret_cast<void **>(&values), 4 * sizeof(cufftComplex)), "cudaMalloc(cufft)");
        std::vector<cufftComplex> host(4);
        host[0].x = 1.0f;
        check(cudaMemcpy(values, host.data(), host.size() * sizeof(cufftComplex), cudaMemcpyHostToDevice), "cudaMemcpy(cufft)");
        check(cufftExecC2C(plan, values, values, CUFFT_FORWARD), "cufftExecC2C");
        check(cudaDeviceSynchronize(), "cudaDeviceSynchronize(cufft)");
        check(cudaFree(values), "cudaFree(cufft)");
        check(cufftDestroy(plan), "cufftDestroy");
        std::cout << "cufft: pass\n";
    }

    void probe_cublas()
    {
        cublasHandle_t handle = nullptr;
        check(cublasCreate(&handle), "cublasCreate");
        const int n = 2;
        cufftComplex host_a[n * n] = {{1.0f, 0.0f}, {0.0f, 0.0f}, {0.0f, 0.0f}, {1.0f, 0.0f}};
        cufftComplex host_b[n * n] = {{2.0f, 0.0f}, {0.0f, 0.0f}, {0.0f, 0.0f}, {3.0f, 0.0f}};
        cufftComplex *a = nullptr;
        cufftComplex *b = nullptr;
        cufftComplex *c = nullptr;
        check(cudaMalloc(reinterpret_cast<void **>(&a), sizeof(host_a)), "cudaMalloc(a)");
        check(cudaMalloc(reinterpret_cast<void **>(&b), sizeof(host_b)), "cudaMalloc(b)");
        check(cudaMalloc(reinterpret_cast<void **>(&c), sizeof(host_b)), "cudaMalloc(c)");
        check(cudaMemcpy(a, host_a, sizeof(host_a), cudaMemcpyHostToDevice), "cudaMemcpy(a)");
        check(cudaMemcpy(b, host_b, sizeof(host_b), cudaMemcpyHostToDevice), "cudaMemcpy(b)");
        const cufftComplex alpha{1.0f, 0.0f};
        const cufftComplex beta{0.0f, 0.0f};
        check(cublasCgemm(handle, CUBLAS_OP_N, CUBLAS_OP_N, n, n, n, &alpha, a, n, b, n, &beta, c, n), "cublasCgemm");
        check(cudaFree(a), "cudaFree(a)");
        check(cudaFree(b), "cudaFree(b)");
        check(cudaFree(c), "cudaFree(c)");
        check(cublasDestroy(handle), "cublasDestroy");
        std::cout << "cublas: pass\n";
    }

    void probe_cusolver()
    {
        cusolverDnHandle_t handle = nullptr;
        check(cusolverDnCreate(&handle), "cusolverDnCreate");
        const int n = 2;
        cufftComplex host_a[n * n] = {{4.0f, 0.0f}, {2.0f, 0.0f}, {1.0f, 0.0f}, {3.0f, 0.0f}};
        cufftComplex host_b[n] = {{1.0f, 0.0f}, {1.0f, 0.0f}};
        cufftComplex *a = nullptr;
        cufftComplex *b = nullptr;
        int *pivot = nullptr;
        int *info_device = nullptr;
        cufftComplex *workspace = nullptr;
        int lwork = 0;
        int info = 0;

        check(cudaMalloc(reinterpret_cast<void **>(&a), sizeof(host_a)), "cudaMalloc(cusolver a)");
        check(cudaMalloc(reinterpret_cast<void **>(&b), sizeof(host_b)), "cudaMalloc(cusolver b)");
        check(cudaMalloc(reinterpret_cast<void **>(&pivot), n * sizeof(int)), "cudaMalloc(cusolver pivot)");
        check(cudaMalloc(reinterpret_cast<void **>(&info_device), sizeof(int)), "cudaMalloc(cusolver info)");
        check(cudaMemcpy(a, host_a, sizeof(host_a), cudaMemcpyHostToDevice), "cudaMemcpy(cusolver a)");
        check(cudaMemcpy(b, host_b, sizeof(host_b), cudaMemcpyHostToDevice), "cudaMemcpy(cusolver b)");

        check(cusolverDnCgetrf_bufferSize(handle, n, n, a, n, &lwork), "cusolverDnCgetrf_bufferSize");
        check(cudaMalloc(reinterpret_cast<void **>(&workspace), static_cast<std::size_t>(lwork) * sizeof(cufftComplex)), "cudaMalloc(cusolver workspace)");
        check(cusolverDnCgetrf(handle, n, n, a, n, workspace, pivot, info_device), "cusolverDnCgetrf");
        check(cudaMemcpy(&info, info_device, sizeof(int), cudaMemcpyDeviceToHost), "cudaMemcpy(cusolver getrf info)");
        if (info != 0)
        {
            throw std::runtime_error("cusolverDnCgetrf info=" + std::to_string(info));
        }
        check(cusolverDnCgetrs(handle, CUBLAS_OP_N, n, 1, a, n, pivot, b, n, info_device), "cusolverDnCgetrs");
        check(cudaMemcpy(&info, info_device, sizeof(int), cudaMemcpyDeviceToHost), "cudaMemcpy(cusolver getrs info)");
        if (info != 0)
        {
            throw std::runtime_error("cusolverDnCgetrs info=" + std::to_string(info));
        }

        check(cudaFree(a), "cudaFree(cusolver a)");
        check(cudaFree(b), "cudaFree(cusolver b)");
        check(cudaFree(pivot), "cudaFree(cusolver pivot)");
        check(cudaFree(info_device), "cudaFree(cusolver info)");
        check(cudaFree(workspace), "cudaFree(cusolver workspace)");
        check(cusolverDnDestroy(handle), "cusolverDnDestroy");
        std::cout << "cusolver: pass\n";
    }
}

int main()
{
    try
    {
        probe_runtime();
        probe_cufft();
        probe_cublas();
        probe_cusolver();
    }
    catch (const std::exception &error)
    {
        std::cerr << "probe failed: " << error.what() << '\n';
        return 1;
    }
    return 0;
}
CU

CMAKE_ARGS=(
  -S "${SRC_DIR}"
  -B "${BUILD_DIR}/build"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}"
)

if [[ -n "${CXX_COMPILER}" ]]; then
  CMAKE_ARGS+=("-DCMAKE_CXX_COMPILER=${CXX_COMPILER}")
fi
if [[ -n "${CUDA_COMPILER}" ]]; then
  CMAKE_ARGS+=("-DCMAKE_CUDA_COMPILER=${CUDA_COMPILER}")
fi
if [[ -n "${CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY:-}" ]]; then
  CMAKE_ARGS+=("-DCUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY=${CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY}")
fi
if [[ -n "${CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY:-}" ]]; then
  CMAKE_ARGS+=("-DCUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY=${CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY}")
fi
if [[ -n "${CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY:-}" ]]; then
  CMAKE_ARGS+=("-DCUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY=${CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY}")
fi

echo "[zx-probe] configure: ${CMAKE_ARGS[*]}"
cmake "${CMAKE_ARGS[@]}"
cmake --build "${BUILD_DIR}/build" --target zx_probe --parallel

echo "[zx-probe] running probe"
"${BUILD_DIR}/build/zx_probe" | tee "${BUILD_DIR}/probe_stdout.txt"

{
  echo "# Zhongkexin Platform Probe"
  echo
  echo "- build_dir: ${BUILD_DIR}"
  echo "- cuda_arch: ${CUDA_ARCH}"
  echo "- result: pass"
  echo
  echo '```text'
  cat "${BUILD_DIR}/probe_stdout.txt"
  echo '```'
} >"${REPORT}"

echo "[zx-probe] report: ${REPORT}"
