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
         * @brief CUDA 一维模糊函数切片结果。
         */
        struct CudaAmbgfunCutResult
        {
            core::CudaRealSignal values;
            core::CudaRealSignal axis;
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
         * @brief CUDA 二维模糊函数结果。
         */
        struct CudaAmbgfunSurfaceResult
        {
            core::CudaRealArray values;
            core::CudaRealSignal delay_axis;
            core::CudaRealSignal doppler_axis;
        };

        /**
         * @brief 模糊函数总返回类型。
         */
        using AmbgfunResult = std::variant<AmbgfunCutResult, AmbgfunSurfaceResult>;

        /**
         * @brief CUDA 模糊函数总返回类型。
         */
        using CudaAmbgfunResult = std::variant<CudaAmbgfunCutResult, CudaAmbgfunSurfaceResult>;

        /**
         * @brief CA-CFAR 返回结果。
         */
        struct CfarResult
        {
            core::RealArray threshold;
            core::RealArray detections;
        };

        /**
         * @brief CUDA CA-CFAR 返回结果。
         */
        struct CudaCfarResult
        {
            core::CudaRealArray threshold;
            core::CudaRealArray detections;
        };

    } // namespace radartools_api

    namespace cpu
    {
        namespace radartools
        {

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

    namespace cuda_backend
    {
        namespace radartools
        {

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
            core::CudaComplexArray pulse_compression(
                const core::ComplexArrayLike &x,
                const core::ComplexSignalLike &templ,
                bool normalize = false,
                core::CudaWindowSpec window = std::string(),
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
            core::CudaComplexArray pulse_doppler(
                const core::ComplexArrayLike &x,
                core::CudaWindowSpec window = std::string(),
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
            radartools_api::CudaAmbgfunResult ambgfun(
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
            radartools_api::CudaAmbgfunResult ambgfun(
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
            radartools_api::CudaCfarResult ca_cfar(
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
            radartools_api::CudaCfarResult ca_cfar(
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
            core::CudaComplexArray mvdr(
                const core::ComplexArrayLike &x,
                const core::ComplexArrayLike &sv,
                bool calc_cov = true);

        } // namespace radartools
    } // namespace cuda_backend
} // namespace cusignal
