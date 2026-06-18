#pragma once

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace bsplines
        {

            /**
             * @brief 计算输入样本处的三次 B-spline 基函数取值。
             *
             * @param x 输入坐标张量，按展平存储。
             * @return 与 `x` 同形状的实数张量。
             */
            core::RealArray cubic(const core::RealArray &x);

            /**
             * @brief 计算高斯近似 B-spline。
             *
             * @param x 输入坐标张量，按展平存储。
             * @param n B-spline 阶数，需为非负整数。
             * @return 与 `x` 同形状的实数张量。
             * @throws std::invalid_argument 当 `n < 0` 时抛出异常。
             */
            core::RealArray gauss_spline(const core::RealArray &x, int n);

            /**
             * @brief 计算输入样本处的二次 B-spline 基函数取值。
             *
             * @param x 输入坐标张量，按展平存储。
             * @return 与 `x` 同形状的实数张量。
             */
            core::RealArray quadratic(const core::RealArray &x);

        } // namespace bsplines
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace bsplines
        {

            /**
             * @brief 计算输入样本处的三次 B-spline 基函数取值。
             *
             * @param x 输入坐标张量，按展平存储。
             * @return 与 `x` 同形状的实数张量。
             */
            core::ZxGpuRealArray cubic(const core::RealArrayLike &x);

            /**
             * @brief 计算高斯近似 B-spline。
             *
             * @param x 输入坐标张量，按展平存储。
             * @param n B-spline 阶数，需为非负整数。
             * @return 与 `x` 同形状的实数张量。
             * @throws std::invalid_argument 当 `n < 0` 时抛出异常。
             */
            core::ZxGpuRealArray gauss_spline(const core::RealArrayLike &x, int n);

            /**
             * @brief 计算输入样本处的二次 B-spline 基函数取值。
             *
             * @param x 输入坐标张量，按展平存储。
             * @return 与 `x` 同形状的实数张量。
             */
            core::ZxGpuRealArray quadratic(const core::RealArrayLike &x);

        } // namespace bsplines
    } // namespace zx_gpu_backend
} // namespace cusignal
