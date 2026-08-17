#!/usr/bin/env python3
"""Regression checks for scale-sensitive operator performance inputs."""

from pathlib import Path
import sys
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from operator_workload_contract import expected_perf_samples, validate_perf_report  # noqa: E402


class OperatorInputContractTest(unittest.TestCase):
    def test_cmplx_sort_reads_manifest_sample_count(self) -> None:
        source = (REPO_ROOT / "tests/unit/filter_design/filter_design_test_support.cu").read_text()
        self.assertIn("const std::size_t sample_count = static_cast<std::size_t>(test_case.sample_count);", source)
        self.assertNotIn("constexpr std::size_t sample_count = 4096;", source)
        self.assertNotIn('get_optional_int(object, "sample_count", 4096)', source)

    def test_firfilter_zi_uses_manifest_filter_order(self) -> None:
        source = (REPO_ROOT / "tests/unit/filtering/filtering_test_support.cu").read_text()
        start = source.index('if (op == "firfilter_zi")')
        end = source.index('if (op == "lfilter_zi")', start)
        block = source[start:end]
        self.assertIn("test_case.filter_order", block)
        self.assertIn("make_lowpass_like_taps(order + 1)", block)
        self.assertNotIn("make_lowpass_like_taps(33)", block)

    def test_gpu_only_perf_does_not_leave_known_scale_samples_at_zero(self) -> None:
        filter_design = (REPO_ROOT / "tests/unit/filter_design/filter_design_test_support.cu").read_text()
        wavelets = (REPO_ROOT / "tests/unit/wavelets/wavelets_test_support.cu").read_text()
        self.assertIn('op == "cmplx_sort"', filter_design)
        self.assertIn('op == "qmf"', wavelets)
        self.assertNotIn("report.samples = test_case.numtaps > 0 ? static_cast<std::size_t>(test_case.numtaps) : 0;", filter_design)
        self.assertNotIn("report.samples = 0;", wavelets)

    def test_known_semantic_sample_counts_are_checked(self) -> None:
        manifest = {"perf_cases": [{"id": "perf", "sample_count": 262144}]}
        payload = {"cases": [{"case_id": "perf", "category": "perf", "samples": 4096}]}
        self.assertEqual(expected_perf_samples("filter_design/cmplx_sort", manifest["perf_cases"][0]), 262144)
        self.assertTrue(validate_perf_report("filter_design/cmplx_sort", manifest, payload))


if __name__ == "__main__":
    unittest.main()
