#!/usr/bin/env python3

"""Generate a compact overview figure for all-operator benchmark output."""

from __future__ import annotations

import argparse
import csv
import math
import statistics
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import matplotlib as mpl
import matplotlib.colors as mcolors
import matplotlib.font_manager as mfont
import matplotlib.pyplot as plt
import numpy as np


ERROR_FLOOR = 1.0e-30
PREFERRED_CJK_FONTS = (
    "Noto Sans CJK SC",
    "Source Han Sans SC",
    "WenQuanYi Micro Hei",
    "SimHei",
    "Microsoft YaHei",
)


@dataclass(frozen=True)
class BenchRow:
    run_id: str
    timestamp: str
    module: str
    operator: str
    scale_level: int
    scale_value: int
    scale_family: str
    status: str
    passed: bool
    mixed_error: float
    error_class: str
    gpu_e2e_speedup: float
    gpu_kernel_speedup: float
    cpu_median_ms: float
    gpu_e2e_median_ms: float
    gpu_kernel_median_ms: float
    gpu_e2e_min_ms: float
    gpu_e2e_max_ms: float
    git_commit: str
    gpu_name: str
    error_note: str

    @property
    def op_key(self) -> tuple[str, str]:
        return self.module, self.operator

    @property
    def op_label(self) -> str:
        return f"{self.module}/{self.operator}"


@dataclass(frozen=True)
class OpSummary:
    module: str
    operator: str
    scale_family: str
    largest_scale_level: int
    largest_scale_value: int
    status: str
    failed_scales: int
    max_mixed_error_all_scales: float
    gpu_e2e_speedup_at_max_scale: float
    gpu_kernel_speedup_at_max_scale: float
    cpu_median_ms_at_max_scale: float
    gpu_e2e_median_ms_at_max_scale: float
    gpu_kernel_median_ms_at_max_scale: float
    git_commit: str
    gpu_name: str

    @property
    def op_label(self) -> str:
        return f"{self.module}/{self.operator}"


def log(message: str) -> None:
    print(f"[all-ops-plot] {message}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a compact all-operator benchmark overview.")
    parser.add_argument(
        "--csv",
        default="data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv",
        help="Input all-operator benchmark CSV.",
    )
    parser.add_argument(
        "--output-dir",
        default="data/reports/unit/benchmarks/all_ops/figures",
        help="Directory for figure and plot summary.",
    )
    parser.add_argument(
        "--formats",
        default="png",
        help="Comma-separated output formats. Default: png.",
    )
    parser.add_argument("--dpi", type=int, default=450, help="Raster output DPI.")
    parser.add_argument(
        "--keep-old-output",
        action="store_true",
        help="Do not remove old figure outputs from the output directory.",
    )
    parser.add_argument(
        "--figure-set",
        choices=("overview", "all", "word", "word-summary"),
        default="overview",
        help=(
            "Figure set to generate. overview writes figure 1; all writes figures 1-5; "
            "word writes module-split A4 portrait figures; word-summary writes compact "
            "Word-ready conclusion figures for the report body."
        ),
    )
    parser.add_argument(
        "--report-mode",
        choices=("compact", "full"),
        default="compact",
        help="Compatibility option; candidate reports are intentionally not generated.",
    )
    return parser.parse_args()


def resolve_path(repo_root: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else repo_root / path


def parse_formats(value: str) -> list[str]:
    formats = [item.strip().lower() for item in value.split(",") if item.strip()]
    return formats or ["png"]


def to_float(value: Any) -> float:
    if value is None:
        return math.nan
    text = str(value).strip()
    if not text:
        return math.nan
    try:
        return float(text)
    except ValueError:
        return math.nan


def to_int(value: Any) -> int:
    number = to_float(value)
    return int(number) if math.isfinite(number) else 0


def to_bool(value: Any, status: str = "") -> bool:
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "passed"}:
        return True
    if text in {"false", "0", "no", "failed"}:
        return False
    return status.strip().lower() == "passed"


def fallback_mixed_error(raw: dict[str, str]) -> float:
    mixed = to_float(raw.get("mixed_error"))
    if math.isfinite(mixed):
        return mixed
    rel = to_float(raw.get("max_floor_rel_error") or raw.get("max_rel_error"))
    abs_error = to_float(raw.get("max_abs_error"))
    rmse = to_float(raw.get("rmse"))
    near_zero = to_float(raw.get("near_zero_fraction"))
    if (
        math.isfinite(rel)
        and rel > 1.0e-2
        and math.isfinite(abs_error)
        and abs_error <= 1.0e-3
        and math.isfinite(rmse)
        and rmse <= 1.0e-4
        and math.isfinite(near_zero)
        and near_zero > 0.0
    ):
        return abs_error
    if math.isfinite(rel):
        return rel
    if math.isfinite(abs_error):
        return abs_error
    return 0.0


def load_rows(csv_path: Path) -> list[BenchRow]:
    if not csv_path.exists():
        raise FileNotFoundError(f"input CSV not found: {csv_path}")
    with csv_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        rows = [
            BenchRow(
                run_id=raw.get("run_id", ""),
                timestamp=raw.get("timestamp", ""),
                module=raw.get("module", ""),
                operator=raw.get("operator", ""),
                scale_level=to_int(raw.get("scale_level")),
                scale_value=to_int(raw.get("scale_value")),
                scale_family=raw.get("scale_family", ""),
                status=raw.get("status", ""),
                passed=to_bool(raw.get("pass"), raw.get("status", "")),
                mixed_error=fallback_mixed_error(raw),
                error_class=raw.get("error_class", ""),
                gpu_e2e_speedup=to_float(raw.get("gpu_e2e_speedup")),
                gpu_kernel_speedup=to_float(raw.get("gpu_kernel_speedup")),
                cpu_median_ms=to_float(raw.get("cpu_median_ms")),
                gpu_e2e_median_ms=to_float(raw.get("gpu_e2e_median_ms")),
                gpu_kernel_median_ms=to_float(raw.get("gpu_kernel_median_ms")),
                gpu_e2e_min_ms=to_float(raw.get("gpu_e2e_min_ms")),
                gpu_e2e_max_ms=to_float(raw.get("gpu_e2e_max_ms")),
                git_commit=raw.get("git_commit", ""),
                gpu_name=raw.get("gpu_name", ""),
                error_note=raw.get("error_note", ""),
            )
            for raw in reader
        ]
    rows = [row for row in rows if row.module and row.operator and row.scale_level > 0]
    if not rows:
        raise RuntimeError(f"input CSV has no benchmark rows: {csv_path}")
    return rows


def finite_max(values: list[float]) -> float:
    finite = [value for value in values if math.isfinite(value)]
    return max(finite) if finite else math.nan


def finite_median(values: list[float]) -> float:
    finite = [value for value in values if math.isfinite(value)]
    return statistics.median(finite) if finite else math.nan


def find_cjk_font() -> str | None:
    available = {font.name for font in mfont.fontManager.ttflist}
    for font_name in PREFERRED_CJK_FONTS:
        if font_name in available:
            return font_name
    return None


