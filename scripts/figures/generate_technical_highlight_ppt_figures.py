#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib import patches


REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "docs" / "submission" / "figures" / "technical_highlights_ppt"

FIGSIZE = (16, 9)
DPI = 300

COLORS = {
    "ink": "#243238",
    "muted": "#607d8b",
    "line": "#8aa0aa",
    "grid": "#e9eff2",
    "host": "#f1f3f4",
    "device": "#d9eaf6",
    "solution": "#dcebdc",
    "value": "#f4ead2",
    "cache": "#eadff1",
    "warn": "#b1742c",
    "accent": "#3f7192",
    "accent2": "#5d8d60",
    "panel": "#fbfcfd",
}


@dataclass(frozen=True)
class PptFigure:
    slug: str
    focus: str
    highlights: tuple[str, ...]
    evidence: tuple[str, ...]


PPT_FIGURES: tuple[PptFigure, ...] = (
    PptFigure(
        "01_parallel_operator_fusion",
        "把递推、归约、相位差等串行瓶颈合并讲成一条 ZQ500 并行化方法论。",
        (
            "sosfilt prefix-scan",
            "detrend two-stage reduction + Kahan",
            "vectorstrength / lombscargle reduction",
            "fm_demod phase-difference fusion",
        ),
        ("src/zhongkexin/filtering.cu", "src/zhongkexin/spectral.cu", "src/zhongkexin/demod.cu"),
    ),
    PptFigure(
        "02_frequency_radar_operator_fusion",
        "把 FFT 频域加速、雷达检测和线性代数路径整合为一张雷达算子簇图。",
        (
            "batched FFT",
            "pulse_doppler safe packing",
            "CA-CFAR integral image",
            "ambgfun tile FFT",
            "MVDR cuBLAS/cuSOLVER path",
        ),
        ("src/zhongkexin/radartools.cu", "tests/unit/radartools/", "scripts/test/READMEV3_8_4.md"),
    ),
    PptFigure(
        "03_workspace_cache_fusion",
        "把 DeviceStorage、Workspace、prepared cache、plan/cache 复用合并为数据驻留图。",
        (
            "DeviceStorage cache",
            "FilteringWorkspace + LineBasesCache",
            "resample / channelizer prepared cache",
            "SpectralWorkspace plan reuse",
            "firwin2 / chebwin / CWT cache",
        ),
        ("include/cusignal/core/types.hpp", "src/zhongkexin/filtering.cu", "src/zhongkexin/spectral.cu", "src/zhongkexin/windows.cu"),
    ),
    PptFigure(
        "04_task_pipeline_fusion",
        "把 Task1 与 Task2 端到端链路放到同一张图，对比算子组合、业务 gate 与证据产物。",
        (
            "Task1 radar pipeline",
            "Task2 multidomain pipeline",
            "CA-CFAR / ambgfun",
            "spectrogram / CWT",
            "Kalman gate",
        ),
        ("demo/task1_radar/", "demo/task2_features/", "data/reports/demo/"),
    ),
    PptFigure(
        "05_task2_postprocess_estimation_fusion",
        "把 Task2 fused 后处理、峰值筛选和 Kalman 批处理合并展示为 device-side 后处理链。",
        (
            "Task2 fused postprocessing",
            "peak select CUB path",
            "Kalman points-batched fast path",
            "device-side score / track",
        ),
        ("demo/task2_features/task2_features_zx_gpu.cu", "src/zhongkexin/peak_finding.cu", "src/zhongkexin/estimation.cu"),
    ),
    PptFigure(
        "06_validation_benchmark_evidence_fusion",
        "把单测、六档 benchmark、自验收、sanitizer 和图件报告串成一条可复跑证据链。",
        (
            "81 unit test entries",
            "53 ops L1-L6 benchmark",
            "precision audit",
            "demo self-validation",
            "invalid input / resource drift gate",
            "compute-sanitizer deep check",
            "plot report pipeline",
        ),
        ("tests/unit/", "scripts/test/", "data/reports/unit/", "data/reports/demo/"),
    ),
    PptFigure(
        "07_performance_precision_gate_fusion",
        "把 e2e speedup、kernel speedup、mixed_error、RMSE 和业务 gate 的口径放在一张图里讲清。",
        (
            "e2e speedup",
            "kernel speedup",
            "mixed_error / max_abs_error",
            "RMSE task gate",
            "GPU-only retest + CPU baseline cache",
        ),
        ("scripts/test/benchmark_all_ops_scales.py", "scripts/test/audit_all_ops_precision.py", "docs/submission/"),
    ),
)


