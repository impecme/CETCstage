#pragma once

#include <string>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace filtering_api
    {

        /**
         * @brief 带最终延迟状态的滤波返回结果。
         */
        struct FilterStateResult
        {
            core::RealArray output;
            core::RealArray final_state;
        };

        /**
         * @brief ZQ500 GPU 带最终延迟状态的滤波返回结果。
         */
        struct ZxGpuFilterStateResult
        {
            core::ZxGpuRealArray output;
            core::ZxGpuRealArray final_state;
        };

        /**
         * @brief 带时间轴的重采样返回结果。
         */
        struct ResampleResult
        {
            core::RealArray output;
            core::RealSignal time;
        };

        /**
         * @brief ZQ500 GPU 带时间轴的重采样返回结果。
         */
        struct ZxGpuResampleResult
        {
            core::ZxGpuRealArray output;
            core::ZxGpuRealSignal time;
        };

        /**
         * @brief 多相信道化结果。
         */
        struct ChannelizerResult
        {
            core::ComplexArray channels;
        };

        /**
         * @brief ZQ500 GPU 多相信道化结果。
         */
        struct ZxGpuChannelizerResult
        {
            core::ZxGpuComplexArray channels;
        };

    } // namespace filtering_api

    namespace cpu
    {
        namespace filtering
        {

            /**
             * @brief 对 N 维实数输入执行 Wiener 滤波。
             *
             * @param image 输入实数张量。
             * @return 与输入同形状的滤波结果。
             */
            core::RealArray wiener(const core::RealArray &image);

            /**
             * @brief 对 N 维实数输入执行 Wiener 滤波，并显式给出窗口边长。
             *
             * @param image 输入实数张量。
             * @param mysize 标量窗口边长。
             * @param noise 噪声功率；小于 0 表示按上游默认规则估计。
             * @return 与输入同形状的滤波结果。
             * @throws std::invalid_argument 当 `mysize <= 0` 时抛出异常。
             */
            core::RealArray wiener(
                const core::RealArray &image,
                int mysize,
                float noise = -1.0);

            /**
             * @brief 对 N 维实数输入执行 Wiener 滤波，并显式给出各维窗口大小。
             *
             * @param image 输入实数张量。
             * @param mysize 各维窗口边长。
             * @param noise 噪声功率；小于 0 表示按上游默认规则估计。
             * @return 与输入同形状的滤波结果。
             * @throws std::invalid_argument 当 `mysize` 为空或 rank 不匹配时抛出异常。
             */
            core::RealArray wiener(
                const core::RealArray &image,
                const core::Shape &mysize,
                float noise = -1.0);

            /**
             * @brief 使用 FIR 系数对输入执行一维线性滤波。
             *
             * @param b FIR 分子系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @return 与输入同形状的滤波结果。
             */
            core::RealArray firfilter(
                const core::RealSignal &b,
                const core::RealArray &x,
                int axis = -1);

            /**
             * @brief 使用 FIR 系数对输入执行一维线性滤波，并返回最终延迟状态。
             *
             * @param b FIR 分子系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param zi 初始延迟状态。
             * @return 滤波输出及最终延迟状态。
             */
            filtering_api::FilterStateResult firfilter(
                const core::RealSignal &b,
                const core::RealArray &x,
                int axis,
                const core::RealArray &zi);

            /**
             * @brief 使用 FIR/IIR 系数对输入执行一维线性滤波。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @return 与输入同形状的滤波结果。
             */
            core::RealArray lfilter(
                const core::RealSignal &b,
                const core::RealSignal &a,
                const core::RealArray &x,
                int axis = -1);

            /**
             * @brief 使用 FIR/IIR 系数对输入执行一维线性滤波，并返回最终延迟状态。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param zi 初始延迟状态。
             * @return 滤波输出及最终延迟状态。
             */
            filtering_api::FilterStateResult lfilter(
                const core::RealSignal &b,
                const core::RealSignal &a,
                const core::RealArray &x,
                int axis,
                const core::RealArray &zi);

            /**
             * @brief 计算 IIR `lfilter` 的稳态初始条件。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @return 一维初始状态向量。
             */
            core::RealSignal lfilter_zi(
                const core::RealSignal &b,
                const core::RealSignal &a);

            /**
             * @brief 计算 FIR `firfilter` 的稳态初始条件。
             *
             * @param b FIR 系数。
             * @return 一维初始状态向量。
             */
            core::RealSignal firfilter_zi(const core::RealSignal &b);

            /**
             * @brief 执行前后向 FIR 滤波。
             *
             * @param b FIR 系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param padtype 边界填充方式，支持 `"odd"`、`"even"`、`"constant"`、`"none"`。
             * @param padlen 边界填充长度，负值表示按上游默认规则推导。
             * @param method 计算方法，支持 `"pad"`、`"gust"`。
             * @param irlen `gust` 方法的冲激响应长度，负值表示未显式提供。
             * @return 与输入同形状的滤波结果。
             */
            core::RealArray firfilter2(
                const core::RealSignal &b,
                const core::RealArray &x,
                int axis = -1,
                const std::string &padtype = "odd",
                int padlen = -1,
                const std::string &method = "pad",
                int irlen = -1);

            /**
             * @brief 执行前后向 IIR/FIR 滤波。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param padtype 边界填充方式，支持 `"odd"`、`"even"`、`"constant"`、`"none"`。
             * @param padlen 边界填充长度，负值表示按上游默认规则推导。
             * @param method 计算方法，支持 `"pad"`、`"gust"`。
             * @param irlen `gust` 方法的冲激响应长度，负值表示未显式提供。
             * @return 与输入同形状的滤波结果。
             */
            core::RealArray filtfilt(
                const core::RealSignal &b,
                const core::RealSignal &a,
                const core::RealArray &x,
                int axis = -1,
                const std::string &padtype = "odd",
                int padlen = -1,
                const std::string &method = "pad",
                int irlen = -1);

            /**
             * @brief 使用二阶节级联对输入执行滤波。
             *
             * @param sos 二阶节系数张量，预期形状为 `[n_sections, 6]`。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @return 与输入同形状的滤波结果。
             */
            core::RealArray sosfilt(
                const core::RealArray &sos,
                const core::RealArray &x,
                int axis = -1);

            /**
             * @brief 使用二阶节级联对输入执行滤波，并返回最终状态。
             *
             * @param sos 二阶节系数张量，预期形状为 `[n_sections, 6]`。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param zi 初始状态。
             * @return 滤波输出及最终状态。
             */
            filtering_api::FilterStateResult sosfilt(
                const core::RealArray &sos,
                const core::RealArray &x,
                int axis,
                const core::RealArray &zi);

            /**
             * @brief 对实数输入执行 Hilbert 变换。
             *
             * @param x 输入实数张量。
             * @param n FFT 点数，0 表示使用目标轴长度。
             * @param axis 变换轴。
             * @return 与输入同 rank 的复数解析信号张量。
             */
            core::ComplexArray hilbert(
                const core::RealArray &x,
                int n = 0,
                int axis = -1);

            /**
             * @brief 对二维实数输入执行二维 Hilbert 变换。
             *
             * @param x 输入二维实数张量。
             * @param n FFT 目标形状；为空表示使用输入形状。
             * @return 与输入同 rank 的复数解析信号张量。
             * @throws std::invalid_argument 当 `x` 不是二维时抛出异常。
             */
            core::ComplexArray hilbert2(
                const core::RealArray &x,
                const core::Shape &n = {});

            /**
             * @brief 沿指定轴移除线性或常量趋势。
             *
             * @param data 输入实数张量。
             * @param axis 去趋势轴。
             * @param type 趋势类型，支持 `"linear"`、`"l"`、`"constant"`、`"c"`。
             * @param bp 分段拟合断点。
             * @param overwrite_data 是否允许覆盖输入缓冲区语义。
             * @return 与输入同形状的去趋势结果。
             */
            core::RealArray detrend(
                const core::RealArray &data,
                int axis = -1,
                const std::string &type = "linear",
                const core::IndexVector &bp = {},
                bool overwrite_data = false);

            /**
             * @brief 对复数输入执行频移。
             *
             * @param x 复数输入张量。
             * @param freq 目标频移，单位 Hz。
             * @param fs 采样率，单位 Hz。
             * @return 与输入同形状的频移后复数张量。
             */
            core::ComplexArray freq_shift(
                const core::ComplexArray &x,
                float freq,
                float fs);

            /**
             * @brief 将输入信号按多相方式信道化。
             *
             * @param x 输入复数信号。
             * @param h 原型滤波器系数。
             * @param n_chans 信道数。
             * @return 信道化后的复数张量结果。
             * @throws std::invalid_argument 当 `n_chans <= 0` 时抛出异常。
             */
            filtering_api::ChannelizerResult channelize_poly(
                const core::ComplexSignal &x,
                const core::RealSignal &h,
                int n_chans);

            /**
             * @brief 对输入执行抽 decimate。
             *
             * @param x 输入实数张量。
             * @param q 抽取倍率。
             * @param n 滤波器阶数，负值表示按上游默认规则推导。
             * @param axis 抽取轴。
             * @param zero_phase 是否使用零相位策略。
             * @return 抽取后的实数张量。
             */
            core::RealArray decimate(
                const core::RealArray &x,
                int q,
                int n = -1,
                int axis = -1,
                bool zero_phase = true);

            /**
             * @brief 仅返回重采样结果。
             *
             * @param x 输入实数张量。
             * @param num 目标样本数。
             * @param axis 重采样轴。
             * @param window 频域窗规格。
             * @param domain 计算域，支持 `"time"` 与 `"freq"`。
             * @return 重采样后的实数张量。
             */
            core::RealArray resample(
                const core::RealArray &x,
                int num,
                int axis = 0,
                core::WindowSpec window = std::string(),
                const std::string &domain = "time");

            /**
             * @brief 返回重采样结果及新时间轴。
             *
             * @param x 输入实数张量。
             * @param num 目标样本数。
             * @param t 原时间轴。
             * @param axis 重采样轴。
             * @param window 频域窗规格。
             * @param domain 计算域，支持 `"time"` 与 `"freq"`。
             * @return 重采样后的张量与新时间轴。
             */
            filtering_api::ResampleResult resample(
                const core::RealArray &x,
                int num,
                const core::RealSignal &t,
                int axis = 0,
                core::WindowSpec window = std::string(),
                const std::string &domain = "time");

            /**
             * @brief 使用多相滤波执行有理比重采样。
             *
             * @param x 输入实数张量。
             * @param up 上采样倍率。
             * @param down 下采样倍率。
             * @param axis 重采样轴。
             * @param window 窗函数规格，默认使用 `("kaiser", 5.0)`。
             * @return 重采样后的实数张量。
             */
            core::RealArray resample_poly(
                const core::RealArray &x,
                int up,
                int down,
                int axis = 0,
                core::WindowSpec window = core::NamedFloatParameter{"kaiser", 5.0});

            /**
             * @brief 执行 upfirdn 操作。
             *
             * @param h FIR 系数。
             * @param x 输入实数张量。
             * @param up 上采样倍率。
             * @param down 下采样倍率。
             * @param axis 处理轴。
             * @return 处理后的实数张量。
             */
            core::RealArray upfirdn(
                const core::RealSignal &h,
                const core::RealArray &x,
                int up = 1,
                int down = 1,
                int axis = -1);

        } // namespace filtering
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace filtering
        {

            /**
             * @brief 在 ZQ500 GPU 后端对 N 维实数输入执行 Wiener 滤波。
             *
             * @param image 输入实数张量。
             * @return 与输入同形状的滤波结果。
             */
            core::ZxGpuRealArray wiener(const core::RealArrayLike &image);

            /**
             * @brief 在 ZQ500 GPU 后端对 N 维实数输入执行 Wiener 滤波，并显式给出窗口边长。
             *
             * @param image 输入实数张量。
             * @param mysize 标量窗口边长。
             * @param noise 噪声功率；小于 0 表示按上游默认规则估计。
             * @return 与输入同形状的滤波结果。
             * @throws std::invalid_argument 当 `mysize <= 0` 时抛出异常。
             */
            core::ZxGpuRealArray wiener(
                const core::RealArrayLike &image,
                int mysize,
                float noise = -1.0);

            /**
             * @brief 在 ZQ500 GPU 后端对 N 维实数输入执行 Wiener 滤波，并显式给出各维窗口大小。
             *
             * @param image 输入实数张量。
             * @param mysize 各维窗口边长。
             * @param noise 噪声功率；小于 0 表示按上游默认规则估计。
             * @return 与输入同形状的滤波结果。
             * @throws std::invalid_argument 当 `mysize` 为空或 rank 不匹配时抛出异常。
             */
            core::ZxGpuRealArray wiener(
                const core::RealArrayLike &image,
                const core::Shape &mysize,
                float noise = -1.0);

            /**
             * @brief 在 ZQ500 GPU 后端使用 FIR 系数对输入执行一维线性滤波。
             *
             * @param b FIR 分子系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @return 与输入同形状的滤波结果。
             */
            core::ZxGpuRealArray firfilter(
                const core::RealSignalLike &b,
                const core::RealArrayLike &x,
                int axis = -1);

            /**
             * @brief 在 ZQ500 GPU 后端使用 FIR 系数对输入执行一维线性滤波，并返回最终延迟状态。
             *
             * @param b FIR 分子系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param zi 初始延迟状态。
             * @return 滤波输出及最终延迟状态。
             */
            filtering_api::ZxGpuFilterStateResult firfilter(
                const core::RealSignalLike &b,
                const core::RealArrayLike &x,
                int axis,
                const core::RealArrayLike &zi);

            /**
             * @brief 在 ZQ500 GPU 后端使用 FIR/IIR 系数对输入执行一维线性滤波。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @return 与输入同形状的滤波结果。
             */
            core::ZxGpuRealArray lfilter(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a,
                const core::RealArrayLike &x,
                int axis = -1);

            /**
             * @brief 在 ZQ500 GPU 后端使用 FIR/IIR 系数对输入执行一维线性滤波，并返回最终延迟状态。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param zi 初始延迟状态。
             * @return 滤波输出及最终延迟状态。
             */
            filtering_api::ZxGpuFilterStateResult lfilter(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a,
                const core::RealArrayLike &x,
                int axis,
                const core::RealArrayLike &zi);

            /**
             * @brief 在 ZQ500 GPU 后端计算 IIR `lfilter` 的稳态初始条件。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @return 一维初始状态向量。
             */
            core::ZxGpuRealSignal lfilter_zi(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a);

            /**
             * @brief 在 ZQ500 GPU 后端计算 FIR `firfilter` 的稳态初始条件。
             *
             * @param b FIR 系数。
             * @return 一维初始状态向量。
             */
            core::ZxGpuRealSignal firfilter_zi(const core::RealSignalLike &b);

            /**
             * @brief 在 ZQ500 GPU 后端执行前后向 FIR 滤波。
             *
             * @param b FIR 系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param padtype 边界填充方式，支持 `"odd"`、`"even"`、`"constant"`、`"none"`。
             * @param padlen 边界填充长度，负值表示按上游默认规则推导。
             * @param method 计算方法，支持 `"pad"`、`"gust"`。
             * @param irlen `gust` 方法的冲激响应长度，负值表示未显式提供。
             * @return 与输入同形状的滤波结果。
             */
            core::ZxGpuRealArray firfilter2(
                const core::RealSignalLike &b,
                const core::RealArrayLike &x,
                int axis = -1,
                const std::string &padtype = "odd",
                int padlen = -1,
                const std::string &method = "pad",
                int irlen = -1);

            /**
             * @brief 在 ZQ500 GPU 后端执行前后向 IIR/FIR 滤波。
             *
             * @param b 分子系数。
             * @param a 分母系数。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param padtype 边界填充方式，支持 `"odd"`、`"even"`、`"constant"`、`"none"`。
             * @param padlen 边界填充长度，负值表示按上游默认规则推导。
             * @param method 计算方法，支持 `"pad"`、`"gust"`。
             * @param irlen `gust` 方法的冲激响应长度，负值表示未显式提供。
             * @return 与输入同形状的滤波结果。
             */
            core::ZxGpuRealArray filtfilt(
                const core::RealSignalLike &b,
                const core::RealSignalLike &a,
                const core::RealArrayLike &x,
                int axis = -1,
                const std::string &padtype = "odd",
                int padlen = -1,
                const std::string &method = "pad",
                int irlen = -1);

            /**
             * @brief 在 ZQ500 GPU 后端使用二阶节级联对输入执行滤波。
             *
             * @param sos 二阶节系数张量，预期形状为 `[n_sections, 6]`。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @return 与输入同形状的滤波结果。
             */
            core::ZxGpuRealArray sosfilt(
                const core::RealArrayLike &sos,
                const core::RealArrayLike &x,
                int axis = -1);

            /**
             * @brief 在 ZQ500 GPU 后端使用二阶节级联对输入执行滤波，并返回最终状态。
             *
             * @param sos 二阶节系数张量，预期形状为 `[n_sections, 6]`。
             * @param x 输入实数张量。
             * @param axis 滤波轴。
             * @param zi 初始状态。
             * @return 滤波输出及最终状态。
             */
            filtering_api::ZxGpuFilterStateResult sosfilt(
                const core::RealArrayLike &sos,
                const core::RealArrayLike &x,
                int axis,
                const core::RealArrayLike &zi);

            /**
             * @brief 在 ZQ500 GPU 后端对实数输入执行 Hilbert 变换。
             *
             * @param x 输入实数张量。
             * @param n FFT 点数，0 表示使用目标轴长度。
             * @param axis 变换轴。
             * @return 与输入同 rank 的复数解析信号张量。
             */
            core::ZxGpuComplexArray hilbert(
                const core::RealArrayLike &x,
                int n = 0,
                int axis = -1);

            /**
             * @brief 在 ZQ500 GPU 后端对二维实数输入执行二维 Hilbert 变换。
             *
             * @param x 输入二维实数张量。
             * @param n FFT 目标形状；为空表示使用输入形状。
             * @return 与输入同 rank 的复数解析信号张量。
             * @throws std::invalid_argument 当 `x` 不是二维时抛出异常。
             */
            core::ZxGpuComplexArray hilbert2(
                const core::RealArrayLike &x,
                const core::Shape &n = {});

            /**
             * @brief 在 ZQ500 GPU 后端沿指定轴移除线性或常量趋势。
             *
             * @param data 输入实数张量。
             * @param axis 去趋势轴。
             * @param type 趋势类型，支持 `"linear"`、`"l"`、`"constant"`、`"c"`。
             * @param bp 分段拟合断点。
             * @param overwrite_data 是否允许覆盖输入缓冲区语义。
             * @return 与输入同形状的去趋势结果。
             */
            core::ZxGpuRealArray detrend(
                const core::RealArrayLike &data,
                int axis = -1,
                const std::string &type = "linear",
                const core::IndexVector &bp = {},
                bool overwrite_data = false);

            /**
             * @brief 在 ZQ500 GPU 后端对复数输入执行频移。
             *
             * @param x 复数输入张量。
             * @param freq 目标频移，单位 Hz。
             * @param fs 采样率，单位 Hz。
             * @return 与输入同形状的频移后复数张量。
             */
            core::ZxGpuComplexArray freq_shift(
                const core::ComplexArrayLike &x,
                float freq,
                float fs);

            /**
             * @brief 在 ZQ500 GPU 后端将输入信号按多相方式信道化。
             *
             * @param x 输入复数信号。
             * @param h 原型滤波器系数。
             * @param n_chans 信道数。
             * @return 信道化后的复数张量结果。
             * @throws std::invalid_argument 当 `n_chans <= 0` 时抛出异常。
             */
            filtering_api::ZxGpuChannelizerResult channelize_poly(
                const core::ComplexSignalLike &x,
                const core::RealSignalLike &h,
                int n_chans);

            /**
             * @brief 在 ZQ500 GPU 后端对输入执行 decimate。
             *
             * @param x 输入实数张量。
             * @param q 抽取倍率。
             * @param n 滤波器阶数，负值表示按上游默认规则推导。
             * @param axis 抽取轴。
             * @param zero_phase 是否使用零相位策略。
             * @return 抽取后的实数张量。
             */
            core::ZxGpuRealArray decimate(
                const core::RealArrayLike &x,
                int q,
                int n = -1,
                int axis = -1,
                bool zero_phase = true);

            /**
             * @brief 在 ZQ500 GPU 后端仅返回重采样结果。
             *
             * @param x 输入实数张量。
             * @param num 目标样本数。
             * @param axis 重采样轴。
             * @param window 频域窗规格。
             * @param domain 计算域，支持 `"time"` 与 `"freq"`。
             * @return 重采样后的实数张量。
             */
            core::ZxGpuRealArray resample(
                const core::RealArrayLike &x,
                int num,
                int axis = 0,
                core::ZxGpuWindowSpec window = std::string(),
                const std::string &domain = "time");

            /**
             * @brief 在 ZQ500 GPU 后端返回重采样结果及新时间轴。
             *
             * @param x 输入实数张量。
             * @param num 目标样本数。
             * @param t 原时间轴。
             * @param axis 重采样轴。
             * @param window 频域窗规格。
             * @param domain 计算域，支持 `"time"` 与 `"freq"`。
             * @return 重采样后的张量与新时间轴。
             */
            filtering_api::ZxGpuResampleResult resample(
                const core::RealArrayLike &x,
                int num,
                const core::RealSignalLike &t,
                int axis = 0,
                core::ZxGpuWindowSpec window = std::string(),
                const std::string &domain = "time");

            /**
             * @brief 在 ZQ500 GPU 后端使用多相滤波执行有理比重采样。
             *
             * @param x 输入实数张量。
             * @param up 上采样倍率。
             * @param down 下采样倍率。
             * @param axis 重采样轴。
             * @param window 窗函数规格，默认使用 `("kaiser", 5.0)`。
             * @return 重采样后的实数张量。
             */
            core::ZxGpuRealArray resample_poly(
                const core::RealArrayLike &x,
                int up,
                int down,
                int axis = 0,
                core::ZxGpuWindowSpec window = core::NamedFloatParameter{"kaiser", 5.0});

            /**
             * @brief 在 ZQ500 GPU 后端执行 upfirdn 操作。
             *
             * @param h FIR 系数。
             * @param x 输入实数张量。
             * @param up 上采样倍率。
             * @param down 下采样倍率。
             * @param axis 处理轴。
             * @return 处理后的实数张量。
             */
            core::ZxGpuRealArray upfirdn(
                const core::RealSignalLike &h,
                const core::RealArrayLike &x,
                int up = 1,
                int down = 1,
                int axis = -1);

        } // namespace filtering
    } // namespace zx_gpu_backend
} // namespace cusignal
