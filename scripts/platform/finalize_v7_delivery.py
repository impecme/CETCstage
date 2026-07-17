#!/usr/bin/env python3

"""Validate frozen V7 evidence and write the compact final delivery summary."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import re
import statistics
import tarfile
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any


EXPECTED_OPERATORS = 81
EXPECTED_CALCULATION_STEPS = 14
EXPECTED_TOP_OPERATORS = 30
EXPECTED_BUFFER_REPEATS_PER_ROUND = 5
EXPECTED_FINAL_EXECUTION_ID = "V7-0011"
DEMO_WALL_LIMIT_SECONDS = 240.0
TASK1_L6_MAX_MEDIAN_MS = 4.5
TASK2_L6_MAX_MEDIAN_MS = 23.0
TOP30_MINIMUM_SPEEDUP = 1.0
TOP30_MINIMUM_MEDIAN_SPEEDUP = 20.0
MINIMUM_MEMORY_HEADROOM_MIB = 512.0
CACHE_MINIMUM_AGGREGATE_GAIN = 0.02
CACHE_MAXIMUM_SINGLE_REGRESSION = 0.05
CORRELATE_ORIGINAL_MIN_FILTER_GAIN = 0.20
CORRELATE_ORIGINAL_MIN_TOTAL_GAIN_L3_L6 = (0.15, 0.12)
CORRELATE_MIN_HOTSPOT_GAIN = 0.30
CORRELATE_MIN_TOTAL_GAIN_L3_L6 = (0.15, 0.08)
CANDIDATE_NUMERIC_MIXED_ERROR_LIMIT = 1.0e-4
BUFFER_MIN_TOTAL_GAIN = 0.05
SPECTROGRAM_ORIGINAL_MIN_HOTSPOT_GAIN = {"L3": 0.20, "L5": 0.25, "L6": 0.25}
SPECTROGRAM_ORIGINAL_MIN_TOTAL_GAIN = {"L3": 0.03, "L5": 0.05, "L6": 0.05}
CWT_ORIGINAL_MIN_HOTSPOT_GAIN = {"L3": 0.20, "L5": 0.20, "L6": 0.20}
CWT_ORIGINAL_MIN_TOTAL_GAIN = {"L3": 0.03, "L5": 0.05, "L6": 0.05}
DEFAULT_CACHE_ENVIRONMENT = {
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS": "8",
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB": "512",
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB": "256",
}
V7_0008_SOURCE_FINGERPRINT_PATHS = [
    "demo/task1_radar/task1_radar_demo.cpp",
    "demo/task2_features/task2_features_demo.cpp",
    "demo/task2_features/task2_features_zx_gpu.cu",
    "demo/task2_features/task2_features_zx_gpu.hpp",
    "scripts/platform/run_v7_4_demo_budget.sh",
    "scripts/platform/select_v7_4_cache_mode.py",
    "scripts/platform/summarize_v7_4_demo.py",
    "scripts/test/benchmark_all_ops_scales.py",
    "scripts/test/operator_sets.json",
]
V7_0008_SUPERSEDED_SOURCE_PATH = "demo/task1_radar/task1_radar_demo.cpp"
V6_EXPECTED_POLICY_FILES = {
    "scripts/test/operator_sets.json",
    "scripts/test/task_step_contracts.json",
    "scripts/test/operator_type_contracts.json",
    "tests/unit/core_types/test_type_contracts.cu",
}
V6_EXPECTED_ACCEPTANCE_POLICY_KEYS = {
    "all81_operator_count",
    "calculation_step_count",
    "task_case_count",
    "task_step_row_count",
    "performance_row_count",
    "performance_scale_levels",
    "performance_warmup",
    "performance_repeat",
    "retained_v6_7_direction_count",
    "v6_1_task_baseline_ms",
    "residual_assessment_policy",
    "benchmark_true_error_threshold",
    "passed_true_error_diagnostic_policy",
    "l6_summary_only_operator_policy",
    "task_check_policy",
    "task_report_step_policy",
}
V6_EXPECTED_TRUE_ERROR_DIAGNOSTICS = {
    ("spectral", "coherence", scale_level)
    for scale_level in range(1, 6)
}

# These are frozen acceptance-policy values, not measured results. Every timing,
# speedup, count, failure reason, and retained/rejected outcome below is derived
# again from the supplied evidence and checked against these policies.
RUN_ROOT_PATTERNS = {
    "V7-0005": r"cetc_v7_0005_task2_fft_\d{8}_\d{6}",
    "V7-0006": r"cetc_v7_0006_spectrogram_\d{8}_\d{6}",
    "V7-0007": r"cetc_v7_0007_cwt_symmetry_\d{8}_\d{6}",
    "V7-0008": r"cetc_v7_0008_demo_budget_\d{8}_\d{6}",
    "V7-0009": r"cetc_v7_0009_task1_buffer_reuse_\d{8}_\d{6}",
    "V7-0010": r"cetc_v7_0010_task1_buffer_reuse_\d{8}_\d{6}",
}

EXPECTED_ACCEPTANCE_POLICY = {
    "all81_operator_count": EXPECTED_OPERATORS,
    "calculation_step_count": EXPECTED_CALCULATION_STEPS,
    "top_operator_count": EXPECTED_TOP_OPERATORS,
    "demo_wall_limit_seconds": DEMO_WALL_LIMIT_SECONDS,
    "task1_l6_max_median_ms": TASK1_L6_MAX_MEDIAN_MS,
    "task2_l6_max_median_ms": TASK2_L6_MAX_MEDIAN_MS,
    "top30_minimum_speedup": TOP30_MINIMUM_SPEEDUP,
    "top30_minimum_median_speedup": TOP30_MINIMUM_MEDIAN_SPEEDUP,
    "minimum_memory_headroom_mib": MINIMUM_MEMORY_HEADROOM_MIB,
    "cache_minimum_aggregate_gain": CACHE_MINIMUM_AGGREGATE_GAIN,
    "cache_maximum_single_regression": CACHE_MAXIMUM_SINGLE_REGRESSION,
    "correlate_original_minimum_filter_gain": CORRELATE_ORIGINAL_MIN_FILTER_GAIN,
    "correlate_original_minimum_total_gain_l3_l6": list(CORRELATE_ORIGINAL_MIN_TOTAL_GAIN_L3_L6),
    "correlate_original_expected_failure_set": [
        "L3_filter_gain",
        "L3_numeric",
        "L6_filter_gain",
        "L6_numeric",
    ],
    "correlate_minimum_hotspot_gain": CORRELATE_MIN_HOTSPOT_GAIN,
    "correlate_minimum_total_gain_l3_l6": list(CORRELATE_MIN_TOTAL_GAIN_L3_L6),
    "candidate_numeric_mixed_error_limit": CANDIDATE_NUMERIC_MIXED_ERROR_LIMIT,
    "spectrogram_original_minimum_hotspot_gain": SPECTROGRAM_ORIGINAL_MIN_HOTSPOT_GAIN,
    "spectrogram_original_minimum_total_gain": SPECTROGRAM_ORIGINAL_MIN_TOTAL_GAIN,
    "spectrogram_original_expected_failure_set": ["L5_spectrogram_gain", "L5_total_gain"],
    "spectrogram_retention_minimum_gain_exclusive": 0.0,
    "cwt_original_minimum_hotspot_gain": CWT_ORIGINAL_MIN_HOTSPOT_GAIN,
    "cwt_original_minimum_total_gain": CWT_ORIGINAL_MIN_TOTAL_GAIN,
    "cwt_original_expected_failure_set": [
        "L3_cwt_gain",
        "L5_cwt_gain",
        "L5_total_gain",
        "L6_cwt_gain",
        "L6_total_gain",
    ],
    "buffer_repeats_per_round": EXPECTED_BUFFER_REPEATS_PER_ROUND,
    "buffer_minimum_total_gain_l5_l6": BUFFER_MIN_TOTAL_GAIN,
    "buffer_expected_decisions": {"V7-0009": "selected", "V7-0010": "rejected"},
    "buffer_v7_0010_expected_failure_set": ["L6_total_gain"],
    "historical_timing_gate_exception_policy": [
        {
            "execution_id": "V7-0009",
            "case": "task2_smoke/L1",
            "check": "gpu_total_stability",
            "scope": "supplemental smoke invoked with --skip-timing-validation; not a final demo gate",
        }
    ],
    "default_cache_environment": DEFAULT_CACHE_ENVIRONMENT,
    "v7_0008_source_fingerprint_paths": V7_0008_SOURCE_FINGERPRINT_PATHS,
    "v7_0008_superseded_source_path": V7_0008_SUPERSEDED_SOURCE_PATH,
}
EXPECTED_POLICY_FILES = {
    "scripts/test/operator_sets.json",
    "scripts/test/task_step_contracts.json",
}
EXPECTED_RUN_IDS = {f"V7-{index:04d}" for index in range(5, 12)}
MINIMUM_CHECK_NAMES = {
    "cpu_gpu_track_match",
    "gpu_matches_truth_within_tolerance",
    "cpu_gpu_detection_match",
    "gpu_matches_expected_detection",
    "invalid_input_checks",
    "repeat_business_consistency",
}
BUFFER_TIMING_NAMES = {
    "pulse_compression",
    "pulse_doppler",
    "power_map",
    "ca_cfar",
    "ambgfun",
    "final_detection",
}
BUFFER_ERROR_NAMES = {
    "pulse_compression_error",
    "pulse_doppler_error",
    "cfar_threshold_error",
    "ambgfun_surface_error",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--correlate-root", required=True)
    parser.add_argument("--spectrogram-root", required=True)
    parser.add_argument("--cwt-root", required=True)
    parser.add_argument("--demo-root", required=True)
    parser.add_argument("--buffer-first-root", required=True)
    parser.add_argument("--buffer-second-root", required=True)
    parser.add_argument("--final-readback-root", required=True)
    parser.add_argument("--correlate-archive", required=True)
    parser.add_argument("--correlate-console", required=True)
    parser.add_argument("--spectrogram-archive", required=True)
    parser.add_argument("--spectrogram-console", required=True)
    parser.add_argument("--cwt-archive", required=True)
    parser.add_argument("--cwt-console", required=True)
    parser.add_argument("--demo-archive", required=True)
    parser.add_argument("--demo-console", required=True)
    parser.add_argument("--buffer-first-archive", required=True)
    parser.add_argument("--buffer-first-console", required=True)
    parser.add_argument("--buffer-second-archive", required=True)
    parser.add_argument("--buffer-second-console", required=True)
    parser.add_argument("--v5-summary-json", required=True)
    parser.add_argument("--v6-summary-json", required=True)
    parser.add_argument(
        "--evidence-manifest",
        default="",
        help="Frozen archive/console SHA256 trust anchor; defaults under source-root",
    )
    parser.add_argument(
        "--source-root",
        default=str(Path(__file__).resolve().parents[2]),
        help="Repository containing this finalizer; overrides are rejected to preserve the trust anchor",
    )
    parser.add_argument("--output-dir", default="data/reports/zhongkexin/v7_final")
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def require_true(value: Any, label: str) -> None:
    require(value is True, f"{label} must be JSON true")


def require_false(value: Any, label: str) -> None:
    require(value is False, f"{label} must be JSON false")


def require_keys(payload: dict[str, Any], expected: set[str], label: str) -> None:
    require(set(payload) == expected, f"{label} keys mismatch")


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


def read_table(path: Path) -> list[dict[str, str]]:
    require_regular_file(path)
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        require(reader.fieldnames is not None, f"missing TSV header: {path}")
        require(len(reader.fieldnames) == len(set(reader.fieldnames)), f"duplicate TSV header: {path}")
        rows = list(reader)
    require(all(None not in row for row in rows), f"TSV column overflow: {path}")
    return rows


def read_csv(path: Path) -> list[dict[str, str]]:
    require_regular_file(path)
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        require(reader.fieldnames is not None, f"missing CSV header: {path}")
        require(len(reader.fieldnames) == len(set(reader.fieldnames)), f"duplicate CSV header: {path}")
        rows = list(reader)
    require(all(None not in row for row in rows), f"CSV column overflow: {path}")
    return rows


def parse_bool(value: Any) -> bool:
    token = str(value).strip().lower()
    require(token in {"true", "false"}, f"invalid boolean: {value}")
    return token == "true"


def parse_float(value: Any) -> float:
    result = float(str(value))
    require(math.isfinite(result), f"non-finite numeric value: {value}")
    return result


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


def sha256_file_set(root: Path, paths: list[Path]) -> str:
    require(paths, f"empty evidence file set: {root}")
    digest = hashlib.sha256()
    for path in sorted(paths):
        require(path.is_file(), f"missing evidence file: {path}")
        relative = path.relative_to(root).as_posix()
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(path).encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def validate_run_root(root: Path, execution_id: str) -> None:
    require(execution_id in RUN_ROOT_PATTERNS, f"unknown V7 execution ID: {execution_id}")
    require(
        re.fullmatch(RUN_ROOT_PATTERNS[execution_id], root.name) is not None,
        f"{execution_id} evidence root identity mismatch: {root}",
    )
    require(root.is_dir(), f"missing evidence root: {root}")


def load_evidence_manifest(path: Path, source_root: Path) -> dict[str, Any]:
    """Load the repository trust anchor and reject caller-supplied self-signing data."""

    expected_path = (source_root / "scripts/platform/v7_final_evidence_manifest.json").resolve()
    require(path.resolve() == expected_path, "evidence manifest must be the tracked repository trust anchor")
    payload = read_json(expected_path)
    require_keys(
        payload,
        {
            "schema_version",
            "version",
            "final_execution_id",
            "acceptance_policy",
            "tracked_policy_files",
            "predecessor_reports",
            "runs",
        },
        "V7 evidence manifest",
    )
    require(payload["schema_version"] == "v7_final_evidence_manifest_v1", "evidence manifest schema mismatch")
    require(payload["version"] == "V7.6", "evidence manifest version mismatch")
    require(payload["final_execution_id"] == EXPECTED_FINAL_EXECUTION_ID, "final execution ID policy mismatch")
    require(payload["acceptance_policy"] == EXPECTED_ACCEPTANCE_POLICY, "acceptance policy mismatch")

    policy_files = payload["tracked_policy_files"]
    require_keys(policy_files, EXPECTED_POLICY_FILES, "tracked policy files")
    for relative, expected_hash in policy_files.items():
        require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"invalid policy SHA256: {relative}")
        require(sha256(source_root / relative) == expected_hash, f"tracked policy SHA256 mismatch: {relative}")

    predecessor_reports = payload["predecessor_reports"]
    require_keys(
        predecessor_reports,
        {
            "v6_final_summary_schema",
            "v6_final_summary_md_sha256",
            "v6_final_summary_json_sha256",
            "v6_evidence_manifest_sha256",
            "report_root_readme_sha256",
        },
        "V7 predecessor reports",
    )
    require(
        predecessor_reports["v6_final_summary_schema"] == "v6_final_summary_v2",
        "V6 predecessor summary schema policy mismatch",
    )
    for name, expected_hash in predecessor_reports.items():
        if name.endswith("_sha256"):
            require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"invalid predecessor SHA256: {name}")

    runs = payload["runs"]
    require_keys(runs, EXPECTED_RUN_IDS, "V7 evidence runs")
    for execution_id in sorted(EXPECTED_RUN_IDS - {EXPECTED_FINAL_EXECUTION_ID}):
        entry = runs[execution_id]
        require_keys(
            entry,
            {"root_name", "archive_name", "archive_sha256", "console_name", "console_sha256"},
            f"{execution_id} evidence manifest entry",
        )
        require(
            re.fullmatch(RUN_ROOT_PATTERNS[execution_id], entry["root_name"]) is not None,
            f"{execution_id} manifest root identity mismatch",
        )
        require(entry["archive_name"] == f"cetc_v7_{execution_id[-4:]}_latest.tar.gz", f"{execution_id} archive name mismatch")
        require(entry["console_name"] == f"cetc_v7_{execution_id[-4:]}_console.log", f"{execution_id} console name mismatch")
        for name in ("archive_sha256", "console_sha256"):
            require(re.fullmatch(r"[0-9a-f]{64}", entry[name]) is not None, f"{execution_id} invalid {name}")

    readback = runs[EXPECTED_FINAL_EXECUTION_ID]
    require_keys(
        readback,
        {"root_name", "standalone_execution_manifest_present", "files"},
        f"{EXPECTED_FINAL_EXECUTION_ID} evidence manifest entry",
    )
    require(readback["root_name"] == "cetc_v7_0011_deploy_readback", "V7-0011 root name mismatch")
    require_false(readback["standalone_execution_manifest_present"], "V7-0011 standalone manifest")
    require_keys(
        readback["files"],
        {"task1_radar_demo.cpp", "run_v7_5_task1_buffer_reuse.sh"},
        "V7-0011 readback files",
    )
    for name, expected_hash in readback["files"].items():
        require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"V7-0011 invalid SHA256: {name}")
    return payload


def validate_frozen_run_inputs(
    execution_id: str,
    root: Path,
    archive: Path,
    console: Path,
    manifest_entry: dict[str, Any],
) -> None:
    validate_run_root(root, execution_id)
    require(root.name == manifest_entry["root_name"], f"{execution_id} root differs from frozen manifest")
    require(archive.name == manifest_entry["archive_name"], f"{execution_id} archive identity mismatch")
    require(console.name == manifest_entry["console_name"], f"{execution_id} console identity mismatch")
    require(sha256_nonempty(archive) == manifest_entry["archive_sha256"], f"{execution_id} archive SHA256 mismatch")
    require(sha256_nonempty(console) == manifest_entry["console_sha256"], f"{execution_id} console SHA256 mismatch")


def validate_archive(path: Path, root: Path, relative_files: tuple[str, ...]) -> str:
    """Bind an archive to the extracted evidence by hashing selected members."""

    archive_hash = sha256_nonempty(path)
    try:
        with tarfile.open(path, mode="r:gz") as archive:
            member_list = archive.getmembers()
            member_names = [member.name for member in member_list]
            require(len(member_names) == len(set(member_names)), "archive contains duplicate member names")
            members = {member.name: member for member in member_list}
            require(any(name.startswith(f"{root.name}/") for name in members), "archive root mismatch")
            for relative in relative_files:
                member_name = f"{root.name}/{relative}"
                require(member_name in members, f"archive lacks {member_name}")
                member = members[member_name]
                require(member.isfile(), f"archive member is not a file: {member_name}")
                handle = archive.extractfile(member)
                require(handle is not None, f"cannot read archive member: {member_name}")
                member_hash = hashlib.sha256(handle.read()).hexdigest()
                require(
                    member_hash == sha256(root / relative),
                    f"archive/extracted evidence mismatch: {relative}",
                )
    except (tarfile.TarError, OSError) as error:
        raise ValueError(f"invalid evidence archive: {path}: {error}") from error
    return archive_hash


def archive_evidence_files(execution_id: str) -> tuple[str, ...]:
    common = [
        "status.tsv",
        "candidate_summary.tsv",
        "candidate_gate.json",
        "reports_restore.diff",
        "manifests_restore.diff",
    ]
    if execution_id == "V7-0005":
        raw = [
            f"modes/{mode}/{scale}/latest_metrics.json"
            for mode in ("baseline", "filter_only", "correlate_only", "combined")
            for scale in ("L3", "L6")
        ]
        return tuple(common + raw)
    if execution_id in {"V7-0006", "V7-0007", "V7-0010"}:
        raw = [
            f"ab/{mode}/{scale}/latest_metrics.json"
            for mode in ("baseline", "candidate")
            for scale in ("L3", "L5", "L6")
        ]
        return tuple(common + raw)
    if execution_id == "V7-0009":
        raw = [
            f"ab/{mode}/{scale}/latest_metrics.json"
            for mode in ("baseline", "candidate")
            for scale in ("L3", "L5", "L6")
        ]
        supplemental = [
            *(f"task1_full/L{level}/latest_metrics.json" for level in (1, 2, 4)),
            *(f"task2_smoke/L{level}/latest_metrics.json" for level in (1, 6)),
        ]
        return tuple(common + raw + supplemental)
    if execution_id == "V7-0008":
        return tuple(
            [
                "status.tsv",
                "demo/summary.json",
                "demo/wall_seconds.txt",
                "all81_registry.tsv",
                "logs/all81_full.log",
                "audits/dtype/latest_dtype_test_coverage.json",
                "audits/task_steps/latest_task_step_audit.json",
                "audits/assertions.json",
                "fingerprint/candidate_sources.sha256",
                "demo/tasks/task1_radar/latest_metrics.json",
                "demo/tasks/task2_features/latest_metrics.json",
                "demo/top30/latest_all_ops_scale_benchmark.csv",
                "demo/telemetry/dlsmi_samples.csv",
                "demo/telemetry/dlsmi_summary.json",
                "prepare/cache_decision.json",
                "prepare/cache_probe/default/latest_all_ops_scale_benchmark.csv",
                "prepare/cache_probe/expanded/latest_all_ops_scale_benchmark.csv",
                "reports_restore.diff",
                "manifests_restore.diff",
            ]
            + [
                f"prepare/task_sweep/{task}/L{level}/latest_metrics.json"
                for task in ("task1_radar", "task2_features")
                for level in range(1, 7)
            ]
        )
    raise ValueError(f"no archive evidence file policy for {execution_id}")


def validate_v7_0008_source_fingerprint(root: Path, source_root: Path) -> dict[str, Any]:
    fingerprint_path = root / "fingerprint/candidate_sources.sha256"
    require_regular_file(fingerprint_path)
    entries: dict[str, str] = {}
    for line_number, line in enumerate(fingerprint_path.read_text(encoding="utf-8").splitlines(), start=1):
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, f"invalid V7-0008 source fingerprint row {line_number}")
        expected_hash, relative = match.groups()
        relative_path = Path(relative)
        require(
            not relative_path.is_absolute()
            and relative_path.as_posix() == relative
            and "." not in relative_path.parts
            and ".." not in relative_path.parts,
            f"unsafe V7-0008 source fingerprint path: {relative}",
        )
        require(relative not in entries, f"duplicate V7-0008 source fingerprint path: {relative}")
        entries[relative] = expected_hash
    require(
        set(entries) == set(V7_0008_SOURCE_FINGERPRINT_PATHS),
        "V7-0008 source fingerprint path set mismatch",
    )
    matched: list[str] = []
    for relative in V7_0008_SOURCE_FINGERPRINT_PATHS:
        if relative == V7_0008_SUPERSEDED_SOURCE_PATH:
            continue
        source_path = source_root / relative
        require(
            source_path.absolute() == source_path.resolve(),
            f"current delivery source path contains symlink: {relative}",
        )
        require(
            sha256(source_path) == entries[relative],
            f"current delivery source differs from V7-0008 fingerprint: {relative}",
        )
        matched.append(relative)
    require(
        len(matched) == len(V7_0008_SOURCE_FINGERPRINT_PATHS) - 1,
        "V7-0008 source fingerprint match count mismatch",
    )
    return {
        "path": str(fingerprint_path),
        "sha256": sha256(fingerprint_path),
        "matched_current_source_count": len(matched),
        "matched_current_sources": matched,
        "superseded_source": V7_0008_SUPERSEDED_SOURCE_PATH,
        "superseded_source_recorded_sha256": entries[V7_0008_SUPERSEDED_SOURCE_PATH],
        "superseded_by_execution_id": EXPECTED_FINAL_EXECUTION_ID,
    }


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


def load_operator_policy(source_root: Path) -> dict[str, set[str]]:
    payload = read_json(source_root / "scripts/test/operator_sets.json")
    sets = payload["sets"]
    result: dict[str, set[str]] = {}
    for name, expected_count in (
        ("all81", EXPECTED_OPERATORS),
        ("demo_top30", EXPECTED_TOP_OPERATORS),
        ("demo_cache_probe4", 4),
    ):
        entry = sets[name]
        operators = entry["operators"]
        require(entry["expected_count"] == expected_count, f"{name} policy count mismatch")
        require(len(operators) == expected_count, f"{name} policy rows mismatch")
        require(len(set(operators)) == expected_count, f"{name} policy is not unique")
        result[name] = set(operators)
    require(result["demo_top30"] <= result["all81"], "Top30 policy is outside all81")
    require(result["demo_cache_probe4"] <= result["all81"], "cache policy is outside all81")
    return result


def load_task_contract_policy(source_root: Path) -> dict[tuple[str, str], dict[str, Any]]:
    payload = read_json(source_root / "scripts/test/task_step_contracts.json")
    require(payload["schema_version"] == 1, "task contract schema mismatch")
    result: dict[tuple[str, str], dict[str, Any]] = {}
    for task, entries in payload["tasks"].items():
        for entry in entries:
            row = {"task": task, **entry}
            key = (task, entry["step"])
            require(key not in result, f"duplicate task contract: {key}")
            result[key] = row
    require(len(result) == 16, "task contract row count mismatch")
    return result


def require_empty(path: Path) -> None:
    require_regular_file(path)
    require(path.stat().st_size == 0, f"expected empty evidence file: {path}")


def validate_registry(path: Path, expected_operators: set[str]) -> list[str]:
    require_regular_file(path)
    rows = [line.split("\t") for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    require(all(len(row) == 4 for row in rows), "all81 registry column mismatch")
    names = [f"{row[0]}/{row[1]}" for row in rows]
    require(len(names) == len(set(names)), "all81 registry is not unique")
    require(set(names) == expected_operators, "all81 registry operator set mismatch")
    return names


def validate_all81_log(path: Path, expected_operators: set[str]) -> int:
    require_regular_file(path)
    lines = path.read_text(encoding="utf-8", errors="strict").splitlines()
    pattern = re.compile(
        r"^\[([a-z0-9_]+/[a-z0-9_]+)\] PASS  accuracy_cases=(\d+)  perf_cases=(\d+)$"
    )
    passed: dict[str, tuple[int, int]] = {}
    for line in lines:
        match = pattern.fullmatch(line)
        if match is None:
            continue
        operator = match.group(1)
        require(operator not in passed, f"duplicate all81 PASS line: {operator}")
        accuracy_cases = int(match.group(2))
        performance_cases = int(match.group(3))
        require(accuracy_cases > 0 and performance_cases > 0, f"empty all81 case set: {operator}")
        passed[operator] = (accuracy_cases, performance_cases)
    require(set(passed) == expected_operators, "all81 execution operator set mismatch")
    summary = f"[cusignal-test] summary: passed {len(expected_operators)}/{len(expected_operators)}"
    nonempty = [line for line in lines if line]
    require(lines.count(summary) == 1 and nonempty[-1] == summary, "all81 terminal summary mismatch")
    require(not any(re.search(r"\[[^]]+/[^]]+\] FAIL\b", line) for line in lines), "all81 log contains FAIL")
    return len(passed)


def status_index(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    rows = read_table(path)
    require(rows, f"empty status table: {path}")
    indexed: dict[tuple[str, str], dict[str, str]] = {}
    for row in rows:
        key = (row["phase"], row["case"])
        require(key not in indexed, f"duplicate status row {key}: {path}")
        indexed[key] = row
    return indexed


def validate_status(
    path: Path,
    expected: dict[tuple[str, str], tuple[int, str]],
    *,
    exact: bool = False,
) -> dict[tuple[str, str], dict[str, str]]:
    """Require exact rc/detail values for the status rows that carry final gates."""

    indexed = status_index(path)
    if exact:
        require(set(indexed) == set(expected), f"status row set mismatch: {path}")
    for key, (expected_rc, expected_detail) in expected.items():
        require(key in indexed, f"missing status row {key}: {path}")
        row = indexed[key]
        require(int(row["rc"]) == expected_rc, f"status rc mismatch for {key}: {row}")
        require(
            row["detail"] == expected_detail,
            f"status detail mismatch for {key}: {row['detail']!r} != {expected_detail!r}",
        )
    return indexed


def parse_audit_evidence(
    root: Path,
    expected_operators: set[str],
    expected_task_rows: dict[tuple[str, str], dict[str, Any]],
) -> dict[str, int]:
    dtype = read_json(root / "audits/dtype/latest_dtype_test_coverage.json")
    task = read_json(root / "audits/task_steps/latest_task_step_audit.json")
    dtype_summary = dtype["summary"]
    task_summary = task["summary"]
    require(dtype_summary["status"] == "passed", "dtype audit status is not passed")
    require(task_summary["status"] == "passed", "task-step audit status is not passed")
    dtype_rows = dtype["operators"]
    require(isinstance(dtype_rows, list), "dtype operator rows are not a list")
    dtype_names = [row["operator"] for row in dtype_rows]
    require(len(dtype_names) == len(set(dtype_names)), "dtype operator rows are not unique")
    require(set(dtype_names) == expected_operators, "dtype operator set mismatch")
    require(dtype_summary["operator_count"] == len(dtype_names), "dtype operator count mismatch")
    declared_counts: dict[str, int] = {}
    concrete_counts: dict[str, int] = {}
    for row in dtype_rows:
        require(row["missing_operator_test_dtypes"] == [], "dtype operator row contains missing edges")
        compatibility = row["compatibility_types"]
        concrete = row["concrete_operator_test_dtypes"]
        require(len(compatibility) == len(set(compatibility)), "duplicate compatibility dtype")
        require(len(concrete) == len(set(concrete)), "duplicate concrete dtype")
        require(set(compatibility) <= set(concrete), "declared dtype lacks a concrete test")
        for name in compatibility:
            declared_counts[name] = declared_counts.get(name, 0) + 1
        for name in set(compatibility) & set(concrete):
            concrete_counts[name] = concrete_counts.get(name, 0) + 1
    summaries = dtype_summary["dtype_summary"]
    require(set(summaries) == set(declared_counts), "dtype summary key set mismatch")
    require(dtype_summary["dtype_count"] == len(summaries), "dtype summary count mismatch")
    require(
        set(dtype_summary["core_type_roundtrip_dtypes"]) == set(summaries),
        "dtype roundtrip set mismatch",
    )
    for name, summary in summaries.items():
        require_true(summary["core_type_roundtrip_tested"], f"dtype {name} roundtrip")
        require(summary["missing_operator_test_count"] == 0, f"dtype {name} contains gaps")
        require(
            summary["declared_operator_count"] == declared_counts[name]
            and summary["concrete_operator_test_count"] == concrete_counts[name],
            f"dtype {name} aggregate coverage mismatch",
        )
    require(dtype_summary["operator_dtype_missing_edges"] == 0, "dtype summary contains gaps")

    task_rows = task["steps"]
    require(isinstance(task_rows, list), "task-step rows are not a list")
    task_keys = [(row["task"], row["step"]) for row in task_rows]
    require(len(task_keys) == len(set(task_keys)), "task-step rows are not unique")
    require(set(task_keys) == set(expected_task_rows), "task-step key set mismatch")
    for row in task_rows:
        require(row == expected_task_rows[(row["task"], row["step"])], "task-step contract mismatch")
    calculation_rows = [row for row in task_rows if row["category"] == "calculation"]
    require(len(task_rows) == task_summary["step_count"], "task row count mismatch")
    require(len(set(row["task"] for row in task_rows)) == task_summary["task_count"], "task count mismatch")
    require(len(calculation_rows) == task_summary["calculation_step_count"], "calculation rows mismatch")
    for row in calculation_rows:
        require(row["timing"] == "present" and row["accuracy"] == "present", "task evidence gap")
        require(row["public_operators"], "calculation step lacks a public operator link")
    public_steps = sum(row["implementation"] == "public" for row in calculation_rows)
    linked_steps = sum(bool(row["public_operators"]) for row in calculation_rows)
    migration_steps = sum(row["migration_target"] != "none" for row in calculation_rows)
    implementation_counts: dict[str, int] = {}
    for row in task_rows:
        name = row["implementation"]
        implementation_counts[name] = implementation_counts.get(name, 0) + 1
    require(task_summary["public_calculation_step_count"] == public_steps, "public step count mismatch")
    require(task_summary["public_operator_link_count"] == linked_steps, "linked step count mismatch")
    require(task_summary["migration_step_count"] == migration_steps, "migration step count mismatch")
    require(task_summary["implementation_counts"] == implementation_counts, "implementation counts mismatch")
    require(task_summary["failure_count"] == 0 and not task_summary["failures"], "task audit failures")
    require(task_summary["timing_gap_count"] == 0, "task timing gaps")
    require(task_summary["accuracy_gap_count"] == 0, "task accuracy gaps")
    assertions = read_json(root / "audits/assertions.json")
    require_keys(assertions, {"dtype", "task_steps"}, "static assertions")
    require_true(assertions["dtype"], "dtype assertion")
    require_true(assertions["task_steps"], "task-step assertion")
    return {
        "dtype_operators": len(dtype_names),
        "dtype_missing_edges": int(dtype_summary["operator_dtype_missing_edges"]),
        "calculation_steps": len(calculation_rows),
        "linked_steps": linked_steps,
        "timing_gaps": int(task_summary["timing_gap_count"]),
        "accuracy_gaps": int(task_summary["accuracy_gap_count"]),
    }


def validate_metrics_evidence(
    path: Path,
    *,
    expected_level: int,
    expected_repeats: int,
    expected_pass: bool,
    label: str,
    allowed_skipped_timing_checks: set[str] | None = None,
) -> dict[str, Any]:
    metrics = read_json(path)
    require(int(metrics["scenario"]["scale_level"]) == expected_level, f"{label} scale mismatch")
    validation = metrics["validation"]
    if expected_pass:
        require_true(validation["pass"], f"{label} validation")
    else:
        require_false(validation["pass"], f"{label} validation")
    checks = validation["checks"]
    require(isinstance(checks, list) and checks, f"{label} validation checks are empty")
    require(all(type(check["pass"]) is bool for check in checks), f"{label} check boolean type")
    check_names = [check["name"] for check in checks]
    require(all(isinstance(name, str) and name for name in check_names), f"{label} invalid check name")
    require(len(check_names) == len(set(check_names)), f"{label} duplicate validation check")
    indexed_checks = {check["name"]: check for check in checks}
    for check in checks:
        require("value" in check and "limit" in check, f"{label} check lacks value/limit: {check['name']}")
        value = parse_float(check["value"])
        limit = parse_float(check["limit"])
        require(value >= 0.0 and limit >= 0.0, f"{label} negative check value/limit: {check['name']}")
        timing_gate_skipped = (
            check["name"] in {"gpu_total_ms", "gpu_total_stability"}
            and check.get("detail") == "GPU timing stability skipped for sanitizer run"
        ) or (
            check["name"] == "gpu_total_ms"
            and check.get("detail") == "GPU timing validation skipped for sanitizer run"
        )
        derived_pass = value >= limit if check["name"] in MINIMUM_CHECK_NAMES else value <= limit
        if check["pass"] is not derived_pass:
            allowed = allowed_skipped_timing_checks or set()
            require(
                timing_gate_skipped and check["name"] in allowed and check["pass"] is True,
                f"{label} check result contradicts value/limit: {check['name']}",
            )
    if expected_pass:
        require(all(check["pass"] is True for check in checks), f"{label} validation check failed")
    else:
        require(any(check["pass"] is False for check in checks), f"{label} lacks a failed check")
    repeats = metrics["repeat_runs"]
    require(isinstance(repeats, list) and len(repeats) == expected_repeats, f"{label} repeat count mismatch")
    require([int(item["index"]) for item in repeats] == list(range(1, expected_repeats + 1)), f"{label} repeat indices mismatch")
    for item in repeats:
        require(type(item["pass"]) is bool, f"{label} repeat pass type")
        require(type(item["business_numeric_pass"]) is bool, f"{label} repeat business type")
        require(parse_float(item["gpu_total_ms"]) > 0.0, f"{label} repeat total must be positive")
        if "cpu_total_ms" in item:
            require(parse_float(item["cpu_total_ms"]) > 0.0, f"{label} repeat CPU total must be positive")
    if expected_pass:
        require(
            all(item["pass"] is True and item["business_numeric_pass"] is True for item in repeats),
            f"{label} repeat failed",
        )
    else:
        require(
            any(item["pass"] is False or item["business_numeric_pass"] is False for item in repeats),
            f"{label} failed validation has no failed repeat",
        )
    timings = metrics.get("timings")
    if timings is not None:
        require(isinstance(timings, dict) and "total" in timings, f"{label} timing set is incomplete")
        for name, timing in timings.items():
            require(isinstance(timing, dict), f"{label} invalid timing entry: {name}")
            require_keys(timing, {"cpu_ms", "gpu_ms"}, f"{label} timing {name}")
            require(
                parse_float(timing["cpu_ms"]) >= 0.0 and parse_float(timing["gpu_ms"]) >= 0.0,
                f"{label} negative timing: {name}",
            )
        require(parse_float(timings["total"]["gpu_ms"]) > 0.0, f"{label} GPU total timing must be positive")
        if "gpu_total_ms" in indexed_checks:
            require_close(
                parse_float(indexed_checks["gpu_total_ms"]["value"]),
                parse_float(timings["total"]["gpu_ms"]),
                f"{label} total timing check",
            )

    for error_name, error in metrics.items():
        if not error_name.endswith("_error") or not isinstance(error, dict) or "mixed_error" not in error:
            continue
        require(
            set(error) == {"mixed_error", "max_abs", "max_rel", "rmse"},
            f"{label} error fields mismatch: {error_name}",
        )
        for field, value in error.items():
            require(parse_float(value) >= 0.0, f"{label} negative {error_name}.{field}")
        check_name = f"{error_name[:-6]}_mixed_error"
        if check_name in indexed_checks:
            require_close(
                parse_float(error["mixed_error"]),
                parse_float(indexed_checks[check_name]["value"]),
                f"{label} {check_name}",
            )
    return metrics


def validate_task_demo(
    root: Path,
    task_name: str,
    summary: dict[str, Any],
) -> dict[str, float]:
    label = f"V7-0008 {task_name} L6"
    metrics = validate_metrics_evidence(
        root / f"demo/tasks/{task_name}/latest_metrics.json",
        expected_level=6,
        expected_repeats=3,
        expected_pass=True,
        label=label,
    )
    require_true(summary["validation_pass"], f"{label} summary validation")
    require(summary["repeat_count"] == 3, f"{label} summary repeat count mismatch")
    totals = [parse_float(item["gpu_total_ms"]) for item in metrics["repeat_runs"]]
    derived = {
        "median": statistics.median(totals),
        "minimum": min(totals),
        "maximum": max(totals),
    }
    maximum = TASK1_L6_MAX_MEDIAN_MS if task_name == "task1_radar" else TASK2_L6_MAX_MEDIAN_MS
    require(derived["median"] <= maximum, f"{label} frozen performance gate failed")
    require_close(derived["median"], parse_float(summary["gpu_total_median_ms"]), f"{label} median")
    require_close(derived["minimum"], parse_float(summary["gpu_total_min_ms"]), f"{label} minimum")
    require_close(derived["maximum"], parse_float(summary["gpu_total_max_ms"]), f"{label} maximum")
    require(set(summary["steps"]) == set(metrics["timings"]), f"{label} timing step set mismatch")
    for name, value in summary["steps"].items():
        require_close(parse_float(value), parse_float(metrics["timings"][name]["gpu_ms"]), f"{label} {name}")
    return derived


def load_benchmark_rows(
    path: Path,
    expected_operators: set[str],
    *,
    require_baseline_reused: bool,
    label: str,
) -> dict[str, dict[str, Any]]:
    rows = read_csv(path)
    require(len(rows) == len(expected_operators), f"{label} row count mismatch")
    indexed: dict[str, dict[str, Any]] = {}
    for row in rows:
        operator = f"{row['module']}/{row['operator']}"
        require(operator not in indexed, f"{label} duplicate operator: {operator}")
        require(row["status"] == "passed", f"{label} status failed: {operator}")
        require(parse_bool(row["pass"]), f"{label} pass=false: {operator}")
        require(int(row["return_code"]) == 0, f"{label} return code failed: {operator}")
        cpu_ms = parse_float(row["cpu_median_ms"])
        gpu_ms = parse_float(row["gpu_e2e_median_ms"])
        speedup = parse_float(row["gpu_e2e_speedup"])
        require(cpu_ms > 0.0 and gpu_ms > 0.0 and speedup > 0.0, f"{label} non-positive timing")
        require_close(cpu_ms / gpu_ms, speedup, f"{label} speedup {operator}")
        if require_baseline_reused:
            require("cpu_baseline=reused" in row["error_note"], f"{label} baseline not reused")
        indexed[operator] = {
            "source": row,
            "cpu_ms": cpu_ms,
            "gpu_ms": gpu_ms,
            "speedup": speedup,
        }
    require(set(indexed) == expected_operators, f"{label} operator set mismatch")
    return indexed


def validate_top30(
    root: Path,
    summary: dict[str, Any],
    expected_operators: set[str],
) -> dict[str, float | int]:
    raw = load_benchmark_rows(
        root / "demo/top30/latest_all_ops_scale_benchmark.csv",
        expected_operators,
        require_baseline_reused=True,
        label="V7-0008 Top30",
    )
    summary_rows = summary["rows"]
    require(isinstance(summary_rows, list) and len(summary_rows) == EXPECTED_TOP_OPERATORS, "Top30 summary rows")
    indexed: dict[str, dict[str, Any]] = {}
    for row in summary_rows:
        operator = row["operator"]
        require(operator not in indexed, f"duplicate Top30 summary operator: {operator}")
        require_true(row["pass"], f"Top30 summary pass {operator}")
        require_true(row["baseline_reused"], f"Top30 baseline reuse {operator}")
        require(row["status"] == "passed", f"Top30 summary status failed: {operator}")
        indexed[operator] = row
    require(set(indexed) == expected_operators, "Top30 summary operator set mismatch")
    for operator, values in raw.items():
        row = indexed[operator]
        source = values["source"]
        require(int(row["scale_value"]) == int(source["scale_value"]), f"Top30 scale mismatch: {operator}")
        require(row["scale_family"] == source["scale_family"], f"Top30 scale family mismatch: {operator}")
        require_close(parse_float(row["cpu_median_ms"]), values["cpu_ms"], f"Top30 CPU {operator}")
        require_close(parse_float(row["gpu_e2e_median_ms"]), values["gpu_ms"], f"Top30 GPU {operator}")
        require_close(parse_float(row["gpu_e2e_speedup"]), values["speedup"], f"Top30 row speedup {operator}")
        require_close(parse_float(row["mixed_error"]), parse_float(source["mixed_error"]), f"Top30 error {operator}")
    speedups = [values["speedup"] for values in raw.values()]
    gpu_sum = sum(values["gpu_ms"] for values in raw.values())
    median_speedup = statistics.median(speedups)
    geometric_mean = math.exp(sum(math.log(value) for value in speedups) / len(speedups))
    require(min(speedups) >= TOP30_MINIMUM_SPEEDUP, "Top30 minimum speedup gate failed")
    require(median_speedup >= TOP30_MINIMUM_MEDIAN_SPEEDUP, "Top30 median speedup gate failed")
    require(summary["count"] == len(raw), "Top30 summary count mismatch")
    require(summary["passed"] == len(raw), "Top30 summary passed mismatch")
    require(summary["baseline_reused"] == len(raw), "Top30 summary baseline count mismatch")
    require_close(min(speedups), parse_float(summary["minimum_speedup"]), "Top30 minimum")
    require_close(median_speedup, parse_float(summary["median_speedup"]), "Top30 median")
    require_close(geometric_mean, parse_float(summary["geometric_mean_speedup"]), "Top30 geometric mean")
    require_close(max(speedups), parse_float(summary["maximum_speedup"]), "Top30 maximum")
    require_close(gpu_sum, parse_float(summary["gpu_e2e_sum_ms"]), "Top30 GPU sum")
    return {
        "count": len(raw),
        "minimum_speedup": min(speedups),
        "median_speedup": median_speedup,
        "geometric_mean_speedup": geometric_mean,
        "maximum_speedup": max(speedups),
    }


def validate_telemetry(root: Path, summary: dict[str, Any]) -> dict[str, float | int]:
    raw = read_json(root / "demo/telemetry/dlsmi_summary.json")
    rows = read_csv(root / "demo/telemetry/dlsmi_samples.csv")
    require_true(raw["available"], "demo telemetry availability")
    require(rows, "demo telemetry samples are empty")
    require(raw["sample_count"] == len(rows), "telemetry sample count mismatch")
    gpu_indices = {int(row["gpu_index"]) for row in rows}
    require(raw["gpu_count"] == len(gpu_indices), "telemetry GPU count mismatch")
    used = [parse_float(row["used_mib"]) for row in rows]
    totals = [parse_float(row["total_mib"]) for row in rows]
    free = [parse_float(row["free_mib"]) for row in rows]
    utilization = [parse_float(row["util_percent"]) for row in rows]
    require(all(value >= 0.0 for value in used + totals + free + utilization), "negative telemetry value")
    require(all(total > 0.0 and used_value <= total for used_value, total in zip(used, totals)), "invalid telemetry capacity")
    for used_value, total, free_value in zip(used, totals, free):
        require_close(total - used_value, free_value, "telemetry free memory")
    minimum_headroom = min(total - used_value for used_value, total in zip(used, totals))
    require(minimum_headroom >= MINIMUM_MEMORY_HEADROOM_MIB, "demo memory headroom gate failed")
    derived = {
        "sample_count": len(rows),
        "used_mib_max": max(used),
        "util_percent_max": max(utilization),
        "minimum_headroom_mib": minimum_headroom,
    }
    comparisons = {
        "used_mib_min": min(used),
        "used_mib_max": max(used),
        "used_mib_avg": statistics.fmean(used),
        "total_mib_max": max(totals),
        "free_mib_min": min(free),
        "util_percent_max": max(utilization),
        "util_percent_avg": statistics.fmean(utilization),
        "duration_s": parse_float(rows[-1]["elapsed_s"]),
    }
    for name, value in comparisons.items():
        require_close(value, parse_float(raw[name]), f"telemetry {name}")
    require(raw["started_at"] == rows[0]["timestamp"], "telemetry start mismatch")
    require(raw["ended_at"] == rows[-1]["timestamp"], "telemetry end mismatch")
    require(summary == raw, "demo summary telemetry differs from raw telemetry")
    return derived


def validate_wall_evidence(path: Path, summary: dict[str, Any]) -> tuple[str, float]:
    require(path.is_file(), f"missing evidence file: {path}")
    wall_text = path.read_text(encoding="utf-8").strip()
    wall_seconds = parse_float(wall_text)
    require(wall_seconds > 0.0, "demo wall must be positive")
    require_close(parse_float(summary["seconds"]), wall_seconds, "demo wall seconds")
    require_close(parse_float(summary["limit_seconds"]), DEMO_WALL_LIMIT_SECONDS, "demo wall limit")
    require_close(
        parse_float(summary["reserve_seconds"]),
        DEMO_WALL_LIMIT_SECONDS - wall_seconds,
        "demo wall reserve",
    )
    require(wall_seconds <= DEMO_WALL_LIMIT_SECONDS, "wall budget failed")
    return wall_text, wall_seconds


def validate_demo_status(root: Path, wall_text: str) -> None:
    expected: dict[tuple[str, str], tuple[int, str]] = {
        ("audit", "registry"): (0, "81 operators"),
        ("audit", "dtype"): (0, "compatibility gaps"),
        ("audit", "task_steps"): (0, "14 calculation steps"),
        ("gate", "static_audits"): (0, "dtype/task steps"),
        ("regression", "all81"): (0, "81/81"),
        ("build", "task_demos"): (0, "build-v7-demo"),
        ("baseline", "top30_large_gpu"): (0, "large-gpu L6 warmup=1 repeat=3"),
        ("cache_probe", "default"): (0, "blocks=8,max_mb=512,single_mb=256"),
        ("cache_probe", "expanded"): (0, "blocks=16,max_mb=4096,single_mb=3072"),
        ("prepare", "cache_decision"): (0, "/tmp/cetc_v7_demo_cache/cache_decision.json"),
        ("demo", "task1_L6"): (0, "repeat=3"),
        ("demo", "task2_L6"): (0, "repeat=3"),
        ("demo", "top30_large_gpu"): (0, "large-gpu L6 warmup=1 repeat=3"),
        ("gate", "five_minute_demo"): (0, f"wall={wall_text}s limit=240s"),
        ("integrity", "restore"): (0, "reports/manifests"),
        ("final", "overall"): (0, "V7-0008 phase=both five-minute demo"),
    }
    for task in ("task1_radar", "task2_features"):
        for level in range(1, 7):
            expected[("prepare_task", f"{task}_L{level}")] = (0, "repeat=1")
    validate_status(root / "status.tsv", expected, exact=True)


def validate_demo_gates(
    root: Path,
    demo: dict[str, Any],
    policy: dict[str, set[str]],
    task_policy: dict[tuple[str, str], dict[str, Any]],
) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_run_root(root, "V7-0008")
    wall_text, wall_seconds = validate_wall_evidence(root / "demo/wall_seconds.txt", demo["wall"])
    validate_demo_status(root, wall_text)

    registry_names = validate_registry(root / "all81_registry.tsv", policy["all81"])
    all81_passed = validate_all81_log(root / "logs/all81_full.log", policy["all81"])
    require(all81_passed == len(registry_names), "all81 log/registry count mismatch")
    audits = parse_audit_evidence(root, policy["all81"], task_policy)
    require(audits["dtype_operators"] == EXPECTED_OPERATORS, "dtype operator count mismatch")
    require(audits["dtype_missing_edges"] == 0, "dtype coverage contains gaps")
    require(
        audits["calculation_steps"] == EXPECTED_CALCULATION_STEPS
        and audits["linked_steps"] == EXPECTED_CALCULATION_STEPS,
        "task calculation-step count mismatch",
    )
    require(audits["timing_gaps"] == audits["accuracy_gaps"] == 0, "task audit gaps")

    require(demo["status"] == "passed", "V7-0008 demo failed")
    expected_checks = {
        "wall_budget",
        "task1_validation",
        "task2_validation",
        "task1_performance",
        "task2_performance",
        "operator_count",
        "operator_pass",
        "cpu_baseline_reused",
        "minimum_speedup",
        "median_speedup",
        "cache_decision",
        "telemetry",
        "memory_headroom",
    }
    require_keys(demo["checks"], expected_checks, "V7-0008 checks")
    for name, value in demo["checks"].items():
        require_true(value, f"V7-0008 check {name}")

    task1 = validate_task_demo(root, "task1_radar", demo["task1"])
    task2 = validate_task_demo(root, "task2_features", demo["task2"])
    task_pass_counts = {"task1_radar": 0, "task2_features": 0}
    for task in task_pass_counts:
        for level in range(1, 7):
            validate_metrics_evidence(
                root / f"prepare/task_sweep/{task}/L{level}/latest_metrics.json",
                expected_level=level,
                expected_repeats=1,
                expected_pass=True,
                label=f"V7-0008 prepare {task} L{level}",
            )
            task_pass_counts[task] += 1
    top30 = validate_top30(root, demo["operators"], policy["demo_top30"])
    telemetry = validate_telemetry(root, demo["telemetry"])
    require_empty(root / "reports_restore.diff")
    require_empty(root / "manifests_restore.diff")
    gates = {
        "all81_passed": all81_passed,
        "all81_total": len(policy["all81"]),
        "dtype_gap_count": audits["dtype_missing_edges"],
        "calculation_steps_passed": audits["linked_steps"],
        "calculation_steps_total": audits["calculation_steps"],
        "timing_gap_count": audits["timing_gaps"],
        "accuracy_gap_count": audits["accuracy_gaps"],
        "task1_l1_l6_passed": task_pass_counts["task1_radar"],
        "task2_l1_l6_passed": task_pass_counts["task2_features"],
        "top30_passed": top30["count"],
        "top30_total": len(policy["demo_top30"]),
        "restore_diff_count": 0,
    }
    derived = {
        "wall_seconds": wall_seconds,
        "wall_limit_seconds": DEMO_WALL_LIMIT_SECONDS,
        "task1_l6_gpu_median_ms": task1["median"],
        "task2_l6_gpu_median_ms": task2["median"],
        "top30_median_speedup": top30["median_speedup"],
        "top30_geometric_mean_speedup": top30["geometric_mean_speedup"],
        "top30_minimum_speedup": top30["minimum_speedup"],
        "gpu_memory_peak_mib": telemetry["used_mib_max"],
        "gpu_utilization_peak_percent": telemetry["util_percent_max"],
    }
    return gates, derived


def keyed_rows(path: Path) -> dict[tuple[str, str], dict[str, str]]:
    rows = read_table(path)
    indexed = {(row["mode"], row["scale"]): row for row in rows}
    require(len(indexed) == len(rows), f"duplicate mode/scale row: {path}")
    return indexed


def gain(baseline: float, candidate: float) -> float:
    require(baseline > 0.0, "baseline must be positive")
    require(candidate > 0.0, "candidate must be positive")
    return (baseline - candidate) / baseline


def require_close(actual: float, expected: float, label: str) -> None:
    require(math.isclose(actual, expected, rel_tol=1.0e-9, abs_tol=1.0e-12), f"{label} mismatch")


def evidence_hashes(root: Path) -> dict[str, str]:
    return {
        "candidate_summary_sha256": sha256(root / "candidate_summary.tsv"),
        "candidate_gate_sha256": sha256(root / "candidate_gate.json"),
        "status_sha256": sha256(root / "status.tsv"),
    }


def validate_candidate_metrics_row(
    path: Path,
    row: dict[str, str],
    *,
    scale: str,
    repeats: int,
    expected_pass: bool,
    timing_columns: dict[str, str],
    error_columns: dict[str, str],
    label: str,
) -> dict[str, Any]:
    metrics = validate_metrics_evidence(
        path,
        expected_level=int(scale[1:]),
        expected_repeats=repeats,
        expected_pass=expected_pass,
        label=label,
    )
    require(parse_bool(row["validation"]) is expected_pass, f"{label} TSV validation mismatch")
    totals = [parse_float(item["gpu_total_ms"]) for item in metrics["repeat_runs"]]
    row_total = parse_float(row["total_ms"])
    require(row_total > 0.0, f"{label} TSV total must be positive")
    require_close(statistics.median(totals), row_total, f"{label} total median")
    for column, timing_name in timing_columns.items():
        timing_value = parse_float(metrics["timings"][timing_name]["gpu_ms"])
        row_value = parse_float(row[column])
        require(timing_value > 0.0 and row_value > 0.0, f"{label} non-positive timing: {column}")
        require_close(
            timing_value,
            row_value,
            f"{label} {column}",
        )
    for column, error_name in error_columns.items():
        error_value = parse_float(metrics[error_name]["mixed_error"])
        row_value = parse_float(row[column])
        require(error_value >= 0.0 and row_value >= 0.0, f"{label} negative error: {column}")
        require_close(
            error_value,
            row_value,
            f"{label} {column}",
        )
    return metrics


def validate_common_candidate_status(
    root: Path,
    *,
    execution_id: str,
    task_phase: str,
    modes: tuple[str, ...],
    scales: tuple[str, ...],
    repeats: int,
    gate_case: str,
    gate_rc: int,
    final_detail: str,
) -> dict[tuple[str, str], dict[str, str]]:
    validate_run_root(root, execution_id)
    expected: dict[tuple[str, str], tuple[int, str]] = {
        ("build", "configure"): (0, "build-v7-task"),
        ("build", "task_demos"): (0, "task1/task2"),
        ("audit", "registry"): (0, "81 operators"),
        ("audit", "dtype"): (0, "compatibility gaps"),
        ("audit", "task_steps"): (0, "14 calculation steps"),
        ("gate", "static_audits"): (0, "dtype/task steps"),
        ("gate", gate_case): (gate_rc, f"/tmp/{root.name}/candidate_gate.json"),
        ("integrity", "restore"): (0, "reports/manifests"),
        ("final", "overall"): (gate_rc, final_detail),
    }
    for mode in modes:
        for scale in scales:
            expected[(task_phase, f"{mode}_{scale}")] = (
                0 if mode in {"baseline", "candidate", "correlate_only"} else 1,
                f"repeat={repeats}",
            )
    indexed = validate_status(root / "status.tsv", expected, exact=True)
    return indexed


def derive_correlate(root: Path) -> tuple[dict[str, Any], dict[str, Any]]:
    validate_run_root(root, "V7-0005")
    rows = keyed_rows(root / "candidate_summary.tsv")
    expected_rows = {(mode, scale) for mode in ("baseline", "filter_only", "correlate_only", "combined") for scale in ("L3", "L6")}
    require(set(rows) == expected_rows, "V7-0005 candidate row set mismatch")
    gate = read_json(root / "candidate_gate.json")
    require(gate["status"] == "failed", "V7-0005 overall branch status changed")
    expected_gate_keys = {f"{scale}_{name}" for scale in ("L3", "L6") for name in ("available", "total_gain", "filter_gain", "correlate_gain", "numeric")}
    require_keys(gate["checks"], expected_gate_keys, "V7-0005 gate checks")
    hotspot_gains: list[float] = []
    total_gains: list[float] = []
    demod_failures: list[dict[str, Any]] = []
    original_failures: set[str] = set()
    for scale in ("L3", "L6"):
        raw: dict[str, dict[str, Any]] = {}
        for mode, expected_pass in (
            ("baseline", True),
            ("filter_only", False),
            ("correlate_only", True),
            ("combined", False),
        ):
            raw[mode] = validate_candidate_metrics_row(
                root / f"modes/{mode}/{scale}/latest_metrics.json",
                rows[(mode, scale)],
                scale=scale,
                repeats=3,
                expected_pass=expected_pass,
                timing_columns={"filter_ms": "filter", "correlate_ms": "correlate"},
                error_columns={"filtered_mixed": "filtered_error", "correlate_mixed": "correlate_error"},
                label=f"V7-0005 {mode} {scale}",
            )
        baseline = rows[("baseline", scale)]
        candidate = rows[("correlate_only", scale)]
        hotspot_gain = gain(
            parse_float(baseline["correlate_ms"]),
            parse_float(candidate["correlate_ms"]),
        )
        total_gain = gain(parse_float(baseline["total_ms"]), parse_float(candidate["total_ms"]))
        require_close(hotspot_gain, parse_float(gate["checks"][f"{scale}_correlate_gain"]), f"{scale} correlate gain")
        hotspot_gains.append(hotspot_gain)
        total_gains.append(total_gain)
        checks = {item["name"]: item for item in raw["filter_only"]["validation"]["checks"]}
        demod = checks["demod_mixed_error"]
        require_false(demod["pass"], f"AOT filter demod {scale}")
        require(parse_float(demod["value"]) > parse_float(demod["limit"]), f"AOT filter demod {scale} is not over limit")
        demod_failures.append(
            {"scale": scale, "mixed_error": parse_float(demod["value"]), "limit": parse_float(demod["limit"])}
        )
        combined_total_gain = gain(
            parse_float(rows[("baseline", scale)]["total_ms"]),
            parse_float(rows[("combined", scale)]["total_ms"]),
        )
        filter_gain = gain(
            parse_float(rows[("baseline", scale)]["filter_ms"]),
            parse_float(rows[("filter_only", scale)]["filter_ms"]),
        )
        require_true(gate["checks"][f"{scale}_available"], f"V7-0005 {scale} availability")
        require_close(combined_total_gain, parse_float(gate["checks"][f"{scale}_total_gain"]), f"{scale} combined total gain")
        require_close(filter_gain, parse_float(gate["checks"][f"{scale}_filter_gain"]), f"{scale} filter gain")
        combined_numeric = (
            parse_float(rows[("combined", scale)]["filtered_mixed"]) <= CANDIDATE_NUMERIC_MIXED_ERROR_LIMIT
            and parse_float(rows[("combined", scale)]["correlate_mixed"]) <= CANDIDATE_NUMERIC_MIXED_ERROR_LIMIT
        )
        require_false(gate["checks"][f"{scale}_numeric"], f"V7-0005 {scale} combined numeric")
        require(combined_numeric is False, f"V7-0005 {scale} combined numeric unexpectedly passes")
        if filter_gain < CORRELATE_ORIGINAL_MIN_FILTER_GAIN:
            original_failures.add(f"{scale}_filter_gain")
        if hotspot_gain < 0.30:
            original_failures.add(f"{scale}_correlate_gain")
        if combined_total_gain < dict(zip(("L3", "L6"), CORRELATE_ORIGINAL_MIN_TOTAL_GAIN_L3_L6))[scale]:
            original_failures.add(f"{scale}_total_gain")
        if not combined_numeric:
            original_failures.add(f"{scale}_numeric")
    require(
        original_failures == {"L3_filter_gain", "L3_numeric", "L6_filter_gain", "L6_numeric"},
        "V7-0005 original gate failure set changed",
    )
    require(all(value >= CORRELATE_MIN_HOTSPOT_GAIN for value in hotspot_gains), "correlate hotspot gate failed")
    require(
        all(value >= minimum for value, minimum in zip(total_gains, CORRELATE_MIN_TOTAL_GAIN_L3_L6)),
        "correlate end-to-end gate failed",
    )
    validate_common_candidate_status(
        root,
        execution_id="V7-0005",
        task_phase="task2_ab",
        modes=("baseline", "filter_only", "correlate_only", "combined"),
        scales=("L3", "L6"),
        repeats=3,
        gate_case="task2_ab",
        gate_rc=1,
        final_detail="Task2 FFT filter+correlate candidate",
    )
    require_empty(root / "reports_restore.diff")
    require_empty(root / "manifests_restore.diff")
    return (
        {
            "original_overall_gate_status": "failed",
            "retention_policy_pass": True,
            "hotspot_reduction_fraction_l3_l6": hotspot_gains,
            "total_reduction_fraction_l3_l6": total_gains,
        },
        {"reason": "demod accuracy failure", "demod_failures": demod_failures},
    )


def derive_spectrogram(root: Path) -> dict[str, Any]:
    validate_run_root(root, "V7-0006")
    rows = keyed_rows(root / "candidate_summary.tsv")
    expected_rows = {(mode, scale) for mode in ("baseline", "candidate") for scale in ("L3", "L5", "L6")}
    require(set(rows) == expected_rows, "V7-0006 candidate row set mismatch")
    gate = read_json(root / "candidate_gate.json")
    require(gate["status"] == "failed", "V7-0006 challenge-gate status changed")
    expected_gate_keys = {f"{scale}_{name}" for scale in ("L3", "L5", "L6") for name in ("available", "spectrogram_gain", "total_gain", "numeric")}
    require_keys(gate["checks"], expected_gate_keys, "V7-0006 gate checks")
    hotspot_gains: list[float] = []
    total_gains: list[float] = []
    original_failures: set[str] = set()
    for scale in ("L3", "L5", "L6"):
        baseline = rows[("baseline", scale)]
        candidate = rows[("candidate", scale)]
        for mode, row in (("baseline", baseline), ("candidate", candidate)):
            validate_candidate_metrics_row(
                root / f"ab/{mode}/{scale}/latest_metrics.json",
                row,
                scale=scale,
                repeats=5,
                expected_pass=True,
                timing_columns={"spectrogram_ms": "spectrogram", "correlate_ms": "correlate"},
                error_columns={"spectrogram_mixed": "spectrogram_error", "correlate_mixed": "correlate_error"},
                label=f"V7-0006 {mode} {scale}",
            )
        hotspot_gain = gain(
            parse_float(baseline["spectrogram_ms"]),
            parse_float(candidate["spectrogram_ms"]),
        )
        total_gain = gain(parse_float(baseline["total_ms"]), parse_float(candidate["total_ms"]))
        require_true(gate["checks"][f"{scale}_available"], f"V7-0006 {scale} availability")
        require_close(hotspot_gain, parse_float(gate["checks"][f"{scale}_spectrogram_gain"]), f"{scale} spectrogram gain")
        require_close(total_gain, parse_float(gate["checks"][f"{scale}_total_gain"]), f"{scale} total gain")
        numeric = (
            parse_float(candidate["spectrogram_mixed"]) <= CANDIDATE_NUMERIC_MIXED_ERROR_LIMIT
            and parse_float(candidate["correlate_mixed"]) <= CANDIDATE_NUMERIC_MIXED_ERROR_LIMIT
        )
        require_true(gate["checks"][f"{scale}_numeric"], f"spectrogram {scale} numeric gate")
        require(numeric, f"spectrogram {scale} raw numeric gate failed")
        hotspot_gains.append(hotspot_gain)
        total_gains.append(total_gain)
        if hotspot_gain < SPECTROGRAM_ORIGINAL_MIN_HOTSPOT_GAIN[scale]:
            original_failures.add(f"{scale}_spectrogram_gain")
        if total_gain < SPECTROGRAM_ORIGINAL_MIN_TOTAL_GAIN[scale]:
            original_failures.add(f"{scale}_total_gain")
        if not numeric:
            original_failures.add(f"{scale}_numeric")
    require(
        original_failures == {"L5_spectrogram_gain", "L5_total_gain"},
        "V7-0006 original challenge failure set changed",
    )
    require(all(value > 0.0 for value in hotspot_gains + total_gains), "spectrogram is not stably positive")
    validate_common_candidate_status(
        root,
        execution_id="V7-0006",
        task_phase="task2_ab",
        modes=("baseline", "candidate"),
        scales=("L3", "L5", "L6"),
        repeats=5,
        gate_case="task2_spectrogram",
        gate_rc=1,
        final_detail="V7-0006 Task2 AOT spectrogram candidate",
    )
    require_empty(root / "reports_restore.diff")
    require_empty(root / "manifests_restore.diff")
    return {
        "original_challenge_gate_status": "failed",
        "original_failure_set": sorted(original_failures),
        "retention_policy_pass": True,
        "hotspot_reduction_fraction_l3_l5_l6": hotspot_gains,
        "total_reduction_fraction_l3_l5_l6": total_gains,
        "retention_basis": "numeric pass and positive hotspot/end-to-end gain at L3/L5/L6",
    }


def derive_cwt_rejection(root: Path) -> dict[str, Any]:
    validate_run_root(root, "V7-0007")
    rows = keyed_rows(root / "candidate_summary.tsv")
    expected_rows = {(mode, scale) for mode in ("baseline", "candidate") for scale in ("L3", "L5", "L6")}
    require(set(rows) == expected_rows, "V7-0007 candidate row set mismatch")
    gate = read_json(root / "candidate_gate.json")
    require(gate["status"] == "failed", "V7-0007 CWT gate status changed")
    expected_gate_keys = {f"{scale}_{name}" for scale in ("L3", "L5", "L6") for name in ("available", "cwt_gain", "total_gain", "numeric")}
    require_keys(gate["checks"], expected_gate_keys, "V7-0007 gate checks")
    hotspot_gains: list[float] = []
    total_gains: list[float] = []
    original_failures: set[str] = set()
    for scale in ("L3", "L5", "L6"):
        baseline = rows[("baseline", scale)]
        candidate = rows[("candidate", scale)]
        for mode, row in (("baseline", baseline), ("candidate", candidate)):
            validate_candidate_metrics_row(
                root / f"ab/{mode}/{scale}/latest_metrics.json",
                row,
                scale=scale,
                repeats=5,
                expected_pass=True,
                timing_columns={"cwt_ms": "cwt", "spectrogram_ms": "spectrogram", "correlate_ms": "correlate"},
                error_columns={
                    "cwt_mixed": "cwt_error",
                    "spectrogram_mixed": "spectrogram_error",
                    "correlate_mixed": "correlate_error",
                },
                label=f"V7-0007 {mode} {scale}",
            )
        hotspot_gain = gain(parse_float(baseline["cwt_ms"]), parse_float(candidate["cwt_ms"]))
        total_gain = gain(parse_float(baseline["total_ms"]), parse_float(candidate["total_ms"]))
        require_true(gate["checks"][f"{scale}_available"], f"V7-0007 {scale} availability")
        require_close(hotspot_gain, parse_float(gate["checks"][f"{scale}_cwt_gain"]), f"{scale} CWT gain")
        require_close(total_gain, parse_float(gate["checks"][f"{scale}_total_gain"]), f"{scale} CWT total gain")
        numeric = all(
            parse_float(candidate[column]) <= CANDIDATE_NUMERIC_MIXED_ERROR_LIMIT
            for column in ("cwt_mixed", "spectrogram_mixed", "correlate_mixed")
        )
        require_true(gate["checks"][f"{scale}_numeric"], f"CWT {scale} numeric gate")
        require(numeric, f"CWT {scale} raw numeric gate failed")
        hotspot_gains.append(hotspot_gain)
        total_gains.append(total_gain)
        if hotspot_gain < CWT_ORIGINAL_MIN_HOTSPOT_GAIN[scale]:
            original_failures.add(f"{scale}_cwt_gain")
        if total_gain < CWT_ORIGINAL_MIN_TOTAL_GAIN[scale]:
            original_failures.add(f"{scale}_total_gain")
        if not numeric:
            original_failures.add(f"{scale}_numeric")
    require(
        original_failures
        == {"L3_cwt_gain", "L5_cwt_gain", "L5_total_gain", "L6_cwt_gain", "L6_total_gain"},
        "V7-0007 original gate failure set changed",
    )
    require(total_gains[1] < 0.0 and total_gains[2] < 0.0, "CWT rejection basis changed")
    validate_common_candidate_status(
        root,
        execution_id="V7-0007",
        task_phase="task2_ab",
        modes=("baseline", "candidate"),
        scales=("L3", "L5", "L6"),
        repeats=5,
        gate_case="task2_cwt_symmetry",
        gate_rc=1,
        final_detail="V7-0007 Task2 Morlet2 CWT symmetry candidate",
    )
    require_empty(root / "reports_restore.diff")
    require_empty(root / "manifests_restore.diff")
    return {
        "reason": "L5/L6 end-to-end regression",
        "original_gate_status": "failed",
        "original_failure_set": sorted(original_failures),
        "hotspot_gain_fraction_l3_l5_l6": hotspot_gains,
        "total_gain_fraction_l3_l5_l6": total_gains,
    }


def validate_buffer_status(root: Path, execution_id: str, expected_decision: str) -> None:
    gate_rc = 0 if expected_decision == "selected" else 1
    decision_case = "candidate_selected" if expected_decision == "selected" else "candidate_rejected"
    decision_detail = (
        "L5/L6 total gain at least 5 percent"
        if expected_decision == "selected"
        else "performance gate below 5 percent"
    )
    expected: dict[tuple[str, str], tuple[int, str]] = {
        ("build", "configure"): (0, "build-v7-demo"),
        ("build", "task_demos"): (0, "task1/task2"),
        ("audit", "registry"): (0, "81 operators"),
        ("audit", "dtype"): (0, "compatibility gaps"),
        ("audit", "task_steps"): (0, "14 calculation steps"),
        ("gate", "static_audits"): (0, "dtype/task steps"),
        ("gate", "task1_buffer_reuse"): (gate_rc, f"/tmp/{root.name}/candidate_gate.json"),
        ("decision", decision_case): (0, decision_detail),
        ("integrity", "restore"): (0, "reports/manifests"),
        ("final", "overall"): (0, f"{execution_id} Task1 warmup buffer reuse"),
    }
    for mode in ("baseline", "candidate"):
        for scale in ("L3", "L5", "L6"):
            expected[("task1_ab", f"{mode}_{scale}")] = (0, "repeat=5")
    if execution_id == "V7-0009":
        for level in (1, 2, 4):
            expected[("task1_full", f"L{level}")] = (0, "repeat=3")
        for level in (1, 6):
            expected[("task2_smoke", f"L{level}")] = (0, "repeat=2")
    validate_status(root / "status.tsv", expected, exact=True)


def validate_historical_timing_gate_exceptions(exceptions: list[dict[str, Any]]) -> None:
    policy = EXPECTED_ACCEPTANCE_POLICY["historical_timing_gate_exception_policy"]
    require(len(exceptions) == len(policy) == 1, "historical timing-gate exception count changed")
    exception = exceptions[0]
    expected = policy[0]
    require_keys(
        exception,
        {"execution_id", "case", "check", "value", "limit", "scope"},
        "historical timing-gate exception",
    )
    for name in ("execution_id", "case", "check", "scope"):
        require(exception[name] == expected[name], f"historical timing-gate exception {name} changed")
    require(
        parse_float(exception["value"]) > parse_float(exception["limit"]),
        "historical timing-gate exception no longer exceeds its limit",
    )


def validate_buffer_round(
    root: Path,
    execution_id: str,
    expected_decision: str,
) -> dict[str, Any]:
    validate_run_root(root, execution_id)
    rows = keyed_rows(root / "candidate_summary.tsv")
    expected_rows = {(mode, scale) for mode in ("baseline", "candidate") for scale in ("L3", "L5", "L6")}
    require(set(rows) == expected_rows, f"{execution_id} candidate row set mismatch")
    gate = read_json(root / "candidate_gate.json")
    expected_gate_keys = {f"{scale}_{name}" for scale in ("L3", "L5", "L6") for name in ("available", "total_gain", "numeric_equal", "steps_complete")}
    require_keys(gate["checks"], expected_gate_keys, f"{execution_id} buffer gate checks")
    values: dict[str, dict[str, list[float]]] = {"baseline": {}, "candidate": {}}
    errors: dict[str, dict[str, dict[str, float]]] = {"baseline": {}, "candidate": {}}
    failure_set: set[str] = set()
    timing_gate_exceptions: list[dict[str, Any]] = []
    for scale in ("L3", "L5", "L6"):
        for mode in ("baseline", "candidate"):
            row = rows[(mode, scale)]
            metrics = validate_metrics_evidence(
                root / f"ab/{mode}/{scale}/latest_metrics.json",
                expected_level=int(scale[1:]),
                expected_repeats=EXPECTED_BUFFER_REPEATS_PER_ROUND,
                expected_pass=True,
                label=f"{execution_id} buffer {mode} {scale}",
            )
            repeats = metrics["repeat_runs"]
            totals = [parse_float(item["gpu_total_ms"]) for item in repeats]
            validation_pass = metrics["validation"]["pass"] is True
            business_pass = all(item["business_numeric_pass"] is True for item in repeats)
            timing_names = set(metrics["timings"]) - {"total"}
            steps_complete = timing_names == BUFFER_TIMING_NAMES
            error_values = {
                name: parse_float(metrics[name]["mixed_error"])
                for name in BUFFER_ERROR_NAMES
                if name in metrics and "mixed_error" in metrics[name]
            }
            errors_complete = set(error_values) == BUFFER_ERROR_NAMES
            require(parse_bool(row["validation"]) is validation_pass, f"buffer {mode} {scale} TSV validation mismatch")
            require(parse_bool(row["business"]) is business_pass, f"buffer {mode} {scale} TSV business mismatch")
            require(parse_bool(row["steps_complete"]) is steps_complete, f"buffer {mode} {scale} TSV steps mismatch")
            require(validation_pass and business_pass, f"buffer {mode} {scale} raw validation failed")
            require(steps_complete, f"buffer {mode} {scale} raw timing steps incomplete")
            require(errors_complete, f"buffer {mode} {scale} raw errors incomplete")
            require_close(statistics.median(totals), parse_float(row["total_ms"]), f"buffer {mode} {scale} median")
            values[mode][scale] = totals
            errors[mode][scale] = error_values
        round_gain = gain(
            parse_float(rows[("baseline", scale)]["total_ms"]),
            parse_float(rows[("candidate", scale)]["total_ms"]),
        )
        numeric_equal = errors["candidate"][scale] == errors["baseline"][scale]
        require_true(gate["checks"][f"{scale}_available"], f"{execution_id} buffer {scale} availability")
        require_close(round_gain, parse_float(gate["checks"][f"{scale}_total_gain"]), f"buffer {scale} gain")
        require(gate["checks"][f"{scale}_numeric_equal"] is numeric_equal, f"buffer {scale} numeric equality mismatch")
        require_true(gate["checks"][f"{scale}_steps_complete"], f"buffer {scale} steps")
        if not numeric_equal:
            failure_set.add(f"{scale}_numeric_equal")
        if scale in {"L5", "L6"} and round_gain < BUFFER_MIN_TOTAL_GAIN:
            failure_set.add(f"{scale}_total_gain")

    expected_failure_set = set() if execution_id == "V7-0009" else {"L6_total_gain"}
    require(failure_set == expected_failure_set, f"{execution_id} buffer gate failure set changed")
    derived_decision = "selected" if not failure_set else "rejected"
    require(derived_decision == expected_decision, f"{execution_id} expected decision mismatch")
    require(gate["status"] == derived_decision, f"buffer decision mismatch: {root}")
    validate_buffer_status(root, execution_id, derived_decision)
    if execution_id == "V7-0009":
        for level in (1, 2, 4):
            validate_metrics_evidence(
                root / f"task1_full/L{level}/latest_metrics.json",
                expected_level=level,
                expected_repeats=3,
                expected_pass=True,
                label=f"{execution_id} Task1 full L{level}",
            )
        for level in (1, 6):
            smoke_metrics = validate_metrics_evidence(
                root / f"task2_smoke/L{level}/latest_metrics.json",
                expected_level=level,
                expected_repeats=2,
                expected_pass=True,
                label=f"{execution_id} Task2 smoke L{level}",
                allowed_skipped_timing_checks={"gpu_total_stability"} if level == 1 else set(),
            )
            stability = next(
                check
                for check in smoke_metrics["validation"]["checks"]
                if check["name"] == "gpu_total_stability"
            )
            if parse_float(stability["value"]) > parse_float(stability["limit"]):
                timing_gate_exceptions.append(
                    {
                        "execution_id": execution_id,
                        "case": f"task2_smoke/L{level}",
                        "check": "gpu_total_stability",
                        "value": parse_float(stability["value"]),
                        "limit": parse_float(stability["limit"]),
                        "scope": EXPECTED_ACCEPTANCE_POLICY[
                            "historical_timing_gate_exception_policy"
                        ][0]["scope"],
                    }
                )
        validate_historical_timing_gate_exceptions(timing_gate_exceptions)
    else:
        require(not timing_gate_exceptions, f"{execution_id} unexpected timing-gate exception")
    require_empty(root / "reports_restore.diff")
    require_empty(root / "manifests_restore.diff")
    return {**values, "timing_gate_exceptions": timing_gate_exceptions}


def derive_combined_buffer_rejection(first_root: Path, second_root: Path) -> dict[str, Any]:
    first = validate_buffer_round(first_root, "V7-0009", "selected")
    second = validate_buffer_round(second_root, "V7-0010", "rejected")
    combined: dict[str, Any] = {"round_count": 2, "repeats_per_mode_and_scale": 10, "scales": {}}
    for scale in ("L3", "L5", "L6"):
        baseline_values = first["baseline"][scale] + second["baseline"][scale]
        candidate_values = first["candidate"][scale] + second["candidate"][scale]
        require(len(baseline_values) == len(candidate_values) == 10, f"combined buffer {scale} repeat count")
        baseline_median = statistics.median(baseline_values)
        candidate_median = statistics.median(candidate_values)
        combined["scales"][scale] = {
            "baseline_median_ms": baseline_median,
            "candidate_median_ms": candidate_median,
            "gain_fraction": gain(baseline_median, candidate_median),
        }
    require(combined["scales"]["L6"]["gain_fraction"] < 0.0, "combined L6 no longer regresses")
    combined["reason"] = "second round rejected and combined L6 median regressed"
    combined["product_default"] = "retain warmup buffers"
    combined["historical_timing_gate_exceptions"] = (
        first.get("timing_gate_exceptions", []) + second.get("timing_gate_exceptions", [])
    )
    return combined


def validate_readback(
    readback_root: Path,
    source_root: Path,
    manifest_entry: dict[str, Any],
) -> dict[str, Any]:
    require(
        readback_root.name == manifest_entry["root_name"],
        f"final readback identity mismatch: {readback_root}",
    )
    require(readback_root.is_dir() and not readback_root.is_symlink(), f"missing final readback directory: {readback_root}")
    pairs = {
        "task1_source": (
            readback_root / "task1_radar_demo.cpp",
            source_root / "demo/task1_radar/task1_radar_demo.cpp",
        ),
        "runner": (
            readback_root / "run_v7_5_task1_buffer_reuse.sh",
            source_root / "scripts/platform/run_v7_5_task1_buffer_reuse.sh",
        ),
    }
    readback_files = {path.name for path in readback_root.iterdir()}
    require(
        readback_files == {readback.name for readback, _ in pairs.values()},
        "V7-0011 readback file set mismatch",
    )
    hashes: dict[str, str] = {}
    for label, (readback, source) in pairs.items():
        readback_hash = sha256(readback)
        source_hash = sha256(source)
        expected_hash = manifest_entry["files"][readback.name]
        require(
            readback_hash == source_hash == expected_hash,
            f"V7-0011 {label} readback/frozen SHA256 mismatch",
        )
        hashes[f"{label}_sha256"] = source_hash
    return {
        "execution_id": EXPECTED_FINAL_EXECUTION_ID,
        "execution_id_source": "frozen delivery policy plus exact readback directory name",
        "source_readback_match": True,
        "standalone_execution_manifest_present": False,
        "provenance_scope": "byte-identical two-file container readback; no standalone execution manifest",
        **hashes,
    }


def percent_list(values: list[float]) -> str:
    return "/".join(f"{value * 100.0:.2f}%" for value in values)


def validate_cache_decision(
    root: Path,
    cache: dict[str, Any],
    expected_operators: set[str],
) -> dict[str, Any]:
    require(cache["status"] == "passed", "cache decision failed")
    require(cache["selected_mode"] == "default", "expanded cache unexpectedly selected")
    require(cache["reason"] == "expanded cache did not meet the performance gates", "cache rejection reason mismatch")
    require(cache["selected_environment"] == DEFAULT_CACHE_ENVIRONMENT, "default cache environment mismatch")
    require_true(cache["default_valid"], "default cache validity")
    require_true(cache["expanded_valid"], "expanded cache validity")
    require(cache["expanded_return_code"] == 0, "expanded cache return code mismatch")
    require_close(
        parse_float(cache["thresholds"]["minimum_aggregate_gain"]),
        CACHE_MINIMUM_AGGREGATE_GAIN,
        "cache aggregate policy",
    )
    require_close(
        parse_float(cache["thresholds"]["maximum_single_regression"]),
        CACHE_MAXIMUM_SINGLE_REGRESSION,
        "cache regression policy",
    )
    default = load_benchmark_rows(
        root / "prepare/cache_probe/default/latest_all_ops_scale_benchmark.csv",
        expected_operators,
        require_baseline_reused=False,
        label="V7-0008 default cache probe",
    )
    expanded = load_benchmark_rows(
        root / "prepare/cache_probe/expanded/latest_all_ops_scale_benchmark.csv",
        expected_operators,
        require_baseline_reused=False,
        label="V7-0008 expanded cache probe",
    )
    comparisons = cache["comparisons"]
    require(isinstance(comparisons, list) and len(comparisons) == len(expected_operators), "cache comparison count")
    indexed: dict[str, dict[str, Any]] = {}
    gains: list[float] = []
    for comparison in comparisons:
        operator = comparison["operator"]
        require(operator not in indexed, f"duplicate cache comparison: {operator}")
        require(operator in expected_operators, f"unexpected cache comparison: {operator}")
        default_ms = default[operator]["gpu_ms"]
        expanded_ms = expanded[operator]["gpu_ms"]
        operator_gain = gain(default_ms, expanded_ms)
        require_close(default_ms, parse_float(comparison["default_ms"]), f"cache default {operator}")
        require_close(expanded_ms, parse_float(comparison["expanded_ms"]), f"cache expanded {operator}")
        require_close(operator_gain, parse_float(comparison["gain"]), f"cache gain {operator}")
        for prefix, source in (("default", default[operator]["source"]), ("expanded", expanded[operator]["source"])):
            require_close(
                parse_float(source["device_cache_peak_cached_mib"]),
                parse_float(comparison[f"{prefix}_peak_cached_mib"]),
                f"cache peak {prefix} {operator}",
            )
            require(
                int(source["device_cache_hits"]) == int(comparison[f"{prefix}_cache_hits"]),
                f"cache hits {prefix} {operator}",
            )
        indexed[operator] = comparison
        gains.append(operator_gain)
    require(set(indexed) == expected_operators, "cache comparison operator set mismatch")
    default_sum = sum(values["gpu_ms"] for values in default.values())
    expanded_sum = sum(values["gpu_ms"] for values in expanded.values())
    aggregate_gain = gain(default_sum, expanded_sum)
    maximum_regression = max(-value for value in gains)
    require_close(aggregate_gain, parse_float(cache["aggregate_gain"]), "cache aggregate gain")
    require_close(maximum_regression, parse_float(cache["maximum_single_regression"]), "cache maximum regression")
    require(aggregate_gain < CACHE_MINIMUM_AGGREGATE_GAIN, "expanded cache aggregate failure changed")
    require(
        maximum_regression <= CACHE_MAXIMUM_SINGLE_REGRESSION,
        "expanded cache single-regression topology changed",
    )
    return {
        "aggregate_gain": aggregate_gain,
        "minimum_aggregate_gain": CACHE_MINIMUM_AGGREGATE_GAIN,
        "maximum_single_regression": maximum_regression,
        "selected_mode": cache["selected_mode"],
        "failure_set": ["aggregate_gain"],
    }


def validate_v5_summary(summary: dict[str, Any]) -> None:
    require(summary.get("status") == "passed", "V5.5 summary is not passed")
    all81 = summary["all81"]
    require(all81["status"] == "passed", "V5.5 all81 status failed")
    require(all81["operator_count"] == all81["row_count"] == EXPECTED_OPERATORS, "V5.5 all81 count mismatch")
    require(all81["failed_count"] == 0 and all81["failed"] == [], "V5.5 all81 failures")
    modules = summary["modules"]
    require(modules["status"] == "passed", "V5.5 module status failed")
    require(modules["operator_count"] == modules["expected_count"] == EXPECTED_OPERATORS, "V5.5 module count")
    require(sum(item["operator_count"] for item in modules["modules"].values()) == EXPECTED_OPERATORS, "V5.5 module total")
    for name, item in modules["modules"].items():
        require(item["status"] == "passed", f"V5.5 module failed: {name}")
        require(item["operator_count"] == item["expected_count"], f"V5.5 module count: {name}")
        require(item["failed"] == [], f"V5.5 module failures: {name}")
    contracts = summary["contracts"]
    require(contracts["status"] == "passed", "V5.5 contracts failed")
    interface = contracts["interface"]
    require(interface["status"] == "passed", "V5.5 interface failed")
    require(
        interface["operator_count"] == interface["passed_count"] == EXPECTED_OPERATORS
        and interface["failed_count"] == 0,
        "V5.5 interface counts",
    )
    require(contracts["types"]["status"] == "passed", "V5.5 types failed")
    require(contracts["types"]["operator_count"] == EXPECTED_OPERATORS, "V5.5 type count")
    task = summary["task_smoke"]
    require(task["status"] == "passed", "V5.5 task smoke failed")
    require_true(task["passed"], "V5.5 task smoke pass")
    require(
        task["task_count"] == 2
        and task["step_count"] == EXPECTED_CALCULATION_STEPS
        and task["failure_count"] == 0,
        "V5.5 task smoke counts",
    )
    require(summary["plots"]["status"] == "passed", "V5.5 plot status failed")
    require(summary["plots"]["operator_total"] == EXPECTED_OPERATORS, "V5.5 plot operator count")
    require(summary["plots"]["missing_paths"] == [], "V5.5 plot paths missing")


def validate_v5_report_hashes(
    markdown_path: Path,
    json_path: Path,
    predecessor_hashes: dict[str, str],
) -> dict[str, str]:
    markdown_hash = sha256(markdown_path)
    json_hash = sha256(json_path)
    require(
        markdown_hash == predecessor_hashes["v5_5_summary_md_sha256"],
        "actual V5.5 predecessor Markdown SHA256 mismatch",
    )
    require(
        json_hash == predecessor_hashes["v5_5_summary_json_sha256"],
        "actual V5.5 predecessor JSON SHA256 mismatch",
    )
    return {"markdown_sha256": markdown_hash, "json_sha256": json_hash}


def validate_v6_report_hashes(
    markdown_path: Path,
    json_path: Path,
    report_readme_path: Path,
    predecessor_hashes: dict[str, str],
) -> dict[str, str]:
    markdown_hash = sha256(markdown_path)
    json_hash = sha256(json_path)
    report_readme_hash = sha256(report_readme_path)
    require(
        markdown_hash == predecessor_hashes["v6_final_summary_md_sha256"],
        "actual V6 predecessor Markdown SHA256 mismatch",
    )
    require(
        json_hash == predecessor_hashes["v6_final_summary_json_sha256"],
        "actual V6 predecessor JSON SHA256 mismatch",
    )
    require(
        report_readme_hash == predecessor_hashes["report_root_readme_sha256"],
        "actual final-report README SHA256 mismatch",
    )
    return {
        "markdown_sha256": markdown_hash,
        "json_sha256": json_hash,
        "report_readme_sha256": report_readme_hash,
    }


def validate_v6_evidence_manifest(source_root: Path) -> dict[str, Any]:
    manifest_path = source_root / "scripts/platform/v6_final_evidence_manifest.json"
    manifest = read_json(manifest_path)
    require_keys(
        manifest,
        {"schema_version", "version", "acceptance_policy", "tracked_policy_files", "predecessor_reports", "runs"},
        "V6 evidence manifest",
    )
    require(manifest["schema_version"] == "v6_final_evidence_manifest_v1", "V6 evidence manifest schema mismatch")
    require(manifest["version"] == "V6.8", "V6 evidence manifest version mismatch")
    require_keys(manifest["acceptance_policy"], V6_EXPECTED_ACCEPTANCE_POLICY_KEYS, "V6 acceptance policy")
    policy_files = manifest["tracked_policy_files"]
    require_keys(policy_files, V6_EXPECTED_POLICY_FILES, "V6 tracked policy files")
    for relative, expected_hash in policy_files.items():
        require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"invalid V6 policy SHA256: {relative}")
        require(sha256(source_root / relative) == expected_hash, f"V6 tracked policy SHA256 mismatch: {relative}")
    require_keys(
        manifest["predecessor_reports"],
        {"v5_5_summary_md_sha256", "v5_5_summary_json_sha256"},
        "V6 predecessor reports",
    )
    for name, expected_hash in manifest["predecessor_reports"].items():
        require(re.fullmatch(r"[0-9a-f]{64}", expected_hash) is not None, f"invalid V6 predecessor SHA256: {name}")
    require_keys(manifest["runs"], {"V6-0138", "V6-0141"}, "V6 evidence runs")
    for execution_id, run in manifest["runs"].items():
        require_keys(
            run,
            {"root_name", "archive_name", "archive_sha256", "console_name", "console_sha256"},
            f"{execution_id} V6 evidence run",
        )
        require(run["archive_name"] == f"cetc_v6_{execution_id[-4:]}_latest.tar.gz", f"{execution_id} V6 archive name")
        require(run["console_name"] == f"cetc_v6_{execution_id[-4:]}_console.log", f"{execution_id} V6 console name")
        for name in ("archive_sha256", "console_sha256"):
            require(re.fullmatch(r"[0-9a-f]{64}", run[name]) is not None, f"invalid {execution_id} V6 {name}")
    return manifest


def validate_v6_true_error_diagnostics(
    diagnostics: dict[str, Any],
    acceptance_policy: dict[str, Any],
) -> None:
    require_keys(diagnostics, {"error_class_counts", "passed_true_error_rows", "policy"}, "V6 benchmark diagnostics")
    require(
        diagnostics["policy"] == acceptance_policy["passed_true_error_diagnostic_policy"],
        "V6 true-error diagnostic policy mismatch",
    )
    counts = diagnostics["error_class_counts"]
    require_keys(counts, {"ok", "performance-bound", "true-error"}, "V6 error-class counts")
    require(
        all(isinstance(value, int) and not isinstance(value, bool) and value >= 0 for value in counts.values()),
        "V6 error-class counts must be non-negative integers",
    )
    require(sum(counts.values()) == 486 and counts["true-error"] == 5, "V6 error-class count mismatch")
    threshold = parse_float(acceptance_policy["benchmark_true_error_threshold"])
    rows = diagnostics["passed_true_error_rows"]
    require(len(rows) == len(V6_EXPECTED_TRUE_ERROR_DIAGNOSTICS), "V6 true-error diagnostic row count mismatch")
    identities: set[tuple[str, str, int]] = set()
    for row in rows:
        require_keys(row, {"module", "operator", "scale_level", "mixed_error", "error_class"}, "V6 true-error row")
        require(row["error_class"] == "true-error", "V6 diagnostic error class mismatch")
        require(parse_float(row["mixed_error"]) > threshold, "V6 true-error diagnostic is below threshold")
        identities.add((row["module"], row["operator"], row["scale_level"]))
    require(identities == V6_EXPECTED_TRUE_ERROR_DIAGNOSTICS, "V6 true-error diagnostic identity set mismatch")


def validate_v6_summary(
    summary: dict[str, Any],
    source_root: Path,
    v6_manifest: dict[str, Any] | None = None,
) -> None:
    require(summary.get("status") == "passed", "V6 summary is not passed")
    require(summary.get("version") == "V6.8", "unexpected V6 summary version")
    require(summary.get("schema_version") == "v6_final_summary_v2", "unexpected V6 summary schema")
    require_true(summary["conclusion"]["v6_closed"], "V6 closure")
    require_true(
        summary["conclusion"]["terminal_product_source_fingerprint_match"],
        "V6 terminal product fingerprint",
    )
    gates = summary["gates"]
    expected_gate_names = {"all81_correctness", "interfaces", "dtype", "tasks", "all81_performance", "platform", "integrity"}
    require_keys(gates, expected_gate_names, "V6 gates")
    for name, gate in gates.items():
        require(gate["status"] == "passed", f"V6 gate failed: {name}")
    require(
        gates["all81_correctness"]["operators"] == EXPECTED_OPERATORS
        and gates["all81_correctness"]["failed"] == 0,
        "V6 all81 correctness",
    )
    require(
        gates["interfaces"]["operators"] == EXPECTED_OPERATORS
        and gates["interfaces"]["compatibility_gap_count"] == 0,
        "V6 interface gate",
    )
    require(gates["dtype"]["operator_dtype_missing_edges"] == 0, "V6 dtype gaps")
    require(
        gates["tasks"]["case_count"] == 24
        and gates["tasks"]["step_row_count"] == 168
        and gates["tasks"]["calculation_step_count"] == EXPECTED_CALCULATION_STEPS
        and gates["tasks"]["public_calculation_step_count"] == 6
        and gates["tasks"]["mixed_calculation_step_count"] == 8
        and gates["tasks"]["public_operator_link_declaration_count"] == EXPECTED_CALCULATION_STEPS
        and gates["tasks"]["failure_count"] == 0,
        "V6 task gate",
    )
    performance = gates["all81_performance"]
    require(
        performance["row_count"] == 486
        and performance["operators"] == EXPECTED_OPERATORS
        and performance["scale_levels"] == 6
        and performance["warmup"] == 5
        and performance["repeat"] == 30
        and performance["failed_rows"] == 0,
        "V6 performance gate",
    )
    require(
        performance["passed_true_error_diagnostic_count"] == 5
        and performance["l6_raw_metrics"]["bound_metrics_count"] == EXPECTED_OPERATORS
        and performance["l6_raw_metrics"]["case_detail_operator_count"] == 73
        and performance["l6_raw_metrics"]["summary_only_operator_count"] == 8,
        "V6 performance diagnostic evidence",
    )
    require_true(gates["platform"]["valid_lifecycle_result"], "V6 platform lifecycle")
    require(
        gates["platform"]["graph_lifecycle_statuses"]
        == {
            "graph_capture_begin_status": 0,
            "graph_capture_work_status": 0,
            "graph_capture_end_status": 0,
            "graph_instantiate_status": 0,
            "graph_launch_status": 0,
            "graph_sync_status": 0,
        },
        "V6 Graph lifecycle statuses",
    )
    integrity = gates["integrity"]
    require(
        integrity["manifest_diff_count"] == 0 and integrity["report_diff_count"] == 0,
        "V6 integrity diffs",
    )
    require_true(integrity["product_source_match"], "V6 product source match")
    v6_manifest_path = source_root / "scripts/platform/v6_final_evidence_manifest.json"
    if v6_manifest is None:
        v6_manifest = validate_v6_evidence_manifest(source_root)
    acceptance = v6_manifest["acceptance_policy"]
    validate_v6_true_error_diagnostics(summary["benchmark_diagnostics"], acceptance)
    historical = summary["historical_policy"]
    require(
        historical["retained_v6_7_direction_count"] == acceptance["retained_v6_7_direction_count"]
        and historical["v6_1_task_baseline_ms"] == acceptance["v6_1_task_baseline_ms"]
        and historical["residual_assessment_policy"] == acceptance["residual_assessment_policy"],
        "V6 historical policy mismatch",
    )
    evidence = summary["evidence"]
    require(
        evidence["evidence_manifest"]["sha256"] == sha256(v6_manifest_path),
        "V6 evidence manifest trust anchor mismatch",
    )
    for execution_id, evidence_key in (("V6-0138", "v6_0138"), ("V6-0141", "v6_0141")):
        run = v6_manifest["runs"][execution_id]
        require(
            evidence[evidence_key]["archive_sha256"] == run["archive_sha256"]
            and evidence[evidence_key]["console_sha256"] == run["console_sha256"],
            f"{execution_id} predecessor evidence hash mismatch",
        )
    require(
        evidence["v5_5_restored_summary"]["json_sha256"]
        == v6_manifest["predecessor_reports"]["v5_5_summary_json_sha256"],
        "V5.5 predecessor JSON trust anchor mismatch",
    )


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
    require(report_root.is_dir() and not report_root.is_symlink(), "report root must be a real directory")
    files: set[Path] = set()
    for path in report_root.rglob("*"):
        require(not path.is_symlink(), f"report tree contains symlink: {path}")
        require(path.is_dir() or path.is_file(), f"report tree contains special node: {path}")
        if path.is_file():
            files.add(path)
    return files


def main() -> int:
    args = parse_args()
    source_root = Path(__file__).resolve().parents[2]
    requested_source_root = canonical_input_path(args.source_root, "source root")
    require(requested_source_root == source_root, "source root must be the repository containing this finalizer")
    manifest_path = (
        canonical_input_path(args.evidence_manifest, "evidence manifest")
        if args.evidence_manifest
        else source_root / "scripts/platform/v7_final_evidence_manifest.json"
    )
    evidence_manifest = load_evidence_manifest(manifest_path, source_root)
    roots = {
        "correlate": canonical_input_path(args.correlate_root, "V7-0005 root"),
        "spectrogram": canonical_input_path(args.spectrogram_root, "V7-0006 root"),
        "cwt": canonical_input_path(args.cwt_root, "V7-0007 root"),
        "demo": canonical_input_path(args.demo_root, "V7-0008 root"),
        "buffer_first": canonical_input_path(args.buffer_first_root, "V7-0009 root"),
        "buffer_second": canonical_input_path(args.buffer_second_root, "V7-0010 root"),
    }
    readback_root = canonical_input_path(args.final_readback_root, "V7-0011 readback root")
    archives = {
        "V7-0005": canonical_input_path(args.correlate_archive, "V7-0005 archive"),
        "V7-0006": canonical_input_path(args.spectrogram_archive, "V7-0006 archive"),
        "V7-0007": canonical_input_path(args.cwt_archive, "V7-0007 archive"),
        "V7-0008": canonical_input_path(args.demo_archive, "V7-0008 archive"),
        "V7-0009": canonical_input_path(args.buffer_first_archive, "V7-0009 archive"),
        "V7-0010": canonical_input_path(args.buffer_second_archive, "V7-0010 archive"),
    }
    consoles = {
        "V7-0005": canonical_input_path(args.correlate_console, "V7-0005 console"),
        "V7-0006": canonical_input_path(args.spectrogram_console, "V7-0006 console"),
        "V7-0007": canonical_input_path(args.cwt_console, "V7-0007 console"),
        "V7-0008": canonical_input_path(args.demo_console, "V7-0008 console"),
        "V7-0009": canonical_input_path(args.buffer_first_console, "V7-0009 console"),
        "V7-0010": canonical_input_path(args.buffer_second_console, "V7-0010 console"),
    }
    root_by_execution = {
        "V7-0005": roots["correlate"],
        "V7-0006": roots["spectrogram"],
        "V7-0007": roots["cwt"],
        "V7-0008": roots["demo"],
        "V7-0009": roots["buffer_first"],
        "V7-0010": roots["buffer_second"],
    }
    frozen_hashes: dict[str, dict[str, str]] = {}
    for execution_id, root in root_by_execution.items():
        entry = evidence_manifest["runs"][execution_id]
        archive = archives[execution_id]
        console = consoles[execution_id]
        validate_frozen_run_inputs(execution_id, root, archive, console, entry)
        archive_hash = validate_archive(archive, root, archive_evidence_files(execution_id))
        terminal_lines = {
            f"OUT=/tmp/{root.name}",
            f"ARCHIVE=/tmp/{entry['archive_name']}",
            f"CONSOLE=/tmp/{entry['console_name']}",
            f"RC={1 if execution_id in {'V7-0005', 'V7-0006', 'V7-0007'} else 0}",
        }
        if execution_id != "V7-0008":
            terminal_lines.update({"TAR_RC=0", "ALIAS_RC=0"})
        console_hash = validate_console(console, terminal_lines)
        frozen_hashes[execution_id] = {
            "archive_sha256": archive_hash,
            "console_sha256": console_hash,
        }

    output_dir = Path(args.output_dir).resolve()
    report_root = output_dir.parents[1]
    require(output_dir == report_root / "zhongkexin/v7_final", "invalid V7 output path")
    v5_summary_path = Path(args.v5_summary_json).resolve()
    v6_summary_path = Path(args.v6_summary_json).resolve()
    v5_summary_markdown_path = report_root / "zhongkexin/v5_5_final/summary.md"
    v6_summary_markdown_path = report_root / "zhongkexin/v6_final/summary.md"
    report_readme_path = report_root / "README.md"
    require(v5_summary_path == report_root / "zhongkexin/v5_5_final/summary.json", "invalid V5.5 summary path")
    require(v6_summary_path == report_root / "zhongkexin/v6_final/summary.json", "invalid V6 summary path")
    allowed_reports = {
        report_readme_path,
        report_root / "zhongkexin/v5_5_final/summary.md",
        v5_summary_path,
        v6_summary_markdown_path,
        v6_summary_path,
        output_dir / "summary.md",
        output_dir / "summary.json",
    }
    preexisting_reports = report_file_inventory(report_root)
    require(preexisting_reports <= allowed_reports, "unexpected pre-existing report files")
    required_predecessors = allowed_reports - {output_dir / "summary.md", output_dir / "summary.json"}
    require(required_predecessors <= preexisting_reports, "V5.5/V6 final reports are incomplete")

    v5_summary = read_json(v5_summary_path)
    v6_summary = read_json(v6_summary_path)
    validate_v5_summary(v5_summary)
    predecessor_hashes = evidence_manifest["predecessor_reports"]
    v6_manifest_path = source_root / "scripts/platform/v6_final_evidence_manifest.json"
    require(
        sha256(v6_manifest_path) == predecessor_hashes["v6_evidence_manifest_sha256"],
        "V6 evidence manifest SHA256 mismatch",
    )
    v6_manifest = validate_v6_evidence_manifest(source_root)
    validate_v6_summary(v6_summary, source_root, v6_manifest)
    v5_report_hashes = validate_v5_report_hashes(
        v5_summary_markdown_path,
        v5_summary_path,
        v6_manifest["predecessor_reports"],
    )
    v6_report_hashes = validate_v6_report_hashes(
        v6_summary_markdown_path,
        v6_summary_path,
        report_readme_path,
        predecessor_hashes,
    )
    operator_policy = load_operator_policy(source_root)
    task_policy = load_task_contract_policy(source_root)

    demo = read_json(roots["demo"] / "demo/summary.json")
    cache = read_json(roots["demo"] / "prepare/cache_decision.json")
    require(demo.get("cache") == cache, "demo/cache decision evidence mismatch")
    gates, demo_measurements = validate_demo_gates(roots["demo"], demo, operator_policy, task_policy)
    cache_decision = validate_cache_decision(roots["demo"], cache, operator_policy["demo_cache_probe4"])

    correlate, filter_rejection = derive_correlate(roots["correlate"])
    spectrogram = derive_spectrogram(roots["spectrogram"])
    cwt_rejection = derive_cwt_rejection(roots["cwt"])
    buffer_rejection = derive_combined_buffer_rejection(roots["buffer_first"], roots["buffer_second"])
    source_fingerprint = validate_v7_0008_source_fingerprint(roots["demo"], source_root)
    readback = validate_readback(
        readback_root,
        source_root,
        evidence_manifest["runs"][EXPECTED_FINAL_EXECUTION_ID],
    )

    payload = {
        "schema_version": "v7_final_summary_v2",
        "status": "passed",
        "version": "V7.6",
        "final_execution_id": readback["execution_id"],
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "conclusion": {
            "v5_5_closed": v5_summary["status"] == "passed",
            "v6_closed": v6_summary["status"] == "passed",
            "v7_closed": readback["source_readback_match"] is True,
            "performance_candidate_policy": "closed; do not start further GPU candidates",
        },
        "gates": gates,
        "demo": demo_measurements,
        "retained": {"aot_correlate": correlate, "aot_spectrogram": spectrogram},
        "rejected": {
            "aot_filter": filter_rejection,
            "morlet2_cwt_symmetry": cwt_rejection,
            "expanded_device_storage_cache": {
                "aggregate_gain_fraction": cache_decision["aggregate_gain"],
                "required_gain_fraction": cache_decision["minimum_aggregate_gain"],
                "maximum_single_regression_fraction": cache_decision["maximum_single_regression"],
                "selected_mode": cache_decision["selected_mode"],
            },
            "task1_release_warmup_buffers": buffer_rejection,
        },
        "evidence": {
            "evidence_manifest_path": str(manifest_path),
            "evidence_manifest_sha256": sha256(manifest_path),
            "v5_5_summary_markdown_sha256": v5_report_hashes["markdown_sha256"],
            "v5_5_summary_sha256": v5_report_hashes["json_sha256"],
            "v6_summary_markdown_sha256": v6_report_hashes["markdown_sha256"],
            "v6_summary_sha256": v6_report_hashes["json_sha256"],
            "report_root_readme_sha256": v6_report_hashes["report_readme_sha256"],
            "v6_evidence_manifest_sha256": sha256(v6_manifest_path),
            "operator_policy_sha256": sha256(source_root / "scripts/test/operator_sets.json"),
            "task_contract_policy_sha256": sha256(source_root / "scripts/test/task_step_contracts.json"),
            "v7_0005": {
                "root": str(roots["correlate"]),
                **evidence_hashes(roots["correlate"]),
                "raw_metrics_set_sha256": sha256_file_set(
                    roots["correlate"], list(roots["correlate"].glob("modes/*/L*/latest_metrics.json"))
                ),
                "archive_bound_file_set_sha256": sha256_file_set(
                    roots["correlate"],
                    [roots["correlate"] / relative for relative in archive_evidence_files("V7-0005")],
                ),
                **frozen_hashes["V7-0005"],
            },
            "v7_0006": {
                "root": str(roots["spectrogram"]),
                **evidence_hashes(roots["spectrogram"]),
                "raw_metrics_set_sha256": sha256_file_set(
                    roots["spectrogram"], list(roots["spectrogram"].glob("ab/*/L*/latest_metrics.json"))
                ),
                "archive_bound_file_set_sha256": sha256_file_set(
                    roots["spectrogram"],
                    [roots["spectrogram"] / relative for relative in archive_evidence_files("V7-0006")],
                ),
                **frozen_hashes["V7-0006"],
            },
            "v7_0007": {
                "root": str(roots["cwt"]),
                **evidence_hashes(roots["cwt"]),
                "raw_metrics_set_sha256": sha256_file_set(
                    roots["cwt"], list(roots["cwt"].glob("ab/*/L*/latest_metrics.json"))
                ),
                "archive_bound_file_set_sha256": sha256_file_set(
                    roots["cwt"],
                    [roots["cwt"] / relative for relative in archive_evidence_files("V7-0007")],
                ),
                **frozen_hashes["V7-0007"],
            },
            "v7_0008": {
                "root": str(roots["demo"]),
                "summary_sha256": sha256(roots["demo"] / "demo/summary.json"),
                "source_fingerprint": source_fingerprint,
                "archive_bound_file_set_sha256": sha256_file_set(
                    roots["demo"],
                    [roots["demo"] / relative for relative in archive_evidence_files("V7-0008")],
                ),
                **frozen_hashes["V7-0008"],
            },
            "v7_0009": {
                "root": str(roots["buffer_first"]),
                **evidence_hashes(roots["buffer_first"]),
                "raw_metrics_set_sha256": sha256_file_set(
                    roots["buffer_first"], list(roots["buffer_first"].glob("ab/*/L*/latest_metrics.json"))
                ),
                "archive_bound_file_set_sha256": sha256_file_set(
                    roots["buffer_first"],
                    [roots["buffer_first"] / relative for relative in archive_evidence_files("V7-0009")],
                ),
                **frozen_hashes["V7-0009"],
            },
            "v7_0010": {
                "root": str(roots["buffer_second"]),
                **evidence_hashes(roots["buffer_second"]),
                "raw_metrics_set_sha256": sha256_file_set(
                    roots["buffer_second"], list(roots["buffer_second"].glob("ab/*/L*/latest_metrics.json"))
                ),
                "archive_bound_file_set_sha256": sha256_file_set(
                    roots["buffer_second"],
                    [roots["buffer_second"] / relative for relative in archive_evidence_files("V7-0010")],
                ),
                **frozen_hashes["V7-0010"],
            },
            "v7_0011": {"root": str(readback_root), **readback},
        },
    }

    summary_json = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    timing_exception = buffer_rejection["historical_timing_gate_exceptions"][0]
    markdown = f"""# V7 最终终测汇总

