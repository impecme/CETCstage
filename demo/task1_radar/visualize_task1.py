from __future__ import annotations

import csv
import json
from pathlib import Path

import numpy as np

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ModuleNotFoundError as exc:
    raise SystemExit(
        "visualize_task1.py requires matplotlib. Install it first, then rerun the script."
    ) from exc


plt.rcParams.update(
    {
        "font.size": 12,
        "axes.titlesize": 15,
        "axes.labelsize": 13,
        "xtick.labelsize": 11,
        "ytick.labelsize": 11,
        "legend.fontsize": 11,
        "lines.linewidth": 1.8,
        "axes.linewidth": 1.0,
        "savefig.dpi": 300,
        "savefig.bbox": "tight",
        "savefig.pad_inches": 0.05,
    }
)

REPO_ROOT = Path(__file__).resolve().parents[2]
GENERATED_ROOT = REPO_ROOT / "data" / "generated" / "demo" / "task1_radar"
REPORT_ROOT = REPO_ROOT / "data" / "reports" / "demo" / "task1_radar"
INPUT_ROOT = GENERATED_ROOT / "input"
OUTPUT_ROOT = GENERATED_ROOT / "output_samples"
FIGURE_ROOT = REPORT_ROOT / "figures"
WORD_DPI = 300
FIG_W = 6.6
FIG_SHORT = (FIG_W, 3.9)
FIG_MEDIUM = (FIG_W, 4.8)
FIG_TALL = (FIG_W, 5.3)


def load_real_csv(path: Path) -> np.ndarray:
    data = np.loadtxt(path, delimiter=",", skiprows=1, ndmin=1)
    if data.ndim == 2:
        data = data[:, 0]
    return np.asarray(data, dtype=float)


def load_complex_csv(path: Path) -> np.ndarray:
    data = np.loadtxt(path, delimiter=",", skiprows=1, ndmin=2)
    return data[:, 0].astype(float) + 1j * data[:, 1].astype(float)


def to_db(values: np.ndarray) -> np.ndarray:
    return 10.0 * np.log10(np.maximum(values, 1.0e-12))


def save_word_figure(fig: plt.Figure, path: Path, bottom: float | None = None) -> None:
    fig.tight_layout(pad=0.8)
    if bottom is not None:
        fig.subplots_adjust(bottom=bottom)
    fig.savefig(path, dpi=WORD_DPI)
    plt.close(fig)


def add_colorbar(fig: plt.Figure, image, ax: plt.Axes, label: str) -> None:
    cbar = fig.colorbar(image, ax=ax, pad=0.02)
    cbar.set_label(label, fontsize=13)
    cbar.ax.tick_params(labelsize=11)


def save_template_figure(tx_template: np.ndarray) -> None:
    fig, axes = plt.subplots(2, 1, figsize=FIG_TALL, sharex=True)
    axes[0].plot(tx_template.real)
    axes[0].set_title("Transmit Template Real")
    axes[0].grid(True, alpha=0.3)
    axes[1].plot(tx_template.imag)
    axes[1].set_title("Transmit Template Imag")
    axes[1].grid(True, alpha=0.3)
    axes[1].set_xlabel("Sample")
    save_word_figure(fig, FIGURE_ROOT / "tx_template.png")


def save_rx_figure(rx_matrix: np.ndarray) -> None:
    pulse0 = rx_matrix[0]
    fig, axes = plt.subplots(2, 1, figsize=FIG_TALL, sharex=True)
    axes[0].plot(pulse0.real)
    axes[0].set_title("Received Echo Pulse 0 Real")
    axes[0].grid(True, alpha=0.3)
    axes[1].plot(pulse0.imag)
    axes[1].set_title("Received Echo Pulse 0 Imag")
    axes[1].grid(True, alpha=0.3)
    axes[1].set_xlabel("Sample")
    save_word_figure(fig, FIGURE_ROOT / "rx_real_imag.png")


def save_pulse_compression_figure(cpu_values: np.ndarray, gpu_values: np.ndarray) -> None:
    fig, ax = plt.subplots(figsize=FIG_SHORT)
    ax.plot(np.abs(cpu_values[0]), label="CPU")
    ax.plot(np.abs(gpu_values[0]), label="GPU", linestyle="--")
    ax.set_title("Pulse Compression Magnitude (Pulse 0)")
    ax.set_xlabel("Range Bin")
    ax.grid(True, alpha=0.3)
    ax.legend()
    save_word_figure(fig, FIGURE_ROOT / "pulse_compression_cpu_gpu.png")


def save_range_doppler_figure(name: str, values: np.ndarray) -> None:
    fig, ax = plt.subplots(figsize=FIG_MEDIUM)
    image = ax.imshow(to_db(np.abs(values)), aspect="auto", origin="lower", cmap="viridis")
    ax.set_title(f"Range-Doppler Map ({name})")
    ax.set_xlabel("Range Bin")
    ax.set_ylabel("Doppler Bin")
    add_colorbar(fig, image, ax, "Power (dB)")
    save_word_figure(fig, FIGURE_ROOT / f"range_doppler_{name.lower()}.png")


def save_cfar_overlay(power_gpu: np.ndarray, detections_gpu: np.ndarray) -> None:
    fig, ax = plt.subplots(figsize=FIG_MEDIUM)
    image = ax.imshow(to_db(np.abs(power_gpu)), aspect="auto", origin="lower", cmap="viridis")
    hits = np.argwhere(detections_gpu > 0.5)
    if hits.size != 0:
        ax.scatter(hits[:, 1], hits[:, 0], marker="x", c="red", s=36, linewidths=1.5, label="Detection")
        ax.legend(loc="upper right")
    ax.set_title("CFAR Detections Overlay (GPU)")
    ax.set_xlabel("Range Bin")
    ax.set_ylabel("Doppler Bin")
    add_colorbar(fig, image, ax, "Power (dB)")
    save_word_figure(fig, FIGURE_ROOT / "cfar_detection_overlay.png")


