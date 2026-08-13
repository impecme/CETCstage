#include "task2_common.hpp"

#include <exception>
#include <iostream>

int main(int argc, char **argv)
{
    try
    {
        const auto options = cusignal_demo::task2_features::parse_options(argc, argv);
        return cusignal_demo::task2_features::run(options);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[task2_features] ERROR: " << error.what() << '\n';
        return 1;
    }
}
