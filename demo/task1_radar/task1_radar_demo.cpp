#include "task1_common.hpp"

#include <exception>
#include <iostream>

int main(int argc, char **argv)
{
    try
    {
        const auto options = cusignal_demo::task1_radar::parse_options(argc, argv);
        return cusignal_demo::task1_radar::run(options);
    }
    catch (const std::exception &error)
    {
        std::cerr << "[task1_radar] ERROR: " << error.what() << '\n';
        return 1;
    }
}
