#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import math
import shutil
from pathlib import Path

import numpy as np

try:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except ModuleNotFoundError as exc:
    raise SystemExit(
        "plot_task_demo_scale_benchmark.py requires matplotlib. Install it first, then rerun the script."
    ) from exc


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CSV = REPO_ROOT / "data" / "reports" / "demo" / "latest_task_demo_scale_benchmark.csv"
DEFAULT_OUTPUT_ROOT = REPO_ROOT / "data" / "reports" / "demo"
WORD_DPI = 300

plt.rcParams.update(
    {
        "font.size": 12,
        "axes.titlesize": 14,
        "axes.labelsize": 12,
        "xtick.labelsize": 10.5,
        "ytick.labelsize": 10.5,
        "legend.fontsize": 10.5,
        "lines.linewidth": 2.0,
        "axes.linewidth": 1.0,
        "savefig.dpi": WORD_DPI,
        "savefig.bbox": "tight",
        "savefig.pad_inches": 0.05,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "svg.fonttype": "none",
    }
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate Word-friendly Task1/Task2 L1-L6 demo scale benchmark figures."
    )
    parser.add_argument("--csv", type=Path, default=DEFAULT_CSV, help="Task demo scale benchmark CSV.")
    parser.add_argument(
        "--output-root",
        type=Path,
        default=DEFAULT_OUTPUT_ROOT,
        help="Demo report root containing task1_radar/ and task2_features/.",
    )
    return parser.parse_args()


def repo_path(path: Path) -> Path:
    return path if path.is_absolute() else REPO_ROOT / path


def rel(path: Path) -> Path:
    return path.resolve().relative_to(REPO_ROOT)


def f(value: object, default: float = 0.0) -> float:
    try:
        number = float(value)
    except Exception:
        return default
    return number if math.isfinite(number) else default


def load_rows(csv_path: Path) -> list[dict[str, str]]:
    if not csv_path.exists():
        raise FileNotFoundError(f"input CSV not found: {csv_path}")
    with csv_path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def task_rows(rows: list[dict[str, str]], task: str) -> list[dict[str, str]]:
    selected = [row for row in rows if row.get("task") == task]
    selected.sort(key=lambda row: int(f(row.get("scale_level"))))
    if not selected:
        raise ValueError(f"no rows found for task: {task}")
    return selected


def numeric(rows: list[dict[str, str]], key: str) -> np.ndarray:
    return np.array([f(row.get(key)) for row in rows], dtype=float)


def scales(rows: list[dict[str, str]]) -> np.ndarray:
    return numeric(rows, "scale_level")


def scale_labels(rows: list[dict[str, str]]) -> list[str]:
    return [f"L{int(f(row.get('scale_level')))}" for row in rows]


def sizes(rows: list[dict[str, str]]) -> list[str]:
    return [f"{int(f(row.get('primary_dim')))}x{int(f(row.get('samples')))}" for row in rows]


def bool_pass(row: dict[str, str]) -> bool:
    return str(row.get("validation_pass", "")).strip().lower() in {"1", "true", "yes", "pass"}


def save_figure(fig: plt.Figure, path: Path, formats: tuple[str, ...]) -> list[Path]:
    path.parent.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for fmt in formats:
        out = path.with_suffix(f".{fmt}")
        fig.savefig(out, dpi=WORD_DPI if fmt == "png" else None)
        written.append(out)
    plt.close(fig)
    return written


def copy_alias(source_stem: Path, alias_stem: Path, formats: tuple[str, ...]) -> list[Path]:
    written: list[Path] = []
    alias_stem.parent.mkdir(parents=True, exist_ok=True)
    for fmt in formats:
        source = source_stem.with_suffix(f".{fmt}")
        target = alias_stem.with_suffix(f".{fmt}")
        shutil.copyfile(source, target)
        written.append(target)
    return written


def add_size_ticks(ax: plt.Axes, rows: list[dict[str, str]]) -> None:
    ax.set_xticks(scales(rows))
    ax.set_xticklabels([f"{label}\n{size}" for label, size in zip(scale_labels(rows), sizes(rows))])


