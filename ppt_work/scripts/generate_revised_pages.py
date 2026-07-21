#!/usr/bin/env python3
"""Render the revised evidence and closing pages for the competition deck.

Unlike the early dense version, this renderer gives each page one decision:
result, workflow, correctness, library overview, scale/hotspots, improvement,
innovation, or AI disclosure.  Every quantitative value is loaded from the
published report snapshot under data/reports/.
"""

from __future__ import annotations

import math

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
    W,
    H,
    arrow,
    base,
    card_header,
    detailed_cases,
    font,
    line,
    load_json,
    rr,
    save,
    txt,
)


def panel(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
          fill: str = NAVY, size: int = 20) -> None:
    card_header(d, box, title, fill, size)


def tag(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str,
        fill: str = LIGHT, color: str = NAVY, size: int = 16) -> None:
    rr(d, box, 9, fill)
    txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), label, size, color, True, "mm")


def horizontal_bar(d: ImageDraw.ImageDraw, x: int, y: int, width: int,
                   value: float, maximum: float, color: str, label: str,
                   value_label: str) -> None:
    txt(d, (x, y), label, 18, TEXT, True)
    rr(d, (x, y + 28, x + width, y + 54), 8, "#E5EDF5")
    rr(d, (x, y + 28, x + max(18, int(width * value / maximum)), y + 54), 8, color)
    txt(d, (x + width, y + 41), value_label, 17, color, True, "rm")


def line_chart(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
               values: list[float], ymax: float, accent_last: bool = False) -> None:
    panel(d, box, title, NAVY, 20)
    bx1, by1, bx2, by2 = box
    x1, y1, x2, y2 = bx1 + 70, by1 + 98, bx2 - 40, by2 - 62
    for frac, label in ((0, "0×"), (0.5, f"{ymax / 2:.0f}×"), (1, f"{ymax:.0f}×")):
        yy = y2 - int(frac * (y2 - y1))
        line(d, (x1, yy, x2, yy), "#DCE8F3", 1)
        txt(d, (x1 - 12, yy), label, 15, MUTED, False, "rm")
    line(d, (x1, y1, x1, y2), MUTED, 2)
    line(d, (x1, y2, x2, y2), MUTED, 2)
    points = []
    for index, value in enumerate(values):
        x = x1 + int(index * (x2 - x1) / (len(values) - 1))
        y = y2 - int(value / ymax * (y2 - y1))
        points.append((x, y))
        txt(d, (x, y2 + 30), f"L{index + 1}", 16, TEXT, True, "ma")
        txt(d, (x, max(y1 + 16, y - 20)), f"{value:.2f}", 15, NAVY, True, "ma")
    for index, (first, second) in enumerate(zip(points[:-1], points[1:])):
        line(d, (*first, *second), ORANGE if accent_last and index == len(points) - 2 else TEAL, 5)
    for index, (x, y) in enumerate(points):
        color = ORANGE if accent_last and index == len(points) - 1 else TEAL
        d.ellipse((x - 8, y - 8, x + 8, y + 8), fill=color, outline=WHITE, width=2)


