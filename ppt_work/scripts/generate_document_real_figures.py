#!/usr/bin/env python3
"""Generate the real-data figures used by the regional-final technical document.

Only files under data/reports/ and data/generated/ are read.  The script never
modifies benchmark or task reports.  SVG is generated with the Python standard
library so plotting does not require matplotlib; optional PNG conversion uses
LibreOffice plus pdftocairo when both are available.

Usage:
  python3 ppt_work/scripts/generate_document_real_figures.py
  python3 ppt_work/scripts/generate_document_real_figures.py --png --strict
"""

from __future__ import annotations

import argparse
import base64
import csv
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from dataclasses import dataclass
from html import escape
from pathlib import Path
from typing import Iterable, Sequence


REPO_ROOT = Path(__file__).resolve().parents[2]
REPORT_ROOT = REPO_ROOT / "data" / "reports" / "demo"
GENERATED_ROOT = REPO_ROOT / "data" / "generated" / "demo"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "ppt_work" / "final_images" / "document_real_data"

WIDTH = 1600
HEIGHT = 900
FONT = "Noto Sans CJK SC, Noto Sans CJK, sans-serif"
CPU_COLOR = "#174A8B"
GPU_COLOR = "#00A6C8"
ACCENT_COLOR = "#F28E2B"
GRID_COLOR = "#D9E2EC"
TEXT_COLOR = "#102A43"
MUTED_COLOR = "#627D98"


@dataclass(frozen=True)
class ScaleRow:
    task: str
    level: int
    input_elements: int
    cpu_ms: float
    gpu_ms: float
    speedup: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"output directory (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--png",
        action="store_true",
        help="also convert generated SVG files to PNG using LibreOffice and pdftocairo",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="return non-zero when a required output-sample CSV is absent",
    )
    return parser.parse_args()


def svg_document(elements: Iterable[str]) -> str:
    body = "\n  ".join(elements)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="{WIDTH}" height="{HEIGHT}" '
        f'viewBox="0 0 {WIDTH} {HEIGHT}">\n'
        f'  <rect width="100%" height="100%" fill="#FFFFFF"/>\n'
        f'  <style>text {{ font-family: {FONT}; fill: {TEXT_COLOR}; }}</style>\n'
        f'  {body}\n'
        "</svg>\n"
    )


def text(x: float, y: float, value: str, size: int = 26, *, anchor: str = "start",
         color: str = TEXT_COLOR, weight: str = "400") -> str:
    return (
        f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" text-anchor="{anchor}" '
        f'fill="{color}" font-weight="{weight}">{escape(value)}</text>'
    )


def line(x1: float, y1: float, x2: float, y2: float, *, color: str = GRID_COLOR,
         width: float = 2.0, dash: str | None = None) -> str:
    dash_attr = f' stroke-dasharray="{dash}"' if dash else ""
    return (
        f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
        f'stroke="{color}" stroke-width="{width}"{dash_attr}/>'
    )


def rect(x: float, y: float, width: float, height: float, *, fill: str = "none",
         stroke: str = "none", stroke_width: float = 0.0, radius: float = 0.0) -> str:
    return (
        f'<rect x="{x:.1f}" y="{y:.1f}" width="{width:.1f}" height="{height:.1f}" '
        f'rx="{radius:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{stroke_width}"/>'
    )


def path(points: Sequence[tuple[float, float]], *, color: str, width: float = 4.0) -> str:
    commands = " ".join(
        ("M" if index == 0 else "L") + f" {x:.1f} {y:.1f}"
        for index, (x, y) in enumerate(points)
    )
    return f'<path d="{commands}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round"/>'


def circle(x: float, y: float, radius: float, *, fill: str) -> str:
    return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{radius:.1f}" fill="{fill}"/>'


