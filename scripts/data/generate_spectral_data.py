#!/usr/bin/env python3

import json
import shutil
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_ROOT = ROOT / "data/reference/unit/spectral"
GENERATED_ROOT = ROOT / "data/generated/unit/spectral"


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


def window_spec_string(name: str):
    return {"kind": "string", "value": name}


def signal_pattern(length: int, freq1: float, freq2: float, phase: float = 0.0, amplitude: float = 1.0, bias: float = 0.0):
    idx = np.arange(length, dtype=np.float32)
    return bias + amplitude * (np.sin(freq1 * idx + phase) + 0.35 * np.cos(freq2 * idx - 0.17))


def irregular_times(count: int, start: float, stop: float, jitter: float):
    base = np.linspace(start, stop, count, dtype=np.float32)
    return base + jitter * np.sin(0.37 * np.arange(count, dtype=np.float32))


def window_values(spec, nperseg: int):
    if isinstance(spec, str):
        if spec == "boxcar":
            return np.ones(nperseg, dtype=np.float32)
        if spec == "hann":
            if nperseg <= 1:
                return np.ones(nperseg, dtype=np.float32)
            n = np.arange(nperseg, dtype=np.float32)
            return 0.5 - 0.5 * np.cos(2.0 * np.pi * n / nperseg)
    raise ValueError(f"unsupported window spec in generator: {spec}")


def detrend_line(x, detrend):
    values = np.asarray(x, dtype=np.float32).copy()
    if detrend is False:
        return values
    if detrend == "constant":
        return values - values.mean()
    raise ValueError(f"unsupported detrend in generator: {detrend}")


def density_scale(window, fs):
    return 1.0 / (fs * np.sum(np.square(window)))


def spectrum_scale(window):
    denom = np.sum(window) ** 2
    return 0.0 if denom == 0.0 else 1.0 / denom


def median_bias(n: int):
    if n <= 0:
        return 1.0
    if n % 2 == 1:
        return 1.0
    return 1.0 + 1.0 / max(n, 1)


def frequency_axis(nfft: int, fs: float, onesided: bool):
    if onesided:
        return np.fft.rfftfreq(nfft, d=1.0 / fs).astype(np.float32)
    return np.fft.fftfreq(nfft, d=1.0 / fs).astype(np.float32)


def segment_times(length: int, nperseg: int, step: int, fs: float, boundary_enabled: bool):
    if length < nperseg:
        return np.empty(0, dtype=np.float32)
    count = 1 + (length - nperseg) // step
    center = nperseg / 2.0
    offset = 0.0 if boundary_enabled else center
    return (np.arange(count, dtype=np.float32) * step + offset) / fs


def extend_line(line, n, mode):
    x = np.asarray(line, dtype=np.float32)
    if n == 0 or mode == "none":
        return x.copy()
    if mode == "zeros":
        return np.pad(x, (n, n), mode="constant")
    if mode == "constant":
        return np.pad(x, (n, n), mode="edge")
    if mode == "even":
        left = x[1 : n + 1][::-1] if x.size > 1 else np.repeat(x[:1], n)
        right = x[-n - 1 : -1][::-1] if x.size > 1 else np.repeat(x[:1], n)
        return np.concatenate([left, x, right])
    if mode == "odd":
        if x.size == 0:
            return x.copy()
        left_base = x[1 : n + 1][::-1] if x.size > 1 else np.repeat(x[:1], n)
        right_base = x[-n - 1 : -1][::-1] if x.size > 1 else np.repeat(x[:1], n)
        left = 2.0 * x[0] - left_base
        right = 2.0 * x[-1] - right_base
        return np.concatenate([left, x, right])
    raise ValueError(f"unsupported boundary mode: {mode}")


def pad_line_to_segments(line, nperseg, step):
    values = np.asarray(line, dtype=np.float32)
    if values.size < nperseg:
        return np.pad(values, (0, nperseg - values.size), mode="constant")
    nadd = ((-(values.size - nperseg) % step) + step) % step
    nadd %= nperseg
    if nadd == 0:
        return values
    return np.pad(values, (0, nadd), mode="constant")


