#include "cusignal/radartools/radartools.hpp"
#include "cusignal/core/helpers.hpp"

#include <cmath>
#include <iostream>
#include <stdexcept>

int main()
{
    using namespace cusignal;
    auto input = core::make_complex_array({4, 2});
    for (std::size_t index = 0; index < input.size(); ++index)
        input.values[index] = core::Complex(static_cast<float>(index), -static_cast<float>(index));
    const auto cpu = cpu::radartools::fftshift_rows(input);
    const auto gpu = zx_gpu_backend::radartools::fftshift_rows(input).get();
    if (cpu.shape != input.shape || gpu.shape != input.shape || cpu.values != gpu.values)
        return 1;
    for (std::size_t row = 0; row < 4; ++row)
    {
        const std::size_t source_row = (row + 2) % 4;
        for (std::size_t col = 0; col < 2; ++col)
        {
            if (cpu.values[row * 2 + col] != input.values[source_row * 2 + col])
                return 1;
        }
    }
    bool rejected = false;
    try
    {
        (void)cpu::radartools::fftshift_rows(core::make_complex_array({8}));
    }
    catch (const std::invalid_argument &)
    {
        rejected = true;
    }
    if (!rejected)
        return 1;
    std::cout << "[radartools/fftshift_rows] PASS\n";
    return 0;
}
