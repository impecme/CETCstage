#!/usr/bin/env python3
"""Print presentation-ready operator tiers and formal task-scale performance.

The script never times GPU work itself.  It reads the structured artifacts
created by ``test_operators.sh`` or ``unified_scale_benchmark.sh`` and prints
CPU/GPU medians plus the already computed CPU-over-GPU speedup.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import math
import os
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise RuntimeError(message)


def read_json(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"无法读取 JSON：{path} ({error})")
    if not isinstance(payload, dict):
        fail(f"JSON 根节点必须是对象：{path}")
    return payload


def finite(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) else None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--operators", action="store_true", help="打印 task27、extended28、core53 三层算子性能")
    parser.add_argument("--tasks", action="store_true", help="打印 Task1/Task2 性能")
    parser.add_argument(
        "--operator-source",
        choices=("published", "staging"),
        default="published",
        help="算子数据来源：published=data/reports，staging=本轮 test_operators 结果",
    )
    parser.add_argument(
        "--operator-set",
        default="all81",
        help="打印 tests/contracts/operator_sets.json 中的某个算子集合，默认 all81",
    )
    parser.add_argument(
        "--task-source",
        choices=("published", "staging"),
        default="published",
        help="任务数据来源：published=正式 L1-L6 报告，staging=本轮现场任务结果",
    )
    parser.add_argument(
        "--write-live-reports",
        action="store_true",
        help="将 core53 与两个现场任务的本轮快照写入既有 data/reports/units 与 data/reports/demo",
    )
    args = parser.parse_args()
    if not args.operators and not args.tasks:
        parser.error("至少指定 --operators 或 --tasks")
    if args.write_live_reports:
        if not (args.operators and args.tasks):
            parser.error("--write-live-reports requires both --operators and --tasks")
        if args.operator_set != "core53":
            parser.error("--write-live-reports requires --operator-set core53")
        if args.operator_source != "staging" or args.task_source != "staging":
            parser.error("--write-live-reports requires staging operator and task results")
    return args


def operator_set_config() -> tuple[dict[str, Any], list[str]]:
    payload = read_json(ROOT / "tests/contracts/operator_sets.json")
    sets = payload.get("sets")
    if not isinstance(sets, dict):
        fail("operator_sets.json 缺少 sets")

    all81_item = sets.get("all81")
    all81 = all81_item.get("operators") if isinstance(all81_item, dict) else None
    if not isinstance(all81, list) or len(all81) != 81 or len(set(all81)) != 81:
        fail("集合 all81 不是 81 个唯一有效算子")
    if not all(isinstance(value, str) for value in all81):
        fail("集合 all81 包含非字符串算子")
    return sets, all81


def resolve_operator_set(name: str, sets: dict[str, Any], all81: list[str], resolving: set[str] | None = None) -> list[str]:
    resolving = resolving or set()
    if name in resolving:
        fail(f"算子集合存在循环引用：{name}")
    item = sets.get(name)
    if not isinstance(item, dict):
        fail(f"未知算子集合：{name}")
    resolving.add(name)
    if "operators" in item:
        values = item.get("operators")
        if not isinstance(values, list) or not all(isinstance(value, str) for value in values):
            fail(f"集合 {name} 不是有效算子列表")
        resolved = list(values)
    else:
        include_sets = item.get("include_sets", [])
        exclude_sets = item.get("exclude_sets", [])
        if not isinstance(include_sets, list) or not isinstance(exclude_sets, list):
            fail(f"集合 {name} 的 include_sets/exclude_sets 无效")
        include: set[str] = set()
        for include_name in include_sets:
            if not isinstance(include_name, str):
                fail(f"集合 {name} 的 include_sets 包含非字符串")
            include.update(resolve_operator_set(include_name, sets, all81, resolving))
        exclude: set[str] = set()
        for exclude_name in exclude_sets:
            if not isinstance(exclude_name, str):
                fail(f"集合 {name} 的 exclude_sets 包含非字符串")
            exclude.update(resolve_operator_set(exclude_name, sets, all81, resolving))
        resolved = [key for key in all81 if key in include and key not in exclude]
    resolving.remove(name)

    expected = item.get("expected_count")
    if not isinstance(expected, int) or len(resolved) != expected or len(set(resolved)) != len(resolved):
        fail(f"集合 {name} 数量校验失败")
    unknown = sorted(set(resolved) - set(all81))
    if unknown:
        fail(f"集合 {name} 包含未知算子：{', '.join(unknown)}")
    return resolved


def operator_tiers() -> tuple[list[str], list[str], list[str], list[str], dict[str, Any]]:
    sets, all81 = operator_set_config()
    task27 = resolve_operator_set("task27", sets, all81)
    extended28 = resolve_operator_set("extended28", sets, all81)
    extended = set(extended28)
    core53 = [key for key in all81 if key not in extended]
    if len(core53) != 53 or not set(task27).issubset(core53):
        fail("集合关系无效：task27 必须属于 core53，core53=all81-extended28")
    return task27, extended28, core53, all81, sets


def published_operator_records() -> tuple[dict[str, dict[str, Any]], Path]:
    path = ROOT / "data/reports/units/benchmarks/summary.json"
    payload = read_json(path)
    operators = payload.get("operators")
    if not isinstance(operators, list):
        fail(f"缺少 operators：{path}")
    records: dict[str, dict[str, Any]] = {}
    for item in operators:
        if not isinstance(item, dict):
            fail(f"算子汇总中存在无效条目：{path}")
        module, operator = item.get("module"), item.get("operator")
        summary = item.get("summary")
        if not isinstance(module, str) or not isinstance(operator, str) or not isinstance(summary, dict):
            fail(f"算子汇总条目字段不完整：{path}")
        key = f"{module}/{operator}"
        if key in records:
            fail(f"算子汇总中存在重复键：{key}")
        records[key] = {"summary": summary, "pass": item.get("pass") is True}
    return records, path


def staging_operator_records(keys: list[str]) -> tuple[dict[str, dict[str, Any]], Path]:
    root = ROOT / "data/.reports_staging/unit"
    records: dict[str, dict[str, Any]] = {}
    for key in keys:
        module, operator = key.split("/", 1)
        path = root / module / operator / "latest_metrics.json"
        payload = read_json(path)
        summary = payload.get("summary")
        if not isinstance(summary, dict):
            fail(f"缺少 summary：{path}")
        records[key] = {"summary": summary, "pass": summary.get("pass") is True}
    return records, root


def format_number(value: float | None) -> str:
    return f"{value:.6f}" if value is not None else "N/A"


def operator_values(record: dict[str, Any]) -> tuple[float | None, float | None, float | None, str]:
    summary = record["summary"]
    cpu = finite(summary.get("cpu_perf", {}).get("median_ms"))
    gpu = finite(summary.get("gpu_e2e_perf", {}).get("median_ms"))
    speedup = finite(summary.get("gpu_e2e_speedup"))
    if speedup is None and cpu is not None and gpu is not None and gpu > 0:
        speedup = cpu / gpu
    if cpu is None or gpu is None or gpu <= 0 or speedup is None:
        state = "NO PERF"
    else:
        state = "PASS" if record["pass"] else "FAIL"
    return cpu, gpu, speedup, state


def print_operator_group(title: str, keys: list[str], records: dict[str, dict[str, Any]]) -> None:
    print("\n" + "=" * 112)
    print(f"{title}｜{len(keys)} 个公开算子")
    print(f"{'算子':<42} {'CPU median (ms)':>16} {'GPU E2E (ms)':>16} {'加速比 CPU/GPU':>18} {'状态':>10}")
    print("-" * 112)
    fast = slow = unavailable = failed = 0
    for key in keys:
        record = records.get(key)
        if record is None:
            fail(f"缺少算子结果：{key}")
        cpu, gpu, speedup, state = operator_values(record)
        if cpu is None or gpu is None or gpu <= 0 or speedup is None:
            unavailable += 1
        else:
            if speedup > 1.0:
                fast += 1
            else:
                slow += 1
        if not record["pass"]:
            failed += 1
        suffix = f"{speedup:.6f}×" if speedup is not None else "N/A"
        print(f"{key:<42} {format_number(cpu):>16} {format_number(gpu):>16} {suffix:>18} {state:>10}")
    print("-" * 112)
    print(f"统计：GPU 快于 CPU {fast}；不快于 CPU {slow}；无性能记录 {unavailable}；失败 {failed}。")


def print_operators(source: str, operator_set: str) -> None:
    task27, extended28, core53, all81, sets = operator_tiers()
    if len(set(all81)) != 81:
        fail("all81 集合不是 81 个唯一公开算子")
    selected = resolve_operator_set(operator_set, sets, all81)
    records, path = published_operator_records() if source == "published" else staging_operator_records(selected)
    missing = sorted(set(selected) - set(records))
    if missing:
        fail(f"性能结果未覆盖 {len(missing)} 个算子：{', '.join(missing)}")

    print(f"\n算子性能数据源：{path}")
    print("计时口径：各算子报告中的 perf case；CPU/GPU 均为 median，speedup=CPU/GPU。")
    if operator_set == "all81":
        print_operator_group("第一层 task27：任务直接依赖", task27, records)
        print_operator_group("第二层 extended28：扩展集合", extended28, records)
        print_operator_group("第三层 core53：原生基础集合（包含 task27，不与 task27 相加）", core53, records)
    elif operator_set == "core53":
        print_operator_group("赛题基础目录 core53（包含 task27）", selected, records)
    else:
        print_operator_group(f"演示集合 {operator_set}", selected, records)


def task_dimensions(task: str, scenario: dict[str, Any]) -> str:
    if task == "task1_radar":
        return f"{scenario.get('num_pulses')} × {scenario.get('samples_per_pulse')}"
    return f"{scenario.get('num_frames')} × {scenario.get('samples_per_frame')}"


def task_record(path: Path) -> tuple[dict[str, Any], int]:
    metrics = read_json(path)
    scenario = metrics.get("scenario")
    if not isinstance(scenario, dict) or scenario.get("unified_scale_protocol") is not True:
        fail(f"不是正式统一规模报告：{path}")
    level = scenario.get("scale_level")
    if not isinstance(level, int) or level not in range(1, 7):
        fail(f"缺少有效 scale_level：{path}")
    return metrics, level


def print_task_row(task: str, metrics: dict[str, Any], level: int) -> None:
    scenario = metrics.get("scenario")
    total = metrics.get("timings", {}).get("total", {})
    speed = metrics.get("speedup", {}).get("cpu_over_gpu")
    if not isinstance(scenario, dict) or not isinstance(total, dict):
        fail(f"任务报告字段不完整：{task}")
    cpu = finite(total.get("cpu_ms"))
    gpu = finite(total.get("gpu_ms"))
    speedup = finite(speed)
    if speedup is None and cpu is not None and gpu is not None and gpu > 0:
        speedup = cpu / gpu
    validation = "PASS" if metrics.get("validation", {}).get("pass") is True else "FAIL"
    suffix = f"{speedup:.6f}×" if speedup is not None else "N/A"
    print(
        f"L{level:<7} {task_dimensions(task, scenario):<18} {format_number(cpu):>16} "
        f"{format_number(gpu):>18} {suffix:>18} {validation:>8}"
    )


def print_tasks(source: str) -> None:
    print("\n" + "=" * 112)
    if source == "published":
        print("正式任务性能｜统一 L1-L6 协议：首轮 warm-up 排除，后续重复取 CPU/GPU total 中位数")
    else:
        print("现场任务性能｜本轮暂存运行：每个任务仅执行当前正式报告中加速比最高的一个规模")
    for task, title in (("task1_radar", "Task1 雷达检测"), ("task2_features", "Task2 特征融合与跟踪")):
        print("\n" + title)
        if source == "published":
            timing_header = f"{'CPU median (ms)':>16} {'GPU median (ms)':>18}"
        else:
            timing_header = f"{'CPU total (ms)':>16} {'GPU total (ms)':>18}"
        print(f"{'级别':<8} {'输入 shape':<18} {timing_header} {'加速比 CPU/GPU':>18} {'验证':>8}")
        print("-" * 96)
        if source == "published":
            for level in range(1, 7):
                path = ROOT / "data/reports/demo" / task / "scales" / f"L{level}" / "metrics.json"
                metrics, declared_level = task_record(path)
                if declared_level != level:
                    fail(f"规模目录与报告不一致：{path}")
                print_task_row(task, metrics, level)
        else:
            path = ROOT / "data/.reports_staging/demo" / task / "latest_metrics.json"
            metrics, level = task_record(path)
            print_task_row(task, metrics, level)


def live_task_row(task: str) -> dict[str, Any]:
    path = ROOT / "data/.reports_staging/demo" / task / "latest_metrics.json"
    metrics, level = task_record(path)
    scenario = metrics["scenario"]
    total = metrics.get("timings", {}).get("total", {})
    if not isinstance(total, dict):
        fail(f"任务报告缺少 total：{path}")
    cpu = finite(total.get("cpu_ms"))
    gpu = finite(total.get("gpu_ms"))
    speedup = finite(metrics.get("speedup", {}).get("cpu_over_gpu"))
    if speedup is None and cpu is not None and gpu is not None and gpu > 0:
        speedup = cpu / gpu
    return {
        "task": task,
        "scale_level": level,
        "input_shape": task_dimensions(task, scenario),
        "cpu_total_ms": cpu,
        "gpu_total_ms": gpu,
        "speedup_cpu_over_gpu": speedup,
        "validation": "PASS" if metrics.get("validation", {}).get("pass") is True else "FAIL",
        "source": str(path.relative_to(ROOT)),
    }


def atomic_write(path: Path, text: str) -> None:
    if not path.parent.is_dir() or path.parent.is_symlink():
        fail(f"现场报告父目录不可用：{path.parent}")
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    try:
        temporary.write_text(text, encoding="utf-8")
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def refresh_report_hash_manifest() -> None:
    root = ROOT / "data/reports"
    lines = []
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.name != "FILES.sha256":
            lines.append(f"{hash_file(path)}  {path.relative_to(root).as_posix()}\n")
    atomic_write(root / "FILES.sha256", "".join(lines))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, Any]]) -> None:
    from io import StringIO

    buffer = StringIO()
    writer = csv.DictWriter(buffer, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    atomic_write(path, buffer.getvalue())


def write_live_reports() -> None:
    task27, extended28, core53, all81, sets = operator_tiers()
    del task27, extended28, all81, sets
    records, source = staging_operator_records(core53)
    operator_rows = []
    for key in core53:
        record = records.get(key)
        if record is None:
            fail(f"现场算子结果缺失：{key}")
        cpu, gpu, speedup, state = operator_values(record)
        operator_rows.append(
            {
                "operator": key,
                "cpu_median_ms": cpu,
                "gpu_e2e_median_ms": gpu,
                "speedup_cpu_over_gpu": speedup,
                "status": state,
            }
        )

    task_rows = [live_task_row("task1_radar"), live_task_row("task2_features")]
    created_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()
    unit_root = ROOT / "data/reports/units"
    demo_root = ROOT / "data/reports/demo"
    unit_payload = {
        "schema": "cetc_live_demo_core53_v1",
        "generated_at": created_at,
        "scope": {
            "operator_set": "core53",
            "operator_count": len(core53),
            "source": str(source.relative_to(ROOT)),
            "note": "现场复核快照；不替代 units/benchmarks/summary.json。",
        },
        "operators": operator_rows,
    }
    demo_payload = {
        "schema": "cetc_live_demo_tasks_v1",
        "generated_at": created_at,
        "scope": {
            "task_count": len(task_rows),
            "selection": "每个任务仅执行当前正式 L1-L6 报告中加速比最高的规模。",
            "note": "现场复核快照；不替代正式 L1-L6 规模报告。",
        },
        "tasks": task_rows,
    }
    atomic_write(unit_root / "live_demo_core53.json", json.dumps(unit_payload, ensure_ascii=False, indent=2) + "\n")
    write_csv(
        unit_root / "live_demo_core53.csv",
        ["operator", "cpu_median_ms", "gpu_e2e_median_ms", "speedup_cpu_over_gpu", "status"],
        operator_rows,
    )
    atomic_write(demo_root / "live_demo_tasks.json", json.dumps(demo_payload, ensure_ascii=False, indent=2) + "\n")
    write_csv(
        demo_root / "live_demo_tasks.csv",
        ["task", "scale_level", "input_shape", "cpu_total_ms", "gpu_total_ms", "speedup_cpu_over_gpu", "validation", "source"],
        task_rows,
    )
    refresh_report_hash_manifest()
    print("\n现场快照已写入：data/reports/units/live_demo_core53.{json,csv}")
    print("现场快照已写入：data/reports/demo/live_demo_tasks.{json,csv}")


def main() -> int:
    args = parse_args()
    if args.operators:
        print_operators(args.operator_source, args.operator_set)
    if args.tasks:
        print_tasks(args.task_source)
    if args.write_live_reports:
        write_live_reports()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(f"[ppt-performance] error: {error}", file=sys.stderr)
        raise SystemExit(2)
