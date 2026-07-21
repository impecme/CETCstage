#!/usr/bin/env python3
"""Visual V4 refresh for the technical deck.

These pages intentionally keep the unified L1-L6 results as empty, truthful
data slots, but replace the spreadsheet-like placeholder layout with technical
visuals: input-scale sequences, measurement gates, target overlays, tracks,
and optimization-priority ladders.  The output is sibling V4 assets so the
earlier images remain available for comparison and rollback.
"""

from __future__ import annotations

from PIL import ImageDraw

from generate_data_pages import (
    BLUE,
    CPU,
    LIGHT,
    MUTED,
    NAVY,
    ORANGE,
    PALE,
    RED,
    TEXT,
    TEAL,
    WHITE,
    arrow,
    base,
    line,
    rr,
    save,
    txt,
)


def soft_card(
    d: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    fill: str = WHITE,
    edge: str = "#BFD5EB",
    radius: int = 14,
) -> None:
    x1, y1, x2, y2 = box
    rr(d, (x1 + 5, y1 + 8, x2 + 5, y2 + 8), radius, "#DCE8F3")
    rr(d, box, radius, fill, edge, 2)


def ribbon(
    d: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    label: str,
    fill: str = BLUE,
    size: int = 18,
) -> None:
    x1, y1, x2, y2 = box
    notch = min(25, (x2 - x1) // 8)
    d.polygon(
        ((x1, y1), (x2 - notch, y1), (x2, (y1 + y2) // 2), (x2 - notch, y2), (x1, y2), (x1 + notch, (y1 + y2) // 2)),
        fill=fill,
    )
    txt(d, ((x1 + x2) // 2, (y1 + y2) // 2), label, size, WHITE, True, "mm")


def mini_grid(
    d: ImageDraw.ImageDraw,
    x: int,
    y: int,
    cols: int,
    rows: int,
    cell: int,
    active: int,
    accent: str = TEAL,
) -> None:
    for row in range(rows):
        for col in range(cols):
            index = row * cols + col
            fill = accent if index < active else "#DCE8F3"
            rr(d, (x + col * (cell + 3), y + row * (cell + 3), x + col * (cell + 3) + cell, y + row * (cell + 3) + cell), 2, fill, fill, 1)


def scale_sequence(
    d: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    task: str,
    description: str,
    last_label: str,
) -> None:
    x1, y1, x2, y2 = box
    soft_card(d, box, "#FBFDFF", "#BFD5EB")
    ribbon(d, (x1 + 26, y1 + 22, x1 + 290, y1 + 62), f"{task} · 输入规模序列", NAVY, 16)
    txt(d, (x1 + 42, y1 + 89), description, 18, TEXT, True)
    baseline = y1 + 250
    line(d, (x1 + 72, baseline, x2 - 58, baseline), "#A4B8CC", 3)
    nodes = []
    for index in range(6):
        x = x1 + 95 + index * int((x2 - x1 - 190) / 5)
        nodes.append(x)
        size = 16 + index * 3
        cols = 2 + index // 2
        rows = 2 + index // 3
        mini_grid(d, x - cols * (size + 3) // 2, baseline - 88 - rows * (size + 3), cols, rows, size, max(1, cols * rows - index), TEAL if index < 5 else ORANGE)
        d.ellipse((x - 11, baseline - 11, x + 11, baseline + 11), fill=TEAL if index < 5 else ORANGE, outline=WHITE, width=3)
        txt(d, (x, baseline + 35), f"L{index + 1}", 18, ORANGE if index == 5 else NAVY, True, "ma")
    for first, second in zip(nodes[:-1], nodes[1:]):
        arrow(d, first + 15, baseline, second - 15, baseline, "#9CB8D3", 2)
    rr(d, (x1 + 46, y2 - 64, x2 - 46, y2 - 27), 8, "#ECF9F6", "#9CDDD8", 1)
    txt(d, ((x1 + x2) // 2, y2 - 46), last_label, 16, TEAL, True, "mm")


def metric_medallion(
    d: ImageDraw.ImageDraw,
    cx: int,
    cy: int,
    label: str,
    color: str,
    detail: str,
) -> None:
    d.ellipse((cx - 55, cy - 55, cx + 55, cy + 55), fill="#F6FAFE", outline=color, width=3)
    d.ellipse((cx - 42, cy - 42, cx + 42, cy + 42), outline="#C9DCEC", width=2)
    txt(d, (cx, cy - 8), label, 18, color, True, "ma")
    txt(d, (cx, cy + 22), detail, 13, MUTED, True, "ma")


def result_gate(
    d: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    task: str,
    fixed_lines: tuple[str, str, str],
) -> None:
    x1, y1, x2, y2 = box
    soft_card(d, box, WHITE, "#BFD5EB")
    ribbon(d, (x1 + 26, y1 + 22, x2 - 26, y1 + 62), "新 L6 端到端结果 · 待复测", TEAL, 17)
    metric_medallion(d, x1 + 105, y1 + 155, "CPU", CPU, "total ms")
    metric_medallion(d, x1 + 250, y1 + 155, "GPU", TEAL, "total ms")
    arrow(d, x1 + 314, y1 + 155, x1 + 380, y1 + 155, ORANGE, 3)
    rr(d, (x1 + 397, y1 + 110, x2 - 34, y1 + 200), 14, "#FFF7ED", "#F4C17A", 2)
    txt(d, ((x1 + 397 + x2 - 34) // 2, y1 + 140), "speedup", 24, ORANGE, True, "ma")
    txt(d, ((x1 + 397 + x2 - 34) // 2, y1 + 172), "CPU total / GPU total", 13, MUTED, True, "ma")
    ribbon(d, (x1 + 40, y1 + 235, x1 + 182, y1 + 269), "冻结", NAVY, 15)
    for index, text in enumerate(fixed_lines):
        txt(d, (x1 + 202, y1 + 244 + index * 25), f"• {text}", 14, TEXT, True)
    txt(d, ((x1 + x2) // 2, y2 - 28), f"{task}：复测报告直接导出三个数字", 14, MUTED, True, "ma")


def target_gate(
    d: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    title: str,
    second: str,
) -> None:
    x1, y1, x2, y2 = box
    soft_card(d, box, "#F9FCFF", "#9CDDD8")
    ribbon(d, (x1 + 26, y1 + 20, x1 + 265, y1 + 58), title, TEAL, 16)
    cx, cy = x1 + 155, y1 + 140
    for radius, color, label in ((52, NAVY, "Expected"), (37, CPU, "CPU"), (22, TEAL, "GPU")):
        d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), outline=color, width=4)
        txt(d, (cx + 78, cy - radius + 10), label, 13, color, True)
    line(d, (cx - 72, cy, cx + 72, cy), ORANGE, 1)
    line(d, (cx, cy - 72, cx, cy + 72), ORANGE, 1)
    txt(d, (x1 + 320, y1 + 107), "检测 / 轨迹语义一致", 21, NAVY, True)
    rr(d, (x1 + 320, y1 + 142, x2 - 35, y1 + 188), 9, "#ECF9F6", "#9CDDD8", 1)
    txt(d, ((x1 + 320 + x2 - 35) // 2, y1 + 165), second, 16, TEAL, True, "mm")


def track_gate(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    x1, y1, x2, y2 = box
    soft_card(d, box, "#F9FCFF", "#9CDDD8")
    ribbon(d, (x1 + 26, y1 + 20, x1 + 265, y1 + 58), "Task2 新 L6 正确性", TEAL, 16)
    plot = (x1 + 40, y1 + 88, x1 + 390, y2 - 35)
    line(d, (plot[0], plot[3], plot[2], plot[3]), "#A4B8CC", 2)
    line(d, (plot[0], plot[1], plot[0], plot[3]), "#A4B8CC", 2)
    points = ((0, 80), (60, 63), (115, 73), (170, 38), (230, 50), (285, 20), (340, 34))
    for shift, color, width in ((0, TEXT, 2), (2, TEAL, 3)):
        last = None
        for px, py in points:
            now = (plot[0] + px, plot[1] + py + shift)
            if last:
                line(d, (*last, *now), color, width)
            last = now
    for px, py in points[::2]:
        d.ellipse((plot[0] + px - 4, plot[1] + py - 4, plot[0] + px + 4, plot[1] + py + 4), fill=TEAL)
    txt(d, (plot[2] + 15, plot[1] + 25), "CPU", 14, TEXT, True)
    txt(d, (plot[2] + 15, plot[1] + 55), "GPU", 14, TEAL, True)
    txt(d, (x1 + 495, y1 + 108), "CPU / GPU 轨迹", 20, NAVY, True)
    rr(d, (x1 + 495, y1 + 146, x2 - 35, y1 + 190), 9, "#ECF9F6", "#9CDDD8", 1)
    txt(d, ((x1 + 495 + x2 - 35) // 2, y1 + 168), "RMSE / feature error · 待填 PASS", 15, TEAL, True, "mm")


def page_p09() -> None:
    im, d = base(
        "技术指标",
        "Task1 统一 L1–L6 测评",
        "同一算法、同一分块与 CFAR 参数；只有输入规模递增，原 final-input 纳入新 L6。",
    )
    scale_sequence(d, (44, 275, 1004, 664), "Task1", "规模递增时，GPU 并行度如何释放？", "待复测后填入真实加速曲线；L6 为原 final-input 配置")
    result_gate(d, (1034, 275, 1628, 664), "Task1", ("窗口 / CFAR 参数", "公开算子处理链", "误差门限"))
    target_gate(d, (44, 700, 1628, 867), "Task1 新 L6 正确性门", "Expected / CPU / GPU 位置 + CFAR error：待填")
    txt(d, (50, 911), "数据槽位：task1_radar/unified_scales/L1…L6/metrics.json；不回填旧 final-input 或旧 scales 数字。", 14, MUTED)
    save(im, "P09_Task1_统一L1-L6_视觉升级_v04.png")


def page_p10() -> None:
    im, d = base(
        "核心技术",
        "Task2：从全量张量到四路 score",
        "同一任务语义下，GPU 只保留后续决策需要的 score 与状态轨迹。",
    )
    left = (44, 276, 755, 705)
    right = (785, 276, 1628, 705)
    soft_card(d, left, "#FBFCFE", "#C6D5E4")
    ribbon(d, (76, 302, 354, 344), "CPU · 逐帧完整中间量", CPU, 17)
    for index, label in enumerate(("frame 1", "frame 2", "frame 3", "… frame N")):
        x = 92 + index * 118
        mini_grid(d, x, 405, 3, 3, 18, 7, CPU)
        txt(d, (x + 31, 480), label, 13, MUTED, True, "ma")
        if index < 3:
            arrow(d, x + 72, 437, x + 106, 437, CPU, 2)
    rr(d, (108, 548, 692, 621), 12, "#F0F3F6", "#C6D5E4", 1)
    txt(d, (400, 574), "correlate · spectrogram · CWT", 23, CPU, True, "ma")
    txt(d, (400, 604), "每帧物化完整中间张量并回传", 16, MUTED, True, "ma")

    soft_card(d, right, "#FBFFFF", "#9CDDD8")
    ribbon(d, (817, 302, 1140, 344), "ZQ500 GPU · batched score-only", TEAL, 17)
    for index in range(5):
        mini_grid(d, 844 + index * 24, 405, 3, 3, 16, 7, TEAL)
    rr(d, (822, 532, 1010, 620), 12, "#ECF9F6", "#9CDDD8", 1)
    txt(d, (916, 559), "B=8 Device batch", 19, TEAL, True, "ma")
    arrow(d, 1025, 576, 1080, 576, TEAL, 4)
    for index, label in enumerate(("filter", "corr", "spec", "CWT")):
        y = 450 + index * 38
        rr(d, (1097, y, 1257, y + 23), 5, "#ECF9F6", "#9CDDD8", 1)
        rr(d, (1097, y, 1150 + index * 15, y + 23), 5, TEAL)
        txt(d, (1272, y + 12), label, 14, TEXT, True, "lm")
    arrow(d, 1350, 575, 1404, 575, ORANGE, 4)
    rr(d, (1420, 501, 1586, 645), 14, "#FFF7ED", "#F4C17A", 2)
    txt(d, (1503, 542), "fusion", 20, ORANGE, True, "ma")
    txt(d, (1503, 576), "peak", 18, ORANGE, True, "ma")
    txt(d, (1503, 610), "track", 18, ORANGE, True, "ma")
    rr(d, (44, 743, 1628, 867), 12, PALE, BLUE, 2)
    ribbon(d, (80, 773, 295, 812), "统一测评约束", NAVY, 16)
    for x, label, color in ((335, "固定：B=8 / score-only", TEAL), (730, "改变：帧数、输入长度", ORANGE), (1120, "P11 填入新 L1–L6 结果", BLUE)):
        rr(d, (x, 764, x + 330, 829), 12, "#ECF9F6" if color == TEAL else "#FFF7ED" if color == ORANGE else LIGHT, color, 2)
        txt(d, (x + 165, 796), label, 17, color, True, "ma")
    txt(d, (50, 911), "mixed：公开算子库与 task helper 协同调用；helper 不是第三后端，不展示旧 final-input 性能数字。", 14, MUTED)
    save(im, "P10_Task2_Score_Only_视觉升级_v04.png")


def page_p11() -> None:
    im, d = base(
        "技术指标",
        "Task2 统一 L1–L6 测评",
        "冻结 B=8、Device-resident、score-only 与门限；仅改变帧数和每帧输入长度。",
    )
    scale_sequence(d, (44, 275, 1004, 664), "Task2", "输入帧与长度递增时，score-only 的端到端收益如何变化？", "待复测后填入真实加速曲线；L6 为原 final-input 配置")
    result_gate(d, (1034, 275, 1628, 664), "Task2", ("B=8 / score-only", "feature 与 track 门限", "同一 filter / CWT / track 路径"))
    track_gate(d, (44, 700, 1628, 867))
    txt(d, (50, 911), "数据槽位：task2_features/unified_scales/L1…L6/metrics.json；无独立传统 GPU 基线。", 14, MUTED)
    save(im, "P11_Task2_统一L1-L6_视觉升级_v04.png")


def coverage_node(d: ImageDraw.ImageDraw, x: int, y: int, number: str, label: str, color: str) -> None:
    d.ellipse((x, y, x + 98, y + 98), fill=WHITE, outline=color, width=4)
    txt(d, (x + 49, y + 35), number, 26, color, True, "ma")
    txt(d, (x + 49, y + 71), label, 14, TEXT, True, "ma")


def page_p14() -> None:
    im, d = base(
        "技术指标",
        "正确性：从算子到任务输出的三层验证",
        "速度结果必须与误差、检测位置和轨迹语义一起通过同一新 L6 run 的门禁。",
    )
    soft_card(d, (44, 275, 680, 866), "#FBFDFF", "#BFD5EB")
    ribbon(d, (80, 301, 346, 343), "① 覆盖与契约", NAVY, 18)
    nodes = (("81/81", "公开算子", TEAL), ("2/2", "端到端任务", BLUE), ("14/14", "正式步骤", ORANGE))
    for index, (number, label, color) in enumerate(nodes):
        y = 385 + index * 133
        coverage_node(d, 112, y, number, label, color)
        arrow(d, 225, y + 49, 298, y + 49, color, 3)
        rr(d, (326, y + 15, 620, y + 83), 12, LIGHT, "#C5D9EE", 1)
        messages = ("参数 / shape / dtype 合约", "CPU 与 GPU 任务链对照", "error 与 GPU event 同时记录")
        txt(d, (473, y + 49), messages[index], 17, TEXT, True, "ma")
    ribbon(d, (80, 780, 642, 823), "只保留新统一 L6 的任务正确性作为正式答辩结论", TEAL, 15)

    target_gate(d, (718, 275, 1628, 537), "② Task1 新 L6", "检测位置 + CFAR error：待填 PASS")
    track_gate(d, (718, 564, 1628, 866))
    txt(d, (50, 911), "P14 不沿用旧 final-input 误差；新结果来自两个 unified_scales/L6/metrics.json。", 14, MUTED)
    save(im, "P14_统一L6正确性_视觉升级_v04.png")


def blank_curve(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str, color: str) -> None:
    x1, y1, x2, y2 = box
    soft_card(d, box, "#FBFDFF", "#BFD5EB")
    ribbon(d, (x1 + 24, y1 + 22, x1 + 240, y1 + 60), f"{task} Scaling", color, 16)
    px1, py1, px2, py2 = x1 + 55, y1 + 92, x2 - 35, y2 - 52
    for fraction in (0.0, 0.33, 0.66, 1.0):
        yy = py2 - int(fraction * (py2 - py1))
        line(d, (px1, yy, px2, yy), "#E1EBF4", 1)
    line(d, (px1, py1, px1, py2), "#9CB4CA", 2)
    line(d, (px1, py2, px2, py2), "#9CB4CA", 2)
    points = []
    for index in range(6):
        x = px1 + index * int((px2 - px1) / 5)
        y = py2 - 26 - index * int((py2 - py1 - 60) / 6)
        points.append((x, y))
        d.ellipse((x - 8, y - 8, x + 8, y + 8), fill=ORANGE if index == 5 else color, outline=WHITE, width=2)
        txt(d, (x, py2 + 26), f"L{index + 1}", 15, ORANGE if index == 5 else NAVY, True, "ma")
    for first, second in zip(points[:-1], points[1:]):
        line(d, (*first, *second), "#B7C9DA", 3)
    rr(d, (x1 + 100, y1 + 128, x2 - 55, y1 + 171), 8, "#ECF9F6", "#9CDDD8", 1)
    txt(d, ((x1 + 100 + x2 - 55) // 2, y1 + 149), "真实 speedup 曲线待统一复测填入", 15, TEAL, True, "mm")


def hotspot_ladder(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str, color: str) -> None:
    x1, y1, x2, y2 = box
    soft_card(d, box, WHITE, "#BFD5EB")
    ribbon(d, (x1 + 24, y1 + 22, x1 + 305, y1 + 60), f"{task} · 新 L6 热点阶梯", color, 16)
    for index, (width, label) in enumerate(((390, "Top1"), (310, "Top2"), (230, "Top3"))):
        y = y1 + 96 + index * 62
        x = x1 + 70 + (390 - width) // 2
        rr(d, (x, y, x + width, y + 43), 8, color if index == 0 else LIGHT, color, 2)
        txt(d, (x + width // 2, y + 21), f"{label} · 步骤 / GPU ms / 占比（待填）", 15, WHITE if index == 0 else TEXT, True, "mm")
    txt(d, ((x1 + x2) // 2, y2 - 34), "热点 = GPU total 时间占比最高的步骤", 14, MUTED, True, "ma")


def page_p16() -> None:
    im, d = base(
        "技术指标",
        "规模效应与热点：下一轮优化从何处开始",
        "统一曲线回答“规模何时释放并行度”；新 L6 Top3 回答“先优化哪个步骤”。",
    )
    blank_curve(d, (44, 275, 810, 558), "Task1", TEAL)
    blank_curve(d, (854, 275, 1628, 558), "Task2", BLUE)
    hotspot_ladder(d, (44, 596, 810, 866), "Task1", TEAL)
    hotspot_ladder(d, (854, 596, 1628, 866), "Task2", BLUE)
    txt(d, (50, 911), "只使用新 unified_scales/L1…L6 数据；GPU event 为 stream work，不解释为单 kernel profiler 时间。", 14, MUTED)
    save(im, "P16_统一L1-L6规模与热点_视觉升级_v04.png")


def mechanism_icon(d: ImageDraw.ImageDraw, cx: int, cy: int, kind: int) -> None:
    if kind == 0:
        mini_grid(d, cx - 41, cy - 30, 4, 4, 13, 11, TEAL)
        rr(d, (cx - 23, cy - 12, cx + 23, cy + 34), 5, "#FFF7ED", ORANGE, 2)
    elif kind == 1:
        for level, count in enumerate((1, 2, 4)):
            y = cy - 35 + level * 28
            for index in range(count):
                x = cx - (count - 1) * 26 // 2 + index * 26
                d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=TEAL)
            if level < 2:
                line(d, (cx, y + 7, cx, y + 21), BLUE, 2)
    else:
        mini_grid(d, cx - 52, cy - 26, 3, 3, 13, 8, CPU)
        arrow(d, cx - 2, cy, cx + 35, cy, ORANGE, 3)
        for index in range(4):
            rr(d, (cx + 40, cy - 31 + index * 17, cx + 88, cy - 21 + index * 17), 3, TEAL, TEAL, 1)


def page_p17() -> None:
    im, d = base(
        "技术指标",
        "性能优势、实验边界与下一轮优化",
        "先用统一 L1–L6 建立可比基线，再让分块、阈值与 shape 成为独立 A/B 变量。",
    )
    headings = ((44, "已经完成", TEAL), (590, "统一复测", BLUE), (1136, "下一轮 A/B", ORANGE))
    cards = (
        (("邻域复用", "Tile / Halo", 0), ("递归转并行", "Affine Scan", 1), ("删中间量", "R2C / score-only", 2)),
        (("L6 对齐", "原 final-input", 0), ("只变规模", "L1–L5 输入递增", 1), ("同 run 绑定", "速度 + 误差", 2)),
        (("Block / Halo", "独立 A/B", 0), ("CFAR 参数", "独立 A/B", 1), ("batch / shape", "按 Top3 优先", 2)),
    )
    for col, (x, heading, color) in enumerate(headings):
        ribbon(d, (x, 285, x + 492, 329), heading, color, 19)
        for index, (title, detail, kind) in enumerate(cards[col]):
            y = 365 + index * 150
            soft_card(d, (x, y, x + 492, y + 120), "#FBFDFF", "#C5D9EE")
            mechanism_icon(d, x + 78, y + 57, kind)
            txt(d, (x + 150, y + 38), title, 22, color, True)
            txt(d, (x + 150, y + 75), detail, 17, TEXT, True)
        if col < 2:
            arrow(d, x + 500, 545, x + 535, 545, "#9CB8D3", 4)
    ribbon(d, (205, 842, 1467, 890), "先可比测量，再逐项优化；不把规模变化与参数调优混在同一条曲线。", NAVY, 20)
    txt(d, (50, 920), "参数优化结果必须由新统一协议上的独立 A/B 填入；当前不把计划写成效果。", 14, MUTED)
    save(im, "P17_统一测评与改进方向_视觉升级_v04.png")


def page_p18() -> None:
    im, d = base(
        "创新点",
        "核心亮点：把不适合 GPU 的结构重写为并行结构",
        "三类亮点分别针对重复访存、递归/频谱冗余和无用中间量，形成公共算子与任务级协同。",
    )
    cards = (
        (44, "① 邻域访存重构", "重复窗口", "Tile / Halo", "块内复用", 0),
        (582, "② 递归与频谱重构", "长状态链 / 双边谱", "Scan / R2C", "缩短依赖、减少计算", 1),
        (1120, "③ 任务语义裁剪", "完整中间张量", "score-only", "只保留 score / 轨迹", 2),
    )
    for x, title, problem, method, value, kind in cards:
        soft_card(d, (x, 282, x + 508, 773), "#FBFDFF", "#BFD5EB")
        ribbon(d, (x + 22, 305, x + 486, 350), title, NAVY, 18)
        mechanism_icon(d, x + 254, 455, kind)
        for y, label, text, color in ((538, "问题", problem, CPU), (611, "方法", method, TEAL), (684, "价值", value, ORANGE)):
            rr(d, (x + 45, y, x + 463, y + 47), 9, "#F0F5FA" if color == CPU else "#ECF9F6" if color == TEAL else "#FFF7ED", "#C5D9EE", 1)
            txt(d, (x + 74, y + 24), label, 16, color, True, "mm")
            txt(d, (x + 122, y + 24), text, 18, TEXT, True, "lm")
    ribbon(d, (140, 816, 1530, 871), "统一 L1–L6 复测完成后，再把同协议的端到端效果填入每项亮点。", BLUE, 20)
    txt(d, (50, 911), "亮点页面只陈述当前代码已实现的结构方法；不使用旧独立 final-input 数字。", 14, MUTED)
    save(im, "P18_核心亮点_视觉升级_v04.png")


if __name__ == "__main__":
    page_p09()
    page_p10()
    page_p11()
    page_p14()
    page_p16()
    page_p17()
    page_p18()
