#!/usr/bin/env python3

"""Audit project CUDA API calls against the generated ZQ500 compatibility matrix."""

from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from pathlib import Path


CALL_PATTERN = re.compile(
    r"\b((?:cuda|cu(?:blas|fft|dnn|solver|sparse|rand)?)[A-Z][A-Za-z0-9_]*)\s*\("
)
SOURCE_SUFFIXES = {".c", ".cc", ".cpp", ".cxx", ".cu", ".h", ".hpp"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", required=True)
    parser.add_argument("--forbidden", required=True)
    parser.add_argument("--exceptions", required=True)
    parser.add_argument("--roots", nargs="+", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    matrix = json.loads(Path(args.matrix).read_text(encoding="utf-8"))
    known = {
        name
        for row in matrix["rows"]
        for name in row.get("api_names", [])
    }
    forbidden = {
        line.strip()
        for line in Path(args.forbidden).read_text(encoding="utf-8").splitlines()
        if line.strip()
    }
    exception_payload = json.loads(Path(args.exceptions).read_text(encoding="utf-8"))
    exceptions = exception_payload.get("apis", {})
    if not exceptions or any(
        not entry.get("reason") or entry.get("verification") != "zx_compat_runtime_probes"
        for entry in exceptions.values()
    ):
        raise ValueError("every API exception must have a reason and runtime-probe verification")
    forbidden_pattern = re.compile(
        r"\b(?:" + "|".join(re.escape(name) for name in sorted(forbidden, key=len, reverse=True)) + r")\b"
    )
    calls: dict[str, list[str]] = defaultdict(list)
    forbidden_references: dict[str, list[str]] = defaultdict(list)
    for root_name in args.roots:
        root = Path(root_name)
        if not root.exists():
            raise FileNotFoundError(root)
        paths = [root] if root.is_file() else root.rglob("*")
        for path in paths:
            if not path.is_file() or path.suffix not in SOURCE_SUFFIXES:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for match in forbidden_pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                forbidden_references[match.group(0)].append(f"{path}:{line}")
            for match in CALL_PATTERN.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                calls[match.group(1)].append(f"{path}:{line}")

    used = set(calls)
    violations = sorted(forbidden_references)
    # Complex helpers and project identifiers use the cu* prefix but are not
    # CUDA runtime or scientific-library APIs represented by the source tables.
    unresolved = sorted(
        name for name in used - known - set(exceptions)
        if not name.startswith(("cuC", "cuSignal"))
    )
    payload = {
        "status": "failed" if violations or unresolved else "passed",
        "used_api_count": len(used),
        "matrix_matched_api_count": len(used & known),
        "forbidden_api_count": len(forbidden),
        "documented_exception_count": len(exceptions),
        "used_exception_count": len(used & set(exceptions)),
        "violation_count": len(violations),
        "unresolved_count": len(unresolved),
        "violations": {name: forbidden_references[name] for name in violations},
        "unresolved": {name: calls[name] for name in unresolved},
        "used_exceptions": {
            name: {**exceptions[name], "locations": calls[name]}
            for name in sorted(used & set(exceptions))
        },
        "used_apis": {name: calls[name] for name in sorted(calls)},
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in payload.items() if not isinstance(value, dict)}, sort_keys=True))
    return 0 if payload["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
