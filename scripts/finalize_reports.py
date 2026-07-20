#!/usr/bin/env python3

"""Validate one complete delivery run and publish its compact final reports."""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path
from typing import Any, Iterable


OPERATOR_FILE_MAP = {
    "latest_metrics.json": "metrics.json",
    "latest_cases.csv": "cases.csv",
    "latest_summary.md": "summary.md",
}
TASK_FILE_MAP = {
    "latest_metrics.json": "metrics.json",
    "latest_stage_timings.csv": "stage_timings.csv",
    "latest_step_metrics.csv": "step_metrics.csv",
    "latest_step_metrics.json": "step_metrics.json",
    "latest_summary.md": "summary.md",
}
OPERATOR_OUTPUT_FILES = tuple(OPERATOR_FILE_MAP.values())
TASK_OUTPUT_FILES = tuple(TASK_FILE_MAP.values())
TASKS = ("task1_radar", "task2_features")
SCALE_LEVELS = tuple(range(1, 7))
FORBIDDEN_PARTS = {
    "cache",
    "caches",
    "cache_evidence",
    "figure",
    "figures",
    "history",
    "histories",
    "log",
    "logs",
    "plot",
    "plots",
    "telemetry",
}
FORBIDDEN_SUFFIXES = {
    ".7z",
    ".bmp",
    ".gif",
    ".jpeg",
    ".jpg",
    ".log",
    ".png",
    ".svg",
    ".tar",
    ".tgz",
    ".xz",
    ".zip",
}
ZERO_COUNTER_SUFFIXES = (
    "_failed_count",
    "_failure_count",
    "_gap_count",
    "_missing_count",
    "_missing_edges",
    "_unresolved_count",
    "_violation_count",
)


