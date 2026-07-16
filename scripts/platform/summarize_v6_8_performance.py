#!/usr/bin/env python3

"""Validate and summarize the V6.8 all81 L1-L6 performance terminal."""

from __future__ import annotations

import argparse
import bisect
import csv
import json
import math
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any


EXPECTED_LEVELS = {1, 2, 3, 4, 5, 6}
TASK_BASELINES = {
    ("task1_radar", "total"): 7.19016,
    ("task1_radar", "pulse_compression"): 3.27254,
    ("task1_radar", "pulse_doppler"): 1.56758,
    ("task1_radar", "ca_cfar"): 0.997072,
    ("task2_features", "total"): 76.0695,
    ("task2_features", "cwt"): 34.0065,
    ("task2_features", "spectrogram"): 25.4401,
    ("task2_features", "correlate"): 9.75641,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark-csv", required=True)
    parser.add_argument("--progress-jsonl", required=True)
    parser.add_argument("--telemetry-csv", required=True)
    parser.add_argument("--telemetry-json", required=True)
    parser.add_argument("--task-totals", required=True)
    parser.add_argument("--task-steps", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--gpu-index", default="0")
    parser.add_argument("--expected-operators", type=int, default=81)
    parser.add_argument("--expected-scales", type=int, default=6)
    parser.add_argument("--warmup", type=int, default=5)
    parser.add_argument("--repeat", type=int, default=30)
    return parser.parse_args()


def read_csv(path: Path, delimiter: str = ",") -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def parse_float(value: Any) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        return math.nan
    return result if math.isfinite(result) else math.nan


def parse_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def parse_timestamp(value: str) -> float:
    return datetime.fromisoformat(value).timestamp()


def nearest_rank(values: list[float], percentile: float) -> float | None:
    finite = sorted(value for value in values if math.isfinite(value))
    if not finite:
        return None
    rank = max(1, math.ceil(percentile * len(finite)))
    return finite[rank - 1]


def median(values: list[float]) -> float | None:
    finite = sorted(value for value in values if math.isfinite(value))
    if not finite:
        return None
    middle = len(finite) // 2
    if len(finite) % 2:
        return finite[middle]
    return (finite[middle - 1] + finite[middle]) / 2.0


def benchmark_key(row: dict[str, Any]) -> tuple[str, str, int]:
    level = parse_int(row.get("scale_level"))
    return str(row.get("module", "")), str(row.get("operator", "")), level or -1


def load_progress(path: Path) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        payload = json.loads(line)
        if not isinstance(payload, dict):
            raise ValueError(f"invalid progress event at line {line_number}")
        events.append(payload)
    return events


def write_tsv(path: Path, rows: list[dict[str, Any]], columns: list[str]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, delimiter="\t")
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    column: (
                        str(row.get(column)).lower()
                        if isinstance(row.get(column), bool)
                        else "" if row.get(column) is None else row.get(column)
                    )
                    for column in columns
                }
            )


def task_comparison(
    totals_path: Path,
    steps_path: Path,
    failures: list[str],
) -> list[dict[str, Any]]:
    totals = read_csv(totals_path, delimiter="\t")
    steps = read_csv(steps_path, delimiter="\t")
    warm_l6_totals = {
        row["task"]: row
        for row in totals
        if row.get("mode") == "warm" and row.get("scale_level") == "6"
    }
    warm_l6_steps = {
        (row["task"], row["step"]): row
        for row in steps
        if row.get("mode") == "warm" and row.get("scale_level") == "6"
    }

    output: list[dict[str, Any]] = []
    for (task, metric), baseline_ms in TASK_BASELINES.items():
        if metric == "total":
            source = warm_l6_totals.get(task)
            current_ms = parse_float(source.get("gpu_median_ms")) if source else math.nan
            measurement = "warm_repeat5_median"
        else:
            source = warm_l6_steps.get((task, metric))
            current_ms = parse_float(source.get("gpu_e2e_ms")) if source else math.nan
            measurement = "warm_report_final_iteration"
        if not math.isfinite(current_ms) or current_ms < 0.0:
            failures.append(f"missing V6.8 task metric: {task}/{metric}")
            continue
        reduction = (
            (baseline_ms - current_ms) / baseline_ms * 100.0
            if baseline_ms > 0.0
            else math.nan
        )
        output.append(
            {
                "task": task,
                "metric": metric,
                "baseline_ms": baseline_ms,
                "current_ms": current_ms,
                "reduction_percent": reduction,
                "measurement": measurement,
            }
        )
    return output


