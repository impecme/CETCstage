#!/usr/bin/env python3

"""Load and validate named cuSignal operator sets."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Iterable, Tuple


OperatorKey = Tuple[str, str]


def parse_operator_key(value: str) -> OperatorKey:
    parts = value.split("/")
    if len(parts) != 2 or not all(parts):
        raise ValueError(f"invalid operator key {value!r}; expected module/operator")
    return parts[0], parts[1]


def format_operator_key(value: OperatorKey) -> str:
    return f"{value[0]}/{value[1]}"


def load_operator_set_config(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError(f"unsupported operator set schema in {path}")
    sets = payload.get("sets")
    if not isinstance(sets, dict) or not sets:
        raise ValueError(f"operator set file has no sets: {path}")
    return payload


def resolve_operator_sets(
    payload: dict[str, Any],
    known_operators: Iterable[OperatorKey] | None = None,
) -> dict[str, set[OperatorKey]]:
    definitions = payload["sets"]
    resolved: dict[str, set[OperatorKey]] = {}
    resolving: set[str] = set()

    def resolve(name: str) -> set[OperatorKey]:
        if name in resolved:
            return resolved[name]
        if name in resolving:
            raise ValueError(f"operator set dependency cycle at {name}")
        definition = definitions.get(name)
        if not isinstance(definition, dict):
            raise ValueError(f"unknown operator set: {name}")

        resolving.add(name)
        values: set[OperatorKey] = set()
        explicit = definition.get("operators", [])
        if not isinstance(explicit, list):
            raise ValueError(f"{name}.operators must be a list")
        parsed = [parse_operator_key(str(value)) for value in explicit]
        if len(parsed) != len(set(parsed)):
            raise ValueError(f"operator set {name} contains duplicate entries")
        values.update(parsed)

        for included in definition.get("include_sets", []):
            values.update(resolve(str(included)))
        for excluded in definition.get("exclude_sets", []):
            values.difference_update(resolve(str(excluded)))

        expected_count = definition.get("expected_count")
        if not isinstance(expected_count, int) or expected_count < 0:
            raise ValueError(f"operator set {name} has invalid expected_count")
        if len(values) != expected_count:
            raise ValueError(
                f"operator set {name} expected {expected_count} entries, got {len(values)}"
            )
        resolving.remove(name)
        resolved[name] = values
        return values

    for set_name in definitions:
        resolve(set_name)

    if known_operators is not None:
        known = set(known_operators)
        for set_name, values in resolved.items():
            unknown = sorted(values - known)
            if unknown:
                labels = ", ".join(format_operator_key(value) for value in unknown)
                raise ValueError(f"operator set {set_name} contains unknown entries: {labels}")
        all81 = resolved.get("all81")
        if all81 is None:
            raise ValueError("required operator set all81 is missing")
        missing = sorted(known - all81)
        extra = sorted(all81 - known)
        if missing or extra:
            details = []
            if missing:
                details.append(
                    "missing=" + ",".join(format_operator_key(value) for value in missing)
                )
            if extra:
                details.append(
                    "extra=" + ",".join(format_operator_key(value) for value in extra)
                )
            raise ValueError("all81 does not match the test registry: " + " ".join(details))

    return resolved
