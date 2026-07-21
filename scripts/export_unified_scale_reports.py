#!/usr/bin/env python3
"""Validate and publish the formal-PPT unified L1-L6 task measurements.

The task binaries write a raw latest_metrics.json for each invocation.  This
tool turns the six raw measurements per task into a separately named evidence
set, computes statistics from repeat runs, and records the speedup directly so
slides never need to re-calculate it by hand.
"""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import json
import math
import shutil
import statistics
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


TASKS = ("task1_radar", "task2_features")
LEVELS = tuple(range(1, 7))
EXPECTED_DIMS: dict[str, dict[int, tuple[int, int]]] = {
    "task1_radar": {
        1: (16, 1536), 2: (32, 1536), 3: (48, 2048),
        4: (64, 2048), 5: (96, 3072), 6: (128, 4096),
    },
    "task2_features": {
        1: (8, 3072), 2: (16, 3072), 3: (32, 3072),
        4: (64, 3072), 5: (96, 3072), 6: (128, 3072),
    },
}
CONSTANT_FIELDS: dict[str, tuple[str, ...]] = {
    "task1_radar": (
        "fs", "template_length", "prf", "doppler_hz", "target_amplitude",
        "snr_db", "seed", "pulse_compression_nfft", "pulse_doppler_nfft",
        "pulse_compression_normalize", "pulse_compression_window",
        "pulse_doppler_window", "cfar_guard_cells", "cfar_reference_cells", "cfar_pfa",
    ),
    "task2_features": (
        "fs", "samples_per_frame", "template_length", "target_step_per_frame",
        "interferer_length", "target_amplitude", "interferer_amplitude", "snr_db",
        "seed", "filter_numtaps", "filter_band_hz", "spectrogram_nperseg",
        "spectrogram_noverlap", "spectrogram_nfft", "peak_order",
        "kalman_rmse_tolerance",
    ),
}
EXPECTED_CONSTANTS: dict[str, dict[str, Any]] = {
    "task1_radar": {
        "fs": 1.0e6, "template_length": 1024, "prf": 2000.0,
        "doppler_hz": 125.0, "target_amplitude": 1.0, "snr_db": 20.0,
        "seed": 20260414, "pulse_compression_nfft": 4096,
        "pulse_doppler_nfft": 128, "pulse_compression_normalize": True,
        "pulse_compression_window": "", "pulse_doppler_window": "hann",
        "cfar_guard_cells": [2, 2], "cfar_reference_cells": [8, 8], "cfar_pfa": 0.001,
    },
    "task2_features": {
        "fs": 1.0e6, "samples_per_frame": 3072, "template_length": 1024,
        "target_step_per_frame": 3, "interferer_length": 1024,
        "target_amplitude": 1.0, "interferer_amplitude": 0.45, "snr_db": 12.0,
        "seed": 20260414, "filter_numtaps": 257,
        "filter_band_hz": [60000.0, 220000.0], "spectrogram_nperseg": 384,
        "spectrogram_noverlap": 288, "spectrogram_nfft": 512,
        "peak_order": 8, "kalman_rmse_tolerance": 2.0,
    },
}


