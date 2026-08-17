#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>

#include "cusignal/core/types.hpp"
#include "cusignal/core/benchmark_input_protocol.hpp"

namespace cusignal_test::benchmark_overhead
{
    // This is an internal benchmark/report protocol.  It deliberately does
    // not wrap CUDA or cuFFT entry points: a producer must explicitly note a
    // call while a Capture is active.  Until a producer is connected, the
    // report uses N/A rather than inferring counts from elapsed time.
    struct Snapshot
    {
        bool captured = false;
        std::optional<std::uint64_t> allocation_calls;
        std::optional<std::uint64_t> allocation_bytes;
        std::optional<std::uint64_t> plan_create_calls;
        std::optional<std::uint64_t> plan_destroy_calls;
        std::optional<std::uint64_t> event_create_calls;
        std::optional<std::uint64_t> event_destroy_calls;
        std::optional<std::uint64_t> explicit_device_sync_calls;
        std::optional<std::uint64_t> h2d_calls;
        std::optional<std::uint64_t> h2d_bytes;
        std::optional<std::uint64_t> d2h_calls;
        std::optional<std::uint64_t> d2h_bytes;
        std::optional<std::uint64_t> materialize_calls;
    };

    namespace detail
    {
        struct CaptureState
        {
            Snapshot snapshot;
        };

        inline thread_local CaptureState *g_active_capture = nullptr;
        inline thread_local Snapshot g_last_snapshot{};

        inline Snapshot zero_snapshot()
        {
            Snapshot snapshot;
            snapshot.captured = true;
            snapshot.allocation_calls = 0;
            snapshot.allocation_bytes = 0;
            snapshot.plan_create_calls = 0;
            snapshot.plan_destroy_calls = 0;
            snapshot.event_create_calls = 0;
            snapshot.event_destroy_calls = 0;
            snapshot.explicit_device_sync_calls = 0;
            snapshot.h2d_calls = 0;
            snapshot.h2d_bytes = 0;
            snapshot.d2h_calls = 0;
            snapshot.d2h_bytes = 0;
            snapshot.materialize_calls = 0;
            return snapshot;
        }
    } // namespace detail

    inline void note_allocation(std::size_t bytes)
    {
        if (detail::g_active_capture == nullptr)
        {
            return;
        }
        ++*detail::g_active_capture->snapshot.allocation_calls;
        *detail::g_active_capture->snapshot.allocation_bytes += static_cast<std::uint64_t>(bytes);
    }

    inline void note_plan_create()
    {
        if (detail::g_active_capture != nullptr)
        {
            ++*detail::g_active_capture->snapshot.plan_create_calls;
        }
    }

    inline void note_plan_destroy()
    {
        if (detail::g_active_capture != nullptr)
        {
            ++*detail::g_active_capture->snapshot.plan_destroy_calls;
        }
    }

    inline void note_event_create()
    {
        if (detail::g_active_capture != nullptr)
        {
            ++*detail::g_active_capture->snapshot.event_create_calls;
        }
    }

    inline void note_event_destroy()
    {
        if (detail::g_active_capture != nullptr)
        {
            ++*detail::g_active_capture->snapshot.event_destroy_calls;
        }
    }

    inline void note_device_sync()
    {
        if (detail::g_active_capture != nullptr)
        {
            ++*detail::g_active_capture->snapshot.explicit_device_sync_calls;
        }
    }

    inline void note_h2d(std::size_t bytes)
    {
        if (detail::g_active_capture == nullptr)
        {
            return;
        }
        ++*detail::g_active_capture->snapshot.h2d_calls;
        *detail::g_active_capture->snapshot.h2d_bytes += static_cast<std::uint64_t>(bytes);
    }

    inline void note_d2h(std::size_t bytes)
    {
        if (detail::g_active_capture == nullptr)
        {
            return;
        }
        ++*detail::g_active_capture->snapshot.d2h_calls;
        *detail::g_active_capture->snapshot.d2h_bytes += static_cast<std::uint64_t>(bytes);
    }

    inline void note_materialize()
    {
        if (detail::g_active_capture != nullptr)
        {
            ++*detail::g_active_capture->snapshot.materialize_calls;
        }
    }

    inline Snapshot snapshot()
    {
        if (!detail::g_last_snapshot.captured)
        {
            // Backend code is intentionally independent of the test-only
            // counter namespace.  Expose the core counters that are already
            // collected by the platform copy helpers and DeviceStorage
            // allocator; fields without a producer remain N/A.
            Snapshot current;
            current.captured = true;
            const auto input = cusignal::core::benchmark::input_refresh_snapshot();
            const auto storage = cusignal::core::device_storage_cache_stats_snapshot();
            current.allocation_calls = storage.allocation_calls;
            current.allocation_bytes = storage.allocation_bytes;
            current.h2d_calls = input.h2d_copy_calls;
            current.h2d_bytes = input.h2d_bytes;
            current.d2h_calls = input.d2h_copy_calls;
            current.d2h_bytes = input.d2h_bytes;
            return current;
        }
        return detail::g_last_snapshot;
    }

    class Capture
    {
    public:
        Capture()
            : previous_(detail::g_active_capture)
        {
            state_.snapshot = detail::zero_snapshot();
            detail::g_active_capture = &state_;
        }

        Capture(const Capture &) = delete;
        Capture &operator=(const Capture &) = delete;

        ~Capture()
        {
            finish();
        }

        void finish()
        {
            if (finished_)
            {
                return;
            }
            if (detail::g_active_capture == &state_)
            {
                detail::g_active_capture = previous_;
            }
            detail::g_last_snapshot = state_.snapshot;
            finished_ = true;
        }

    private:
        detail::CaptureState state_{};
        detail::CaptureState *previous_ = nullptr;
        bool finished_ = false;
    };
} // namespace cusignal_test::benchmark_overhead