def resolve_segment_config(length, nperseg, noverlap, nfft, default_nperseg, default_noverlap):
    nperseg = default_nperseg if nperseg <= 0 else nperseg
    nperseg = min(nperseg, length)
    noverlap = default_noverlap if noverlap < 0 else noverlap
    if noverlap >= nperseg:
        raise ValueError("noverlap must be less than nperseg")
    nfft = nperseg if nfft <= 0 else nfft
    if nfft < nperseg:
        raise ValueError("nfft must be greater than or equal to nperseg")
    return nperseg, noverlap, nfft, nperseg - noverlap


def fft_segments(line, window, nperseg, noverlap, nfft, detrend, onesided, boundary="none", padded=False, fs=1.0):
    x = np.asarray(line, dtype=np.float32)
    if boundary != "none":
        x = extend_line(x, nperseg // 2, boundary)
    if padded:
        x = pad_line_to_segments(x, nperseg, nperseg - noverlap)
    step = nperseg - noverlap
    if x.size < nperseg:
        return [], np.empty(0, dtype=np.float32)
    count = 1 + (x.size - nperseg) // step
    times = segment_times(x.size, nperseg, step, fs, boundary != "none")
    spectra = []
    for seg in range(count):
        start = seg * step
        chunk = detrend_line(x[start : start + nperseg], detrend) * window
        fft_values = np.fft.fft(chunk, nfft)
        if onesided:
            fft_values = fft_values[: nfft // 2 + 1]
        spectra.append(fft_values.astype(np.complex64))
    return spectra, times


def psd_from_fft(values, scale, onesided, nfft):
    psd = np.abs(values) ** 2 * scale
    if onesided:
        if nfft % 2 == 0:
            if psd.size > 2:
                psd[1:-1] *= 2.0
        else:
            if psd.size > 1:
                psd[1:] *= 2.0
    return psd.astype(np.float32)


def cross_from_fft(x_values, y_values, scale, onesided, nfft):
    cross = np.conj(x_values) * y_values * scale
    if onesided:
        if nfft % 2 == 0:
            if cross.size > 2:
                cross[1:-1] *= 2.0
        else:
            if cross.size > 1:
                cross[1:] *= 2.0
    return cross.astype(np.complex64)


def mean_real_segments(segments):
    return np.mean(np.asarray(segments, dtype=np.float32), axis=0)


def mean_complex_segments(segments):
    return np.mean(np.asarray(segments, dtype=np.complex64), axis=0)


def unwrap_phase(values):
    return np.unwrap(np.asarray(values, dtype=np.float32))


def lombscargle_py(x, y, freqs, precenter=False, normalize=False):
    x = np.asarray(x, dtype=np.float32)
    y = np.asarray(y, dtype=np.float32)
    freqs = np.asarray(freqs, dtype=np.float32)
    values = y - y.mean() if precenter else y.copy()
    y_dot = np.dot(values, values)
    out = np.zeros(freqs.shape[0], dtype=np.float32)
    for i, w in enumerate(freqs):
        c = np.cos(w * x)
        s = np.sin(w * x)
        xc = np.dot(values, c)
        xs = np.dot(values, s)
        cc = np.dot(c, c)
        ss = np.dot(s, s)
        power = 0.5 * ((xc * xc / cc) if cc > 0.0 else 0.0 + (xs * xs / ss) if ss > 0.0 else 0.0)
        if cc > 0.0 and ss > 0.0:
            power = 0.5 * ((xc * xc / cc) + (xs * xs / ss))
        out[i] = 2.0 * power / y_dot if normalize and y_dot > 0.0 else power
    return out


def periodogram_py(x, fs=1.0, window="boxcar", nfft=0, detrend="constant", return_onesided=True, scaling="density"):
    x = np.asarray(x, dtype=np.float32)
    if nfft > 0 and nfft < x.size:
        line = x[:nfft]
        resolved_nfft = nfft
    else:
        line = x
        resolved_nfft = nfft if nfft > 0 else x.size
    w = window_values(window, line.size)
    chunk = detrend_line(line, detrend) * w
    fft_values = np.fft.fft(chunk, resolved_nfft)
    if return_onesided:
        fft_values = fft_values[: resolved_nfft // 2 + 1]
    scale = density_scale(w, fs) if scaling == "density" else spectrum_scale(w)
    return frequency_axis(resolved_nfft, fs, return_onesided), psd_from_fft(fft_values, scale, return_onesided, resolved_nfft)


def welch_py(x, fs=1.0, window="hann", nperseg=0, noverlap=-1, nfft=0, detrend="constant", return_onesided=True, scaling="density"):
    x = np.asarray(x, dtype=np.float32)
    base_nperseg = min(256, x.size)
    w = window_values(window, min(nperseg if nperseg > 0 else base_nperseg, x.size))
    nperseg, noverlap, nfft, _ = resolve_segment_config(x.size, w.size, noverlap, nfft, w.size, w.size // 2)
    spectra, _ = fft_segments(x, w, nperseg, noverlap, nfft, detrend, return_onesided, boundary="none", padded=False, fs=fs)
    scale = density_scale(w, fs) if scaling == "density" else spectrum_scale(w)
    values = mean_real_segments([psd_from_fft(spec, scale, return_onesided, nfft) for spec in spectra])
    return frequency_axis(nfft, fs, return_onesided), values


def csd_py(x, y, fs=1.0, window="hann", nperseg=0, noverlap=-1, nfft=0, detrend="constant", return_onesided=True, scaling="density"):
    x = np.asarray(x, dtype=np.float32)
    y = np.asarray(y, dtype=np.float32)
    base_nperseg = min(256, x.size)
    w = window_values(window, min(nperseg if nperseg > 0 else base_nperseg, x.size))
    nperseg, noverlap, nfft, _ = resolve_segment_config(x.size, w.size, noverlap, nfft, w.size, w.size // 2)
    xspec, _ = fft_segments(x, w, nperseg, noverlap, nfft, detrend, return_onesided, boundary="none", padded=False, fs=fs)
    yspec, _ = fft_segments(y, w, nperseg, noverlap, nfft, detrend, return_onesided, boundary="none", padded=False, fs=fs)
    scale = density_scale(w, fs) if scaling == "density" else spectrum_scale(w)
    values = mean_complex_segments([cross_from_fft(a, b, scale, return_onesided, nfft) for a, b in zip(xspec, yspec)])
    return frequency_axis(nfft, fs, return_onesided), values


def spectrogram_py(x, fs=1.0, window="hann", nperseg=0, noverlap=-1, nfft=0, detrend="constant", return_onesided=True, scaling="density", mode="psd"):
    x = np.asarray(x, dtype=np.float32)
    base_nperseg = min(256, x.size)
    w = window_values(window, min(nperseg if nperseg > 0 else base_nperseg, x.size))
    nperseg, noverlap, nfft, _ = resolve_segment_config(x.size, w.size, noverlap, nfft, w.size, w.size // 8)
    spectra, times = fft_segments(x, w, nperseg, noverlap, nfft, detrend, return_onesided, boundary="none", padded=False, fs=fs)
    base_scale = density_scale(w, fs) if scaling == "density" else spectrum_scale(w)
    if mode == "psd":
        values = np.stack([psd_from_fft(spec, base_scale, return_onesided, nfft) for spec in spectra], axis=1)
    else:
        scaled = np.stack([spec * np.sqrt(base_scale) for spec in spectra], axis=1)
        if mode == "complex":
            values = scaled
        elif mode == "magnitude":
            values = np.abs(scaled)
        elif mode == "angle":
            values = np.angle(scaled)
        elif mode == "phase":
            values = np.unwrap(np.angle(scaled), axis=0)
        else:
            raise ValueError("unsupported mode")
    return frequency_axis(nfft, fs, return_onesided), times, values


def stft_py(x, fs=1.0, window="hann", nperseg=256, noverlap=-1, nfft=0, detrend=False, return_onesided=True, boundary="zeros", padded=True):
    x = np.asarray(x, dtype=np.float32)
    w = window_values(window, min(nperseg, x.size if x.size > 0 else 1))
    nperseg, noverlap, nfft, _ = resolve_segment_config(x.size, w.size, noverlap, nfft, w.size, w.size // 2)
    spectra, times = fft_segments(x, w, nperseg, noverlap, nfft, detrend, return_onesided, boundary=boundary, padded=padded, fs=fs)
    values = np.stack([spec * np.sqrt(spectrum_scale(w)) for spec in spectra], axis=1)
    return frequency_axis(nfft, fs, return_onesided), times, values


def expand_onesided(values, nfft):
    onesided = np.asarray(values, dtype=np.complex64)
    full = np.zeros(nfft, dtype=np.complex64)
    full[: onesided.size] = onesided
    upper = onesided.size - 1 if nfft % 2 == 0 else onesided.size
    for idx in range(1, upper):
        full[nfft - idx] = np.conj(onesided[idx])
    return full


def istft_py(zxx, fs=1.0, window="hann", nperseg=0, noverlap=-1, nfft=0, input_onesided=True, boundary=True):
    zxx = np.asarray(zxx, dtype=np.complex64)
    freq_bins, segs = zxx.shape
    if nperseg <= 0:
        nperseg = 2 * (freq_bins - 1) if input_onesided else freq_bins
    default_nfft = 2 * (freq_bins - 1) if input_onesided else freq_bins
    if nfft <= 0:
        nfft = nperseg if input_onesided and nperseg == default_nfft + 1 else default_nfft
    if noverlap < 0:
        noverlap = nperseg // 2
    step = nperseg - noverlap
    w = window_values(window, nperseg)
    window_sum = np.sum(w)
    output_length = nperseg + (segs - 1) * step
    accum = np.zeros(output_length, dtype=np.float32)
    norm = np.zeros(output_length, dtype=np.float32)
    for seg in range(segs):
        spectrum = zxx[:, seg]
        full = expand_onesided(spectrum, nfft) if input_onesided else spectrum
        time_seg = np.fft.ifft(full, nfft)
        start = seg * step
        for i in range(nperseg):
            accum[start + i] += time_seg[i].real * window_sum * w[i]
            norm[start + i] += w[i] * w[i]
    trim = nperseg // 2 if boundary else 0
    final_length = output_length - nperseg if boundary else output_length
    signal = np.zeros(final_length, dtype=np.float32)
    for i in range(final_length):
        src = i + trim
        denom = norm[src] if norm[src] > 1e-10 else 1.0
        signal[i] = accum[src] / denom
    times = np.arange(final_length, dtype=np.float32) / fs
    return times, signal


def coherence_py(x, y, fs=1.0, window="hann", nperseg=0, noverlap=-1, nfft=0, detrend="constant"):
    f, pxx = welch_py(x, fs, window, nperseg, noverlap, nfft, detrend, True, "density")
    _, pyy = welch_py(y, fs, window, nperseg, noverlap, nfft, detrend, True, "density")
    _, pxy = csd_py(x, y, fs, window, nperseg, noverlap, nfft, detrend, True, "density")
    denom = pxx * pyy
    values = np.where(denom > 0.0, (np.abs(pxy) ** 2) / denom, 0.0)
    return f, values


def vectorstrength_py(events, period):
    events = np.asarray(events, dtype=np.float32)
    period = np.asarray(period, dtype=np.float32)
    strengths = []
    phases = []
    for p in period.reshape(-1):
        mean = np.mean(np.exp(1j * 2.0 * np.pi * events / p))
        strengths.append(np.abs(mean))
        phases.append(np.angle(mean))
    return np.asarray(strengths, dtype=np.float32), np.asarray(phases, dtype=np.float32)


def build_case(case_id, atol, rtol):
    return {"id": case_id, "atol": atol, "rtol": rtol}


def write_lombscargle():
    ref_root = REFERENCE_ROOT / "lombscargle"
    gen_root = GENERATED_ROOT / "lombscargle"
    x = irregular_times(48, 0.05, 25.0, 0.03)
    y = np.sin(1.3 * x) + 0.35 * np.cos(0.7 * x - 0.2)
    freqs = np.linspace(0.2, 4.5, 96, dtype=np.float32)
    expected = lombscargle_py(x, y, freqs, precenter=True, normalize=True)
    case = build_case("normalized_precentered", 1e-10, 1e-10)
    case.update({
        "precenter": True,
        "normalize": True,
        "x_file": save_real_input(ref_root, "normalized_precentered__x", x),
        "y_file": save_real_input(ref_root, "normalized_precentered__y", y),
        "freqs_file": save_real_input(ref_root, "normalized_precentered__freqs", freqs),
        "expected_signal_file": save_real_expected(ref_root, "normalized_precentered__signal", expected),
    })
    perf_case = {
        "id": "perf_large",
        "precenter": True,
        "normalize": True,
        "x_generator": {"kind": "irregular_times", "count": 2048, "start": 0.01, "stop": 200.0, "jitter": 0.005},
        "y_generator": {"kind": "real_array_pattern", "shape": [2048], "freq_row": 0.013, "freq_col": 0.031, "phase": 0.2, "amplitude": 1.0, "bias": 0.0},
        "freqs_generator": {"kind": "real_linspace", "start": 0.1, "stop": 8.0, "count": 4096},
    }
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], [perf_case])


def write_periodogram():
    ref_root = REFERENCE_ROOT / "periodogram"
    gen_root = GENERATED_ROOT / "periodogram"
    x = signal_pattern(256, 0.11, 0.031, phase=0.2)
    f, values = periodogram_py(x, fs=1024.0, window="hann", scaling="density")
    case = build_case("hann_density", 1e-10, 1e-10)
    case.update({
        "fs": 1024.0,
        "window": window_spec_string("hann"),
        "scaling": "density",
        "x_shape": [x.size],
        "x_file": save_real_input(ref_root, "hann_density__x", x),
        "expected_frequencies_file": save_real_expected(ref_root, "hann_density__frequencies", f),
        "expected_values_file": save_real_expected(ref_root, "hann_density__values", values),
    })
    perf_case = {
        "id": "perf_hann_density",
        "fs": 1024.0,
        "window": window_spec_string("hann"),
        "scaling": "density",
        "x_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.009, "freq_col": 0.021, "phase": 0.1, "amplitude": 1.0, "bias": 0.0},
    }
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], [perf_case])


def write_welch():
    ref_root = REFERENCE_ROOT / "welch"
    gen_root = GENERATED_ROOT / "welch"
    x = signal_pattern(512, 0.09, 0.027, phase=0.1)
    f, values = welch_py(x, fs=800.0, window="hann", nperseg=128, noverlap=64, nfft=128)
    case = build_case("mean_hann", 1e-10, 1e-10)
    case.update({
        "fs": 800.0,
        "window": window_spec_string("hann"),
        "nperseg": 128,
        "noverlap": 64,
        "nfft": 128,
        "average": "mean",
        "x_shape": [x.size],
        "x_file": save_real_input(ref_root, "mean_hann__x", x),
        "expected_frequencies_file": save_real_expected(ref_root, "mean_hann__frequencies", f),
        "expected_values_file": save_real_expected(ref_root, "mean_hann__values", values),
    })
    perf_case = {
        "id": "perf_mean_hann",
        "fs": 800.0,
        "window": window_spec_string("hann"),
        "nperseg": 256,
        "noverlap": 128,
        "nfft": 256,
        "average": "mean",
        "x_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.013, "freq_col": 0.023, "phase": 0.05, "amplitude": 1.0, "bias": 0.0},
    }
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], [perf_case])


def write_csd():
    ref_root = REFERENCE_ROOT / "csd"
    gen_root = GENERATED_ROOT / "csd"
    x = signal_pattern(512, 0.09, 0.027, phase=0.1)
    y = signal_pattern(512, 0.09, 0.027, phase=0.6)
    f, values = csd_py(x, y, fs=800.0, window="hann", nperseg=128, noverlap=64, nfft=128)
    case = build_case("mean_hann", 1e-10, 1e-10)
    case.update({
        "fs": 800.0,
        "window": window_spec_string("hann"),
        "nperseg": 128,
        "noverlap": 64,
        "nfft": 128,
        "average": "mean",
        "x_shape": [x.size],
        "y_shape": [y.size],
        "x_file": save_real_input(ref_root, "mean_hann__x", x),
        "y_file": save_real_input(ref_root, "mean_hann__y", y),
        "expected_frequencies_file": save_real_expected(ref_root, "mean_hann__frequencies", f),
        "expected_values_file": save_complex_expected(ref_root, "mean_hann__values", values),
    })
    perf_case = {
        "id": "perf_mean_hann",
        "fs": 800.0,
        "window": window_spec_string("hann"),
        "nperseg": 256,
        "noverlap": 128,
        "nfft": 256,
        "average": "mean",
        "x_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.013, "freq_col": 0.023, "phase": 0.05, "amplitude": 1.0, "bias": 0.0},
        "y_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.013, "freq_col": 0.023, "phase": 0.45, "amplitude": 1.0, "bias": 0.0},
    }
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], [perf_case])


