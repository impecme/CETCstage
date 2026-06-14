#pragma once

#include <variant>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace filter_design_api
    {

        /**
         * @brief `cmplx_sort` 的返回结果。
         */
        struct ComplexSortResult
        {
            std::variant<core::RealSignal, core::ComplexSignal> values;
            core::IndexVector indices;
        };

        /**
         * @brief CUDA `cmplx_sort` 的返回结果。
         */
        struct CudaComplexSortResult
        {
            std::variant<core::CudaRealSignal, core::CudaComplexSignal> values;
            core::CudaIndexSignal indices;
        };

    } // namespace filter_design_api

    namespace cpu
    {
        namespace filter_design
        {

            /**
             * @brief 计算 Kaiser 窗 beta 参数。
             *
             * @param attenuation 目标阻带衰减，单位 dB。
             * @return 对应的 beta 值。
             */
            float kaiser_beta(float attenuation);

            /**
             * @brief 估算 Kaiser FIR 设计的阻带衰减。
             *
             * @param numtaps 滤波器 tap 数。
             * @param width 归一化过渡带宽。
             * @return 估算得到的阻带衰减，单位 dB。
             * @throws std::invalid_argument 当 `numtaps <= 0` 或 `width <= 0` 时抛出异常。
             */
            float kaiser_atten(int numtaps, float width);

            /**
             * @brief 按幅值对实数根数组排序。
             *
             * @param p 待排序的一维实数根数组。
             * @return 排序后的根与对应原始索引。
             */
            filter_design_api::ComplexSortResult cmplx_sort(const core::RealSignal &p);

            /**
             * @brief 按幅值对复数根数组排序。
             *
             * @param p 待排序的一维复数根数组。
             * @return 排序后的根与对应原始索引。
             */
            filter_design_api::ComplexSortResult cmplx_sort(const core::ComplexSignal &p);

            /**
             * @brief 使用窗函数法设计单截止频率 FIR 滤波器。
             *
             * @param numtaps 滤波器 tap 数。
             * @param cutoff 单个截止频率。
             * @param width 近似过渡带宽；小于等于 0 表示未显式提供。
             * @param window 窗函数规格，支持字符串、参数 tuple 或显式窗数组。
             * @param pass_zero 通带是否包含直流，支持 bool 和字符串语义。
             * @param scale 是否做单位增益缩放。
             * @param nyq 已废弃的 Nyquist 频率参数；占位实现仅做保留。
             * @param fs 采样频率。
             * @return 长度为 `numtaps` 的 FIR 系数。
             * @throws std::invalid_argument 当 `numtaps <= 0` 或 `cutoff` 非法时抛出异常。
             */
            core::RealSignal firwin(
                int numtaps,
                float cutoff,
                float width = -1.0,
                core::WindowSpec window = std::string("hamming"),
                core::PassZeroSpec pass_zero = true,
                bool scale = true,
                float nyq = -1.0,
                float fs = 2.0);

            /**
             * @brief 使用窗函数法设计多截止频率 FIR 滤波器。
             *
             * @param numtaps 滤波器 tap 数。
             * @param cutoff 一维截止频率数组。
             * @param width 近似过渡带宽；小于等于 0 表示未显式提供。
             * @param window 窗函数规格，支持字符串、参数 tuple 或显式窗数组。
             * @param pass_zero 通带是否包含直流，支持 bool 和字符串语义。
             * @param scale 是否做单位增益缩放。
             * @param nyq 已废弃的 Nyquist 频率参数；占位实现仅做保留。
             * @param fs 采样频率。
             * @return 长度为 `numtaps` 的 FIR 系数。
             * @throws std::invalid_argument 当 `numtaps <= 0` 或 `cutoff` 为空时抛出异常。
             */
            core::RealSignal firwin(
                int numtaps,
                const core::RealSignal &cutoff,
                float width = -1.0,
                core::WindowSpec window = std::string("hamming"),
                core::PassZeroSpec pass_zero = true,
                bool scale = true,
                float nyq = -1.0,
                float fs = 2.0);

            /**
             * @brief 根据频率采样点和目标增益设计任意频响 FIR 滤波器。
             *
             * @param numtaps 滤波器 tap 数。
             * @param freq 频率采样点，一维数组。
             * @param gain 各采样点对应增益。
             * @param nfreqs 频域插值网格数，0 表示按上游默认规则推导。
             * @param window 窗函数规格，支持字符串、参数 tuple、浮点 Kaiser beta 或显式窗数组。
             * @param nyq 已废弃的 Nyquist 频率参数；占位实现仅做保留。
             * @param antisymmetric 是否生成反对称冲激响应。
             * @param fs 采样频率。
             * @return 长度为 `numtaps` 的 FIR 系数。
             * @throws std::invalid_argument 当 `freq` 与 `gain` 长度不一致或 `numtaps <= 0` 时抛出异常。
             */
            core::RealSignal firwin2(
                int numtaps,
                const core::RealSignal &freq,
                const core::RealSignal &gain,
                int nfreqs = 0,
                core::WindowSpec window = std::string("hamming"),
                float nyq = -1.0,
                bool antisymmetric = false,
                float fs = 2.0);

        } // namespace filter_design
    } // namespace cpu

    namespace cuda_backend
    {
        namespace filter_design
        {

            /**
             * @brief 计算 Kaiser 窗 beta 参数。
             *
             * @param attenuation 目标阻带衰减，单位 dB。
             * @return 对应的 beta 值。
             */
            float kaiser_beta(float attenuation);

            /**
             * @brief 估算 Kaiser FIR 设计的阻带衰减。
             *
             * @param numtaps 滤波器 tap 数。
             * @param width 归一化过渡带宽。
             * @return 估算得到的阻带衰减，单位 dB。
             * @throws std::invalid_argument 当 `numtaps <= 0` 或 `width <= 0` 时抛出异常。
             */
            float kaiser_atten(int numtaps, float width);

            /**
             * @brief 按幅值对实数根数组排序。
             *
             * @param p 待排序的一维实数根数组。
             * @return 排序后的根与对应原始索引。
             */
            filter_design_api::CudaComplexSortResult cmplx_sort(const core::RealSignalLike &p);

            /**
             * @brief 按幅值对复数根数组排序。
             *
             * @param p 待排序的一维复数根数组。
             * @return 排序后的根与对应原始索引。
             */
            filter_design_api::CudaComplexSortResult cmplx_sort(const core::ComplexSignalLike &p);

            /**
             * @brief 使用窗函数法设计单截止频率 FIR 滤波器。
             *
             * @param numtaps 滤波器 tap 数。
             * @param cutoff 单个截止频率。
             * @param width 近似过渡带宽；小于等于 0 表示未显式提供。
             * @param window 窗函数规格，支持字符串、参数 tuple 或显式窗数组。
             * @param pass_zero 通带是否包含直流，支持 bool 和字符串语义。
             * @param scale 是否做单位增益缩放。
             * @param nyq 已废弃的 Nyquist 频率参数；占位实现仅做保留。
             * @param fs 采样频率。
             * @return 长度为 `numtaps` 的 FIR 系数。
             * @throws std::invalid_argument 当 `numtaps <= 0` 或 `cutoff` 非法时抛出异常。
             */
            core::CudaRealSignal firwin(
                int numtaps,
                float cutoff,
                float width = -1.0,
                core::CudaWindowSpec window = std::string("hamming"),
                core::PassZeroSpec pass_zero = true,
                bool scale = true,
                float nyq = -1.0,
                float fs = 2.0);

            /**
             * @brief 使用窗函数法设计多截止频率 FIR 滤波器。
             *
             * @param numtaps 滤波器 tap 数。
             * @param cutoff 一维截止频率数组。
             * @param width 近似过渡带宽；小于等于 0 表示未显式提供。
             * @param window 窗函数规格，支持字符串、参数 tuple 或显式窗数组。
             * @param pass_zero 通带是否包含直流，支持 bool 和字符串语义。
             * @param scale 是否做单位增益缩放。
             * @param nyq 已废弃的 Nyquist 频率参数；占位实现仅做保留。
             * @param fs 采样频率。
             * @return 长度为 `numtaps` 的 FIR 系数。
             * @throws std::invalid_argument 当 `numtaps <= 0` 或 `cutoff` 为空时抛出异常。
             */
            core::CudaRealSignal firwin(
                int numtaps,
                const core::RealSignalLike &cutoff,
                float width = -1.0,
                core::CudaWindowSpec window = std::string("hamming"),
                core::PassZeroSpec pass_zero = true,
                bool scale = true,
                float nyq = -1.0,
                float fs = 2.0);

            /**
             * @brief 根据频率采样点和目标增益设计任意频响 FIR 滤波器。
             *
             * @param numtaps 滤波器 tap 数。
             * @param freq 频率采样点，一维数组。
             * @param gain 各采样点对应增益。
             * @param nfreqs 频域插值网格数，0 表示按上游默认规则推导。
             * @param window 窗函数规格，支持字符串、参数 tuple、浮点 Kaiser beta 或显式窗数组。
             * @param nyq 已废弃的 Nyquist 频率参数；占位实现仅做保留。
             * @param antisymmetric 是否生成反对称冲激响应。
             * @param fs 采样频率。
             * @return 长度为 `numtaps` 的 FIR 系数。
             * @throws std::invalid_argument 当 `freq` 与 `gain` 长度不一致或 `numtaps <= 0` 时抛出异常。
             */
            core::CudaRealSignal firwin2(
                int numtaps,
                const core::RealSignalLike &freq,
                const core::RealSignalLike &gain,
                int nfreqs = 0,
                core::CudaWindowSpec window = std::string("hamming"),
                float nyq = -1.0,
                bool antisymmetric = false,
                float fs = 2.0);

        } // namespace filter_design
    } // namespace cuda_backend
} // namespace cusignal
