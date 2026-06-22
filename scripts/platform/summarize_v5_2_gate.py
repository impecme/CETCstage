#!/usr/bin/env python3

"""Summarize V5.2 contract, compatibility, and 81-operator accuracy gates."""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", required=True)
    parser.add_argument("--operator-sets", required=True)
    parser.add_argument("--interface-audit", required=True)
    parser.add_argument("--type-contracts", required=True)
    parser.add_argument("--compatibility", required=True)
    parser.add_argument("--api-usage", required=True)
    parser.add_argument("--execution-stamp", required=True)
    parser.add_argument("--unit-report-root", required=True)
    parser.add_argument("--output-dir", required=True)
    return parser.parse_args()


def load_json(path: str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    args = parse_args()
    registry = []
    with Path(args.registry).open(encoding="utf-8") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) >= 2:
                registry.append({"module": row[0], "operator": row[1]})
    operator_rows = []
    missing_reports = []
    failed_operators = []
    for entry in registry:
        module = entry["module"]
        operator = entry["operator"]
        report_path = Path(args.unit_report_root) / module / operator / "latest_metrics.json"
        if not report_path.is_file():
            missing_reports.append(f"{module}/{operator}")
            continue
        report = load_json(str(report_path))
        summary = report.get("summary", {})
        passed = bool(summary.get("pass")) and int(summary.get("accuracy_cases", 0)) > 0
        operator_rows.append(
            {
                "operator": f"{module}/{operator}",
                "passed": passed,
                "accuracy_cases": int(summary.get("accuracy_cases", 0)),
                "max_abs_error": summary.get("max_abs_error"),
                "mixed_error": summary.get("mixed_error"),
                "report": str(report_path),
            }
        )
        if not passed:
            failed_operators.append(f"{module}/{operator}")

    sets = load_json(args.operator_sets)
    interfaces = load_json(args.interface_audit)["summary"]
    types = load_json(args.type_contracts)["summary"]
    compatibility = load_json(args.compatibility)
    api_usage = load_json(args.api_usage)
    execution = load_json(args.execution_stamp)
    checks = {
        "registry_81": len(registry) == 81,
        "operator_sets": sets.get("status") == "passed" and sets.get("registry_count") == 81,
        "interfaces_81": interfaces.get("status") == "passed" and interfaces.get("passed_count") == 81,
        "type_contracts_81": types.get("status") == "passed" and types.get("operator_count") == 81,
        "compatibility_900_rows": compatibility.get("status") == "passed" and compatibility.get("source_row_count") == 900,
        "api_usage": api_usage.get("status") == "passed" and api_usage.get("violation_count") == 0 and api_usage.get("unresolved_count") == 0,
        "operator_accuracy_81": len(operator_rows) == 81 and not missing_reports and not failed_operators,
        "type_and_platform_ctest": execution.get("status") == "passed",
    }
    status = "passed" if all(checks.values()) else "failed"
    payload = {
        "status": status,
        "checks": checks,
        "operator_count": len(registry),
        "operator_accuracy_passed_count": sum(row["passed"] for row in operator_rows),
        "missing_reports": missing_reports,
        "failed_operators": failed_operators,
        "compatibility": {
            "source_row_count": compatibility.get("source_row_count"),
            "api_row_count": compatibility.get("api_row_count"),
            "unique_api_count": compatibility.get("unique_api_count"),
            "forbidden_api_count": compatibility.get("forbidden_api_count"),
        },
        "api_usage": {
            key: api_usage.get(key)
            for key in ("used_api_count", "violation_count", "unresolved_count", "documented_exception_count")
        },
        "operators": operator_rows,
    }
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    (output / "summary.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    lines = [
        "# V5.2 阶段门禁摘要",
        "",
        f"- status: `{status}`",
        f"- operator accuracy: `{payload['operator_accuracy_passed_count']}/81`",
        f"- compatibility rows/APIs: `{compatibility.get('source_row_count')}` / `{compatibility.get('unique_api_count')}`",
        f"- forbidden API violations: `{api_usage.get('violation_count')}`",
        f"- unresolved APIs: `{api_usage.get('unresolved_count')}`",
        "",
        "| 门禁 | 状态 |",
        "| --- | --- |",
    ]
    lines.extend(f"| {name} | {'passed' if passed else 'failed'} |" for name, passed in checks.items())
    if missing_reports:
        lines.extend(("", "## 缺失报告", "", *[f"- `{name}`" for name in missing_reports]))
    if failed_operators:
        lines.extend(("", "## 失败算子", "", *[f"- `{name}`" for name in failed_operators]))
    (output / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in payload.items() if key != "operators"}, ensure_ascii=False, sort_keys=True))
    return 0 if status == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
