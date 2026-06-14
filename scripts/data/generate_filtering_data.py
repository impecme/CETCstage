#!/usr/bin/env python3

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "third_party/python"))

import numpy as np
from scipy import signal


REFERENCE_ROOT = ROOT / "data/reference/unit/filtering"
GENERATED_ROOT = ROOT / "data/generated/unit/filtering"


def write_real_csv(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    array = np.asarray(values, dtype=np.float32).reshape(-1)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("value\n")
        for value in array:
            handle.write(f"{value:.17g}\n")


def write_complex_csv(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    array = np.asarray(values, dtype=np.complex64).reshape(-1)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("real,imag\n")
        for value in array:
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


def clean_module_root(root: Path):
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True, exist_ok=True)


def build_window_spec(spec):
    if isinstance(spec, str):
        return {"kind": "string", "value": spec}
    if isinstance(spec, (int, float)):
        return {"kind": "float", "value": float(spec)}
    if isinstance(spec, tuple):
        if len(spec) == 2:
            return {"kind": "named_float", "name": spec[0], "value": float(spec[1])}
        if len(spec) == 3:
            return {
                "kind": "named_pair",
                "name": spec[0],
                "first": float(spec[1]),
                "second": float(spec[2]),
            }
    raise TypeError(f"unsupported window spec: {spec!r}")


def save_real_input(root: Path, name: str, values) -> str:
    path = root / "input" / f"{name}.csv"
    write_real_csv(path, values)
    return f"input/{name}.csv"


def save_complex_input(root: Path, name: str, values) -> str:
    path = root / "input" / f"{name}.csv"
    write_complex_csv(path, values)
    return f"input/{name}.csv"


def add_expected_real(case, root: Path, case_id: str, values, key="expected_signal_file"):
    rel = f"expected/{case_id}.csv"
    write_real_csv(root / rel, values)
    case[key] = rel


def add_expected_complex(case, root: Path, case_id: str, values, key="expected_signal_file"):
    rel = f"expected/{case_id}.csv"
    write_complex_csv(root / rel, values)
    case[key] = rel


def add_expected_state(case, root: Path, case_id: str, values):
    rel = f"expected/{case_id}__state.csv"
    write_real_csv(root / rel, values)
    case["expected_state_file"] = rel


def add_expected_time(case, root: Path, case_id: str, values):
    rel = f"expected/{case_id}__time.csv"
    write_real_csv(root / rel, values)
    case["expected_time_file"] = rel


def write_wiener_cases():
    ref_root = REFERENCE_ROOT / "wiener"
    gen_root = GENERATED_ROOT / "wiener"
    image = np.array([[0.5, 0.0, 1.0, 0.5], [1.5, 0.5, 0.2, 0.7], [1.0, 0.8, 0.1, 0.2]], dtype=np.float32)
    image_file = save_real_input(ref_root, "image_small", image)
    expected = signal.wiener(image, mysize=(3, 3), noise=None)
    case = {
        "id": "image_2d_default_noise",
        "x_file": image_file,
        "x_shape": list(image.shape),
        "mysize": [3, 3],
        "noise": -1.0,
        "atol": 1e-8,
        "rtol": 1e-8,
    }
    add_expected_real(case, ref_root, case["id"], expected)
    perf = [{
        "id": "perf_image_large",
        "x_file": save_real_input(gen_root, "image_large", np.arange(128 * 128, dtype=np.float32).reshape(128, 128) / 97.0),
        "x_shape": [128, 128],
        "mysize": [5, 5],
        "noise": -1.0,
        "atol": 1e-8,
        "rtol": 1e-8,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_firfilter_cases():
    ref_root = REFERENCE_ROOT / "firfilter"
    gen_root = GENERATED_ROOT / "firfilter"
    b = np.array([0.2, 0.6, 0.2], dtype=np.float32)
    x = np.array([[1.0, 2.0, 0.0, -1.0, 3.0], [0.5, -0.5, 1.5, 2.0, -1.0]], dtype=np.float32)
    zi = np.zeros((2, 2), dtype=np.float32)
    y, zf = signal.lfilter(b, [1.0], x, axis=-1, zi=zi)
    case = {
        "id": "with_state_axis_last",
        "b_file": save_real_input(ref_root, "b", b),
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": list(x.shape),
        "axis": -1,
        "zi_file": save_real_input(ref_root, "zi", zi),
        "zi_shape": list(zi.shape),
        "atol": 1e-12,
        "rtol": 1e-12,
    }
    add_expected_real(case, ref_root, case["id"], y)
    case["expected_signal_shape"] = list(y.shape)
    add_expected_state(case, ref_root, case["id"], zf)
    case["expected_state_shape"] = list(zf.shape)
    perf = [{
        "id": "perf_axis_last",
        "b_file": save_real_input(gen_root, "b", b),
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 40.0, 4096)).reshape(64, 64)),
        "x_shape": [64, 64],
        "axis": -1,
        "atol": 1e-12,
        "rtol": 1e-12,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_lfilter_cases():
    ref_root = REFERENCE_ROOT / "lfilter"
    gen_root = GENERATED_ROOT / "lfilter"
    b = np.array([0.1, 0.2, 0.1], dtype=np.float32)
    a = np.array([1.0, -0.3, 0.12], dtype=np.float32)
    x = np.array([1.0, 0.5, -0.5, 2.0, 1.0, -1.0], dtype=np.float32)
    zi = signal.lfilter_zi(b, a) * x[0]
    y, zf = signal.lfilter(b, a, x, zi=zi)
    case = {
        "id": "with_state_1d",
        "b_file": save_real_input(ref_root, "b", b),
        "a_file": save_real_input(ref_root, "a", a),
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": [x.size],
        "axis": -1,
        "zi_file": save_real_input(ref_root, "zi", zi),
        "zi_shape": [zi.size],
        "atol": 1e-11,
        "rtol": 1e-11,
    }
    add_expected_real(case, ref_root, case["id"], y)
    case["expected_signal_shape"] = [y.size]
    add_expected_state(case, ref_root, case["id"], zf)
    case["expected_state_shape"] = [zf.size]
    perf = [{
        "id": "perf_1d",
        "b_file": save_real_input(gen_root, "b", b),
        "a_file": save_real_input(gen_root, "a", a),
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 80.0, 8192))),
        "x_shape": [8192],
        "axis": -1,
        "atol": 1e-11,
        "rtol": 1e-11,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_zi_cases():
    lzi_ref = REFERENCE_ROOT / "lfilter_zi"
    lzi_gen = GENERATED_ROOT / "lfilter_zi"
    fzi_ref = REFERENCE_ROOT / "firfilter_zi"
    fzi_gen = GENERATED_ROOT / "firfilter_zi"

    b = np.array([0.1, 0.2, 0.1], dtype=np.float32)
    a = np.array([1.0, -0.3, 0.12], dtype=np.float32)

    lzi_case = {
        "id": "stable_iir",
        "b_file": save_real_input(lzi_ref, "b", b),
        "a_file": save_real_input(lzi_ref, "a", a),
        "atol": 1e-12,
        "rtol": 1e-12,
    }
    add_expected_real(lzi_case, lzi_ref, lzi_case["id"], signal.lfilter_zi(b, a))
    lzi_case["expected_signal_shape"] = [max(len(a), len(b)) - 1]
    dump_manifest(lzi_ref, [lzi_case], [])
    dump_manifest(
        lzi_gen,
        [],
        [{
            "id": "perf_stable_iir",
            "b_file": save_real_input(lzi_gen, "b", b),
            "a_file": save_real_input(lzi_gen, "a", a),
            "atol": 1e-12,
            "rtol": 1e-12,
        }],
    )

    fir_b = np.array([0.2, 0.5, 0.3], dtype=np.float32)
    fzi_case = {
        "id": "fir_steady_state",
        "b_file": save_real_input(fzi_ref, "b", fir_b),
        "atol": 1e-12,
        "rtol": 1e-12,
    }
    add_expected_real(fzi_case, fzi_ref, fzi_case["id"], signal.lfilter_zi(fir_b, [1.0]))
    fzi_case["expected_signal_shape"] = [len(fir_b) - 1]
    dump_manifest(fzi_ref, [fzi_case], [])
    dump_manifest(
        fzi_gen,
        [],
        [{
            "id": "perf_fir_steady_state",
            "b_file": save_real_input(fzi_gen, "b", fir_b),
            "atol": 1e-12,
            "rtol": 1e-12,
        }],
    )


def write_filtfilt_cases():
    fir_ref = REFERENCE_ROOT / "firfilter2"
    fir_gen = GENERATED_ROOT / "firfilter2"
    iir_ref = REFERENCE_ROOT / "filtfilt"
    iir_gen = GENERATED_ROOT / "filtfilt"

    fir_b = np.array([0.2, 0.6, 0.2], dtype=np.float32)
    x = np.linspace(0.0, 1.0, 32) + 0.1 * np.sin(np.linspace(0.0, 6.0 * np.pi, 32))
    for root, op_name, b, a in [
        (fir_ref, "fir_pad", fir_b, np.array([1.0], dtype=np.float32)),
        (iir_ref, "iir_gust", np.array([0.1, 0.2, 0.1], dtype=np.float32), np.array([1.0, -0.3, 0.12], dtype=np.float32)),
    ]:
        x_file = save_real_input(root, "x", x)
        b_file = save_real_input(root, "b", b)
        case = {
            "id": op_name,
            "b_file": b_file,
            "x_file": x_file,
            "x_shape": [x.size],
            "axis": -1,
            "padtype": "odd" if op_name == "fir_pad" else "even",
            "padlen": -1,
            "method": "pad" if op_name == "fir_pad" else "gust",
            "irlen": -1,
            "atol": 1e-9,
            "rtol": 1e-9,
        }
        if a.size > 1:
            case["a_file"] = save_real_input(root, "a", a)
            expected = signal.filtfilt(b, a, x, method="gust")
        else:
            expected = signal.filtfilt(b, a, x, padtype="odd")
        add_expected_real(case, root, case["id"], expected)
        case["expected_signal_shape"] = [expected.size]
        dump_manifest(root, [case], [])

    dump_manifest(
        fir_gen,
        [],
        [{
            "id": "perf_fir_pad",
            "b_file": save_real_input(fir_gen, "b", fir_b),
            "x_file": save_real_input(fir_gen, "x", np.sin(np.linspace(0.0, 20.0 * np.pi, 4096))),
            "x_shape": [4096],
            "axis": -1,
            "padtype": "odd",
            "padlen": -1,
            "method": "pad",
            "irlen": -1,
            "atol": 1e-9,
            "rtol": 1e-9,
        }],
    )
    b = np.array([0.1, 0.2, 0.1], dtype=np.float32)
    a = np.array([1.0, -0.3, 0.12], dtype=np.float32)
    dump_manifest(
        iir_gen,
        [],
        [{
            "id": "perf_iir_pad",
            "b_file": save_real_input(iir_gen, "b", b),
            "a_file": save_real_input(iir_gen, "a", a),
            "x_file": save_real_input(iir_gen, "x", np.cos(np.linspace(0.0, 16.0 * np.pi, 4096))),
            "x_shape": [4096],
            "axis": -1,
            "padtype": "even",
            "padlen": -1,
            "method": "pad",
            "irlen": -1,
            "atol": 1e-9,
            "rtol": 1e-9,
        }],
    )


def write_sosfilt_cases():
    ref_root = REFERENCE_ROOT / "sosfilt"
    gen_root = GENERATED_ROOT / "sosfilt"
    b = np.array([0.0675, 0.1349, 0.0675], dtype=np.float32)
    a = np.array([1.0, -1.1430, 0.4128], dtype=np.float32)
    sos = signal.tf2sos(b, a)
    x = np.array([1.0, 0.5, -0.2, 0.1, 0.0, 0.4], dtype=np.float32)
    zi = signal.sosfilt_zi(sos) * x[0]
    y, zf = signal.sosfilt(sos, x, zi=zi)
    case = {
        "id": "with_state_1d",
        "sos_file": save_real_input(ref_root, "sos", sos),
        "sos_shape": list(sos.shape),
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": [x.size],
        "axis": -1,
        "zi_file": save_real_input(ref_root, "zi", zi),
        "zi_shape": list(zi.shape),
        "atol": 1e-10,
        "rtol": 1e-10,
    }
    add_expected_real(case, ref_root, case["id"], y)
    case["expected_signal_shape"] = [y.size]
    add_expected_state(case, ref_root, case["id"], zf)
    case["expected_state_shape"] = list(zf.shape)
    perf = [{
        "id": "perf_1d",
        "sos_file": save_real_input(gen_root, "sos", sos),
        "sos_shape": list(sos.shape),
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 60.0, 4096))),
        "x_shape": [4096],
        "axis": -1,
        "atol": 1e-10,
        "rtol": 1e-10,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_hilbert_cases():
    ref_root = REFERENCE_ROOT / "hilbert"
    gen_root = GENERATED_ROOT / "hilbert"
    x = np.cos(np.linspace(0.0, 2.0 * np.pi, 16, endpoint=False))
    case = {
        "id": "analytic_1d",
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": [x.size],
        "n": 0,
        "axis": -1,
        "atol": 1e-10,
        "rtol": 1e-10,
    }
    add_expected_complex(case, ref_root, case["id"], signal.hilbert(x))
    case["expected_signal_shape"] = [x.size]
    perf = [{
        "id": "perf_1d",
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 100.0, 8192))),
        "x_shape": [8192],
        "n": 0,
        "axis": -1,
        "atol": 1e-10,
        "rtol": 1e-10,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_hilbert2_cases():
    ref_root = REFERENCE_ROOT / "hilbert2"
    gen_root = GENERATED_ROOT / "hilbert2"
    x = np.arange(16, dtype=np.float32).reshape(4, 4) / 10.0
    case = {
        "id": "analytic_2d",
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": list(x.shape),
        "n_shape": [],
        "atol": 1e-9,
        "rtol": 1e-9,
    }
    add_expected_complex(case, ref_root, case["id"], signal.hilbert2(x))
    case["expected_signal_shape"] = list(x.shape)
    perf = [{
        "id": "perf_2d",
        "x_file": save_real_input(gen_root, "x", np.arange(64 * 64, dtype=np.float32).reshape(64, 64) / 100.0),
        "x_shape": [64, 64],
        "n_shape": [],
        "atol": 1e-9,
        "rtol": 1e-9,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_detrend_cases():
    ref_root = REFERENCE_ROOT / "detrend"
    gen_root = GENERATED_ROOT / "detrend"
    x = np.linspace(0.0, 1.0, 12)
    data = 1.5 + 2.0 * x + 0.05 * np.sin(np.linspace(0.0, 4.0 * np.pi, 12))
    case = {
        "id": "linear_bp",
        "data_file": save_real_input(ref_root, "data", data),
        "data_shape": [data.size],
        "axis": -1,
        "type": "linear",
        "bp": [4, 8],
        "overwrite_data": False,
        "atol": 1e-10,
        "rtol": 1e-10,
    }
    add_expected_real(case, ref_root, case["id"], signal.detrend(data, type="linear", bp=[4, 8]))
    case["expected_signal_shape"] = [data.size]
    perf = [{
        "id": "perf_linear",
        "data_file": save_real_input(gen_root, "data", 2.0 + 0.01 * np.arange(8192)),
        "data_shape": [8192],
        "axis": -1,
        "type": "linear",
        "bp": [],
        "overwrite_data": False,
        "atol": 1e-10,
        "rtol": 1e-10,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_freq_shift_cases():
    ref_root = REFERENCE_ROOT / "freq_shift"
    gen_root = GENERATED_ROOT / "freq_shift"
    x = np.exp(1j * np.linspace(0.0, 2.0 * np.pi, 16, endpoint=False))
    freq = 5.0
    fs = 64.0
    n = np.arange(x.size, dtype=np.float32)
    expected = x * np.exp(1j * 2.0 * np.pi * freq * n / fs)
    case = {
        "id": "shift_complex_1d",
        "x_file": save_complex_input(ref_root, "x", x),
        "x_shape": [x.size],
        "freq": freq,
        "fs": fs,
        "atol": 1e-12,
        "rtol": 1e-12,
    }
    add_expected_complex(case, ref_root, case["id"], expected)
    case["expected_signal_shape"] = [x.size]
    perf = [{
        "id": "perf_shift",
        "x_file": save_complex_input(gen_root, "x", np.exp(1j * np.linspace(0.0, 40.0 * np.pi, 4096))),
        "x_shape": [4096],
        "freq": 7.5,
        "fs": 512.0,
        "atol": 1e-12,
        "rtol": 1e-12,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def channelize_poly_reference(x, h, n_chans):
    h_padded = np.asarray(h, dtype=np.float32)
    if h_padded.size % n_chans != 0:
        pad = n_chans - (h_padded.size % n_chans)
        h_padded = np.pad(h_padded, (0, pad))
    taps_per_phase = h_padded.size // n_chans
    n_pts = len(x) // n_chans
    out = np.zeros((n_pts, n_chans), dtype=np.complex64)
    for point in range(n_pts):
        accum = np.zeros(n_chans, dtype=np.complex64)
        for phase in range(n_chans):
            value = 0.0j
            for tap in range(taps_per_phase):
                sample_index = point * n_chans + phase - tap * n_chans
                if 0 <= sample_index < len(x):
                    value += x[sample_index] * h_padded[tap * n_chans + phase]
            accum[phase] = value
        out[point, :] = np.fft.fft(accum)
    return out


def write_channelize_poly_cases():
    ref_root = REFERENCE_ROOT / "channelize_poly"
    gen_root = GENERATED_ROOT / "channelize_poly"
    x = np.exp(1j * np.linspace(0.0, 8.0 * np.pi, 24))
    h = signal.firwin(12, 0.25)
    expected = channelize_poly_reference(x, h, 4)
    case = {
        "id": "channels_4",
        "x_file": save_complex_input(ref_root, "x", x),
        "h_file": save_real_input(ref_root, "h", h),
        "n_chans": 4,
        "atol": 1e-10,
        "rtol": 1e-10,
    }
    add_expected_complex(case, ref_root, case["id"], expected)
    case["expected_signal_shape"] = list(expected.shape)
    perf = [{
        "id": "perf_channels_8",
        "x_file": save_complex_input(gen_root, "x", np.exp(1j * np.linspace(0.0, 80.0 * np.pi, 8192))),
        "h_file": save_real_input(gen_root, "h", signal.firwin(64, 0.125)),
        "n_chans": 8,
        "atol": 1e-10,
        "rtol": 1e-10,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_decimate_cases():
    ref_root = REFERENCE_ROOT / "decimate"
    gen_root = GENERATED_ROOT / "decimate"
    x = np.sin(np.linspace(0.0, 4.0 * np.pi, 48)) + 0.25 * np.cos(np.linspace(0.0, 16.0 * np.pi, 48))
    case = {
        "id": "q3_zero_phase",
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": [x.size],
        "q": 3,
        "n": -1,
        "axis": -1,
        "zero_phase": True,
        "atol": 1e-8,
        "rtol": 1e-8,
    }
    add_expected_real(case, ref_root, case["id"], signal.decimate(x, 3, ftype="fir", zero_phase=True))
    case["expected_signal_shape"] = [signal.decimate(x, 3, ftype="fir", zero_phase=True).size]
    perf = [{
        "id": "perf_q4",
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 120.0 * np.pi, 8192))),
        "x_shape": [8192],
        "q": 4,
        "n": -1,
        "axis": -1,
        "zero_phase": True,
        "atol": 1e-8,
        "rtol": 1e-8,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_resample_cases():
    ref_root = REFERENCE_ROOT / "resample"
    gen_root = GENERATED_ROOT / "resample"
    x = np.sin(np.linspace(0.0, 2.0 * np.pi, 12, endpoint=False))
    t = np.linspace(0.0, 1.1, 12)
    case0 = {
        "id": "time_domain_no_t",
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": [x.size],
        "num": 20,
        "axis": 0,
        "window": build_window_spec("hann"),
        "domain": "time",
        "atol": 1e-9,
        "rtol": 1e-9,
    }
    add_expected_real(case0, ref_root, case0["id"], signal.resample(x, 20, window="hann"))
    case0["expected_signal_shape"] = [20]
    case1 = {
        "id": "time_domain_with_t",
        "x_file": save_real_input(ref_root, "x_t", x),
        "x_shape": [x.size],
        "num": 18,
        "t_file": save_real_input(ref_root, "t", t),
        "axis": 0,
        "window": build_window_spec("hann"),
        "domain": "time",
        "atol": 1e-9,
        "rtol": 1e-9,
    }
    y, new_t = signal.resample(x, 18, t=t, window="hann")
    add_expected_real(case1, ref_root, case1["id"], y)
    case1["expected_signal_shape"] = [18]
    add_expected_time(case1, ref_root, case1["id"], new_t)
    perf = [{
        "id": "perf_time_domain",
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 100.0, 4096))),
        "x_shape": [4096],
        "num": 6144,
        "axis": 0,
        "window": build_window_spec("hann"),
        "domain": "time",
        "atol": 1e-9,
        "rtol": 1e-9,
    }]
    dump_manifest(ref_root, [case0, case1], [])
    dump_manifest(gen_root, [], perf)


def write_resample_poly_cases():
    ref_root = REFERENCE_ROOT / "resample_poly"
    gen_root = GENERATED_ROOT / "resample_poly"
    x = np.sin(np.linspace(0.0, 6.0 * np.pi, 30))
    case = {
        "id": "up3_down2",
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": [x.size],
        "up": 3,
        "down": 2,
        "axis": 0,
        "window": build_window_spec(("kaiser", 5.0)),
        "atol": 1e-8,
        "rtol": 1e-8,
    }
    expected = signal.resample_poly(x, 3, 2, window=("kaiser", 5.0))
    add_expected_real(case, ref_root, case["id"], expected)
    case["expected_signal_shape"] = [expected.size]
    perf = [{
        "id": "perf_up4_down3",
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 120.0, 8192))),
        "x_shape": [8192],
        "up": 4,
        "down": 3,
        "axis": 0,
        "window": build_window_spec(("kaiser", 5.0)),
        "atol": 1e-8,
        "rtol": 1e-8,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def write_upfirdn_cases():
    ref_root = REFERENCE_ROOT / "upfirdn"
    gen_root = GENERATED_ROOT / "upfirdn"
    h = np.array([0.5, 1.0, 0.5], dtype=np.float32)
    x = np.array([1.0, -1.0, 0.5, 2.0], dtype=np.float32)
    case = {
        "id": "up2_down3",
        "h_file": save_real_input(ref_root, "h", h),
        "x_file": save_real_input(ref_root, "x", x),
        "x_shape": [x.size],
        "up": 2,
        "down": 3,
        "axis": -1,
        "atol": 1e-12,
        "rtol": 1e-12,
    }
    expected = signal.upfirdn(h, x, up=2, down=3)
    add_expected_real(case, ref_root, case["id"], expected)
    case["expected_signal_shape"] = [expected.size]
    perf = [{
        "id": "perf_up2_down1",
        "h_file": save_real_input(gen_root, "h", signal.firwin(31, 0.25)),
        "x_file": save_real_input(gen_root, "x", np.sin(np.linspace(0.0, 100.0, 4096))),
        "x_shape": [4096],
        "up": 2,
        "down": 1,
        "axis": -1,
        "atol": 1e-12,
        "rtol": 1e-12,
    }]
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], perf)


def main():
    clean_module_root(REFERENCE_ROOT)
    clean_module_root(GENERATED_ROOT)
    write_wiener_cases()
    write_firfilter_cases()
    write_lfilter_cases()
    write_zi_cases()
    write_filtfilt_cases()
    write_sosfilt_cases()
    write_hilbert_cases()
    write_hilbert2_cases()
    write_detrend_cases()
    write_freq_shift_cases()
    write_channelize_poly_cases()
    write_decimate_cases()
    write_resample_cases()
    write_resample_poly_cases()
    write_upfirdn_cases()


if __name__ == "__main__":
    main()
