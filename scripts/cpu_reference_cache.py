#!/usr/bin/env python3
"""Validate a complete CPU reference cache produced by performance.sh."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


class CacheError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate(root: Path) -> dict:
    metadata_path = root / "cache_metadata.json"
    if not metadata_path.is_file():
        raise CacheError(f"missing cache metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    if metadata.get("schema_version") != 1:
        raise CacheError("unsupported CPU reference cache schema")
    if metadata.get("status") != "COMPLETE":
        raise CacheError(f"cache status is not COMPLETE: {metadata.get('status')!r}")
    if metadata.get("workload_count") != metadata.get("expected_workloads"):
        raise CacheError("cache workload count does not match expected_workloads")
    workloads = metadata.get("workloads")
    if not isinstance(workloads, list) or len(workloads) != metadata.get("expected_workloads"):
        raise CacheError("cache workload list is incomplete")

    seen: set[tuple[str, str]] = set()
    file_count = 0
    for workload in workloads:
        key = (str(workload.get("operator")), str(workload.get("scale_level")))
        if key in seen:
            raise CacheError(f"duplicate workload: {key[0]}/{key[1]}")
        seen.add(key)
        if workload.get("cpu_reference_complete") is not True:
            raise CacheError(f"CPU reference is incomplete: {key[0]}/{key[1]}")
        for group in ("manifest", "metrics"):
            item = workload.get(group, {})
            path = root / str(item.get("path", ""))
            if not path.is_file() or sha256(path) != item.get("sha256"):
                raise CacheError(f"{group} hash mismatch: {key[0]}/{key[1]}")
        files = workload.get("cpu_output_files")
        if not isinstance(files, list) or not files:
            raise CacheError(f"missing CPU output files: {key[0]}/{key[1]}")
        for item in files:
            path = root / str(item.get("path", ""))
            if not path.is_file() or path.stat().st_size != item.get("bytes"):
                raise CacheError(f"CPU output size mismatch: {path}")
            if sha256(path) != item.get("sha256"):
                raise CacheError(f"CPU output hash mismatch: {path}")
            if int(item.get("data_rows", 0)) <= 0:
                raise CacheError(f"CPU output has no data rows: {path}")
            file_count += 1
    return {"workloads": len(workloads), "cpu_output_files": file_count}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    args = parser.parse_args()
    try:
        result = validate(args.root.resolve())
    except (OSError, ValueError, json.JSONDecodeError, CacheError) as error:
        print(f"[cpu-reference-cache] FAIL: {error}")
        return 1
    print(
        f"[cpu-reference-cache] PASS workloads={result['workloads']} "
        f"cpu_output_files={result['cpu_output_files']} root={args.root.resolve()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
