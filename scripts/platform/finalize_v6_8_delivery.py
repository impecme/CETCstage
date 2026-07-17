#!/usr/bin/env python3

"""Validate V6.8 terminal evidence and write the compact final delivery report."""

from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import json
import math
import re
import shutil
import statistics
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any


EXPECTED_TASK_CASES = 24
EXPECTED_TASK_STEPS = 168
EXPECTED_OPERATORS = 81
EXPECTED_PERFORMANCE_ROWS = 486
EXPECTED_CALCULATION_STEPS = 14
EXPECTED_LEVELS = {1, 2, 3, 4, 5, 6}
EXPECTED_TASKS = {"task1_radar": 6, "task2_features": 8}
EXPECTED_MODES = {"first_process": 1, "warm": 5}
EXPECTED_STATUS_ROWS = {"V6-0138": 64, "V6-0141": 11}
EXPECTED_RETAINED_DIRECTIONS = 21
BENCHMARK_TRUE_ERROR_THRESHOLD = 1.0e-2
TASK_BASELINES = {
    "task1_radar": {
        "total": 7.19016,
        "pulse_compression": 3.27254,
        "pulse_doppler": 1.56758,
        "ca_cfar": 0.997072,
    },
    "task2_features": {
        "total": 76.0695,
        "cwt": 34.0065,
        "spectrogram": 25.4401,
        "correlate": 9.75641,
    },
}
RESIDUAL_TARGETS = [
    {
        "module": "radartools",
        "operator": "ambgfun",
        "scale_level": 6,
        "assessment": "compute-bound in the final terminal; prior rejected candidates remain documented in the V6 ledger",
    },
    {
        "module": "filtering",
        "operator": "hilbert2",
        "scale_level": 5,
        "assessment": "unfavorable FFT dimensions; the V6 ledger records the same cliff in the V6.1 baseline",
    },
    {
        "module": "spectral",
        "operator": "lombscargle",
        "scale_level": 6,
        "assessment": "remaining cost is kernel arithmetic after the retained pair-input and reduction work",
    },
    {
        "module": "radartools",
        "operator": "mvdr",
        "scale_level": 6,
        "assessment": "further work requires a cross-call lifecycle or output/synchronization redesign",
    },
]
PASSED_TRUE_ERROR_DIAGNOSTIC_POLICY = [
    {
        "module": "spectral",
        "operator": "coherence",
        "scale_levels": [1, 2, 3, 4, 5],
        "scope": (
            "the independent all81 accuracy case passed under its historical calibrated "
            "float32 tolerance; the V6-0141 perf runner does not fail rows on mixed_error, "
            "while the benchmark-wide 1e-2 diagnostic classified these perf rows as true-error"
        ),
    }
]
L6_SUMMARY_ONLY_OPERATOR_POLICY = [
    "correlate/correlate",
    "correlate/correlate2d",
    "correlate/correlation_lags",
    "demod/fm_demod",
    "estimation/kalman_filter",
    "peak_finding/argrelextrema",
    "peak_finding/argrelmax",
    "peak_finding/argrelmin",
]
TASK_CHECK_POLICY = {
    "task1_radar": {
        "check_names": [
            "cpu_gpu_detection_match",
            "gpu_matches_expected_detection",
            "gpu_total_ms",
            "pulse_compression_mixed_error",
            "pulse_doppler_mixed_error",
            "cfar_threshold_mixed_error",
            "ambgfun_surface_mixed_error",
            "invalid_input_checks",
            "repeat_business_consistency",
            "gpu_total_stability",
            "gpu_free_memory_drift_mib",
            "rss_current_drift_mib",
        ],
        "constant_limits": {
            "cpu_gpu_detection_match": 1.0,
            "gpu_matches_expected_detection": 1.0,
            "pulse_compression_mixed_error": 1.0e-4,
            "ambgfun_surface_mixed_error": 1.0e-4,
            "invalid_input_checks": 1.0,
            "repeat_business_consistency": 1.0,
            "gpu_total_stability": 0.35,
            "gpu_free_memory_drift_mib": 32.0,
            "rss_current_drift_mib": 64.0,
        },
        "scale_limits": {
            "gpu_total_ms": [10.0, 5.0, 5.0, 10.0, 30.0, 75.0],
            "pulse_doppler_mixed_error": [1.0e-4, 1.0e-4, 1.0e-4, 1.0e-4, 3.0e-4, 5.0e-4],
            "cfar_threshold_mixed_error": [0.005, 0.005, 0.005, 0.05, 0.1, 0.5],
        },
    },
    "task2_features": {
        "check_names": [
            "cpu_gpu_track_match",
            "gpu_matches_truth_within_tolerance",
            "kalman_rmse",
            "gpu_total_ms",
            "filtered_mixed_error",
            "demod_mixed_error",
            "correlate_mixed_error",
            "spectrogram_mixed_error",
            "cwt_mixed_error",
            "feature_score_mixed_error",
            "measurement_mixed_error",
            "kalman_cpu_gpu_rmse",
            "invalid_input_checks",
            "repeat_business_consistency",
            "gpu_total_stability",
            "gpu_free_memory_drift_mib",
            "rss_current_drift_mib",
        ],
        "constant_limits": {
            "cpu_gpu_track_match": 1.0,
            "gpu_matches_truth_within_tolerance": 1.0,
            "kalman_rmse": 2.0,
            "filtered_mixed_error": 1.0e-4,
            "demod_mixed_error": 5.0e-4,
            "correlate_mixed_error": 1.0e-4,
            "spectrogram_mixed_error": 1.0e-4,
            "cwt_mixed_error": 1.0e-4,
            "feature_score_mixed_error": 1.0e-4,
            "measurement_mixed_error": 1.0e-4,
            "kalman_cpu_gpu_rmse": 2.0,
            "invalid_input_checks": 1.0,
            "repeat_business_consistency": 1.0,
            "gpu_total_stability": 0.35,
            "gpu_free_memory_drift_mib": 32.0,
            "rss_current_drift_mib": 64.0,
        },
        "scale_limits": {
            "gpu_total_ms": [50.0, 87.5, 150.0, 200.0, 450.0, 900.0],
        },
    },
}
TASK_REPORT_STEP_POLICY = {
    "task1_radar": [
        {"step": "pulse_compression", "operator": "radartools/pulse_compression"},
        {"step": "pulse_doppler", "operator": "radartools/pulse_doppler_shifted"},
        {"step": "power_map", "operator": "radartools/power_map"},
        {"step": "ca_cfar", "operator": "radartools/ca_cfar"},
        {"step": "ambgfun", "operator": "radartools/ambgfun"},
        {"step": "final_detection", "operator": "radartools/detect_peak"},
    ],
    "task2_features": [
        {
            "step": "filter",
            "operator": "filter_design/firwin + filtering/firfilter public complex64 path",
        },
        {"step": "demod", "operator": "demod/fm_demod + private batched score"},
        {"step": "correlate", "operator": "correlate/correlate + private normalization"},
        {"step": "spectrogram", "operator": "spectral/spectrogram + private band score"},
        {"step": "cwt", "operator": "wavelets/cwt + private scale reduction"},
        {"step": "feature_fusion", "operator": "private weighted fusion + peak selection"},
        {"step": "measurement_conversion", "operator": "estimation measurement helper"},
        {"step": "kalman", "operator": "estimation/kalman_filter + private GPU pipeline"},
    ],
}
EXPECTED_ACCEPTANCE_POLICY = {
    "all81_operator_count": EXPECTED_OPERATORS,
    "calculation_step_count": EXPECTED_CALCULATION_STEPS,
    "task_case_count": EXPECTED_TASK_CASES,
    "task_step_row_count": EXPECTED_TASK_STEPS,
    "performance_row_count": EXPECTED_PERFORMANCE_ROWS,
    "performance_scale_levels": sorted(EXPECTED_LEVELS),
    "performance_warmup": 5,
    "performance_repeat": 30,
    "retained_v6_7_direction_count": EXPECTED_RETAINED_DIRECTIONS,
    "v6_1_task_baseline_ms": TASK_BASELINES,
    "residual_assessment_policy": RESIDUAL_TARGETS,
    "benchmark_true_error_threshold": BENCHMARK_TRUE_ERROR_THRESHOLD,
    "passed_true_error_diagnostic_policy": PASSED_TRUE_ERROR_DIAGNOSTIC_POLICY,
    "l6_summary_only_operator_policy": L6_SUMMARY_ONLY_OPERATOR_POLICY,
    "task_check_policy": TASK_CHECK_POLICY,
    "task_report_step_policy": TASK_REPORT_STEP_POLICY,
}
MINIMUM_CHECK_NAMES = {
    "cpu_gpu_track_match",
    "gpu_matches_truth_within_tolerance",
    "cpu_gpu_detection_match",
    "gpu_matches_expected_detection",
    "invalid_input_checks",
    "repeat_business_consistency",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight-root", required=True)
    parser.add_argument("--performance-root", required=True)
    parser.add_argument("--preflight-archive", required=True)
    parser.add_argument("--preflight-console", required=True)
    parser.add_argument("--performance-archive", required=True)
    parser.add_argument("--performance-console", required=True)
    parser.add_argument("--v5-summary-markdown", required=True)
    parser.add_argument("--v5-summary-json", required=True)
    parser.add_argument(
        "--v5-source-dir",
        help="Optional historical v5_5_final directory used to restore summary.md/json",
    )
    parser.add_argument("--report-root", default="data/reports")
    parser.add_argument(
        "--evidence-manifest",
        default="",
        help="Frozen V6 archive/console SHA256 trust anchor; defaults under source-root",
    )
    parser.add_argument(
        "--source-root",
        default=str(Path(__file__).resolve().parents[2]),
        help="Repository containing this finalizer; overrides are rejected",
    )
    parser.add_argument(
        "--output-dir",
        default="data/reports/zhongkexin/v6_final",
    )
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def require_keys(payload: dict[str, Any], expected: set[str], label: str) -> None:
    require(set(payload) == expected, f"{label} keys mismatch")


def require_true(value: Any, label: str) -> None:
    require(value is True, f"{label} must be JSON true")


def require_regular_file(path: Path) -> None:
    require(path.is_file() and not path.is_symlink(), f"missing or non-regular evidence file: {path}")


def canonical_input_path(value: str | Path, label: str) -> Path:
    path = Path(value).absolute()
    require(path == path.resolve(), f"{label} must not contain symlinks: {path}")
    return path


def reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in payload, f"duplicate JSON key: {key}")
        payload[key] = value
    return payload


def read_json(path: Path) -> dict[str, Any]:
    require_regular_file(path)
    payload = json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=reject_duplicate_json_keys,
    )
    require(isinstance(payload, dict), f"expected JSON object: {path}")
    return payload


def read_table(path: Path, delimiter: str = "\t") -> list[dict[str, str]]:
    require_regular_file(path)
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        require(reader.fieldnames is not None, f"missing table header: {path}")
        require(len(reader.fieldnames) == len(set(reader.fieldnames)), f"duplicate table header: {path}")
        rows = list(reader)
    require(all(None not in row for row in rows), f"table column overflow: {path}")
    return rows


def parse_int(value: Any) -> int:
    return int(str(value))


def parse_float(value: Any) -> float:
    result = float(str(value))
    require(math.isfinite(result), f"non-finite numeric value: {value}")
    return result


def parse_bool(value: Any) -> bool:
    token = str(value).strip().lower()
    require(token in {"true", "false"}, f"invalid boolean: {value}")
    return token == "true"


def require_close(actual: float, expected: float, label: str) -> None:
    require(math.isclose(actual, expected, rel_tol=1.0e-9, abs_tol=1.0e-12), f"{label} mismatch")


def require_csv_close(actual: float, expected: float, label: str) -> None:
    require(math.isclose(actual, expected, rel_tol=5.0e-5, abs_tol=5.0e-10), f"{label} mismatch")


def sha256(path: Path) -> str:
    require_regular_file(path)
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_nonempty(path: Path) -> str:
    require_regular_file(path)
    require(path.stat().st_size > 0, f"empty evidence file: {path}")
    return sha256(path)


def read_sha256_inventory(path: Path, label: str) -> dict[str, str]:
    require_regular_file(path)
    rows: dict[str, str] = {}
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        match = re.fullmatch(r"([0-9a-f]{64})  ([^\x00]+)", line)
        require(match is not None, f"invalid {label} row {line_number}")
        digest, relative = match.groups()
        relative_path = Path(relative)
        require(
            not relative_path.is_absolute()
            and relative_path.as_posix() == relative
            and "." not in relative_path.parts
            and ".." not in relative_path.parts,
            f"unsafe {label} path: {relative}",
        )
        require(relative not in rows, f"duplicate {label} path: {relative}")
        rows[relative] = digest
    require(rows, f"empty {label}")
    return rows


def load_evidence_manifest(path: Path, source_root: Path) -> dict[str, Any]:
    expected_path = (source_root / "scripts/platform/v6_final_evidence_manifest.json").resolve()
    require(path.resolve() == expected_path, "V6 evidence manifest must be the tracked repository trust anchor")
    payload = read_json(expected_path)
    require_keys(
        payload,
        {"schema_version", "version", "acceptance_policy", "tracked_policy_files", "predecessor_reports", "runs"},
        "V6 evidence manifest",
    )
    require(payload["schema_version"] == "v6_final_evidence_manifest_v1", "V6 evidence manifest schema mismatch")
    require(payload["version"] == "V6.8", "V6 evidence manifest version mismatch")
    require(payload["acceptance_policy"] == EXPECTED_ACCEPTANCE_POLICY, "V6 acceptance policy mismatch")
    policy_files = payload["tracked_policy_files"]
    require_keys(
        policy_files,
        {
            "scripts/test/operator_sets.json",
            "scripts/test/task_step_contracts.json",
            "scripts/test/operator_type_contracts.json",
            "tests/unit/core_types/test_type_contracts.cu",
        },
        "V6 tracked policy files",
    )
    for relative, expected_hash in policy_files.items():
        require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"invalid policy SHA256: {relative}")
        require(sha256(source_root / relative) == expected_hash, f"tracked policy SHA256 mismatch: {relative}")
    predecessor_reports = payload["predecessor_reports"]
    require_keys(predecessor_reports, {"v5_5_summary_md_sha256", "v5_5_summary_json_sha256"}, "V5.5 predecessor report hashes")
    for name, expected_hash in predecessor_reports.items():
        require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"invalid predecessor SHA256: {name}")
    runs = payload["runs"]
    require_keys(runs, {"V6-0138", "V6-0141"}, "V6 evidence runs")
    expected_names = {
        "V6-0138": ("cetc_v6_0138_v6_8_preflight_20260716_122947", "cetc_v6_0138_latest.tar.gz", "cetc_v6_0138_console.log"),
        "V6-0141": ("cetc_v6_0141_v6_8_performance_20260716_131750", "cetc_v6_0141_latest.tar.gz", "cetc_v6_0141_console.log"),
    }
    for execution_id, expected in expected_names.items():
        entry = runs[execution_id]
        require_keys(
            entry,
            {"root_name", "archive_name", "archive_sha256", "console_name", "console_sha256"},
            f"{execution_id} manifest entry",
        )
        require(
            (entry["root_name"], entry["archive_name"], entry["console_name"]) == expected,
            f"{execution_id} manifest identity mismatch",
        )
        for field in ("archive_sha256", "console_sha256"):
            require(re.fullmatch(r"[0-9a-f]{64}", entry[field]) is not None, f"invalid {execution_id} {field}")
    return payload


