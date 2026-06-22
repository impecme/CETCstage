#!/usr/bin/env python3

"""Validate the V5 dtype contract assigned to every registered operator."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from operator_set_support import format_operator_key
from validate_operator_sets import parse_registry_text


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--contracts", default="scripts/test/operator_type_contracts.json")
    parser.add_argument(
        "--output-dir",
        default="data/reports/zhongkexin/v5_2_type_contracts",
    )
    parser.add_argument(
        "--contract-markdown",
        default="docs/performance/v5_0/operator_type_contracts.md",
    )
    return parser.parse_args()


def load_contracts(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema_version") != 1:
        raise ValueError("unsupported type contract schema")
    return payload


def main() -> int:
    args = parse_args()
    registry_order, _targets = parse_registry_text(Path(args.registry).read_text(encoding="utf-8"))
    registry = {format_operator_key(key) for key in registry_order}
    payload = load_contracts(Path(args.contracts))
    real_types = set(payload["real_types"])
    complex_types = set(payload["complex_types"])
    forbidden = set(payload["forbidden_types"])
    allowed = real_types | complex_types
    if real_types != {"float32", "float16", "int32", "int16", "int8"}:
        raise ValueError("real type set must be FP32/FP16/INT32/INT16/INT8")
    if complex_types != {"complex64"}:
        raise ValueError("complex type set must contain only complex64")

    policies = payload.get("policies", {})
    assignments = payload.get("assignments", {})
    if not isinstance(policies, dict) or not isinstance(assignments, dict):
        raise ValueError("policies and assignments must be objects")

    owner: dict[str, str] = {}
    for policy_name, operators in assignments.items():
        if policy_name not in policies:
            raise ValueError(f"assignment references unknown policy: {policy_name}")
        if not isinstance(operators, list):
            raise ValueError(f"assignment {policy_name} must be a list")
        for operator in operators:
            if operator in owner:
                raise ValueError(f"operator {operator} assigned to multiple policies")
            owner[operator] = policy_name
    unused_policies = sorted(set(policies) - set(assignments))
    if unused_policies:
        raise ValueError(f"type policies have no assigned operators: {unused_policies}")

    missing = sorted(registry - set(owner))
    unknown = sorted(set(owner) - registry)
    if missing or unknown:
        raise ValueError(f"type contract coverage mismatch: missing={missing}, unknown={unknown}")

    rows = []
    for key in registry_order:
        operator = format_operator_key(key)
        policy_name = owner[operator]
        policy = policies[policy_name]
        input_types = set(policy.get("input_types", []))
        output_types = set(policy.get("output_types", []))
        current_types = set(policy.get("current_types", []))
        used_types = input_types | output_types | current_types
        if not output_types:
            raise ValueError(f"{policy_name} has no output types")
        if used_types - allowed:
            raise ValueError(f"{policy_name} uses unsupported types: {sorted(used_types - allowed)}")
        if used_types & forbidden:
            raise ValueError(f"{policy_name} uses forbidden types")
        if any(value.startswith("complex") and value != "complex64" for value in used_types):
            raise ValueError(f"{policy_name} violates complex64-only rule")
        integer_inputs = input_types & {"int32", "int16", "int8"}
        integer_policy = str(policy.get("integer_policy", ""))
        if integer_inputs and integer_policy in {"", "not_applicable"}:
            raise ValueError(f"{policy_name} lacks an integer policy")
        rows.append({"operator": operator, "policy": policy_name, **policy})

    summary = {
        "status": "passed",
        "operator_count": len(rows),
        "policy_count": len(policies),
        "real_types": sorted(real_types),
        "complex_types": sorted(complex_types),
        "forbidden_types": sorted(forbidden),
        "integer_enabled_operators": sum(
            bool(set(row["input_types"]) & {"int32", "int16", "int8"})
            or bool(set(row["output_types"]) & {"int32", "int16", "int8"})
            for row in rows
        ),
        "complex64_operators": sum(
            "complex64" in set(row["input_types"]) | set(row["output_types"])
            for row in rows
        ),
    }
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "latest_type_contracts.json").write_text(
        json.dumps({"summary": summary, "operators": rows}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    lines = [
        "# V5.2-04 算子类型契约",
        "",
        f"- status: `{summary['status']}`",
        f"- operators: `{summary['operator_count']}`",
        f"- policies: `{summary['policy_count']}`",
        f"- integer-enabled operators: `{summary['integer_enabled_operators']}`",
        f"- complex64 operators: `{summary['complex64_operators']}`",
        "",
        "| 算子 | 策略 | 输入类型 | 输出类型 | 当前类型 | 累加 | 整数规则 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for row in rows:
        lines.append(
            f"| `{row['operator']}` | `{row['policy']}` | "
            f"{','.join(row['input_types']) or '-'} | {','.join(row['output_types'])} | "
            f"{','.join(row['current_types'])} | {row['accumulator']} | {row['integer_policy']} |"
        )
    markdown = "\n".join(lines) + "\n"
    (output_dir / "latest_type_contracts.md").write_text(markdown, encoding="utf-8")
    contract_markdown = Path(args.contract_markdown)
    contract_markdown.parent.mkdir(parents=True, exist_ok=True)
    contract_markdown.write_text(markdown, encoding="utf-8")
    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
