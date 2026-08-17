#pragma once

// Internal Zhongkexin C500 tile and offline-autotuning policy.
//
// The public operator APIs deliberately do not expose tuning state.  This
// header is the single private seam where an operator turns its complete
// workload description into a finite, precompiled CandidateConfig.  Runtime
// selection only reads an external cache (or an explicit test override); it
// never benchmarks, compiles, or writes a cache entry.

#include <cuda_runtime_api.h>

#include <array>
#include <cctype>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <limits>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

namespace cusignal
{
    namespace zx_tile
    {
        constexpr const char *kRegistryVersion = "zx-c500-all81-v2";

        enum class TileMode : std::uint8_t
        {
            Auto = 0,
            Legacy = 1,
            Optimized = 2,
        };

        enum class LayoutKind : std::uint8_t
        {
            RowMajor = 0,
            ColumnMajor = 1,
            Strided = 2,
            Transpose = 3,
        };

        enum class StageCount : std::uint8_t
        {
            Single = 1,
            Double = 2,
        };

        enum class MemoryTier : std::uint8_t
        {
            M50 = 50,
            M75 = 75,
            M90 = 90,
        };

        enum class EpilogueKind : std::uint8_t
        {
            None = 0,
            AbsSquare = 1,
            Normalize = 2,
            Threshold = 3,
            Reduction = 4,
        };

        enum class OperatorFamily : std::uint8_t
        {
            Cfar2d = 0,
            PulseCompression = 1,
            PulseDoppler = 2,
            Correlate2d = 3,
            Linear = 4,
            RowReduction = 5,
            FftBatch = 6,
            FirFilter = 7,
            Static = 8,
        };

        // CandidateId is intentionally closed.  A cache entry is accepted
        // only when its name maps to one of these registered, precompiled
        // candidates; arbitrary numeric values from a JSON file are ignored.
        enum class CandidateId : std::uint16_t
        {
            CfarStatic = 0,
            CfarLegacy,
            CfarTiledT128E1,
            CfarTiledT256E2,
            CfarTiledT512E2,

            PulseCompressionStatic,
            PulseCompressionLegacy,
            PulseCompressionSplitT128,
            PulseCompressionSplitT256,
            PulseCompressionSplitT512,

            PulseDopplerStatic,
            PulseDopplerLegacy,
            PulseDopplerFusedT128,
            PulseDopplerFusedT256,
            PulseDopplerFusedT512,

            Correlate2dStatic,
            Correlate2dGeneric,
            Correlate2dShared8x32,
            Correlate2dShared16x16,
            Correlate2dShared32x8,
            Correlate2dShared16x32,
            Correlate2dShared32x16,

            LinearStatic,
            LinearM50T256E1V1,
            LinearM50T256E2V2,
            LinearM50T256E4V4,
            LinearM50T256E8V4,
            LinearM75T256E2V2,
            LinearM75T256E4V4,
            LinearM75T256E8V4,
            LinearM75T256E4V2B4,
            LinearM90T256E4V4B4,
            LinearM90T256E8V4B4,
            LinearM90T256E8V4B8,

            RowStatic,
            RowM50T256E1R1V1,
            RowM50T256E2R2V2,
            RowM50T256E4R2V4,
            RowM50T256E8R4V4,
            RowM75T256E2R2V2,
            RowM75T256E4R4V4,
            RowM75T256E8R4V4,
            RowM75T256E4R8V4,
            RowM90T256E4R4V4,
            RowM90T256E8R4V4,
            RowM90T256E8R8V4,
            RowM90T256E8R8V4B4,

            FftBatchStatic,
            FftBatchM50B1,
            FftBatchM50B2,
            FftBatchM50B4,
            FftBatchM50B8,
            FftBatchM75B2,
            FftBatchM75B4,
            FftBatchM75B8,
            FftBatchM75B8S2,
            FftBatchM90B4,
            FftBatchM90B8,
            FftBatchM90B8S2,
            FftBatchM90B8S2B2,

            FirFilterStatic,
            FirFilterM50R1,
            FirFilterM50R2,
            FirFilterM50R4,
            FirFilterM50R8,
            FirFilterM75R2,
            FirFilterM75R4,
            FirFilterM75R8,
            FirFilterM75R8B2,
            FirFilterM90R4,
            FirFilterM90R8,
            FirFilterM90R8B2,
            FirFilterM90R8B4,

            StaticOperator,
        };

        struct TileShape
        {
            int threads = 256;
            int elements_per_thread = 1;
            int rows_per_block = 1;
            int vector_width = 1;
            StageCount stages = StageCount::Single;
        };

        struct WorkspaceKey
        {
            int device = -1;
            int dtype = 0;
            std::size_t extent0 = 0;
            std::size_t extent1 = 0;
            int batch = 1;
            LayoutKind layout = LayoutKind::RowMajor;
            int transform = 0;
            TileShape tile{};
        };

        struct CandidateConfig
        {
            CandidateId id = CandidateId::CfarStatic;
            TileShape tile{};
            int tile_rows = 1;
            int tile_cols = 1;
            // For CA-CFAR this is the compile-time scan footprint.  For the
            // other families it is zero unless the candidate uses a tile.
            int scan_elements = 0;
            bool optimized_route = false;
            bool split_plan = false;
            bool fused_pack = false;
            bool shared_halo = false;
            int buffer_count = 1;
            int batch_tile = 1;
            MemoryTier memory_tier = MemoryTier::M50;
            int plan_variant = 0;
            // Filled from an offline measurement when a cache entry is
            // selected.  Registry candidates keep this at zero.
            std::size_t workspace_bytes = 0;
            std::size_t workspace_peak_bytes = 0;
        };

        struct TuningKey
        {
            OperatorFamily family = OperatorFamily::Cfar2d;
            // Public operator identity is separate from the implementation
            // family.  This prevents a cache entry for one C500 operator
            // from being reused by another operator that happens to share a
            // launch shape.
            std::string operator_id;
            int dtype = 0; // 0=float32, 1=complex64
            LayoutKind layout = LayoutKind::RowMajor;
            std::array<std::size_t, 6> shape{};
            std::uint8_t shape_count = 0;
            std::array<std::uint64_t, 10> semantic{};
            std::uint8_t semantic_count = 0;
            int batch = 1;

            std::string canonical() const
            {
                std::ostringstream stream;
                stream << family_name(family);
                if (!operator_id.empty())
                {
                    stream << "|operator=" << operator_id;
                }
                stream << "|dtype=" << dtype
                       << "|layout=" << static_cast<int>(layout)
                       << "|batch=" << batch << "|shape=";
                for (std::size_t i = 0; i < shape_count; ++i)
                {
                    if (i != 0)
                    {
                        stream << 'x';
                    }
                    stream << shape[i];
                }
                stream << "|semantic=";
                for (std::size_t i = 0; i < semantic_count; ++i)
                {
                    if (i != 0)
                    {
                        stream << ',';
                    }
                    stream << semantic[i];
                }
                return stream.str();
            }

            static const char *family_name(OperatorFamily value)
            {
                switch (value)
                {
                case OperatorFamily::Cfar2d:
                    return "ca_cfar";
                case OperatorFamily::PulseCompression:
                    return "pulse_compression";
                case OperatorFamily::PulseDoppler:
                    return "pulse_doppler";
                case OperatorFamily::Correlate2d:
                    return "correlate2d";
                case OperatorFamily::Linear:
                    return "linear";
                case OperatorFamily::RowReduction:
                    return "row_reduction";
                case OperatorFamily::FftBatch:
                    return "fft_batch";
                case OperatorFamily::FirFilter:
                    return "fir_filter";
                case OperatorFamily::Static:
                    return "static";
                }
                return "unknown";
            }
        };

        struct DeviceFingerprint
        {
            bool valid = false;
            int id = -1;
            int runtime_version = 0;
            int compute_major = 0;
            int compute_minor = 0;
            std::uint64_t total_global_mem = 0;
            std::string name;
            std::string target;
        };

        struct PolicyTrace
        {
            bool valid = false;
            std::string family;
            std::string operator_id;
            std::string key;
            std::string candidate;
            std::string source;
            std::string reason;
            CandidateConfig config{};
            DeviceFingerprint device{};
        };

        struct PolicyDecision
        {
            CandidateConfig config{};
            std::string key;
            std::string source;
            std::string reason;
            bool cache_hit = false;
        };

        struct ActivePolicyState
        {
            bool valid = false;
            CandidateConfig config{};
        };

        inline thread_local ActivePolicyState g_active_policy;

        class ScopedPolicy
        {
        public:
            explicit ScopedPolicy(const PolicyDecision &decision)
                : previous_(g_active_policy)
            {
                g_active_policy.valid = true;
                g_active_policy.config = decision.config;
            }

            ScopedPolicy(const ScopedPolicy &) = delete;
            ScopedPolicy &operator=(const ScopedPolicy &) = delete;

            ~ScopedPolicy()
            {
                g_active_policy = previous_;
            }

        private:
            ActivePolicyState previous_{};
        };

