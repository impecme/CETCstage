#!/usr/bin/env python3

"""Regression tests for the V7 final-evidence summarizer."""

from __future__ import annotations

import csv
import importlib.util
import json
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/platform/finalize_v7_delivery.py"
SPEC = importlib.util.spec_from_file_location("finalize_v7_delivery", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ValidateStatusTest(unittest.TestCase):
    def write_status(
        self,
        directory: str,
        *,
        registry_detail: str = "81 operators",
        dtype_detail: str = "compatibility gaps",
        task_steps_detail: str = "14 calculation steps",
    ) -> Path:
        status = Path(directory) / "status.tsv"
        status.write_text(
            "phase\tcase\trc\tdetail\n"
            f"audit\tregistry\t0\t{registry_detail}\n"
            f"audit\tdtype\t0\t{dtype_detail}\n"
            f"audit\ttask_steps\t0\t{task_steps_detail}\n"
            "final\toverall\t0\tV7-0008 phase=both five-minute demo\n",
            encoding="utf-8",
        )
        return status

    def expected(self) -> dict[tuple[str, str], tuple[int, str]]:
        return {
            ("audit", "registry"): (0, "81 operators"),
            ("audit", "dtype"): (0, "compatibility gaps"),
            ("audit", "task_steps"): (0, "14 calculation steps"),
        }

    def test_accepts_exact_gate_details(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status = self.write_status(directory)
            indexed = MODULE.validate_status(status, self.expected())
            self.assertEqual(indexed[("audit", "registry")]["detail"], "81 operators")

    def assert_false_detail_rejected(self, **details: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status = self.write_status(directory, **details)
            with self.assertRaisesRegex(ValueError, "status detail mismatch"):
                MODULE.validate_status(status, self.expected())

    def test_rejects_success_rc_with_false_registry_detail(self) -> None:
        self.assert_false_detail_rejected(registry_detail="0 operators")

    def test_rejects_success_rc_with_false_dtype_detail(self) -> None:
        self.assert_false_detail_rejected(dtype_detail="999 compatibility gaps")

    def test_rejects_success_rc_with_false_task_step_detail(self) -> None:
        self.assert_false_detail_rejected(task_steps_detail="0 calculation steps")

    def test_exact_status_rejects_unexpected_rows(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status = self.write_status(directory)
            with self.assertRaisesRegex(ValueError, "status row set mismatch"):
                MODULE.validate_status(status, self.expected(), exact=True)

    def test_rejects_forged_repeat_detail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            status = Path(directory) / "status.tsv"
            status.write_text(
                "phase\tcase\trc\tdetail\n"
                "task1_ab\tbaseline_L3\t0\tFORGED_DETAIL\n",
                encoding="utf-8",
            )
            expected = {("task1_ab", "baseline_L3"): (0, "repeat=5")}
            with self.assertRaisesRegex(ValueError, "status detail mismatch"):
                MODULE.validate_status(status, expected, exact=True)


class MetricsEvidenceTest(unittest.TestCase):
    def write_metrics(self, directory: str, **changes: object) -> Path:
        payload = {
            "scenario": {"scale_level": 1},
            "validation": {
                "pass": True,
                "checks": [{"name": "numeric", "pass": True, "value": 0.0, "limit": 1.0}],
            },
            "repeat_runs": [
                {"index": 1, "pass": True, "business_numeric_pass": True, "gpu_total_ms": 1.0}
            ],
        }
        payload.update(changes)
        path = Path(directory) / "latest_metrics.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def validate(self, path: Path) -> dict[str, object]:
        return MODULE.validate_metrics_evidence(
            path,
            expected_level=1,
            expected_repeats=1,
            expected_pass=True,
            label="fixture",
        )

    def test_accepts_nonempty_strict_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(len(self.validate(self.write_metrics(directory))["repeat_runs"]), 1)

    def test_rejects_empty_checks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            validation = {"pass": True, "checks": []}
            with self.assertRaisesRegex(ValueError, "checks are empty"):
                self.validate(self.write_metrics(directory, validation=validation))

    def test_rejects_empty_repeats(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "repeat count mismatch"):
                self.validate(self.write_metrics(directory, repeat_runs=[]))

    def test_rejects_truthy_non_boolean(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            validation = {
                "pass": "true",
                "checks": [{"name": "numeric", "pass": True, "value": 0.0, "limit": 1.0}],
            }
            with self.assertRaisesRegex(ValueError, "must be JSON true"):
                self.validate(self.write_metrics(directory, validation=validation))

    def test_rejects_failed_subcheck_under_passed_summary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            validation = {
                "pass": True,
                "checks": [{"name": "numeric", "pass": False, "value": 2.0, "limit": 1.0}],
            }
            with self.assertRaisesRegex(ValueError, "validation check failed"):
                self.validate(self.write_metrics(directory, validation=validation))

    def test_rejects_passed_check_whose_value_exceeds_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            validation = {
                "pass": True,
                "checks": [{"name": "numeric", "pass": True, "value": 999.0, "limit": 1.0}],
            }
            with self.assertRaisesRegex(ValueError, "contradicts value/limit"):
                self.validate(self.write_metrics(directory, validation=validation))

    def test_rejects_negative_raw_error_even_when_check_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            error = {"mixed_error": -1.0, "max_abs": 0.0, "max_rel": 0.0, "rmse": 0.0}
            with self.assertRaisesRegex(ValueError, "negative signal_error.mixed_error"):
                self.validate(self.write_metrics(directory, signal_error=error))

    def test_duplicate_json_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "duplicate.json"
            path.write_text('{"status": "passed", "status": "failed"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                MODULE.read_json(path)


class WallEvidenceTest(unittest.TestCase):
    def test_rejects_evidence_defined_wall_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wall = Path(directory) / "wall_seconds.txt"
            wall.write_text("999", encoding="utf-8")
            summary = {"seconds": 999, "limit_seconds": 1000, "reserve_seconds": 1}
            with self.assertRaisesRegex(ValueError, "wall limit mismatch"):
                MODULE.validate_wall_evidence(wall, summary)


class DemoTaskGateTest(unittest.TestCase):
    def test_rejects_self_consistent_task1_median_above_frozen_gate(self) -> None:
        metrics = {
            "repeat_runs": [
                {"gpu_total_ms": 5.0},
                {"gpu_total_ms": 5.0},
                {"gpu_total_ms": 5.0},
            ],
            "timings": {"step": {"gpu_ms": 1.0}},
        }
        summary = {
            "validation_pass": True,
            "repeat_count": 3,
            "gpu_total_median_ms": 5.0,
            "gpu_total_min_ms": 5.0,
            "gpu_total_max_ms": 5.0,
            "steps": {"step": 1.0},
        }
        with mock.patch.object(MODULE, "validate_metrics_evidence", return_value=metrics):
            with self.assertRaisesRegex(ValueError, "frozen performance gate failed"):
                MODULE.validate_task_demo(Path("unused"), "task1_radar", summary)


class Top30EvidenceTest(unittest.TestCase):
    def fixture(self, directory: str, speedup: float) -> tuple[Path, dict[str, object], set[str]]:
        root = Path(directory)
        target = root / "demo/top30/latest_all_ops_scale_benchmark.csv"
        target.parent.mkdir(parents=True)
        fieldnames = [
            "module",
            "operator",
            "status",
            "pass",
            "return_code",
            "scale_value",
            "scale_family",
            "cpu_median_ms",
            "gpu_e2e_median_ms",
            "gpu_e2e_speedup",
            "mixed_error",
            "error_note",
        ]
        operators = {f"module/operator_{index:02d}" for index in range(30)}
        with target.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames)
            writer.writeheader()
            for operator in sorted(operators):
                module, name = operator.split("/")
                writer.writerow(
                    {
                        "module": module,
                        "operator": name,
                        "status": "passed",
                        "pass": "true",
                        "return_code": 0,
                        "scale_value": 1,
                        "scale_family": "fixture",
                        "cpu_median_ms": speedup,
                        "gpu_e2e_median_ms": 1.0,
                        "gpu_e2e_speedup": speedup,
                        "mixed_error": 0.0,
                        "error_note": "cpu_baseline=reused",
                    }
                )
        rows = [
            {
                "operator": operator,
                "status": "passed",
                "pass": True,
                "scale_value": 1,
                "scale_family": "fixture",
                "cpu_median_ms": speedup,
                "gpu_e2e_median_ms": 1.0,
                "gpu_e2e_speedup": speedup,
                "mixed_error": 0.0,
                "baseline_reused": True,
            }
            for operator in sorted(operators)
        ]
        summary = {
            "count": 30,
            "passed": 30,
            "baseline_reused": 30,
            "minimum_speedup": speedup,
            "median_speedup": speedup,
            "geometric_mean_speedup": speedup,
            "maximum_speedup": speedup,
            "gpu_e2e_sum_ms": 30.0,
            "rows": rows,
        }
        return root, summary, operators

    def test_accepts_raw_speedups_above_frozen_gates(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, summary, operators = self.fixture(directory, 25.0)
            result = MODULE.validate_top30(root, summary, operators)
            self.assertEqual(result["count"], 30)

    def test_rejects_self_consistent_half_speed_summary(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root, summary, operators = self.fixture(directory, 0.5)
            with self.assertRaisesRegex(ValueError, "minimum speedup gate failed"):
                MODULE.validate_top30(root, summary, operators)


class ArchiveAndReadbackTest(unittest.TestCase):
    def test_rejects_empty_archive_and_console(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            empty = root / "empty"
            empty.write_bytes(b"")
            with self.assertRaisesRegex(ValueError, "empty evidence file"):
                MODULE.validate_archive(empty, root, ("status.tsv",))
            with self.assertRaisesRegex(ValueError, "empty evidence file"):
                MODULE.validate_console(empty, {"RC=0"})

    def test_archive_members_must_match_extracted_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "run"
            root.mkdir()
            evidence = root / "status.tsv"
            evidence.write_text("original", encoding="utf-8")
            archive = base / "run.tar.gz"
            with tarfile.open(archive, "w:gz") as handle:
                handle.add(root, arcname=root.name)
            MODULE.validate_archive(archive, root, ("status.tsv",))
            evidence.write_text("changed", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "archive/extracted evidence mismatch"):
                MODULE.validate_archive(archive, root, ("status.tsv",))

    def test_console_conflicting_terminal_marker_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "console.log"
            path.write_text("RC=1\nRC=0\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "conflicting terminal marker"):
                MODULE.validate_console(path, {"RC=0"})

    def test_frozen_hash_anchor_rejects_bundle_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "cetc_v7_0005_task2_fft_20260716_155059"
            root.mkdir()
            archive = base / "cetc_v7_0005_latest.tar.gz"
            console = base / "cetc_v7_0005_console.log"
            archive.write_bytes(b"frozen archive")
            console.write_text("frozen console\n", encoding="utf-8")
            entry = {
                "root_name": root.name,
                "archive_name": archive.name,
                "archive_sha256": MODULE.sha256(archive),
                "console_name": console.name,
                "console_sha256": MODULE.sha256(console),
            }
            MODULE.validate_frozen_run_inputs("V7-0005", root, archive, console, entry)
            archive.write_bytes(b"replacement archive")
            with self.assertRaisesRegex(ValueError, "archive SHA256 mismatch"):
                MODULE.validate_frozen_run_inputs("V7-0005", root, archive, console, entry)

    def test_readback_id_is_frozen_and_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / "source"
            (source / "demo/task1_radar").mkdir(parents=True)
            (source / "scripts/platform").mkdir(parents=True)
            source_task = source / "demo/task1_radar/task1_radar_demo.cpp"
            source_runner = source / "scripts/platform/run_v7_5_task1_buffer_reuse.sh"
            source_task.write_text("task", encoding="utf-8")
            source_runner.write_text("runner", encoding="utf-8")
            readback = base / "cetc_v7_0011_deploy_readback"
            readback.mkdir()
            (readback / "task1_radar_demo.cpp").write_text("task", encoding="utf-8")
            (readback / "run_v7_5_task1_buffer_reuse.sh").write_text("runner", encoding="utf-8")
            manifest_entry = {
                "root_name": "cetc_v7_0011_deploy_readback",
                "standalone_execution_manifest_present": False,
                "files": {
                    "task1_radar_demo.cpp": MODULE.sha256(source_task),
                    "run_v7_5_task1_buffer_reuse.sh": MODULE.sha256(source_runner),
                },
            }
            result = MODULE.validate_readback(readback, source, manifest_entry)
            self.assertEqual(result["execution_id"], "V7-0011")
            self.assertFalse(result["standalone_execution_manifest_present"])
            renamed = base / "cetc_v7_9999_deploy_readback"
            readback.rename(renamed)
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                MODULE.validate_readback(renamed, source, manifest_entry)

    def test_readback_symlink_is_not_accepted_as_a_regular_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            source = base / "source"
            (source / "demo/task1_radar").mkdir(parents=True)
            (source / "scripts/platform").mkdir(parents=True)
            source_task = source / "demo/task1_radar/task1_radar_demo.cpp"
            source_runner = source / "scripts/platform/run_v7_5_task1_buffer_reuse.sh"
            source_task.write_text("task", encoding="utf-8")
            source_runner.write_text("runner", encoding="utf-8")
            readback = base / "cetc_v7_0011_deploy_readback"
            readback.mkdir()
            (readback / "task1_radar_demo.cpp").symlink_to(source_task)
            (readback / "run_v7_5_task1_buffer_reuse.sh").write_text("runner", encoding="utf-8")
            entry = {
                "root_name": readback.name,
                "standalone_execution_manifest_present": False,
                "files": {
                    "task1_radar_demo.cpp": MODULE.sha256(source_task),
                    "run_v7_5_task1_buffer_reuse.sh": MODULE.sha256(source_runner),
                },
            }
            with self.assertRaisesRegex(ValueError, "non-regular evidence file"):
                MODULE.validate_readback(readback, source, entry)


class CombinedBufferTest(unittest.TestCase):
    def fixture(self, l6_candidate: tuple[float, float]) -> tuple[dict[str, object], dict[str, object]]:
        first = {
            "baseline": {"L3": [10.0] * 5, "L5": [20.0] * 5, "L6": [40.0] * 5},
            "candidate": {"L3": [9.0] * 5, "L5": [18.0] * 5, "L6": [l6_candidate[0]] * 5},
        }
        second = {
            "baseline": {"L3": [12.0] * 5, "L5": [22.0] * 5, "L6": [44.0] * 5},
            "candidate": {"L3": [10.0] * 5, "L5": [19.0] * 5, "L6": [l6_candidate[1]] * 5},
        }
        return first, second

    def test_combined_gain_is_recomputed_from_twenty_raw_values(self) -> None:
        first, second = self.fixture((41.0, 45.0))
        with mock.patch.object(MODULE, "validate_buffer_round", side_effect=[first, second]):
            result = MODULE.derive_combined_buffer_rejection(Path("first"), Path("second"))
        self.assertAlmostEqual(result["scales"]["L6"]["gain_fraction"], (42.0 - 43.0) / 42.0)

    def test_combined_l6_non_regression_invalidates_rejection(self) -> None:
        first, second = self.fixture((30.0, 32.0))
        with mock.patch.object(MODULE, "validate_buffer_round", side_effect=[first, second]):
            with self.assertRaisesRegex(ValueError, "no longer regresses"):
                MODULE.derive_combined_buffer_rejection(Path("first"), Path("second"))


class HistoricalTimingGateExceptionTest(unittest.TestCase):
    def test_only_frozen_task2_l1_stability_exception_is_accepted(self) -> None:
        policy = MODULE.EXPECTED_ACCEPTANCE_POLICY[
            "historical_timing_gate_exception_policy"
        ][0]
        exception = {**policy, "value": 0.5, "limit": 0.35}
        MODULE.validate_historical_timing_gate_exceptions([exception])

        for field, replacement in (
            ("case", "task2_smoke/L6"),
            ("check", "gpu_total_ms"),
        ):
            with self.subTest(field=field):
                altered = {**exception, field: replacement}
                with self.assertRaisesRegex(ValueError, "historical timing-gate exception"):
                    MODULE.validate_historical_timing_gate_exceptions([altered])


class PredecessorSummaryTest(unittest.TestCase):
    def test_v5_nested_all81_failure_is_not_hidden_by_top_level_pass(self) -> None:
        summary = {"status": "passed", "all81": {"status": "failed"}}
        with self.assertRaisesRegex(ValueError, "all81 status failed"):
            MODULE.validate_v5_summary(summary)

    def test_actual_v5_files_must_match_frozen_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            markdown = root / "summary.md"
            summary_json = root / "summary.json"
            markdown.write_text("frozen markdown\n", encoding="utf-8")
            summary_json.write_text('{"status":"passed"}\n', encoding="utf-8")
            expected = {
                "v5_5_summary_md_sha256": MODULE.sha256(markdown),
                "v5_5_summary_json_sha256": MODULE.sha256(summary_json),
            }
            MODULE.validate_v5_report_hashes(markdown, summary_json, expected)
            summary_json.write_text('{"status":"passed","forged":true}\n', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "actual V5.5 predecessor JSON SHA256 mismatch"):
                MODULE.validate_v5_report_hashes(markdown, summary_json, expected)

    def test_actual_v6_markdown_and_json_must_match_frozen_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            markdown = root / "summary.md"
            summary_json = root / "summary.json"
            report_readme = root / "README.md"
            markdown.write_text("frozen V6 markdown\n", encoding="utf-8")
            summary_json.write_text('{"schema_version":"v6_final_summary_v2"}\n', encoding="utf-8")
            report_readme.write_text("frozen report index\n", encoding="utf-8")
            expected = {
                "v6_final_summary_md_sha256": MODULE.sha256(markdown),
                "v6_final_summary_json_sha256": MODULE.sha256(summary_json),
                "report_root_readme_sha256": MODULE.sha256(report_readme),
            }
            MODULE.validate_v6_report_hashes(markdown, summary_json, report_readme, expected)

            markdown.write_text("forged V6 markdown\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "actual V6 predecessor Markdown SHA256 mismatch"):
                MODULE.validate_v6_report_hashes(markdown, summary_json, report_readme, expected)

            markdown.write_text("frozen V6 markdown\n", encoding="utf-8")
            summary_json.write_text(
                '{"schema_version":"v6_final_summary_v2","forged":true}\n',
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "actual V6 predecessor JSON SHA256 mismatch"):
                MODULE.validate_v6_report_hashes(markdown, summary_json, report_readme, expected)

            summary_json.write_text('{"schema_version":"v6_final_summary_v2"}\n', encoding="utf-8")
            report_readme.write_text("forged report index\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "actual final-report README SHA256 mismatch"):
                MODULE.validate_v6_report_hashes(markdown, summary_json, report_readme, expected)

    def test_v6_type_policy_drift_is_rejected(self) -> None:
        source_root = SCRIPT.parents[2]
        target = source_root / "scripts/test/operator_type_contracts.json"
        real_sha256 = MODULE.sha256

        def drifted_sha256(path: Path) -> str:
            if path == target:
                return "0" * 64
            return real_sha256(path)

        with mock.patch.object(MODULE, "sha256", side_effect=drifted_sha256):
            with self.assertRaisesRegex(
                ValueError,
                "V6 tracked policy SHA256 mismatch: scripts/test/operator_type_contracts.json",
            ):
                MODULE.validate_v6_evidence_manifest(source_root)

    def test_v6_true_error_rows_are_exactly_coherence_l1_through_l5(self) -> None:
        policy = {
            "benchmark_true_error_threshold": 0.01,
            "passed_true_error_diagnostic_policy": [
                {
                    "module": "spectral",
                    "operator": "coherence",
                    "scale_levels": [1, 2, 3, 4, 5],
                    "scope": "fixture",
                }
            ],
        }
        rows = [
            {
                "module": "spectral",
                "operator": "coherence",
                "scale_level": level,
                "mixed_error": 0.02,
                "error_class": "true-error",
            }
            for level in range(1, 6)
        ]
        diagnostics = {
            "error_class_counts": {
                "ok": 191,
                "performance-bound": 290,
                "true-error": 5,
            },
            "passed_true_error_rows": rows,
            "policy": policy["passed_true_error_diagnostic_policy"],
        }
        MODULE.validate_v6_true_error_diagnostics(diagnostics, policy)

        for field, replacement in (("scale_level", 6), ("operator", "periodogram")):
            with self.subTest(field=field):
                altered_row = {**rows[-1], field: replacement}
                altered = {**diagnostics, "passed_true_error_rows": rows[:-1] + [altered_row]}
                with self.assertRaisesRegex(ValueError, "true-error diagnostic identity set mismatch"):
                    MODULE.validate_v6_true_error_diagnostics(altered, policy)


class SourceFingerprintTest(unittest.TestCase):
    def fixture(self, directory: str) -> tuple[Path, Path]:
        base = Path(directory)
        source = base / "source"
        evidence = base / "run"
        fingerprint = evidence / "fingerprint/candidate_sources.sha256"
        fingerprint.parent.mkdir(parents=True)
        lines = []
        for relative in MODULE.V7_0008_SOURCE_FINGERPRINT_PATHS:
            path = source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(f"current {relative}\n", encoding="utf-8")
            if relative == MODULE.V7_0008_SUPERSEDED_SOURCE_PATH:
                old = base / "old_task1.cpp"
                old.write_text("superseded task1\n", encoding="utf-8")
                digest = MODULE.sha256(old)
            else:
                digest = MODULE.sha256(path)
            lines.append(f"{digest}  {relative}")
        fingerprint.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return evidence, source

    def test_v7_0008_sources_match_except_frozen_task1_supersession(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence, source = self.fixture(directory)
            result = MODULE.validate_v7_0008_source_fingerprint(evidence, source)
            self.assertEqual(result["matched_current_source_count"], 8)
            self.assertEqual(result["superseded_source"], MODULE.V7_0008_SUPERSEDED_SOURCE_PATH)

    def test_current_task2_source_tamper_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence, source = self.fixture(directory)
            target = source / "demo/task2_features/task2_features_demo.cpp"
            target.write_text("tampered\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "differs from V7-0008 fingerprint"):
                MODULE.validate_v7_0008_source_fingerprint(evidence, source)

    def test_duplicate_source_fingerprint_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            evidence, source = self.fixture(directory)
            fingerprint = evidence / "fingerprint/candidate_sources.sha256"
            first = fingerprint.read_text(encoding="utf-8").splitlines()[0]
            with fingerprint.open("a", encoding="utf-8") as handle:
                handle.write(first + "\n")
            with self.assertRaisesRegex(ValueError, "duplicate V7-0008 source fingerprint path"):
                MODULE.validate_v7_0008_source_fingerprint(evidence, source)


class RegistryEvidenceTest(unittest.TestCase):
    def test_registry_names_must_match_frozen_operator_policy(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            registry = Path(directory) / "registry.tsv"
            registry.write_text("fake\toperator\ttarget\ttest/path\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "operator set mismatch"):
                MODULE.validate_registry(registry, {"real/operator"})

    def test_all81_count_comes_from_unique_execution_lines(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "all81.log"
            log.write_text(
                "[module/one] PASS  accuracy_cases=2  perf_cases=1\n"
                "[module/two] PASS  accuracy_cases=3  perf_cases=1\n"
                "[cusignal-test] summary: passed 2/2\n",
                encoding="utf-8",
            )
            self.assertEqual(MODULE.validate_all81_log(log, {"module/one", "module/two"}), 2)
            log.write_text(
                "[module/one] PASS  accuracy_cases=2  perf_cases=1\n"
                "[cusignal-test] summary: passed 2/2\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "execution operator set mismatch"):
                MODULE.validate_all81_log(log, {"module/one", "module/two"})


class EvidenceManifestTest(unittest.TestCase):
    def test_repository_manifest_matches_code_policy_and_tracked_files(self) -> None:
        source_root = SCRIPT.parents[2]
        manifest_path = source_root / "scripts/platform/v7_final_evidence_manifest.json"
        manifest = MODULE.load_evidence_manifest(manifest_path, source_root)
        self.assertEqual(set(manifest["runs"]), MODULE.EXPECTED_RUN_IDS)

    def test_cli_input_path_rejects_symlinks_before_resolution(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            target = base / "target"
            target.write_text("evidence", encoding="utf-8")
            link = base / "link"
            link.symlink_to(target)
            with self.assertRaisesRegex(ValueError, "must not contain symlinks"):
                MODULE.canonical_input_path(link, "fixture")

    def test_report_tree_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "reports"
            root.mkdir()
            target = Path(directory) / "outside"
            target.write_text("outside\n", encoding="utf-8")
            (root / "summary.json").symlink_to(target)
            with self.assertRaisesRegex(ValueError, "report tree contains symlink"):
                MODULE.report_file_inventory(root)

    def test_demo_archive_policy_binds_raw_all81_and_every_task_scale(self) -> None:
        files = set(MODULE.archive_evidence_files("V7-0008"))
        self.assertIn("logs/all81_full.log", files)
        self.assertIn("demo/wall_seconds.txt", files)
        self.assertIn("fingerprint/candidate_sources.sha256", files)
        for task in ("task1_radar", "task2_features"):
            for level in range(1, 7):
                self.assertIn(f"prepare/task_sweep/{task}/L{level}/latest_metrics.json", files)


if __name__ == "__main__":
    unittest.main()
