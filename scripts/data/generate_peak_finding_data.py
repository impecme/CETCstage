#!/usr/bin/env python3

import json
import shutil
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_ROOT = ROOT / "data/reference/unit/peak_finding"
GENERATED_ROOT = ROOT / "data/generated/unit/peak_finding"


def clean_root(root: Path):
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True, exist_ok=True)


def write_real_csv(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = np.asarray(values, dtype=np.float32).reshape(-1)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("value\n")
        for value in flat:
            handle.write(f"{value:.17g}\n")


def write_index_csv(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = np.asarray(values, dtype=np.int64).reshape(-1)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("value\n")
        for value in flat:
            handle.write(f"{int(value)}\n")


def dump_manifest(root: Path, accuracy_cases, perf_cases):
    root.mkdir(parents=True, exist_ok=True)
    payload = {}
    if accuracy_cases:
        payload["accuracy_cases"] = accuracy_cases
    if perf_cases:
        payload["perf_cases"] = perf_cases
    with (root / "manifest.json").open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def save_real_input(root: Path, rel_name: str, values) -> str:
    rel = f"input/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def save_index_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_index_csv(root / rel, values)
    return rel


def write_cases(op: str, accuracy_cases, perf_cases):
    dump_manifest(REFERENCE_ROOT / op, accuracy_cases, [])
    dump_manifest(GENERATED_ROOT / op, [], perf_cases)


def main():
    clean_root(REFERENCE_ROOT)
    clean_root(GENERATED_ROOT)

    write_cases(
        "argrelmax",
        [
            {
                "id": "max_1d",
                "comparator": "greater",
                "axis": 0,
                "order": 1,
                "mode": "clip",
                "shape": [7],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelmax", "max_1d__data", [1, 3, 2, 4, 3, 5, 1]),
                "expected_axis0_file": save_index_expected(REFERENCE_ROOT / "argrelmax", "max_1d__axis0", [1, 3, 5]),
            },
            {
                "id": "max_2d_axis1",
                "comparator": "greater",
                "axis": 1,
                "order": 1,
                "mode": "clip",
                "shape": [2, 5],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelmax", "max_2d_axis1__data", [1, 3, 2, 4, 3, 0, 1, 0, 2, 1]),
                "expected_axis0_file": save_index_expected(REFERENCE_ROOT / "argrelmax", "max_2d_axis1__axis0", [0, 0, 1, 1]),
                "expected_axis1_file": save_index_expected(REFERENCE_ROOT / "argrelmax", "max_2d_axis1__axis1", [1, 3, 1, 3]),
            },
            {
                "id": "plateau_none",
                "comparator": "greater",
                "axis": 0,
                "order": 1,
                "mode": "clip",
                "shape": [4],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelmax", "plateau_none__data", [1, 2, 2, 1]),
                "expected_axis0_file": save_index_expected(REFERENCE_ROOT / "argrelmax", "plateau_none__axis0", []),
            },
        ],
        [{"id": "perf_case", "shape": [128, 256], "axis": 1, "order": 2, "mode": "clip"}],
    )

    write_cases(
        "argrelmin",
        [
            {
                "id": "min_1d",
                "comparator": "less",
                "axis": 0,
                "order": 1,
                "mode": "clip",
                "shape": [5],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelmin", "min_1d__data", [3, 1, 2, 0, 1]),
                "expected_axis0_file": save_index_expected(REFERENCE_ROOT / "argrelmin", "min_1d__axis0", [1, 3]),
            },
            {
                "id": "min_wrap",
                "comparator": "less",
                "axis": 0,
                "order": 1,
                "mode": "wrap",
                "shape": [3],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelmin", "min_wrap__data", [2, 1, 2]),
                "expected_axis0_file": save_index_expected(REFERENCE_ROOT / "argrelmin", "min_wrap__axis0", [1]),
            },
        ],
        [{"id": "perf_case", "shape": [128, 256], "axis": 1, "order": 2, "mode": "clip"}],
    )

    write_cases(
        "argrelextrema",
        [
            {
                "id": "extrema_greater_order2",
                "comparator": "greater",
                "axis": 0,
                "order": 2,
                "mode": "clip",
                "shape": [9],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelextrema", "extrema_greater_order2__data", [0, 1, 3, 1, 0, 2, 5, 1, 0]),
                "expected_axis0_file": save_index_expected(REFERENCE_ROOT / "argrelextrema", "extrema_greater_order2__axis0", [2, 6]),
            },
            {
                "id": "extrema_less_2d",
                "comparator": "less",
                "axis": 1,
                "order": 1,
                "mode": "clip",
                "shape": [2, 5],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelextrema", "extrema_less_2d__data", [2, 1, 2, 0, 2, 5, 4, 5, 3, 5]),
                "expected_axis0_file": save_index_expected(REFERENCE_ROOT / "argrelextrema", "extrema_less_2d__axis0", [0, 0, 1, 1]),
                "expected_axis1_file": save_index_expected(REFERENCE_ROOT / "argrelextrema", "extrema_less_2d__axis1", [1, 3, 1, 3]),
            },
            {
                "id": "invalid_order",
                "comparator": "greater",
                "axis": 0,
                "order": 0,
                "mode": "clip",
                "shape": [3],
                "data_file": save_real_input(REFERENCE_ROOT / "argrelextrema", "invalid_order__data", [1, 0, 1]),
                "expect_invalid_argument": True,
            },
        ],
        [{"id": "perf_case", "shape": [128, 256], "axis": 1, "order": 2, "mode": "clip"}],
    )


if __name__ == "__main__":
    main()
