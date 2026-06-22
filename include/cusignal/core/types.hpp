#pragma once

#include <algorithm>
#include <complex>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

#include "cusignal/core/platform_zx_gpu_compat.hpp"

#include <cuComplex.h>
#include <cuda_fp16.h>

namespace cusignal
{
    namespace core
    {
        using Float32 = float;
        using Float16 = __half;
        using Int32 = std::int32_t;
        using Int16 = std::int16_t;
        using Int8 = std::int8_t;

        static_assert(sizeof(Float32) == 4, "FP32 must occupy 4 bytes");
        static_assert(sizeof(Float16) == 2, "FP16 must occupy 2 bytes");
        static_assert(sizeof(Int32) == 4, "INT32 must occupy 4 bytes");
        static_assert(sizeof(Int16) == 2, "INT16 must occupy 2 bytes");
        static_assert(sizeof(Int8) == 1, "INT8 must occupy 1 byte");

        template <typename T>
        struct ScalarTypeTraits;

        template <>
        struct ScalarTypeTraits<Float32>
        {
            using accumulator_type = Float32;
            static constexpr const char *name = "float32";
        };

        template <>
        struct ScalarTypeTraits<Float16>
        {
            using accumulator_type = Float32;
            static constexpr const char *name = "float16";
        };

        template <>
        struct ScalarTypeTraits<Int32>
        {
            using accumulator_type = std::int64_t;
            static constexpr const char *name = "int32";
        };

        template <>
        struct ScalarTypeTraits<Int16>
        {
            using accumulator_type = Int32;
            static constexpr const char *name = "int16";
        };

        template <>
        struct ScalarTypeTraits<Int8>
        {
            using accumulator_type = Int32;
            static constexpr const char *name = "int8";
        };

        template <typename T>
        struct IsSupportedRealScalar : std::false_type
        {
        };

        template <>
        struct IsSupportedRealScalar<Float32> : std::true_type
        {
        };

        template <>
        struct IsSupportedRealScalar<Float16> : std::true_type
        {
        };

        template <>
        struct IsSupportedRealScalar<Int32> : std::true_type
        {
        };

        template <>
        struct IsSupportedRealScalar<Int16> : std::true_type
        {
        };

        template <>
        struct IsSupportedRealScalar<Int8> : std::true_type
        {
        };

        template <typename T>
        inline constexpr bool is_supported_real_scalar_v = IsSupportedRealScalar<T>::value;

        /**
         * @brief 项目默认实数标量类型，保留 FP32 兼容别名。
         */
        using Scalar = Float32;

        /**
         * @brief 项目默认复数标量类型，统一采用 FP32。
         */
        using Complex = std::complex<Float32>;

        static_assert(sizeof(Complex) == sizeof(cuFloatComplex), "complex64 host/device size mismatch");

        /**
         * @brief 通用形状描述，按各维长度顺序存放。
         */
        using Shape = std::vector<std::size_t>;

        /**
         * @brief 检查 CUDA 运行时调用返回值。
         *
         * @param status CUDA 返回状态。
         * @param what 调用说明。
         * @throws std::runtime_error 当状态非成功时抛出异常。
         */
        inline void throw_on_zx_gpu_error(cudaError_t status, const char *what)
        {
            platform::throw_on_zx_gpu_error(status, what);
        }

        /**
         * @brief 模板化张量容器，用于承接 cuSignal 中 ndarray 风格输入与输出。
         *
         * @tparam T 张量元素类型。
         */
        template <typename T>
        struct Tensor
        {
            Shape shape;
            std::vector<T> values;

            /**
             * @brief 返回张量维度数。
             *
             * @return 张量 rank。
             */
            std::size_t rank() const
            {
                return shape.size();
            }

            /**
             * @brief 返回底层元素总数。
             *
             * @return 展平后的元素数量。
             */
            std::size_t size() const
            {
                return values.size();
            }

            /**
             * @brief 判断张量是否为空。
             *
             * @return 当 shape 为空或 values 为空时返回 true。
             */
            bool empty() const
            {
                return shape.empty() || values.empty();
            }
        };

        template <typename T>
        using Signal = std::vector<T>;

        template <typename T>
        using Array = Tensor<T>;

        /**
         * @brief 一维实数信号便捷类型。
         */
        using RealSignal = Signal<Scalar>;