def summarize() -> int:
    args = parse_args()
    benchmark_path = Path(args.benchmark_csv)
    progress_path = Path(args.progress_jsonl)
    telemetry_csv_path = Path(args.telemetry_csv)
    telemetry_json_path = Path(args.telemetry_json)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    failures: list[str] = []
    rows = read_csv(benchmark_path)
    expected_rows = args.expected_operators * args.expected_scales
    if len(rows) != expected_rows:
        failures.append(f"benchmark row count: expected={expected_rows} actual={len(rows)}")

    keys = [benchmark_key(row) for row in rows]
    if len(set(keys)) != len(keys):
        failures.append("benchmark rows contain duplicate operator/scale keys")

    operators: dict[tuple[str, str], set[int]] = defaultdict(set)
    run_ids = set()
    gpu_names = set()
    for row in rows:
        module, operator, level = benchmark_key(row)
        if not module or not operator or level not in EXPECTED_LEVELS:
            failures.append(f"invalid benchmark key: {module}/{operator}/L{level}")
            continue
        operators[(module, operator)].add(level)
        run_ids.add(row.get("run_id", ""))
        gpu_names.add(row.get("gpu_name", ""))
        if row.get("status") != "passed" or row.get("pass") != "true":
            failures.append(f"benchmark failed: {module}/{operator}/L{level}")
        if parse_int(row.get("return_code")) != 0:
            failures.append(f"nonzero return code: {module}/{operator}/L{level}")
        if parse_int(row.get("warmup")) != args.warmup:
            failures.append(f"warmup mismatch: {module}/{operator}/L{level}")
        if parse_int(row.get("repeat")) != args.repeat:
            failures.append(f"repeat mismatch: {module}/{operator}/L{level}")
        cpu_ms = parse_float(row.get("cpu_median_ms"))
        e2e_ms = parse_float(row.get("gpu_e2e_median_ms"))
        kernel_ms = parse_float(row.get("gpu_kernel_median_ms"))
        if not math.isfinite(cpu_ms) or cpu_ms <= 0.0:
            failures.append(f"invalid CPU timing: {module}/{operator}/L{level}")
        if not math.isfinite(e2e_ms) or e2e_ms <= 0.0:
            failures.append(f"invalid GPU E2E timing: {module}/{operator}/L{level}")
        if not math.isfinite(kernel_ms) or kernel_ms < 0.0:
            failures.append(f"invalid GPU kernel timing: {module}/{operator}/L{level}")

    if len(operators) != args.expected_operators:
        failures.append(
            f"operator count: expected={args.expected_operators} actual={len(operators)}"
        )
    for operator_key, levels in operators.items():
        if levels != EXPECTED_LEVELS:
            failures.append(
                f"scale coverage mismatch: {operator_key[0]}/{operator_key[1]}={sorted(levels)}"
            )
    if len(run_ids) != 1:
        failures.append(f"expected one benchmark run_id, got {sorted(run_ids)}")

    progress = load_progress(progress_path)
    start_events: dict[tuple[str, str, int], dict[str, Any]] = {}
    end_events: dict[tuple[str, str, int], dict[str, Any]] = {}
    for event in progress:
        if event.get("event") not in {"case_start", "case_end"}:
            continue
        key = benchmark_key(event)
        target = start_events if event["event"] == "case_start" else end_events
        if key in target:
            failures.append(f"duplicate progress event: {event['event']} {key}")
        target[key] = event
    if len(start_events) != expected_rows:
        failures.append(
            f"case_start count: expected={expected_rows} actual={len(start_events)}"
        )
    if len(end_events) != expected_rows:
        failures.append(
            f"case_end count: expected={expected_rows} actual={len(end_events)}"
        )
    for key, event in end_events.items():
        if (
            event.get("status") != "passed"
            or event.get("passed") is not True
            or parse_int(event.get("return_code")) != 0
        ):
            failures.append(f"failed case_end event: {key}")
    run_end_events = [event for event in progress if event.get("event") == "run_end"]
    if len(run_end_events) != 1:
        failures.append(f"run_end count: expected=1 actual={len(run_end_events)}")
    elif (
        run_end_events[0].get("status") != "passed"
        or parse_int(run_end_events[0].get("row_count")) != expected_rows
        or parse_int(run_end_events[0].get("failed_row_count")) != 0
    ):
        failures.append("run_end event did not report a complete passing run")
    restored_events = [
        event for event in progress if event.get("event") == "manifests_restored"
    ]
    if len(restored_events) != 1:
        failures.append(
            f"manifests_restored count: expected=1 actual={len(restored_events)}"
        )

    telemetry_summary = read_json(telemetry_json_path)
    if telemetry_summary.get("available") is not True:
        failures.append("dlsmi telemetry is unavailable")
    telemetry_rows = [
        row
        for row in read_csv(telemetry_csv_path)
        if row.get("gpu_index") == args.gpu_index
    ]
    samples: list[tuple[float, dict[str, str]]] = []
    for row in telemetry_rows:
        try:
            samples.append((parse_timestamp(row["timestamp"]), row))
        except (KeyError, ValueError):
            continue
    samples.sort(key=lambda item: item[0])
    sample_times = [item[0] for item in samples]
    if not samples:
        failures.append(f"no dlsmi samples for gpu_index={args.gpu_index}")

    telemetry_by_case: list[dict[str, Any]] = []
    covered_windows = 0
    for row in rows:
        key = benchmark_key(row)
        start_event = start_events.get(key)
        end_event = end_events.get(key)
        start_time = parse_float(start_event.get("timestamp_unix")) if start_event else math.nan
        end_time = parse_float(end_event.get("timestamp_unix")) if end_event else math.nan
        if (
            start_event is None
            or end_event is None
            or not math.isfinite(start_time)
            or not math.isfinite(end_time)
            or end_time < start_time
        ):
            window_samples: list[dict[str, str]] = []
        else:
            left = bisect.bisect_left(sample_times, start_time)
            right = bisect.bisect_right(sample_times, end_time)
            window_samples = [sample for _, sample in samples[left:right]]
        if window_samples:
            covered_windows += 1
        used = [parse_float(sample.get("used_mib")) for sample in window_samples]
        util = [parse_float(sample.get("util_percent")) for sample in window_samples]
        active_util = [value for value in util if math.isfinite(value) and value > 0.0]
        e2e_ms = parse_float(row.get("gpu_e2e_median_ms"))
        kernel_ms = parse_float(row.get("gpu_kernel_median_ms"))
        telemetry_by_case.append(
            {
                "module": key[0],
                "operator": key[1],
                "scale_level": key[2],
                "scale_value": row.get("scale_value"),
                "window_duration_s": (
                    end_time - start_time
                    if math.isfinite(start_time) and math.isfinite(end_time)
                    else None
                ),
                "sample_count": len(window_samples),
                "used_mib_max": max(
                    (value for value in used if math.isfinite(value)),
                    default=None,
                ),
                "util_percent_max": max(
                    (value for value in util if math.isfinite(value)),
                    default=None,
                ),
                "util_percent_p95": nearest_rank(util, 0.95),
                "active_util_median": median(active_util),
                "active_sample_fraction": (
                    len(active_util) / len(window_samples) if window_samples else None
                ),
                "gpu_e2e_median_ms": e2e_ms,
                "gpu_kernel_median_ms": kernel_ms,
                "fixed_overhead_ms": (
                    e2e_ms - kernel_ms
                    if math.isfinite(e2e_ms) and math.isfinite(kernel_ms)
                    else None
                ),
            }
        )

    l6_hotspots = sorted(
        (
            {
                "module": row.get("module"),
                "operator": row.get("operator"),
                "scale_value": parse_int(row.get("scale_value")),
                "gpu_e2e_median_ms": parse_float(row.get("gpu_e2e_median_ms")),
                "gpu_kernel_median_ms": parse_float(row.get("gpu_kernel_median_ms")),
                "fixed_overhead_ms": (
                    parse_float(row.get("gpu_e2e_median_ms"))
                    - parse_float(row.get("gpu_kernel_median_ms"))
                ),
                "cpu_median_ms": parse_float(row.get("cpu_median_ms")),
                "gpu_e2e_speedup": parse_float(row.get("gpu_e2e_speedup")),
                "gpu_kernel_speedup": parse_float(row.get("gpu_kernel_speedup")),
                "mixed_error": parse_float(row.get("mixed_error")),
            }
            for row in rows
            if row.get("scale_level") == "6"
        ),
        key=lambda row: row["gpu_e2e_median_ms"],
        reverse=True,
    )

    task_rows = task_comparison(
        Path(args.task_totals),
        Path(args.task_steps),
        failures,
    )
    status = "passed" if not failures else "failed"
    payload = {
        "status": status,
        "summary": {
            "expected_rows": expected_rows,
            "benchmark_rows": len(rows),
            "operator_count": len(operators),
            "scale_levels": sorted(EXPECTED_LEVELS),
            "passed_rows": sum(row.get("status") == "passed" for row in rows),
            "failed_rows": sum(row.get("status") != "passed" for row in rows),
            "run_ids": sorted(run_ids),
            "gpu_names": sorted(name for name in gpu_names if name),
            "warmup": args.warmup,
            "repeat": args.repeat,
            "progress_start_count": len(start_events),
            "progress_end_count": len(end_events),
            "telemetry_gpu_index": args.gpu_index,
            "telemetry_sample_count": len(samples),
            "telemetry_window_coverage_count": covered_windows,
            "telemetry_window_coverage_fraction": (
                covered_windows / len(rows) if rows else 0.0
            ),
            "failure_count": len(failures),
        },
        "telemetry_summary": telemetry_summary,
        "task_comparison": task_rows,
        "l6_hotspots": l6_hotspots,
        "failures": failures,
        "artifacts": {
            "benchmark_csv": str(benchmark_path),
            "progress_jsonl": str(progress_path),
            "telemetry_csv": str(telemetry_csv_path),
            "telemetry_json": str(telemetry_json_path),
        },
    }
    (output_dir / "summary.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    write_tsv(
        output_dir / "operator_telemetry.tsv",
        telemetry_by_case,
        [
            "module",
            "operator",
            "scale_level",
            "scale_value",
            "window_duration_s",
            "sample_count",
            "used_mib_max",
            "util_percent_max",
            "util_percent_p95",
            "active_util_median",
            "active_sample_fraction",
            "gpu_e2e_median_ms",
            "gpu_kernel_median_ms",
            "fixed_overhead_ms",
        ],
    )
    write_tsv(
        output_dir / "l6_hotspots.tsv",
        l6_hotspots,
        [
            "module",
            "operator",
            "scale_value",
            "gpu_e2e_median_ms",
            "gpu_kernel_median_ms",
            "fixed_overhead_ms",
            "cpu_median_ms",
            "gpu_e2e_speedup",
            "gpu_kernel_speedup",
            "mixed_error",
        ],
    )
    write_tsv(
        output_dir / "task_comparison.tsv",
        task_rows,
        [
            "task",
            "metric",
            "baseline_ms",
            "current_ms",
            "reduction_percent",
            "measurement",
        ],
    )

    lines = [
        "# V6.8 性能终测汇总",
        "",
        f"- 状态：`{status}`",
        f"- all81 L1-L6：`{len(rows)}/{expected_rows}` 行，算子 `{len(operators)}/{args.expected_operators}`。",
        f"- 通过行：`{sum(row.get('status') == 'passed' for row in rows)}`；失败行：`{sum(row.get('status') != 'passed' for row in rows)}`。",
        f"- 计时：warmup=`{args.warmup}`，repeat=`{args.repeat}`。",
        f"- dlsmi：GPU `{args.gpu_index}` 样本 `{len(samples)}`，覆盖算子时间窗 `{covered_windows}/{len(rows)}`。",
        "- dlsmi 是低频外部采样，适合判断显存峰值和长窗口活跃度；不能替代 kernel profiler。",
        "",
        "## 任务 L6 对照",
        "",
        "| 任务 | 指标 | V6.1 ms | V6.8 ms | 降幅 | 口径 |",
        "| --- | --- | ---: | ---: | ---: | --- |",
    ]
    for row in task_rows:
        lines.append(
            f"| {row['task']} | {row['metric']} | {row['baseline_ms']:.6f} | "
            f"{row['current_ms']:.6f} | {row['reduction_percent']:.2f}% | "
            f"{row['measurement']} |"
        )
    lines.extend(
        [
            "",
            "## L6 绝对耗时热点",
            "",
            "| 算子 | E2E ms | kernel ms | 固定开销 ms | CPU ms |",
            "| --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for row in l6_hotspots[:20]:
        lines.append(
            f"| {row['module']}/{row['operator']} | "
            f"{row['gpu_e2e_median_ms']:.6f} | "
            f"{row['gpu_kernel_median_ms']:.6f} | "
            f"{row['fixed_overhead_ms']:.6f} | "
            f"{row['cpu_median_ms']:.6f} |"
        )
    if failures:
        lines.extend(["", "## 失败项", ""])
        lines.extend(f"- {failure}" for failure in failures)
    (output_dir / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(
        json.dumps(
            {
                "status": status,
                "rows": len(rows),
                "operators": len(operators),
                "failed_rows": sum(row.get("status") != "passed" for row in rows),
                "telemetry_windows": covered_windows,
                "failure_count": len(failures),
            },
            sort_keys=True,
        )
    )
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(summarize())
