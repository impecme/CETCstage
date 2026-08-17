import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class InputRefreshProtocolTests(unittest.TestCase):
    def test_public_operator_harnesses_use_refresh_audit(self):
        files = [
            "tests/unit/bsplines/bsplines_test_support.cu",
            "tests/unit/correlate/correlate_test_support.cu",
            "tests/unit/demod/demod_test_support.cu",
            "tests/unit/estimation/estimation_test_support.cu",
            "tests/unit/filter_design/filter_design_test_support.cu",
            "tests/unit/filtering/filtering_test_support.cu",
            "tests/unit/peak_finding/peak_finding_test_support.cu",
            "tests/unit/radartools/radartools_test_support.cu",
            "tests/unit/spectral/spectral_test_support.cu",
            "tests/unit/waveforms/waveform_test_support.cu",
            "tests/unit/wavelets/wavelets_test_support.cu",
            "tests/unit/windows/windows_test_support.cu",
        ]
        for relative in files:
            text = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn(
                "InputRefreshRun",
                text,
                msg=f"{relative} has no per-run input refresh audit",
            )
            self.assertIn(
                "note_iteration",
                text,
                msg=f"{relative} does not count warmup/repeat iterations",
            )

    def test_kernel_paths_do_not_use_only_prepared_input(self):
        checks = {
            "tests/unit/bsplines/bsplines_test_support.cu": r"gpu_kernel_perf[\s\S]{0,1200}from_host",
            "tests/unit/demod/demod_test_support.cu": r"gpu_e2e_perf[\s\S]{0,1600}from_host",
            "tests/unit/correlate/correlate_test_support.cu": r"fresh_left[\s\S]{0,1200}from_host",
        }
        for relative, pattern in checks.items():
            text = (ROOT / relative).read_text(encoding="utf-8")
            self.assertRegex(
                text,
                re.compile(pattern),
                msg=f"{relative} still appears to reuse a prepared input in its measured path",
            )


if __name__ == "__main__":
    unittest.main()