        inline TileMode requested_mode()
        {
            const char *value = std::getenv("CUSIGNAL_ZX_TILE_PATH");
            if (value == nullptr || std::strcmp(value, "auto") == 0)
            {
                return TileMode::Auto;
            }
            if (std::strcmp(value, "legacy") == 0)
            {
                return TileMode::Legacy;
            }
            if (std::strcmp(value, "optimized") == 0)
            {
                return TileMode::Optimized;
            }
            return TileMode::Auto;
        }

        inline bool optimized_path(bool implementation_supported = true)
        {
            return implementation_supported && requested_mode() != TileMode::Legacy;
        }

        inline bool legacy_path()
        {
            return requested_mode() == TileMode::Legacy;
        }

        constexpr std::size_t ceil_div(std::size_t value, std::size_t divisor)
        {
            return divisor == 0 ? 0 : (value + divisor - 1) / divisor;
        }

        inline TileShape linear_shape(std::size_t count)
        {
            if (g_active_policy.valid &&
                (g_active_policy.config.id > CandidateId::LinearStatic &&
                 g_active_policy.config.id <= CandidateId::LinearM90T256E8V4B8))
            {
                TileShape shape = g_active_policy.config.tile;
                // batch_tile is a real work-grouping parameter for the
                // elementwise kernels: each thread processes this many
                // adjacent tiles. It does not allocate dummy device memory.
                shape.elements_per_thread *= g_active_policy.config.batch_tile;
                return shape;
            }
            return TileShape{
                256,
                count >= 4096 ? 2 : 1,
                1,
                count >= 4096 ? 2 : 1,
                StageCount::Single};
        }

        inline TileShape linear_shape(std::size_t count, int threads)
        {
            TileShape shape = linear_shape(count);
            shape.threads = threads;
            return shape;
        }

        inline TileShape row_shape(std::size_t columns, std::size_t rows)
        {
            if (g_active_policy.valid &&
                (g_active_policy.config.id > CandidateId::RowStatic &&
                 g_active_policy.config.id <= CandidateId::RowM90T256E8R8V4B4))
            {
                TileShape shape = g_active_policy.config.tile;
                shape.elements_per_thread *= g_active_policy.config.batch_tile;
                return shape;
            }
            return TileShape{
                256,
                columns >= 1024 ? 2 : 1,
                rows >= 2 ? 1 : 1,
                columns % 4 == 0 ? 4 : 1,
                columns >= 2048 ? StageCount::Double : StageCount::Single};
        }

        constexpr bool valid_shape(const TileShape &shape)
        {
            return shape.threads > 0 &&
                   shape.elements_per_thread > 0 &&
                   shape.rows_per_block > 0 &&
                   shape.vector_width > 0;
        }

        inline bool same_shape(const TileShape &lhs, const TileShape &rhs)
        {
            return lhs.threads == rhs.threads &&
                   lhs.elements_per_thread == rhs.elements_per_thread &&
                   lhs.rows_per_block == rhs.rows_per_block &&
                   lhs.vector_width == rhs.vector_width &&
                   lhs.stages == rhs.stages;
        }

        inline std::uint64_t float_bits(float value)
        {
            std::uint32_t bits = 0;
            static_assert(sizeof(bits) == sizeof(value), "float must be IEEE-754 sized");
            std::memcpy(&bits, &value, sizeof(bits));
            return bits;
        }

        inline std::uint64_t stable_string_hash(const std::string &value)
        {
            std::uint64_t hash = 1469598103934665603ULL;
            for (unsigned char character : value)
            {
                hash ^= static_cast<std::uint64_t>(character);
                hash *= 1099511628211ULL;
            }
            return hash;
        }

        inline TuningKey make_cfar_2d_key(
            std::size_t rows,
            std::size_t cols,
            int guard_rows,
            int guard_cols,
            int reference_rows,
            int reference_cols,
            float alpha,
            int cells)
        {
            TuningKey key;
            key.family = OperatorFamily::Cfar2d;
            key.dtype = 0;
            key.shape = {rows, cols, 0, 0, 0, 0};
            key.shape_count = 2;
            key.semantic = {
                static_cast<std::uint64_t>(guard_rows),
                static_cast<std::uint64_t>(guard_cols),
                static_cast<std::uint64_t>(reference_rows),
                static_cast<std::uint64_t>(reference_cols),
                float_bits(alpha),
                static_cast<std::uint64_t>(cells),
                0,
                0,
                0,
                0};
            key.semantic_count = 6;
            return key;
        }

        inline TuningKey make_cfar_1d_key(
            std::size_t size,
            int guard_cells,
            int reference_cells,
            float alpha,
            int cells)
        {
            TuningKey key;
            key.family = OperatorFamily::Cfar2d;
            key.dtype = 0;
            key.shape = {size, 0, 0, 0, 0, 0};
            key.shape_count = 1;
            key.semantic = {
                static_cast<std::uint64_t>(guard_cells),
                static_cast<std::uint64_t>(reference_cells),
                float_bits(alpha),
                static_cast<std::uint64_t>(cells),
                1,
                0,
                0,
                0,
                0,
                0};
            key.semantic_count = 5;
            return key;
        }

        inline TuningKey make_pulse_compression_key(
            std::size_t pulses,
            std::size_t samples,
            std::size_t template_size,
            int nfft,
            bool normalize,
            const std::string &window_name)
        {
            TuningKey key;
            key.family = OperatorFamily::PulseCompression;
            key.dtype = 1;
            key.shape = {pulses, samples, 0, 0, 0, 0};
            key.shape_count = 2;
            key.semantic = {
                static_cast<std::uint64_t>(template_size),
                static_cast<std::uint64_t>(nfft),
                normalize ? 1ULL : 0ULL,
                stable_string_hash(window_name),
                0,
                0,
                0,
                0,
                0,
                0};
            key.semantic_count = 4;
            return key;
        }

        inline TuningKey make_pulse_doppler_key(
            std::size_t pulses,
            std::size_t samples,
            int nfft,
            bool shift_output,
            bool use_window,
            const std::string &window_name)
        {
            TuningKey key;
            key.family = OperatorFamily::PulseDoppler;
            key.dtype = 1;
            key.shape = {pulses, samples, 0, 0, 0, 0};
            key.shape_count = 2;
            key.semantic = {
                static_cast<std::uint64_t>(nfft),
                shift_output ? 1ULL : 0ULL,
                use_window ? 1ULL : 0ULL,
                stable_string_hash(window_name),
                0,
                0,
                0,
                0,
                0,
                0};
            key.semantic_count = 4;
            return key;
        }

        inline TuningKey make_correlate_2d_key(
            std::size_t left_rows,
            std::size_t left_cols,
            std::size_t right_rows,
            std::size_t right_cols,
            int dtype,
            const std::string &mode,
            const std::string &boundary,
            float fillvalue)
        {
            TuningKey key;
            key.family = OperatorFamily::Correlate2d;
            key.dtype = dtype;
            key.shape = {left_rows, left_cols, right_rows, right_cols, 0, 0};
            key.shape_count = 4;
            key.semantic = {
                stable_string_hash(mode),
                stable_string_hash(boundary),
                float_bits(fillvalue),
                0,
                0,
                0,
                0,
                0,
                0,
                0};
            key.semantic_count = 3;
            return key;
        }

        inline TuningKey make_operator_key(
            const char *operator_id,
            OperatorFamily family,
            const std::array<std::size_t, 6> &shape,
            std::uint8_t shape_count,
            int dtype = 0,
            int batch = 1,
            const std::array<std::uint64_t, 10> &semantic = std::array<std::uint64_t, 10>{},
            std::uint8_t semantic_count = 0,
            LayoutKind layout = LayoutKind::RowMajor)
        {
            TuningKey key;
            key.family = family;
            key.operator_id = operator_id == nullptr ? std::string{} : std::string(operator_id);
            key.dtype = dtype;
            key.layout = layout;
            key.shape = shape;
            key.shape_count = shape_count > key.shape.size() ? static_cast<std::uint8_t>(key.shape.size()) : shape_count;
            key.semantic = semantic;
            key.semantic_count = semantic_count > key.semantic.size()
                                     ? static_cast<std::uint8_t>(key.semantic.size())
                                     : semantic_count;
            key.batch = batch;
            return key;
        }

        inline TuningKey make_linear_operator_key(
            const char *operator_id,
            std::size_t count,
            int dtype = 0,
            std::uint64_t semantic0 = 0,
            std::uint64_t semantic1 = 0)
        {
            return make_operator_key(
                operator_id,
                OperatorFamily::Linear,
                {count, 0, 0, 0, 0, 0},
                1,
                dtype,
                1,
                {semantic0, semantic1, 0, 0, 0, 0, 0, 0, 0, 0},
                semantic1 == 0 ? (semantic0 == 0 ? 0 : 1) : 2);
        }

        inline TuningKey make_row_operator_key(
            const char *operator_id,
            std::size_t rows,
            std::size_t columns,
            int dtype = 0,
            std::uint64_t semantic0 = 0,
            std::uint64_t semantic1 = 0)
        {
            return make_operator_key(
                operator_id,
                OperatorFamily::RowReduction,
                {rows, columns, 0, 0, 0, 0},
                2,
                dtype,
                1,
                {semantic0, semantic1, 0, 0, 0, 0, 0, 0, 0, 0},
                semantic1 == 0 ? (semantic0 == 0 ? 0 : 1) : 2);
        }