def save_ambgfun_surface(name: str, values: np.ndarray, delay_axis: np.ndarray, doppler_axis: np.ndarray) -> None:
    fig, ax = plt.subplots(figsize=FIG_MEDIUM)
    extent = [delay_axis[0], delay_axis[-1], doppler_axis[0], doppler_axis[-1]]
    image = ax.imshow(values.T, aspect="auto", origin="lower", extent=extent, cmap="magma")
    ax.set_title(f"Ambiguity Function Surface ({name})")
    ax.set_xlabel("Delay (s)")
    ax.set_ylabel("Doppler (Hz)")
    add_colorbar(fig, image, ax, "Magnitude")
    save_word_figure(fig, FIGURE_ROOT / f"ambgfun_surface_{name.lower()}.png")


def save_stage_timing_figure(csv_path: Path) -> None:
    rows = []
    with csv_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            rows.append(row)

    labels = [row["stage"] for row in rows]
    cpu = np.array([float(row["cpu_ms"]) for row in rows], dtype=float)
    gpu = np.array([float(row["gpu_ms"]) for row in rows], dtype=float)

    x = np.arange(len(labels))
    width = 0.38
    fig, ax = plt.subplots(figsize=FIG_TALL)
    ax.bar(x - width / 2.0, cpu, width, label="CPU")
    ax.bar(x + width / 2.0, gpu, width, label="GPU")
    ax.set_xticks(x)
    ax.set_xticklabels(labels, rotation=35, ha="right")
    ax.set_ylabel("Time (ms)")
    ax.set_title("Task 1 Stage Timing")
    ax.legend()
    ax.grid(True, axis="y", alpha=0.3)
    save_word_figure(fig, FIGURE_ROOT / "stage_timing_bar.png", bottom=0.28)


def write_figure_index() -> None:
    files = [
        "tx_template.png",
        "rx_real_imag.png",
        "pulse_compression_cpu_gpu.png",
        "range_doppler_cpu.png",
        "range_doppler_gpu.png",
        "cfar_detection_overlay.png",
        "ambgfun_surface_cpu.png",
        "ambgfun_surface_gpu.png",
        "stage_timing_bar.png",
    ]
    lines = ["# Task1 Radar Figures", ""]
    lines.extend(f"- `{name}`" for name in files)
    (FIGURE_ROOT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    FIGURE_ROOT.mkdir(parents=True, exist_ok=True)

    scenario = json.loads((INPUT_ROOT / "scenario.json").read_text(encoding="utf-8"))
    metrics = json.loads((REPORT_ROOT / "latest_metrics.json").read_text(encoding="utf-8"))

    tx_template = load_complex_csv(INPUT_ROOT / "tx_template.csv")
    rx_flat = load_complex_csv(INPUT_ROOT / "rx_matrix.csv")
    rx_shape = tuple(int(v) for v in scenario["rx_shape"])
    rx_matrix = rx_flat.reshape(rx_shape)

    pulse_shape = tuple(int(v) for v in metrics["shapes"]["pulse_compression"])
    range_shape = tuple(int(v) for v in metrics["shapes"]["range_doppler"])
    ambg_shape = tuple(int(v) for v in metrics["shapes"]["ambgfun_surface"])

    pulse_cpu = load_complex_csv(OUTPUT_ROOT / "pulse_compression__cpu__values.csv").reshape(pulse_shape)
    pulse_gpu = load_complex_csv(OUTPUT_ROOT / "pulse_compression__gpu__values.csv").reshape(pulse_shape)
    range_cpu = load_complex_csv(OUTPUT_ROOT / "range_doppler__cpu__values.csv").reshape(range_shape)
    range_gpu = load_complex_csv(OUTPUT_ROOT / "range_doppler__gpu__values.csv").reshape(range_shape)
    cfar_det_gpu = load_real_csv(OUTPUT_ROOT / "cfar_detections__gpu__values.csv").reshape(range_shape)
    ambg_cpu = load_real_csv(OUTPUT_ROOT / "ambgfun_surface__cpu__values.csv").reshape(ambg_shape)
    ambg_gpu = load_real_csv(OUTPUT_ROOT / "ambgfun_surface__gpu__values.csv").reshape(ambg_shape)
    delay_axis = load_real_csv(OUTPUT_ROOT / "ambgfun_delay_axis__gpu__values.csv")
    doppler_axis = load_real_csv(OUTPUT_ROOT / "ambgfun_doppler_axis__gpu__values.csv")

    save_template_figure(tx_template)
    save_rx_figure(rx_matrix)
    save_pulse_compression_figure(pulse_cpu, pulse_gpu)
    save_range_doppler_figure("CPU", range_cpu)
    save_range_doppler_figure("GPU", range_gpu)
    save_cfar_overlay(np.abs(range_gpu) ** 2, cfar_det_gpu)
    save_ambgfun_surface("CPU", ambg_cpu, delay_axis, doppler_axis)
    save_ambgfun_surface("GPU", ambg_gpu, delay_axis, doppler_axis)
    save_stage_timing_figure(REPORT_ROOT / "latest_stage_timings.csv")
    write_figure_index()

    print("[task1_radar] visualization complete")
    print(f"figures       : {FIGURE_ROOT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
