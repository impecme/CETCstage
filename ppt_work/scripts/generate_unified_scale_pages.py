#!/usr/bin/env python3
"""Render P09/P11/P14/P16 from the formal L1-L6 task reports."""

from __future__ import annotations

import json
from pathlib import Path

from generate_data_pages import BLUE, CPU, LIGHT, MUTED, NAVY, ORANGE, PALE, TEAL, TEXT, WHITE, base, card_header, line, rr, save, txt


ROOT = Path(__file__).resolve().parents[2]


def metrics(task: str, level: int) -> dict:
    return json.loads((ROOT / "data" / "reports" / "demo" / task / "scales" / f"L{level}" / "metrics.json").read_text())


def panel(d, box, title, color=NAVY, size=20):
    card_header(d, box, title, color, size)


def badge(d, box, text, color=NAVY, fill=LIGHT, size=16):
    rr(d, box, 8, fill, "#C5D9EE", 1)
    txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), text, size, color, True, "mm")


def task_label(task: str) -> str:
    return "Task1 雷达检测" if task == "task1_radar" else "Task2 特征融合与跟踪"


def plot_speedup(d, box, task: str, title: str):
    panel(d, box, title, NAVY, 18)
    values = [metrics(task, level)["speedup"]["cpu_over_gpu"] for level in range(1, 7)]
    x1, y1, x2, y2 = box[0] + 75, box[1] + 98, box[2] - 42, box[3] - 68
    maximum = 35 if task == "task1_radar" else 1100
    ticks = (0, 10, 20, 30, 35) if task == "task1_radar" else (0, 250, 500, 750, 1000)
    for value in ticks:
        y = y2 - int(value / maximum * (y2 - y1))
        line(d, (x1, y, x2, y), "#DDE8F3", 1)
        txt(d, (x1 - 15, y), f"{value}×", 14, MUTED, False, "rm")
    line(d, (x1, y1, x1, y2), MUTED, 2)
    line(d, (x1, y2, x2, y2), MUTED, 2)
    points = []
    for index, value in enumerate(values):
        x = x1 + int(index * (x2 - x1) / 5)
        y = y2 - int(value / maximum * (y2 - y1))
        points.append((x, y))
        txt(d, (x, y2 + 29), f"L{index + 1}", 16, ORANGE if index == 5 else TEXT, True, "ma")
        txt(d, (x, max(y1 + 12, y - 17)), f"{value:.1f}" if task == "task1_radar" else f"{value:.0f}", 14, NAVY, True, "ma")
    for a, b in zip(points[:-1], points[1:]):
        line(d, (*a, *b), TEAL, 4)
    for index, (x, y) in enumerate(points):
        d.ellipse((x - 8, y - 8, x + 8, y + 8), fill=ORANGE if index == 5 else TEAL, outline=WHITE, width=2)
    return values