def load_operator_policy(source_root: Path) -> set[str]:
    payload = read_json(source_root / "scripts/test/operator_sets.json")
    entry = payload["sets"]["all81"]
    operators = entry["operators"]
    require(entry["expected_count"] == EXPECTED_OPERATORS, "all81 policy count mismatch")
    require(len(operators) == len(set(operators)) == EXPECTED_OPERATORS, "all81 policy operator set mismatch")
    return set(operators)


def load_task_contract_policy(source_root: Path) -> dict[tuple[str, str], dict[str, Any]]:
    payload = read_json(source_root / "scripts/test/task_step_contracts.json")
    require(payload["schema_version"] == 1, "task contract schema mismatch")
    rows: dict[tuple[str, str], dict[str, Any]] = {}
    for task, entries in payload["tasks"].items():
        for entry in entries:
            key = (task, entry["step"])
            require(key not in rows, f"duplicate task contract: {key}")
            rows[key] = {"task": task, **entry}
    require(len(rows) == 16, "task contract row count mismatch")
    return rows


def load_type_contract_policy(source_root: Path, expected_operators: set[str]) -> dict[str, dict[str, Any]]:
    payload = read_json(source_root / "scripts/test/operator_type_contracts.json")
    require(payload["schema_version"] == 1, "type contract policy schema mismatch")
    policies = payload["policies"]
    assignments = payload["assignments"]
    require(set(assignments) == set(policies), "type policy assignment names mismatch")
    rows: dict[str, dict[str, Any]] = {}
    for policy_name, operators in assignments.items():
        require(isinstance(operators, list), f"type policy assignment is not a list: {policy_name}")
        for operator in operators:
            require(operator not in rows, f"duplicate type policy assignment: {operator}")
            rows[operator] = {"policy": policy_name, **policies[policy_name]}
    require(set(rows) == expected_operators, "type policy operator set mismatch")
    return rows


def case_dtypes(case: dict[str, Any]) -> set[str]:
    all_dtypes = {"float32", "float16", "int32", "int16", "int8", "complex64"}
    result: set[str] = set()
    dtype = case.get("dtype")
    if isinstance(dtype, str) and dtype in all_dtypes:
        result.add(dtype)
    for field in ("type", "input_kind", "output_kind"):
        value = case.get(field)
        if value == "complex":
            result.add("complex64")
        elif value == "real":
            result.add("float32")
    if case.get("is_complex") is True:
        result.add("complex64")
    elif case.get("is_complex") is False:
        result.add("float32")
    if case.get("index_dtype") == "int32":
        result.add("int32")
    return result or {"float32"}


def validate_manifest_inventory(
    root: Path,
    source_root: Path,
    expected_operators: set[str],
) -> dict[str, list[str]]:
    before_path = root / "manifest_before.sha256"
    after_path = root / "manifest_after.sha256"
    require_regular_file(before_path)
    require_regular_file(after_path)
    before_text = before_path.read_text(encoding="utf-8")
    require(before_text == after_path.read_text(encoding="utf-8"), "manifest before/after inventory mismatch")
    rows: dict[str, str] = {}
    concrete: dict[str, set[str]] = {operator: set() for operator in expected_operators}
    for line_number, line in enumerate(before_text.splitlines(), start=1):
        match = re.fullmatch(r"([0-9a-f]{64})  (data/(?:reference|generated)/unit/[^/]+/[^/]+/manifest\.json)", line)
        require(match is not None, f"invalid manifest inventory row {line_number}")
        expected_hash, relative = match.groups()
        require(relative not in rows, f"duplicate manifest inventory path: {relative}")
        rows[relative] = expected_hash
        parts = Path(relative).parts
        require(len(parts) == 6, f"invalid manifest inventory path: {relative}")
        operator = f"{parts[3]}/{parts[4]}"
        require(operator in expected_operators, f"unexpected manifest inventory operator: {operator}")
        path = source_root / relative
        require(path.absolute() == path.resolve(), f"manifest inventory path contains symlink: {relative}")
        require(sha256(path) == expected_hash, f"current manifest differs from V6-0138 inventory: {relative}")
        payload = read_json(path)
        for name in ("accuracy_cases", "perf_cases"):
            cases = payload.get(name, [])
            require(isinstance(cases, list), f"manifest case set is not a list: {relative}/{name}")
            for case in cases:
                require(isinstance(case, dict), f"manifest case is not an object: {relative}/{name}")
                concrete[operator].update(case_dtypes(case))
    require(len(rows) == EXPECTED_OPERATORS * 2, "manifest inventory row count mismatch")
    for operator in expected_operators:
        expected_paths = {
            f"data/reference/unit/{operator}/manifest.json",
            f"data/generated/unit/{operator}/manifest.json",
        }
        require(expected_paths <= set(rows), f"manifest pair is incomplete: {operator}")
    return {operator: sorted(values) for operator, values in concrete.items()}


def validate_frozen_run_inputs(
    execution_id: str,
    root: Path,
    archive: Path,
    console: Path,
    entry: dict[str, Any],
) -> None:
    require(root.is_dir() and not root.is_symlink(), f"missing {execution_id} evidence root")
    require(root.name == entry["root_name"], f"{execution_id} root differs from frozen manifest")
    require(archive.name == entry["archive_name"], f"{execution_id} archive identity mismatch")
    require(console.name == entry["console_name"], f"{execution_id} console identity mismatch")
    require(sha256_nonempty(archive) == entry["archive_sha256"], f"{execution_id} archive SHA256 mismatch")
    require(sha256_nonempty(console) == entry["console_sha256"], f"{execution_id} console SHA256 mismatch")


def validate_archive(path: Path, root: Path, relative_files: tuple[str, ...]) -> str:
    archive_hash = sha256_nonempty(path)
    try:
        with tarfile.open(path, mode="r:gz") as archive:
            member_list = archive.getmembers()
            names = [member.name for member in member_list]
            require(len(names) == len(set(names)), "archive contains duplicate member names")
            members = {member.name: member for member in member_list}
            for relative in relative_files:
                member_name = f"{root.name}/{relative}"
                require(member_name in members, f"archive lacks {member_name}")
                member = members[member_name]
                require(member.isfile(), f"archive member is not a file: {member_name}")
                handle = archive.extractfile(member)
                require(handle is not None, f"cannot read archive member: {member_name}")
                member_hash = hashlib.sha256(handle.read()).hexdigest()
                require(member_hash == sha256(root / relative), f"archive/extracted mismatch: {relative}")
    except (tarfile.TarError, OSError) as error:
        raise ValueError(f"invalid evidence archive: {path}: {error}") from error
    return archive_hash


def validate_console(path: Path, required_lines: set[str]) -> str:
    console_hash = sha256_nonempty(path)
    lines = path.read_text(encoding="utf-8", errors="strict").splitlines()
    for required in required_lines:
        require(lines.count(required) == 1, f"console terminal marker count mismatch: {required}")
        key = required.split("=", 1)[0]
        require(
            sum(line.startswith(f"{key}=") for line in lines) == 1,
            f"console contains conflicting terminal marker: {key}",
        )
    return console_hash


def archive_evidence_files(
    execution_id: str,
    expected_operators: set[str] | None = None,
) -> tuple[str, ...]:
    if execution_id == "V6-0138":
        files = [
            "status.tsv",
            "manifest_before.sha256",
            "manifest_after.sha256",
            "manifest_diff.log",
            "reports_diff.log",
            "all81_registry.tsv",
            "logs/regression_all81_full.log",
            "audits/assertions.json",
            "audits/interface/latest_interface_audit.json",
            "audits/types/latest_type_contracts.json",
            "audits/dtype/latest_dtype_test_coverage.json",
            "audits/task_steps/latest_task_step_audit.json",
            "task_summary/task_matrix.json",
            "task_summary/task_totals.tsv",
            "task_summary/task_steps.tsv",
            "platform/runtime_probe.tsv",
            "logs/platform_ctest.log",
            "fingerprint/source_sha256.txt",
        ]
        for mode in EXPECTED_MODES:
            for task in EXPECTED_TASKS:
                for level in sorted(EXPECTED_LEVELS):
                    base = f"tasks/{mode}/{task}/L{level}"
                    files.extend(
                        [
                            f"{base}/latest_metrics.json",
                            f"{base}/latest_step_metrics.json",
                            f"{base}/latest_step_metrics.csv",
                            f"{base}/process_wall_ns.txt",
                        ]
                    )
            for level in sorted(EXPECTED_LEVELS):
                files.append(f"task_schema_validation/{mode}/L{level}/summary.json")
        return tuple(files)
    if execution_id == "V6-0141":
        require(expected_operators is not None, "V6-0141 operator policy is required")
        files = [
            "status.tsv",
            "manifest_diff.log",
            "reports_diff.log",
            "preflight/product_source_diff.log",
            "preflight/product_source_sha256.txt",
            "preflight/archive.sha256",
            "preflight/cetc_v6_0138_v6_8_preflight_20260716_122947/status.tsv",
            "preflight/cetc_v6_0138_v6_8_preflight_20260716_122947/audits/assertions.json",
            "preflight/cetc_v6_0138_v6_8_preflight_20260716_122947/task_summary/task_matrix.json",
            "preflight/cetc_v6_0138_v6_8_preflight_20260716_122947/fingerprint/source_sha256.txt",
            "fingerprint/product_source_sha256.sorted.txt",
            "benchmark/latest_all_ops_scale_benchmark.csv",
            "telemetry/operator_windows.jsonl",
            "telemetry/dlsmi_samples.csv",
            "telemetry/dlsmi_summary.json",
            "summary/operator_telemetry.tsv",
            "summary/task_comparison.tsv",
            "summary/l6_hotspots.tsv",
            "summary/summary.json",
        ]
        files.extend(
            f"benchmark/l6_reports/{operator}/latest_metrics.json"
            for operator in sorted(expected_operators)
        )
        return tuple(files)
    raise ValueError(f"unknown V6 execution ID: {execution_id}")


def expected_status_keys(label: str) -> set[tuple[str, str]]:
    if label == "V6-0138":
        keys = {
            ("guard", "clean_report_roots"),
            ("fingerprint", "source_and_toolchain"),
            ("build", "configure_release"),
            ("audit", "registry"),
            ("audit", "static_contracts"),
            ("audit", "static_assertions"),
            ("regression", "all81_full"),
            ("regression", "all81_assert"),
            ("evidence", "copy_all81_reports"),
            ("build", "task_platform_targets"),
            ("build", "release_flags"),
            ("platform", "ctest"),
            ("platform", "runtime_probe"),
            ("platform", "runtime_probe_assert"),
            ("schema", "task_reports"),
            ("summary", "task_matrix"),
            ("telemetry", "assert"),
            ("integrity", "manifest_unchanged"),
            ("integrity", "reports_restored"),
            ("final", "overall"),
        }
        for mode in EXPECTED_MODES:
            for task in EXPECTED_TASKS:
                keys.add(("task", f"{mode}_{task}"))
                keys.add(("telemetry", f"{mode}_{task}"))
                for level in EXPECTED_LEVELS:
                    keys.add(("task", f"{mode}_{task}_L{level}"))
            for level in EXPECTED_LEVELS:
                keys.add(("schema", f"{mode}_L{level}"))
        return keys
    if label == "V6-0141":
        return {
            ("guard", "clean_report_roots"),
            ("fingerprint", "source_and_toolchain"),
            ("preflight", "extract"),
            ("preflight", "hard_gate_and_source_match"),
            ("benchmark", "all81_l1_l6"),
            ("telemetry", "dlsmi"),
            ("evidence", "copy_l6_reports"),
            ("summary", "performance"),
            ("integrity", "manifest_unchanged"),
            ("integrity", "reports_restored"),
            ("final", "overall"),
        }
    raise ValueError(f"unknown V6 status label: {label}")


def validate_status_table(root: Path, label: str) -> list[dict[str, str]]:
    rows = read_table(root / "status.tsv")
    require(rows, f"{label} status.tsv is empty")
    require(len(rows) == EXPECTED_STATUS_ROWS[label], f"{label} status row count mismatch")
    keys = [(row["phase"], row["case"]) for row in rows]
    require(len(keys) == len(set(keys)), f"{label} duplicate status row")
    require(set(keys) == expected_status_keys(label), f"{label} status topology mismatch")
    failures = [row for row in rows if parse_int(row["rc"]) != 0]
    require(not failures, f"{label} contains nonzero status rows: {failures}")
    final_rows = [
        row
        for row in rows
        if row.get("phase") == "final" and row.get("case") == "overall"
    ]
    require(len(final_rows) == 1, f"{label} final/overall row count is not 1")
    expected_note = "V6-0138 hard-gate preflight" if label == "V6-0138" else "V6-0141 performance terminal"
    require(final_rows[0]["note"] == expected_note, f"{label} final status note mismatch")
    if label == "V6-0138":
        for row in rows:
            if row["phase"] == "task" and re.fullmatch(r"(?:first_process|warm)_.+_L[1-6]", row["case"]):
                mode = row["case"].split("_", 1)[0]
                if row["case"].startswith("first_process_"):
                    mode = "first_process"
                require(row["note"] == f"repeat={EXPECTED_MODES[mode]}", f"{label} task repeat note mismatch")
    return rows


