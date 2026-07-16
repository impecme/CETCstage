#!/usr/bin/env python3

"""Validate and summarize the V7.4 five-minute live demo."""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate Task1, Task2 and top-30 operator demo evidence."
    )
    parser.add_argument("--task1-metrics", required=True)
    parser.add_argument("--task2-metrics", required=True)
    parser.add_argument("--top30-csv", required=True)
    parser.add_argument("--cache-decision", required=True)
    parser.add_argument("--telemetry-json", required=True)
    parser.add_argument("--wall-seconds", required=True, type=float)
    parser.add_argument("--wall-limit-seconds", type=float, default=240.0)
    parser.add_argument("--task1-max-ms", type=float, default=4.5)
    parser.add_argument("--task2-max-ms", type=float, default=23.0)
    parser.add_argument("--expected-operators", type=int, default=30)
    parser.add_argument("--minimum-speedup", type=float, default=1.0)
    parser.add_argument("--minimum-median-speedup", type=float, default=20.0)
    parser.add_argument("--minimum-free-memory-mib", type=float, default=512.0)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-markdown", required=True)
    return parser.parse_args()


def load_json(path_value: str) -> dict[str, Any]:
    path = Path(path_value)
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def finite_float(value: Any) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite value: {value!r}")
    return parsed


def task_summary(payload: dict[str, Any]) -> dict[str, Any]:
    repeats = [
        finite_float(item["gpu_total_ms"])
        for item in payload.get("repeat_runs", [])
        if isinstance(item, dict) and "gpu_total_ms" in item
    ]
    if not repeats:
        raise ValueError("task metrics contain no gpu_total_ms repeats")
    timings = payload.get("timings")
    if not isinstance(timings, dict):
        raise ValueError("task metrics contain no timings object")
    steps = {}
    for name, timing in timings.items():
        if isinstance(timing, dict) and "gpu_ms" in timing:
            steps[name] = finite_float(timing["gpu_ms"])
    return {
        "validation_pass": bool(payload.get("validation", {}).get("pass")),
        "repeat_count": len(repeats),
        "gpu_total_median_ms": statistics.median(repeats),
        "gpu_total_min_ms": min(repeats),
        "gpu_total_max_ms": max(repeats),
        "steps": steps,
    }


def load_operator_rows(path_value: str) -> list[dict[str, Any]]:
    rows = []
    with Path(path_value).open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            rows.append(
                {
                    "operator": f"{row.get('module', '')}/{row.get('operator', '')}",
                    "status": row.get("status", ""),
                    "pass": str(row.get("pass", "")).lower() == "true",
                    "scale_value": int(float(row["scale_value"])),
                    "scale_family": row.get("scale_family", ""),
                    "cpu_median_ms": finite_float(row["cpu_median_ms"]),
                    "gpu_e2e_median_ms": finite_float(row["gpu_e2e_median_ms"]),
                    "gpu_kernel_median_ms": finite_float(row["gpu_kernel_median_ms"]),
                    "gpu_e2e_speedup": finite_float(row["gpu_e2e_speedup"]),
                    "mixed_error": finite_float(row["mixed_error"]),
                    "baseline_reused": "cpu_baseline=reused"
                    in str(row.get("error_note", "")),
                    "device_cache_peak_cached_mib": (
                        finite_float(row["device_cache_peak_cached_mib"])
                        if str(row.get("device_cache_peak_cached_mib", "")).strip()
                        else None
                    ),
                }
            )
    return rows


def geometric_mean(values: list[float]) -> float:
    return math.exp(sum(math.log(value) for value in values) / len(values))


