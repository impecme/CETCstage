#!/usr/bin/env python3

import json
import shutil
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_ROOT = ROOT / "data/reference/unit/wavelets"
GENERATED_ROOT = ROOT / "data/generated/unit/wavelets"


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


def save_real_input(root: Path, rel_name: str, values) -> str:
    rel = f"input/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def save_real_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def save_complex_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_complex_csv(root / rel, values)
    return rel


def qmf_np(hk):
    hk = np.asarray(hk, dtype=np.float32)
    return hk[::-1] * np.where(np.arange(hk.size) % 2 == 0, 1.0, -1.0)


def morlet_np(points, w=5.0, s=1.0, complete=True):
    if points == 0:
        return np.asarray([], dtype=np.complex64)
    if points == 1:
        x = np.asarray([0.0], dtype=np.float32)
    else:
        x = np.linspace(-s * 2.0 * np.pi, s * 2.0 * np.pi, points, dtype=np.float32)
    base = np.exp(1j * w * x)
    if complete:
        base = base - np.exp(-0.5 * w * w)
    return (np.pi ** -0.25) * base * np.exp(-0.5 * x * x)


def ricker_np(points, a):
    if points == 0:
        return np.asarray([], dtype=np.float32)
    vec = np.arange(points, dtype=np.float32) - (points - 1.0) * 0.5
    xsq = vec * vec
    amplitude = 2.0 / (np.sqrt(3.0 * a) * np.pi ** 0.25)
    return amplitude * (1.0 - xsq / (a * a)) * np.exp(-xsq / (2.0 * a * a))


def morlet2_np(points, s, w=5.0):
    if points == 0:
        return np.asarray([], dtype=np.complex64)
    x = (np.arange(points, dtype=np.float32) - (points - 1.0) * 0.5) / s
    return np.sqrt(1.0 / s) * (np.pi ** -0.25) * np.exp(1j * w * x) * np.exp(-0.5 * x * x)


def same_convolve(data, kernel):
    data = np.asarray(data, dtype=np.float32)
    kernel = np.asarray(kernel, dtype=np.complex64)
    if data.size == 0:
        return np.asarray([], dtype=np.complex64)
    start = (kernel.size - 1) // 2
    out = np.zeros(data.size, dtype=np.complex64)
    for i in range(data.size):
        accum = 0.0 + 0.0j
        for k in range(kernel.size):
            x_idx = i + start - k
            if 0 <= x_idx < data.size:
                accum += data[x_idx] * kernel[k]
        out[i] = accum
    return out


def cwt_np(data, wavelet, widths):
    data = np.asarray(data, dtype=np.float32)
    widths = np.asarray(widths, dtype=np.float32)
    if widths.size == 0:
        raise ValueError("widths must not be empty")
    rows = []
    for width in widths:
        integral_width = int(width)
        if width <= 0.0 or integral_width <= 0:
            raise ValueError("widths must be > 0 and produce positive integral widths")
        length = min(10 * integral_width, data.size)
        if wavelet == "ricker":
            wav = ricker_np(length, integral_width)
        elif wavelet == "morlet2":
            wav = morlet2_np(length, integral_width, 5.0)
        else:
            raise ValueError("wavelet must be ricker or morlet2")
        kernel = np.conj(wav)[::-1]
        rows.append(same_convolve(data, kernel))
    return np.asarray(rows, dtype=np.complex64)


