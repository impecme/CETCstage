#!/usr/bin/env python3

import json
import shutil
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_ROOT = ROOT / "data/reference/unit/radartools"
GENERATED_ROOT = ROOT / "data/generated/unit/radartools"


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


def save_real_input(root: Path, rel_name: str, values) -> str:
    rel = f"input/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def save_complex_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_complex_csv(root / rel, values)
    return rel


def save_real_expected(root: Path, rel_name: str, values) -> str:
    rel = f"expected/{rel_name}.csv"
    write_real_csv(root / rel, values)
    return rel


def complex_tone(length: int, freq: float, phase: float = 0.0, amplitude: float = 1.0):
    t = np.arange(length, dtype=np.float32)
    return amplitude * np.exp(1j * (2.0 * np.pi * freq * t + phase))


def complex_matrix(rows: int, cols: int, freq_row: float, freq_col: float, phase: float = 0.0, amplitude: float = 1.0):
    out = np.empty((rows, cols), dtype=np.complex64)
    for row in range(rows):
        for col in range(cols):
            angle = 2.0 * np.pi * (freq_row * row + freq_col * col) + phase
            out[row, col] = amplitude * np.exp(1j * angle)
    return out


def complex_matrix_pattern(rows: int, cols: int, freq_row: float, freq_col: float, phase: float = 0.0, amplitude: float = 1.0):
    out = np.empty((rows, cols), dtype=np.complex64)
    for row in range(rows):
        for col in range(cols):
            base = phase + freq_row * row + freq_col * col
            cross = 0.071 * (row + 1) * (col + 2)
            real = np.cos(base) + 0.31 * np.sin(cross) + 0.05 * (row % 3) - 0.03 * (col % 5)
            imag = np.sin(base) + 0.23 * np.cos(cross) - 0.04 * (row % 4) + 0.02 * (col % 7)
            out[row, col] = amplitude * (real + 1j * imag)
    return out


def steering_vector(length: int, phase_step: float, phase: float = 0.0):
    indices = np.arange(length, dtype=np.float32)
    return np.exp(1j * (phase + phase_step * indices)).reshape(length, 1)


def boxcar(length: int):
    return np.ones(length, dtype=np.float32)


def pulse_compression_py(x, templ, normalize=False, window=None, nfft=0):
    x = np.asarray(x, dtype=np.complex64)
    templ = np.asarray(templ, dtype=np.complex64)
    if x.ndim != 2:
        raise ValueError("pulse_compression expects rank-2 x")
    if nfft in (0, None):
        nfft = x.shape[1]
    if window is not None:
        templ = templ * window
    if normalize:
        templ = templ / np.linalg.norm(templ)
    fft_x = np.fft.fft(x, nfft, axis=1)
    fft_t = np.conj(np.tile(np.fft.fft(templ, nfft), (x.shape[0], 1)))
    return np.fft.ifft(fft_x * fft_t, nfft, axis=1)


def pulse_doppler_py(x, window=None, nfft=0):
    x = np.asarray(x, dtype=np.complex64)
    if x.ndim != 2:
        raise ValueError("pulse_doppler expects rank-2 x")
    if nfft in (0, None):
        nfft = x.shape[0]
    if window is None:
        return np.fft.fft(x, nfft, axis=0)
    return np.fft.fft(x * window[:, np.newaxis], nfft, axis=0)


def next_power_of_two(value: int) -> int:
    power = 1
    while power < value:
        power <<= 1
    return power


