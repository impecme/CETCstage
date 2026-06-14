#!/usr/bin/env python3

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "third_party/python"))

import numpy as np
from scipy import signal


REFERENCE_ROOT = ROOT / "data/reference/unit/filter_design"
GENERATED_ROOT = ROOT / "data/generated/unit/filter_design"


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


def write_index_csv(path: Path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    array = np.asarray(values, dtype=np.int64).reshape(-1)
    with path.open("w", encoding="utf-8") as handle:
        handle.write("value\n")
        for value in array:
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


def cmplx_sort(values):
    array = np.asarray(values)
    order = np.argsort(np.abs(array), kind="stable")
    return array[order], order


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
        name = spec[0]
        if name == "taylor":
            return {
                "kind": "named_taylor",
                "name": "taylor",
                "nbar": int(spec[1]),
                "sll": float(spec[2]),
                "norm": bool(spec[3]),
            }
        if len(spec) == 2:
            return {"kind": "named_float", "name": name, "value": float(spec[1])}
        if len(spec) == 3:
            return {
                "kind": "named_pair",
                "name": name,
                "first": float(spec[1]),
                "second": float(spec[2]),
            }
    if isinstance(spec, np.ndarray):
        return {"kind": "array", "values": [float(value) for value in spec.reshape(-1)]}
    raise TypeError(f"unsupported window spec: {spec!r}")


def write_scalar_cases():
    beta_root_ref = REFERENCE_ROOT / "kaiser_beta"
    beta_root_gen = GENERATED_ROOT / "kaiser_beta"
    atten_root_ref = REFERENCE_ROOT / "kaiser_atten"
    atten_root_gen = GENERATED_ROOT / "kaiser_atten"

    beta_accuracy = []
    for case_id, attenuation, atol in [
        ("atten_20", 20.0, 1e-12),
        ("atten_80", 80.0, 1e-12),
    ]:
        expected = np.array([signal.kaiser_beta(attenuation)])
        expected_file = beta_root_ref / "expected" / f"{case_id}.csv"
        write_real_csv(expected_file, expected)
        beta_accuracy.append(
            {
                "id": case_id,
                "attenuation": attenuation,
                "atol": atol,
                "rtol": atol,
                "expected_signal_file": f"expected/{case_id}.csv",
            }
        )

    beta_perf = [
        {
            "id": "perf_atten_80",
            "attenuation": 80.0,
            "atol": 1e-12,
            "rtol": 1e-12,
        }
    ]
    dump_manifest(beta_root_ref, beta_accuracy, [])
    dump_manifest(beta_root_gen, [], beta_perf)

    atten_accuracy = []
    for case_id, numtaps, width in [
        ("ntaps_7_width_01", 7, 0.1),
        ("ntaps_51_width_008", 51, 0.08),
    ]:
        expected = np.array([signal.kaiser_atten(numtaps, width)])
        expected_file = atten_root_ref / "expected" / f"{case_id}.csv"
        write_real_csv(expected_file, expected)
        atten_accuracy.append(
            {
                "id": case_id,
                "numtaps": numtaps,
                "width": width,
                "atol": 1e-12,
                "rtol": 1e-12,
                "expected_signal_file": f"expected/{case_id}.csv",
            }
        )

    atten_perf = [
        {
            "id": "perf_ntaps_127_width_004",
            "numtaps": 127,
            "width": 0.04,
            "atol": 1e-12,
            "rtol": 1e-12,
        }
    ]
    dump_manifest(atten_root_ref, atten_accuracy, [])
    dump_manifest(atten_root_gen, [], atten_perf)


def write_cmplx_sort_cases():
    ref_root = REFERENCE_ROOT / "cmplx_sort"
    gen_root = GENERATED_ROOT / "cmplx_sort"
    accuracy = [
        {
            "id": "real_case",
            "input_kind": "real",
            "atol": 1e-12,
            "rtol": 1e-12,
        },
        {
            "id": "complex_case",
            "input_kind": "complex",
            "atol": 1e-12,
            "rtol": 1e-12,
        },
    ]

    perf = [
        {
            "id": "perf_complex",
            "input_kind": "complex",
            "atol": 1e-12,
            "rtol": 1e-12,
        }
    ]

    dump_manifest(ref_root, accuracy, [])
    dump_manifest(gen_root, [], perf)


def write_firwin_cases():
    ref_root = REFERENCE_ROOT / "firwin"
    gen_root = GENERATED_ROOT / "firwin"
    accuracy = []

    cases = [
        {
            "id": "lowpass_scalar",
            "numtaps": 11,
            "cutoff": 0.3,
            "width": -1.0,
            "window": "hamming",
            "pass_zero": True,
            "scale": True,
            "fs": 2.0,
            "atol": 1e-11,
            "rtol": 1e-11,
        },
        {
            "id": "bandpass_multi",
            "numtaps": 13,
            "cutoff": [0.2, 0.5],
            "width": -1.0,
            "window": "hann",
            "pass_zero": False,
            "scale": True,
            "fs": 2.0,
            "atol": 1e-11,
            "rtol": 1e-11,
        },
        {
            "id": "width_override",
            "numtaps": 21,
            "cutoff": 0.25,
            "width": 0.05,
            "window": "boxcar",
            "pass_zero": True,
            "scale": True,
            "fs": 2.0,
            "atol": 1e-10,
            "rtol": 1e-10,
        },
    ]

    for case in cases:
        cutoff = case["cutoff"]
        kwargs = {
            "width": None if case["width"] <= 0 else case["width"],
            "window": case["window"],
            "pass_zero": case["pass_zero"],
            "scale": case["scale"],
            "fs": case["fs"],
        }
        expected = signal.firwin(case["numtaps"], cutoff, **kwargs)
        expected_file = ref_root / "expected" / f"{case['id']}.csv"
        write_real_csv(expected_file, expected)
        accuracy.append(
            {
                "id": case["id"],
                "numtaps": case["numtaps"],
                "cutoff": cutoff,
                "width": case["width"],
                "window": build_window_spec(case["window"]),
                "pass_zero": {
                    "kind": "bool" if isinstance(case["pass_zero"], bool) else "string",
                    "value": case["pass_zero"],
                },
                "scale": case["scale"],
                "nyq": -1.0,
                "fs": case["fs"],
                "atol": case["atol"],
                "rtol": case["rtol"],
                "expected_signal_file": f"expected/{case['id']}.csv",
            }
        )

    perf = [
        {
            "id": "perf_lowpass_large",
            "numtaps": 1025,
            "cutoff": 0.2,
            "width": 0.02,
            "window": build_window_spec(("kaiser", 8.0)),
            "pass_zero": {"kind": "bool", "value": True},
            "scale": True,
            "nyq": -1.0,
            "fs": 2.0,
            "atol": 1e-10,
            "rtol": 1e-10,
        }
    ]

    dump_manifest(ref_root, accuracy, [])
    dump_manifest(gen_root, [], perf)


def write_firwin2_cases():
    ref_root = REFERENCE_ROOT / "firwin2"
    gen_root = GENERATED_ROOT / "firwin2"
    accuracy = []

    cases = [
        {
            "id": "type1_lowpass",
            "numtaps": 11,
            "freq": [0.0, 0.35, 0.35, 1.0],
            "gain": [1.0, 1.0, 0.0, 0.0],
            "nfreqs": 33,
            "window": "hamming",
            "antisymmetric": False,
            "fs": 2.0,
            "atol": 1e-10,
            "rtol": 1e-10,
        },
        {
            "id": "type3_antisymmetric",
            "numtaps": 13,
            "freq": [0.0, 0.25, 0.5, 0.75, 1.0],
            "gain": [0.0, 0.8, 1.0, 0.4, 0.0],
            "nfreqs": 65,
            "window": "hann",
            "antisymmetric": True,
            "fs": 2.0,
            "atol": 1e-10,
            "rtol": 1e-10,
        },
    ]

    for case in cases:
        expected = signal.firwin2(
            case["numtaps"],
            case["freq"],
            case["gain"],
            nfreqs=case["nfreqs"],
            window=case["window"],
            antisymmetric=case["antisymmetric"],
            fs=case["fs"],
        )
        expected_file = ref_root / "expected" / f"{case['id']}.csv"
        write_real_csv(expected_file, expected)
        accuracy.append(
            {
                "id": case["id"],
                "numtaps": case["numtaps"],
                "freq": case["freq"],
                "gain": case["gain"],
                "nfreqs": case["nfreqs"],
                "window": build_window_spec(case["window"]),
                "nyq": -1.0,
                "antisymmetric": case["antisymmetric"],
                "fs": case["fs"],
                "atol": case["atol"],
                "rtol": case["rtol"],
                "expected_signal_file": f"expected/{case['id']}.csv",
            }
        )

    perf = [
        {
            "id": "perf_multiband_large",
            "numtaps": 1025,
            "freq": [0.0, 0.15, 0.15, 0.3, 0.3, 0.6, 0.6, 1.0],
            "gain": [1.0, 1.0, 0.0, 0.0, 0.7, 0.7, 0.0, 0.0],
            "nfreqs": 2049,
            "window": build_window_spec("hamming"),
            "nyq": -1.0,
            "antisymmetric": False,
            "fs": 2.0,
            "atol": 1e-10,
            "rtol": 1e-10,
        }
    ]

    dump_manifest(ref_root, accuracy, [])
    dump_manifest(gen_root, [], perf)


def main():
    clean_module_root(REFERENCE_ROOT)
    clean_module_root(GENERATED_ROOT)
    write_scalar_cases()
    write_cmplx_sort_cases()
    write_firwin_cases()
    write_firwin2_cases()


if __name__ == "__main__":
    main()
