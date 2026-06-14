#!/usr/bin/env python3

import json
import shutil
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_ROOT = ROOT / "data/reference/unit/correlate"
GENERATED_ROOT = ROOT / "data/generated/unit/correlate"


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


def save_complex_input(root: Path, rel_name: str, values) -> str:
    rel = f"input/{rel_name}.csv"
    write_complex_csv(root / rel, values)
    return rel


def save_real_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def save_complex_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_complex_csv(root / rel, values)
    return rel


def save_index_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_index_csv(root / rel, values)
    return rel


def write_correlate_cases():
    ref_root = REFERENCE_ROOT / "correlate"
    gen_root = GENERATED_ROOT / "correlate"

    accuracy_cases = [
        {
            "id": "real_full_direct",
            "mode": "full",
            "method": "direct",
            "is_complex": False,
            "shape1": [3],
            "shape2": [3],
            "in1_file": save_real_input(ref_root, "real_full_direct__in1", [1.0, 2.0, 3.0]),
            "in2_file": save_real_input(ref_root, "real_full_direct__in2", [0.0, 1.0, 0.5]),
            "expected_values_file": save_real_expected(ref_root, "real_full_direct__values", [0.5, 2.0, 3.5, 3.0, 0.0]),
            "atol": 1e-6,
            "rtol": 1e-6,
        },
        {
            "id": "complex_full_fft",
            "mode": "full",
            "method": "fft",
            "is_complex": True,
            "shape1": [2],
            "shape2": [2],
            "in1_file": save_complex_input(ref_root, "complex_full_fft__in1", [1.0 + 1.0j, 2.0 - 1.0j]),
            "in2_file": save_complex_input(ref_root, "complex_full_fft__in2", [1.0 - 2.0j, -1.0 + 0.5j]),
            "expected_values_file": save_complex_expected(
                ref_root,
                "complex_full_fft__values",
                [-0.5 - 1.5j, -3.5 + 3.0j, 4.0 + 3.0j],
            ),
            "atol": 1e-6,
            "rtol": 1e-6,
        },
    ]

    perf_cases = [
        {
            "id": "perf_real_auto",
            "mode": "same",
            "method": "auto",
            "shape1": [2048],
            "shape2": [257],
            "in1_start": 0.0,
            "in1_step": 0.01,
            "in2_start": 0.0,
            "in2_step": 0.02,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_correlate2d_cases():
    ref_root = REFERENCE_ROOT / "correlate2d"
    gen_root = GENERATED_ROOT / "correlate2d"

    accuracy_cases = [
        {
            "id": "real_full_wrap",
            "mode": "full",
            "boundary": "wrap",
            "is_complex": False,
            "shape1": [2, 2],
            "shape2": [2, 2],
            "in1_file": save_real_input(ref_root, "real_full_wrap__in1", [1.0, 2.0, 3.0, 4.0]),
            "in2_file": save_real_input(ref_root, "real_full_wrap__in2", [0.0, 1.0, 2.0, 1.0]),
            "expected_values_file": save_real_expected(
                ref_root,
                "real_full_wrap__values",
                [8.0, 8.0, 8.0, 12.0, 12.0, 12.0, 8.0, 8.0, 8.0],
            ),
            "atol": 1e-6,
            "rtol": 1e-6,
        },
        {
            "id": "complex_same_fill",
            "mode": "same",
            "boundary": "fill",
            "is_complex": True,
            "shape1": [2, 2],
            "shape2": [2, 2],
            "in1_file": save_complex_input(
                ref_root,
                "complex_same_fill__in1",
                [1.0 + 1.0j, 2.0 - 1.0j, 0.5 + 0.25j, -1.0 + 2.0j],
            ),
            "in2_file": save_complex_input(
                ref_root,
                "complex_same_fill__in2",
                [1.0 - 1.0j, 0.5 + 0.5j, -0.5 + 1.0j, 2.0 - 0.25j],
            ),
            "expected_values_file": save_complex_expected(
                ref_root,
                "complex_same_fill__values",
                [1.75 + 2.25j, 4.75 - 3.0j, 1.9375 + 0.625j, -2.0 + 3.625j],
            ),
            "atol": 1e-6,
            "rtol": 1e-6,
        },
    ]

    perf_cases = [
        {
            "id": "perf_real2d_same",
            "mode": "same",
            "boundary": "fill",
            "shape1": [64, 64],
            "shape2": [7, 7],
            "in1_step": 0.03,
            "in2_step": 0.05,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_lag_cases():
    ref_root = REFERENCE_ROOT / "correlation_lags"
    gen_root = GENERATED_ROOT / "correlation_lags"

    accuracy_cases = [
        {
            "id": "full_case",
            "in1_len": 5,
            "in2_len": 3,
            "mode": "full",
            "expected_lags_file": save_index_expected(ref_root, "full_case__lags", [-2, -1, 0, 1, 2, 3, 4]),
        },
        {
            "id": "same_case",
            "in1_len": 5,
            "in2_len": 4,
            "mode": "same",
            "expected_lags_file": save_index_expected(ref_root, "same_case__lags", [-2, -1, 0, 1, 2]),
        },
        {
            "id": "valid_case",
            "in1_len": 2,
            "in2_len": 5,
            "mode": "valid",
            "expected_lags_file": save_index_expected(ref_root, "valid_case__lags", [-3, -2, -1, 0]),
        },
    ]

    perf_cases = [
        {"id": "perf_lags", "in1_len": 4096, "in2_len": 1025, "mode": "full"}
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def main():
    clean_root(REFERENCE_ROOT)
    clean_root(GENERATED_ROOT)
    write_correlate_cases()
    write_correlate2d_cases()
    write_lag_cases()


if __name__ == "__main__":
    main()