        using Float32Signal = Signal<Float32>;
        using Float16Signal = Signal<Float16>;
        using Int32Signal = Signal<Int32>;
        using Int16Signal = Signal<Int16>;
        using Int8Signal = Signal<Int8>;

        /**
         * @brief 一维复数信号便捷类型。
         */
        using ComplexSignal = Signal<Complex>;

        /**
         * @brief 一维整数索引序列。
         */
        using IndexVector = std::vector<int>;

        /**
         * @brief 二维实数矩阵便捷类型。
         */
        using RealMatrix = std::vector<RealSignal>;

        /**
         * @brief 二维复数矩阵便捷类型。
         */
        using ComplexMatrix = std::vector<ComplexSignal>;

        /**
         * @brief 三维实数张量便捷类型。
         */
        using RealTensor3 = std::vector<RealMatrix>;

        /**
         * @brief 通用 N 维实数张量。
         */
        using RealArray = Array<Scalar>;

        using Float32Array = Array<Float32>;
        using Float16Array = Array<Float16>;
        using Int32Array = Array<Int32>;
        using Int16Array = Array<Int16>;
        using Int8Array = Array<Int8>;

        /**
         * @brief 通用 N 维复数张量。
         */
        using ComplexArray = Array<Complex>;

        /**
         * @brief 通用 N 维整型张量。
         */
        using IndexArray = Tensor<int>;

        /**
         * @brief host 到 device 的元素存储映射。
         *
         * 默认情形下 host 与 device 使用同一标量类型；复数会单独映射到
         * CUDA 友好的 `float2` 存储。
         *
         * @tparam T host 侧元素类型。
         */
        template <typename T>
        struct DeviceValueTraits
        {
            using device_value_type = T;

            static std::vector<device_value_type> pack(const std::vector<T> &values)
            {
                return values;
            }

            static std::vector<T> unpack(const std::vector<device_value_type> &values)
            {
                return values;
            }
        };

        /**
         * @brief 复数元素的 device 存储映射。
         */
        template <>
        struct DeviceValueTraits<Complex>
        {
            using device_value_type = cuFloatComplex;

            static std::vector<device_value_type> pack(const std::vector<Complex> &values)
            {
                std::vector<device_value_type> packed(
                    values.size(),
                    make_cuFloatComplex(0.0f, 0.0f));
                for (std::size_t index = 0; index < values.size(); ++index)
                {
                    packed[index] = make_cuFloatComplex(
                        values[index].real(),
                        values[index].imag());
                }
                return packed;
            }

            static std::vector<Complex> unpack(const std::vector<device_value_type> &values)
            {
                std::vector<Complex> unpacked(values.size(), Complex(0.0f, 0.0f));
                for (std::size_t index = 0; index < values.size(); ++index)
                {
                    unpacked[index] = Complex(
                        cuCrealf(values[index]),
                        cuCimagf(values[index]));
                }
                return unpacked;
            }
        };

        /**
         * @brief 查询 host 元素对应的 device 存储类型。
         *
         * @tparam T host 侧元素类型。
         */
        template <typename T>
        using device_value_t = typename DeviceValueTraits<T>::device_value_type;

        namespace detail
        {
            struct DeviceStorageCacheStats
            {
                std::size_t allocation_calls = 0;
                std::size_t allocation_bytes = 0;
                std::size_t cache_hits = 0;
                std::size_t cache_misses = 0;
                std::size_t recycled_blocks = 0;
                std::size_t recycled_bytes = 0;
                std::size_t evicted_blocks = 0;
                std::size_t evicted_bytes = 0;
                std::size_t freed_blocks = 0;
                std::size_t freed_bytes = 0;
                std::size_t cached_blocks = 0;
                std::size_t cached_bytes = 0;
                std::size_t peak_cached_bytes = 0;
            };

            inline DeviceStorageCacheStats &device_storage_cache_stats()
            {
                thread_local DeviceStorageCacheStats *stats = new DeviceStorageCacheStats();
                return *stats;
            }

            inline std::size_t env_size_or_default(const char *name, std::size_t default_value)
            {
                const char *value = std::getenv(name);
                if (value == nullptr || *value == '\0')
                {
                    return default_value;
                }
                char *end = nullptr;
                const unsigned long long parsed = std::strtoull(value, &end, 10);
                if (end == value || parsed == 0)
                {
                    return default_value;
                }
                return static_cast<std::size_t>(parsed);
            }

