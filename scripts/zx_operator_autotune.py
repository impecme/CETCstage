#!/usr/bin/env python3
"""Offline, finite-candidate autotuner for Zhongkexin C500 operators.

The script deliberately delegates execution to performance.sh.  It never
benchmarks from the production library and never changes the frozen baseline.
The generated JSON is a repository-owned, device-specific lookup cache consumed
by src/common/zx_tile_policy.hpp.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


REGISTRY_VERSION = "zx-c500-all81-task-v3"
CACHE_SCHEMA_VERSION = 3
LEVELS = [f"L{index}" for index in range(1, 7)]
SELECTION_VALIDATION_WINNER = "winner-against-static"


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


def _load_operator_contract() -> List[str]:
    path = Path(__file__).resolve().parents[1] / "tests" / "contracts" / "operator_sets.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    operators = payload["sets"]["all81"]["operators"]
    if len(operators) != 81 or len(set(operators)) != 81:
        raise RuntimeError("all81 operator contract must contain 81 unique operators")
    return operators


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
    "filter_design": "host-side coefficient/design contract; no independent safe C500 launch variant",
    "spectral": "public spectral plan/layout variants are not independently bound; failed PlanMany remains disabled",
    "windows": "window kernels use fixed shared-memory layout; no independently validated launch variant",
    "wavelets": "wavelet shared-table variants require a separate correctness probe before registration",
    "estimation": "stateful Kalman path has no independently validated parallel launch variant",
    "correlate": "generic/lag paths have no independently validated alternate C500 dispatch",
    "radartools": "non-hotspot radar paths have no independently validated alternate C500 dispatch",
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
        else:
            policy_family = "static"
            candidates = []
        module_name = operator.split("/", 1)[0]
        FAMILIES[operator] = {
            "operator": operator,
            "policy_family": policy_family,
            "static": (
                STATIC_CANDIDATE_NAMES[policy_family]
                if policy_family in STATIC_CANDIDATE_NAMES
                else "static_operator"
            ),
            "candidates": candidates,
            "static_only_reason": (
                STATIC_ONLY_REASON.get(module_name, "no independently validated safe precompiled C500 variant")
                if not candidates else "",
            ),
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


def all_candidate_names(family: str) -> List[str]:
    return [FAMILIES[family]["static"]] + [item["candidate"] for item in FAMILIES[family]["candidates"]]


def iter_workloads(families: Iterable[str]) -> Iterable[tuple[str, str, str]]:
    for family in families:
        operator = FAMILIES[family]["operator"]
        for candidate_name in [FAMILIES[family]["static"]] + [
            item["candidate"] for item in FAMILIES[family]["candidates"]
        ]:
            yield family, operator, candidate_name


def cache_default_path() -> Path:
    # Keep the final offline artifact with the repository so runtime Auto mode
    # does not depend on a user-specific home-directory cache.
    return project_root() / "data" / "tuning" / "zx_tuning.json"


def resolve_families(
    family_args: Optional[List[str]], operator_args: Optional[List[str]]
) -> List[str]:
    if family_args and operator_args:
        raise SystemExit("--family and --operator cannot be used together")
    if operator_args:
        return [OPERATOR_ID_TO_FAMILY[operator] for operator in operator_args]
    return family_args or list(OPERATOR_KEYS)


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
) -> None:
    root = project_root()
    definition = FAMILIES[family]
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
        str(args.warmup),
        "--repeat",
        str(args.repeat),
        "--frozen-baseline",
        str(args.frozen_baseline),
        "--output-root",
        str(output_root),
        "--build-dir",
        str(args.build_dir),
        "--no-build",
    ]
    if args.skip_cpu_timing:
        command.append("--skip-timing-validation")
    print("[zx-autotune] run:", " ".join(command), flush=True)
    output_root.mkdir(parents=True, exist_ok=True)
    (output_root / "run_metadata.json").write_text(
        json.dumps(
            {
                "schema_version": 2,
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
                "warmup": args.warmup,
                "repeat": args.repeat,
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
    subprocess.run(command, cwd=root, env=environment, check=True)


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
        operator_id_required = expected_trace_family in {"linear", "row_reduction", "fir_filter"}
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


def write_cache(path: Path, results: List[Dict[str, Any]], entries: List[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    device = device_from_results(results)
    if not device:
        if entries:
            raise RuntimeError("cache entries require a device fingerprint")
        print(f"[zx-autotune] no tunable candidate/device for {path}; cache not written")
        return
    payload = {
        "schema_version": CACHE_SCHEMA_VERSION,
        "registry_version": REGISTRY_VERSION,
        "platform": "zhongkexin-c500",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "device": device,
        "selection_policy": (
            "exact_key;correctness_pass;input_refresh_pass;candidate_applied;"
            "gpu_e2e_median_min;winner_against_static_round2"
        ),
        "entries": entries,
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
            names = all_candidate_names(family)
        else:
            names = candidate_names.get(family, [])
        for candidate_name in names:
            output_root = round_root / family / candidate_name
            if not args.resume or not run_output_is_complete(output_root, family, candidate_name):
                invoke_candidate(args, family, candidate_name, output_root, round_name)
            all_results.extend(read_metrics(output_root, family, candidate_name))
    return all_results


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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
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
    parser.add_argument("--build-dir", type=Path, default=project_root() / "build-zx")
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--repeat", type=int, default=30)
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


def main(argv: Optional[List[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    if args.list_candidates:
        print(json.dumps({family: all_candidate_names(family) for family in sorted(FAMILIES)}, indent=2))
        return 0
    if args.warmup < 0 or args.repeat < 3:
        raise SystemExit("--warmup must be >= 0 and --repeat must be >= 3")
    families = resolve_families(args.family, args.operator)
    if args.frozen_baseline is None:
        raise SystemExit("--frozen-baseline is required for an offline tuning run")
    if not args.frozen_baseline.is_dir():
        raise SystemExit(f"frozen baseline does not exist: {args.frozen_baseline}")
    all_results: List[Dict[str, Any]] = []
    validation_results: List[Dict[str, Any]] = []
    if args.dry_run:
        for family, operator, candidate_name in iter_workloads(families):
            output_root = args.output_root / "round1" / family / candidate_name
            print(
                "[zx-autotune] dry-run:",
                operator,
                candidate_name,
                "->",
                output_root,
            )
    else:
        first_round_root = args.output_root / "round1"
        all_results = run_candidate_round(args, families, first_round_root, "round1")
        if args.selection_validation == SELECTION_VALIDATION_WINNER:
            names_by_family = validation_candidate_names(all_results, families)
            print(
                "[zx-autotune] validation candidates=",
                sum(len(names) for names in names_by_family.values()),
                flush=True,
            )
            validation_results = run_candidate_round(
                args,
                families,
                args.output_root / "round2_winner_against_static",
                SELECTION_VALIDATION_WINNER,
                names_by_family,
            )
    if args.dry_run:
        print(f"[zx-autotune] dry-run candidates={sum(1 for _ in iter_workloads(families))}")
        return 0
    entries: List[Dict[str, Any]] = []
    for family in families:
        family_results = [item for item in all_results if item["family"] == family]
        family_validation = [item for item in validation_results if item["family"] == family]
        entries.extend(
            select_cache_entries(
                family_results,
                family,
                family_validation if args.selection_validation == SELECTION_VALIDATION_WINNER else None,
            )
        )
    write_cache(args.cache_output, all_results + validation_results, entries)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode or 1)
