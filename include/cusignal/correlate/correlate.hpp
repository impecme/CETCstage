#pragma once

#include <string>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace correlate
        {

            /**
             * @brief 计算两个实数 N 维张量的离散互相关。
             *
             * @param in1 第一个输入张量。
             * @param in2 第二个输入张量，需与 `in1` 维度数一致。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param method 计算方式，可选 `"auto"`、`"direct"`、`"fft"`。
             * @return 互相关结果张量。
             * @throws std::invalid_argument 当 `mode`、`method` 或 rank 不合法时抛出异常。
             */
            core::RealArray correlate(
                const core::RealArray &in1,
                const core::RealArray &in2,
                const std::string &mode = "full",
                const std::string &method = "auto");

            /**
             * @brief 计算两个复数 N 维张量的离散互相关。
             *
             * @param in1 第一个输入张量。
             * @param in2 第二个输入张量，需与 `in1` 维度数一致。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param method 计算方式，可选 `"auto"`、`"direct"`、`"fft"`。
             * @return 互相关结果张量。
             * @throws std::invalid_argument 当 `mode`、`method` 或 rank 不合法时抛出异常。
             */
            core::ComplexArray correlate(
                const core::ComplexArray &in1,
                const core::ComplexArray &in2,
                const std::string &mode = "full",
                const std::string &method = "auto");

            /**
             * @brief 计算两个二维实数张量的二维互相关。
             *
             * @param in1 第一个二维输入。
             * @param in2 第二个二维输入。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param boundary 边界处理模式，可选 `"fill"`、`"wrap"`、`"symm"`。
             * @param fillvalue `boundary="fill"` 时使用的填充值。
             * @return 二维互相关结果张量。
             * @throws std::invalid_argument 当输入不是二维或模式字符串非法时抛出异常。
             */
            core::RealArray correlate2d(
                const core::RealArray &in1,
                const core::RealArray &in2,
                const std::string &mode = "full",
                const std::string &boundary = "fill",
                float fillvalue = 0.0);

            /**
             * @brief 计算两个二维复数张量的二维互相关。
             *
             * @param in1 第一个二维输入。
             * @param in2 第二个二维输入。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param boundary 边界处理模式，可选 `"fill"`、`"wrap"`、`"symm"`。
             * @param fillvalue `boundary="fill"` 时使用的填充值。
             * @return 二维互相关结果张量。
             * @throws std::invalid_argument 当输入不是二维或模式字符串非法时抛出异常。
             */
            core::ComplexArray correlate2d(
                const core::ComplexArray &in1,
                const core::ComplexArray &in2,
                const std::string &mode = "full",
                const std::string &boundary = "fill",
                float fillvalue = 0.0);

            /**
             * @brief 计算一维互相关结果对应的 lag 索引。
             *
             * @param in1_len 第一个输入长度。
             * @param in2_len 第二个输入长度。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @return 一维 lag 索引序列。
             * @throws std::invalid_argument 当长度或模式非法时抛出异常。
             */
            core::IndexVector correlation_lags(
                int in1_len,
                int in2_len,
                const std::string &mode = "full");

        } // namespace correlate
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace correlate
        {

            /**
             * @brief 计算两个实数 N 维张量的离散互相关。
             *
             * @param in1 第一个输入张量。
             * @param in2 第二个输入张量，需与 `in1` 维度数一致。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param method 计算方式，可选 `"auto"`、`"direct"`、`"fft"`。
             * @return 互相关结果张量。
             * @throws std::invalid_argument 当 `mode`、`method` 或 rank 不合法时抛出异常。
             */
            core::ZxGpuRealArray correlate(
                const core::RealArrayLike &in1,
                const core::RealArrayLike &in2,
                const std::string &mode = "full",
                const std::string &method = "auto");

            /**
             * @brief 计算两个复数 N 维张量的离散互相关。
             *
             * @param in1 第一个输入张量。
             * @param in2 第二个输入张量，需与 `in1` 维度数一致。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param method 计算方式，可选 `"auto"`、`"direct"`、`"fft"`。
             * @return 互相关结果张量。
             * @throws std::invalid_argument 当 `mode`、`method` 或 rank 不合法时抛出异常。
             */
            core::ZxGpuComplexArray correlate(
                const core::ComplexArrayLike &in1,
                const core::ComplexArrayLike &in2,
                const std::string &mode = "full",
                const std::string &method = "auto");

            /**
             * @brief 计算两个二维实数张量的二维互相关。
             *
             * @param in1 第一个二维输入。
             * @param in2 第二个二维输入。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param boundary 边界处理模式，可选 `"fill"`、`"wrap"`、`"symm"`。
             * @param fillvalue `boundary="fill"` 时使用的填充值。
             * @return 二维互相关结果张量。
             * @throws std::invalid_argument 当输入不是二维或模式字符串非法时抛出异常。
             */
            core::ZxGpuRealArray correlate2d(
                const core::RealArrayLike &in1,
                const core::RealArrayLike &in2,
                const std::string &mode = "full",
                const std::string &boundary = "fill",
                float fillvalue = 0.0);

            /**
             * @brief 计算两个二维复数张量的二维互相关。
             *
             * @param in1 第一个二维输入。
             * @param in2 第二个二维输入。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @param boundary 边界处理模式，可选 `"fill"`、`"wrap"`、`"symm"`。
             * @param fillvalue `boundary="fill"` 时使用的填充值。
             * @return 二维互相关结果张量。
             * @throws std::invalid_argument 当输入不是二维或模式字符串非法时抛出异常。
             */
            core::ZxGpuComplexArray correlate2d(
                const core::ComplexArrayLike &in1,
                const core::ComplexArrayLike &in2,
                const std::string &mode = "full",
                const std::string &boundary = "fill",
                float fillvalue = 0.0);

            /**
             * @brief 计算一维互相关结果对应的 lag 索引。
             *
             * @param in1_len 第一个输入长度。
             * @param in2_len 第二个输入长度。
             * @param mode 输出模式，可选 `"full"`、`"same"`、`"valid"`。
             * @return 一维 lag 索引序列。
             * @throws std::invalid_argument 当长度或模式非法时抛出异常。
             */
            core::ZxGpuIndexSignal correlation_lags(
                int in1_len,
                int in2_len,
                const std::string &mode = "full");

        } // namespace correlate
    } // namespace zx_gpu_backend
} // namespace cusignal
