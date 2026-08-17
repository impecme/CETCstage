#!/usr/bin/env python3
"""Compare one optimized all81 operator report to the frozen GPU baseline.

The CPU reference is always taken from the frozen CSV.  CPU timings emitted by
the optimized run are retained only as diagnostic metadata and never replace
the frozen numerator in the published speedup columns.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import statistics
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from operator_gpu_protocol import (
    BaselineSnapshot,
    ProtocolError,
    _finite_float,
    sha256_file,
    validate_frozen_baseline,
    validate_optimized_rows,
    workload_key,
)


COMPARISON_FIELDS = [
    "operator",
    "module",
    "name",
    "scale_level",
    "scale_profile",
    "scale_fields",
    "input_elements",
    "power_of_two_dimensions",
    "warmup",
    "repeat",
    "gpu_name",
    "saved_cpu_median_ms",
    "baseline_gpu_e2e_median_ms",
    "optimized_gpu_e2e_median_ms",
    "baseline_cpu_to_gpu_e2e_speedup",
    "optimized_cpu_to_gpu_e2e_speedup",
    "gpu_e2e_before_after",
    "baseline_gpu_kernel_median_ms",
    "optimized_gpu_kernel_median_ms",
    "gpu_kernel_before_after",
    "optimized_cpu_gpu_max_abs_error",
    "optimized_cpu_gpu_max_rel_error",
    "optimized_cpu_gpu_mixed_error",
    "optimized_cpu_gpu_rmse",
    "optimized_correctness_status",
    "optimization_status",
    "unavailable_reason",
]


def _number(row: dict[str, Any], field: str) -> float | None:
    return _finite_float(row, field)


def _median(values: list[float]) -> float | None:
    return statistics.median(values) if values else None


def _fmt(value: Any, digits: int = 6) -> str:
    if value is None:
        return "—"
    if isinstance(value, float):
        return f"{value:.{digits}f}"
    return str(value)


def _status(row: dict[str, str]) -> str:
    return str(row.get("correctness_status") or row.get("status") or "UNAVAILABLE").upper()


def _compare_row(baseline: dict[str, str], optimized: dict[str, str]) -> dict[str, Any]:
    baseline_e2e = _number(baseline, "gpu_e2e_median_ms")
    optimized_e2e = _number(optimized, "gpu_e2e_median_ms")
    saved_cpu = _number(baseline, "saved_cpu_median_ms")
    baseline_kernel = _number(baseline, "gpu_kernel_median_ms")
    optimized_kernel = _number(optimized, "gpu_kernel_median_ms")
    correctness = _status(optimized)
    reasons: list[str] = []

    base_speedup = None
    optimized_speedup = None
    e2e_ratio = None
    kernel_ratio = None
    if saved_cpu is None or saved_cpu <= 0:
        reasons.append("saved_cpu_median_ms unavailable")
    if baseline_e2e is None or baseline_e2e <= 0:
        reasons.append("baseline gpu_e2e_median_ms unavailable")
    if optimized_e2e is None or optimized_e2e <= 0:
        reasons.append("optimized gpu_e2e_median_ms unavailable")
    if not reasons:
        base_speedup = saved_cpu / baseline_e2e
        optimized_speedup = saved_cpu / optimized_e2e
        e2e_ratio = baseline_e2e / optimized_e2e
    if baseline_kernel is None or baseline_kernel <= 0:
        reasons.append("baseline gpu_kernel_median_ms unavailable")
    if optimized_kernel is None or optimized_kernel <= 0:
        reasons.append("optimized gpu_kernel_median_ms unavailable")
    if baseline_kernel is not None and baseline_kernel > 0 and optimized_kernel is not None and optimized_kernel > 0:
        kernel_ratio = baseline_kernel / optimized_kernel

    if correctness != "PASS":
        optimization_status = "CORRECTNESS_FAIL" if correctness == "FAIL" else "UNAVAILABLE"
    elif base_speedup is None or optimized_speedup is None:
        optimization_status = "UNAVAILABLE"
    elif optimized_speedup > base_speedup:
        optimization_status = "POSITIVE"
    elif optimized_speedup < base_speedup:
        optimization_status = "REGRESSION"
    else:
        optimization_status = "NO_GAIN"

    module, name = str(baseline["operator"]).split("/", 1)
    return {
        "operator": baseline["operator"],
        "module": module,
        "name": name,
        "scale_level": baseline["scale_level"],
        "scale_profile": baseline["scale_profile"],
        "scale_fields": baseline["scale_fields"],
        "input_elements": baseline["input_elements"],
        "power_of_two_dimensions": baseline["power_of_two_dimensions"],
        "warmup": baseline.get("warmup", ""),
        "repeat": baseline.get("repeat", ""),
        "gpu_name": baseline.get("gpu_name", optimized.get("gpu_name", "")),
        "saved_cpu_median_ms": saved_cpu,
        "baseline_gpu_e2e_median_ms": baseline_e2e,
        "optimized_gpu_e2e_median_ms": optimized_e2e,
        "baseline_cpu_to_gpu_e2e_speedup": base_speedup,
        "optimized_cpu_to_gpu_e2e_speedup": optimized_speedup,
        "gpu_e2e_before_after": e2e_ratio,
        "baseline_gpu_kernel_median_ms": baseline_kernel,
        "optimized_gpu_kernel_median_ms": optimized_kernel,
        "gpu_kernel_before_after": kernel_ratio,
        "optimized_cpu_gpu_max_abs_error": _number(optimized, "cpu_gpu_max_abs_error"),
        "optimized_cpu_gpu_max_rel_error": _number(optimized, "cpu_gpu_max_rel_error"),
        "optimized_cpu_gpu_mixed_error": _number(optimized, "cpu_gpu_mixed_error"),
        "optimized_cpu_gpu_rmse": _number(optimized, "cpu_gpu_rmse"),
        "optimized_correctness_status": correctness,
        "optimization_status": optimization_status,
        "unavailable_reason": "; ".join(dict.fromkeys(reasons)),
    }


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=COMPARISON_FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _operator_summary(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[row["operator"]].append(row)
    result = []
    for operator, items in sorted(grouped.items()):
        statuses = Counter(item["optimization_status"] for item in items)
        e2e = [item["gpu_e2e_before_after"] for item in items if item["gpu_e2e_before_after"] is not None]
        base = [item["baseline_cpu_to_gpu_e2e_speedup"] for item in items if item["baseline_cpu_to_gpu_e2e_speedup"] is not None]
        opt = [item["optimized_cpu_to_gpu_e2e_speedup"] for item in items if item["optimized_cpu_to_gpu_e2e_speedup"] is not None]
        result.append({
            "operator": operator,
            "rows": len(items),
            "positive": statuses.get("POSITIVE", 0),
            "no_gain": statuses.get("NO_GAIN", 0),
            "regression": statuses.get("REGRESSION", 0),
            "unavailable": statuses.get("UNAVAILABLE", 0),
            "correctness_fail": statuses.get("CORRECTNESS_FAIL", 0),
            "baseline_cpu_to_gpu_e2e_median": _median(base),
            "optimized_cpu_to_gpu_e2e_median": _median(opt),
            "gpu_e2e_before_after_median": _median(e2e),
        })
    return result


def _write_markdown(
    path: Path,
    baseline: BaselineSnapshot,
    optimized_csv: Path,
    rows: list[dict[str, Any]],
    operator_rows: list[dict[str, Any]],
    optimized_source: str,
) -> None:
    statuses = Counter(row["optimization_status"] for row in rows)
    baseline_e2e = [row["baseline_gpu_e2e_median_ms"] for row in rows if row["baseline_gpu_e2e_median_ms"] is not None]
    optimized_e2e = [row["optimized_gpu_e2e_median_ms"] for row in rows if row["optimized_gpu_e2e_median_ms"] is not None]
    e2e_ratios = [row["gpu_e2e_before_after"] for row in rows if row["gpu_e2e_before_after"] is not None]
    base_speedups = [row["baseline_cpu_to_gpu_e2e_speedup"] for row in rows if row["baseline_cpu_to_gpu_e2e_speedup"] is not None]
    optimized_speedups = [row["optimized_cpu_to_gpu_e2e_speedup"] for row in rows if row["optimized_cpu_to_gpu_e2e_speedup"] is not None]
    kernel_ratios = [row["gpu_kernel_before_after"] for row in rows if row["gpu_kernel_before_after"] is not None]
    ratio_of_medians = (
        statistics.median(baseline_e2e) / statistics.median(optimized_e2e)
        if baseline_e2e and optimized_e2e else None
    )
    lines = [
        "# Frozen GPU baseline vs optimized operator report",
        "",
        "本报告只运行优化版本；baseline CSV 未重新运行、未修改。CPU reference 取 frozen baseline 的 saved_cpu_median_ms。",
        "",
        f"- baseline: `{baseline.root / 'gpu_baseline.csv'}`",
        f"- baseline commit: `{baseline.metadata.get('baseline_commit')}`",
        f"- optimized report: `{optimized_csv}`",
        f"- optimized source: `{optimized_source}`",
        f"- protocol: `warmup={baseline.metadata.get('warmup')}, repeat={baseline.metadata.get('repeat')}, device={baseline.metadata.get('device_target')}`",
        f"- rows: `{len(rows)}`",
        "",
        "## Summary",
        "",
        "| 指标 | 结果 |",
        "| --- | ---: |",
        f"| POSITIVE workload rows | {statuses.get('POSITIVE', 0)} |",
        f"| NO_GAIN workload rows | {statuses.get('NO_GAIN', 0)} |",
        f"| REGRESSION workload rows | {statuses.get('REGRESSION', 0)} |",
        f"| UNAVAILABLE workload rows | {statuses.get('UNAVAILABLE', 0)} |",
        f"| CORRECTNESS_FAIL rows | {statuses.get('CORRECTNESS_FAIL', 0)} |",
        f"| baseline CPU→GPU E2E speedup median | {_fmt(_median(base_speedups), 3)}x |",
        f"| optimized CPU→GPU E2E speedup median | {_fmt(_median(optimized_speedups), 3)}x |",
        f"| GPU E2E before/after ratio of medians | {_fmt(ratio_of_medians, 3)}x |",
        f"| GPU E2E before/after row median | {_fmt(_median(e2e_ratios), 3)}x |",
        f"| valid GPU kernel before/after rows | {len(kernel_ratios)} |",
        f"| GPU kernel before/after row median | {_fmt(_median(kernel_ratios), 3)}x |",
        "",
        "`optimized_cpu_to_gpu_e2e_speedup > baseline_cpu_to_gpu_e2e_speedup` 才记为 POSITIVE；kernel 缺失时只记 N/A，不用 E2E 替代。",
        "",
        "## Per-operator summary",
        "",
        "| 算子 | rows | positive | no gain | regression | unavailable | correctness fail | baseline CPU→GPU | optimized CPU→GPU | GPU E2E before/after |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for item in operator_rows:
        lines.append(
            f"| {item['operator']} | {item['rows']} | {item['positive']} | {item['no_gain']} | "
            f"{item['regression']} | {item['unavailable']} | {item['correctness_fail']} | "
            f"{_fmt(item['baseline_cpu_to_gpu_e2e_median'], 3)}x | "
            f"{_fmt(item['optimized_cpu_to_gpu_e2e_median'], 3)}x | "
            f"{_fmt(item['gpu_e2e_before_after_median'], 3)}x |"
        )
    lines.extend([
        "",
        "## Acceptance boundary",
        "",
        "- 不把历史 baseline 重新测量；只对优化版本执行 `all81 × L1-L6`。",
        "- 优化版本必须保持完整 workload key、输入布局、dtype、warmup/repeat 和正确性契约。",
        "- 误差字段只来自优化版本 GPU 与保存 CPU reference 的比较。",
        "- POSITIVE/NO_GAIN/REGRESSION 是逐 workload 结果；不能用总体中位数掩盖单算子回退。",
    ])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def compare(
    baseline_root: Path,
    optimized_csv: Path,
    output_root: Path,
    optimized_source: str,
    *,
    require_positive: bool = False,
    scales: tuple[str, ...] | None = None,
) -> int:
    baseline = validate_frozen_baseline(baseline_root)
    selected_scales = tuple(scales or ())
    if selected_scales and "all" not in selected_scales:
        valid_scales = {f"L{index}" for index in range(1, 7)}
        invalid = set(selected_scales) - valid_scales
        if invalid:
            raise ProtocolError(f"invalid comparison scale(s): {sorted(invalid)}")
        selected_keys = frozenset(
            workload_key(row) for row in baseline.rows if row["scale_level"] in selected_scales
        )
        if not selected_keys:
            raise ProtocolError(f"no frozen baseline rows for scale(s): {selected_scales}")
    else:
        selected_keys = baseline.keys
    optimized_rows = validate_optimized_rows(optimized_csv, baseline, selected_keys)
    baseline_by_key = {workload_key(row): row for row in baseline.rows}
    rows = [
        _compare_row(baseline_by_key[workload_key(optimized)], optimized)
        for optimized in optimized_rows
    ]
    output_root.mkdir(parents=True, exist_ok=True)
    comparison_csv = output_root / "operator_gpu_comparison.csv"
    comparison_json = output_root / "operator_gpu_comparison.json"
    comparison_md = output_root / "operator_gpu_comparison.md"
    metadata_path = output_root / "comparison_metadata.json"
    operator_rows = _operator_summary(rows)
    _write_csv(comparison_csv, rows)
    _write_json(comparison_json, {
        "schema_version": 1,
        "baseline_root": str(baseline.root),
        "baseline_csv_sha256": baseline.csv_sha256,
        "baseline_frozen_sha256": baseline.frozen_sha256,
        "baseline_commit": baseline.metadata.get("baseline_commit"),
        "optimized_source": optimized_source,
        "optimized_csv": str(optimized_csv.resolve()),
        "optimized_csv_sha256": sha256_file(optimized_csv),
        "operator_count": len({row["operator"] for row in rows}),
        "row_count": len(rows),
        "rows": rows,
        "operator_summary": operator_rows,
    })
    _write_json(metadata_path, {
        "schema_version": 1,
        "status": "COMPARED",
        "baseline_root": str(baseline.root),
        "baseline_csv_sha256": baseline.csv_sha256,
        "baseline_frozen_sha256": baseline.frozen_sha256,
        "baseline_commit": baseline.metadata.get("baseline_commit"),
        "optimized_source": optimized_source,
        "optimized_csv": str(optimized_csv.resolve()),
        "optimized_csv_sha256": sha256_file(optimized_csv),
        "operator_count": len({row["operator"] for row in rows}),
        "row_count": len(rows),
        "warmup": baseline.metadata.get("warmup"),
        "repeat": baseline.metadata.get("repeat"),
        "device_target": baseline.metadata.get("device_target"),
        "generated_at": datetime.now(timezone.utc).isoformat(),
    })
    _write_markdown(comparison_md, baseline, optimized_csv, rows, operator_rows, optimized_source)

    statuses = Counter(row["optimization_status"] for row in rows)
    print(
        f"[operator-gpu-compare] rows={len(rows)} operators={len({row['operator'] for row in rows})} "
        f"positive={statuses.get('POSITIVE', 0)} no_gain={statuses.get('NO_GAIN', 0)} "
        f"regression={statuses.get('REGRESSION', 0)} unavailable={statuses.get('UNAVAILABLE', 0)} "
        f"correctness_fail={statuses.get('CORRECTNESS_FAIL', 0)}"
    )
    print(f"[operator-gpu-compare] report={comparison_md}")
    if statuses.get("CORRECTNESS_FAIL", 0) or statuses.get("UNAVAILABLE", 0):
        return 1
    if require_positive and (statuses.get("REGRESSION", 0) or statuses.get("NO_GAIN", 0)):
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline-root", required=True, type=Path)
    parser.add_argument("--optimized-csv", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--optimized-source", default="working-tree")
    parser.add_argument("--require-positive", action="store_true")
    parser.add_argument(
        "--scale",
        dest="scales",
        action="append",
        choices=["all", "L1", "L2", "L3", "L4", "L5", "L6"],
        help="compare only selected scale(s); default is all six scales",
    )
    args = parser.parse_args()
    return compare(
        args.baseline_root,
        args.optimized_csv,
        args.output_root,
        args.optimized_source,
        require_positive=args.require_positive,
        scales=tuple(args.scales or ()),
    )


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ProtocolError as exc:
        print(f"[operator-gpu-compare] error: {exc}", file=sys.stderr)
        raise SystemExit(2)