def setup_style() -> None:
    plt.rcParams.update(
        {
            "font.family": ["Droid Sans Fallback", "DejaVu Sans"],
            "font.size": 16,
            "axes.linewidth": 1.0,
            "axes.unicode_minus": False,
            "figure.facecolor": "white",
            "savefig.facecolor": "white",
            "savefig.dpi": DPI,
            "svg.fonttype": "none",
            "pdf.fonttype": 42,
            "ps.fonttype": 42,
        }
    )


def new_canvas() -> tuple[plt.Figure, plt.Axes]:
    fig, ax = plt.subplots(figsize=FIGSIZE, dpi=DPI)
    ax.set_xlim(0, 16)
    ax.set_ylim(0, 9)
    ax.axis("off")
    fig.subplots_adjust(left=0, right=1, bottom=0, top=1)
    return fig, ax


def wrap_label(text: str, limit: int = 9) -> str:
    if "\n" in text:
        return text
    length = 0
    chunks: list[str] = []
    current: list[str] = []
    for ch in text:
        width = 1 if ord(ch) < 128 else 2
        if length + width > limit and current:
            chunks.append("".join(current))
            current = [ch]
            length = width
        else:
            current.append(ch)
            length += width
    if current:
        chunks.append("".join(current))
    return "\n".join(chunks)


def panel(ax: plt.Axes, x: float, y: float, w: float, h: float, label: str) -> None:
    ax.add_patch(
        patches.FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle="round,pad=0.02,rounding_size=0.08",
            linewidth=1.2,
            edgecolor="#cad6dc",
            facecolor=COLORS["panel"],
        )
    )
    ax.text(x + 0.25, y + h - 0.42, label, ha="left", va="center", fontsize=17, color=COLORS["muted"], fontweight="bold")


def box(
    ax: plt.Axes,
    x: float,
    y: float,
    w: float,
    h: float,
    text: str,
    *,
    face: str,
    fontsize: float = 16,
    weight: str = "normal",
    edge: str | None = None,
    limit: int = 11,
) -> None:
    ax.add_patch(
        patches.FancyBboxPatch(
            (x, y),
            w,
            h,
            boxstyle="round,pad=0.025,rounding_size=0.09",
            linewidth=1.35,
            edgecolor=edge or COLORS["line"],
            facecolor=face,
        )
    )
    ax.text(
        x + w / 2,
        y + h / 2,
        wrap_label(text, limit),
        ha="center",
        va="center",
        fontsize=fontsize,
        color=COLORS["ink"],
        fontweight=weight,
    )


def arrow(ax: plt.Axes, x1: float, y1: float, x2: float, y2: float, *, color: str | None = None, lw: float = 1.8) -> None:
    ax.annotate(
        "",
        xy=(x2, y2),
        xytext=(x1, y1),
        arrowprops=dict(arrowstyle="-|>", lw=lw, color=color or COLORS["accent"], mutation_scale=18, shrinkA=5, shrinkB=5),
    )


def evidence(ax: plt.Axes, items: tuple[str, ...]) -> None:
    text = " | ".join(items)
    ax.text(15.35, 0.38, text, ha="right", va="bottom", fontsize=11.5, color=COLORS["muted"])


def tag(ax: plt.Axes, x: float, y: float, text: str, *, face: str = "#eef4f7", width: float = 1.72) -> None:
    box(ax, x, y, width, 0.48, text, face=face, fontsize=13.5, limit=14)


def heatmap(ax: plt.Axes, x: float, y: float, w: float, h: float, *, seed: int = 3) -> None:
    rng = np.random.default_rng(seed)
    rows, cols = 7, 12
    data = rng.normal(0.5, 0.13, (rows, cols))
    data[2:4, 5:9] += 0.25
    for r in range(rows):
        for c in range(cols):
            v = float(np.clip(data[r, c], 0, 1))
            color = (0.84 - 0.22 * v, 0.94 - 0.15 * v, 0.98)
            ax.add_patch(
                patches.Rectangle(
                    (x + c * w / cols, y + r * h / rows),
                    w / cols,
                    h / rows,
                    facecolor=color,
                    edgecolor="white",
                    lw=0.25,
                )
            )
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=False, edgecolor=COLORS["line"], lw=1.0))