def make_summaries(rows: list[BenchRow]) -> list[OpSummary]:
    by_op: dict[tuple[str, str], list[BenchRow]] = defaultdict(list)
    for row in rows:
        by_op[row.op_key].append(row)

    summaries: list[OpSummary] = []
    for key, op_rows in by_op.items():
        ordered = sorted(op_rows, key=lambda row: (row.scale_level, row.scale_value))
        last = ordered[-1]
        failed_scales = sum(1 for row in ordered if not row.passed)
        summaries.append(
            OpSummary(
                module=key[0],
                operator=key[1],
                scale_family=last.scale_family,
                largest_scale_level=last.scale_level,
                largest_scale_value=last.scale_value,
                status="passed" if failed_scales == 0 else "failed",
                failed_scales=failed_scales,
                max_mixed_error_all_scales=finite_max([row.mixed_error for row in ordered]),
                gpu_e2e_speedup_at_max_scale=last.gpu_e2e_speedup,
                gpu_kernel_speedup_at_max_scale=last.gpu_kernel_speedup,
                cpu_median_ms_at_max_scale=last.cpu_median_ms,
                gpu_e2e_median_ms_at_max_scale=last.gpu_e2e_median_ms,
                gpu_kernel_median_ms_at_max_scale=last.gpu_kernel_median_ms,
                git_commit=last.git_commit,
                gpu_name=last.gpu_name,
            )
        )
    return sorted(summaries, key=lambda item: (item.module, item.operator))