## 结论

- 状态：`{payload['status']}`；V5.5、V6、V7 均已关闭，最终执行编号 `{payload['final_execution_id']}`。
- 不再启动 GPU 性能候选；既有性能结论保持不变。
- 五分钟演示 wall：`{payload['demo']['wall_seconds']:.3f}/{payload['demo']['wall_limit_seconds']:.0f} s`。
- Top30：`{gates['top30_passed']}/{gates['top30_total']}`，中位加速 `{payload['demo']['top30_median_speedup']:.3f}x`，几何平均 `{payload['demo']['top30_geometric_mean_speedup']:.3f}x`。

## 最终门禁

| 检查 | 结果 |
| --- | ---: |
| all81 correctness | `{gates['all81_passed']}/{gates['all81_total']}` |
| dtype 缺口 | `{gates['dtype_gap_count']}` |
| Task timing/accuracy 步骤 | `{gates['calculation_steps_passed']}/{gates['calculation_steps_total']}` |
| Task1 / Task2 L1-L6 | `{gates['task1_l1_l6_passed']}/6` / `{gates['task2_l1_l6_passed']}/6` |
| Top30 | `{gates['top30_passed']}/{gates['top30_total']}` |
| 报告/manifest 恢复 diff | `{gates['restore_diff_count']}` |

