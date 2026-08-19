#!/usr/bin/env python3
"""Tests for frozen-baseline validation and optimized-report comparison."""

from __future__ import annotations

import csv
import hashlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from compare_operator_gpu_baseline import compare  # noqa: E402
from operator_gpu_protocol import ProtocolError, validate_frozen_baseline  # noqa: E402


BASELINE_ROOT = REPO_ROOT / "data" / "baseline"
BASELINE_CSV = BASELINE_ROOT / "gpu_baseline.csv"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class FrozenOperatorProtocolTest(unittest.TestCase):
    def test_frozen_snapshot_has_exact_all81_coverage(self) -> None:
        before = sha256(BASELINE_CSV)
        snapshot = validate_frozen_baseline(BASELINE_ROOT)
        self.assertEqual(len(snapshot.rows), 486)
        self.assertEqual(len(snapshot.keys), 486)
        self.assertEqual(before, sha256(BASELINE_CSV))

    def test_comparison_uses_saved_cpu_numerator(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cetc_operator_compare_") as directory:
            root = Path(directory)
            optimized = root / "optimized.csv"
            with BASELINE_CSV.open(newline="", encoding="utf-8") as source:
                rows = list(csv.DictReader(source))
                fields = list(rows[0])
            baseline_cpu = float(rows[0]["saved_cpu_median_ms"])
            baseline_e2e = float(rows[0]["gpu_e2e_median_ms"])
            rows[0]["gpu_e2e_median_ms"] = str(float(rows[0]["gpu_e2e_median_ms"]) / 2.0)
            # This value must not replace the frozen CPU numerator.
            rows[0]["saved_cpu_median_ms"] = "0.000001"
            with optimized.open("w", newline="", encoding="utf-8") as target:
                writer = csv.DictWriter(target, fieldnames=fields)
                writer.writeheader()
                writer.writerows(rows)

            output = root / "comparison"
            result = compare(BASELINE_ROOT, optimized, output, "synthetic-test")
            self.assertEqual(result, 0)
            comparison = output / "operator_gpu_comparison.csv"
            with comparison.open(newline="", encoding="utf-8") as handle:
                compared = list(csv.DictReader(handle))
            self.assertEqual(len(compared), 486)
            first = next(row for row in compared if row["operator"] == rows[0]["operator"] and row["scale_level"] == rows[0]["scale_level"])
            self.assertEqual(first["optimization_status"], "POSITIVE")
            self.assertAlmostEqual(
                float(first["baseline_cpu_to_gpu_e2e_speedup"]),
                baseline_cpu / baseline_e2e,
            )

    def test_optimized_workload_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="cetc_operator_compare_") as directory:
            root = Path(directory)
            optimized = root / "optimized.csv"
            shutil.copyfile(BASELINE_CSV, optimized)
            with optimized.open(newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
                fields = list(rows[0])
            rows[0]["input_elements"] = str(int(rows[0]["input_elements"]) + 1)
            with optimized.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                writer.writerows(rows)
            with self.assertRaises(ProtocolError):
                compare(BASELINE_ROOT, optimized, root / "comparison", "synthetic-test")


if __name__ == "__main__":
    unittest.main()
