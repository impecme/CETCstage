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


def format_type_list(values: list[str] | set[str]) -> str:
    return ",".join(sorted(values)) if values else "-"


def flatten_alignment_groups(groups: dict[str, Any], label: str) -> dict[str, str]:
    owners: dict[str, str] = {}
    for group_name, operators in groups.items():
        if not isinstance(operators, list):
            raise ValueError(f"{label}.{group_name} must be a list")
        for operator in operators:
            if operator in owners:
                raise ValueError(
                    f"{operator} appears in multiple {label} groups: {owners[operator]}, {group_name}"
                )
            owners[operator] = group_name
    return owners


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
        compatibility_types = set(policy.get("compatibility_types", []))
        used_types = input_types | output_types | current_types | compatibility_types
        if not output_types:
            raise ValueError(f"{policy_name} has no output types")
        if not compatibility_types:
            raise ValueError(f"{policy_name} has no compatibility_types")
        if not str(policy.get("compatibility_mode", "")).strip():
            raise ValueError(f"{policy_name} has no compatibility_mode")
        if used_types - allowed:
            raise ValueError(f"{policy_name} uses unsupported types: {sorted(used_types - allowed)}")
        if used_types & forbidden:
            raise ValueError(f"{policy_name} uses forbidden types")
        if any(value.startswith("complex") and value != "complex64" for value in used_types):
            raise ValueError(f"{policy_name} violates complex64-only rule")
        target_types = input_types | output_types
        compatibility_gap = target_types - compatibility_types
        if compatibility_gap:
            raise ValueError(
                f"{policy_name} compatibility_types misses target types: {sorted(compatibility_gap)}"
            )
        integer_inputs = input_types & {"int32", "int16", "int8"}
        integer_policy = str(policy.get("integer_policy", ""))
        if integer_inputs and integer_policy in {"", "not_applicable"}:
            raise ValueError(f"{policy_name} lacks an integer policy")
        converted_compatibility_types = sorted(target_types - current_types)
        rows.append(
            {
                "operator": operator,
                "policy": policy_name,
                "target_types": sorted(target_types),
                "converted_compatibility_types": converted_compatibility_types,
                **policy,
            }
        )
    row_by_operator = {row["operator"]: row for row in rows}

    alignment = payload.get("upstream_complex64_alignment", {})
    if not isinstance(alignment, dict):
        raise ValueError("upstream_complex64_alignment must be an object")
    supported_groups = alignment.get("supported", {})
    planned_gap_groups = alignment.get("planned_public_gaps", {})
    if not isinstance(supported_groups, dict) or not isinstance(planned_gap_groups, dict):
        raise ValueError("upstream_complex64_alignment groups must be objects")
    supported_complex64 = flatten_alignment_groups(supported_groups, "supported")
    planned_complex64_gaps = flatten_alignment_groups(planned_gap_groups, "planned_public_gaps")
    alignment_unknown = sorted((set(supported_complex64) | set(planned_complex64_gaps)) - registry)
    if alignment_unknown:
        raise ValueError(f"upstream complex64 alignment references unknown operators: {alignment_unknown}")
    overlap = sorted(set(supported_complex64) & set(planned_complex64_gaps))
    if overlap:
        raise ValueError(f"operators cannot be both supported and planned complex64 gaps: {overlap}")
    for operator in sorted(supported_complex64):
        row = row_by_operator[operator]
        supported_types = set(row["target_types"]) | set(row["current_types"]) | set(row["compatibility_types"])
        if "complex64" not in supported_types:
            raise ValueError(f"{operator} is listed as upstream complex64 supported but lacks complex64 contract")

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
        "compatibility_gap_count": sum(
            bool((set(row["input_types"]) | set(row["output_types"])) - set(row["compatibility_types"]))
            for row in rows
        ),
        "native_direct_operator_count": sum(not row["converted_compatibility_types"] for row in rows),
        "converted_compatibility_operator_count": sum(
            bool(row["converted_compatibility_types"]) for row in rows
        ),
        "converted_type_counts": {
            dtype: sum(dtype in set(row["converted_compatibility_types"]) for row in rows)
            for dtype in sorted(allowed)
        },
        "upstream_complex64_supported_count": len(supported_complex64),
        "upstream_complex64_planned_gap_count": len(planned_complex64_gaps),
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
        f"- compatibility gaps: `{summary['compatibility_gap_count']}`",
        f"- real types: `{','.join(summary['real_types'])}`",
        f"- complex types: `{','.join(summary['complex_types'])}`",
        f"- forbidden types: `{','.join(summary['forbidden_types'])}`",
        f"- native direct operators: `{summary['native_direct_operator_count']}`",
        f"- compatibility-converted operators: `{summary['converted_compatibility_operator_count']}`",
        f"- upstream complex64 supported operators: `{summary['upstream_complex64_supported_count']}`",
        f"- upstream complex64 planned public gaps: `{summary['upstream_complex64_planned_gap_count']}`",
        "",
        "结论：81 个算子的目标输入/输出类型均有兼容路径；复数类型仅支持 `complex64`。"
        " `current_types` 表示当前原生直达类型，`compatibility_types` 表示允许通过 FP32/complex64"
        " 中间计算、整数扩展累加或受控转换覆盖的兼容类型。",
        "",
        "| 类型 | 需兼容转换的算子数 |",
        "| --- | ---: |",
    ]
    for dtype, count in summary["converted_type_counts"].items():
        lines.append(f"| `{dtype}` | `{count}` |")
    lines.extend(
        [
            "",
            "## 原 cuSignal complex64 对齐",
            "",
            "下表列出原 cuSignal/SciPy 语义中涉及复数输出、复数输入或复数 dtype-preserving 的"
            "算子在本项目中的 complex64 对齐状态。已支持项进入公共算子契约；待公共化项是"
            "当前仍只有实数公共接口或任务级 helper 的后续兼容计划。",
            "",
            "| 状态 | 类别 | 算子 |",
            "| --- | --- | --- |",
        ]
    )
    for operator, group_name in sorted(supported_complex64.items()):
        lines.append(f"| supported | `{group_name}` | `{operator}` |")
    for operator, group_name in sorted(planned_complex64_gaps.items()):
        lines.append(f"| planned_public_gap | `{group_name}` | `{operator}` |")
    lines.extend(
        [
            "",
            "| 算子 | 策略 | 目标类型 | 当前原生类型 | 兼容类型 | 需转换类型 | 兼容方式 |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for row in rows:
        lines.append(
            f"| `{row['operator']}` | `{row['policy']}` | "
            f"{format_type_list(row['target_types'])} | "
            f"{format_type_list(row['current_types'])} | "
            f"{format_type_list(row['compatibility_types'])} | "
            f"{format_type_list(row['converted_compatibility_types'])} | "
            f"{row['compatibility_mode']} |"
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
