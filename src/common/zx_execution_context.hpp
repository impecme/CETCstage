#pragma once

#include <cuda_runtime_api.h>

#include <cstddef>
#include <memory>
#include <string>

#include "cusignal/core/types.hpp"


// Internal ZQ500 execution helpers.  This header is deliberately kept under
// src/common: it is a backend seam, not part of the public cusignal interface.
// The implementation reuses the existing DeviceStorage cache instead of
// introducing a second allocator with a different lifetime policy.
namespace cusignal::zx_execution
{
    inline void throw_on_zx_execution_error(cudaError_t status, const char *what)
    {
        cusignal::core::platform::throw_on_zx_gpu_error(status, what);
    }

    template <typename T>
    class ReusableDeviceBuffer
    {
    public:
        ReusableDeviceBuffer() = default;

        ReusableDeviceBuffer(const ReusableDeviceBuffer &) = delete;
        ReusableDeviceBuffer &operator=(const ReusableDeviceBuffer &) = delete;
        ReusableDeviceBuffer(ReusableDeviceBuffer &&) noexcept = default;
        ReusableDeviceBuffer &operator=(ReusableDeviceBuffer &&) noexcept = default;

        ~ReusableDeviceBuffer() = default;

        void reserve(std::size_t count)
        {
            if (count <= capacity_ && storage_ != nullptr &&
                storage_->device_id == cusignal::core::platform::current_device())
            {
                return;
            }

            storage_.reset();
            capacity_ = 0;
            if (count == 0)
            {
                return;
            }

            storage_ = cusignal::core::detail::make_device_storage<T>(count);
            capacity_ = storage_ == nullptr ? 0 : storage_->capacity;
        }

        void zero(std::size_t count, const char *what = "cudaMemset")
        {
            reserve(count);
            if (count != 0)
            {
                throw_on_zx_execution_error(
                    cudaMemset(data(), 0, count * sizeof(T)),
                    what);
            }
        }

        void copy_from_host(
            const T *host,
            std::size_t count,
            const char *what = "cudaMemcpy H2D")
        {
            reserve(count);
            if (count != 0)
            {
                cusignal::core::platform::copy_host_to_device(
                    data(), host, count * sizeof(T), what);
            }
        }

        void copy_to_host(
            T *host,
            std::size_t count,
            const char *what = "cudaMemcpy D2H") const
        {
            if (count != 0)
            {
                cusignal::core::platform::copy_device_to_host(
                    host, data(), count * sizeof(T), what);
            }
        }

        void reset() noexcept
        {
            storage_.reset();
            capacity_ = 0;
        }

        T *data() noexcept
        {
            return storage_ == nullptr ? nullptr : storage_->data;
        }

        const T *data() const noexcept
        {
            return storage_ == nullptr ? nullptr : storage_->data;
        }

        T *get() noexcept
        {
            return data();
        }

        const T *get() const noexcept
        {
            return data();
        }

        std::size_t capacity() const noexcept
        {
            return capacity_;
        }

    private:
        std::shared_ptr<cusignal::core::detail::DeviceStorage<T>> storage_;
        std::size_t capacity_ = 0;
    };
} // namespace cusignal::zx_execution
