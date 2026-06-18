#pragma once

#include <cstddef>
#include <string>
#include <variant>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace waveforms_api
    {

        /**
         * @brief 高斯脉冲的 IQ 双路返回结果。
         */
        template <typename SignalType>
        struct IqWaveformTemplate
        {
            SignalType signal;
            SignalType quadrature;
        };

        /**
         * @brief 高斯脉冲的 IQ 双路返回结果。
         */
        using IqWaveform = IqWaveformTemplate<core::RealSignal>;

        /**
         * @brief ZQ500 GPU 高斯脉冲的 IQ 双路返回结果。
         */
        using ZxGpuIqWaveform = IqWaveformTemplate<core::ZxGpuRealSignal>;

        /**
         * @brief 高斯脉冲的信号与包络双路返回结果。
         */
        template <typename SignalType>
        struct IEnvWaveformTemplate
        {
            SignalType signal;
            SignalType envelope;
        };

        /**
         * @brief 高斯脉冲的信号与包络双路返回结果。
         */
        using IEnvWaveform = IEnvWaveformTemplate<core::RealSignal>;

        /**
         * @brief ZQ500 GPU 高斯脉冲的信号与包络双路返回结果。
         */
        using ZxGpuIEnvWaveform = IEnvWaveformTemplate<core::ZxGpuRealSignal>;

        /**
         * @brief N 维单位冲激结果。
         */
        template <typename SignalType>
        struct NdRealSignalTemplate
        {
            core::Shape shape;
            SignalType values;
        };

        /**
         * @brief N 维单位冲激结果。
         */
        using NdRealSignal = NdRealSignalTemplate<core::RealSignal>;

        /**
         * @brief ZQ500 GPU N 维单位冲激结果。
         */
        using ZxGpuNdRealSignal = NdRealSignalTemplate<core::ZxGpuRealSignal>;

        /**
         * @brief chirp 的返回类型。
         *
         * `type="real"` 时返回实数波形，`type="complex"` 时返回复数波形。
         */
        using ChirpResult = std::variant<core::RealSignal, core::ComplexSignal>;

        /**
         * @brief ZQ500 GPU chirp 的返回类型。
         *
         * `type="real"` 时返回实数波形，`type="complex"` 时返回复数波形。
         */
        using ZxGpuChirpResult =
            std::variant<core::ZxGpuRealSignal, core::ZxGpuComplexSignal>;

        /**
         * @brief gausspulse 的返回类型。
         *
         * 默认返回单路实数信号；当 `retquad/retenv` 打开时返回双路或三路结果。
         */
        using GausspulseResult =
            std::variant<core::RealSignal, IqWaveform, IEnvWaveform, core::WaveformBundle>;

        /**
         * @brief ZQ500 GPU gausspulse 的返回类型。
         *
         * 默认返回单路实数信号；当 `retquad/retenv` 打开时返回双路或三路结果。
         */
        using ZxGpuGausspulseResult =
            std::variant<
                core::ZxGpuRealSignal,
                ZxGpuIqWaveform,
                ZxGpuIEnvWaveform,
                core::ZxGpuWaveformBundle>;

    } // namespace waveforms_api

    namespace cpu
    {
        namespace waveforms
        {

            /**
             * @brief 生成线性、二次、对数或双曲 chirp 波形。
             *
             * @param t 时间采样点。
             * @param f0 起始频率。
             * @param t1 参考终止时刻。
             * @param f1 `t1` 处的目标频率。
             * @param method 调频方式，支持 `linear/quadratic/logarithmic/hyperbolic` 及其别名。
             * @param phi 初始相位，单位度。
             * @param vertex_zero 二次 chirp 时抛物线顶点是否位于 `t=0`。
             * @param type 输出类型，支持 `real` 与 `complex`。
             * @return 当 `type="real"` 返回实数波形；当 `type="complex"` 返回复数波形。
             * @throws std::invalid_argument 当方法、类型或数值参数不合法时抛出异常。
             */
            waveforms_api::ChirpResult chirp(
                const core::RealSignal &t,
                float f0,
                float t1,
                float f1,
                const std::string &method = "linear",
                float phi = 0.0,
                bool vertex_zero = true,
                const std::string &type = "real");

            /**
             * @brief 生成高斯调制脉冲。
             *
             * @param t 时间采样点。
             * @param fc 中心频率。
             * @param bw 分数带宽。
             * @param bwr 参考带宽对应的 dB 电平。
             * @param tpr 截止时间参考电平，单位 dB。
             * @param retquad 是否同时返回正交分量。
             * @param retenv 是否同时返回包络。
             * @return 根据 `retquad/retenv` 返回单路、双路或三路波形结果。
             * @throws std::invalid_argument 当频率或带宽参数不合法时抛出异常。
             */
            waveforms_api::GausspulseResult gausspulse(
                const core::RealSignal &t,
                float fc = 1000.0,
                float bw = 0.5,
                float bwr = -6.0,
                float tpr = -60.0,
                bool retquad = false,
                bool retenv = false);

            /**
             * @brief 计算高斯脉冲在给定参考电平下的截止时间。
             *
             * @param t 字符串入口，当前仅支持 `"cutoff"`。
             * @param fc 中心频率。
             * @param bw 分数带宽。
             * @param bwr 参考带宽对应的 dB 电平。
             * @param tpr 截止时间参考电平，单位 dB。
             * @return 截止时间标量。
             * @throws std::invalid_argument 当入口字符串或数值参数不合法时抛出异常。
             */
            float gausspulse(
                const std::string &t,
                float fc = 1000.0,
                float bw = 0.5,
                float bwr = -6.0,
                float tpr = -60.0);

            /**
             * @brief 生成锯齿波，宽度参数为标量。
             *
             * @param t 时间采样点。
             * @param width 上升沿占完整周期的比例，范围 `[0, 1]`。
             * @return 与 `t` 等长的锯齿波序列。
             * @throws std::invalid_argument 当 `width` 不在 `[0,1]` 内时抛出异常。
             */
            core::RealSignal sawtooth(const core::RealSignal &t, float width = 1.0);

            /**
             * @brief 生成锯齿波，宽度参数按采样点逐点给定。
             *
             * @param t 时间采样点。
             * @param width 与 `t` 等长的逐点宽度比例，范围 `[0, 1]`。
             * @return 与 `t` 等长的锯齿波序列。
             * @throws std::invalid_argument 当长度不匹配或参数越界时抛出异常。
             */
            core::RealSignal sawtooth(
                const core::RealSignal &t,
                const core::RealSignal &width);

            /**
             * @brief 生成方波，占空比参数为标量。
             *
             * @param t 时间采样点。
             * @param duty 高电平占完整周期的比例，范围 `[0, 1]`。
             * @return 与 `t` 等长的方波序列。
             * @throws std::invalid_argument 当 `duty` 不在 `[0,1]` 内时抛出异常。
             */
            core::RealSignal square(const core::RealSignal &t, float duty = 0.5);

            /**
             * @brief 生成方波，占空比参数按采样点逐点给定。
             *
             * @param t 时间采样点。
             * @param duty 与 `t` 等长的逐点占空比，范围 `[0, 1]`。
             * @return 与 `t` 等长的方波序列。
             * @throws std::invalid_argument 当长度不匹配或参数越界时抛出异常。
             */
            core::RealSignal square(
                const core::RealSignal &t,
                const core::RealSignal &duty);

            /**
             * @brief 生成一维单位冲激。
             *
             * @param size 输出长度。
             * @param index 冲激所在索引。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 长度为 `size` 的单位冲激序列。
             * @throws std::invalid_argument 或 std::logic_error 当索引或 dtype 非法时抛出异常。
             */
            core::RealSignal unit_impulse(
                std::size_t size,
                std::size_t index = 0,
                const std::string &dtype = "float32");

            /**
             * @brief 生成一维单位冲激，并通过字符串规格指定冲激位置。
             *
             * @param size 输出长度。
             * @param index_spec 冲激索引规格，当前支持 `"mid"`。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 长度为 `size` 的单位冲激序列。
             * @throws std::invalid_argument 或 std::logic_error 当索引规格或 dtype 非法时抛出异常。
             */
            core::RealSignal unit_impulse(
                std::size_t size,
                const std::string &index_spec,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，默认冲激点位于原点。
             *
             * @param shape 输出形状。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::logic_error 当 dtype 非法时抛出异常。
             */
            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，并在所有维度上使用同一个标量索引。
             *
             * @param shape 输出形状。
             * @param index 每个维度使用的冲激索引。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::out_of_range 或 std::logic_error 当索引或 dtype 非法时抛出异常。
             */
            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                std::size_t index,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，并显式指定各维索引。
             *
             * @param shape 输出形状。
             * @param index 与 `shape` 同 rank 的多维索引。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::invalid_argument、std::out_of_range 或 std::logic_error 当索引或 dtype 非法时抛出异常。
             */
            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                const core::Shape &index,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，并通过字符串规格指定冲激位置。
             *
             * @param shape 输出形状。
             * @param index_spec 冲激索引规格，当前支持 `"mid"`。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::invalid_argument 或 std::logic_error 当索引规格或 dtype 非法时抛出异常。
             */
            waveforms_api::NdRealSignal unit_impulse(
                const core::Shape &shape,
                const char *index_spec,
                const std::string &dtype = "float32");

        } // namespace waveforms
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace waveforms
        {

            /**
             * @brief 生成线性、二次、对数或双曲 chirp 波形。
             *
             * @param t 时间采样点。
             * @param f0 起始频率。
             * @param t1 参考终止时刻。
             * @param f1 `t1` 处的目标频率。
             * @param method 调频方式，支持 `linear/quadratic/logarithmic/hyperbolic` 及其别名。
             * @param phi 初始相位，单位度。
             * @param vertex_zero 二次 chirp 时抛物线顶点是否位于 `t=0`。
             * @param type 输出类型，支持 `real` 与 `complex`。
             * @return 当 `type="real"` 返回实数波形；当 `type="complex"` 返回复数波形。
             * @throws std::invalid_argument 当方法、类型或数值参数不合法时抛出异常。
             */
            waveforms_api::ZxGpuChirpResult chirp(
                const core::RealSignalLike &t,
                float f0,
                float t1,
                float f1,
                const std::string &method = "linear",
                float phi = 0.0,
                bool vertex_zero = true,
                const std::string &type = "real");

            /**
             * @brief 生成高斯调制脉冲。
             *
             * @param t 时间采样点。
             * @param fc 中心频率。
             * @param bw 分数带宽。
             * @param bwr 参考带宽对应的 dB 电平。
             * @param tpr 截止时间参考电平，单位 dB。
             * @param retquad 是否同时返回正交分量。
             * @param retenv 是否同时返回包络。
             * @return 根据 `retquad/retenv` 返回单路、双路或三路波形结果。
             * @throws std::invalid_argument 当频率或带宽参数不合法时抛出异常。
             */
            waveforms_api::ZxGpuGausspulseResult gausspulse(
                const core::RealSignalLike &t,
                float fc = 1000.0,
                float bw = 0.5,
                float bwr = -6.0,
                float tpr = -60.0,
                bool retquad = false,
                bool retenv = false);

            /**
             * @brief 计算高斯脉冲在给定参考电平下的截止时间。
             *
             * @param t 字符串入口，当前仅支持 `"cutoff"`。
             * @param fc 中心频率。
             * @param bw 分数带宽。
             * @param bwr 参考带宽对应的 dB 电平。
             * @param tpr 截止时间参考电平，单位 dB。
             * @return 截止时间标量。
             * @throws std::invalid_argument 当入口字符串或数值参数不合法时抛出异常。
             */
            float gausspulse(
                const std::string &t,
                float fc = 1000.0,
                float bw = 0.5,
                float bwr = -6.0,
                float tpr = -60.0);

            /**
             * @brief 生成锯齿波，宽度参数为标量。
             *
             * @param t 时间采样点。
             * @param width 上升沿占完整周期的比例，范围 `[0, 1]`。
             * @return 与 `t` 等长的锯齿波序列。
             * @throws std::invalid_argument 当 `width` 不在 `[0,1]` 内时抛出异常。
             */
            core::ZxGpuRealSignal sawtooth(const core::RealSignalLike &t, float width = 1.0);

            /**
             * @brief 生成锯齿波，宽度参数按采样点逐点给定。
             *
             * @param t 时间采样点。
             * @param width 与 `t` 等长的逐点宽度比例，范围 `[0, 1]`。
             * @return 与 `t` 等长的锯齿波序列。
             * @throws std::invalid_argument 当长度不匹配或参数越界时抛出异常。
             */
            core::ZxGpuRealSignal sawtooth(
                const core::RealSignalLike &t,
                const core::RealSignalLike &width);

            /**
             * @brief 生成方波，占空比参数为标量。
             *
             * @param t 时间采样点。
             * @param duty 高电平占完整周期的比例，范围 `[0, 1]`。
             * @return 与 `t` 等长的方波序列。
             * @throws std::invalid_argument 当 `duty` 不在 `[0,1]` 内时抛出异常。
             */
            core::ZxGpuRealSignal square(const core::RealSignalLike &t, float duty = 0.5);

            /**
             * @brief 生成方波，占空比参数按采样点逐点给定。
             *
             * @param t 时间采样点。
             * @param duty 与 `t` 等长的逐点占空比，范围 `[0, 1]`。
             * @return 与 `t` 等长的方波序列。
             * @throws std::invalid_argument 当长度不匹配或参数越界时抛出异常。
             */
            core::ZxGpuRealSignal square(
                const core::RealSignalLike &t,
                const core::RealSignalLike &duty);

            /**
             * @brief 生成一维单位冲激。
             *
             * @param size 输出长度。
             * @param index 冲激所在索引。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 长度为 `size` 的单位冲激序列。
             * @throws std::invalid_argument 或 std::logic_error 当索引或 dtype 非法时抛出异常。
             */
            core::ZxGpuRealSignal unit_impulse(
                std::size_t size,
                std::size_t index = 0,
                const std::string &dtype = "float32");

            /**
             * @brief 生成一维单位冲激，并通过字符串规格指定冲激位置。
             *
             * @param size 输出长度。
             * @param index_spec 冲激索引规格，当前支持 `"mid"`。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 长度为 `size` 的单位冲激序列。
             * @throws std::invalid_argument 或 std::logic_error 当索引规格或 dtype 非法时抛出异常。
             */
            core::ZxGpuRealSignal unit_impulse(
                std::size_t size,
                const std::string &index_spec,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，默认冲激点位于原点。
             *
             * @param shape 输出形状。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::logic_error 当 dtype 非法时抛出异常。
             */
            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，并在所有维度上使用同一个标量索引。
             *
             * @param shape 输出形状。
             * @param index 每个维度使用的冲激索引。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::out_of_range 或 std::logic_error 当索引或 dtype 非法时抛出异常。
             */
            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                std::size_t index,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，并显式指定各维索引。
             *
             * @param shape 输出形状。
             * @param index 与 `shape` 同 rank 的多维索引。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::invalid_argument、std::out_of_range 或 std::logic_error 当索引或 dtype 非法时抛出异常。
             */
            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                const core::Shape &index,
                const std::string &dtype = "float32");

            /**
             * @brief 生成 N 维单位冲激，并通过字符串规格指定冲激位置。
             *
             * @param shape 输出形状。
             * @param index_spec 冲激索引规格，当前支持 `"mid"`。
             * @param dtype 输出 dtype 名称，本轮仅支持 `float32`。
             * @return 包含 `shape` 与展平值数组的 N 维单位冲激结果。
             * @throws std::invalid_argument 或 std::logic_error 当索引规格或 dtype 非法时抛出异常。
             */
            waveforms_api::ZxGpuNdRealSignal unit_impulse(
                const core::Shape &shape,
                const char *index_spec,
                const std::string &dtype = "float32");

        } // namespace waveforms
    } // namespace zx_gpu_backend
} // namespace cusignal