def curve(ax: plt.Axes, x: float, y: float, w: float, h: float, *, kind: str = "speed") -> None:
    t = np.linspace(0, 1, 160)
    if kind == "speed":
        yy = 0.15 + 0.72 * (1 - np.exp(-4.2 * t))
        color = COLORS["accent2"]
    elif kind == "error":
        yy = 0.18 + 0.66 * np.exp(-4.0 * t)
        color = "#8f5d7f"
    else:
        yy = 0.5 + 0.28 * np.sin(2 * np.pi * (2.3 * t))
        color = COLORS["accent"]
    ax.plot(x + w * t, y + h * yy, color=color, lw=2.5)
    if kind in {"speed", "error"}:
        yy2 = 0.15 + 0.25 * np.sqrt(t)
        ax.plot(x + w * t, y + h * yy2, color=COLORS["warn"], lw=1.8, ls="--")
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=False, edgecolor=COLORS["grid"], lw=1.0))


def bars(ax: plt.Axes, x: float, y: float, w: float, h: float, labels: tuple[str, ...], values: tuple[float, ...], *, color: str) -> None:
    ax.add_patch(patches.Rectangle((x, y), w, h, fill=False, edgecolor=COLORS["grid"], lw=1.0))
    gap = w / (len(values) * 3.0)
    bw = (w - gap * (len(values) + 1)) / len(values)
    for i, value in enumerate(values):
        bx = x + gap + i * (bw + gap)
        bh = h * 0.75 * value
        ax.add_patch(patches.Rectangle((bx, y + 0.22), bw, bh, facecolor=color, edgecolor="white", lw=0.5))
        ax.text(bx + bw / 2, y + 0.06, labels[i], ha="center", va="bottom", fontsize=12, color=COLORS["muted"])


def chip_row(
    ax: plt.Axes,
    x: float,
    y: float,
    labels: tuple[str, ...],
    *,
    face: str = "#eef4f7",
    width: float = 1.54,
    gap: float = 0.28,
) -> None:
    for i, label in enumerate(labels):
        tag(ax, x + i * (width + gap), y, label, face=face, width=width)