def main() -> int:
    args = parse_args()
    task1 = task_summary(load_json(args.task1_metrics))
    task2 = task_summary(load_json(args.task2_metrics))
    operators = load_operator_rows(args.top30_csv)
    cache = load_json(args.cache_decision)
    telemetry = load_json(args.telemetry_json)

    speedups = [row["gpu_e2e_speedup"] for row in operators]
    passed_rows = [
        row
        for row in operators
        if row["status"] == "passed" and row["pass"]
    ]
    reused_rows = [row for row in operators if row["baseline_reused"]]
    telemetry_available = bool(telemetry.get("available"))
    used_mib_max = (
        finite_float(telemetry["used_mib_max"])
        if telemetry_available and telemetry.get("used_mib_max") is not None
        else None
    )
    total_mib_max = (
        finite_float(telemetry["total_mib_max"])
        if telemetry_available and telemetry.get("total_mib_max") is not None
        else None
    )
    free_headroom_ok = bool(
        telemetry_available
        and used_mib_max is not None
        and total_mib_max is not None
        and total_mib_max - used_mib_max >= args.minimum_free_memory_mib
    )

    checks = {
        "wall_budget": args.wall_seconds <= args.wall_limit_seconds,
        "task1_validation": task1["validation_pass"],
        "task2_validation": task2["validation_pass"],
        "task1_performance": task1["gpu_total_median_ms"] <= args.task1_max_ms,
        "task2_performance": task2["gpu_total_median_ms"] <= args.task2_max_ms,
        "operator_count": len(operators) == args.expected_operators,
        "operator_pass": len(passed_rows) == args.expected_operators,
        "cpu_baseline_reused": len(reused_rows) == args.expected_operators,
        "minimum_speedup": bool(speedups)
        and min(speedups) >= args.minimum_speedup,
        "median_speedup": bool(speedups)
        and statistics.median(speedups) >= args.minimum_median_speedup,
        "cache_decision": cache.get("status") == "passed"
        and cache.get("selected_mode") in {"default", "expanded"},
        "telemetry": telemetry_available
        and int(telemetry.get("sample_count", 0)) > 0,
        "memory_headroom": free_headroom_ok,
    }
    passed = all(checks.values())

    operator_summary = {
        "count": len(operators),
        "passed": len(passed_rows),
        "baseline_reused": len(reused_rows),
        "minimum_speedup": min(speedups) if speedups else None,
        "median_speedup": statistics.median(speedups) if speedups else None,
        "geometric_mean_speedup": (
            geometric_mean(speedups)
            if speedups and all(value > 0.0 for value in speedups)
            else None
        ),
        "maximum_speedup": max(speedups) if speedups else None,
        "gpu_e2e_sum_ms": sum(row["gpu_e2e_median_ms"] for row in operators),
        "rows": sorted(
            operators,
            key=lambda row: row["gpu_e2e_speedup"],
            reverse=True,
        ),
    }
    payload = {
        "status": "passed" if passed else "failed",
        "checks": checks,
        "wall": {
            "seconds": args.wall_seconds,
            "limit_seconds": args.wall_limit_seconds,
            "reserve_seconds": args.wall_limit_seconds - args.wall_seconds,
        },
        "task1": task1,
        "task2": task2,
        "operators": operator_summary,
        "cache": cache,
        "telemetry": telemetry,
    }

    output_json = Path(args.output_json)
    output_markdown = Path(args.output_markdown)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_markdown.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

    with output_markdown.open("w", encoding="utf-8") as handle:
        handle.write("# V7.4 五分钟演示结果\n\n")
        handle.write(f"- 状态：`{payload['status']}`\n")
        handle.write(
            f"- 现场 wall：`{args.wall_seconds:.3f} s / "
            f"{args.wall_limit_seconds:.0f} s`\n"
        )
        handle.write(
            f"- 缓存模式：`{cache.get('selected_mode', 'unknown')}`\n"
        )
        handle.write(
            f"- Task1 L6：`{task1['gpu_total_median_ms']:.6g} ms`\n"
        )
        handle.write(
            f"- Task2 L6：`{task2['gpu_total_median_ms']:.6g} ms`\n"
        )
        handle.write(
            f"- Top30 中位加速：`{operator_summary['median_speedup']:.3f}x`；"
            f"几何平均：`{operator_summary['geometric_mean_speedup']:.3f}x`\n"
        )
        if used_mib_max is not None:
            handle.write(f"- 进程显存峰值：`{used_mib_max:.0f} MiB`\n")
        handle.write("\n## 检查\n\n")
        for name, value in checks.items():
            handle.write(f"- `{name}`: `{'pass' if value else 'fail'}`\n")
        handle.write("\n## Top30\n\n")
        handle.write("| 算子 | 数据量 | E2E ms | 加速比 | mixed error |\n")
        handle.write("| --- | ---: | ---: | ---: | ---: |\n")
        for row in operator_summary["rows"]:
            handle.write(
                f"| `{row['operator']}` | {row['scale_value']} | "
                f"{row['gpu_e2e_median_ms']:.6g} | "
                f"{row['gpu_e2e_speedup']:.3f}x | "
                f"{row['mixed_error']:.3g} |\n"
            )
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
