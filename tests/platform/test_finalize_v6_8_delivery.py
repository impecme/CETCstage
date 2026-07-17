#!/usr/bin/env python3

"""Regression tests for the V6 final-evidence summarizer."""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from contextlib import ExitStack
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[2] / "scripts/platform/finalize_v6_8_delivery.py"
SPEC = importlib.util.spec_from_file_location("finalize_v6_8_delivery", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class TrustAnchorTest(unittest.TestCase):
    def test_repository_manifest_matches_code_policy(self) -> None:
        source_root = SCRIPT.parents[2]
        path = source_root / "scripts/platform/v6_final_evidence_manifest.json"
        manifest = MODULE.load_evidence_manifest(path, source_root)
        self.assertEqual(set(manifest["runs"]), {"V6-0138", "V6-0141"})

    def test_frozen_hash_rejects_archive_replacement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "run"
            root.mkdir()
            archive = base / "archive.tar.gz"
            console = base / "console.log"
            archive.write_bytes(b"frozen archive")
            console.write_text("frozen console\n", encoding="utf-8")
            entry = {
                "root_name": root.name,
                "archive_name": archive.name,
                "archive_sha256": MODULE.sha256(archive),
                "console_name": console.name,
                "console_sha256": MODULE.sha256(console),
            }
            MODULE.validate_frozen_run_inputs("V6-test", root, archive, console, entry)
            archive.write_bytes(b"replacement archive")
            with self.assertRaisesRegex(ValueError, "archive SHA256 mismatch"):
                MODULE.validate_frozen_run_inputs("V6-test", root, archive, console, entry)

    def test_symlink_is_rejected_before_cli_resolution(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            target = base / "target"
            target.write_text("evidence", encoding="utf-8")
            link = base / "link"
            link.symlink_to(target)
            with self.assertRaisesRegex(ValueError, "must not contain symlinks"):
                MODULE.canonical_input_path(link, "fixture")

    def test_empty_sha256_inventory_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "inventory.sha256"
            path.write_text("", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "empty fixture inventory"):
                MODULE.read_sha256_inventory(path, "fixture inventory")

    def test_duplicate_sha256_inventory_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "inventory.sha256"
            digest = "0" * 64
            path.write_text(
                f"{digest}  src/example.cu\n{digest}  src/example.cu\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "duplicate fixture inventory path"):
                MODULE.read_sha256_inventory(path, "fixture inventory")

    def test_preexisting_v7_reports_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            report_root = base / "reports"
            args = SimpleNamespace(
                source_root=str(SCRIPT.parents[2]),
                evidence_manifest="",
                preflight_root=str(base / "preflight"),
                performance_root=str(base / "performance"),
                preflight_archive=str(base / "preflight.tar.gz"),
                preflight_console=str(base / "preflight.log"),
                performance_archive=str(base / "performance.tar.gz"),
                performance_console=str(base / "performance.log"),
                v5_summary_markdown=str(report_root / "zhongkexin/v5_5_final/summary.md"),
                v5_summary_json=str(report_root / "zhongkexin/v5_5_final/summary.json"),
                v5_source_dir=None,
                report_root=str(report_root),
                output_dir=str(report_root / "zhongkexin/v6_final"),
            )
            manifest = {
                "runs": {
                    "V6-0138": {"archive_name": "preflight.tar.gz"},
                    "V6-0141": {"archive_name": "performance.tar.gz"},
                }
            }
            preexisting_v7 = {
                report_root / "zhongkexin/v7_final/summary.md",
                report_root / "zhongkexin/v7_final/summary.json",
            }
            with ExitStack() as stack:
                stack.enter_context(mock.patch.object(MODULE, "parse_args", return_value=args))
                stack.enter_context(mock.patch.object(MODULE, "load_evidence_manifest", return_value=manifest))
                stack.enter_context(mock.patch.object(MODULE, "load_operator_policy", return_value=set()))
                stack.enter_context(mock.patch.object(MODULE, "load_task_contract_policy", return_value={}))
                stack.enter_context(mock.patch.object(MODULE, "load_type_contract_policy", return_value={}))
                stack.enter_context(mock.patch.object(MODULE, "validate_frozen_run_inputs"))
                stack.enter_context(mock.patch.object(MODULE, "validate_archive", return_value="0" * 64))
                stack.enter_context(mock.patch.object(MODULE, "validate_console", return_value="0" * 64))
                stack.enter_context(mock.patch.object(MODULE, "report_file_inventory", return_value=preexisting_v7))
                with self.assertRaisesRegex(ValueError, "unexpected pre-existing report files"):
                    MODULE.main()


class StructuredEvidenceTest(unittest.TestCase):
    def test_duplicate_json_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "duplicate.json"
            path.write_text('{"status": "passed", "status": "failed"}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                MODULE.read_json(path)

    def task1_metrics(self) -> dict[str, object]:
        policy = MODULE.TASK_CHECK_POLICY["task1_radar"]
        values = {
            "cpu_gpu_detection_match": 1.0,
            "gpu_matches_expected_detection": 1.0,
            "gpu_total_ms": 1.0,
            "pulse_compression_mixed_error": 0.0,
            "pulse_doppler_mixed_error": 0.0,
            "cfar_threshold_mixed_error": 0.0,
            "ambgfun_surface_mixed_error": 0.0,
            "invalid_input_checks": 1.0,
            "repeat_business_consistency": 1.0,
            "gpu_total_stability": 0.0,
            "gpu_free_memory_drift_mib": 0.0,
            "rss_current_drift_mib": 0.0,
        }
        checks = []
        for name in policy["check_names"]:
            limit = policy["constant_limits"].get(name)
            if limit is None:
                limit = policy["scale_limits"][name][0]
            checks.append(
                {
                    "name": name,
                    "pass": True,
                    "value": values[name],
                    "limit": limit,
                    "detail": "validated",
                }
            )
        zero_error = {"mixed_error": 0.0, "max_abs": 0.0, "max_rel": 0.0, "rmse": 0.0}
        return {
            "scenario": {"scale_level": 1},
            "consistency": {
                "cpu_gpu_detection_match": True,
                "gpu_matches_expected_detection": True,
            },
            "validation": {"pass": True, "checks": checks},
            "repeat_runs": [
                {
                    "index": 1,
                    "pass": True,
                    "business_numeric_pass": True,
                    "cpu_total_ms": 2.0,
                    "gpu_total_ms": 1.0,
                    "gpu_free_mib": 100.0,
                    "rss_current_mib": 10.0,
                }
            ],
            "timings": {"total": {"cpu_ms": 2.0, "gpu_ms": 1.0}},
            "pulse_compression_error": dict(zero_error),
            "pulse_doppler_error": dict(zero_error),
            "cfar_threshold_error": dict(zero_error),
            "ambgfun_surface_error": dict(zero_error),
        }

    def validate_task1(self, path: Path) -> dict[str, object]:
        return MODULE.validate_task_metrics(
            path,
            task="task1_radar",
            level=1,
            repeat=1,
            label="fixture",
        )

    def test_valid_task_check_fixture_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metrics.json"
            path.write_text(json.dumps(self.task1_metrics()), encoding="utf-8")
            self.assertTrue(self.validate_task1(path)["validation"]["pass"])

    def test_passed_check_cannot_exceed_its_limit(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metrics.json"
            payload = self.task1_metrics()
            check = payload["validation"]["checks"][3]
            check["value"] = 1.0
            payload["pulse_compression_error"]["mixed_error"] = 1.0
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "validation check failed"):
                self.validate_task1(path)

    def test_unknown_task_check_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metrics.json"
            payload = self.task1_metrics()
            payload["validation"]["checks"][0]["name"] = "forged_check"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "check topology mismatch"):
                self.validate_task1(path)

    def test_check_value_must_match_top_level_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metrics.json"
            payload = self.task1_metrics()
            payload["validation"]["checks"][3]["value"] = 5.0e-5
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "top-level error check"):
                self.validate_task1(path)

    def test_skipped_task_validation_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "metrics.json"
            payload = self.task1_metrics()
            payload["validation"]["checks"][2]["detail"] = "timing skipped"
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "skipped validation"):
                self.validate_task1(path)

    def test_task_comparison_is_derived_from_current_rows_and_frozen_baselines(self) -> None:
        totals = [
            {"mode": "warm", "task": "task1_radar", "scale_level": 6, "gpu_median_ms": 4.0},
            {"mode": "warm", "task": "task2_features", "scale_level": 6, "gpu_median_ms": 25.0},
        ]
        steps = []
        for task, baselines in MODULE.TASK_BASELINES.items():
            for metric in baselines:
                if metric == "total":
                    continue
                steps.append(
                    {
                        "mode": "warm",
                        "task": task,
                        "scale_level": 6,
                        "step": metric,
                        "gpu_e2e_ms": 1.0,
                    }
                )
        result = MODULE.derive_task_comparison(totals, steps)
        task1_total = next(row for row in result if row["task"] == "task1_radar" and row["metric"] == "total")
        self.assertEqual(task1_total["current_ms"], 4.0)
        self.assertAlmostEqual(
            task1_total["reduction_percent"],
            (MODULE.TASK_BASELINES["task1_radar"]["total"] - 4.0)
            / MODULE.TASK_BASELINES["task1_radar"]["total"]
            * 100.0,
        )

    def test_final_measurements_are_not_literals_in_the_summarizer(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        for literal in (
            "3.91998",
            "25.2926",
            "167.855",
            "97.534",
            "11.497",
            "2.481",
        ):
            self.assertNotIn(literal, source)

    def test_output_schema_is_v2(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn('"schema_version": "v6_final_summary_v2"', source)
        self.assertNotIn('"schema_version": "v6_final_summary_v1"', source)


class TopologyAndDiagnosticTest(unittest.TestCase):
    def benchmark_fixture(
        self,
    ) -> tuple[set[str], list[dict[str, str]], list[dict[str, object]]]:
        operators = {f"module{index:02d}/operator{index:02d}" for index in range(81)}
        rows: list[dict[str, str]] = []
        events: list[dict[str, object]] = [
            {
                "event": "run_start",
                "operator_count": 81,
                "platform": "ZHONGKEXIN",
                "repeat": 30,
                "run_id": "fixture-run",
                "scale_levels": [1, 2, 3, 4, 5, 6],
                "scale_profile": "default",
                "timestamp_unix": 0.0,
                "warmup": 5,
            }
        ]
        timestamp = 1.0
        for target_index, operator in enumerate(sorted(operators), start=1):
            module, name = operator.split("/", 1)
            for level in range(1, 7):
                row = {
                    "module": module,
                    "operator": name,
                    "scale_level": str(level),
                    "scale_value": str(level * 1024),
                    "scale_family": "fixture-scale",
                    "shape_note": "fixture",
                    "status": "passed",
                    "pass": "true",
                    "return_code": "0",
                    "warmup": "5",
                    "repeat": "30",
                    "gpu_e2e_median_ms": "1.0",
                    "gpu_kernel_median_ms": "0.5",
                    "cpu_median_ms": "2.0",
                    "gpu_e2e_speedup": "2.0",
                    "gpu_kernel_speedup": "4.0",
                    "gpu_e2e_min_ms": "0.9",
                    "gpu_e2e_max_ms": "1.1",
                    "mixed_error": "0.0",
                    "error_class": "performance-bound",
                    "run_id": "fixture-run",
                    "gpu_name": "fixture-gpu",
                }
                rows.append(row)
                common = {
                    "module": module,
                    "operator": name,
                    "run_id": "fixture-run",
                    "scale_family": "fixture-scale",
                    "scale_level": level,
                    "scale_value": level * 1024,
                    "target_count": 81,
                    "target_index": target_index,
                }
                events.append(
                    {
                        **common,
                        "event": "case_start",
                        "repeat": 30,
                        "timestamp_unix": timestamp,
                        "warmup": 5,
                    }
                )
                timestamp += 1.0
                events.append(
                    {
                        **common,
                        "duration_s": 1.0,
                        "event": "case_end",
                        "gpu_e2e_median_ms": "1.0",
                        "gpu_kernel_median_ms": "0.5",
                        "passed": True,
                        "return_code": 0,
                        "status": "passed",
                        "timestamp_unix": timestamp,
                    }
                )
                timestamp += 1.0
        events.extend(
            [
                {
                    "event": "manifests_restored",
                    "restored_count": 81,
                    "run_id": "fixture-run",
                    "timestamp_unix": timestamp,
                },
                {
                    "event": "run_end",
                    "failed_row_count": 0,
                    "row_count": 486,
                    "run_id": "fixture-run",
                    "status": "passed",
                    "timestamp_unix": timestamp + 1.0,
                },
            ]
        )
        return operators, rows, events

    def assert_progress_events_rejected(self, events: list[dict[str, object]]) -> None:
        operators, rows, _ = self.benchmark_fixture()
        with ExitStack() as stack:
            stack.enter_context(mock.patch.object(MODULE, "read_table", return_value=rows))
            stack.enter_context(mock.patch.object(MODULE, "read_json_lines", return_value=events))
            with self.assertRaisesRegex(ValueError, "benchmark progress event topology mismatch"):
                MODULE.validate_benchmark(Path("/fixture"), operators)

    def test_extra_progress_event_is_rejected(self) -> None:
        _, _, events = self.benchmark_fixture()
        events.insert(-1, {"event": "error", "message": "conflicting terminal"})
        self.assert_progress_events_rejected(events)

    def test_conflicting_duplicate_progress_event_is_rejected(self) -> None:
        _, _, events = self.benchmark_fixture()
        duplicate = dict(next(event for event in events if event["event"] == "case_end"))
        duplicate["status"] = "failed"
        events.insert(-1, duplicate)
        self.assert_progress_events_rejected(events)

    def test_operator_telemetry_sample_count_tampering_is_rejected(self) -> None:
        timestamp = "2026-01-01T00:00:01+00:00"
        sample_time = datetime.fromisoformat(timestamp).timestamp()
        samples = [
            {
                "timestamp": timestamp,
                "elapsed_s": "1.0",
                "gpu_index": "0",
                "used_mib": "100.0",
                "total_mib": "1000.0",
                "free_mib": "900.0",
                "util_percent": "0.0",
            }
        ]
        raw = {
            "available": True,
            "sample_count": 1,
            "gpu_count": 1,
            "started_at": timestamp,
            "ended_at": timestamp,
            "duration_s": 1.0,
            "used_mib_min": 100.0,
            "used_mib_max": 100.0,
            "used_mib_avg": 100.0,
            "total_mib_max": 1000.0,
            "free_mib_min": 900.0,
            "util_percent_max": 0.0,
            "util_percent_avg": 0.0,
            "used_mib_delta_by_gpu": {"0": 0.0},
            "used_mib_peak_by_gpu": {"0": 100.0},
        }
        benchmark_rows: list[dict[str, object]] = []
        windows: list[dict[str, str]] = []
        progress: list[dict[str, object]] = []
        for operator_index in range(81):
            module = f"module{operator_index:02d}"
            operator = f"operator{operator_index:02d}"
            for level in range(1, 7):
                benchmark_rows.append(
                    {
                        "module": module,
                        "operator": operator,
                        "scale_level": level,
                        "scale_value": level * 1024,
                        "gpu_e2e_median_ms": 1.0,
                        "gpu_kernel_median_ms": 0.5,
                        "fixed_overhead_ms": 0.5,
                    }
                )
                windows.append(
                    {
                        "module": module,
                        "operator": operator,
                        "scale_level": str(level),
                        "scale_value": str(level * 1024),
                        "window_duration_s": "2.0",
                        "sample_count": "1",
                        "used_mib_max": "100.0",
                        "util_percent_max": "0.0",
                        "util_percent_p95": "0.0",
                        "active_util_median": "",
                        "active_sample_fraction": "",
                        "gpu_e2e_median_ms": "1.0",
                        "gpu_kernel_median_ms": "0.5",
                        "fixed_overhead_ms": "0.5",
                    }
                )
                identity = {
                    "module": module,
                    "operator": operator,
                    "scale_level": level,
                }
                progress.extend(
                    [
                        {
                            **identity,
                            "event": "case_start",
                            "timestamp_unix": sample_time - 1.0,
                        },
                        {
                            **identity,
                            "event": "case_end",
                            "timestamp_unix": sample_time + 1.0,
                        },
                    ]
                )
        windows[0]["sample_count"] = "0"

        def read_table(path: Path, delimiter: str = "\t") -> list[dict[str, str]]:
            del delimiter
            return samples if path.name == "dlsmi_samples.csv" else windows

        with ExitStack() as stack:
            stack.enter_context(mock.patch.object(MODULE, "read_json", return_value=raw))
            stack.enter_context(mock.patch.object(MODULE, "read_table", side_effect=read_table))
            stack.enter_context(mock.patch.object(MODULE, "read_json_lines", return_value=progress))
            with self.assertRaisesRegex(ValueError, "operator telemetry sample count mismatch"):
                MODULE.validate_telemetry(
                    Path("/fixture"),
                    {"telemetry_summary": raw},
                    benchmark_rows,
                )

    def test_performance_status_requires_exact_topology(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = sorted(MODULE.expected_status_keys("V6-0141"))
            lines = ["phase\tcase\trc\tnote"]
            for phase, case in rows:
                note = "V6-0141 performance terminal" if (phase, case) == ("final", "overall") else "evidence"
                lines.append(f"{phase}\t{case}\t0\t{note}")
            (root / "status.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
            MODULE.validate_status_table(root, "V6-0141")
            lines[1] = "forged\tplaceholder\t0\tevidence"
            (root / "status.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "status topology mismatch"):
                MODULE.validate_status_table(root, "V6-0141")

    def test_console_conflicting_terminal_marker_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "console.log"
            path.write_text("OVERALL_RC=1\nOVERALL_RC=0\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "conflicting terminal marker"):
                MODULE.validate_console(path, {"OVERALL_RC=0"})

    def test_report_tree_symlink_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "reports"
            root.mkdir()
            target = Path(directory) / "outside"
            target.write_text("outside\n", encoding="utf-8")
            (root / "summary.json").symlink_to(target)
            with self.assertRaisesRegex(ValueError, "report tree contains symlink"):
                MODULE.report_file_inventory(root)

    def benchmark_row(self, error_class: str = "true-error") -> dict[str, str]:
        return {
            "module": "spectral",
            "operator": "coherence",
            "scale_level": "1",
            "scale_value": "1024",
            "shape_note": "fixture",
            "gpu_e2e_median_ms": "1.0",
            "gpu_kernel_median_ms": "0.5",
            "cpu_median_ms": "2.0",
            "gpu_e2e_speedup": "2.0",
            "gpu_kernel_speedup": "4.0",
            "mixed_error": "0.1",
            "error_class": error_class,
            "gpu_name": "fixture",
        }

    def test_true_error_classification_is_recomputed(self) -> None:
        row = MODULE.typed_hotspot(self.benchmark_row())
        self.assertEqual(row["error_class"], "true-error")
        with self.assertRaisesRegex(ValueError, "error classification mismatch"):
            MODULE.typed_hotspot(self.benchmark_row(error_class="ok"))

    def test_archive_policy_binds_l6_raw_metrics_and_manifest_inventory(self) -> None:
        source_root = SCRIPT.parents[2]
        operators = MODULE.load_operator_policy(source_root)
        preflight = set(MODULE.archive_evidence_files("V6-0138", operators))
        performance = set(MODULE.archive_evidence_files("V6-0141", operators))
        self.assertIn("manifest_before.sha256", preflight)
        self.assertIn("logs/platform_ctest.log", preflight)
        self.assertIn("fingerprint/source_sha256.txt", preflight)
        self.assertIn("preflight/archive.sha256", performance)
        self.assertEqual(
            sum(path.startswith("benchmark/l6_reports/") for path in performance),
            81,
        )

    def test_type_policy_is_a_frozen_all81_partition(self) -> None:
        source_root = SCRIPT.parents[2]
        operators = MODULE.load_operator_policy(source_root)
        policy = MODULE.load_type_contract_policy(source_root, operators)
        self.assertEqual(set(policy), operators)
        manifest = MODULE.load_evidence_manifest(
            source_root / "scripts/platform/v6_final_evidence_manifest.json",
            source_root,
        )
        self.assertIn("scripts/test/operator_type_contracts.json", manifest["tracked_policy_files"])
        self.assertIn("tests/unit/core_types/test_type_contracts.cu", manifest["tracked_policy_files"])


if __name__ == "__main__":
    unittest.main()
