#!/usr/bin/env python3

import json
import math
import shutil
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_ROOT = ROOT / "data/reference/unit/demod"
GENERATED_ROOT = ROOT / "data/generated/unit/demod"


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


def write_complex_csv(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    flat = np.asarray(values, dtype=np.complex64).reshape(-1)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("real,imag\n")
        for value in flat:
            handle.write(f"{value.real:.17g},{value.imag:.17g}\n")


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


def save_complex_input(root: Path, rel_name: str, values) -> str:
    rel = f"input/{rel_name}.csv"
    write_complex_csv(root / rel, values)
    return rel


def save_real_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def cx(angle):
    return complex(math.cos(angle), math.sin(angle))


def main():
    clean_root(REFERENCE_ROOT)
    clean_root(GENERATED_ROOT)

    ref_root = REFERENCE_ROOT / "fm_demod"
    gen_root = GENERATED_ROOT / "fm_demod"

    accuracy_cases = [
        {
            "id": "constant_step",
            "axis": -1,
            "input_file": save_complex_input(ref_root, "constant_step__signal", [cx(0.0), cx(0.5), cx(1.0), cx(1.5)]),
            "expected_signal_file": save_real_expected(ref_root, "constant_step__signal", [0.5, 0.5, 0.5]),
            "atol": 1e-6,
            "rtol": 1e-6,
        },
        {
            "id": "unwrap_step",
            "axis": -1,
            "input_file": save_complex_input(ref_root, "unwrap_step__signal", [cx(2.8), cx(3.1), cx(-3.0), cx(-2.7)]),
            "expected_signal_file": save_real_expected(ref_root, "unwrap_step__signal", [0.29999995, 0.18318558, 0.29999995]),
            "atol": 1e-6,
            "rtol": 1e-6,
        },
        {
            "id": "matrix_axis0",
            "axis": 0,
            "shape": [3, 2],
            "input_file": save_complex_input(
                ref_root,
                "matrix_axis0__signal",
                [cx(0.0), cx(1.0), cx(0.5), cx(1.5), cx(1.0), cx(2.0)],
            ),
            "expected_signal_file": save_real_expected(ref_root, "matrix_axis0__signal", [0.5, 0.5, 0.5, 0.5]),
            "expected_shape": [2, 2],
            "atol": 1e-6,
            "rtol": 1e-6,
        },
        {
            "id": "invalid_axis",
            "axis": 3,
            "input_file": save_complex_input(ref_root, "invalid_axis__signal", [1.0 + 0.0j, 0.0 + 1.0j]),
            "expect_invalid_argument": True,
        },
    ]

    perf_cases = [
        {
            "id": "perf_case",
            "shape": [64, 512],
            "axis": -1,
            "phase_step": 0.01,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


if __name__ == "__main__":
    main()