def validate_embedded_preflight_reference(
    performance_root: Path,
    preflight_root: Path,
    manifest: dict[str, Any],
) -> None:
    preflight_entry = manifest["runs"]["V6-0138"]
    reference_path = performance_root / "preflight/archive.sha256"
    require_regular_file(reference_path)
    fields = reference_path.read_text(encoding="utf-8").strip().split()
    require(
        fields == [preflight_entry["archive_sha256"], f"/tmp/{preflight_entry['archive_name']}"],
        "V6-0141 embedded V6-0138 archive reference mismatch",
    )
    embedded = performance_root / "preflight" / preflight_entry["root_name"]
    require(embedded.is_dir() and not embedded.is_symlink(), "V6-0141 embedded preflight root mismatch")
    for relative in (
        "status.tsv",
        "audits/assertions.json",
        "task_summary/task_matrix.json",
        "fingerprint/source_sha256.txt",
    ):
        require(
            sha256(embedded / relative) == sha256(preflight_root / relative),
            f"V6-0141 embedded V6-0138 evidence mismatch: {relative}",
        )


def require_empty(path: Path) -> None:
    require_regular_file(path)
    require(path.stat().st_size == 0, f"expected empty evidence file: {path}")


def typed_task_total(row: dict[str, str]) -> dict[str, Any]:
    return {
        "mode": row["mode"],
        "task": row["task"],
        "scale_level": parse_int(row["scale_level"]),
        "scale_value": parse_int(row["scale_value"]),
        "repeat": parse_int(row["repeat"]),
        "validation_pass": parse_bool(row["validation_pass"]),
        "cpu_first_ms": parse_float(row["cpu_first_ms"]),
        "gpu_first_ms": parse_float(row["gpu_first_ms"]),
        "cpu_median_ms": parse_float(row["cpu_median_ms"]),
        "gpu_median_ms": parse_float(row["gpu_median_ms"]),
        "gpu_p95_ms": parse_float(row["gpu_p95_ms"]),
        "gpu_min_ms": parse_float(row["gpu_min_ms"]),
        "gpu_max_ms": parse_float(row["gpu_max_ms"]),
        "process_wall_ms": parse_float(row["process_wall_ms"]),
        "step_count": parse_int(row["step_count"]),
        "step_csv_count": parse_int(row["step_csv_count"]),
        "gpu_device": parse_int(row["gpu_device"]),
        "gpu_device_name": row["gpu_device_name"],
        "gpu_total_mib": parse_int(row["gpu_total_mib"]),
        "gpu_free_delta_mib": parse_int(row["gpu_free_delta_mib"]),
        "rss_current_delta_mib": parse_float(row["rss_current_delta_mib"]),
        "metrics_path": row["metrics_path"],
        "step_json_path": row["step_json_path"],
        "step_csv_path": row["step_csv_path"],
        "process_wall_path": row["process_wall_path"],
    }


def typed_task_step(row: dict[str, str]) -> dict[str, Any]:
    return {
        "mode": row["mode"],
        "task": row["task"],
        "scale_level": parse_int(row["scale_level"]),
        "step": row["step"],
        "operator": row["operator"],
        "cpu_ms": parse_float(row["cpu_ms"]),
        "gpu_e2e_ms": parse_float(row["gpu_e2e_ms"]),
        "gpu_kernel_ms": None if row.get("gpu_kernel_ms", "") == "" else parse_float(row["gpu_kernel_ms"]),
        "mixed_error": parse_float(row["mixed_error"]),
        "max_abs": parse_float(row["max_abs"]),
        "rmse": parse_float(row["rmse"]),
        "pass": parse_bool(row["pass"]),
    }


def classify_benchmark_error(mixed_error: float, kernel_speedup: float, e2e_speedup: float) -> str:
    if mixed_error > BENCHMARK_TRUE_ERROR_THRESHOLD:
        return "true-error"
    if kernel_speedup < 10.0 or e2e_speedup < 3.0:
        return "performance-bound"
    return "ok"


def typed_hotspot(row: dict[str, str]) -> dict[str, Any]:
    e2e_ms = parse_float(row["gpu_e2e_median_ms"])
    kernel_ms = parse_float(row["gpu_kernel_median_ms"])
    result = {
        "module": row["module"],
        "operator": row["operator"],
        "scale_level": parse_int(row["scale_level"]),
        "scale_value": parse_int(row["scale_value"]),
        "shape_note": row["shape_note"],
        "gpu_e2e_median_ms": e2e_ms,
        "gpu_kernel_median_ms": kernel_ms,
        "fixed_overhead_ms": e2e_ms - kernel_ms,
        "cpu_median_ms": parse_float(row["cpu_median_ms"]),
        "gpu_e2e_speedup": parse_float(row["gpu_e2e_speedup"]),
        "gpu_kernel_speedup": parse_float(row["gpu_kernel_speedup"]),
        "mixed_error": parse_float(row["mixed_error"]),
        "error_class": row["error_class"],
        "gpu_name": row["gpu_name"],
    }
    require(e2e_ms > 0.0 and kernel_ms >= 0.0, "benchmark timing must be nonnegative")
    require(result["cpu_median_ms"] > 0.0, "benchmark CPU timing must be positive")
    require(result["gpu_e2e_speedup"] > 0.0, "benchmark speedup must be positive")
    require(
        (kernel_ms > 0.0 and result["gpu_kernel_speedup"] > 0.0)
        or (kernel_ms == 0.0 and result["gpu_kernel_speedup"] == 0.0),
        "benchmark kernel timing/speedup mismatch",
    )
    require(result["mixed_error"] >= 0.0, "benchmark mixed error must be nonnegative")
    require(result["fixed_overhead_ms"] >= 0.0, "benchmark kernel exceeds E2E timing")
    require_csv_close(
        result["gpu_e2e_speedup"],
        result["cpu_median_ms"] / e2e_ms,
        "benchmark E2E speedup",
    )
    if kernel_ms > 0.0:
        require_csv_close(
            result["gpu_kernel_speedup"],
            result["cpu_median_ms"] / kernel_ms,
            "benchmark kernel speedup",
        )
    require(
        result["error_class"]
        == classify_benchmark_error(
            result["mixed_error"],
            result["gpu_kernel_speedup"],
            result["gpu_e2e_speedup"],
        ),
        "benchmark error classification mismatch",
    )
    return result


def validate_all81_and_audits(
    root: Path,
    expected_operators: set[str],
    expected_task_rows: dict[tuple[str, str], dict[str, Any]],
    expected_type_rows: dict[str, dict[str, Any]],
    manifest_dtypes: dict[str, list[str]],
) -> dict[str, int]:
    registry_rows = [
        line.split("\t")
        for line in (root / "all81_registry.tsv").read_text(encoding="utf-8").splitlines()
        if line
    ]
    require(all(len(row) == 4 for row in registry_rows), "all81 registry column mismatch")
    registry_names = [f"{row[0]}/{row[1]}" for row in registry_rows]
    require(len(registry_names) == len(set(registry_names)), "all81 registry contains duplicates")
    require(set(registry_names) == expected_operators, "all81 registry operator set mismatch")

    log_path = root / "logs/regression_all81_full.log"
    require_regular_file(log_path)
    pattern = re.compile(r"^\[([a-z0-9_]+/[a-z0-9_]+)\] PASS  accuracy_cases=(\d+)  perf_cases=(\d+)$")
    passed: dict[str, tuple[int, int]] = {}
    log_lines = log_path.read_text(encoding="utf-8", errors="strict").splitlines()
    for line in log_lines:
        match = pattern.fullmatch(line)
        if match is None:
            continue
        operator = match.group(1)
        require(operator not in passed, f"duplicate all81 execution line: {operator}")
        counts = (int(match.group(2)), int(match.group(3)))
        require(counts[0] > 0 and counts[1] > 0, f"empty all81 case set: {operator}")
        passed[operator] = counts
    failure_pattern = re.compile(r"^\[([a-z0-9_]+/[a-z0-9_]+)\] (?:FAIL|ERROR)\b")
    require(
        not any(failure_pattern.match(line) for line in log_lines),
        "all81 execution log contains operator FAIL/ERROR lines",
    )
    require(set(passed) == expected_operators, "all81 execution operator set mismatch")
    terminal = f"[cusignal-test] summary: passed {EXPECTED_OPERATORS}/{EXPECTED_OPERATORS}"
    require(log_lines.count(terminal) == 1 and log_lines[-1] == terminal, "all81 terminal summary mismatch")
    require(
        sum(line.startswith("[cusignal-test] summary:") for line in log_lines) == 1,
        "all81 execution log contains conflicting terminal summaries",
    )

    interface = read_json(root / "audits/interface/latest_interface_audit.json")
    interface_rows = interface["operators"]
    interface_names = [row["key"] for row in interface_rows]
    require(len(interface_names) == len(set(interface_names)), "interface rows contain duplicates")
    require(set(interface_names) == expected_operators, "interface operator set mismatch")
    atomic_interface_fields = (
        "declaration_pass",
        "cpu_pass",
        "gpu_pass",
        "test_pass",
        "doxygen_pass",
    )
    for row in interface_rows:
        require(row["key"] == f"{row['module']}/{row['operator']}", "interface key mismatch")
        require(row["header"] == f"include/cusignal/{row['module']}/{row['module']}.hpp", "interface header mismatch")
        require(row["cpu_source"] == f"src/cpu/{row['module']}.cpp", "interface CPU source mismatch")
        require(row["gpu_source"] == f"src/zhongkexin/{row['module']}.cu", "interface GPU source mismatch")
        for field in atomic_interface_fields:
            require_true(row[field], f"interface atomic gate {row['key']}/{field}")
        require_true(row["pass"], f"interface aggregate gate {row['key']}")
        require(row["findings"] == [], f"interface findings are not empty: {row['key']}")
        require(
            parse_int(row["declaration_count"]) > 0
            and parse_int(row["cpu_definition_count"]) > 0
            and parse_int(row["gpu_definition_count"]) > 0,
            f"interface declaration/definition count is empty: {row['key']}",
        )
        require(
            parse_int(row["documented_declaration_count"]) == parse_int(row["declaration_count"]),
            f"interface documented declaration count mismatch: {row['key']}",
        )
        require(
            parse_int(row["documented_constructor_count"]) == parse_int(row["constructor_declaration_count"]),
            f"interface documented constructor count mismatch: {row['key']}",
        )
    interface_passed = len(interface_rows)
    interface_summary = interface["summary"]
    require(interface_summary["status"] == "passed", "interface audit status failed")
    require(
        interface_summary["operator_count"] == len(interface_rows)
        and interface_summary["passed_count"] == interface_passed
        and interface_summary["failed_count"] == len(interface_rows) - interface_passed,
        "interface summary mismatch",
    )
    require(interface_passed == EXPECTED_OPERATORS, "interface audit contains failures")

    types = read_json(root / "audits/types/latest_type_contracts.json")
    type_rows = types["operators"]
    type_names = [row["operator"] for row in type_rows]
    require(len(type_names) == len(set(type_names)), "type rows contain duplicates")
    require(set(type_names) == expected_operators, "type operator set mismatch")
    compatibility_gaps = 0
    policy_fields = (
        "input_types",
        "output_types",
        "current_types",
        "compatibility_types",
        "compatibility_mode",
        "accumulator",
        "integer_policy",
        "output_rule",
    )
    for row in type_rows:
        expected = expected_type_rows[row["operator"]]
        require(row["policy"] == expected["policy"], f"type policy mismatch: {row['operator']}")
        for field in policy_fields:
            require(row[field] == expected[field], f"type policy field mismatch: {row['operator']}/{field}")
        target = set(expected["input_types"]) | set(expected["output_types"])
        converted = target - set(expected["current_types"])
        require(row["target_types"] == sorted(target), f"type target set mismatch: {row['operator']}")
        require(
            row["converted_compatibility_types"] == sorted(converted),
            f"converted type set mismatch: {row['operator']}",
        )
    type_summary = types["summary"]
    require(type_summary["status"] == "passed", "type audit status failed")
    require(type_summary["operator_count"] == len(type_rows), "type operator count mismatch")
    require(type_summary["compatibility_gap_count"] == compatibility_gaps == 0, "type compatibility gaps")

    dtype = read_json(root / "audits/dtype/latest_dtype_test_coverage.json")
    dtype_rows = dtype["operators"]
    dtype_names = [row["operator"] for row in dtype_rows]
    require(len(dtype_names) == len(set(dtype_names)), "dtype rows contain duplicates")
    require(set(dtype_names) == expected_operators, "dtype operator set mismatch")
    missing_edges = 0
    declared: dict[str, int] = {}
    concrete: dict[str, int] = {}
    for row in dtype_rows:
        expected = expected_type_rows[row["operator"]]
        require(row["policy"] == expected["policy"], f"dtype policy mismatch: {row['operator']}")
        require(
            row["compatibility_types"] == sorted(set(expected["compatibility_types"])),
            f"dtype compatibility policy mismatch: {row['operator']}",
        )
        require(
            row["current_types"] == sorted(set(expected["current_types"])),
            f"dtype current-type policy mismatch: {row['operator']}",
        )
        require(row["compatibility_mode"] == expected["compatibility_mode"], f"dtype compatibility mode mismatch: {row['operator']}")
        missing = row["missing_operator_test_dtypes"]
        missing_edges += len(missing)
        compatibility = row["compatibility_types"]
        tests = row["concrete_operator_test_dtypes"]
        require(len(compatibility) == len(set(compatibility)), "duplicate compatibility dtype")
        require(len(tests) == len(set(tests)), "duplicate concrete dtype")
        require(tests == manifest_dtypes[row["operator"]], f"dtype manifest evidence mismatch: {row['operator']}")
        require(
            missing == sorted(set(compatibility) - set(tests)),
            f"dtype missing-edge derivation mismatch: {row['operator']}",
        )
        require(set(compatibility) <= set(tests), f"dtype coverage gap: {row['operator']}")
        for name in compatibility:
            declared[name] = declared.get(name, 0) + 1
            concrete[name] = concrete.get(name, 0) + int(name in tests)
    dtype_summary = dtype["summary"]
    require(dtype_summary["status"] == "passed", "dtype audit status failed")
    require(dtype_summary["operator_count"] == len(dtype_rows), "dtype operator count mismatch")
    require(dtype_summary["operator_dtype_missing_edges"] == missing_edges == 0, "dtype missing edges")
    require(set(dtype_summary["dtype_summary"]) == set(declared), "dtype summary key set mismatch")
    for name, summary in dtype_summary["dtype_summary"].items():
        require_true(summary["core_type_roundtrip_tested"], f"dtype roundtrip {name}")
        require(
            summary["declared_operator_count"] == declared[name]
            and summary["concrete_operator_test_count"] == concrete[name]
            and summary["missing_operator_test_count"] == 0,
            f"dtype aggregate mismatch: {name}",
        )

    ctest_path = root / "logs/platform_ctest.log"
    require_regular_file(ctest_path)
    ctest_lines = ctest_path.read_text(encoding="utf-8", errors="strict").splitlines()
    require(
        sum(re.search(r"cusignal_type_contract .*Passed", line) is not None for line in ctest_lines) == 1,
        "core type contract ctest result mismatch",
    )
    require(
        sum(line.startswith("100% tests passed, 0 tests failed out of ") for line in ctest_lines) == 1,
        "platform ctest terminal result mismatch",
    )

    task = read_json(root / "audits/task_steps/latest_task_step_audit.json")
    task_rows = task["steps"]
    task_keys = [(row["task"], row["step"]) for row in task_rows]
    require(len(task_keys) == len(set(task_keys)), "task audit contains duplicate steps")
    require(set(task_keys) == set(expected_task_rows), "task audit step set mismatch")
    for row in task_rows:
        require(row == expected_task_rows[(row["task"], row["step"])], "task contract mismatch")
    calculation_rows = [row for row in task_rows if row["category"] == "calculation"]
    linked_steps = sum(bool(row["public_operators"]) for row in calculation_rows)
    implementation_counts: dict[str, int] = {}
    for row in task_rows:
        implementation_counts[row["implementation"]] = implementation_counts.get(row["implementation"], 0) + 1
    require(
        all(row["timing"] == "present" and row["accuracy"] == "present" for row in calculation_rows),
        "task timing/accuracy gap",
    )
    task_summary = task["summary"]
    require(task_summary["status"] == "passed", "task audit status failed")
    require(
        task_summary["calculation_step_count"] == len(calculation_rows) == EXPECTED_CALCULATION_STEPS
        and task_summary["public_operator_link_count"] == linked_steps == EXPECTED_CALCULATION_STEPS,
        "task calculation-step summary mismatch",
    )
    require(
        task_summary["public_calculation_step_count"]
        == sum(row["implementation"] == "public" for row in calculation_rows)
        == 6
        and task_summary["migration_step_count"]
        == sum(row["implementation"] == "mixed" for row in calculation_rows)
        == 8
        and task_summary["implementation_counts"] == implementation_counts,
        "task implementation classification mismatch",
    )
    require(
        task_summary["failure_count"] == 0
        and task_summary["failures"] == []
        and task_summary["timing_gap_count"] == 0
        and task_summary["accuracy_gap_count"] == 0,
        "task audit contains failures",
    )

    assertions = read_json(root / "audits/assertions.json")
    require_keys(assertions, {"dtype", "interface", "operator_sets", "registry_81", "task_steps", "types"}, "V6 static assertions")
    for name, value in assertions.items():
        require_true(value, f"V6 static assertion {name}")
    return {
        "all81_passed": len(passed),
        "interface_passed": interface_passed,
        "compatibility_gap_count": compatibility_gaps,
        "dtype_missing_edges": missing_edges,
        "calculation_steps": len(calculation_rows),
        "public_calculation_steps": task_summary["public_calculation_step_count"],
        "mixed_calculation_steps": task_summary["migration_step_count"],
        "public_operator_link_declarations": linked_steps,
    }


