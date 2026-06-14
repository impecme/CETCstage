#!/usr/bin/env python3

import json
import shutil
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_ROOT = ROOT / "data/reference/unit/estimation"
GENERATED_ROOT = ROOT / "data/generated/unit/estimation"


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


def save_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def main():
    clean_root(REFERENCE_ROOT)
    clean_root(GENERATED_ROOT)

    ref_root = REFERENCE_ROOT / "kalman_filter"
    gen_root = GENERATED_ROOT / "kalman_filter"

    accuracy_cases = [
        {
            "id": "defaults",
            "scenario": "defaults",
            "dim_x": 2,
            "dim_z": 1,
            "dim_u": 0,
            "points": 1,
            "dtype": "float32",
            "expected_x_file": save_expected(ref_root, "defaults__x", [0.0, 0.0]),
            "expected_P_file": save_expected(ref_root, "defaults__P", [1.0, 0.0, 0.0, 1.0]),
        },
        {
            "id": "predict",
            "scenario": "predict",
            "dim_x": 2,
            "dim_z": 1,
            "dim_u": 0,
            "points": 1,
            "dtype": "float32",
            "expected_x_file": save_expected(ref_root, "predict__x", [1.0, 1.0]),
            "expected_P_file": save_expected(ref_root, "predict__P", [2.1, 1.0, 1.0, 1.2]),
        },
        {
            "id": "predict_control",
            "scenario": "predict_control",
            "dim_x": 2,
            "dim_z": 1,
            "dim_u": 1,
            "points": 1,
            "dtype": "float32",
            "expected_x_file": save_expected(ref_root, "predict_control__x", [4.0, 3.5]),
            "expected_P_file": save_expected(ref_root, "predict_control__P", [1.0, 0.0, 0.0, 1.0]),
        },
        {
            "id": "update",
            "scenario": "update",
            "dim_x": 2,
            "dim_z": 1,
            "dim_u": 0,
            "points": 1,
            "dtype": "float32",
            "expected_x_file": save_expected(ref_root, "update__x", [1.16153848, 1.07692313]),
            "expected_P_file": save_expected(ref_root, "update__P", [0.40384614, 0.19230771, 0.19230771, 0.81538463]),
        },
        {
            "id": "invalid_dtype",
            "scenario": "invalid_dtype",
            "dim_x": 2,
            "dim_z": 1,
            "dim_u": 0,
            "points": 1,
            "dtype": "float32",
            "expect_invalid_argument": True,
        },
        {
            "id": "invalid_control_shape",
            "scenario": "invalid_control_shape",
            "dim_x": 2,
            "dim_z": 1,
            "dim_u": 1,
            "points": 1,
            "dtype": "float32",
            "expect_invalid_argument": True,
        },
        {
            "id": "invalid_measurement_shape",
            "scenario": "invalid_measurement_shape",
            "dim_x": 2,
            "dim_z": 1,
            "dim_u": 0,
            "points": 1,
            "dtype": "float32",
            "expect_invalid_argument": True,
        },
    ]

    perf_cases = [
        {
            "id": "perf_cycle",
            "dim_x": 4,
            "dim_z": 2,
            "dim_u": 2,
            "points": 64,
            "dtype": "float32",
            "control_fill": 0.25,
            "measurement_fill": 0.5,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


if __name__ == "__main__":
    main()
