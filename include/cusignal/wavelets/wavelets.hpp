#pragma once

#include <string>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace wavelets
        {

            /**
             * @brief 构造正交镜像滤波器系数。
             *
             * @param hk 输入低通滤波器系数。
             * @return 与 `hk` 等长的镜像滤波器系数。
             */
            core::RealSignal qmf(const core::RealSignal &hk);

            /**
             * @brief 生成 Morlet 小波。
             *
             * @param points 输出点数。
             * @param w 中心角频率参数。
             * @param s 缩放参数。
             * @param complete 是否使用 complete 形式。
             * @return 长度为 `points` 的复数小波序列。
             * @throws std::invalid_argument 当 `points < 0` 或 `s <= 0` 时抛出异常。
             */
            core::ComplexSignal morlet(
                int points,
                float w = 5.0,
                float s = 1.0,
                bool complete = true);

            /**
             * @brief 生成 Ricker 小波。
             *
             * @param points 输出点数。
             * @param a 宽度参数。
             * @return 长度为 `points` 的实数小波序列。
             * @throws std::invalid_argument 当 `points < 0` 或 `a <= 0` 时抛出异常。
             */
            core::RealSignal ricker(int points, float a);

            /**
             * @brief 生成 Morlet2 小波。
             *
             * @param points 输出点数。
             * @param s 缩放参数。
             * @param w 中心角频率参数。
             * @return 长度为 `points` 的复数小波序列。
             * @throws std::invalid_argument 当 `points < 0` 或 `s <= 0` 时抛出异常。
             */
            core::ComplexSignal morlet2(int points, float s, float w = 5.0);

            /**
             * @brief 执行连续小波变换。
             *
             * @param data 输入一维实数信号。
             * @param wavelet 小波名称，本轮仅支持 `"ricker"` 与 `"morlet2"`。
             * @param widths 各尺度宽度。
             * @return 形状为 `[widths.size(), data.size()]` 的复数张量。
             * @throws std::invalid_argument 当 `wavelet` 不受支持或 `widths` 为空时抛出异常。
             * @note Python callable wavelet 本轮暂不支持。
             */
            core::ComplexArray cwt(
                const core::RealSignal &data,
                const std::string &wavelet,
                const core::RealSignal &widths);

        } // namespace wavelets
    } // namespace cpu

    namespace cuda_backend
    {
        namespace wavelets
        {

            /**
             * @brief 构造正交镜像滤波器系数。
             *
             * @param hk 输入低通滤波器系数。
             * @return 与 `hk` 等长的镜像滤波器系数。
             */
            core::CudaRealSignal qmf(const core::RealSignalLike &hk);

            /**
             * @brief 生成 Morlet 小波。
             *
             * @param points 输出点数。
             * @param w 中心角频率参数。
             * @param s 缩放参数。
             * @param complete 是否使用 complete 形式。
             * @return 长度为 `points` 的复数小波序列。
             * @throws std::invalid_argument 当 `points < 0` 或 `s <= 0` 时抛出异常。
             */
            core::CudaComplexSignal morlet(
                int points,
                float w = 5.0,
                float s = 1.0,
                bool complete = true);

            /**
             * @brief 生成 Ricker 小波。
             *
             * @param points 输出点数。
             * @param a 宽度参数。
             * @return 长度为 `points` 的实数小波序列。
             * @throws std::invalid_argument 当 `points < 0` 或 `a <= 0` 时抛出异常。
             */
            core::CudaRealSignal ricker(int points, float a);

            /**
             * @brief 生成 Morlet2 小波。
             *
             * @param points 输出点数。
             * @param s 缩放参数。
             * @param w 中心角频率参数。
             * @return 长度为 `points` 的复数小波序列。
             * @throws std::invalid_argument 当 `points < 0` 或 `s <= 0` 时抛出异常。
             */
            core::CudaComplexSignal morlet2(int points, float s, float w = 5.0);

            /**
             * @brief 执行连续小波变换。
             *
             * @param data 输入一维实数信号。
             * @param wavelet 小波名称，本轮仅支持 `"ricker"` 与 `"morlet2"`。
             * @param widths 各尺度宽度。
             * @return 形状为 `[widths.size(), data.size()]` 的复数张量。
             * @throws std::invalid_argument 当 `wavelet` 不受支持或 `widths` 为空时抛出异常。
             * @note Python callable wavelet 本轮暂不支持。
             */
            core::CudaComplexArray cwt(
                const core::RealSignalLike &data,
                const std::string &wavelet,
                const core::RealSignalLike &widths);

        } // namespace wavelets
    } // namespace cuda_backend
} // namespace cusignal
