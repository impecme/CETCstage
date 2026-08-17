#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

namespace cusignal::core::benchmark
{
    // Internal test/profiling state.  The public signal/array API does not
    // expose this protocol; it is only active while a unit-test benchmark is
    // running.
    struct InputRefreshSnapshot
    {
        std::uint64_t expected_iterations = 0;
        std::uint64_t observed_iterations = 0;
        std::uint64_t h2d_copy_calls = 0;
        std::uint64_t h2d_bytes = 0;
        std::uint64_t d2h_copy_calls = 0;
        std::uint64_t d2h_bytes = 0;
        std::uint64_t iterations_with_h2d = 0;
        std::uint64_t min_h2d_bytes_per_iteration = 0;
        std::uint64_t max_h2d_bytes_per_iteration = 0;
        std::uint64_t current_h2d_bytes = 0;
        std::uint64_t finalized_iterations = 0;
        bool requires_h2d = true;
        bool pass = false;
    };

    inline void finalize_input_refresh_iteration(InputRefreshSnapshot &snapshot)
    {
        if (snapshot.observed_iterations == 0 ||
            snapshot.observed_iterations <= snapshot.finalized_iterations)
        {
            return;
        }
        if (snapshot.current_h2d_bytes != 0)
        {
            ++snapshot.iterations_with_h2d;
            if (snapshot.min_h2d_bytes_per_iteration == 0 ||
                snapshot.current_h2d_bytes < snapshot.min_h2d_bytes_per_iteration)
            {
                snapshot.min_h2d_bytes_per_iteration = snapshot.current_h2d_bytes;
            }
            if (snapshot.current_h2d_bytes > snapshot.max_h2d_bytes_per_iteration)
            {
                snapshot.max_h2d_bytes_per_iteration = snapshot.current_h2d_bytes;
            }
        }
        snapshot.finalized_iterations = snapshot.observed_iterations;
    }

    inline thread_local InputRefreshSnapshot *g_active_input_refresh = nullptr;
    inline thread_local InputRefreshSnapshot g_last_input_refresh{};

    inline void note_iteration()
    {
        if (g_active_input_refresh != nullptr)
        {
            finalize_input_refresh_iteration(*g_active_input_refresh);
            ++g_active_input_refresh->observed_iterations;
            g_active_input_refresh->current_h2d_bytes = 0;
        }
    }

    inline void note_host_to_device(std::size_t bytes)
    {
        if (g_active_input_refresh != nullptr)
        {
            ++g_active_input_refresh->h2d_copy_calls;
            g_active_input_refresh->h2d_bytes += static_cast<std::uint64_t>(bytes);
            g_active_input_refresh->current_h2d_bytes += static_cast<std::uint64_t>(bytes);
        }
    }

    inline void note_device_to_host(std::size_t bytes)
    {
        if (g_active_input_refresh != nullptr)
        {
            ++g_active_input_refresh->d2h_copy_calls;
            g_active_input_refresh->d2h_bytes += static_cast<std::uint64_t>(bytes);
        }
    }

    inline InputRefreshSnapshot input_refresh_snapshot()
    {
        return g_last_input_refresh;
    }

    // Optimized-only validation reuses the frozen CPU reference and does not
    // need a second CPU timing loop.  The CPU output used for correctness is
    // still produced once by the operator test; this switch only suppresses
    // repeated CPU latency sampling.
    inline bool skip_cpu_timing()
    {
        const char *value = std::getenv("CUSIGNAL_SKIP_CPU_TIMING");
        return value != nullptr &&
               (std::strcmp(value, "1") == 0 ||
                std::strcmp(value, "true") == 0 ||
                std::strcmp(value, "on") == 0);
    }

    class InputRefreshRun
    {
    public:
        InputRefreshRun(std::uint64_t expected_iterations, bool requires_h2d = true)
            : previous_(g_active_input_refresh)
        {
            g_last_input_refresh = {};
            snapshot_.expected_iterations = expected_iterations;
            snapshot_.requires_h2d = requires_h2d;
            g_active_input_refresh = &snapshot_;
        }

        InputRefreshRun(const InputRefreshRun &) = delete;
        InputRefreshRun &operator=(const InputRefreshRun &) = delete;

        ~InputRefreshRun()
        {
            finish();
        }

        void finish()
        {
            if (finished_)
            {
                return;
            }
            finalize_input_refresh_iteration(snapshot_);
            snapshot_.pass =
                snapshot_.observed_iterations == snapshot_.expected_iterations &&
                (!snapshot_.requires_h2d ||
                 (snapshot_.h2d_copy_calls >= snapshot_.expected_iterations &&
                  snapshot_.iterations_with_h2d == snapshot_.expected_iterations));
            if (g_active_input_refresh == &snapshot_)
            {
                g_active_input_refresh = previous_;
            }
            g_last_input_refresh = snapshot_;
            finished_ = true;
        }

    private:
        InputRefreshSnapshot snapshot_{};
        InputRefreshSnapshot *previous_ = nullptr;
        bool finished_ = false;
    };
} // namespace cusignal::core::benchmark
