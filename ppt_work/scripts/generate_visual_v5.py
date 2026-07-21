#!/usr/bin/env python3
"""High-visual, evidence-bounded refresh for the technical defense deck.

The visual language follows the strongest early technical pages: one dominant
technical mechanism per panel, blue hierarchy bands, visual cause→method→value
paths, and no decorative images without a technical meaning.  Pages that await
the unified L1–L6 rerun deliberately render measurement slots rather than
inventing curves or performance values.
"""

from __future__ import annotations

from PIL import ImageDraw

from generate_data_pages import (
    BLUE, CPU, LIGHT, MUTED, NAVY, ORANGE, PALE, TEXT, TEAL, WHITE,
    arrow, base, card_header, line, rr, save, txt,
)


def panel(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
          color: str = NAVY, size: int = 21) -> None:
    """A large white technical canvas with a stable blue header band."""
    card_header(d, box, title, color, size)


def chip(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str,
         fill: str, color: str = WHITE, size: int = 15, edge: str | None = None) -> None:
    rr(d, box, 8, fill, edge or fill, 1)
    txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), label, size, color, True, "mm")


def shadow_card(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                fill: str = WHITE, edge: str = "#BDD2E8") -> None:
    x1, y1, x2, y2 = box
    rr(d, (x1 + 4, y1 + 6, x2 + 4, y2 + 6), 10, "#DDE9F3")
    rr(d, box, 10, fill, edge, 2)


def grid(d: ImageDraw.ImageDraw, x: int, y: int, cols: int, rows: int,
         cell: int, active: int, color: str = TEAL, halo: bool = False) -> None:
    """A grid represents tensor/array layout, not decoration."""
    for row in range(rows):
        for col in range(cols):
            idx = row * cols + col
            fill = color if idx < active else "#DCE8F3"
            if halo and (row in (0, rows - 1) or col in (0, cols - 1)):
                fill = ORANGE
            rr(d, (x + col * (cell + 3), y + row * (cell + 3),
                   x + col * (cell + 3) + cell, y + row * (cell + 3) + cell),
               2, fill, fill, 1)


def wave(d: ImageDraw.ImageDraw, x: int, y: int, width: int, height: int,
         color: str = BLUE) -> None:
    points = []
    pattern = (0.50, 0.45, 0.78, 0.20, 0.85, 0.34, 0.62, 0.15, 0.54, 0.42, 0.62, 0.47)
    for i, f in enumerate(pattern):
        points.append((x + int(i * width / (len(pattern) - 1)), y + int(f * height)))
    for a, b in zip(points[:-1], points[1:]):
        line(d, (*a, *b), color, 3)


def target(d: ImageDraw.ImageDraw, cx: int, cy: int, radius: int = 35) -> None:
    for rad, col in ((radius, NAVY), (int(radius * .68), CPU), (int(radius * .36), TEAL)):
        d.ellipse((cx-rad, cy-rad, cx+rad, cy+rad), outline=col, width=3)
    line(d, (cx-radius-8, cy, cx+radius+8, cy), ORANGE, 1)
    line(d, (cx, cy-radius-8, cx, cy+radius+8), ORANGE, 1)


def route_arrow(d: ImageDraw.ImageDraw, x: int, y: int, label: str, color: str = BLUE) -> None:
    d.polygon([(x, y), (x+22, y-18), (x+167, y-18), (x+189, y),
               (x+167, y+18), (x+22, y+18)], fill=color)
    txt(d, (x+94, y), label, 14, WHITE, True, "mm")