            inline std::size_t max_cached_blocks()
            {
                static const std::size_t value =
                    env_size_or_default("CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS", 8);
                return value;
            }

            inline std::size_t max_cached_bytes()
            {
                static const std::size_t value =
                    env_size_or_default("CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB", 512) *
                    1024ULL * 1024ULL;
                return value;
            }

            inline std::size_t max_single_cached_bytes()
            {
                static const std::size_t value =
                    env_size_or_default("CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB", 256) *
                    1024ULL * 1024ULL;
                return value;
            }

            template <typename T>
            struct DeviceStorage
            {
                T *data = nullptr;
                std::size_t capacity = 0;
                int device_id = 0;

                ~DeviceStorage()
                {
                    if (data != nullptr)
                    {
                        platform::device_free(data);
                    }
                }
            };

            inline bool device_storage_cache_enabled()
            {
                const char *value = std::getenv("CUSIGNAL_DISABLE_DEVICE_STORAGE_CACHE");
                if (value == nullptr)
                {
                    return true;
                }
                const std::string token(value);
                return !(token == "1" || token == "true" || token == "TRUE" ||
                         token == "on" || token == "ON");
            }

            template <typename T>
            std::size_t device_storage_bytes(std::size_t capacity)
            {
                if (capacity > std::numeric_limits<std::size_t>::max() / sizeof(T))
                {
                    return std::numeric_limits<std::size_t>::max();
                }
                return capacity * sizeof(T);
            }

            template <typename T>
            struct DeviceStorageCache
            {
                std::vector<std::unique_ptr<DeviceStorage<T>>> blocks;
                std::size_t bytes = 0;
            };

            template <typename T>
            DeviceStorageCache<T> &device_storage_cache()
            {
                // Keep the cache alive until process teardown; device-owning thread_local
                // workspaces may release their last shared_ptr after this helper was first used.
                thread_local DeviceStorageCache<T> *cache = new DeviceStorageCache<T>();
                return *cache;
            }

            template <typename T>
            void trim_device_storage_cache(DeviceStorageCache<T> &cache)
            {
                const std::size_t block_limit = max_cached_blocks();
                const std::size_t byte_limit = max_cached_bytes();
                while ((!cache.blocks.empty() && cache.blocks.size() > block_limit) ||
                       cache.bytes > byte_limit)
                {
                    const std::size_t bytes =
                        device_storage_bytes<T>(cache.blocks.front()->capacity);
                    cache.bytes -= bytes;
                    auto &stats = device_storage_cache_stats();
                    stats.evicted_blocks += 1;
                    stats.evicted_bytes += bytes;
                    if (stats.cached_blocks != 0)
                    {
                        stats.cached_blocks -= 1;
                    }
                    stats.cached_bytes =
                        stats.cached_bytes >= bytes ? stats.cached_bytes - bytes : 0;
                    cache.blocks.erase(cache.blocks.begin());
                }
            }

            template <typename T>
            void recycle_device_storage(DeviceStorage<T> *storage) noexcept
            {
                if (storage == nullptr)
                {
                    return;
                }

                const std::size_t bytes = device_storage_bytes<T>(storage->capacity);
                try
                {
                    if (device_storage_cache_enabled() && storage->data != nullptr &&
                        storage->capacity != 0 && bytes <= max_single_cached_bytes())
                    {
                        auto &cache = device_storage_cache<T>();
                        cache.bytes += bytes;
                        cache.blocks.emplace_back(storage);
                        auto &stats = device_storage_cache_stats();
                        stats.recycled_blocks += 1;
                        stats.recycled_bytes += bytes;
                        stats.cached_blocks += 1;
                        stats.cached_bytes += bytes;
                        stats.peak_cached_bytes =
                            std::max(stats.peak_cached_bytes, stats.cached_bytes);
                        trim_device_storage_cache(cache);
                        return;
                    }
                }
                catch (...)
                {
                }
                auto &stats = device_storage_cache_stats();
                stats.freed_blocks += 1;
                stats.freed_bytes += bytes;
                delete storage;
            }

