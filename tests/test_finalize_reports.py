#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/finalize_reports.py"
TASK_COUNTS = {"task1_radar": 6, "task2_features": 8}
PERF_STATS = {
    "warmup": 1,
    "repeat": 3,
    "mean_ms": 1.0,
    "median_ms": 1.0,
    "p95_ms": 1.0,
    "min_ms": 1.0,
    "max_ms": 1.0,
    "std_ms": 0.0,
}


def write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


class FinalizeReportsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.reports = self.repo / "data/reports"
        self.output = self.reports / "final"
        self.operators = [f"module{index // 9}/operator{index}" for index in range(81)]
        self._write_contracts()
        self._write_delivery_sources()
        self._write_operators()
        self._write_tasks()
        self._write_audits()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write_contracts(self) -> None:
        write_json(
            self.repo / "tests/contracts/operator_sets.json",
            {
                "schema_version": 1,
                "sets": {"all81": {"expected_count": 81, "operators": self.operators}},
            },
        )
        task_contracts = {}
        for task, count in TASK_COUNTS.items():
            task_contracts[task] = [
                {"step": f"step_{index}", "category": "calculation"}
                for index in range(count)
            ]
        write_json(
            self.repo / "tests/contracts/task_step_contracts.json",
            {"schema_version": 1, "tasks": task_contracts},
        )

    def _write_delivery_sources(self) -> None:
        write_text(self.repo / "source.cpp", "int delivery_source = 1;\n")
        write_text(
            self.repo / "DELIVERY_FILES.txt",
            "source.cpp\ndata/reports/summary.json\n",
        )

    def _write_operators(self) -> None:
        for index, key in enumerate(self.operators):
            module, operator = key.split("/", 1)
            report = self.reports / "unit" / module / operator
            write_json(
                report / "latest_metrics.json",
                {
                    "module": module,
                    "operator": operator,
                    "generated_at": "2026-07-17 12:00:00",
                    "git_commit": "fixture-commit",
                    "gpu_name": "fixture-gpu",
                    "summary": {
                        "pass": True,
                        "accuracy_cases": 1,
                        "perf_cases": 1,
                        "cpu_perf": PERF_STATS,
                        "gpu_e2e_perf": PERF_STATS,
                        "gpu_kernel_perf": PERF_STATS,
                    },
                    # Several real operators use summary-only metrics and keep
                    # their case detail in latest_cases.csv.
                    "cases": [] if index == 0 else [
                        {"case_id": "case", "category": "perf", "pass": True}
                    ],
                },
            )
            write_text(report / "latest_cases.csv", "case_id,pass\ncase,true\n")
            write_text(report / "latest_summary.md", f"# {key}\n\nPASS\n")

    def _task_metrics(self, scale: int) -> dict[str, object]:
        return {
            "version": "fixture",
            "scenario": {"scale_level": scale},
            "validation": {
                "pass": True,
                "checks": [{"name": "fixture", "pass": True}],
            },
            "repeat_runs": [{"index": 1, "pass": True}],
        }

    def _write_task_case(self, report: Path, task: str, scale: int) -> None:
        count = TASK_COUNTS[task]
        write_json(report / "latest_metrics.json", self._task_metrics(scale))
        write_json(
            report / "latest_step_metrics.json",
            {
                "task": task,
                "schema_version": 2,
                "steps": [
                    {"step": f"step_{index}", "pass": True}
                    for index in range(count)
                ],
            },
        )
        write_text(report / "latest_summary.md", f"# {task} L{scale}\n\nPASS\n")
        write_text(report / "latest_stage_timings.csv", "stage,gpu_ms\ntotal,1.0\n")
        rows = "".join(f"step_{index},true\n" for index in range(count))
        write_text(report / "latest_step_metrics.csv", "step,pass\n" + rows)

    def _write_tasks(self) -> None:
        for task in TASK_COUNTS:
            root = self.reports / "demo" / task
            self._write_task_case(root, task, 3)
            for scale in range(1, 7):
                report = root / "scales" / f"L{scale}"
                self._write_task_case(report, task, scale)
                write_json(report / "input_scenario.json", {"scale_level": scale})

    def _write_audits(self) -> None:
        audit = self.reports / "runtime/audits"
        write_json(
            audit / "operator_contract.json",
            {"summary": {"status": "passed", "operator_count": 81, "failed_count": 0}},
        )
        write_json(
            audit / "dtype_contract.json",
            {
                "summary": {
                    "status": "passed",
                    "operator_count": 81,
                    "compatibility_gap_count": 0,
                    "upstream_complex64_planned_gap_count": 8,
                }
            },
        )
        write_json(
            audit / "task_contract.json",
            {
                "summary": {
                    "status": "passed",
                    "calculation_step_count": 14,
                    "timing_gap_count": 0,
                    "accuracy_gap_count": 0,
                    "failure_count": 0,
                }
            },
        )

    def run_finalizer(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--repo-root",
                str(self.repo),
                "--source-root",
                str(self.reports),
                "--output",
                str(self.output),
                "--run-id",
                "fixture-run",
                *extra,
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def test_successful_fixture_publishes_and_verifies(self) -> None:
        completed = self.run_finalizer()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        summary = json.loads((self.output / "summary.json").read_text(encoding="utf-8"))
        self.assertEqual(summary["status"], "passed")
        self.assertEqual(summary["operator_count"], 81)
        self.assertEqual(summary["task_count"], 2)
        self.assertEqual(summary["task_scale_report_count"], 12)
        self.assertEqual(summary["calculation_step_count"], 14)
        self.assertTrue((self.output / "validation/task_contract.json").is_file())
        self.assertEqual(
            len(list((self.output / "units").glob("*/*/metrics.json"))),
            81,
        )
        benchmark_summary = json.loads(
            (self.output / "units/benchmarks/summary.json").read_text(encoding="utf-8")
        )
        self.assertEqual(benchmark_summary["operator_count"], 81)
        self.assertEqual(benchmark_summary["operators_with_performance"], 81)
        self.assertEqual(
            benchmark_summary["operators"][0]["performance_cases"][0]["source"],
            "summary_aggregate",
        )
        operator_summary = (
            self.output / "units/module0/operator0/summary.md"
        ).read_text(encoding="utf-8")
        self.assertIn("GPU kernel 最小时间", operator_summary)
        self.assertIn("GPU kernel 最大时间", operator_summary)
        table_header = (
            self.output / "units/benchmarks/summary.csv"
        ).read_text(encoding="utf-8").splitlines()[0]
        self.assertIn("GPU_kernel最小运行时间_ms", table_header)
        self.assertIn("GPU_kernel最大运行时间_ms", table_header)
        self.assertNotIn(
            b"\r\n",
            (self.output / "units/benchmarks/summary.csv").read_bytes(),
        )
        verified = self.run_finalizer("--verify")
        self.assertEqual(verified.returncode, 0, verified.stderr)

    def test_missing_operator_is_rejected(self) -> None:
        module, operator = self.operators[-1].split("/", 1)
        (self.reports / "unit" / module / operator / "latest_metrics.json").unlink()
        completed = self.run_finalizer()
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("unit operator set mismatch", completed.stderr)
        self.assertFalse(self.output.exists())

    def test_failed_task_is_rejected(self) -> None:
        path = self.reports / "demo/task2_features/scales/L4/latest_metrics.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["validation"]["pass"] = False
        write_json(path, payload)
        completed = self.run_finalizer()
        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("validation.pass must be true", completed.stderr)
        self.assertFalse(self.output.exists())

    def test_cold_start_timing_outlier_does_not_reject_business_valid_task(self) -> None:
        path = self.reports / "demo/task1_radar/latest_metrics.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_runs"] = [
            {"index": 1, "pass": False, "business_numeric_pass": True},
            {"index": 2, "pass": True, "business_numeric_pass": True},
        ]
        write_json(path, payload)

        completed = self.run_finalizer()

        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_repeat_business_failure_is_rejected(self) -> None:
        path = self.reports / "demo/task1_radar/latest_metrics.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["repeat_runs"] = [
            {"index": 1, "pass": True, "business_numeric_pass": False},
        ]
        write_json(path, payload)

        completed = self.run_finalizer()

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("failed business or numeric validation", completed.stderr)
        self.assertFalse(self.output.exists())

    def test_failure_does_not_modify_existing_final(self) -> None:
        marker = self.output / "existing.marker"
        write_text(marker, "preserve exactly\n")
        audit = self.reports / "runtime/audits/task_contract.json"
        payload = json.loads(audit.read_text(encoding="utf-8"))
        payload["summary"]["timing_gap_count"] = 1
        write_json(audit, payload)
        completed = self.run_finalizer()
        self.assertNotEqual(completed.returncode, 0)
        self.assertEqual(marker.read_bytes(), b"preserve exactly\n")
        self.assertEqual([path.name for path in self.output.iterdir()], ["existing.marker"])


if __name__ == "__main__":
    unittest.main()
