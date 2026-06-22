#!/usr/bin/env python3

"""Audit Task1/Task2 calculation steps and public-operator migration status."""

from __future__ import annotations

import argparse
import json
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contracts", default="scripts/test/task_step_contracts.json")
    parser.add_argument("--output-dir", default="data/reports/zhongkexin/v5_3_task_step_audit")
    parser.add_argument("--summary-markdown", default="docs/performance/v5_0/task_step_audit.md")
    return parser.parse_args()


def escape(value: Any) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


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
    summary = {
        "status": "failed" if failures else "passed",
        "task_count": len(tasks),
        "step_count": len(rows),
        "calculation_step_count": calculation_count,
        "public_calculation_step_count": public_calculation_count,
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
        "# V5.3 Task1/Task2 步骤审计",
        "",
        "本文件由 `scripts/test/audit_task_steps.py` 根据机器可读步骤契约生成。",
        "`public` 表示已完全调用公共算子；`mixed/private` 是 V5.3-03/04 的迁移清单。",
        "",
        f"- status: `{summary['status']}`",
        f"- steps/calculation: `{summary['step_count']}` / `{calculation_count}`",
        f"- public calculation: `{public_calculation_count}`",
        f"- migration steps: `{summary['migration_step_count']}`",
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
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
