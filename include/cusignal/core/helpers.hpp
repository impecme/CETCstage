#pragma once

#include <stdexcept>
#include <type_traits>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace core
    {

        /**
         * @brief 计算形状对应的展平元素总数。
         *
         * @param shape 张量形状。
         * @return 全部维度乘积；若形状为空则返回 0。
         */
        inline std::size_t shape_product(const Shape &shape)
        {
            if (shape.empty())
            {
                return 0;
            }

            std::size_t total = 1;
            for (std::size_t dim : shape)
            {
                total *= dim;
            }
            return total;
        }

        /**
         * @brief 构造通用张量。
         *
         * @tparam T 张量元素类型。
         * @param shape 张量形状。
         * @param value 初始填充值。
         * @return 形状为 shape 的张量。
         */
        template <typename T>
        inline Tensor<T> make_tensor(const Shape &shape, const T &value = T{})
        {
            Tensor<T> tensor;
            tensor.shape = shape;
            tensor.values.assign(shape_product(shape), value);
            return tensor;
        }

        /**
         * @brief 构造一维实数信号。
         *
         * @param size 信号长度。
         * @param value 初始值。
         * @return 长度为 size 的实数信号。
         */
        inline RealSignal make_real_signal(std::size_t size, Scalar value = 0.0f)
        {
            return RealSignal(size, value);
        }

        /**
         * @brief 构造一维复数信号。
         *
         * @param size 信号长度。
         * @param value 初始值。
         * @return 长度为 size 的复数信号。
         */
        inline ComplexSignal make_complex_signal(
            std::size_t size,
            const Complex &value = Complex(0.0f, 0.0f))
        {
            return ComplexSignal(size, value);
        }

        /**
         * @brief 构造二维实数矩阵。
         *
         * @param rows 行数。
         * @param cols 列数。
         * @param value 初始值。
         * @return 大小为 rows x cols 的实数矩阵。
         */
        inline RealMatrix make_real_matrix(
            std::size_t rows,
            std::size_t cols,
            Scalar value = 0.0f)
        {
            return RealMatrix(rows, RealSignal(cols, value));
        }

        /**
         * @brief 构造二维复数矩阵。
         *
         * @param rows 行数。
         * @param cols 列数。
         * @param value 初始值。
         * @return 大小为 rows x cols 的复数矩阵。
         */
        inline ComplexMatrix make_complex_matrix(
            std::size_t rows,
            std::size_t cols,
            const Complex &value = Complex(0.0f, 0.0f))
        {
            return ComplexMatrix(rows, ComplexSignal(cols, value));
        }

        /**
         * @brief 构造 N 维实数张量。
         *
         * @param shape 张量形状。
         * @param value 初始值。
         * @return 实数张量。
         */
        inline RealArray make_real_array(const Shape &shape, Scalar value = 0.0f)
        {
            return make_tensor<Scalar>(shape, value);
        }

        /**
         * @brief 构造 N 维复数张量。
         *
         * @param shape 张量形状。
         * @param value 初始值。
         * @return 复数张量。
         */
        inline ComplexArray make_complex_array(
            const Shape &shape,
            const Complex &value = Complex(0.0f, 0.0f))
        {
            return make_tensor<Complex>(shape, value);
        }

        /**
         * @brief 构造 N 维整型张量。
         *
         * @param shape 张量形状。
         * @param value 初始值。
         * @return 整型张量。
         */
        inline IndexArray make_index_array(const Shape &shape, int value = 0)
        {
            return make_tensor<int>(shape, value);
        }

        /**
         * @brief 构造一维实数 device 信号。
         *
         * @param size 信号长度。
         * @param value 初始值。
         * @return 长度为 size 的 device 实数信号。
         */
        inline CudaRealSignal make_cuda_real_signal(std::size_t size, Scalar value = 0.0f)
        {
            if (value == 0.0f)
            {
                return CudaRealSignal(size, true);
            }
            return CudaRealSignal::from_host(make_real_signal(size, value));
        }

        /**
         * @brief 构造一维复数 device 信号。
         *
         * @param size 信号长度。
         * @param value 初始值。
         * @return 长度为 size 的 device 复数信号。
         */
        inline CudaComplexSignal make_cuda_complex_signal(
            std::size_t size,
            const Complex &value = Complex(0.0f, 0.0f))
        {
            if (value == Complex(0.0f, 0.0f))
            {
                return CudaComplexSignal(size, true);
            }
            return CudaComplexSignal::from_host(make_complex_signal(size, value));
        }

        /**
         * @brief 构造一维整型 device 索引序列。
         *
         * @param size 序列长度。
         * @param value 初始值。
         * @return 长度为 size 的 device 整型信号。
         */
        inline CudaIndexSignal make_cuda_index_signal(std::size_t size, int value = 0)
        {
            if (value == 0)
            {
                return CudaIndexSignal(size, true);
            }
            return CudaIndexSignal::from_host(IndexVector(size, value));
        }

        /**
         * @brief 构造 N 维实数 device 张量。
         *
         * @param shape 张量形状。
         * @param value 初始值。
         * @return 实数 device 张量。
         */
        inline CudaRealArray make_cuda_real_array(const Shape &shape, Scalar value = 0.0f)
        {
            if (value == 0.0f)
            {
                return CudaRealArray(shape, true);
            }
            return CudaRealArray::from_host(make_real_array(shape, value));
        }

        /**
         * @brief 构造 N 维复数 device 张量。
         *
         * @param shape 张量形状。
         * @param value 初始值。
         * @return 复数 device 张量。
         */
        inline CudaComplexArray make_cuda_complex_array(
            const Shape &shape,
            const Complex &value = Complex(0.0f, 0.0f))
        {
            if (value == Complex(0.0f, 0.0f))
            {
                return CudaComplexArray(shape, true);
            }
            return CudaComplexArray::from_host(make_complex_array(shape, value));
        }

        /**
         * @brief 构造 N 维整型 device 张量。
         *
         * @param shape 张量形状。
         * @param value 初始值。
         * @return 整型 device 张量。
         */
        inline CudaIndexArray make_cuda_index_array(const Shape &shape, int value = 0)
        {
            if (value == 0)
            {
                return CudaIndexArray(shape, true);
            }
            return CudaIndexArray::from_host(make_index_array(shape, value));
        }

        /**
         * @brief 获取实数矩阵行数。
         *
         * @param matrix 输入矩阵。
         * @return 行数。
         */
        inline std::size_t row_count(const RealMatrix &matrix)
        {
            return matrix.size();
        }

        /**
         * @brief 获取实数矩阵列数。
         *
         * @param matrix 输入矩阵。
         * @return 列数；空矩阵返回 0。
         */
        inline std::size_t column_count(const RealMatrix &matrix)
        {
            return matrix.empty() ? 0 : matrix.front().size();
        }

        /**
         * @brief 获取复数矩阵行数。
         *
         * @param matrix 输入矩阵。
         * @return 行数。
         */
        inline std::size_t row_count(const ComplexMatrix &matrix)
        {
            return matrix.size();
        }

        /**
         * @brief 获取复数矩阵列数。
         *
         * @param matrix 输入矩阵。
         * @return 列数；空矩阵返回 0。
         */
        inline std::size_t column_count(const ComplexMatrix &matrix)
        {
            return matrix.empty() ? 0 : matrix.front().size();
        }

        /**
         * @brief 生成与参考实数信号等长的零值信号。
         *
         * @param signal 参考信号。
         * @return 同长度的实数信号。
         */
        inline RealSignal make_real_like(const RealSignal &signal)
        {
            return make_real_signal(signal.size());
        }

        /**
         * @brief 生成与参考复数信号等长的零值信号。
         *
         * @param signal 参考信号。
         * @return 同长度的复数信号。
         */
        inline ComplexSignal make_complex_like(const ComplexSignal &signal)
        {
            return make_complex_signal(signal.size());
        }

        /**
         * @brief 生成与参考 device 实数信号等长的零值 signal。
         *
         * @param signal 参考信号。
         * @return 同长度的 device 实数信号。
         */
        inline CudaRealSignal make_cuda_real_like(const CudaRealSignal &signal)
        {
            return make_cuda_real_signal(signal.size());
        }

        /**
         * @brief 生成与参考 device 复数信号等长的零值 signal。
         *
         * @param signal 参考信号。
         * @return 同长度的 device 复数信号。
         */
        inline CudaComplexSignal make_cuda_complex_like(const CudaComplexSignal &signal)
        {
            return make_cuda_complex_signal(signal.size());
        }

        /**
         * @brief 生成与参考 device 整型信号等长的零值 signal。
         *
         * @param signal 参考信号。
         * @return 同长度的 device 整型信号。
         */
        inline CudaIndexSignal make_cuda_index_like(const CudaIndexSignal &signal)
        {
            return make_cuda_index_signal(signal.size());
        }

        /**
         * @brief 生成与参考实数矩阵同形状的零值矩阵。
         *
         * @param matrix 参考矩阵。
         * @return 同形状实数矩阵。
         */
        inline RealMatrix make_real_matrix_like(const RealMatrix &matrix)
        {
            return make_real_matrix(row_count(matrix), column_count(matrix));
        }

        /**
         * @brief 生成与参考复数矩阵同形状的零值矩阵。
         *
         * @param matrix 参考矩阵。
         * @return 同形状复数矩阵。
         */
        inline ComplexMatrix make_complex_matrix_like(const ComplexMatrix &matrix)
        {
            return make_complex_matrix(row_count(matrix), column_count(matrix));
        }

        /**
         * @brief 生成与参考张量同形状的零值张量。
         *
         * @tparam T 元素类型。
         * @param tensor 参考张量。
         * @return 同形状张量。
         */
        template <typename T>
        inline Tensor<T> make_tensor_like(const Tensor<T> &tensor)
        {
            return make_tensor<T>(tensor.shape);
        }

        /**
         * @brief 生成与参考实数张量同形状的零值张量。
         *
         * @param tensor 参考张量。
         * @return 同形状实数张量。
         */
        inline RealArray make_real_array_like(const RealArray &tensor)
        {
            return make_real_array(tensor.shape);
        }

        /**
         * @brief 生成与参考复数张量同形状的零值张量。
         *
         * @param tensor 参考张量。
         * @return 同形状复数张量。
         */
        inline ComplexArray make_complex_array_like(const ComplexArray &tensor)
        {
            return make_complex_array(tensor.shape);
        }

        /**
         * @brief 生成与参考 device 实数张量同形状的零值张量。
         *
         * @param tensor 参考张量。
         * @return 同形状 device 实数张量。
         */
        inline CudaRealArray make_cuda_real_array_like(const CudaRealArray &tensor)
        {
            return make_cuda_real_array(tensor.shape());
        }

        /**
         * @brief 生成与参考 device 复数张量同形状的零值张量。
         *
         * @param tensor 参考张量。
         * @return 同形状 device 复数张量。
         */
        inline CudaComplexArray make_cuda_complex_array_like(const CudaComplexArray &tensor)
        {
            return make_cuda_complex_array(tensor.shape());
        }

        /**
         * @brief 生成与参考 device 整型张量同形状的零值张量。
         *
         * @param tensor 参考张量。
         * @return 同形状 device 整型张量。
         */
        inline CudaIndexArray make_cuda_index_array_like(const CudaIndexArray &tensor)
        {
            return make_cuda_index_array(tensor.shape());
        }

        /**
         * @brief 将负轴索引规范化到 `[0, rank)`。
         *
         * @param axis 输入轴。
         * @param rank 总维度数。
         * @return 规范化后的轴索引。
         * @throws std::out_of_range 当 axis 超出范围时抛出异常。
         */
        inline std::size_t normalize_axis(int axis, std::size_t rank)
        {
            if (rank == 0)
            {
                throw std::out_of_range("cannot normalize axis for rank-0 tensor");
            }

            const int signed_rank = static_cast<int>(rank);
            const int normalized = axis < 0 ? axis + signed_rank : axis;
            if (normalized < 0 || normalized >= signed_rank)
            {
                throw std::out_of_range("axis is out of range for tensor rank");
            }
            return static_cast<std::size_t>(normalized);
        }

        /**
         * @brief 读取指定轴长度。
         *
         * @tparam T 元素类型。
         * @param tensor 输入张量。
         * @param axis 轴索引。
         * @return 该轴长度。
         */
        template <typename T>
        inline std::size_t axis_size(const Tensor<T> &tensor, int axis)
        {
            return tensor.shape[normalize_axis(axis, tensor.rank())];
        }

        /**
         * @brief 读取指定 axis 的 device 张量长度。
         *
         * @tparam T 元素类型。
         * @param tensor 输入 device 张量。
         * @param axis 轴索引。
         * @return 该轴长度。
         */
        template <typename T>
        inline std::size_t axis_size(const DeviceArray<T> &tensor, int axis)
        {
            return tensor.shape()[normalize_axis(axis, tensor.rank())];
        }

        /**
         * @brief 构造将某一轴替换为新长度后的形状。
         *
         * @param shape 原形状。
         * @param axis 目标轴。
         * @param new_size 新长度。
         * @return 更新后的形状。
         */
        inline Shape replace_axis_size(const Shape &shape, int axis, std::size_t new_size)
        {
            Shape updated = shape;
            updated[normalize_axis(axis, updated.size())] = new_size;
            return updated;
        }

        /**
         * @brief 从一维实数信号构造 rank-1 张量。
         *
         * @param signal 输入信号。
         * @return 对应的一维实数张量。
         */
        inline RealArray as_real_array(const RealSignal &signal)
        {
            RealArray tensor;
            tensor.shape = Shape{signal.size()};
            tensor.values = signal;
            return tensor;
        }

        /**
         * @brief 从一维复数信号构造 rank-1 张量。
         *
         * @param signal 输入信号。
         * @return 对应的一维复数张量。
         */
        inline ComplexArray as_complex_array(const ComplexSignal &signal)
        {
            ComplexArray tensor;
            tensor.shape = Shape{signal.size()};
            tensor.values = signal;
            return tensor;
        }

        /**
         * @brief 将 host/device 双态实数信号归一为 device 信号。
         *
         * @param signal 输入规格。
         * @param storage 当输入为 host 时用于承接上传后的临时 device 信号。
         * @return 可直接参与 CUDA 计算的 device 信号引用。
         */
        inline const CudaRealSignal &as_device_signal(
            const RealSignalLike &signal,
            CudaRealSignal &storage)
        {
            if (const auto *device = std::get_if<CudaRealSignal>(&signal))
            {
                return *device;
            }
            storage.copy_from(std::get<RealSignal>(signal));
            return storage;
        }

        /**
         * @brief 将 host/device 双态复数信号归一为 device 信号。
         *
         * @param signal 输入规格。
         * @param storage 当输入为 host 时用于承接上传后的临时 device 信号。
         * @return 可直接参与 CUDA 计算的 device 信号引用。
         */
        inline const CudaComplexSignal &as_device_signal(
            const ComplexSignalLike &signal,
            CudaComplexSignal &storage)
        {
            if (const auto *device = std::get_if<CudaComplexSignal>(&signal))
            {
                return *device;
            }
            storage.copy_from(std::get<ComplexSignal>(signal));
            return storage;
        }

        /**
         * @brief 将 host/device 双态整型信号归一为 device 信号。
         *
         * @param signal 输入规格。
         * @param storage 当输入为 host 时用于承接上传后的临时 device 信号。
         * @return 可直接参与 CUDA 计算的 device 信号引用。
         */
        inline const CudaIndexSignal &as_device_signal(
            const IndexSignalLike &signal,
            CudaIndexSignal &storage)
        {
            if (const auto *device = std::get_if<CudaIndexSignal>(&signal))
            {
                return *device;
            }
            storage.copy_from(std::get<IndexVector>(signal));
            return storage;
        }

        /**
         * @brief 将 host/device 双态实数张量归一为 device 张量。
         *
         * @param tensor 输入规格。
         * @param storage 当输入为 host 时用于承接上传后的临时 device 张量。
         * @return 可直接参与 CUDA 计算的 device 张量引用。
         */
        inline const CudaRealArray &as_device_array(
            const RealArrayLike &tensor,
            CudaRealArray &storage)
        {
            if (const auto *device = std::get_if<CudaRealArray>(&tensor))
            {
                return *device;
            }
            storage.copy_from(std::get<RealArray>(tensor));
            return storage;
        }

        /**
         * @brief 将 host/device 双态复数张量归一为 device 张量。
         *
         * @param tensor 输入规格。
         * @param storage 当输入为 host 时用于承接上传后的临时 device 张量。
         * @return 可直接参与 CUDA 计算的 device 张量引用。
         */
        inline const CudaComplexArray &as_device_array(
            const ComplexArrayLike &tensor,
            CudaComplexArray &storage)
        {
            if (const auto *device = std::get_if<CudaComplexArray>(&tensor))
            {
                return *device;
            }
            storage.copy_from(std::get<ComplexArray>(tensor));
            return storage;
        }

        /**
         * @brief 将 host/device 双态整型张量归一为 device 张量。
         *
         * @param tensor 输入规格。
         * @param storage 当输入为 host 时用于承接上传后的临时 device 张量。
         * @return 可直接参与 CUDA 计算的 device 张量引用。
         */
        inline const CudaIndexArray &as_device_array(
            const IndexArrayLike &tensor,
            CudaIndexArray &storage)
        {
            if (const auto *device = std::get_if<CudaIndexArray>(&tensor))
            {
                return *device;
            }
            storage.copy_from(std::get<IndexArray>(tensor));
            return storage;
        }

    } // namespace core
} // namespace cusignal