def write_qmf_cases():
    ref_root = REFERENCE_ROOT / "qmf"
    gen_root = GENERATED_ROOT / "qmf"

    accuracy_specs = [
        ("even_taps", np.array([0.125, 0.375, 0.375, 0.125], dtype=np.float32), 1e-12, 1e-12),
        ("odd_taps", np.array([1.0, -2.0, 3.0, -4.0, 5.0], dtype=np.float32), 1e-12, 1e-12),
        ("empty_taps", np.asarray([], dtype=np.float32), 1e-12, 1e-12),
    ]
    accuracy_cases = []
    for case_id, hk, atol, rtol in accuracy_specs:
        case = {
            "id": case_id,
            "atol": atol,
            "rtol": rtol,
            "hk_file": save_real_input(ref_root, f"{case_id}__hk", hk),
            "expected_signal_file": save_real_expected(ref_root, f"{case_id}__signal", qmf_np(hk)),
        }
        accuracy_cases.append(case)

    perf_cases = [
        {
            "id": "perf_large_vector",
            "atol": 1e-12,
            "rtol": 1e-12,
            "hk_start": -1.0,
            "hk_stop": 1.0,
            "hk_count": 16384,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_morlet_cases():
    ref_root = REFERENCE_ROOT / "morlet"
    gen_root = GENERATED_ROOT / "morlet"

    accuracy_specs = [
        ("complete_default", 16, 5.0, 1.0, True, 1e-12, 1e-12, False),
        ("standard_custom", 17, 4.5, 1.75, False, 1e-12, 1e-12, False),
        ("point_center", 1, 3.0, 2.0, True, 1e-12, 1e-12, False),
        ("zero_points", 0, 5.0, 1.0, True, 1e-12, 1e-12, False),
        ("invalid_s", 16, 5.0, 0.0, True, 1e-12, 1e-12, True),
    ]
    accuracy_cases = []
    for case_id, points, w, s, complete, atol, rtol, invalid in accuracy_specs:
        case = {
            "id": case_id,
            "points": points,
            "w": w,
            "s": s,
            "complete": complete,
            "atol": atol,
            "rtol": rtol,
        }
        if invalid:
            case["expect_invalid_argument"] = True
        else:
            case["expected_signal_file"] = save_complex_expected(
                ref_root,
                f"{case_id}__signal",
                morlet_np(points, w, s, complete),
            )
        accuracy_cases.append(case)

    perf_cases = [
        {
            "id": "perf_complete_large",
            "points": 16384,
            "w": 5.0,
            "s": 1.0,
            "complete": True,
            "atol": 1e-12,
            "rtol": 1e-12,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_ricker_cases():
    ref_root = REFERENCE_ROOT / "ricker"
    gen_root = GENERATED_ROOT / "ricker"

    accuracy_specs = [
        ("width4_points17", 17, 4.0, 1e-12, 1e-12, False),
        ("width10_point1", 1, 10.0, 1e-12, 1e-12, False),
        ("invalid_a", 16, 0.0, 1e-12, 1e-12, True),
    ]
    accuracy_cases = []
    for case_id, points, a, atol, rtol, invalid in accuracy_specs:
        case = {
            "id": case_id,
            "points": points,
            "a": a,
            "atol": atol,
            "rtol": rtol,
        }
        if invalid:
            case["expect_invalid_argument"] = True
        else:
            case["expected_signal_file"] = save_real_expected(
                ref_root,
                f"{case_id}__signal",
                ricker_np(points, a),
            )
        accuracy_cases.append(case)

    perf_cases = [
        {
            "id": "perf_large",
            "points": 16384,
            "a": 32.0,
            "atol": 1e-12,
            "rtol": 1e-12,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_morlet2_cases():
    ref_root = REFERENCE_ROOT / "morlet2"
    gen_root = GENERATED_ROOT / "morlet2"

    accuracy_specs = [
        ("default_w", 16, 4.0, 5.0, 1e-12, 1e-12, False),
        ("custom_w", 17, 7.5, 2.5, 1e-12, 1e-12, False),
        ("invalid_s", 16, 0.0, 5.0, 1e-12, 1e-12, True),
    ]
    accuracy_cases = []
    for case_id, points, s, w, atol, rtol, invalid in accuracy_specs:
        case = {
            "id": case_id,
            "points": points,
            "s": s,
            "w": w,
            "atol": atol,
            "rtol": rtol,
        }
        if invalid:
            case["expect_invalid_argument"] = True
        else:
            case["expected_signal_file"] = save_complex_expected(
                ref_root,
                f"{case_id}__signal",
                morlet2_np(points, s, w),
            )
        accuracy_cases.append(case)

    perf_cases = [
        {
            "id": "perf_large",
            "points": 16384,
            "s": 64.0,
            "w": 5.0,
            "atol": 1e-12,
            "rtol": 1e-12,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_cwt_cases():
    ref_root = REFERENCE_ROOT / "cwt"
    gen_root = GENERATED_ROOT / "cwt"

    ricker_data = np.sin(np.linspace(0.0, 6.0 * np.pi, 32, dtype=np.float32)) + 0.25 * np.cos(
        np.linspace(0.0, 2.0 * np.pi, 32, dtype=np.float32)
    )
    morlet_data = np.cos(np.linspace(0.0, 4.0 * np.pi, 24, dtype=np.float32)) + np.linspace(
        -0.5, 0.5, 24, dtype=np.float32
    )
    accuracy_specs = [
        ("ricker_case", "ricker", ricker_data, np.array([1.0, 2.0, 3.0, 4.0, 5.0], dtype=np.float32), 1e-11, 1e-11, False),
        ("morlet2_case", "morlet2", morlet_data, np.array([2.0, 4.0, 6.0], dtype=np.float32), 1e-11, 1e-11, False),
        ("invalid_empty_widths", "ricker", ricker_data, np.asarray([], dtype=np.float32), 1e-11, 1e-11, True),
        ("invalid_wavelet", "unknown", ricker_data, np.array([1.0, 2.0], dtype=np.float32), 1e-11, 1e-11, True),
        ("invalid_width_value", "ricker", ricker_data, np.array([0.0, 2.0], dtype=np.float32), 1e-11, 1e-11, True),
    ]
    accuracy_cases = []
    for case_id, wavelet, data, widths, atol, rtol, invalid in accuracy_specs:
        case = {
            "id": case_id,
            "wavelet": wavelet,
            "atol": atol,
            "rtol": rtol,
            "data_file": save_real_input(ref_root, f"{case_id}__data", data),
            "widths_file": save_real_input(ref_root, f"{case_id}__widths", widths),
        }
        if invalid:
            case["expect_invalid_argument"] = True
        else:
            case["expected_values_file"] = save_complex_expected(
                ref_root,
                f"{case_id}__values",
                cwt_np(data, wavelet, widths),
            )
        accuracy_cases.append(case)

    perf_cases = [
        {
            "id": "perf_ricker_large",
            "wavelet": "ricker",
            "atol": 1e-11,
            "rtol": 1e-11,
            "data_start": -2.0,
            "data_stop": 2.0,
            "data_count": 2048,
            "widths_start": 1.0,
            "widths_stop": 32.0,
            "widths_count": 32,
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def main():
    clean_root(REFERENCE_ROOT)
    clean_root(GENERATED_ROOT)
    write_qmf_cases()
    write_morlet_cases()
    write_ricker_cases()
    write_morlet2_cases()
    write_cwt_cases()


if __name__ == "__main__":
    main()