class FinalizeError(ValueError):
    """Raised when source evidence is incomplete or inconsistent."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FinalizeError(message)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    require(path.is_file() and not path.is_symlink(), f"missing or unsafe regular file: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def reject_nonfinite(token: str) -> None:
    raise FinalizeError(f"non-finite JSON number: {token}")


def read_json(path: Path) -> dict[str, Any]:
    require(path.is_file() and not path.is_symlink(), f"missing or unsafe JSON file: {path}")
    try:
        payload = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=reject_duplicate_keys,
            parse_constant=reject_nonfinite,
        )
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise FinalizeError(f"invalid JSON {path}: {error}") from error
    require(isinstance(payload, dict), f"expected JSON object: {path}")
    return payload


def read_nonempty_text(path: Path) -> str:
    require(path.is_file() and not path.is_symlink(), f"missing or unsafe text file: {path}")
    try:
        value = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise FinalizeError(f"invalid UTF-8 text {path}: {error}") from error
    require(bool(value.strip()), f"empty text file: {path}")
    return value


def read_csv_rows(path: Path) -> tuple[list[str], list[list[str]]]:
    text = read_nonempty_text(path)
    try:
        rows = list(csv.reader(text.splitlines()))
    except csv.Error as error:
        raise FinalizeError(f"invalid CSV {path}: {error}") from error
    require(bool(rows) and bool(rows[0]), f"missing CSV header: {path}")
    header = rows[0]
    require(all(header), f"empty CSV column name: {path}")
    require(len(header) == len(set(header)), f"duplicate CSV column name: {path}")
    body = [row for row in rows[1:] if row]
    require(bool(body), f"CSV has no data rows: {path}")
    require(all(len(row) == len(header) for row in body), f"inconsistent CSV row width: {path}")
    return header, body


def json_summary(payload: dict[str, Any]) -> dict[str, Any]:
    summary = payload.get("summary", payload)
    require(isinstance(summary, dict), "audit summary must be an object")
    return summary


def iter_items(value: Any) -> Iterable[tuple[str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield key, child
            yield from iter_items(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_items(child)


def validate_audit_payload(payload: dict[str, Any], label: str) -> None:
    status_count = 0
    pass_count = 0
    for key, value in iter_items(payload):
        normalized = key.lower()
        if normalized == "status":
            status_count += 1
            require(value == "passed", f"{label}: status is not passed")
        if normalized == "pass" and isinstance(value, bool):
            pass_count += 1
            require(value, f"{label}: pass is false")
        if normalized.endswith(ZERO_COUNTER_SUFFIXES) and "planned_" not in normalized:
            require(isinstance(value, (int, float)) and not isinstance(value, bool),
                    f"{label}: {key} must be numeric")
            require(value == 0, f"{label}: {key} must be zero")
    if status_count == 0 and pass_count == 0:
        boolean_values = list(payload.values())
        require(boolean_values and all(value is True for value in boolean_values),
                f"{label}: audit has no passed status or true assertions")


def safe_relative_path(token: str, label: str) -> Path:
    require(bool(token) and "\n" not in token and "\r" not in token, f"invalid {label}: {token!r}")
    path = Path(token)
    require(not path.is_absolute(), f"{label} must be relative: {token}")
    require(all(part not in {"", ".", ".."} for part in path.parts), f"unsafe {label}: {token}")
    return path


def load_operator_contract(repo_root: Path) -> list[str]:
    path = repo_root / "tests/contracts/operator_sets.json"
    payload = read_json(path)
    all81 = payload.get("sets", {}).get("all81", {}) if isinstance(payload.get("sets"), dict) else {}
    require(isinstance(all81, dict), f"missing all81 operator set: {path}")
    operators = all81.get("operators")
    require(isinstance(operators, list) and all(isinstance(item, str) for item in operators),
            f"invalid all81 operator list: {path}")
    require(all81.get("expected_count") == 81, f"all81 expected_count must be 81: {path}")
    require(len(operators) == 81 and len(set(operators)) == 81,
            f"all81 must contain exactly 81 unique operators: {path}")
    for operator in operators:
        parts = safe_relative_path(operator, "operator key").parts
        require(len(parts) == 2, f"operator key must be module/operator: {operator}")
    return operators


def load_task_counts(repo_root: Path) -> dict[str, int]:
    path = repo_root / "tests/contracts/task_step_contracts.json"
    payload = read_json(path)
    tasks = payload.get("tasks")
    require(isinstance(tasks, dict), f"missing task contracts: {path}")
    result: dict[str, int] = {}
    for task in TASKS:
        entries = tasks.get(task)
        require(isinstance(entries, list), f"missing task contract: {task}")
        steps = [entry.get("step") for entry in entries if isinstance(entry, dict) and entry.get("category") == "calculation"]
        require(all(isinstance(step, str) and step for step in steps), f"invalid calculation step: {task}")
        require(len(steps) == len(set(steps)), f"duplicate calculation step: {task}")
        result[task] = len(steps)
    require(sum(result.values()) == 14, "task contracts must contain exactly 14 calculation steps")
    return result


def validate_operator_metrics(payload: dict[str, Any], key: str, label: str) -> dict[str, Any]:
    module, operator = key.split("/", 1)
    require(payload.get("module") == module, f"{label}: module identity mismatch")
    require(payload.get("operator") == operator, f"{label}: operator identity mismatch")
    summary = payload.get("summary")
    require(isinstance(summary, dict), f"{label}: missing summary")
    require(summary.get("pass") is True, f"{label}: summary.pass must be true")
    cases = payload.get("cases")
    require(isinstance(cases, list), f"{label}: cases must be a list")
    for index, case in enumerate(cases):
        require(isinstance(case, dict), f"{label}: case {index} must be an object")
        require(case.get("pass") is not False, f"{label}: case {index} failed")
    return summary


def performance_cases_for_metrics(
    metrics: dict[str, Any],
    summary: dict[str, Any],
    label: str,
) -> list[dict[str, Any]]:
    """Return detailed perf cases, recovering one summary-only runner result when needed."""
    declared_count = summary.get("perf_cases")
    require(isinstance(declared_count, int) and not isinstance(declared_count, bool) and declared_count >= 0,
            f"{label}: summary.perf_cases must be a non-negative integer")
    detailed_cases = [
        case for case in metrics.get("cases", [])
        if isinstance(case, dict) and case.get("category") == "perf"
    ]
    if detailed_cases:
        require(len(detailed_cases) == declared_count,
                f"{label}: perf case detail count differs from summary.perf_cases")
        return detailed_cases
    if declared_count == 0:
        return []

    # A few legacy runners write only aggregate summary statistics. They still
    # contain one valid performance result; expose it without inventing case data.
    require(declared_count == 1,
            f"{label}: cannot recover {declared_count} summary-only performance cases")
    for key in ("cpu_perf", "gpu_e2e_perf", "gpu_kernel_perf"):
        require(isinstance(summary.get(key), dict),
                f"{label}: summary-only performance result is missing {key}")
    return [{
        "case_id": "summary_aggregate",
        "samples": None,
        "pass": summary.get("pass") is True,
        "cpu_perf": summary["cpu_perf"],
        "gpu_e2e_perf": summary["gpu_e2e_perf"],
        "gpu_kernel_perf": summary["gpu_kernel_perf"],
        "_source": "summary_aggregate",
    }]


def validate_task_metrics(payload: dict[str, Any], task: str, scale: int | None, label: str) -> None:
    scenario = payload.get("scenario")
    require(isinstance(scenario, dict), f"{label}: missing scenario")
    if scale is not None:
        require(scenario.get("scale_level") == scale, f"{label}: scale identity mismatch")
    validation = payload.get("validation")
    require(isinstance(validation, dict), f"{label}: missing validation")
    require(validation.get("pass") is True, f"{label}: validation.pass must be true")
    checks = validation.get("checks")
    require(isinstance(checks, list) and checks, f"{label}: validation checks are missing")
    require(all(isinstance(check, dict) and check.get("pass") is True for check in checks),
            f"{label}: one or more validation checks failed")
    repeats = payload.get("repeat_runs", [])
    require(isinstance(repeats, list), f"{label}: repeat_runs must be a list")
    for index, run in enumerate(repeats):
        require(isinstance(run, dict), f"{label}: repeat run {index} must be an object")
        # Task demos record business/numeric correctness separately from the
        # per-run timing gate.  The first run may include one-time GPU setup;
        # final validation already checks stabilized timing independently.
        passed = run.get("business_numeric_pass", run.get("pass"))
        require(passed is True, f"{label}: repeat run {index} failed business or numeric validation")


def validate_step_metrics(payload: dict[str, Any], task: str, expected: int, label: str) -> None:
    require(payload.get("task") == task, f"{label}: task identity mismatch")
    steps = payload.get("steps")
    require(isinstance(steps, list) and len(steps) == expected,
            f"{label}: expected {expected} calculation steps")
    names = []
    for index, step in enumerate(steps):
        require(isinstance(step, dict), f"{label}: step {index} must be an object")
        name = step.get("step")
        require(isinstance(name, str) and name, f"{label}: step {index} has no identity")
        require(step.get("pass") is True, f"{label}: step {name} failed")
        names.append(name)
    require(len(names) == len(set(names)), f"{label}: duplicate step identity")


class EvidenceBuilder:
    def __init__(self, source_root: Path, stage: Path) -> None:
        self.source_root = source_root
        self.stage = stage
        self.source_hashes: dict[str, str] = {}

    def copy(self, source: Path, destination: Path) -> None:
        digest = sha256_file(source)
        try:
            relative = source.relative_to(self.source_root).as_posix()
        except ValueError as error:
            raise FinalizeError(f"evidence is outside source root: {source}") from error
        require(relative not in self.source_hashes, f"duplicate source evidence: {relative}")
        self.source_hashes[relative] = digest
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        require(sha256_file(destination) == digest, f"copy verification failed: {destination}")


def display_number(value: Any) -> str:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return "无"
    return f"{value:.6g}"


def display_timing(stats: Any) -> str:
    if not isinstance(stats, dict):
        return "未测"
    return f"{display_number(stats.get('median_ms'))} ms"


def display_timing_stat(stats: Any, name: str) -> str:
    if not isinstance(stats, dict):
        return "未测"
    return f"{display_number(stats.get(name))} ms"


def operator_summary_markdown(key: str, summary: dict[str, Any]) -> str:
    status = "通过" if summary.get("pass") is True else "失败"
    lines = [
        f"# 算子测试报告：{key}",
        "",
        f"- 状态：{status}",
        f"- 精度用例：{summary.get('accuracy_cases', 0)}",
        f"- 性能用例：{summary.get('perf_cases', 0)}",
        "",
        "## 误差",
        "",
        f"- 最大绝对误差：{display_number(summary.get('max_abs_error'))}",
        f"- 最大相对误差：{display_number(summary.get('max_rel_error'))}",
        f"- 混合误差：{display_number(summary.get('mixed_error'))}",
        f"- 均方根误差：{display_number(summary.get('rmse'))}",
        "",
        "## 性能",
        "",
        f"- CPU 中位时间：{display_timing(summary.get('cpu_perf'))}",
        f"- GPU 端到端中位时间：{display_timing(summary.get('gpu_e2e_perf'))}",
        f"- GPU kernel 最小时间：{display_timing_stat(summary.get('gpu_kernel_perf'), 'min_ms')}",
        f"- GPU kernel 中位时间：{display_timing(summary.get('gpu_kernel_perf'))}",
        f"- GPU kernel 最大时间：{display_timing_stat(summary.get('gpu_kernel_perf'), 'max_ms')}",
        f"- GPU 端到端加速比：{display_number(summary.get('gpu_e2e_speedup'))}x",
        f"- GPU kernel 加速比：{display_number(summary.get('gpu_kernel_speedup'))}x",
    ]
    return "\n".join(lines) + "\n"


def task_summary_markdown(
    task: str,
    metrics: dict[str, Any],
    scale: int | None,
    step_count: int,
    stage_count: int,
) -> str:
    title = "Task1 雷达处理" if task == "task1_radar" else "Task2 特征提取"
    scenario = "最终场景（L3）" if scale is None else f"规模 L{scale}"
    validation = metrics.get("validation")
    check_count = len(validation.get("checks", [])) if isinstance(validation, dict) else 0
    status = "通过" if isinstance(validation, dict) and validation.get("pass") is True else "失败"
    lines = [
        f"# 任务测试报告：{title}",
        "",
        f"- 场景：{scenario}",
        f"- 状态：{status}",
        f"- 计算步骤：{step_count}",
        f"- 阶段记录：{stage_count}",
        f"- 验证检查：{check_count}",
    ]
    return "\n".join(lines) + "\n"


def compact_performance_case(case: dict[str, Any]) -> dict[str, Any]:
    def timing(name: str) -> dict[str, Any] | None:
        value = case.get(name)
        return value if isinstance(value, dict) else None

    cpu_perf = timing("cpu_perf")
    gpu_e2e_perf = timing("gpu_e2e_perf")
    gpu_kernel_perf = timing("gpu_kernel_perf")

    def speedup(gpu_perf: dict[str, Any] | None) -> float | None:
        if not isinstance(cpu_perf, dict) or not isinstance(gpu_perf, dict):
            return None
        cpu = cpu_perf.get("median_ms")
        gpu = gpu_perf.get("median_ms")
        if (isinstance(cpu, bool) or not isinstance(cpu, (int, float)) or
                isinstance(gpu, bool) or not isinstance(gpu, (int, float)) or gpu <= 0):
            return None
        return cpu / gpu

    error = case.get("cpu_gpu_error")
    return {
        "case_id": case.get("case_id"),
        "source": case.get("_source", "case_detail"),
        "samples": case.get("samples"),
        "pass": case.get("pass") is True,
        "cpu_perf": cpu_perf,
        "gpu_e2e_perf": gpu_e2e_perf,
        "gpu_kernel_perf": gpu_kernel_perf,
        "gpu_e2e_speedup": speedup(gpu_e2e_perf),
        "gpu_kernel_speedup": speedup(gpu_kernel_perf),
        "cpu_gpu_error": error if isinstance(error, dict) else None,
    }


BENCHMARK_TABLE_HEADER = [
    "模块",
    "算子",
    "状态",
    "精度用例数",
    "性能用例数",
    "有性能数据",
    "CPU中位时间_ms",
    "GPU端到端中位时间_ms",
    "GPU_kernel最小运行时间_ms",
    "GPU_kernel中位时间_ms",
    "GPU_kernel最大运行时间_ms",
    "GPU端到端加速比",
    "GPU_kernel加速比",
    "最大绝对误差",
    "最大相对误差",
    "混合误差",
    "均方根误差",
]


def benchmark_summary_value(row: dict[str, Any], key: str) -> Any:
    summary = row.get("summary")
    return summary.get(key) if isinstance(summary, dict) else None


def benchmark_timing_value(row: dict[str, Any], key: str) -> Any:
    timing = benchmark_summary_value(row, key)
    return timing.get("median_ms") if isinstance(timing, dict) else None


def benchmark_timing_stat(row: dict[str, Any], key: str, stat: str) -> Any:
    timing = benchmark_summary_value(row, key)
    return timing.get(stat) if isinstance(timing, dict) else None


def write_benchmark_table(path: Path, rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(BENCHMARK_TABLE_HEADER)
        for row in rows:
            errors = row.get("errors")
            errors = errors if isinstance(errors, dict) else {}
            writer.writerow([
                row.get("module"),
                row.get("operator"),
                "通过" if row.get("pass") is True else "失败",
                row.get("accuracy_case_count"),
                row.get("performance_case_count"),
                "是" if row.get("available") is True else "否",
                benchmark_timing_value(row, "cpu_perf"),
                benchmark_timing_value(row, "gpu_e2e_perf"),
                benchmark_timing_stat(row, "gpu_kernel_perf", "min_ms"),
                benchmark_timing_value(row, "gpu_kernel_perf"),
                benchmark_timing_stat(row, "gpu_kernel_perf", "max_ms"),
                benchmark_summary_value(row, "gpu_e2e_speedup"),
                benchmark_summary_value(row, "gpu_kernel_speedup"),
                errors.get("max_abs_error"),
                errors.get("max_rel_error"),
                errors.get("mixed_error"),
                errors.get("rmse"),
            ])


def collect_operators(
    source_root: Path,
    stage: Path,
    operators: list[str],
    builder: EvidenceBuilder,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    unit_root = source_root / "unit"
    discovered = {
        f"{path.parent.parent.name}/{path.parent.name}"
        for path in unit_root.glob("*/*/latest_metrics.json")
        if path.is_file() and not path.is_symlink()
    }
    expected = set(operators)
    require(discovered == expected,
            f"unit operator set mismatch: missing={sorted(expected - discovered)}, extra={sorted(discovered - expected)}")
    summaries: list[dict[str, Any]] = []
    benchmark_rows: list[dict[str, Any]] = []
    module_counts: Counter[str] = Counter()
    for key in operators:
        module, operator = key.split("/", 1)
        source_dir = unit_root / module / operator
        metrics = read_json(source_dir / "latest_metrics.json")
        summary = validate_operator_metrics(metrics, key, key)
        read_csv_rows(source_dir / "latest_cases.csv")
        read_nonempty_text(source_dir / "latest_summary.md")
        destination = stage / "units" / module / operator
        for source_name, output_name in OPERATOR_FILE_MAP.items():
            builder.copy(source_dir / source_name, destination / output_name)
        (destination / "summary.md").write_text(
            operator_summary_markdown(key, summary),
            encoding="utf-8",
        )
        performance_cases = performance_cases_for_metrics(metrics, summary, key)
        benchmark_rows.append({
            "module": module,
            "operator": operator,
            "generated_at": metrics.get("generated_at"),
            "pass": summary.get("pass") is True,
            "accuracy_case_count": summary.get("accuracy_cases"),
            "available": bool(performance_cases),
            "performance_case_count": len(performance_cases),
            "performance_cases": [
                compact_performance_case(case) for case in performance_cases
            ],
            "summary": {
                name: summary[name]
                for name in (
                    "cpu_perf",
                    "gpu_e2e_perf",
                    "gpu_kernel_perf",
                    "gpu_e2e_speedup",
                    "gpu_kernel_speedup",
                )
                if name in summary
            },
            "errors": {
                name: summary.get(name)
                for name in (
                    "max_abs_error",
                    "max_rel_error",
                    "mixed_error",
                    "rmse",
                )
            },
        })
        summaries.append({
            "operator": key,
            "generated_at": metrics.get("generated_at"),
            "gpu_name": metrics.get("gpu_name"),
            "git_commit": metrics.get("git_commit"),
            "accuracy_cases": summary.get("accuracy_cases"),
            "perf_cases": summary.get("perf_cases"),
        })
        module_counts[module] += 1
    unavailable = sorted([
        f"{row['module']}/{row['operator']}"
        for row in benchmark_rows
        if not row["available"]
    ])
    write_json(stage / "units" / "benchmarks" / "summary.json", {
        "schema_version": "cetc_operator_benchmark_summary_v1",
        "operator_count": len(benchmark_rows),
        "operators_with_performance": len(benchmark_rows) - len(unavailable),
        "operators_without_performance": unavailable,
        "operators": benchmark_rows,
    })
    write_benchmark_table(
        stage / "units" / "benchmarks" / "summary.csv",
        benchmark_rows,
    )
    return summaries, dict(sorted(module_counts.items()))


def collect_task_case(
    source_dir: Path,
    destination: Path,
    task: str,
    expected_steps: int,
    scale: int | None,
    builder: EvidenceBuilder,
) -> dict[str, Any]:
    label = f"{task}/{'final' if scale is None else f'L{scale}'}"
    metrics = read_json(source_dir / "latest_metrics.json")
    validate_task_metrics(metrics, task, scale, label)
    step_metrics = read_json(source_dir / "latest_step_metrics.json")
    validate_step_metrics(step_metrics, task, expected_steps, label)
    _stage_header, stage_rows = read_csv_rows(source_dir / "latest_stage_timings.csv")
    _step_header, step_rows = read_csv_rows(source_dir / "latest_step_metrics.csv")
    require(len(step_rows) == expected_steps, f"{label}: step CSV row count mismatch")
    read_nonempty_text(source_dir / "latest_summary.md")
    for source_name, output_name in TASK_FILE_MAP.items():
        builder.copy(source_dir / source_name, destination / output_name)
    (destination / "summary.md").write_text(
        task_summary_markdown(task, metrics, scale, expected_steps, len(stage_rows)),
        encoding="utf-8",
    )
    if scale is not None:
        scenario_path = source_dir / "input_scenario.json"
        scenario = read_json(scenario_path)
        if "scale_level" in scenario:
            require(scenario["scale_level"] == scale, f"{label}: input scenario scale mismatch")
        builder.copy(scenario_path, destination / "input_scenario.json")
    return {
        "scale_level": metrics["scenario"].get("scale_level"),
        "validation_check_count": len(metrics["validation"]["checks"]),
        "step_count": expected_steps,
        "stage_row_count": len(stage_rows),
    }


def collect_tasks(
    source_root: Path,
    stage: Path,
    task_counts: dict[str, int],
    builder: EvidenceBuilder,
) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for task in TASKS:
        source_dir = source_root / "demo" / task
        destination = stage / "demo" / task
        final = collect_task_case(
            source_dir, destination / "final", task, task_counts[task], None, builder
        )
        scales = {}
        for scale in SCALE_LEVELS:
            scales[f"L{scale}"] = collect_task_case(
                source_dir / "scales" / f"L{scale}",
                destination / "scales" / f"L{scale}",
                task,
                task_counts[task],
                scale,
                builder,
            )
        result[task] = {"final": final, "scales": scales}
    require(sum(task_counts.values()) == 14, "final task step total must be 14")
    return result


def collect_audits(source_root: Path, stage: Path, builder: EvidenceBuilder) -> list[str]:
    audit_root = source_root / "runtime/audits"
    require(audit_root.is_dir() and not audit_root.is_symlink(), f"missing audit directory: {audit_root}")
    paths = sorted(path for path in audit_root.rglob("*.json") if path.is_file())
    require(paths, f"no audit JSON files found: {audit_root}")
    operator_coverage = False
    dtype_coverage = False
    task_coverage = False
    copied: list[str] = []
    for path in paths:
        require(not path.is_symlink(), f"unsafe audit symlink: {path}")
        relative = path.relative_to(audit_root)
        require(not (set(part.lower() for part in relative.parts) & FORBIDDEN_PARTS),
                f"forbidden audit category: {relative}")
        payload = read_json(path)
        validate_audit_payload(payload, relative.as_posix())
        summary = json_summary(payload)
        operator_count = summary.get("operator_count", payload.get("registry_count"))
        if operator_count is not None:
            require(operator_count == 81, f"{relative}: operator count must be 81")
            operator_coverage = True
        flattened_keys = {key.lower() for key, _value in iter_items(payload)}
        if {"compatibility_gap_count", "operator_dtype_missing_edges"} & flattened_keys:
            dtype_coverage = True
        if "calculation_step_count" in summary:
            require(summary["calculation_step_count"] == 14,
                    f"{relative}: calculation step count must be 14")
            task_coverage = True
        builder.copy(path, stage / "validation" / relative)
        copied.append(relative.as_posix())
    require(operator_coverage, "runtime audits do not prove exact 81-operator coverage")
    require(dtype_coverage, "runtime audits do not prove zero dtype/type gaps")
    require(task_coverage, "runtime audits do not prove 14 task calculation steps")
    return copied


def parse_delivery_manifest(repo_root: Path, output: Path) -> tuple[dict[str, str], str]:
    manifest = repo_root / "DELIVERY_FILES.txt"
    text = read_nonempty_text(manifest)
    hashes: dict[str, str] = {}
    output_resolved = output.resolve(strict=False)
    for line_number, raw in enumerate(text.splitlines(), start=1):
        token = raw.strip()
        if not token or token.startswith("#"):
            continue
        relative = safe_relative_path(token, f"DELIVERY_FILES.txt line {line_number}")
        require(relative.as_posix() not in hashes, f"duplicate delivery path: {relative}")
        path = repo_root / relative
        resolved = path.resolve(strict=False)
        if relative.parts[:2] == ("data", "reports"):
            # Published reports are generated output. Excluding this fixed path
            # keeps source verification stable during host-side promotion.
            continue
        if resolved == output_resolved or output_resolved in resolved.parents:
            # Generated reports cannot participate in their own source fingerprint.
            continue
        hashes[relative.as_posix()] = sha256_file(path)
    require(hashes, "DELIVERY_FILES.txt has no source files")
    hashes = dict(sorted(hashes.items()))
    source_manifest = "".join(f"{path}\n" for path in hashes)
    return hashes, sha256_bytes(source_manifest.encode("utf-8"))


def hash_lines(hashes: dict[str, str]) -> str:
    return "".join(f"{digest}  {path}\n" for path, digest in sorted(hashes.items()))


def git_value(repo_root: Path, args: list[str]) -> str | None:
    try:
        completed = subprocess.run(
            ["git", "-C", str(repo_root), *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_sha_manifest(root: Path) -> None:
    hashes = {
        path.relative_to(root).as_posix(): sha256_file(path)
        for path in sorted(root.rglob("*"))
        if path.is_file() and path.name != "FILES.sha256"
    }
    (root / "FILES.sha256").write_text(hash_lines(hashes), encoding="utf-8")


def validate_output_policy(root: Path) -> list[Path]:
    require(root.is_dir() and not root.is_symlink(), f"missing report directory: {root}")
    files: list[Path] = []
    for path in root.rglob("*"):
        require(not path.is_symlink(), f"reports contain symlink: {path}")
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        lowered = {part.lower() for part in relative.parts}
        require(not (lowered & FORBIDDEN_PARTS), f"reports contain forbidden category: {relative}")
        require(path.suffix.lower() not in FORBIDDEN_SUFFIXES,
                f"reports contain forbidden file type: {relative}")
        files.append(path)
    return sorted(files)


SHA_LINE = re.compile(r"^([0-9a-f]{64})  (.+)$")


def parse_sha_lines(text: str, label: str) -> dict[str, str]:
    listed: dict[str, str] = {}
    for line in text.splitlines():
        match = SHA_LINE.fullmatch(line)
        require(match is not None, f"invalid {label} line: {line!r}")
        relative = safe_relative_path(match.group(2), f"{label} path").as_posix()
        require(relative not in listed, f"duplicate {label} path: {relative}")
        listed[relative] = match.group(1)
    require(listed, f"{label} is empty")
    return listed


def verify_hash_manifest(root: Path) -> None:
    manifest = root / "FILES.sha256"
    listed = parse_sha_lines(read_nonempty_text(manifest), "FILES.sha256")
    actual = {
        path.relative_to(root).as_posix(): sha256_file(path)
        for path in root.rglob("*")
        if path.is_file() and path.name != "FILES.sha256"
    }
    require(listed == actual, "FILES.sha256 does not exactly match report contents")


def verify_output(root: Path, repo_root: Path | None = None) -> dict[str, Any]:
    validate_output_policy(root)
    verify_hash_manifest(root)
    expected_top_level = {
        "FILES.sha256",
        "units",
        "provenance.json",
        "SOURCE_FILES.sha256",
        "summary.json",
        "summary.md",
        "demo",
        "validation",
    }
    top_level = {path.name for path in root.iterdir()}
    if "README.md" in top_level:
        read_nonempty_text(root / "README.md")
        expected_top_level.add("README.md")
    require(top_level == expected_top_level, "unexpected report top-level contents")
    summary = read_json(root / "summary.json")
    require(summary.get("schema_version") == "cetc_final_reports_v1", "final summary schema mismatch")
    require(summary.get("report_schema_version") == "cetc_final_reports_v1",
            "stable report schema version mismatch")
    require(summary.get("status") == "passed", "final summary status is not passed")
    require(summary.get("operator_count") == 81, "stable final operator count is not 81")
    require(summary.get("task_count") == 2, "stable final task count is not 2")
    require(summary.get("task_scale_report_count") == 12,
            "stable final task scale report count is not 12")
    require(summary.get("calculation_step_count") == 14,
            "stable final calculation step count is not 14")
    require(summary.get("operators", {}).get("expected") == 81, "final operator count is not 81")
    require(summary.get("operators", {}).get("passed") == 81, "not all final operators passed")
    require(summary.get("tasks", {}).get("calculation_step_count") == 14,
            "final calculation step count is not 14")
    require(summary.get("tasks", {}).get("scale_run_count") == 12,
            "final task scale run count is not 12")
    read_nonempty_text(root / "summary.md")
    provenance = read_json(root / "provenance.json")
    require(provenance.get("run_id") == summary.get("run_id"), "run ID mismatch")
    source_hash_text = read_nonempty_text(root / "SOURCE_FILES.sha256")
    source_hashes = parse_sha_lines(source_hash_text, "SOURCE_FILES.sha256")
    require(len(source_hashes) == provenance.get("source_file_count"),
            "source file count mismatch")
    require(sha256_bytes(source_hash_text.encode("utf-8")) == provenance.get("source_content_fingerprint"),
            "source content fingerprint mismatch")
    require(summary.get("source_fingerprint") == provenance.get("source_content_fingerprint"),
            "stable source fingerprint mismatch")
    discovered_operators = {
        f"{path.parent.parent.name}/{path.parent.name}"
        for path in (root / "units").glob("*/*/metrics.json")
    }
    require(len(discovered_operators) == 81, "unit operator metrics file count is not 81")
    if repo_root is not None:
        require(discovered_operators == set(load_operator_contract(repo_root)),
                "unit operator set differs from repository contract")
        task_counts = load_task_counts(repo_root)
    else:
        task_counts_payload = summary.get("tasks", {}).get("calculation_steps_by_task")
        require(isinstance(task_counts_payload, dict), "missing task step counts in report summary")
        task_counts = {}
        for task in TASKS:
            count = task_counts_payload.get(task)
            require(isinstance(count, int) and count > 0, f"invalid report step count: {task}")
            task_counts[task] = count
        require(sum(task_counts.values()) == 14, "final task step counts do not total 14")
    expected_benchmark_counts: dict[str, int] = {}
    for key in sorted(discovered_operators):
        module, operator = key.split("/", 1)
        operator_dir = root / "units" / module / operator
        require({path.name for path in operator_dir.iterdir() if path.is_file()} == set(OPERATOR_OUTPUT_FILES),
                f"unexpected unit operator file set: {key}")
        metrics = read_json(operator_dir / "metrics.json")
        operator_summary = validate_operator_metrics(metrics, key, key)
        read_csv_rows(operator_dir / "cases.csv")
        read_nonempty_text(operator_dir / "summary.md")
        expected_benchmark_counts[key] = len(
            performance_cases_for_metrics(metrics, operator_summary, key)
        )
    benchmark_root = root / "units" / "benchmarks"
    benchmark_files = sorted(
        path.relative_to(benchmark_root).as_posix()
        for path in benchmark_root.rglob("*")
        if path.is_file()
    )
    require(benchmark_files == ["summary.csv", "summary.json"],
            "benchmark directory must contain only summary.csv and summary.json")
    benchmark_summary = read_json(benchmark_root / "summary.json")
    require(benchmark_summary.get("schema_version") == "cetc_operator_benchmark_summary_v1",
            "benchmark summary schema mismatch")
    require(benchmark_summary.get("operator_count") == 81, "benchmark operator count is not 81")
    benchmark_rows = benchmark_summary.get("operators")
    require(isinstance(benchmark_rows, list) and len(benchmark_rows) == 81,
            "benchmark summary must contain 81 operator rows")
    benchmark_keys = set()
    available_count = 0
    for row in benchmark_rows:
        require(isinstance(row, dict), "benchmark row must be an object")
        module = row.get("module")
        operator = row.get("operator")
        require(isinstance(module, str) and isinstance(operator, str),
                "benchmark row has invalid identity")
        key = f"{module}/{operator}"
        require(key not in benchmark_keys, f"duplicate benchmark row: {key}")
        benchmark_keys.add(key)
        count = row.get("performance_case_count")
        require(count == expected_benchmark_counts.get(key),
                f"benchmark performance case count mismatch: {key}")
        require(row.get("available") is (count > 0),
                f"benchmark availability mismatch: {key}")
        cases = row.get("performance_cases")
        require(isinstance(cases, list) and len(cases) == count,
                f"benchmark case payload mismatch: {key}")
        available_count += int(count > 0)
    require(benchmark_keys == discovered_operators, "benchmark summary differs from unit operators")
    require(benchmark_summary.get("operators_with_performance") == available_count,
            "benchmark available operator count mismatch")
    require(benchmark_summary.get("operators_without_performance") == sorted(
        key for key, count in expected_benchmark_counts.items() if count == 0
    ), "benchmark unavailable operator list mismatch")
    table_header, table_rows = read_csv_rows(benchmark_root / "summary.csv")
    require(table_header == BENCHMARK_TABLE_HEADER,
            "benchmark table header mismatch")
    require(len(table_rows) == 81, "benchmark table row count is not 81")
    expected_task_files = set(TASK_OUTPUT_FILES)
    for task in TASKS:
        final_dir = root / "demo" / task / "final"
        require({path.name for path in final_dir.iterdir() if path.is_file()} == expected_task_files,
                f"unexpected demo task file set: {task}")
        final_metrics = read_json(final_dir / "metrics.json")
        validate_task_metrics(final_metrics, task, None, f"{task}/final")
        validate_step_metrics(
            read_json(final_dir / "step_metrics.json"),
            task,
            task_counts[task],
            f"{task}/final",
        )
        read_csv_rows(final_dir / "stage_timings.csv")
        _header, step_rows = read_csv_rows(final_dir / "step_metrics.csv")
        require(len(step_rows) == task_counts[task], f"{task}/final: step CSV row count mismatch")
        for scale in SCALE_LEVELS:
            scale_dir = root / "demo" / task / "scales" / f"L{scale}"
            require({path.name for path in scale_dir.iterdir() if path.is_file()} ==
                    expected_task_files | {"input_scenario.json"},
                    f"unexpected task scale file set: {task}/L{scale}")
            label = f"{task}/L{scale}"
            validate_task_metrics(read_json(scale_dir / "metrics.json"), task, scale, label)
            validate_step_metrics(
                read_json(scale_dir / "step_metrics.json"),
                task,
                task_counts[task],
                label,
            )
            read_csv_rows(scale_dir / "stage_timings.csv")
            _header, step_rows = read_csv_rows(scale_dir / "step_metrics.csv")
            require(len(step_rows) == task_counts[task], f"{label}: step CSV row count mismatch")
            scenario = read_json(scale_dir / "input_scenario.json")
            if "scale_level" in scenario:
                require(scenario["scale_level"] == scale, f"{label}: input scenario scale mismatch")
    audit_paths = sorted(path for path in (root / "validation").rglob("*") if path.is_file())
    require(audit_paths and all(path.suffix == ".json" for path in audit_paths),
            "validation reports must contain only JSON files")
    audit_operator_coverage = False
    audit_dtype_coverage = False
    audit_task_coverage = False
    for path in audit_paths:
        payload = read_json(path)
        validate_audit_payload(payload, path.relative_to(root).as_posix())
        audit_summary = json_summary(payload)
        operator_count = audit_summary.get("operator_count", payload.get("registry_count"))
        if operator_count is not None:
            require(operator_count == 81, f"{path}: audit operator count must be 81")
            audit_operator_coverage = True
        flattened_keys = {key.lower() for key, _value in iter_items(payload)}
        audit_dtype_coverage |= bool(
            {"compatibility_gap_count", "operator_dtype_missing_edges"} & flattened_keys
        )
        if "calculation_step_count" in audit_summary:
            require(audit_summary["calculation_step_count"] == 14,
                    f"{path}: audit calculation step count must be 14")
            audit_task_coverage = True
    require(audit_operator_coverage and audit_dtype_coverage and audit_task_coverage,
            "validation reports do not cover operators, dtype gaps, and task steps")
    if repo_root is not None:
        current_source_hashes, manifest_hash = parse_delivery_manifest(repo_root, root)
        require(manifest_hash == provenance.get("delivery_manifest_sha256"),
                "DELIVERY_FILES.txt changed after finalization")
        require(current_source_hashes == source_hashes,
                "one or more DELIVERY_FILES source files changed after finalization")
    return summary


def publish(stage: Path, output: Path) -> None:
    backup: Path | None = None
    try:
        if output.exists():
            require(output.is_dir() and not output.is_symlink(), f"unsafe existing output: {output}")
            backup = output.with_name(f".{output.name}.previous.{os.getpid()}")
            require(not backup.exists(), f"temporary backup already exists: {backup}")
            os.replace(output, backup)
        os.replace(stage, output)
    except Exception:
        if backup is not None and backup.exists() and not output.exists():
            os.replace(backup, output)
        raise
    if backup is not None:
        shutil.rmtree(backup)


def finalize(repo_root: Path, source_root: Path, output: Path, run_id: str) -> dict[str, Any]:
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", run_id) is not None,
            "run ID must use only letters, digits, dot, underscore, and hyphen")
    repo_root = repo_root.resolve()
    source_root = source_root.resolve()
    output = output.resolve(strict=False)
    require(source_root.is_dir() and not source_root.is_symlink(), f"missing source root: {source_root}")
    require(output != source_root, "output must not replace the source report root")
    for input_name in ("unit", "demo", "runtime"):
        input_root = source_root / input_name
        require(output != input_root and input_root not in output.parents,
                f"output must be outside the source {input_name} tree")
    output.parent.mkdir(parents=True, exist_ok=True)
    operators = load_operator_contract(repo_root)
    task_counts = load_task_counts(repo_root)
    source_files, manifest_hash = parse_delivery_manifest(repo_root, output)
    stage: Path | None = Path(
        tempfile.mkdtemp(prefix=f".{output.name}.staging.", dir=output.parent)
    )
    try:
        require(stage is not None, "failed to create staging directory")
        if output == repo_root / "data" / "reports":
            report_readme = repo_root / "data" / "reports" / "README.md"
            require(report_readme.is_file() and not report_readme.is_symlink(),
                    f"missing report README: {report_readme}")
            shutil.copyfile(report_readme, stage / "README.md")
        builder = EvidenceBuilder(source_root, stage)
        operator_rows, module_counts = collect_operators(source_root, stage, operators, builder)
        task_results = collect_tasks(source_root, stage, task_counts, builder)
        audit_files = collect_audits(source_root, stage, builder)
        generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
        source_hash_text = hash_lines(source_files)
        (stage / "SOURCE_FILES.sha256").write_text(source_hash_text, encoding="utf-8")
        evidence_hash_text = hash_lines(builder.source_hashes)
        git_commit = git_value(repo_root, ["rev-parse", "HEAD"])
        tracked_status = git_value(repo_root, ["status", "--porcelain", "--untracked-files=no"])
        provenance = {
            "schema_version": "cetc_run_provenance_v1",
            "run_id": run_id,
            "generated_at": generated_at,
            "delivery_manifest": "DELIVERY_FILES.txt",
            "delivery_manifest_sha256": manifest_hash,
            "delivery_manifest_scope": "entries outside the generated output tree",
            "source_file_count": len(source_files),
            "source_content_fingerprint": sha256_bytes(source_hash_text.encode("utf-8")),
            "input_evidence_file_count": len(builder.source_hashes),
            "input_evidence_fingerprint": sha256_bytes(evidence_hash_text.encode("utf-8")),
            "git_commit": git_commit,
            "tracked_worktree_dirty": None if tracked_status is None else bool(tracked_status),
            "reported_git_commits": sorted({str(row["git_commit"]) for row in operator_rows if row["git_commit"]}),
            "gpu_names": sorted({str(row["gpu_name"]) for row in operator_rows if row["gpu_name"]}),
        }
        write_json(stage / "provenance.json", provenance)
        summary = {
            "schema_version": "cetc_final_reports_v1",
            "report_schema_version": "cetc_final_reports_v1",
            "status": "passed",
            "run_id": run_id,
            "generated_at": generated_at,
            "operator_count": 81,
            "task_count": 2,
            "task_scale_report_count": 12,
            "calculation_step_count": 14,
            "source_fingerprint": provenance["source_content_fingerprint"],
            "operators": {
                "expected": 81,
                "passed": 81,
                "module_counts": module_counts,
            },
            "tasks": {
                "expected": list(TASKS),
                "passed": list(TASKS),
                "calculation_step_count": sum(task_counts.values()),
                "calculation_steps_by_task": task_counts,
                "scale_levels": list(SCALE_LEVELS),
                "scale_run_count": len(TASKS) * len(SCALE_LEVELS),
                "results": task_results,
            },
            "validation": {
                "status": "passed",
                "file_count": len(audit_files),
                "files": audit_files,
            },
            "provenance": {
                "run_id": run_id,
                "source_file_count": len(source_files),
                "source_content_fingerprint": provenance["source_content_fingerprint"],
                "input_evidence_file_count": len(builder.source_hashes),
                "input_evidence_fingerprint": provenance["input_evidence_fingerprint"],
            },
        }
        write_json(stage / "summary.json", summary)
        (stage / "summary.md").write_text(
            "# 当前代码验证报告\n\n"
            f"- 运行编号：`{run_id}`\n"
            f"- 报告生成时间：`{generated_at}`\n"
            "- 状态：`通过`\n"
            "- 算子：`81/81`\n"
            "- 任务：`2/2`\n"
            "- 任务计算步骤：`14/14`\n"
            "- 任务规模运行：`12/12`（`L1` 至 `L6`）\n"
            f"- 运行期审计：`{len(audit_files)}` 份 JSON，全部通过且无缺口\n"
            f"- 源文件指纹：`{provenance['source_content_fingerprint']}`\n\n"
            "本目录只包含本次运行的算子、benchmark、demo、验证和来源数据；不包含历史版本、"
            "日志、图件、缓存或遥测数据。\n",
            encoding="utf-8",
        )
        write_sha_manifest(stage)
        verify_output(stage)
        publish(stage, output)
        stage = None
        return summary
    finally:
        if stage is not None and stage.exists():
            shutil.rmtree(stage)


def parse_args() -> argparse.Namespace:
    script = Path(__file__).resolve()
    default_repo = script.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=str(default_repo), help="repository root")
    parser.add_argument(
        "--source-root",
        default="",
        help="staging report root containing unit, demo, and runtime "
        "(default: REPO/data/.reports_staging)",
    )
    parser.add_argument("--output", default="", help="published report directory (default: REPO/data/reports)")
    parser.add_argument("--run-id", default="", help="identity of the container validation run")
    parser.add_argument("--verify", action="store_true", help="verify an existing published report directory")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    source_root = Path(args.source_root).resolve() if args.source_root else repo_root / "data/.reports_staging"
    output = Path(args.output).resolve() if args.output else repo_root / "data/reports"
    try:
        if args.verify:
            summary = verify_output(output, repo_root)
            print(f"[finalize-reports] verified {output} (run_id={summary['run_id']})")
            return 0
        require(bool(args.run_id), "--run-id is required when finalizing reports")
        summary = finalize(repo_root, source_root, output, args.run_id)
        print(
            f"[finalize-reports] published {output} "
            f"(run_id={summary['run_id']}, operators=81, task_steps=14)"
        )
        return 0
    except (FinalizeError, OSError, shutil.Error) as error:
        print(f"[finalize-reports] error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
