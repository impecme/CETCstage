#include <cuda.h>
#include <cuda_runtime_api.h>
#include <cublas_v2.h>
#include <cudnn.h>
#include <cufft.h>
#include <curand.h>
#include <cusolverDn.h>
#include <cusparse.h>

#include <type_traits>

namespace
{
    using RuntimeReset = decltype(&cudaDeviceReset);
    using RuntimePeer = decltype(&cudaDeviceCanAccessPeer);
    using RuntimeIpc = decltype(&cudaIpcGetMemHandle);
    using RuntimePeerCopy = decltype(&cudaMemcpyPeer);
    using DriverReset = decltype(&cuDevicePrimaryCtxReset);
    using DriverPeer = decltype(&cuCtxEnablePeerAccess);
    using DriverIpc = decltype(&cuIpcGetMemHandle);
    using DriverPeerCopy = decltype(&cuMemcpyPeer);

    static_assert(std::is_pointer<RuntimeReset>::value, "runtime reset declaration missing");
    static_assert(std::is_pointer<RuntimePeer>::value, "runtime peer declaration missing");
    static_assert(std::is_pointer<RuntimeIpc>::value, "runtime IPC declaration missing");
    static_assert(std::is_pointer<RuntimePeerCopy>::value, "runtime peer-copy declaration missing");
    static_assert(std::is_pointer<DriverReset>::value, "driver reset declaration missing");
    static_assert(std::is_pointer<DriverPeer>::value, "driver peer declaration missing");
    static_assert(std::is_pointer<DriverIpc>::value, "driver IPC declaration missing");
    static_assert(std::is_pointer<DriverPeerCopy>::value, "driver peer-copy declaration missing");

    static_assert(sizeof(cufftComplex) == sizeof(float) * 2, "complex64 ABI mismatch");
    static_assert(std::is_pointer<cublasHandle_t>::value, "BLAS handle declaration missing");
    static_assert(std::is_pointer<cudnnHandle_t>::value, "DNN handle declaration missing");
    static_assert(std::is_pointer<cusolverDnHandle_t>::value, "SOLVER handle declaration missing");
    static_assert(std::is_pointer<cusparseHandle_t>::value, "SPARSE handle declaration missing");
    static_assert(std::is_pointer<curandGenerator_t>::value, "RAND handle declaration missing");
}
