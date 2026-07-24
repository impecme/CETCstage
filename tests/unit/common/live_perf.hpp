#pragma once

#include <cstdlib>
#include <filesystem>

// Unit tests normally read their generated manifests under the source tree.
// The live presentation may supply a disposable root containing smaller
// performance inputs. Formal and accuracy manifests are not modified.
namespace cusignal_test::live_perf
{
    inline std::filesystem::path generated_unit_root(const std::filesystem::path &default_root)
    {
        const char *const override_root = std::getenv("CUSIGNAL_GENERATED_UNIT_ROOT");
        if (override_root != nullptr && override_root[0] != '\0')
        {
            return std::filesystem::path(override_root);
        }
        return default_root;
    }
} // namespace cusignal_test::live_perf
