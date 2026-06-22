#include "cusignal/core/types.hpp"

#include <cmath>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <type_traits>
#include <vector>

namespace
{
    template <typename T>
    bool equal_value(const T &lhs, const T &rhs)
    {
        return lhs == rhs;
    }

    template <>
    bool equal_value<cusignal::core::Float16>(
        const cusignal::core::Float16 &lhs,
        const cusignal::core::Float16 &rhs)
    {
        return static_cast<float>(lhs) == static_cast<float>(rhs);
    }

    template <>
    bool equal_value<cusignal::core::Complex>(
        const cusignal::core::Complex &lhs,
        const cusignal::core::Complex &rhs)
    {
        return lhs.real() == rhs.real() && lhs.imag() == rhs.imag();
    }

    template <typename T>
    void require_equal(const std::vector<T> &actual, const std::vector<T> &expected, const char *name)
    {
        if (actual.size() != expected.size())
        {
            throw std::runtime_error(std::string(name) + " size mismatch");
        }
        for (std::size_t index = 0; index < expected.size(); ++index)
        {
            if (!equal_value(actual[index], expected[index]))
            {
                throw std::runtime_error(std::string(name) + " value mismatch");
            }
        }
    }

    template <typename T>
    void test_roundtrip(const std::vector<T> &values, const char *name)
    {
        using namespace cusignal::core;

        DeviceSignal<T> device_signal = DeviceSignal<T>::from_host(values);
        require_equal(device_signal.get(), values, name);

        Array<T> host_array;
        host_array.shape = Shape{1, values.size()};
        host_array.values = values;
        DeviceArray<T> device_array = DeviceArray<T>::from_host(host_array);
        const Array<T> output = device_array.get();
        if (output.shape != host_array.shape)
        {
            throw std::runtime_error(std::string(name) + " shape mismatch");
        }
        require_equal(output.values, values, name);

        DeviceSignal<T> empty_signal;
        empty_signal.copy_from({});
        if (!empty_signal.empty() || !empty_signal.get().empty())
        {
            throw std::runtime_error(std::string(name) + " empty signal mismatch");
        }
    }
}

int main()
{
    using namespace cusignal::core;

    static_assert(is_supported_real_scalar_v<Float32>);
    static_assert(is_supported_real_scalar_v<Float16>);
    static_assert(is_supported_real_scalar_v<Int32>);
    static_assert(is_supported_real_scalar_v<Int16>);
    static_assert(is_supported_real_scalar_v<Int8>);
    static_assert(!is_supported_real_scalar_v<double>);
    static_assert(std::is_same_v<ScalarTypeTraits<Float16>::accumulator_type, Float32>);
    static_assert(std::is_same_v<ScalarTypeTraits<Int32>::accumulator_type, std::int64_t>);
    static_assert(std::is_same_v<device_value_t<Complex>, cuFloatComplex>);

    test_roundtrip<Float32>({-3.25f, 0.0f, 1.5f, 65504.0f}, "float32");
    test_roundtrip<Float16>(
        {Float16(-2.0f), Float16(-0.5f), Float16(0.0f), Float16(1.5f)},
        "float16");
    test_roundtrip<Int32>({INT32_MIN, -1, 0, INT32_MAX}, "int32");
    test_roundtrip<Int16>({INT16_MIN, -1, 0, INT16_MAX}, "int16");
    test_roundtrip<Int8>({INT8_MIN, -1, 0, INT8_MAX}, "int8");
    test_roundtrip<Complex>(
        {Complex(-2.0f, 0.5f), Complex(0.0f, 0.0f), Complex(1.25f, -3.0f)},
        "complex64");

    std::cout << "[core/types] PASS real_types=5 complex_types=1" << std::endl;
    return 0;
}