def write_summary_csv(path: Path, summaries: list[OpSummary]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = [
        "module",
        "operator",
        "scale_family",
        "largest_scale_level",
        "largest_scale_value",
        "status",
        "failed_scales",
        "max_mixed_error_all_scales",
        "gpu_e2e_speedup_at_max_scale",
        "gpu_kernel_speedup_at_max_scale",
        "cpu_median_ms_at_max_scale",
        "gpu_e2e_median_ms_at_max_scale",
        "gpu_kernel_median_ms_at_max_scale",
        "git_commit",
        "gpu_name",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        for item in summaries:
            writer.writerow({column: getattr(item, column) for column in columns})


def apply_style() -> None:
    font_family = find_cjk_font() or "DejaVu Sans"
    mpl.rcParams.update(
        {
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "axes.edgecolor": "#222222",
            "axes.linewidth": 0.7,
            "axes.grid": False,
            "font.family": font_family,
            "font.size": 8.0,
            "axes.titlesize": 9.0,
            "axes.labelsize": 8.0,
            "xtick.labelsize": 7.0,
            "ytick.labelsize": 6.0,
            "axes.unicode_minus": False,
            "savefig.bbox": "tight",
            "savefig.pad_inches": 0.04,
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
            "svg.fonttype": "none",
        }
    )


def clean_plot_outputs(output_dir: Path) -> None:
    if not output_dir.exists():
        return
    for pattern in (
        "figure_*.png",
        "figure_*.pdf",
        "figure_*.svg",
        "latest_all_ops_plot_summary.csv",
        "latest_*operator*index*.csv",
        "latest_*operator*index*.md",
    ):
        for path in output_dir.glob(pattern):
            if path.is_file():
                path.unlink()
    operator_dir = output_dir / "operator_figures"
    if operator_dir.exists():
        for path in operator_dir.glob("*"):
            if path.is_file():
                path.unlink()


def clean_word_outputs(word_dir: Path) -> None:
    if not word_dir.exists():
        return
    for pattern in ("figure_*.png", "figure_*.pdf", "figure_*.svg", "latest_word_figure_manifest.csv"):
        for path in word_dir.glob(pattern):
            if path.is_file():
                path.unlink()


def clean_word_summary_outputs(word_summary_dir: Path) -> None:
    if not word_summary_dir.exists():
        return
    for pattern in ("figure_*.png", "figure_*.pdf", "figure_*.svg", "latest_word_summary_manifest.csv"):
        for path in word_summary_dir.glob(pattern):
            if path.is_file():
                path.unlink()


def sorted_operator_keys(rows: list[BenchRow]) -> list[tuple[str, str]]:
    return sorted({row.op_key for row in rows}, key=lambda key: (key[0], key[1]))


def sorted_scale_levels(rows: list[BenchRow]) -> list[int]:
    return sorted({row.scale_level for row in rows})


def matrix_for(
    rows: list[BenchRow],
    op_keys: list[tuple[str, str]],
    scale_levels: list[int],
    field_name: str,
) -> np.ndarray:
    row_map = {(row.op_key, row.scale_level): row for row in rows}
    matrix = np.full((len(op_keys), len(scale_levels)), np.nan, dtype=float)
    for row_index, key in enumerate(op_keys):
        for col_index, level in enumerate(scale_levels):
            row = row_map.get((key, level))
            if row is not None:
                matrix[row_index, col_index] = getattr(row, field_name)
    return matrix


def status_matrix(rows: list[BenchRow], op_keys: list[tuple[str, str]], scale_levels: list[int]) -> np.ndarray:
    row_map = {(row.op_key, row.scale_level): row for row in rows}
    matrix = np.full((len(op_keys), len(scale_levels)), np.nan, dtype=float)
    for row_index, key in enumerate(op_keys):
        for col_index, level in enumerate(scale_levels):
            row = row_map.get((key, level))
            if row is not None:
                matrix[row_index, col_index] = 1.0 if row.passed else 0.0
    return matrix


def log10_or_floor(values: np.ndarray, floor: float = ERROR_FLOOR) -> np.ndarray:
    out = values.astype(float, copy=True)
    mask = np.isfinite(out)
    out[mask] = np.log10(np.maximum(out[mask], floor))
    return out


def add_module_separators(ax: plt.Axes, op_keys: list[tuple[str, str]]) -> None:
    if not op_keys:
        return
    last_module = op_keys[0][0]
    for index, (module, _) in enumerate(op_keys[1:], start=1):
        if module != last_module:
            ax.axhline(index - 0.5, color="white", linewidth=0.8)
            last_module = module


def add_panel_label(ax: plt.Axes, label: str) -> None:
    ax.text(
        -0.045,
        1.018,
        label,
        transform=ax.transAxes,
        ha="left",
        va="bottom",
        fontsize=9.0,
        fontweight="bold",
    )


def draw_heatmap(
    ax: plt.Axes,
    data: np.ndarray,
    title: str,
    colorbar_label: str,
    scale_levels: list[int],
    labels: list[str],
    op_keys: list[tuple[str, str]],
    cmap: str,
    vcenter: float | None = None,
    show_ylabels: bool = True,
) -> None:
    masked = np.ma.masked_invalid(data)
    if vcenter is None:
        norm = None
    else:
        finite = data[np.isfinite(data)]
        extent = max(abs(float(np.nanmin(finite))), abs(float(np.nanmax(finite))), 1e-6) if finite.size else 1.0
        norm = mcolors.TwoSlopeNorm(vcenter=vcenter, vmin=-extent, vmax=extent)
    image = ax.imshow(masked, aspect="auto", interpolation="nearest", cmap=cmap, norm=norm)
    ax.set_title(title, pad=6)
    ax.set_xticks(np.arange(len(scale_levels)))
    ax.set_xticklabels([str(level) for level in scale_levels])
    ax.set_xlabel("Scale level")
    ax.set_yticks(np.arange(len(labels)))
    ax.set_yticklabels(labels if show_ylabels else [])
    if show_ylabels:
        ax.set_ylabel("Operator")
    ax.tick_params(length=0)
    ax.tick_params(axis="y", labelsize=5.0, pad=1)
    add_module_separators(ax, op_keys)
    cbar = plt.colorbar(image, ax=ax, fraction=0.046, pad=0.012)
    cbar.ax.set_ylabel(colorbar_label, rotation=90)


def save_figure(fig: plt.Figure, output_dir: Path, stem: str, formats: list[str], dpi: int) -> list[Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    saved_paths: list[Path] = []
    for fmt in formats:
        path = output_dir / f"{stem}.{fmt}"
        fig.savefig(path, dpi=dpi if fmt == "png" else None)
        saved_paths.append(path)
        log(f"wrote {path}")
    plt.close(fig)
    return saved_paths


def plot_overview(rows: list[BenchRow], output_dir: Path, formats: list[str], dpi: int) -> None:
    op_keys = sorted_operator_keys(rows)
    scale_levels = sorted_scale_levels(rows)
    labels = [f"{module}/{operator}" for module, operator in op_keys]
    height = max(7.0, 1.4 + 0.18 * len(op_keys))
    fig, axes = plt.subplots(1, 4, figsize=(27.0, height), sharey=True)

    e2e = log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_e2e_speedup"), floor=1.0e-12)
    kernel = log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_kernel_speedup"), floor=1.0e-12)
    error = log10_or_floor(matrix_for(rows, op_keys, scale_levels, "mixed_error"))
    status = status_matrix(rows, op_keys, scale_levels)

    draw_heatmap(
        axes[0],
        e2e,
        "GPU e2e speedup",
        "log10(CPU / GPU e2e)",
        scale_levels,
        labels,
        op_keys,
        "RdBu_r",
        vcenter=0.0,
    )
    draw_heatmap(
        axes[1],
        kernel,
        "GPU kernel speedup",
        "log10(CPU / GPU kernel)",
        scale_levels,
        labels,
        op_keys,
        "RdBu_r",
        vcenter=0.0,
        show_ylabels=True,
    )
    draw_heatmap(
        axes[2],
        error,
        "Mixed error",
        "log10(mixed error)",
        scale_levels,
        labels,
        op_keys,
        "magma_r",
        show_ylabels=True,
    )

    cmap = mcolors.ListedColormap(["#B84A59", "#2F6F5E"])
    cmap.set_bad("#F2F2F2")
    status_image = axes[3].imshow(
        np.ma.masked_invalid(status),
        aspect="auto",
        interpolation="nearest",
        cmap=cmap,
        vmin=0.0,
        vmax=1.0,
    )
    axes[3].set_title("Status", pad=6)
    axes[3].set_xticks(np.arange(len(scale_levels)))
    axes[3].set_xticklabels([str(level) for level in scale_levels])
    axes[3].set_xlabel("Scale level")
    axes[3].set_yticks(np.arange(len(labels)))
    axes[3].set_yticklabels(labels)
    axes[3].set_ylabel("Operator")
    axes[3].tick_params(length=0)
    axes[3].tick_params(axis="y", labelsize=5.0, pad=1)
    add_module_separators(axes[3], op_keys)
    cbar = plt.colorbar(status_image, ax=axes[3], fraction=0.046, pad=0.012, ticks=[0.25, 0.75])
    cbar.ax.set_yticklabels(["Failed", "Passed"])

    for label, ax in zip(["A", "B", "C", "D"], axes):
        add_panel_label(ax, label)
    fig.suptitle("All-operator benchmark overview", y=0.995, fontsize=11, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.985))
    save_figure(fig, output_dir, "figure_1_accuracy_performance_overview", formats, dpi)


def plot_time_heatmaps(rows: list[BenchRow], output_dir: Path, formats: list[str], dpi: int) -> None:
    op_keys = sorted_operator_keys(rows)
    scale_levels = sorted_scale_levels(rows)
    labels = [f"{module}/{operator}" for module, operator in op_keys]
    height = max(7.0, 1.4 + 0.18 * len(op_keys))
    fig, axes = plt.subplots(1, 2, figsize=(15.5, height), sharey=True)

    cpu = log10_or_floor(matrix_for(rows, op_keys, scale_levels, "cpu_median_ms"), floor=1.0e-6)
    gpu = log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_e2e_median_ms"), floor=1.0e-6)
    draw_heatmap(
        axes[0],
        cpu,
        "CPU e2e median time",
        "log10(ms)",
        scale_levels,
        labels,
        op_keys,
        "viridis",
    )
    draw_heatmap(
        axes[1],
        gpu,
        "GPU e2e median time",
        "log10(ms)",
        scale_levels,
        labels,
        op_keys,
        "viridis",
        show_ylabels=True,
    )
    for label, ax in zip(["A", "B"], axes):
        add_panel_label(ax, label)
    fig.suptitle("All-operator CPU/GPU e2e timing", y=0.995, fontsize=11, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.985))
    save_figure(fig, output_dir, "figure_2_cpu_gpu_e2e_time_heatmaps", formats, dpi)


def plot_speedup_heatmap(rows: list[BenchRow], output_dir: Path, formats: list[str], dpi: int) -> None:
    op_keys = sorted_operator_keys(rows)
    scale_levels = sorted_scale_levels(rows)
    labels = [f"{module}/{operator}" for module, operator in op_keys]
    height = max(7.0, 1.4 + 0.18 * len(op_keys))
    fig, ax = plt.subplots(1, 1, figsize=(9.4, height))
    e2e = log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_e2e_speedup"), floor=1.0e-12)
    draw_heatmap(
        ax,
        e2e,
        "GPU e2e speedup",
        "log10(CPU / GPU e2e)",
        scale_levels,
        labels,
        op_keys,
        "RdBu_r",
        vcenter=0.0,
        show_ylabels=True,
    )
    add_panel_label(ax, "A")
    fig.suptitle("All-operator GPU acceleration by scale", y=0.995, fontsize=11, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.985))
    save_figure(fig, output_dir, "figure_3_e2e_speedup_heatmap", formats, dpi)


def largest_scale_rows(rows: list[BenchRow]) -> list[BenchRow]:
    by_op: dict[tuple[str, str], list[BenchRow]] = defaultdict(list)
    for row in rows:
        by_op[row.op_key].append(row)
    return [
        sorted(op_rows, key=lambda row: (row.scale_level, row.scale_value))[-1]
        for op_rows in by_op.values()
    ]


