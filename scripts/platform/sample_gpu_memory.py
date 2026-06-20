#!/usr/bin/env python3
"""Sample ZQ500 GPU memory while a benchmark command is running.

The script intentionally treats dlsmi as a best-effort data source. If the
current SDK image does not support the queried fields, it writes an unavailable
summary instead of failing the surrounding benchmark.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import signal
import subprocess
import time
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class Sample:
    timestamp: str
    elapsed_s: float
    gpu_index: str
    used_mib: float
    total_mib: float
    free_mib: float
    util_percent: float | None


STOP = False


def request_stop(_signum: int, _frame: Any) -> None:
    global STOP
    STOP = True


def parse_number(value: str) -> float | None:
    text = value.strip()
    if not text:
        return None
    token = text.split()[0].replace("%", "")
    try:
        return float(token)
    except ValueError:
        return None


def run_dlsmi_query(fields: str) -> tuple[int, str, str]:
    cmd = ["dlsmi", f"--query-gpu={fields}", "--format=csv,noheader,nounits"]
    try:
        completed = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        return 127, "", str(exc)
    return completed.returncode, completed.stdout, completed.stderr


def query_gpu_samples(start_time: float) -> list[Sample]:
    rc, stdout, stderr = run_dlsmi_query("index,memory.used,memory.total,utilization.gpu")
    if rc != 0:
        raise RuntimeError(stderr.strip() or "dlsmi memory query failed")

    rows: list[Sample] = []
    now = time.time()
    timestamp = datetime.now(timezone.utc).isoformat()
    for row in csv.reader(stdout.splitlines()):
        if len(row) < 3:
            continue
        index = row[0].strip()
        used = parse_number(row[1])
        total = parse_number(row[2])
        util = parse_number(row[3]) if len(row) > 3 else None
        if used is None or total is None or total <= 0:
            continue
        rows.append(
            Sample(
                timestamp=timestamp,
                elapsed_s=now - start_time,
                gpu_index=index,
                used_mib=used,
                total_mib=total,
                free_mib=max(total - used, 0.0),
                util_percent=util,
            )
        )
    if not rows:
        raise RuntimeError("dlsmi memory query returned no parseable GPU rows")
    return rows


def finite_values(values: list[float]) -> list[float]:
    return [value for value in values if math.isfinite(value)]


def summarize(samples: list[Sample], available: bool, error: str = "") -> dict[str, Any]:
    if not available or not samples:
        return {
            "available": False,
            "error": error,
            "sample_count": len(samples),
        }

    used_values = finite_values([sample.used_mib for sample in samples])
    total_values = finite_values([sample.total_mib for sample in samples])
    free_values = finite_values([sample.free_mib for sample in samples])
    util_values = finite_values(
        [sample.util_percent for sample in samples if sample.util_percent is not None]
    )
    first_by_gpu: dict[str, Sample] = {}
    last_by_gpu: dict[str, Sample] = {}
    peak_by_gpu: dict[str, float] = {}
    for sample in samples:
        first_by_gpu.setdefault(sample.gpu_index, sample)
        last_by_gpu[sample.gpu_index] = sample
        peak_by_gpu[sample.gpu_index] = max(peak_by_gpu.get(sample.gpu_index, 0.0), sample.used_mib)

    deltas = {
        gpu: last_by_gpu[gpu].used_mib - first.used_mib
        for gpu, first in first_by_gpu.items()
        if gpu in last_by_gpu
    }
    return {
        "available": True,
        "sample_count": len(samples),
        "gpu_count": len(first_by_gpu),
        "started_at": samples[0].timestamp,
        "ended_at": samples[-1].timestamp,
        "duration_s": samples[-1].elapsed_s,
        "used_mib_min": min(used_values) if used_values else None,
        "used_mib_max": max(used_values) if used_values else None,
        "used_mib_avg": sum(used_values) / len(used_values) if used_values else None,
        "total_mib_max": max(total_values) if total_values else None,
        "free_mib_min": min(free_values) if free_values else None,
        "util_percent_max": max(util_values) if util_values else None,
        "util_percent_avg": sum(util_values) / len(util_values) if util_values else None,
        "used_mib_delta_by_gpu": deltas,
        "used_mib_peak_by_gpu": peak_by_gpu,
    }


def write_csv(path: Path, samples: list[Sample]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "timestamp",
                "elapsed_s",
                "gpu_index",
                "used_mib",
                "total_mib",
                "free_mib",
                "util_percent",
            ],
        )
        writer.writeheader()
        for sample in samples:
            writer.writerow(asdict(sample))


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sample dlsmi GPU memory into CSV and JSON.")
    parser.add_argument("--csv", required=True, help="Output sample CSV path")
    parser.add_argument("--json", required=True, help="Output summary JSON path")
    parser.add_argument("--interval", type=float, default=0.5, help="Poll interval in seconds")
    parser.add_argument(
        "--max-samples",
        type=int,
        default=0,
        help="Optional sample limit; 0 means run until SIGTERM/SIGINT",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.interval <= 0:
        raise SystemExit("--interval must be > 0")
    if args.max_samples < 0:
        raise SystemExit("--max-samples must be >= 0")

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)

    csv_path = Path(args.csv)
    json_path = Path(args.json)
    samples: list[Sample] = []
    first_error = ""
    start_time = time.time()

    while not STOP:
        try:
            samples.extend(query_gpu_samples(start_time))
        except Exception as exc:  # Best-effort monitor; record and keep benchmark alive.
            if not first_error:
                first_error = str(exc)
            if args.max_samples == 1:
                break
        if args.max_samples and len(samples) >= args.max_samples:
            break
        time.sleep(args.interval)

    available = bool(samples)
    write_csv(csv_path, samples)
    write_json(json_path, summarize(samples, available=available, error=first_error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
