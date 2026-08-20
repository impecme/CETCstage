#!/usr/bin/env python3
"""Offline, finite-candidate autotuner for Zhongkexin C500 operators.

The script deliberately delegates execution to performance.sh.  It never
benchmarks from the production library and never changes the frozen baseline.
The generated JSON is a repository-owned, device-specific lookup cache consumed
by src/common/zx_tile_policy.hpp.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


REGISTRY_VERSION = "zx-c500-appendix53-task-v5"
CACHE_SCHEMA_VERSION = 5
LEVELS = [f"L{index}" for index in range(1, 7)]
SELECTION_VALIDATION_WINNER = "winner-against-static"
OPERATOR_SET_NAMES = ("all81", "task_appendix", "appendix_only", "native_only")
CANDIDATE_PROFILE_NAMES = ("full", "two_day")


def candidate(name: str, **config: int) -> Dict[str, Any]:
    return {"candidate": name, "config": config}


def _generated_candidates(prefix: str) -> List[Dict[str, Any]]:
    """Return finite names understood by CandidateId::*Generated.

    These are not arbitrary JSON knobs: the C++ policy parser accepts only
    this grammar and the corresponding existing kernels consume the fields.
    The matrix is intentionally broad enough to search C500 launch behavior,
    while avoiding a full unsafe Cartesian product.
    """
    result: List[Dict[str, Any]] = []
    threads_values = (64, 128, 256, 512)
    if prefix == "linear":
        tiers = (
            (50, ((1, 1, 1, 1, 1), (2, 2, 1, 1, 1), (4, 4, 1, 1, 1), (8, 4, 1, 1, 1))),
            (75, ((2, 2, 2, 2, 2), (4, 4, 2, 2, 2), (8, 4, 2, 2, 2), (4, 2, 2, 4, 2))),
            (90, ((4, 4, 2, 4, 2), (8, 4, 2, 4, 2), (8, 4, 2, 8, 2))),
        )
        for threads in threads_values:
            for memory_tier, specs in tiers:
                for elements, vector, stages, batch, buffers in specs:
                    name = (
                        f"linear_t{threads}_e{elements}_v{vector}_s{stages}_"
                        f"b{batch}_buf{buffers}_m{memory_tier}"
                    )
                    result.append(candidate(
                        name,
                        threads=threads,
                        tile_rows=1,
                        tile_cols=1,
                        elements_per_thread=elements,
                        rows_per_block=1,
                        vector_width=vector,
                        stages=stages,
                        scan_elements=0,
                        batch_tile=batch,
                        buffer_count=buffers,
                        memory_tier=memory_tier,
                        plan_variant=0,
                    ))
        return result
    if prefix == "row_reduction":
        tiers = (
            (50, ((1, 1, 1, 1, 1), (2, 2, 2, 1, 1), (4, 4, 2, 1, 1), (8, 4, 4, 1, 1))),
            (75, ((2, 2, 2, 2, 2), (4, 4, 4, 2, 2), (8, 4, 4, 2, 2), (4, 4, 8, 2, 2))),
            (90, ((4, 4, 4, 4, 2), (8, 4, 4, 4, 2), (8, 4, 8, 4, 2))),
        )
        for threads in threads_values:
            for memory_tier, specs in tiers:
                for elements, vector, rows, batch, buffers in specs:
                    name = (
                        f"row_t{threads}_e{elements}_r{rows}_v{vector}_s"
                        f"{2 if memory_tier != 50 else 1}_b{batch}_buf{buffers}_m{memory_tier}"
                    )
                    result.append(candidate(
                        name,
                        threads=threads,
                        tile_rows=rows,
                        tile_cols=1,
                        elements_per_thread=elements,
                        rows_per_block=rows,
                        vector_width=vector,
                        stages=2 if memory_tier != 50 else 1,
                        scan_elements=0,
                        batch_tile=batch,
                        buffer_count=buffers,
                        memory_tier=memory_tier,
                        plan_variant=0,
                    ))
        return result
    if prefix == "fir_filter":
        specs = (
            (50, ((1, 1, 1, 1), (2, 1, 1, 1), (4, 1, 1, 1), (8, 1, 1, 1))),
            (75, ((2, 2, 2, 2), (4, 2, 2, 2), (8, 2, 2, 2))),
            (90, ((4, 4, 2, 2), (8, 4, 2, 2), (8, 2, 2, 2))),
        )
        for threads in threads_values:
            for memory_tier, variants in specs:
                for rows, batch, stages, buffers in variants:
                    name = (
                        f"fir_filter_t{threads}_r{rows}_b{batch}_s{stages}_"
                        f"buf{buffers}_m{memory_tier}"
                    )
                    result.append(candidate(
                        name,
                        threads=threads,
                        tile_rows=rows,
                        tile_cols=1,
                        elements_per_thread=1,
                        rows_per_block=rows,
                        vector_width=1,
                        stages=stages,
                        scan_elements=0,
                        batch_tile=batch,
                        buffer_count=buffers,
                        memory_tier=memory_tier,
                        plan_variant=rows,
                    ))
        return result
    raise ValueError(f"unknown generated candidate class: {prefix}")


def _class_candidates(prefix: str) -> List[Dict[str, Any]]:
    if prefix == "linear":
        names = [
            ("linear_m50_t256_e1_v1", dict(threads=256, elements_per_thread=1, vector_width=1, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("linear_m50_t256_e2_v2", dict(threads=256, elements_per_thread=2, vector_width=2, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("linear_m50_t256_e4_v4", dict(threads=256, elements_per_thread=4, vector_width=4, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("linear_m50_t256_e8_v4", dict(threads=256, elements_per_thread=8, vector_width=4, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("linear_m75_t256_e2_v2", dict(threads=256, elements_per_thread=2, vector_width=2, stages=2, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("linear_m75_t256_e4_v4", dict(threads=256, elements_per_thread=4, vector_width=4, stages=2, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("linear_m75_t256_e8_v4", dict(threads=256, elements_per_thread=8, vector_width=4, stages=2, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("linear_m75_t256_e4_v2_b4", dict(threads=256, elements_per_thread=4, vector_width=2, stages=2, batch_tile=4, buffer_count=2, memory_tier=75)),
            ("linear_m90_t256_e4_v4_b4", dict(threads=256, elements_per_thread=4, vector_width=4, stages=2, batch_tile=4, buffer_count=2, memory_tier=90)),
            ("linear_m90_t256_e8_v4_b4", dict(threads=256, elements_per_thread=8, vector_width=4, stages=2, batch_tile=4, buffer_count=2, memory_tier=90)),
            ("linear_m90_t256_e8_v4_b8", dict(threads=256, elements_per_thread=8, vector_width=4, stages=2, batch_tile=8, buffer_count=2, memory_tier=90)),
        ]
        return [candidate(name, **config) for name, config in names] + _generated_candidates(prefix)
    if prefix == "row_reduction":
        names = [
            ("row_m50_t256_e1_r1_v1", dict(threads=256, elements_per_thread=1, rows_per_block=1, vector_width=1, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("row_m50_t256_e2_r2_v2", dict(threads=256, elements_per_thread=2, rows_per_block=2, vector_width=2, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("row_m50_t256_e4_r2_v4", dict(threads=256, elements_per_thread=4, rows_per_block=2, vector_width=4, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("row_m50_t256_e8_r4_v4", dict(threads=256, elements_per_thread=8, rows_per_block=4, vector_width=4, stages=1, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("row_m75_t256_e2_r2_v2", dict(threads=256, elements_per_thread=2, rows_per_block=2, vector_width=2, stages=2, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("row_m75_t256_e4_r4_v4", dict(threads=256, elements_per_thread=4, rows_per_block=4, vector_width=4, stages=2, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("row_m75_t256_e8_r4_v4", dict(threads=256, elements_per_thread=8, rows_per_block=4, vector_width=4, stages=2, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("row_m75_t256_e4_r8_v4", dict(threads=256, elements_per_thread=4, rows_per_block=8, vector_width=4, stages=2, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("row_m90_t256_e4_r4_v4", dict(threads=256, elements_per_thread=4, rows_per_block=4, vector_width=4, stages=2, batch_tile=4, buffer_count=2, memory_tier=90)),
            ("row_m90_t256_e8_r4_v4", dict(threads=256, elements_per_thread=8, rows_per_block=4, vector_width=4, stages=2, batch_tile=4, buffer_count=2, memory_tier=90)),
            ("row_m90_t256_e8_r8_v4", dict(threads=256, elements_per_thread=8, rows_per_block=8, vector_width=4, stages=2, batch_tile=4, buffer_count=2, memory_tier=90)),
            ("row_m90_t256_e8_r8_v4_b4", dict(threads=256, elements_per_thread=8, rows_per_block=8, vector_width=4, stages=2, batch_tile=4, buffer_count=2, memory_tier=90)),
        ]
        return [candidate(name, **config) for name, config in names] + _generated_candidates(prefix)
    if prefix == "fft_batch":
        names = [
            ("fft_batch_m50_b1", dict(threads=256, batch_tile=1, buffer_count=1, memory_tier=50)),
            ("fft_batch_m50_b2", dict(threads=256, batch_tile=2, buffer_count=1, memory_tier=50)),
            ("fft_batch_m50_b4", dict(threads=256, batch_tile=4, buffer_count=1, memory_tier=50)),
            ("fft_batch_m50_b8", dict(threads=256, batch_tile=8, buffer_count=1, memory_tier=50)),
            ("fft_batch_m75_b2", dict(threads=256, batch_tile=2, buffer_count=2, memory_tier=75)),
            ("fft_batch_m75_b4", dict(threads=256, batch_tile=4, buffer_count=2, memory_tier=75)),
            ("fft_batch_m75_b8", dict(threads=256, batch_tile=8, buffer_count=2, memory_tier=75)),
            ("fft_batch_m75_b8_s2", dict(threads=256, batch_tile=8, buffer_count=2, stages=2, plan_variant=2, memory_tier=75)),
            ("fft_batch_m90_b4", dict(threads=256, batch_tile=4, buffer_count=2, memory_tier=90)),
            ("fft_batch_m90_b8", dict(threads=256, batch_tile=8, buffer_count=2, memory_tier=90)),
            ("fft_batch_m90_b8_s2", dict(threads=256, batch_tile=8, buffer_count=2, stages=2, plan_variant=2, memory_tier=90)),
            ("fft_batch_m90_b8_s2_b2", dict(threads=256, batch_tile=8, buffer_count=2, stages=2, plan_variant=2, memory_tier=90)),
        ]
        return [candidate(name, **config) for name, config in names]
    if prefix == "fir_filter":
        names = [
            ("fir_filter_m50_r1", dict(threads=256, rows_per_block=1, plan_variant=1, memory_tier=50)),
            ("fir_filter_m50_r2", dict(threads=256, rows_per_block=2, plan_variant=2, memory_tier=50)),
            ("fir_filter_m50_r4", dict(threads=256, rows_per_block=4, plan_variant=4, memory_tier=50)),
            ("fir_filter_m50_r8", dict(threads=256, rows_per_block=8, plan_variant=8, memory_tier=50)),
            ("fir_filter_m75_r2", dict(threads=256, rows_per_block=2, plan_variant=2, buffer_count=2, batch_tile=2, memory_tier=75)),
            ("fir_filter_m75_r4", dict(threads=256, rows_per_block=4, plan_variant=4, buffer_count=2, batch_tile=2, memory_tier=75)),
            ("fir_filter_m75_r8", dict(threads=256, rows_per_block=8, plan_variant=8, buffer_count=2, batch_tile=2, memory_tier=75)),
            ("fir_filter_m75_r8_b2", dict(threads=256, rows_per_block=8, plan_variant=8, buffer_count=2, batch_tile=2, stages=2, memory_tier=75)),
            ("fir_filter_m90_r4", dict(threads=256, rows_per_block=4, plan_variant=4, buffer_count=2, batch_tile=4, stages=2, memory_tier=90)),
            ("fir_filter_m90_r8", dict(threads=256, rows_per_block=8, plan_variant=8, buffer_count=2, batch_tile=4, stages=2, memory_tier=90)),
            ("fir_filter_m90_r8_b2", dict(threads=256, rows_per_block=8, plan_variant=8, buffer_count=2, batch_tile=2, stages=2, memory_tier=90)),
            ("fir_filter_m90_r8_b4", dict(threads=256, rows_per_block=8, plan_variant=8, buffer_count=2, batch_tile=4, stages=2, memory_tier=90)),
        ]
        return [candidate(name, **config) for name, config in names] + _generated_candidates(prefix)
    raise ValueError(f"unknown candidate class: {prefix}")


def _expanded_candidates(prefix: str) -> List[Dict[str, Any]]:
    """Finite candidate matrices for the families added in registry v4.

    Each row names a real route already present in the C500 implementation.
    The route is intentionally encoded in the candidate name so the C++
    closed parser can reject unknown or malformed cache entries.  This is a
    matrix, not a Cartesian product: it covers thread, element, stage,
    batching and work-path changes without manufacturing combinations that
    no kernel can consume.
    """
    matrices = {
        "window": [
            (128, 1, 1, 1, 1, 1, 50), (256, 1, 2, 1, 1, 1, 50),
            (512, 2, 4, 1, 1, 1, 50), (128, 2, 2, 2, 2, 2, 75),
            (256, 2, 4, 2, 2, 2, 75), (512, 4, 4, 2, 2, 2, 75),
            (256, 4, 4, 3, 4, 2, 90), (512, 4, 4, 3, 4, 2, 90),
        ],
        "spectral": [
            (64, 1, 1, 1, 1, 1, 50), (128, 1, 2, 1, 1, 1, 50),
            (256, 2, 4, 1, 1, 1, 50), (256, 4, 4, 1, 1, 1, 50),
            (128, 1, 2, 2, 2, 2, 75), (256, 2, 4, 2, 2, 2, 75),
            (256, 4, 4, 2, 4, 2, 75), (128, 2, 2, 3, 2, 2, 75),
            (256, 2, 4, 3, 4, 2, 90), (256, 4, 4, 3, 8, 2, 90),
            (256, 4, 4, 4, 4, 2, 90), (256, 4, 4, 4, 8, 2, 90),
        ],
        "filtering": [
            (64, 1, 1, 1, 1, 1, 50), (128, 1, 2, 1, 1, 1, 50),
            (256, 2, 4, 1, 1, 1, 50), (256, 4, 4, 1, 1, 1, 50),
            (128, 1, 2, 2, 2, 2, 75), (256, 2, 4, 2, 2, 2, 75),
            (256, 4, 4, 2, 4, 2, 75), (128, 2, 2, 3, 2, 2, 75),
            (256, 4, 4, 3, 4, 2, 90), (256, 4, 4, 3, 8, 2, 90),
            (128, 2, 2, 4, 2, 2, 90), (256, 4, 4, 4, 4, 2, 90),
        ],
        "wavelet": [
            (64, 1, 1, 1, 1, 1, 50), (128, 1, 2, 1, 1, 1, 50),
            (256, 2, 4, 1, 1, 1, 50), (512, 4, 4, 1, 1, 1, 50),
            (128, 2, 2, 2, 2, 2, 75), (256, 2, 4, 2, 2, 2, 75),
            (256, 4, 4, 3, 4, 2, 90), (512, 4, 4, 3, 8, 2, 90),
        ],
        "radar_aux": [
            (64, 1, 1, 1, 1, 1, 50), (128, 1, 2, 1, 1, 1, 50),
            (256, 2, 4, 1, 1, 1, 50), (256, 4, 4, 1, 1, 1, 50),
            (128, 2, 2, 2, 2, 2, 75), (256, 2, 4, 2, 2, 2, 75),
            (256, 4, 4, 3, 4, 2, 90), (256, 4, 4, 3, 8, 2, 90),
        ],
        "correlate1d": [
            (64, 1, 1, 1, 1, 1, 50), (128, 1, 2, 1, 1, 1, 50),
            (256, 2, 4, 1, 1, 1, 50), (512, 4, 4, 1, 1, 1, 50),
            (128, 2, 2, 2, 2, 2, 75), (256, 2, 4, 2, 2, 2, 75),
            (256, 4, 4, 3, 4, 2, 90), (512, 4, 4, 3, 8, 2, 90),
        ],
        "kalman": [
            (64, 1, 1, 1, 1, 1, 50), (128, 1, 2, 1, 1, 1, 50),
            (256, 2, 4, 1, 1, 1, 50), (512, 4, 4, 1, 1, 1, 50),
            (128, 2, 2, 2, 2, 2, 75), (256, 2, 4, 2, 2, 2, 75),
        ],
        "filter_design": [
            (64, 1, 1, 1, 1, 1, 50), (128, 1, 2, 1, 1, 1, 50),
            (256, 2, 4, 1, 1, 1, 50), (512, 4, 4, 1, 1, 1, 50),
            (128, 2, 2, 2, 2, 2, 75), (256, 2, 4, 2, 2, 2, 75),
            (256, 4, 4, 3, 4, 2, 90), (512, 4, 4, 3, 8, 2, 90),
        ],
    }
    if prefix not in matrices:
        raise ValueError(f"unknown expanded candidate class: {prefix}")
    result: List[Dict[str, Any]] = []
    for index, (threads, elements, vector, route, batch, buffers, tier) in enumerate(matrices[prefix], 1):
        stages = 2 if tier != 50 else 1
        rows = 2 if elements >= 2 else 1
        cols = 2 if vector >= 2 else 1
        result.append(candidate(
            f"{prefix}_t{threads}_e{elements}_v{vector}_r{rows}_s{stages}_"
            f"b{batch}_buf{buffers}_m{tier}_o{route}_y{rows}_z{cols}",
            threads=threads,
            tile_rows=rows,
            tile_cols=cols,
            elements_per_thread=elements,
            rows_per_block=rows,
            vector_width=vector,
            stages=stages,
            scan_elements=0,
            batch_tile=batch,
            buffer_count=buffers,
            memory_tier=tier,
            plan_variant=index % 5,
            route=route,
        ))
    return result


FAMILIES: Dict[str, Dict[str, Any]] = {
    "ca_cfar": {
        "operator": "radartools/ca_cfar",
        "static": "ca_cfar_static",
        "candidates": [
            candidate("ca_cfar_legacy", threads=256, elements_per_thread=2, scan_elements=512),
            candidate("ca_cfar_tiled_t128_e128", threads=128, elements_per_thread=1, scan_elements=128),
            candidate("ca_cfar_tiled_t256_e512", threads=256, elements_per_thread=2, scan_elements=512),
            candidate("ca_cfar_tiled_t512_e1024", threads=512, elements_per_thread=2, scan_elements=1024, stages=2),
        ],
    },
    "pulse_compression": {
        "operator": "radartools/pulse_compression",
        "static": "pulse_compression_static",
        "candidates": [
            candidate("pulse_compression_legacy_plan", threads=256),
            candidate("pulse_compression_split_t128", threads=128),
            candidate("pulse_compression_split_t256", threads=256),
            candidate("pulse_compression_split_t512", threads=512, stages=2),
        ],
    },
    "pulse_doppler": {
        "operator": "radartools/pulse_doppler",
        "static": "pulse_doppler_static",
        "candidates": [
            candidate("pulse_doppler_legacy", threads=256),
            candidate("pulse_doppler_fused_t128", threads=128),
            candidate("pulse_doppler_fused_t256", threads=256),
            candidate("pulse_doppler_fused_t512", threads=512, stages=2),
        ],
    },
    "correlate2d": {
        "operator": "correlate/correlate2d",
        "static": "correlate2d_static",
        "candidates": [
            candidate("correlate2d_generic", threads=256),
            candidate("correlate2d_shared_8x32", threads=256, tile_rows=8, tile_cols=32),
            candidate("correlate2d_shared_16x16", threads=256, tile_rows=16, tile_cols=16),
            candidate("correlate2d_shared_32x8", threads=256, tile_rows=32, tile_cols=8),
            candidate("correlate2d_shared_16x32", threads=512, tile_rows=16, tile_cols=32, stages=2),
            candidate("correlate2d_shared_32x16", threads=512, tile_rows=32, tile_cols=16, stages=2),
        ],
    },
}


def _load_operator_set(operator_set: str) -> List[str]:
    path = Path(__file__).resolve().parents[1] / "tests" / "contracts" / "operator_sets.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    if operator_set not in OPERATOR_SET_NAMES or operator_set not in payload.get("sets", {}):
        raise RuntimeError(f"unknown operator contract set: {operator_set}")
    definition = payload["sets"][operator_set]
    operators = definition["operators"]
    expected_count = int(definition["expected_count"])
    if len(operators) != expected_count or len(set(operators)) != expected_count:
        raise RuntimeError(f"{operator_set} operator contract must contain {expected_count} unique operators")
    return operators


def _load_operator_contract() -> List[str]:
    return _load_operator_set("all81")


LINEAR_OPERATORS = {
    "waveforms/chirp", "waveforms/gausspulse", "waveforms/sawtooth", "waveforms/square",
    "bsplines/cubic", "bsplines/quadratic", "bsplines/gauss_spline",
}
ROW_OPERATORS = {
    "demod/fm_demod",
    "peak_finding/argrelextrema",
    "peak_finding/argrelmin",
    "peak_finding/argrelmax",
}
FIR_OPERATORS = {"filtering/firfilter", "filtering/lfilter"}
STATIC_CANDIDATE_NAMES = {
    "linear": "linear_static",
    # CandidateId::RowStatic is exposed by the C500 policy registry as
    # row_static, even though the Python family is named row_reduction.
    "row_reduction": "row_static",
    "fir_filter": "fir_filter_static",
}

STATIC_ONLY_REASON = {
    "filter_design/kaiser_beta": "host-side scalar coefficient helper; no independent C500 dispatch",
    "filter_design/kaiser_atten": "host-side scalar coefficient helper; no independent C500 dispatch",
    "filter_design/cmplx_sort": "host-side CPU sort contract; no independent C500 dispatch",
    # This public API returns one scalar used by CA-CFAR.  It has no
    # independent GPU workload; CA-CFAR itself remains tunable.
    "radartools/cfar_alpha": "host-side scalar helper used by CA-CFAR; no independent C500 dispatch",
}


EXPANDED_FAMILY_BY_OPERATOR = {
    "waveforms/unit_impulse": "window",
    **{operator: "window" for operator in (
        "windows/get_window", "windows/barthann", "windows/bartlett", "windows/blackman",
        "windows/blackmanharris", "windows/bohman", "windows/boxcar", "windows/chebwin",
        "windows/cosine", "windows/exponential", "windows/flattop", "windows/gaussian",
        "windows/general_cosine", "windows/general_gaussian", "windows/general_hamming",
        "windows/hamming", "windows/hann", "windows/kaiser", "windows/nuttall",
        "windows/parzen", "windows/taylor", "windows/triang", "windows/tukey",
    )},
    **{operator: "filter_design_gpu" for operator in ("filter_design/firwin", "filter_design/firwin2")},
    **{operator: "filtering" for operator in (
        "filtering/wiener", "filtering/firfilter_zi", "filtering/lfilter_zi",
        "filtering/firfilter2", "filtering/filtfilt", "filtering/sosfilt",
        "filtering/hilbert", "filtering/hilbert2", "filtering/detrend",
        "filtering/freq_shift", "filtering/channelize_poly", "filtering/decimate",
        "filtering/resample", "filtering/resample_poly", "filtering/upfirdn",
    )},
    **{operator: "radar_aux" for operator in ("radartools/ambgfun", "radartools/mvdr")},
    **{operator: "spectral" for operator in (
        "spectral/lombscargle", "spectral/periodogram", "spectral/welch", "spectral/csd",
        "spectral/spectrogram", "spectral/stft", "spectral/istft", "spectral/coherence",
        "spectral/vectorstrength",
    )},
    **{operator: "wavelet" for operator in (
        "wavelets/qmf", "wavelets/morlet", "wavelets/ricker", "wavelets/morlet2", "wavelets/cwt",
    )},
    **{operator: "correlate1d" for operator in ("correlate/correlate", "correlate/correlation_lags")},
    "estimation/kalman_filter": "kalman",
}


TASKS: Dict[str, Dict[str, Any]] = {
    "task1_radar": {
        "scope": "task1_radar",
        "static": "task1_static",
        "candidates": [
            candidate("task1_input_t128", threads=128, route=1, stages=1, buffer_count=1, batch_tile=1, memory_tier=50),
            candidate("task1_input_t256", threads=256, route=1, stages=1, buffer_count=1, batch_tile=1, memory_tier=50),
            candidate("task1_input_t512", threads=512, route=1, stages=1, buffer_count=1, batch_tile=1, memory_tier=50),
        ],
    },
    "task2_features": {
        "scope": "task2_features",
        "static": "task2_static",
        "candidates": [
            candidate("task2_direct_t128", threads=128, route=1, stages=1, buffer_count=1, batch_tile=1, memory_tier=50),
            candidate("task2_direct_t256", threads=256, route=1, stages=1, buffer_count=1, batch_tile=1, memory_tier=50),
            candidate("task2_fft_t128", threads=128, route=2, stages=1, buffer_count=2, batch_tile=1, memory_tier=75),
            candidate("task2_fft_t256", threads=256, route=2, stages=1, buffer_count=2, batch_tile=1, memory_tier=75),
        ],
    },
}


def _register_all81() -> List[str]:
    operators = _load_operator_contract()
    keys: List[str] = []
    family_aliases = {
        definition["operator"]: family for family, definition in FAMILIES.items()
    }
    for operator in operators:
        if operator in family_aliases:
            # The first four routes retain their existing family identifiers
            # because the C500 implementations already consume them.
            keys.append(family_aliases[operator])
            continue
        if operator in LINEAR_OPERATORS:
            policy_family = "linear"
            candidates = _class_candidates("linear")
        elif operator in ROW_OPERATORS:
            policy_family = "row_reduction"
            candidates = _class_candidates("row_reduction")
        elif operator in FIR_OPERATORS:
            policy_family = "fir_filter"
            candidates = _class_candidates("fir_filter")
        elif operator in STATIC_ONLY_REASON:
            policy_family = "static"
            candidates = []
        elif operator in EXPANDED_FAMILY_BY_OPERATOR:
            policy_family = EXPANDED_FAMILY_BY_OPERATOR[operator]
            candidate_family = "filter_design" if policy_family == "filter_design_gpu" else policy_family
            candidates = _expanded_candidates(candidate_family)
        else:
            raise RuntimeError(f"all81 operator has no candidate family registration: {operator}")
        FAMILIES[operator] = {
            "operator": operator,
            "policy_family": policy_family,
            "static": (
                STATIC_CANDIDATE_NAMES[policy_family]
                if policy_family in STATIC_CANDIDATE_NAMES
                else "static_operator"
            ),
            "candidates": candidates,
            "static_only_reason": STATIC_ONLY_REASON.get(operator, "") if not candidates else "",
        }
        keys.append(operator)
    return keys


OPERATOR_KEYS = _register_all81()
OPERATOR_ID_TO_FAMILY = {
    definition["operator"]: family for family, definition in FAMILIES.items()
}

TASK_ID_TO_SCOPE = {name: definition["scope"] for name, definition in TASKS.items()}


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def operator_ids_for_set(operator_set: str) -> List[str]:
    operators = _load_operator_set(operator_set)
    unknown = [operator for operator in operators if operator not in OPERATOR_ID_TO_FAMILY]
    if unknown:
        raise RuntimeError(f"operator contract contains unregistered operators: {unknown}")
    return operators


def _two_day_candidate_names(family: str) -> List[str]:
    """Keep a deterministic, representative shortlist for the two-day run.

    The full profile is retained for future exhaustive runs.  The reduced
    profile only trims the three historically largest candidate families;
    every retained shortlist still contains all hand-written M50/M75/M90
    anchors plus generated thread representatives for 64/128/256/512.
    """
    definition = FAMILIES[family]
    base = [definition["static"]] + [item["candidate"] for item in definition["candidates"]]
    policy_family = definition.get("policy_family", family)
    if policy_family not in {"linear", "row_reduction", "fir_filter"} or len(base) <= 17:
        return base

    prefix = {
        "linear": "linear",
        "row_reduction": "row",
        "fir_filter": "fir_filter",
    }[policy_family]
    nonstatic = base[1:]
    manual = [name for name in nonstatic if name.startswith(f"{prefix}_m")]
    generated = [name for name in nonstatic if name.startswith(f"{prefix}_t")]
    selected: List[str] = []
    for threads in (64, 128, 256, 512):
        marker = f"{prefix}_t{threads}_"
        representative = next((name for name in generated if marker in name), None)
        if representative is not None:
            selected.append(representative)
    selected.extend(manual)
    for name in generated:
        if name not in selected:
            selected.append(name)
        if len(selected) >= 16:
            break
    return [base[0], *selected[:16]]


def all_candidate_names(family: str, candidate_profile: str = "full") -> List[str]:
    if candidate_profile not in CANDIDATE_PROFILE_NAMES:
        raise ValueError(f"unknown candidate profile: {candidate_profile}")
    if candidate_profile == "two_day":
        return _two_day_candidate_names(family)
    return [FAMILIES[family]["static"]] + [item["candidate"] for item in FAMILIES[family]["candidates"]]


def iter_workloads(
    families: Iterable[str], candidate_profile: str = "full"
) -> Iterable[tuple[str, str, str]]:
    for family in families:
        operator = FAMILIES[family]["operator"]
        for candidate_name in all_candidate_names(family, candidate_profile):
            yield family, operator, candidate_name


def cache_default_path() -> Path:
    # Keep the final offline artifact with the repository so runtime Auto mode
    # does not depend on a user-specific home-directory cache.
    return project_root() / "data" / "tuning" / "zx_tuning.json"


def resolve_families(
    family_args: Optional[List[str]],
    operator_args: Optional[List[str]],
    operator_set: str = "all81",
) -> List[str]:
    if family_args and operator_args:
        raise SystemExit("--family and --operator cannot be used together")
    selected_operators = set(operator_ids_for_set(operator_set))
    if operator_args:
        outside = [operator for operator in operator_args if operator not in selected_operators]
        if outside:
            raise SystemExit(f"operators outside --operator-set {operator_set}: {', '.join(outside)}")
        return [OPERATOR_ID_TO_FAMILY[operator] for operator in operator_args]
    if family_args:
        outside = [
            family for family in family_args
            if FAMILIES[family]["operator"] not in selected_operators
        ]
        if outside:
            raise SystemExit(f"families outside --operator-set {operator_set}: {', '.join(outside)}")
        return family_args
    return [
        family for family in OPERATOR_KEYS
        if FAMILIES[family]["operator"] in selected_operators
    ]


def structured_key(key: str) -> Dict[str, Any]:
    fields: Dict[str, str] = {}
    for item in key.split("|"):
        if "=" in item:
            name, value = item.split("=", 1)
            fields[name] = value
    shape = [] if not fields.get("shape") else [int(value) for value in fields["shape"].split("x")]
    semantic = [] if not fields.get("semantic") else [int(value) for value in fields["semantic"].split(",")]
    return {
        "family": fields.get("family", key.split("|", 1)[0]),
        "operator_id": fields.get("operator", ""),
        "dtype": int(fields.get("dtype", 0)),
        "layout": int(fields.get("layout", 0)),
        "batch": int(fields.get("batch", 1)),
        "shape": shape,
        "semantic_parameters": semantic,
    }


def run_output_is_complete(output_root: Path, family: str, candidate_name: str) -> bool:
    metadata_path = output_root / "run_metadata.json"
    if not metadata_path.is_file():
        return False
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    aggregate = output_root / "units" / "benchmarks" / "operator_scales.json"
    if metadata.get("family") != family or metadata.get("candidate") != candidate_name or not aggregate.is_file():
        return False
    try:
        metrics = read_metrics(output_root, family, candidate_name)
    except (OSError, RuntimeError, json.JSONDecodeError):
        # A six-row aggregate is not sufficient for resume: a previous
        # binary may have emitted no trace, applied a fallback, or failed the
        # input/correctness gate.  Treat it as incomplete and re-run it.
        return False
    requires_trace = FAMILIES[family].get("policy_family", family) != "static"
    return (
        len(metrics) == len(LEVELS)
        # A real candidate may be safely rejected for a particular shape or
        # semantic workload (for example, FIR shared-memory variants below
        # their minimum axis).  The trace must still prove that the policy
        # seam ran; candidate_applied is kept as a selection gate, not a
        # reason to benchmark the same inapplicable shape forever on resume.
        and (not requires_trace or all(item["trace_present"] for item in metrics))
        and all(item["correctness_status"] == "PASS" for item in metrics)
        and all(item["input_refresh_status"] == "PASS" for item in metrics)
    )


def tuning_env(family: str, candidate_name: str) -> Dict[str, str]:
    env = dict(os.environ)
    definition = FAMILIES[family]
    # The autotuner owns these routing variables for the duration of a run.
    # An inherited legacy override would otherwise make a candidate run a
    # different path than the candidate being measured.
    for name in (
        "CUSIGNAL_ZX_TUNING_CACHE",
        "CUSIGNAL_ZX_CFAR_PATH",
        "CUSIGNAL_ZX_PULSE_PLAN",
        "CUSIGNAL_ZX_DOPPLER_PATH",
        "CUSIGNAL_ZX_DOPPLER_PLAN_MANY",
        "CUSIGNAL_ZX_TUNING_OPERATOR",
    ):
        env.pop(name, None)
    env["CUSIGNAL_ZX_TILE_PATH"] = "auto"
    if candidate_name == definition["static"]:
        env["CUSIGNAL_ZX_TUNING_MODE"] = "off"
        env.pop("CUSIGNAL_ZX_TUNING_FORCE", None)
    else:
        env["CUSIGNAL_ZX_TUNING_MODE"] = "force"
        force_key = definition.get("operator") if family not in {"ca_cfar", "pulse_compression", "pulse_doppler", "correlate2d"} else family
        env["CUSIGNAL_ZX_TUNING_FORCE"] = f"{force_key}={candidate_name}"
        env["CUSIGNAL_ZX_TUNING_OPERATOR"] = definition.get("operator", family)
    env["CUSIGNAL_PERF_FRESH_INPUT"] = "1"
    return env


def invoke_candidate(
    args: argparse.Namespace,
    family: str,
    candidate_name: str,
    output_root: Path,
    round_name: str = "round1",
) -> int:
    root = project_root()
    definition = FAMILIES[family]
    warmup = args.screening_warmup if round_name == "screening" else args.warmup
    repeat = args.screening_repeat if round_name == "screening" else args.repeat
    command = [
        str(root / "scripts" / "performance.sh"),
        "--operators",
        "--operator",
        FAMILIES[family]["operator"],
        "--scale",
        "all",
        "--case-set",
        "full",
        "--warmup",
        str(warmup),
        "--repeat",
        str(repeat),
        "--output-root",
        str(output_root),
        "--build-dir",
        str(args.build_dir),
        "--no-build",
    ]
    if args.frozen_baseline is not None:
        # Keep the immutable baseline immediately before the output options;
        # omit it only for an explicitly non-baseline probe.
        insert_at = command.index("--output-root")
        command[insert_at:insert_at] = ["--frozen-baseline", str(args.frozen_baseline)]
    if args.skip_cpu_timing:
        command.append("--skip-timing-validation")
    print("[zx-autotune] run:", " ".join(command), flush=True)
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "run_metadata.json").write_text(
        json.dumps(
            {
                "schema_version": 3,
                "registry_version": REGISTRY_VERSION,
                "platform": "zhongkexin-c500",
                "family": family,
                "policy_family": definition.get("policy_family", family),
                "operator": definition["operator"],
                "candidate": candidate_name,
                "round": round_name,
                "selection_validation": args.selection_validation,
                "candidate_config": next(
                    (
                        item.get("config", {})
                        for item in definition.get("candidates", [])
                        if item.get("candidate") == candidate_name
                    ),
                    {},
                ),
                "warmup": warmup,
                "repeat": repeat,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    environment = tuning_env(family, candidate_name)
    if args.skip_cpu_timing:
        environment["CUSIGNAL_SKIP_CPU_TIMING"] = "1"
    (output_root / "failure.json").unlink(missing_ok=True)
    completed = subprocess.run(command, cwd=root, env=environment, check=False)
    if completed.returncode != 0:
        write_candidate_failure(
            output_root,
            "operators",
            family,
            candidate_name,
            completed.returncode,
            "performance command returned non-zero",
            command,
        )
    return completed.returncode


def read_metrics(output_root: Path, family: str, candidate_name: str) -> List[Dict[str, Any]]:
    definition = FAMILIES[family]
    expected_trace_family = definition.get("policy_family", family)
    static_candidate = candidate_name == definition["static"]
    aggregate_path = output_root / "units" / "benchmarks" / "operator_scales.json"
    if not aggregate_path.is_file():
        raise RuntimeError(f"missing aggregate candidate metrics: {aggregate_path}")
    rows = json.loads(aggregate_path.read_text(encoding="utf-8")).get("rows", [])
    rows = [row for row in rows if row.get("operator") == FAMILIES[family]["operator"]]
    results: List[Dict[str, Any]] = []
    for row in sorted(rows, key=lambda item: item.get("scale_level", "")):
        level = row.get("scale_level")
        if level not in LEVELS:
            continue
        trace_present = any(
            row.get(name) not in (None, "")
            for name in ("tuning_registry_version", "tuning_family", "tuning_candidate", "tuning_key")
        )
        if trace_present:
            if row.get("tuning_registry_version") != REGISTRY_VERSION or row.get("tuning_family") != expected_trace_family:
                raise RuntimeError(
                    f"candidate trace mismatch at aggregate row {family}/{level}: "
                    f"expected registry/family {REGISTRY_VERSION}/{expected_trace_family}, got "
                    f"{row.get('tuning_registry_version')}/{row.get('tuning_family')}"
                )
        elif not static_candidate:
            raise RuntimeError(
                f"missing candidate trace at aggregate row {family}/{level}: "
                f"{family} requires a real policy dispatch for {candidate_name}"
            )
        operator_id = row.get("tuning_operator_id")
        operator_id_required = expected_trace_family in {
            "linear", "row_reduction", "fir_filter", "window", "spectral",
            "filtering", "wavelet", "radar_aux", "correlate1d", "kalman",
            "filter_design_gpu",
        }
        if trace_present and ((operator_id_required and operator_id != definition["operator"]) or (
            not operator_id_required and operator_id not in (None, "", definition["operator"])
        )):
            raise RuntimeError(
                f"candidate trace operator mismatch at aggregate row {family}/{level}: "
                f"expected {definition['operator']}, got {operator_id}"
            )
        e2e = row.get("gpu_e2e_median_ms")
        kernel = row.get("gpu_kernel_median_ms")
        if not isinstance(e2e, (int, float)) or e2e <= 0:
            raise RuntimeError(f"invalid GPU E2E median in aggregate row: {family}/{level}")
        config = {
            "threads": row.get("tuning_threads"),
            "tile_rows": row.get("tuning_tile_rows"),
            "tile_cols": row.get("tuning_tile_cols"),
            "elements_per_thread": row.get("tuning_elements_per_thread"),
            "rows_per_block": row.get("tuning_rows_per_block"),
            "vector_width": row.get("tuning_vector_width"),
            "stages": row.get("tuning_stages"),
            "scan_elements": row.get("tuning_scan_elements"),
            "workspace_bytes": row.get("tuning_workspace_bytes"),
            "buffer_count": row.get("tuning_buffer_count", 1),
            "batch_tile": row.get("tuning_batch_tile", 1),
            "memory_tier": row.get("tuning_memory_tier", 50),
            "plan_variant": row.get("tuning_plan_variant", 0),
            "route": row.get("tuning_route", 0),
            "workspace_peak_bytes": row.get("tuning_workspace_peak_bytes", 0),
        }
        if not trace_present:
            # Static candidates do not need to call the tuning seam.  They
            # are still measured for the all81 correctness/input-refresh
            # pass, but cannot create an exact cache entry without a real key.
            config.update(
                {
                    "threads": 256,
                    "tile_rows": 1,
                    "tile_cols": 1,
                    "elements_per_thread": 1,
                    "rows_per_block": 1,
                    "vector_width": 1,
                    "stages": 1,
                    "scan_elements": 0,
                }
            )
        required_config_names = (
            "threads", "tile_rows", "tile_cols", "elements_per_thread",
            "rows_per_block", "vector_width", "stages", "scan_elements",
        )
        if any(not isinstance(config[name], (int, float)) for name in required_config_names):
            raise RuntimeError(f"incomplete tuning config in aggregate row: {family}/{level}")
        workspace = config.get("workspace_bytes", 0)
        if not isinstance(workspace, int) or workspace < 0:
            workspace = 0
        results.append(
            {
                "family": family,
                "policy_family": expected_trace_family,
                "operator": definition["operator"],
                "scale_level": level,
                "trace_present": trace_present,
                "key": row.get("tuning_key") if trace_present else None,
                "candidate": candidate_name,
                "candidate_applied": (
                    row.get("tuning_candidate") == candidate_name
                    if trace_present
                    else candidate_name == definition["static"]
                ),
                "gpu_e2e_median_ms": float(e2e),
                "gpu_kernel_median_ms": float(kernel) if isinstance(kernel, (int, float)) and kernel >= 0 else 0.0,
                "correctness_status": row.get("correctness_status", "FAIL"),
                "input_refresh_status": "PASS" if row.get("input_refresh_pass") is True else "FAIL",
                "tuning_source": row.get("tuning_source"),
                "tuning_reason": row.get("tuning_reason"),
                "workspace_bytes": workspace,
                "config": config,
                "device": {
                    "id": row.get("tuning_device_id"),
                    "name": row.get("tuning_device_name"),
                    "runtime_version": row.get("tuning_runtime_version"),
                    "compute_major": row.get("tuning_compute_major"),
                    "compute_minor": row.get("tuning_compute_minor"),
                    "total_global_mem": row.get("tuning_total_global_mem"),
                    "target": row.get("tuning_device_target"),
                },
                "metrics_path": str(aggregate_path),
            }
        )
    if len(results) != len(LEVELS):
        raise RuntimeError(f"aggregate candidate metrics incomplete for {family}: {len(results)}/{len(LEVELS)}")
    return results


def all_task_candidate_names(task: str) -> List[str]:
    definition = TASKS[task]
    return [definition["static"]] + [item["candidate"] for item in definition["candidates"]]


def task_tuning_env(task: str, candidate_name: str, operator_cache: Optional[Path]) -> Dict[str, str]:
    env = dict(os.environ)
    for name in (
        "CUSIGNAL_ZX_TASK_TUNING_CACHE",
        "CUSIGNAL_ZX_TASK_TUNING_FORCE",
        "CUSIGNAL_ZX_TUNING_FORCE",
    ):
        env.pop(name, None)
    # Task runs consume the already-frozen operator cache.  This keeps public
    # pulse-compression/doppler/CFAR paths separate from private task routes.
    env["CUSIGNAL_ZX_TUNING_MODE"] = "auto"
    if operator_cache is not None:
        env["CUSIGNAL_ZX_TUNING_CACHE"] = str(operator_cache)
    definition = TASKS[task]
    if candidate_name == definition["static"]:
        env["CUSIGNAL_ZX_TASK_TUNING_MODE"] = "off"
    else:
        env["CUSIGNAL_ZX_TASK_TUNING_MODE"] = "force"
        env["CUSIGNAL_ZX_TASK_TUNING_FORCE"] = f"{task}={candidate_name}"
    env["CUSIGNAL_PERF_FRESH_INPUT"] = "1"
    return env


def invoke_task_candidate(
    args: argparse.Namespace,
    task: str,
    candidate_name: str,
    output_root: Path,
    round_name: str,
) -> int:
    root = project_root()
    warmup = args.screening_warmup if round_name == "screening" else args.warmup
    repeat = args.screening_repeat if round_name == "screening" else args.repeat
    command = [
        str(root / "scripts" / "performance.sh"),
        "--tasks",
        "--task",
        "task1" if task == "task1_radar" else "task2",
        "--scale",
        "all",
        "--case-set",
        "full",
        "--warmup",
        str(warmup),
        "--repeat",
        str(repeat),
        "--output-root",
        str(output_root),
        "--build-dir",
        str(args.build_dir),
        "--no-build",
    ]
    if args.skip_cpu_timing:
        command.append("--skip-timing-validation")
    print("[zx-autotune] run task:", " ".join(command), flush=True)
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "run_metadata.json").write_text(
        json.dumps(
            {
                "schema_version": 3,
                "registry_version": REGISTRY_VERSION,
                "platform": "zhongkexin-c500",
                "scope": "task",
                "task": task,
                "candidate": candidate_name,
                "round": round_name,
                "candidate_config": next(
                    (item.get("config", {}) for item in TASKS[task]["candidates"]
                     if item.get("candidate") == candidate_name),
                    {},
                ),
                "warmup": warmup,
                "repeat": repeat,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )
    environment = task_tuning_env(task, candidate_name, args.cache_output)
    if args.skip_cpu_timing:
        environment["CUSIGNAL_SKIP_CPU_TIMING"] = "1"
    (output_root / "failure.json").unlink(missing_ok=True)
    completed = subprocess.run(command, cwd=root, env=environment, check=False)
    if completed.returncode != 0:
        write_candidate_failure(
            output_root,
            "tasks",
            task,
            candidate_name,
            completed.returncode,
            "performance command returned non-zero",
            command,
        )
    return completed.returncode


def read_task_metrics(output_root: Path, task: str, candidate_name: str) -> List[Dict[str, Any]]:
    definition = TASKS[task]
    aggregate_path = output_root / "demo" / task / "summary.csv"
    if not aggregate_path.is_file():
        raise RuntimeError(f"missing task aggregate candidate metrics: {aggregate_path}")
    import csv

    with aggregate_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))

    def optional_int(row: Dict[str, str], field: str) -> Optional[int]:
        value = row.get(field)
        if value in (None, ""):
            return None
        try:
            return int(float(value))
        except (TypeError, ValueError):
            raise RuntimeError(f"invalid task device field {field} in {task}")

    def optional_text(row: Dict[str, str], field: str) -> Optional[str]:
        value = row.get(field)
        return value if value not in (None, "") else None

    results: List[Dict[str, Any]] = []
    for row in sorted(rows, key=lambda item: item.get("scale", "")):
        level = row.get("scale")
        if level not in LEVELS:
            continue
        trace_candidate = row.get("task_tuning_candidate", "")
        trace_key = row.get("task_tuning_key", "")
        if row.get("task_tuning_registry_version") != REGISTRY_VERSION or not trace_key:
            raise RuntimeError(f"missing task trace at aggregate row {task}/{level}")
        if trace_candidate != candidate_name and candidate_name != definition["static"]:
            # A forced task candidate that fell back to static is a measured
            # failure, not a successful candidate application.
            candidate_applied = False
        else:
            candidate_applied = trace_candidate == candidate_name
        e2e = row.get("gpu_e2e_ms")
        kernel = row.get("gpu_kernel_ms")
        try:
            e2e_value = float(e2e)
        except (TypeError, ValueError):
            raise RuntimeError(f"invalid task GPU E2E median in {task}/{level}")
        try:
            kernel_value = float(kernel) if kernel not in (None, "") else 0.0
        except (TypeError, ValueError):
            kernel_value = 0.0
        correctness = "PASS" if row.get("validation_pass") == "PASS" else "FAIL"
        results.append(
            {
                "family": task,
                "task": task,
                "scale_level": level,
                "key": trace_key,
                "candidate": candidate_name,
                "candidate_applied": candidate_applied,
                "gpu_e2e_median_ms": e2e_value,
                "gpu_kernel_median_ms": kernel_value,
                "correctness_status": correctness,
                "input_refresh_status": "PASS" if correctness == "PASS" else "FAIL",
                "tuning_source": row.get("task_tuning_source"),
                "tuning_reason": row.get("task_tuning_reason"),
                "workspace_bytes": int(float(row.get("task_tuning_workspace_bytes") or 0)),
                "config": {
                    "threads": int(float(row.get("task_tuning_threads") or 256)),
                    "elements_per_thread": 1,
                    "rows_per_block": 1,
                    "tile_rows": 1,
                    "tile_cols": 1,
                    "stages": 1,
                    "buffer_count": 1,
                    "batch_tile": 1,
                    "memory_tier": 50,
                    "route": int(float(row.get("task_tuning_route") or 0)),
                    "workspace_bytes": int(float(row.get("task_tuning_workspace_bytes") or 0)),
                    "workspace_peak_bytes": int(float(row.get("task_tuning_workspace_peak_bytes") or 0)),
                },
                "device": {
                    "id": optional_int(row, "task_tuning_device_id"),
                    "name": optional_text(row, "task_tuning_device_name"),
                    "runtime_version": optional_int(row, "task_tuning_runtime_version"),
                    "compute_major": optional_int(row, "task_tuning_compute_major"),
                    "compute_minor": optional_int(row, "task_tuning_compute_minor"),
                    "total_global_mem": optional_int(row, "task_tuning_total_global_mem"),
                    "target": optional_text(row, "task_tuning_device_target"),
                },
                "metrics_path": str(aggregate_path),
            }
        )
    if len(results) != len(LEVELS):
        raise RuntimeError(f"aggregate task metrics incomplete for {task}: {len(results)}/{len(LEVELS)}")
    return results


def _valid_results_by_key(results: List[Dict[str, Any]]) -> Dict[str, List[Dict[str, Any]]]:
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    for result in results:
        key = result.get("key")
        if not key:
            continue
        if (
            result["correctness_status"] == "PASS"
            and result["input_refresh_status"] == "PASS"
            and result.get("candidate_applied") is True
        ):
            grouped.setdefault(str(key), []).append(result)
    return grouped


def provisional_candidate_names(results: List[Dict[str, Any]], family: str) -> List[str]:
    """Return first-round winners that need a second static A/B validation."""

    definition = FAMILIES[family]
    static_name = definition["static"]
    names = set()
    for candidates in _valid_results_by_key(results).values():
        static = next((item for item in candidates if item["candidate"] == static_name), None)
        if static is None:
            continue
        winner = min(candidates, key=lambda item: item["gpu_e2e_median_ms"])
        if (
            winner["candidate"] != static_name
            and winner["gpu_e2e_median_ms"] < static["gpu_e2e_median_ms"]
        ):
            names.add(winner["candidate"])
    return sorted(names)


def select_cache_entries(
    results: List[Dict[str, Any]],
    family: str,
    validation_results: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    for result in results:
        if result.get("key"):
            grouped.setdefault(str(result["key"]), []).append(result)
    validation_grouped: Dict[str, List[Dict[str, Any]]] = {}
    if validation_results is not None:
        for result in validation_results:
            if result.get("key"):
                validation_grouped.setdefault(str(result["key"]), []).append(result)
    definition = FAMILIES[family]
    static_name = definition["static"]
    entries: List[Dict[str, Any]] = []
    for key, candidates in sorted(grouped.items()):
        valid = _valid_results_by_key(candidates).get(key, [])
        if not valid:
            continue
        first_static = next((item for item in valid if item["candidate"] == static_name), None)
        if first_static is None:
            continue
        first_winner = min(valid, key=lambda item: item["gpu_e2e_median_ms"])

        if validation_results is None:
            static = first_static
            winner = first_winner
            selection = {
                "static_candidate": static_name,
                "static_gpu_e2e_median_ms": static["gpu_e2e_median_ms"],
                "winner_gpu_e2e_median_ms": winner["gpu_e2e_median_ms"],
                "validation_round": "none",
            }
        else:
            # A second round is only meaningful for a non-static first-round
            # winner.  If the first-round winner was static, keep the safe
            # fallback and publish no cache entry for this key.
            if first_winner["candidate"] == static_name:
                continue
            second_valid = _valid_results_by_key(validation_grouped.get(key, [])).get(key, [])
            static = next((item for item in second_valid if item["candidate"] == static_name), None)
            winner = next(
                (item for item in second_valid if item["candidate"] == first_winner["candidate"]),
                None,
            )
            if static is None or winner is None:
                continue
            if winner["gpu_e2e_median_ms"] >= static["gpu_e2e_median_ms"]:
                continue
            selection = {
                "static_candidate": static_name,
                "static_gpu_e2e_median_ms": static["gpu_e2e_median_ms"],
                "winner_gpu_e2e_median_ms": winner["gpu_e2e_median_ms"],
                "validation_round": SELECTION_VALIDATION_WINNER,
                "round1_static_gpu_e2e_median_ms": first_static["gpu_e2e_median_ms"],
                "round1_winner_candidate": first_winner["candidate"],
                "round1_winner_gpu_e2e_median_ms": first_winner["gpu_e2e_median_ms"],
            }

        # A cache entry is an optimization only.  Static behavior remains the
        # safe fallback and is not duplicated in the repository cache.
        if winner["candidate"] == static_name or winner["gpu_e2e_median_ms"] >= static["gpu_e2e_median_ms"]:
            continue
        config = dict(winner.get("config", {}))
        config.setdefault("workspace_bytes", winner.get("workspace_bytes", 0))
        entries.append(
            {
                "family": definition.get("policy_family", family),
                "policy_family": definition.get("policy_family", family),
                "operator_id": definition.get("operator"),
                "key": key,
                "key_fields": structured_key(key),
                "candidate": winner["candidate"],
                "config": config,
                "gpu_e2e_median_ms": winner["gpu_e2e_median_ms"],
                "gpu_kernel_median_ms": winner["gpu_kernel_median_ms"],
                "correctness_status": "PASS",
                "input_refresh_status": "PASS",
                "selection": selection,
            }
        )
    return entries


def device_from_results(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    required = ("id", "name", "runtime_version", "compute_major", "compute_minor", "total_global_mem")
    devices = [
        item.get("device")
        for item in results
        if isinstance(item.get("device"), dict)
        and all(item.get("device", {}).get(key) is not None for key in required)
    ]
    if not devices:
        # Static-only operators deliberately do not emit a tuning trace or a
        # device fingerprint.  They still participate in correctness and
        # input-refresh validation, but have no cache entry to publish.
        return {}
    first = {key: devices[0].get(key) for key in required}
    if any(first[key] is None for key in required):
        raise RuntimeError("incomplete device fingerprint in candidate report")
    if any({key: device.get(key) for key in required} != first for device in devices[1:]):
        raise RuntimeError("candidate reports came from different device fingerprints")
    first["target"] = devices[0].get("target") or "c500"
    return first


def write_cache(
    path: Path,
    results: List[Dict[str, Any]],
    entries: List[Dict[str, Any]],
    task_entries: Optional[List[Dict[str, Any]]] = None,
    operator_set: str = "all81",
    candidate_profile: str = "full",
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    device = device_from_results(results)
    if not device:
        if entries or task_entries:
            raise RuntimeError("cache entries require a device fingerprint")
        print(f"[zx-autotune] no tunable candidate/device for {path}; cache not written")
        return
    payload = {
        "schema_version": CACHE_SCHEMA_VERSION,
        "registry_version": REGISTRY_VERSION,
        "platform": "zhongkexin-c500",
        "operator_set": operator_set,
        "candidate_profile": candidate_profile,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "device": device,
        "selection_policy": (
            "exact_key;correctness_pass;input_refresh_pass;candidate_applied;"
            "gpu_e2e_median_min;winner_against_static_round2"
        ),
        "entries": entries,
        "task_entries": task_entries or [],
    }
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)
    print(f"[zx-autotune] cache written: {path} entries={len(entries)}")


def run_candidate_round(
    args: argparse.Namespace,
    families: List[str],
    round_root: Path,
    round_name: str,
    candidate_names: Optional[Dict[str, List[str]]] = None,
) -> List[Dict[str, Any]]:
    all_results: List[Dict[str, Any]] = []
    for family in families:
        if candidate_names is None:
            names = all_candidate_names(family, args.candidate_profile)
        else:
            names = candidate_names.get(family, [])
        for candidate_name in names:
            output_root = round_root / family / candidate_name
            failure = read_candidate_failure(output_root)
            if args.resume and failure is not None:
                metrics = failed_candidate_metrics("operators", family, candidate_name, output_root)
            else:
                if not args.resume or not run_output_is_complete(output_root, family, candidate_name):
                    return_code = invoke_candidate(args, family, candidate_name, output_root, round_name)
                    failure = read_candidate_failure(output_root)
                    if return_code != 0 and failure is None:
                        write_candidate_failure(
                            output_root,
                            "operators",
                            family,
                            candidate_name,
                            return_code,
                            "performance command returned non-zero",
                        )
                        failure = read_candidate_failure(output_root)
                    if return_code != 0 or failure is not None:
                        metrics = failed_candidate_metrics("operators", family, candidate_name, output_root)
                    else:
                        try:
                            metrics = read_metrics(output_root, family, candidate_name)
                        except (OSError, RuntimeError, json.JSONDecodeError) as error:
                            write_candidate_failure(
                                output_root,
                                "operators",
                                family,
                                candidate_name,
                                1,
                                f"invalid candidate report: {error}",
                            )
                            metrics = failed_candidate_metrics("operators", family, candidate_name, output_root)
                else:
                    metrics = read_metrics(output_root, family, candidate_name)
            all_results.extend(metrics)
            record_candidate_workloads(args, "operators", family, candidate_name, metrics)
    return all_results


def run_task_candidate_round(
    args: argparse.Namespace,
    tasks: List[str],
    round_root: Path,
    round_name: str,
    candidate_names: Optional[Dict[str, List[str]]] = None,
) -> List[Dict[str, Any]]:
    all_results: List[Dict[str, Any]] = []
    for task in tasks:
        names = all_task_candidate_names(task) if candidate_names is None else candidate_names.get(task, [])
        for candidate_name in names:
            output_root = round_root / task / candidate_name
            failure = read_candidate_failure(output_root)
            if args.resume and failure is not None:
                metrics = failed_candidate_metrics("tasks", task, candidate_name, output_root)
            else:
                if not args.resume or not run_task_output_is_complete(output_root, task, candidate_name):
                    return_code = invoke_task_candidate(args, task, candidate_name, output_root, round_name)
                    failure = read_candidate_failure(output_root)
                    if return_code != 0 and failure is None:
                        write_candidate_failure(
                            output_root,
                            "tasks",
                            task,
                            candidate_name,
                            return_code,
                            "performance command returned non-zero",
                        )
                        failure = read_candidate_failure(output_root)
                    if return_code != 0 or failure is not None:
                        metrics = failed_candidate_metrics("tasks", task, candidate_name, output_root)
                    else:
                        try:
                            metrics = read_task_metrics(output_root, task, candidate_name)
                        except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
                            write_candidate_failure(
                                output_root,
                                "tasks",
                                task,
                                candidate_name,
                                1,
                                f"invalid candidate report: {error}",
                            )
                            metrics = failed_candidate_metrics("tasks", task, candidate_name, output_root)
                else:
                    metrics = read_task_metrics(output_root, task, candidate_name)
            all_results.extend(metrics)
            record_candidate_workloads(args, "tasks", task, candidate_name, metrics)
    return all_results


def run_task_output_is_complete(output_root: Path, task: str, candidate_name: str) -> bool:
    metadata_path = output_root / "run_metadata.json"
    if not metadata_path.is_file():
        return False
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        metrics = read_task_metrics(output_root, task, candidate_name)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError):
        return False
    return (
        metadata.get("task") == task
        and metadata.get("candidate") == candidate_name
        and len(metrics) == len(LEVELS)
        and all(item["correctness_status"] == "PASS" for item in metrics)
        and all(item["input_refresh_status"] == "PASS" for item in metrics)
    )


def atomic_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def write_candidate_failure(
    output_root: Path,
    scope: str,
    family_or_task: str,
    candidate_name: str,
    return_code: int,
    reason: str,
    command: Optional[List[str]] = None,
) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    atomic_json(
        output_root / "failure.json",
        {
            "scope": scope,
            "family_or_task": family_or_task,
            "candidate": candidate_name,
            "return_code": return_code,
            "reason": reason,
            "command": command or [],
            "updated_at": datetime.now(timezone.utc).isoformat(),
        },
    )


def read_candidate_failure(output_root: Path) -> Optional[Dict[str, Any]]:
    path = output_root / "failure.json"
    if not path.is_file():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"reason": "invalid failure record", "return_code": 1}
    return payload if isinstance(payload, dict) else {"reason": "invalid failure record", "return_code": 1}


def failed_candidate_metrics(
    scope: str,
    family_or_task: str,
    candidate_name: str,
    output_root: Path,
) -> List[Dict[str, Any]]:
    failure = read_candidate_failure(output_root) or {
        "reason": "candidate execution failed without a failure record",
        "return_code": 1,
    }
    if scope == "operators":
        definition = FAMILIES[family_or_task]
        config = next(
            (
                dict(item.get("config", {}))
                for item in definition.get("candidates", [])
                if item.get("candidate") == candidate_name
            ),
            {},
        )
        policy_family = definition.get("policy_family", family_or_task)
        operator = definition.get("operator")
    else:
        definition = TASKS[family_or_task]
        config = next(
            (
                dict(item.get("config", {}))
                for item in definition.get("candidates", [])
                if item.get("candidate") == candidate_name
            ),
            {},
        )
        policy_family = None
        operator = None

    return [
        {
            "family": family_or_task,
            "policy_family": policy_family,
            "operator": operator,
            "task": family_or_task if scope == "tasks" else None,
            "scale_level": level,
            "trace_present": False,
            "key": None,
            "candidate": candidate_name,
            "candidate_applied": False,
            "gpu_e2e_median_ms": None,
            "gpu_kernel_median_ms": None,
            "correctness_status": "FAIL",
            "input_refresh_status": "FAIL",
            "failure_reason": failure.get("reason", "candidate execution failed"),
            "return_code": failure.get("return_code"),
            "workspace_bytes": 0,
            "config": config,
            "device": {},
            "metrics_path": str(output_root / "failure.json"),
        }
        for level in LEVELS
    ]


def record_candidate_workloads(
    args: argparse.Namespace,
    scope: str,
    family_or_task: str,
    candidate_name: str,
    results: List[Dict[str, Any]],
) -> None:
    if args.state_root is None:
        return
    for result in results:
        level = result.get("scale_level", "unknown")
        state_path = args.state_root / "state" / scope / family_or_task / candidate_name / f"{level}.json"
        atomic_json(
            state_path,
            {
                "scope": scope,
                "family_or_task": family_or_task,
                "candidate": candidate_name,
                "scale_level": level,
                "key": result.get("key"),
                "candidate_applied": result.get("candidate_applied"),
                "correctness_status": result.get("correctness_status"),
                "input_refresh_status": result.get("input_refresh_status"),
                "gpu_e2e_median_ms": result.get("gpu_e2e_median_ms"),
                "gpu_kernel_median_ms": result.get("gpu_kernel_median_ms"),
                "workspace_bytes": result.get("workspace_bytes", 0),
                "failure_reason": result.get("failure_reason"),
                "return_code": result.get("return_code"),
                "metrics_path": result.get("metrics_path"),
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
        )
    if args.state_root is not None:
        atomic_json(
            args.state_root / "heartbeat.json",
            {"scope": scope, "family_or_task": family_or_task, "candidate": candidate_name,
             "updated_at": datetime.now(timezone.utc).isoformat()},
        )


def validation_candidate_names(
    first_results: List[Dict[str, Any]], families: List[str]
) -> Dict[str, List[str]]:
    names_by_family: Dict[str, List[str]] = {}
    for family in families:
        winners = provisional_candidate_names(
            [item for item in first_results if item["family"] == family], family
        )
        if winners:
            names_by_family[family] = [FAMILIES[family]["static"], *winners]
    return names_by_family


def formal_candidate_names(
    screening_results: List[Dict[str, Any]],
    families: List[str],
) -> Dict[str, List[str]]:
    """Select up to three screening winners per exact key plus static."""
    selected: Dict[str, List[str]] = {}
    for family in families:
        definition = FAMILIES[family]
        grouped: Dict[str, Dict[str, List[float]]] = {}
        for item in screening_results:
            if item["family"] != family or not item.get("key"):
                continue
            if item["correctness_status"] != "PASS" or item["input_refresh_status"] != "PASS":
                continue
            grouped.setdefault(str(item["key"]), {}).setdefault(item["candidate"], []).append(
                float(item["gpu_e2e_median_ms"])
            )
        ranked_names: List[str] = []
        for candidates in grouped.values():
            ranked = sorted(
                ((sum(values) / len(values), name) for name, values in candidates.items()),
                key=lambda item: item[0],
            )
            ranked_names.extend(name for _, name in ranked[:3])
        unique = []
        for name in [definition["static"], *ranked_names]:
            if name not in unique:
                unique.append(name)
        selected[family] = unique
    return selected


def formal_task_candidate_names(
    screening_results: List[Dict[str, Any]],
    tasks: List[str],
) -> Dict[str, List[str]]:
    selected: Dict[str, List[str]] = {}
    for task in tasks:
        grouped: Dict[str, Dict[str, List[float]]] = {}
        for item in screening_results:
            if item["task"] != task or not item.get("key"):
                continue
            if item["correctness_status"] != "PASS" or item["input_refresh_status"] != "PASS":
                continue
            grouped.setdefault(str(item["key"]), {}).setdefault(item["candidate"], []).append(
                float(item["gpu_e2e_median_ms"])
            )
        ranked_names: List[str] = []
        for candidates in grouped.values():
            ranked = sorted(
                ((sum(values) / len(values), name) for name, values in candidates.items()),
                key=lambda item: item[0],
            )
            ranked_names.extend(name for _, name in ranked[:3])
        unique: List[str] = []
        for name in [TASKS[task]["static"], *ranked_names]:
            if name not in unique:
                unique.append(name)
        selected[task] = unique
    return selected


def provisional_task_candidate_names(results: List[Dict[str, Any]], task: str) -> List[str]:
    definition = TASKS[task]
    static_name = definition["static"]
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    for item in results:
        if item.get("key"):
            grouped.setdefault(str(item["key"]), []).append(item)
    names = set()
    for values in grouped.values():
        valid = [
            item for item in values
            if item["correctness_status"] == "PASS"
            and item["input_refresh_status"] == "PASS"
            and item.get("candidate_applied") is True
        ]
        static = next((item for item in valid if item["candidate"] == static_name), None)
        if static is None:
            continue
        winner = min(valid, key=lambda item: item["gpu_e2e_median_ms"])
        if winner["candidate"] != static_name and winner["gpu_e2e_median_ms"] < static["gpu_e2e_median_ms"]:
            names.add(winner["candidate"])
    return sorted(names)


def select_task_cache_entries(
    results: List[Dict[str, Any]],
    task: str,
    validation_results: Optional[List[Dict[str, Any]]] = None,
) -> List[Dict[str, Any]]:
    definition = TASKS[task]
    static_name = definition["static"]
    grouped: Dict[str, List[Dict[str, Any]]] = {}
    for item in results:
        if item.get("key"):
            grouped.setdefault(str(item["key"]), []).append(item)
    validation_grouped: Dict[str, List[Dict[str, Any]]] = {}
    if validation_results is not None:
        for item in validation_results:
            if item.get("key"):
                validation_grouped.setdefault(str(item["key"]), []).append(item)
    entries: List[Dict[str, Any]] = []
    for key, values in sorted(grouped.items()):
        valid = [
            item for item in values
            if item["correctness_status"] == "PASS"
            and item["input_refresh_status"] == "PASS"
            and item.get("candidate_applied") is True
        ]
        static_first = next((item for item in valid if item["candidate"] == static_name), None)
        if static_first is None:
            continue
        first = min(valid, key=lambda item: item["gpu_e2e_median_ms"])
        if first["candidate"] == static_name:
            continue
        if validation_results is None:
            static = static_first
            winner = first
            selection = {"validation_round": "none"}
        else:
            second = [
                item for item in validation_grouped.get(key, [])
                if item["correctness_status"] == "PASS"
                and item["input_refresh_status"] == "PASS"
                and item.get("candidate_applied") is True
            ]
            static = next((item for item in second if item["candidate"] == static_name), None)
            winner = next((item for item in second if item["candidate"] == first["candidate"]), None)
            if static is None or winner is None or winner["gpu_e2e_median_ms"] >= static["gpu_e2e_median_ms"]:
                continue
            selection = {
                "validation_round": SELECTION_VALIDATION_WINNER,
                "round1_static_gpu_e2e_median_ms": static_first["gpu_e2e_median_ms"],
                "round1_winner_candidate": first["candidate"],
                "round1_winner_gpu_e2e_median_ms": first["gpu_e2e_median_ms"],
            }
        if winner["candidate"] == static_name or winner["gpu_e2e_median_ms"] >= static["gpu_e2e_median_ms"]:
            continue
        entries.append(
            {
                "scope": task,
                "task_id": task,
                "key": key,
                "candidate": winner["candidate"],
                "config": dict(winner.get("config", {})),
                "gpu_e2e_median_ms": winner["gpu_e2e_median_ms"],
                "gpu_kernel_median_ms": winner["gpu_kernel_median_ms"],
                "workspace_bytes": winner.get("workspace_bytes", 0),
                "correctness_status": "PASS",
                "input_refresh_status": "PASS",
                "selection": selection,
            }
        )
    return entries


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scope",
        choices=["operators", "tasks", "all"],
        default="operators",
        help="tuning scope; operators keeps the backward-compatible default",
    )
    parser.add_argument(
        "--operator-set",
        choices=OPERATOR_SET_NAMES,
        default="all81",
        help="operator contract set; task_appendix is the 53-operator appendix",
    )
    parser.add_argument(
        "--candidate-profile",
        choices=CANDIDATE_PROFILE_NAMES,
        default="full",
        help="full registry or the reduced representative two-day shortlist",
    )
    parser.add_argument("--family", choices=sorted(FAMILIES), action="append", help="family to tune; repeatable")
    parser.add_argument(
        "--operator",
        choices=sorted(OPERATOR_ID_TO_FAMILY),
        action="append",
        help="exact operator to tune; repeatable",
    )
    parser.add_argument("--frozen-baseline", type=Path, required=False)
    parser.add_argument("--output-root", type=Path, default=project_root() / "data/reports/autotune/tuning_runs")
    parser.add_argument("--cache-output", type=Path, default=cache_default_path())
    parser.add_argument("--state-root", type=Path, default=None)
    parser.add_argument("--task", choices=sorted(TASKS), action="append", help="task to tune; repeatable")
    parser.add_argument("--build-dir", type=Path, default=project_root() / "build-zx")
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--repeat", type=int, default=30)
    parser.add_argument("--screening-warmup", type=int, default=2)
    parser.add_argument("--screening-repeat", type=int, default=5)
    parser.add_argument("--skip-cpu-timing", action="store_true")
    parser.add_argument(
        "--selection-validation",
        choices=["none", SELECTION_VALIDATION_WINNER],
        default=SELECTION_VALIDATION_WINNER,
        help="validate first-round winners against the static path before writing cache",
    )
    parser.add_argument("--resume", action="store_true", help="reuse complete candidate output directories")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--list-candidates", action="store_true")
    return parser


def initialize_run_state(
    args: argparse.Namespace,
    families: List[str],
    tasks: List[str],
) -> None:
    if args.state_root is None:
        return
    for directory in ("logs", "state", "results", "cache"):
        (args.state_root / directory).mkdir(parents=True, exist_ok=True)
    operator_workloads = [
        {"family": family, "operator": FAMILIES[family]["operator"], "scale_level": level,
         "candidates": all_candidate_names(family, args.candidate_profile)}
        for family in families for level in LEVELS
    ]
    task_workloads = [
        {"task": task, "scale_level": level, "candidates": all_task_candidate_names(task)}
        for task in tasks for level in LEVELS
    ]
    manifest = {
            "schema_version": 3,
            "registry_version": REGISTRY_VERSION,
            "platform": "zhongkexin-c500",
            "scope": args.scope,
            "operator_set": args.operator_set,
            "candidate_profile": args.candidate_profile,
            "operator_count": len({FAMILIES[family]["operator"] for family in families}),
            "operator_workload_count": len(operator_workloads),
            "task_workload_count": len(task_workloads),
            "candidate_count": {
                "operators": sum(len(all_candidate_names(family, args.candidate_profile)) for family in families),
                "tasks": sum(len(all_task_candidate_names(task)) for task in tasks),
            },
            "static_only": {
                family: FAMILIES[family].get("static_only_reason", "")
                for family in families if FAMILIES[family].get("static_only_reason")
            },
            "operator_workloads": operator_workloads,
            "task_workloads": task_workloads,
            "created_at": datetime.now(timezone.utc).isoformat(),
        }
    if not args.resume or not (args.state_root / "manifest.json").is_file():
        atomic_json(args.state_root / "manifest.json", manifest)
    if not args.resume or not (args.state_root / "status.json").is_file():
        atomic_json(
            args.state_root / "status.json",
            {
            "status": "initialized",
            "phase": "manifest",
            "registry_version": REGISTRY_VERSION,
            "updated_at": datetime.now(timezone.utc).isoformat(),
            },
        )


def update_run_status(args: argparse.Namespace, **fields: Any) -> None:
    if args.state_root is None:
        return
    payload = {"registry_version": REGISTRY_VERSION, "updated_at": datetime.now(timezone.utc).isoformat()}
    status_path = args.state_root / "status.json"
    if status_path.is_file():
        try:
            payload.update(json.loads(status_path.read_text(encoding="utf-8")))
        except (OSError, json.JSONDecodeError):
            pass
    payload.update(fields)
    atomic_json(status_path, payload)


@contextlib.contextmanager
def run_lock(args: argparse.Namespace):
    if args.state_root is None:
        yield
        return
    lock_path = args.state_root / "lock"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w", encoding="utf-8") as handle:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(f"another autotune process owns {lock_path}")
        handle.write(f"pid={os.getpid()}\n")
        handle.flush()
        yield


def resolve_tasks(task_args: Optional[List[str]], scope: str) -> List[str]:
    if task_args:
        return list(dict.fromkeys(task_args))
    return list(TASKS) if scope in {"tasks", "all"} else []


def run_final_benchmarks(
    args: argparse.Namespace,
    run_operators: bool,
    run_tasks: bool,
) -> None:
    """Run the final same-build Auto/Static reports after cache publication."""
    root = project_root()
    common = [
        "--scale", "all", "--case-set", "full", "--warmup", str(args.warmup),
        "--repeat", str(args.repeat), "--no-build", "--build-dir", str(args.build_dir),
    ]
    if args.skip_cpu_timing:
        common.append("--skip-timing-validation")
    if run_operators:
        for mode, name in (("auto", "final_auto"), ("off", "final_static")):
            command = [
                str(root / "scripts" / "performance.sh"), "--operators",
                "--operator-set", args.operator_set, *common,
                "--frozen-baseline", str(args.frozen_baseline),
                "--output-root", str(args.output_root / name),
            ]
            environment = dict(os.environ)
            environment["CUSIGNAL_ZX_TUNING_MODE"] = mode
            environment["CUSIGNAL_ZX_TUNING_CACHE"] = str(args.cache_output)
            environment["CUSIGNAL_PERF_FRESH_INPUT"] = "1"
            print("[zx-autotune] final operator:", " ".join(command), flush=True)
            subprocess.run(command, cwd=root, env=environment, check=True)
    if run_tasks:
        for mode, name in (("auto", "final_auto"), ("off", "final_static")):
            command = [
                str(root / "scripts" / "performance.sh"), "--tasks", "--task", "both", *common,
                "--output-root", str(args.output_root / name),
            ]
            environment = dict(os.environ)
            environment["CUSIGNAL_ZX_TUNING_MODE"] = mode
            environment["CUSIGNAL_ZX_TUNING_CACHE"] = str(args.cache_output)
            environment["CUSIGNAL_ZX_TASK_TUNING_MODE"] = mode
            environment["CUSIGNAL_PERF_FRESH_INPUT"] = "1"
            print("[zx-autotune] final task:", " ".join(command), flush=True)
            subprocess.run(command, cwd=root, env=environment, check=True)


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.list_candidates:
        listed_families = resolve_families(None, None, args.operator_set)
        print(json.dumps({
            "operator_set": args.operator_set,
            "candidate_profile": args.candidate_profile,
            "operators": {
                family: all_candidate_names(family, args.candidate_profile)
                for family in sorted(listed_families)
            },
            "tasks": {task: all_task_candidate_names(task) for task in sorted(TASKS)},
        }, indent=2))
        return 0
    if args.warmup < 0 or args.repeat < 3 or args.screening_warmup < 0 or args.screening_repeat < 3:
        raise SystemExit("warmup/repeat must satisfy warmup>=0 and repeat>=3")
    families = (
        resolve_families(args.family, args.operator, args.operator_set)
        if args.scope in {"operators", "all"} else []
    )
    tasks = resolve_tasks(args.task, args.scope)
    if args.scope == "operators" and args.task:
        raise SystemExit("--task requires --scope tasks or all")
    if args.scope == "tasks" and (args.family or args.operator):
        raise SystemExit("--family/--operator require --scope operators or all")
    if not families and not tasks:
        raise SystemExit("no tuning scope selected")
    if args.frozen_baseline is None and families:
        default_baseline = project_root() / "data" / "baseline"
        if default_baseline.is_dir():
            args.frozen_baseline = default_baseline
    if families and args.frozen_baseline is None and not args.dry_run:
        raise SystemExit("--frozen-baseline is required for operator tuning")
    if args.frozen_baseline is not None and not args.frozen_baseline.is_dir():
        raise SystemExit(f"frozen baseline does not exist: {args.frozen_baseline}")
    if args.state_root is None:
        args.state_root = args.output_root / "state"
    initialize_run_state(args, families, tasks)

    with run_lock(args):
        if args.dry_run:
            print(
                f"[zx-autotune] registry={REGISTRY_VERSION} scope={args.scope} "
                f"operator_set={args.operator_set} candidate_profile={args.candidate_profile} "
                "platform=zhongkexin-c500"
            )
            operator_candidate_count = 0
            for family in families:
                names = all_candidate_names(family, args.candidate_profile)
                operator_candidate_count += len(names)
                definition = FAMILIES[family]
                reason = definition.get("static_only_reason", "")
                suffix = f" static_only_reason={reason}" if reason else ""
                print(
                    f"[zx-autotune] operator={definition['operator']} candidates={len(names)}"
                    f" static={definition['static']}{suffix}"
                )
            task_candidate_count = 0
            for task in tasks:
                names = all_task_candidate_names(task)
                task_candidate_count += len(names)
                print(f"[zx-autotune] task={task} candidates={len(names)} static={TASKS[task]['static']}")
            print(
                f"[zx-autotune] exact_operator_workloads={len(families) * len(LEVELS)} "
                f"exact_task_workloads={len(tasks) * len(LEVELS)} "
                f"operator_candidate_combinations={operator_candidate_count} "
                f"task_candidate_combinations={task_candidate_count} "
                f"operator_candidate_workloads={operator_candidate_count * len(LEVELS)} "
                f"task_candidate_workloads={task_candidate_count * len(LEVELS)}"
            )
            update_run_status(args, status="dry_run_complete", phase="manifest")
            return 0

        all_results: List[Dict[str, Any]] = []
        validation_results: List[Dict[str, Any]] = []
        formal_results: List[Dict[str, Any]] = []
        task_screening: List[Dict[str, Any]] = []
        task_formal: List[Dict[str, Any]] = []
        task_validation: List[Dict[str, Any]] = []
        operator_entries: List[Dict[str, Any]] = []
        task_entries: List[Dict[str, Any]] = []

        if families:
            update_run_status(args, status="running", phase="operator_screening")
            screening_results = run_candidate_round(args, families, args.output_root / "operator_screening", "screening")
            update_run_status(args, phase="operator_formal_top3", completed_operator_screening=len(screening_results))
            formal_names = formal_candidate_names(screening_results, families)
            formal_results = run_candidate_round(
                args, families, args.output_root / "operator_formal_top3", "formal_top3", formal_names
            )
            if args.selection_validation == SELECTION_VALIDATION_WINNER:
                names_by_family = validation_candidate_names(formal_results, families)
                update_run_status(args, phase="operator_winner_validation", validation_candidate_count=sum(len(v) for v in names_by_family.values()))
                validation_results = run_candidate_round(
                    args, families, args.output_root / "operator_winner_against_static", SELECTION_VALIDATION_WINNER, names_by_family
                )
            for family in families:
                family_formal = [item for item in formal_results if item["family"] == family]
                family_validation = [item for item in validation_results if item["family"] == family]
                operator_entries.extend(select_cache_entries(
                    family_formal,
                    family,
                    family_validation if args.selection_validation == SELECTION_VALIDATION_WINNER else None,
                ))
            # Freeze operator choices before Task1/Task2 candidate search.
            write_cache(
                args.cache_output,
                formal_results + validation_results,
                operator_entries,
                [],
                args.operator_set,
                args.candidate_profile,
            )
            all_results.extend(screening_results + formal_results + validation_results)

        if tasks:
            update_run_status(args, status="running", phase="task_screening", operator_cache_entries=len(operator_entries))
            task_screening = run_task_candidate_round(args, tasks, args.output_root / "task_screening", "screening")
            update_run_status(args, phase="task_formal_top3", completed_task_screening=len(task_screening))
            task_names = formal_task_candidate_names(task_screening, tasks)
            task_formal = run_task_candidate_round(args, tasks, args.output_root / "task_formal_top3", "formal_top3", task_names)
            if args.selection_validation == SELECTION_VALIDATION_WINNER:
                task_validation_names = {
                    task: [TASKS[task]["static"], *provisional_task_candidate_names(
                        [item for item in task_formal if item["task"] == task], task
                    )]
                    for task in tasks
                }
                update_run_status(args, phase="task_winner_validation", validation_candidate_count=sum(len(v) for v in task_validation_names.values()))
                task_validation = run_task_candidate_round(
                    args, tasks, args.output_root / "task_winner_against_static", SELECTION_VALIDATION_WINNER, task_validation_names
                )
            for task in tasks:
                task_entries.extend(select_task_cache_entries(
                    [item for item in task_formal if item["task"] == task],
                    task,
                    [item for item in task_validation if item["task"] == task]
                    if args.selection_validation == SELECTION_VALIDATION_WINNER else None,
                ))
            all_results.extend(task_screening + task_formal + task_validation)

        update_run_status(args, phase="cache_publish", status="publishing", operator_entries=len(operator_entries), task_entries=len(task_entries))
        write_cache(
            args.cache_output,
            all_results,
            operator_entries,
            task_entries,
            args.operator_set,
            args.candidate_profile,
        )
        update_run_status(args, phase="final_benchmark", status="running")
        run_final_benchmarks(args, bool(families), bool(tasks))
        update_run_status(args, phase="complete", status="complete", operator_entries=len(operator_entries), task_entries=len(task_entries))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode or 1)
