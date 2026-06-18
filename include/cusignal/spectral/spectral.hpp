#pragma once

#include <string>
#include <variant>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace spectral_api
    {

        /**
         * @brief 实数谱估计结果。
         */
        struct RealSpectrumResult
        {
            core::RealSignal frequencies;
            core::RealArray values;
        };

        /**
         * @brief ZQ500 GPU 实数谱估计结果。
         */
        struct ZxGpuRealSpectrumResult
        {
            core::ZxGpuRealSignal frequencies;
            core::ZxGpuRealArray values;
        };

        /**
         * @brief 复数谱估计结果。
         */
        struct ComplexSpectrumResult
        {
            core::RealSignal frequencies;
            core::ComplexArray values;
        };

        /**
         * @brief ZQ500 GPU 复数谱估计结果。
         */
        struct ZxGpuComplexSpectrumResult
        {
            core::ZxGpuRealSignal frequencies;
            core::ZxGpuComplexArray values;
        };

        /**
         * @brief spectrogram 返回结果。
         */
        struct SpectrogramResult
        {
            core::RealSignal frequencies;
            core::RealSignal times;
            std::variant<core::RealArray, core::ComplexArray> values;
        };

        /**
         * @brief ZQ500 GPU spectrogram 返回结果。
         */
        struct ZxGpuSpectrogramResult
        {
            core::ZxGpuRealSignal frequencies;
            core::ZxGpuRealSignal times;
            std::variant<core::ZxGpuRealArray, core::ZxGpuComplexArray> values;
        };

        /**
         * @brief STFT 返回结果。
         */
        struct StftResult
        {
            core::RealSignal frequencies;
            core::RealSignal times;
            core::ComplexArray values;
        };

        /**
         * @brief ZQ500 GPU STFT 返回结果。
         */
        struct ZxGpuStftResult
        {
            core::ZxGpuRealSignal frequencies;
            core::ZxGpuRealSignal times;
            core::ZxGpuComplexArray values;
        };

        /**
         * @brief iSTFT 返回结果。
         */
        struct IstftResult
        {
            core::RealSignal times;
            core::RealArray signal;
        };

        /**
         * @brief ZQ500 GPU iSTFT 返回结果。
         */
        struct ZxGpuIstftResult
        {
            core::ZxGpuRealSignal times;
            core::ZxGpuRealArray signal;
        };

        /**
         * @brief 向量强度分析返回结果。
         */
        struct VectorStrengthResult
        {
            core::RealSignal strength;
            core::RealSignal phase;
        };

        /**
         * @brief ZQ500 GPU 向量强度分析返回结果。
         */
        struct ZxGpuVectorStrengthResult
        {
            core::ZxGpuRealSignal strength;
            core::ZxGpuRealSignal phase;
        };

    } // namespace spectral_api

    namespace cpu
    {
        namespace spectral
        {

            /**
             * @brief 计算 Lomb-Scargle 周期图。
             *
             * @param x 样本时间。
             * @param y 测量值。
             * @param freqs 角频率采样点。
             * @param precenter 是否先对 `y` 去均值。
             * @param normalize 是否返回归一化周期图。
             * @return 与 `freqs` 等长的周期图序列。
             * @throws std::invalid_argument 当输入长度不一致时抛出异常。
             */
            core::RealSignal lombscargle(
                const core::RealSignal &x,
                const core::RealSignal &y,
                const core::RealSignal &freqs,
                bool precenter = false,
                bool normalize = false);

            /**
             * @brief 使用 periodogram 估计功率谱密度或功率谱。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nfft FFT 长度，0 表示使用输入长度。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @return 频率轴与实数谱值。
             * @throws std::invalid_argument 当 `scaling` 非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::RealSpectrumResult periodogram(
                const core::RealArray &x,
                float fs = 1.0,
                core::WindowSpec window = std::string("boxcar"),
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1);

            /**
             * @brief 使用 Welch 方法估计功率谱密度或功率谱。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @param average 平均模式，支持 `"mean"` 与 `"median"`。
             * @return 频率轴与实数谱值。
             * @throws std::invalid_argument 当字符串模式非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::RealSpectrumResult welch(
                const core::RealArray &x,
                float fs = 1.0,
                core::WindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1,
                const std::string &average = "mean");

            /**
             * @brief 使用 Welch 方法估计互谱密度。
             *
             * @param x 第一个输入张量。
             * @param y 第二个输入张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @param average 平均模式，支持 `"mean"` 与 `"median"`。
             * @return 频率轴与复数谱值。
             * @throws std::invalid_argument 当输入形状、字符串模式或轴不合法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::ComplexSpectrumResult csd(
                const core::RealArray &x,
                const core::RealArray &y,
                float fs = 1.0,
                core::WindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1,
                const std::string &average = "mean");

            /**
             * @brief 计算 spectrogram。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @param mode 返回模式，支持 `"psd"`、`"complex"`、`"magnitude"`、`"angle"`、`"phase"`。
             * @return 频率轴、时间轴以及实数或复数时频结果。
             * @throws std::invalid_argument 当字符串模式非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::SpectrogramResult spectrogram(
                const core::RealArray &x,
                float fs = 1.0,
                core::WindowSpec window = core::NamedFloatParameter{"tukey", 0.25},
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1,
                const std::string &mode = "psd");

            /**
             * @brief 计算短时傅里叶变换。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param boundary 边界延拓模式，支持 `"even"`、`"odd"`、`"constant"`、`"zeros"`、`"none"`。
             * @param padded 是否在末尾补零以凑整段数。
             * @param axis 计算所沿的轴。
             * @return STFT 的频率轴、时间轴和复数时频矩阵。
             * @throws std::invalid_argument 当字符串模式非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::StftResult stft(
                const core::RealArray &x,
                float fs = 1.0,
                core::WindowSpec window = std::string("hann"),
                int nperseg = 256,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = false,
                bool return_onesided = true,
                const std::string &boundary = "zeros",
                bool padded = true,
                int axis = -1);

            /**
             * @brief 执行逆短时傅里叶变换。
             *
             * @param zxx 输入 STFT 张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param input_onesided 输入是否为单边谱。
             * @param boundary 输入是否来自启用边界延拓的 STFT。
             * @param time_axis 时间轴位置。
             * @param freq_axis 频率轴位置。
             * @return 重建信号及时间轴。
             */
            spectral_api::IstftResult istft(
                const core::ComplexArray &zxx,
                float fs = 1.0,
                core::WindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                bool input_onesided = true,
                bool boundary = true,
                int time_axis = -1,
                int freq_axis = -2);

            /**
             * @brief 估计两个信号的幅值平方相干函数。
             *
             * @param x 第一个输入张量。
             * @param y 第二个输入张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param axis 计算所沿的轴。
             * @return 频率轴与实数相干函数。
             * @throws std::invalid_argument 当输入形状、字符串模式或轴不合法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::RealSpectrumResult coherence(
                const core::RealArray &x,
                const core::RealArray &y,
                float fs = 1.0,
                core::WindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                int axis = -1);

            /**
             * @brief 计算单个周期标量下的向量强度。
             *
             * @param events 事件时刻序列。
             * @param period 周期标量。
             * @return 长度为 1 的向量强度与相位结果。
             * @throws std::invalid_argument 当 `period <= 0` 时抛出异常。
             */
            spectral_api::VectorStrengthResult vectorstrength(
                const core::RealSignal &events,
                float period);

            /**
             * @brief 计算多个周期下的向量强度。
             *
             * @param events 事件时刻序列。
             * @param period 周期序列。
             * @return 与 `period` 等长的向量强度与相位结果。
             * @throws std::invalid_argument 当 `period` 为空或含非正值时抛出异常。
             */
            spectral_api::VectorStrengthResult vectorstrength(
                const core::RealSignal &events,
                const core::RealSignal &period);

        } // namespace spectral
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace spectral
        {

            /**
             * @brief 计算 Lomb-Scargle 周期图。
             *
             * @param x 样本时间。
             * @param y 测量值。
             * @param freqs 角频率采样点。
             * @param precenter 是否先对 `y` 去均值。
             * @param normalize 是否返回归一化周期图。
             * @return 与 `freqs` 等长的周期图序列。
             * @throws std::invalid_argument 当输入长度不一致时抛出异常。
             */
            core::ZxGpuRealSignal lombscargle(
                const core::RealSignalLike &x,
                const core::RealSignalLike &y,
                const core::RealSignalLike &freqs,
                bool precenter = false,
                bool normalize = false);

            /**
             * @brief 使用 periodogram 估计功率谱密度或功率谱。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nfft FFT 长度，0 表示使用输入长度。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @return 频率轴与实数谱值。
             * @throws std::invalid_argument 当 `scaling` 非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::ZxGpuRealSpectrumResult periodogram(
                const core::RealArrayLike &x,
                float fs = 1.0,
                core::ZxGpuWindowSpec window = std::string("boxcar"),
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1);

            /**
             * @brief 使用 Welch 方法估计功率谱密度或功率谱。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @param average 平均模式，支持 `"mean"` 与 `"median"`。
             * @return 频率轴与实数谱值。
             * @throws std::invalid_argument 当字符串模式非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::ZxGpuRealSpectrumResult welch(
                const core::RealArrayLike &x,
                float fs = 1.0,
                core::ZxGpuWindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1,
                const std::string &average = "mean");

            /**
             * @brief 使用 Welch 方法估计互谱密度。
             *
             * @param x 第一个输入张量。
             * @param y 第二个输入张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @param average 平均模式，支持 `"mean"` 与 `"median"`。
             * @return 频率轴与复数谱值。
             * @throws std::invalid_argument 当输入形状、字符串模式或轴不合法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::ZxGpuComplexSpectrumResult csd(
                const core::RealArrayLike &x,
                const core::RealArrayLike &y,
                float fs = 1.0,
                core::ZxGpuWindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1,
                const std::string &average = "mean");

            /**
             * @brief 计算 spectrogram。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param scaling 标度模式，支持 `"density"` 与 `"spectrum"`。
             * @param axis 计算所沿的轴。
             * @param mode 返回模式，支持 `"psd"`、`"complex"`、`"magnitude"`、`"angle"`、`"phase"`。
             * @return 频率轴、时间轴以及实数或复数时频结果。
             * @throws std::invalid_argument 当字符串模式非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::ZxGpuSpectrogramResult spectrogram(
                const core::RealArrayLike &x,
                float fs = 1.0,
                core::ZxGpuWindowSpec window = core::NamedFloatParameter{"tukey", 0.25},
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                bool return_onesided = true,
                const std::string &scaling = "density",
                int axis = -1,
                const std::string &mode = "psd");

            /**
             * @brief 计算短时傅里叶变换。
             *
             * @param x 输入信号张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param return_onesided 是否返回单边谱。
             * @param boundary 边界延拓模式，支持 `"even"`、`"odd"`、`"constant"`、`"zeros"`、`"none"`。
             * @param padded 是否在末尾补零以凑整段数。
             * @param axis 计算所沿的轴。
             * @return STFT 的频率轴、时间轴和复数时频矩阵。
             * @throws std::invalid_argument 当字符串模式非法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::ZxGpuStftResult stft(
                const core::RealArrayLike &x,
                float fs = 1.0,
                core::ZxGpuWindowSpec window = std::string("hann"),
                int nperseg = 256,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = false,
                bool return_onesided = true,
                const std::string &boundary = "zeros",
                bool padded = true,
                int axis = -1);

            /**
             * @brief 执行逆短时傅里叶变换。
             *
             * @param zxx 输入 STFT 张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param input_onesided 输入是否为单边谱。
             * @param boundary 输入是否来自启用边界延拓的 STFT。
             * @param time_axis 时间轴位置。
             * @param freq_axis 频率轴位置。
             * @return 重建信号及时间轴。
             */
            spectral_api::ZxGpuIstftResult istft(
                const core::ComplexArrayLike &zxx,
                float fs = 1.0,
                core::ZxGpuWindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                bool input_onesided = true,
                bool boundary = true,
                int time_axis = -1,
                int freq_axis = -2);

            /**
             * @brief 估计两个信号的幅值平方相干函数。
             *
             * @param x 第一个输入张量。
             * @param y 第二个输入张量。
             * @param fs 采样频率。
             * @param window 窗函数规格。
             * @param nperseg 每段长度，0 表示按上游默认规则推导。
             * @param noverlap 段间重叠长度，负值表示按上游默认规则推导。
             * @param nfft FFT 长度，0 表示按上游默认规则推导。
             * @param detrend 去趋势规格，支持字符串或 `false`。
             * @param axis 计算所沿的轴。
             * @return 频率轴与实数相干函数。
             * @throws std::invalid_argument 当输入形状、字符串模式或轴不合法时抛出异常。
             * @note Python callable detrend 本轮暂不支持。
             */
            spectral_api::ZxGpuRealSpectrumResult coherence(
                const core::RealArrayLike &x,
                const core::RealArrayLike &y,
                float fs = 1.0,
                core::ZxGpuWindowSpec window = std::string("hann"),
                int nperseg = 0,
                int noverlap = -1,
                int nfft = 0,
                core::DetrendSpec detrend = std::string("constant"),
                int axis = -1);

            /**
             * @brief 计算单个周期标量下的向量强度。
             *
             * @param events 事件时刻序列。
             * @param period 周期标量。
             * @return 长度为 1 的向量强度与相位结果。
             * @throws std::invalid_argument 当 `period <= 0` 时抛出异常。
             */
            spectral_api::ZxGpuVectorStrengthResult vectorstrength(
                const core::RealSignalLike &events,
                float period);

            /**
             * @brief 计算多个周期下的向量强度。
             *
             * @param events 事件时刻序列。
             * @param period 周期序列。
             * @return 与 `period` 等长的向量强度与相位结果。
             * @throws std::invalid_argument 当 `period` 为空或含非正值时抛出异常。
             */
            spectral_api::ZxGpuVectorStrengthResult vectorstrength(
                const core::RealSignalLike &events,
                const core::RealSignalLike &period);

        } // namespace spectral
    } // namespace zx_gpu_backend
} // namespace cusignal