            template <typename T>
            inline std::shared_ptr<DeviceStorage<T>> make_device_storage(std::size_t capacity)
            {
                int device_id = 0;
                device_id = platform::current_device();

                if (device_storage_cache_enabled() && capacity != 0)
                {
                    auto &cache = device_storage_cache<T>();
                    auto best = cache.blocks.end();
                    for (auto iter = cache.blocks.begin(); iter != cache.blocks.end(); ++iter)
                    {
                        const bool fits = (*iter)->device_id == device_id &&
                                          (*iter)->capacity >= capacity;
                        if (fits && (best == cache.blocks.end() ||
                                     (*iter)->capacity < (*best)->capacity))
                        {
                            best = iter;
                        }
                    }
                    if (best != cache.blocks.end())
                    {
                        std::unique_ptr<DeviceStorage<T>> storage = std::move(*best);
                        const std::size_t bytes =
                            device_storage_bytes<T>(storage->capacity);
                        cache.bytes -= bytes;
                        cache.blocks.erase(best);
                        auto &stats = device_storage_cache_stats();
                        stats.cache_hits += 1;
                        if (stats.cached_blocks != 0)
                        {
                            stats.cached_blocks -= 1;
                        }
                        stats.cached_bytes =
                            stats.cached_bytes >= bytes ? stats.cached_bytes - bytes : 0;
                        return std::shared_ptr<DeviceStorage<T>>(
                            storage.release(),
                            recycle_device_storage<T>);
                    }
                    device_storage_cache_stats().cache_misses += 1;
                }

                std::unique_ptr<DeviceStorage<T>> storage(new DeviceStorage<T>());
                storage->device_id = device_id;
                if (capacity != 0)
                {
                    platform::device_malloc(
                        reinterpret_cast<void **>(&storage->data),
                        capacity * sizeof(T));
                    auto &stats = device_storage_cache_stats();
                    stats.allocation_calls += 1;
                    stats.allocation_bytes += capacity * sizeof(T);
                }
                storage->capacity = capacity;
                return std::shared_ptr<DeviceStorage<T>>(
                    storage.release(),
                    recycle_device_storage<T>);
            }
        } // namespace detail

        struct DeviceStorageCacheStatsSnapshot
        {
            std::size_t allocation_calls = 0;
            std::size_t allocation_bytes = 0;
            std::size_t cache_hits = 0;
            std::size_t cache_misses = 0;
            std::size_t recycled_blocks = 0;
            std::size_t recycled_bytes = 0;
            std::size_t evicted_blocks = 0;
            std::size_t evicted_bytes = 0;
            std::size_t freed_blocks = 0;
            std::size_t freed_bytes = 0;
            std::size_t cached_blocks = 0;
            std::size_t cached_bytes = 0;
            std::size_t peak_cached_bytes = 0;
            std::size_t max_cached_blocks = 0;
            std::size_t max_cached_bytes = 0;
            std::size_t max_single_cached_bytes = 0;
            bool cache_enabled = true;
        };

        inline DeviceStorageCacheStatsSnapshot device_storage_cache_stats_snapshot()
        {
            const auto &stats = detail::device_storage_cache_stats();
            DeviceStorageCacheStatsSnapshot snapshot;
            snapshot.allocation_calls = stats.allocation_calls;
            snapshot.allocation_bytes = stats.allocation_bytes;
            snapshot.cache_hits = stats.cache_hits;
            snapshot.cache_misses = stats.cache_misses;
            snapshot.recycled_blocks = stats.recycled_blocks;
            snapshot.recycled_bytes = stats.recycled_bytes;
            snapshot.evicted_blocks = stats.evicted_blocks;
            snapshot.evicted_bytes = stats.evicted_bytes;
            snapshot.freed_blocks = stats.freed_blocks;
            snapshot.freed_bytes = stats.freed_bytes;
            snapshot.cached_blocks = stats.cached_blocks;
            snapshot.cached_bytes = stats.cached_bytes;
            snapshot.peak_cached_bytes = stats.peak_cached_bytes;
            snapshot.max_cached_blocks = detail::max_cached_blocks();
            snapshot.max_cached_bytes = detail::max_cached_bytes();
            snapshot.max_single_cached_bytes = detail::max_single_cached_bytes();
            snapshot.cache_enabled = detail::device_storage_cache_enabled();
            return snapshot;
        }