## 最终演示

- Task1 L6 GPU median：`{payload['demo']['task1_l6_gpu_median_ms']:.5f} ms`。
- Task2 L6 GPU median：`{payload['demo']['task2_l6_gpu_median_ms']:.4f} ms`。
- 进程显存峰值：`{payload['demo']['gpu_memory_peak_mib']:.0f} MiB`；GPU 利用率峰值 `{payload['demo']['gpu_utilization_peak_percent']:.0f}%`。

## 保留与关闭

- 保留 AOT correlate：L3/L6 热点下降 `{percent_list(correlate['hotspot_reduction_fraction_l3_l6'])}`，端到端下降 `{percent_list(correlate['total_reduction_fraction_l3_l6'])}`。
- 保留 AOT spectrogram：L3/L5/L6 热点下降 `{percent_list(spectrogram['hotspot_reduction_fraction_l3_l5_l6'])}`。
- AOT filter 的 L3/L6 demod mixed error 均超过结构化证据中的阈值，默认关闭。
- Morlet2 CWT 对称路径 L5/L6 端到端变化为 `{percent_list(cwt_rejection['total_gain_fraction_l3_l5_l6'][1:])}`，默认关闭。
- 扩大 DeviceStorage cache 总收益 `{cache_decision['aggregate_gain'] * 100:.3f}%`，低于冻结门限 `{cache_decision['minimum_aggregate_gain'] * 100:.1f}%`，保持默认缓存。
- Task1 预热 buffer 释放两轮合并 L6 变化 `{buffer_rejection['scales']['L6']['gain_fraction'] * 100:.2f}%`，保持产品默认关闭。

