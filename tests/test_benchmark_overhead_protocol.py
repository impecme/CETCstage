#!/usr/bin/env python3
"""Protocol checks for non-kernel overhead reporting."""

from __future__ import annotations

import csv
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
REPORT_HEADER = REPO_ROOT / "tests/unit/common/benchmark_overhead_protocol.hpp"
REPORT_WRITER = REPO_ROOT / "scripts/performance.sh"
OVERHEAD_FIELDS = (
    "allocation_calls",
    "allocation_bytes",
    "plan_create_calls",
    "plan_destroy_calls",
    "event_create_calls",
    "event_destroy_calls",
    "explicit_device_sync_calls",
    "h2d_calls",
    "h2d_bytes",
    "d2h_calls",
    "d2h_bytes",
    "materialize_calls",
)


def extract_operator_report_writer() -> str:
    source = REPORT_WRITER.read_text(encoding="utf-8")
    marker = 'python3 - "$raw_root/reports" "$OUTPUT_ROOT/units/benchmarks"'
    start = source.index(marker)
    start = source.index("\n", start) + 1
    end = source.index("\nPY\n", start)
    return source[start:end]


class BenchmarkOverheadProtocolTests(unittest.TestCase):
    def test_counter_interface_and_report_fields_are_explicit(self) -> None:
        header = REPORT_HEADER.read_text(encoding="utf-8")
        report = (REPO_ROOT / "tests/unit/common/report.hpp").read_text(encoding="utf-8")
        for name in OVERHEAD_FIELDS:
            self.assertIn(name, header)
            self.assertIn(name, report)
        for operation in (
            "note_allocation",
            "note_plan_create",
            "note_plan_destroy",
            "note_event_create",
            "note_event_destroy",
            "note_device_sync",
            "note_h2d",
            "note_d2h",
            "note_materialize",
        ):
            self.assertIn(operation, header)
        self.assertIn("non_kernel_overhead", report)
        self.assertIn('"N/A"', report)

    def test_missing_counters_are_published_as_na_without_e2e_inference(self) -> None:
        writer = extract_operator_report_writer()
        with tempfile.TemporaryDirectory(prefix="cetc_overhead_protocol_") as directory:
            root = Path(directory)
            reports = root / "reports" / "L1"
            report_dir = reports / "demo" / "op"
            report_dir.mkdir(parents=True)
            (reports / "scale_metadata.json").write_text(
                json.dumps(
                    {
                        "operators": {
                            "demo/op": {
                                "scale_kind": "synthetic",
                                "scale_profile": "synthetic",
                                "scale_fields": {},
                                "input_elements": 1,
                                "power_of_two_dimensions": True,
                            }
                        }
                    }
                ),
                encoding="utf-8",
            )
            (report_dir / "latest_metrics.json").write_text(
                json.dumps(
                    {
                        "summary": {
                            "pass": True,
                            "accuracy_cases": 1,
                            "input_refresh": {"pass": True},
                            "cpu_perf": {"median_ms": 2.0},
                            "gpu_e2e_perf": {"median_ms": 1.0},
                        },
                        "cases": [],
                    }
                ),
                encoding="utf-8",
            )
            output = root / "published"
            result = subprocess.run(
                [
                    sys.executable,
                    "-",
                    str(root / "reports"),
                    str(output),
                    "synthetic",
                    "L1",
                    "5",
                    "30",
                    "full",
                ],
                input=writer,
                cwd=REPO_ROOT,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            with (output / "operator_scales.csv").open(newline="", encoding="utf-8") as handle:
                row = next(csv.DictReader(handle))
            self.assertEqual(row["warmup"], "5")
            self.assertEqual(row["repeat"], "30")
            self.assertEqual(row["cpu_median_ms"], "2.0")
            self.assertEqual(row["gpu_e2e_median_ms"], "1.0")
            for name in OVERHEAD_FIELDS:
                self.assertEqual(row["non_kernel_overhead_" + name], "N/A")
            published = json.loads(
                (output / "operator_scales.json").read_text(encoding="utf-8")
            )
            self.assertEqual(published["non_kernel_overhead_missing_value"], "N/A")

    def test_all81_report_shape_remains_486_workload_keys(self) -> None:
        contract = json.loads(
            (REPO_ROOT / "tests/contracts/operator_sets.json").read_text(encoding="utf-8")
        )
        all81 = contract["sets"]["all81"]["operators"]
        self.assertEqual(len(all81), 81)
        self.assertEqual(len(all81) * 6, 486)
        source = REPORT_WRITER.read_text(encoding="utf-8")
        self.assertIn('"all81": 81', source)
        self.assertIn('WARMUP=5', source)
        self.assertIn('REPEAT=30', source)
        self.assertIn('"gpu_e2e_speedup": cpu / e2e', source)
        self.assertIn('"input_refresh_pass"', source)


if __name__ == "__main__":
    unittest.main()