        /**
         * @brief 一维 device 信号容器。
         *
         * @tparam T host 侧元素类型。
         */
        template <typename T>
        class DeviceSignal
        {
        public:
            using value_type = T;
            using device_value_type = device_value_t<T>;
            using host_container_type = std::vector<T>;

            DeviceSignal() = default;

            explicit DeviceSignal(std::size_t size, bool zero_fill = false)
            {
                resize(size, zero_fill);
            }

            explicit DeviceSignal(const host_container_type &host)
            {
                copy_from(host);
            }

            DeviceSignal &operator=(const host_container_type &host)
            {
                copy_from(host);
                return *this;
            }

            static DeviceSignal from_host(const host_container_type &host)
            {
                DeviceSignal signal;
                signal.copy_from(host);
                return signal;
            }

            void reserve(std::size_t size)
            {
                if (capacity() >= size)
                {
                    return;
                }
                storage_ = detail::make_device_storage<device_value_type>(size);
            }

            void resize(std::size_t size, bool zero_fill = false)
            {
                reserve(size);
                size_ = size;
                shape_ = size == 0 ? Shape{} : Shape{size};
                if (zero_fill && size_ != 0)
                {
                    platform::device_memset(data(), 0, size_ * sizeof(device_value_type));
                }
            }

            void clear()
            {
                size_ = 0;
                shape_.clear();
            }

            void copy_from(const host_container_type &host)
            {
                resize(host.size());
                if (host.empty())
                {
                    return;
                }

                const std::vector<device_value_type> packed = DeviceValueTraits<T>::pack(host);
                platform::copy_host_to_device(
                    data(),
                    packed.data(),
                    packed.size() * sizeof(device_value_type));
            }

            host_container_type get() const
            {
                std::vector<device_value_type> packed(size_);
                if (size_ != 0)
                {
                    platform::copy_device_to_host(
                        packed.data(),
                        data(),
                        packed.size() * sizeof(device_value_type));
                }
                return DeviceValueTraits<T>::unpack(packed);
            }

            device_value_type *data()
            {
                return storage_ != nullptr ? storage_->data : nullptr;
            }

            const device_value_type *data() const
            {
                return storage_ != nullptr ? storage_->data : nullptr;
            }

            std::size_t size() const
            {
                return size_;
            }

            std::size_t rank() const
            {
                return shape_.size();
            }

            bool empty() const
            {
                return size_ == 0;
            }

            const Shape &shape() const
            {
                return shape_;
            }

            std::size_t capacity() const
            {
                return storage_ != nullptr ? storage_->capacity : 0;
            }

        private:
            std::shared_ptr<detail::DeviceStorage<device_value_type>> storage_;
            std::size_t size_ = 0;
            Shape shape_;
        };

        /**
         * @brief N 维 device 张量容器。
         *
         * @tparam T host 侧元素类型。
         */
        template <typename T>
        class DeviceArray
        {
        public:
            using value_type = T;
            using device_value_type = device_value_t<T>;
            using host_container_type = Tensor<T>;

            DeviceArray() = default;

            explicit DeviceArray(const Shape &shape, bool zero_fill = false)
            {
                resize(shape, zero_fill);
            }

            explicit DeviceArray(const host_container_type &host)
            {
                copy_from(host);
            }

            DeviceArray &operator=(const host_container_type &host)
            {
                copy_from(host);
                return *this;
            }

            static DeviceArray from_host(const host_container_type &host)
            {
                DeviceArray array;
                array.copy_from(host);
                return array;
            }

            void reserve(std::size_t size)
            {
                if (capacity() >= size)
                {
                    return;
                }
                storage_ = detail::make_device_storage<device_value_type>(size);
            }

            void resize(const Shape &shape, bool zero_fill = false)
            {
                const std::size_t size = shape.empty() ? 0 : [&shape]() {
                    std::size_t total = 1;
                    for (std::size_t dim : shape)
                    {
                        total *= dim;
                    }
                    return total;
                }();
                reserve(size);
                shape_ = shape;
                size_ = size;
                if (zero_fill && size_ != 0)
                {
                    platform::device_memset(data(), 0, size_ * sizeof(device_value_type));
                }
            }

            void clear()
            {
                shape_.clear();
                size_ = 0;
            }

