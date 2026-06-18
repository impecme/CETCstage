#!/usr/bin/env python3

"""Run six-scale perf benchmarks for every enabled unit-test operator.

Workflow:
1. Read enabled module/operator pairs from scripts/test/run_all_tests.sh --list.
2. Backup each generated perf manifest that will be touched.
3. For each operator and scale level, rewrite the perf manifest according to
   the operator's scale policy.
4. Execute the operator through scripts/test/run_all_tests.sh.
5. Parse latest_metrics.json and write the latest all-operator CSV.
6. Restore manifests in a finally block.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_SCALE_FAMILIES: dict[str, tuple[int, ...]] = {
    "linear_points": (1024, 4096, 16384, 65536, 262144, 1048576),
    "medium_1d_fft": (1024, 2048, 4096, 8192, 16384, 32768),
    "heavy_quadratic": (256, 512, 1024, 2048, 4096, 8192),
    "matrix_total": (4096, 16384, 65536, 262144, 524288, 1048576),
    "filter_design_taps": (129, 257, 513, 1025, 2049, 4097),
    "small_state": (16, 32, 64, 128, 256, 512),
    "kalman_points": (16, 32, 64, 128, 256, 512),
    "istft_frames": (9, 17, 33, 65, 129, 257),
    "zhongkexin_chebwin_points": (128, 256, 512, 768, 1024, 1536),
    "zhongkexin_firwin2_taps": (65, 129, 257, 513, 769, 1025),
}

LARGE_GPU_SCALE_FAMILIES: dict[str, tuple[int, ...]] = {
    **DEFAULT_SCALE_FAMILIES,
    "linear_points": (65536, 262144, 1048576, 4194304, 8388608, 16777216),
    "medium_1d_fft": (32768, 65536, 131072, 262144, 524288, 1048576),
    "kalman_points": (512, 2048, 8192, 32768, 131072, 524288),
}

SCALE_PROFILES: dict[str, dict[str, tuple[int, ...]]] = {
    "default": DEFAULT_SCALE_FAMILIES,
    "large-gpu": LARGE_GPU_SCALE_FAMILIES,
}

LINEAR_WAVEFORMS = {"chirp", "gausspulse", "sawtooth", "square"}
LINEAR_WAVELETS = {"morlet", "morlet2", "ricker"}
MATRIX_FILTERING = {"wiener", "firfilter", "hilbert2"}
MEDIUM_FILTERING = {
    "firfilter2",
    "sosfilt",
    "hilbert",
    "detrend",
    "freq_shift",
    "decimate",
    "resample",
    "resample_poly",
    "upfirdn",
}

REL_ERROR_THRESHOLD = 1.0e-2
TRUE_ERROR_ABS_THRESHOLD = 1.0e-3
TRUE_ERROR_RMSE_THRESHOLD = 1.0e-4
DEFAULT_UNIT_REL_FLOOR = 1.0e-30
UNIT_REL_FLOORS_BY_MODULE = {
    "filtering": 1.0e-15,
    "filter_design": 1.0e-15,
    "demod": 1.0e-12,
    "correlate": 1.0e-12,
    "estimation": 1.0e-12,
}
BENCHMARK_OUTPUT_PATTERNS = (
    "all_ops_scale_benchmark_*.csv",
    "*_scale_benchmark_*.csv",
    "latest_*_scale_benchmark.csv",
    "latest_all_ops_scale_benchmark.csv",
    "latest_report.md",
    "latest_large_gpu_candidate_report.csv",
    "latest_large_gpu_candidate_report.md",
)
GENERATED_SAMPLE_DIRS = ("input", "output_samples")
BASELINE_SCHEMA_VERSION = 1
ACCURACY_SUMMARY_FIELDS = (
    "pass",
    "accuracy_cases",
    "max_abs_error",
    "max_rel_error",
    "mixed_error",
    "rmse",
    "near_zero_count",
    "near_zero_fraction",
    "max_abs_cpu",
    "min_abs_cpu",
    "unit_rel_denominator_floor",
    "error_class",
)


@dataclass(frozen=True)
class Target:
    module: str
    operator: str
    manifest_path: Path
    metrics_path: Path


@dataclass
class RunMetrics:
    summary_pass: bool | None = None
    mixed_error: str = ""
    error_class: str = ""
    gpu_e2e_speedup: str = ""
    gpu_kernel_speedup: str = ""
    cpu_median_ms: str = ""
    gpu_e2e_median_ms: str = ""
    gpu_kernel_median_ms: str = ""
    gpu_e2e_min_ms: str = ""
    gpu_e2e_max_ms: str = ""
    git_commit: str = ""
    gpu_name: str = ""


def log(message: str) -> None:
    print(f"[all-ops-bench] {message}")


def format_metric(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float):
        if not math.isfinite(value):
            return ""
        return f"{value:.17g}"
    return str(value)


def parse_csv_tokens(value: str, field_name: str) -> list[str]:
    if value == "all":
        return ["all"]
    parts = [item.strip() for item in value.split(",") if item.strip()]
    if not parts:
        raise ValueError(f"--{field_name} cannot be empty")
    return parts


def create_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run six-scale perf benchmarks for all enabled unit-test operators."
    )
    parser.add_argument("--modules", default="all", help="Comma-separated modules (default: all)")
    parser.add_argument("--operators", default="all", help="Comma-separated operators (default: all)")
    parser.add_argument(
        "--scale-count",
        type=int,
        default=6,
        help="Number of scale levels. Currently fixed at 6.",
    )
    parser.add_argument(
        "--scale-levels",
        default="1,2,3,4,5,6",
        help="Comma-separated scale levels to run, each in 1..6 (default: 1,2,3,4,5,6)",
    )
    parser.add_argument(
        "--scale-profile",
        choices=sorted(SCALE_PROFILES),
        default="default",
        help="Scale profile to use (default: default)",
    )
    parser.add_argument("--warmup", type=int, default=None, help="Warmup iterations (default: 5, or 1 with --demo-fast)")
    parser.add_argument("--repeat", type=int, default=None, help="Repeat iterations (default: 30, or 3 with --demo-fast)")
    parser.add_argument(
        "--demo-fast",
        action="store_true",
        help="Use fast demo timing defaults: warmup=1 and repeat=3 unless explicitly overridden.",
    )
    parser.add_argument(
        "--build",
        dest="do_build",
        action="store_true",
        help="Build selected test targets once before benchmark",
    )
    parser.add_argument(
        "--no-build",
        dest="do_build",
        action="store_false",
        help="Reuse existing binaries (default)",
    )
    parser.set_defaults(do_build=False)
    parser.add_argument("--build-dir", default="build", help="Build directory (default: build)")
    parser.add_argument(
        "--platform",
        choices=("ZHONGKEXIN",),
        default=os.environ.get("CUSIGNAL_PLATFORM", "ZHONGKEXIN").upper(),
        help="CUSIGNAL platform passed to run_all_tests.sh (default: ZHONGKEXIN)",
    )
    parser.add_argument(
        "--output-dir",
        default="data/reports/unit/benchmarks/all_ops",
        help="Benchmark CSV output root",
    )
    parser.add_argument(
        "--report-mode",
        choices=("csv", "concise", "full"),
        default="csv",
        help=(
            "Report output mode. csv writes only latest_all_ops_scale_benchmark.csv; "
            "concise also writes latest_report.md; full also writes timestamped archives, "
            "module CSVs, and candidate CSV/MD."
        ),
    )
    parser.add_argument(
        "--keep-old-output",
        action="store_true",
        help="Keep old benchmark CSV/Markdown files in the output directory.",
    )
    parser.add_argument(
        "--keep-generated-samples",
        action="store_true",
        help=(
            "Keep per-operator generated input/output sample files. By default the benchmark "
            "removes those debug samples after reading metrics to keep reports compact."
        ),
    )
    parser.add_argument(
        "--runner-script",
        default="scripts/test/run_all_tests.sh",
        help="Path to run_all_tests.sh",
    )
    parser.add_argument(
        "--gpu-only",
        action="store_true",
        help=(
            "Reuse cached CPU baseline rows and run only GPU perf timings when possible. "
            "Use with --cpu-baseline-mode to control cache behavior."
        ),
    )
    parser.add_argument(
        "--cpu-baseline-mode",
        choices=("auto", "refresh", "reuse"),
        default="auto",
        help=(
            "CPU baseline policy for --gpu-only. auto refreshes missing rows and reuses cached rows; "
            "refresh rebuilds selected baselines; reuse requires all rows to exist."
        ),
    )
    parser.add_argument(
        "--cpu-baseline-file",
        default="",
        help=(
            "CPU baseline cache JSON for --gpu-only. Default: "
            "data/reports/unit/benchmarks/cpu_baselines/<scale-profile>/latest_cpu_baseline.json"
        ),
    )
    return parser


def parse_args() -> argparse.Namespace:
    parser = create_argument_parser()
    args = parser.parse_args()
    args.platform = args.platform.upper()
    if args.scale_count != 6:
        parser.error("--scale-count is currently fixed at 6")
    try:
        scale_levels = [int(item.strip()) for item in args.scale_levels.split(",") if item.strip()]
    except ValueError:
        parser.error("--scale-levels must contain comma-separated integers")
    if not scale_levels or any(level < 1 or level > 6 for level in scale_levels):
        parser.error("--scale-levels must contain only levels 1..6")
    args.scale_levels = sorted(set(scale_levels))
    if args.warmup is None:
        args.warmup = 1 if args.demo_fast else 5
    if args.repeat is None:
        args.repeat = 3 if args.demo_fast else 30
    if args.warmup < 0:
        parser.error("--warmup must be a non-negative integer")
    if args.repeat < 0:
        parser.error("--repeat must be a non-negative integer")
    try:
        args.modules = parse_csv_tokens(args.modules, "modules")
        args.operators = parse_csv_tokens(args.operators, "operators")
    except ValueError as exc:
        parser.error(str(exc))
    return args


def resolve_path(repo_root: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else repo_root / path


def load_enabled_entries(runner_script: Path, build_dir: Path, platform: str) -> list[tuple[str, str, str]]:
    completed = subprocess.run(
        [str(runner_script), "--list", "--build-dir", str(build_dir), "--platform", platform],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip())

    entries: list[tuple[str, str, str]] = []
    for line in completed.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        module = parts[0].strip()
        operator = parts[1].strip()
        target_name = parts[2].strip()
        if module and operator and target_name:
            entries.append((module, operator, target_name))
    if not entries:
        raise RuntimeError("run_all_tests.sh --list returned no enabled operators")
    return entries


def filter_entries(
    entries: list[tuple[str, str, str]],
    selected_modules: list[str],
    selected_operators: list[str],
) -> list[tuple[str, str, str]]:
    module_filter = None if selected_modules == ["all"] else set(selected_modules)
    operator_filter = None if selected_operators == ["all"] else set(selected_operators)

    known_modules = {module for module, _operator, _target_name in entries}
    known_operators = {operator for _module, operator, _target_name in entries}
    if module_filter is not None:
        missing = sorted(module_filter - known_modules)
        if missing:
            raise RuntimeError(f"unknown module(s): {', '.join(missing)}")
    if operator_filter is not None:
        missing = sorted(operator_filter - known_operators)
        if missing:
            raise RuntimeError(f"unknown operator(s): {', '.join(missing)}")

    filtered = [
        (module, operator, target_name)
        for module, operator, target_name in entries
        if (module_filter is None or module in module_filter)
        and (operator_filter is None or operator in operator_filter)
    ]
    if not filtered:
        raise RuntimeError("no operators match --modules/--operators filters")
    return filtered


def build_selected_targets(repo_root: Path, build_dir: Path, target_names: list[str], platform: str) -> None:
    unique_targets = sorted(set(target_names))
    if not unique_targets:
        return

    jobs = str(os.cpu_count() or 1)
    build_type = os.environ.get("CMAKE_BUILD_TYPE", "Release")
    configure_cmd = [
        "cmake",
        "-S",
        str(repo_root),
        "-B",
        str(build_dir),
        f"-DCMAKE_BUILD_TYPE={build_type}",
        f"-DCUSIGNAL_PLATFORM={platform}",
    ]
    zhongkexin_cxx = os.environ.get("ZHONGKEXIN_CXX_COMPILER") or shutil.which("dlcc")
    if not zhongkexin_cxx:
        raise RuntimeError("dlcc was not found for ZHONGKEXIN build")
    configure_cmd.append(f"-DCMAKE_CXX_COMPILER={zhongkexin_cxx}")
    build_cmd = [
        "cmake",
        "--build",
        str(build_dir),
        "--target",
        *unique_targets,
        "--parallel",
        jobs,
    ]

    log(
        "building selected targets once: "
        f"{len(unique_targets)} targets, platform={platform}, build_type={build_type}, "
        f"gpu_arch=dlgput64, jobs={jobs}"
    )
    subprocess.run(configure_cmd, cwd=repo_root, check=True)
    subprocess.run(build_cmd, cwd=repo_root, check=True)


def make_target(repo_root: Path, module: str, operator: str) -> Target:
    return Target(
        module=module,
        operator=operator,
        manifest_path=repo_root / "data" / "generated" / "unit" / module / operator / "manifest.json",
        metrics_path=repo_root / "data" / "reports" / "unit" / module / operator / "latest_metrics.json",
    )


def scale_family_for(
    module: str,
    operator: str,
    scale_profile: str = "default",
    platform: str = "ZHONGKEXIN",
) -> str:
    if platform == "ZHONGKEXIN":
        if module == "windows" and operator == "chebwin":
            return "zhongkexin_chebwin_points"
        if module == "filter_design" and operator == "firwin2":
            return "zhongkexin_firwin2_taps"
    if module in {"bsplines", "windows"}:
        return "linear_points"
    if module == "waveforms":
        return "linear_points"
    if module == "wavelets":
        return "medium_1d_fft" if operator == "cwt" else "linear_points"
    if module == "spectral":
        if operator == "lombscargle":
            return "heavy_quadratic"
        if operator == "istft":
            return "istft_frames"
        return "medium_1d_fft"
    if module == "filtering":
        if operator in MATRIX_FILTERING:
            return "matrix_total"
        if operator == "lfilter_zi":
            return "small_state"
        return "medium_1d_fft"
    if module == "filter_design":
        return "filter_design_taps"
    if module == "radartools":
        if operator in {"ambgfun"}:
            return "heavy_quadratic"
        if operator in {"cfar_alpha"}:
            return "small_state"
        return "matrix_total"
    if module == "correlate":
        return "matrix_total" if operator == "correlate2d" else "heavy_quadratic"
    if module in {"demod", "peak_finding"}:
        return "matrix_total"
    if module == "estimation":
        return "kalman_points" if scale_profile == "large-gpu" else "small_state"
    raise ValueError(f"missing scale family for {module}/{operator}")


def scale_values_for(scale_profile: str, scale_family: str) -> tuple[int, ...]:
    try:
        return SCALE_PROFILES[scale_profile][scale_family]
    except KeyError as exc:
        raise ValueError(f"missing scales for profile={scale_profile}, family={scale_family}") from exc


def shape_product(shape: list[int]) -> int:
    total = 1
    for dim in shape:
        total *= dim
    return total


def parse_shape(value: Any, key: str) -> list[int]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"expected non-empty list for {key}")
    dims: list[int] = []
    for index, item in enumerate(value):
        if not isinstance(item, (int, float)):
            raise ValueError(f"non-numeric dimension in {key}[{index}]")
        dim = int(round(item))
        if dim <= 0:
            raise ValueError(f"non-positive dimension in {key}[{index}]")
        dims.append(dim)
    return dims


def resize_shape_keep_ratio(original_shape: list[int], target_total: int) -> list[int]:
    if len(original_shape) == 1:
        return [target_total]
    if len(original_shape) == 2:
        rows0, cols0 = original_shape
        ratio = rows0 / cols0 if cols0 > 0 else 1.0
        rows = max(1, int(round(math.sqrt(target_total * ratio))))
        cols = max(1, int(round(target_total / rows)))
        while rows * cols < target_total:
            cols += 1
        return [rows, cols]
    prefix = [max(1, dim) for dim in original_shape[:-1]]
    prefix_total = shape_product(prefix)
    last = max(1, int(math.ceil(target_total / max(prefix_total, 1))))
    return prefix + [last]


def odd_at_least(value: int, minimum: int = 3) -> int:
    out = max(value, minimum)
    if out % 2 == 0:
        out += 1
    return out


def update_generator_shape(generator: dict[str, Any], shape: list[int]) -> None:
    generator["shape"] = shape


def update_first_shape_dim(generator: dict[str, Any], scale: int, key_name: str) -> list[int]:
    shape = parse_shape(generator.get("shape"), key_name)
    shape[0] = scale
    generator["shape"] = shape
    return shape


def require_dict(value: Any, key: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"missing object field: {key}")
    return value


def set_spike_inside(generator: dict[str, Any], shape: list[int]) -> None:
    if len(shape) < 2:
        return
    if "spike_row" in generator:
        generator["spike_row"] = min(int(generator.get("spike_row", 0)), shape[0] - 1)
    if "spike_col" in generator:
        generator["spike_col"] = min(int(generator.get("spike_col", 0)), shape[1] - 1)


def apply_scale_mapping(module: str, operator: str, case: dict[str, Any], scale: int) -> str:
    if module == "bsplines":
        case["x_shape"] = [scale]
        case["x_count"] = scale
        return f"x_shape=[{scale}]"

    if module == "windows":
        case["size"] = scale
        return f"size={scale}"

    if module == "waveforms":
        if operator in LINEAR_WAVEFORMS:
            generator = require_dict(case.get("t_generator"), "t_generator")
            generator["count"] = scale
            return f"t_generator.count={scale}"
        if operator == "unit_impulse":
            if bool(case.get("is_nd", False)):
                base_shape = case.get("shape") if isinstance(case.get("shape"), list) else [64, 64]
                shape = resize_shape_keep_ratio(parse_shape(base_shape, "shape"), scale)
                case["shape"] = shape
                case["size"] = None
                return f"shape={shape}"
            case["size"] = scale
            case["shape"] = None
            return f"size={scale}"

    if module == "wavelets":
        if operator == "qmf":
            case["hk_count"] = scale
            return f"hk_count={scale}"
        if operator in LINEAR_WAVELETS:
            case["points"] = scale
            return f"points={scale}"
        if operator == "cwt":
            case["data_count"] = scale
            return f"data_count={scale}"

    if module == "spectral":
        if operator == "lombscargle":
            x_generator = require_dict(case.get("x_generator"), "x_generator")
            y_generator = require_dict(case.get("y_generator"), "y_generator")
            freqs_generator = require_dict(case.get("freqs_generator"), "freqs_generator")
            x_generator["count"] = scale
            y_shape = update_first_shape_dim(y_generator, scale, "y_generator.shape")
            freqs_generator["count"] = scale * 2
            return f"x_count={scale}; y_shape={y_shape}; freqs_count={scale * 2}"
        if operator in {"csd", "spectrogram", "stft"}:
            x_generator = require_dict(case.get("x_generator"), "x_generator")
            x_shape = update_first_shape_dim(x_generator, scale, "x_generator.shape")
            note = f"x_shape={x_shape}"
            if operator == "csd":
                y_generator = require_dict(case.get("y_generator"), "y_generator")
                y_shape = update_first_shape_dim(y_generator, scale, "y_generator.shape")
                note += f"; y_shape={y_shape}"
            return note
        if operator == "vectorstrength":
            events_generator = require_dict(case.get("events_generator"), "events_generator")
            events_generator["count"] = scale
            return f"events_count={scale}"
        if operator in {"periodogram", "welch", "coherence"}:
            x_generator = require_dict(case.get("x_generator"), "x_generator")
            x_shape = update_first_shape_dim(x_generator, scale, "x_generator.shape")
            note = f"x_shape={x_shape}"
            if operator == "coherence":
                y_generator = require_dict(case.get("y_generator"), "y_generator")
                y_shape = update_first_shape_dim(y_generator, scale, "y_generator.shape")
                note += f"; y_shape={y_shape}"
            return note
        if operator == "istft":
            zxx_generator = require_dict(case.get("zxx_generator"), "zxx_generator")
            shape = parse_shape(zxx_generator.get("shape"), "zxx_generator.shape")
            if len(shape) < 2:
                raise ValueError("istft zxx_generator.shape must be 2D")
            shape[1] = scale
            zxx_generator["shape"] = shape
            return f"zxx_shape={shape}"

    if module == "filtering":
        if operator in MATRIX_FILTERING:
            shape = resize_shape_keep_ratio(parse_shape(case.get("x_shape"), "x_shape"), scale)
            case["x_shape"] = shape
            return f"x_shape={shape}"
        if operator in MEDIUM_FILTERING:
            if operator == "detrend":
                shape = resize_shape_keep_ratio(parse_shape(case.get("data_shape"), "data_shape"), scale)
                case["data_shape"] = shape
                return f"data_shape={shape}"
            shape = resize_shape_keep_ratio(parse_shape(case.get("x_shape"), "x_shape"), scale)
            old_shape = parse_shape(case.get("x_shape"), "x_shape")
            old_count = shape_product(old_shape)
            case["x_shape"] = shape
            note = f"x_shape={shape}"
            if operator == "resample":
                old_num = case.get("num")
                if isinstance(old_num, (int, float)) and old_num > 0 and old_count > 0:
                    new_count = shape_product(shape)
                    case["num"] = max(1, int(round(float(old_num) * new_count / old_count)))
                    note += f"; num={case['num']}"
            return note
        if operator in {"lfilter", "filtfilt"}:
            shape = resize_shape_keep_ratio(parse_shape(case.get("x_shape"), "x_shape"), scale)
            case["x_shape"] = shape
            return f"x_shape={shape}"
        if operator == "firfilter_zi":
            case["filter_order"] = max(1, int(scale))
            return f"filter_order={case['filter_order']} (fixed generated FIR taps)"
        if operator == "lfilter_zi":
            case["filter_order"] = scale
            return f"filter_order={scale}"
        if operator == "channelize_poly":
            n_chans = int(case.get("n_chans", 8) or 8)
            h_count = odd_at_least(n_chans * 12, 33)
            case["x_count"] = scale
            case["h_count"] = h_count
            return f"x_count={scale}; h_count={h_count}; n_chans={n_chans}"

    if module == "filter_design":
        if operator == "kaiser_beta":
            attenuation = min(140.0, 20.0 + math.log2(max(scale, 2)) * 8.0)
            case["attenuation"] = attenuation
            return f"attenuation={attenuation:.3f}"
        if operator == "kaiser_atten":
            case["numtaps"] = scale
            return f"numtaps={scale}; width={case.get('width')}"
        if operator == "cmplx_sort":
            return f"input_kind={case.get('input_kind', 'real')} (fixed cmplx_sort fixture)"
        if operator == "firwin":
            case["numtaps"] = scale
            return f"numtaps={scale}"
        if operator == "firwin2":
            case["numtaps"] = scale
            case["nfreqs"] = scale * 2 + 1
            return f"numtaps={scale}; nfreqs={scale * 2 + 1}"

    if module == "radartools":
        if operator == "ambgfun":
            x_generator = require_dict(case.get("x_generator"), "x_generator")
            case["x_shape"] = [scale]
            x_generator["length"] = scale
            return f"x_shape=[{scale}]; x_generator.length={scale}"
        if operator == "cfar_alpha":
            case["cells"] = scale
            return f"cells={scale}"
        if operator == "ca_cfar":
            shape = resize_shape_keep_ratio(parse_shape(case.get("x_shape"), "x_shape"), scale)
            case["x_shape"] = shape
            generator = require_dict(case.get("real_x_generator"), "real_x_generator")
            update_generator_shape(generator, shape)
            set_spike_inside(generator, shape)
            return f"x_shape={shape}"
        if operator == "mvdr":
            rows = 8
            cols = max(1, int(math.ceil(scale / rows)))
            x_shape = [rows, cols]
            case["x_shape"] = x_shape
            case["sv_shape"] = [rows, 1]
            x_generator = require_dict(case.get("x_generator"), "x_generator")
            sv_generator = require_dict(case.get("sv_generator"), "sv_generator")
            update_generator_shape(x_generator, x_shape)
            sv_generator["length"] = rows
            sv_generator["column_vector"] = True
            return f"x_shape={x_shape}; sv_shape={[rows, 1]}"
        if operator in {"pulse_compression", "pulse_doppler"}:
            old_shape = parse_shape(case.get("x_shape"), "x_shape")
            cols = old_shape[1] if len(old_shape) > 1 else old_shape[0]
            rows = max(1, int(math.ceil(scale / max(cols, 1))))
            shape = [rows, cols]
            case["x_shape"] = shape
            x_generator = require_dict(case.get("x_generator"), "x_generator")
            update_generator_shape(x_generator, shape)
            return f"x_shape={shape}"

    if module == "correlate":
        if operator == "correlate":
            kernel = odd_at_least(scale // 16, 17)
            case["shape1"] = [scale]
            case["shape2"] = [kernel]
            return f"shape1=[{scale}]; shape2=[{kernel}]"
        if operator == "correlate2d":
            shape = resize_shape_keep_ratio(parse_shape(case.get("shape1"), "shape1"), scale)
            case["shape1"] = shape
            return f"shape1={shape}; shape2={case.get('shape2')}"
        if operator == "correlation_lags":
            in1_len = max(2, int(scale))
            in2_len = max(1, min(in1_len, int(scale // 4) + 1))
            case["in1_len"] = in1_len
            case["in2_len"] = in2_len
            return f"in1_len={in1_len}; in2_len={in2_len}"

    if module == "demod" and operator == "fm_demod":
        rows = 64
        cols = max(1, int(math.ceil(scale / rows)))
        case["shape"] = [rows, cols]
        return f"shape={[rows, cols]}"

    if module == "estimation" and operator == "kalman_filter":
        case["points"] = scale
        return f"points={scale}"

    if module == "peak_finding" and operator in {"argrelextrema", "argrelmin", "argrelmax"}:
        shape = resize_shape_keep_ratio(parse_shape(case.get("shape"), "shape"), scale)
        case["shape"] = shape
        return f"shape={shape}"

    raise ValueError(f"missing scale mapping for {module}/{operator}")


def rewrite_manifest(target: Target, original_text: str, scale: int) -> str:
    payload = json.loads(original_text)
    perf_cases = payload.get("perf_cases")
    if not isinstance(perf_cases, list) or not perf_cases:
        raise ValueError(f"{target.manifest_path} has no perf_cases")

    notes: list[str] = []
    for case in perf_cases:
        if not isinstance(case, dict):
            raise ValueError(f"{target.manifest_path} has non-object perf case")
        note = apply_scale_mapping(target.module, target.operator, case, scale)
        notes.append(f"{case.get('id', 'case')}: {note}")

    target.manifest_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return " | ".join(notes)


def backup_manifests(targets: list[Target]) -> dict[Path, str]:
    backups: dict[Path, str] = {}
    for target in targets:
        if not target.manifest_path.exists():
            raise FileNotFoundError(f"manifest not found: {target.manifest_path}")
        if target.manifest_path not in backups:
            backups[target.manifest_path] = target.manifest_path.read_text(encoding="utf-8")
    return backups


def restore_manifests(backups: dict[Path, str]) -> None:
    for path, content in backups.items():
        path.write_text(content, encoding="utf-8")


def read_numeric_csv_values(path: Path) -> list[float]:
    values: list[float] = []
    if not path.exists():
        return values
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        for row in reader:
            parsed_row: list[float] = []
            for cell in row:
                text = cell.strip()
                if not text:
                    continue
                try:
                    parsed_row.append(float(text))
                except ValueError:
                    parsed_row = []
                    break
            values.extend(parsed_row)
    return values


def is_diagnostic_output_role(role: str) -> bool:
    if not role.startswith("cpu_"):
        return False
    suffix = role[4:]
    return suffix not in {
        "frequency",
        "frequencies",
        "time",
        "times",
        "delay_axis",
        "doppler_axis",
    }


def cpu_gpu_artifact_pairs(case: dict[str, Any]) -> list[tuple[str, Path, Path]]:
    artifacts = case.get("artifacts")
    if not isinstance(artifacts, list):
        return []
    role_to_path: dict[str, Path] = {}
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            continue
        role = str(artifact.get("role", ""))
        path = str(artifact.get("path", ""))
        if role and path:
            role_to_path[role] = Path(path)
    pairs: list[tuple[str, Path, Path]] = []
    for role, cpu_path in role_to_path.items():
        if not is_diagnostic_output_role(role):
            continue
        gpu_path = role_to_path.get("gpu_" + role[4:])
        if gpu_path is not None:
            pairs.append((role, cpu_path, gpu_path))
    return pairs


def unit_test_relative_floor(module: str) -> float:
    return UNIT_REL_FLOORS_BY_MODULE.get(module, DEFAULT_UNIT_REL_FLOOR)


def near_zero_metrics_from_cpu_gpu_pairs(module: str, case: dict[str, Any]) -> dict[str, Any]:
    max_abs_cpu = 0.0
    min_abs_cpu = math.inf
    near_zero_count = 0
    sample_count = 0
    rel_floor = unit_test_relative_floor(module)
    for _, cpu_path, gpu_path in cpu_gpu_artifact_pairs(case):
        cpu_values = read_numeric_csv_values(cpu_path)
        gpu_values = read_numeric_csv_values(gpu_path)
        count = min(len(cpu_values), len(gpu_values))
        if count == 0:
            continue
        for index in range(count):
            cpu_value = cpu_values[index]
            abs_cpu = abs(cpu_value)
            max_abs_cpu = max(max_abs_cpu, abs_cpu)
            min_abs_cpu = min(min_abs_cpu, abs_cpu)
            if (module == "waveforms" and abs_cpu == 0.0) or (
                module != "waveforms" and abs_cpu <= rel_floor
            ):
                near_zero_count += 1
        sample_count += count

    if sample_count == 0:
        return {}
    return {
        "max_abs_cpu": max_abs_cpu,
        "min_abs_cpu": min_abs_cpu if math.isfinite(min_abs_cpu) else 0.0,
        "unit_rel_denominator_floor": rel_floor,
        "near_zero_count": near_zero_count,
        "near_zero_fraction": near_zero_count / sample_count if sample_count else 0.0,
        "near_zero_compared_samples": sample_count,
    }


def mixed_error_from_summary(
    explicit_mixed_error: float,
    max_abs_error: float,
    max_rel_error: float,
    rmse: float,
    near_zero_fraction: float,
) -> float:
    if math.isfinite(explicit_mixed_error):
        return explicit_mixed_error
    near_zero_relative = (
        math.isfinite(max_rel_error)
        and max_rel_error > REL_ERROR_THRESHOLD
        and math.isfinite(max_abs_error)
        and max_abs_error <= TRUE_ERROR_ABS_THRESHOLD
        and math.isfinite(rmse)
        and rmse <= TRUE_ERROR_RMSE_THRESHOLD
        and (near_zero_fraction > 0.0 or max_rel_error > 1.0)
    )
    if near_zero_relative and math.isfinite(max_abs_error):
        return max_abs_error
    if math.isfinite(max_rel_error):
        return max_rel_error
    if math.isfinite(max_abs_error):
        return max_abs_error
    return 0.0


def classify_error_metrics(mixed_error: float, kernel_speedup: float, e2e_speedup: float) -> str:
    if math.isfinite(mixed_error) and mixed_error > REL_ERROR_THRESHOLD:
        return "true-error"
    if (
        (math.isfinite(kernel_speedup) and kernel_speedup < 10.0)
        or (math.isfinite(e2e_speedup) and e2e_speedup < 3.0)
    ):
        return "performance-bound"
    return "ok"


def finite_payload_number(value: Any) -> float:
    if isinstance(value, (int, float)):
        out = float(value)
        return out if math.isfinite(out) else math.nan
    return math.nan


def enrich_metrics_payload(payload: dict[str, Any]) -> bool:
    cases = payload.get("cases")
    if not isinstance(cases, list):
        return False

    module = str(payload.get("module", ""))
    changed = False
    summary_near_zero_count = 0
    summary_sample_count = 0
    summary_max_abs_cpu = 0.0
    summary_min_abs_cpu = math.inf
    summary_floor = unit_test_relative_floor(module)

    for case in cases:
        if not isinstance(case, dict):
            continue
        error = case.get("cpu_gpu_error")
        if not isinstance(error, dict):
            continue
        raw_rel = finite_payload_number(error.get("max_rel_error"))
        max_abs_error = finite_payload_number(error.get("max_abs_error"))
        rmse = finite_payload_number(error.get("rmse"))
        explicit_mixed = finite_payload_number(error.get("mixed_error"))
        near_zero = near_zero_metrics_from_cpu_gpu_pairs(module, case)
        if near_zero:
            error["near_zero_count"] = int(near_zero["near_zero_count"])
            error["near_zero_fraction"] = float(near_zero["near_zero_fraction"])
            error["max_abs_cpu"] = float(near_zero["max_abs_cpu"])
            error["min_abs_cpu"] = float(near_zero["min_abs_cpu"])
            error["unit_rel_denominator_floor"] = float(near_zero["unit_rel_denominator_floor"])
            summary_near_zero_count += int(near_zero["near_zero_count"])
            summary_sample_count += int(near_zero["near_zero_compared_samples"])
            summary_max_abs_cpu = max(summary_max_abs_cpu, float(near_zero["max_abs_cpu"]))
            summary_min_abs_cpu = min(summary_min_abs_cpu, float(near_zero["min_abs_cpu"]))
        else:
            error["near_zero_count"] = 0
            error["near_zero_fraction"] = 0.0
            error["unit_rel_denominator_floor"] = summary_floor
        error["mixed_error"] = mixed_error_from_summary(
            explicit_mixed,
            max_abs_error,
            raw_rel,
            rmse,
            float(error.get("near_zero_fraction", 0.0)),
        )
        changed = True

    summary = payload.get("summary")
    if not isinstance(summary, dict):
        return changed

    raw_rel = finite_payload_number(summary.get("max_rel_error"))
    max_abs_error = finite_payload_number(summary.get("max_abs_error"))
    rmse = finite_payload_number(summary.get("rmse"))
    explicit_mixed = finite_payload_number(summary.get("mixed_error"))
    kernel_speedup = finite_payload_number(summary.get("gpu_kernel_speedup"))
    e2e_speedup = finite_payload_number(summary.get("gpu_e2e_speedup"))
    if summary_sample_count > 0:
        near_zero_fraction = summary_near_zero_count / summary_sample_count
        summary["near_zero_count"] = summary_near_zero_count
        summary["near_zero_fraction"] = near_zero_fraction
        summary["max_abs_cpu"] = summary_max_abs_cpu
        summary["min_abs_cpu"] = summary_min_abs_cpu if math.isfinite(summary_min_abs_cpu) else 0.0
    else:
        near_zero_fraction = 0.0
        summary["near_zero_count"] = 0
        summary["near_zero_fraction"] = 0.0
    summary["unit_rel_denominator_floor"] = summary_floor
    mixed_error = mixed_error_from_summary(
        explicit_mixed,
        max_abs_error,
        raw_rel,
        rmse,
        near_zero_fraction,
    )
    summary["mixed_error"] = mixed_error
    summary["error_class"] = classify_error_metrics(
        mixed_error,
        kernel_speedup,
        e2e_speedup,
    )
    return True


def read_metrics_payload(metrics_file: Path) -> dict[str, Any]:
    payload = json.loads(metrics_file.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"metrics file is not a JSON object: {metrics_file}")
    if enrich_metrics_payload(payload):
        metrics_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def summary_timing_stat(summary: dict[str, Any], field: str, stat: str) -> float:
    value = summary.get(field)
    if not isinstance(value, dict):
        return math.nan
    try:
        return float(value.get(stat))
    except (TypeError, ValueError):
        return math.nan


def metrics_from_payload(payload: dict[str, Any]) -> RunMetrics:
    summary = payload.get("summary", {})
    if not isinstance(summary, dict):
        summary = {}

    return RunMetrics(
        summary_pass=summary.get("pass") if isinstance(summary.get("pass"), bool) else None,
        mixed_error=format_metric(summary.get("mixed_error")),
        error_class=format_metric(summary.get("error_class")),
        gpu_e2e_speedup=format_metric(summary.get("gpu_e2e_speedup")),
        gpu_kernel_speedup=format_metric(summary.get("gpu_kernel_speedup")),
        cpu_median_ms=format_metric(summary_timing_stat(summary, "cpu_perf", "median_ms")),
        gpu_e2e_median_ms=format_metric(summary_timing_stat(summary, "gpu_e2e_perf", "median_ms")),
        gpu_kernel_median_ms=format_metric(summary_timing_stat(summary, "gpu_kernel_perf", "median_ms")),
        gpu_e2e_min_ms=format_metric(summary_timing_stat(summary, "gpu_e2e_perf", "min_ms")),
        gpu_e2e_max_ms=format_metric(summary_timing_stat(summary, "gpu_e2e_perf", "max_ms")),
        git_commit=format_metric(payload.get("git_commit")),
        gpu_name=format_metric(payload.get("gpu_name")),
    )


def load_metrics(metrics_file: Path) -> RunMetrics:
    return metrics_from_payload(read_metrics_payload(metrics_file))


def default_baseline_file(repo_root: Path, scale_profile: str) -> Path:
    return (
        repo_root
        / "data"
        / "reports"
        / "unit"
        / "benchmarks"
        / "cpu_baselines"
        / scale_profile
        / "latest_cpu_baseline.json"
    )


def load_baseline(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "schema_version": BASELINE_SCHEMA_VERSION,
            "created_at": "",
            "updated_at": "",
            "entries": {},
        }
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"baseline cache is not a JSON object: {path}")
    entries = payload.get("entries")
    if not isinstance(entries, dict):
        raise ValueError(f"baseline cache has no entries object: {path}")
    return payload


def save_baseline(path: Path, payload: dict[str, Any]) -> None:
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if not payload.get("created_at"):
        payload["created_at"] = now
    payload["updated_at"] = now
    payload["schema_version"] = BASELINE_SCHEMA_VERSION
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def manifest_hash(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def baseline_key(
    target: Target,
    scale_profile: str,
    scale_level: int,
    scale_value: int,
    shape_note: str,
    manifest_sha256: str,
) -> str:
    shape_digest = hashlib.sha256(shape_note.encode("utf-8")).hexdigest()[:16]
    return (
        f"{target.module}/{target.operator}|{scale_profile}|"
        f"L{scale_level}|{scale_value}|{shape_digest}|{manifest_sha256}"
    )


def timing_median(summary: dict[str, Any], field: str) -> float:
    value = summary.get(field)
    if not isinstance(value, dict):
        return math.nan
    try:
        return float(value.get("median_ms"))
    except (TypeError, ValueError):
        return math.nan


def speedup(cpu_perf: dict[str, Any] | None, gpu_perf: dict[str, Any] | None) -> float:
    if not isinstance(cpu_perf, dict) or not isinstance(gpu_perf, dict):
        return math.nan
    try:
        cpu_median = float(cpu_perf.get("median_ms"))
        gpu_median = float(gpu_perf.get("median_ms"))
    except (TypeError, ValueError):
        return math.nan
    if cpu_median <= 0.0 or gpu_median <= 0.0 or not math.isfinite(cpu_median) or not math.isfinite(gpu_median):
        return math.nan
    return cpu_median / gpu_median


def make_baseline_entry(
    payload: dict[str, Any],
    run_id: str,
    target: Target,
    scale_profile: str,
    scale_level: int,
    scale_value: int,
    shape_note: str,
    manifest_sha256: str,
) -> dict[str, Any]:
    summary = payload.get("summary")
    if not isinstance(summary, dict):
        raise ValueError("metrics summary is missing")
    cpu_perf = summary.get("cpu_perf")
    if not isinstance(cpu_perf, dict) or not math.isfinite(timing_median(summary, "cpu_perf")):
        raise ValueError("metrics summary has no usable cpu_perf")
    cached_summary = {key: summary[key] for key in ACCURACY_SUMMARY_FIELDS if key in summary}
    return {
        "run_id": run_id,
        "module": target.module,
        "operator": target.operator,
        "scale_profile": scale_profile,
        "scale_level": scale_level,
        "scale_value": scale_value,
        "shape_note": shape_note,
        "manifest_sha256": manifest_sha256,
        "summary": cached_summary,
        "cpu_perf": cpu_perf,
        "git_commit": payload.get("git_commit", ""),
        "gpu_name": payload.get("gpu_name", ""),
        "metrics_json_path": str(target.metrics_path),
        "updated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }


def merge_gpu_with_baseline(
    payload: dict[str, Any],
    baseline_entry: dict[str, Any],
    baseline_key_value: str,
    metrics_path: Path,
) -> dict[str, Any]:
    summary = payload.setdefault("summary", {})
    if not isinstance(summary, dict):
        raise ValueError("current metrics summary is missing")
    baseline_summary = baseline_entry.get("summary")
    if not isinstance(baseline_summary, dict):
        raise ValueError("baseline entry has no summary")
    cpu_perf = baseline_entry.get("cpu_perf")
    if not isinstance(cpu_perf, dict):
        raise ValueError("baseline entry has no cpu_perf")

    current_pass = summary.get("pass")
    for field in ACCURACY_SUMMARY_FIELDS:
        if field in baseline_summary:
            summary[field] = baseline_summary[field]
    if current_pass is False:
        summary["pass"] = False
    elif "pass" not in summary:
        summary["pass"] = bool(baseline_summary.get("pass", True))

    summary["cpu_perf"] = cpu_perf
    summary["gpu_e2e_speedup"] = speedup(cpu_perf, summary.get("gpu_e2e_perf"))
    summary["gpu_kernel_speedup"] = speedup(cpu_perf, summary.get("gpu_kernel_perf"))
    summary["cpu_baseline_source"] = {
        "mode": "reused",
        "key": baseline_key_value,
        "run_id": baseline_entry.get("run_id", ""),
        "updated_at": baseline_entry.get("updated_at", ""),
    }
    summary["accuracy_source"] = "cpu_baseline_cache"
    payload["cpu_baseline_source"] = summary["cpu_baseline_source"]
    metrics_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def clean_generated_samples(target: Target) -> None:
    generated_root = target.manifest_path.parent
    for dirname in GENERATED_SAMPLE_DIRS:
        path = generated_root / dirname
        if path.exists():
            shutil.rmtree(path)


def run_operator(
    repo_root: Path,
    runner_script: Path,
    build_dir: Path,
    target: Target,
    warmup: int,
    repeat: int,
    do_build: bool,
    keep_generated_samples: bool,
    demo_fast: bool,
    platform: str,
) -> tuple[int, RunMetrics | None, str]:
    return_code, payload, issue = run_operator_payload(
        repo_root,
        runner_script,
        build_dir,
        target,
        warmup,
        repeat,
        do_build,
        keep_generated_samples,
        gpu_only_perf=False,
        demo_fast=demo_fast,
        platform=platform,
    )
    return return_code, metrics_from_payload(payload) if payload is not None else None, issue


def run_operator_payload(
    repo_root: Path,
    runner_script: Path,
    build_dir: Path,
    target: Target,
    warmup: int,
    repeat: int,
    do_build: bool,
    keep_generated_samples: bool,
    gpu_only_perf: bool,
    demo_fast: bool,
    platform: str,
) -> tuple[int, dict[str, Any] | None, str]:
    old_mtime = target.metrics_path.stat().st_mtime_ns if target.metrics_path.exists() else None
    cmd = [
        str(runner_script),
        "--module",
        target.module,
        "--operator",
        target.operator,
        "--case-set",
        "perf",
        "--emit-report",
        "--warmup",
        str(warmup),
        "--repeat",
        str(repeat),
        "--build-dir",
        str(build_dir),
        "--platform",
        platform,
    ]
    if gpu_only_perf:
        cmd.append("--gpu-only-perf")
    if demo_fast:
        cmd.append("--demo-fast")
    if not do_build:
        cmd.append("--no-build")

    mode = "gpu-only " if gpu_only_perf else ""
    log(f"running {mode}{target.module}/{target.operator}: {' '.join(cmd)}")
    completed = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True, check=False)
    if completed.stdout:
        print(completed.stdout, end="")
    if completed.stderr:
        print(completed.stderr, end="", file=sys.stderr)

    error_note = ""
    if completed.returncode != 0:
        tail = "\n".join([completed.stdout, completed.stderr])[-800:]
        error_note = f"command failed, rc={completed.returncode}; output_tail={tail}"

    if not target.metrics_path.exists():
        if not keep_generated_samples:
            clean_generated_samples(target)
        return completed.returncode, None, append_note(error_note, "metrics file missing")

    new_mtime = target.metrics_path.stat().st_mtime_ns
    if old_mtime is not None and new_mtime == old_mtime:
        if not keep_generated_samples:
            clean_generated_samples(target)
        return completed.returncode, None, append_note(error_note, "metrics not updated")

    try:
        payload = read_metrics_payload(target.metrics_path)
        if not keep_generated_samples:
            clean_generated_samples(target)
        return completed.returncode, payload, error_note
    except Exception as exc:  # noqa: BLE001
        if not keep_generated_samples:
            clean_generated_samples(target)
        return completed.returncode, None, append_note(error_note, f"failed to parse metrics: {exc}")


def append_note(existing: str, extra: str) -> str:
    return f"{existing} | {extra}" if existing else extra


def csv_columns() -> list[str]:
    return [
        "run_id",
        "timestamp",
        "scale_level",
        "scale_value",
        "scale_family",
        "module",
        "operator",
        "status",
        "pass",
        "return_code",
        "warmup",
        "repeat",
        "mixed_error",
        "error_class",
        "gpu_e2e_speedup",
        "gpu_kernel_speedup",
        "cpu_median_ms",
        "gpu_e2e_median_ms",
        "gpu_kernel_median_ms",
        "gpu_e2e_min_ms",
        "gpu_e2e_max_ms",
        "shape_note",
        "metrics_json_path",
        "git_commit",
        "gpu_name",
        "error_note",
    ]


def empty_row(
    run_id: str,
    timestamp: str,
    target: Target,
    scale_level: int,
    scale_value: int,
    scale_family: str,
    warmup: int,
    repeat: int,
) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "timestamp": timestamp,
        "scale_level": scale_level,
        "scale_value": scale_value,
        "scale_family": scale_family,
        "module": target.module,
        "operator": target.operator,
        "status": "",
        "pass": "",
        "return_code": "",
        "warmup": warmup,
        "repeat": repeat,
        "mixed_error": "",
        "error_class": "",
        "gpu_e2e_speedup": "",
        "gpu_kernel_speedup": "",
        "cpu_median_ms": "",
        "gpu_e2e_median_ms": "",
        "gpu_kernel_median_ms": "",
        "gpu_e2e_min_ms": "",
        "gpu_e2e_max_ms": "",
        "shape_note": "",
        "metrics_json_path": str(target.metrics_path),
        "git_commit": "",
        "gpu_name": "",
        "error_note": "",
    }


def fill_metrics(row: dict[str, Any], metrics: RunMetrics) -> None:
    for field in (
        "mixed_error",
        "error_class",
        "gpu_e2e_speedup",
        "gpu_kernel_speedup",
        "cpu_median_ms",
        "gpu_e2e_median_ms",
        "gpu_kernel_median_ms",
        "gpu_e2e_min_ms",
        "gpu_e2e_max_ms",
        "git_commit",
        "gpu_name",
    ):
        row[field] = getattr(metrics, field)


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=csv_columns())
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_outputs(
    output_dir: Path,
    run_id: str,
    rows: list[dict[str, Any]],
    report_mode: str,
    scale_profile: str,
    keep_old_output: bool,
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    if not keep_old_output:
        clean_benchmark_outputs(output_dir)
    latest_csv = output_dir / "latest_all_ops_scale_benchmark.csv"
    write_csv(latest_csv, rows)

    if report_mode == "full":
        global_csv = output_dir / f"all_ops_scale_benchmark_{run_id}.csv"
        shutil.copyfile(latest_csv, global_csv)
        modules = sorted({str(row["module"]) for row in rows})
        for module in modules:
            module_rows = [row for row in rows if row.get("module") == module]
            module_csv = output_dir / f"{module}_scale_benchmark_{run_id}.csv"
            module_latest = output_dir / f"latest_{module}_scale_benchmark.csv"
            write_csv(module_csv, module_rows)
            shutil.copyfile(module_csv, module_latest)
        log(f"wrote {global_csv}")

    log(f"updated {latest_csv}")
    if report_mode in {"concise", "full"}:
        write_concise_report(output_dir, run_id, rows, scale_profile)


def clean_benchmark_outputs(output_dir: Path) -> None:
    if not output_dir.exists():
        return
    for pattern in BENCHMARK_OUTPUT_PATTERNS:
        for path in output_dir.glob(pattern):
            if path.is_file():
                path.unlink()
    figures_dir = output_dir / "figures"
    if figures_dir.is_dir():
        shutil.rmtree(figures_dir)


def parse_row_float(row: dict[str, Any], key: str) -> float:
    value = str(row.get(key, "")).strip()
    if not value:
        return math.nan
    try:
        return float(value)
    except ValueError:
        return math.nan


def classify_large_gpu_candidate(row: dict[str, Any]) -> str:
    module = str(row.get("module", ""))
    operator = str(row.get("operator", ""))
    op_label = f"{module}/{operator}"
    if op_label == "radartools/cfar_alpha":
        return "scalar-helper"
    mixed_error = parse_row_float(row, "mixed_error")
    kernel_speedup = parse_row_float(row, "gpu_kernel_speedup")
    e2e_speedup = parse_row_float(row, "gpu_e2e_speedup")
    if str(row.get("error_class", "")) == "true-error" or (
        math.isfinite(mixed_error) and mixed_error > REL_ERROR_THRESHOLD
    ):
        return "error-bound"
    if math.isfinite(kernel_speedup) and kernel_speedup < 10.0:
        return "kernel-bound"
    if (
        math.isfinite(kernel_speedup)
        and math.isfinite(e2e_speedup)
        and kernel_speedup >= 10.0
        and e2e_speedup < 3.0
    ):
        return "e2e-copy-bound"
    return "already-fast"


def recommended_large_gpu_action(row: dict[str, Any]) -> str:
    op_label = f"{row.get('module', '')}/{row.get('operator', '')}"
    if op_label == "filtering/sosfilt":
        return "hierarchical affine prefix-scan"
    if op_label == "filtering/detrend":
        return "two-pass block reduction"
    if op_label == "estimation/kalman_filter":
        return "points-batched register kernel"
    if op_label in {"waveforms/gausspulse", "waveforms/sawtooth"}:
        return "single-precision numeric path"
    if op_label == "filtering/resample":
        return "overflow-safe cuFFT scaling"
    if op_label == "radartools/pulse_doppler":
        return "truncate-safe batched cuFFT pack"
    if op_label == "spectral/vectorstrength":
        return "two-stage parallel reduction"
    if classify_large_gpu_candidate(row) == "e2e-copy-bound":
        return "remove internal copies or improve data residency"
    if op_label == "radartools/cfar_alpha":
        return "none; scalar helper"
    return "none"


def write_large_gpu_candidate_report(output_dir: Path, rows: list[dict[str, Any]]) -> None:
    latest_by_op: dict[tuple[str, str], dict[str, Any]] = {}
    for row in rows:
        key = (str(row.get("module", "")), str(row.get("operator", "")))
        if not key[0] or not key[1]:
            continue
        previous = latest_by_op.get(key)
        if previous is None or parse_row_float(row, "scale_level") >= parse_row_float(previous, "scale_level"):
            latest_by_op[key] = row

    ordered = sorted(
        latest_by_op.values(),
        key=lambda row: (
            classify_large_gpu_candidate(row) not in {"kernel-bound", "error-bound"},
            parse_row_float(row, "gpu_kernel_speedup")
            if math.isfinite(parse_row_float(row, "gpu_kernel_speedup"))
            else math.inf,
            str(row.get("module", "")),
            str(row.get("operator", "")),
        ),
    )
    columns = [
        "module",
        "operator",
        "largest_scale_value",
        "bottleneck_type",
        "recommended_action",
        "mixed_error",
        "gpu_e2e_speedup",
        "gpu_kernel_speedup",
        "status",
    ]
    csv_path = output_dir / "latest_large_gpu_candidate_report.csv"
    md_path = output_dir / "latest_large_gpu_candidate_report.md"
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for row in ordered:
            writer.writerow(
                {
                    "module": row.get("module", ""),
                    "operator": row.get("operator", ""),
                    "largest_scale_value": row.get("scale_value", ""),
                    "bottleneck_type": classify_large_gpu_candidate(row),
                    "recommended_action": recommended_large_gpu_action(row),
                    "mixed_error": row.get("mixed_error", ""),
                    "gpu_e2e_speedup": row.get("gpu_e2e_speedup", ""),
                    "gpu_kernel_speedup": row.get("gpu_kernel_speedup", ""),
                    "status": row.get("status", ""),
                }
            )

    counts: dict[str, int] = {}
    for row in latest_by_op.values():
        label = classify_large_gpu_candidate(row)
        counts[label] = counts.get(label, 0) + 1
    with md_path.open("w", encoding="utf-8") as handle:
        handle.write("# Large-GPU Candidate Report\n\n")
        handle.write("## Bottleneck Counts\n\n")
        for label in ["kernel-bound", "error-bound", "e2e-copy-bound", "scalar-helper", "already-fast"]:
            handle.write(f"- {label}: {counts.get(label, 0)}\n")
        handle.write("\n## Priority Operators\n\n")
        handle.write("| Operator | Type | Action | Mixed error | E2E speedup | Kernel speedup |\n")
        handle.write("|---|---|---|---:|---:|---:|\n")
        for row in ordered[:25]:
            handle.write(
                f"| {row.get('module', '')}/{row.get('operator', '')} | "
                f"{classify_large_gpu_candidate(row)} | "
                f"{recommended_large_gpu_action(row)} | "
                f"{parse_row_float(row, 'mixed_error'):.3g} | "
                f"{parse_row_float(row, 'gpu_e2e_speedup'):.3g} | "
                f"{parse_row_float(row, 'gpu_kernel_speedup'):.3g} |\n"
            )
    log(f"wrote {csv_path}")
    log(f"wrote {md_path}")


def latest_rows_by_operator(rows: list[dict[str, Any]]) -> dict[tuple[str, str], dict[str, Any]]:
    latest_by_op: dict[tuple[str, str], dict[str, Any]] = {}
    for row in rows:
        key = (str(row.get("module", "")), str(row.get("operator", "")))
        if not key[0] or not key[1]:
            continue
        previous = latest_by_op.get(key)
        if previous is None or parse_row_float(row, "scale_level") >= parse_row_float(previous, "scale_level"):
            latest_by_op[key] = row
    return latest_by_op


def write_concise_report(
    output_dir: Path,
    run_id: str,
    rows: list[dict[str, Any]],
    scale_profile: str,
) -> None:
    path = output_dir / "latest_report.md"
    latest_by_op = latest_rows_by_operator(rows)
    status_counts: dict[str, int] = {}
    for row in rows:
        status = str(row.get("status", "") or "unknown")
        status_counts[status] = status_counts.get(status, 0) + 1
    latest_rows = sorted(latest_by_op.values(), key=lambda row: (str(row.get("module", "")), str(row.get("operator", ""))))

    def finite_sort_value(row: dict[str, Any], key: str, default: float, reverse: bool = False) -> float:
        value = parse_row_float(row, key)
        if math.isfinite(value):
            return value
        return default if not reverse else -default

    with path.open("w", encoding="utf-8") as handle:
        handle.write("# All-Operator Benchmark Report\n\n")
        handle.write(f"- run_id: `{run_id}`\n")
        handle.write(f"- scale_profile: `{scale_profile}`\n")
        handle.write(f"- rows: `{len(rows)}`\n")
        handle.write(f"- operators: `{len(latest_by_op)}`\n")
        handle.write(f"- passed_rows: `{status_counts.get('passed', 0)}`\n")
        handle.write(
            "- status: "
            + ", ".join(f"{key}={value}" for key, value in sorted(status_counts.items()))
            + "\n"
        )
        handle.write("- data_csv: `latest_all_ops_scale_benchmark.csv`\n")

        handle.write("\n## Largest-Scale Operator Summary\n\n")
        handle.write("| Operator | Scale | Status | Mixed error | E2E speedup | Kernel speedup |\n")
        handle.write("|---|---:|---|---:|---:|---:|\n")
        for row in latest_rows:
            handle.write(
                f"| {row.get('module', '')}/{row.get('operator', '')} | "
                f"{row.get('scale_value', '')} | "
                f"{row.get('status', '')} | "
                f"{parse_row_float(row, 'mixed_error'):.3g} | "
                f"{parse_row_float(row, 'gpu_e2e_speedup'):.3g} | "
                f"{parse_row_float(row, 'gpu_kernel_speedup'):.3g} |\n"
            )

        high_error = sorted(
            latest_rows,
            key=lambda row: finite_sort_value(row, "mixed_error", math.inf, reverse=True),
            reverse=True,
        )[:12]
        low_e2e = sorted(latest_rows, key=lambda row: finite_sort_value(row, "gpu_e2e_speedup", math.inf))[:12]
        low_kernel = sorted(latest_rows, key=lambda row: finite_sort_value(row, "gpu_kernel_speedup", math.inf))[:12]

        handle.write("\n## Highest Mixed Error\n\n")
        handle.write("| Operator | Mixed error | E2E speedup | Kernel speedup |\n")
        handle.write("|---|---:|---:|---:|\n")
        for row in high_error:
            handle.write(
                f"| {row.get('module', '')}/{row.get('operator', '')} | "
                f"{parse_row_float(row, 'mixed_error'):.3g} | "
                f"{parse_row_float(row, 'gpu_e2e_speedup'):.3g} | "
                f"{parse_row_float(row, 'gpu_kernel_speedup'):.3g} |\n"
            )

        handle.write("\n## Lowest E2E Speedup\n\n")
        handle.write("| Operator | E2E speedup | Kernel speedup | Mixed error |\n")
        handle.write("|---|---:|---:|---:|\n")
        for row in low_e2e:
            handle.write(
                f"| {row.get('module', '')}/{row.get('operator', '')} | "
                f"{parse_row_float(row, 'gpu_e2e_speedup'):.3g} | "
                f"{parse_row_float(row, 'gpu_kernel_speedup'):.3g} | "
                f"{parse_row_float(row, 'mixed_error'):.3g} |\n"
            )

        handle.write("\n## Lowest Kernel Speedup\n\n")
        handle.write("| Operator | Kernel speedup | E2E speedup | Mixed error |\n")
        handle.write("|---|---:|---:|---:|\n")
        for row in low_kernel:
            handle.write(
                f"| {row.get('module', '')}/{row.get('operator', '')} | "
                f"{parse_row_float(row, 'gpu_kernel_speedup'):.3g} | "
                f"{parse_row_float(row, 'gpu_e2e_speedup'):.3g} | "
                f"{parse_row_float(row, 'mixed_error'):.3g} |\n"
            )
    log(f"updated {path}")


def main() -> int:
    args = parse_args()
    script_path = Path(__file__).resolve()
    repo_root = script_path.parents[2]
    runner_script = resolve_path(repo_root, args.runner_script)
    build_dir = resolve_path(repo_root, args.build_dir)
    output_dir = resolve_path(repo_root, args.output_dir)
    baseline_file = (
        resolve_path(repo_root, args.cpu_baseline_file)
        if args.cpu_baseline_file
        else default_baseline_file(repo_root, args.scale_profile)
    )

    entries = load_enabled_entries(runner_script, build_dir, args.platform)
    filtered_entries = filter_entries(entries, args.modules, args.operators)
    target_names = [target_name for _module, _operator, target_name in filtered_entries]
    targets = [
        make_target(repo_root, module, operator)
        for module, operator, _target_name in filtered_entries
    ]
    baseline: dict[str, Any] | None = None
    baseline_entries: dict[str, Any] = {}
    baseline_changed = False
    if args.gpu_only:
        baseline = load_baseline(baseline_file)
        entries_obj = baseline.setdefault("entries", {})
        if not isinstance(entries_obj, dict):
            raise ValueError("baseline entries is not an object")
        baseline_entries = entries_obj

    run_started = datetime.now()
    run_id = run_started.strftime("%Y%m%d_%H%M%S")
    timestamp = run_started.strftime("%Y-%m-%d %H:%M:%S")
    rows: list[dict[str, Any]] = []
    has_failure = False

    backups = backup_manifests(targets)
    log(f"selected operators: {len(targets)}")
    log(f"build mode: {'build' if args.do_build else 'no-build'}")
    log(f"platform: {args.platform}")
    log(f"scale profile: {args.scale_profile}")
    log(f"scale levels: {','.join(str(level) for level in args.scale_levels)}")
    log(f"report mode: {args.report_mode}")
    if args.gpu_only:
        log(f"gpu-only mode: enabled")
        log(f"cpu baseline mode: {args.cpu_baseline_mode}")
        log(f"cpu baseline file: {baseline_file}")
    log(
        f"timing: warmup={args.warmup} repeat={args.repeat}"
        f"{' (demo-fast)' if args.demo_fast else ''}"
    )
    if args.do_build:
        build_selected_targets(repo_root, build_dir, target_names, args.platform)
        args.do_build = False
    log("backed up manifests")

    try:
        for target_index, target in enumerate(targets, start=1):
            family = scale_family_for(target.module, target.operator, args.scale_profile, args.platform)
            scales = scale_values_for(args.scale_profile, family)
            original_text = backups[target.manifest_path]
            for scale_index in args.scale_levels:
                scale_value = scales[scale_index - 1]
                log(
                    f"[{target_index}/{len(targets)} L{scale_index}] "
                    f"{target.module}/{target.operator} scale={scale_value}"
                )
                row = empty_row(
                    run_id,
                    timestamp,
                    target,
                    scale_index,
                    scale_value,
                    family,
                    args.warmup,
                    args.repeat,
                )
                try:
                    shape_note = rewrite_manifest(target, original_text, scale_value)
                    row["shape_note"] = shape_note
                    metrics: RunMetrics | None = None
                    return_code = 1
                    issue = ""

                    if not args.gpu_only:
                        return_code, metrics, issue = run_operator(
                            repo_root,
                            runner_script,
                            build_dir,
                            target,
                            args.warmup,
                            args.repeat,
                            args.do_build,
                            args.keep_generated_samples,
                            demo_fast=args.demo_fast,
                            platform=args.platform,
                        )
                    else:
                        if baseline is None:
                            raise RuntimeError("internal error: baseline cache not initialized")
                        manifest_sha = manifest_hash(target.manifest_path)
                        key = baseline_key(
                            target,
                            args.scale_profile,
                            scale_index,
                            scale_value,
                            shape_note,
                            manifest_sha,
                        )
                        cached_entry = baseline_entries.get(key)
                        refresh_baseline = args.cpu_baseline_mode == "refresh" or (
                            args.cpu_baseline_mode == "auto" and not isinstance(cached_entry, dict)
                        )

                        if args.cpu_baseline_mode == "reuse" and not isinstance(cached_entry, dict):
                            raise RuntimeError(f"missing CPU baseline entry: {key}")

                        if refresh_baseline:
                            return_code, payload, issue = run_operator_payload(
                                repo_root,
                                runner_script,
                                build_dir,
                                target,
                                args.warmup,
                                args.repeat,
                                args.do_build,
                                args.keep_generated_samples,
                                gpu_only_perf=False,
                                demo_fast=args.demo_fast,
                                platform=args.platform,
                            )
                            if payload is not None:
                                metrics = metrics_from_payload(payload)
                                try:
                                    baseline_entries[key] = make_baseline_entry(
                                        payload,
                                        run_id,
                                        target,
                                        args.scale_profile,
                                        scale_index,
                                        scale_value,
                                        shape_note,
                                        manifest_sha,
                                    )
                                    baseline_changed = True
                                    issue = append_note(issue, "cpu_baseline=refreshed")
                                except Exception as exc:  # noqa: BLE001
                                    issue = append_note(issue, f"baseline update skipped: {exc}")
                        else:
                            if not isinstance(cached_entry, dict):
                                raise RuntimeError(f"missing CPU baseline entry: {key}")
                            return_code, payload, issue = run_operator_payload(
                                repo_root,
                                runner_script,
                                build_dir,
                                target,
                                args.warmup,
                                args.repeat,
                                args.do_build,
                                args.keep_generated_samples,
                                gpu_only_perf=True,
                                demo_fast=args.demo_fast,
                                platform=args.platform,
                            )
                            if payload is not None:
                                merged = merge_gpu_with_baseline(payload, cached_entry, key, target.metrics_path)
                                metrics = metrics_from_payload(merged)
                                issue = append_note(
                                    issue,
                                    "cpu_baseline=reused; accuracy=baseline; gpu_output=not_materialized",
                                )

                    row["return_code"] = return_code
                    if metrics is not None:
                        fill_metrics(row, metrics)
                    row_pass = return_code == 0 and metrics is not None and metrics.summary_pass is True
                    row["pass"] = "true" if row_pass else "false"
                    row["status"] = "passed" if row_pass else "failed"
                    row["error_note"] = issue
                    if not row_pass:
                        has_failure = True
                except Exception as exc:  # noqa: BLE001
                    row["status"] = "failed"
                    row["pass"] = "false"
                    row["error_note"] = str(exc)
                    has_failure = True
                rows.append(row)
    finally:
        log("restoring original manifests")
        restore_manifests(backups)
        if args.gpu_only and baseline_changed and baseline is not None:
            save_baseline(baseline_file, baseline)
            log(f"updated CPU baseline cache: {baseline_file}")

    write_outputs(output_dir, run_id, rows, args.report_mode, args.scale_profile, args.keep_old_output)
    if args.scale_profile == "large-gpu" and args.report_mode == "full":
        write_large_gpu_candidate_report(output_dir, rows)
    log(f"rows={len(rows)}")
    return 1 if has_failure else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        log("interrupted")
        raise SystemExit(130)
    except Exception as exc:  # noqa: BLE001
        log(f"error: {exc}")
        raise SystemExit(1)
