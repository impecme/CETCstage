#!/usr/bin/env python3

"""Audit precision for all enabled unit-test operators.

Workflow:
1. Read enabled operators from run_all_tests.sh --list.
2. Run accuracy for selected operators and write baseline CSV.
3. Build a fix queue from failed operators (summary.pass == false or command failure).
4. Run perf for queue operators and write perf snapshot CSV.
5. Optionally compare with a previous baseline to produce perf delta + markdown report.
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class OperatorEntry:
    module: str
    operator: str
    target: str
    binary_rel: str


@dataclass
class MetricsSummary:
    summary_pass: bool | None = None
    accuracy_cases: int | None = None
    perf_cases: int | None = None
    max_abs_error: str = ""
    max_rel_error: str = ""
    rmse: str = ""
    cpu_median_ms: str = ""
    gpu_e2e_median_ms: str = ""
    gpu_kernel_median_ms: str = ""
    gpu_e2e_speedup: str = ""
    gpu_kernel_speedup: str = ""
    git_commit: str = ""
    gpu_name: str = ""


def log(message: str) -> None:
    print(f"[precision-audit] {message}")


def format_metric(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, float):
        return f"{value:.17g}"
    return str(value)


def parse_csv_tokens(value: str, field_name: str) -> list[str]:
    parts = [item.strip() for item in value.split(",") if item.strip()]
    if not parts:
        raise ValueError(f"--{field_name} cannot be empty")
    return parts


def create_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Audit precision (accuracy baseline + fix queue + perf snapshot)."
    )
    parser.add_argument(
        "--modules",
        default="all",
        help="Comma-separated module filter (default: all)",
    )
    parser.add_argument(
        "--operators",
        default="all",
        help="Comma-separated operator filter (default: all)",
    )
    parser.add_argument(
        "--build",
        dest="do_build",
        action="store_true",
        help="Build before each operator execution",
    )
    parser.add_argument(
        "--no-build",
        dest="do_build",
        action="store_false",
        help="Reuse existing binaries (default)",
    )
    parser.set_defaults(do_build=False)
    parser.add_argument(
        "--build-dir",
        default="build",
        help="Build directory (default: build)",
    )
    parser.add_argument(
        "--warmup",
        type=int,
        default=5,
        help="Warmup iterations for perf runs (default: 5)",
    )
    parser.add_argument(
        "--repeat",
        type=int,
        default=30,
        help="Repeat iterations for perf runs (default: 30)",
    )
    parser.add_argument(
        "--output-dir",
        default="data/reports/unit/audit",
        help="Output directory (default: data/reports/unit/audit)",
    )
    parser.add_argument(
        "--runner-script",
        default="scripts/test/run_all_tests.sh",
        help="Path to run_all_tests.sh",
    )
    parser.add_argument(
        "--compare-baseline",
        default="",
        help="Optional baseline CSV path from a previous run for perf-delta comparison",
    )
    parser.add_argument(
        "--fix-notes-file",
        default="",
        help="Optional CSV: module,operator,trigger_reason,fix_mechanism,impact_scope",
    )
    return parser


def parse_args() -> argparse.Namespace:
    parser = create_argument_parser()
    args = parser.parse_args()

    if args.warmup < 0:
        parser.error("--warmup must be a non-negative integer")
    if args.repeat < 0:
        parser.error("--repeat must be a non-negative integer")

    if args.modules != "all":
        try:
            args.modules = parse_csv_tokens(args.modules, "modules")
        except ValueError as exc:
            parser.error(str(exc))
    else:
        args.modules = "all"

    if args.operators != "all":
        try:
            args.operators = parse_csv_tokens(args.operators, "operators")
        except ValueError as exc:
            parser.error(str(exc))
    else:
        args.operators = "all"

    return args


def resolve_path(repo_root: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return repo_root / path


def parse_list_output(text: str) -> list[OperatorEntry]:
    entries: list[OperatorEntry] = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            continue
        entries.append(
            OperatorEntry(
                module=parts[0].strip(),
                operator=parts[1].strip(),
                target=parts[2].strip(),
                binary_rel=parts[3].strip(),
            )
        )
    return entries


def load_enabled_entries(
    runner_script: Path,
    build_dir: Path,
) -> list[OperatorEntry]:
    cmd = [
        str(runner_script),
        "--list",
        "--no-build",
        "--build-dir",
        str(build_dir),
    ]
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    entries = parse_list_output(result.stdout)
    if not entries:
        raise RuntimeError("no enabled operators returned from run_all_tests.sh --list")
    return entries


def filter_entries(
    entries: list[OperatorEntry],
    modules: list[str] | str,
    operators: list[str] | str,
) -> list[OperatorEntry]:
    filtered: list[OperatorEntry] = []
    for item in entries:
        if modules != "all" and item.module not in modules:
            continue
        if operators != "all" and item.operator not in operators:
            continue
        filtered.append(item)
    if not filtered:
        raise RuntimeError("no operators match --modules/--operators filters")
    return filtered


def run_one_operator(
    runner_script: Path,
    build_dir: Path,
    do_build: bool,
    module: str,
    operator: str,
    case_set: str,
    warmup: int,
    repeat: int,
) -> tuple[int, str]:
    cmd = [
        str(runner_script),
        "--module",
        module,
        "--operator",
        operator,
        "--case-set",
        case_set,
        "--emit-report",
        "--warmup",
        str(warmup),
        "--repeat",
        str(repeat),
        "--build-dir",
        str(build_dir),
    ]
    if not do_build:
        cmd.append("--no-build")

    result = subprocess.run(cmd, capture_output=True, text=True)
    combined = "\n".join(
        [part for part in [result.stdout.strip(), result.stderr.strip()] if part]
    )
    return result.returncode, combined


def metrics_path(repo_root: Path, module: str, operator: str) -> Path:
    return repo_root / "data" / "reports" / "unit" / module / operator / "latest_metrics.json"


def load_metrics_summary(metrics_file: Path) -> MetricsSummary:
    payload = json.loads(metrics_file.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("metrics payload is not an object")

    summary_node = payload.get("summary")
    if not isinstance(summary_node, dict):
        raise ValueError("metrics payload missing standard summary object")
    summary = summary_node
    summary_pass = summary.get("pass")
    if not isinstance(summary_pass, bool):
        raise ValueError("metrics summary.pass must be a boolean")

    def timing_value(section: str, key: str) -> str:
        node = summary.get(section)
        if not isinstance(node, dict):
            return ""
        return format_metric(node.get(key))

    max_abs_error = summary.get("max_abs_error")
    max_rel_error = summary.get("max_rel_error")
    rmse = summary.get("rmse")

    out = MetricsSummary(
        summary_pass=summary_pass,
        accuracy_cases=summary.get("accuracy_cases"),
        perf_cases=summary.get("perf_cases"),
        max_abs_error=format_metric(max_abs_error),
        max_rel_error=format_metric(max_rel_error),
        rmse=format_metric(rmse),
        cpu_median_ms=timing_value("cpu_perf", "median_ms"),
        gpu_e2e_median_ms=timing_value("gpu_e2e_perf", "median_ms"),
        gpu_kernel_median_ms=timing_value("gpu_kernel_perf", "median_ms"),
        gpu_e2e_speedup=format_metric(summary.get("gpu_e2e_speedup")),
        gpu_kernel_speedup=format_metric(summary.get("gpu_kernel_speedup")),
        git_commit=format_metric(payload.get("git_commit")),
        gpu_name=format_metric(payload.get("gpu_name")),
    )
    return out


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def copy_latest(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


def load_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def load_fix_notes(path: Path | None) -> dict[tuple[str, str], dict[str, str]]:
    if path is None:
        return {}
    if not path.exists():
        raise FileNotFoundError(f"fix notes file not found: {path}")
    rows = load_csv_rows(path)
    notes: dict[tuple[str, str], dict[str, str]] = {}
    for row in rows:
        module = row.get("module", "").strip()
        operator = row.get("operator", "").strip()
        if not module or not operator:
            continue
        notes[(module, operator)] = {
            "trigger_reason": row.get("trigger_reason", "").strip(),
            "fix_mechanism": row.get("fix_mechanism", "").strip(),
            "impact_scope": row.get("impact_scope", "").strip(),
        }
    return notes


def to_float(value: str) -> float | None:
    text = value.strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def format_delta(before: str, after: str) -> tuple[str, str]:
    before_v = to_float(before)
    after_v = to_float(after)
    if before_v is None or after_v is None:
        return "", ""
    diff = after_v - before_v
    rel = ""
    if before_v != 0.0:
        rel = f"{(diff / before_v) * 100.0:.6g}"
    return format_metric(diff), rel


def build_report_markdown(
    report_path: Path,
    run_id: str,
    baseline_rows: list[dict[str, Any]],
    queue_rows: list[dict[str, Any]],
    delta_rows: list[dict[str, Any]],
    notes: dict[tuple[str, str], dict[str, str]],
) -> None:
    lines: list[str] = []
    infra_count = sum(1 for row in baseline_rows if row.get("status") == "infra_failed")
    lines.append(f"# Precision Fix Report ({run_id})")
    lines.append("")
    lines.append(f"- Total operators audited: {len(baseline_rows)}")
    lines.append(f"- Operators in fix queue: {len(queue_rows)}")
    lines.append(f"- Infra failed operators: {infra_count}")
    lines.append(f"- Operators with perf delta records: {len(delta_rows)}")
    lines.append("")

    if not queue_rows:
        if infra_count > 0:
            lines.append(
                "No threshold-based precision failures were detected, but some operators are infra_failed "
                "(for example missing binaries)."
            )
        else:
            lines.append("All operators passed current threshold-based accuracy checks.")
    else:
        lines.append("## Queue Details")
        lines.append("")
        for row in queue_rows:
            module = row["module"]
            operator = row["operator"]
            key = (module, operator)
            note = notes.get(key, {})
            lines.append(f"### {module}/{operator}")
            lines.append(f"- Trigger reason: {note.get('trigger_reason') or row.get('error_note') or 'summary.pass=false'}")
            lines.append(f"- Baseline max_rel_error: {row.get('max_rel_error', '')}")
            lines.append(f"- Fix mechanism: {note.get('fix_mechanism') or 'N/A (provide --fix-notes-file for detailed mechanism)'}")
            lines.append(f"- Impact scope: {note.get('impact_scope') or 'N/A'}")
            lines.append("")

    if delta_rows:
        lines.append("## Perf Delta")
        lines.append("")
        for row in delta_rows:
            lines.append(f"### {row['module']}/{row['operator']}")
            lines.append(f"- Full pass after fix: {row.get('full_pass_after', '')}")
            lines.append(
                f"- CPU median ms: {row.get('cpu_median_before', '')} -> {row.get('cpu_median_after', '')} (delta={row.get('cpu_median_delta', '')}, delta_pct={row.get('cpu_median_delta_pct', '')})"
            )
            lines.append(
                f"- GPU e2e median ms: {row.get('gpu_e2e_median_before', '')} -> {row.get('gpu_e2e_median_after', '')} (delta={row.get('gpu_e2e_median_delta', '')}, delta_pct={row.get('gpu_e2e_median_delta_pct', '')})"
            )
            lines.append(
                f"- GPU kernel median ms: {row.get('gpu_kernel_median_before', '')} -> {row.get('gpu_kernel_median_after', '')} (delta={row.get('gpu_kernel_median_delta', '')}, delta_pct={row.get('gpu_kernel_median_delta_pct', '')})"
            )
            lines.append("")

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")


def run_baseline_accuracy(
    repo_root: Path,
    runner_script: Path,
    build_dir: Path,
    do_build: bool,
    entries: list[OperatorEntry],
    run_id: str,
    timestamp: str,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    baseline_rows: list[dict[str, Any]] = []

    for idx, entry in enumerate(entries, start=1):
        log(f"[accuracy {idx}/{len(entries)}] {entry.module}/{entry.operator}")
        return_code, output = run_one_operator(
            runner_script=runner_script,
            build_dir=build_dir,
            do_build=do_build,
            module=entry.module,
            operator=entry.operator,
            case_set="accuracy",
            warmup=0,
            repeat=0,
        )

        row: dict[str, Any] = {
            "run_id": run_id,
            "timestamp": timestamp,
            "module": entry.module,
            "operator": entry.operator,
            "return_code": return_code,
            "summary_pass": "",
            "status": "infra_failed" if return_code != 0 else "unknown",
            "accuracy_cases": "",
            "perf_cases": "",
            "max_abs_error": "",
            "max_rel_error": "",
            "rmse": "",
            "cpu_median_ms": "",
            "gpu_e2e_median_ms": "",
            "gpu_kernel_median_ms": "",
            "gpu_e2e_speedup": "",
            "gpu_kernel_speedup": "",
            "git_commit": "",
            "gpu_name": "",
            "metrics_json_path": "",
            "error_note": "",
        }

        metrics_file = metrics_path(repo_root, entry.module, entry.operator)
        if return_code != 0:
            tail = output[-800:] if output else ""
            row["error_note"] = f"command failed, rc={return_code}; output_tail={tail}"

        if metrics_file.exists():
            try:
                summary = load_metrics_summary(metrics_file)
                row["summary_pass"] = (
                    "true" if summary.summary_pass is True else "false" if summary.summary_pass is False else ""
                )
                if return_code == 0 and summary.summary_pass is True:
                    row["status"] = "passed"
                elif return_code == 0 and summary.summary_pass is False:
                    row["status"] = "failed"
                elif return_code != 0:
                    row["status"] = "infra_failed"
                else:
                    row["status"] = "infra_failed"
                row["accuracy_cases"] = format_metric(summary.accuracy_cases)
                row["perf_cases"] = format_metric(summary.perf_cases)
                row["max_abs_error"] = summary.max_abs_error
                row["max_rel_error"] = summary.max_rel_error
                row["rmse"] = summary.rmse
                row["cpu_median_ms"] = summary.cpu_median_ms
                row["gpu_e2e_median_ms"] = summary.gpu_e2e_median_ms
                row["gpu_kernel_median_ms"] = summary.gpu_kernel_median_ms
                row["gpu_e2e_speedup"] = summary.gpu_e2e_speedup
                row["gpu_kernel_speedup"] = summary.gpu_kernel_speedup
                row["git_commit"] = summary.git_commit
                row["gpu_name"] = summary.gpu_name
                row["metrics_json_path"] = str(metrics_file)
            except Exception as exc:  # noqa: BLE001
                if row["status"] == "unknown":
                    row["status"] = "infra_failed"
                parse_note = f"failed to parse metrics: {exc}"
                row["error_note"] = (
                    f"{row['error_note']} | {parse_note}" if row["error_note"] else parse_note
                )
        else:
            if row["status"] == "unknown":
                row["status"] = "infra_failed"
            miss_note = "metrics file missing after accuracy run"
            row["error_note"] = (
                f"{row['error_note']} | {miss_note}" if row["error_note"] else miss_note
            )

        baseline_rows.append(row)

    queue_rows = [row for row in baseline_rows if row.get("status") == "failed"]
    return baseline_rows, queue_rows


def run_perf_snapshot_for_queue(
    repo_root: Path,
    runner_script: Path,
    build_dir: Path,
    do_build: bool,
    queue_rows: list[dict[str, Any]],
    run_id: str,
    timestamp: str,
    warmup: int,
    repeat: int,
) -> list[dict[str, Any]]:
    snapshot_rows: list[dict[str, Any]] = []
    if not queue_rows:
        return snapshot_rows

    for idx, row in enumerate(queue_rows, start=1):
        module = row["module"]
        operator = row["operator"]
        log(f"[perf snapshot {idx}/{len(queue_rows)}] {module}/{operator}")
        return_code, output = run_one_operator(
            runner_script=runner_script,
            build_dir=build_dir,
            do_build=do_build,
            module=module,
            operator=operator,
            case_set="perf",
            warmup=warmup,
            repeat=repeat,
        )

        snap: dict[str, Any] = {
            "run_id": run_id,
            "timestamp": timestamp,
            "module": module,
            "operator": operator,
            "return_code": return_code,
            "summary_pass": "",
            "status": "failed" if return_code != 0 else "unknown",
            "max_abs_error": "",
            "max_rel_error": "",
            "rmse": "",
            "cpu_median_ms": "",
            "gpu_e2e_median_ms": "",
            "gpu_kernel_median_ms": "",
            "gpu_e2e_speedup": "",
            "gpu_kernel_speedup": "",
            "metrics_json_path": "",
            "error_note": "",
        }

        metrics_file = metrics_path(repo_root, module, operator)
        if return_code != 0:
            tail = output[-800:] if output else ""
            snap["error_note"] = f"command failed, rc={return_code}; output_tail={tail}"

        if metrics_file.exists():
            try:
                summary = load_metrics_summary(metrics_file)
                snap["summary_pass"] = (
                    "true" if summary.summary_pass is True else "false" if summary.summary_pass is False else ""
                )
                snap["status"] = "passed" if (return_code == 0 and summary.summary_pass is True) else "failed"
                snap["max_abs_error"] = summary.max_abs_error
                snap["max_rel_error"] = summary.max_rel_error
                snap["rmse"] = summary.rmse
                snap["cpu_median_ms"] = summary.cpu_median_ms
                snap["gpu_e2e_median_ms"] = summary.gpu_e2e_median_ms
                snap["gpu_kernel_median_ms"] = summary.gpu_kernel_median_ms
                snap["gpu_e2e_speedup"] = summary.gpu_e2e_speedup
                snap["gpu_kernel_speedup"] = summary.gpu_kernel_speedup
                snap["metrics_json_path"] = str(metrics_file)
            except Exception as exc:  # noqa: BLE001
                snap["status"] = "failed"
                parse_note = f"failed to parse metrics: {exc}"
                snap["error_note"] = (
                    f"{snap['error_note']} | {parse_note}" if snap["error_note"] else parse_note
                )
        else:
            snap["status"] = "failed"
            miss_note = "metrics file missing after perf run"
            snap["error_note"] = (
                f"{snap['error_note']} | {miss_note}" if snap["error_note"] else miss_note
            )

        snapshot_rows.append(snap)

    return snapshot_rows


def build_delta_rows(
    tracked_ops: list[tuple[str, str]],
    old_snapshot_rows: list[dict[str, str]],
    new_perf_rows: list[dict[str, Any]],
    full_status_rows: dict[tuple[str, str], str],
    run_id: str,
    timestamp: str,
) -> list[dict[str, Any]]:
    old_map: dict[tuple[str, str], dict[str, str]] = {
        (row["module"], row["operator"]): row for row in old_snapshot_rows
    }
    new_map: dict[tuple[str, str], dict[str, Any]] = {
        (row["module"], row["operator"]): row for row in new_perf_rows
    }

    rows: list[dict[str, Any]] = []
    for module, operator in tracked_ops:
        before = old_map.get((module, operator), {})
        after = new_map.get((module, operator), {})

        cpu_delta, cpu_delta_pct = format_delta(
            before.get("cpu_median_ms", ""),
            str(after.get("cpu_median_ms", "")),
        )
        e2e_delta, e2e_delta_pct = format_delta(
            before.get("gpu_e2e_median_ms", ""),
            str(after.get("gpu_e2e_median_ms", "")),
        )
        kernel_delta, kernel_delta_pct = format_delta(
            before.get("gpu_kernel_median_ms", ""),
            str(after.get("gpu_kernel_median_ms", "")),
        )

        rows.append(
            {
                "run_id": run_id,
                "timestamp": timestamp,
                "module": module,
                "operator": operator,
                "full_pass_after": full_status_rows.get((module, operator), ""),
                "cpu_median_before": before.get("cpu_median_ms", ""),
                "cpu_median_after": after.get("cpu_median_ms", ""),
                "cpu_median_delta": cpu_delta,
                "cpu_median_delta_pct": cpu_delta_pct,
                "gpu_e2e_median_before": before.get("gpu_e2e_median_ms", ""),
                "gpu_e2e_median_after": after.get("gpu_e2e_median_ms", ""),
                "gpu_e2e_median_delta": e2e_delta,
                "gpu_e2e_median_delta_pct": e2e_delta_pct,
                "gpu_kernel_median_before": before.get("gpu_kernel_median_ms", ""),
                "gpu_kernel_median_after": after.get("gpu_kernel_median_ms", ""),
                "gpu_kernel_median_delta": kernel_delta,
                "gpu_kernel_median_delta_pct": kernel_delta_pct,
                "max_rel_error_before": before.get("max_rel_error", ""),
                "max_rel_error_after": str(after.get("max_rel_error", "")),
                "max_abs_error_before": before.get("max_abs_error", ""),
                "max_abs_error_after": str(after.get("max_abs_error", "")),
            }
        )

    return rows


def run_full_for_ops(
    repo_root: Path,
    runner_script: Path,
    build_dir: Path,
    do_build: bool,
    tracked_ops: list[tuple[str, str]],
) -> dict[tuple[str, str], str]:
    status: dict[tuple[str, str], str] = {}
    for idx, (module, operator) in enumerate(tracked_ops, start=1):
        log(f"[full verify {idx}/{len(tracked_ops)}] {module}/{operator}")
        return_code, _ = run_one_operator(
            runner_script=runner_script,
            build_dir=build_dir,
            do_build=do_build,
            module=module,
            operator=operator,
            case_set="full",
            warmup=1,
            repeat=1,
        )
        metrics_file = metrics_path(repo_root, module, operator)
        pass_value = ""
        if metrics_file.exists():
            try:
                summary = load_metrics_summary(metrics_file)
                pass_value = (
                    "true" if (return_code == 0 and summary.summary_pass is True) else "false"
                )
            except Exception:  # noqa: BLE001
                pass_value = "false"
        else:
            pass_value = "false"
        status[(module, operator)] = pass_value
    return status


def main() -> int:
    args = parse_args()

    script_path = Path(__file__).resolve()
    repo_root = script_path.parents[2]

    runner_script = resolve_path(repo_root, args.runner_script)
    build_dir = resolve_path(repo_root, args.build_dir)
    output_dir = resolve_path(repo_root, args.output_dir)
    compare_baseline = resolve_path(repo_root, args.compare_baseline) if args.compare_baseline else None
    fix_notes_file = resolve_path(repo_root, args.fix_notes_file) if args.fix_notes_file else None

    if not runner_script.exists():
        raise FileNotFoundError(f"runner script not found: {runner_script}")

    notes = load_fix_notes(fix_notes_file)

    entries = load_enabled_entries(runner_script, build_dir)
    entries = filter_entries(entries, args.modules, args.operators)

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    log(f"selected operators: {len(entries)}")
    log(f"build mode: {'build' if args.do_build else 'no-build'}")

    baseline_rows, queue_rows = run_baseline_accuracy(
        repo_root=repo_root,
        runner_script=runner_script,
        build_dir=build_dir,
        do_build=args.do_build,
        entries=entries,
        run_id=run_id,
        timestamp=timestamp,
    )

    baseline_fields = [
        "run_id",
        "timestamp",
        "module",
        "operator",
        "status",
        "summary_pass",
        "return_code",
        "accuracy_cases",
        "perf_cases",
        "max_abs_error",
        "max_rel_error",
        "rmse",
        "cpu_median_ms",
        "gpu_e2e_median_ms",
        "gpu_kernel_median_ms",
        "gpu_e2e_speedup",
        "gpu_kernel_speedup",
        "git_commit",
        "gpu_name",
        "metrics_json_path",
        "error_note",
    ]
    baseline_csv = output_dir / f"precision_baseline_{run_id}.csv"
    write_csv(baseline_csv, baseline_fields, baseline_rows)
    copy_latest(baseline_csv, output_dir / "latest_precision_baseline.csv")
    log(f"baseline csv: {baseline_csv}")

    queue_fields = baseline_fields
    queue_csv = output_dir / f"precision_fix_queue_{run_id}.csv"
    write_csv(queue_csv, queue_fields, queue_rows)
    copy_latest(queue_csv, output_dir / "latest_precision_fix_queue.csv")
    log(f"fix queue csv: {queue_csv}")

    perf_snapshot_rows = run_perf_snapshot_for_queue(
        repo_root=repo_root,
        runner_script=runner_script,
        build_dir=build_dir,
        do_build=args.do_build,
        queue_rows=queue_rows,
        run_id=run_id,
        timestamp=timestamp,
        warmup=args.warmup,
        repeat=args.repeat,
    )

    perf_snapshot_fields = [
        "run_id",
        "timestamp",
        "module",
        "operator",
        "status",
        "summary_pass",
        "return_code",
        "max_abs_error",
        "max_rel_error",
        "rmse",
        "cpu_median_ms",
        "gpu_e2e_median_ms",
        "gpu_kernel_median_ms",
        "gpu_e2e_speedup",
        "gpu_kernel_speedup",
        "metrics_json_path",
        "error_note",
    ]
    perf_snapshot_csv = output_dir / f"precision_perf_snapshot_{run_id}.csv"
    write_csv(perf_snapshot_csv, perf_snapshot_fields, perf_snapshot_rows)
    copy_latest(perf_snapshot_csv, output_dir / "latest_precision_perf_snapshot.csv")
    log(f"perf snapshot csv: {perf_snapshot_csv}")

    delta_rows: list[dict[str, Any]] = []
    if compare_baseline is not None:
        if not compare_baseline.exists():
            raise FileNotFoundError(f"compare baseline file not found: {compare_baseline}")

        old_baseline_rows = load_csv_rows(compare_baseline)
        tracked_ops = sorted(
            {
                (row.get("module", "").strip(), row.get("operator", "").strip())
                for row in old_baseline_rows
                if row.get("status", "") != "passed"
            }
        )
        tracked_ops = [(m, o) for (m, o) in tracked_ops if m and o]

        old_run_id = ""
        if old_baseline_rows:
            old_run_id = old_baseline_rows[0].get("run_id", "").strip()

        old_snapshot_csv = output_dir / f"precision_perf_snapshot_{old_run_id}.csv" if old_run_id else None
        old_snapshot_rows: list[dict[str, str]] = []
        if old_snapshot_csv is not None and old_snapshot_csv.exists():
            old_snapshot_rows = load_csv_rows(old_snapshot_csv)

        if tracked_ops:
            full_status_rows = run_full_for_ops(
                repo_root=repo_root,
                runner_script=runner_script,
                build_dir=build_dir,
                do_build=args.do_build,
                tracked_ops=tracked_ops,
            )

            new_perf_rows = run_perf_snapshot_for_queue(
                repo_root=repo_root,
                runner_script=runner_script,
                build_dir=build_dir,
                do_build=args.do_build,
                queue_rows=[
                    {
                        "module": module,
                        "operator": operator,
                    }
                    for module, operator in tracked_ops
                ],
                run_id=run_id,
                timestamp=timestamp,
                warmup=args.warmup,
                repeat=args.repeat,
            )

            delta_rows = build_delta_rows(
                tracked_ops=tracked_ops,
                old_snapshot_rows=old_snapshot_rows,
                new_perf_rows=new_perf_rows,
                full_status_rows=full_status_rows,
                run_id=run_id,
                timestamp=timestamp,
            )

    delta_fields = [
        "run_id",
        "timestamp",
        "module",
        "operator",
        "full_pass_after",
        "cpu_median_before",
        "cpu_median_after",
        "cpu_median_delta",
        "cpu_median_delta_pct",
        "gpu_e2e_median_before",
        "gpu_e2e_median_after",
        "gpu_e2e_median_delta",
        "gpu_e2e_median_delta_pct",
        "gpu_kernel_median_before",
        "gpu_kernel_median_after",
        "gpu_kernel_median_delta",
        "gpu_kernel_median_delta_pct",
        "max_rel_error_before",
        "max_rel_error_after",
        "max_abs_error_before",
        "max_abs_error_after",
    ]
    delta_csv = output_dir / f"precision_perf_delta_{run_id}.csv"
    write_csv(delta_csv, delta_fields, delta_rows)
    copy_latest(delta_csv, output_dir / "latest_precision_perf_delta.csv")
    log(f"perf delta csv: {delta_csv}")

    report_md = output_dir / "latest_precision_fix_report.md"
    build_report_markdown(
        report_path=report_md,
        run_id=run_id,
        baseline_rows=baseline_rows,
        queue_rows=queue_rows,
        delta_rows=delta_rows,
        notes=notes,
    )
    log(f"fix report: {report_md}")

    failed_count = sum(1 for row in baseline_rows if row.get("status") == "failed")
    infra_failed_count = sum(1 for row in baseline_rows if row.get("status") == "infra_failed")
    passed_count = sum(1 for row in baseline_rows if row.get("status") == "passed")
    log(
        "audit summary: "
        f"passed={passed_count}, failed={failed_count}, infra_failed={infra_failed_count}"
    )
    return 1 if (failed_count > 0 or infra_failed_count > 0) else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        log("interrupted")
        raise SystemExit(130)
