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
        "visualize_task2.py requires matplotlib. Install it first, then rerun the script."
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
GENERATED_ROOT = REPO_ROOT / "data" / "generated" / "demo" / "task2_features"
REPORT_ROOT = REPO_ROOT / "data" / "reports" / "demo" / "task2_features"
INPUT_ROOT = GENERATED_ROOT / "input"
OUTPUT_ROOT = GENERATED_ROOT / "output_samples"
FIGURE_ROOT = REPORT_ROOT / "figures"
WORD_DPI = 300
FIG_W = 6.6
FIG_SHORT = (FIG_W, 3.9)
FIG_MEDIUM = (FIG_W, 4.8)
FIG_TALL = (FIG_W, 5.3)
FIG_XTALL = (FIG_W, 6.2)


def load_real_csv(path: Path) -> np.ndarray:
    data = np.loadtxt(path, delimiter=",", skiprows=1, ndmin=1)
    if data.ndim == 2:
        data = data[:, 0]
    return np.asarray(data, dtype=float)


def load_complex_csv(path: Path) -> np.ndarray:
    data = np.loadtxt(path, delimiter=",", skiprows=1, ndmin=2)
    return data[:, 0].astype(float) + 1j * data[:, 1].astype(float)


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


def write_figure_index() -> None:
    lines = [
        "# Task2 Feature Demo Figures",
        "",
        "- `target_template_components.png`: 目标模板复数分量与包络",
        "- `raw_frame_real_imag.png`: 代表帧原始输入的实部与虚部",
        "- `filtered_vs_raw_frame.png`: 代表帧滤波前后对比",
        "- `correlate_trace_cpu_gpu.png`: 相关性曲线 CPU/GPU 对比",
        "- `spectrogram_gpu.png`: GPU spectrogram 热图",
        "- `cwt_gpu.png`: GPU CWT scalogram",
        "- `feature_score_peaks.png`: 融合分数、峰值与真值",
        "- `kalman_track_vs_truth.png`: 跨帧真值/峰值/Kalman 轨迹对比",
        "- `stage_timing_bar.png`: CPU/GPU 分阶段时间柱状图",
    ]
    (FIGURE_ROOT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def save_target_template(template: np.ndarray) -> None:
    fig, axes = plt.subplots(3, 1, figsize=FIG_XTALL, sharex=True)
    axes[0].plot(template.real)
    axes[0].set_title("Target Template Real")
    axes[0].grid(True, alpha=0.3)
    axes[1].plot(template.imag)
    axes[1].set_title("Target Template Imag")
    axes[1].grid(True, alpha=0.3)
    axes[2].plot(np.abs(template))
    axes[2].set_title("Target Template Envelope")
    axes[2].set_xlabel("Sample")
    axes[2].grid(True, alpha=0.3)
    save_word_figure(fig, FIGURE_ROOT / "target_template_components.png")


def save_raw_frame(rx_frames: np.ndarray, frame_index: int) -> None:
    frame = rx_frames[frame_index]
    fig, axes = plt.subplots(2, 1, figsize=FIG_TALL, sharex=True)
    axes[0].plot(frame.real)
    axes[0].set_title(f"Raw Frame {frame_index} Real")
    axes[0].grid(True, alpha=0.3)
    axes[1].plot(frame.imag)
    axes[1].set_title(f"Raw Frame {frame_index} Imag")
    axes[1].set_xlabel("Sample")
    axes[1].grid(True, alpha=0.3)
    save_word_figure(fig, FIGURE_ROOT / "raw_frame_real_imag.png")


def save_filtered_vs_raw(rx_frames: np.ndarray, filtered: np.ndarray, frame_index: int) -> None:
    fig, ax = plt.subplots(figsize=FIG_SHORT)
    ax.plot(rx_frames[frame_index].real, label="Raw Real", alpha=0.7)
    ax.plot(filtered[frame_index].real, label="Filtered Real", linewidth=1.2)
    ax.set_title(f"Frame {frame_index} Raw vs Filtered")
    ax.set_xlabel("Sample")
    ax.grid(True, alpha=0.3)
    ax.legend()
    save_word_figure(fig, FIGURE_ROOT / "filtered_vs_raw_frame.png")


def save_correlate(cpu_corr: np.ndarray, gpu_corr: np.ndarray, frame_index: int) -> None:
    fig, ax = plt.subplots(figsize=FIG_SHORT)
    ax.plot(cpu_corr[frame_index], label="CPU")
    ax.plot(gpu_corr[frame_index], label="GPU", linestyle="--")
    ax.set_title(f"Correlation Trace Frame {frame_index}")
    ax.set_xlabel("Sample")
    ax.grid(True, alpha=0.3)
    ax.legend()
    save_word_figure(fig, FIGURE_ROOT / "correlate_trace_cpu_gpu.png")


def save_spectrogram(values: np.ndarray, freqs: np.ndarray, times: np.ndarray) -> None:
    fig, ax = plt.subplots(figsize=FIG_MEDIUM)
    extent = [times[0], times[-1], freqs[0], freqs[-1]]
    image = ax.imshow(values, aspect="auto", origin="lower", extent=extent, cmap="viridis")
    ax.set_title("GPU Spectrogram")
    ax.set_xlabel("Time (s)")
    ax.set_ylabel("Frequency (Hz)")
    add_colorbar(fig, image, ax, "Magnitude")
    save_word_figure(fig, FIGURE_ROOT / "spectrogram_gpu.png")


def save_cwt(values: np.ndarray, widths: np.ndarray) -> None:
    fig, ax = plt.subplots(figsize=FIG_MEDIUM)
    image = ax.imshow(np.abs(values), aspect="auto", origin="lower", cmap="magma")
    ax.set_title("GPU CWT Magnitude")
    ax.set_xlabel("Sample")
    ax.set_ylabel("Width Index")
    ax.set_yticks(np.arange(len(widths)))
    ax.set_yticklabels([str(int(v)) for v in widths])
    add_colorbar(fig, image, ax, "Magnitude")
    save_word_figure(fig, FIGURE_ROOT / "cwt_gpu.png")


def save_feature_score(
    cpu_score: np.ndarray,
    gpu_score: np.ndarray,
    truth_track: np.ndarray,
    cpu_peaks: np.ndarray,
    gpu_peaks: np.ndarray,
    frame_index: int,
) -> None:
    fig, ax = plt.subplots(figsize=FIG_MEDIUM)
    ax.plot(cpu_score[frame_index], label="CPU score")
    ax.plot(gpu_score[frame_index], label="GPU score", linestyle="--")
    ax.axvline(truth_track[frame_index], color="green", linestyle=":", label="Truth")
    ax.axvline(cpu_peaks[frame_index], color="blue", alpha=0.5, label="CPU peak")
    ax.axvline(gpu_peaks[frame_index], color="red", alpha=0.5, label="GPU peak")
    ax.set_title(f"Feature Score Frame {frame_index}")
    ax.set_xlabel("Sample")
    ax.grid(True, alpha=0.3)
    ax.legend(ncol=2, fontsize=10.5)
    save_word_figure(fig, FIGURE_ROOT / "feature_score_peaks.png")


def save_track_compare(
    truth_track: np.ndarray,
    cpu_peaks: np.ndarray,
    gpu_peaks: np.ndarray,
    cpu_kalman: np.ndarray,
    gpu_kalman: np.ndarray,
) -> None:
    frames = np.arange(len(truth_track))
    fig, ax = plt.subplots(figsize=FIG_MEDIUM)
    ax.plot(frames, truth_track, label="Truth", linewidth=2.0)
    ax.plot(frames, cpu_peaks, label="CPU Peaks", linestyle="--")
    ax.plot(frames, gpu_peaks, label="GPU Peaks", linestyle="--")
    ax.plot(frames, cpu_kalman, label="CPU Kalman")
    ax.plot(frames, gpu_kalman, label="GPU Kalman")
    ax.set_title("Track Comparison")
    ax.set_xlabel("Frame")
    ax.set_ylabel("Sample")
    ax.grid(True, alpha=0.3)
    ax.legend(ncol=2, fontsize=10.5)
    save_word_figure(fig, FIGURE_ROOT / "kalman_track_vs_truth.png")


def save_stage_timing(csv_path: Path) -> None:
    rows = []
    with csv_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row["stage"] == "total":
                continue
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
    ax.set_title("Task 2 Stage Timing")
    ax.grid(True, axis="y", alpha=0.3)
    ax.legend()
    save_word_figure(fig, FIGURE_ROOT / "stage_timing_bar.png", bottom=0.28)


def main() -> int:
    FIGURE_ROOT.mkdir(parents=True, exist_ok=True)

    scenario = json.loads((INPUT_ROOT / "scenario.json").read_text(encoding="utf-8"))
    metrics = json.loads((REPORT_ROOT / "latest_metrics.json").read_text(encoding="utf-8"))

    rx_shape = tuple(int(v) for v in scenario["rx_shape"])
    rep_frame = int(scenario["representative_frame_index"])
    widths = np.asarray(scenario["cwt_widths"], dtype=float)

    template = load_complex_csv(INPUT_ROOT / "target_template.csv")
    rx_frames = load_complex_csv(INPUT_ROOT / "rx_frames.csv").reshape(rx_shape)
    truth_track = load_real_csv(INPUT_ROOT / "truth_track.csv")

    filtered_shape = tuple(int(v) for v in metrics["shapes"]["filtered"])
    correlate_shape = tuple(int(v) for v in metrics["shapes"]["correlate"])
    spectrogram_shape = tuple(int(v) for v in metrics["shapes"]["spectrogram"])
    cwt_shape = tuple(int(v) for v in metrics["shapes"]["cwt"])
    feature_shape = tuple(int(v) for v in metrics["shapes"]["feature_score"])

    filtered_cpu = load_complex_csv(OUTPUT_ROOT / "filtered__cpu__values.csv").reshape(filtered_shape)
    filtered_gpu = load_complex_csv(OUTPUT_ROOT / "filtered__gpu__values.csv").reshape(filtered_shape)
    corr_cpu = load_real_csv(OUTPUT_ROOT / "correlate__cpu__values.csv").reshape(correlate_shape)
    corr_gpu = load_real_csv(OUTPUT_ROOT / "correlate__gpu__values.csv").reshape(correlate_shape)
    spectrogram_gpu = load_real_csv(OUTPUT_ROOT / "spectrogram__gpu__values.csv").reshape(spectrogram_shape)
    spectrogram_freqs = load_real_csv(OUTPUT_ROOT / "spectrogram_freqs__gpu__values.csv")
    spectrogram_times = load_real_csv(OUTPUT_ROOT / "spectrogram_times__gpu__values.csv")
    cwt_gpu = load_complex_csv(OUTPUT_ROOT / "cwt__gpu__values.csv").reshape(cwt_shape)
    feature_cpu = load_real_csv(OUTPUT_ROOT / "feature_score__cpu__values.csv").reshape(feature_shape)
    feature_gpu = load_real_csv(OUTPUT_ROOT / "feature_score__gpu__values.csv").reshape(feature_shape)
    peak_cpu = load_real_csv(OUTPUT_ROOT / "peak_track__cpu__values.csv")
    peak_gpu = load_real_csv(OUTPUT_ROOT / "peak_track__gpu__values.csv")
    kalman_cpu = load_real_csv(OUTPUT_ROOT / "kalman_track__cpu__values.csv")
    kalman_gpu = load_real_csv(OUTPUT_ROOT / "kalman_track__gpu__values.csv")

    save_target_template(template)
    save_raw_frame(rx_frames, rep_frame)
    save_filtered_vs_raw(rx_frames, filtered_gpu, rep_frame)
    save_correlate(corr_cpu, corr_gpu, rep_frame)
    save_spectrogram(spectrogram_gpu, spectrogram_freqs, spectrogram_times)
    save_cwt(cwt_gpu, widths)
    save_feature_score(feature_cpu, feature_gpu, truth_track, peak_cpu, peak_gpu, rep_frame)
    save_track_compare(truth_track, peak_cpu, peak_gpu, kalman_cpu, kalman_gpu)
    save_stage_timing(REPORT_ROOT / "latest_stage_timings.csv")
    write_figure_index()

    print("[task2_features] visualization complete")
    print(f"figures       : {FIGURE_ROOT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