class EvidenceError(RuntimeError):
    """A raw task measurement does not meet the formal-PPT contract."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True,
                        help="directory containing task1_radar/L1...L6 raw artifacts")
    parser.add_argument("--output-root", type=Path, required=True,
                        help="data/reports/demo directory to receive unified_scales")
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EvidenceError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(payload, dict):
        raise EvidenceError(f"JSON object expected: {path}")
    return payload


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def numeric(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise EvidenceError(f"{name} must be numeric")
    result = float(value)
    if not math.isfinite(result):
        raise EvidenceError(f"{name} must be finite")
    return result


def same_value(left: Any, right: Any) -> bool:
    if isinstance(left, (int, float)) and not isinstance(left, bool) and \
            isinstance(right, (int, float)) and not isinstance(right, bool):
        return math.isclose(float(left), float(right), rel_tol=1.0e-8, abs_tol=1.0e-10)
    return left == right


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def get_mapping(container: dict[str, Any], name: str) -> dict[str, Any]:
    value = container.get(name)
    if not isinstance(value, dict):
        raise EvidenceError(f"missing object: {name}")
    return value


def validate_task_correctness(task: str, metrics: dict[str, Any], label: str) -> None:
    validation = get_mapping(metrics, "validation")
    if validation.get("pass") is not True:
        raise EvidenceError(f"{label}: task validation did not pass")
    consistency = get_mapping(metrics, "consistency")
    if task == "task1_radar":
        for field in ("cpu_gpu_detection_match", "gpu_matches_expected_detection"):
            if consistency.get(field) is not True:
                raise EvidenceError(f"{label}: {field} is not true")
    else:
        for field in ("cpu_gpu_track_match", "gpu_matches_truth_within_tolerance"):
            if consistency.get(field) is not True:
                raise EvidenceError(f"{label}: {field} is not true")


def validate_and_summarize(task: str, level: int, metrics_path: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    metrics = read_json(metrics_path)
    label = f"{task}/L{level}"
    scenario = get_mapping(metrics, "scenario")
    if scenario.get("unified_scale_protocol") is not True:
        raise EvidenceError(f"{label}: unified_scale_protocol is not true")
    if scenario.get("scale_level") != level:
        raise EvidenceError(f"{label}: scale_level does not match its directory")
    dim_fields = ("num_pulses", "samples_per_pulse") if task == "task1_radar" else ("num_frames", "samples_per_frame")
    actual_dims = tuple(scenario.get(field) for field in dim_fields)
    if actual_dims != EXPECTED_DIMS[task][level]:
        raise EvidenceError(f"{label}: dimensions {actual_dims!r} != expected {EXPECTED_DIMS[task][level]!r}")
    if scenario.get("rx_shape") != list(actual_dims):
        raise EvidenceError(f"{label}: rx_shape is inconsistent with scenario dimensions")
    for field, expected in EXPECTED_CONSTANTS[task].items():
        if not same_value(scenario.get(field), expected):
            raise EvidenceError(
                f"{label}: frozen L6 field {field} is {scenario.get(field)!r}, expected {expected!r}")
    validate_task_correctness(task, metrics, label)

    repeats = metrics.get("repeat_runs")
    if not isinstance(repeats, list) or len(repeats) < 3:
        raise EvidenceError(f"{label}: at least three repeats are required")
    # Task binaries explicitly use run 1 as warm-up for their stability check.
    measured_repeats = repeats[1:]
    cpu_samples: list[float] = []
    gpu_samples: list[float] = []
    for index, repeat in enumerate(repeats, start=1):
        if not isinstance(repeat, dict) or repeat.get("pass") is not True or \
                repeat.get("business_numeric_pass") is not True:
            raise EvidenceError(f"{label}: repeat {index} did not pass")
        cpu = numeric(repeat.get("cpu_total_ms"), f"{label} repeat {index} cpu_total_ms")
        gpu = numeric(repeat.get("gpu_total_ms"), f"{label} repeat {index} gpu_total_ms")
        if cpu <= 0.0 or gpu <= 0.0:
            raise EvidenceError(f"{label}: repeat {index} has non-positive timing")
        if index > 1:
            cpu_samples.append(cpu)
            gpu_samples.append(gpu)

    cpu_median = float(statistics.median(cpu_samples))
    gpu_median = float(statistics.median(gpu_samples))
    timings = get_mapping(metrics, "timings")
    raw_total = copy.deepcopy(get_mapping(timings, "total"))
    kernel_total = numeric(raw_total.get("gpu_kernel_ms"), f"{label} gpu_kernel_ms")
    summary = {
        "repeat_count": len(repeats),
        "warmup_excluded": 1,
        "measured_repeat_count": len(measured_repeats),
        "aggregation": "median of repeat_runs[1:] after one warm-up iteration",
        "cpu_total": {
            "median_ms": cpu_median,
            "p95_ms": percentile(cpu_samples, 0.95),
            "samples_ms": cpu_samples,
        },
        "gpu_total": {
            "median_ms": gpu_median,
            "p95_ms": percentile(gpu_samples, 0.95),
            "samples_ms": gpu_samples,
        },
        "gpu_kernel_total": {
            "profiled_final_run_ms": kernel_total,
            "source": "sum of final-run stage gpu_kernel_ms; task binary does not emit per-repeat kernel samples",
        },
        "speedup_cpu_over_gpu": cpu_median / gpu_median,
    }
    return metrics, summary


def task_correctness_summary(task: str, metrics: dict[str, Any]) -> dict[str, Any]:
    if task == "task1_radar":
        return {
            "expected_detection": metrics.get("expected_detection"),
            "cpu_detection": metrics.get("cpu_detection"),
            "gpu_detection": metrics.get("gpu_detection"),
            "pulse_doppler_mixed_error": get_mapping(metrics, "pulse_doppler_error").get("mixed_error"),
            "cfar_threshold_mixed_error": get_mapping(metrics, "cfar_threshold_error").get("mixed_error"),
        }
    return {
        "kalman_track_rmse": get_mapping(metrics, "kalman_track_error").get("rmse"),
        "feature_score_mixed_error": get_mapping(metrics, "feature_score_error").get("mixed_error"),
        "cpu_gpu_track_match": get_mapping(metrics, "consistency").get("cpu_gpu_track_match"),
        "gpu_matches_truth_within_tolerance": get_mapping(metrics, "consistency").get("gpu_matches_truth_within_tolerance"),
    }


def copy_artifacts(source_dir: Path, destination_dir: Path) -> None:
    for item in source_dir.iterdir():
        if item.is_file() and item.name != "latest_metrics.json":
            stem = item.name.removeprefix("latest_")
            shutil.copy2(item, destination_dir / stem)
    scenario = source_dir / "input_scenario.json"
    if not scenario.is_file():
        raise EvidenceError(f"missing input scenario artifact: {scenario}")
    shutil.copy2(scenario, destination_dir / "input_scenario.json")


def main() -> int:
    args = parse_args()
    source_root = args.source_root.resolve()
    output_root = args.output_root.resolve()
    if not source_root.is_dir():
        raise EvidenceError(f"source root is not a directory: {source_root}")
    output_root.mkdir(parents=True, exist_ok=True)

    collected: dict[str, dict[int, tuple[dict[str, Any], dict[str, Any], Path]]] = {}
    for task in TASKS:
        task_rows: dict[int, tuple[dict[str, Any], dict[str, Any], Path]] = {}
        reference_scenario: dict[str, Any] | None = None
        for level in LEVELS:
            source_dir = source_root / task / f"L{level}"
            metrics_path = source_dir / "latest_metrics.json"
            if not metrics_path.is_file():
                raise EvidenceError(f"missing raw measurement: {metrics_path}")
            metrics, measurement = validate_and_summarize(task, level, metrics_path)
            scenario = get_mapping(metrics, "scenario")
            if reference_scenario is None:
                reference_scenario = scenario
            else:
                for field in CONSTANT_FIELDS[task]:
                    if not same_value(scenario.get(field), reference_scenario.get(field)):
                        raise EvidenceError(
                            f"{task}/L{level}: frozen field {field} differs from L1 "
                            f"({scenario.get(field)!r} != {reference_scenario.get(field)!r})")
            task_rows[level] = (metrics, measurement, source_dir)
        collected[task] = task_rows

    stage_root = Path(tempfile.mkdtemp(prefix=".unified_scales.", dir=output_root))
    try:
        report_rows: list[dict[str, Any]] = []
        for task, task_rows in collected.items():
            task_stage = stage_root / task
            task_stage.mkdir(parents=True)
            for level, (raw_metrics, measurement, source_dir) in task_rows.items():
                level_stage = task_stage / f"L{level}"
                level_stage.mkdir()
                copy_artifacts(source_dir, level_stage)
                published = copy.deepcopy(raw_metrics)
                raw_total = copy.deepcopy(get_mapping(get_mapping(raw_metrics, "timings"), "total"))
                total = get_mapping(get_mapping(published, "timings"), "total")
                total["cpu_ms"] = measurement["cpu_total"]["median_ms"]
                total["gpu_ms"] = measurement["gpu_total"]["median_ms"]
                total["aggregation"] = measurement["aggregation"]
                published["raw_final_timing_total"] = raw_total
                published["measurement"] = measurement
                published["speedup"] = {
                    "cpu_over_gpu": measurement["speedup_cpu_over_gpu"],
                    "formula": "median_cpu_total_ms / median_gpu_total_ms",
                }
                published["correctness_summary"] = task_correctness_summary(task, raw_metrics)
                published["provenance"] = {
                    "protocol": "unified_l1_l6_v1",
                    "raw_metrics_relative_path": f"{task}/L{level}/latest_metrics.json",
                    "raw_metrics_sha256": sha256(source_dir / "latest_metrics.json"),
                    "published_utc": datetime.now(timezone.utc).isoformat(),
                }
                (level_stage / "metrics.json").write_text(
                    json.dumps(published, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                scenario = get_mapping(raw_metrics, "scenario")
                dims = EXPECTED_DIMS[task][level]
                report_rows.append({
                    "task": task,
                    "level": level,
                    "input_shape": f"{dims[0]} x {dims[1]}",
                    "input_elements": scenario.get("scale_value"),
                    "cpu_median_ms": measurement["cpu_total"]["median_ms"],
                    "gpu_median_ms": measurement["gpu_total"]["median_ms"],
                    "gpu_p95_ms": measurement["gpu_total"]["p95_ms"],
                    "gpu_kernel_profiled_final_ms": measurement["gpu_kernel_total"]["profiled_final_run_ms"],
                    "speedup_cpu_over_gpu": measurement["speedup_cpu_over_gpu"],
                    "validation_pass": True,
                })

        report_rows.sort(key=lambda row: (row["task"], row["level"]))
        csv_path = stage_root / "unified_scale_summary.csv"
        with csv_path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(report_rows[0]))
            writer.writeheader()
            writer.writerows(report_rows)
        (stage_root / "unified_scale_summary.json").write_text(
            json.dumps({
                "protocol": "unified_l1_l6_v1",
                "description": "L6 acceptance configuration frozen; only input dimensions vary by level.",
                "warmup_policy": "first repeat is excluded; CPU/GPU totals use median of later repeats",
                "speedup_formula": "median_cpu_total_ms / median_gpu_total_ms",
                "rows": report_rows,
            }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        lines = [
            "# 统一 L1–L6 正式答辩测评汇总", "",
            "- 协议：固定 L6 算法/验证参数，仅改变输入尺寸。",
            "- 统计：首轮 warm-up 不计入，CPU/GPU 总时延取其余重复的中位数。",
            "- 加速比：`CPU 中位总时延 / GPU 中位总时延`，已直接写入 JSON 与 CSV。", "",
            "| 任务 | 规模 | 输入形状 | CPU中位 ms | GPU中位 ms | GPU P95 ms | 加速比 | 验证 |",
            "| --- | --- | --- | ---: | ---: | ---: | ---: | --- |",
        ]
        for row in report_rows:
            lines.append(
                f"| {row['task']} | L{row['level']} | {row['input_shape']} | "
                f"{row['cpu_median_ms']:.6f} | {row['gpu_median_ms']:.6f} | "
                f"{row['gpu_p95_ms']:.6f} | {row['speedup_cpu_over_gpu']:.3f}x | PASS |")
        (stage_root / "unified_scale_summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

        destination = output_root / "unified_scales"
        backup: Path | None = None
        if destination.exists():
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup = output_root / f"unified_scales.backup_{timestamp}"
            destination.rename(backup)
        stage_root.rename(destination)
        print(f"published unified evidence: {destination}")
        if backup is not None:
            print(f"previous unified evidence preserved: {backup}")
    except Exception:
        shutil.rmtree(stage_root, ignore_errors=True)
        raise
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except EvidenceError as exc:
        print(f"[unified-scale-export] error: {exc}", file=sys.stderr)
        raise SystemExit(2)
