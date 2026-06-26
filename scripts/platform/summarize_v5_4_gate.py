#!/usr/bin/env python3

"""Summarize V5.4 core53 performance, regression, contract, and plot gates."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


REQUIRED_MODULE_COUNTS = {
    "filter_design": 5,
    "filtering": 17,
    "radartools": 6,
    "spectral": 9,
    "bsplines": 3,
    "wavelets": 5,
    "windows": 23,
}


def is_timestamped_operator_name(name: str) -> bool:
    suffix_len = 16
    if len(name) <= suffix_len:
        return False
    suffix = name[-suffix_len:]
    if suffix[0] != "_" or suffix[9] != "_":
        return False
    return all(ch.isdigit() for index, ch in enumerate(suffix[1:], start=1) if index != 9)


def read_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"missing JSON: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(f"missing CSV: {path}")
    with path.open("r", encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def status_passed(value: Any) -> bool:
    return str(value).strip().lower() == "passed"


def report_path_exists(path_text: str, repo_root: Path) -> bool:
    path = Path(path_text)
    if path.exists():
        return True
    if path.is_absolute() and len(path.parts) > 1 and path.parts[1] == "CETC":
        mapped = repo_root.joinpath(*path.parts[2:])
        if mapped.exists():
            return True
        if len(mapped.parts) >= 2 and mapped.parts[-2] == "operator_figures":
            nested = mapped.parent.parent / "figures" / "operator_figures" / mapped.name
            return nested.exists()
    return False


def summarize_core53(csv_path: Path) -> dict[str, Any]:
    rows = read_csv_rows(csv_path)
    operators = {(row.get("module", ""), row.get("operator", "")) for row in rows}
    failed = [row for row in rows if not status_passed(row.get("status"))]
    passed = len(rows) == 53 and len(operators) == 53 and not failed
    return {
        "csv_path": str(csv_path),
        "row_count": len(rows),
        "operator_count": len(operators),
        "failed_count": len(failed),
        "failed": [f'{row.get("module")}/{row.get("operator")}' for row in failed],
        "status": "passed" if passed else "failed",
    }


def summarize_modules(unit_root: Path) -> dict[str, Any]:
    modules: dict[str, Any] = {}
    failed_modules: list[str] = []
    for module, expected_count in REQUIRED_MODULE_COUNTS.items():
        path = unit_root / module / "latest_metrics.json"
        payload = read_json(path)
        operators = [
            item for item in payload.get("operators", [])
            if not is_timestamped_operator_name(str(item.get("operator", "")))
        ]
        failed = [item.get("operator", "") for item in operators if not item.get("pass")]
        passed = len(operators) == expected_count and not failed
        modules[module] = {
            "path": str(path),
            "operator_count": len(operators),
            "expected_count": expected_count,
            "failed": failed,
            "status": "passed" if passed else "failed",
        }
        if not passed:
            failed_modules.append(module)
    return {
        "modules": modules,
        "failed_modules": failed_modules,
        "status": "passed" if not failed_modules else "failed",
    }


def summarize_task_smoke(path: Path) -> dict[str, Any]:
    payload = read_json(path)
    passed = payload.get("status") == "passed" and payload.get("failure_count") == 0
    return {
        "path": str(path),
        "status": payload.get("status", "unknown"),
        "task_count": payload.get("task_count"),
        "step_count": payload.get("step_count"),
        "failure_count": payload.get("failure_count"),
        "passed": passed,
    }


def summarize_contracts(interface_path: Path, type_path: Path) -> dict[str, Any]:
    interface = read_json(interface_path).get("summary", {})
    types = read_json(type_path).get("summary", {})
    passed = (
        interface.get("status") == "passed"
        and interface.get("operator_count") == 81
        and interface.get("failed_count") == 0
        and types.get("status") == "passed"
        and types.get("operator_count") == 81
        and types.get("complex_types") == ["complex64"]
    )
    return {
        "interface_path": str(interface_path),
        "type_path": str(type_path),
        "interface": interface,
        "types": types,
        "status": "passed" if passed else "failed",
    }


def summarize_plots(manifest_path: Path, repo_root: Path) -> dict[str, Any]:
    expected_manifest_path = manifest_path
    source_manifest_path = manifest_path
    if not source_manifest_path.exists():
        nested = source_manifest_path.parents[1] / "figures" / "operator_figures" / source_manifest_path.name
        if nested.exists():
            source_manifest_path = nested
    rows = read_csv_rows(source_manifest_path)
    operator_total = sum(int(row.get("operator_count", "0") or "0") for row in rows)
    missing = [row.get("path", "") for row in rows if row.get("path") and not report_path_exists(row["path"], repo_root)]
    passed = len(rows) == 12 and operator_total == 53 and not missing
    return {
        "manifest_path": str(expected_manifest_path),
        "source_manifest_path": str(source_manifest_path),
        "module_figure_count": len(rows),
        "operator_total": operator_total,
        "missing_paths": missing,
        "status": "passed" if passed else "failed",
    }


def write_markdown(path: Path, payload: dict[str, Any]) -> None:
    lines = [
        "# V5.4 Gate Summary",
        "",
        f"- status: `{payload['status']}`",
        f"- core53 rows: `{payload['core53']['row_count']}`",
        f"- core53 operators: `{payload['core53']['operator_count']}`",
        f"- core53 failed: `{payload['core53']['failed_count']}`",
        f"- module regression: `{payload['modules']['status']}`",
        f"- task smoke: `{payload['task_smoke']['status']}`",
        f"- contracts: `{payload['contracts']['status']}`",
        f"- compact plot figures: `{payload['plots']['module_figure_count']}` modules, `{payload['plots']['operator_total']}` operators",
        "",
        "## Module Regression",
        "",
        "| module | status | operators | failed |",
        "| --- | --- | ---: | --- |",
    ]
    for module, item in payload["modules"]["modules"].items():
        failed = ", ".join(item["failed"]) if item["failed"] else "-"
        lines.append(f"| {module} | {item['status']} | {item['operator_count']}/{item['expected_count']} | {failed} |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=".", help="Repository root.")
    parser.add_argument("--output-dir", default="data/reports/zhongkexin/v5_4_gate_latest")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    output_dir = (repo_root / args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "core53": summarize_core53(
            repo_root / "data/reports/unit/benchmarks/v5_4_core53_batch_close_probe/latest_all_ops_scale_benchmark.csv"
        ),
        "modules": summarize_modules(repo_root / "data/reports/unit"),
        "task_smoke": summarize_task_smoke(repo_root / "data/reports/zhongkexin/v5_4_task_smoke_after_core53.json"),
        "contracts": summarize_contracts(
            repo_root / "data/reports/zhongkexin/v5_4_interface_audit/latest_interface_audit.json",
            repo_root / "data/reports/zhongkexin/v5_4_type_contracts/latest_type_contracts.json",
        ),
        "plots": summarize_plots(
            repo_root
            / "data/reports/unit/benchmarks/v5_4_core53_batch_close_probe/figures/operator_figures/latest_operator_curve_manifest.csv",
            repo_root,
        ),
    }
    payload["status"] = "passed" if (
        payload["core53"]["status"] == "passed"
        and payload["modules"]["status"] == "passed"
        and payload["task_smoke"]["passed"]
        and payload["contracts"]["status"] == "passed"
        and payload["plots"]["status"] == "passed"
    ) else "failed"

    json_path = output_dir / "summary.json"
    md_path = output_dir / "summary.md"
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(md_path, payload)
    print(json.dumps({"status": payload["status"], "summary_json": str(json_path), "summary_markdown": str(md_path)}, ensure_ascii=False))
    return 0 if payload["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
