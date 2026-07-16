#!/usr/bin/env python3

"""Validate and summarize the V6.8 Task1/Task2 L1-L6 report matrix."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from pathlib import Path
from typing import Any


EXPECTED_STEPS = {
    "task1_radar": {
        "pulse_compression",
        "pulse_doppler",
        "power_map",
        "ca_cfar",
        "ambgfun",
        "final_detection",
    },
    "task2_features": {
        "filter",
        "demod",
        "correlate",
        "spectrogram",
        "cwt",
        "feature_fusion",
        "measurement_conversion",
        "kalman",
    },
}
EXPECTED_SCHEMA_VERSION = 2
REQUIRED_STEP_FIELDS = {
    "step",
    "operator",
    "input_shape",
    "output_shape",
    "input_dtype",
    "output_dtype",
    "cpu_ms",
    "gpu_e2e_ms",
    "gpu_kernel_ms",
    "gpu_e2e_speedup",
    "gpu_kernel_speedup",
    "error_available",
    "error",
    "pass",
    "note",
}
ERROR_FIELDS = ("max_abs", "max_rel", "rmse", "mixed_error")
MODES = {
    "first_process": 1,
    "warm": 5,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--first-root", required=True)
    parser.add_argument("--warm-root", required=True)
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args()


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and math.isfinite(float(value))


def nearest_rank_percentile(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return math.nan
    rank = max(1, math.ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def relative(path: Path, base: Path) -> str:
    try:
        return str(path.relative_to(base))
    except ValueError:
        return str(path)


def validate_step_report(
    task: str,
    scale: int,
    step_json_path: Path,
    step_csv_path: Path,
    failures: list[str],
) -> tuple[list[dict[str, Any]], int]:
    if not step_json_path.is_file():
        failures.append(f"missing step JSON: {step_json_path}")
        return [], 0
    if not step_csv_path.is_file():
        failures.append(f"missing step CSV: {step_csv_path}")
        return [], 0

    payload = read_json(step_json_path)
    steps = payload.get("steps", [])
    if payload.get("task") != task:
        failures.append(
            f"invalid task in {step_json_path}: {payload.get('task')!r}"
        )
    if payload.get("schema_version") != EXPECTED_SCHEMA_VERSION:
        failures.append(
            f"invalid schema in {step_json_path}: {payload.get('schema_version')!r}"
        )

    expected = EXPECTED_STEPS[task]
    actual = {str(step.get("step", "")) for step in steps if isinstance(step, dict)}
    if actual != expected:
        failures.append(
            f"step mismatch for {task}/L{scale}: expected={sorted(expected)} actual={sorted(actual)}"
        )

    normalized: list[dict[str, Any]] = []
    for step in steps:
        if not isinstance(step, dict):
            failures.append(f"non-object step in {step_json_path}")
            continue
        name = str(step.get("step", ""))
        missing = REQUIRED_STEP_FIELDS - set(step)
        if missing:
            failures.append(
                f"missing fields for {task}/L{scale}/{name}: {sorted(missing)}"
            )
            continue
        if step.get("pass") is not True:
            failures.append(f"step failed: {task}/L{scale}/{name}")
        if step.get("error_available") is not True:
            failures.append(f"step error missing: {task}/L{scale}/{name}")
        for field in ("cpu_ms", "gpu_e2e_ms"):
            if not finite_number(step.get(field)) or float(step[field]) < 0.0:
                failures.append(
                    f"invalid {field}: {task}/L{scale}/{name}={step.get(field)!r}"
                )
        kernel_ms = step.get("gpu_kernel_ms")
        if kernel_ms is not None and (
            not finite_number(kernel_ms) or float(kernel_ms) < 0.0
        ):
            failures.append(
                f"invalid gpu_kernel_ms: {task}/L{scale}/{name}={kernel_ms!r}"
            )
        error = step.get("error")
        if not isinstance(error, dict):
            failures.append(f"invalid error object: {task}/L{scale}/{name}")
            error = {}
        for field in ERROR_FIELDS:
            if not finite_number(error.get(field)):
                failures.append(
                    f"invalid error {field}: {task}/L{scale}/{name}={error.get(field)!r}"
                )
        normalized.append(step)

    with step_csv_path.open("r", encoding="utf-8", newline="") as handle:
        csv_rows = list(csv.DictReader(handle))
    csv_steps = {str(row.get("step", "")) for row in csv_rows}
    if csv_steps != expected:
        failures.append(
            f"step CSV mismatch for {task}/L{scale}: "
            f"expected={sorted(expected)} actual={sorted(csv_steps)}"
        )
    if any(None in row for row in csv_rows):
        failures.append(f"malformed step CSV: {step_csv_path}")
    return normalized, len(csv_rows)


def summarize_case(
    mode: str,
    expected_repeat: int,
    task: str,
    scale: int,
    case_dir: Path,
    evidence_root: Path,
    failures: list[str],
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    metrics_path = case_dir / "latest_metrics.json"
    step_json_path = case_dir / "latest_step_metrics.json"
    step_csv_path = case_dir / "latest_step_metrics.csv"
    process_wall_path = case_dir / "process_wall_ns.txt"
    if not metrics_path.is_file():
        failures.append(f"missing metrics: {metrics_path}")
        return None, []
    process_wall_ms = None
    if not process_wall_path.is_file():
        failures.append(f"missing process wall: {process_wall_path}")
    else:
        try:
            process_wall_ns = int(process_wall_path.read_text(encoding="utf-8").strip())
        except ValueError:
            process_wall_ns = 0
        if process_wall_ns <= 0:
            failures.append(f"invalid process wall: {process_wall_path}")
        else:
            process_wall_ms = process_wall_ns / 1_000_000.0

    metrics = read_json(metrics_path)
    scenario = metrics.get("scenario", {})
    if scenario.get("scale_level") != scale:
        failures.append(
            f"scale mismatch for {mode}/{task}/L{scale}: "
            f"{scenario.get('scale_level')!r}"
        )
    validation = metrics.get("validation", {})
    if validation.get("pass") is not True:
        failures.append(f"task validation failed: {mode}/{task}/L{scale}")

    repeat_runs = metrics.get("repeat_runs", [])
    if not isinstance(repeat_runs, list) or len(repeat_runs) != expected_repeat:
        failures.append(
            f"repeat mismatch for {mode}/{task}/L{scale}: "
            f"expected={expected_repeat} actual={len(repeat_runs) if isinstance(repeat_runs, list) else 'invalid'}"
        )
        repeat_runs = repeat_runs if isinstance(repeat_runs, list) else []

    cpu_totals: list[float] = []
    gpu_totals: list[float] = []
    for index, run in enumerate(repeat_runs, start=1):
        if not isinstance(run, dict):
            failures.append(f"invalid repeat row: {mode}/{task}/L{scale}/{index}")
            continue
        if run.get("index") != index:
            failures.append(
                f"repeat index mismatch: {mode}/{task}/L{scale}/{index}"
            )
        if run.get("pass") is not True or run.get("business_numeric_pass") is not True:
            failures.append(f"repeat failed: {mode}/{task}/L{scale}/{index}")
        for field, target in (
            ("cpu_total_ms", cpu_totals),
            ("gpu_total_ms", gpu_totals),
        ):
            value = run.get(field)
            if not finite_number(value) or float(value) <= 0.0:
                failures.append(
                    f"invalid {field}: {mode}/{task}/L{scale}/{index}={value!r}"
                )
            else:
                target.append(float(value))

    timings = metrics.get("timings", {})
    total_timing = timings.get("total", {}) if isinstance(timings, dict) else {}
    for field in ("cpu_ms", "gpu_ms"):
        if not finite_number(total_timing.get(field)) or float(total_timing[field]) <= 0.0:
            failures.append(
                f"invalid final total {field}: {mode}/{task}/L{scale}"
            )

    steps, csv_step_count = validate_step_report(
        task,
        scale,
        step_json_path,
        step_csv_path,
        failures,
    )
    step_rows = []
    for step in steps:
        error = step.get("error") or {}
        step_rows.append(
            {
                "mode": mode,
                "task": task,
                "scale_level": scale,
                "step": step.get("step"),
                "operator": step.get("operator"),
                "cpu_ms": step.get("cpu_ms"),
                "gpu_e2e_ms": step.get("gpu_e2e_ms"),
                "gpu_kernel_ms": step.get("gpu_kernel_ms"),
                "mixed_error": error.get("mixed_error"),
                "max_abs": error.get("max_abs"),
                "rmse": error.get("rmse"),
                "pass": step.get("pass"),
            }
        )

    resource = metrics.get("resource_usage", {})
    before = resource.get("before", {}) if isinstance(resource, dict) else {}
    after = resource.get("after", {}) if isinstance(resource, dict) else {}
    case = {
        "mode": mode,
        "task": task,
        "scale_level": scale,
        "scale_value": scenario.get("scale_value"),
        "repeat": expected_repeat,
        "validation_pass": validation.get("pass") is True,
        "cpu_first_ms": cpu_totals[0] if cpu_totals else None,
        "gpu_first_ms": gpu_totals[0] if gpu_totals else None,
        "cpu_median_ms": statistics.median(cpu_totals) if cpu_totals else None,
        "gpu_median_ms": statistics.median(gpu_totals) if gpu_totals else None,
        "gpu_p95_ms": nearest_rank_percentile(gpu_totals, 0.95) if gpu_totals else None,
        "gpu_min_ms": min(gpu_totals) if gpu_totals else None,
        "gpu_max_ms": max(gpu_totals) if gpu_totals else None,
        "process_wall_ms": process_wall_ms,
        "step_count": len(steps),
        "step_csv_count": csv_step_count,
        "gpu_device": before.get("gpu_device", after.get("gpu_device")),
        "gpu_device_name": before.get("gpu_device_name", after.get("gpu_device_name")),
        "gpu_total_mib": before.get("gpu_total_mib", after.get("gpu_total_mib")),
        "gpu_free_delta_mib": resource.get("gpu_free_delta_mib"),
        "rss_current_delta_mib": resource.get("rss_current_delta_mib"),
        "metrics_path": relative(metrics_path, evidence_root),
        "step_json_path": relative(step_json_path, evidence_root),
        "step_csv_path": relative(step_csv_path, evidence_root),
        "process_wall_path": relative(process_wall_path, evidence_root),
    }
    return case, step_rows


def write_tsv(path: Path, rows: list[dict[str, Any]], columns: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t")
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    key: (
                        str(value).lower()
                        if isinstance(value, bool)
                        else "" if value is None else value
                    )
                    for key, value in row.items()
                }
            )


def write_markdown(path: Path, payload: dict[str, Any]) -> None:
    def format_ms(value: Any) -> str:
        return f"{float(value):.6f}" if finite_number(value) else "-"

    summary = payload["summary"]
    lines = [
        "# V6.8 Task1/Task2 终测预验收",
        "",
        f"- 状态：`{summary['status']}`",
        f"- 任务规模用例：`{summary['case_count']}/{summary['expected_case_count']}`",
        f"- 分步记录：`{summary['step_row_count']}/{summary['expected_step_row_count']}`",
        f"- 失败项：`{summary['failure_count']}`",
        "- `first_process` 是新进程内首次计量结果；任务程序仍会执行其内部必要预热，不等同于未初始化裸冷启动。",
        "- warm P95 使用 nearest-rank；repeat=5 时等于五次测量中的最大值。",
        "",
        "## 总耗时",
        "",
        "| 模式 | 任务 | 规模 | repeat | 首次 GPU ms | GPU median ms | GPU P95 ms | 进程 wall ms | 验证 |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for row in payload["cases"]:
        lines.append(
            f"| {row['mode']} | {row['task']} | L{row['scale_level']} | "
            f"{row['repeat']} | {format_ms(row['gpu_first_ms'])} | "
            f"{format_ms(row['gpu_median_ms'])} | {format_ms(row['gpu_p95_ms'])} | "
            f"{format_ms(row['process_wall_ms'])} | "
            f"{str(row['validation_pass']).lower()} |"
        )
    if payload["failures"]:
        lines.extend(["", "## 失败项", ""])
        lines.extend(f"- {item}" for item in payload["failures"])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    roots = {
        "first_process": Path(args.first_root).resolve(),
        "warm": Path(args.warm_root).resolve(),
    }
    evidence_root = Path(args.output_dir).resolve().parent
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    failures: list[str] = []
    cases: list[dict[str, Any]] = []
    step_rows: list[dict[str, Any]] = []
    for mode, expected_repeat in MODES.items():
        root = roots[mode]
        for task in EXPECTED_STEPS:
            for scale in range(1, 7):
                case, steps = summarize_case(
                    mode,
                    expected_repeat,
                    task,
                    scale,
                    root / task / f"L{scale}",
                    evidence_root,
                    failures,
                )
                if case is not None:
                    cases.append(case)
                step_rows.extend(steps)

    expected_case_count = len(MODES) * len(EXPECTED_STEPS) * 6
    expected_step_row_count = (
        len(MODES) * 6 * sum(len(steps) for steps in EXPECTED_STEPS.values())
    )
    if len(cases) != expected_case_count:
        failures.append(
            f"case count mismatch: expected={expected_case_count} actual={len(cases)}"
        )
    if len(step_rows) != expected_step_row_count:
        failures.append(
            "step row count mismatch: "
            f"expected={expected_step_row_count} actual={len(step_rows)}"
        )

    summary = {
        "status": "passed" if not failures else "failed",
        "task_count": len(EXPECTED_STEPS),
        "scale_count": 6,
        "mode_count": len(MODES),
        "case_count": len(cases),
        "expected_case_count": expected_case_count,
        "step_row_count": len(step_rows),
        "expected_step_row_count": expected_step_row_count,
        "failure_count": len(failures),
    }
    payload = {
        "schema_version": 1,
        "summary": summary,
        "cases": cases,
        "steps": step_rows,
        "failures": failures,
    }
    (output_dir / "task_matrix.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_tsv(
        output_dir / "task_totals.tsv",
        cases,
        [
            "mode",
            "task",
            "scale_level",
            "scale_value",
            "repeat",
            "validation_pass",
            "cpu_first_ms",
            "gpu_first_ms",
            "cpu_median_ms",
            "gpu_median_ms",
            "gpu_p95_ms",
            "gpu_min_ms",
            "gpu_max_ms",
            "process_wall_ms",
            "step_count",
            "step_csv_count",
            "gpu_device",
            "gpu_device_name",
            "gpu_total_mib",
            "gpu_free_delta_mib",
            "rss_current_delta_mib",
            "metrics_path",
            "step_json_path",
            "step_csv_path",
            "process_wall_path",
        ],
    )
    write_tsv(
        output_dir / "task_steps.tsv",
        step_rows,
        [
            "mode",
            "task",
            "scale_level",
            "step",
            "operator",
            "cpu_ms",
            "gpu_e2e_ms",
            "gpu_kernel_ms",
            "mixed_error",
            "max_abs",
            "rmse",
            "pass",
        ],
    )
    write_markdown(output_dir / "task_matrix.md", payload)
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
