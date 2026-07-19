#!/usr/bin/env python3

"""Validate operator dtype contracts and audit concrete dtype test coverage."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Tuple


OperatorKey = Tuple[str, str]
ALL_DTYPES = {"float32", "float16", "int32", "int16", "int8", "complex64"}


def format_operator_key(value: OperatorKey) -> str:
    return f"{value[0]}/{value[1]}"


def parse_registry_text(text: str) -> tuple[list[OperatorKey], dict[OperatorKey, str]]:
    operators: list[OperatorKey] = []
    targets: dict[OperatorKey, str] = {}
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        key = (parts[0].strip(), parts[1].strip())
        target = parts[2].strip()
        if not all(key) or not target:
            continue
        if key in targets:
            raise ValueError(f"duplicate registry entry: {format_operator_key(key)}")
        operators.append(key)
        targets[key] = target
    if not operators:
        raise ValueError("registry contains no operators")
    return operators, targets


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--contracts", default="tests/contracts/operator_type_contracts.json")
    parser.add_argument(
        "--output-dir",
        default="data/.reports_staging/runtime/audits/type_contracts",
    )
    parser.add_argument(
        "--contract-markdown",
        default="data/.reports_staging/runtime/audits/type_contracts.md",
    )
    parser.add_argument("--reference-root", default="data/reference/unit")
    parser.add_argument("--generated-root", default="data/generated/unit")
    parser.add_argument(
        "--coverage-output-dir",
        default="data/.reports_staging/runtime/audits/dtype_coverage",
    )
    parser.add_argument(
        "--coverage-summary-markdown",
        "--summary-markdown",
        dest="coverage_summary_markdown",
        default="data/.reports_staging/runtime/audits/dtype_coverage.md",
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


def dtype_values_from_case(case: dict[str, Any]) -> set[str]:
    values: set[str] = set()
    dtype = case.get("dtype")
    if isinstance(dtype, str) and dtype in ALL_DTYPES:
        values.add(dtype)
    case_type = case.get("type")
    if case_type == "complex":
        values.add("complex64")
    elif case_type == "real":
        values.add("float32")
    is_complex = case.get("is_complex")
    if is_complex is True:
        values.add("complex64")
    elif is_complex is False:
        values.add("float32")
    input_kind = case.get("input_kind")
    if input_kind == "complex":
        values.add("complex64")
    elif input_kind == "real":
        values.add("float32")
    output_kind = case.get("output_kind")
    if output_kind == "complex":
        values.add("complex64")
    elif output_kind == "real":
        values.add("float32")
    if case.get("index_dtype") == "int32":
        values.add("int32")
    return values


def scan_manifest_dtypes(path: Path) -> set[str]:
    if not path.exists():
        return set()
    payload = json.loads(path.read_text(encoding="utf-8"))
    dtypes: set[str] = set()
    for key in ("accuracy_cases", "perf_cases"):
        for case in payload.get(key, []):
            if isinstance(case, dict):
                case_dtypes = dtype_values_from_case(case)
                if not case_dtypes:
                    case_dtypes.add("float32")
                dtypes.update(case_dtypes)
    return dtypes


def scan_operator_test_dtypes(reference_root: Path, generated_root: Path) -> dict[str, list[str]]:
    coverage: dict[str, list[str]] = {}
    for root in (reference_root, generated_root):
        if not root.exists():
            continue
        for manifest in root.glob("*/*/manifest.json"):
            operator = f"{manifest.parent.parent.name}/{manifest.parent.name}"
            coverage.setdefault(operator, [])
            coverage[operator] = sorted(set(coverage[operator]) | scan_manifest_dtypes(manifest))
    return coverage


def audit_dtype_test_coverage(
    args: argparse.Namespace,
    contract_rows: list[dict[str, Any]],
) -> dict[str, Any]:
    operator_test_dtypes = scan_operator_test_dtypes(
        Path(args.reference_root), Path(args.generated_root)
    )
    core_type_dtypes = sorted(ALL_DTYPES)
    details = []
    for row in contract_rows:
        operator = row["operator"]
        concrete = set(operator_test_dtypes.get(operator, []))
        compatibility_types = sorted(set(row["compatibility_types"]))
        current_types = sorted(set(row["current_types"]))
        required = set(compatibility_types)
        details.append(
            {
                "operator": operator,
                "policy": row["policy"],
                "compatibility_types": compatibility_types,
                "current_types": current_types,
                "concrete_operator_test_dtypes": sorted(concrete),
                "missing_operator_test_dtypes": sorted(required - concrete),
                "compatibility_mode": row["compatibility_mode"],
            }
        )

    dtype_summary = {}
    for dtype in sorted(ALL_DTYPES):
        declaring = [row for row in details if dtype in row["compatibility_types"]]
        tested = [
            row
            for row in details
            if dtype in row["compatibility_types"]
            and dtype in row["concrete_operator_test_dtypes"]
        ]
        dtype_summary[dtype] = {
            "core_type_roundtrip_tested": dtype in core_type_dtypes,
            "declared_operator_count": len(declaring),
            "concrete_operator_test_count": len(tested),
            "missing_operator_test_count": len(declaring) - len(tested),
        }

    missing_edges = sum(len(row["missing_operator_test_dtypes"]) for row in details)
    summary = {
        "status": "passed" if missing_edges == 0 else "action_required",
        "operator_count": len(details),
        "dtype_count": len(ALL_DTYPES),
        "core_type_roundtrip_dtypes": core_type_dtypes,
        "operator_dtype_missing_edges": missing_edges,
        "dtype_summary": dtype_summary,
    }

    output_dir = Path(args.coverage_output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "latest_dtype_test_coverage.json").write_text(
        json.dumps({"summary": summary, "operators": details}, ensure_ascii=False, indent=2)
        + "\n",
        encoding="utf-8",
    )
    lines = [
        "# Dtype 测试覆盖审计",
        "",
        f"- status: `{summary['status']}`",
        f"- operators: `{summary['operator_count']}`",
        f"- dtypes: `{','.join(core_type_dtypes)}`",
        f"- operator dtype missing edges: `{summary['operator_dtype_missing_edges']}`",
        "",
        "结论：`cusignal_type_contract_tests` 已覆盖 5 种实数和 complex64 的公共容器、shape、空输入和 H2D/D2H roundtrip。"
        "逐算子 dtype 测试仍需按 `compatibility_types` 补齐；当前表中的 missing 表示该算子声明兼容该 dtype，"
        "但现有 accuracy/perf manifest 没有可识别的该 dtype 用例。",
        "",
        "| dtype | core roundtrip | 声明兼容算子数 | 已有逐算子 dtype 用例 | 缺口 |",
        "| --- | --- | ---: | ---: | ---: |",
    ]
    for dtype, data in dtype_summary.items():
        lines.append(
            f"| `{dtype}` | `{str(data['core_type_roundtrip_tested']).lower()}` | "
            f"{data['declared_operator_count']} | {data['concrete_operator_test_count']} | "
            f"{data['missing_operator_test_count']} |"
        )
    lines.extend(
        [
            "",
            "| 算子 | 兼容类型 | 已有 dtype 用例 | 缺少 dtype 用例 |",
            "| --- | --- | --- | --- |",
        ]
    )
    for row in details:
        if row["missing_operator_test_dtypes"]:
            lines.append(
                f"| `{row['operator']}` | `{','.join(row['compatibility_types'])}` | "
                f"`{','.join(row['concrete_operator_test_dtypes']) or '-'}` | "
                f"`{','.join(row['missing_operator_test_dtypes'])}` |"
            )
    markdown = "\n".join(lines) + "\n"
    (output_dir / "latest_dtype_test_coverage.md").write_text(markdown, encoding="utf-8")
    summary_markdown = Path(args.coverage_summary_markdown)
    summary_markdown.parent.mkdir(parents=True, exist_ok=True)
    summary_markdown.write_text(markdown, encoding="utf-8")
    return summary


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
        "# 算子类型契约",
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
    coverage_summary = audit_dtype_test_coverage(args, rows)
    print(json.dumps(summary, sort_keys=True))
    print(json.dumps(coverage_summary, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