def write_spectrogram():
    ref_root = REFERENCE_ROOT / "spectrogram"
    gen_root = GENERATED_ROOT / "spectrogram"
    x = signal_pattern(384, 0.08, 0.021, phase=0.3)
    acc_cases = []
    for case_id, mode in [("psd_case", "psd"), ("complex_case", "complex")]:
        f, t, values = spectrogram_py(x, fs=400.0, window="hann", nperseg=64, noverlap=48, nfft=128, mode=mode)
        case = build_case(case_id, 1e-9, 1e-9)
        case.update({
            "fs": 400.0,
            "window": window_spec_string("hann"),
            "nperseg": 64,
            "noverlap": 48,
            "nfft": 128,
            "mode": mode,
            "x_shape": [x.size],
            "x_file": save_real_input(ref_root, f"{case_id}__x", x),
            "expected_frequencies_file": save_real_expected(ref_root, f"{case_id}__frequencies", f),
            "expected_times_file": save_real_expected(ref_root, f"{case_id}__times", t),
        })
        if mode == "complex":
            case["expected_values_file"] = save_complex_expected(ref_root, f"{case_id}__values", values)
        else:
            case["expected_values_file"] = save_real_expected(ref_root, f"{case_id}__values", values)
        acc_cases.append(case)
    perf_case = {
        "id": "perf_psd",
        "fs": 400.0,
        "window": window_spec_string("hann"),
        "nperseg": 128,
        "noverlap": 96,
        "nfft": 256,
        "mode": "psd",
        "x_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.011, "freq_col": 0.019, "phase": 0.0, "amplitude": 1.0, "bias": 0.0},
    }
    dump_manifest(ref_root, acc_cases, [])
    dump_manifest(gen_root, [], [perf_case])