def ambgfun_py(x, fs, prf, y=None, cut="2d", cut_value=0.0):
    del prf
    x = np.asarray(x, dtype=np.complex64)
    xnorm = x / np.linalg.norm(x)
    if y is None:
        ynorm = xnorm
    else:
        ynorm = np.asarray(y, dtype=np.complex64)
        ynorm = ynorm / np.linalg.norm(ynorm)
    len_seq = xnorm.size + ynorm.size
    nfreq = next_power_of_two(len_seq - 1)
    xlen = xnorm.size
    if cut == "2d":
        rows = len_seq - 1
        shifted = np.zeros((rows, xlen), dtype=np.complex64)
        for row in range(rows):
            for col in range(xlen):
                x_col = col - (xlen - 1) + row
                if 0 <= x_col < xlen and col < ynorm.size:
                    shifted[row, col] = ynorm[col] * np.conj(xnorm[x_col])
        values = nfreq * np.abs(np.fft.fftshift(np.fft.ifft(shifted, nfreq, axis=1), axes=1))
        delay_axis = (np.arange(rows, dtype=np.float32) - (xlen - 1)) / fs
        doppler_axis = np.fft.fftshift(np.fft.fftfreq(nfreq, d=1.0 / fs))
        return values, delay_axis, doppler_axis
    if cut == "delay":
        fd = np.arange(-fs / 2.0, fs / 2.0, fs / nfreq, dtype=np.float32)
        fftx = np.fft.fft(xnorm, nfreq) * np.exp(1j * 2.0 * np.pi * fd * cut_value)
        xshift = np.fft.ifft(fftx, nfreq)
        ynorm_pad = np.zeros(nfreq, dtype=np.complex64)
        ynorm_pad[: ynorm.size] = ynorm
        values = nfreq * np.abs(np.fft.ifftshift(np.fft.ifft(ynorm_pad * np.conj(xshift), nfreq)))
        axis = np.fft.fftshift(np.fft.fftfreq(nfreq, d=1.0 / fs))
        return values, axis
    if cut == "doppler":
        t = np.arange(xlen, dtype=np.float32) / fs
        ffty = np.fft.fft(ynorm, len_seq - 1)
        fftx = np.fft.fft(xnorm * np.exp(1j * 2.0 * np.pi * cut_value * t), len_seq - 1)
        values = np.abs(np.fft.fftshift(np.fft.ifft(ffty * np.conj(fftx))))
        axis = (np.arange(len_seq - 1, dtype=np.float32) - (xlen - 1)) / fs
        return values, axis
    raise ValueError("unsupported cut")


def cfar_alpha_py(pfa, cells):
    return cells * ((pfa ** (-1.0 / cells)) - 1.0)


def ca_cfar_1d_py(array, guard_cells, reference_cells, pfa):
    x = np.asarray(array, dtype=np.float32).reshape(-1)
    threshold = np.zeros_like(x)
    detections = np.zeros_like(x)
    cells = 2 * reference_cells
    alpha = cfar_alpha_py(pfa, cells)
    for idx in range(reference_cells + guard_cells, x.size - reference_cells - guard_cells):
        left = x[idx - guard_cells - reference_cells : idx - guard_cells]
        right = x[idx + guard_cells + 1 : idx + guard_cells + reference_cells + 1]
        noise = (left.sum() + right.sum()) / cells
        threshold[idx] = alpha * noise
        detections[idx] = 1.0 if x[idx] > threshold[idx] else 0.0
    return threshold, detections


def ca_cfar_2d_py(array, guard_shape, reference_shape, pfa):
    x = np.asarray(array, dtype=np.float32)
    rows, cols = x.shape
    gr, gc = guard_shape
    rr, rc = reference_shape
    threshold = np.zeros_like(x)
    detections = np.zeros_like(x)
    cells = 2 * rr * (2 * rc + 2 * gc + 1) + 2 * (2 * gr + 1) * rc
    alpha = cfar_alpha_py(pfa, cells)
    for row in range(rr + gr, rows - rr - gr):
        for col in range(rc + gc, cols - rc - gc):
            total = 0.0
            count = 0
            for prow in range(row - rr - gr, row + rr + gr + 1):
                for pcol in range(col - rc - gc, col + rc + gc + 1):
                    if abs(prow - row) <= gr and abs(pcol - col) <= gc:
                        continue
                    total += x[prow, pcol]
                    count += 1
            noise = total / count
            threshold[row, col] = alpha * noise
            detections[row, col] = 1.0 if x[row, col] > threshold[row, col] else 0.0
    return threshold, detections


def mvdr_py(x, sv, calc_cov=True):
    x = np.asarray(x, dtype=np.complex64)
    sv = np.asarray(sv, dtype=np.complex64)
    if calc_cov:
        centered = x - x.mean(axis=1, keepdims=True)
        r = centered @ np.conj(centered.T) / max(x.shape[1] - 1, 1)
    else:
        r = x
    wb = np.linalg.solve(r, sv)
    wa = np.conj(sv).T @ wb
    return wb / wa


def window_spec_string(name: str):
    return {"kind": "string", "value": name}


