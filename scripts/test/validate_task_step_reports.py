#!/usr/bin/env python3

"""Validate the shared Task1/Task2 step-metrics report schema."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path


EXPECTED_STEPS = {
    "task1_radar": {
        "pulse_compression", "pulse_doppler", "power_map", "ca_cfar", "ambgfun", "final_detection",
    },
    "task2_features": {
        "filter", "demod", "correlate", "spectrogram", "cwt", "feature_fusion",
        "measurement_conversion", "kalman",
    },
}
REQUIRED_FIELDS = {
    "step", "operator", "input_shape", "output_shape", "input_dtype", "output_dtype",
    "cpu_ms", "gpu_e2e_ms", "gpu_kernel_ms", "gpu_e2e_speedup", "gpu_kernel_speedup",
    "error_available", "error", "pass", "note",
}
COMPLEX_ERROR_STEPS = {"task1_radar/pulse_compression", "task1_radar/pulse_doppler", "task2_features/filter", "task2_features/cwt"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report-root", default="data/reports/demo")
    parser.add_argument("--output", default="data/reports/zhongkexin/v5_3_step_reports_summary.json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    failures = []
    task_summaries = {}
    for task, expected_steps in EXPECTED_STEPS.items():
        path = Path(args.report_root) / task / "latest_step_metrics.json"
        if not path.is_file():
            failures.append(f"missing report: {path}")
            continue
        payload = json.loads(path.read_text(encoding="utf-8"))
        steps = payload.get("steps", [])
        actual_steps = {step.get("step") for step in steps}
        if payload.get("task") != task or payload.get("schema_version") != 1:
            failures.append(f"invalid task/schema: {task}")
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
            if step["error_available"]:
                error_available += 1
                error = step.get("error") or {}
                for field in ("max_abs", "max_rel", "rmse", "mixed_error"):
                    if not isinstance(error.get(field), (int, float)) or not math.isfinite(error[field]):
                        failures.append(f"invalid error {field}: {task}/{name}")
                if f"{task}/{name}" in COMPLEX_ERROR_STEPS:
                    if error.get("real_max_abs") is None or error.get("imag_max_abs") is None:
                        failures.append(f"missing complex components: {task}/{name}")
        task_summaries[task] = {
            "step_count": len(steps),
            "error_available_count": error_available,
            "kernel_available_count": kernel_available,
        }

    summary = {
        "status": "failed" if failures else "passed",
        "task_count": len(task_summaries),
        "step_count": sum(item["step_count"] for item in task_summaries.values()),
        "error_available_count": sum(item["error_available_count"] for item in task_summaries.values()),
        "kernel_available_count": sum(item["kernel_available_count"] for item in task_summaries.values()),
        "tasks": task_summaries,
        "failure_count": len(failures),
        "failures": failures,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
