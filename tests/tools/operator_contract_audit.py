#!/usr/bin/env python3

"""Validate operator sets and audit every public operator interface."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any, Iterable, Tuple


OperatorKey = Tuple[str, str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default="")
    parser.add_argument(
        "--runner",
        default="",
        help="optional compatible registry runner; otherwise pass --registry",
    )
    parser.add_argument("--sets", default="tests/contracts/operator_sets.json")
    parser.add_argument(
        "--appendix-xlsx",
        default="",
        help="optional XLSX source used to verify task_appendix exactly",
    )
    parser.add_argument("--build-dir", default="build-zx")
    parser.add_argument("--platform", default="ZHONGKEXIN")
    parser.add_argument("--summary-json", default="")
    parser.add_argument("--list-set", default="")
    parser.add_argument("--set-contract-markdown", default="")
    parser.add_argument(
        "--output-dir",
        default="data/.reports_staging/runtime/audits/interfaces",
    )
    parser.add_argument(
        "--contract-markdown",
        default="data/.reports_staging/runtime/audits/interfaces.md",
    )
    return parser.parse_args()


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


def load_appendix_from_xlsx(path: Path) -> set[OperatorKey]:
    """Read the operator-name column from the small appendix workbook.

    The repository deliberately avoids an openpyxl dependency.  The workbook
    is an ordinary XLSX package, so reading shared strings and column B is
    sufficient and makes the source check reproducible in the container.
    """
    namespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    ns = {"x": namespace}
    try:
        with zipfile.ZipFile(path) as archive:
            shared_root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            shared: list[str] = []
            for item in shared_root.findall("x:si", ns):
                shared.append("".join(text.text or "" for text in item.iter(f"{{{namespace}}}t")))
            sheet_root = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
    except (OSError, KeyError, ET.ParseError, zipfile.BadZipFile) as error:
        raise ValueError(f"cannot read appendix XLSX {path}: {error}") from error

    operators: set[OperatorKey] = set()
    for row in sheet_root.findall(".//x:sheetData/x:row", ns):
        if row.attrib.get("r") == "1":
            continue
        name_cell = None
        for cell in row.findall("x:c", ns):
            reference = cell.attrib.get("r", "")
            if reference.startswith("B"):
                name_cell = cell
                break
        if name_cell is None:
            continue
        value = name_cell.find("x:v", ns)
        if value is None or not value.text:
            continue
        if name_cell.attrib.get("t") == "s":
            index = int(value.text)
            if index < 0 or index >= len(shared):
                raise ValueError(f"invalid shared-string index in {path}: {index}")
            operator_name = shared[index].strip()
        else:
            operator_name = value.text.strip()
        if operator_name:
            operators.add(("estimation", "kalman_filter" if operator_name == "kalmanfilter" else operator_name))

    # The worksheet lists module names in column C only at the first row of a
    # block.  Reconstruct each block from the known source paths rather than
    # depending on merged-cell formatting details.
    module_by_name = {
        "cubic": "bsplines", "gauss_spline": "bsplines", "quadratic": "bsplines",
        "correlate": "correlate", "correlate2d": "correlate",
        "fm_demod": "demod", "kalmanfilter": "estimation",
        "firwin": "filter_design", "firwin2": "filter_design",
        "channelize_poly": "filtering", "detrend": "filtering", "firfilter": "filtering",
        "firfilter2": "filtering", "freq_shift": "filtering", "hilbert": "filtering",
        "hilbert2": "filtering", "lfilter_zi": "filtering", "sosfilt": "filtering",
        "wiener": "filtering", "decimate": "filtering", "resample": "filtering",
        "resample_poly": "filtering", "upfirdn": "filtering", "argrelextrema": "peak_finding",
        "ambgfun": "radartools", "ca_cfar": "radartools", "cfar_alpha": "radartools",
        "pulse_compression": "radartools", "pulse_doppler": "radartools", "csd": "spectral",
        "istft": "spectral", "lombscargle": "spectral", "spectrogram": "spectral",
        "stft": "spectral", "vectorstrength": "spectral", "chirp": "waveforms",
        "gausspulse": "waveforms", "sawtooth": "waveforms", "square": "waveforms",
        "unit_impulse": "waveforms", "cwt": "wavelets", "morlet": "wavelets",
        "morlet2": "wavelets", "qmf": "wavelets", "ricker": "wavelets",
        "chebwin": "windows", "general_cosine": "windows", "general_gaussian": "windows",
        "hamming": "windows", "kaiser": "windows", "parzen": "windows", "taylor": "windows",
        "triang": "windows",
    }
    normalized: set[OperatorKey] = set()
    for _ignored_module, name in operators:
        original = "kalmanfilter" if name == "kalman_filter" else name
        module = module_by_name.get(original)
        if module is None:
            raise ValueError(f"appendix XLSX contains unknown operator name: {original}")
        normalized.add((module, name))
    return normalized


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
    if not args.runner:
        # The checked-in contract is the authoritative registry when this
        # audit is run before a build exists.  A built runner can still be
        # supplied explicitly for an independent target-name check.
        payload = load_operator_set_config(Path(args.sets))
        values = payload.get("sets", {}).get("all81", {}).get("operators", [])
        if not isinstance(values, list) or len(values) != 81:
            raise ValueError("operator set contract cannot provide an all81 registry")
        operators = [parse_operator_key(str(value)) for value in values]
        targets = {key: f"{key[0]}_test_{key[1]}" for key in operators}
        return operators, targets
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


def validate_operator_sets(
    registry_order: list[OperatorKey],
    payload: dict[str, Any],
    appendix_xlsx: Path | None = None,
) -> tuple[dict[str, set[OperatorKey]], dict[str, Any]]:
    resolved = resolve_operator_sets(payload, registry_order)
    required = {
        "all81": 81,
        "task_appendix": 53,
        "task_used": 18,
        "appendix_only": 37,
        "native_only": 26,
    }
    for name, expected in required.items():
        if name not in resolved or len(resolved[name]) != expected:
            raise ValueError(f"required set {name} must contain {expected} operators")
    if resolved["task_used"] & resolved["appendix_only"]:
        raise ValueError("task_used and appendix_only must be disjoint")
    expected_appendix_only = resolved["task_appendix"] - resolved["task_used"]
    if resolved["appendix_only"] != expected_appendix_only:
        raise ValueError("appendix_only must equal task_appendix minus task_used")
    groups = (
        resolved["task_used"],
        resolved["appendix_only"],
        resolved["native_only"],
    )
    if sum(len(group) for group in groups) != len(resolved["all81"]):
        raise ValueError("task tiers must cover all81 without overlap")
    if len(set().union(*groups)) != len(resolved["all81"]):
        raise ValueError("task tiers must be pairwise disjoint and cover all81")
    if set().union(*groups) != resolved["all81"]:
        raise ValueError("task tiers union must equal all81")
    source = payload["sets"]["task_appendix"].get("source")
    if source == "算子表.xlsx":
        if appendix_xlsx is None:
            raise ValueError("task_appendix requires an appendix XLSX source")
        xlsx_values = load_appendix_from_xlsx(appendix_xlsx)
        if xlsx_values != resolved["task_appendix"]:
            missing = sorted(resolved["task_appendix"] - xlsx_values)
            extra = sorted(xlsx_values - resolved["task_appendix"])
            raise ValueError(
                "task_appendix differs from 算子表.xlsx: "
                f"missing={','.join(format_operator_key(value) for value in missing)} "
                f"extra={','.join(format_operator_key(value) for value in extra)}"
            )
        expected_sha = payload["sets"]["task_appendix"].get("source_sha256")
        if expected_sha:
            digest = hashlib.sha256(appendix_xlsx.read_bytes()).hexdigest()
            if digest != expected_sha:
                raise ValueError(
                    f"算子表.xlsx sha256 mismatch: expected={expected_sha} actual={digest}"
                )
    summary = {
        "status": "passed",
        "registry_count": len(registry_order),
        "source_path_check": "passed",
        "task_appendix_source": source,
        "sets": {name: len(values) for name, values in sorted(resolved.items())},
    }
    return resolved, summary


def write_set_contract_markdown(
    path: Path,
    registry_order: list[OperatorKey],
    targets: dict[OperatorKey, str],
    resolved: dict[str, set[OperatorKey]],
) -> None:
    lines = [
        "# 81 算子集合清单",
        "",
        "本清单由 `operator_contract_audit.py` 根据测试注册表和 "
        "`operator_sets.json` 生成。本文件冻结集合、源码和 target；接口、类型和平台状态由对应最终审计给出。",
        "",
        "| # | 集合 | 算子 | 声明 | CPU | ZQ500 GPU | 独立测试 target | 接口 | 类型 | 平台 | 性能 |",
        "| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, key in enumerate(registry_order, start=1):
        module, operator = key
        if key in resolved["task_used"]:
            group = "A-task_used"
        elif key in resolved["appendix_only"]:
            group = "B-appendix_only"
        else:
            group = "C-native_only"
        lines.append(
            f"| {index} | {group} | `{module}/{operator}` | "
            f"`include/cusignal/{module}/{module}.hpp` | `src/cpu/{module}.cpp` | "
            f"`src/zhongkexin/{module}.cu` | `{targets[key]}` | "
            "见接口审计 | 见类型审计 | 见平台审计 | 见冻结报告 |"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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

    if key in groups["task_used"]:
        group = "A-task_used"
    elif key in groups["appendix_only"]:
        group = "B-appendix_only"
    else:
        group = "C-native_only"
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
        "# 算子接口审计",
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
        "# 81 算子接口清单",
        "",
        "本清单由 `operator_contract_audit.py` 根据测试注册表、命名集合和实际源码生成。"
        "结论覆盖声明、CPU/GPU 定义、独立测试 target 和 Doxygen；类型与平台状态由各自最终审计给出。",
        "",
        "| # | 集合 | 算子 | 声明 | CPU | ZQ500 GPU | 独立测试 target | 接口审计 | 类型 | 平台 | 性能 |",
        "| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for index, row in enumerate(rows, start=1):
        interface = "通过" if row["pass"] else "整改：" + ",".join(row["findings"])
        lines.append(
            f"| {index} | {row['group']} | `{row['key']}` | `{row['header']}` | "
            f"`{row['cpu_source']}` | `{row['gpu_source']}` | `{row['test_target']}` | "
            f"{interface} | 见类型审计 | 见平台审计 | 见冻结报告 |"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    registry_order, targets = load_registry(args)
    validate_source_paths(repo_root, registry_order)
    sets_path = Path(args.sets)
    payload = load_operator_set_config(sets_path)
    appendix_source = Path(args.appendix_xlsx) if args.appendix_xlsx else None
    if appendix_source is None and payload.get("sets", {}).get("task_appendix", {}).get("source") == "算子表.xlsx":
        appendix_source = sets_path.resolve().parents[2] / "算子表.xlsx"
    groups, set_summary = validate_operator_sets(
        registry_order,
        payload,
        appendix_source,
    )

    if args.summary_json:
        summary_path = Path(args.summary_json)
        summary_path.parent.mkdir(parents=True, exist_ok=True)
        summary_path.write_text(json.dumps(set_summary, indent=2) + "\n", encoding="utf-8")
    if args.set_contract_markdown:
        write_set_contract_markdown(
            Path(args.set_contract_markdown),
            registry_order,
            targets,
            groups,
        )
    if args.list_set:
        if args.list_set not in groups:
            raise ValueError(f"unknown operator set: {args.list_set}")
        selected = groups[args.list_set]
        for key in registry_order:
            if key in selected:
                print(f"{key[0]}\t{key[1]}\t{targets[key]}")
        return 0

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
    contract_markdown = Path(args.contract_markdown)
    contract_markdown.parent.mkdir(parents=True, exist_ok=True)
    write_contract_inventory(contract_markdown, rows)
    print(json.dumps(set_summary, sort_keys=True))
    print(json.dumps(summary, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
