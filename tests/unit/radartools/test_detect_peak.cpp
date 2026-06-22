#include "cusignal/radartools/radartools.hpp"
#include "cusignal/core/helpers.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>

int main()
{
    using namespace cusignal;
    auto power = core::make_real_array({4, 3}, 0.0f);
    auto detections = core::make_real_array({4, 3}, 0.0f);
    power.values[1] = 7.0f;
    power.values[8] = 11.0f;
    detections.values[1] = 1.0f;
    detections.values[8] = 1.0f;
    const auto cpu = cpu::radartools::detect_peak(power, detections, 4, 2000.0f);
    const auto gpu = zx_gpu_backend::radartools::detect_peak(power, detections, 4, 2000.0f);
    if (!cpu.found || !gpu.found || cpu.range_bin != 2 || cpu.doppler_bin != 2 ||
        cpu.range_bin != gpu.range_bin || cpu.doppler_bin != gpu.doppler_bin ||
        std::fabs(cpu.doppler_hz) > 1.0e-6f || std::fabs(cpu.power - 11.0f) > 1.0e-6f)
        return 1;
    auto no_candidates = core::make_real_array({4, 3}, 0.0f);
    if (cpu::radartools::detect_peak(power, no_candidates, 4, 2000.0f).found)
        return 1;
    bool rejected = false;
    try
    {
        (void)cpu::radartools::detect_peak(power, core::make_real_array({3, 4}), 4, 2000.0f);
    }
    catch (const std::invalid_argument &)
    {
        rejected = true;
    }
    if (!rejected)
        return 1;
    std::cout << "[radartools/detect_peak] PASS\n";
    return 0;
}