def plot_largest_scale_scatter(rows: list[BenchRow], output_dir: Path, formats: list[str], dpi: int) -> None:
    last_rows = largest_scale_rows(rows)
    valid = [
        row for row in last_rows
        if row.cpu_median_ms > 0.0 and row.gpu_e2e_median_ms > 0.0
        and math.isfinite(row.cpu_median_ms) and math.isfinite(row.gpu_e2e_median_ms)
    ]
    fig, ax = plt.subplots(1, 1, figsize=(6.8, 5.8))
    if valid:
        modules = sorted({row.module for row in valid})
        module_to_index = {module: index for index, module in enumerate(modules)}
        colors = [module_to_index[row.module] for row in valid]
        scatter = ax.scatter(
            [row.cpu_median_ms for row in valid],
            [row.gpu_e2e_median_ms for row in valid],
            c=colors,
            cmap="tab20",
            s=24,
            alpha=0.86,
            edgecolors="white",
            linewidths=0.35,
        )
        values = [value for row in valid for value in (row.cpu_median_ms, row.gpu_e2e_median_ms)]
        lo = min(values) * 0.7
        hi = max(values) * 1.4
        ax.plot([lo, hi], [lo, hi], color="#333333", linewidth=0.8, linestyle="--", label="CPU = GPU")
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.set_xlim(lo, hi)
        ax.set_ylim(lo, hi)
        ax.legend(loc="upper left", frameon=False)
        cbar = plt.colorbar(scatter, ax=ax, fraction=0.046, pad=0.012)
        cbar.set_ticks(range(len(modules)))
        cbar.set_ticklabels(modules)
        cbar.ax.set_ylabel("Module", rotation=90)
    else:
        ax.text(0.5, 0.5, "No CPU/GPU timing columns available", ha="center", va="center", transform=ax.transAxes)
    ax.set_title("Largest-scale CPU vs GPU e2e time")
    ax.set_xlabel("CPU median time (ms)")
    ax.set_ylabel("GPU e2e median time (ms)")
    ax.grid(True, which="both", color="#DDDDDD", linewidth=0.45)
    fig.tight_layout()
    save_figure(fig, output_dir, "figure_4_largest_scale_cpu_vs_gpu_scatter", formats, dpi)


def plot_largest_scale_speedup_rank(rows: list[BenchRow], output_dir: Path, formats: list[str], dpi: int) -> None:
    valid = [
        row for row in largest_scale_rows(rows)
        if row.gpu_e2e_speedup > 0.0 and math.isfinite(row.gpu_e2e_speedup)
    ]
    valid.sort(key=lambda row: row.gpu_e2e_speedup)
    height = max(6.0, 1.0 + 0.18 * len(valid))
    fig, ax = plt.subplots(1, 1, figsize=(8.6, height))
    if valid:
        labels = [row.op_label for row in valid]
        values = [row.gpu_e2e_speedup for row in valid]
        colors = ["#B84A59" if value < 1.0 else "#2F6F5E" for value in values]
        y = np.arange(len(valid))
        ax.barh(y, values, color=colors, height=0.72)
        ax.axvline(1.0, color="#333333", linewidth=0.8, linestyle="--")
        ax.set_yticks(y)
        ax.set_yticklabels(labels)
        ax.set_xscale("log")
        ax.set_xlabel("CPU / GPU e2e speedup at largest scale")
    else:
        ax.text(0.5, 0.5, "No speedup data available", ha="center", va="center", transform=ax.transAxes)
    ax.set_title("Largest-scale GPU speedup ranking")
    ax.grid(True, axis="x", color="#DDDDDD", linewidth=0.45)
    fig.tight_layout()
    save_figure(fig, output_dir, "figure_5_largest_scale_speedup_rank", formats, dpi)


def safe_operator_stem(row: BenchRow) -> str:
    text = f"{row.module}__{row.operator}"
    return "".join(ch if ch.isalnum() or ch in {"_", "-"} else "_" for ch in text)


def append_operator_curve_manifest(
    manifest_rows: list[dict[str, str]],
    module: str,
    saved_paths: list[Path],
    operator_count: int,
) -> None:
    manifest_rows.append(
        {
            "module": module,
            "figure": f"module_operator_curves_{safe_module_stem(module)}",
            "path": str(primary_saved_path(saved_paths)),
            "operator_count": str(operator_count),
        }
    )