def write_stft():
    ref_root = REFERENCE_ROOT / "stft"
    gen_root = GENERATED_ROOT / "stft"
    x = signal_pattern(384, 0.08, 0.021, phase=0.3)
    f, t, values = stft_py(x, fs=400.0, window="hann", nperseg=64, noverlap=48, nfft=128, boundary="zeros", padded=True)
    case = build_case("zeros_padded", 1e-9, 1e-9)
    case.update({
        "fs": 400.0,
        "window": window_spec_string("hann"),
        "nperseg": 64,
        "noverlap": 48,
        "nfft": 128,
        "detrend": False,
        "boundary": "zeros",
        "padded": True,
        "x_shape": [x.size],
        "x_file": save_real_input(ref_root, "zeros_padded__x", x),
        "expected_frequencies_file": save_real_expected(ref_root, "zeros_padded__frequencies", f),
        "expected_times_file": save_real_expected(ref_root, "zeros_padded__times", t),
        "expected_values_file": save_complex_expected(ref_root, "zeros_padded__values", values),
    })
    perf_case = {
        "id": "perf_zeros_padded",
        "fs": 400.0,
        "window": window_spec_string("hann"),
        "nperseg": 128,
        "noverlap": 96,
        "nfft": 256,
        "detrend": False,
        "boundary": "zeros",
        "padded": True,
        "x_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.011, "freq_col": 0.019, "phase": 0.0, "amplitude": 1.0, "bias": 0.0},
    }
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], [perf_case])


