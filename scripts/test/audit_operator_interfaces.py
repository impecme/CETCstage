#!/usr/bin/env python3

"""Audit public declarations, CPU/GPU definitions, tests, and Doxygen for all operators."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any

from operator_set_support import (
    OperatorKey,
    format_operator_key,
    load_operator_set_config,
    resolve_operator_sets,
)
from validate_operator_sets import parse_registry_text, validate_source_paths


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default="")
    parser.add_argument("--runner", default="scripts/test/run_all_tests.sh")
    parser.add_argument("--sets", default="scripts/test/operator_sets.json")
    parser.add_argument("--build-dir", default="build-zx")
    parser.add_argument("--platform", default="ZHONGKEXIN")
    parser.add_argument(
        "--output-dir",
        default="data/reports/zhongkexin/v5_2_interface_audit",
    )
    parser.add_argument(
        "--contract-markdown",
        default="docs/performance/v5_0/operator_contract_inventory.md",
    )
    return parser.parse_args()


def load_registry(args: argparse.Namespace) -> tuple[list[OperatorKey], dict[OperatorKey, str]]:
    if args.registry:
        return parse_registry_text(Path(args.registry).read_text(encoding="utf-8"))
    completed = subprocess.run(
        [
            args.runner,
            "--list",
            "--build-dir",
            args.build_dir,
            "--platform",
            args.platform,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or completed.stdout.strip())
    return parse_registry_text(completed.stdout)


def symbol_pattern(symbol: str, api_kind: str) -> re.Pattern[str]:
    if api_kind == "class":
        return re.compile(r"\bclass\s+" + re.escape(symbol) + r"\b")
    return re.compile(r"\b" + re.escape(symbol) + r"\s*\(")


def implementation_pattern(symbol: str, api_kind: str) -> re.Pattern[str]:
    if api_kind == "class":
        return re.compile(r"\b" + re.escape(symbol) + r"::" + re.escape(symbol) + r"\s*\(")
    return symbol_pattern(symbol, api_kind)


def doxygen_before(text: str, position: int) -> str:
    close = text.rfind("*/", 0, position)
    if close < 0:
        return ""
    open_pos = text.rfind("/**", 0, close)
    if open_pos < 0:
        return ""
    between = text[close + 2 : position]
    if ";" in between or "}" in between:
        return ""
    return text[open_pos : close + 2]


def matching_paren(text: str, open_position: int) -> int:
    depth = 0
    for position in range(open_position, len(text)):
        if text[position] == "(":
            depth += 1
        elif text[position] == ")":
            depth -= 1
            if depth == 0:
                return position
    return -1


def function_declaration_documented(text: str, match: re.Match[str]) -> bool:
    block = doxygen_before(text, match.start())
    if "@brief" not in block or "@return" not in block:
        return False
    open_position = text.find("(", match.start(), match.end() + 1)
    close_position = matching_paren(text, open_position) if open_position >= 0 else -1
    if close_position < 0:
        return False
    parameters = text[open_position + 1 : close_position].strip()
    return not parameters or parameters == "void" or "@param" in block


def audit_operator(
    repo_root: Path,
    key: OperatorKey,
    target: str,
    override: dict[str, Any],
    groups: dict[str, set[OperatorKey]],
) -> dict[str, Any]:
    module, operator = key
    symbol = str(override.get("api_symbol", operator))
    api_kind = str(override.get("api_kind", "function"))
    if api_kind not in {"function", "class"}:
        raise ValueError(f"unsupported api_kind for {format_operator_key(key)}: {api_kind}")

    header_path = repo_root / "include" / "cusignal" / module / f"{module}.hpp"
    cpu_path = repo_root / "src" / "cpu" / f"{module}.cpp"
    gpu_path = repo_root / "src" / "zhongkexin" / f"{module}.cu"
    test_cmake_path = repo_root / "tests" / "unit" / module / "CMakeLists.txt"
    header = header_path.read_text(encoding="utf-8")
    cpu = cpu_path.read_text(encoding="utf-8")
    gpu = gpu_path.read_text(encoding="utf-8")
    test_cmake = test_cmake_path.read_text(encoding="utf-8")

    declaration_matches = list(symbol_pattern(symbol, api_kind).finditer(header))
    cpu_matches = list(implementation_pattern(symbol, api_kind).finditer(cpu))
    gpu_matches = list(implementation_pattern(symbol, api_kind).finditer(gpu))
    expected_declarations = 2
    if api_kind == "class":
        documented = [
            block
            for match in declaration_matches
            if "@brief" in (block := doxygen_before(header, match.start()))
        ]
        constructor_pattern = re.compile(r"\b" + re.escape(symbol) + r"\s*\(")
        constructor_matches = list(constructor_pattern.finditer(header))
        documented_constructors = [
            block
            for match in constructor_matches
            if "@brief" in (block := doxygen_before(header, match.start()))
            and "@param" in block
        ]
        parameter_docs_pass = (
            len(constructor_matches) >= expected_declarations
            and len(documented_constructors) == len(constructor_matches)
        )
    else:
        documented = [
            match for match in declaration_matches if function_declaration_documented(header, match)
        ]
        constructor_matches = []
        documented_constructors = []
        parameter_docs_pass = len(documented) == len(declaration_matches)

    declaration_pass = len(declaration_matches) >= expected_declarations
    cpu_pass = bool(cpu_matches)
    gpu_pass = bool(gpu_matches)
    doxygen_pass = (
        len(declaration_matches) >= expected_declarations
        and len(documented) == len(declaration_matches)
        and parameter_docs_pass
    )
    test_pass = bool(target) and test_cmake_path.is_file()

    if key in groups["task27"]:
        group = "A-task27"
    elif key in groups["core53"]:
        group = "B-core53"
    else:
        group = "C-extended28"
    findings = []
    if not declaration_pass:
        findings.append("missing_cpu_or_gpu_public_declaration")
    if not cpu_pass:
        findings.append("missing_cpu_definition")
    if not gpu_pass:
        findings.append("missing_gpu_definition")
    if not test_pass:
        findings.append("missing_independent_test_target")
    if not doxygen_pass:
        findings.append("incomplete_doxygen")

    return {
        "module": module,
        "operator": operator,
        "key": format_operator_key(key),
        "group": group,
        "api_kind": api_kind,
        "api_symbol": symbol,
        "header": str(header_path.relative_to(repo_root)),
        "cpu_source": str(cpu_path.relative_to(repo_root)),
        "gpu_source": str(gpu_path.relative_to(repo_root)),
        "test_target": target,
        "test_cmake_mentions_target": target in test_cmake,
        "declaration_count": len(declaration_matches),
        "cpu_definition_count": len(cpu_matches),
        "gpu_definition_count": len(gpu_matches),
        "documented_declaration_count": len(documented),
        "constructor_declaration_count": len(constructor_matches),
        "documented_constructor_count": len(documented_constructors),
        "declaration_pass": declaration_pass,
        "cpu_pass": cpu_pass,
        "gpu_pass": gpu_pass,
        "test_pass": test_pass,
        "doxygen_pass": doxygen_pass,
        "pass": not findings,
        "findings": findings,
    }


def write_report(path: Path, rows: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    lines = [
        "# V5.2-02 算子接口审计",
        "",
        f"- status: `{summary['status']}`",
        f"- operators: `{summary['operator_count']}`",
        f"- passed: `{summary['passed_count']}`",
        f"- failed: `{summary['failed_count']}`",
        "",
        "| 集合 | 算子 | API | 声明 | CPU | GPU | 测试 | Doxygen | 结论 |",
        "| --- | --- | --- | ---: | ---: | ---: | --- | ---: | --- |",
    ]
    for row in rows:
        findings = ", ".join(row["findings"]) if row["findings"] else "passed"
        lines.append(
            f"| {row['group']} | `{row['key']}` | {row['api_kind']} `{row['api_symbol']}` | "
            f"{row['declaration_count']} | {row['cpu_definition_count']} | "
            f"{row['gpu_definition_count']} | `{row['test_target']}` | "
            f"{row['documented_declaration_count']} | {findings} |"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_contract_inventory(path: Path, rows: list[dict[str, Any]]) -> None:
    lines = [
        "# V5 81 算子契约清单",
        "",
        "本清单由 `audit_operator_interfaces.py` 根据测试注册表、命名集合和实际源码生成。"
        "V5.2-02 结论仅覆盖声明、CPU/GPU 定义、独立测试 target 和 Doxygen；类型与平台状态由后续工作包更新。",
        "",
        "| # | 集合 | 算子 | 声明 | CPU | ZQ500 GPU | 独立测试 target | 接口审计 | 类型 | 平台 | 性能 |",
        "| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, row in enumerate(rows, start=1):
        interface = "通过" if row["pass"] else "整改：" + ",".join(row["findings"])
        performance = (
            "已优化（V5.4 提前）"
            if row["key"] == "filtering/wiener"
            else "待所属阶段"
        )
        lines.append(
            f"| {index} | {row['group']} | `{row['key']}` | `{row['header']}` | "
            f"`{row['cpu_source']}` | `{row['gpu_source']}` | `{row['test_target']}` | "
            f"{interface} | 待 V5.2-04 | 待 V5.2-05/06 | {performance} |"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    registry_order, targets = load_registry(args)
    validate_source_paths(repo_root, registry_order)
    payload = load_operator_set_config(Path(args.sets))
    groups = resolve_operator_sets(payload, registry_order)
    overrides = payload.get("operator_overrides", {})
    if not isinstance(overrides, dict):
        raise ValueError("operator_overrides must be an object")

    rows = [
        audit_operator(
            repo_root,
            key,
            targets[key],
            overrides.get(format_operator_key(key), {}),
            groups,
        )
        for key in registry_order
    ]
    failed = [row for row in rows if not row["pass"]]
    summary = {
        "status": "passed" if not failed else "failed",
        "operator_count": len(rows),
        "passed_count": len(rows) - len(failed),
        "failed_count": len(failed),
        "failure_counts": {
            finding: sum(finding in row["findings"] for row in rows)
            for finding in sorted({item for row in rows for item in row["findings"]})
        },
    }
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "latest_interface_audit.json").write_text(
        json.dumps({"summary": summary, "operators": rows}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    write_report(output_dir / "latest_interface_audit.md", rows, summary)
    write_contract_inventory(Path(args.contract_markdown), rows)
    print(json.dumps(summary, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