def write_pulse_compression():
    ref_root = REFERENCE_ROOT / "pulse_compression"
    gen_root = GENERATED_ROOT / "pulse_compression"

    x0 = complex_matrix(3, 8, 0.07, 0.11, phase=0.1, amplitude=1.0)
    templ0 = complex_tone(8, 0.09, phase=0.25, amplitude=0.8)
    y0 = pulse_compression_py(x0, templ0, normalize=False, window=None, nfft=8)

    x1 = complex_matrix(2, 8, 0.12, 0.06, phase=-0.2, amplitude=0.9)
    templ1 = complex_tone(8, 0.15, phase=0.35, amplitude=1.0)
    y1 = pulse_compression_py(x1, templ1, normalize=True, window=boxcar(8), nfft=16)

    accuracy_cases = [
        {
            "id": "basic",
            "x_shape": [3, 8],
            "x_file": save_complex_input(ref_root, "basic_x", x0),
            "templ_file": save_complex_input(ref_root, "basic_templ", templ0),
            "nfft": 8,
            "normalize": False,
            "atol": 1e-11,
            "rtol": 1e-11,
            "expected_signal_file": save_complex_expected(ref_root, "basic_signal", y0),
        },
        {
            "id": "normalize_boxcar_nfft16",
            "x_shape": [2, 8],
            "x_file": save_complex_input(ref_root, "normalize_boxcar_nfft16_x", x1),
            "templ_file": save_complex_input(ref_root, "normalize_boxcar_nfft16_templ", templ1),
            "window": window_spec_string("boxcar"),
            "nfft": 16,
            "normalize": True,
            "atol": 1e-11,
            "rtol": 1e-11,
            "expected_signal_file": save_complex_expected(ref_root, "normalize_boxcar_nfft16_signal", y1),
        },
    ]

    perf_cases = [
        {
            "id": "perf_large",
            "x_shape": [32, 256],
            "nfft": 256,
            "normalize": True,
            "atol": 1e-11,
            "rtol": 1e-11,
            "x_generator": {
                "kind": "complex_matrix_tone",
                "shape": [32, 256],
                "freq_row": 0.013,
                "freq_col": 0.041,
                "phase": 0.2,
                "amplitude": 1.0,
            },
            "templ_generator": {
                "kind": "complex_signal_tone",
                "length": 256,
                "freq": 0.037,
                "phase": 0.15,
                "amplitude": 1.0,
            },
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_pulse_doppler():
    ref_root = REFERENCE_ROOT / "pulse_doppler"
    gen_root = GENERATED_ROOT / "pulse_doppler"

    x0 = complex_matrix(4, 6, 0.09, 0.05, phase=0.0, amplitude=1.0)
    y0 = pulse_doppler_py(x0, None, 4)
    x1 = complex_matrix(4, 6, 0.04, 0.08, phase=0.3, amplitude=0.7)
    y1 = pulse_doppler_py(x1, boxcar(4), 8)

    accuracy_cases = [
        {
            "id": "basic",
            "x_shape": [4, 6],
            "x_file": save_complex_input(ref_root, "basic_x", x0),
            "nfft": 4,
            "atol": 1e-11,
            "rtol": 1e-11,
            "expected_signal_file": save_complex_expected(ref_root, "basic_signal", y0),
        },
        {
            "id": "boxcar_nfft8",
            "x_shape": [4, 6],
            "x_file": save_complex_input(ref_root, "boxcar_nfft8_x", x1),
            "window": window_spec_string("boxcar"),
            "nfft": 8,
            "atol": 1e-11,
            "rtol": 1e-11,
            "expected_signal_file": save_complex_expected(ref_root, "boxcar_nfft8_signal", y1),
        },
    ]

    perf_cases = [
        {
            "id": "perf_large",
            "x_shape": [64, 256],
            "nfft": 128,
            "atol": 1e-11,
            "rtol": 1e-11,
            "x_generator": {
                "kind": "complex_matrix_tone",
                "shape": [64, 256],
                "freq_row": 0.017,
                "freq_col": 0.023,
                "phase": 0.1,
                "amplitude": 1.0,
            },
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_ambgfun():
    ref_root = REFERENCE_ROOT / "ambgfun"
    gen_root = GENERATED_ROOT / "ambgfun"

    x0 = complex_tone(16, 0.08, phase=0.2, amplitude=1.0)
    values0, delay0, doppler0 = ambgfun_py(x0, 8.0, 2.0, cut="2d")

    x1 = complex_tone(16, 0.06, phase=0.1, amplitude=0.9)
    y1 = complex_tone(12, 0.09, phase=-0.2, amplitude=1.1)
    values1, axis1 = ambgfun_py(x1, 8.0, 2.0, y=y1, cut="delay", cut_value=0.25)

    x2 = complex_tone(16, 0.04, phase=0.0, amplitude=1.0)
    values2, axis2 = ambgfun_py(x2, 8.0, 2.0, cut="doppler", cut_value=0.5)

    accuracy_cases = [
        {
            "id": "surface_auto",
            "x_shape": [16],
            "x_file": save_complex_input(ref_root, "surface_auto_x", x0),
            "fs": 8.0,
            "prf": 2.0,
            "cut": "2d",
            "atol": 1e-10,
            "rtol": 1e-10,
            "expected_values_file": save_real_expected(ref_root, "surface_auto_values", values0),
            "expected_delay_axis_file": save_real_expected(ref_root, "surface_auto_delay_axis", delay0),
            "expected_doppler_axis_file": save_real_expected(ref_root, "surface_auto_doppler_axis", doppler0),
        },
        {
            "id": "delay_cross",
            "x_shape": [16],
            "x_file": save_complex_input(ref_root, "delay_cross_x", x1),
            "y_shape": [12],
            "y_file": save_complex_input(ref_root, "delay_cross_y", y1),
            "fs": 8.0,
            "prf": 2.0,
            "cut": "delay",
            "cut_value": 0.25,
            "atol": 1e-10,
            "rtol": 1e-10,
            "expected_values_file": save_real_expected(ref_root, "delay_cross_values", values1),
            "expected_axis_file": save_real_expected(ref_root, "delay_cross_axis", axis1),
        },
        {
            "id": "doppler_auto",
            "x_shape": [16],
            "x_file": save_complex_input(ref_root, "doppler_auto_x", x2),
            "fs": 8.0,
            "prf": 2.0,
            "cut": "doppler",
            "cut_value": 0.5,
            "atol": 1e-10,
            "rtol": 1e-10,
            "expected_values_file": save_real_expected(ref_root, "doppler_auto_values", values2),
            "expected_axis_file": save_real_expected(ref_root, "doppler_auto_axis", axis2),
        },
    ]

    perf_cases = [
        {
            "id": "perf_surface",
            "x_shape": [256],
            "fs": 64.0,
            "prf": 8.0,
            "cut": "2d",
            "atol": 1e-10,
            "rtol": 1e-10,
            "x_generator": {
                "kind": "complex_signal_tone",
                "length": 256,
                "freq": 0.021,
                "phase": 0.3,
                "amplitude": 1.0,
            },
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_cfar_alpha():
    ref_root = REFERENCE_ROOT / "cfar_alpha"
    gen_root = GENERATED_ROOT / "cfar_alpha"

    alpha = cfar_alpha_py(1e-3, 20)
    accuracy_cases = [
        {
            "id": "basic",
            "cells": 20,
            "pfa": 1e-3,
            "atol": 1e-14,
            "rtol": 1e-14,
            "expected_value_file": save_real_expected(ref_root, "basic_value", [alpha]),
        }
    ]
    perf_cases = [
        {
            "id": "perf_scalar",
            "cells": 64,
            "pfa": 1e-4,
            "atol": 1e-14,
            "rtol": 1e-14,
        }
    ]
    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_ca_cfar():
    ref_root = REFERENCE_ROOT / "ca_cfar"
    gen_root = GENERATED_ROOT / "ca_cfar"

    x0 = np.ones(32, dtype=np.float32)
    t0, d0 = ca_cfar_1d_py(x0, 2, 4, 1e-3)
    x1 = np.zeros((16, 16), dtype=np.float32)
    x1[7, 9] = 1000.0
    t1, d1 = ca_cfar_2d_py(x1, (1, 1), (2, 2), 1e-3)

    accuracy_cases = [
        {
            "id": "ones_1d",
            "x_shape": [32],
            "x_file": save_real_input(ref_root, "ones_1d_x", x0),
            "guard_cells": 2,
            "reference_cells": 4,
            "pfa": 1e-3,
            "atol": 1e-12,
            "rtol": 1e-12,
            "expected_threshold_file": save_real_expected(ref_root, "ones_1d_threshold", t0),
            "expected_detections_file": save_real_expected(ref_root, "ones_1d_detections", d0),
        },
        {
            "id": "spike_2d",
            "x_shape": [16, 16],
            "x_file": save_real_input(ref_root, "spike_2d_x", x1),
            "guard_shape": [1, 1],
            "reference_shape": [2, 2],
            "pfa": 1e-3,
            "atol": 1e-12,
            "rtol": 1e-12,
            "expected_threshold_file": save_real_expected(ref_root, "spike_2d_threshold", t1),
            "expected_detections_file": save_real_expected(ref_root, "spike_2d_detections", d1),
        },
    ]

    perf_cases = [
        {
            "id": "perf_2d",
            "x_shape": [128, 256],
            "guard_shape": [2, 2],
            "reference_shape": [4, 8],
            "pfa": 1e-3,
            "atol": 1e-12,
            "rtol": 1e-12,
            "real_x_generator": {
                "kind": "real_matrix_pattern",
                "shape": [128, 256],
                "scale": 1.0,
                "bias": 2.0,
                "spike_row": 61,
                "spike_col": 145,
                "spike_value": 100.0,
            },
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def write_mvdr():
    ref_root = REFERENCE_ROOT / "mvdr"
    gen_root = GENERATED_ROOT / "mvdr"

    x0 = complex_matrix_pattern(4, 16, 0.11, 0.07, phase=0.0, amplitude=1.0)
    sv0 = steering_vector(4, 0.2, phase=0.1)
    w0 = mvdr_py(x0, sv0, calc_cov=True)

    cov = np.array(
        [
            [1.0 + 0.0j, 0.1 - 0.05j, 0.02 + 0.01j, 0.03 - 0.04j],
            [0.1 + 0.05j, 1.2 + 0.0j, 0.05 - 0.02j, 0.04 + 0.03j],
            [0.02 - 0.01j, 0.05 + 0.02j, 0.9 + 0.0j, 0.03 - 0.01j],
            [0.03 + 0.04j, 0.04 - 0.03j, 0.03 + 0.01j, 1.1 + 0.0j],
        ],
        dtype=np.complex64,
    )
    sv1 = steering_vector(4, 0.17, phase=-0.2)
    w1 = mvdr_py(cov, sv1, calc_cov=False)

    accuracy_cases = [
        {
            "id": "calc_cov_true",
            "x_shape": [4, 16],
            "x_file": save_complex_input(ref_root, "calc_cov_true_x", x0),
            "sv_shape": [4, 1],
            "sv_file": save_complex_input(ref_root, "calc_cov_true_sv", sv0),
            "calc_cov": True,
            "atol": 1e-10,
            "rtol": 1e-10,
            "expected_signal_file": save_complex_expected(ref_root, "calc_cov_true_signal", w0),
        },
        {
            "id": "covariance_input",
            "x_shape": [4, 4],
            "x_file": save_complex_input(ref_root, "covariance_input_x", cov),
            "sv_shape": [4, 1],
            "sv_file": save_complex_input(ref_root, "covariance_input_sv", sv1),
            "calc_cov": False,
            "atol": 1e-10,
            "rtol": 1e-10,
            "expected_signal_file": save_complex_expected(ref_root, "covariance_input_signal", w1),
        },
    ]

    perf_cases = [
        {
            "id": "perf_calc_cov",
            "x_shape": [8, 64],
            "sv_shape": [8, 1],
            "calc_cov": True,
            "atol": 1e-10,
            "rtol": 1e-10,
            "x_generator": {
                "kind": "complex_matrix_pattern",
                "shape": [8, 64],
                "freq_row": 0.03,
                "freq_col": 0.02,
                "phase": 0.1,
                "amplitude": 1.0,
            },
            "sv_generator": {
                "kind": "steering_vector",
                "length": 8,
                "phase_step": 0.14,
                "phase": 0.05,
                "column_vector": True,
            },
        }
    ]

    dump_manifest(ref_root, accuracy_cases, [])
    dump_manifest(gen_root, [], perf_cases)


def main():
    clean_root(REFERENCE_ROOT)
    clean_root(GENERATED_ROOT)
    write_pulse_compression()
    write_pulse_doppler()
    write_ambgfun()
    write_cfar_alpha()
    write_ca_cfar()
    write_mvdr()


if __name__ == "__main__":
    main()