def draw_parallel_operator_fusion(figinfo: PptFigure) -> plt.Figure:
    fig, ax = new_canvas()
    panel(ax, 0.45, 0.78, 4.7, 7.65, "A. 串行瓶颈")
    panel(ax, 5.38, 0.78, 5.15, 7.65, "B. ZQ500 并行策略")
    panel(ax, 10.75, 0.78, 4.8, 7.65, "C. 统一收益")

    serial = (("sosfilt", "递推依赖"), ("detrend", "全轴求和"), ("periodogram", "逐频循环"), ("fm_demod", "相位/差分"))
    for i, (op, note) in enumerate(serial):
        y = 6.72 - i * 1.28
        box(ax, 0.85, y, 1.65, 0.74, op, face=COLORS["device"], fontsize=15, weight="bold", limit=12)
        box(ax, 2.72, y, 1.9, 0.74, note, face=COLORS["host"], fontsize=15, limit=9)
        arrow(ax, 2.5, y + 0.37, 2.72, y + 0.37, color=COLORS["warn"])
    for i in range(7):
        cx = 1.0 + i * 0.52
        ax.add_patch(patches.Circle((cx, 1.86), 0.16, facecolor="#f6e7d7", edgecolor=COLORS["warn"], lw=1.2))
        if i < 6:
            arrow(ax, cx + 0.17, 1.86, cx + 0.36, 1.86, color=COLORS["warn"], lw=1.3)
    ax.text(0.95, 1.28, "依赖链越长，CPU 循环越重", fontsize=14, color=COLORS["muted"])

    strategies = (("prefix-scan", "递推拆块"), ("two-stage\nreduction", "归约稳定"), ("shared\nreduction", "频点并行"), ("fused\nphase diff", "少一次回传"))
    for i, (kernel, note) in enumerate(strategies):
        x = 5.75 + (i % 2) * 2.22
        y = 6.55 - (i // 2) * 1.8
        box(ax, x, y, 1.88, 0.82, kernel, face=COLORS["solution"], fontsize=14.5, weight="bold", limit=12)
        box(ax, x, y - 0.78, 1.88, 0.5, note, face="#f5faf5", fontsize=13.5, limit=8)
    for lane in range(4):
        yy = 2.76 - lane * 0.42
        ax.plot([5.86, 9.96], [yy, yy], color=COLORS["grid"], lw=1.4)
        for step in range(5):
            ax.add_patch(
                patches.Rectangle(
                    (5.95 + step * 0.76 + (lane % 2) * 0.13, yy - 0.13),
                    0.48,
                    0.26,
                    facecolor="#cfe4ef" if step <= lane + 1 else "#f2f6f8",
                    edgecolor=COLORS["line"],
                    lw=0.5,
                )
            )
    ax.text(5.85, 1.16, "tile / block / warp 并行展开", fontsize=14, color=COLORS["muted"])

    box(ax, 11.18, 6.66, 3.85, 0.82, "Kernel 并行度\n明显提高", face=COLORS["value"], fontsize=16, weight="bold", limit=14)
    box(ax, 11.18, 5.48, 3.85, 0.82, "mixed_error\n保持受控", face=COLORS["value"], fontsize=16, weight="bold", limit=14)
    bars(ax, 11.26, 3.82, 3.55, 1.0, ("CPU", "e2e", "Kernel"), (1.0, 0.45, 0.18), color=COLORS["accent2"])
    curve(ax, 11.26, 2.08, 3.55, 0.95, kind="error")
    chip_row(ax, 11.18, 1.2, ("CSV", "JSON", "单测"), face="#eef4f7", width=1.28, gap=0.24)
    evidence(ax, figinfo.evidence)
    return fig


def draw_frequency_radar_operator_fusion(figinfo: PptFigure) -> plt.Figure:
    fig, ax = new_canvas()
    panel(ax, 0.45, 0.78, 5.1, 7.65, "A. 频域与雷达算子簇")
    panel(ax, 5.78, 0.78, 5.05, 7.65, "B. 并行执行路径")
    panel(ax, 11.05, 0.78, 4.5, 7.65, "C. 检测结果与证据")

    y = 6.8
    for i, label in enumerate(("回波", "匹配滤波", "pulse\nDoppler", "CA-CFAR", "ambgfun")):
        x = 0.82 + (i % 3) * 1.5
        yy = y - (i // 3) * 1.35
        box(ax, x, yy, 1.25, 0.72, label, face=COLORS["device"] if i else COLORS["host"], fontsize=13.5, weight="bold", limit=10)
        if i in (0, 1):
            arrow(ax, x + 1.25, yy + 0.36, x + 1.5, yy + 0.36)
    arrow(ax, 3.56, 7.16, 1.0, 5.82)
    arrow(ax, 2.07, 5.82, 2.32, 5.82)
    box(ax, 3.74, 5.46, 1.35, 0.72, "MVDR\n波束形成", face=COLORS["solution"], fontsize=13.5, weight="bold", limit=10)
    heatmap(ax, 0.88, 2.68, 2.28, 1.42, seed=7)
    heatmap(ax, 3.26, 2.68, 1.66, 1.42, seed=11)
    ax.text(0.9, 2.23, "距离-多普勒图", fontsize=14, color=COLORS["muted"])
    ax.text(3.25, 2.23, "模糊函数面", fontsize=14, color=COLORS["muted"])
    chip_row(ax, 0.88, 1.18, ("FFT", "积分图", "cuBLAS"), face="#eef4f7", width=1.28, gap=0.25)

    rows = (("Batch FFT", "R2C/C2C plan"), ("safe packing", "边界填充/截断"), ("Integral\nimage", "矩形窗 O(1) 求和"), ("Tile FFT", "显存峰值受控"))
    for i, (left, right) in enumerate(rows):
        yy = 6.75 - i * 1.18
        box(ax, 6.22, yy, 1.88, 0.68, left, face=COLORS["solution"], fontsize=14.5, weight="bold", limit=12)
        box(ax, 8.38, yy, 1.95, 0.68, right, face="#f7fbf7", fontsize=14, limit=12)
        arrow(ax, 8.1, yy + 0.34, 8.38, yy + 0.34)
    curve(ax, 6.28, 1.62, 3.8, 1.05, kind="speed")
    ax.text(6.28, 1.18, "大规模吞吐随 batch / tile 展开", fontsize=14, color=COLORS["muted"])

    box(ax, 11.45, 6.56, 3.55, 0.82, "目标检测\n业务 gate", face=COLORS["value"], fontsize=16, weight="bold", limit=12)
    box(ax, 11.45, 5.32, 3.55, 0.82, "CPU 语义\n保持一致", face=COLORS["value"], fontsize=16, weight="bold", limit=12)
    heatmap(ax, 11.58, 3.28, 3.08, 1.35, seed=19)
    ax.add_patch(patches.Circle((13.35, 3.95), 0.2, fill=False, edgecolor=COLORS["warn"], lw=2.0))
    ax.text(11.58, 2.82, "检测点 / 阈值面 / 波束响应", fontsize=14, color=COLORS["muted"])
    chip_row(ax, 11.35, 1.42, ("Task1", "unit", "report"), face="#eef4f7", width=1.25, gap=0.24)
    evidence(ax, figinfo.evidence)
    return fig


def draw_workspace_cache_fusion(figinfo: PptFigure) -> plt.Figure:
    fig, ax = new_canvas()
    panel(ax, 0.45, 0.78, 4.75, 7.65, "A. 固定开销来源")
    panel(ax, 5.45, 0.78, 5.05, 7.65, "B. Workspace / Cache")
    panel(ax, 10.75, 0.78, 4.8, 7.65, "C. 计时路径更干净")

    for i, label in enumerate(("cudaMalloc", "H2D 元数据", "FFT plan", "窗口/taps")):
        box(ax, 0.9, 6.82 - i * 1.08, 3.65, 0.66, label, face=COLORS["host"], fontsize=15, weight="bold" if i == 0 else "normal", limit=14)
    bars(ax, 0.92, 2.35, 3.55, 1.15, ("分配", "搬运", "准备", "Kernel"), (0.86, 0.72, 0.78, 0.34), color=COLORS["warn"])
    ax.text(0.9, 1.76, "小规模 e2e 容易被准备开销淹没", fontsize=14, color=COLORS["muted"])
    chip_row(ax, 0.92, 1.08, ("Host", "Device", "D2D"), face="#eef4f7", width=1.2, gap=0.2)

    box(ax, 5.92, 6.88, 1.42, 0.62, "Host", face=COLORS["host"], fontsize=15, weight="bold")
    box(ax, 5.92, 5.05, 1.42, 0.62, "Device", face=COLORS["device"], fontsize=15, weight="bold")
    cache_items = (("DeviceStorage", "分配池"), ("LineBasesCache", "轴线索引"), ("Prepared Cache", "taps/window"), ("Plan Reuse", "FFT/R2C"))
    for i, (name, note) in enumerate(cache_items):
        yy = 6.48 - i * 1.02
        box(ax, 7.72, yy, 2.08, 0.58, name, face=COLORS["cache"], fontsize=13.8, weight="bold", limit=14)
        ax.text(7.75, yy - 0.22, note, fontsize=12.5, color=COLORS["muted"])
        arrow(ax, 7.35, yy + 0.29, 7.72, yy + 0.29)
    ax.annotate(
        "",
        xy=(9.98, 6.62),
        xytext=(9.98, 3.6),
        arrowprops=dict(arrowstyle="<|-|>", lw=2.0, color=COLORS["accent2"], mutation_scale=20),
    )
    ax.text(5.9, 1.56, "复用 key:\nshape / dtype / device / window", fontsize=13.5, color=COLORS["muted"])

    box(ax, 11.18, 6.62, 3.85, 0.76, "repeat 主要测 Kernel\n而非重复构造", face=COLORS["value"], fontsize=16, weight="bold", limit=16)
    bars(ax, 11.28, 4.5, 3.48, 1.15, ("before", "after"), (1.0, 0.36), color=COLORS["accent2"])
    curve(ax, 11.28, 2.68, 3.48, 1.0, kind="speed")
    chip_row(ax, 11.1, 1.48, ("Cache", "D2D", "repeat"), face="#eef4f7", width=1.25, gap=0.24)
    evidence(ax, figinfo.evidence)
    return fig


def draw_task_pipeline_fusion(figinfo: PptFigure) -> plt.Figure:
    fig, ax = new_canvas()
    panel(ax, 0.45, 0.78, 7.45, 7.65, "A. Task1 雷达目标检测")
    panel(ax, 8.15, 0.78, 7.4, 7.65, "B. Task2 多域特征定位")

    y1 = 6.78
    task1 = ("回波", "匹配滤波", "Doppler", "CA-CFAR", "目标")
    for i, label in enumerate(task1):
        x = 0.9 + i * 1.32
        box(ax, x, y1, 1.08, 0.7, label, face=COLORS["device"] if i else COLORS["host"], fontsize=13.8, weight="bold", limit=8)
        if i < len(task1) - 1:
            arrow(ax, x + 1.08, y1 + 0.35, x + 1.32, y1 + 0.35)
    heatmap(ax, 0.95, 4.55, 2.55, 1.38, seed=21)
    curve(ax, 4.1, 4.55, 2.55, 1.38, kind="wave")
    box(ax, 1.0, 2.7, 2.6, 0.75, "业务 gate:\n目标命中", face=COLORS["value"], fontsize=15.5, weight="bold", limit=13)
    box(ax, 4.05, 2.7, 2.6, 0.75, "e2e 证据:\nJSON / 图件", face=COLORS["value"], fontsize=15.5, weight="bold", limit=13)
    chip_row(ax, 1.0, 1.45, ("pulse", "CFAR", "ambgfun"), face="#eef4f7")

    y2 = 6.78
    task2 = ("信号", "滤波/解调", "谱图/CWT", "峰值", "轨迹")
    for i, label in enumerate(task2):
        x = 8.6 + i * 1.32
        box(ax, x, y2, 1.08, 0.7, label, face=COLORS["device"] if i else COLORS["host"], fontsize=13.5, weight="bold", limit=8)
        if i < len(task2) - 1:
            arrow(ax, x + 1.08, y2 + 0.35, x + 1.32, y2 + 0.35)
    heatmap(ax, 8.65, 4.55, 2.5, 1.38, seed=25)
    curve(ax, 11.76, 4.55, 2.55, 1.38, kind="wave")
    box(ax, 8.7, 2.7, 2.6, 0.75, "融合后处理:\nDevice 驻留", face=COLORS["solution"], fontsize=15.5, weight="bold", limit=13)
    box(ax, 11.75, 2.7, 2.6, 0.75, "业务 gate:\nRMSE / track", face=COLORS["value"], fontsize=15.5, weight="bold", limit=13)
    chip_row(ax, 8.7, 1.45, ("spectrogram", "CWT", "Kalman"), face="#eef4f7")
    evidence(ax, figinfo.evidence)
    return fig


def draw_task2_postprocess_estimation_fusion(figinfo: PptFigure) -> plt.Figure:
    fig, ax = new_canvas()
    panel(ax, 0.45, 0.78, 4.85, 7.65, "A. 多域特征输入")
    panel(ax, 5.55, 0.78, 5.05, 7.65, "B. Device-side 后处理")
    panel(ax, 10.85, 0.78, 4.7, 7.65, "C. 轨迹输出")

    for i, label in enumerate(("spectrogram", "CWT", "correlate", "demod")):
        y = 6.8 - i * 1.05
        box(ax, 0.92, y, 1.72, 0.62, label, face=COLORS["device"], fontsize=14.5, weight="bold", limit=12)
        box(ax, 3.0, y, 1.62, 0.62, "feature map", face=COLORS["host"], fontsize=13.5, limit=12)
        arrow(ax, 2.64, y + 0.31, 3.0, y + 0.31)
    heatmap(ax, 1.0, 1.95, 3.18, 1.25, seed=29)
    ax.text(1.0, 1.52, "多域特征矩阵", fontsize=14, color=COLORS["muted"])

    flow = (("fused score", 6.65), ("CUB select", 5.35), ("row peaks", 4.05), ("Kalman batch", 2.75))
    for label, y in flow:
        box(ax, 6.15, y, 3.65, 0.72, label, face=COLORS["solution"], fontsize=16, weight="bold", limit=14)
    for _, y in flow[:-1]:
        arrow(ax, 7.98, y, 7.98, y - 0.55)
    for i in range(5):
        ax.add_patch(patches.Rectangle((6.2 + i * 0.62, 1.6), 0.42, 0.34 + 0.08 * i, facecolor="#cfe4ef", edgecolor=COLORS["line"], lw=0.7))
    ax.text(6.15, 1.18, "小状态批处理提高 occupancy", fontsize=14, color=COLORS["muted"])

    curve(ax, 11.35, 5.92, 3.28, 1.28, kind="wave")
    box(ax, 11.38, 4.58, 3.2, 0.72, "RMSE gate\n自动判定", face=COLORS["value"], fontsize=16, weight="bold", limit=14)
    curve(ax, 11.38, 2.8, 3.16, 1.05, kind="error")
    chip_row(ax, 11.18, 1.52, ("peaks", "track", "JSON"), face="#eef4f7", width=1.25, gap=0.24)
    evidence(ax, figinfo.evidence)
    return fig


def draw_validation_benchmark_evidence_fusion(figinfo: PptFigure) -> plt.Figure:
    fig, ax = new_canvas()
    panel(ax, 0.45, 0.78, 4.9, 7.65, "A. 输入与运行")
    panel(ax, 5.6, 0.78, 4.75, 7.65, "B. 统一度量")
    panel(ax, 10.6, 0.78, 4.95, 7.65, "C. 答辩证据")

    sources = (("81 单测入口", "tests/unit"), ("53 算子六档", "L1-L6"), ("Task demo", "Task1/Task2"), ("sanitizer", "memcheck"))
    for i, (main, sub) in enumerate(sources):
        y = 6.78 - i * 1.08
        box(ax, 0.95, y, 1.92, 0.62, main, face=COLORS["device"], fontsize=14.5, weight="bold", limit=12)
        box(ax, 3.1, y, 1.58, 0.62, sub, face=COLORS["host"], fontsize=13.5, limit=14)
        arrow(ax, 2.87, y + 0.31, 3.1, y + 0.31)
    bars(ax, 1.0, 1.75, 3.4, 1.08, ("L1", "L2", "L3", "L4", "L5", "L6"), (0.25, 0.36, 0.51, 0.67, 0.82, 0.96), color=COLORS["accent"])

    metrics = (("speedup", "e2e / kernel"), ("accuracy", "mixed_error"), ("business", "RMSE / pass"), ("resource", "RSS / CUDA"))
    for i, (main, sub) in enumerate(metrics):
        y = 6.78 - i * 1.08
        box(ax, 6.1, y, 1.72, 0.62, main, face=COLORS["solution"], fontsize=14.5, weight="bold", limit=12)
        box(ax, 8.04, y, 1.6, 0.62, sub, face="#f7fbf7", fontsize=13.2, limit=12)
        arrow(ax, 7.82, y + 0.31, 8.04, y + 0.31)
    curve(ax, 6.25, 1.75, 3.2, 1.08, kind="speed")

    outputs = (("CSV", "原始表"), ("JSON", "可追溯"), ("README", "索引"), ("PNG/SVG", "PPT 图件"))
    for i, (main, sub) in enumerate(outputs):
        x = 11.1 + (i % 2) * 1.95
        y = 6.75 - (i // 2) * 1.2
        box(ax, x, y, 1.56, 0.68, main, face=COLORS["value"], fontsize=15, weight="bold", limit=10)
        ax.text(x, y - 0.24, sub, fontsize=12.5, color=COLORS["muted"])
        arrow(ax, 9.7, 5.1, x, y + 0.34, color=COLORS["accent2"], lw=1.6)
    box(ax, 11.05, 2.72, 3.78, 0.78, "可复跑 / 可追溯\n避免只给截图", face=COLORS["value"], fontsize=16, weight="bold", limit=16)
    chip_row(ax, 10.98, 1.45, ("report", "gate", "plot"), face="#eef4f7", width=1.25, gap=0.24)
    evidence(ax, figinfo.evidence)
    return fig


def draw_performance_precision_gate_fusion(figinfo: PptFigure) -> plt.Figure:
    fig, ax = new_canvas()
    panel(ax, 0.45, 0.78, 4.85, 7.65, "A. 性能口径分离")
    panel(ax, 5.55, 0.78, 5.0, 7.65, "B. 精度口径分离")
    panel(ax, 10.8, 0.78, 4.75, 7.65, "C. 复测与业务 gate")

    box(ax, 0.92, 6.66, 3.78, 0.78, "e2e speedup\n含 H2D/D2H/准备", face=COLORS["value"], fontsize=15.5, weight="bold", limit=16)
    box(ax, 0.92, 5.36, 3.78, 0.78, "kernel speedup\n只看 ZQ500 GPU Kernel", face=COLORS["solution"], fontsize=15.5, weight="bold", limit=16)
    bars(ax, 1.08, 3.45, 3.3, 1.1, ("CPU", "e2e", "Kernel"), (1.0, 0.55, 0.22), color=COLORS["accent2"])
    ax.text(1.08, 2.85, "小规模 copy-bound，大规模吞吐更明显", fontsize=14, color=COLORS["muted"])
    chip_row(ax, 1.05, 1.48, ("L1-L6", "repeat", "CSV"), face="#eef4f7")

    precision = (("mixed_error", "综合误差"), ("max_abs_error", "最大绝对误差"), ("RMSE", "任务级轨迹"), ("pass/fail", "业务阈值"))
    for i, (main, sub) in enumerate(precision):
        y = 6.78 - i * 1.08
        box(ax, 6.05, y, 1.88, 0.62, main, face=COLORS["device"], fontsize=14.3, weight="bold", limit=14)
        box(ax, 8.28, y, 1.56, 0.62, sub, face=COLORS["host"], fontsize=13.5, limit=10)
        arrow(ax, 7.94, y + 0.31, 8.28, y + 0.31, color=COLORS["accent2"])
    curve(ax, 6.18, 1.78, 3.45, 1.12, kind="error")

    box(ax, 11.25, 6.68, 3.62, 0.76, "CPU baseline cache\n固定参考口径", face=COLORS["cache"], fontsize=15.5, weight="bold", limit=16)
    box(ax, 11.25, 5.38, 3.62, 0.76, "GPU-only retest\n快速刷新现场数据", face=COLORS["solution"], fontsize=15.5, weight="bold", limit=16)
    arrow(ax, 13.05, 6.68, 13.05, 6.14, color=COLORS["accent2"])
    box(ax, 11.25, 3.68, 3.62, 0.76, "任务 gate\n结果可解释", face=COLORS["value"], fontsize=15.5, weight="bold", limit=16)
    chip_row(ax, 11.12, 2.25, ("CPU", "CUDA", "gate"), face="#eef4f7", width=1.25, gap=0.24)
    evidence(ax, figinfo.evidence)
    return fig


DRAWERS = {
    "01_parallel_operator_fusion": draw_parallel_operator_fusion,
    "02_frequency_radar_operator_fusion": draw_frequency_radar_operator_fusion,
    "03_workspace_cache_fusion": draw_workspace_cache_fusion,
    "04_task_pipeline_fusion": draw_task_pipeline_fusion,
    "05_task2_postprocess_estimation_fusion": draw_task2_postprocess_estimation_fusion,
    "06_validation_benchmark_evidence_fusion": draw_validation_benchmark_evidence_fusion,
    "07_performance_precision_gate_fusion": draw_performance_precision_gate_fusion,
}


def save_figure(figinfo: PptFigure) -> None:
    fig = DRAWERS[figinfo.slug](figinfo)
    fig.savefig(OUTPUT_DIR / f"{figinfo.slug}.png", dpi=DPI)
    fig.savefig(OUTPUT_DIR / f"{figinfo.slug}.svg")
    plt.close(fig)


def write_readme() -> None:
    lines = [
        "# CETC 技术亮点 PPT 融合图索引",
        "",
        "本目录是面向答辩 PPT 的融合版图件：把 30 个逐算子技术亮点压缩为 7 张大字号复合示意图。每张图覆盖一组相关算子/工程机制，图内不放总标题，主标签字号更大，便于投影展示。",
        "",
        "逐算子细节图仍保留在 `docs/submission/figures/technical_highlights/`，本目录优先用于 PPT 正文。",
        "",
        "| 序号 | PPT 图件 | 覆盖亮点 | 视觉重点 | 证据路径 |",
        "|---:|---|---|---|---|",
    ]
    for index, figinfo in enumerate(PPT_FIGURES, start=1):
        highlights = "<br>".join(figinfo.highlights)
        evidence_text = "<br>".join(f"`{item}`" for item in figinfo.evidence)
        lines.append(
            f"| {index} | [`{figinfo.slug}.png`]({figinfo.slug}.png)<br>[`{figinfo.slug}.svg`]({figinfo.slug}.svg) | "
            f"{highlights} | {figinfo.focus} | {evidence_text} |"
        )
    lines.extend(
        [
            "",
            "重新生成：",
            "",
            "```bash",
            "python3 scripts/figures/generate_technical_highlight_ppt_figures.py",
            "```",
        ]
    )
    (OUTPUT_DIR / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    setup_style()
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for figinfo in PPT_FIGURES:
        save_figure(figinfo)
    write_readme()
    print(f"wrote {len(PPT_FIGURES)} PPT PNG/SVG figure pairs to {OUTPUT_DIR.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