def write_istft():
    ref_root = REFERENCE_ROOT / "istft"
    gen_root = GENERATED_ROOT / "istft"
    x = signal_pattern(384, 0.08, 0.021, phase=0.3)
    _, _, zxx = stft_py(x, fs=400.0, window="hann", nperseg=64, noverlap=48, nfft=128, boundary="zeros", padded=True)
    t, signal = istft_py(zxx, fs=400.0, window="hann", nperseg=64, noverlap=48, nfft=128, input_onesided=True, boundary=True)
    case = build_case("onesided_boundary", 1e-8, 1e-8)
    case.update({
        "fs": 400.0,
        "window": window_spec_string("hann"),
        "nperseg": 64,
        "noverlap": 48,
        "nfft": 128,
        "input_onesided": True,
        "boundary_enabled": True,
        "zxx_shape": list(zxx.shape),
        "zxx_file": save_complex_input(ref_root, "onesided_boundary__zxx", zxx),
        "expected_times_file": save_real_expected(ref_root, "onesided_boundary__times", t),
        "expected_signal_file": save_real_expected(ref_root, "onesided_boundary__signal", signal),
    })
    perf_case = {
        "id": "perf_onesided",
        "fs": 400.0,
        "window": window_spec_string("hann"),
        "nperseg": 128,
        "noverlap": 96,
        "nfft": 256,
        "input_onesided": True,
        "boundary_enabled": True,
        "zxx_generator": {"kind": "complex_matrix_pattern", "shape": [129, 33], "freq_row": 0.07, "freq_col": 0.13, "phase": 0.2, "amplitude": 0.4},
    }
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], [perf_case])


