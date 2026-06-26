#pragma once

#include <string>
#include <variant>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace radartools_api
    {

        /**
         * @brief 一维模糊函数切片结果。
         */
        struct AmbgfunCutResult
        {
            core::RealSignal values;
            core::RealSignal axis;
        };

        /**
         * @brief ZQ500 GPU 一维模糊函数切片结果。
         */
        struct ZxGpuAmbgfunCutResult
        {
            core::ZxGpuRealSignal values;
            core::ZxGpuRealSignal axis;
        };

        /**
         * @brief 二维模糊函数结果。
         */
        struct AmbgfunSurfaceResult
        {
            core::RealArray values;
            core::RealSignal delay_axis;
            core::RealSignal doppler_axis;
        };

        /**
         * @brief ZQ500 GPU 二维模糊函数结果。
         */
        struct ZxGpuAmbgfunSurfaceResult
        {
            core::ZxGpuRealArray values;
            core::ZxGpuRealSignal delay_axis;
            core::ZxGpuRealSignal doppler_axis;
        };

        /**
         * @brief 模糊函数总返回类型。
         */
        using AmbgfunResult = std::variant<AmbgfunCutResult, AmbgfunSurfaceResult>;

        /**
         * @brief ZQ500 GPU 模糊函数总返回类型。
         */
        using ZxGpuAmbgfunResult = std::variant<ZxGpuAmbgfunCutResult, ZxGpuAmbgfunSurfaceResult>;

        /**
         * @brief CA-CFAR 返回结果。
         */
        struct CfarResult
        {
            core::RealArray threshold;
            core::RealArray detections;
        };

        /**
         * @brief ZQ500 GPU CA-CFAR 返回结果。
         */
        struct ZxGpuCfarResult
        {
            core::ZxGpuRealArray threshold;
            core::ZxGpuRealArray detections;
        };

        /**
         * @brief 二维距离-多普勒峰值检测结果。
         */
        struct DetectionSummary
        {
            bool found = false;
            int range_bin = -1;
            int doppler_bin = -1;
            float doppler_hz = 0.0f;
            float power = 0.0f;
        };

        /**
         * @brief ZQ500 GPU 二维距离-多普勒峰值检测结果。
         *
         * `indices` 依次保存 found、range bin、doppler bin，`values` 保存 doppler Hz 和 power。
         */
        struct ZxGpuDetectionSummary
        {
            core::ZxGpuIndexSignal indices;
            core::ZxGpuRealSignal values;

            DetectionSummary get() const
            {
                const core::IndexVector host_indices = indices.get();
                const core::RealSignal host_values = values.get();
                DetectionSummary output;
                if (host_indices.size() == 3 && host_values.size() == 2)
                {
                    output.found = host_indices[0] != 0;
                    output.range_bin = host_indices[1];
                    output.doppler_bin = host_indices[2];
                    output.doppler_hz = host_values[0];
                    output.power = host_values[1];
                }
                return output;
            }
        };

    } // namespace radartools_api

    namespace cpu
    {
        namespace radartools
        {

            /**
             * @brief 对复数二维矩阵的行维执行 FFT shift。
             * @param input rank-2 complex64 输入，形状为行数乘列数。
             * @return 形状不变的 complex64 矩阵，行维循环平移一半长度。
             * @throws std::invalid_argument 当输入不是二维时抛出异常。
             */
            core::ComplexArray fftshift_rows(const core::ComplexArray &input);

            /**
             * @brief 计算 complex64 矩阵的逐元素模平方功率图。
             * @param input 任意形状 complex64 输入。
             * @return 与输入形状一致的 FP32 功率图。
             */
            core::RealArray power_map(const core::ComplexArray &input);

            /**
             * @brief 在二维检测掩码内选择功率最大的距离-多普勒单元。
             * @param power rank-2 FP32 功率图。
             * @param detections 与功率图同形状的 FP32 检测掩码，大于 0.5 表示候选。
             * @param nfft 多普勒 FFT 长度，必须为正数。
             * @param prf 脉冲重复频率，必须为正数。
             * @return 峰值是否存在、距离/多普勒 bin、多普勒频率及功率。
             * @throws std::invalid_argument 当 shape 或采样参数非法时抛出异常。
             */
            radartools_api::DetectionSummary detect_peak(
                const core::RealArray &power,
                const core::RealArray &detections,
                int nfft,
                float prf);

            /**
             * @brief 执行脉冲压缩。
             *
             * @param x 接收信号矩阵或二维张量。
             * @param templ 发射模板信号。
             * @param normalize 是否先对模板做归一化。
             * @param window 频域窗规格；传空字符串表示不加窗。
             * @param nfft FFT 长度，0 表示按输入长度推导。
             * @return 与输入脉冲数匹配的复数二维张量。
             * @throws std::invalid_argument 当输入 rank 非法时抛出异常。
             * @note Python callable window 本轮暂不支持。
             */
            core::ComplexArray pulse_compression(
                const core::ComplexArray &x,
                const core::ComplexSignal &templ,
                bool normalize = false,
                core::WindowSpec window = std::string(),
                int nfft = 0);

            /**
             * @brief 执行脉冲多普勒处理。
             *
             * @param x 接收信号矩阵或二维张量。
             * @param window 频域窗规格；传空字符串表示不加窗。
             * @param nfft FFT 长度，0 表示按输入长度推导。
             * @return 脉冲-多普勒复数矩阵。
             * @throws std::invalid_argument 当输入 rank 非法时抛出异常。
             * @note Python callable window 本轮暂不支持。
             */
            core::ComplexArray pulse_doppler(
                const core::ComplexArray &x,
                core::WindowSpec window = std::string(),
                int nfft = 0);

            /**
             * @brief 计算归一化模糊函数。
             *
             * @param x 第一组脉冲波形。
             * @param fs 采样率。
             * @param prf 脉冲重复频率。
             * @param cut 截取模式，支持 `"2d"`、`"delay"`、`"doppler"`。
             * @param cut_value 一维切片时的延迟或多普勒位置。
             * @return 当 `cut="2d"` 返回二维结果，否则返回一维切片结果。
             * @throws std::invalid_argument 当 `cut` 非法或采样参数非正时抛出异常。
             */
            radartools_api::AmbgfunResult ambgfun(
                const core::ComplexSignal &x,
                float fs,
                float prf,
                const std::string &cut = "2d",
                float cut_value = 0.0);

            /**
             * @brief 计算双输入模糊函数。
             *
             * @param x 第一组脉冲波形。
             * @param y 第二组脉冲波形。
             * @param fs 采样率。
             * @param prf 脉冲重复频率。
             * @param cut 截取模式，支持 `"2d"`、`"delay"`、`"doppler"`。
             * @param cut_value 一维切片时的延迟或多普勒位置。
             * @return 当 `cut="2d"` 返回二维结果，否则返回一维切片结果。
             * @throws std::invalid_argument 当 `cut` 非法、长度为空或采样参数非正时抛出异常。
             */
            radartools_api::AmbgfunResult ambgfun(
                const core::ComplexSignal &x,
                const core::ComplexSignal &y,
                float fs,
                float prf,
                const std::string &cut = "2d",
                float cut_value = 0.0);

            /**
             * @brief 计算 CA-CFAR 的 alpha 系数。
             *
             * @param pfa 虚警概率。
             * @param cells 参考单元总数。
             * @return CA-CFAR alpha 系数。
             * @throws std::invalid_argument 当 `pfa` 不在 `(0,1)` 或 `cells <= 0` 时抛出异常。
             */
            float cfar_alpha(float pfa, int cells);

            /**
             * @brief 对一维输入执行 CA-CFAR 检测。
             *
             * @param array 待检测输入。
             * @param guard_cells 单侧保护单元数。
             * @param reference_cells 单侧参考单元数。
             * @param pfa 虚警概率。
             * @return 阈值张量和检测结果张量。
             * @throws std::invalid_argument 当窗口配置与输入长度不匹配时抛出异常。
             */
            radartools_api::CfarResult ca_cfar(
                const core::RealArray &array,
                int guard_cells,
                int reference_cells,
                float pfa = 1e-3);

            /**
             * @brief 对二维输入执行 CA-CFAR 检测。
             *
             * @param array 待检测二维输入。
             * @param guard_cells 两个维度的单侧保护单元数。
             * @param reference_cells 两个维度的单侧参考单元数。
             * @param pfa 虚警概率。
             * @return 阈值张量和检测结果张量。
             * @throws std::invalid_argument 当输入不是二维或窗口配置不合法时抛出异常。
             */
            radartools_api::CfarResult ca_cfar(
                const core::RealArray &array,
                const core::Shape &guard_cells,
                const core::Shape &reference_cells,
                float pfa = 1e-3);

            /**
             * @brief 计算 MVDR 波束形成权重。
             *
             * @param x 输入接收信号矩阵或协方差矩阵。
             * @param sv 导向向量。
             * @param calc_cov 为 true 时先从 `x` 估计协方差矩阵。
             * @return 长度与 `sv` 相匹配的复数权重张量。
             * @throws std::invalid_argument 当输入维度不匹配时抛出异常。
             */
            core::ComplexArray mvdr(
                const core::ComplexArray &x,
                const core::ComplexArray &sv,
                bool calc_cov = true);

        } // namespace radartools
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace radartools
        {

            /**
             * @brief 在 ZQ500 上对复数二维矩阵的行维执行 FFT shift。
             * @param input host/device rank-2 complex64 输入。
             * @return 设备驻留、形状不变的 complex64 矩阵。
             * @throws std::invalid_argument 当输入不是二维时抛出异常。
             */
            core::ZxGpuComplexArray fftshift_rows(const core::ComplexArrayLike &input);

            /**
             * @brief 在 ZQ500 上计算 complex64 输入的逐元素模平方功率图。
             * @param input host/device complex64 输入。
             * @return 设备驻留且与输入同形状的 FP32 功率图。
             */
            core::ZxGpuRealArray power_map(const core::ComplexArrayLike &input);

            /**
             * @brief 在 ZQ500 上从二维检测掩码选择最大功率单元。
             * @param power host/device rank-2 FP32 功率图。
             * @param detections 与功率图同形状的 host/device FP32 检测掩码。
             * @param nfft 多普勒 FFT 长度，必须为正数。
             * @param prf 脉冲重复频率，必须为正数。
             * @return 设备驻留结果；调用 `.get()` 后得到与 CPU 接口语义一致的标量结果。
             * @throws std::invalid_argument 当 shape 或采样参数非法时抛出异常。
             */
            radartools_api::ZxGpuDetectionSummary detect_peak(
                const core::RealArrayLike &power,
                const core::RealArrayLike &detections,
                int nfft,
                float prf);

            /**
             * @brief 执行脉冲压缩。
             *
             * @param x 接收信号矩阵或二维张量。
             * @param templ 发射模板信号。
             * @param normalize 是否先对模板做归一化。
             * @param window 频域窗规格；传空字符串表示不加窗。
             * @param nfft FFT 长度，0 表示按输入长度推导。
             * @return 与输入脉冲数匹配的复数二维张量。
             * @throws std::invalid_argument 当输入 rank 非法时抛出异常。
             * @note Python callable window 本轮暂不支持。
             */
            core::ZxGpuComplexArray pulse_compression(
                const core::ComplexArrayLike &x,
                const core::ComplexSignalLike &templ,
                bool normalize = false,
                core::ZxGpuWindowSpec window = std::string(),
                int nfft = 0);

            /**
             * @brief 执行脉冲多普勒处理。
             *
             * @param x 接收信号矩阵或二维张量。
             * @param window 频域窗规格；传空字符串表示不加窗。
             * @param nfft FFT 长度，0 表示按输入长度推导。
             * @return 脉冲-多普勒复数矩阵。
             * @throws std::invalid_argument 当输入 rank 非法时抛出异常。
             * @note Python callable window 本轮暂不支持。
             */
            core::ZxGpuComplexArray pulse_doppler(
                const core::ComplexArrayLike &x,
                core::ZxGpuWindowSpec window = std::string(),
                int nfft = 0);

            /**
             * @brief 计算归一化模糊函数。
             *
             * @param x 第一组脉冲波形。
             * @param fs 采样率。
             * @param prf 脉冲重复频率。
             * @param cut 截取模式，支持 `"2d"`、`"delay"`、`"doppler"`。
             * @param cut_value 一维切片时的延迟或多普勒位置。
             * @return 当 `cut="2d"` 返回二维结果，否则返回一维切片结果。
             * @throws std::invalid_argument 当 `cut` 非法或采样参数非正时抛出异常。
             */
            radartools_api::ZxGpuAmbgfunResult ambgfun(
                const core::ComplexSignalLike &x,
                float fs,
                float prf,
                const std::string &cut = "2d",
                float cut_value = 0.0);

            /**
             * @brief 计算双输入模糊函数。
             *
             * @param x 第一组脉冲波形。
             * @param y 第二组脉冲波形。
             * @param fs 采样率。
             * @param prf 脉冲重复频率。
             * @param cut 截取模式，支持 `"2d"`、`"delay"`、`"doppler"`。
             * @param cut_value 一维切片时的延迟或多普勒位置。
             * @return 当 `cut="2d"` 返回二维结果，否则返回一维切片结果。
             * @throws std::invalid_argument 当 `cut` 非法、长度为空或采样参数非正时抛出异常。
             */
            radartools_api::ZxGpuAmbgfunResult ambgfun(
                const core::ComplexSignalLike &x,
                const core::ComplexSignalLike &y,
                float fs,
                float prf,
                const std::string &cut = "2d",
                float cut_value = 0.0);

            /**
             * @brief 计算 CA-CFAR 的 alpha 系数。
             *
             * @param pfa 虚警概率。
             * @param cells 参考单元总数。
             * @return CA-CFAR alpha 系数。
             * @throws std::invalid_argument 当 `pfa` 不在 `(0,1)` 或 `cells <= 0` 时抛出异常。
             */
            float cfar_alpha(float pfa, int cells);

            /**
             * @brief 对一维输入执行 CA-CFAR 检测。
             *
             * @param array 待检测输入。
             * @param guard_cells 单侧保护单元数。
             * @param reference_cells 单侧参考单元数。
             * @param pfa 虚警概率。
             * @return 阈值张量和检测结果张量。
             * @throws std::invalid_argument 当窗口配置与输入长度不匹配时抛出异常。
             */
            radartools_api::ZxGpuCfarResult ca_cfar(
                const core::RealArrayLike &array,
                int guard_cells,
                int reference_cells,
                float pfa = 1e-3);

            /**
             * @brief 对二维输入执行 CA-CFAR 检测。
             *
             * @param array 待检测二维输入。
             * @param guard_cells 两个维度的单侧保护单元数。
             * @param reference_cells 两个维度的单侧参考单元数。
             * @param pfa 虚警概率。
             * @return 阈值张量和检测结果张量。
             * @throws std::invalid_argument 当输入不是二维或窗口配置不合法时抛出异常。
             */
            radartools_api::ZxGpuCfarResult ca_cfar(
                const core::RealArrayLike &array,
                const core::Shape &guard_cells,
                const core::Shape &reference_cells,
                float pfa = 1e-3);

            /**
             * @brief 计算 MVDR 波束形成权重。
             *
             * @param x 输入接收信号矩阵或协方差矩阵。
             * @param sv 导向向量。
             * @param calc_cov 为 true 时先从 `x` 估计协方差矩阵。
             * @return 长度与 `sv` 相匹配的复数权重张量。
             * @throws std::invalid_argument 当输入维度不匹配时抛出异常。
             */
            core::ZxGpuComplexArray mvdr(
                const core::ComplexArrayLike &x,
                const core::ComplexArrayLike &sv,
                bool calc_cov = true);

        } // namespace radartools
    } // namespace zx_gpu_backend
} // namespace cusignal
