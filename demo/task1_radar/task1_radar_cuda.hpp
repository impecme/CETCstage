#pragma once

#include "cusignal/core/types.hpp"

namespace cusignal_demo::task1_radar
{
    cusignal::core::CudaRealArray power_map_cuda(const cusignal::core::CudaComplexArray &input);
    cusignal::core::CudaComplexArray fftshift_rows_complex_cuda(const cusignal::core::CudaComplexArray &input);
}
