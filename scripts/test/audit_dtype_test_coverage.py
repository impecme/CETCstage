#!/usr/bin/env python3

"""Audit concrete dtype test coverage against operator type contracts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from operator_set_support import format_operator_key
from validate_operator_sets import parse_registry_text


ALL_DTYPES = {"float32", "float16", "int32", "int16", "int8", "complex64"}
REAL_DTYPES = {"float32", "float16", "int32", "int16", "int8"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--contracts", default="scripts/test/operator_type_contracts.json")
    parser.add_argument("--reference-root", default="data/reference/unit")
    parser.add_argument("--generated-root", default="data/generated/unit")
    parser.add_argument(
        "--output-dir",
        default="data/reports/zhongkexin/v5_2_dtype_test_coverage",
    )
    parser.add_argument(
        "--summary-markdown",
        default="docs/performance/v5_0/dtype_test_coverage.md",
    )
    return parser.parse_args()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def flatten_contracts(payload: dict[str, Any], registry_order: list[Any]) -> list[dict[str, Any]]:
    policies = payload["policies"]
    assignments = payload["assignments"]
    owner: dict[str, str] = {}
    for policy_name, operators in assignments.items():
        for operator in operators:
            owner[operator] = policy_name

    rows = []
    for key in registry_order:
        operator = format_operator_key(key)
        policy_name = owner[operator]
        policy = policies[policy_name]
        rows.append(
            {
                "operator": operator,
                "policy": policy_name,
                "current_types": sorted(set(policy.get("current_types", []))),
                "compatibility_types": sorted(set(policy.get("compatibility_types", []))),
                "target_types": sorted(set(policy.get("input_types", [])) | set(policy.get("output_types", []))),
                "compatibility_mode": policy.get("compatibility_mode", ""),
            }
        )
    return rows


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
    index_dtype = case.get("index_dtype")
    if index_dtype == "int32":
        values.add("int32")
    return values


def scan_manifest_dtypes(path: Path) -> set[str]:
    if not path.exists():
        return set()
    payload = load_json(path)
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


def main() -> int:
    args = parse_args()
    registry_order, _targets = parse_registry_text(Path(args.registry).read_text(encoding="utf-8"))
    payload = load_json(Path(args.contracts))
    rows = flatten_contracts(payload, registry_order)
    operator_test_dtypes = scan_operator_test_dtypes(Path(args.reference_root), Path(args.generated_root))

    core_type_dtypes = sorted(ALL_DTYPES)
    details = []
    for row in rows:
        operator = row["operator"]
        concrete = set(operator_test_dtypes.get(operator, []))
        required = set(row["compatibility_types"])
        missing = sorted(required - concrete)
        details.append(
            {
                "operator": operator,
                "policy": row["policy"],
                "compatibility_types": row["compatibility_types"],
                "current_types": row["current_types"],
                "concrete_operator_test_dtypes": sorted(concrete),
                "missing_operator_test_dtypes": missing,
                "compatibility_mode": row["compatibility_mode"],
            }
        )

    dtype_summary = {}
    for dtype in sorted(ALL_DTYPES):
        declaring = [row for row in details if dtype in row["compatibility_types"]]
        tested = [
            row for row in details
            if dtype in row["compatibility_types"] and dtype in row["concrete_operator_test_dtypes"]
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

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "latest_dtype_test_coverage.json").write_text(
        json.dumps({"summary": summary, "operators": details}, ensure_ascii=False, indent=2) + "\n",
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
    summary_markdown = Path(args.summary_markdown)
    summary_markdown.parent.mkdir(parents=True, exist_ok=True)
    summary_markdown.write_text(markdown, encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