        inline TuningKey make_fir_filter_key(
            const char *operator_id,
            std::size_t line_count,
            std::size_t axis_size,
            int dtype,
            std::size_t order,
            int axis,
            std::size_t numerator_count = 0,
            std::size_t denominator_count = 1,
            bool stateful = false,
            std::size_t axis_stride = 1)
        {
            return make_operator_key(
                operator_id,
                OperatorFamily::FirFilter,
                {line_count, axis_size, 0, 0, 0, 0},
                2,
                dtype,
                1,
                {static_cast<std::uint64_t>(order),
                 static_cast<std::uint64_t>(axis + 1),
                 static_cast<std::uint64_t>(numerator_count),
                 static_cast<std::uint64_t>(denominator_count),
                 stateful ? 1ULL : 0ULL,
                 static_cast<std::uint64_t>(axis_stride),
                 0,
                 0,
                 0,
                 0},
                6);
        }

        inline const char *candidate_name(CandidateId value)
        {
            switch (value)
            {
            case CandidateId::CfarStatic:
                return "ca_cfar_static";
            case CandidateId::CfarLegacy:
                return "ca_cfar_legacy";
            case CandidateId::CfarTiledT128E1:
                return "ca_cfar_tiled_t128_e128";
            case CandidateId::CfarTiledT256E2:
                return "ca_cfar_tiled_t256_e512";
            case CandidateId::CfarTiledT512E2:
                return "ca_cfar_tiled_t512_e1024";
            case CandidateId::PulseCompressionStatic:
                return "pulse_compression_static";
            case CandidateId::PulseCompressionLegacy:
                return "pulse_compression_legacy_plan";
            case CandidateId::PulseCompressionSplitT128:
                return "pulse_compression_split_t128";
            case CandidateId::PulseCompressionSplitT256:
                return "pulse_compression_split_t256";
            case CandidateId::PulseCompressionSplitT512:
                return "pulse_compression_split_t512";
            case CandidateId::PulseDopplerStatic:
                return "pulse_doppler_static";
            case CandidateId::PulseDopplerLegacy:
                return "pulse_doppler_legacy";
            case CandidateId::PulseDopplerFusedT128:
                return "pulse_doppler_fused_t128";
            case CandidateId::PulseDopplerFusedT256:
                return "pulse_doppler_fused_t256";
            case CandidateId::PulseDopplerFusedT512:
                return "pulse_doppler_fused_t512";
            case CandidateId::Correlate2dStatic:
                return "correlate2d_static";
            case CandidateId::Correlate2dGeneric:
                return "correlate2d_generic";
            case CandidateId::Correlate2dShared8x32:
                return "correlate2d_shared_8x32";
            case CandidateId::Correlate2dShared16x16:
                return "correlate2d_shared_16x16";
            case CandidateId::Correlate2dShared32x8:
                return "correlate2d_shared_32x8";
            case CandidateId::Correlate2dShared16x32:
                return "correlate2d_shared_16x32";
            case CandidateId::Correlate2dShared32x16:
                return "correlate2d_shared_32x16";
            case CandidateId::LinearStatic:
                return "linear_static";
            case CandidateId::LinearM50T256E1V1:
                return "linear_m50_t256_e1_v1";
            case CandidateId::LinearM50T256E2V2:
                return "linear_m50_t256_e2_v2";
            case CandidateId::LinearM50T256E4V4:
                return "linear_m50_t256_e4_v4";
            case CandidateId::LinearM50T256E8V4:
                return "linear_m50_t256_e8_v4";
            case CandidateId::LinearM75T256E2V2:
                return "linear_m75_t256_e2_v2";
            case CandidateId::LinearM75T256E4V4:
                return "linear_m75_t256_e4_v4";
            case CandidateId::LinearM75T256E8V4:
                return "linear_m75_t256_e8_v4";
            case CandidateId::LinearM75T256E4V2B4:
                return "linear_m75_t256_e4_v2_b4";
            case CandidateId::LinearM90T256E4V4B4:
                return "linear_m90_t256_e4_v4_b4";
            case CandidateId::LinearM90T256E8V4B4:
                return "linear_m90_t256_e8_v4_b4";
            case CandidateId::LinearM90T256E8V4B8:
                return "linear_m90_t256_e8_v4_b8";
            case CandidateId::RowStatic:
                return "row_static";
            case CandidateId::RowM50T256E1R1V1:
                return "row_m50_t256_e1_r1_v1";
            case CandidateId::RowM50T256E2R2V2:
                return "row_m50_t256_e2_r2_v2";
            case CandidateId::RowM50T256E4R2V4:
                return "row_m50_t256_e4_r2_v4";
            case CandidateId::RowM50T256E8R4V4:
                return "row_m50_t256_e8_r4_v4";
            case CandidateId::RowM75T256E2R2V2:
                return "row_m75_t256_e2_r2_v2";
            case CandidateId::RowM75T256E4R4V4:
                return "row_m75_t256_e4_r4_v4";
            case CandidateId::RowM75T256E8R4V4:
                return "row_m75_t256_e8_r4_v4";
            case CandidateId::RowM75T256E4R8V4:
                return "row_m75_t256_e4_r8_v4";
            case CandidateId::RowM90T256E4R4V4:
                return "row_m90_t256_e4_r4_v4";
            case CandidateId::RowM90T256E8R4V4:
                return "row_m90_t256_e8_r4_v4";
            case CandidateId::RowM90T256E8R8V4:
                return "row_m90_t256_e8_r8_v4";
            case CandidateId::RowM90T256E8R8V4B4:
                return "row_m90_t256_e8_r8_v4_b4";
            case CandidateId::FftBatchStatic:
                return "fft_batch_static";
            case CandidateId::FftBatchM50B1:
                return "fft_batch_m50_b1";
            case CandidateId::FftBatchM50B2:
                return "fft_batch_m50_b2";
            case CandidateId::FftBatchM50B4:
                return "fft_batch_m50_b4";
            case CandidateId::FftBatchM50B8:
                return "fft_batch_m50_b8";
            case CandidateId::FftBatchM75B2:
                return "fft_batch_m75_b2";
            case CandidateId::FftBatchM75B4:
                return "fft_batch_m75_b4";
            case CandidateId::FftBatchM75B8:
                return "fft_batch_m75_b8";
            case CandidateId::FftBatchM75B8S2:
                return "fft_batch_m75_b8_s2";
            case CandidateId::FftBatchM90B4:
                return "fft_batch_m90_b4";
            case CandidateId::FftBatchM90B8:
                return "fft_batch_m90_b8";
            case CandidateId::FftBatchM90B8S2:
                return "fft_batch_m90_b8_s2";
            case CandidateId::FftBatchM90B8S2B2:
                return "fft_batch_m90_b8_s2_b2";
            case CandidateId::FirFilterStatic:
                return "fir_filter_static";
            case CandidateId::FirFilterM50R1:
                return "fir_filter_m50_r1";
            case CandidateId::FirFilterM50R2:
                return "fir_filter_m50_r2";
            case CandidateId::FirFilterM50R4:
                return "fir_filter_m50_r4";
            case CandidateId::FirFilterM50R8:
                return "fir_filter_m50_r8";
            case CandidateId::FirFilterM75R2:
                return "fir_filter_m75_r2";
            case CandidateId::FirFilterM75R4:
                return "fir_filter_m75_r4";
            case CandidateId::FirFilterM75R8:
                return "fir_filter_m75_r8";
            case CandidateId::FirFilterM75R8B2:
                return "fir_filter_m75_r8_b2";
            case CandidateId::FirFilterM90R4:
                return "fir_filter_m90_r4";
            case CandidateId::FirFilterM90R8:
                return "fir_filter_m90_r8";
            case CandidateId::FirFilterM90R8B2:
                return "fir_filter_m90_r8_b2";
            case CandidateId::FirFilterM90R8B4:
                return "fir_filter_m90_r8_b4";
            case CandidateId::StaticOperator:
                return "static_operator";
            }
            return "unknown";
        }