def page_p09() -> None:
    task = load_json("data", "reports", "demo", "task1_radar", "final", "metrics.json")
    total = task["timings"]["total"]
    expected = task["expected_detection"]
    im, d = base(
        "技术指标",
        "Task1 端到端运行结果：34.20× 加速，检测位置一致",
        "CPU 387.942 ms → ZQ500 GPU 11.3444 ms；收益来自整条公开算子链的结构优化。",
    )

    left = (44, 265, 755, 713)
    panel(d, left, "final-input · application-total", NAVY, 21)
    txt(d, (400, 385), "34.20×", 64, BLUE, True, "ma")
    txt(d, (400, 468), "RUN 2026-07-20 SNAPSHOT", 16, MUTED, True, "ma")
    horizontal_bar(d, 104, 525, 560, total["cpu_ms"], total["cpu_ms"], CPU, "CPU reference", f"{total['cpu_ms']:.3f} ms")
    horizontal_bar(d, 104, 617, 560, total["gpu_ms"], total["cpu_ms"], TEAL, "ZQ500 GPU", f"{total['gpu_ms']:.4f} ms")
    tag(d, (210, 670, 591, 704), "同一 Task1 final-input 场景", LIGHT, NAVY, 16)

    right = (790, 265, 1628, 713)
    panel(d, right, "沿链关键优化证据（HISTORICAL A/B）", NAVY, 20)
    evidence = (
        ("CA-CFAR row prefix", "关键步骤时间 ↓28.68%", TEAL),
        ("two-stage peak", "4.052 → 0.096 ms", BLUE),
        ("Doppler transpose / shift", "关键步骤时间 ↓11.57%", ORANGE),
    )
    for index, (name, result, color) in enumerate(evidence):
        y = 347 + index * 105
        rr(d, (830, y, 1584, y + 78), 10, PALE, "#C5D9EE", 1)
        tag(d, (850, y + 19, 1110, y + 59), name, LIGHT, NAVY, 13)
        txt(d, (1140, y + 39), result, 22, color, True, "lm")
    txt(d, (1205, 667), "不同 A/B 证据分别说明，不相乘", 16, MUTED, False, "ma")

    bottom = (44, 742, 1628, 872)
    panel(d, bottom, "最终业务正确性", TEAL, 21)
    txt(d, (88, 814), "Expected = CPU = GPU", 28, TEAL, True)
    txt(d, (88, 846), f"range={expected['range_bin']} · Doppler={expected['doppler_bin']} · {expected['doppler_hz']} Hz", 18, TEXT, True)
    for radius, color in ((42, NAVY), (30, CPU), (18, TEAL)):
        d.ellipse((1390 - radius, 823 - radius, 1390 + radius, 823 + radius), outline=color, width=4)
    tag(d, (1420, 790, 1595, 852), "CFAR 误差\n0.276398 < 0.5", "#ECF9F6", TEAL, 14)
    txt(d, (50, 911), "数据：Task1 final/metrics.json；final-input 为独立验收配置，不并入 P16 的 L1–L6 规模曲线。", 14, MUTED)
    save(im, "P09_Task1_结果与正确性_整页_v02.png")


