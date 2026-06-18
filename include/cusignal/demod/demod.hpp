#pragma once

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace demod
        {

            /**
             * @brief 对复数输入执行 FM 解调。
             *
             * @param x 复数输入张量。
             * @param axis 解调所沿的轴，默认沿最后一维。
             * @return 沿 `axis` 维长度减少 1 的实数张量。
             * @throws std::out_of_range 当 `axis` 超出输入 rank 时抛出异常。
             */
            core::RealArray fm_demod(const core::ComplexArray &x, int axis = -1);

        } // namespace demod
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace demod
        {

            /**
             * @brief 对复数输入执行 FM 解调。
             *
             * @param x 复数输入张量。
             * @param axis 解调所沿的轴，默认沿最后一维。
             * @return 沿 `axis` 维长度减少 1 的实数张量。
             * @throws std::out_of_range 当 `axis` 超出输入 rank 时抛出异常。
             */
            core::ZxGpuRealArray fm_demod(const core::ComplexArrayLike &x, int axis = -1);

        } // namespace demod
    } // namespace zx_gpu_backend
} // namespace cusignal
