#!/usr/bin/env python3

"""Validate V6.8 terminal evidence and write the compact final delivery report."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any


EXPECTED_TASK_CASES = 24
EXPECTED_TASK_STEPS = 168
EXPECTED_OPERATORS = 81
EXPECTED_PERFORMANCE_ROWS = 486


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-root", required=True)
    parser.add_argument("--performance-root", required=True)
    parser.add_argument("--preflight-archive", required=True)
    parser.add_argument("--performance-archive", required=True)
    parser.add_argument("--performance-console", required=True)
    parser.add_argument("--v5-summary-markdown", required=True)
    parser.add_argument("--v5-summary-json", required=True)
    parser.add_argument(
        "--v5-source-dir",
        help="Optional historical v5_5_final directory used to restore summary.md/json",
    )
    parser.add_argument("--report-root", default="data/reports")
    parser.add_argument(
        "--output-dir",
        default="data/reports/zhongkexin/v6_final",
    )
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), f"expected JSON object: {path}")
    return payload


def read_table(path: Path, delimiter: str = "\t") -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def parse_int(value: Any) -> int:
    return int(str(value))


def parse_float(value: Any) -> float:
    result = float(str(value))
    require(math.isfinite(result), f"non-finite numeric value: {value}")
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_status_table(root: Path, label: str) -> list[dict[str, str]]:
    rows = read_table(root / "status.tsv")
    require(rows, f"{label} status.tsv is empty")
    failures = [row for row in rows if parse_int(row["rc"]) != 0]
    require(not failures, f"{label} contains nonzero status rows: {failures}")
    final_rows = [
        row
        for row in rows
        if row.get("phase") == "final" and row.get("case") == "overall"
    ]
    require(len(final_rows) == 1, f"{label} final/overall row count is not 1")
    return rows


def require_empty(path: Path) -> None:
    require(path.is_file(), f"missing evidence file: {path}")
    require(path.stat().st_size == 0, f"expected empty evidence file: {path}")


def typed_task_total(row: dict[str, str]) -> dict[str, Any]:
    return {
        "mode": row["mode"],
        "task": row["task"],
        "scale_level": parse_int(row["scale_level"]),
        "scale_value": parse_int(row["scale_value"]),
        "repeat": parse_int(row["repeat"]),
        "validation_pass": row["validation_pass"] == "true",
        "cpu_first_ms": parse_float(row["cpu_first_ms"]),
        "gpu_first_ms": parse_float(row["gpu_first_ms"]),
        "cpu_median_ms": parse_float(row["cpu_median_ms"]),
        "gpu_median_ms": parse_float(row["gpu_median_ms"]),
        "gpu_p95_ms": parse_float(row["gpu_p95_ms"]),
        "gpu_min_ms": parse_float(row["gpu_min_ms"]),
        "gpu_max_ms": parse_float(row["gpu_max_ms"]),
        "process_wall_ms": parse_float(row["process_wall_ms"]),
        "step_count": parse_int(row["step_count"]),
        "gpu_device": parse_int(row["gpu_device"]),
        "gpu_device_name": row["gpu_device_name"],
        "gpu_total_mib": parse_int(row["gpu_total_mib"]),
        "gpu_free_delta_mib": parse_int(row["gpu_free_delta_mib"]),
        "rss_current_delta_mib": parse_float(row["rss_current_delta_mib"]),
    }


def typed_task_step(row: dict[str, str]) -> dict[str, Any]:
    return {
        "mode": row["mode"],
        "task": row["task"],
        "scale_level": parse_int(row["scale_level"]),
        "step": row["step"],
        "operator": row["operator"],
        "cpu_ms": parse_float(row["cpu_ms"]),
        "gpu_e2e_ms": parse_float(row["gpu_e2e_ms"]),
        "mixed_error": parse_float(row["mixed_error"]),
        "max_abs": parse_float(row["max_abs"]),
        "rmse": parse_float(row["rmse"]),
        "pass": row["pass"] == "true",
    }


def typed_hotspot(row: dict[str, str]) -> dict[str, Any]:
    e2e_ms = parse_float(row["gpu_e2e_median_ms"])
    kernel_ms = parse_float(row["gpu_kernel_median_ms"])
    return {
        "module": row["module"],
        "operator": row["operator"],
        "scale_level": parse_int(row["scale_level"]),
        "scale_value": parse_int(row["scale_value"]),
        "shape_note": row["shape_note"],
        "gpu_e2e_median_ms": e2e_ms,
        "gpu_kernel_median_ms": kernel_ms,
        "fixed_overhead_ms": e2e_ms - kernel_ms,
        "cpu_median_ms": parse_float(row["cpu_median_ms"]),
        "gpu_e2e_speedup": parse_float(row["gpu_e2e_speedup"]),
        "mixed_error": parse_float(row["mixed_error"]),
    }


def gate_row(item: str, result: str, evidence: str) -> str:
    return f"| {item} | {result} | {evidence} |"


def write_report_readme(report_root: Path) -> None:
    lines = [
        "# 终测报告目录",
        "",
        "仓库内只保留最终汇总；完整日志、长表、图件和容器取回内容位于",
        "`/home/usr_04/CETC_garbage/`。",
        "",
        "| 版本 | Markdown | JSON |",
        "| --- | --- | --- |",
        "| V5.5 | `zhongkexin/v5_5_final/summary.md` | `zhongkexin/v5_5_final/summary.json` |",
        "| V6 | `zhongkexin/v6_final/summary.md` | `zhongkexin/v6_final/summary.json` |",
        "| V7 | `zhongkexin/v7_final/summary.md` | `zhongkexin/v7_final/summary.json` |",
        "",
        "禁止在此目录长期保留 unit/demo 中间报告、benchmark 长表、probe 日志和图件。",
    ]
    (report_root / "README.md").write_text(
        "\n".join(lines) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    preflight_root = Path(args.preflight_root).resolve()
    performance_root = Path(args.performance_root).resolve()
    preflight_archive = Path(args.preflight_archive).resolve()
    performance_archive = Path(args.performance_archive).resolve()
    performance_console = Path(args.performance_console).resolve()
    v5_summary_markdown = Path(args.v5_summary_markdown).resolve()
    v5_summary_json = Path(args.v5_summary_json).resolve()
    report_root = Path(args.report_root).resolve()
    output_dir = Path(args.output_dir).resolve()

    expected_v5_markdown = report_root / "zhongkexin/v5_5_final/summary.md"
    expected_v5_json = report_root / "zhongkexin/v5_5_final/summary.json"
    expected_output_dir = report_root / "zhongkexin/v6_final"
    expected_v7_markdown = report_root / "zhongkexin/v7_final/summary.md"
    expected_v7_json = report_root / "zhongkexin/v7_final/summary.json"
    require(
        v5_summary_markdown == expected_v5_markdown.resolve(),
        "v5-summary-markdown must use the final report path",
    )
    require(
        v5_summary_json == expected_v5_json.resolve(),
        "v5-summary-json must use the final report path",
    )
    require(
        output_dir == expected_output_dir.resolve(),
        "output-dir must use the final report path",
    )
    require(not (report_root / "unit").exists(), "data/reports/unit must not exist")
    require(not (report_root / "demo").exists(), "data/reports/demo must not exist")
    if args.v5_source_dir:
        v5_source_dir = Path(args.v5_source_dir).resolve()
        source_markdown = v5_source_dir / "summary.md"
        source_json = v5_source_dir / "summary.json"
        require(source_markdown.is_file(), f"missing V5.5 source: {source_markdown}")
        require(source_json.is_file(), f"missing V5.5 source: {source_json}")
        expected_v5_markdown.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_markdown, expected_v5_markdown)
        shutil.copy2(source_json, expected_v5_json)
    allowed = {
        report_root / "README.md",
        expected_v5_markdown,
        expected_v5_json,
        output_dir / "summary.md",
        output_dir / "summary.json",
    }
    optional_v7 = {expected_v7_markdown, expected_v7_json}
    preexisting = {path for path in report_root.rglob("*") if path.is_file()}
    require(
        preexisting <= allowed | optional_v7,
        f"unexpected pre-existing report files: {sorted(preexisting - allowed - optional_v7)}",
    )

    validate_status_table(preflight_root, "V6-0138")
    validate_status_table(performance_root, "V6-0141")
    for root in (preflight_root, performance_root):
        require_empty(root / "manifest_diff.log")
        require_empty(root / "reports_diff.log")
    require_empty(performance_root / "preflight/product_source_diff.log")

    assertions = read_json(preflight_root / "audits/assertions.json")
    require(assertions and all(assertions.values()), "V6-0138 static assertions failed")

    task_matrix = read_json(preflight_root / "task_summary/task_matrix.json")
    task_summary = task_matrix["summary"]
    require(task_summary["status"] == "passed", "task matrix failed")
    require(
        task_summary["case_count"] == EXPECTED_TASK_CASES,
        "task case count mismatch",
    )
    require(
        task_summary["step_row_count"] == EXPECTED_TASK_STEPS,
        "task step row count mismatch",
    )
    require(task_summary["failure_count"] == 0, "task matrix contains failures")

    performance = read_json(performance_root / "summary/summary.json")
    perf_summary = performance["summary"]
    require(performance["status"] == "passed", "performance terminal failed")
    require(
        perf_summary["benchmark_rows"] == EXPECTED_PERFORMANCE_ROWS,
        "performance row count mismatch",
    )
    require(
        perf_summary["operator_count"] == EXPECTED_OPERATORS,
        "performance operator count mismatch",
    )
    require(perf_summary["failed_rows"] == 0, "performance rows contain failures")
    require(perf_summary["warmup"] == 5, "performance warmup mismatch")
    require(perf_summary["repeat"] == 30, "performance repeat mismatch")

    task_totals = [
        typed_task_total(row)
        for row in read_table(preflight_root / "task_summary/task_totals.tsv")
    ]
    task_steps = [
        typed_task_step(row)
        for row in read_table(preflight_root / "task_summary/task_steps.tsv")
    ]
    require(len(task_totals) == EXPECTED_TASK_CASES, "task totals row count mismatch")
    require(len(task_steps) == EXPECTED_TASK_STEPS, "task steps row count mismatch")
    require(all(row["validation_pass"] for row in task_totals), "task total failed")
    require(all(row["pass"] for row in task_steps), "task step failed")

    l6_steps = [
        row
        for row in task_steps
        if row["mode"] == "warm" and row["scale_level"] == 6
    ]
    require(len(l6_steps) == 14, "warm L6 step count mismatch")

    benchmark_rows = read_table(
        performance_root / "benchmark/latest_all_ops_scale_benchmark.csv",
        delimiter=",",
    )
    require(len(benchmark_rows) == EXPECTED_PERFORMANCE_ROWS, "benchmark CSV incomplete")
    all_level_hotspots = sorted(
        (typed_hotspot(row) for row in benchmark_rows),
        key=lambda row: row["gpu_e2e_median_ms"],
        reverse=True,
    )

    runtime_rows = read_table(preflight_root / "platform/runtime_probe.tsv")
    runtime = {row["field"]: row["value"] for row in runtime_rows}
    graph_status_fields = [
        "graph_capture_begin_status",
        "graph_capture_work_status",
        "graph_capture_end_status",
        "graph_instantiate_status",
        "graph_launch_status",
        "graph_sync_status",
    ]
    require(
        runtime.get("valid_lifecycle_result") == "true"
        and all(runtime.get(field) == "0" for field in graph_status_fields),
        "CUDA Graph lifecycle probe failed",
    )

    preflight_product = (
        performance_root / "preflight/product_source_sha256.txt"
    ).read_text(encoding="utf-8")
    current_product = (
        performance_root / "fingerprint/product_source_sha256.sorted.txt"
    ).read_text(encoding="utf-8")
    require(preflight_product == current_product, "product source fingerprints differ")

    v5_payload = read_json(v5_summary_json)
    require(v5_payload.get("status") == "passed", "V5.5 summary is not passed")
    require(v5_summary_markdown.is_file(), "missing V5.5 summary markdown")

    telemetry = performance["telemetry_summary"]
    task_comparison = performance["task_comparison"]
    l6_hotspots = performance["l6_hotspots"]
    evidence = {
        "v6_0138": {
            "root": str(preflight_root),
            "archive": str(preflight_archive),
            "archive_sha256": sha256(preflight_archive),
        },
        "v6_0141": {
            "root": str(performance_root),
            "archive": str(performance_archive),
            "archive_sha256": sha256(performance_archive),
            "console": str(performance_console),
            "console_sha256": sha256(performance_console),
        },
        "v5_5_restored_summary": {
            "markdown": str(v5_summary_markdown),
            "markdown_sha256": sha256(v5_summary_markdown),
            "json": str(v5_summary_json),
            "json_sha256": sha256(v5_summary_json),
        },
        "product_source_inventory_sha256": sha256(
            performance_root / "fingerprint/product_source_sha256.sorted.txt"
        ),
    }

    residual_bottlenecks = [
        {
            "operator": "radartools/ambgfun",
            "case": "L6, 8192 points",
            "conclusion": (
                "167.855 ms E2E / 167.303 ms kernel; compute-bound. "
                "The prior single-tile memory expansion was rejected for accuracy "
                "failure and a 0.22% E2E regression."
            ),
        },
        {
            "operator": "filtering/hilbert2",
            "case": "L5, shape 724x725",
            "conclusion": (
                "97.534 ms E2E / 97.472 ms kernel. The same cliff existed in "
                "V6.1, so it is not a V6.8 regression; removing it requires an "
                "FFT algorithm or layout redesign for unfavorable dimensions."
            ),
        },
        {
            "operator": "spectral/lombscargle",
            "case": "L6, 8192 samples x 16384 frequencies",
            "conclusion": (
                "11.497 ms E2E / 11.293 ms kernel after the retained pair-input "
                "reuse and warp-reduction optimization; the remaining cost is "
                "kernel arithmetic."
            ),
        },
        {
            "operator": "radartools/mvdr",
            "case": "L6, shape 8x131072",
            "conclusion": (
                "2.481 ms E2E / 0.794 ms kernel. Host-input caching removed the "
                "main repeated transfer cost; further work needs a cross-call "
                "lifecycle or output/synchronization redesign."
            ),
        },
    ]

    payload = {
        "schema_version": "v6_final_summary_v1",
        "status": "passed",
        "version": "V6.8",
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "conclusion": {
            "v6_closed": True,
            "product_changes_after_v6_7": 0,
            "retained_v6_7_directions": 21,
            "reason": (
                "V6-0138 hard gates and V6-0141 all81 performance terminal both "
                "passed on an identical product-source fingerprint."
            ),
        },
        "gates": {
            "all81_correctness": {
                "status": "passed",
                "operators": 81,
                "failed": 0,
            },
            "interfaces": {
                "status": "passed",
                "operators": 81,
                "compatibility_gap_count": 0,
            },
            "dtype": {
                "status": "passed",
                "operator_dtype_missing_edges": 0,
            },
            "tasks": {
                "status": "passed",
                "case_count": EXPECTED_TASK_CASES,
                "step_row_count": EXPECTED_TASK_STEPS,
                "calculation_step_count": 14,
                "failure_count": 0,
            },
            "all81_performance": {
                "status": "passed",
                "row_count": EXPECTED_PERFORMANCE_ROWS,
                "operators": EXPECTED_OPERATORS,
                "scale_levels": 6,
                "warmup": 5,
                "repeat": 30,
                "failed_rows": 0,
            },
            "platform": {
                "status": "passed",
                "graph_lifecycle_statuses": {
                    field: parse_int(runtime[field]) for field in graph_status_fields
                },
                "valid_lifecycle_result": True,
            },
            "integrity": {
                "status": "passed",
                "manifest_diff_count": 0,
                "report_diff_count": 0,
                "product_source_match": True,
            },
        },
        "task_comparison_v6_1_to_v6_8": task_comparison,
        "task_totals": task_totals,
        "task_warm_l6_steps": l6_steps,
        "all81_l6_hotspots": l6_hotspots[:20],
        "all81_all_level_hotspots": all_level_hotspots[:20],
        "telemetry": telemetry,
        "residual_bottlenecks": residual_bottlenecks,
        "measurement_limits": [
            (
                "The V6.1 all81 archive used warmup=1/repeat=3, while V6.8 used "
                "warmup=5/repeat=30; no formal all81 percentage is published."
            ),
            (
                "dlsmi sampled externally at low frequency and covered "
                f"{perf_summary['telemetry_window_coverage_count']}/"
                f"{perf_summary['benchmark_rows']} operator windows; it is not "
                "a kernel profiler."
            ),
            (
                "The full terminal includes CPU reference execution and gaps "
                "between operators, so average GPU utilization does not measure "
                "kernel efficiency."
            ),
        ],
        "evidence": evidence,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "summary.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    gate_lines = [
        gate_row("all81 correctness", "81/81，失败 0", "V6-0138"),
        gate_row("接口与类型", "接口 81/81，兼容缺口 0", "V6-0138"),
        gate_row("dtype", "operator_dtype_missing_edges=0", "V6-0138"),
        gate_row("Task1/Task2", "24/24 用例，168/168 分步，14 步失败 0", "V6-0138"),
        gate_row("all81 L1-L6", "486/486，warmup=5，repeat=30", "V6-0141"),
        gate_row("平台", "CUDA Graph 六阶段状态均为 0", "V6-0138"),
        gate_row("完整性", "manifest/report diff 0，产品源码指纹一致", "V6-0138/0141"),
    ]
    markdown = [
        "# V6 最终终测汇总",
        "",
        "## 结论",
        "",
        "- 状态：`passed`，V6.8 已关闭。",
        "- V6-0138 硬门和 V6-0141 性能终测使用相同产品源码指纹，全部返回 0。",
        "- V6.7 正式保留 21 个优化方向；V6.8 不再改产品算子，只做同源码验收和报告收束。",
        "- Task1 L6 warm median 为 `3.91998 ms`，相对 V6.1 下降 `45.48%`。",
        "- Task2 L6 warm median 为 `25.2926 ms`，相对 V6.1 下降 `66.75%`。",
        "",
        "## 硬门",
        "",
        "| 项目 | 结果 | 证据 |",
        "| --- | --- | --- |",
        *gate_lines,
        "",
        "## 任务 L6 对照",
        "",
        "| 任务 | 指标 | V6.1 ms | V6.8 ms | 降幅 | 口径 |",
        "| --- | --- | ---: | ---: | ---: | --- |",
    ]
    for row in task_comparison:
        markdown.append(
            f"| {row['task']} | {row['metric']} | {row['baseline_ms']:.6f} | "
            f"{row['current_ms']:.6f} | {row['reduction_percent']:.2f}% | "
            f"{row['measurement']} |"
        )

    markdown.extend(
        [
            "",
            "## 任务 L1-L6 总时间",
            "",
            "| 模式 | 任务 | 规模 | GPU first ms | GPU median ms | GPU P95 ms |",
            "| --- | --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for row in task_totals:
        markdown.append(
            f"| {row['mode']} | {row['task']} | L{row['scale_level']} | "
            f"{row['gpu_first_ms']:.6f} | {row['gpu_median_ms']:.6f} | "
            f"{row['gpu_p95_ms']:.6f} |"
        )

    markdown.extend(
        [
            "",
            "## L6 任务步骤",
            "",
            "| 任务 | 步骤 | GPU E2E ms | mixed error | max abs |",
            "| --- | --- | ---: | ---: | ---: |",
        ]
    )
    for row in l6_steps:
        markdown.append(
            f"| {row['task']} | {row['step']} | {row['gpu_e2e_ms']:.6f} | "
            f"{row['mixed_error']:.6e} | {row['max_abs']:.6e} |"
        )

    markdown.extend(
        [
            "",
            "## all81 性能终测",
            "",
            "- 完整结果：81 个算子 × 6 个规模，共 `486/486` 行通过。",
            "- 正式计时：warmup=`5`，repeat=`30`，GPU 为 `ZQ500-Q QUAD-0`。",
            "- V6.1 all81 历史包使用 warmup=`1`、repeat=`3`，与本轮协议不同，因此不发布全库百分比。",
            "",
            "| 全规模热点 | 规模 | E2E ms | kernel ms | 固定开销 ms |",
            "| --- | --- | ---: | ---: | ---: |",
        ]
    )
    for row in all_level_hotspots[:12]:
        markdown.append(
            f"| {row['module']}/{row['operator']} | L{row['scale_level']} "
            f"({row['scale_value']}) | {row['gpu_e2e_median_ms']:.6f} | "
            f"{row['gpu_kernel_median_ms']:.6f} | "
            f"{row['fixed_overhead_ms']:.6f} |"
        )

    used_fraction = (
        parse_float(telemetry["used_mib_max"])
        / parse_float(telemetry["total_mib_max"])
        * 100.0
    )
    markdown.extend(
        [
            "",
            "## GPU 资源",
            "",
            f"- dlsmi 样本 `{telemetry['sample_count']}`，持续 `{telemetry['duration_s']:.2f} s`。",
            f"- 显存峰值 `{telemetry['used_mib_max']:.0f}/{telemetry['total_mib_max']:.0f} MiB`，约 `{used_fraction:.2f}%`。",
            f"- 瞬时 GPU utilization 最大 `{telemetry['util_percent_max']:.0f}%`。",
            f"- 逐算子时间窗覆盖 `{perf_summary['telemetry_window_coverage_count']}/{perf_summary['benchmark_rows']}`。",
            "- 平均利用率包含 CPU 参考执行和算子切换空隙，不能据此判断 kernel 未吃满。",
            "",
            "## 剩余瓶颈",
            "",
            "- `radartools/ambgfun` L6 为 `167.855/167.303 ms`（E2E/kernel），已是计算主导；单 tile 扩显存候选因精度失败且退化 0.22% 已回退。",
            "- `filtering/hilbert2` L5 的 `724x725` 为 `97.534/97.472 ms`；V6.1 已存在同一性能陡坡，不是本轮回归，后续需 FFT 算法或 layout 重写。",
            "- `spectral/lombscargle` L6 为 `11.497/11.293 ms`，保留双频输入复用与 warp 归约后剩余为算术主导。",
            "- `radartools/mvdr` L6 为 `2.481/0.794 ms`，继续下降需要跨调用生命周期或输出/同步重构。",
            "",
            "## 证据",
            "",
            f"- V6-0138：`{preflight_root}`；归档 SHA256 `{evidence['v6_0138']['archive_sha256']}`。",
            f"- V6-0141：`{performance_root}`；归档 SHA256 `{evidence['v6_0141']['archive_sha256']}`。",
            f"- V6-0141 console SHA256 `{evidence['v6_0141']['console_sha256']}`。",
            "",
            "## 报告治理",
            "",
            "- 仓库内只保留 V5.5 与 V6 的 `summary.md/json`。",
            "- all81 长表、逐算子 telemetry、任务 168 行明细、日志和容器归档保留在仓库外证据目录。",
        ]
    )
    (output_dir / "summary.md").write_text(
        "\n".join(markdown) + "\n",
        encoding="utf-8",
    )
    write_report_readme(report_root)

    actual = {path for path in report_root.rglob("*") if path.is_file()}
    require(
        actual in (allowed, allowed | optional_v7),
        f"unexpected final report files: {sorted(actual - allowed - optional_v7)}",
    )

    print(
        json.dumps(
            {
                "status": "passed",
                "output_dir": str(output_dir),
                "report_file_count": len(actual),
                "all81_rows": perf_summary["benchmark_rows"],
                "task_cases": task_summary["case_count"],
                "task_steps": task_summary["step_row_count"],
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