def nearest_rank(values: list[float], percentile: float) -> float:
    ordered = sorted(values)
    index = max(1, math.ceil(percentile * len(ordered))) - 1
    return ordered[index]


def validate_task_metrics(
    path: Path,
    *,
    task: str,
    level: int,
    repeat: int,
    label: str,
) -> dict[str, Any]:
    metrics = read_json(path)
    require(parse_int(metrics["scenario"]["scale_level"]) == level, f"{label} scale mismatch")
    validation = metrics["validation"]
    require_true(validation["pass"], f"{label} validation")
    checks = validation["checks"]
    require(isinstance(checks, list) and checks, f"{label} validation checks are empty")
    names = [check["name"] for check in checks]
    require(len(names) == len(set(names)), f"{label} duplicate validation check")
    policy = TASK_CHECK_POLICY[task]
    require(names == policy["check_names"], f"{label} validation check topology mismatch")
    check_index = {check["name"]: check for check in checks}
    for check in checks:
        require(type(check["pass"]) is bool, f"{label} check pass type")
        value = parse_float(check["value"])
        limit = parse_float(check["limit"])
        require(value >= 0.0 and limit >= 0.0, f"{label} negative check value/limit")
        expected_limit = policy["constant_limits"].get(check["name"])
        if expected_limit is None:
            expected_limit = policy["scale_limits"][check["name"]][level - 1]
        require_close(limit, expected_limit, f"{label} validation limit {check['name']}")
        require("skipped" not in str(check.get("detail", "")).lower(), f"{label} contains skipped validation")
        derived = value >= limit if check["name"] in MINIMUM_CHECK_NAMES else value <= limit
        require(check["pass"] is derived is True, f"{label} validation check failed: {check['name']}")
    repeats = metrics["repeat_runs"]
    require(len(repeats) == repeat, f"{label} repeat count mismatch")
    require([parse_int(row["index"]) for row in repeats] == list(range(1, repeat + 1)), f"{label} repeat indices mismatch")
    for row in repeats:
        require_true(row["pass"], f"{label} repeat pass")
        require_true(row["business_numeric_pass"], f"{label} repeat business pass")
        require(parse_float(row["cpu_total_ms"]) > 0.0 and parse_float(row["gpu_total_ms"]) > 0.0, f"{label} repeat timing")
        require(parse_float(row["gpu_free_mib"]) >= 0.0, f"{label} repeat GPU memory")
        require(parse_float(row["rss_current_mib"]) >= 0.0, f"{label} repeat RSS")
    timings = metrics["timings"]
    require("total" in timings, f"{label} missing total timing")
    for name, timing in timings.items():
        require(parse_float(timing["cpu_ms"]) >= 0.0 and parse_float(timing["gpu_ms"]) >= 0.0, f"{label} negative timing: {name}")
    for name, error in metrics.items():
        if not name.endswith("_error") or not isinstance(error, dict) or "mixed_error" not in error:
            continue
        for field in ("mixed_error", "max_abs", "max_rel", "rmse"):
            require(parse_float(error[field]) >= 0.0, f"{label} negative {name}.{field}")

    def check_value(name: str) -> float:
        return parse_float(check_index[name]["value"])

    require_close(
        check_value("gpu_total_ms"),
        parse_float(timings["total"]["gpu_ms"]),
        f"{label} final GPU total check",
    )
    require_close(
        check_value("gpu_total_ms"),
        parse_float(repeats[-1]["gpu_total_ms"]),
        f"{label} final GPU repeat total",
    )
    consistency = metrics["consistency"]
    consistency_checks = (
        ("cpu_gpu_detection_match", "cpu_gpu_detection_match"),
        ("gpu_matches_expected_detection", "gpu_matches_expected_detection"),
    ) if task == "task1_radar" else (
        ("cpu_gpu_track_match", "cpu_gpu_track_match"),
        ("gpu_matches_truth_within_tolerance", "gpu_matches_truth_within_tolerance"),
    )
    for check_name, field in consistency_checks:
        require_true(consistency[field], f"{label} consistency {field}")
        require_close(check_value(check_name), 1.0, f"{label} consistency check {check_name}")
    require_close(check_value("invalid_input_checks"), 1.0, f"{label} invalid-input check")
    require_close(
        check_value("repeat_business_consistency"),
        float(all(row["business_numeric_pass"] is True for row in repeats)),
        f"{label} repeat business check",
    )

    timing_rows = repeats[1:] if len(repeats) > 2 else repeats
    gpu_totals = [parse_float(row["gpu_total_ms"]) for row in timing_rows]
    median = statistics.median(gpu_totals)
    stability = max(abs(value - median) / median for value in gpu_totals) if median > 0.0 else 0.0
    require(
        math.isclose(check_value("gpu_total_stability"), stability, rel_tol=1.0e-5, abs_tol=5.0e-6),
        f"{label} GPU stability check mismatch",
    )
    gpu_drift = parse_float(repeats[0]["gpu_free_mib"]) - parse_float(repeats[-1]["gpu_free_mib"])
    rss_drift = parse_float(repeats[-1]["rss_current_mib"]) - parse_float(repeats[0]["rss_current_mib"])
    require(
        math.isclose(check_value("gpu_free_memory_drift_mib"), gpu_drift, rel_tol=1.0e-9, abs_tol=2.0e-3),
        f"{label} GPU memory drift check mismatch",
    )
    require(
        math.isclose(check_value("rss_current_drift_mib"), rss_drift, rel_tol=1.0e-9, abs_tol=2.0e-3),
        f"{label} RSS drift check mismatch",
    )

    top_level_error_checks = {
        "task1_radar": {
            "pulse_compression_mixed_error": ("pulse_compression_error", "mixed_error"),
            "pulse_doppler_mixed_error": ("pulse_doppler_error", "mixed_error"),
            "cfar_threshold_mixed_error": ("cfar_threshold_error", "mixed_error"),
            "ambgfun_surface_mixed_error": ("ambgfun_surface_error", "mixed_error"),
        },
        "task2_features": {
            "kalman_rmse": ("kalman_track_error", "rmse"),
            "filtered_mixed_error": ("filtered_error", "mixed_error"),
            "correlate_mixed_error": ("correlate_error", "mixed_error"),
            "spectrogram_mixed_error": ("spectrogram_error", "mixed_error"),
            "cwt_mixed_error": ("cwt_error", "mixed_error"),
            "feature_score_mixed_error": ("feature_score_error", "mixed_error"),
        },
    }
    for check_name, (error_name, field) in top_level_error_checks[task].items():
        require_close(
            check_value(check_name),
            parse_float(metrics[error_name][field]),
            f"{label} top-level error check {check_name}",
        )
    return metrics