        inline bool candidate_from_name(const std::string &name, CandidateId &result)
        {
            const CandidateId values[] = {
                CandidateId::CfarStatic,
                CandidateId::CfarLegacy,
                CandidateId::CfarTiledT128E1,
                CandidateId::CfarTiledT256E2,
                CandidateId::CfarTiledT512E2,
                CandidateId::PulseCompressionStatic,
                CandidateId::PulseCompressionLegacy,
                CandidateId::PulseCompressionSplitT128,
                CandidateId::PulseCompressionSplitT256,
                CandidateId::PulseCompressionSplitT512,
                CandidateId::PulseDopplerStatic,
                CandidateId::PulseDopplerLegacy,
                CandidateId::PulseDopplerFusedT128,
                CandidateId::PulseDopplerFusedT256,
                CandidateId::PulseDopplerFusedT512,
                CandidateId::Correlate2dStatic,
                CandidateId::Correlate2dGeneric,
                CandidateId::Correlate2dShared8x32,
                CandidateId::Correlate2dShared16x16,
                CandidateId::Correlate2dShared32x8,
                CandidateId::Correlate2dShared16x32,
                CandidateId::Correlate2dShared32x16,
                CandidateId::LinearStatic,
                CandidateId::LinearM50T256E1V1,
                CandidateId::LinearM50T256E2V2,
                CandidateId::LinearM50T256E4V4,
                CandidateId::LinearM50T256E8V4,
                CandidateId::LinearM75T256E2V2,
                CandidateId::LinearM75T256E4V4,
                CandidateId::LinearM75T256E8V4,
                CandidateId::LinearM75T256E4V2B4,
                CandidateId::LinearM90T256E4V4B4,
                CandidateId::LinearM90T256E8V4B4,
                CandidateId::LinearM90T256E8V4B8,
                CandidateId::RowStatic,
                CandidateId::RowM50T256E1R1V1,
                CandidateId::RowM50T256E2R2V2,
                CandidateId::RowM50T256E4R2V4,
                CandidateId::RowM50T256E8R4V4,
                CandidateId::RowM75T256E2R2V2,
                CandidateId::RowM75T256E4R4V4,
                CandidateId::RowM75T256E8R4V4,
                CandidateId::RowM75T256E4R8V4,
                CandidateId::RowM90T256E4R4V4,
                CandidateId::RowM90T256E8R4V4,
                CandidateId::RowM90T256E8R8V4,
                CandidateId::RowM90T256E8R8V4B4,
                CandidateId::FftBatchStatic,
                CandidateId::FftBatchM50B1,
                CandidateId::FftBatchM50B2,
                CandidateId::FftBatchM50B4,
                CandidateId::FftBatchM50B8,
                CandidateId::FftBatchM75B2,
                CandidateId::FftBatchM75B4,
                CandidateId::FftBatchM75B8,
                CandidateId::FftBatchM75B8S2,
                CandidateId::FftBatchM90B4,
                CandidateId::FftBatchM90B8,
                CandidateId::FftBatchM90B8S2,
                CandidateId::FftBatchM90B8S2B2,
                CandidateId::FirFilterStatic,
                CandidateId::FirFilterM50R1,
                CandidateId::FirFilterM50R2,
                CandidateId::FirFilterM50R4,
                CandidateId::FirFilterM50R8,
                CandidateId::FirFilterM75R2,
                CandidateId::FirFilterM75R4,
                CandidateId::FirFilterM75R8,
                CandidateId::FirFilterM75R8B2,
                CandidateId::FirFilterM90R4,
                CandidateId::FirFilterM90R8,
                CandidateId::FirFilterM90R8B2,
                CandidateId::FirFilterM90R8B4,
                CandidateId::StaticOperator};
            for (CandidateId value : values)
            {
                if (name == candidate_name(value))
                {
                    result = value;
                    return true;
                }
            }
            return false;
        }

