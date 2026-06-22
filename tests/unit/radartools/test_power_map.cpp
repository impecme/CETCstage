#include "cusignal/radartools/radartools.hpp"
#include "cusignal/core/helpers.hpp"

#include <cmath>
#include <iostream>

int main()
{
    using namespace cusignal;
    auto input = core::make_complex_array({2, 2});
    input.values = {{3.0f, 4.0f}, {0.0f, -2.0f}, {1.0f, 1.0f}, {-5.0f, 0.0f}};
    const auto cpu = cpu::radartools::power_map(input);
    const auto gpu = zx_gpu_backend::radartools::power_map(input).get();
    const float expected[] = {25.0f, 4.0f, 2.0f, 25.0f};
    for (std::size_t index = 0; index < input.size(); ++index)
    {
        if (std::fabs(cpu.values[index] - expected[index]) > 1.0e-6f ||
            std::fabs(gpu.values[index] - expected[index]) > 1.0e-6f)
            return 1;
    }
    const auto empty = zx_gpu_backend::radartools::power_map(core::make_complex_array({0, 3}));
    if (!empty.empty() || empty.shape() != core::Shape({0, 3}))
        return 1;
    std::cout << "[radartools/power_map] PASS\n";
    return 0;
}