def mechanism_row(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                  number: str, title: str, detail: str, kind: str) -> None:
    x1, y1, x2, y2 = box
    shadow_card(d, box, "#FBFDFF")
    d.ellipse((x1+18, y1+19, x1+57, y1+58), fill=BLUE)
    txt(d, (x1+37, y1+39), number, 18, WHITE, True, "mm")
    txt(d, (x1+73, y1+29), title, 18, NAVY, True, "lm")
    txt(d, (x1+73, y1+57), detail, 13, TEXT, True, "lm")
    sx = x2 - 215
    cy = (y1 + y2) // 2
    if kind == "resident":
        chip(d, (sx, cy-23, sx+47, cy+23), "H", "#EEF3F8", MUTED, 15, "#C2D5E7")
        arrow(d, sx+55, cy, sx+93, cy, ORANGE, 2)
        rr(d, (sx+104, cy-27, sx+200, cy+27), 8, "#E9F9F7", "#8ED8D3", 2)
        for i, op in enumerate(("A", "B", "N")):
            chip(d, (sx+112+i*27, cy-15, sx+135+i*27, cy+15), op, TEAL, WHITE, 11)
    elif kind == "cache":
        rr(d, (sx+12, cy-24, sx+72, cy+24), 16, "#E9F9F7", TEAL, 2)
        d.ellipse((sx+12, cy-30, sx+72, cy-18), fill="#F5FFFE", outline=TEAL, width=2)
        txt(d, (sx+42, cy), "pool", 12, TEAL, True, "mm")
        arrow(d, sx+80, cy, sx+111, cy, TEAL, 2)
        for i, label in enumerate(("plan", "win", "H2D")):
            chip(d, (sx+121+i*27, cy-18, sx+146+i*27, cy+18), label, LIGHT, TEAL, 9, "#9CCCE8")
    else:
        chip(d, (sx, cy-22, sx+57, cy+22), "shape", LIGHT, BLUE, 11, "#A9C8E6")
        arrow(d, sx+63, cy, sx+93, cy, BLUE, 2)
        for i, label in enumerate(("Tile", "Scan", "R2C")):
            chip(d, (sx+103+i*32, cy-18, sx+130+i*32, cy+18), label, "#E9F9F7", TEAL, 9, "#8ED8D3")


def task_mini_flow(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                   task: str, speed: str, kind: str) -> None:
    x1, y1, x2, y2 = box
    shadow_card(d, box, "#FCFEFF", "#B8D5E8")
    txt(d, (x1+24, y1+25), task, 18, TEAL, True, "lm")
    if kind == "radar":
        grid(d, x1+32, y1+60, 4, 4, 12, 10, BLUE)
        arrow(d, x1+95, y1+87, x1+135, y1+87, BLUE, 2)
        grid(d, x1+145, y1+60, 4, 4, 12, 12, TEAL)
        arrow(d, x1+208, y1+87, x1+244, y1+87, TEAL, 2)
        target(d, x1+279, y1+87, 22)
        evidence = "公开算子驻留组合 → 检测"
    else:
        grid(d, x1+32, y1+62, 3, 3, 13, 7, BLUE)
        arrow(d, x1+85, y1+87, x1+124, y1+87, BLUE, 2)
        for i in range(4):
            rr(d, (x1+136, y1+59+i*16, x1+191, y1+70+i*16), 2, TEAL)
        arrow(d, x1+202, y1+87, x1+239, y1+87, TEAL, 2)
        pts = ((0, 25), (16, 14), (31, 23), (47, 5), (63, 15))
        prev = None
        for px, py in pts:
            cur = (x1+250+px, y1+70+py)
            if prev: line(d, (*prev, *cur), TEAL, 2)
            prev = cur
        evidence = "算子库 + helper → score / 轨迹"
    txt(d, (x1+24, y2-29), evidence, 12, TEXT, True, "lm")
    rr(d, (x2-122, y2-54, x2-18, y2-18), 8, "#FFF7ED", "#F4C17A", 1)
    txt(d, (x2-70, y2-36), speed, 20, ORANGE, True, "mm")