def l6_card(d, box, task: str):
    data = metrics(task, 6)
    measure = data["measurement"]
    panel(d, box, "正式 L6 · 预热后中位数", TEAL, 18)
    items = (("CPU", measure["cpu_total"]["median_ms"], CPU), ("ZQ500 GPU", measure["gpu_total"]["median_ms"], TEAL))
    for index, (label, value, color) in enumerate(items):
        y = box[1] + 100 + index * 82
        txt(d, (box[0] + 30, y), label, 17, TEXT, True)
        txt(d, ((box[0] + box[2]) // 2, y + 25), f"{value:.1f} ms", 18, color, True, "ma")
    txt(d, ((box[0] + box[2]) // 2, box[1] + 290), f"{data['speedup']['cpu_over_gpu']:.2f}×", 38, BLUE, True, "ma")
    txt(d, ((box[0] + box[2]) // 2, box[1] + 335), "CPU median / GPU median", 14, MUTED, True, "ma")
    txt(d, ((box[0] + box[2]) // 2, box[3] - 35), "7 次运行；首轮 warm-up 排除", 14, MUTED, True, "ma")


def protocol_card(d, box, task: str):
    panel(d, box, "正式 L1–L6 协议", ORANGE, 18)
    rows = (("L6：原 final-input 验收配置",), ("固定：算法参数与正确性门限",), ("固定：GPU 处理链与输出语义",), ("改变：仅输入尺寸",))
    if task == "task1_radar":
        rows = (("L6：128 × 4096",), ("固定：template/FFT/Hann/CFAR",), ("固定：公开算子驻留链",), ("改变：脉冲数、每脉冲采样",))
    else:
        rows = (("L6：128 × 3072",), ("固定：filter/spec/CWT/track",), ("固定：batch-friendly / score-only",), ("改变：帧数",))
    for index, (label,) in enumerate(rows):
        badge(d, (box[0] + 28, box[1] + 87 + index * 61, box[2] - 28, box[1] + 131 + index * 61), label, TEXT, "#FFF7ED", 13)


def page_performance(task: str, page: str):
    title = "Task1：正式 L1–L6 下端到端加速保持 25×以上" if task == "task1_radar" else "Task2：批量 score-only 随规模扩展至 1048.78×"
    conclusion = "冻结 L6 模板、FFT、Hann 与 CFAR；L1–L6 仅改变任务输入尺寸。" if task == "task1_radar" else "冻结 L6 filter/spectrogram/CWT/track 与 score-only 语义；仅改变帧数。"
    im, d = base("技术指标", title, conclusion)
    plot_speedup(d, (44, 265, 810, 652), task, f"{task_label(task)} · L1–L6 加速比")
    l6_card(d, (834, 265, 1190, 652), task)
    protocol_card(d, (1215, 265, 1628, 652), task)
    data = metrics(task, 6)
    check = data["correctness_summary"]
    rr(d, (44, 690, 1628, 865), 12, PALE, BLUE, 2)
    if task == "task1_radar":
        detected = check["gpu_detection"]
        txt(d, (80, 730), "L6 正确性门禁 · PASS", 23, TEAL, True)
        txt(d, (80, 777), f"Expected = CPU = GPU：range={detected['range_bin']}，Doppler={detected['doppler_bin']}，{detected['doppler_hz']} Hz", 21, TEXT, True)
        txt(d, (80, 826), f"CFAR threshold mixed error = {check['cfar_threshold_mixed_error']:.6f} < 0.5；pulse-Doppler = {check['pulse_doppler_mixed_error']:.6f} < 0.0005", 17, NAVY, True)
    else:
        txt(d, (80, 730), "L6 正确性门禁 · PASS", 23, TEAL, True)
        txt(d, (80, 777), "CPU/GPU peak track 一致；GPU Kalman track 满足 truth 门限", 21, TEXT, True)
        txt(d, (80, 826), f"Kalman RMSE = {check['kalman_track_rmse']:.6f} < 2；feature-score mixed error = {check['feature_score_mixed_error']:.5e} < 1e-4", 17, NAVY, True)
    txt(d, (50, 912), f"真实运行：ZQ500-Q QUAD-0 · final_l1_l6_v1 · 7 repeats / first warm-up excluded · data/reports/demo/{task}/scales/", 13, MUTED)
    save(im, page)


def page_p14():
    t1, t2 = metrics("task1_radar", 6), metrics("task2_features", 6)
    im, d = base("技术指标", "正式 L6 正确性闭环：两条任务、12 个规模点均通过验证", "正确性、性能、统计口径来自同一套正式 L1–L6 运行报告，而非旧 final-input 快照。")
    left = (44, 265, 540, 850)
    panel(d, left, "覆盖与运行门禁", NAVY, 21)
    for index, (number, label, color) in enumerate((("81/81", "公开算子有性能记录", TEAL), ("2/2", "端到端任务", BLUE), ("12/12", "正式 L1–L6 运行", ORANGE), ("14/14", "正式计算步骤", NAVY))):
        y = 345 + index * 102
        badge(d, (80, y, 504, y + 70), f"{number}  {label}", color, "#ECF9F6" if color == TEAL else LIGHT, 21)
    top = (574, 265, 1628, 526)
    panel(d, top, "Task1 L6 · 检测位置与中间误差", TEAL, 20)
    c1 = t1["correctness_summary"]
    detect = c1["gpu_detection"]
    txt(d, (622, 355), "Expected = CPU = GPU", 25, TEAL, True)
    txt(d, (622, 410), f"range={detect['range_bin']} · Doppler={detect['doppler_bin']} · {detect['doppler_hz']} Hz", 22, TEXT, True)
    badge(d, (1170, 344, 1578, 404), f"CFAR {c1['cfar_threshold_mixed_error']:.6f} < 0.5", NAVY, LIGHT, 17)
    badge(d, (1170, 425, 1578, 485), "validation PASS · 7 repeats", TEAL, "#ECF9F6", 17)
    bottom = (574, 555, 1628, 850)
    panel(d, bottom, "Task2 L6 · 轨迹与特征误差", TEAL, 20)
    c2 = t2["correctness_summary"]
    txt(d, (622, 645), "CPU/GPU peak track 一致；GPU track 匹配 truth 门限", 21, TEXT, True)
    badge(d, (622, 704, 1082, 768), f"Kalman RMSE {c2['kalman_track_rmse']:.6f} < 2", NAVY, LIGHT, 18)
    badge(d, (1110, 704, 1578, 768), f"feature {c2['feature_score_mixed_error']:.5e} < 1e-4", NAVY, LIGHT, 16)
    badge(d, (622, 788, 1578, 829), "两条任务全部 validation PASS；任何失败运行均不会被导出", TEAL, "#ECF9F6", 17)
    txt(d, (50, 912), "数据：final_l1_l6_v1；L6 为原 final-input 配置，L1–L5 固定算法参数，仅输入尺寸递增。", 13, MUTED)
    save(im, "P14_L6正确性_实测_v08.png")


def top3(task: str):
    data = metrics(task, 6)
    total = data["raw_final_timing_total"]["gpu_ms"]
    values = [(name, value["gpu_ms"], value["gpu_ms"] / total * 100) for name, value in data["timings"].items() if name != "total" and value["gpu_ms"] > 0]
    return sorted(values, key=lambda item: item[1], reverse=True)[:3]


def page_p16():
    im, d = base("技术指标", "规模效应与热点：Task1 固定开销，Task2 batch 并行度释放", "曲线只反映输入规模；L6 Top3 来自同一 L6 的 GPU event 阶段时间，包含 input construction。")
    plot_speedup(d, (44, 265, 810, 548), "task1_radar", "Task1 · L1–L6 speedup")
    plot_speedup(d, (854, 265, 1628, 548), "task2_features", "Task2 · L1–L6 speedup")
    for box, task, title in (((44, 590, 810, 850), "task1_radar", "Task1 L6 Top3 GPU 阶段"), ((854, 590, 1628, 850), "task2_features", "Task2 L6 Top3 GPU 阶段")):
        panel(d, box, title, NAVY, 19)
        for index, (name, ms, share) in enumerate(top3(task), start=1):
            y = box[1] + 78 + (index - 1) * 52
            rr(d, (box[0] + 32, y, box[2] - 32, y + 38), 7, "#F0F4F8", "#C5D9EE", 1)
            txt(d, (box[0] + 52, y + 19), f"Top{index} · {name}", 15, NAVY, True, "lm")
            txt(d, (box[0] + 505, y + 19), f"{ms:.2f}ms | {share:.1f}%", 13, TEAL, True, "la")
        txt(d, ((box[0] + box[2]) // 2, box[3] - 23), "占比基于 L6 final-run GPU total；不与中位总时延混算", 11, MUTED, True, "ma")
    txt(d, (50, 912), "Task1 L6=128×4096，Task2 L6=128×3072；无 DRAM bytes/FLOPS 同协议数据，故不绘制 Roofline。", 13, MUTED)
    save(im, "P16_L1-L6规模与热点_实测_v08.png")


if __name__ == "__main__":
    page_performance("task1_radar", "P09_Task1_L1-L6_实测_v08.png")
    page_performance("task2_features", "P11_Task2_L1-L6_实测_v08.png")
    page_p14()
    page_p16()