## 证据

- V6 前置汇总 `summary.md/json`、V6 evidence manifest 和报告目录 README 均与 V7 manifest 中冻结的 SHA256 一致；任一正文改值都会判红。
- V7-0005/0006/0007：候选 TSV、gate JSON 和 status TSV 均已校验并记录 SHA256。
- V7-0008/0009/0010：结构化结果、归档和 console 均已校验并记录 SHA256。
- {payload['final_execution_id']}：容器回读的 Task1 源码和 runner 与当前仓库 SHA256 一致。
- {payload['final_execution_id']} 来源边界：当前只有两文件字节级回读，没有独立执行 manifest；执行编号由冻结交付口径和精确目录名共同约束。
- 历史门禁边界：V7-0009 补充 Task2 L1 smoke 以 `--skip-timing-validation` 运行，`{timing_exception['check']}` 原始值 `{timing_exception['value']:.6f}` 超过 limit `{timing_exception['limit']:.2f}`；该项不是最终演示门，已单独披露且不外推为通过。
"""
    atomic_write(output_dir / "summary.json", summary_json)
    atomic_write(output_dir / "summary.md", markdown)
    actual_reports = report_file_inventory(report_root)
    require(actual_reports == allowed_reports, "final report file set mismatch")
    print(
        json.dumps(
            {
                "status": payload["status"],
                "final_execution_id": payload["final_execution_id"],
                "output_dir": str(output_dir),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