def page_p04() -> None:
    im, d = base(
        "技术路线",
        "“3 + 2 + 5” 技术路线",
        "三类通用机制支撑两条应用构建，并形成五种可组合优化路径。",
    )
    left, right = (44, 265, 756, 791), (788, 265, 1628, 791)
    panel(d, left, "底层公共算子库优化", NAVY, 23)
    route_arrow(d, 279, 341, "3 类通用机制")
    mechanism_row(d, (73, 388, 726, 480), "1", "Device-resident 数据链", "入口 H2D 一次；链内 Device 连续执行；边界 .get() 回传", "resident")
    mechanism_row(d, (73, 501, 726, 593), "2", "存储与准备缓存复用", "DeviceStorage 容量复用；plan / window / uploaded content 可复用", "cache")
    mechanism_row(d, (73, 614, 726, 706), "3", "Shape-aware 分派与融合", "按 shape 选择路径；在合法场景融合，删减中间写回", "dispatch")
    rr(d, (73, 729, 726, 766), 8, "#E9F9F7", "#9CDDD8", 1)
    txt(d, (399, 747), "代表展开：Wiener Tile/Halo · IIR Scan · Periodogram", 14, TEAL, True, "mm")

    panel(d, right, "应用级算法构建", NAVY, 23)
    route_arrow(d, 895, 341, "2 条任务构建")
    task_mini_flow(d, (820, 387, 1205, 520), "Task1 雷达检测", "34.20×", "radar")
    task_mini_flow(d, (820, 546, 1205, 679), "Task2 特征融合与跟踪", "1071.70×", "feature")
    txt(d, (1012, 718), "已发布快照 · 统一复测后替换", 13, MUTED, True, "ma")

    route_arrow(d, 1300, 341, "5 类路径")
    routes = ("设备驻留 / 批处理", "准备与内容缓存", "融合 / 直接写回", "并行 Scan / 归约", "score-only / 紧凑输出")
    for i, label in enumerate(routes):
        y = 390 + i*68
        rr(d, (1242, y, 1589, y+45), 9, "#FBFDFF", "#9DC7E7", 2)
        d.ellipse((1258, y+10, 1283, y+35), fill=BLUE)
        txt(d, (1270, y+22), str(i+1), 13, WHITE, True, "mm")
        txt(d, (1302, y+22), label, 16, TEXT, True, "lm")
        if i < 4:
            line(d, (1420, y+45, 1420, y+64), "#BCD0E4", 2)
    rr(d, (44, 825, 1628, 892), 12, NAVY)
    txt(d, (836, 858), "3 类公共机制 + 2 条应用构建 + 5 类组合路径：让优化从算子延续到完整任务链。", 22, WHITE, True, "ma")
    txt(d, (50, 921), "Task 速度为已发布 2026-07-20 快照；正式答辩数据由统一 L1–L6 新 L6 复测替换。", 14, MUTED)
    save(im, "P04_技术路线_视觉重构_v05.png")