def write_coherence():
    ref_root = REFERENCE_ROOT / "coherence"
    gen_root = GENERATED_ROOT / "coherence"
    x = signal_pattern(512, 0.09, 0.027, phase=0.1)
    y = signal_pattern(512, 0.09, 0.027, phase=0.25)
    f, values = coherence_py(x, y, fs=800.0, window="hann", nperseg=128, noverlap=64, nfft=128)
    case = build_case("hann_mean", 1e-9, 1e-9)
    case.update({
        "fs": 800.0,
        "window": window_spec_string("hann"),
        "nperseg": 128,
        "noverlap": 64,
        "nfft": 128,
        "x_shape": [x.size],
        "y_shape": [y.size],
        "x_file": save_real_input(ref_root, "hann_mean__x", x),
        "y_file": save_real_input(ref_root, "hann_mean__y", y),
        "expected_frequencies_file": save_real_expected(ref_root, "hann_mean__frequencies", f),
        "expected_values_file": save_real_expected(ref_root, "hann_mean__values", values),
    })
    perf_case = {
        "id": "perf_hann_mean",
        "fs": 800.0,
        "window": window_spec_string("hann"),
        "nperseg": 256,
        "noverlap": 128,
        "nfft": 256,
        "x_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.013, "freq_col": 0.023, "phase": 0.05, "amplitude": 1.0, "bias": 0.0},
        "y_generator": {"kind": "real_array_pattern", "shape": [4096], "freq_row": 0.013, "freq_col": 0.023, "phase": 0.17, "amplitude": 1.0, "bias": 0.0},
    }
    dump_manifest(ref_root, [case], [])
    dump_manifest(gen_root, [], [perf_case])


