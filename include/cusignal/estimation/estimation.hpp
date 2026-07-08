#pragma once

#include <string>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace cpu
    {
        namespace estimation
        {

            /**
             * @brief 与 cuSignal `KalmanFilter` 公开形态对齐的滤波类。
             *
             * 构造后会按 `points x dim_x x 1`、`points x dim_x x dim_x` 等形状
             * 初始化状态、协方差和系统矩阵，并提供标准 Kalman predict/update 步骤。
             */
            class KalmanFilter
            {
            public:
                /**
                 * @brief 当前状态估计，形状为 `[points, dim_x, 1]`。
                 */
                core::RealArray x;

                /**
                 * @brief 当前状态协方差，形状为 `[points, dim_x, dim_x]`。
                 */
                core::RealArray P;

                /**
                 * @brief 最近一次更新使用的观测量，形状为 `[points, dim_z, 1]`。
                 */
                core::RealArray z;

                /**
                 * @brief 测量噪声协方差，形状为 `[points, dim_z, dim_z]`。
                 */
                core::RealArray R;

                /**
                 * @brief 过程噪声协方差，形状为 `[points, dim_x, dim_x]`。
                 */
                core::RealArray Q;

                /**
                 * @brief 状态转移矩阵，形状为 `[points, dim_x, dim_x]`。
                 */
                core::RealArray F;

                /**
                 * @brief 观测矩阵，形状为 `[points, dim_z, dim_x]`。
                 */
                core::RealArray H;

                /**
                 * @brief 控制矩阵，形状为 `[points, dim_x, dim_u]`。
                 */
                core::RealArray B;

                /**
                 * @brief 控制输入，形状为 `[points, dim_u, 1]`。
                 */
                core::RealArray u;

                /**
                 * @brief 淡忘因子平方，形状为 `[points, 1, 1]`。
                 */
                core::RealArray alpha_sq;

                /**
                 * @brief 构造 KalmanFilter 对象。
                 *
                 * @param dim_x 状态维度。
                 * @param dim_z 观测维度。
                 * @param dim_u 控制维度。
                 * @param points 并行跟踪点数。
                 * @param dtype 计算 dtype 名称；`"float16"` 通过 FP32 中间计算提供兼容路径。
                 * @throws std::invalid_argument 当维度非法或 dtype 不受支持时抛出异常。
                 */
                KalmanFilter(
                    int dim_x,
                    int dim_z,
                    int dim_u = 0,
                    int points = 1,
                    const std::string &dtype = "float32");

                /**
                 * @brief 执行一次预测步骤。
                 *
                 * @return 无返回值。
                 */
                void predict();

                /**
                 * @brief 使用显式控制输入执行一次预测步骤。
                 *
                 * @param control 控制输入，形状建议为 `[points, dim_u, 1]`。
                 * @return 无返回值；会缓存 `control` 到公共成员 `u`。
                 */
                void predict(const core::RealArray &control);

                /**
                 * @brief 执行一次更新步骤。
                 *
                 * @param measurement 当前观测，形状建议为 `[points, dim_z, 1]`。
                 * @return 无返回值；会缓存 `measurement` 到公共成员 `z`。
                 */
                void update(const core::RealArray &measurement);

                /**
                 * @brief 获取状态维度。
                 *
                 * @return `dim_x`。
                 */
                int dim_x() const;

                /**
                 * @brief 获取观测维度。
                 *
                 * @return `dim_z`。
                 */
                int dim_z() const;

                /**
                 * @brief 获取控制维度。
                 *
                 * @return `dim_u`。
                 */
                int dim_u() const;

                /**
                 * @brief 获取并行跟踪点数。
                 *
                 * @return `points`。
                 */
                int points() const;

                /**
                 * @brief 获取构造时声明的 dtype。
                 *
                 * @return dtype 名称。
                 */
                const std::string &dtype() const;

            private:
                int dim_x_;
                int dim_z_;
                int dim_u_;
                int points_;
                std::string dtype_;
            };

        } // namespace estimation
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace estimation
        {

            /**
             * @brief 与 cuSignal `KalmanFilter` 公开形态对齐的滤波类。
             *
             * 构造后会按 `points x dim_x x 1`、`points x dim_x x dim_x` 等形状
             * 初始化状态、协方差和系统矩阵，并提供标准 Kalman predict/update 步骤。
             */
            class KalmanFilter
            {
            public:
                /**
                 * @brief 当前状态估计，形状为 `[points, dim_x, 1]`。
                 */
                core::ZxGpuRealArray x;

                /**
                 * @brief 当前状态协方差，形状为 `[points, dim_x, dim_x]`。
                 */
                core::ZxGpuRealArray P;

                /**
                 * @brief 最近一次更新使用的观测量，形状为 `[points, dim_z, 1]`。
                 */
                core::ZxGpuRealArray z;

                /**
                 * @brief 测量噪声协方差，形状为 `[points, dim_z, dim_z]`。
                 */
                core::ZxGpuRealArray R;

                /**
                 * @brief 过程噪声协方差，形状为 `[points, dim_x, dim_x]`。
                 */
                core::ZxGpuRealArray Q;

                /**
                 * @brief 状态转移矩阵，形状为 `[points, dim_x, dim_x]`。
                 */
                core::ZxGpuRealArray F;

                /**
                 * @brief 观测矩阵，形状为 `[points, dim_z, dim_x]`。
                 */
                core::ZxGpuRealArray H;

                /**
                 * @brief 控制矩阵，形状为 `[points, dim_x, dim_u]`。
                 */
                core::ZxGpuRealArray B;

                /**
                 * @brief 控制输入，形状为 `[points, dim_u, 1]`。
                 */
                core::ZxGpuRealArray u;

                /**
                 * @brief 淡忘因子平方，形状为 `[points, 1, 1]`。
                 */
                core::ZxGpuRealArray alpha_sq;

                /**
                 * @brief 构造 KalmanFilter 对象。
                 *
                 * @param dim_x 状态维度。
                 * @param dim_z 观测维度。
                 * @param dim_u 控制维度。
                 * @param points 并行跟踪点数。
                 * @param dtype 计算 dtype 名称；`"float16"` 通过 FP32 中间计算提供兼容路径。
                 * @throws std::invalid_argument 当维度非法或 dtype 不受支持时抛出异常。
                 */
                KalmanFilter(
                    int dim_x,
                    int dim_z,
                    int dim_u = 0,
                    int points = 1,
                    const std::string &dtype = "float32");

                /**
                 * @brief 执行一次预测步骤。
                 *
                 * @return 无返回值。
                 */
                void predict();

                /**
                 * @brief 使用显式控制输入执行一次预测步骤。
                 *
                 * @param control 控制输入，形状建议为 `[points, dim_u, 1]`。
                 * @return 无返回值；会缓存 `control` 到公共成员 `u`。
                 */
                void predict(const core::RealArrayLike &control);

                /**
                 * @brief 执行一次更新步骤。
                 *
                 * @param measurement 当前观测，形状建议为 `[points, dim_z, 1]`。
                 * @return 无返回值；会缓存 `measurement` 到公共成员 `z`。
                 */
                void update(const core::RealArrayLike &measurement);

                /**
                 * @brief 获取状态维度。
                 *
                 * @return `dim_x`。
                 */
                int dim_x() const;

                /**
                 * @brief 获取观测维度。
                 *
                 * @return `dim_z`。
                 */
                int dim_z() const;

                /**
                 * @brief 获取控制维度。
                 *
                 * @return `dim_u`。
                 */
                int dim_u() const;

                /**
                 * @brief 获取并行跟踪点数。
                 *
                 * @return `points`。
                 */
                int points() const;

                /**
                 * @brief 获取构造时声明的 dtype。
                 *
                 * @return dtype 名称。
                 */
                const std::string &dtype() const;

            private:
                int dim_x_;
                int dim_z_;
                int dim_u_;
                int points_;
                std::string dtype_;
            };

        } // namespace estimation
    } // namespace zx_gpu_backend
} // namespace cusignal
