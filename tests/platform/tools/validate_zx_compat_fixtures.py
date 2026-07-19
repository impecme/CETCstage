#!/usr/bin/env python3

"""Validate external ZQ500 compatibility fixtures against a frozen manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any, Mapping


SCHEMA_VERSION = "zx_compat_fixture_manifest_v1"
ROLES = ("driver", "runtime", "libraries")
TOP_LEVEL_KEYS = {"schema_version", "fixture_set", "files", "derived_expectations"}
FILE_KEYS = {"filename", "size_bytes", "sha256"}
DERIVED_COUNT_KEYS = {
    "source_row_count",
    "api_row_count",
    "unique_api_count",
    "forbidden_api_count",
}
DERIVED_HASH_KEYS = {"unique_api_sha256", "forbidden_api_sha256"}
DERIVED_KEYS = DERIVED_COUNT_KEYS | DERIVED_HASH_KEYS
SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--derived-summary")
    parser.add_argument("--output")
    return parser.parse_args()


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json_strict(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        payload = json.load(handle, object_pairs_hook=reject_duplicate_keys)
    if not isinstance(payload, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return payload


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_name_content(names: list[str] | set[str]) -> str:
    return "".join(f"{name}\n" for name in sorted(set(names)))


def canonical_name_sha256(names: list[str] | set[str]) -> str:
    return hashlib.sha256(canonical_name_content(names).encode("utf-8")).hexdigest()


def load_manifest(path: Path) -> dict[str, Any]:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"fixture manifest must be a regular file: {path}")
    payload = load_json_strict(path)
    if set(payload) != TOP_LEVEL_KEYS:
        raise ValueError(f"fixture manifest keys must be exactly {sorted(TOP_LEVEL_KEYS)}")
    if payload["schema_version"] != SCHEMA_VERSION:
        raise ValueError(f"unsupported fixture manifest schema: {payload['schema_version']}")
    if not isinstance(payload["fixture_set"], str) or not payload["fixture_set"]:
        raise ValueError("fixture_set must be a non-empty string")
    files = payload["files"]
    if not isinstance(files, dict) or set(files) != set(ROLES):
        raise ValueError(f"fixture roles must be exactly {list(ROLES)}")
    for role in ROLES:
        entry = files[role]
        if not isinstance(entry, dict) or set(entry) != FILE_KEYS:
            raise ValueError(f"fixture entry keys for {role} must be exactly {sorted(FILE_KEYS)}")
        filename = entry["filename"]
        if not isinstance(filename, str) or Path(filename).name != filename:
            raise ValueError(f"fixture filename for {role} must be a basename")
        if not isinstance(entry["size_bytes"], int) or entry["size_bytes"] < 1:
            raise ValueError(f"invalid fixture size for {role}")
        if not isinstance(entry["sha256"], str) or not SHA256_PATTERN.fullmatch(entry["sha256"]):
            raise ValueError(f"invalid fixture SHA256 for {role}")
    derived = payload["derived_expectations"]
    if not isinstance(derived, dict) or set(derived) != DERIVED_KEYS:
        raise ValueError(f"derived expectation keys must be exactly {sorted(DERIVED_KEYS)}")
    if any(
        not isinstance(derived[key], int) or derived[key] < 1
        for key in DERIVED_COUNT_KEYS
    ):
        raise ValueError("derived count expectations must be positive integers")
    if any(
        not isinstance(derived[key], str) or not SHA256_PATTERN.fullmatch(derived[key])
        for key in DERIVED_HASH_KEYS
    ):
        raise ValueError("derived hash expectations must be SHA256 values")
    return payload


def validate_derived_summary(
    summary_path: Path,
    expected: Mapping[str, Any],
    manifest_sha256: str,
    fixture_set: str,
    expected_files: Mapping[str, Mapping[str, Any]],
) -> dict[str, Any]:
    payload = load_json_strict(summary_path)
    summary = payload.get("summary", payload)
    if not isinstance(summary, dict):
        raise ValueError("derived compatibility summary must be an object")
    actual = {key: summary.get(key) for key in DERIVED_KEYS}
    if actual != dict(expected):
        raise ValueError(f"derived compatibility identities do not match manifest: {actual}")
    if summary.get("source_manifest_sha256") != manifest_sha256:
        raise ValueError("derived compatibility summary is bound to a different fixture manifest")
    if summary.get("fixture_set") != fixture_set:
        raise ValueError("derived compatibility summary has the wrong fixture set")
    if summary.get("source_files") != dict(expected_files):
        raise ValueError("derived compatibility summary has the wrong fixture identities")
    return {key: actual[key] for key in sorted(actual)}


def validate_fixture_set(
    source_dir: Path,
    manifest_path: Path,
    derived_summary_path: Path | None = None,
) -> dict[str, Any]:
    manifest = load_manifest(manifest_path)
    manifest_sha256 = sha256_file(manifest_path)
    actual_files: dict[str, dict[str, Any]] = {}
    for role in ROLES:
        expected = manifest["files"][role]
        path = source_dir / expected["filename"]
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"fixture must be a regular non-symlink file: {path}")
        size_bytes = path.stat().st_size
        digest = sha256_file(path)
        if size_bytes != expected["size_bytes"]:
            raise ValueError(f"fixture size mismatch for {role}: {size_bytes}")
        if digest != expected["sha256"]:
            raise ValueError(f"fixture SHA256 mismatch for {role}: {digest}")
        actual_files[role] = {
            "filename": expected["filename"],
            "size_bytes": size_bytes,
            "sha256": digest,
        }
    payload: dict[str, Any] = {
        "status": "passed",
        "schema_version": SCHEMA_VERSION,
        "fixture_set": manifest["fixture_set"],
        "source_manifest_sha256": manifest_sha256,
        "files": actual_files,
        "derived_expectations": manifest["derived_expectations"],
    }
    if derived_summary_path is not None:
        payload["derived_summary"] = validate_derived_summary(
            derived_summary_path,
            manifest["derived_expectations"],
            manifest_sha256,
            manifest["fixture_set"],
            manifest["files"],
        )
    return payload


def write_json_atomic(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def main() -> int:
    args = parse_args()
    output = Path(args.output) if args.output else None
    if output is not None and (output.exists() or output.is_symlink()):
        output.unlink()
    payload = validate_fixture_set(
        Path(args.source_dir),
        Path(args.manifest),
        Path(args.derived_summary) if args.derived_summary else None,
    )
    if output is not None:
        write_json_atomic(output, payload)
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