def write_svg(path: Path, elements: Iterable[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(svg_document(elements), encoding="utf-8")


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def read_scale_rows() -> dict[str, list[ScaleRow]]:
    summary_path = REPORT_ROOT / "scale_summary.json"
    payload = json.loads(summary_path.read_text(encoding="utf-8"))
    by_task: dict[str, list[ScaleRow]] = {}
    for row in payload["rows"]:
        item = ScaleRow(
            task=row["task"],
            level=int(row["level"]),
            input_elements=int(row["input_elements"]),
            cpu_ms=float(row["cpu_median_ms"]),
            gpu_ms=float(row["gpu_median_ms"]),
            speedup=float(row["speedup_cpu_over_gpu"]),
        )
        by_task.setdefault(item.task, []).append(item)
    for rows in by_task.values():
        rows.sort(key=lambda item: item.level)
    return by_task


def read_metrics(task: str, level: int = 6) -> dict:
    return json.loads(
        (REPORT_ROOT / task / "scales" / f"L{level}" / "metrics.json").read_text(encoding="utf-8")
    )


def read_sample_scenario(task: str) -> dict:
    path = GENERATED_ROOT / task / "input" / "scenario.json"
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"sample scenario must be an object: {path}")
    level = payload.get("scale_level")
    if not isinstance(level, int) or level not in range(1, 7):
        raise ValueError(f"sample scenario has invalid scale_level: {path}")
    return payload


def nice_upper(value: float) -> float:
    if value <= 0:
        return 1.0
    magnitude = 10 ** math.floor(math.log10(value))
    return math.ceil(value / magnitude * 1.1) * magnitude


def linear_y(value: float, min_value: float, max_value: float, top: float, height: float) -> float:
    if max_value == min_value:
        return top + height / 2
    return top + height * (1.0 - (value - min_value) / (max_value - min_value))


def log_y(value: float, min_value: float, max_value: float, top: float, height: float) -> float:
    lower = math.log10(max(min_value, 1e-12))
    upper = math.log10(max(max_value, 1e-12))
    current = math.log10(max(value, 1e-12))
    if upper == lower:
        return top + height / 2
    return top + height * (1.0 - (current - lower) / (upper - lower))


def chart_panel(
    rows: Sequence[ScaleRow],
    x: float,
    y: float,
    width: float,
    height: float,
    title_text: str,
    mode: str,
) -> list[str]:
    elements = [rect(x, y, width, height, fill="#FFFFFF", stroke="#B8C7D9", stroke_width=2, radius=16)]
    elements.append(text(x + 24, y + 42, title_text, 28, weight="700"))
    left, right, top, bottom = x + 85, x + width - 35, y + 85, y + height - 80
    plot_w, plot_h = right - left, bottom - top
    elements.extend([line(left, top, left, bottom, color="#8FA5BA"), line(left, bottom, right, bottom, color="#8FA5BA")])

    xs = [left + plot_w * index / max(1, len(rows) - 1) for index in range(len(rows))]
    for x_value, row in zip(xs, rows):
        elements.append(line(x_value, bottom, x_value, bottom + 8, color="#8FA5BA"))
        elements.append(text(x_value, bottom + 38, f"L{row.level}", 20, anchor="middle", color=MUTED_COLOR))

    if mode == "time":
        values_cpu = [row.cpu_ms for row in rows]
        values_gpu = [row.gpu_ms for row in rows]
        y_min = 10 ** math.floor(math.log10(min(values_gpu)))
        y_max = 10 ** math.ceil(math.log10(max(values_cpu)))
        ticks = [10 ** power for power in range(int(math.log10(y_min)), int(math.log10(y_max)) + 1)]
        for tick in ticks:
            yy = log_y(tick, y_min, y_max, top, plot_h)
            elements.append(line(left, yy, right, yy, color=GRID_COLOR, dash="5 7"))
            elements.append(text(left - 14, yy + 7, f"{tick:g}", 17, anchor="end", color=MUTED_COLOR))
        cpu_points = [(x_value, log_y(value, y_min, y_max, top, plot_h)) for x_value, value in zip(xs, values_cpu)]
        gpu_points = [(x_value, log_y(value, y_min, y_max, top, plot_h)) for x_value, value in zip(xs, values_gpu)]
        elements.extend([path(cpu_points, color=CPU_COLOR), path(gpu_points, color=GPU_COLOR)])
        elements.extend(circle(px, py, 6, fill=CPU_COLOR) for px, py in cpu_points)
        elements.extend(circle(px, py, 6, fill=GPU_COLOR) for px, py in gpu_points)
        elements.append(text(left, y + 68, "总耗时 / ms（对数坐标）", 18, color=MUTED_COLOR))
        legend_x = right - 210
        elements.extend([
            line(legend_x, y + 45, legend_x + 35, y + 45, color=CPU_COLOR, width=4),
            text(legend_x + 45, y + 52, "CPU", 18, color=MUTED_COLOR),
            line(legend_x + 115, y + 45, legend_x + 150, y + 45, color=GPU_COLOR, width=4),
            text(legend_x + 160, y + 52, "GPU E2E", 18, color=MUTED_COLOR),
        ])
    else:
        values = [row.speedup for row in rows]
        y_min = 0.0
        y_max = nice_upper(max(values))
        for index in range(5):
            tick = y_max * index / 4
            yy = linear_y(tick, y_min, y_max, top, plot_h)
            elements.append(line(left, yy, right, yy, color=GRID_COLOR, dash="5 7"))
            elements.append(text(left - 14, yy + 7, f"{tick:.0f}×", 17, anchor="end", color=MUTED_COLOR))
        points = [(x_value, linear_y(value, y_min, y_max, top, plot_h)) for x_value, value in zip(xs, values)]
        elements.append(path(points, color=ACCENT_COLOR, width=5))
        elements.extend(circle(px, py, 7, fill=ACCENT_COLOR) for px, py in points)
        for (px, py), value in zip(points, values):
            elements.append(text(px, py - 16, f"{value:.1f}×", 17, anchor="middle", color=ACCENT_COLOR, weight="700"))
        elements.append(text(left, y + 68, "CPU / GPU E2E 加速比", 18, color=MUTED_COLOR))
    return elements


def generate_scale_figure(rows: Sequence[ScaleRow], task_label: str, filename: str, output_dir: Path) -> Path:
    elements = [text(WIDTH / 2, 56, f"{task_label}：L1—L6 真实端到端性能", 38, anchor="middle", weight="700")]
    elements.extend(chart_panel(rows, 70, 110, 710, 680, "总耗时", "time"))
    elements.extend(chart_panel(rows, 820, 110, 710, 680, "端到端加速比", "speedup"))
    elements.append(text(WIDTH / 2, 850, "数据来源：data/reports/demo/scale_summary.json；CPU/GPU 均为 warm-up 后 median", 18, anchor="middle", color=MUTED_COLOR))
    path_out = output_dir / filename
    write_svg(path_out, elements)
    return path_out


def generate_combined_scale_figure(by_task: dict[str, list[ScaleRow]], output_dir: Path) -> Path:
    elements = [text(WIDTH / 2, 48, "Task1 / Task2：L1—L6 真实端到端性能", 36, anchor="middle", weight="700")]
    elements.extend(chart_panel(by_task["task1_radar"], 55, 85, 735, 360, "Task1 雷达任务", "time"))
    elements.extend(chart_panel(by_task["task1_radar"], 810, 85, 735, 360, "Task1 加速比", "speedup"))
    elements.extend(chart_panel(by_task["task2_features"], 55, 485, 735, 360, "Task2 特征任务", "time"))
    elements.extend(chart_panel(by_task["task2_features"], 810, 485, 735, 360, "Task2 加速比", "speedup"))
    path_out = output_dir / "Figure36_Task1_Task2_L1_L6_Performance.svg"
    write_svg(path_out, elements)
    return path_out


def read_numeric_csv(path: Path) -> list[float]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        return [float(row["value"]) for row in reader]


def read_complex_magnitude_csv(path: Path) -> list[float]:
    with path.open(newline="", encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        return [math.hypot(float(row["real"]), float(row["imag"])) for row in reader]


def reshape(values: Sequence[float], shape: Sequence[int]) -> list[list[float]]:
    rows, cols = int(shape[0]), int(shape[1])
    if len(values) != rows * cols:
        raise ValueError(f"CSV values={len(values)} but expected shape={rows}×{cols}")
    return [list(values[row * cols:(row + 1) * cols]) for row in range(rows)]


def downsample_max(matrix: Sequence[Sequence[float]], max_rows: int = 160, max_cols: int = 360) -> list[list[float]]:
    source_rows, source_cols = len(matrix), len(matrix[0])
    target_rows, target_cols = min(source_rows, max_rows), min(source_cols, max_cols)
    reduced: list[list[float]] = []
    for target_row in range(target_rows):
        row_start = target_row * source_rows // target_rows
        row_end = max(row_start + 1, (target_row + 1) * source_rows // target_rows)
        reduced_row = []
        for target_col in range(target_cols):
            col_start = target_col * source_cols // target_cols
            col_end = max(col_start + 1, (target_col + 1) * source_cols // target_cols)
            reduced_row.append(max(matrix[row][col] for row in range(row_start, row_end) for col in range(col_start, col_end)))
        reduced.append(reduced_row)
    return reduced


def color_map(value: float) -> tuple[int, int, int, int]:
    """A compact, perceptually ordered blue-cyan-yellow heat-map palette."""
    value = min(1.0, max(0.0, value))
    stops = [(15, 35, 70), (18, 96, 154), (0, 166, 200), (127, 214, 170), (255, 206, 84)]
    scaled = value * (len(stops) - 1)
    index = min(len(stops) - 2, int(scaled))
    fraction = scaled - index
    start, end = stops[index], stops[index + 1]
    return tuple(round(start[channel] + fraction * (end[channel] - start[channel])) for channel in range(3)) + (255,)


def png_bytes(
    matrix: Sequence[Sequence[float]],
    *,
    logarithmic: bool,
    lower_bound: float | None = None,
    upper_bound: float | None = None,
) -> bytes:
    flattened = [value for row in matrix for value in row]
    if logarithmic:
        flattened = [math.log10(max(value, 0.0) + 1.0) for value in flattened]
    lower = min(flattened) if lower_bound is None else lower_bound
    upper = max(flattened) if upper_bound is None else upper_bound
    scale = 1.0 / (upper - lower) if upper > lower else 1.0
    width, height = len(matrix[0]), len(matrix)
    raw = bytearray()
    for source_row in matrix:
        raw.append(0)
        for raw_value in source_row:
            value = math.log10(max(raw_value, 0.0) + 1.0) if logarithmic else raw_value
            raw.extend(color_map((value - lower) * scale))
    def chunk(chunk_type: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + chunk_type + payload + struct.pack(">I", zlib.crc32(chunk_type + payload) & 0xFFFFFFFF)
    header = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return header + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), level=9)) + chunk(b"IEND", b"")


def heatmap_element(
    matrix: Sequence[Sequence[float]],
    x: float,
    y: float,
    width: float,
    height: float,
    *,
    logarithmic: bool,
    lower_bound: float | None = None,
    upper_bound: float | None = None,
) -> str:
    encoded = base64.b64encode(
        png_bytes(matrix, logarithmic=logarithmic, lower_bound=lower_bound, upper_bound=upper_bound)
    ).decode("ascii")
    uri = f"data:image/png;base64,{encoded}"
    return (
        f'<image x="{x:.1f}" y="{y:.1f}" width="{width:.1f}" height="{height:.1f}" '
        f'preserveAspectRatio="none" href="{uri}" xlink:href="{uri}"/>'
    )


def draw_heatmap_pair(
    title_text: str,
    left_matrix: Sequence[Sequence[float]],
    right_matrix: Sequence[Sequence[float]],
    left_label: str,
    right_label: str,
    y_axis: str,
    x_axis: str,
    output_path: Path,
    *,
    logarithmic: bool = True,
) -> None:
    left_x, top, map_w, map_h = 110, 140, 610, 590
    right_x = 870
    combined = [value for row in left_matrix for value in row] + [value for row in right_matrix for value in row]
    normalized = [math.log10(max(value, 0.0) + 1.0) for value in combined] if logarithmic else combined
    lower_bound, upper_bound = min(normalized), max(normalized)
    elements = [text(WIDTH / 2, 56, title_text, 36, anchor="middle", weight="700")]
    for x, label in ((left_x, left_label), (right_x, right_label)):
        elements.extend([
            rect(x - 2, top - 2, map_w + 4, map_h + 4, fill="#FFFFFF", stroke="#B8C7D9", stroke_width=2),
            text(x + map_w / 2, 112, label, 28, anchor="middle", weight="700"),
            text(x + map_w / 2, top + map_h + 54, x_axis, 20, anchor="middle", color=MUTED_COLOR),
            text(x - 48, top + map_h / 2, y_axis, 20, anchor="middle", color=MUTED_COLOR),
        ])
    elements.extend([
        heatmap_element(left_matrix, left_x, top, map_w, map_h, logarithmic=logarithmic, lower_bound=lower_bound, upper_bound=upper_bound),
        heatmap_element(right_matrix, right_x, top, map_w, map_h, logarithmic=logarithmic, lower_bound=lower_bound, upper_bound=upper_bound),
        text(WIDTH / 2, 825, "颜色范围按 CPU/GPU 合并数据归一化；热图为原始数组的可视化降采样", 18, anchor="middle", color=MUTED_COLOR),
    ])
    write_svg(output_path, elements)


def draw_single_heatmap(
    title_text: str,
    matrix: Sequence[Sequence[float]],
    y_axis: str,
    x_axis: str,
    output_path: Path,
    *,
    logarithmic: bool = True,
    note: str,
) -> None:
    map_x, top, map_w, map_h = 250, 140, 1100, 590
    elements = [
        text(WIDTH / 2, 56, title_text, 36, anchor="middle", weight="700"),
        rect(map_x - 2, top - 2, map_w + 4, map_h + 4, fill="#FFFFFF", stroke="#B8C7D9", stroke_width=2),
        heatmap_element(matrix, map_x, top, map_w, map_h, logarithmic=logarithmic),
        text(WIDTH / 2, top + map_h + 54, x_axis, 20, anchor="middle", color=MUTED_COLOR),
        text(map_x - 70, top + map_h / 2, y_axis, 20, anchor="middle", color=MUTED_COLOR),
        text(WIDTH / 2, 825, note, 18, anchor="middle", color=MUTED_COLOR),
    ]
    write_svg(output_path, elements)


def draw_detection_pair(metrics: dict, level: int, cpu: Sequence[Sequence[float]], gpu: Sequence[Sequence[float]], output_path: Path) -> None:
    left_x, top, map_w, map_h = 110, 140, 610, 590
    right_x = 870
    expected = metrics["expected_detection"]
    cpu_detection = metrics["cpu_detection"]
    gpu_detection = metrics["gpu_detection"]
    rows, cols = len(cpu), len(cpu[0])
    elements = [text(WIDTH / 2, 56, f"Task1 L{level}：CA-CFAR 检测结果与预期目标", 36, anchor="middle", weight="700")]
    for x, label, matrix, detection in ((left_x, "CPU 检测图", cpu, cpu_detection), (right_x, "ZQ500 GPU 检测图", gpu, gpu_detection)):
        elements.extend([
            rect(x - 2, top - 2, map_w + 4, map_h + 4, fill="#FFFFFF", stroke="#B8C7D9", stroke_width=2),
            heatmap_element(downsample_max(matrix), x, top, map_w, map_h, logarithmic=False),
            text(x + map_w / 2, 112, label, 28, anchor="middle", weight="700"),
            text(x + map_w / 2, top + map_h + 54, "距离 bin", 20, anchor="middle", color=MUTED_COLOR),
            text(x - 50, top + map_h / 2, "多普勒 bin", 20, anchor="middle", color=MUTED_COLOR),
        ])
        def coord(item: dict) -> tuple[float, float]:
            return x + map_w * item["range_bin"] / max(1, cols - 1), top + map_h * item["doppler_bin"] / max(1, rows - 1)
        ex, ey = coord(expected)
        dx, dy = coord(detection)
        elements.extend([
            f'<path d="M {ex - 12:.1f} {ey:.1f} L {ex + 12:.1f} {ey:.1f} M {ex:.1f} {ey - 12:.1f} L {ex:.1f} {ey + 12:.1f}" stroke="{ACCENT_COLOR}" stroke-width="4"/>',
            f'<path d="M {dx - 11:.1f} {dy - 11:.1f} L {dx + 11:.1f} {dy + 11:.1f} M {dx + 11:.1f} {dy - 11:.1f} L {dx - 11:.1f} {dy + 11:.1f}" stroke="#FFFFFF" stroke-width="4"/>',
        ])
    elements.extend([
        text(WIDTH / 2, 795, "橙色十字：预期目标；白色叉号：对应后端检测结果", 20, anchor="middle", color=MUTED_COLOR),
        text(WIDTH / 2, 835, f"预期 = CPU = GPU：range bin {expected['range_bin']}，doppler bin {expected['doppler_bin']}，{expected['doppler_hz']} Hz", 20, anchor="middle", color=TEXT_COLOR, weight="700"),
    ])
    write_svg(output_path, elements)


def draw_feature_peak_figure(
    metrics: dict,
    level: int,
    cpu_scores: Sequence[Sequence[float]],
    gpu_scores: Sequence[Sequence[float]],
    output_path: Path,
) -> None:
    frame = int(metrics["scenario"]["representative_frame_index"])
    cpu = list(cpu_scores[frame])
    gpu = list(gpu_scores[frame])
    truth = float(metrics["truth_track"][frame])
    cpu_peak = float(metrics["cpu_peak_track"][frame])
    gpu_peak = float(metrics["gpu_peak_track"][frame])
    chart_x, chart_y, chart_w, chart_h = 130, 145, 1360, 500
    low = min(min(cpu), min(gpu))
    high = max(max(cpu), max(gpu))
    margin = max(1e-6, (high - low) * 0.08)
    low, high = low - margin, high + margin

    def point_x(index: float) -> float:
        return chart_x + chart_w * index / max(1, len(cpu) - 1)

    def point_y(value: float) -> float:
        return linear_y(value, low, high, chart_y, chart_h)

    def points(values: Sequence[float]) -> list[tuple[float, float]]:
        return [(point_x(index), point_y(value)) for index, value in enumerate(values)]

    elements = [
        text(WIDTH / 2, 56, f"Task2 L{level}：第 {frame} 帧特征融合得分与峰值定位", 36, anchor="middle", weight="700"),
        rect(chart_x, chart_y, chart_w, chart_h, fill="#FFFFFF", stroke="#B8C7D9", stroke_width=2, radius=12),
    ]
    for index in range(5):
        y_value = chart_y + chart_h * index / 4
        tick = high - (high - low) * index / 4
        elements.extend([
            line(chart_x, y_value, chart_x + chart_w, y_value, color=GRID_COLOR, dash="5 7"),
            text(chart_x - 16, y_value + 6, f"{tick:.2f}", 17, anchor="end", color=MUTED_COLOR),
        ])
    cpu_points, gpu_points = points(cpu), points(gpu)
    elements.extend([
        path(cpu_points, color=CPU_COLOR, width=3),
        path(gpu_points, color=GPU_COLOR, width=3),
        line(point_x(truth), chart_y, point_x(truth), chart_y + chart_h, color=ACCENT_COLOR, width=3, dash="8 6"),
        circle(point_x(cpu_peak), point_y(cpu[int(round(cpu_peak))]), 9, fill=CPU_COLOR),
        circle(point_x(gpu_peak), point_y(gpu[int(round(gpu_peak))]), 6, fill=GPU_COLOR),
        line(chart_x + 30, 105, chart_x + 70, 105, color=CPU_COLOR, width=4),
        text(chart_x + 80, 112, "CPU 特征得分", 18, color=MUTED_COLOR),
        line(chart_x + 270, 105, chart_x + 310, 105, color=GPU_COLOR, width=4),
        text(chart_x + 320, 112, "ZQ500 GPU 特征得分", 18, color=MUTED_COLOR),
        line(chart_x + 600, 105, chart_x + 640, 105, color=ACCENT_COLOR, width=3, dash="8 6"),
        text(chart_x + 650, 112, "真值位置", 18, color=MUTED_COLOR),
        text(WIDTH / 2, 700, "样本索引", 20, anchor="middle", color=MUTED_COLOR),
        text(WIDTH / 2, 770, f"真值 = {truth:.0f}；CPU 峰值 = {cpu_peak:.0f}；ZQ500 GPU 峰值 = {gpu_peak:.0f}", 25, anchor="middle", color=TEXT_COLOR, weight="700"),
        text(WIDTH / 2, 825, "数据来源：任务真实运行生成的 feature_score 与 peak_track 输出。", 18, anchor="middle", color=MUTED_COLOR),
    ])
    write_svg(output_path, elements)


def draw_track_figure(metrics: dict, level: int, truth: Sequence[float], cpu: Sequence[float], gpu: Sequence[float], output_path: Path) -> None:
    chart_x, chart_y, chart_w, chart_h = 130, 130, 1360, 610
    values = list(truth) + list(cpu) + list(gpu)
    low, high = min(values), max(values)
    margin = max(10.0, (high - low) * 0.08)
    low, high = low - margin, high + margin
    count = len(truth)
    elements = [
        text(WIDTH / 2, 56, f"Task2 L{level}：CPU / GPU / 真值轨迹对照", 36, anchor="middle", weight="700"),
        rect(chart_x, chart_y, chart_w, chart_h, fill="#FFFFFF", stroke="#B8C7D9", stroke_width=2, radius=12),
    ]
    for index in range(5):
        y_value = chart_y + chart_h * index / 4
        tick = high - (high - low) * index / 4
        elements.extend([line(chart_x, y_value, chart_x + chart_w, y_value, color=GRID_COLOR, dash="5 7"), text(chart_x - 16, y_value + 6, f"{tick:.0f}", 18, anchor="end", color=MUTED_COLOR)])
    def to_points(items: Sequence[float]) -> list[tuple[float, float]]:
        return [(chart_x + chart_w * index / max(1, count - 1), linear_y(value, low, high, chart_y, chart_h)) for index, value in enumerate(items)]
    series = [(truth, "真值", ACCENT_COLOR), (cpu, "CPU Kalman", CPU_COLOR), (gpu, "ZQ500 GPU Kalman", GPU_COLOR)]
    legend_x = chart_x + 30
    for index, (items, label, color) in enumerate(series):
        elements.append(path(to_points(items), color=color, width=4 if index else 3))
        x_pos = legend_x + index * 230
        elements.extend([line(x_pos, 105, x_pos + 35, 105, color=color, width=4), text(x_pos + 45, 112, label, 18, color=MUTED_COLOR)])
    elements.extend([
        text(WIDTH / 2, 800, "帧索引", 20, anchor="middle", color=MUTED_COLOR),
        text(WIDTH / 2, 845, f"GPU Kalman RMSE = {metrics['kalman_track_error']['rmse']:.6f}，阈值 = {metrics['scenario']['kalman_rmse_tolerance']}", 20, anchor="middle", color=TEXT_COLOR, weight="700"),
    ])
    write_svg(output_path, elements)


def sample_path(task: str, filename: str) -> Path:
    return GENERATED_ROOT / task / "output_samples" / filename


def generate_sample_figures(output_dir: Path) -> tuple[list[Path], list[str]]:
    generated: list[Path] = []
    missing: list[str] = []
    task1_level = int(read_sample_scenario("task1_radar")["scale_level"])
    task2_level = int(read_sample_scenario("task2_features")["scale_level"])
    task1_metrics = read_metrics("task1_radar", task1_level)
    task1_shape = task1_metrics["shapes"]["range_doppler"]
    radar_cpu_path = sample_path("task1_radar", "range_doppler__cpu__values.csv")
    radar_gpu_path = sample_path("task1_radar", "range_doppler__gpu__values.csv")
    if radar_cpu_path.exists() and radar_gpu_path.exists():
        cpu = reshape(read_complex_magnitude_csv(radar_cpu_path), task1_shape)
        gpu = reshape(read_complex_magnitude_csv(radar_gpu_path), task1_shape)
        output = output_dir / f"Figure20_Task1_L{task1_level}_RangeDoppler_CPU_GPU.svg"
        draw_heatmap_pair(f"Task1 L{task1_level}：CPU / ZQ500 GPU 距离—多普勒功率图", downsample_max(cpu), downsample_max(gpu), "CPU", "ZQ500 GPU", "多普勒 bin", "距离 bin", output)
        generated.append(output)
    else:
        missing.append("图20：缺少 Task1 range_doppler CPU/GPU 输出样本")

    cfar_cpu_path = sample_path("task1_radar", "cfar_detections__cpu__values.csv")
    cfar_gpu_path = sample_path("task1_radar", "cfar_detections__gpu__values.csv")
    if cfar_cpu_path.exists() and cfar_gpu_path.exists():
        cpu = reshape(read_numeric_csv(cfar_cpu_path), task1_metrics["shapes"]["cfar"])
        gpu = reshape(read_numeric_csv(cfar_gpu_path), task1_metrics["shapes"]["cfar"])
        output = output_dir / f"Figure21_Task1_L{task1_level}_CFAR_Detection_Overlay.svg"
        draw_detection_pair(task1_metrics, task1_level, cpu, gpu, output)
        generated.append(output)
    else:
        missing.append("图21：缺少 Task1 CFAR CPU/GPU 输出样本")

    task2_metrics = read_metrics("task2_features", task2_level)
    ambgfun_gpu_path = sample_path("task1_radar", "ambgfun_surface__gpu__values.csv")
    if ambgfun_gpu_path.exists():
        output = output_dir / f"Figure22_Task1_L{task1_level}_Ambiguity_Function_Surface.svg"
        surface = reshape(read_numeric_csv(ambgfun_gpu_path), task1_metrics["shapes"]["ambgfun_surface"])
        draw_single_heatmap(
            f"Task1 L{task1_level}：ZQ500 GPU 模糊函数曲面",
            downsample_max(surface),
            "多普勒 bin",
            "时延 bin",
            output,
            note="数据来源：任务真实运行生成的 ambgfun_surface GPU 输出；热图为原始曲面的最大值降采样。",
        )
        generated.append(output)
    else:
        missing.append("图22：缺少 Task1 GPU 模糊函数输出样本")

    spectrogram_cpu = sample_path("task2_features", "spectrogram__cpu__values.csv")
    spectrogram_gpu = sample_path("task2_features", "spectrogram__gpu__values.csv")
    if spectrogram_cpu.exists() and spectrogram_gpu.exists():
        shape = task2_metrics["shapes"]["spectrogram"]
        output = output_dir / f"Figure31_Task2_L{task2_level}_Spectrogram_CPU_GPU.svg"
        draw_heatmap_pair(f"Task2 L{task2_level} 代表帧：CPU / ZQ500 GPU Spectrogram", reshape(read_numeric_csv(spectrogram_cpu), shape), reshape(read_numeric_csv(spectrogram_gpu), shape), "CPU", "ZQ500 GPU", "频率 bin", "时间帧", output)
        generated.append(output)
    else:
        missing.append("图31：缺少 Task2 CPU/GPU spectrogram 输出样本")

    cwt_cpu = sample_path("task2_features", "cwt__cpu__values.csv")
    cwt_gpu = sample_path("task2_features", "cwt__gpu__values.csv")
    if cwt_cpu.exists() and cwt_gpu.exists():
        shape = task2_metrics["shapes"]["cwt"]
        output = output_dir / f"Figure32_Task2_L{task2_level}_CWT_CPU_GPU.svg"
        draw_heatmap_pair(f"Task2 L{task2_level} 代表帧：CPU / ZQ500 GPU CWT 幅值", downsample_max(reshape(read_complex_magnitude_csv(cwt_cpu), shape)), downsample_max(reshape(read_complex_magnitude_csv(cwt_gpu), shape)), "CPU", "ZQ500 GPU", "尺度", "位置采样点", output)
        generated.append(output)
    else:
        missing.append("图32：缺少 Task2 CPU/GPU CWT 输出样本")

    feature_cpu = sample_path("task2_features", "feature_score__cpu__values.csv")
    feature_gpu = sample_path("task2_features", "feature_score__gpu__values.csv")
    if feature_cpu.exists() and feature_gpu.exists():
        shape = task2_metrics["shapes"]["feature_score"]
        output = output_dir / f"Figure33_Task2_L{task2_level}_Feature_Score_Peak.svg"
        draw_feature_peak_figure(
            task2_metrics,
            task2_level,
            reshape(read_numeric_csv(feature_cpu), shape),
            reshape(read_numeric_csv(feature_gpu), shape),
            output,
        )
        generated.append(output)
    else:
        missing.append("图33：缺少 Task2 CPU/GPU 特征融合得分输出样本")

    truth_path = GENERATED_ROOT / "task2_features" / "input" / "truth_track.csv"
    cpu_track_path = sample_path("task2_features", "kalman_track__cpu__values.csv")
    gpu_track_path = sample_path("task2_features", "kalman_track__gpu__values.csv")
    if cpu_track_path.exists() and gpu_track_path.exists():
        truth = read_numeric_csv(truth_path) if truth_path.exists() else [float(value) for value in task2_metrics["truth_track"]]
        output = output_dir / f"Figure34_Task2_L{task2_level}_Kalman_Track_CPU_GPU_Truth.svg"
        draw_track_figure(task2_metrics, task2_level, truth, read_numeric_csv(cpu_track_path), read_numeric_csv(gpu_track_path), output)
        generated.append(output)
    else:
        missing.append("图34：缺少 Task2 CPU/GPU Kalman 轨迹输出样本")
    return generated, missing


def convert_svg_to_png(svg_paths: Sequence[Path], output_dir: Path) -> tuple[list[Path], list[str]]:
    if shutil.which("libreoffice") is None or shutil.which("pdftocairo") is None:
        return [], ["PNG 转换跳过：需要 libreoffice 与 pdftocairo"]
    converted: list[Path] = []
    messages: list[str] = []
    with tempfile.TemporaryDirectory(prefix="cetc_real_figures_") as temporary:
        temporary_dir = Path(temporary)
        for svg_path in svg_paths:
            process = subprocess.run(
                ["libreoffice", "--headless", "--convert-to", "pdf", "--outdir", str(temporary_dir), str(svg_path)],
                text=True,
                capture_output=True,
                check=False,
            )
            pdf_path = temporary_dir / f"{svg_path.stem}.pdf"
            if process.returncode != 0 or not pdf_path.exists():
                messages.append(f"PNG 转换失败：{svg_path.name}；保留 SVG")
                continue
            png_base = output_dir / svg_path.stem
            process = subprocess.run(
                ["pdftocairo", "-singlefile", "-png", "-r", "180", str(pdf_path), str(png_base)],
                text=True,
                capture_output=True,
                check=False,
            )
            png_path = png_base.with_suffix(".png")
            if process.returncode == 0 and png_path.exists():
                converted.append(png_path)
            else:
                messages.append(f"PNG 转换失败：{svg_path.name}；保留 SVG")
    return converted, messages


def main() -> int:
    args = parse_args()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    by_task = read_scale_rows()
    required_tasks = {"task1_radar", "task2_features"}
    missing_tasks = required_tasks - by_task.keys()
    if missing_tasks:
        raise RuntimeError(f"scale_summary.json missing tasks: {sorted(missing_tasks)}")

    generated = [generate_combined_scale_figure(by_task, output_dir)]
    sample_figures, missing = generate_sample_figures(output_dir)
    generated.extend(sample_figures)

    conversion_messages: list[str] = []
    converted: list[Path] = []
    if args.png:
        converted, conversion_messages = convert_svg_to_png(generated, output_dir)

    manifest = {
        "source": {
            "scale_summary": str((REPORT_ROOT / "scale_summary.json").relative_to(REPO_ROOT)),
            "task1_l6_metrics": str((REPORT_ROOT / "task1_radar" / "scales" / "L6" / "metrics.json").relative_to(REPO_ROOT)),
            "task2_l6_metrics": str((REPORT_ROOT / "task2_features" / "scales" / "L6" / "metrics.json").relative_to(REPO_ROOT)),
            "task1_l6_output_samples": str((GENERATED_ROOT / "task1_radar" / "output_samples").relative_to(REPO_ROOT)),
            "task2_l6_output_samples": str((GENERATED_ROOT / "task2_features" / "output_samples").relative_to(REPO_ROOT)),
        },
        "generated_svg": [display_path(path) for path in generated],
        "generated_png": [display_path(path) for path in converted],
        "missing_output_samples": missing,
        "notes": [
            "性能数据只来自 data/reports；输出对照图只来自任务 demo 生成的 CSV。",
            "未生成的图表示宿主机当前缺少对应 output_samples，不能以 AI 或报告中的标量指标替代。",
        ] + conversion_messages,
    }
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for output in generated:
        print(f"[real-figure] generated {display_path(output)}")
    for output in converted:
        print(f"[real-figure] generated {display_path(output)}")
    for message in missing + conversion_messages:
        print(f"[real-figure] pending {message}")
    print(f"[real-figure] manifest {display_path(manifest_path)}")
    return 1 if args.strict and missing else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"[real-figure] error: {error}", file=sys.stderr)
        raise SystemExit(2)