            void copy_from(const host_container_type &host)
            {
                resize(host.shape);
                if (host.values.empty())
                {
                    return;
                }

                const std::vector<device_value_type> packed = DeviceValueTraits<T>::pack(host.values);
                platform::copy_host_to_device(
                    data(),
                    packed.data(),
                    packed.size() * sizeof(device_value_type));
            }

            host_container_type get() const
            {
                host_container_type host;
                host.shape = shape_;
                std::vector<device_value_type> packed(size_);
                if (size_ != 0)
                {
                    platform::copy_device_to_host(
                        packed.data(),
                        data(),
                        packed.size() * sizeof(device_value_type));
                }
                host.values = DeviceValueTraits<T>::unpack(packed);
                return host;
            }

            device_value_type *data()
            {
                return storage_ != nullptr ? storage_->data : nullptr;
            }

            const device_value_type *data() const
            {
                return storage_ != nullptr ? storage_->data : nullptr;
            }

            std::size_t size() const
            {
                return size_;
            }

            std::size_t rank() const
            {
                return shape_.size();
            }

            bool empty() const
            {
                return shape_.empty() || size_ == 0;
            }

            const Shape &shape() const
            {
                return shape_;
            }

            std::size_t capacity() const
            {
                return storage_ != nullptr ? storage_->capacity : 0;
            }

        private:
            std::shared_ptr<detail::DeviceStorage<device_value_type>> storage_;
            Shape shape_;
            std::size_t size_ = 0;
        };

        template <typename T>
        using SignalLike = std::variant<Signal<T>, DeviceSignal<T>>;

        template <typename T>
        using ArrayLike = std::variant<Array<T>, DeviceArray<T>>;

        /**
         * @brief 一维实数 device 信号便捷类型。
         */
        using ZxGpuRealSignal = DeviceSignal<Scalar>;

        using ZxGpuFloat32Signal = DeviceSignal<Float32>;
        using ZxGpuFloat16Signal = DeviceSignal<Float16>;
        using ZxGpuInt32Signal = DeviceSignal<Int32>;
        using ZxGpuInt16Signal = DeviceSignal<Int16>;
        using ZxGpuInt8Signal = DeviceSignal<Int8>;

        /**
         * @brief 一维复数 device 信号便捷类型。
         */
        using ZxGpuComplexSignal = DeviceSignal<Complex>;

        /**
         * @brief 一维整型 device 索引序列。
         */
        using ZxGpuIndexSignal = DeviceSignal<int>;

        /**
         * @brief 通用 N 维实数 device 张量。
         */
        using ZxGpuRealArray = DeviceArray<Scalar>;

        using ZxGpuFloat32Array = DeviceArray<Float32>;
        using ZxGpuFloat16Array = DeviceArray<Float16>;
        using ZxGpuInt32Array = DeviceArray<Int32>;
        using ZxGpuInt16Array = DeviceArray<Int16>;
        using ZxGpuInt8Array = DeviceArray<Int8>;

        /**
         * @brief 通用 N 维复数 device 张量。
         */
        using ZxGpuComplexArray = DeviceArray<Complex>;

        /**
         * @brief 通用 N 维整型 device 张量。
         */
        using ZxGpuIndexArray = DeviceArray<int>;

        /**
         * @brief ZQ500 GPU API 接受的一维实数信号输入规格。
         */
        using RealSignalLike = std::variant<RealSignal, ZxGpuRealSignal>;

        /**
         * @brief ZQ500 GPU API 接受的一维复数信号输入规格。
         */
        using ComplexSignalLike = std::variant<ComplexSignal, ZxGpuComplexSignal>;

        /**
         * @brief ZQ500 GPU API 接受的一维整型索引输入规格。
         */
        using IndexSignalLike = std::variant<IndexVector, ZxGpuIndexSignal>;

        /**
         * @brief ZQ500 GPU API 接受的 N 维实数张量输入规格。
         */
        using RealArrayLike = std::variant<RealArray, ZxGpuRealArray>;

        /**
         * @brief ZQ500 GPU API 接受的 N 维复数张量输入规格。
         */
        using ComplexArrayLike = std::variant<ComplexArray, ZxGpuComplexArray>;

        /**
         * @brief ZQ500 GPU API 接受的 N 维整型张量输入规格。
         */
        using IndexArrayLike = std::variant<IndexArray, ZxGpuIndexArray>;

