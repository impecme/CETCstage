#!/usr/bin/env python3

"""Validate V5 operator sets against the unit-test registry."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from operator_set_support import (
    OperatorKey,
    format_operator_key,
    load_operator_set_config,
    resolve_operator_sets,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", help="TSV produced by run_all_tests.sh --list")
    parser.add_argument("--runner", default="scripts/test/run_all_tests.sh")
    parser.add_argument("--sets", default="scripts/test/operator_sets.json")
    parser.add_argument("--build-dir", default="build-zx")
    parser.add_argument("--platform", default="ZHONGKEXIN")
    parser.add_argument("--summary-json", default="")
    parser.add_argument("--list-set", default="")
    parser.add_argument("--contract-markdown", default="")
    return parser.parse_args()


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


def write_contract_markdown(
    path: Path,
    registry_order: list[OperatorKey],
    targets: dict[OperatorKey, str],
    resolved: dict[str, set[OperatorKey]],
) -> None:
    lines = [
        "# V5 81 算子契约清单",
        "",
        "本清单由 `validate_operator_sets.py` 根据测试注册表和 "
        "`operator_sets.json` 生成。V5.2-01 只冻结范围和真实路径；接口、类型和平台状态由后续工作包审计。",
        "",
        "| # | 集合 | 算子 | 声明 | CPU | ZQ500 GPU | 独立测试 target | 接口 | 类型 | 平台 | 性能 |",
        "| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, key in enumerate(registry_order, start=1):
        module, operator = key
        if key in resolved["task27"]:
            group = "A-task27"
        elif key in resolved["core53"]:
            group = "B-core53"
        else:
            group = "C-extended28"
        performance = "已优化（V5.4 提前）" if key == ("filtering", "wiener") else "待所属阶段"
        lines.append(
            f"| {index} | {group} | `{module}/{operator}` | "
            f"`include/cusignal/{module}/{module}.hpp` | `src/cpu/{module}.cpp` | "
            f"`src/zhongkexin/{module}.cu` | `{targets[key]}` | "
            f"待 V5.2-02 | 待 V5.2-04 | 待 V5.2-05/06 | {performance} |"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def validate_source_paths(repo_root: Path, registry_order: list[OperatorKey]) -> None:
    missing: list[str] = []
    for module in sorted({module for module, _operator in registry_order}):
        expected = (
            repo_root / "include" / "cusignal" / module / f"{module}.hpp",
            repo_root / "src" / "cpu" / f"{module}.cpp",
            repo_root / "src" / "zhongkexin" / f"{module}.cu",
            repo_root / "tests" / "unit" / module,
        )
        missing.extend(str(path.relative_to(repo_root)) for path in expected if not path.exists())
    if missing:
        raise ValueError("registered module paths are missing: " + ", ".join(missing))


def main() -> int:
    args = parse_args()
    registry_order, targets = load_registry(args)
    repo_root = Path(__file__).resolve().parents[2]
    validate_source_paths(repo_root, registry_order)
    payload = load_operator_set_config(Path(args.sets))
    resolved = resolve_operator_sets(payload, registry_order)

    required = {"task27": 27, "core53": 53, "extended28": 28, "all81": 81}
    for name, expected in required.items():
        if name not in resolved or len(resolved[name]) != expected:
            raise ValueError(f"required set {name} must contain {expected} operators")
    if not resolved["task27"] <= resolved["core53"]:
        raise ValueError("task27 must be a subset of core53")
    if resolved["core53"] & resolved["extended28"]:
        raise ValueError("core53 and extended28 must be disjoint")
    if resolved["core53"] | resolved["extended28"] != resolved["all81"]:
        raise ValueError("core53 union extended28 must equal all81")

    summary = {
        "status": "passed",
        "registry_count": len(registry_order),
        "source_path_check": "passed",
        "sets": {name: len(values) for name, values in sorted(resolved.items())},
    }
    if args.summary_json:
        output = Path(args.summary_json)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    if args.contract_markdown:
        write_contract_markdown(
            Path(args.contract_markdown),
            registry_order,
            targets,
            resolved,
        )

    if args.list_set:
        if args.list_set not in resolved:
            raise ValueError(f"unknown operator set: {args.list_set}")
        selected = resolved[args.list_set]
        for key in registry_order:
            if key in selected:
                print(f"{key[0]}\t{key[1]}\t{targets[key]}")
    else:
        print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
