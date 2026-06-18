#pragma once

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace windows
        {

            /**
             * @brief 根据字符串、tuple 风格参数或显式窗数组构造窗函数。
             *
             * @param window 窗函数规格，支持字符串名称、浮点 Kaiser beta、具名单参数 tuple 或显式窗数组。
             * @param nx 输出窗长度。
             * @param fftbins 为 true 时生成周期窗；为 false 时生成对称窗。
             * @return 长度为 `nx` 的实数窗序列。
             * @throws std::invalid_argument 当 `nx < 0` 或窗规格不受支持时抛出异常。
             * @note callable 形式本轮暂不支持。
             */
            core::RealSignal get_window(
                core::WindowSpec window,
                int nx,
                bool fftbins = true);

            /**
             * @brief 生成 Bartlett-Hann 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal barthann(int size, bool sym = true);

            /**
             * @brief 生成 Bartlett 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal bartlett(int size, bool sym = true);

            /**
             * @brief 生成 Blackman 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal blackman(int size, bool sym = true);

            /**
             * @brief 生成 Blackman-Harris 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal blackmanharris(int size, bool sym = true);

            /**
             * @brief 生成 Bohman 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal bohman(int size, bool sym = true);

            /**
             * @brief 生成矩形窗。
             *
             * @param size 窗长度。
             * @param sym 是否生成对称窗；矩形窗下仅保留接口语义。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal boxcar(int size, bool sym = true);

            /**
             * @brief 生成 Dolph-Chebyshev 窗。
             *
             * @param size 窗长度。
             * @param at 阻带衰减，单位 dB。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal chebwin(int size, float at, bool sym = true);

            /**
             * @brief 生成余弦窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal cosine(int size, bool sym = true);

            /**
             * @brief 生成指数窗，中心位置按上游默认规则自动推导。
             *
             * @param size 窗长度。
             * @param tau 衰减常数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal exponential(int size, float tau = 1.0, bool sym = true);

            /**
             * @brief 生成指数窗，并显式指定中心位置。
             *
             * @param size 窗长度。
             * @param center 指数窗中心位置。
             * @param tau 衰减常数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal exponential(int size, float center, float tau, bool sym);

            /**
             * @brief 生成 Flat-top 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal flattop(int size, bool sym = true);

            /**
             * @brief 生成高斯窗。
             *
             * @param size 窗长度。
             * @param std 标准差参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal gaussian(int size, float std, bool sym = true);

            /**
             * @brief 生成一般余弦窗。
             *
             * @param size 窗长度。
             * @param a 余弦加权系数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal general_cosine(
                int size,
                const core::RealSignal &a,
                bool sym = true);

            /**
             * @brief 生成一般高斯窗。
             *
             * @param size 窗长度。
             * @param p 幂指数参数。
             * @param sig 宽度参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal general_gaussian(
                int size,
                float p,
                float sig,
                bool sym = true);

            /**
             * @brief 生成一般 Hamming 窗。
             *
             * @param size 窗长度。
             * @param alpha Hamming 系数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal general_hamming(int size, float alpha, bool sym = true);

            /**
             * @brief 生成 Hamming 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal hamming(int size, bool sym = true);

            /**
             * @brief 生成 Hann 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal hann(int size, bool sym = true);

            /**
             * @brief 生成 Kaiser 窗。
             *
             * @param size 窗长度。
             * @param beta Kaiser beta 参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal kaiser(int size, float beta, bool sym = true);

            /**
             * @brief 生成 Nuttall 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal nuttall(int size, bool sym = true);

            /**
             * @brief 生成 Parzen 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal parzen(int size, bool sym = true);

            /**
             * @brief 生成 Taylor 窗。
             *
             * @param size 窗长度。
             * @param nbar 控制主瓣附近等高旁瓣数量。
             * @param sll 旁瓣电平，单位 dB。
             * @param norm 是否按峰值归一化。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal taylor(
                int size,
                int nbar = 4,
                float sll = 30.0,
                bool norm = true,
                bool sym = true);

            /**
             * @brief 生成三角窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal triang(int size, bool sym = true);

            /**
             * @brief 生成 Tukey 窗。
             *
             * @param size 窗长度。
             * @param alpha 渐变区比例参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::RealSignal tukey(int size, float alpha = 0.5, bool sym = true);

        } // namespace windows
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace windows
        {

            /**
             * @brief 根据字符串、tuple 风格参数或显式窗数组构造窗函数。
             *
             * @param window 窗函数规格，支持字符串名称、浮点 Kaiser beta、具名单参数 tuple 或显式窗数组。
             * @param nx 输出窗长度。
             * @param fftbins 为 true 时生成周期窗；为 false 时生成对称窗。
             * @return 长度为 `nx` 的实数窗序列。
             * @throws std::invalid_argument 当 `nx < 0` 或窗规格不受支持时抛出异常。
             * @note callable 形式本轮暂不支持。
             */
            core::ZxGpuRealSignal get_window(
                core::ZxGpuWindowSpec window,
                int nx,
                bool fftbins = true);

            /**
             * @brief 生成 Bartlett-Hann 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal barthann(int size, bool sym = true);

            /**
             * @brief 生成 Bartlett 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal bartlett(int size, bool sym = true);

            /**
             * @brief 生成 Blackman 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal blackman(int size, bool sym = true);

            /**
             * @brief 生成 Blackman-Harris 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal blackmanharris(int size, bool sym = true);

            /**
             * @brief 生成 Bohman 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal bohman(int size, bool sym = true);

            /**
             * @brief 生成矩形窗。
             *
             * @param size 窗长度。
             * @param sym 是否生成对称窗；矩形窗下仅保留接口语义。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal boxcar(int size, bool sym = true);

            /**
             * @brief 生成 Dolph-Chebyshev 窗。
             *
             * @param size 窗长度。
             * @param at 阻带衰减，单位 dB。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal chebwin(int size, float at, bool sym = true);

            /**
             * @brief 生成余弦窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal cosine(int size, bool sym = true);

            /**
             * @brief 生成指数窗，中心位置按上游默认规则自动推导。
             *
             * @param size 窗长度。
             * @param tau 衰减常数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal exponential(int size, float tau = 1.0, bool sym = true);

            /**
             * @brief 生成指数窗，并显式指定中心位置。
             *
             * @param size 窗长度。
             * @param center 指数窗中心位置。
             * @param tau 衰减常数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal exponential(int size, float center, float tau, bool sym);

            /**
             * @brief 生成 Flat-top 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal flattop(int size, bool sym = true);

            /**
             * @brief 生成高斯窗。
             *
             * @param size 窗长度。
             * @param std 标准差参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal gaussian(int size, float std, bool sym = true);

            /**
             * @brief 生成一般余弦窗。
             *
             * @param size 窗长度。
             * @param a 余弦加权系数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal general_cosine(
                int size,
                const core::RealSignalLike &a,
                bool sym = true);

            /**
             * @brief 生成一般高斯窗。
             *
             * @param size 窗长度。
             * @param p 幂指数参数。
             * @param sig 宽度参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal general_gaussian(
                int size,
                float p,
                float sig,
                bool sym = true);

            /**
             * @brief 生成一般 Hamming 窗。
             *
             * @param size 窗长度。
             * @param alpha Hamming 系数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal general_hamming(int size, float alpha, bool sym = true);

            /**
             * @brief 生成 Hamming 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal hamming(int size, bool sym = true);

            /**
             * @brief 生成 Hann 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal hann(int size, bool sym = true);

            /**
             * @brief 生成 Kaiser 窗。
             *
             * @param size 窗长度。
             * @param beta Kaiser beta 参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal kaiser(int size, float beta, bool sym = true);

            /**
             * @brief 生成 Nuttall 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal nuttall(int size, bool sym = true);

            /**
             * @brief 生成 Parzen 窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal parzen(int size, bool sym = true);

            /**
             * @brief 生成 Taylor 窗。
             *
             * @param size 窗长度。
             * @param nbar 控制主瓣附近等高旁瓣数量。
             * @param sll 旁瓣电平，单位 dB。
             * @param norm 是否按峰值归一化。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal taylor(
                int size,
                int nbar = 4,
                float sll = 30.0,
                bool norm = true,
                bool sym = true);

            /**
             * @brief 生成三角窗。
             *
             * @param size 窗长度。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal triang(int size, bool sym = true);

            /**
             * @brief 生成 Tukey 窗。
             *
             * @param size 窗长度。
             * @param alpha 渐变区比例参数。
             * @param sym 为 true 生成对称窗，为 false 生成周期窗。
             * @return 长度为 `size` 的实数窗序列。
             */
            core::ZxGpuRealSignal tukey(int size, float alpha = 0.5, bool sym = true);

        } // namespace windows
    } // namespace zx_gpu_backend
} // namespace cusignal