        /**
         * @brief 带名字的单个窗口参数，用于表达 Python 中 `(name, value)` 形式的 tuple。
         */
        struct NamedFloatParameter
        {
            std::string name;
            Scalar value = 0.0f;
        };

        /**
         * @brief 带名字的双浮点窗口参数，用于表达 Python 中 `(name, x, y)` 形式的 tuple。
         */
        struct NamedFloatPairParameter
        {
            std::string name;
            Scalar first = 0.0f;
            Scalar second = 0.0f;
        };

        /**
         * @brief Taylor 窗规格。
         */
        struct NamedTaylorParameter
        {
            std::string name;
            int nbar = 4;
            Scalar sll = 30.0f;
            bool norm = true;
        };

        /**
         * @brief 窗函数规格描述。
         *
         * 可用于 `get_window`、`periodogram`、`welch`、`spectrogram`、`stft`
         * 等接口，支持字符串名称、单浮点参数、具名单单参数 tuple、
         * 具名单双参数 tuple、Taylor 参数 tuple 和显式窗数组。
         */
        using WindowSpec =
            std::variant<
                std::string,
                Scalar,
                NamedFloatParameter,
                NamedFloatPairParameter,
                NamedTaylorParameter,
                RealSignal>;

        /**
         * @brief ZQ500 GPU 侧窗函数规格描述。
         *
         * 与 `WindowSpec` 相比，显式窗数组既可以是 host 信号，也可以是
         * device 信号。
         */
        using ZxGpuWindowSpec =
            std::variant<
                std::string,
                Scalar,
                NamedFloatParameter,
                NamedFloatPairParameter,
                NamedTaylorParameter,
                RealSignal,
                ZxGpuRealSignal>;

        /**
         * @brief `pass_zero` 规格描述。
         *
         * 支持 bool 与字符串两类公开语义。
         */
        using PassZeroSpec = std::variant<bool, std::string>;

        /**
         * @brief `detrend` 规格描述。
         *
         * 支持字符串类型和关闭去趋势的布尔值；callable 形态本轮暂不支持。
         */
        using DetrendSpec = std::variant<std::string, bool>;

        /**
         * @brief 表示“每个维度一个索引数组”的结果形式。
         */
        using AxisIndices = std::vector<IndexVector>;

        /**
         * @brief ZQ500 GPU 侧“每个维度一个索引数组”的结果形式。
         */
        using DeviceAxisIndices = std::vector<ZxGpuIndexSignal>;

        /**
         * @brief 波形函数复合输出。
         */
        template <typename SignalType>
        struct WaveformBundleTemplate
        {
            SignalType signal;
            SignalType quadrature;
            SignalType envelope;
        };

        /**
         * @brief 波形函数复合输出。
         */
        using WaveformBundle = WaveformBundleTemplate<RealSignal>;

        /**
         * @brief ZQ500 GPU 波形函数复合输出。
         */
        using ZxGpuWaveformBundle = WaveformBundleTemplate<ZxGpuRealSignal>;

        /**
         * @brief 兼容旧骨架的 CFAR 检测结果。
         */
        struct DetectionResult
        {
            IndexVector indices;
            RealSignal thresholds;
            RealSignal values;
        };

        /**
         * @brief 兼容旧骨架的模糊函数结果。
         */
        struct AmbgfunResult
        {
            RealMatrix magnitude;
            RealSignal delay_axis;
            RealSignal doppler_axis;
        };

        /**
         * @brief 兼容旧骨架的互谱密度结果。
         */
        struct CsdResult
        {
            ComplexSignal values;
            RealSignal frequencies;
        };

        /**
         * @brief 兼容旧骨架的时频结果。
         */
        struct SpectralResult
        {
            ComplexMatrix values;
            RealSignal frequencies;
            RealSignal times;
        };

        /**
         * @brief 兼容旧骨架的逆 STFT 结果。
         */
        struct IstftResult
        {
            RealSignal signal;
            RealSignal times;
        };

        /**
         * @brief 兼容旧骨架的向量强度结果。
         */
        struct VectorStrengthResult
        {
            RealSignal strengths;
            RealSignal phases;
        };

        /**
         * @brief 兼容旧骨架的多相信道化结果。
         */
        struct ChannelizerResult
        {
            ComplexMatrix channels;
        };

    } // namespace core
} // namespace cusignal