        inline CandidateConfig candidate_config(CandidateId id)
        {
            CandidateConfig config;
            config.id = id;
            switch (id)
            {
            case CandidateId::CfarStatic:
                config.tile = TileShape{256, 2, 1, 1, StageCount::Single};
                config.scan_elements = 512;
                config.optimized_route = true;
                break;
            case CandidateId::CfarLegacy:
                config.tile = TileShape{256, 2, 1, 1, StageCount::Single};
                config.scan_elements = 512;
                break;
            case CandidateId::CfarTiledT128E1:
                config.tile = TileShape{128, 1, 1, 1, StageCount::Single};
                config.scan_elements = 128;
                config.optimized_route = true;
                break;
            case CandidateId::CfarTiledT256E2:
                config.tile = TileShape{256, 2, 1, 1, StageCount::Single};
                config.scan_elements = 512;
                config.optimized_route = true;
                break;
            case CandidateId::CfarTiledT512E2:
                config.tile = TileShape{512, 2, 1, 1, StageCount::Double};
                config.scan_elements = 1024;
                config.optimized_route = true;
                break;
            case CandidateId::PulseCompressionStatic:
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                config.optimized_route = true;
                config.split_plan = true;
                break;
            case CandidateId::PulseCompressionLegacy:
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                break;
            case CandidateId::PulseCompressionSplitT128:
                config.tile = TileShape{128, 1, 1, 1, StageCount::Single};
                config.optimized_route = true;
                config.split_plan = true;
                break;
            case CandidateId::PulseCompressionSplitT256:
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                config.optimized_route = true;
                config.split_plan = true;
                break;
            case CandidateId::PulseCompressionSplitT512:
                config.tile = TileShape{512, 1, 1, 1, StageCount::Double};
                config.optimized_route = true;
                config.split_plan = true;
                break;
            case CandidateId::PulseDopplerStatic:
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                config.optimized_route = true;
                config.fused_pack = true;
                break;
            case CandidateId::PulseDopplerLegacy:
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                break;
            case CandidateId::PulseDopplerFusedT128:
                config.tile = TileShape{128, 1, 1, 1, StageCount::Single};
                config.optimized_route = true;
                config.fused_pack = true;
                break;
            case CandidateId::PulseDopplerFusedT256:
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                config.optimized_route = true;
                config.fused_pack = true;
                break;
            case CandidateId::PulseDopplerFusedT512:
                config.tile = TileShape{512, 1, 1, 1, StageCount::Double};
                config.optimized_route = true;
                config.fused_pack = true;
                break;
            case CandidateId::Correlate2dStatic:
                config.tile = TileShape{256, 1, 16, 16, StageCount::Single};
                config.tile_rows = 16;
                config.tile_cols = 16;
                config.optimized_route = true;
                config.shared_halo = true;
                break;
            case CandidateId::Correlate2dGeneric:
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                break;
            case CandidateId::Correlate2dShared8x32:
                config.tile = TileShape{256, 1, 8, 32, StageCount::Single};
                config.tile_rows = 8;
                config.tile_cols = 32;
                config.optimized_route = true;
                config.shared_halo = true;
                break;
            case CandidateId::Correlate2dShared16x16:
                config.tile = TileShape{256, 1, 16, 16, StageCount::Single};
                config.tile_rows = 16;
                config.tile_cols = 16;
                config.optimized_route = true;
                config.shared_halo = true;
                break;
            case CandidateId::Correlate2dShared32x8:
                config.tile = TileShape{256, 1, 32, 8, StageCount::Single};
                config.tile_rows = 32;
                config.tile_cols = 8;
                config.optimized_route = true;
                config.shared_halo = true;
                break;
            case CandidateId::Correlate2dShared16x32:
                config.tile = TileShape{512, 1, 16, 32, StageCount::Double};
                config.tile_rows = 16;
                config.tile_cols = 32;
                config.optimized_route = true;
                config.shared_halo = true;
                break;
            case CandidateId::Correlate2dShared32x16:
                config.tile = TileShape{512, 1, 32, 16, StageCount::Double};
                config.tile_rows = 32;
                config.tile_cols = 16;
                config.optimized_route = true;
                config.shared_halo = true;
                break;
            default:
                break;
            }

            auto set_memory_tier = [&config](MemoryTier tier) {
                config.memory_tier = tier;
                config.optimized_route = true;
            };

            if (id >= CandidateId::LinearStatic && id <= CandidateId::LinearM90T256E8V4B8)
            {
                config.tile_rows = 1;
                config.tile_cols = 1;
                switch (id)
                {
                case CandidateId::LinearStatic:
                    config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                    break;
                case CandidateId::LinearM50T256E1V1:
                    config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::LinearM50T256E2V2:
                    config.tile = TileShape{256, 2, 1, 2, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::LinearM50T256E4V4:
                    config.tile = TileShape{256, 4, 1, 4, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::LinearM50T256E8V4:
                    config.tile = TileShape{256, 8, 1, 4, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::LinearM75T256E2V2:
                    config.tile = TileShape{256, 2, 1, 2, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::LinearM75T256E4V4:
                    config.tile = TileShape{256, 4, 1, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::LinearM75T256E8V4:
                    config.tile = TileShape{256, 8, 1, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::LinearM75T256E4V2B4:
                    config.tile = TileShape{256, 4, 1, 2, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::LinearM90T256E4V4B4:
                    config.tile = TileShape{256, 4, 1, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::LinearM90T256E8V4B4:
                    config.tile = TileShape{256, 8, 1, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::LinearM90T256E8V4B8:
                    config.tile = TileShape{256, 8, 1, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 8;
                    set_memory_tier(MemoryTier::M90);
                    break;
                default:
                    break;
                }
            }

            if (id >= CandidateId::RowStatic && id <= CandidateId::RowM90T256E8R8V4B4)
            {
                config.tile_cols = 1;
                config.tile_rows = 1;
                switch (id)
                {
                case CandidateId::RowStatic:
                    config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                    break;
                case CandidateId::RowM50T256E1R1V1:
                    config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::RowM50T256E2R2V2:
                    config.tile = TileShape{256, 2, 2, 2, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::RowM50T256E4R2V4:
                    config.tile = TileShape{256, 4, 2, 4, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::RowM50T256E8R4V4:
                    config.tile = TileShape{256, 8, 4, 4, StageCount::Single};
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::RowM75T256E2R2V2:
                    config.tile = TileShape{256, 2, 2, 2, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::RowM75T256E4R4V4:
                    config.tile = TileShape{256, 4, 4, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::RowM75T256E8R4V4:
                    config.tile = TileShape{256, 8, 4, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::RowM75T256E4R8V4:
                    config.tile = TileShape{256, 4, 8, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::RowM90T256E4R4V4:
                    config.tile = TileShape{256, 4, 4, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::RowM90T256E8R4V4:
                    config.tile = TileShape{256, 8, 4, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::RowM90T256E8R8V4:
                    config.tile = TileShape{256, 8, 8, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::RowM90T256E8R8V4B4:
                    config.tile = TileShape{256, 8, 8, 4, StageCount::Double};
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M90);
                    break;
                default:
                    break;
                }
                config.tile_rows = config.tile.rows_per_block;
            }

            if (id >= CandidateId::FftBatchStatic && id <= CandidateId::FftBatchM90B8S2B2)
            {
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                config.tile_rows = 1;
                config.tile_cols = 1;
                switch (id)
                {
                case CandidateId::FftBatchStatic:
                    break;
                case CandidateId::FftBatchM50B1:
                    config.batch_tile = 1;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FftBatchM50B2:
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FftBatchM50B4:
                    config.batch_tile = 4;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FftBatchM50B8:
                    config.batch_tile = 8;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FftBatchM75B2:
                    config.batch_tile = 2;
                    config.buffer_count = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FftBatchM75B4:
                    config.batch_tile = 4;
                    config.buffer_count = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FftBatchM75B8:
                    config.batch_tile = 8;
                    config.buffer_count = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FftBatchM75B8S2:
                    config.batch_tile = 8;
                    config.buffer_count = 2;
                    config.tile.stages = StageCount::Double;
                    config.plan_variant = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FftBatchM90B4:
                    config.batch_tile = 4;
                    config.buffer_count = 2;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::FftBatchM90B8:
                    config.batch_tile = 8;
                    config.buffer_count = 2;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::FftBatchM90B8S2:
                    config.batch_tile = 8;
                    config.buffer_count = 2;
                    config.tile.stages = StageCount::Double;
                    config.plan_variant = 2;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::FftBatchM90B8S2B2:
                    config.batch_tile = 8;
                    config.buffer_count = 2;
                    config.tile.stages = StageCount::Double;
                    config.plan_variant = 2;
                    config.split_plan = true;
                    set_memory_tier(MemoryTier::M90);
                    break;
                default:
                    break;
                }
            }

            if (id >= CandidateId::FirFilterStatic && id <= CandidateId::FirFilterM90R8B4)
            {
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                config.tile_rows = 1;
                config.tile_cols = 1;
                switch (id)
                {
                case CandidateId::FirFilterStatic:
                    break;
                case CandidateId::FirFilterM50R1:
                    config.tile.rows_per_block = 1;
                    config.plan_variant = 1;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FirFilterM50R2:
                    config.tile.rows_per_block = 2;
                    config.plan_variant = 2;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FirFilterM50R4:
                    config.tile.rows_per_block = 4;
                    config.plan_variant = 4;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FirFilterM50R8:
                    config.tile.rows_per_block = 8;
                    config.plan_variant = 8;
                    set_memory_tier(MemoryTier::M50);
                    break;
                case CandidateId::FirFilterM75R2:
                    config.tile.rows_per_block = 2;
                    config.plan_variant = 2;
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FirFilterM75R4:
                    config.tile.rows_per_block = 4;
                    config.plan_variant = 4;
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FirFilterM75R8:
                    config.tile.rows_per_block = 8;
                    config.plan_variant = 8;
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FirFilterM75R8B2:
                    config.tile.rows_per_block = 8;
                    config.plan_variant = 8;
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    config.tile.stages = StageCount::Double;
                    set_memory_tier(MemoryTier::M75);
                    break;
                case CandidateId::FirFilterM90R4:
                    config.tile.rows_per_block = 4;
                    config.plan_variant = 4;
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    config.tile.stages = StageCount::Double;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::FirFilterM90R8:
                    config.tile.rows_per_block = 8;
                    config.plan_variant = 8;
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    config.tile.stages = StageCount::Double;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::FirFilterM90R8B2:
                    config.tile.rows_per_block = 8;
                    config.plan_variant = 8;
                    config.buffer_count = 2;
                    config.batch_tile = 2;
                    config.tile.stages = StageCount::Double;
                    set_memory_tier(MemoryTier::M90);
                    break;
                case CandidateId::FirFilterM90R8B4:
                    config.tile.rows_per_block = 8;
                    config.plan_variant = 8;
                    config.buffer_count = 2;
                    config.batch_tile = 4;
                    config.tile.stages = StageCount::Double;
                    set_memory_tier(MemoryTier::M90);
                    break;
                default:
                    break;
                }
            }

            if (id == CandidateId::StaticOperator)
            {
                config.tile = TileShape{256, 1, 1, 1, StageCount::Single};
                config.tile_rows = 1;
                config.tile_cols = 1;
            }
            return config;
        }

        inline CandidateId static_candidate(OperatorFamily family)
        {
            switch (family)
            {
            case OperatorFamily::Cfar2d:
                return CandidateId::CfarStatic;
            case OperatorFamily::PulseCompression:
                return CandidateId::PulseCompressionStatic;
            case OperatorFamily::PulseDoppler:
                return CandidateId::PulseDopplerStatic;
            case OperatorFamily::Correlate2d:
                return CandidateId::Correlate2dStatic;
            case OperatorFamily::Linear:
                return CandidateId::LinearStatic;
            case OperatorFamily::RowReduction:
                return CandidateId::RowStatic;
            case OperatorFamily::FftBatch:
                return CandidateId::FftBatchStatic;
            case OperatorFamily::FirFilter:
                return CandidateId::FirFilterStatic;
            case OperatorFamily::Static:
                return CandidateId::StaticOperator;
            }
            return CandidateId::CfarStatic;
        }

        inline CandidateId legacy_candidate(OperatorFamily family)
        {
            switch (family)
            {
            case OperatorFamily::Cfar2d:
                return CandidateId::CfarLegacy;
            case OperatorFamily::PulseCompression:
                return CandidateId::PulseCompressionLegacy;
            case OperatorFamily::PulseDoppler:
                return CandidateId::PulseDopplerLegacy;
            case OperatorFamily::Correlate2d:
                return CandidateId::Correlate2dGeneric;
            case OperatorFamily::Linear:
                return CandidateId::LinearStatic;
            case OperatorFamily::RowReduction:
                return CandidateId::RowStatic;
            case OperatorFamily::FftBatch:
                return CandidateId::FftBatchStatic;
            case OperatorFamily::FirFilter:
                return CandidateId::FirFilterStatic;
            case OperatorFamily::Static:
                return CandidateId::StaticOperator;
            }
            return CandidateId::CfarLegacy;
        }

        inline bool candidate_belongs_to_family(OperatorFamily family, CandidateId id)
        {
            switch (family)
            {
            case OperatorFamily::Cfar2d:
                return id >= CandidateId::CfarStatic && id <= CandidateId::CfarTiledT512E2;
            case OperatorFamily::PulseCompression:
                return id >= CandidateId::PulseCompressionStatic && id <= CandidateId::PulseCompressionSplitT512;
            case OperatorFamily::PulseDoppler:
                return id >= CandidateId::PulseDopplerStatic && id <= CandidateId::PulseDopplerFusedT512;
            case OperatorFamily::Correlate2d:
                return id >= CandidateId::Correlate2dStatic && id <= CandidateId::Correlate2dShared32x16;
            case OperatorFamily::Linear:
                return id >= CandidateId::LinearStatic && id <= CandidateId::LinearM90T256E8V4B8;
            case OperatorFamily::RowReduction:
                return id >= CandidateId::RowStatic && id <= CandidateId::RowM90T256E8R8V4B4;
            case OperatorFamily::FftBatch:
                return id >= CandidateId::FftBatchStatic && id <= CandidateId::FftBatchM90B8S2B2;
            case OperatorFamily::FirFilter:
                return id >= CandidateId::FirFilterStatic && id <= CandidateId::FirFilterM90R8B4;
            case OperatorFamily::Static:
                return id == CandidateId::StaticOperator;
            }
            return false;
        }

        inline bool cfar_tiled_candidate(CandidateId id)
        {
            return id == CandidateId::CfarTiledT128E1 ||
                   id == CandidateId::CfarTiledT256E2 ||
                   id == CandidateId::CfarTiledT512E2 ||
                   id == CandidateId::CfarStatic;
        }

        inline bool correlate_shared_candidate(CandidateId id)
        {
            return id == CandidateId::Correlate2dShared8x32 ||
                   id == CandidateId::Correlate2dShared16x16 ||
                   id == CandidateId::Correlate2dShared32x8 ||
                   id == CandidateId::Correlate2dShared16x32 ||
                   id == CandidateId::Correlate2dShared32x16 ||
                   id == CandidateId::Correlate2dStatic;
        }

        inline bool is_truthy(const char *value)
        {
            return value != nullptr &&
                   (std::strcmp(value, "1") == 0 ||
                    std::strcmp(value, "true") == 0 ||
                    std::strcmp(value, "TRUE") == 0 ||
                    std::strcmp(value, "on") == 0 ||
                    std::strcmp(value, "ON") == 0 ||
                    std::strcmp(value, "legacy") == 0 ||
                    std::strcmp(value, "LEGACY") == 0);
        }

        inline bool explicit_legacy(OperatorFamily family)
        {
            if (legacy_path())
            {
                return true;
            }
            const char *name = nullptr;
            switch (family)
            {
            case OperatorFamily::Cfar2d:
                name = "CUSIGNAL_ZX_CFAR_PATH";
                break;
            case OperatorFamily::PulseCompression:
                name = "CUSIGNAL_ZX_PULSE_PLAN";
                break;
            case OperatorFamily::PulseDoppler:
                name = "CUSIGNAL_ZX_DOPPLER_PATH";
                break;
            case OperatorFamily::Correlate2d:
                break;
            default:
                break;
            }
            return name != nullptr && is_truthy(std::getenv(name));
        }

        inline bool tuning_disabled()
        {
            const char *value = std::getenv("CUSIGNAL_ZX_TUNING_MODE");
            return value != nullptr &&
                   (std::strcmp(value, "off") == 0 ||
                    std::strcmp(value, "OFF") == 0 ||
                    std::strcmp(value, "0") == 0);
        }

        inline bool tuning_forced()
        {
            const char *value = std::getenv("CUSIGNAL_ZX_TUNING_MODE");
            return value != nullptr &&
                   (std::strcmp(value, "force") == 0 ||
                    std::strcmp(value, "FORCE") == 0);
        }

        inline DeviceFingerprint current_device_fingerprint()
        {
            DeviceFingerprint fingerprint;
            int device = -1;
            if (cudaGetDevice(&device) != cudaSuccess || device < 0)
            {
                return fingerprint;
            }
            cudaDeviceProp properties{};
            if (cudaGetDeviceProperties(&properties, device) != cudaSuccess)
            {
                return fingerprint;
            }
            int runtime_version = 0;
            // Some ZQ500 compatibility runtimes expose device properties but
            // not the CUDA runtime-version query.  The device name, compute
            // capability and memory size still form a usable fingerprint;
            // keep runtime_version at zero in that compatibility case.
            (void)cudaRuntimeGetVersion(&runtime_version);
            fingerprint.valid = true;
            fingerprint.id = device;
            fingerprint.runtime_version = runtime_version;
            fingerprint.compute_major = properties.major;
            fingerprint.compute_minor = properties.minor;
            fingerprint.total_global_mem = static_cast<std::uint64_t>(properties.totalGlobalMem);
            fingerprint.name = properties.name;
            const char *target = std::getenv("CUSIGNAL_ZX_C500_TARGET");
            fingerprint.target = target == nullptr || target[0] == '\0' ? "c500" : target;
            return fingerprint;
        }

        namespace cache_detail
        {
            struct CacheEntry
            {
                std::string family;
                std::string key;
                std::string candidate_name;
                CandidateId candidate = CandidateId::CfarStatic;
                int threads = 0;
                int tile_rows = 0;
                int tile_cols = 0;
                int elements_per_thread = 0;
                int rows_per_block = 0;
                int vector_width = 0;
                int stages = 0;
                int scan_elements = 0;
                int buffer_count = 1;
                int batch_tile = 1;
                int memory_tier = 50;
                int plan_variant = 0;
                std::size_t workspace_bytes = 0;
                std::size_t workspace_peak_bytes = 0;
                double gpu_e2e_median_ms = 0.0;
                double gpu_kernel_median_ms = 0.0;
                bool correctness_pass = false;
                bool input_refresh_pass = false;
            };

            struct CacheDocument
            {
                bool valid = false;
                std::string registry_version;
                DeviceFingerprint device{};
                std::vector<CacheEntry> entries;
            };

            inline std::size_t skip_space(const std::string &text, std::size_t index)
            {
                while (index < text.size() && std::isspace(static_cast<unsigned char>(text[index])))
                {
                    ++index;
                }
                return index;
            }

            inline bool json_string_value(
                const std::string &text,
                const std::string &key,
                std::string &value,
                std::size_t start = 0)
            {
                const std::string marker = "\"" + key + "\"";
                const std::size_t marker_pos = text.find(marker, start);
                if (marker_pos == std::string::npos)
                {
                    return false;
                }
                std::size_t index = skip_space(text, marker_pos + marker.size());
                if (index >= text.size() || text[index] != ':')
                {
                    return false;
                }
                index = skip_space(text, index + 1);
                if (index >= text.size() || text[index] != '"')
                {
                    return false;
                }
                ++index;
                value.clear();
                while (index < text.size())
                {
                    const char character = text[index++];
                    if (character == '"')
                    {
                        return true;
                    }
                    if (character != '\\' || index >= text.size())
                    {
                        value.push_back(character);
                        continue;
                    }
                    const char escaped = text[index++];
                    switch (escaped)
                    {
                    case '"':
                    case '\\':
                    case '/':
                        value.push_back(escaped);
                        break;
                    case 'b':
                        value.push_back('\b');
                        break;
                    case 'f':
                        value.push_back('\f');
                        break;
                    case 'n':
                        value.push_back('\n');
                        break;
                    case 'r':
                        value.push_back('\r');
                        break;
                    case 't':
                        value.push_back('\t');
                        break;
                    default:
                        value.push_back(escaped);
                        break;
                    }
                }
                return false;
            }

            inline bool json_number_value(
                const std::string &text,
                const std::string &key,
                double &value,
                std::size_t start = 0)
            {
                const std::string marker = "\"" + key + "\"";
                const std::size_t marker_pos = text.find(marker, start);
                if (marker_pos == std::string::npos)
                {
                    return false;
                }
                std::size_t index = skip_space(text, marker_pos + marker.size());
                if (index >= text.size() || text[index] != ':')
                {
                    return false;
                }
                index = skip_space(text, index + 1);
                char *end = nullptr;
                value = std::strtod(text.c_str() + index, &end);
                return end != text.c_str() + index;
            }

            inline bool json_bool_value(
                const std::string &text,
                const std::string &key,
                bool &value,
                std::size_t start = 0)
            {
                const std::string marker = "\"" + key + "\"";
                const std::size_t marker_pos = text.find(marker, start);
                if (marker_pos == std::string::npos)
                {
                    return false;
                }
                std::size_t index = skip_space(text, marker_pos + marker.size());
                if (index >= text.size() || text[index] != ':')
                {
                    return false;
                }
                index = skip_space(text, index + 1);
                if (text.compare(index, 4, "true") == 0)
                {
                    value = true;
                    return true;
                }
                if (text.compare(index, 5, "false") == 0)
                {
                    value = false;
                    return true;
                }
                return false;
            }

            inline bool extract_object(
                const std::string &text,
                const std::string &key,
                std::string &object,
                std::size_t start = 0)
            {
                const std::string marker = "\"" + key + "\"";
                const std::size_t marker_pos = text.find(marker, start);
                if (marker_pos == std::string::npos)
                {
                    return false;
                }
                std::size_t index = skip_space(text, marker_pos + marker.size());
                if (index >= text.size() || text[index] != ':')
                {
                    return false;
                }
                index = skip_space(text, index + 1);
                if (index >= text.size() || text[index] != '{')
                {
                    return false;
                }
                const std::size_t begin = index;
                int depth = 0;
                bool quoted = false;
                bool escaped = false;
                for (; index < text.size(); ++index)
                {
                    const char character = text[index];
                    if (quoted)
                    {
                        if (escaped)
                        {
                            escaped = false;
                        }
                        else if (character == '\\')
                        {
                            escaped = true;
                        }
                        else if (character == '"')
                        {
                            quoted = false;
                        }
                        continue;
                    }
                    if (character == '"')
                    {
                        quoted = true;
                    }
                    else if (character == '{')
                    {
                        ++depth;
                    }
                    else if (character == '}' && --depth == 0)
                    {
                        object = text.substr(begin, index - begin + 1);
                        return true;
                    }
                }
                return false;
            }

            inline bool extract_entry_objects(
                const std::string &text,
                std::vector<std::string> &objects)
            {
                const std::string marker = "\"entries\"";
                const std::size_t marker_pos = text.find(marker);
                if (marker_pos == std::string::npos)
                {
                    return false;
                }
                std::size_t index = skip_space(text, marker_pos + marker.size());
                if (index >= text.size() || text[index] != ':')
                {
                    return false;
                }
                index = skip_space(text, index + 1);
                if (index >= text.size() || text[index] != '[')
                {
                    return false;
                }
                int array_depth = 0;
                int object_depth = 0;
                bool quoted = false;
                bool escaped = false;
                std::size_t object_begin = std::string::npos;
                for (; index < text.size(); ++index)
                {
                    const char character = text[index];
                    if (quoted)
                    {
                        if (escaped)
                        {
                            escaped = false;
                        }
                        else if (character == '\\')
                        {
                            escaped = true;
                        }
                        else if (character == '"')
                        {
                            quoted = false;
                        }
                        continue;
                    }
                    if (character == '"')
                    {
                        quoted = true;
                    }
                    else if (character == '[')
                    {
                        ++array_depth;
                    }
                    else if (character == ']')
                    {
                        --array_depth;
                        if (array_depth == 0)
                        {
                            return true;
                        }
                    }
                    else if (character == '{')
                    {
                        if (object_depth == 0)
                        {
                            object_begin = index;
                        }
                        ++object_depth;
                    }
                    else if (character == '}' && object_depth > 0)
                    {
                        --object_depth;
                        if (object_depth == 0 && object_begin != std::string::npos)
                        {
                            objects.push_back(text.substr(object_begin, index - object_begin + 1));
                            object_begin = std::string::npos;
                        }
                    }
                }
                return false;
            }

            inline bool device_matches(
                const DeviceFingerprint &expected,
                const DeviceFingerprint &actual)
            {
                if (!expected.valid || !actual.valid || expected.id != actual.id ||
                    expected.runtime_version != actual.runtime_version ||
                    expected.compute_major != actual.compute_major ||
                    expected.compute_minor != actual.compute_minor ||
                    expected.name != actual.name ||
                    (!expected.target.empty() && expected.target != actual.target))
                {
                    return false;
                }
                return expected.total_global_mem == 0 ||
                       expected.total_global_mem == actual.total_global_mem;
            }

            inline bool parse_cache(const std::string &text, CacheDocument &document)
            {
                double schema = 0.0;
                if (!json_number_value(text, "schema_version", schema) ||
                    (schema != 1.0 && schema != 2.0))
                {
                    return false;
                }
                if (!json_string_value(text, "registry_version", document.registry_version) ||
                    document.registry_version != kRegistryVersion)
                {
                    return false;
                }
                std::string device_object;
                if (!extract_object(text, "device", device_object))
                {
                    return false;
                }
                double number = 0.0;
                if (!json_number_value(device_object, "id", number))
                {
                    return false;
                }
                document.device.id = static_cast<int>(number);
                if (!json_number_value(device_object, "runtime_version", number))
                {
                    return false;
                }
                document.device.runtime_version = static_cast<int>(number);
                if (!json_number_value(device_object, "compute_major", number))
                {
                    return false;
                }
                document.device.compute_major = static_cast<int>(number);
                if (!json_number_value(device_object, "compute_minor", number))
                {
                    return false;
                }
                document.device.compute_minor = static_cast<int>(number);
                if (!json_number_value(device_object, "total_global_mem", number))
                {
                    return false;
                }
                document.device.total_global_mem = static_cast<std::uint64_t>(number);
                if (!json_string_value(device_object, "name", document.device.name))
                {
                    return false;
                }
                if (!json_string_value(device_object, "target", document.device.target))
                {
                    document.device.target = "c500";
                }
                document.device.valid = true;

                std::vector<std::string> objects;
                if (!extract_entry_objects(text, objects))
                {
                    return false;
                }
                for (const std::string &object : objects)
                {
                    CacheEntry entry;
                    if (!json_string_value(object, "family", entry.family) ||
                        !json_string_value(object, "key", entry.key) ||
                        !json_string_value(object, "candidate", entry.candidate_name))
                    {
                        return false;
                    }
                    if (!candidate_from_name(entry.candidate_name, entry.candidate))
                    {
                        return false;
                    }
                    std::string correctness;
                    std::string input_refresh;
                    if (!json_string_value(object, "correctness_status", correctness) ||
                        !json_string_value(object, "input_refresh_status", input_refresh))
                    {
                        return false;
                    }
                    entry.correctness_pass = correctness == "PASS";
                    entry.input_refresh_pass = input_refresh == "PASS";
                    if (!entry.correctness_pass || !entry.input_refresh_pass)
                    {
                        continue;
                    }
                    std::string config_object;
                    if (!extract_object(object, "config", config_object))
                    {
                        return false;
                    }
                    if (!json_number_value(config_object, "threads", number))
                    {
                        return false;
                    }
                    entry.threads = static_cast<int>(number);
                    if (!json_number_value(config_object, "tile_rows", number))
                    {
                        return false;
                    }
                    entry.tile_rows = static_cast<int>(number);
                    if (!json_number_value(config_object, "tile_cols", number))
                    {
                        return false;
                    }
                    entry.tile_cols = static_cast<int>(number);
                    if (!json_number_value(config_object, "elements_per_thread", number))
                    {
                        return false;
                    }
                    entry.elements_per_thread = static_cast<int>(number);
                    if (!json_number_value(config_object, "rows_per_block", number))
                    {
                        return false;
                    }
                    entry.rows_per_block = static_cast<int>(number);
                    if (!json_number_value(config_object, "vector_width", number))
                    {
                        return false;
                    }
                    entry.vector_width = static_cast<int>(number);
                    if (!json_number_value(config_object, "stages", number))
                    {
                        return false;
                    }
                    entry.stages = static_cast<int>(number);
                    if (!json_number_value(config_object, "scan_elements", number))
                    {
                        return false;
                    }
                    entry.scan_elements = static_cast<int>(number);
                    if (json_number_value(config_object, "buffer_count", number))
                    {
                        entry.buffer_count = static_cast<int>(number);
                    }
                    if (json_number_value(config_object, "batch_tile", number))
                    {
                        entry.batch_tile = static_cast<int>(number);
                    }
                    if (json_number_value(config_object, "memory_tier", number))
                    {
                        entry.memory_tier = static_cast<int>(number);
                    }
                    if (json_number_value(config_object, "plan_variant", number))
                    {
                        entry.plan_variant = static_cast<int>(number);
                    }
                    if (json_number_value(config_object, "workspace_bytes", number))
                    {
                        entry.workspace_bytes = static_cast<std::size_t>(number);
                    }
                    if (json_number_value(config_object, "workspace_peak_bytes", number))
                    {
                        entry.workspace_peak_bytes = static_cast<std::size_t>(number);
                    }
                    if (!json_number_value(object, "gpu_e2e_median_ms", number) ||
                        !std::isfinite(number) || number <= 0.0)
                    {
                        return false;
                    }
                    entry.gpu_e2e_median_ms = number;
                    if (json_number_value(object, "gpu_kernel_median_ms", number) &&
                        std::isfinite(number) && number >= 0.0)
                    {
                        entry.gpu_kernel_median_ms = number;
                    }
                    document.entries.push_back(std::move(entry));
                }
                document.valid = true;
                return true;
            }

            struct CacheState
            {
                std::mutex mutex;
                std::string path;
                CacheDocument document;
                bool attempted = false;
            };

            inline CacheState &cache_state()
            {
                static CacheState state;
                return state;
            }

            inline const CacheDocument *load_cache(const std::string &path)
            {
                CacheState &state = cache_state();
                std::lock_guard<std::mutex> lock(state.mutex);
                if (state.attempted && state.path == path)
                {
                    return state.document.valid ? &state.document : nullptr;
                }
                state.path = path;
                state.document = CacheDocument{};
                state.attempted = true;
                std::ifstream input(path);
                if (!input)
                {
                    return nullptr;
                }
                std::ostringstream buffer;
                buffer << input.rdbuf();
                if (!parse_cache(buffer.str(), state.document))
                {
                    state.document = CacheDocument{};
                    return nullptr;
                }
                return &state.document;
            }
        } // namespace cache_detail

        inline thread_local PolicyTrace g_policy_trace;

        inline std::size_t memory_tier_budget_bytes(
            MemoryTier tier,
            std::size_t free_bytes,
            std::size_t total_bytes);

        inline bool config_resource_supported(
            const CandidateConfig &config,
            const TuningKey &key,
            std::size_t workspace_bytes = 0)
        {
            if (!valid_shape(config.tile) ||
                (config.tile.threads != 64 && config.tile.threads != 128 &&
                 config.tile.threads != 256 && config.tile.threads != 512))
            {
                return false;
            }
            cudaDeviceProp properties{};
            int device = -1;
            if (cudaGetDevice(&device) == cudaSuccess &&
                cudaGetDeviceProperties(&properties, device) == cudaSuccess &&
                config.tile.threads > properties.maxThreadsPerBlock)
            {
                return false;
            }
            if (config.tile_rows <= 0 || config.tile_cols <= 0 ||
                config.tile_rows * config.tile_cols > 1024)
            {
                return false;
            }
            if (config.scan_elements < 0 || config.scan_elements > 1024)
            {
                return false;
            }
            if (workspace_bytes > (static_cast<std::size_t>(8192) << 20))
            {
                return false;
            }
            if (workspace_bytes != 0)
            {
                std::size_t free_bytes = 0;
                std::size_t total_bytes = 0;
                if (cudaMemGetInfo(&free_bytes, &total_bytes) == cudaSuccess &&
                    workspace_bytes > memory_tier_budget_bytes(
                        config.memory_tier, free_bytes, total_bytes))
                {
                    return false;
                }
            }
            if (config.buffer_count < 1 || config.buffer_count > 2 ||
                config.batch_tile < 1 || config.batch_tile > 8 ||
                (config.memory_tier != MemoryTier::M50 &&
                 config.memory_tier != MemoryTier::M75 &&
                 config.memory_tier != MemoryTier::M90) ||
                config.plan_variant < 0 || config.plan_variant > 8)
            {
                return false;
            }
            if ((key.family == OperatorFamily::Linear ||
                 key.family == OperatorFamily::RowReduction) &&
                config.tile.elements_per_thread * config.batch_tile > 64)
            {
                return false;
            }
            if (key.family == OperatorFamily::FirFilter && config.plan_variant > 0)
            {
                const std::size_t minimum_axis = key.dtype == 1 ? 2048 : 1024;
                if (key.shape_count < 2 || key.shape[1] < minimum_axis ||
                    key.semantic_count < 6 || key.semantic[3] != 1 ||
                    key.semantic[4] != 0 || key.semantic[5] != 1)
                {
                    return false;
                }
                const std::size_t output_count =
                    static_cast<std::size_t>(config.plan_variant) *
                    static_cast<std::size_t>(config.tile.threads);
                const std::size_t sample_bytes = key.dtype == 1 ? sizeof(float) * 2 : sizeof(float);
                const std::size_t estimated_shared =
                    (output_count + key.semantic[0]) * sample_bytes +
                    (key.semantic[0] + 1) * sizeof(float);
                // Keep the precompiled FIR variants below the conservative
                // C500 shared-memory envelope.  The runtime probe can still
                // reject a candidate through the device thread limit.
                if (estimated_shared > (static_cast<std::size_t>(48) << 10))
                {
                    return false;
                }
            }
            if (config.shared_halo && key.shape_count >= 4 &&
                (key.shape[2] > 15 || key.shape[3] > 15))
            {
                return false;
            }
            if (key.family == OperatorFamily::Cfar2d &&
                config.id != CandidateId::CfarStatic &&
                config.id != CandidateId::CfarLegacy &&
                (key.shape_count < 2 || key.shape[0] < 32 || key.shape[1] < 512))
            {
                return false;
            }
            if (key.family == OperatorFamily::Correlate2d && config.shared_halo &&
                (key.shape_count < 4 || key.semantic_count < 2 ||
                 key.semantic[1] != stable_string_hash("fill") ||
                 key.shape[0] < static_cast<std::size_t>(config.tile_rows) ||
                 key.shape[1] < static_cast<std::size_t>(config.tile_cols)))
            {
                return false;
            }
            return true;
        }

        inline std::size_t memory_tier_budget_bytes(
            MemoryTier tier,
            std::size_t free_bytes,
            std::size_t total_bytes)
        {
            const std::size_t basis = free_bytes == 0 ? total_bytes : free_bytes;
            const std::uint64_t percent = static_cast<std::uint64_t>(tier);
            const std::uint64_t budget =
                static_cast<std::uint64_t>(basis) * percent / 100ULL;
            return budget > (static_cast<std::size_t>(8192) << 20)
                       ? (static_cast<std::size_t>(8192) << 20)
                       : static_cast<std::size_t>(budget);
        }

        inline bool cache_workspace_available(std::size_t workspace_bytes)
        {
            if (workspace_bytes == 0)
            {
                return true;
            }
            std::size_t free_bytes = 0;
            std::size_t total_bytes = 0;
            return cudaMemGetInfo(&free_bytes, &total_bytes) == cudaSuccess &&
                   free_bytes >= workspace_bytes;
        }

        inline bool cache_config_matches(
            const CandidateConfig &config,
            const cache_detail::CacheEntry &entry)
        {
            return config.tile.threads == entry.threads &&
                   config.tile_rows == entry.tile_rows &&
                   config.tile_cols == entry.tile_cols &&
                   config.tile.elements_per_thread == entry.elements_per_thread &&
                   config.tile.rows_per_block == entry.rows_per_block &&
                   config.tile.vector_width == entry.vector_width &&
                   static_cast<int>(config.tile.stages) == entry.stages &&
                   config.scan_elements == entry.scan_elements &&
                   config.buffer_count == entry.buffer_count &&
                   config.batch_tile == entry.batch_tile &&
                   static_cast<int>(config.memory_tier) == entry.memory_tier &&
                   config.plan_variant == entry.plan_variant;
        }

        inline bool forced_candidate(
            const TuningKey &key,
            CandidateId &candidate)
        {
            const char *value = std::getenv("CUSIGNAL_ZX_TUNING_FORCE");
            if (value == nullptr)
            {
                return false;
            }
            std::string text(value);
            std::size_t begin = 0;
            while (begin < text.size())
            {
                const std::size_t end = text.find(';', begin);
                const std::string token = text.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
                const std::size_t separator = token.find('=') != std::string::npos
                                                  ? token.find('=')
                                                  : token.find(':');
                if (separator != std::string::npos)
                {
                    const std::string family_name = token.substr(0, separator);
                    const std::string candidate_name = token.substr(separator + 1);
                    if (family_name == TuningKey::family_name(key.family) ||
                        (!key.operator_id.empty() && family_name == key.operator_id))
                    {
                        CandidateId parsed;
                        if (candidate_from_name(candidate_name, parsed) &&
                            candidate_belongs_to_family(key.family, parsed))
                        {
                            candidate = parsed;
                            return true;
                        }
                        return false;
                    }
                }
                if (end == std::string::npos)
                {
                    break;
                }
                begin = end + 1;
            }
            return false;
        }

        inline void set_policy_trace(
            OperatorFamily family,
            const TuningKey &key,
            const CandidateConfig &config,
            const std::string &source,
            const std::string &reason,
            const DeviceFingerprint &device)
        {
            g_policy_trace.valid = true;
            g_policy_trace.family = TuningKey::family_name(family);
            g_policy_trace.operator_id = key.operator_id;
            g_policy_trace.key = key.canonical();
            g_policy_trace.candidate = candidate_name(config.id);
            g_policy_trace.source = source;
            g_policy_trace.reason = reason;
            g_policy_trace.config = config;
            g_policy_trace.device = device;
        }

        inline PolicyDecision select(const TuningKey &key)
        {
            const OperatorFamily family = key.family;
            const DeviceFingerprint device = current_device_fingerprint();
            const CandidateConfig static_config = candidate_config(static_candidate(family));
            if (explicit_legacy(family))
            {
                const CandidateConfig config = candidate_config(legacy_candidate(family));
                set_policy_trace(family, key, config, "legacy", "explicit_legacy_override", device);
                return PolicyDecision{config, key.canonical(), "legacy", "explicit_legacy_override", false};
            }
            if (tuning_disabled())
            {
                set_policy_trace(family, key, static_config, "static", "tuning_disabled", device);
                return PolicyDecision{static_config, key.canonical(), "static", "tuning_disabled", false};
            }

            CandidateId forced;
            if (tuning_forced() && forced_candidate(key, forced))
            {
                const CandidateConfig config = candidate_config(forced);
                if (config_resource_supported(config, key))
                {
                    set_policy_trace(family, key, config, "force", "explicit_candidate", device);
                    return PolicyDecision{config, key.canonical(), "force", "explicit_candidate", false};
                }
            }

            const char *cache_path = std::getenv("CUSIGNAL_ZX_TUNING_CACHE");
            if (!tuning_forced() && cache_path != nullptr && cache_path[0] != '\0' && device.valid)
            {
                const cache_detail::CacheDocument *document =
                    cache_detail::load_cache(std::string(cache_path));
                if (document != nullptr && cache_detail::device_matches(document->device, device))
                {
                    const std::string canonical_key = key.canonical();
                    for (const cache_detail::CacheEntry &entry : document->entries)
                    {
                        CandidateConfig config = candidate_config(entry.candidate);
                        if (entry.family != TuningKey::family_name(family) ||
                            entry.key != canonical_key ||
                            !candidate_belongs_to_family(family, entry.candidate) ||
                            !cache_config_matches(config, entry) ||
                            !config_resource_supported(config, key, entry.workspace_bytes) ||
                            !cache_workspace_available(entry.workspace_bytes))
                        {
                            continue;
                        }
                        config.workspace_bytes = entry.workspace_bytes;
                        config.workspace_peak_bytes = entry.workspace_peak_bytes;
                        config.buffer_count = entry.buffer_count;
                        config.batch_tile = entry.batch_tile;
                        config.memory_tier = static_cast<MemoryTier>(entry.memory_tier);
                        config.plan_variant = entry.plan_variant;
                        set_policy_trace(family, key, config, "cache", "exact_key", device);
                        return PolicyDecision{config, canonical_key, "cache", "exact_key", true};
                    }
                }
            }

            set_policy_trace(family, key, static_config, "static", "cache_miss_or_invalid", device);
            return PolicyDecision{static_config, key.canonical(), "static", "cache_miss_or_invalid", false};
        }

        inline const PolicyTrace &policy_trace_snapshot()
        {
            return g_policy_trace;
        }

        inline const std::string &policy_trace_operator_id()
        {
            return g_policy_trace.operator_id;
        }

        inline bool tuning_trace_enabled()
        {
            return is_truthy(std::getenv("CUSIGNAL_ZX_TUNING_TRACE"));
        }
    } // namespace zx_tile
} // namespace cusignal
