#pragma once

#include <cuda_runtime_api.h>

#include <stdexcept>
#include <string>

namespace cusignal
{
    namespace core
    {
        namespace platform
        {
            inline constexpr const char *kPlatformName = "ZHONGKEXIN";

            inline const char *platform_name()
            {
                return kPlatformName;
            }

            inline void throw_on_zx_gpu_error(cudaError_t status, const char *what)
            {
                if (status != cudaSuccess)
                {
                    throw std::runtime_error(
                        std::string(what) + " [" + platform_name() + "]: " +
                        cudaGetErrorString(status));
                }
            }

            inline void device_malloc(void **ptr, std::size_t bytes, const char *what = "cudaMalloc")
            {
                throw_on_zx_gpu_error(cudaMalloc(ptr, bytes), what);
            }

            inline void device_free(void *ptr) noexcept
            {
                if (ptr != nullptr)
                {
                    (void)cudaFree(ptr);
                }
            }

            inline void device_memset(void *ptr, int value, std::size_t bytes, const char *what = "cudaMemset")
            {
                throw_on_zx_gpu_error(cudaMemset(ptr, value, bytes), what);
            }

            inline void copy_host_to_device(void *dst, const void *src, std::size_t bytes, const char *what = "cudaMemcpy H2D")
            {
                throw_on_zx_gpu_error(cudaMemcpy(dst, src, bytes, cudaMemcpyHostToDevice), what);
            }

            inline void copy_device_to_host(void *dst, const void *src, std::size_t bytes, const char *what = "cudaMemcpy D2H")
            {
                throw_on_zx_gpu_error(cudaMemcpy(dst, src, bytes, cudaMemcpyDeviceToHost), what);
            }

            inline int current_device()
            {
                int device_id = 0;
                throw_on_zx_gpu_error(cudaGetDevice(&device_id), "cudaGetDevice");
                return device_id;
            }

            inline void memory_info(std::size_t *free_bytes, std::size_t *total_bytes)
            {
                throw_on_zx_gpu_error(cudaMemGetInfo(free_bytes, total_bytes), "cudaMemGetInfo");
            }
        } // namespace platform
    } // namespace core
} // namespace cusignal
