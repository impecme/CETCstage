import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "zx_operator_autotune.py"
SPEC = importlib.util.spec_from_file_location("zx_operator_autotune", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class ZxOperatorAutotuneTests(unittest.TestCase):
    def test_failed_task_candidate_is_recorded_and_does_not_abort_round(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            args = SimpleNamespace(
                state_root=root / "state",
                resume=False,
            )
            with patch.object(MODULE, "invoke_task_candidate", return_value=2):
                results = MODULE.run_task_candidate_round(
                    args,
                    ["task2_features"],
                    root / "round",
                    "screening",
                    {"task2_features": ["task2_direct_t128"]},
                )
            self.assertEqual(len(results), len(MODULE.LEVELS))
            self.assertTrue(all(row["correctness_status"] == "FAIL" for row in results))
            self.assertTrue(all(row["candidate_applied"] is False for row in results))
            self.assertTrue((root / "round" / "task2_features" / "task2_direct_t128" / "failure.json").is_file())
            self.assertTrue((root / "state" / "state" / "tasks" / "task2_features" / "task2_direct_t128" / "L1.json").is_file())

    def test_task2_grouped_spectrogram_uses_runtime_thread_group_count(self):
        source = (
            Path(__file__).resolve().parents[1]
            / "demo" / "task2_features" / "task2_features_zx_gpu.cu"
        ).read_text(encoding="utf-8")
        self.assertNotIn(
            "constexpr int kBinGroupsPerBlock = kThreadsPerBlock / kBinGroupSize;",
            source,
        )
        self.assertIn("const int bin_groups_per_block = blockDim.x / kBinGroupSize;", source)
        self.assertIn("bin_base += bin_groups_per_block", source)

    def test_default_cache_is_repository_owned(self):
        self.assertEqual(
            MODULE.cache_default_path(),
            MODULE.project_root() / "data" / "tuning" / "zx_tuning.json",
        )

    def test_registry_is_finite_and_matches_runtime_names(self):
        for family, definition in MODULE.FAMILIES.items():
            names = MODULE.all_candidate_names(family)
            self.assertEqual(len(names), len(set(names)))
            self.assertTrue(names)
            self.assertEqual(definition["operator"].count("/"), 1)
            for name in names:
                self.assertNotIn("jit", name.lower())

    def test_exact_operator_selection_resolves_to_registered_family(self):
        self.assertEqual(
            MODULE.resolve_families(None, ["waveforms/chirp"]),
            ["waveforms/chirp"],
        )
        self.assertEqual(
            MODULE.resolve_families(None, ["radartools/ca_cfar"]),
            ["ca_cfar"],
        )

    def test_static_only_run_does_not_publish_unfingerprinted_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            cache_path = Path(directory) / "static-only.json"
            MODULE.write_cache(cache_path, [], [])
            self.assertFalse(cache_path.exists())

    def test_static_candidate_without_trace_is_allowed_for_tunable_family(self):
        family = "peak_finding/argrelextrema"
        candidate_name = MODULE.FAMILIES[family]["static"]
        with tempfile.TemporaryDirectory() as directory:
            aggregate = Path(directory) / "units" / "benchmarks" / "operator_scales.json"
            aggregate.parent.mkdir(parents=True)
            aggregate.write_text(
                json.dumps(
                    {
                        "rows": [
                            {
                                "operator": MODULE.FAMILIES[family]["operator"],
                                "scale_level": level,
                                "gpu_e2e_median_ms": 1.0,
                                "gpu_kernel_median_ms": 0.5,
                                "correctness_status": "PASS",
                                "input_refresh_pass": True,
                            }
                            for level in MODULE.LEVELS
                        ]
                    }
                ),
                encoding="utf-8",
            )
            rows = MODULE.read_metrics(Path(directory), family, candidate_name)
        self.assertEqual(len(rows), len(MODULE.LEVELS))
        self.assertTrue(all(row["key"] is None for row in rows))
        self.assertTrue(all(row["candidate_applied"] for row in rows))

    def test_resume_rejects_complete_rows_without_real_candidate_trace(self):
        family = "waveforms/chirp"
        candidate = "linear_m50_t256_e1_v1"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "run_metadata.json").write_text(
                json.dumps({"family": family, "candidate": candidate}),
                encoding="utf-8",
            )
            aggregate = root / "units" / "benchmarks" / "operator_scales.json"
            aggregate.parent.mkdir(parents=True)
            aggregate.write_text(
                json.dumps(
                    {
                        "rows": [
                            {
                                "operator": MODULE.FAMILIES[family]["operator"],
                                "scale_level": level,
                                "gpu_e2e_median_ms": 1.0,
                                "gpu_kernel_median_ms": 0.5,
                                "correctness_status": "PASS",
                                "input_refresh_pass": True,
                            }
                            for level in MODULE.LEVELS
                        ]
                    }
                ),
                encoding="utf-8",
            )
            self.assertFalse(MODULE.run_output_is_complete(root, family, candidate))

    def test_only_faster_correct_and_applied_candidate_enters_cache(self):
        family = "ca_cfar"
        static_name = MODULE.FAMILIES[family]["static"]
        results = []
        for level, static_ms, tuned_ms in zip(MODULE.LEVELS, [10.0, 10.0], [9.0, 11.0]):
            for name, elapsed in ((static_name, static_ms), ("ca_cfar_tiled_t128_e128", tuned_ms)):
                results.append(
                    {
                        "family": family,
                        "key": f"key-{level}",
                        "candidate": name,
                        "candidate_applied": True,
                        "gpu_e2e_median_ms": elapsed,
                        "gpu_kernel_median_ms": elapsed / 2,
                        "correctness_status": "PASS",
                        "input_refresh_status": "PASS",
                        "workspace_bytes": 4096,
                        "config": {
                            "threads": 128,
                            "tile_rows": 1,
                            "tile_cols": 1,
                            "elements_per_thread": 1,
                            "rows_per_block": 1,
                            "vector_width": 1,
                            "stages": 1,
                            "scan_elements": 128,
                            "workspace_bytes": 4096,
                        },
                        "device": {
                            "id": 0,
                            "name": "test",
                            "runtime_version": 1,
                            "compute_major": 7,
                            "compute_minor": 0,
                            "total_global_mem": 1024,
                        },
                    }
                )
        entries = MODULE.select_cache_entries(results, family)
        self.assertEqual([entry["key"] for entry in entries], ["key-L1"])
        self.assertEqual(entries[0]["candidate"], "ca_cfar_tiled_t128_e128")

    def test_second_round_winner_must_still_beat_static(self):
        family = "waveforms/chirp"
        static_name = MODULE.FAMILIES[family]["static"]
        tuned_name = "linear_m90_t256_e8_v4_b8"
        key = "linear|operator=waveforms/chirp|dtype=0|layout=0|batch=1|shape=4096|semantic=1"

        def result(candidate, elapsed):
            return {
                "family": family,
                "key": key,
                "candidate": candidate,
                "candidate_applied": True,
                "gpu_e2e_median_ms": elapsed,
                "gpu_kernel_median_ms": elapsed / 2,
                "correctness_status": "PASS",
                "input_refresh_status": "PASS",
                "workspace_bytes": 4096,
                "config": {"threads": 256, "memory_tier": 90, "workspace_bytes": 4096},
                "device": {},
            }

        first_round = [result(static_name, 10.0), result(tuned_name, 9.0)]
        validation_round = [result(static_name, 8.0), result(tuned_name, 8.5)]
        self.assertEqual(
            MODULE.select_cache_entries(first_round, family, validation_round), []
        )

        validation_round[1]["gpu_e2e_median_ms"] = 7.5
        entries = MODULE.select_cache_entries(first_round, family, validation_round)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["candidate"], tuned_name)
        self.assertEqual(entries[0]["selection"]["validation_round"], "winner-against-static")

    def test_provisional_validation_candidates_are_unique_and_exclude_static(self):
        family = "waveforms/chirp"
        static_name = MODULE.FAMILIES[family]["static"]
        base = {
            "family": family,
            "candidate_applied": True,
            "gpu_kernel_median_ms": 1.0,
            "correctness_status": "PASS",
            "input_refresh_status": "PASS",
            "workspace_bytes": 0,
            "config": {},
            "device": {},
        }
        first = [
            dict(base, key="key-1", candidate=static_name, gpu_e2e_median_ms=10.0),
            dict(base, key="key-1", candidate="linear_m50_t256_e2_v2", gpu_e2e_median_ms=9.0),
            dict(base, key="key-2", candidate=static_name, gpu_e2e_median_ms=10.0),
            dict(base, key="key-2", candidate="linear_m50_t256_e2_v2", gpu_e2e_median_ms=9.0),
        ]
        self.assertEqual(
            MODULE.provisional_candidate_names(first, family),
            ["linear_m50_t256_e2_v2"],
        )

    def test_registry_version_invalidates_previous_cache_generation(self):
        self.assertEqual(MODULE.REGISTRY_VERSION, "zx-c500-appendix53-task-v5")

    def test_full_registry_has_expanded_candidates_and_tasks(self):
        self.assertEqual(len(MODULE.OPERATOR_KEYS), 81)
        self.assertGreater(sum(len(MODULE.all_candidate_names(family)) for family in MODULE.OPERATOR_KEYS), 995)
        self.assertEqual(set(MODULE.TASKS), {"task1_radar", "task2_features"})
        self.assertEqual(sum(len(MODULE.all_task_candidate_names(task)) for task in MODULE.TASKS), 9)

    def test_appendix53_scope_and_two_day_profile_are_exact(self):
        families = MODULE.resolve_families(None, None, "task_appendix")
        self.assertEqual(len(families), 53)
        self.assertEqual(
            sum(len(MODULE.all_candidate_names(family, "two_day")) for family in families),
            609,
        )
        self.assertLess(
            sum(len(MODULE.all_candidate_names(family, "two_day")) for family in families),
            sum(len(MODULE.all_candidate_names(family)) for family in families),
        )

    def test_static_only_operator_has_explicit_reason(self):
        definition = MODULE.FAMILIES["filter_design/kaiser_beta"]
        self.assertEqual(definition["candidates"], [])
        self.assertIn("no independent C500 dispatch", definition["static_only_reason"])

    def test_expanded_families_have_exact_runtime_family_names(self):
        expected = {
            "window", "spectral", "filtering", "wavelet", "radar_aux",
            "correlate1d", "kalman", "filter_design_gpu",
        }
        actual = {
            definition["policy_family"]
            for definition in MODULE.FAMILIES.values()
            if definition.get("policy_family") in expected
        }
        self.assertEqual(actual, expected)
        for family, definition in MODULE.FAMILIES.items():
            if definition.get("policy_family") in expected:
                self.assertTrue(definition["candidates"], family)
                self.assertTrue(all(item["config"].get("route", 0) >= 1 for item in definition["candidates"]))

    def test_fallback_candidate_is_not_compared_as_an_applied_candidate(self):
        family = "correlate2d"
        static_name = MODULE.FAMILIES[family]["static"]
        base = {
            "family": family,
            "key": "exact-key",
            "gpu_kernel_median_ms": 1.0,
            "correctness_status": "PASS",
            "input_refresh_status": "PASS",
            "workspace_bytes": 1,
            "config": {},
            "device": {},
        }
        static = dict(base, candidate=static_name, candidate_applied=True, gpu_e2e_median_ms=2.0)
        fallback = dict(
            base,
            candidate="correlate2d_shared_16x32",
            candidate_applied=False,
            gpu_e2e_median_ms=1.0,
        )
        self.assertEqual(MODULE.select_cache_entries([static, fallback], family), [])

    def test_generic_cache_uses_policy_family_and_exact_operator_key(self):
        family = "waveforms/chirp"
        static_name = MODULE.FAMILIES[family]["static"]
        key = "linear|operator=waveforms/chirp|dtype=0|layout=0|batch=1|shape=4096|semantic=1"
        config = {
            "threads": 256,
            "tile_rows": 1,
            "tile_cols": 1,
            "elements_per_thread": 2,
            "rows_per_block": 1,
            "vector_width": 2,
            "stages": 1,
            "scan_elements": 0,
            "buffer_count": 1,
            "batch_tile": 1,
            "memory_tier": 50,
            "plan_variant": 0,
            "workspace_bytes": 0,
        }
        base = {
            "family": family,
            "key": key,
            "candidate_applied": True,
            "gpu_kernel_median_ms": 1.0,
            "correctness_status": "PASS",
            "input_refresh_status": "PASS",
            "workspace_bytes": 0,
            "config": config,
            "device": {},
        }
        static = dict(base, candidate=static_name, gpu_e2e_median_ms=2.0)
        tuned = dict(base, candidate="linear_m50_t256_e2_v2", gpu_e2e_median_ms=1.0)
        entries = MODULE.select_cache_entries([static, tuned], family)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["family"], "linear")
        self.assertEqual(entries[0]["operator_id"], "waveforms/chirp")
        self.assertEqual(entries[0]["key_fields"]["operator_id"], "waveforms/chirp")

    def test_read_metrics_requires_all_six_scales_and_exact_candidate_fields(self):
        family = "pulse_doppler"
        candidate = MODULE.FAMILIES[family]["static"]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rows = []
            for level in MODULE.LEVELS:
                rows.append(
                    {
                        "operator": MODULE.FAMILIES[family]["operator"],
                        "scale_level": level,
                        "tuning_registry_version": MODULE.REGISTRY_VERSION,
                        "tuning_family": family,
                        "tuning_candidate": candidate,
                        "tuning_key": f"key-{level}",
                        "gpu_e2e_median_ms": 2.0,
                        "gpu_kernel_median_ms": 1.0,
                        "correctness_status": "PASS",
                        "input_refresh_pass": True,
                        "tuning_threads": 256,
                        "tuning_tile_rows": 1,
                        "tuning_tile_cols": 1,
                        "tuning_elements_per_thread": 1,
                        "tuning_rows_per_block": 1,
                        "tuning_vector_width": 1,
                        "tuning_stages": 1,
                        "tuning_scan_elements": 0,
                        "tuning_workspace_bytes": 0,
                        "tuning_device_id": 0,
                        "tuning_device_name": "test",
                        "tuning_runtime_version": 1,
                        "tuning_compute_major": 7,
                        "tuning_compute_minor": 0,
                        "tuning_total_global_mem": 1024,
                    }
                )
            target = root / "units" / "benchmarks"
            target.mkdir(parents=True)
            (target / "operator_scales.json").write_text(json.dumps({"rows": rows}), encoding="utf-8")
            parsed = MODULE.read_metrics(root, family, candidate)
            self.assertEqual(len(parsed), 6)
            self.assertTrue(all(item["candidate_applied"] for item in parsed))


if __name__ == "__main__":
    unittest.main()
