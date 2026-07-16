#!/usr/bin/env python3

"""Select the V7.4 demo DeviceStorage cache mode from a focused A/B."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any


DEFAULT_CACHE = {
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS": "8",
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB": "512",
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB": "256",
}
EXPANDED_CACHE = {
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS": "16",
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB": "4096",
    "CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB": "3072",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select default or expanded DeviceStorage cache for the V7.4 demo."
    )
    parser.add_argument("--default-csv", required=True)
    parser.add_argument("--expanded-csv", required=True)
    parser.add_argument("--expanded-return-code", required=True, type=int)
    parser.add_argument("--default-telemetry", default="")
    parser.add_argument("--expanded-telemetry", default="")
    parser.add_argument("--expected-count", type=int, default=4)
    parser.add_argument("--minimum-aggregate-gain", type=float, default=0.02)
    parser.add_argument("--maximum-single-regression", type=float, default=0.05)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--output-tsv", required=True)
    return parser.parse_args()


def finite_float(value: Any) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite value: {value!r}")
    return parsed


def optional_finite_float(value: Any) -> float | None:
    if not str(value if value is not None else "").strip():
        return None
    try:
        return finite_float(value)
    except (TypeError, ValueError):
        return None


def optional_int(value: Any) -> int | None:
    parsed = optional_finite_float(value)
    return int(parsed) if parsed is not None else None


def load_rows(path: Path) -> dict[str, dict[str, Any]]:
    if not path.exists():
        return {}
    rows: dict[str, dict[str, Any]] = {}
    with path.open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            operator = f"{row.get('module', '')}/{row.get('operator', '')}"
            if operator == "/":
                continue
            rows[operator] = {
                "status": row.get("status", ""),
                "pass": str(row.get("pass", "")).lower() == "true",
                "gpu_e2e_median_ms": optional_finite_float(
                    row.get("gpu_e2e_median_ms")
                ),
                "device_cache_peak_cached_mib": optional_finite_float(
                    row.get("device_cache_peak_cached_mib")
                ),
                "device_cache_hits": optional_int(row.get("device_cache_hits")),
            }
    return rows


def load_telemetry(path_value: str) -> dict[str, Any]:
    if not path_value:
        return {"available": False}
    path = Path(path_value)
    if not path.exists():
        return {"available": False, "error": "missing"}
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {
        "available": bool(payload.get("available")),
        "sample_count": int(payload.get("sample_count", 0)),
        "used_mib_max": payload.get("used_mib_max"),
        "util_percent_max": payload.get("util_percent_max"),
    }


def rows_are_valid(rows: dict[str, dict[str, Any]], expected_count: int) -> bool:
    return (
        len(rows) == expected_count
        and all(
            row["status"] == "passed"
            and row["pass"]
            and isinstance(row["gpu_e2e_median_ms"], float)
            and row["gpu_e2e_median_ms"] > 0.0
            for row in rows.values()
        )
    )


def main() -> int:
    args = parse_args()
    default_rows = load_rows(Path(args.default_csv))
    expanded_rows = load_rows(Path(args.expanded_csv))
    default_valid = rows_are_valid(default_rows, args.expected_count)
    if not default_valid:
        payload = {
            "status": "failed",
            "selected_mode": "none",
            "reason": "default cache probe is incomplete or failed",
            "default_operator_count": len(default_rows),
        }
        output_json = Path(args.output_json)
        output_json.parent.mkdir(parents=True, exist_ok=True)
        output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        return 1

    same_operators = set(default_rows) == set(expanded_rows)
    expanded_valid = (
        args.expanded_return_code == 0
        and same_operators
        and rows_are_valid(expanded_rows, args.expected_count)
    )
    comparisons: list[dict[str, Any]] = []
    aggregate_gain = None
    maximum_regression = None
    if expanded_valid:
        default_sum = sum(
            row["gpu_e2e_median_ms"] for row in default_rows.values()
        )
        expanded_sum = sum(
            row["gpu_e2e_median_ms"] for row in expanded_rows.values()
        )
        aggregate_gain = 1.0 - expanded_sum / default_sum
        regressions = []
        for operator in sorted(default_rows):
            default_ms = default_rows[operator]["gpu_e2e_median_ms"]
            expanded_ms = expanded_rows[operator]["gpu_e2e_median_ms"]
            gain = 1.0 - expanded_ms / default_ms
            regressions.append(-gain)
            comparisons.append(
                {
                    "operator": operator,
                    "default_ms": default_ms,
                    "expanded_ms": expanded_ms,
                    "gain": gain,
                    "default_peak_cached_mib": default_rows[operator][
                        "device_cache_peak_cached_mib"
                    ],
                    "expanded_peak_cached_mib": expanded_rows[operator][
                        "device_cache_peak_cached_mib"
                    ],
                    "default_cache_hits": default_rows[operator]["device_cache_hits"],
                    "expanded_cache_hits": expanded_rows[operator]["device_cache_hits"],
                }
            )
        maximum_regression = max(regressions)

    select_expanded = bool(
        expanded_valid
        and aggregate_gain is not None
        and maximum_regression is not None
        and aggregate_gain >= args.minimum_aggregate_gain
        and maximum_regression <= args.maximum_single_regression
    )
    selected_mode = "expanded" if select_expanded else "default"
    if select_expanded:
        reason = "expanded cache passed the aggregate and per-operator gates"
    elif not expanded_valid:
        reason = "expanded cache probe failed or is incomplete"
    else:
        reason = "expanded cache did not meet the performance gates"

    payload = {
        "status": "passed",
        "selected_mode": selected_mode,
        "selected_environment": (
            EXPANDED_CACHE if select_expanded else DEFAULT_CACHE
        ),
        "reason": reason,
        "thresholds": {
            "minimum_aggregate_gain": args.minimum_aggregate_gain,
            "maximum_single_regression": args.maximum_single_regression,
        },
        "default_valid": default_valid,
        "expanded_valid": expanded_valid,
        "expanded_return_code": args.expanded_return_code,
        "aggregate_gain": aggregate_gain,
        "maximum_single_regression": maximum_regression,
        "comparisons": comparisons,
        "telemetry": {
            "default": load_telemetry(args.default_telemetry),
            "expanded": load_telemetry(args.expanded_telemetry),
        },
    }

    output_json = Path(args.output_json)
    output_tsv = Path(args.output_tsv)
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_tsv.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    with output_tsv.open("w", encoding="utf-8") as handle:
        handle.write("operator\tdefault_ms\texpanded_ms\tgain\n")
        for item in comparisons:
            handle.write(
                f"{item['operator']}\t{item['default_ms']:.9g}\t"
                f"{item['expanded_ms']:.9g}\t{item['gain']:.9g}\n"
            )
        handle.write(
            f"summary\t\t\t{aggregate_gain if aggregate_gain is not None else ''}\n"
        )
        handle.write(f"selected_mode\t{selected_mode}\t\t\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