def write_operator_curve_manifest(path: Path, manifest_rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = ["module", "figure", "path", "operator_count"]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(manifest_rows)
    log(f"wrote {path}")


def plot_operator_figures(rows: list[BenchRow], output_dir: Path, formats: list[str], dpi: int) -> None:
    by_op: dict[tuple[str, str], list[BenchRow]] = defaultdict(list)
    for row in rows:
        by_op[row.op_key].append(row)

    operator_dir = output_dir / "operator_figures"
    operator_dir.mkdir(parents=True, exist_ok=True)
    manifest_rows: list[dict[str, str]] = []
    by_module: dict[str, list[tuple[tuple[str, str], list[BenchRow]]]] = defaultdict(list)
    for key, op_rows in by_op.items():
        by_module[key[0]].append((key, sorted(op_rows, key=lambda row: (row.scale_level, row.scale_value))))

    for module, module_items in sorted(by_module.items()):
        module_items.sort(key=lambda item: item[0][1])
        operator_count = len(module_items)
        fig_height = max(3.0, min(24.0, 0.62 * operator_count + 1.35))
        fig, axes = plt.subplots(
            operator_count,
            2,
            figsize=(9.2, fig_height),
            sharex="col",
            squeeze=False,
            gridspec_kw={"width_ratios": [1.0, 1.0], "wspace": 0.18, "hspace": 0.16},
        )

        for row_index, (key, op_rows) in enumerate(module_items):
            levels = [row.scale_level for row in op_rows]
            cpu = np.array([row.cpu_median_ms for row in op_rows], dtype=float)
            gpu = np.array([row.gpu_e2e_median_ms for row in op_rows], dtype=float)
            e2e_speedup = np.array([row.gpu_e2e_speedup for row in op_rows], dtype=float)
            kernel_speedup = np.array([row.gpu_kernel_speedup for row in op_rows], dtype=float)
            ax_time, ax_speed = axes[row_index]

            ax_time.text(
                -0.02,
                0.5,
                key[1],
                transform=ax_time.transAxes,
                ha="right",
                va="center",
                fontsize=5.7,
                color="#26323A",
                clip_on=False,
            )
            if np.isfinite(cpu).any() and np.isfinite(gpu).any():
                ax_time.plot(levels, cpu, marker="o", markersize=2.2, linewidth=0.9, color="#A54B3D", label="CPU")
                ax_time.plot(levels, gpu, marker="o", markersize=2.2, linewidth=0.9, color="#2F6F5E", label="GPU")
                positive = np.concatenate([cpu[cpu > 0.0], gpu[gpu > 0.0]])
                if positive.size:
                    ax_time.set_yscale("log")
                    ax_time.set_ylim(max(float(np.min(positive)) * 0.55, 1.0e-6), float(np.max(positive)) * 1.95)
            else:
                ax_time.text(0.5, 0.5, "No timing", ha="center", va="center", transform=ax_time.transAxes, fontsize=5.5)

            if np.isfinite(e2e_speedup).any():
                ax_speed.plot(levels, e2e_speedup, marker="o", markersize=2.2, linewidth=0.9, color="#375A7F", label="e2e")
            if np.isfinite(kernel_speedup).any():
                ax_speed.plot(levels, kernel_speedup, marker="s", markersize=2.0, linewidth=0.8, color="#8A6F2A", label="kernel")
            positive_speedup = np.concatenate([
                e2e_speedup[e2e_speedup > 0.0],
                kernel_speedup[kernel_speedup > 0.0],
            ])
            if positive_speedup.size:
                ax_speed.set_yscale("log")
                ax_speed.set_ylim(max(float(np.min(positive_speedup)) * 0.55, 1.0e-3), float(np.max(positive_speedup)) * 1.95)
            ax_speed.axhline(1.0, color="#333333", linewidth=0.55, linestyle="--")

            for ax in (ax_time, ax_speed):
                ax.grid(True, which="both", color="#DDDDDD", linewidth=0.32)
                ax.tick_params(labelsize=5.5, length=2.0, pad=1.0)
                ax.set_xticks(levels)
                ax.set_xticklabels([f"L{level}" for level in levels])

            if row_index == 0:
                ax_time.set_title("CPU/GPU e2e time (ms, log)", fontsize=7.2, pad=4)
                ax_speed.set_title("CPU/GPU speedup (log)", fontsize=7.2, pad=4)
                ax_time.legend(loc="upper right", frameon=False, ncols=2, fontsize=5.6, handlelength=1.3)
                ax_speed.legend(loc="upper right", frameon=False, ncols=2, fontsize=5.6, handlelength=1.3)
            if row_index != operator_count - 1:
                ax_time.tick_params(axis="x", labelbottom=False)
                ax_speed.tick_params(axis="x", labelbottom=False)

        axes[-1, 0].set_xlabel("Scale level", fontsize=6.5)
        axes[-1, 1].set_xlabel("Scale level", fontsize=6.5)
        fig.suptitle(
            f"{module}: compact per-operator CPU/GPU curves",
            y=0.995,
            fontsize=10,
            fontweight="bold",
        )
        fig.tight_layout(rect=(0.13, 0.0, 1.0, 0.975))
        saved = save_figure(
            fig,
            operator_dir,
            f"module_operator_curves_{safe_module_stem(module)}",
            formats,
            dpi,
        )
        append_operator_curve_manifest(manifest_rows, module, saved, operator_count)

    write_operator_curve_manifest(operator_dir / "latest_operator_curve_manifest.csv", manifest_rows)


def safe_module_stem(module: str) -> str:
    return "".join(ch if ch.isalnum() or ch in {"_", "-"} else "_" for ch in module)


def grouped_rows_by_module(rows: list[BenchRow]) -> dict[str, list[BenchRow]]:
    by_module: dict[str, list[BenchRow]] = defaultdict(list)
    for row in rows:
        by_module[row.module].append(row)
    return {
        module: sorted(module_rows, key=lambda row: (row.operator, row.scale_level, row.scale_value))
        for module, module_rows in sorted(by_module.items())
    }


def word_height(operator_count: int, base: float, per_operator: float, minimum: float) -> float:
    return max(minimum, base + per_operator * operator_count)


def word_labels(op_keys: list[tuple[str, str]]) -> list[str]:
    return [f"{module}/{operator}" for module, operator in op_keys]


def draw_word_heatmap(
    ax: plt.Axes,
    data: np.ndarray,
    title: str,
    colorbar_label: str,
    scale_levels: list[int],
    labels: list[str],
    op_keys: list[tuple[str, str]],
    cmap: str,
    vcenter: float | None = None,
) -> None:
    masked = np.ma.masked_invalid(data)
    if vcenter is None:
        norm = None
    else:
        finite = data[np.isfinite(data)]
        extent = max(abs(float(np.nanmin(finite))), abs(float(np.nanmax(finite))), 1e-6) if finite.size else 1.0
        norm = mcolors.TwoSlopeNorm(vcenter=vcenter, vmin=-extent, vmax=extent)
    image = ax.imshow(masked, aspect="auto", interpolation="nearest", cmap=cmap, norm=norm)
    ax.set_title(title, pad=4, fontsize=7.0)
    ax.set_xticks(np.arange(len(scale_levels)))
    ax.set_xticklabels([f"L{level}" for level in scale_levels], fontsize=6.0)
    ax.set_xlabel("Scale", fontsize=6.5)
    ax.set_yticks(np.arange(len(labels)))
    ax.set_yticklabels(labels, fontsize=5.5)
    ax.set_ylabel("Operator", fontsize=6.5)
    ax.tick_params(length=0, pad=1)
    add_module_separators(ax, op_keys)
    cbar = plt.colorbar(image, ax=ax, fraction=0.045, pad=0.012)
    cbar.ax.tick_params(labelsize=5.5, length=0, pad=1)
    cbar.ax.set_ylabel(colorbar_label, rotation=90, fontsize=6.0)


def draw_word_status_heatmap(
    ax: plt.Axes,
    status: np.ndarray,
    scale_levels: list[int],
    labels: list[str],
    op_keys: list[tuple[str, str]],
) -> None:
    cmap = mcolors.ListedColormap(["#B84A59", "#2F6F5E"])
    cmap.set_bad("#F2F2F2")
    image = ax.imshow(np.ma.masked_invalid(status), aspect="auto", interpolation="nearest", cmap=cmap, vmin=0.0, vmax=1.0)
    ax.set_title("Status", pad=4, fontsize=7.0)
    ax.set_xticks(np.arange(len(scale_levels)))
    ax.set_xticklabels([f"L{level}" for level in scale_levels], fontsize=6.0)
    ax.set_xlabel("Scale", fontsize=6.5)
    ax.set_yticks(np.arange(len(labels)))
    ax.set_yticklabels(labels, fontsize=5.5)
    ax.set_ylabel("Operator", fontsize=6.5)
    ax.tick_params(length=0, pad=1)
    add_module_separators(ax, op_keys)
    cbar = plt.colorbar(image, ax=ax, fraction=0.045, pad=0.012, ticks=[0.25, 0.75])
    cbar.ax.set_yticklabels(["Fail", "Pass"], fontsize=5.5)


def add_word_title(fig: plt.Figure, module: str, title: str) -> None:
    fig.suptitle(f"{module}: {title}", y=0.99, fontsize=9.0, fontweight="bold")


def primary_saved_path(saved_paths: list[Path]) -> Path:
    png_paths = [path for path in saved_paths if path.suffix.lower() == ".png"]
    return png_paths[0] if png_paths else saved_paths[0]


def append_word_manifest(
    manifest_rows: list[dict[str, str]],
    module: str,
    figure: str,
    saved_paths: list[Path],
    operator_count: int,
) -> None:
    manifest_rows.append(
        {
            "module": module,
            "figure": figure,
            "path": str(primary_saved_path(saved_paths)),
            "operator_count": str(operator_count),
        }
    )


def write_word_manifest(path: Path, manifest_rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = ["module", "figure", "path", "operator_count"]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(manifest_rows)
    log(f"wrote {path}")


def plot_word_overview(
    module: str,
    rows: list[BenchRow],
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
) -> None:
    op_keys = sorted_operator_keys(rows)
    scale_levels = sorted_scale_levels(rows)
    labels = word_labels(op_keys)
    operator_count = len(op_keys)
    fig, axes = plt.subplots(2, 2, figsize=(6.3, word_height(operator_count, 2.0, 0.28, 4.6)))

    draw_word_heatmap(
        axes[0, 0],
        log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_e2e_speedup"), floor=1.0e-12),
        "GPU e2e speedup",
        "log10(CPU/GPU)",
        scale_levels,
        labels,
        op_keys,
        "RdBu_r",
        vcenter=0.0,
    )
    draw_word_heatmap(
        axes[0, 1],
        log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_kernel_speedup"), floor=1.0e-12),
        "GPU kernel speedup",
        "log10(CPU/GPU)",
        scale_levels,
        labels,
        op_keys,
        "RdBu_r",
        vcenter=0.0,
    )
    draw_word_heatmap(
        axes[1, 0],
        log10_or_floor(matrix_for(rows, op_keys, scale_levels, "mixed_error")),
        "Mixed error",
        "log10(error)",
        scale_levels,
        labels,
        op_keys,
        "magma_r",
    )
    draw_word_status_heatmap(axes[1, 1], status_matrix(rows, op_keys, scale_levels), scale_levels, labels, op_keys)
    add_word_title(fig, module, "accuracy and performance overview")
    fig.tight_layout(rect=(0, 0, 1, 0.96), h_pad=0.8, w_pad=0.6)
    figure = f"figure_1_accuracy_performance_overview_{safe_module_stem(module)}"
    append_word_manifest(manifest_rows, module, figure, save_figure(fig, word_dir, figure, formats, dpi), operator_count)


def plot_word_time_heatmaps(
    module: str,
    rows: list[BenchRow],
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
) -> None:
    op_keys = sorted_operator_keys(rows)
    scale_levels = sorted_scale_levels(rows)
    labels = word_labels(op_keys)
    operator_count = len(op_keys)
    fig, axes = plt.subplots(2, 1, figsize=(6.3, word_height(operator_count, 2.1, 0.38, 4.6)))

    draw_word_heatmap(
        axes[0],
        log10_or_floor(matrix_for(rows, op_keys, scale_levels, "cpu_median_ms"), floor=1.0e-6),
        "CPU e2e median time",
        "log10(ms)",
        scale_levels,
        labels,
        op_keys,
        "viridis",
    )
    draw_word_heatmap(
        axes[1],
        log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_e2e_median_ms"), floor=1.0e-6),
        "GPU e2e median time",
        "log10(ms)",
        scale_levels,
        labels,
        op_keys,
        "viridis",
    )
    add_word_title(fig, module, "CPU/GPU e2e timing")
    fig.tight_layout(rect=(0, 0, 1, 0.96), h_pad=0.7)
    figure = f"figure_2_cpu_gpu_e2e_time_heatmaps_{safe_module_stem(module)}"
    append_word_manifest(manifest_rows, module, figure, save_figure(fig, word_dir, figure, formats, dpi), operator_count)


def plot_word_speedup_heatmap(
    module: str,
    rows: list[BenchRow],
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
) -> None:
    op_keys = sorted_operator_keys(rows)
    scale_levels = sorted_scale_levels(rows)
    labels = word_labels(op_keys)
    operator_count = len(op_keys)
    fig, ax = plt.subplots(1, 1, figsize=(6.3, word_height(operator_count, 1.4, 0.27, 2.8)))
    draw_word_heatmap(
        ax,
        log10_or_floor(matrix_for(rows, op_keys, scale_levels, "gpu_e2e_speedup"), floor=1.0e-12),
        "GPU e2e speedup",
        "log10(CPU/GPU)",
        scale_levels,
        labels,
        op_keys,
        "RdBu_r",
        vcenter=0.0,
    )
    add_word_title(fig, module, "GPU acceleration by scale")
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    figure = f"figure_3_e2e_speedup_heatmap_{safe_module_stem(module)}"
    append_word_manifest(manifest_rows, module, figure, save_figure(fig, word_dir, figure, formats, dpi), operator_count)


def plot_word_largest_scale_scatter(
    module: str,
    rows: list[BenchRow],
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
) -> None:
    valid = [
        row for row in largest_scale_rows(rows)
        if row.cpu_median_ms > 0.0
        and row.gpu_e2e_median_ms > 0.0
        and math.isfinite(row.cpu_median_ms)
        and math.isfinite(row.gpu_e2e_median_ms)
    ]
    fig, ax = plt.subplots(1, 1, figsize=(6.3, 4.2))
    if valid:
        x_values = [row.cpu_median_ms for row in valid]
        y_values = [row.gpu_e2e_median_ms for row in valid]
        ax.scatter(x_values, y_values, color="#2F6F5E", s=18, alpha=0.9, edgecolors="white", linewidths=0.35)
        values = [value for row in valid for value in (row.cpu_median_ms, row.gpu_e2e_median_ms)]
        lo = min(values) * 0.7
        hi = max(values) * 1.4
        ax.plot([lo, hi], [lo, hi], color="#333333", linewidth=0.8, linestyle="--", label="CPU = GPU")
        for index, row in enumerate(valid):
            ax.annotate(
                row.operator,
                (row.cpu_median_ms, row.gpu_e2e_median_ms),
                xytext=(3, 3 if index % 2 == 0 else -6),
                textcoords="offset points",
                fontsize=5.0,
            )
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.set_xlim(lo, hi)
        ax.set_ylim(lo, hi)
        ax.legend(loc="upper left", frameon=False, fontsize=6.0)
    else:
        ax.text(0.5, 0.5, "No CPU/GPU timing columns available", ha="center", va="center", transform=ax.transAxes, fontsize=7.0)
    ax.set_title("Largest-scale CPU vs GPU e2e time", fontsize=7.0)
    ax.set_xlabel("CPU median time (ms)", fontsize=6.5)
    ax.set_ylabel("GPU e2e median time (ms)", fontsize=6.5)
    ax.tick_params(labelsize=6.0)
    ax.grid(True, which="both", color="#DDDDDD", linewidth=0.45)
    add_word_title(fig, module, "largest-scale CPU vs GPU")
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    figure = f"figure_4_largest_scale_cpu_vs_gpu_scatter_{safe_module_stem(module)}"
    append_word_manifest(manifest_rows, module, figure, save_figure(fig, word_dir, figure, formats, dpi), len(sorted_operator_keys(rows)))


def plot_word_largest_scale_speedup_rank(
    module: str,
    rows: list[BenchRow],
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
) -> None:
    valid = [
        row for row in largest_scale_rows(rows)
        if row.gpu_e2e_speedup > 0.0 and math.isfinite(row.gpu_e2e_speedup)
    ]
    valid.sort(key=lambda row: row.gpu_e2e_speedup)
    operator_count = len(sorted_operator_keys(rows))
    fig, ax = plt.subplots(1, 1, figsize=(6.3, word_height(operator_count, 1.2, 0.28, 2.7)))
    if valid:
        labels = [row.op_label for row in valid]
        values = [row.gpu_e2e_speedup for row in valid]
        colors = ["#B84A59" if value < 1.0 else "#2F6F5E" for value in values]
        y = np.arange(len(valid))
        ax.barh(y, values, color=colors, height=0.72)
        ax.axvline(1.0, color="#333333", linewidth=0.8, linestyle="--")
        ax.set_yticks(y)
        ax.set_yticklabels(labels, fontsize=5.8)
        ax.set_xscale("log")
        ax.set_xlabel("CPU / GPU e2e speedup at largest scale", fontsize=6.5)
    else:
        ax.text(0.5, 0.5, "No speedup data available", ha="center", va="center", transform=ax.transAxes, fontsize=7.0)
    ax.set_title("Largest-scale GPU speedup ranking", fontsize=7.0)
    ax.tick_params(axis="x", labelsize=6.0)
    ax.grid(True, axis="x", color="#DDDDDD", linewidth=0.45)
    add_word_title(fig, module, "largest-scale speedup ranking")
    fig.tight_layout(rect=(0, 0, 1, 0.94))
    figure = f"figure_5_largest_scale_speedup_rank_{safe_module_stem(module)}"
    append_word_manifest(manifest_rows, module, figure, save_figure(fig, word_dir, figure, formats, dpi), operator_count)


def plot_word_figures(rows: list[BenchRow], output_dir: Path, formats: list[str], dpi: int) -> None:
    word_dir = output_dir / "word_figures"
    word_dir.mkdir(parents=True, exist_ok=True)
    manifest_rows: list[dict[str, str]] = []
    for module, module_rows in grouped_rows_by_module(rows).items():
        plot_word_overview(module, module_rows, word_dir, formats, dpi, manifest_rows)
        plot_word_time_heatmaps(module, module_rows, word_dir, formats, dpi, manifest_rows)
        plot_word_speedup_heatmap(module, module_rows, word_dir, formats, dpi, manifest_rows)
        plot_word_largest_scale_scatter(module, module_rows, word_dir, formats, dpi, manifest_rows)
        plot_word_largest_scale_speedup_rank(module, module_rows, word_dir, formats, dpi, manifest_rows)
    write_word_manifest(word_dir / "latest_word_figure_manifest.csv", manifest_rows)


def benchmark_totals(rows: list[BenchRow]) -> dict[str, str]:
    op_count = len({row.op_key for row in rows})
    passed_count = sum(1 for row in rows if row.passed)
    max_error = finite_max([row.mixed_error for row in rows])
    median_speedup = finite_median([row.gpu_e2e_speedup for row in rows])
    gpu_names = sorted({row.gpu_name for row in rows if row.gpu_name})
    return {
        "operator_count": str(op_count),
        "record_count": str(len(rows)),
        "passed_count": str(passed_count),
        "max_mixed_error": f"{max_error:.6g}" if math.isfinite(max_error) else "n/a",
        "median_e2e_speedup": f"{median_speedup:.3f}x" if math.isfinite(median_speedup) else "n/a",
        "gpu_name": gpu_names[0] if gpu_names else "n/a",
    }


def error_bins(rows: list[BenchRow]) -> list[tuple[str, int]]:
    bins = [
        ("<1e-6", lambda value: value < 1.0e-6),
        ("1e-6~1e-5", lambda value: 1.0e-6 <= value < 1.0e-5),
        ("1e-5~1e-4", lambda value: 1.0e-5 <= value < 1.0e-4),
        (">=1e-4", lambda value: value >= 1.0e-4),
    ]
    finite_errors = [row.mixed_error for row in rows if math.isfinite(row.mixed_error)]
    return [(label, sum(1 for value in finite_errors if predicate(value))) for label, predicate in bins]


def scale_speedup_medians(rows: list[BenchRow]) -> list[tuple[int, float]]:
    by_scale: dict[int, list[float]] = defaultdict(list)
    for row in rows:
        by_scale[row.scale_level].append(row.gpu_e2e_speedup)
    return [(scale, finite_median(values)) for scale, values in sorted(by_scale.items())]


def module_largest_scale_speedup_medians(rows: list[BenchRow]) -> list[tuple[str, float]]:
    by_module: dict[str, list[float]] = defaultdict(list)
    for row in largest_scale_rows(rows):
        by_module[row.module].append(row.gpu_e2e_speedup)
    values = [(module, finite_median(speedups)) for module, speedups in by_module.items()]
    return sorted(
        values,
        key=lambda item: (item[1] if math.isfinite(item[1]) else -math.inf, item[0]),
        reverse=True,
    )


def append_word_summary_manifest(
    manifest_rows: list[dict[str, str]],
    figure_number: str,
    title: str,
    saved_paths: list[Path],
    csv_path: Path,
) -> None:
    manifest_rows.append(
        {
            "figure_number": figure_number,
            "title": title,
            "path": str(primary_saved_path(saved_paths)),
            "data_source": str(csv_path),
        }
    )


def write_word_summary_manifest(path: Path, manifest_rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    columns = ["figure_number", "title", "path", "data_source"]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(manifest_rows)
    log(f"wrote {path}")


def word_summary_title(chinese: str, english: str, use_chinese: bool) -> str:
    return chinese if use_chinese else english


def plot_word_summary_validation_error(
    rows: list[BenchRow],
    csv_path: Path,
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
    use_chinese: bool,
) -> None:
    totals = benchmark_totals(rows)
    labels_counts = error_bins(rows)
    title = word_summary_title("53 个核心算子验证状态与误差分布", "Validation status and mixed-error distribution", use_chinese)
    fig, (ax_cards, ax_bar) = plt.subplots(
        1,
        2,
        figsize=(10.4, 5.85),
        gridspec_kw={"width_ratios": [1.0, 1.25]},
    )
    fig.suptitle(title, fontsize=16, fontweight="bold", y=0.97)

    ax_cards.axis("off")
    card_items = [
        (word_summary_title("核心算子数", "Operators", use_chinese), totals["operator_count"]),
        (word_summary_title("验证通过", "Passed rows", use_chinese), f'{totals["passed_count"]}/{totals["record_count"]}'),
        (word_summary_title("最大 mixed_error", "Max mixed_error", use_chinese), totals["max_mixed_error"]),
        (word_summary_title("全量 e2e 加速比中位数", "Median e2e speedup", use_chinese), totals["median_e2e_speedup"]),
        (word_summary_title("测试 GPU", "GPU", use_chinese), totals["gpu_name"]),
    ]
    for index, (label, value) in enumerate(card_items):
        y = 0.86 - index * 0.18
        ax_cards.text(
            0.06,
            y,
            label,
            ha="left",
            va="center",
            fontsize=11,
            color="#46505A",
            transform=ax_cards.transAxes,
        )
        ax_cards.text(
            0.58,
            y,
            value,
            ha="left",
            va="center",
            fontsize=14 if index < 4 else 10,
            fontweight="bold",
            color="#193B59",
            transform=ax_cards.transAxes,
            bbox={"boxstyle": "round,pad=0.35", "facecolor": "#F3F6F8", "edgecolor": "#D8E0E6", "linewidth": 0.8},
        )
    ax_cards.text(
        0.06,
        0.04,
        word_summary_title("数据来源：all_ops_large benchmark CSV", "Source: all_ops_large benchmark CSV", use_chinese),
        ha="left",
        va="bottom",
        fontsize=8,
        color="#68737D",
        transform=ax_cards.transAxes,
    )

    labels = [item[0] for item in labels_counts]
    counts = [item[1] for item in labels_counts]
    colors = ["#2F6F5E", "#6EA4BF", "#E0A84F", "#B84A59"]
    bars = ax_bar.bar(labels, counts, color=colors, width=0.62)
    ax_bar.set_title(word_summary_title("mixed_error 区间分布", "mixed_error bins", use_chinese), fontsize=12, pad=10)
    ax_bar.set_ylabel(word_summary_title("记录数", "Rows", use_chinese))
    ax_bar.grid(True, axis="y", color="#E2E6EA", linewidth=0.8)
    ax_bar.set_axisbelow(True)
    ax_bar.tick_params(axis="x", labelrotation=18)
    ymax = max(counts) * 1.18 if counts else 1.0
    ax_bar.set_ylim(0.0, ymax)
    for bar, count in zip(bars, counts):
        ax_bar.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + ymax * 0.025,
            str(count),
            ha="center",
            va="bottom",
            fontsize=11,
            fontweight="bold",
        )
    fig.tight_layout(rect=(0, 0, 1, 0.93), w_pad=2.4)
    saved = save_figure(fig, word_dir, "figure_3_2_validation_error_distribution", formats, dpi)
    append_word_summary_manifest(manifest_rows, "图 3-2", "53 个核心算子验证状态与误差分布图", saved, csv_path)


def plot_word_summary_scale_speedup(
    rows: list[BenchRow],
    csv_path: Path,
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
    use_chinese: bool,
) -> None:
    values = scale_speedup_medians(rows)
    title = word_summary_title("53 个核心算子 L1-L6 加速比中位数趋势", "Median e2e speedup across L1-L6", use_chinese)
    fig, ax = plt.subplots(1, 1, figsize=(9.6, 5.4))
    labels = [f"L{scale}" for scale, _ in values]
    medians = [median for _, median in values]
    colors = ["#DDE9F2", "#BFD8EA", "#91BCD7", "#659FBE", "#397F9F", "#1F5F7A"][: len(values)]
    bars = ax.bar(labels, medians, color=colors, width=0.62, edgecolor="#FFFFFF", linewidth=1.2)
    ax.plot(labels, medians, color="#193B59", marker="o", linewidth=2.0)
    ax.set_title(title, fontsize=16, fontweight="bold", pad=14)
    ax.set_ylabel(word_summary_title("e2e 加速比中位数", "Median e2e speedup", use_chinese))
    ax.grid(True, axis="y", color="#E2E6EA", linewidth=0.8)
    ax.set_axisbelow(True)
    ymax = max(medians) * 1.22 if medians else 1.0
    ax.set_ylim(0.0, ymax)
    for bar, median in zip(bars, medians):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + ymax * 0.025,
            f"{median:.3f}x",
            ha="center",
            va="bottom",
            fontsize=11,
            fontweight="bold",
            color="#193B59",
        )
    ax.text(
        0.01,
        -0.16,
        word_summary_title("统计口径：每个规模下 53 个核心算子的 gpu_e2e_speedup 中位数", "Metric: median gpu_e2e_speedup across 53 operators per scale", use_chinese),
        transform=ax.transAxes,
        ha="left",
        va="top",
        fontsize=8.5,
        color="#68737D",
    )
    fig.tight_layout()
    saved = save_figure(fig, word_dir, "figure_3_3_scale_speedup_median", formats, dpi)
    append_word_summary_manifest(manifest_rows, "图 3-3", "53 个核心算子 L1-L6 加速比中位数趋势图", saved, csv_path)


def plot_word_summary_module_speedup(
    rows: list[BenchRow],
    csv_path: Path,
    word_dir: Path,
    formats: list[str],
    dpi: int,
    manifest_rows: list[dict[str, str]],
    use_chinese: bool,
) -> None:
    values = module_largest_scale_speedup_medians(rows)
    title = word_summary_title("最大规模下各模块加速比中位数对比", "Largest-scale median e2e speedup by module", use_chinese)
    modules = [module for module, _ in values]
    medians = [median for _, median in values]
    fig, ax = plt.subplots(1, 1, figsize=(9.8, 7.2))
    y = np.arange(len(values))
    colors = ["#2F6F5E" if value >= 100.0 else "#E0A84F" for value in medians]
    ax.barh(y, medians, color=colors, height=0.68)
    ax.set_yticks(y)
    ax.set_yticklabels(modules)
    ax.invert_yaxis()
    ax.set_xscale("log")
    ax.set_xlabel(word_summary_title("L6 e2e 加速比中位数（对数刻度）", "L6 median e2e speedup (log scale)", use_chinese))
    ax.set_title(title, fontsize=16, fontweight="bold", pad=14)
    ax.grid(True, axis="x", color="#E2E6EA", linewidth=0.8, which="both")
    ax.set_axisbelow(True)
    for row_index, value in enumerate(medians):
        ax.text(
            value * 1.08,
            row_index,
            f"{value:.3f}x",
            ha="left",
            va="center",
            fontsize=9.5,
            fontweight="bold",
            color="#193B59",
        )
    ax.text(
        0.01,
        -0.08,
        word_summary_title("统计口径：每个模块在最大规模记录上的 gpu_e2e_speedup 中位数", "Metric: median largest-scale gpu_e2e_speedup per module", use_chinese),
        transform=ax.transAxes,
        ha="left",
        va="top",
        fontsize=8.5,
        color="#68737D",
    )
    fig.tight_layout()
    saved = save_figure(fig, word_dir, "figure_3_4_module_l6_speedup_median", formats, dpi)
    append_word_summary_manifest(manifest_rows, "图 3-4", "最大规模下各模块加速比中位数对比图", saved, csv_path)


def plot_word_summary_figures(rows: list[BenchRow], csv_path: Path, output_dir: Path, formats: list[str], dpi: int) -> None:
    word_dir = output_dir / "word_summary_figures"
    word_dir.mkdir(parents=True, exist_ok=True)
    manifest_rows: list[dict[str, str]] = []
    use_chinese = find_cjk_font() is not None
    plot_word_summary_validation_error(rows, csv_path, word_dir, formats, dpi, manifest_rows, use_chinese)
    plot_word_summary_scale_speedup(rows, csv_path, word_dir, formats, dpi, manifest_rows, use_chinese)
    plot_word_summary_module_speedup(rows, csv_path, word_dir, formats, dpi, manifest_rows, use_chinese)
    write_word_summary_manifest(word_dir / "latest_word_summary_manifest.csv", manifest_rows)


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[2]
    csv_path = resolve_path(repo_root, args.csv)
    output_dir = resolve_path(repo_root, args.output_dir)
    formats = parse_formats(args.formats)

    if not args.keep_old_output and args.figure_set == "word":
        clean_word_outputs(output_dir / "word_figures")
    elif not args.keep_old_output and args.figure_set == "word-summary":
        clean_word_summary_outputs(output_dir / "word_summary_figures")
    elif not args.keep_old_output:
        clean_plot_outputs(output_dir)

    apply_style()
    rows = load_rows(csv_path)
    summaries = make_summaries(rows)
    summary_csv = output_dir / "latest_all_ops_plot_summary.csv"
    write_summary_csv(summary_csv, summaries)
    log(f"rows={len(rows)} operators={len(summaries)}")
    log(f"wrote {summary_csv}")
    if args.figure_set == "word":
        plot_word_figures(rows, output_dir, formats, args.dpi)
        return 0
    if args.figure_set == "word-summary":
        plot_word_summary_figures(rows, csv_path, output_dir, formats, args.dpi)
        return 0
    plot_overview(rows, output_dir, formats, args.dpi)
    if args.figure_set == "all":
        plot_time_heatmaps(rows, output_dir, formats, args.dpi)
        plot_speedup_heatmap(rows, output_dir, formats, args.dpi)
        plot_largest_scale_scatter(rows, output_dir, formats, args.dpi)
        plot_largest_scale_speedup_rank(rows, output_dir, formats, args.dpi)
        plot_operator_figures(rows, output_dir, formats, args.dpi)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
