#!/usr/bin/env python3
"""Regression checks for the formal task-performance report workflow."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
VALIDATE_SCRIPT = REPO_ROOT / "scripts" / "validate.sh"
UNIFIED_SCALE_SCRIPT = REPO_ROOT / "scripts" / "unified_scale_benchmark.sh"


class TaskReportProtocolScriptTest(unittest.TestCase):
    def test_validation_uses_formal_scales_before_regular_final_run(self) -> None:
        text = VALIDATE_SCRIPT.read_text(encoding="utf-8")
        formal_call = 'scripts/unified_scale_benchmark.sh'
        regular_call = 'scripts/demo.sh --build-dir "${BUILD_DIR}" --no-build --repeat 5'

        self.assertIn(formal_call, text)
        self.assertIn('--output-root "${PROJECT_ROOT}/data/.reports_staging/demo"', text)
        self.assertIn(regular_call, text)
        self.assertLess(text.index(formal_call), text.index(regular_call))
        self.assertNotIn(
            'scripts/demo.sh --build-dir "${BUILD_DIR}" --no-build --repeat 5 --scale-sweep',
            text,
        )

    def test_formal_scale_runner_exposes_staging_output_option(self) -> None:
        result = subprocess.run(
            ["bash", str(UNIFIED_SCALE_SCRIPT), "--help"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--output-root DIR", result.stdout)


if __name__ == "__main__":
    unittest.main()