def write_vectorstrength():
    ref_root = REFERENCE_ROOT / "vectorstrength"
    gen_root = GENERATED_ROOT / "vectorstrength"
    events = np.linspace(0.05, 12.0, 64, dtype=np.float32)
    acc_cases = []
    strength, phase = vectorstrength_py(events, np.asarray([1.25], dtype=np.float32))
    case = build_case("scalar_period", 1e-12, 1e-12)
    case.update({
        "period_scalar": 1.25,
        "events_file": save_real_input(ref_root, "scalar_period__events", events),
        "expected_strength_file": save_real_expected(ref_root, "scalar_period__strength", strength),
        "expected_phase_file": save_real_expected(ref_root, "scalar_period__phase", phase),
    })
    acc_cases.append(case)
    periods = np.asarray([0.75, 1.25, 2.0], dtype=np.float32)
    strength, phase = vectorstrength_py(events, periods)
    case = build_case("vector_periods", 1e-12, 1e-12)
    case.update({
        "events_file": save_real_input(ref_root, "vector_periods__events", events),
        "period_file": save_real_input(ref_root, "vector_periods__periods", periods),
        "expected_strength_file": save_real_expected(ref_root, "vector_periods__strength", strength),
        "expected_phase_file": save_real_expected(ref_root, "vector_periods__phase", phase),
    })
    acc_cases.append(case)
    perf_case = {
        "id": "perf_vector",
        "events_generator": {"kind": "real_linspace", "start": 0.0, "stop": 409.5, "count": 4096},
        "period_generator": {"kind": "real_linspace", "start": 0.75, "stop": 2.25, "count": 64},
    }
    dump_manifest(ref_root, acc_cases, [])
    dump_manifest(gen_root, [], [perf_case])


def main():
    clean_root(REFERENCE_ROOT)
    clean_root(GENERATED_ROOT)
    write_lombscargle()
    write_periodogram()
    write_welch()
    write_csd()
    write_spectrogram()
    write_stft()
    write_istft()
    write_coherence()
    write_vectorstrength()


if __name__ == "__main__":
    main()
