#!/usr/bin/env python3
"""Regression checks for the consolidated build/performance script interface."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO_ROOT / "scripts" / "build.sh"
PERFORMANCE_SCRIPT = REPO_ROOT / "scripts" / "performance.sh"
SMOKE_SCRIPT = REPO_ROOT / "scripts" / "smoke.sh"
PULL_SCRIPT = REPO_ROOT / "scripts" / "pull_results.sh"


def run_help(script: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(script), "--help"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )


class ConsolidatedScriptInterfaceTest(unittest.TestCase):
    def test_build_exposes_operator_and_task_selectors(self) -> None:
        result = run_help(BUILD_SCRIPT)
        self.assertEqual(result.returncode, 0, result.stderr)
        for option in ("--operator-set", "--module", "--operator", "--tasks", "--all"):
            self.assertIn(option, result.stdout)

    def test_performance_exposes_fixed_scale_and_selectors(self) -> None:
        result = run_help(PERFORMANCE_SCRIPT)
        self.assertEqual(result.returncode, 0, result.stderr)
        for option in ("--operator-set", "--module", "--operator", "--task", "--scale"):
            self.assertIn(option, result.stdout)
        self.assertIn("L1|L2|L3|L4|L5|L6|all", result.stdout)
        self.assertIn("--case-set SET", result.stdout)
        self.assertIn("--frozen-baseline PATH", result.stdout)

    def test_performance_defaults_to_full_correctness_protocol(self) -> None:
        source = PERFORMANCE_SCRIPT.read_text(encoding="utf-8")
        self.assertIn('CASE_SET="full"', source)
        self.assertIn('case_set == "full"', source)
        self.assertIn("NOT_REPORTED", source)

    def test_demo_batches_task_scales_in_one_process(self) -> None:
        source = PERFORMANCE_SCRIPT.read_text(encoding="utf-8")
        self.assertIn("run_task_batch", source)
        self.assertIn("--scale-level all", source)
        for relative in (
            "demo/task1_radar/task1_common.hpp",
            "demo/task2_features/task2_common.hpp",
        ):
            task_source = (REPO_ROOT / relative).read_text(encoding="utf-8")
            self.assertIn("all_scale_levels", task_source)

    def test_performance_rejects_custom_scale_without_building(self) -> None:
        result = subprocess.run(
            [str(PERFORMANCE_SCRIPT), "--scale", "custom", "--no-build"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--scale", result.stderr)

    def test_smoke_is_a_correctness_entrypoint(self) -> None:
        result = run_help(SMOKE_SCRIPT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("correctness", result.stdout)
        self.assertIn("--all", result.stdout)

    def test_pull_results_has_no_report_promotion_mode(self) -> None:
        result = run_help(PULL_SCRIPT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--sync-reports", result.stdout)
        self.assertNotIn("--promote-reports", result.stdout)


if __name__ == "__main__":
    unittest.main()