def scale_ladder(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str,
                 question: str, final_note: str, color: str) -> None:
    """Visualizes the fixed-path L1–L6 protocol without fabricating a curve."""
    panel(d, box, f"{task} · 仅输入规模递增", color, 20)
    x1, y1, x2, y2 = box
    txt(d, (x1+38, y1+82), question, 18, TEXT, True)
    base_y = y1 + 238
    line(d, (x1+62, base_y, x2-62, base_y), "#ADC3D8", 3)
    positions = []
    for i in range(6):
        x = x1 + 96 + i * int((x2-x1-192) / 5)
        positions.append(x)
        cols, rows, size = 2 + i//2, 2 + i//3, 16 + i*2
        grid(d, x-cols*(size+3)//2, base_y-48-rows*(size+3), cols, rows, size,
             cols*rows-i, ORANGE if i == 5 else color)
        d.ellipse((x-10, base_y-10, x+10, base_y+10), fill=ORANGE if i == 5 else color,
                  outline=WHITE, width=2)
        txt(d, (x, base_y+31), f"L{i+1}", 17, ORANGE if i == 5 else NAVY, True, "ma")
    for a, b in zip(positions[:-1], positions[1:]):
        arrow(d, a+14, base_y, b-14, base_y, "#9CB9D2", 2)
    rr(d, (x1+44, y2-62, x2-44, y2-25), 7, "#ECF9F6", "#8FD8D3", 1)
    txt(d, ((x1+x2)//2, y2-44), final_note, 15, TEAL, True, "mm")


def result_slot(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str,
                lines: tuple[str, ...]) -> None:
    panel(d, box, f"{task} · 新 L6 端到端结果", TEAL, 19)
    x1, y1, x2, y2 = box
    txt(d, ((x1+x2)//2, y1+78), "统一复测后直接导出", 16, MUTED, True, "ma")
    for cx, label, color in ((x1+102, "CPU", CPU), (x1+244, "GPU", TEAL)):
        d.ellipse((cx-43, y1+105, cx+43, y1+191), fill="#F8FBFE", outline=color, width=3)
        d.ellipse((cx-33, y1+115, cx+33, y1+181), outline="#CBDCEB", width=1)
        txt(d, (cx, y1+137), label, 18, color, True, "ma")
        txt(d, (cx, y1+165), "total ms", 12, MUTED, True, "ma")
    arrow(d, x1+301, y1+148, x1+348, y1+148, ORANGE, 3)
    rr(d, (x1+364, y1+112, x2-30, y1+190), 10, "#FFF7ED", "#F4BE77", 2)
    txt(d, ((x1+364+x2-30)//2, y1+140), "speedup", 22, ORANGE, True, "ma")
    txt(d, ((x1+364+x2-30)//2, y1+167), "CPU ÷ GPU", 13, MUTED, True, "ma")
    for i, label in enumerate(lines):
        d.ellipse((x1+51, y1+226+i*27, x1+59, y1+234+i*27), fill=TEAL)
        txt(d, (x1+73, y1+230+i*27), label, 14, TEXT, True, "lm")


def radar_gate(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], heading: str) -> None:
    panel(d, box, heading, TEAL, 20)
    x1, y1, x2, y2 = box
    target(d, x1+180, y1+133, 45)
    labels = (("Expected", NAVY), ("CPU", CPU), ("GPU", TEAL))
    for i, (label, color) in enumerate(labels):
        txt(d, (x1+262, y1+100+i*28), label, 15, color, True, "lm")
    txt(d, (x1+470, y1+99), "检测语义一致", 22, NAVY, True, "lm")
    chip(d, (x1+470, y1+131, x2-42, y1+175), "位置 / CFAR error · 待填 PASS", "#ECF9F6", TEAL, 16, "#9CDDD8")
    arrow(d, x1+302, y1+145, x1+430, y1+145, TEAL, 3)
    txt(d, (x1+470, y2-18), "速度、位置与误差必须来自同一统一 L6 run", 15, NAVY, True, "lm")


def task2_track_gate(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], heading: str) -> None:
    panel(d, box, heading, TEAL, 20)
    x1, y1, x2, y2 = box
    chart = (x1+74, y1+93, x1+505, y2-48)
    line(d, (chart[0], chart[3], chart[2], chart[3]), "#A9BED2", 2)
    line(d, (chart[0], chart[1], chart[0], chart[3]), "#A9BED2", 2)
    points = ((0, 98), (70, 78), (130, 87), (203, 45), (272, 63), (349, 26), (420, 48))
    last = None
    for px, py in points:
        current = (chart[0]+px, chart[1]+py)
        if last:
            line(d, (*last, *current), TEXT, 2)
            line(d, (last[0], last[1]+2, current[0], current[1]+2), TEAL, 3)
        d.ellipse((current[0]-4, current[1]-4, current[0]+4, current[1]+4), fill=TEAL)
        last = current
    txt(d, (chart[2]+20, chart[1]+35), "CPU", 15, TEXT, True, "lm")
    txt(d, (chart[2]+20, chart[1]+64), "GPU", 15, TEAL, True, "lm")
    txt(d, (x1+620, y1+108), "CPU / GPU 轨迹", 22, NAVY, True, "lm")
    chip(d, (x1+620, y1+143, x2-44, y1+189), "RMSE / feature error · 待填 PASS", "#ECF9F6", TEAL, 15, "#9CDDD8")
    txt(d, (x1+620, y1+230), "仅验证同一 score-only 路径", 15, MUTED, True, "lm")


def page_p09() -> None:
    im, d = base(
        "技术指标",
        "Task1 统一 L1–L6：先建立可比基线，再讨论加速趋势",
        "固定公开算子处理链、分块和 CFAR 参数；只有输入规模递增，原 final-input 纳入新 L6。",
    )
    scale_ladder(d, (44, 274, 1016, 646), "Task1", "规模递增时，GPU 并行度如何释放？",
                 "L6 = 原 final-input 的配置；待复测后写入真实 speedup", TEAL)
    result_slot(d, (1042, 274, 1628, 646), "Task1", ("窗口 / CFAR 参数冻结", "公开算子链冻结", "误差门限冻结"))
    radar_gate(d, (44, 670, 1628, 871), "Task1 · 新 L6 正确性门")
    txt(d, (50, 912), "数据槽位：task1_radar/unified_scales/L1…L6/metrics.json；不回填旧 scales 或旧 final-input 性能数字。", 14, MUTED)
    save(im, "P09_Task1_统一L1-L6_视觉重构_v05.png")


def cpu_tensor_scene(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    panel(d, box, "CPU reference · 逐帧物化完整中间量", CPU, 20)
    x1, y1, x2, y2 = box
    for i, label in enumerate(("frame 1", "frame 2", "frame 3", "… frame N")):
        x = x1+58+i*124
        grid(d, x, y1+118, 3, 3, 17, 7, CPU)
        txt(d, (x+30, y1+190), label, 13, MUTED, True, "ma")
        if i < 3: arrow(d, x+76, y1+151, x+109, y1+151, CPU, 2)
    rr(d, (x1+65, y1+245, x2-65, y1+325), 8, "#F1F4F7", "#C7D5E2", 1)
    txt(d, ((x1+x2)//2, y1+273), "correlate · spectrogram · CWT", 20, CPU, True, "ma")
    txt(d, ((x1+x2)//2, y1+301), "每帧生成完整中间张量并回传", 15, MUTED, True, "ma")
    for i in range(3):
        chip(d, (x1+126+i*128, y2-59, x1+228+i*128, y2-27), "中间张量", "#EEF2F6", CPU, 11, "#C5D3DF")


def gpu_score_scene(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    panel(d, box, "ZQ500 GPU · batched score-only", TEAL, 20)
    x1, y1, x2, y2 = box
    # A stack of three small frame grids makes B=8 batching concrete.
    for i in range(4):
        grid(d, x1+62+i*19, y1+109, 3, 3, 14, 7, TEAL)
    chip(d, (x1+58, y1+220, x1+240, y1+270), "B=8 Device batch", "#ECF9F6", TEAL, 17, "#9CDDD8")
    arrow(d, x1+258, y1+245, x1+312, y1+245, TEAL, 3)
    for i, label in enumerate(("filter", "corr", "spec", "CWT")):
        y = y1+121+i*38
        rr(d, (x1+328, y, x1+472, y+22), 4, "#E9F9F7", "#9CDDD8", 1)
        rr(d, (x1+328, y, x1+378+i*14, y+22), 4, TEAL)
        txt(d, (x1+486, y+11), label, 13, TEXT, True, "lm")
    arrow(d, x1+545, y1+189, x1+598, y1+189, ORANGE, 3)
    rr(d, (x1+612, y1+122, x2-45, y1+264), 10, "#FFF7ED", "#F4C17A", 2)
    for i, label in enumerate(("fusion", "peak", "track")):
        txt(d, ((x1+612+x2-45)//2, y1+151+i*34), label, 18, ORANGE, True, "ma")
    txt(d, ((x1+x2)//2, y2-41), "只保留四路 score 与状态轨迹，不写回全量中间张量", 15, TEAL, True, "ma")


def page_p10() -> None:
    im, d = base(
        "核心技术",
        "Task2：从全量张量到四路 score",
        "任务语义不变：GPU 保留后续决策所需 score 与状态轨迹，删除无效物化与回传。",
    )
    cpu_tensor_scene(d, (44, 276, 758, 686))
    gpu_score_scene(d, (786, 276, 1628, 686))
    panel(d, (44, 724, 1628, 866), "同一任务语义下的测评约束", NAVY, 20)
    rules = (("固定", "B=8 / score-only", TEAL), ("仅变", "帧数、每帧输入长度", ORANGE), ("验证", "P11 新 L1–L6 + 轨迹误差", BLUE))
    for i, (prefix, body, color) in enumerate(rules):
        x = 135+i*502
        rr(d, (x, 790, x+418, 838), 9, "#ECF9F6" if color == TEAL else "#FFF7ED" if color == ORANGE else LIGHT, color, 2)
        chip(d, (x+14, 800, x+72, 828), prefix, color, WHITE, 14)
        txt(d, (x+94, 814), body, 17, color, True, "lm")
    txt(d, (50, 912), "mixed：公开算子库与 task helper 协同调用；helper 不是第三后端，不展示旧 final-input 性能数字。", 14, MUTED)
    save(im, "P10_Task2_Score_Only_视觉重构_v05.png")


def page_p11() -> None:
    im, d = base(
        "技术指标",
        "Task2 统一 L1–L6：以 score-only 路径验证规模收益",
        "冻结 B=8、Device-resident、score-only 与门限；仅改变帧数和每帧输入长度。",
    )
    scale_ladder(d, (44, 274, 1016, 646), "Task2", "帧数与输入长度递增时，端到端收益如何变化？",
                 "L6 = 原 final-input 的配置；待复测后写入真实 speedup", BLUE)
    result_slot(d, (1042, 274, 1628, 646), "Task2", ("B=8 / score-only 冻结", "filter / CWT / track 路径冻结", "feature 与 track 门限冻结"))
    task2_track_gate(d, (44, 670, 1628, 871), "Task2 · 新 L6 轨迹与特征门")
    txt(d, (50, 912), "数据槽位：task2_features/unified_scales/L1…L6/metrics.json；无独立传统 GPU 基线。", 14, MUTED)
    save(im, "P11_Task2_统一L1-L6_视觉重构_v05.png")


def coverage_panel(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int]) -> None:
    panel(d, box, "① 覆盖、合约与任务链对照", NAVY, 20)
    x1, y1, x2, y2 = box
    specs = (("81/81", "公开算子", "type / shape / axis 合约", TEAL),
             ("2/2", "端到端任务", "CPU 与 GPU 同链对照", BLUE),
             ("14/14", "正式计算步骤", "error 与 GPU event 同时记录", ORANGE))
    for i, (count, label, detail, color) in enumerate(specs):
        y = y1+92+i*142
        d.ellipse((x1+55, y, x1+153, y+98), fill=WHITE, outline=color, width=4)
        txt(d, (x1+104, y+34), count, 25, color, True, "ma")
        txt(d, (x1+104, y+69), label, 14, TEXT, True, "ma")
        arrow(d, x1+170, y+49, x1+232, y+49, color, 3)
        rr(d, (x1+253, y+14, x2-42, y+84), 9, LIGHT, "#BED4E9", 1)
        txt(d, ((x1+253+x2-42)//2, y+49), detail, 16, TEXT, True, "mm")
    rr(d, (x1+46, y2-58, x2-42, y2-25), 7, "#ECF9F6", "#9CDDD8", 1)
    txt(d, ((x1+46+x2-42)//2, y2-41), "统一 L6 是速度与任务正确性的共同门禁", 15, TEAL, True, "mm")


def page_p14() -> None:
    im, d = base(
        "技术指标",
        "正确性：从算子合约到任务输出的三层验证",
        "不是只测速度：新 L6 的端到端速度、误差与业务语义必须由同一次运行共同确认。",
    )
    coverage_panel(d, (44, 274, 592, 870))
    radar_gate(d, (626, 274, 1628, 548), "② Task1 · 目标检测一致")
    task2_track_gate(d, (626, 578, 1628, 870), "③ Task2 · 特征与轨迹一致")
    txt(d, (50, 912), "正式答辩不沿用旧 final-input 误差；新结果来自两个 unified_scales/L6/metrics.json。", 14, MUTED)
    save(im, "P14_统一L6正确性_视觉重构_v05.png")


def empty_scale_canvas(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str,
                       color: str) -> None:
    panel(d, box, f"{task} · speedup 测量画布", color, 19)
    x1, y1, x2, y2 = box
    px1, py1, px2, py2 = x1+58, y1+99, x2-34, y2-50
    for i in range(4):
        y = py1+i*int((py2-py1)/3)
        line(d, (px1, y, px2, y), "#E0EBF4", 1)
    line(d, (px1, py1, px1, py2), "#A4BDD3", 2)
    line(d, (px1, py2, px2, py2), "#A4BDD3", 2)
    for i in range(6):
        x = px1+i*int((px2-px1)/5)
        # Deliberately unconnected: no assertion of a monotonic trend before data exists.
        d.ellipse((x-8, py2-8, x+8, py2+8), fill=ORANGE if i == 5 else WHITE,
                  outline=ORANGE if i == 5 else color, width=3)
        txt(d, (x, py2+27), f"L{i+1}", 15, ORANGE if i == 5 else NAVY, True, "ma")
        txt(d, (x, py2-26), "待填", 12, MUTED, True, "ma")
    chip(d, (x1+190, y1+109, x2-55, y1+148), "复测后插入真实曲线；不预设单调趋势", "#ECF9F6", TEAL, 14, "#9CDDD8")


def hotspot_steps(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str,
                  color: str) -> None:
    panel(d, box, f"{task} · 新 L6 GPU 热点 Top3", color, 19)
    x1, y1, x2, y2 = box
    steps = (("Top1", 380), ("Top2", 300), ("Top3", 220))
    for i, (label, width) in enumerate(steps):
        y = y1+98+i*53
        x = x1+78+(380-width)//2
        rr(d, (x, y, x+width, y+35), 7, color if i == 0 else LIGHT, color, 2)
        txt(d, (x+50, y+17), label, 15, WHITE if i == 0 else color, True, "ma")
        txt(d, (x+155, y+17), "步骤 / GPU ms / 占比（待填）", 13, WHITE if i == 0 else TEXT, True, "ma")
    txt(d, ((x1+x2)//2, y2-28), "热点 = stream work 中 GPU total 占比最高的步骤", 13, MUTED, True, "ma")


def page_p16() -> None:
    im, d = base(
        "技术指标",
        "规模效应与热点：复测后回答“何时加速、先优化什么”",
        "统一曲线只讨论规模；新 L6 Top3 只讨论瓶颈。两类结论分开测量、再建立因果。",
    )
    empty_scale_canvas(d, (44, 276, 810, 552), "Task1", TEAL)
    empty_scale_canvas(d, (854, 276, 1628, 552), "Task2", BLUE)
    hotspot_steps(d, (44, 596, 810, 868), "Task1", TEAL)
    hotspot_steps(d, (854, 596, 1628, 868), "Task2", BLUE)
    txt(d, (50, 912), "只使用新 unified_scales/L1…L6 数据；GPU event 代表 stream work，不能解释为单 kernel profiler 时间。", 14, MUTED)
    save(im, "P16_统一L1-L6规模与热点_视觉重构_v05.png")


def small_mechanism(d: ImageDraw.ImageDraw, cx: int, cy: int, kind: int, color: str) -> None:
    if kind == 0:
        grid(d, cx-34, cy-28, 4, 4, 12, 11, color, halo=True)
        rr(d, (cx-18, cy-11, cx+29, cy+36), 4, "#FFF7ED", ORANGE, 2)
    elif kind == 1:
        for level, n in enumerate((1, 2, 4)):
            y = cy-31+level*26
            for i in range(n):
                x = cx-(n-1)*25//2+i*25
                d.ellipse((x-6, y-6, x+6, y+6), fill=color)
            if level < 2: line(d, (cx, y+6, cx, y+19), BLUE, 2)
    else:
        grid(d, cx-43, cy-25, 3, 3, 12, 7, CPU)
        arrow(d, cx-1, cy, cx+31, cy, ORANGE, 3)
        for i in range(4):
            rr(d, (cx+39, cy-29+i*16, cx+88, cy-19+i*16), 3, color, color, 1)


def roadmap_column(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                   title: str, color: str, items: tuple[tuple[str, str, int], ...]) -> None:
    panel(d, box, title, color, 20)
    x1, y1, x2, _ = box
    for i, (heading, detail, kind) in enumerate(items):
        y = y1+95+i*124
        small_mechanism(d, x1+70, y+38, kind, color)
        txt(d, (x1+142, y+20), heading, 19, color, True, "lm")
        txt(d, (x1+142, y+52), detail, 14, TEXT, True, "lm")
        if i < len(items)-1:
            line(d, (x1+70, y+82, x1+70, y+112), "#BFD2E4", 2)


def page_p17() -> None:
    im, d = base(
        "技术指标",
        "性能优势、实验边界与下一轮优化",
        "先完成统一可比测量；再让分块、阈值和 batch/shape 成为独立 A/B 变量，而不是混入规模曲线。",
    )
    roadmap_column(d, (44, 286, 540, 778), "已实现的结构优化", TEAL,
                   (("邻域复用", "Tile / Halo：减少重复 global read", 0),
                    ("递归转并行", "Affine Scan：把长状态链改成树形前缀", 1),
                    ("删减中间量", "R2C / score-only：只保留任务需要的信息", 2)))
    roadmap_column(d, (586, 286, 1082, 778), "先补齐统一复测", BLUE,
                   (("L6 对齐", "原 final-input 规格成为新的统一 L6", 0),
                    ("只变规模", "L1–L5 仅增加输入规模", 1),
                    ("同 run 绑定", "CPU/GPU total、误差、语义一并记录", 2)))
    roadmap_column(d, (1128, 286, 1628, 778), "再做独立 A/B", ORANGE,
                   (("Block / Halo", "按 Top3 热点单独比较 block、halo", 0),
                    ("CFAR 参数", "guard / reference / PFA 单独扫描", 1),
                    ("batch / shape", "按任务路径验证 batch 与输入形状", 2)))
    arrow(d, 545, 532, 580, 532, "#9DBAD3", 4)
    arrow(d, 1087, 532, 1122, 532, "#9DBAD3", 4)
    rr(d, (160, 817, 1512, 880), 11, NAVY)
    txt(d, (836, 848), "先可比、再定位、后调参：让每一个优化结论都能回到同一基线验证。", 21, WHITE, True, "ma")
    txt(d, (50, 912), "参数优化结果只能由统一协议上的独立 A/B 填入；当前不将“计划”表述成已获得的性能效果。", 14, MUTED)
    save(im, "P17_统一测评与改进方向_视觉重构_v05.png")


def feature_branch(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
                   difficulty: str, method: str, value: str, kind: int, color: str) -> None:
    panel(d, box, title, color, 18)
    x1, y1, x2, y2 = box
    small_mechanism(d, (x1+x2)//2-18, y1+135, kind, color)
    for i, (label, text, shade) in enumerate((("难点", difficulty, "#F0F4F8"),
                                                ("方法", method, "#ECF9F6"),
                                                ("价值", value, "#FFF7ED"))):
        y = y1+205+i*58
        rr(d, (x1+30, y, x2-30, y+39), 7, shade, "#C7D9EA", 1)
        txt(d, (x1+50, y+20), label, 14, color if i < 2 else ORANGE, True, "mm")
        txt(d, (x1+97, y+20), text, 15, TEXT, True, "lm")


def page_p18() -> None:
    im, d = base(
        "创新点",
        "核心亮点：把不适合 GPU 的结构重写为并行结构",
        "从访存、数据依赖到任务输出语义，三类结构性重构共同减少无效工作并提升可组合性。",
    )
    feature_branch(d, (44, 286, 548, 748), "① 邻域访存重构", "重叠窗口反复读 global memory",
                   "Tile / Halo 协作加载", "块内复用同一 Halo 数据", 0, TEAL)
    feature_branch(d, (584, 286, 1088, 748), "② 递归与频谱重构", "长状态链 / 双边频谱冗余",
                   "Affine Scan / R2C", "缩短依赖、减少无效频点", 1, BLUE)
    feature_branch(d, (1124, 286, 1628, 748), "③ 任务语义裁剪", "完整中间张量物化与回传",
                   "Device-resident + score-only", "只保留 score 与轨迹", 2, ORANGE)
    # Three branches converge on one reusable execution core.
    for x in (296, 836, 1376):
        arrow(d, x, 772, x, 805, BLUE, 3)
    rr(d, (152, 815, 1520, 879), 11, NAVY)
    txt(d, (836, 847), "公共算子结构重构 + 任务级语义裁剪：让优化可复用，也让端到端收益可解释。", 21, WHITE, True, "ma")
    txt(d, (50, 912), "亮点页陈述当前代码已实现的结构方法；统一 L1–L6 复测完成后，再填入同协议端到端效果。", 14, MUTED)
    save(im, "P18_核心亮点_视觉重构_v05.png")


if __name__ == "__main__":
    page_p04()
    page_p09()
    page_p10()
    page_p11()
    page_p14()
    page_p16()
    page_p17()
    page_p18()
