#!/usr/bin/env python3

"""Audit Task1/Task2 contracts and optionally validate runtime step reports."""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import Counter
from pathlib import Path
from typing import Any


TASK_SOURCES = {
    "task1_radar": (
        Path("demo/task1_radar/task1_radar_demo.cpp"),
        Path("include/cusignal/radartools/radartools.hpp"),
        Path("src/cpu/radartools.cpp"),
        Path("src/zhongkexin/radartools.cu"),
    ),
    "task2_features": (
        Path("demo/task2_features/task2_features_demo.cpp"),
        Path("demo/task2_features/task2_features_zx_gpu.hpp"),
        Path("demo/task2_features/task2_features_zx_gpu.cu"),
    ),
}
IMPLEMENTATIONS = {"public", "mixed", "private", "orchestration"}
REPORT_STATES = {"present", "missing", "bundled", "business_only"}
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
REQUIRED_FIELDS = {
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
COMPLEX_ERROR_STEPS = {
    "task1_radar/pulse_compression",
    "task1_radar/pulse_doppler",
    "task2_features/filter",
    "task2_features/cwt",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contracts", default="tests/contracts/task_step_contracts.json")
    parser.add_argument("--output-dir", default="data/.reports_staging/runtime/audits/task_steps")
    parser.add_argument("--summary-markdown", default="data/.reports_staging/runtime/audits/task_steps.md")
    parser.add_argument(
        "--report-root",
        default="",
        help="validate runtime task reports below this directory when provided",
    )
    parser.add_argument(
        "--report-output",
        "--output",
        dest="report_output",
        default="data/.reports_staging/runtime/audits/task_step_reports.json",
    )
    return parser.parse_args()


def escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def validate_task_step_reports(report_root: Path, output: Path) -> tuple[dict[str, Any], int]:
    failures = []
    task_summaries = {}
    for task, expected_steps in EXPECTED_STEPS.items():
        path = report_root / task / "latest_step_metrics.json"
        if not path.is_file():
            failures.append(f"missing report: {path}")
            continue
        csv_path = report_root / task / "latest_step_metrics.csv"
        payload = json.loads(path.read_text(encoding="utf-8"))
        steps = payload.get("steps", [])
        actual_steps = {step.get("step") for step in steps}
        if payload.get("task") != task or payload.get("schema_version") != EXPECTED_SCHEMA_VERSION:
            failures.append(
                f"invalid task/schema: {task}: "
                f"task={payload.get('task')!r} schema={payload.get('schema_version')!r}"
            )
        if actual_steps != expected_steps:
            failures.append(f"step mismatch: {task}: {sorted(actual_steps)}")
        kernel_available = 0
        error_available = 0
        for step in steps:
            name = step.get("step", "")
            missing = REQUIRED_FIELDS - set(step)
            if missing:
                failures.append(f"missing fields: {task}/{name}: {sorted(missing)}")
                continue
            if step["gpu_kernel_ms"] is not None:
                kernel_available += 1
                if not math.isfinite(step["gpu_kernel_ms"]):
                    failures.append(f"invalid kernel timing: {task}/{name}")
            if not step["error_available"]:
                failures.append(f"missing step error: {task}/{name}")
                continue
            if step.get("pass") is not True:
                failures.append(f"step did not pass: {task}/{name}")
            error_available += 1
            error = step.get("error") or {}
            for field in ("max_abs", "max_rel", "rmse", "mixed_error"):
                if not isinstance(error.get(field), (int, float)) or not math.isfinite(error[field]):
                    failures.append(f"invalid error {field}: {task}/{name}")
            if f"{task}/{name}" in COMPLEX_ERROR_STEPS:
                if error.get("real_max_abs") is None or error.get("imag_max_abs") is None:
                    failures.append(f"missing complex components: {task}/{name}")
        if not csv_path.is_file():
            failures.append(f"missing CSV report: {csv_path}")
        else:
            with csv_path.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            csv_steps = {row.get("step") for row in rows}
            if csv_steps != expected_steps:
                failures.append(f"CSV step mismatch: {task}: {sorted(csv_steps)}")
            for row in rows:
                if None in row:
                    failures.append(f"malformed CSV row: {task}/{row.get('step', '')}")
        task_summaries[task] = {
            "step_count": len(steps),
            "error_available_count": error_available,
            "kernel_available_count": kernel_available,
        }

    summary = {
        "status": "failed" if failures else "passed",
        "task_count": len(task_summaries),
        "step_count": sum(item["step_count"] for item in task_summaries.values()),
        "error_available_count": sum(
            item["error_available_count"] for item in task_summaries.values()
        ),
        "kernel_available_count": sum(
            item["kernel_available_count"] for item in task_summaries.values()
        ),
        "tasks": task_summaries,
        "failure_count": len(failures),
        "failures": failures,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary, (0 if not failures else 1)


def main() -> int:
    args = parse_args()
    payload = json.loads(Path(args.contracts).read_text(encoding="utf-8"))
    tasks = payload.get("tasks", {})
    failures = []
    rows = []
    seen = set()
    for task, sources in TASK_SOURCES.items():
        if task not in tasks:
            failures.append(f"missing task: {task}")
            continue
        source_text = "\n".join(path.read_text(encoding="utf-8") for path in sources)
        for entry in tasks[task]:
            step = entry.get("step", "")
            key = (task, step)
            if not step or key in seen:
                failures.append(f"invalid or duplicate step: {task}/{step}")
                continue
            seen.add(key)
            implementation = entry.get("implementation")
            if implementation not in IMPLEMENTATIONS:
                failures.append(f"invalid implementation: {task}/{step}")
            if entry.get("timing") not in REPORT_STATES or entry.get("accuracy") not in REPORT_STATES:
                failures.append(f"invalid report state: {task}/{step}")
            for side in ("cpu_symbols", "gpu_symbols"):
                symbols = entry.get(side, [])
                if not symbols:
                    failures.append(f"missing {side}: {task}/{step}")
                for symbol in symbols:
                    if symbol not in source_text:
                        failures.append(f"symbol not found: {task}/{step}: {symbol}")
            if implementation in {"mixed", "private"} and not entry.get("migration_target"):
                failures.append(f"missing migration target: {task}/{step}")
            rows.append({"task": task, **entry})

    implementation_counts = Counter(row["implementation"] for row in rows)
    timing_gap_count = sum(row["timing"] != "present" for row in rows if row["category"] == "calculation")
    accuracy_gap_count = sum(row["accuracy"] != "present" for row in rows if row["category"] == "calculation")
    calculation_count = sum(row["category"] == "calculation" for row in rows)
    public_calculation_count = sum(
        row["category"] == "calculation" and row["implementation"] == "public" for row in rows
    )
    public_operator_link_count = sum(
        row["category"] == "calculation" and bool(row.get("public_operators")) for row in rows
    )
    summary = {
        "status": "failed" if failures else "passed",
        "task_count": len(tasks),
        "step_count": len(rows),
        "calculation_step_count": calculation_count,
        "public_calculation_step_count": public_calculation_count,
        "public_operator_link_count": public_operator_link_count,
        "migration_step_count": sum(row["implementation"] in {"mixed", "private"} for row in rows),
        "timing_gap_count": timing_gap_count,
        "accuracy_gap_count": accuracy_gap_count,
        "implementation_counts": dict(sorted(implementation_counts.items())),
        "failure_count": len(failures),
        "failures": failures,
    }
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    (output / "latest_task_step_audit.json").write_text(
        json.dumps({"summary": summary, "steps": rows}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    lines = [
        "# Task1/Task2 步骤审计",
        "",
        "本文件由 `tests/tools/task_contract_audit.py` 根据机器可读步骤契约生成。",
        "`public` 表示完全调用公共算子；`mixed` 表示公共算子加任务辅助函数，按当前验收口径也属于公共算子实现链路。",
        "",
        f"- status: `{summary['status']}`",
        f"- steps/calculation: `{summary['step_count']}` / `{calculation_count}`",
        f"- public calculation: `{public_calculation_count}`",
        f"- calculation steps with public-operator link: `{public_operator_link_count}`",
        f"- mixed/private helper steps: `{summary['migration_step_count']}`",
        f"- timing/accuracy gaps: `{timing_gap_count}` / `{accuracy_gap_count}`",
        "",
        "| 任务 | 步骤 | 公共算子 | 实现 | 计时 | 精度 | 迁移目标 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        operators = ", ".join(row["public_operators"]) or "-"
        lines.append(
            f"| {row['task']} | {row['step']} | {escape(operators)} | {row['implementation']} | "
            f"{row['timing']} | {row['accuracy']} | {escape(row['migration_target'])} |"
        )
    summary_path = Path(args.summary_markdown)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    report_status = 0
    if args.report_root:
        report_summary, report_status = validate_task_step_reports(
            Path(args.report_root), Path(args.report_output)
        )
        print(json.dumps(report_summary, ensure_ascii=False, sort_keys=True))
    return 1 if failures or report_status else 0


if __name__ == "__main__":
    raise SystemExit(main())
