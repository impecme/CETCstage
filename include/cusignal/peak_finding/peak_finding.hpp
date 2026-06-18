#pragma once

#include <string>

#include "cusignal/core/types.hpp"

namespace cusignal
{
    namespace peak_finding_api
    {

        /**
         * @brief 极值索引结果，按轴返回索引数组。
         */
        struct ExtremaResult
        {
            core::AxisIndices indices;
        };

        /**
         * @brief ZQ500 GPU 极值索引结果，按轴返回 device 索引数组。
         */
        struct ZxGpuExtremaResult
        {
            core::DeviceAxisIndices indices;
        };

    } // namespace peak_finding_api

    namespace cpu
    {
        namespace peak_finding
        {

            /**
             * @brief 计算相对极值位置。
             *
             * @param data 输入张量。
             * @param comparator 比较器名称，仅支持 `"greater"` 与 `"less"`。
             * @param axis 搜索极值的轴。
             * @param order 每侧比较的邻域点数，需大于等于 1。
             * @param mode 边界模式，支持 `"clip"` 与 `"wrap"`。
             * @return 按轴组织的极值索引结果。
             * @throws std::invalid_argument 当比较器、`order` 或 `mode` 非法时抛出异常。
             * @note Python callable comparator 本轮暂不支持。
             */
            peak_finding_api::ExtremaResult argrelextrema(
                const core::RealArray &data,
                const std::string &comparator,
                int axis = 0,
                int order = 1,
                const std::string &mode = "clip");

            /**
             * @brief 计算相对最小值位置。
             *
             * @param data 输入张量。
             * @param axis 搜索极值的轴。
             * @param order 每侧比较的邻域点数，需大于等于 1。
             * @param mode 边界模式，支持 `"clip"` 与 `"wrap"`。
             * @return 按轴组织的最小值索引结果。
             * @throws std::invalid_argument 当 `order` 或 `mode` 非法时抛出异常。
             */
            peak_finding_api::ExtremaResult argrelmin(
                const core::RealArray &data,
                int axis = 0,
                int order = 1,
                const std::string &mode = "clip");

            /**
             * @brief 计算相对最大值位置。
             *
             * @param data 输入张量。
             * @param axis 搜索极值的轴。
             * @param order 每侧比较的邻域点数，需大于等于 1。
             * @param mode 边界模式，支持 `"clip"` 与 `"wrap"`。
             * @return 按轴组织的最大值索引结果。
             * @throws std::invalid_argument 当 `order` 或 `mode` 非法时抛出异常。
             */
            peak_finding_api::ExtremaResult argrelmax(
                const core::RealArray &data,
                int axis = 0,
                int order = 1,
                const std::string &mode = "clip");

        } // namespace peak_finding
    } // namespace cpu

    namespace zx_gpu_backend
    {
        namespace peak_finding
        {

            /**
             * @brief 计算相对极值位置。
             *
             * @param data 输入张量。
             * @param comparator 比较器名称，仅支持 `"greater"` 与 `"less"`。
             * @param axis 搜索极值的轴。
             * @param order 每侧比较的邻域点数，需大于等于 1。
             * @param mode 边界模式，支持 `"clip"` 与 `"wrap"`。
             * @return 按轴组织的极值索引结果。
             * @throws std::invalid_argument 当比较器、`order` 或 `mode` 非法时抛出异常。
             * @note Python callable comparator 本轮暂不支持。
             */
            peak_finding_api::ZxGpuExtremaResult argrelextrema(
                const core::RealArrayLike &data,
                const std::string &comparator,
                int axis = 0,
                int order = 1,
                const std::string &mode = "clip");

            /**
             * @brief 计算相对最小值位置。
             *
             * @param data 输入张量。
             * @param axis 搜索极值的轴。
             * @param order 每侧比较的邻域点数，需大于等于 1。
             * @param mode 边界模式，支持 `"clip"` 与 `"wrap"`。
             * @return 按轴组织的最小值索引结果。
             * @throws std::invalid_argument 当 `order` 或 `mode` 非法时抛出异常。
             */
            peak_finding_api::ZxGpuExtremaResult argrelmin(
                const core::RealArrayLike &data,
                int axis = 0,
                int order = 1,
                const std::string &mode = "clip");

            /**
             * @brief 计算相对最大值位置。
             *
             * @param data 输入张量。
             * @param axis 搜索极值的轴。
             * @param order 每侧比较的邻域点数，需大于等于 1。
             * @param mode 边界模式，支持 `"clip"` 与 `"wrap"`。
             * @return 按轴组织的最大值索引结果。
             * @throws std::invalid_argument 当 `order` 或 `mode` 非法时抛出异常。
             */
            peak_finding_api::ZxGpuExtremaResult argrelmax(
                const core::RealArrayLike &data,
                int axis = 0,
                int order = 1,
                const std::string &mode = "clip");

        } // namespace peak_finding
    } // namespace zx_gpu_backend
} // namespace cusignal
