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
        Path("demo/task1_radar/task1_common.hpp"),
        Path("demo/task1_radar/task1_common.cpp"),
        Path("demo/task1_radar/task1_cpu.cpp"),
        Path("demo/task1_radar/task1_gpu.cu"),
        Path("include/cusignal/radartools/radartools.hpp"),
        Path("src/cpu/radartools.cpp"),
        Path("src/zhongkexin/radartools.cu"),
    ),
    "task2_features": (
        Path("demo/task2_features/task2_features_demo.cpp"),
        Path("demo/task2_features/task2_common.hpp"),
        Path("demo/task2_features/task2_common.cpp"),
        Path("demo/task2_features/task2_cpu.cpp"),
        Path("demo/task2_features/task2_gpu.cu"),
        Path("demo/task2_features/task2_features_zx_gpu.hpp"),
        Path("demo/task2_features/task2_features_zx_gpu.cu"),
    ),
}
IMPLEMENTATIONS = {"public", "mixed", "private", "orchestration"}
REPORT_STATES = {"present", "missing", "bundled", "business_only"}
EXPECTED_STEPS = {
    "task1_radar": {
        "input_construction",
        "pulse_compression",
        "pulse_doppler",
        "power_map",
        "ca_cfar",
        "ambgfun",
        "final_detection",
    },
    "task2_features": {
        "input_construction",
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
    parser.add_argument("--operator-sets", default="tests/contracts/operator_sets.json")
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


def validate_task_step_reports(
    report_root: Path,
    output: Path,
    expected_operators: dict[str, set[str]],
) -> tuple[dict[str, Any], int]:
    failures: list[str] = []
    task_summaries: dict[str, Any] = {}

    def number(row: dict[str, str], field: str, *, positive: bool = False) -> float | None:
        raw = row.get(field, "")
        if raw in (None, ""):
            return None
        try:
            value = float(raw)
        except (TypeError, ValueError):
            failures.append(f"invalid number {field}: {row.get('task', '?')}/{row.get('scale', '?')}")
            return None
        if not math.isfinite(value) or (positive and value <= 0.0):
            failures.append(f"invalid value {field}: {row.get('task', '?')}/{row.get('scale', '?')}")
            return None
        return value

    for task, expected_steps in EXPECTED_STEPS.items():
        task_root = report_root / task
        summary_path = task_root / "summary.csv"
        if not summary_path.is_file():
            failures.append(f"missing task summary: {summary_path}")
            continue
        with summary_path.open("r", encoding="utf-8", newline="") as handle:
            summary_rows = list(csv.DictReader(handle))
        scales = {row.get("scale") for row in summary_rows}
        if len(summary_rows) != 6 or scales != {f"L{index}" for index in range(1, 7)}:
            failures.append(f"summary must contain exactly L1-L6: {task}: {sorted(scales)}")
        required_summary = {
            "task", "scale", "warmup", "repeat", "task_input_h2d_ms",
            "cpu_total_ms", "gpu_e2e_ms", "gpu_kernel_ms", "e2e_speedup", "kernel_speedup",
            "input_max_abs", "input_max_rel", "input_rmse", "input_mixed_error",
            "operator_max_abs", "operator_max_rel", "operator_rmse", "operator_mixed_error",
            "e2e_max_abs", "e2e_max_rel", "e2e_rmse", "e2e_mixed_error", "validation_pass",
        }
        for row in summary_rows:
            missing = required_summary - set(row)
            if missing:
                failures.append(f"missing summary fields: {task}/{row.get('scale', '')}: {sorted(missing)}")
                continue
            if row.get("task") != task:
                failures.append(f"summary task mismatch: {task}/{row.get('scale', '')}")
            number(row, "warmup")
            repeat = number(row, "repeat", positive=True)
            if repeat is not None and repeat < 3:
                failures.append(f"repeat must be >=3: {task}/{row.get('scale', '')}")
            number(row, "task_input_h2d_ms")
            if row.get("task_input_h2d_ms") not in {"0", "0.0", "0.000000", "0.000000000"}:
                failures.append(f"task_input_h2d_ms must be 0 for device-native task protocol: {task}/{row.get('scale', '')}")
            cpu_total = number(row, "cpu_total_ms", positive=True)
            gpu_e2e = number(row, "gpu_e2e_ms", positive=True)
            gpu_kernel = number(row, "gpu_kernel_ms", positive=True)
            e2e_speedup = number(row, "e2e_speedup", positive=True)
            if cpu_total is not None and gpu_e2e is not None and e2e_speedup is not None:
                expected = cpu_total / gpu_e2e
                if not math.isclose(e2e_speedup, expected, rel_tol=1.0e-5, abs_tol=1.0e-6):
                    failures.append(
                        f"task E2E speedup must be CPU E2E / GPU E2E: "
                        f"{task}/{row.get('scale', '')}"
                    )
            kernel_speedup = number(row, "kernel_speedup")
            if cpu_total is not None and gpu_kernel is not None and kernel_speedup is not None:
                expected = cpu_total / gpu_kernel
                if not math.isclose(kernel_speedup, expected, rel_tol=1.0e-5, abs_tol=1.0e-6):
                    failures.append(
                        f"task kernel speedup must be CPU E2E / GPU kernel total: "
                        f"{task}/{row.get('scale', '')}"
                    )
            for field in (
                "input_max_abs", "input_max_rel", "input_rmse", "input_mixed_error",
                "operator_max_abs", "operator_max_rel", "operator_rmse", "operator_mixed_error",
                "e2e_max_abs", "e2e_max_rel", "e2e_rmse", "e2e_mixed_error",
            ):
                number(row, field)
            if row.get("validation_pass") != "PASS":
                failures.append(f"task validation failed: {task}/{row.get('scale', '')}")

        operator_dir = task_root / "operators"
        kernel_available = 0
        error_available = 0
        report_steps: set[str] = set()
        for index in range(1, 7):
            path = operator_dir / f"L{index}.csv"
            if not path.is_file():
                failures.append(f"missing operator report: {path}")
                continue
            with path.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            names = [row.get("operator", "") for row in rows]
            actual = set(names)
            expected_public = expected_operators[task]
            if actual != expected_public or len(names) != len(actual):
                failures.append(f"operator step mismatch: {task}/L{index}: {sorted(actual)}")
            if actual & set(EXPECTED_STEPS[task]):
                failures.append(f"stage name leaked into public operator report: {task}/L{index}")
            report_steps.update(actual)
            required_operator = {
                "task", "scale", "operator", "cpu_ms", "gpu_e2e_ms", "gpu_kernel_ms",
                "source_step", "mapping_mode", "e2e_speedup", "kernel_speedup",
                "operator_max_abs", "e2e_max_abs", "status",
            }
            for row in rows:
                missing = required_operator - set(row)
                name = row.get("operator", "")
                if missing:
                    failures.append(f"missing operator fields: {task}/L{index}/{name}: {sorted(missing)}")
                    continue
                cpu_ms = number(row, "cpu_ms", positive=True)
                gpu_e2e_ms = number(row, "gpu_e2e_ms", positive=True)
                kernel = number(row, "gpu_kernel_ms", positive=True)
                if kernel is not None:
                    kernel_available += 1
                e2e_speedup = number(row, "e2e_speedup", positive=True)
                if cpu_ms is not None and gpu_e2e_ms is not None and e2e_speedup is not None:
                    expected = cpu_ms / gpu_e2e_ms
                    if not math.isclose(e2e_speedup, expected, rel_tol=1.0e-5, abs_tol=1.0e-6):
                        failures.append(
                            f"operator E2E speedup must be CPU E2E / GPU E2E: "
                            f"{task}/L{index}/{name}"
                        )
                kernel_speedup = number(row, "kernel_speedup")
                if cpu_ms is not None and kernel is not None and kernel_speedup is not None:
                    expected = cpu_ms / kernel
                    if not math.isclose(kernel_speedup, expected, rel_tol=1.0e-5, abs_tol=1.0e-6):
                        failures.append(
                            f"operator kernel speedup must be CPU E2E / GPU kernel: "
                            f"{task}/L{index}/{name}"
                        )
                number(row, "operator_max_abs")
                number(row, "operator_max_rel")
                number(row, "operator_rmse")
                number(row, "operator_mixed_error")
                number(row, "e2e_max_abs")
                number(row, "e2e_max_rel")
                number(row, "e2e_rmse")
                number(row, "e2e_mixed_error")
                error_available += 1
                if row.get("status") != "PASS":
                    failures.append(f"operator validation failed: {task}/L{index}/{name}")
        stage_dir = task_root / "stages"
        stage_rows = 0
        allowed_stage_names = EXPECTED_STEPS[task] | {"h2d", "final_output", "validation_h2d", "validation_d2h"}
        for index in range(1, 7):
            path = stage_dir / f"L{index}.csv"
            if not path.is_file():
                failures.append(f"missing stage report: {path}")
                continue
            with path.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            stage_rows += len(rows)
            required_stage = {
                "task", "scale", "stage", "record_kind", "helper_names",
                "public_operator_links", "cpu_ms", "gpu_e2e_ms", "gpu_kernel_ms",
                "counted_in_task_e2e",
            }
            for row in rows:
                missing = required_stage - set(row)
                stage = row.get("stage", "")
                if missing:
                    failures.append(f"missing stage fields: {task}/L{index}/{stage}: {sorted(missing)}")
                    continue
                if stage not in allowed_stage_names:
                    failures.append(f"unknown task stage: {task}/L{index}/{stage}")
                if row.get("record_kind") != "task_stage":
                    failures.append(f"stage record kind mismatch: {task}/L{index}/{stage}")
                number(row, "cpu_ms")
                number(row, "gpu_e2e_ms")
                if row.get("counted_in_task_e2e") != "true":
                    failures.append(f"stage not counted in task E2E: {task}/L{index}/{stage}")
        task_summaries[task] = {
            "scale_count": len(summary_rows),
            "operator_count": len(report_steps),
            "operator_rows": len(report_steps) * 6,
            "stage_rows": stage_rows,
            "error_available_count": error_available,
            "kernel_available_count": kernel_available,
        }

    summary = {
        "status": "failed" if failures else "passed",
        "task_count": len(task_summaries),
        "step_count": sum(item["operator_count"] for item in task_summaries.values()),
        "registered_task_operator_count": len(set().union(*expected_operators.values())),
        "operator_rows": sum(item["operator_rows"] for item in task_summaries.values()),
        "stage_rows": sum(item["stage_rows"] for item in task_summaries.values()),
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
    operator_sets_payload = json.loads(Path(args.operator_sets).read_text(encoding="utf-8"))
    operator_sets = operator_sets_payload.get("sets", {})
    all81 = set(operator_sets.get("all81", {}).get("operators", []))
    task_used = set(operator_sets.get("task_used", {}).get("operators", []))
    if len(all81) != 81:
        raise ValueError("operator_sets all81 must contain 81 registered operators")
    if len(task_used) != 18:
        raise ValueError("operator_sets task_used must contain 18 task-used operators")
    tasks = payload.get("tasks", {})
    failures = []
    rows = []
    seen = set()
    registered_public_operators = set()
    task_helpers = set()
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
            public_operators = entry.get("public_operators", [])
            if not isinstance(public_operators, list):
                failures.append(f"public_operators must be a list: {task}/{step}")
                public_operators = []
            for operator in public_operators:
                if operator not in all81:
                    failures.append(f"unregistered public operator: {task}/{step}: {operator}")
                registered_public_operators.add(operator)
            helpers = entry.get("task_helpers", [])
            if not isinstance(helpers, list):
                failures.append(f"task_helpers must be a list: {task}/{step}")
                helpers = []
            for helper in helpers:
                if helper in all81:
                    failures.append(f"task helper is registered operator: {task}/{step}: {helper}")
                if helper and helper not in source_text:
                    failures.append(f"task helper not found: {task}/{step}: {helper}")
                task_helpers.add(helper)
            mapping = entry.get("operator_mapping", {})
            if not isinstance(mapping, dict):
                failures.append(f"operator_mapping must be an object: {task}/{step}")
                mapping = {}
            if set(mapping) != set(public_operators):
                failures.append(
                    f"operator mapping mismatch: {task}/{step}: "
                    f"public={sorted(public_operators)} mapping={sorted(mapping)}"
                )
            for operator, mode in mapping.items():
                if mode not in {"direct", "variant", "private_equivalent"}:
                    failures.append(f"invalid operator mapping: {task}/{step}: {operator}={mode}")
            if implementation in {"mixed", "private"} and not entry.get("migration_target"):
                failures.append(f"missing migration target: {task}/{step}")
            rows.append({"task": task, **entry})

    if registered_public_operators != task_used:
        failures.append(
            "task_used does not match public operators in task contracts: "
            f"missing={sorted(task_used - registered_public_operators)} "
            f"extra={sorted(registered_public_operators - task_used)}"
        )

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
        "registered_task_operator_count": len(registered_public_operators),
        "task_helper_count": len(task_helpers),
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
        expected_operators = {
            task: {
                operator
                for entry in tasks.get(task, [])
                for operator in entry.get("public_operators", [])
            }
            for task in EXPECTED_STEPS
        }
        report_summary, report_status = validate_task_step_reports(
            Path(args.report_root), Path(args.report_output), expected_operators
        )
        print(json.dumps(report_summary, ensure_ascii=False, sort_keys=True))
    return 1 if failures or report_status else 0


if __name__ == "__main__":
    raise SystemExit(main())