def validate_task_matrix(root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    task_matrix = read_json(root / "task_summary/task_matrix.json")
    require(task_matrix["schema_version"] == 1, "task matrix schema mismatch")
    require(task_matrix["failures"] == [], "task matrix failures")
    summary = task_matrix["summary"]
    require(summary["status"] == "passed", "task matrix status failed")
    require(
        summary["task_count"] == len(EXPECTED_TASKS)
        and summary["scale_count"] == len(EXPECTED_LEVELS)
        and summary["mode_count"] == len(EXPECTED_MODES),
        "task matrix dimensions mismatch",
    )
    require(
        summary["case_count"] == summary["expected_case_count"] == EXPECTED_TASK_CASES
        and summary["step_row_count"] == summary["expected_step_row_count"] == EXPECTED_TASK_STEPS
        and summary["failure_count"] == 0,
        "task matrix count mismatch",
    )
    totals = [typed_task_total(row) for row in read_table(root / "task_summary/task_totals.tsv")]
    steps = [typed_task_step(row) for row in read_table(root / "task_summary/task_steps.tsv")]
    require(totals == task_matrix["cases"], "task total TSV/JSON mismatch")
    require(steps == task_matrix["steps"], "task step TSV/JSON mismatch")
    expected_cases = {
        (mode, task, level)
        for mode in EXPECTED_MODES
        for task in EXPECTED_TASKS
        for level in EXPECTED_LEVELS
    }
    total_keys = {(row["mode"], row["task"], row["scale_level"]) for row in totals}
    require(total_keys == expected_cases and len(totals) == len(total_keys), "task total case set mismatch")
    step_index = {
        (row["mode"], row["task"], row["scale_level"], row["step"]): row
        for row in steps
    }
    require(len(step_index) == len(steps) == EXPECTED_TASK_STEPS, "task step key set mismatch")
    expected_step_keys = {
        (mode, task, level, item["step"])
        for mode in EXPECTED_MODES
        for task, items in TASK_REPORT_STEP_POLICY.items()
        for level in EXPECTED_LEVELS
        for item in items
    }
    require(set(step_index) == expected_step_keys, "task runtime step topology mismatch")
    for total in totals:
        mode = total["mode"]
        task = total["task"]
        level = total["scale_level"]
        repeat = EXPECTED_MODES[mode]
        expected_base = f"tasks/{mode}/{task}/L{level}"
        require(total["repeat"] == repeat, f"task repeat mismatch: {mode}/{task}/L{level}")
        require_true(total["validation_pass"], f"task total {mode}/{task}/L{level}")
        require(total["step_count"] == total["step_csv_count"] == EXPECTED_TASKS[task], "task step count mismatch")
        expected_paths = {
            "metrics_path": f"{expected_base}/latest_metrics.json",
            "step_json_path": f"{expected_base}/latest_step_metrics.json",
            "step_csv_path": f"{expected_base}/latest_step_metrics.csv",
            "process_wall_path": f"{expected_base}/process_wall_ns.txt",
        }
        require(all(total[name] == value for name, value in expected_paths.items()), "task evidence path mismatch")
        metrics = validate_task_metrics(
            root / total["metrics_path"],
            task=task,
            level=level,
            repeat=repeat,
            label=f"{mode}/{task}/L{level}",
        )
        repeats = metrics["repeat_runs"]
        cpu_values = [parse_float(row["cpu_total_ms"]) for row in repeats]
        gpu_values = [parse_float(row["gpu_total_ms"]) for row in repeats]
        comparisons = {
            "cpu_first_ms": cpu_values[0],
            "gpu_first_ms": gpu_values[0],
            "cpu_median_ms": statistics.median(cpu_values),
            "gpu_median_ms": statistics.median(gpu_values),
            "gpu_p95_ms": nearest_rank(gpu_values, 0.95),
            "gpu_min_ms": min(gpu_values),
            "gpu_max_ms": max(gpu_values),
        }
        for name, value in comparisons.items():
            require_close(total[name], value, f"task aggregate {mode}/{task}/L{level} {name}")
        resource = metrics["resource_usage"]
        require(total["gpu_device"] == resource["after"]["gpu_device"], "task GPU device mismatch")
        require(total["gpu_device_name"] == resource["after"]["gpu_device_name"], "task GPU name mismatch")
        require(total["gpu_total_mib"] == resource["after"]["gpu_total_mib"], "task GPU memory mismatch")
        require(total["gpu_free_delta_mib"] == resource["gpu_free_delta_mib"], "task GPU delta mismatch")
        require_close(total["rss_current_delta_mib"], parse_float(resource["rss_current_delta_mib"]), "task RSS delta")
        wall_ns_path = root / total["process_wall_path"]
        require_regular_file(wall_ns_path)
        require_close(total["process_wall_ms"], parse_float(wall_ns_path.read_text().strip()) / 1.0e6, "task process wall")

        step_json = read_json(root / total["step_json_path"])
        require(step_json["schema_version"] == 2 and step_json["task"] == task, "task step JSON identity mismatch")
        raw_steps = step_json["steps"]
        csv_steps = read_table(root / total["step_csv_path"], delimiter=",")
        require(len(raw_steps) == len(csv_steps) == EXPECTED_TASKS[task], "task raw step count mismatch")
        expected_step_rows = TASK_REPORT_STEP_POLICY[task]
        require(
            [(row["step"], row["operator"]) for row in raw_steps]
            == [(row["step"], row["operator"]) for row in expected_step_rows],
            f"task JSON step policy mismatch: {mode}/{task}/L{level}",
        )
        require(
            [(row["step"], row["operator"]) for row in csv_steps]
            == [(row["step"], row["operator"]) for row in expected_step_rows],
            f"task CSV step policy mismatch: {mode}/{task}/L{level}",
        )
        raw_step_keys = {
            "step",
            "operator",
            "input_shape",
            "output_shape",
            "input_dtype",
            "output_dtype",
            "cpu_ms",
            "gpu_e2e_ms",
            "gpu_kernel_ms",
            "gpu_e2e_speedup",
            "gpu_kernel_speedup",
            "error_available",
            "error",
            "pass",
            "note",
        }
        csv_step_keys = {
            "task",
            "step",
            "operator",
            "input_shape",
            "output_shape",
            "input_dtype",
            "output_dtype",
            "cpu_ms",
            "gpu_e2e_ms",
            "gpu_kernel_ms",
            "gpu_e2e_speedup",
            "gpu_kernel_speedup",
            "max_abs",
            "max_rel",
            "rmse",
            "mixed_error",
            "real_max_abs",
            "imag_max_abs",
            "error_available",
            "pass",
            "note",
        }
        raw_error_keys = {"max_abs", "max_rel", "rmse", "mixed_error", "real_max_abs", "imag_max_abs"}
        raw_index: dict[str, dict[str, Any]] = {}
        for raw, csv_row in zip(raw_steps, csv_steps):
            key = (mode, task, level, raw["step"])
            require(key in step_index, f"missing aggregate task step: {key}")
            aggregate = step_index[key]
            require(set(raw) == raw_step_keys, f"task JSON step fields mismatch: {key}")
            require(set(csv_row) == csv_step_keys, f"task CSV step fields mismatch: {key}")
            require(set(raw["error"]) == raw_error_keys, f"task JSON error fields mismatch: {key}")
            require(raw["step"] not in raw_index, f"duplicate raw task step: {key}")
            raw_index[raw["step"]] = raw
            require(csv_row["task"] == task and csv_row["step"] == raw["step"], f"task CSV identity mismatch: {key}")
            require(raw["operator"] == aggregate["operator"] == csv_row["operator"], f"task operator mismatch: {key}")
            for field in ("input_shape", "output_shape", "input_dtype", "output_dtype", "note"):
                require(str(raw[field]) == csv_row[field], f"task CSV metadata mismatch: {key}/{field}")
            require_true(raw["pass"], f"task raw step {key}")
            require(parse_bool(csv_row["pass"]), f"task CSV step {key}")
            require_true(raw["error_available"], f"task raw error availability {key}")
            require(parse_bool(csv_row["error_available"]), f"task CSV error availability {key}")
            require(raw["gpu_kernel_ms"] is None and raw["gpu_kernel_speedup"] is None, f"unexpected task kernel metric: {key}")
            require(csv_row["gpu_kernel_ms"] == csv_row["gpu_kernel_speedup"] == "", f"unexpected task CSV kernel metric: {key}")
            for field in ("cpu_ms", "gpu_e2e_ms"):
                require_close(parse_float(raw[field]), aggregate[field], f"task step {key} {field}")
                require_csv_close(parse_float(csv_row[field]), aggregate[field], f"task CSV step {key} {field}")
            timing = metrics["timings"][raw["step"]]
            require_csv_close(parse_float(raw["cpu_ms"]), parse_float(timing["cpu_ms"]), f"task timing JSON {key}/cpu")
            require_csv_close(parse_float(raw["gpu_e2e_ms"]), parse_float(timing["gpu_ms"]), f"task timing JSON {key}/gpu")
            if raw["gpu_e2e_speedup"] is None:
                require(
                    raw["step"] == "measurement_conversion"
                    and parse_float(raw["gpu_e2e_ms"]) == 0.0
                    and csv_row["gpu_e2e_speedup"].lower() == "nan",
                    f"unexpected missing task speedup: {key}",
                )
            else:
                expected_speedup = parse_float(raw["cpu_ms"]) / parse_float(raw["gpu_e2e_ms"])
                require_csv_close(parse_float(raw["gpu_e2e_speedup"]), expected_speedup, f"task speedup {key}")
                require_csv_close(parse_float(csv_row["gpu_e2e_speedup"]), expected_speedup, f"task CSV speedup {key}")
            error = raw["error"]
            for field in ("mixed_error", "max_abs", "max_rel", "rmse"):
                require(parse_float(error[field]) >= 0.0, f"negative task step error: {key}/{field}")
                require_csv_close(parse_float(csv_row[field]), parse_float(error[field]), f"task CSV step {key} {field}")
                if field in {"mixed_error", "max_abs", "rmse"}:
                    require_close(parse_float(error[field]), aggregate[field], f"task step {key} {field}")
            for field in ("real_max_abs", "imag_max_abs"):
                if error[field] is None:
                    require(csv_row[field] == "", f"task CSV optional error mismatch: {key}/{field}")
                else:
                    require_csv_close(parse_float(csv_row[field]), parse_float(error[field]), f"task CSV optional error {key}/{field}")

        require_close(
            parse_float(metrics["timings"]["total"]["cpu_ms"]),
            parse_float(repeats[-1]["cpu_total_ms"]),
            f"task final CPU total: {mode}/{task}/L{level}",
        )
        step_check_sources = {
            "task1_radar": {
                "pulse_compression_mixed_error": ("pulse_compression", "mixed_error"),
                "pulse_doppler_mixed_error": ("pulse_doppler", "mixed_error"),
                "cfar_threshold_mixed_error": ("ca_cfar", "mixed_error"),
                "ambgfun_surface_mixed_error": ("ambgfun", "mixed_error"),
            },
            "task2_features": {
                "filtered_mixed_error": ("filter", "mixed_error"),
                "demod_mixed_error": ("demod", "mixed_error"),
                "correlate_mixed_error": ("correlate", "mixed_error"),
                "spectrogram_mixed_error": ("spectrogram", "mixed_error"),
                "cwt_mixed_error": ("cwt", "mixed_error"),
                "feature_score_mixed_error": ("feature_fusion", "mixed_error"),
                "measurement_mixed_error": ("measurement_conversion", "mixed_error"),
                "kalman_cpu_gpu_rmse": ("kalman", "rmse"),
            },
        }
        check_index = {check["name"]: check for check in metrics["validation"]["checks"]}
        for check_name, (step_name, error_field) in step_check_sources[task].items():
            require_csv_close(
                parse_float(check_index[check_name]["value"]),
                parse_float(raw_index[step_name]["error"][error_field]),
                f"task validation/step error mismatch: {mode}/{task}/L{level}/{check_name}",
            )

    for mode in EXPECTED_MODES:
        for level in EXPECTED_LEVELS:
            schema = read_json(root / f"task_schema_validation/{mode}/L{level}/summary.json")
            require(schema["status"] == "passed", f"task schema failed: {mode}/L{level}")
            require(
                schema["task_count"] == len(EXPECTED_TASKS)
                and schema["step_count"] == EXPECTED_CALCULATION_STEPS
                and schema["error_available_count"] == EXPECTED_CALCULATION_STEPS
                and schema["failure_count"] == 0
                and schema["failures"] == [],
                f"task schema summary mismatch: {mode}/L{level}",
            )
            require(
                {task: values["step_count"] for task, values in schema["tasks"].items()} == EXPECTED_TASKS,
                f"task schema task breakdown mismatch: {mode}/L{level}",
            )
    l6_steps = [row for row in steps if row["mode"] == "warm" and row["scale_level"] == 6]
    require(len(l6_steps) == EXPECTED_CALCULATION_STEPS, "warm L6 step count mismatch")
    return totals, steps, l6_steps


def read_json_lines(path: Path) -> list[dict[str, Any]]:
    require_regular_file(path)
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not line:
            continue
        payload = json.loads(line, object_pairs_hook=reject_duplicate_json_keys)
        require(isinstance(payload, dict), f"invalid JSONL object at {path}:{line_number}")
        rows.append(payload)
    require(rows, f"empty JSONL evidence: {path}")
    return rows


def validate_l6_raw_metrics(
    root: Path,
    benchmark_rows: list[dict[str, Any]],
    expected_operators: set[str],
) -> dict[str, Any]:
    l6_index = {
        f"{row['module']}/{row['operator']}": row
        for row in benchmark_rows
        if row["scale_level"] == 6
    }
    require(set(l6_index) == expected_operators, "L6 benchmark operator set mismatch")
    summary_only: list[str] = []
    case_detail_count = 0
    timing_fields = ("cpu_perf", "gpu_e2e_perf", "gpu_kernel_perf")
    csv_fields = {
        "cpu_perf": "cpu_median_ms",
        "gpu_e2e_perf": "gpu_e2e_median_ms",
        "gpu_kernel_perf": "gpu_kernel_median_ms",
    }
    for operator in sorted(expected_operators):
        module, name = operator.split("/", 1)
        path = root / f"benchmark/l6_reports/{operator}/latest_metrics.json"
        payload = read_json(path)
        require(payload["module"] == module and payload["operator"] == name, f"L6 raw identity mismatch: {operator}")
        row = l6_index[operator]
        require(payload["gpu_name"] == row["gpu_name"], f"L6 raw GPU mismatch: {operator}")
        summary = payload["summary"]
        require_true(summary["pass"], f"L6 raw pass {operator}")
        require(parse_int(summary["accuracy_cases"]) >= 0, f"L6 raw accuracy-case count {operator}")
        require(parse_int(summary["perf_cases"]) > 0, f"L6 raw perf-case count {operator}")
        for timing_name in timing_fields:
            timing = summary[timing_name]
            require(
                parse_int(timing["warmup"]) == 5 and parse_int(timing["repeat"]) == 30,
                f"L6 raw timing protocol: {operator}/{timing_name}",
            )
            values = {field: parse_float(timing[f"{field}_ms"]) for field in ("mean", "median", "p95", "min", "max", "std")}
            require(
                0.0 <= values["min"] <= values["median"] <= values["p95"] <= values["max"]
                and values["min"] <= values["mean"] <= values["max"]
                and values["std"] >= 0.0,
                f"L6 raw timing statistics: {operator}/{timing_name}",
            )
            require_csv_close(
                parse_float(row[csv_fields[timing_name]]),
                values["median"],
                f"L6 raw/CSV median {operator}/{timing_name}",
            )
        require_csv_close(parse_float(row["mixed_error"]), parse_float(summary["mixed_error"]), f"L6 raw mixed error {operator}")
        require(row["error_class"] == summary["error_class"], f"L6 raw error class {operator}")
        require_csv_close(
            parse_float(summary["gpu_e2e_speedup"]),
            parse_float(summary["cpu_perf"]["median_ms"]) / parse_float(summary["gpu_e2e_perf"]["median_ms"]),
            f"L6 raw E2E speedup {operator}",
        )
        kernel_median = parse_float(summary["gpu_kernel_perf"]["median_ms"])
        if kernel_median > 0.0:
            require_csv_close(
                parse_float(summary["gpu_kernel_speedup"]),
                parse_float(summary["cpu_perf"]["median_ms"]) / kernel_median,
                f"L6 raw kernel speedup {operator}",
            )

        cases = payload["cases"]
        require(isinstance(cases, list), f"L6 raw cases are not a list: {operator}")
        if not cases:
            summary_only.append(operator)
            continue
        require(parse_int(summary["accuracy_cases"]) == 0, f"L6 raw case-detail accuracy count: {operator}")
        require(len(cases) == parse_int(summary["perf_cases"]), f"L6 raw case count mismatch: {operator}")
        case_detail_count += 1
        for case in cases:
            require(case["category"] == "perf", f"L6 raw non-perf case: {operator}")
            require_true(case["pass"], f"L6 raw case pass: {operator}")
            for timing_name in timing_fields:
                timing = case[timing_name]
                require(
                    parse_int(timing["warmup"]) == 5 and parse_int(timing["repeat"]) == 30,
                    f"L6 raw case protocol: {operator}/{timing_name}",
                )
                minimum = parse_float(timing["min_ms"])
                median = parse_float(timing["median_ms"])
                p95 = parse_float(timing["p95_ms"])
                maximum = parse_float(timing["max_ms"])
                require(0.0 <= minimum <= median <= p95 <= maximum, f"L6 raw case timing order: {operator}/{timing_name}")
        for timing_name in timing_fields:
            require_csv_close(
                parse_float(summary[timing_name]["median_ms"]),
                max(parse_float(case[timing_name]["median_ms"]) for case in cases),
                f"L6 raw case aggregation: {operator}/{timing_name}",
            )
    require(summary_only == L6_SUMMARY_ONLY_OPERATOR_POLICY, "L6 summary-only operator policy mismatch")
    return {
        "bound_metrics_count": len(l6_index),
        "case_detail_operator_count": case_detail_count,
        "summary_only_operator_count": len(summary_only),
        "summary_only_operators": summary_only,
    }


def validate_benchmark(
    root: Path,
    expected_operators: set[str],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    rows = read_table(root / "benchmark/latest_all_ops_scale_benchmark.csv", delimiter=",")
    require(len(rows) == EXPECTED_PERFORMANCE_ROWS, "benchmark CSV row count mismatch")
    indexed: dict[tuple[str, str, int], dict[str, str]] = {}
    run_ids: set[str] = set()
    gpu_names: set[str] = set()
    typed_rows: list[dict[str, Any]] = []
    for row in rows:
        key = (row["module"], row["operator"], parse_int(row["scale_level"]))
        require(key not in indexed, f"duplicate benchmark row: {key}")
        require(f"{key[0]}/{key[1]}" in expected_operators, f"unexpected benchmark operator: {key}")
        require(key[2] in EXPECTED_LEVELS, f"unexpected benchmark level: {key}")
        require(row["status"] == "passed" and parse_bool(row["pass"]), f"benchmark row failed: {key}")
        require(parse_int(row["return_code"]) == 0, f"benchmark return code failed: {key}")
        require(parse_int(row["warmup"]) == 5 and parse_int(row["repeat"]) == 30, f"benchmark protocol mismatch: {key}")
        typed_rows.append(typed_hotspot(row))
        require(parse_float(row["gpu_e2e_min_ms"]) > 0.0, f"benchmark minimum timing: {key}")
        require(
            parse_float(row["gpu_e2e_min_ms"])
            <= parse_float(row["gpu_e2e_median_ms"])
            <= parse_float(row["gpu_e2e_max_ms"]),
            f"benchmark timing range: {key}",
        )
        indexed[key] = row
        run_ids.add(row["run_id"])
        gpu_names.add(row["gpu_name"])
    expected_keys = {
        (*operator.split("/"), level)
        for operator in expected_operators
        for level in EXPECTED_LEVELS
    }
    require(set(indexed) == expected_keys, "benchmark operator/scale matrix mismatch")
    require(len(run_ids) == len(gpu_names) == 1, "benchmark run/GPU identity mismatch")

    events = read_json_lines(root / "telemetry/operator_windows.jsonl")
    run_start = [event for event in events if event.get("event") == "run_start"]
    run_end = [event for event in events if event.get("event") == "run_end"]
    starts = [event for event in events if event.get("event") == "case_start"]
    ends = [event for event in events if event.get("event") == "case_end"]
    restored = [event for event in events if event.get("event") == "manifests_restored"]
    require(
        len(events) == EXPECTED_PERFORMANCE_ROWS * 2 + 3
        and {event.get("event") for event in events}
        == {"run_start", "case_start", "case_end", "manifests_restored", "run_end"},
        "benchmark progress event topology mismatch",
    )
    timestamps = [parse_float(event["timestamp_unix"]) for event in events]
    require(timestamps == sorted(timestamps), "benchmark progress timestamps are not monotonic")
    require(len(run_start) == len(run_end) == len(restored) == 1, "benchmark progress terminal event mismatch")
    require(len(starts) == len(ends) == EXPECTED_PERFORMANCE_ROWS, "benchmark progress case count mismatch")
    start = run_start[0]
    end = run_end[0]
    run_id = next(iter(run_ids))
    require(
        start["run_id"] == end["run_id"] == run_id
        and start["operator_count"] == EXPECTED_OPERATORS
        and start["platform"] == "ZHONGKEXIN"
        and start["scale_profile"] == "default"
        and start["scale_levels"] == sorted(EXPECTED_LEVELS)
        and start["warmup"] == 5
        and start["repeat"] == 30,
        "benchmark run-start policy mismatch",
    )
    require(
        end["status"] == "passed"
        and end["row_count"] == EXPECTED_PERFORMANCE_ROWS
        and end["failed_row_count"] == 0
        and restored[0]["restored_count"] == EXPECTED_OPERATORS,
        "benchmark terminal progress mismatch",
    )
    start_keys = [(event["module"], event["operator"], parse_int(event["scale_level"])) for event in starts]
    end_keys = [(event["module"], event["operator"], parse_int(event["scale_level"])) for event in ends]
    require(len(start_keys) == len(set(start_keys)) and set(start_keys) == set(indexed), "benchmark start event matrix mismatch")
    require(len(end_keys) == len(set(end_keys)) and set(end_keys) == set(indexed), "benchmark end event matrix mismatch")
    start_index = {
        (event["module"], event["operator"], parse_int(event["scale_level"])): event
        for event in starts
    }
    target_indices: dict[tuple[str, str], int] = {}
    for key, event in start_index.items():
        source = indexed[key]
        require(
            event["run_id"] == run_id
            and event["warmup"] == 5
            and event["repeat"] == 30
            and event["target_count"] == EXPECTED_OPERATORS
            and parse_int(event["scale_value"]) == parse_int(source["scale_value"])
            and event["scale_family"] == source["scale_family"],
            f"benchmark start event metadata mismatch: {key}",
        )
        operator_key = (key[0], key[1])
        target_index = parse_int(event["target_index"])
        previous = target_indices.setdefault(operator_key, target_index)
        require(previous == target_index, f"benchmark target index changed across scales: {operator_key}")
    require(set(target_indices.values()) == set(range(1, EXPECTED_OPERATORS + 1)), "benchmark target index topology mismatch")
    for event in ends:
        key = (event["module"], event["operator"], parse_int(event["scale_level"]))
        source = indexed[key]
        begin = start_index[key]
        require_true(event["passed"], f"benchmark end pass {key}")
        require(
            event["status"] == "passed"
            and event["return_code"] == 0
            and event["run_id"] == run_id
            and event["target_count"] == EXPECTED_OPERATORS
            and event["target_index"] == begin["target_index"]
            and parse_int(event["scale_value"]) == parse_int(source["scale_value"])
            and event["scale_family"] == source["scale_family"]
            and parse_float(event["duration_s"]) >= 0.0
            and parse_float(event["timestamp_unix"]) >= parse_float(begin["timestamp_unix"]),
            f"benchmark end status/metadata {key}",
        )
        require_close(parse_float(event["gpu_e2e_median_ms"]), parse_float(source["gpu_e2e_median_ms"]), f"benchmark progress E2E {key}")
        require_close(parse_float(event["gpu_kernel_median_ms"]), parse_float(source["gpu_kernel_median_ms"]), f"benchmark progress kernel {key}")

    expected_true_error_keys = {
        (entry["module"], entry["operator"], level)
        for entry in PASSED_TRUE_ERROR_DIAGNOSTIC_POLICY
        for level in entry["scale_levels"]
    }
    true_error_rows = [row for row in typed_rows if row["error_class"] == "true-error"]
    actual_true_error_keys = {
        (row["module"], row["operator"], row["scale_level"])
        for row in true_error_rows
    }
    require(
        actual_true_error_keys == expected_true_error_keys,
        "passed benchmark true-error diagnostic set mismatch",
    )
    error_class_counts: dict[str, int] = {}
    for row in typed_rows:
        error_class_counts[row["error_class"]] = error_class_counts.get(row["error_class"], 0) + 1
    l6_raw = validate_l6_raw_metrics(root, typed_rows, expected_operators)
    derived = {
        "expected_rows": EXPECTED_PERFORMANCE_ROWS,
        "benchmark_rows": len(rows),
        "operator_count": len({f"{row['module']}/{row['operator']}" for row in rows}),
        "scale_levels": sorted({parse_int(row["scale_level"]) for row in rows}),
        "passed_rows": len(rows),
        "failed_rows": 0,
        "run_ids": sorted(run_ids),
        "gpu_names": sorted(gpu_names),
        "warmup": 5,
        "repeat": 30,
        "progress_start_count": len(starts),
        "progress_end_count": len(ends),
        "failure_count": 0,
        "error_class_counts": error_class_counts,
        "passed_true_error_diagnostic_count": len(true_error_rows),
        "passed_true_error_diagnostics": [
            {
                "module": row["module"],
                "operator": row["operator"],
                "scale_level": row["scale_level"],
                "mixed_error": row["mixed_error"],
                "error_class": row["error_class"],
            }
            for row in sorted(
                true_error_rows,
                key=lambda item: (item["module"], item["operator"], item["scale_level"]),
            )
        ],
        "l6_raw_metrics": l6_raw,
    }
    return typed_rows, derived


def validate_telemetry(
    root: Path,
    performance: dict[str, Any],
    benchmark_rows: list[dict[str, Any]],
) -> dict[str, Any]:
    raw = read_json(root / "telemetry/dlsmi_summary.json")
    rows = read_table(root / "telemetry/dlsmi_samples.csv", delimiter=",")
    require_true(raw["available"], "V6 telemetry availability")
    require(rows, "V6 telemetry samples are empty")
    used = [parse_float(row["used_mib"]) for row in rows]
    total = [parse_float(row["total_mib"]) for row in rows]
    free = [parse_float(row["free_mib"]) for row in rows]
    utilization = [parse_float(row["util_percent"]) for row in rows]
    elapsed = [parse_float(row["elapsed_s"]) for row in rows]
    require(all(value >= 0.0 for value in used + total + free + utilization + elapsed), "negative V6 telemetry value")
    require(all(value <= 100.0 for value in utilization), "invalid V6 telemetry utilization")
    require(elapsed == sorted(elapsed) and len(elapsed) == len(set(elapsed)), "V6 telemetry elapsed time is not strictly increasing")
    timestamps = [datetime.fromisoformat(row["timestamp"]) for row in rows]
    require(timestamps == sorted(timestamps), "V6 telemetry timestamps are not monotonic")
    for used_value, total_value, free_value in zip(used, total, free):
        require(total_value > 0.0 and used_value <= total_value, "invalid V6 telemetry capacity")
        require_close(total_value - used_value, free_value, "V6 telemetry free memory")
    gpu_indices = {row["gpu_index"] for row in rows}
    require(gpu_indices == {"0"}, "V6 telemetry GPU identity mismatch")
    used_by_gpu: dict[str, list[float]] = {}
    for row in rows:
        used_by_gpu.setdefault(row["gpu_index"], []).append(parse_float(row["used_mib"]))
    comparisons = {
        "sample_count": len(rows),
        "gpu_count": len(gpu_indices),
        "duration_s": elapsed[-1],
        "used_mib_min": min(used),
        "used_mib_max": max(used),
        "used_mib_avg": statistics.fmean(used),
        "total_mib_max": max(total),
        "free_mib_min": min(free),
        "util_percent_max": max(utilization),
        "util_percent_avg": statistics.fmean(utilization),
    }
    for name, value in comparisons.items():
        if isinstance(value, int):
            require(raw[name] == value, f"V6 telemetry {name} mismatch")
        else:
            require_close(parse_float(raw[name]), value, f"V6 telemetry {name}")
    require(raw["started_at"] == rows[0]["timestamp"] and raw["ended_at"] == rows[-1]["timestamp"], "V6 telemetry timestamp mismatch")
    derived_delta = {gpu: values[-1] - values[0] for gpu, values in used_by_gpu.items()}
    derived_peak = {gpu: max(values) for gpu, values in used_by_gpu.items()}
    require(raw["used_mib_delta_by_gpu"] == derived_delta, "V6 telemetry per-GPU delta mismatch")
    require(raw["used_mib_peak_by_gpu"] == derived_peak, "V6 telemetry per-GPU peak mismatch")
    require(performance["telemetry_summary"] == raw, "performance telemetry summary differs from raw evidence")

    windows = read_table(root / "summary/operator_telemetry.tsv")
    require(len(windows) == EXPECTED_PERFORMANCE_ROWS, "operator telemetry row count mismatch")
    benchmark_index = {
        (row["module"], row["operator"], row["scale_level"]): row
        for row in benchmark_rows
    }
    window_keys: set[tuple[str, str, int]] = set()
    coverage = 0
    progress = read_json_lines(root / "telemetry/operator_windows.jsonl")
    progress_starts = {
        (event["module"], event["operator"], parse_int(event["scale_level"])): event
        for event in progress
        if event.get("event") == "case_start"
    }
    progress_ends = {
        (event["module"], event["operator"], parse_int(event["scale_level"])): event
        for event in progress
        if event.get("event") == "case_end"
    }
    sample_pairs = sorted(
        (datetime.fromisoformat(row["timestamp"]).timestamp(), row)
        for row in rows
        if row["gpu_index"] == "0"
    )
    sample_times = [timestamp for timestamp, _ in sample_pairs]
    for row in windows:
        key = (row["module"], row["operator"], parse_int(row["scale_level"]))
        require(key not in window_keys and key in benchmark_index, f"operator telemetry key mismatch: {key}")
        window_keys.add(key)
        require(key in progress_starts and key in progress_ends, f"operator telemetry progress window missing: {key}")
        start_time = parse_float(progress_starts[key]["timestamp_unix"])
        end_time = parse_float(progress_ends[key]["timestamp_unix"])
        left = bisect.bisect_left(sample_times, start_time)
        right = bisect.bisect_right(sample_times, end_time)
        window_samples = [sample for _, sample in sample_pairs[left:right]]
        sample_count = len(window_samples)
        require(parse_int(row["sample_count"]) == sample_count, f"operator telemetry sample count mismatch: {key}")
        coverage += int(sample_count > 0)
        source = benchmark_index[key]
        require(parse_int(row["scale_value"]) == source["scale_value"], f"operator telemetry scale value {key}")
        require_close(parse_float(row["window_duration_s"]), end_time - start_time, f"operator telemetry duration {key}")
        require_close(parse_float(row["gpu_e2e_median_ms"]), source["gpu_e2e_median_ms"], f"operator telemetry E2E {key}")
        require_close(parse_float(row["gpu_kernel_median_ms"]), source["gpu_kernel_median_ms"], f"operator telemetry kernel {key}")
        require_close(parse_float(row["fixed_overhead_ms"]), source["fixed_overhead_ms"], f"operator telemetry overhead {key}")
        used_values = [parse_float(sample["used_mib"]) for sample in window_samples]
        util_values = [parse_float(sample["util_percent"]) for sample in window_samples]
        active_values = [value for value in util_values if value > 0.0]
        derived_fields: dict[str, float | None] = {
            "used_mib_max": max(used_values) if used_values else None,
            "util_percent_max": max(util_values) if util_values else None,
            "util_percent_p95": nearest_rank(util_values, 0.95) if util_values else None,
            "active_util_median": statistics.median(active_values) if active_values else None,
            "active_sample_fraction": len(active_values) / sample_count if sample_count else None,
        }
        for name, value in derived_fields.items():
            if value is None:
                require(row[name] == "", f"operator telemetry optional field mismatch: {key}/{name}")
            else:
                require_close(parse_float(row[name]), value, f"operator telemetry field {key}/{name}")
    require(window_keys == set(benchmark_index), "operator telemetry matrix mismatch")
    return {**raw, "window_coverage_count": coverage, "window_coverage_fraction": coverage / len(windows)}


def derive_task_comparison(
    totals: list[dict[str, Any]],
    steps: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    warm_l6_totals = {
        row["task"]: row
        for row in totals
        if row["mode"] == "warm" and row["scale_level"] == 6
    }
    warm_l6_steps = {
        (row["task"], row["step"]): row
        for row in steps
        if row["mode"] == "warm" and row["scale_level"] == 6
    }
    result: list[dict[str, Any]] = []
    for task, baselines in TASK_BASELINES.items():
        for metric, baseline in baselines.items():
            if metric == "total":
                current = warm_l6_totals[task]["gpu_median_ms"]
                measurement = "warm_repeat5_median"
            else:
                current = warm_l6_steps[(task, metric)]["gpu_e2e_ms"]
                measurement = "warm_report_final_iteration"
            result.append(
                {
                    "task": task,
                    "metric": metric,
                    "baseline_ms": baseline,
                    "current_ms": current,
                    "reduction_percent": (baseline - current) / baseline * 100.0,
                    "measurement": measurement,
                }
            )
    return result


def validate_performance_summary(
    root: Path,
    performance: dict[str, Any],
    benchmark_rows: list[dict[str, Any]],
    derived_summary: dict[str, Any],
    telemetry: dict[str, Any],
    task_comparison: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    require(performance["status"] == "passed" and performance["failures"] == [], "performance summary failed")
    summary = performance["summary"]
    upstream_summary_fields = {
        "expected_rows",
        "benchmark_rows",
        "operator_count",
        "scale_levels",
        "passed_rows",
        "failed_rows",
        "run_ids",
        "gpu_names",
        "warmup",
        "repeat",
        "progress_start_count",
        "progress_end_count",
        "failure_count",
    }
    for name in upstream_summary_fields:
        value = derived_summary[name]
        require(summary[name] == value, f"performance summary mismatch: {name}")
    require(summary["telemetry_gpu_index"] == "0", "performance telemetry GPU mismatch")
    require(summary["telemetry_sample_count"] == telemetry["sample_count"], "performance telemetry count mismatch")
    require(summary["telemetry_window_coverage_count"] == telemetry["window_coverage_count"], "performance coverage count mismatch")
    require_close(summary["telemetry_window_coverage_fraction"], telemetry["window_coverage_fraction"], "performance coverage fraction")

    summary_comparison = performance["task_comparison"]
    tsv_rows = read_table(root / "summary/task_comparison.tsv")
    require(len(summary_comparison) == len(tsv_rows) == len(task_comparison), "task comparison row count mismatch")
    for derived, summary_row, tsv in zip(task_comparison, summary_comparison, tsv_rows):
        require(derived["task"] == summary_row["task"] == tsv["task"], "task comparison task mismatch")
        require(derived["metric"] == summary_row["metric"] == tsv["metric"], "task comparison metric mismatch")
        require(derived["measurement"] == summary_row["measurement"] == tsv["measurement"], "task comparison measurement mismatch")
        for name in ("baseline_ms", "current_ms", "reduction_percent"):
            require_close(derived[name], parse_float(summary_row[name]), f"task comparison summary {name}")
            require_close(derived[name], parse_float(tsv[name]), f"task comparison TSV {name}")

    l6_derived = sorted(
        [row for row in benchmark_rows if row["scale_level"] == 6],
        key=lambda row: row["gpu_e2e_median_ms"],
        reverse=True,
    )
    require(len(l6_derived) == EXPECTED_OPERATORS, "L6 hotspot row count mismatch")
    l6_summary = performance["l6_hotspots"]
    l6_tsv = read_table(root / "summary/l6_hotspots.tsv")
    require(len(l6_summary) == len(l6_tsv) == len(l6_derived), "L6 hotspot evidence count mismatch")
    numeric_fields = (
        "scale_value",
        "gpu_e2e_median_ms",
        "gpu_kernel_median_ms",
        "fixed_overhead_ms",
        "cpu_median_ms",
        "gpu_e2e_speedup",
        "gpu_kernel_speedup",
        "mixed_error",
    )
    for derived, summary_row, tsv in zip(l6_derived, l6_summary, l6_tsv):
        require(derived["module"] == summary_row["module"] == tsv["module"], "L6 hotspot module mismatch")
        require(derived["operator"] == summary_row["operator"] == tsv["operator"], "L6 hotspot operator mismatch")
        for name in numeric_fields:
            require_close(parse_float(derived[name]), parse_float(summary_row[name]), f"L6 hotspot summary {name}")
            require_close(parse_float(derived[name]), parse_float(tsv[name]), f"L6 hotspot TSV {name}")
    return l6_derived


def validate_runtime(root: Path) -> dict[str, Any]:
    rows = read_table(root / "platform/runtime_probe.tsv")
    fields = [row["field"] for row in rows]
    require(len(fields) == len(set(fields)), "runtime probe contains duplicate fields")
    runtime = {row["field"]: row["value"] for row in rows}
    graph_fields = [
        "graph_capture_begin_status",
        "graph_capture_work_status",
        "graph_capture_end_status",
        "graph_instantiate_status",
        "graph_launch_status",
        "graph_sync_status",
    ]
    statuses = {field: parse_int(runtime[field]) for field in graph_fields}
    require(all(value == 0 for value in statuses.values()), "GPU Graph lifecycle probe failed")
    require(parse_bool(runtime["valid_lifecycle_result"]), "GPU Graph lifecycle result failed")
    return {"graph_lifecycle_statuses": statuses, "valid_lifecycle_result": True}


def derive_residual_bottlenecks(benchmark_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    indexed = {
        (row["module"], row["operator"], row["scale_level"]): row
        for row in benchmark_rows
    }
    result: list[dict[str, Any]] = []
    for target in RESIDUAL_TARGETS:
        key = (target["module"], target["operator"], target["scale_level"])
        require(key in indexed, f"missing residual bottleneck evidence: {key}")
        row = indexed[key]
        result.append(
            {
                "operator": f"{target['module']}/{target['operator']}",
                "scale_level": target["scale_level"],
                "scale_value": row["scale_value"],
                "shape_note": row["shape_note"],
                "gpu_e2e_median_ms": row["gpu_e2e_median_ms"],
                "gpu_kernel_median_ms": row["gpu_kernel_median_ms"],
                "fixed_overhead_ms": row["fixed_overhead_ms"],
                "assessment": target["assessment"],
            }
        )
    return result


def gate_row(item: str, result: str, evidence: str) -> str:
    return f"| {item} | {result} | {evidence} |"


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as handle:
        temporary = Path(handle.name)
        handle.write(content)
    try:
        temporary.replace(path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def report_file_inventory(report_root: Path) -> set[Path]:
    if not report_root.exists():
        return set()
    require(report_root.is_dir() and not report_root.is_symlink(), "report root must be a real directory")
    files: set[Path] = set()
    for path in report_root.rglob("*"):
        require(not path.is_symlink(), f"report tree contains symlink: {path}")
        require(path.is_dir() or path.is_file(), f"report tree contains special node: {path}")
        if path.is_file():
            files.add(path)
    return files


def write_report_readme(report_root: Path) -> None:
    lines = [
        "# 终测报告目录",
        "",
        "仓库内只保留最终汇总；完整日志、长表、图件和容器取回内容位于",
        "`/home/usr_04/CETC_garbage/`。",
        "",
        "| 版本 | Markdown | JSON |",
        "| --- | --- | --- |",
        "| V5.5 | `zhongkexin/v5_5_final/summary.md` | `zhongkexin/v5_5_final/summary.json` |",
        "| V6 | `zhongkexin/v6_final/summary.md` | `zhongkexin/v6_final/summary.json` |",
        "| V7 | `zhongkexin/v7_final/summary.md` | `zhongkexin/v7_final/summary.json` |",
        "",
        "禁止在此目录长期保留 unit/demo 中间报告、benchmark 长表、probe 日志和图件。",
    ]
    atomic_write(report_root / "README.md", "\n".join(lines) + "\n")


def main() -> int:
    args = parse_args()
    source_root = Path(__file__).resolve().parents[2]
    requested_source_root = canonical_input_path(args.source_root, "source root")
    require(requested_source_root == source_root, "source root must contain this V6 finalizer")
    manifest_path = (
        canonical_input_path(args.evidence_manifest, "V6 evidence manifest")
        if args.evidence_manifest
        else source_root / "scripts/platform/v6_final_evidence_manifest.json"
    )
    evidence_manifest = load_evidence_manifest(manifest_path, source_root)
    operator_policy = load_operator_policy(source_root)
    task_policy = load_task_contract_policy(source_root)
    type_policy = load_type_contract_policy(source_root, operator_policy)
    preflight_root = canonical_input_path(args.preflight_root, "V6-0138 root")
    performance_root = canonical_input_path(args.performance_root, "V6-0141 root")
    preflight_archive = canonical_input_path(args.preflight_archive, "V6-0138 archive")
    preflight_console = canonical_input_path(args.preflight_console, "V6-0138 console")
    performance_archive = canonical_input_path(args.performance_archive, "V6-0141 archive")
    performance_console = canonical_input_path(args.performance_console, "V6-0141 console")

    frozen_inputs = {
        "V6-0138": (preflight_root, preflight_archive, preflight_console),
        "V6-0141": (performance_root, performance_archive, performance_console),
    }
    frozen_hashes: dict[str, dict[str, str]] = {}
    for execution_id, (root, archive, console) in frozen_inputs.items():
        entry = evidence_manifest["runs"][execution_id]
        validate_frozen_run_inputs(execution_id, root, archive, console, entry)
        archive_hash = validate_archive(
            archive,
            root,
            archive_evidence_files(execution_id, operator_policy),
        )
        console_hash = validate_console(
            console,
            {
                f"OUT=/tmp/{root.name}",
                f"ARCHIVE=/tmp/{root.name}.tar.gz",
                f"LATEST_ARCHIVE=/tmp/{entry['archive_name']}",
                "ARCHIVE_RC=0",
                "OVERALL_RC=0",
            },
        )
        frozen_hashes[execution_id] = {
            "archive_sha256": archive_hash,
            "console_sha256": console_hash,
        }

    v5_summary_markdown = Path(args.v5_summary_markdown).resolve()
    v5_summary_json = Path(args.v5_summary_json).resolve()
    report_root = Path(args.report_root).resolve()
    output_dir = Path(args.output_dir).resolve()

    expected_v5_markdown = report_root / "zhongkexin/v5_5_final/summary.md"
    expected_v5_json = report_root / "zhongkexin/v5_5_final/summary.json"
    expected_output_dir = report_root / "zhongkexin/v6_final"
    require(
        v5_summary_markdown == expected_v5_markdown.resolve(),
        "v5-summary-markdown must use the final report path",
    )
    require(
        v5_summary_json == expected_v5_json.resolve(),
        "v5-summary-json must use the final report path",
    )
    require(
        output_dir == expected_output_dir.resolve(),
        "output-dir must use the final report path",
    )
    require(not (report_root / "unit").exists(), "data/reports/unit must not exist")
    require(not (report_root / "demo").exists(), "data/reports/demo must not exist")
    v5_sources: tuple[Path, Path] | None = None
    if args.v5_source_dir:
        v5_source_dir = canonical_input_path(args.v5_source_dir, "V5.5 source directory")
        source_markdown = v5_source_dir / "summary.md"
        source_json = v5_source_dir / "summary.json"
        predecessor = evidence_manifest["predecessor_reports"]
        require(
            sha256(source_markdown) == predecessor["v5_5_summary_md_sha256"],
            "V5.5 source Markdown SHA256 mismatch",
        )
        require(
            sha256(source_json) == predecessor["v5_5_summary_json_sha256"],
            "V5.5 source JSON SHA256 mismatch",
        )
        v5_sources = (source_markdown, source_json)
    allowed = {
        report_root / "README.md",
        expected_v5_markdown,
        expected_v5_json,
        output_dir / "summary.md",
        output_dir / "summary.json",
    }
    preexisting = report_file_inventory(report_root)
    require(
        preexisting <= allowed,
        f"unexpected pre-existing report files: {sorted(preexisting - allowed)}",
    )

    validate_status_table(preflight_root, "V6-0138")
    validate_status_table(performance_root, "V6-0141")
    validate_embedded_preflight_reference(performance_root, preflight_root, evidence_manifest)
    for root in (preflight_root, performance_root):
        require_empty(root / "manifest_diff.log")
        require_empty(root / "reports_diff.log")
    require_empty(performance_root / "preflight/product_source_diff.log")
    manifest_dtypes = validate_manifest_inventory(preflight_root, source_root, operator_policy)
    audit_results = validate_all81_and_audits(
        preflight_root,
        operator_policy,
        task_policy,
        type_policy,
        manifest_dtypes,
    )
    task_totals, task_steps, l6_steps = validate_task_matrix(preflight_root)
    runtime_results = validate_runtime(preflight_root)

    performance = read_json(performance_root / "summary/summary.json")
    benchmark_rows, derived_perf_summary = validate_benchmark(performance_root, operator_policy)
    telemetry = validate_telemetry(performance_root, performance, benchmark_rows)
    task_comparison = derive_task_comparison(task_totals, task_steps)
    l6_hotspots = validate_performance_summary(
        performance_root,
        performance,
        benchmark_rows,
        derived_perf_summary,
        telemetry,
        task_comparison,
    )
    perf_summary = performance["summary"]
    all_level_hotspots = sorted(
        benchmark_rows,
        key=lambda row: row["gpu_e2e_median_ms"],
        reverse=True,
    )

    preflight_product = read_sha256_inventory(
        performance_root / "preflight/product_source_sha256.txt",
        "V6-0138 product source inventory",
    )
    current_product = read_sha256_inventory(
        performance_root / "fingerprint/product_source_sha256.sorted.txt",
        "V6-0141 product source inventory",
    )
    product_source_match = preflight_product == current_product
    require(product_source_match, "product source fingerprints differ")
    manifest_diff_count = sum(
        bool((root / "manifest_diff.log").read_text(encoding="utf-8"))
        for root in (preflight_root, performance_root)
    )
    report_diff_count = sum(
        bool((root / "reports_diff.log").read_text(encoding="utf-8"))
        for root in (preflight_root, performance_root)
    )

    if v5_sources is not None:
        expected_v5_markdown.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(v5_sources[0], expected_v5_markdown)
        shutil.copy2(v5_sources[1], expected_v5_json)
    v5_payload = read_json(v5_summary_json)
    require(v5_payload.get("status") == "passed", "V5.5 summary is not passed")
    predecessor = evidence_manifest["predecessor_reports"]
    require(sha256(v5_summary_markdown) == predecessor["v5_5_summary_md_sha256"], "V5.5 Markdown trust anchor mismatch")
    require(sha256(v5_summary_json) == predecessor["v5_5_summary_json_sha256"], "V5.5 JSON trust anchor mismatch")

    evidence = {
        "evidence_manifest": {
            "path": str(manifest_path),
            "sha256": sha256(manifest_path),
        },
        "v6_0138": {
            "root": str(preflight_root),
            "archive": str(preflight_archive),
            "console": str(preflight_console),
            **frozen_hashes["V6-0138"],
        },
        "v6_0141": {
            "root": str(performance_root),
            "archive": str(performance_archive),
            "console": str(performance_console),
            **frozen_hashes["V6-0141"],
        },
        "v5_5_restored_summary": {
            "markdown": "data/reports/zhongkexin/v5_5_final/summary.md",
            "markdown_sha256": sha256(v5_summary_markdown),
            "json": "data/reports/zhongkexin/v5_5_final/summary.json",
            "json_sha256": sha256(v5_summary_json),
        },
        "product_source_inventory_sha256": sha256(
            performance_root / "fingerprint/product_source_sha256.sorted.txt"
        ),
    }
    residual_bottlenecks = derive_residual_bottlenecks(benchmark_rows)
    task_summary = {"case_count": len(task_totals), "step_row_count": len(task_steps)}

    payload = {
        "schema_version": "v6_final_summary_v2",
        "status": "passed",
        "version": "V6.8",
        "evidence_run_id": derived_perf_summary["run_ids"][0],
        "conclusion": {
            "v6_closed": True,
            "terminal_product_source_fingerprint_match": product_source_match,
            "reason": (
                "V6-0138 hard gates and V6-0141 all81 performance terminal both "
                "passed on an identical product-source fingerprint."
            ),
        },
        "historical_policy": {
            "retained_v6_7_direction_count": EXPECTED_RETAINED_DIRECTIONS,
            "v6_1_task_baseline_ms": TASK_BASELINES,
            "residual_assessment_policy": RESIDUAL_TARGETS,
        },
        "gates": {
            "all81_correctness": {
                "status": "passed",
                "operators": audit_results["all81_passed"],
                "failed": EXPECTED_OPERATORS - audit_results["all81_passed"],
            },
            "interfaces": {
                "status": "passed",
                "operators": audit_results["interface_passed"],
                "compatibility_gap_count": audit_results["compatibility_gap_count"],
            },
            "dtype": {
                "status": "passed",
                "operator_dtype_missing_edges": audit_results["dtype_missing_edges"],
            },
            "tasks": {
                "status": "passed",
                "case_count": len(task_totals),
                "step_row_count": len(task_steps),
                "calculation_step_count": audit_results["calculation_steps"],
                "public_calculation_step_count": audit_results["public_calculation_steps"],
                "mixed_calculation_step_count": audit_results["mixed_calculation_steps"],
                "public_operator_link_declaration_count": audit_results["public_operator_link_declarations"],
                "failure_count": sum(not row["validation_pass"] for row in task_totals)
                + sum(not row["pass"] for row in task_steps),
            },
            "all81_performance": {
                "status": "passed",
                "row_count": derived_perf_summary["benchmark_rows"],
                "operators": derived_perf_summary["operator_count"],
                "scale_levels": len(derived_perf_summary["scale_levels"]),
                "warmup": derived_perf_summary["warmup"],
                "repeat": derived_perf_summary["repeat"],
                "failed_rows": derived_perf_summary["failed_rows"],
                "passed_true_error_diagnostic_count": derived_perf_summary["passed_true_error_diagnostic_count"],
                "l6_raw_metrics": derived_perf_summary["l6_raw_metrics"],
            },
            "platform": {
                "status": "passed",
                **runtime_results,
            },
            "integrity": {
                "status": "passed",
                "manifest_diff_count": manifest_diff_count,
                "report_diff_count": report_diff_count,
                "product_source_match": product_source_match,
            },
        },
        "task_comparison_v6_1_to_v6_8": task_comparison,
        "task_totals": task_totals,
        "task_warm_l6_steps": l6_steps,
        "all81_l6_hotspots": l6_hotspots[:20],
        "all81_all_level_hotspots": all_level_hotspots[:20],
        "benchmark_diagnostics": {
            "error_class_counts": derived_perf_summary["error_class_counts"],
            "passed_true_error_rows": derived_perf_summary["passed_true_error_diagnostics"],
            "policy": PASSED_TRUE_ERROR_DIAGNOSTIC_POLICY,
        },
        "telemetry": telemetry,
        "residual_bottlenecks": residual_bottlenecks,
        "measurement_limits": [
            (
                "The V6.1 all81 archive used warmup=1/repeat=3, while V6.8 used "
                "warmup=5/repeat=30; no formal all81 percentage is published."
            ),
            (
                "dlsmi sampled externally at low frequency and covered "
                f"{perf_summary['telemetry_window_coverage_count']}/"
                f"{perf_summary['benchmark_rows']} operator windows; it is not "
                "a kernel profiler."
            ),
            (
                "The full terminal includes CPU reference execution and gaps "
                "between operators, so average GPU utilization does not measure "
                "kernel efficiency."
            ),
            (
                "V6-0141 retained per-operator latest_metrics.json only for L6. "
                "L1-L5 are bound to the frozen CSV/progress/console evidence and "
                "cannot be independently reconstructed from raw repeat samples."
            ),
            (
                f"L6 binds {derived_perf_summary['l6_raw_metrics']['bound_metrics_count']} "
                "operator metrics files; "
                f"{derived_perf_summary['l6_raw_metrics']['summary_only_operator_count']} "
                "operators contain summary-only timing without case detail."
            ),
        ],
        "evidence": evidence,
    }

    gates = payload["gates"]
    total_comparison = {
        row["task"]: row
        for row in task_comparison
        if row["metric"] == "total"
    }
    gate_lines = [
        gate_row(
            "all81 correctness",
            f"{gates['all81_correctness']['operators']}/{EXPECTED_OPERATORS}，失败 {gates['all81_correctness']['failed']}",
            "V6-0138",
        ),
        gate_row(
            "接口与类型",
            f"接口 {gates['interfaces']['operators']}/{EXPECTED_OPERATORS}，兼容缺口 {gates['interfaces']['compatibility_gap_count']}",
            "V6-0138",
        ),
        gate_row("dtype", f"operator_dtype_missing_edges={gates['dtype']['operator_dtype_missing_edges']}", "V6-0138"),
        gate_row(
            "Task1/Task2",
            f"{gates['tasks']['case_count']}/{EXPECTED_TASK_CASES} 用例，{gates['tasks']['step_row_count']}/{EXPECTED_TASK_STEPS} 分步；14 个计算步骤中 public={gates['tasks']['public_calculation_step_count']}、mixed={gates['tasks']['mixed_calculation_step_count']}，失败 {gates['tasks']['failure_count']}",
            "V6-0138",
        ),
        gate_row(
            "all81 L1-L6",
            f"{gates['all81_performance']['row_count']}/{EXPECTED_PERFORMANCE_ROWS}，warmup={gates['all81_performance']['warmup']}，repeat={gates['all81_performance']['repeat']}",
            "V6-0141",
        ),
        gate_row("平台", "CUDA Graph 六阶段状态均为 0", "V6-0138"),
        gate_row(
            "完整性",
            f"manifest/report diff {gates['integrity']['manifest_diff_count']}/{gates['integrity']['report_diff_count']}，产品源码指纹一致",
            "V6-0138/0141",
        ),
    ]
    markdown = [
        "# V6 最终终测汇总",
        "",
        "## 结论",
        "",
        "- 状态：`passed`，V6.8 已关闭。",
        "- V6-0138 硬门和 V6-0141 性能终测使用相同产品源码指纹，全部返回 0。",
        f"- 冻结历史政策记录 V6.7 正式保留 {payload['historical_policy']['retained_v6_7_direction_count']} 个优化方向；该数量不是由 V6-0138/0141 测量反推。",
        f"- Task1 L6 warm median 为 `{total_comparison['task1_radar']['current_ms']:.5f} ms`，相对 V6.1 下降 `{total_comparison['task1_radar']['reduction_percent']:.2f}%`。",
        f"- Task2 L6 warm median 为 `{total_comparison['task2_features']['current_ms']:.4f} ms`，相对 V6.1 下降 `{total_comparison['task2_features']['reduction_percent']:.2f}%`。",
        "",
        "## 硬门",
        "",
        "| 项目 | 结果 | 证据 |",
        "| --- | --- | --- |",
        *gate_lines,
        "",
        "## 任务 L6 对照",
        "",
        "| 任务 | 指标 | V6.1 ms | V6.8 ms | 降幅 | 口径 |",
        "| --- | --- | ---: | ---: | ---: | --- |",
    ]
    for row in task_comparison:
        markdown.append(
            f"| {row['task']} | {row['metric']} | {row['baseline_ms']:.6f} | "
            f"{row['current_ms']:.6f} | {row['reduction_percent']:.2f}% | "
            f"{row['measurement']} |"
        )

    markdown.extend(
        [
            "",
            "## 任务 L1-L6 总时间",
            "",
            "| 模式 | 任务 | 规模 | GPU first ms | GPU median ms | GPU P95 ms |",
            "| --- | --- | ---: | ---: | ---: | ---: |",
        ]
    )
    for row in task_totals:
        markdown.append(
            f"| {row['mode']} | {row['task']} | L{row['scale_level']} | "
            f"{row['gpu_first_ms']:.6f} | {row['gpu_median_ms']:.6f} | "
            f"{row['gpu_p95_ms']:.6f} |"
        )

    markdown.extend(
        [
            "",
            "## L6 任务步骤",
            "",
            "| 任务 | 步骤 | GPU E2E ms | mixed error | max abs |",
            "| --- | --- | ---: | ---: | ---: |",
        ]
    )
    for row in l6_steps:
        markdown.append(
            f"| {row['task']} | {row['step']} | {row['gpu_e2e_ms']:.6f} | "
            f"{row['mixed_error']:.6e} | {row['max_abs']:.6e} |"
        )

    markdown.extend(
        [
            "",
            "## all81 性能终测",
            "",
            f"- runner 用例门：{gates['all81_performance']['operators']} 个算子 × {gates['all81_performance']['scale_levels']} 个规模，共 `{gates['all81_performance']['row_count']}/{EXPECTED_PERFORMANCE_ROWS}` 行 `status/pass=passed/true`，失败行 0。",
            f"- 正式计时：warmup=`{gates['all81_performance']['warmup']}`，repeat=`{gates['all81_performance']['repeat']}`，GPU 为 `{derived_perf_summary['gpu_names'][0]}`。",
            f"- L6 已绑定 `{derived_perf_summary['l6_raw_metrics']['bound_metrics_count']}` 份逐算子 `latest_metrics.json`；其中 `{derived_perf_summary['l6_raw_metrics']['summary_only_operator_count']}` 份没有 case-level 明细。L6 也只保存聚合统计，未保留 30 次 timing 原始样本或输出数组；L1-L5 归档仅保留冻结 CSV、progress 和 console。",
            "- V6.1 all81 历史包使用 warmup=`1`、repeat=`3`，与本轮协议不同，因此不发布全库百分比。",
            "",
            "### 精度诊断边界",
            "",
            f"- 与 perf 执行门分开统计：benchmark-wide `mixed_error > {BENCHMARK_TRUE_ERROR_THRESHOLD:g}` 的 `true-error` 诊断共 `{derived_perf_summary['passed_true_error_diagnostic_count']}` 行。独立 all81 accuracy case 按历史校准容差通过，但 V6-0141 perf runner 不以误差判失败；因此这些 `spectral/coherence` L1-L5 行不能静默写成‘无异常’。",
            "",
            "| 算子 | 规模 | mixed error | runner gate | 全局诊断 |",
            "| --- | ---: | ---: | --- | --- |",
            *[
                f"| {row['module']}/{row['operator']} | L{row['scale_level']} | {row['mixed_error']:.6g} | passed | {row['error_class']} |"
                for row in derived_perf_summary["passed_true_error_diagnostics"]
            ],
            "",
            "### 全规模热点",
            "",
            "| 全规模热点 | 规模 | E2E ms | kernel ms | 固定开销 ms |",
            "| --- | --- | ---: | ---: | ---: |",
        ]
    )
    for row in all_level_hotspots[:12]:
        markdown.append(
            f"| {row['module']}/{row['operator']} | L{row['scale_level']} "
            f"({row['scale_value']}) | {row['gpu_e2e_median_ms']:.6f} | "
            f"{row['gpu_kernel_median_ms']:.6f} | "
            f"{row['fixed_overhead_ms']:.6f} |"
        )

    used_fraction = (
        parse_float(telemetry["used_mib_max"])
        / parse_float(telemetry["total_mib_max"])
        * 100.0
    )
    markdown.extend(
        [
            "",
            "## GPU 资源",
            "",
            f"- dlsmi 样本 `{telemetry['sample_count']}`，持续 `{telemetry['duration_s']:.2f} s`。",
            f"- 显存峰值 `{telemetry['used_mib_max']:.0f}/{telemetry['total_mib_max']:.0f} MiB`，约 `{used_fraction:.2f}%`。",
            f"- 瞬时 GPU utilization 最大 `{telemetry['util_percent_max']:.0f}%`。",
            f"- 逐算子时间窗覆盖 `{perf_summary['telemetry_window_coverage_count']}/{perf_summary['benchmark_rows']}`。",
            "- 平均利用率包含 CPU 参考执行和算子切换空隙，不能据此判断 kernel 未吃满。",
            "",
            "## 剩余瓶颈",
            "",
            *[
                f"- `{item['operator']}` L{item['scale_level']}（{item['shape_note']}）为 `{item['gpu_e2e_median_ms']:.6f}/{item['gpu_kernel_median_ms']:.6f} ms`（E2E/kernel）；{item['assessment']}。"
                for item in residual_bottlenecks
            ],
            "",
            "## 证据",
            "",
            f"- V6-0138：`{preflight_root}`；归档 SHA256 `{evidence['v6_0138']['archive_sha256']}`。",
            f"- V6-0138 console SHA256 `{evidence['v6_0138']['console_sha256']}`。",
            f"- V6-0141：`{performance_root}`；归档 SHA256 `{evidence['v6_0141']['archive_sha256']}`。",
            f"- V6-0141 console SHA256 `{evidence['v6_0141']['console_sha256']}`。",
            f"- 冻结信任锚 `{manifest_path}`；SHA256 `{evidence['evidence_manifest']['sha256']}`。",
            "",
            "## 报告治理",
            "",
            "- 最终仓库内只保留 README 与 V5.5/V6/V7 的 `summary.md/json`。",
            "- all81 长表、逐算子 telemetry、任务 168 行明细、日志和容器归档保留在仓库外证据目录。",
        ]
    )
    atomic_write(
        output_dir / "summary.json",
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    )
    atomic_write(output_dir / "summary.md", "\n".join(markdown) + "\n")
    write_report_readme(report_root)

    actual = report_file_inventory(report_root)
    require(
        actual == allowed,
        f"unexpected final report files: {sorted(actual - allowed)}",
    )

    print(
        json.dumps(
            {
                "status": "passed",
                "output_dir": str(output_dir),
                "report_file_count": len(actual),
                "all81_rows": perf_summary["benchmark_rows"],
                "task_cases": task_summary["case_count"],
                "task_steps": task_summary["step_row_count"],
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