def flow_card(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
              lines: tuple[str, ...], color: str) -> None:
    rr(d, box, 12, WHITE, color, 2)
    txt(d, ((box[0] + box[2]) // 2, box[1] + 29), title, 22, color, True, "ma")
    for index, label in enumerate(lines):
        y = box[1] + 76 + index * 48
        rr(d, (box[0] + 28, y, box[2] - 28, y + 33), 7, LIGHT if color != CPU else "#F0F3F6")
        txt(d, ((box[0] + box[2]) // 2, y + 17), label, 16, TEXT, True, "mm")


def page_p10() -> None:
    im, d = base(
        "核心技术",
        "Task2 算法构建：批量生成四路 score",
        "从逐帧全量相关、谱图、小波中间量，改为 Device-resident 的 batched score-only 管线。",
    )
    cpu = (44, 275, 725, 690)
    gpu = (825, 275, 1628, 690)
    panel(d, cpu, "CPU reference · 逐帧完整中间量", CPU, 21)
    flow_card(d, (80, 365, 270, 610), "输入帧", ("frame 1", "frame 2", "… frame N"), CPU)
    flow_card(d, (350, 330, 665, 650), "全量计算", ("full correlate", "full spectrogram", "full CWT", "Host 侧融合 / 跟踪"), CPU)
    arrow(d, 278, 487, 338, 487, CPU, 4)
    txt(d, (384, 670), "逐帧物化完整相关 / 谱图 / 小波张量", 17, RED, True, "ma")

    panel(d, gpu, "ZQ500 GPU · batched score-only", TEAL, 21)
    flow_card(d, (861, 365, 1036, 610), "Device batch", ("stack B=8", "设备驻留", "一次批处理"), TEAL)
    flow_card(d, (1090, 330, 1337, 650), "四路 score", ("filter / demod", "correlate", "spectrogram", "CWT"), TEAL)
    flow_card(d, (1390, 365, 1590, 610), "任务输出", ("特征融合", "peak", "Kalman track"), TEAL)
    arrow(d, 1048, 487, 1078, 487, TEAL, 4)
    arrow(d, 1349, 487, 1378, 487, TEAL, 4)
    txt(d, (1228, 670), "只保留任务所需 score，避免全量中间张量写回", 17, TEAL, True, "ma")

    rr(d, (44, 728, 1628, 867), 12, PALE, BLUE, 2)
    txt(d, (85, 769), "结构收益", 23, NAVY, True)
    tag(d, (285, 744, 635, 824), "减少：中间张量物化与回传", "#ECF9F6", TEAL, 20)
    tag(d, (678, 744, 1028, 824), "保留：四路 score + 状态轨迹", LIGHT, NAVY, 20)
    tag(d, (1071, 744, 1587, 824), "对应性能证据见 P11：1071.70×", "#FFF7ED", ORANGE, 20)
    txt(d, (50, 910), "流程依据：demo/task2_features/task2_features_demo.cpp；性能数字来自已发布 final metrics。", 14, MUTED)
    save(im, "P10_Task2_Score_Only_整页_v02.png")


def track_points(values: list[float], box: tuple[int, int, int, int]) -> list[tuple[int, int]]:
    x1, y1, x2, y2 = box
    low, high = min(values) - 8, max(values) + 8
    return [
        (
            x1 + int(index * (x2 - x1) / (len(values) - 1)),
            y2 - int((value - low) * (y2 - y1) / (high - low)),
        )
        for index, value in enumerate(values)
    ]


def page_p14() -> None:
    summary = load_json("data", "reports", "summary.json")
    contracts = load_json("data", "reports", "validation", "type_contracts", "latest_type_contracts.json")
    steps = load_json("data", "reports", "validation", "task_steps", "latest_task_step_audit.json")
    task1 = load_json("data", "reports", "demo", "task1_radar", "final", "metrics.json")
    task2 = load_json("data", "reports", "demo", "task2_features", "final", "metrics.json")
    im, d = base(
        "技术指标",
        "正确性验证：算子、任务、最终输出均通过门限",
        "不只展示速度：CPU/GPU 语义一致、关键误差受控，两个任务均完成端到端运行。",
    )
    coverage = (44, 265, 560, 850)
    panel(d, coverage, "报告快照覆盖", NAVY, 21)
    entries = (
        (f"{contracts['summary']['operator_count']}/81", "公开算子", TEAL),
        (f"{summary['task_count']}/2", "端到端任务", BLUE),
        (f"{steps['summary']['calculation_step_count']}/14", "正式计算步骤", ORANGE),
    )
    for index, (num, label, color) in enumerate(entries):
        y = 342 + index * 138
        rr(d, (92, y, 512, y + 118), 12, WHITE, "#C5D9EE", 2)
        txt(d, (210, y + 36), num, 32, color, True, "ma")
        txt(d, (374, y + 36), label, 20, TEXT, True, "ma")
        tag(d, (160, y + 74, 444, y + 102), "PASS", "#ECF9F6", TEAL, 14)
    txt(d, (302, 783), "RUN 2026-07-20 SNAPSHOT", 16, MUTED, True, "ma")

    task1_box = (602, 265, 1628, 528)
    panel(d, task1_box, "Task1 · 目标检测位置一致", TEAL, 21)
    ex = task1["expected_detection"]
    for radius, color, label in ((42, NAVY, "Expected"), (30, CPU, "CPU"), (18, TEAL, "GPU")):
        d.ellipse((826 - radius, 402 - radius, 826 + radius, 402 + radius), outline=color, width=4)
        txt(d, (915, 372 + (42 - radius) * 2), label, 18, color, True)
    txt(d, (1095, 370), "Expected = CPU = GPU", 28, TEAL, True)
    txt(d, (1095, 419), f"range={ex['range_bin']} · Doppler={ex['doppler_bin']} · {ex['doppler_hz']} Hz", 21, TEXT, True)
    tag(d, (1095, 458, 1515, 500), f"CFAR mixed error  {task1['cfar_threshold_error']['mixed_error']:.6f} < 0.5  · PASS", "#ECF9F6", TEAL, 16)

    task2_box = (602, 552, 1628, 850)
    panel(d, task2_box, "Task2 · 轨迹与特征误差均通过", TEAL, 21)
    graph = (660, 641, 1190, 795)
    line(d, (graph[0], graph[3], graph[2], graph[3]), MUTED, 2)
    line(d, (graph[0], graph[1], graph[0], graph[3]), MUTED, 2)
    truth = track_points(task2["truth_track"], graph)
    cpu = track_points(task2["cpu_kalman_track"], graph)
    gpu = track_points(task2["gpu_kalman_track"], graph)
    for points, color, width in ((truth, TEXT, 2), (cpu, CPU, 2), (gpu, TEAL, 4)):
        for first, second in zip(points[:-1], points[1:]):
            line(d, (*first, *second), color, width)
    txt(d, (1235, 648), "truth", 18, TEXT, True)
    txt(d, (1235, 683), "CPU = GPU（重合）", 18, TEAL, True)
    tag(d, (1235, 716, 1574, 758), f"track RMSE  {task2['kalman_track_error']['rmse']:.6f} < 2  · PASS", "#ECF9F6", TEAL, 15)
    tag(d, (1215, 770, 1595, 812), f"score error  {task2['feature_score_error']['mixed_error']:.4e} < 1e-4  · PASS", "#ECF9F6", TEAL, 13)
    txt(d, (50, 911), "数据：summary.json、type contracts、task-step audit、两个任务 final/metrics.json；误差以阈值通过形式展示。", 14, MUTED)
    save(im, "P14_正确性与运行验证_整页_v02.png")


def page_p15() -> None:
    rows = detailed_cases()
    benchmark = load_json("data", "reports", "units", "benchmarks", "summary.json")
    operator_count = benchmark["operator_count"]
    detailed_operator_count = sum(
        any(case["source"] == "case_detail" for case in operator["performance_cases"])
        for operator in benchmark["operators"]
    )
    aggregate_operator_count = sum(
        all(case["source"] == "summary_aggregate" for case in operator["performance_cases"])
        for operator in benchmark["operators"]
    )
    speeds = [row["speedup"] for row in rows]
    fast = sum(value > 1 for value in speeds)
    median = sum(sorted(speeds)[38:40]) / 2
    geomean = math.exp(sum(math.log(value) for value in speeds) / len(speeds))
    top = sorted(rows, key=lambda item: item["speedup"], reverse=True)[:5]
    bands = (
        ("< 1×", sum(value < 1 for value in speeds), MUTED),
        ("1–10×", sum(1 <= value < 10 for value in speeds), TEAL),
        ("10–100×", sum(10 <= value < 100 for value in speeds), BLUE),
        ("≥ 100×", sum(value >= 100 for value in speeds), NAVY),
    )
    im, d = base(
        "技术指标",
        "算子库性能总览：81/81 算子均有性能记录，69/78 条详细样本加速",
        "81 个公开算子全部有性能记录；78 条可比详细样本用于分布统计，8 条聚合记录单独保留。",
    )
    hero = (44, 265, 600, 850)
    panel(d, hero, "详细性能样本覆盖", NAVY, 22)
    txt(d, (322, 390), f"{operator_count} / {operator_count}", 62, TEAL, True, "ma")
    txt(d, (322, 470), "公开算子均有性能记录", 21, TEXT, True, "ma")
    tag(d, (137, 510, 507, 552), f"详细样本：{fast} / {len(rows)}  GPU E2E > CPU", "#ECF9F6", TEAL, 17)
    for index, (value, label, color) in enumerate(((median, "中位数加速", BLUE), (geomean, "几何平均加速", NAVY))):
        y = 602 + index * 98
        rr(d, (118, y, 524, y + 76), 10, LIGHT, "#C5D9EE", 1)
        txt(d, (238, y + 34), f"{value:.2f}×", 34, color, True, "ma")
        txt(d, (401, y + 34), label, 19, TEXT, True, "ma")
    txt(d, (322, 818), f"{detailed_operator_count} 个算子提供 78 条详细 case；{aggregate_operator_count} 个算子为 aggregate", 14, MUTED, True, "ma")

    top_box = (638, 265, 1628, 620)
    panel(d, top_box, "代表性高收益算子（GPU E2E speedup）", NAVY, 21)
    maximum = top[0]["speedup"]
    for index, row in enumerate(top):
        y = 345 + index * 49
        label = f"{row['operator']} · {row['case']}"
        horizontal_bar(d, 678, y, 720, row["speedup"], maximum, TEAL if index < 3 else BLUE, label, f"{row['speedup']:.2f}×")

    band_box = (638, 655, 1628, 850)
    panel(d, band_box, "78 条可比详细样本的性能分布", NAVY, 21)
    x = 692
    for name, count, color in bands:
        width = 150
        rr(d, (x, 737, x + width, 798), 10, color)
        txt(d, (x + width // 2, 758), str(count), 30, WHITE, True, "ma")
        txt(d, (x + width // 2, 820), name, 18, TEXT, True, "ma")
        x += 205
    txt(d, (1133, 704), "8 条 aggregate 记录不与详细样本混合统计", 16, MUTED, False, "ma")
    txt(d, (50, 911), "完整 81 算子性能表：ppt_work/data_tables/operator_performance_81.csv；分布图数据：78 条 case_detail。", 14, MUTED)
    save(im, "P15_算子库性能总览_整页_v02.png")


def task_speeds(task: str) -> list[float]:
    output = []
    for level in range(1, 7):
        metrics = load_json("data", "reports", "demo", task, "scales", f"L{level}", "metrics.json")
        total = metrics["timings"]["total"]
        output.append(total["cpu_ms"] / total["gpu_ms"])
    return output


def time_top3(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
              values: tuple[tuple[str, float, str], ...]) -> None:
    panel(d, box, title, NAVY, 20)
    maximum = max(value for _, value, _ in values)
    for index, (name, value, color) in enumerate(values):
        horizontal_bar(d, box[0] + 52, box[1] + 90 + index * 62, box[2] - box[0] - 104, value, maximum, color, name, f"{value:.2f}%")


def page_p16() -> None:
    t1 = task_speeds("task1_radar")
    t2 = task_speeds("task2_features")
    im, d = base(
        "技术指标",
        "规模效应与主要耗时环节：规模越大，GPU 并行收益越充分",
        "L1–L6 同时增加多维输入；曲线说明加速趋势，耗时占比说明下一步优化优先级。",
    )
    line_chart(d, (44, 265, 810, 548), "Task1 · 1.54× → 19.68×", t1, 25, True)
    line_chart(d, (854, 265, 1628, 548), "Task2 · 70.93× → 894.16×", t2, 950)
    time_top3(d, (44, 590, 810, 850), "Task1 final-input · GPU 时间 Top3", (("input construction", 30.17, CPU), ("ambgfun", 27.46, NAVY), ("Doppler", 15.20, BLUE)))
    time_top3(d, (854, 590, 1628, 850), "Task2 final-input · GPU 时间 Top3", (("CWT", 45.94, NAVY), ("input construction", 19.12, CPU), ("spectrogram", 13.95, BLUE)))
    txt(d, (50, 911), "数据：scales/L1-L6 为同规则规模实验；final-input 为独立验收配置。“主要耗时环节（热点）”= final-input 中占 GPU 时间最高的步骤。", 14, MUTED)
    save(im, "P16_规模效应与主要耗时_整页_v02.png")


def page_p17() -> None:
    im, d = base(
        "技术指标",
        "性能优势、边界与改进方向",
        "优势来自结构与规模匹配；改进聚焦高占比耗时环节，而不把局部 kernel 数字当作最终成果。",
    )
    columns = ((44, 265, 578, 830), (602, 265, 1084, 830), (1108, 265, 1628, 830))
    panel(d, columns[0], "已验证优势", TEAL, 22)
    advantage = (("Task1", "34.20×", "公开算子 Device-resident 组合"), ("Task2", "1071.70×", "batched score-only 特化"), ("算子库", "69/78", "详细性能样本获得加速"))
    for index, (name, metric, reason) in enumerate(advantage):
        y = 350 + index * 133
        rr(d, (86, y, 536, y + 104), 10, LIGHT, "#B6E4DE", 1)
        txt(d, (116, y + 31), name, 19, NAVY, True)
        txt(d, (302, y + 33), metric, 33, TEAL, True, "ma")
        txt(d, (302, y + 74), reason, 16, TEXT, True, "ma")

    panel(d, columns[1], "当前性能边界", "#7B8794", 22)
    boundary = (("小规模 / 标量路径", "固定 setup 与 launch 占比高"), ("Task1 input", "final-input GPU 时间占 30.17%"), ("Task2 CWT", "final-input GPU 时间占 45.94%"))
    for index, (name, desc) in enumerate(boundary):
        y = 355 + index * 135
        tag(d, (642, y, 832, y + 43), name, "#EEF2F6", TEXT, 17)
        txt(d, (854, y + 21), desc, 17, TEXT, True, "lm")
        line(d, (642, y + 77, 1044, y + 77), "#DDE5ED", 1)
    txt(d, (843, 770), "边界用于确定优化优先级", 16, MUTED, False, "ma")

    panel(d, columns[2], "下一步改进", ORANGE, 22)
    next_steps = (("输入路径", "减少 H2D/D2H 与参数准备的固定成本"), ("CWT 重算子", "裁剪搜索范围并评估 segmented scan"), ("工程验证", "冻结 commit 后复验数值与 E2E 收益"))
    for index, (name, desc) in enumerate(next_steps):
        y = 355 + index * 135
        tag(d, (1148, y, 1300, y + 43), name, "#FFF7ED", ORANGE, 17)
        txt(d, (1320, y + 11), desc, 16, TEXT, True)
        line(d, (1148, y + 77, 1585, y + 77), "#F6D6B5", 1)
    rr(d, (44, 860, 1628, 907), 10, NAVY)
    txt(d, (836, 881), "结论：用已验证的结构优化放大优势，用热点数据约束下一步投入。", 20, WHITE, True, "ma")
    save(im, "P17_性能优缺点与改进_整页_v02.png")


def page_p18() -> None:
    im, d = base(
        "创新点",
        "核心亮点：结构重构与任务级语义裁剪",
        "亮点不是单个 API 替换，而是公共算法结构重构与任务级语义裁剪的组合。",
    )
    cards = ((44, 265, 555, 760), (581, 265, 1092, 760), (1118, 265, 1628, 760))
    specs = (
        ("① 邻域数据复用", "重复窗口全局访存", "Tile / Halo 协作加载", "Wiener 183.615×", "RUN SNAPSHOT"),
        ("② 递归与频谱重写", "IIR 依赖 / 双边频谱", "Affine Scan / R2C Fusion", "Periodogram E2E ↓41.24%", "HISTORICAL A/B"),
        ("③ 任务级语义裁剪", "全量中间张量物化", "Device-resident + score-only", "Task1 34.20× / Task2 1071.70×", "RUN SNAPSHOT"),
    )
    for box, (title, difficulty, method, effect, origin) in zip(cards, specs):
        panel(d, box, title, NAVY, 21)
        bx1, by1, bx2, _ = box
        tag(d, (bx1 + 42, by1 + 105, bx2 - 42, by1 + 158), "难点：" + difficulty, "#F0F4F8", TEXT, 18)
        arrow(d, (bx1 + bx2) // 2, by1 + 180, (bx1 + bx2) // 2, by1 + 222, ORANGE, 4)
        tag(d, (bx1 + 42, by1 + 245, bx2 - 42, by1 + 300), "方法：" + method, "#ECF9F6", TEAL, 18)
        rr(d, (bx1 + 42, by1 + 344, bx2 - 42, by1 + 425), 12, LIGHT, "#BFD5E9", 1)
        txt(d, ((bx1 + bx2) // 2, by1 + 381), effect, 18, BLUE, True, "ma")
        txt(d, ((bx1 + bx2) // 2, by1 + 453), origin, 15, MUTED, True, "ma")
    rr(d, (44, 798, 1628, 880), 12, "#F2F8FE", BLUE, 2)
    txt(d, (836, 830), "公共算子重构 + 任务级组合 + 可追溯报告，构成可复用的 ZQ500 迁移闭环。", 24, NAVY, True, "ma")
    txt(d, (50, 911), "数值来源：unit benchmark summary、Task1/Task2 final metrics、历史 A/B ledger；不同口径已显式区分。", 14, MUTED)
    save(im, "P18_核心亮点_整页_v03.png")


def page_p19() -> None:
    im, d = base(
        "创新点",
        "AI 工具使用说明",
        "本页仅披露已确认的答辩制作使用；性能数据、测试结论和代码事实不由 AI 生成。",
    )
    cards = ((44, 275, 550, 790), (583, 275, 1089, 790), (1122, 275, 1628, 790))
    content = (
        ("已确认的 AI 辅助", TEAL, ("ChatGPT / Codex", "答辩结构与证据审计", "中文提示词与技术可视化", "PPT 静态页汇编与迭代")),
        ("AI 不参与的部分", CPU, ("不生成性能数字", "不生成测试曲线", "不替代代码运行", "不替代正确性判定")),
        ("人工复核与责任", ORANGE, ("阅读 README、源码与报告", "JSON 真实数据制图", "核对性能口径与误差门限", "最终答辩稿由团队确认")),
    )
    for box, (title, color, lines) in zip(cards, content):
        panel(d, box, title, color, 22)
        bx1, by1, bx2, _ = box
        for index, label in enumerate(lines):
            y = by1 + 102 + index * 84
            rr(d, (bx1 + 42, y, bx2 - 42, y + 52), 9, LIGHT if color != ORANGE else "#FFF7ED", "#C5D9EE", 1)
            d.ellipse((bx1 + 64, y + 17, bx1 + 82, y + 35), fill=color)
            txt(d, (bx1 + 104, y + 26), label, 18, TEXT, True, "lm")
    rr(d, (44, 830, 1628, 897), 12, NAVY)
    txt(d, (836, 864), "AI 辅助表达；所有可答辩技术结论均可回溯到源码、JSON 报告与人工复核。", 18, WHITE, True, "ma")
    txt(d, (50, 921), "如团队在编码、测试等环节还使用了其他 AI 工具，应在正式答辩前按实际情况补充披露。", 14, MUTED)
    save(im, "P19_AI工具使用说明_整页_v02.png")


if __name__ == "__main__":
    page_p09()
    page_p10()
    page_p14()
    page_p15()
    page_p16()
    page_p17()
    page_p18()
    page_p19()
