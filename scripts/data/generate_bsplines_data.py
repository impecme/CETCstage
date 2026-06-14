#!/usr/bin/env python3

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

import numpy as np


REFERENCE_ROOT = ROOT / "data/reference/unit/bsplines"
GENERATED_ROOT = ROOT / "data/generated/unit/bsplines"


def write_real_csv(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    array = np.asarray(values).reshape(-1)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("value\n")
        for value in array:
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


def clean_module_root(root: Path):
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True, exist_ok=True)


def cubic(values):
    x = np.asarray(values, dtype=np.float32)
    ax = np.abs(x)
    output = np.zeros_like(x)
    inner = ax < 1.0
    transition = (ax >= 1.0) & (ax < 2.0)
    output[inner] = 2.0 / 3.0 - 0.5 * ax[inner] * ax[inner] * (2.0 - ax[inner])
    output[transition] = ((2.0 - ax[transition]) ** 3) / 6.0
    return output


def quadratic(values):
    x = np.asarray(values, dtype=np.float32)
    ax = np.abs(x)
    output = np.zeros_like(x)
    inner = ax < 0.5
    transition = (ax >= 0.5) & (ax < 1.5)
    output[inner] = 0.75 - ax[inner] * ax[inner]
    output[transition] = 0.5 * (ax[transition] - 1.5) ** 2
    return output


def gauss_spline(values, order):
    x = np.asarray(values, dtype=np.float32)
    sigma_sq = (float(order) + 1.0) / 12.0
    coeff = 1.0 / np.sqrt(2.0 * np.pi * sigma_sq)
    return coeff * np.exp(-(x * x) / (2.0 * sigma_sq))


def save_real_input(root: Path, name: str, values) -> str:
    path = root / "input" / f"{name}.csv"
    write_real_csv(path, values)
    return f"input/{name}.csv"


def add_expected_output(case, root: Path, case_id: str, values):
    rel = f"expected/{case_id}.csv"
    write_real_csv(root / rel, values)
    case["expected_signal_file"] = rel
    case["expected_signal_shape"] = list(np.asarray(values).shape)


def build_case(case_id: str, x, atol: float, rtol: float, *, order=None):
    case = {
        "id": case_id,
        "x_shape": list(np.asarray(x).shape),
        "atol": atol,
        "rtol": rtol,
    }
    if order is not None:
        case["n"] = int(order)
    return case


DTYPES = [
    ("float32", np.float32, 5e-6, 5e-6),
]


def write_cubic_cases():
    ref_root = REFERENCE_ROOT / "cubic"
    gen_root = GENERATED_ROOT / "cubic"

    accuracy_specs = [
        (
            "boundary_vector",
            np.array([-2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5], dtype=np.float32),
        ),
        (
            "matrix_dense",
            np.linspace(-2.25, 2.25, 12, dtype=np.float32).reshape(3, 4),
        ),
    ]
    accuracy_cases = []
    for dtype_name, dtype, atol, rtol in DTYPES:
        for case_base, x in accuracy_specs:
            case_id = f"{case_base}_{dtype_name}"
            x_typed = np.asarray(x, dtype=dtype)
            case = build_case(case_id, x_typed, atol, rtol)
            case["x_file"] = save_real_input(ref_root, case_id, x_typed)
            add_expected_output(case, ref_root, case_id, cubic(x_typed).astype(dtype))
            accuracy_cases.append(case)

    perf_x = np.linspace(-4.0, 4.0, 16384, dtype=np.float32)
    perf_cases = [
        {
            **build_case("perf_large_vector_float32", perf_x, 5e-6, 5e-6),
            "x_start": float(perf_x[0]),
            "x_stop": float(perf_x[-1]),
            "x_count": int(perf_x.size),
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_quadratic_cases():
    ref_root = REFERENCE_ROOT / "quadratic"
    gen_root = GENERATED_ROOT / "quadratic"

    accuracy_specs = [
        (
            "boundary_vector",
            np.array([-2.0, -1.5, -1.0, -0.5, -0.25, 0.0, 0.25, 0.5, 1.0, 1.5, 2.0], dtype=np.float32),
        ),
        (
            "matrix_dense",
            np.linspace(-2.0, 2.0, 15, dtype=np.float32).reshape(3, 5),
        ),
    ]
    accuracy_cases = []
    for dtype_name, dtype, atol, rtol in DTYPES:
        for case_base, x in accuracy_specs:
            case_id = f"{case_base}_{dtype_name}"
            x_typed = np.asarray(x, dtype=dtype)
            case = build_case(case_id, x_typed, atol, rtol)
            case["x_file"] = save_real_input(ref_root, case_id, x_typed)
            add_expected_output(case, ref_root, case_id, quadratic(x_typed).astype(dtype))
            accuracy_cases.append(case)

    perf_x = np.linspace(-3.5, 3.5, 16384, dtype=np.float32)
    perf_cases = [
        {
            **build_case("perf_large_vector_float32", perf_x, 5e-6, 5e-6),
            "x_start": float(perf_x[0]),
            "x_stop": float(perf_x[-1]),
            "x_count": int(perf_x.size),
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_gauss_spline_cases():
    ref_root = REFERENCE_ROOT / "gauss_spline"
    gen_root = GENERATED_ROOT / "gauss_spline"

    accuracy_specs = [
        (
            "order3_vector",
            np.linspace(-4.0, 4.0, 17, dtype=np.float32),
            3,
        ),
        (
            "order6_matrix",
            np.linspace(-6.0, 6.0, 18, dtype=np.float32).reshape(3, 6),
            6,
        ),
        (
            "invalid_order",
            np.array([0.0], dtype=np.float32),
            -1,
        ),
    ]
    accuracy_cases = []
    for dtype_name, dtype, _, _ in DTYPES:
        atol = 1e-5 if dtype_name == "float32" else 1e-11
        rtol = 1e-5 if dtype_name == "float32" else 1e-11
        for case_base, x, order in accuracy_specs:
            case_id = f"{case_base}_{dtype_name}"
            x_typed = np.asarray(x, dtype=dtype)
            case = build_case(case_id, x_typed, atol, rtol, order=order)
            case["x_file"] = save_real_input(ref_root, case_id, x_typed)
            if order < 0:
                case["expect_invalid_argument"] = True
            else:
                add_expected_output(
                    case,
                    ref_root,
                    case_id,
                    gauss_spline(x_typed, order).astype(dtype),
                )
            accuracy_cases.append(case)

    perf_x = np.linspace(-8.0, 8.0, 32768, dtype=np.float32)
    perf_cases = [
        {
            **build_case("perf_order5_large_vector_float32", perf_x, 1e-5, 1e-5, order=5),
            "x_start": float(perf_x[0]),
            "x_stop": float(perf_x[-1]),
            "x_count": int(perf_x.size),
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def main():
    clean_module_root(REFERENCE_ROOT)
    clean_module_root(GENERATED_ROOT)
    write_cubic_cases()
    write_quadratic_cases()
    write_gauss_spline_cases()


if __name__ == "__main__":
    main()
