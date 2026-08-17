#pragma once

#include <cstdlib>
#include <filesystem>
#include <string>

namespace cusignal_test::cpu_reference_cache
{
    inline bool write_enabled()
    {
        const char *const value = std::getenv("CUSIGNAL_CPU_REFERENCE_CACHE_WRITE");
        if (value == nullptr)
        {
            return false;
        }
        const std::string normalized(value);
        return normalized == "1" || normalized == "true" || normalized == "on";
    }

    // Normal reports intentionally keep output_samples compact.  A cache
    // collection is the explicit exception: CPU output files must contain
    // the complete logical output, not the 32-value diagnostic prefix.
    inline bool write_full_outputs()
    {
        return write_enabled();
    }
} // namespace cusignal_test::cpu_reference_cache
