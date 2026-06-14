/*
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=80
cmake --build build --target smoke_demo1 --parallel 8
*/
#include "cusignal/cusignal.hpp"

#include <cmath>
#include <complex>
#include <iostream>
#include <stdexcept>

int main()
{
    const auto zeros = cusignal::core::make_cuda_real_signal(4, 0.0f).get();
    for (float value : zeros)
    {
        if (value != 0.0f)
        {
            throw std::runtime_error("CudaRealSignal zero-fill check failed");
        }
    }

    const cusignal::core::ComplexSignal complex_input{
        {1.0f, -2.0f},
        {3.5f, 4.0f},
    };
    const auto complex_output =
        cusignal::core::CudaComplexSignal::from_host(complex_input).get();
    for (std::size_t index = 0; index < complex_input.size(); ++index)
    {
        if (std::abs(complex_output[index] - complex_input[index]) > 1.0e-6f)
        {
            throw std::runtime_error("CudaComplexSignal round-trip check failed");
        }
    }

    const cusignal::core::RealSignal t{-3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 4.0};
    const auto duty = cusignal::cuda_backend::windows::hann(static_cast<int>(t.size()));
    const auto saw = cusignal::cuda_backend::waveforms::sawtooth(t, duty);
    const auto square = cusignal::cuda_backend::waveforms::square(saw, duty);

    std::cout << "demo1:";
    for (float value : saw.get())
    {
        std::cout << ' ' << value;
    }
    std::cout << '\n';
    return 0;
}
