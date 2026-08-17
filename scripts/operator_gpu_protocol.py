#!/usr/bin/env python3
"""Shared validation helpers for the frozen operator GPU protocol.

This module is intentionally independent of the CUDA build.  It validates the
immutable baseline snapshot, canonicalizes workload keys, and supplies the
comparison code with one source of truth for missing/invalid measurements.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


EXPECTED_COMMIT = "75a700da93eb7ebe6133392273493ef90cf54d82"
EXPECTED_LEVELS = tuple(f"L{index}" for index in range(1, 7))
EXPECTED_WARMUP = 5
EXPECTED_REPEAT = 30
EXPECTED_OPERATOR_COUNT = 81
EXPECTED_ROW_COUNT = 486
KEY_FIELDS = (
    "operator",
    "scale_level",
    "scale_profile",
    "scale_fields",
    "input_elements",
    "power_of_two_dimensions",
)


class ProtocolError(RuntimeError):
    """Raised when a protocol artifact is unsafe to compare."""


@dataclass(frozen=True)
class BaselineSnapshot:
    root: Path
    rows: tuple[dict[str, str], ...]
    keys: frozenset[tuple[str, ...]]
    csv_sha256: str
    frozen_sha256: str
    metadata: dict[str, Any]


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ProtocolError(f"cannot read JSON: {path}: {exc}") from exc


def _read_csv(path: Path) -> list[dict[str, str]]:
    try:
        with path.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))
    except OSError as exc:
        raise ProtocolError(f"cannot read CSV: {path}: {exc}") from exc


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise ProtocolError(f"cannot hash file: {path}: {exc}") from exc
    return digest.hexdigest()


def _canonical_value(value: Any) -> str:
    if isinstance(value, str):
        stripped = value.strip()
        if stripped == "":
            return ""
        try:
            value = json.loads(stripped)
        except json.JSONDecodeError:
            return stripped
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def canonical_scale_fields(value: Any) -> str:
    if isinstance(value, str):
        try:
            value = json.loads(value)
        except json.JSONDecodeError as exc:
            raise ProtocolError(f"invalid scale_fields JSON: {value!r}") from exc
    if not isinstance(value, dict):
        raise ProtocolError(f"scale_fields must be an object: {value!r}")
    return _canonical_value(value)


def _bool_text(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    text = str(value).strip().lower()
    if text in {"true", "1"}:
        return "true"
    if text in {"false", "0"}:
        return "false"
    raise ProtocolError(f"invalid boolean value: {value!r}")


def workload_key(row: dict[str, Any]) -> tuple[str, ...]:
    missing = [field for field in KEY_FIELDS if field not in row]
    if missing:
        raise ProtocolError(f"workload row missing fields {missing}: {row.get('operator', '<unknown>')}")
    return (
        str(row["operator"]),
        str(row["scale_level"]),
        str(row["scale_profile"]),
        canonical_scale_fields(row["scale_fields"]),
        str(int(row["input_elements"])),
        _bool_text(row["power_of_two_dimensions"]),
    )


def _finite_float(row: dict[str, Any], field: str, *, required: bool = False) -> float | None:
    raw = row.get(field)
    if raw in (None, ""):
        if required:
            raise ProtocolError(f"missing required numeric field {field} for {row.get('operator')}/{row.get('scale_level')}")
        return None
    try:
        value = float(raw)
    except (TypeError, ValueError) as exc:
        raise ProtocolError(f"invalid numeric field {field}={raw!r}") from exc
    if not math.isfinite(value):
        raise ProtocolError(f"non-finite numeric field {field}={raw!r}")
    return value


def _integer(row: dict[str, Any], field: str, expected: int | None = None) -> int:
    raw = row.get(field)
    try:
        value = int(raw)
    except (TypeError, ValueError) as exc:
        raise ProtocolError(f"invalid integer field {field}={raw!r}") from exc
    if expected is not None and value != expected:
        raise ProtocolError(f"{field}={value}, expected {expected}")
    return value


def _metadata_path(root: Path, level: str) -> Path:
    return root / "inputs" / f"{level}_scale_metadata.json"


def _manifest_path(root: Path, level: str, operator: str) -> Path:
    return root / "inputs" / level / operator / "manifest.json"


def _get_path(payload: Any, dotted: str) -> Any:
    current = payload
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            raise ProtocolError(f"manifest missing field {dotted}")
        current = current[part]
    return current


def _values_equal(left: Any, right: Any) -> bool:
    if isinstance(left, float) or isinstance(right, float):
        try:
            return math.isclose(float(left), float(right), rel_tol=0.0, abs_tol=1e-12)
        except (TypeError, ValueError):
            return False
    return left == right


def _validate_manifest_against_metadata(root: Path, level: str, item: dict[str, Any]) -> None:
    operator = str(item.get("operator", ""))
    manifest_path = _manifest_path(root, level, operator)
    if not manifest_path.is_file():
        raise ProtocolError(f"missing frozen input manifest: {manifest_path}")
    payload = _read_json(manifest_path)
    cases = payload.get("perf_cases") if isinstance(payload, dict) else None
    if not isinstance(cases, list) or len(cases) != 1 or not isinstance(cases[0], dict):
        raise ProtocolError(f"frozen manifest must contain exactly one perf case: {manifest_path}")
    case = cases[0]
    if case.get("scale_level") != level:
        raise ProtocolError(f"manifest scale mismatch: {manifest_path}")
    for dotted, expected in item.get("scale_fields", {}).items():
        actual = _get_path(case, dotted)
        if not _values_equal(actual, expected):
            raise ProtocolError(
                f"frozen manifest mismatch {manifest_path}: {dotted}={actual!r}, expected {expected!r}"
            )


def validate_frozen_baseline(root: Path, *, require_all81: bool = True) -> BaselineSnapshot:
    """Validate and load the immutable baseline without modifying it."""

    root = root.resolve()
    frozen_path = root / "FROZEN"
    csv_path = root / "gpu_baseline.csv"
    metadata_path = root / "run_metadata.json"
    if not frozen_path.is_file() or not csv_path.is_file() or not metadata_path.is_file():
        raise ProtocolError(f"incomplete frozen baseline root: {root}")
    frozen_text = frozen_path.read_text(encoding="utf-8")
    if "Do not modify this snapshot." not in frozen_text:
        raise ProtocolError(f"baseline is not marked immutable: {frozen_path}")
    metadata = _read_json(metadata_path)
    if metadata.get("status") != "FROZEN":
        raise ProtocolError(f"baseline metadata status is not FROZEN: {metadata_path}")
    if metadata.get("baseline_commit") != EXPECTED_COMMIT:
        raise ProtocolError(f"unexpected baseline commit: {metadata.get('baseline_commit')!r}")
    if require_all81:
        expected_metadata = {
            "operator_set": "all81",
            "operator_count": EXPECTED_OPERATOR_COUNT,
            "expected_rows": EXPECTED_ROW_COUNT,
            "scale_levels": list(EXPECTED_LEVELS),
            "warmup": EXPECTED_WARMUP,
            "repeat": EXPECTED_REPEAT,
        }
        for field, expected in expected_metadata.items():
            if metadata.get(field) != expected:
                raise ProtocolError(f"baseline metadata {field}={metadata.get(field)!r}, expected {expected!r}")

    rows = _read_csv(csv_path)
    if require_all81 and len(rows) != EXPECTED_ROW_COUNT:
        raise ProtocolError(f"baseline rows={len(rows)}, expected {EXPECTED_ROW_COUNT}")
    keys: set[tuple[str, ...]] = set()
    operators: set[str] = set()
    levels: set[str] = set()
    for row in rows:
        key = workload_key(row)
        if key in keys:
            raise ProtocolError(f"duplicate baseline workload key: {key}")
        keys.add(key)
        operators.add(key[0])
        levels.add(key[1])
        _integer(row, "warmup", EXPECTED_WARMUP)
        _integer(row, "repeat", EXPECTED_REPEAT)
        if row.get("baseline_commit") != EXPECTED_COMMIT:
            raise ProtocolError(f"row baseline_commit mismatch: {row.get('operator')}/{row.get('scale_level')}")
        if row.get("correctness_status") != "PASS":
            raise ProtocolError(f"baseline correctness is not PASS: {row.get('operator')}/{row.get('scale_level')}")
        _finite_float(row, "gpu_e2e_median_ms", required=True)
        _finite_float(row, "saved_cpu_median_ms", required=True)
        _finite_float(row, "gpu_kernel_median_ms")
    if require_all81 and (len(operators) != EXPECTED_OPERATOR_COUNT or levels != set(EXPECTED_LEVELS)):
        raise ProtocolError(f"baseline coverage operators={len(operators)}, levels={sorted(levels)}")

    for level in EXPECTED_LEVELS if require_all81 else sorted(levels):
        metadata_level_path = _metadata_path(root, level)
        level_payload = _read_json(metadata_level_path)
        level_items = level_payload.get("operators") if isinstance(level_payload, dict) else None
        if not isinstance(level_items, dict):
            raise ProtocolError(f"invalid frozen scale metadata: {metadata_level_path}")
        if require_all81 and len(level_items) != EXPECTED_OPERATOR_COUNT:
            raise ProtocolError(f"frozen metadata {level} operators={len(level_items)}")
        for item in level_items.values():
            if not isinstance(item, dict):
                raise ProtocolError(f"invalid operator metadata in {metadata_level_path}")
            _validate_manifest_against_metadata(root, level, item)
            metadata_key = workload_key(item)
            if metadata_key not in keys:
                raise ProtocolError(f"metadata workload is absent from baseline CSV: {metadata_key}")

    return BaselineSnapshot(
        root=root,
        rows=tuple(rows),
        keys=frozenset(keys),
        csv_sha256=sha256_file(csv_path),
        frozen_sha256=sha256_file(frozen_path),
        metadata=metadata,
    )


def validate_optimized_rows(
    path: Path,
    baseline: BaselineSnapshot,
    expected_keys: frozenset[tuple[str, ...]] | None = None,
) -> list[dict[str, str]]:
    rows = _read_csv(path)
    by_key: dict[tuple[str, ...], dict[str, str]] = {}
    for row in rows:
        key = workload_key(row)
        if key in by_key:
            raise ProtocolError(f"duplicate optimized workload key: {key}")
        by_key[key] = row
    expected = baseline.keys if expected_keys is None else expected_keys
    missing = expected - by_key.keys()
    extra = by_key.keys() - expected
    if missing or extra:
        message = []
        if missing:
            message.append(f"missing={len(missing)}")
        if extra:
            message.append(f"extra={len(extra)}")
        raise ProtocolError("optimized workload coverage mismatch: " + ", ".join(message))
    ordered = []
    for baseline_row in baseline.rows:
        if workload_key(baseline_row) not in expected:
            continue
        row = by_key[workload_key(baseline_row)]
        for field in ("warmup", "repeat"):
            if field in row and row[field] not in ("", None):
                _integer(row, field, _integer(baseline_row, field))
        if row.get("case_set") not in (None, "", "full"):
            raise ProtocolError(f"optimized case_set is not full: {row.get('operator')}/{row.get('scale_level')}")
        _finite_float(row, "gpu_e2e_median_ms", required=True)
        _finite_float(row, "gpu_kernel_median_ms")
        ordered.append(row)
    return ordered


def _cli() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--validate-baseline", metavar="ROOT")
    args = parser.parse_args()
    if args.validate_baseline:
        snapshot = validate_frozen_baseline(Path(args.validate_baseline))
        print(
            f"PASS frozen baseline: rows={len(snapshot.rows)} "
            f"csv_sha256={snapshot.csv_sha256}"
        )
        return 0
    parser.error("use --validate-baseline ROOT")
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(_cli())
    except ProtocolError as exc:
        print(f"[operator-gpu-protocol] error: {exc}", file=sys.stderr)
        raise SystemExit(2)
