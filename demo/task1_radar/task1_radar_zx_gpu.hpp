#pragma once

#include "cusignal/core/types.hpp"

namespace cusignal_demo::task1_radar
{
    cusignal::core::ZxGpuRealArray power_map_zx_gpu(const cusignal::core::ZxGpuComplexArray &input);
    cusignal::core::ZxGpuComplexArray fftshift_rows_complex_zx_gpu(const cusignal::core::ZxGpuComplexArray &input);
}