def plot_task_scale(rows: list[dict[str, str]], title: str) -> plt.Figure:
    x = scales(rows)
    cpu = numeric(rows, "cpu_median_total_ms")
    gpu = numeric(rows, "gpu_median_total_ms")
    speedup = numeric(rows, "speedup")
    error = np.maximum(numeric(rows, "max_mixed_error"), 1.0e-12)
    jitter = numeric(rows, "gpu_total_jitter")
    cuda_drift = np.abs(numeric(rows, "cuda_free_drift_mib"))
    rss_drift = np.abs(numeric(rows, "rss_current_drift_mib"))
    status = np.array([1.0 if bool_pass(row) else 0.0 for row in rows], dtype=float)

    fig, axes = plt.subplots(2, 2, figsize=(8.4, 5.6))
    ax_time, ax_speed, ax_error, ax_health = axes.ravel()

    ax_time.semilogy(x, cpu, marker="o", label="CPU total")
    ax_time.semilogy(x, gpu, marker="s", label="GPU total")
    ax_time.set_title("Median total time")
    ax_time.set_ylabel("Time (ms, log)")
    ax_time.grid(True, which="both", alpha=0.28)
    ax_time.legend(loc="best")

    ax_speed.plot(x, speedup, marker="o", color="#1f77b4")
    ax_speed.fill_between(x, 0.0, speedup, color="#1f77b4", alpha=0.12)
    ax_speed.set_title("GPU e2e speedup")
    ax_speed.set_ylabel("CPU / GPU")
    ax_speed.grid(True, axis="y", alpha=0.28)

    ax_error.semilogy(x, error, marker="o", color="#d62728")
    ax_error.set_title("Max mixed error")
    ax_error.set_ylabel("mixed_error (log)")
    ax_error.grid(True, which="both", alpha=0.28)

    ax_health.plot(x, jitter, marker="o", label="GPU jitter")
    ax_health.plot(x, cuda_drift, marker="s", label="CUDA drift MiB")
    ax_health.plot(x, rss_drift, marker="^", label="RSS drift MiB")
    for row_x, ok in zip(x, status):
        ax_health.scatter(row_x, 0.0, marker="s", s=46, color=("#2ca02c" if ok else "#d62728"))
    ax_health.set_title("Stability and resource drift")
    ax_health.set_ylabel("Observed value")
    ax_health.grid(True, axis="y", alpha=0.28)
    ax_health.legend(loc="best", fontsize=9.5)

    for ax in axes.ravel():
        add_size_ticks(ax, rows)
        ax.set_xlabel("Scale and input size")

    passed = sum(bool_pass(row) for row in rows)
    fig.suptitle(f"{title} L1-L6 scale performance ({passed}/{len(rows)} passed)", fontsize=16, fontweight="bold")
    fig.tight_layout(rect=(0.0, 0.0, 1.0, 0.94), pad=0.8)
    return fig


def main() -> int:
    args = parse_args()
    rows = load_rows(repo_path(args.csv))
    output_root = repo_path(args.output_root)

    task1 = task_rows(rows, "task1_radar")
    task1_stem = output_root / "task1_radar" / "task1_l1_l6_scale_performance"
    task1_word_stem = output_root / "task1_radar" / "task1_l1_l6_scale_performance_word"
    save_figure(plot_task_scale(task1, "Task1 Radar"), task1_stem, ("png", "svg", "pdf"))
    copy_alias(task1_stem, task1_word_stem, ("png", "svg", "pdf"))

    task2 = task_rows(rows, "task2_features")
    task2_stem = output_root / "task2_multidomain_l1_l6_scale_performance"
    save_figure(plot_task_scale(task2, "Task2 Multi-domain Features"), task2_stem, ("png", "svg"))

    print(f"[task-demos] wrote {rel(task1_stem)}.[png|svg|pdf]")
    print(f"[task-demos] wrote {rel(task1_word_stem)}.[png|svg|pdf]")
    print(f"[task-demos] wrote {rel(task2_stem)}.[png|svg]")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
