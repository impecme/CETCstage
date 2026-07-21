#!/usr/bin/env python3
"""Render the task pages with slots for the forthcoming unified L1-L6 rerun.

No old task-scale or independent-final numbers are drawn.  The pages make the
new experiment contract visible and reserve exactly the locations to be filled
from new metrics.json files after the rerun.
"""

from __future__ import annotations

from PIL import ImageDraw

from generate_data_pages import BLUE, CPU, LIGHT, MUTED, NAVY, ORANGE, PALE, TEAL, TEXT, WHITE, arrow, base, card_header, line, rr, save, txt


def panel(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str, color: str = NAVY) -> None:
    card_header(d, box, title, color, 20)


def badge(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], text: str, color: str = NAVY, fill: str = LIGHT, size: int = 17) -> None:
    rr(d, box, 8, fill, "#C5D9EE", 1)
    txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), text, size, color, True, "mm")


def pending_chart(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str, task: str) -> None:
    panel(d, box, title)
    x1, y1, x2, y2 = box[0] + 68, box[1] + 100, box[2] - 44, box[3] - 72
    for fraction in (0, .25, .5, .75, 1):
        y = y2 - int(fraction * (y2 - y1))
        line(d, (x1, y, x2, y), "#DDE8F3", 1)
    line(d, (x1, y1, x1, y2), MUTED, 2)
    line(d, (x1, y2, x2, y2), MUTED, 2)
    for level in range(6):
        x = x1 + int(level * (x2 - x1) / 5)
        line(d, (x, y2 - 5, x, y2 + 5), MUTED, 2)
        txt(d, (x, y2 + 30), f"L{level + 1}", 16, ORANGE if level == 5 else TEXT, True, "ma")
    badge(d, (x1 + 45, y1 + 28, x2 - 45, y1 + 74), "统一 L1–L6 复测后填入", TEAL, "#ECF9F6", 18)
    txt(d, ((x1 + x2) // 2, y2 - 38), "固定算法参数；仅输入规模递增", 15, MUTED, True, "ma")


def pending_l6_result(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str) -> None:
    panel(d, box, "统一 L6 端到端结果（待复测）", TEAL)
    badge(d, (box[0] + 40, box[1] + 95, box[2] - 40, box[1] + 147), "CPU（ms）", CPU, "#F1F4F6", 17)
    badge(d, (box[0] + 40, box[1] + 177, box[2] - 40, box[1] + 229), "GPU（ms）", TEAL, "#ECF9F6", 17)
    badge(d, (box[0] + 40, box[1] + 259, box[2] - 40, box[1] + 324), "speedup", BLUE, LIGHT, 17)
    txt(d, ((box[0] + box[2]) // 2, box[3] - 48), f"{task} · 新 L6 端到端总时间", 16, MUTED, True, "ma")


def pending_correctness(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str) -> None:
    panel(d, box, f"{task} · 新 L6 正确性门禁（待复测）", TEAL)
    if task == "Task1":
        badge(d, (box[0] + 42, box[1] + 72, box[2] - 42, box[1] + 119), "Expected / CPU / GPU：待填", TEAL, "#ECF9F6", 17)
        badge(d, (box[0] + 42, box[1] + 130, box[2] - 42, box[1] + 177), "CFAR error / PASS：待填", NAVY, LIGHT, 16)
    else:
        badge(d, (box[0] + 42, box[1] + 72, box[2] - 42, box[1] + 119), "CPU / GPU 轨迹：待填", TEAL, "#ECF9F6", 17)
        badge(d, (box[0] + 42, box[1] + 130, box[2] - 42, box[1] + 177), "RMSE / feature error：待填", NAVY, LIGHT, 15)


def page_p09() -> None:
    im, d = base(
        "技术指标",
        "Task1 统一 L1–L6 性能验证（待复测）",
        "将原 final-input 作为新 L6；冻结分块与 CFAR 阈值配置，只改变输入规模。",
    )
    pending_chart(d, (44, 265, 810, 652), "Task1 L1–L6 加速比（待填入）", "Task1")
    pending_l6_result(d, (854, 265, 1227, 652), "Task1")
    protocol = (1250, 265, 1628, 652)
    panel(d, protocol, "统一复测协议", ORANGE)
    for index, text in enumerate(("L6：原 final-input 配置", "固定：窗口 / CFAR 阈值", "固定：公开算子处理链", "改变：任务输入规模")):
        badge(d, (1280, 352 + index * 62, 1598, 396 + index * 62), text, TEXT, "#FFF7ED", 15)
    pending_correctness(d, (44, 688, 790, 866), "Task1")
    rr(d, (824, 688, 1628, 866), 12, PALE, BLUE, 2)
    txt(d, (864, 730), "填表输出", 22, NAVY, True)
    txt(d, (864, 772), "CPU total · GPU total · 已计算 speedup · 检测位置 · CFAR error", 19, TEXT, True)
    txt(d, (864, 817), "写入：task1_radar/scales/L1…L6/metrics.json", 16, MUTED, True)
    txt(d, (50, 911), "本页不使用旧 final-input 或旧 L1–L6 数字；复测协议：ppt_work/unified_scale_retest_plan.md。", 14, MUTED)
    save(im, "P09_Task1_统一L1-L6待复测_整页_v03.png")


def page_p04() -> None:
    im, d = base(
        "技术路线",
        "“3 + 2 + 5” 技术路线",
        "三类通用公共机制 + 两条应用算法构建 + 五类可组合优化路径。",
    )
    left = (44, 265, 735, 805)
    app = (765, 265, 1628, 805)
    panel(d, left, "底层公共算子库优化")
    d.polygon(((112, 365), (152, 335), (535, 335), (575, 365), (535, 395), (152, 395)), fill=BLUE, outline="#F4C542")
    txt(d, (343, 365), "3 通用机制", 25, WHITE, True, "mm")
    mechanisms = (
        ("① Device-resident 数据链", "入口 H2D · 链内驻留 · 链尾 .get()"),
        ("② 存储与准备缓存复用", "容量 / plan / content 复用"),
        ("③ Shape-aware 分派与 Fusion", "shape 选路径 · 融合减少读写"),
    )
    for index, (name, detail) in enumerate(mechanisms):
        y = 420 + index * 95
        rr(d, (84, y, 695, y + 75), 10, LIGHT, "#BFD5EB", 1)
        txt(d, (110, y + 20), name, 16, BLUE, True)
        txt(d, (110, y + 51), detail, 14, TEXT, True)
        if index == 0:
            badge(d, (500, y + 19, 536, y + 53), "H", CPU, "#F0F3F6", 15)
            arrow(d, 541, y + 36, 568, y + 36, ORANGE, 2)
            badge(d, (573, y + 19, 628, y + 53), "Device", TEAL, "#ECF9F6", 12)
            txt(d, (648, y + 36), ".get()", 12, MUTED, True, "mm")
        elif index == 1:
            for x, label in ((500, "buf"), (552, "plan"), (610, "data")):
                badge(d, (x, y + 20, x + 43, y + 51), label, TEAL, "#ECF9F6", 10)
            arrow(d, 655, y + 49, 655, y + 20, ORANGE, 2)
            arrow(d, 655, y + 20, 644, y + 20, ORANGE, 2)
        else:
            badge(d, (495, y + 20, 535, y + 51), "shape", BLUE, WHITE, 10)
            for x, label in ((555, "T"), (588, "F"), (621, "S")):
                badge(d, (x, y + 20, x + 25, y + 51), label, TEAL, "#ECF9F6", 10)
            arrow(d, 539, y + 36, 551, y + 36, BLUE, 2)
            badge(d, (653, y + 20, 682, y + 51), "↓", ORANGE, "#FFF7ED", 13)
    rr(d, (84, 718, 695, 773), 9, "#ECF9F6", "#9CDDD8", 1)
    txt(d, (105, 737), "代表展开：Wiener Tile/Halo · IIR Scan · Periodogram R2C", 14, TEAL, True)
    txt(d, (390, 758), "典型公开算子 Wiener：183.62×", 15, NAVY, True, "ma")

    panel(d, app, "应用级算法构建")
    d.polygon(((800, 365), (835, 337), (1015, 337), (1050, 365), (1015, 393), (835, 393)), fill=BLUE, outline="#F4C542")
    txt(d, (925, 365), "2 构建", 24, WHITE, True, "mm")
    d.polygon(((1260, 365), (1295, 337), (1485, 337), (1520, 365), (1485, 393), (1295, 393)), fill=BLUE, outline="#F4C542")
    txt(d, (1390, 365), "5 路径", 24, WHITE, True, "mm")
    tasks = (
        ("Task1 雷达检测", "公开算子驻留组合 → 检测", "34.20×"),
        ("Task2 特征融合与跟踪", "算子库 + private helper → score/轨迹", "1071.70×"),
    )
    for index, (name, flow, score) in enumerate(tasks):
        y = 420 + index * 165
        rr(d, (805, y, 1180, y + 140), 10, "#ECF9F6", "#9CDDD8", 1)
        txt(d, (835, y + 22), name, 19, TEAL, True)
        if index == 0:
            for row in range(3):
                for col in range(3):
                    color = "#BFD5EB" if (row + col) % 2 else "#EAF3FB"
                    rr(d, (835 + col * 11, y + 52 + row * 11, 843 + col * 11, y + 60 + row * 11), 1, color, color, 1)
            arrow(d, 872, y + 69, 892, y + 69, BLUE, 2)
            rr(d, (896, y + 52, 930, y + 86), 3, "#1B69C9", "#1B69C9", 1)
            d.ellipse((906, y + 62, 914, y + 70), fill="#F4C542")
            arrow(d, 935, y + 69, 954, y + 69, TEAL, 2)
            d.ellipse((962, y + 59, 981, y + 78), outline=ORANGE, width=2)
            line(d, (971, y + 54, 971, y + 83), ORANGE, 1)
            line(d, (956, y + 69, 986, y + 69), ORANGE, 1)
        else:
            for frame in range(3):
                rr(d, (835 + frame * 15, y + 53, 847 + frame * 15, y + 82), 2, "#BFD5EB", "#7BAEE4", 1)
            arrow(d, 884, y + 68, 902, y + 68, BLUE, 2)
            for bar in range(4):
                rr(d, (906, y + 52 + bar * 9, 947, y + 58 + bar * 9), 2, "#ECF9F6", "#9CDDD8", 1)
                rr(d, (906, y + 52 + bar * 9, 929 + bar * 3, y + 58 + bar * 9), 2, TEAL, TEAL, 1)
            arrow(d, 951, y + 68, 968, y + 68, TEAL, 2)
            line(d, (973, y + 78, 980, y + 70, 988, y + 73, 996, y + 58), TEAL, 2)
            d.ellipse((970, y + 75, 976, y + 81), fill=TEAL)
            d.ellipse((985, y + 70, 991, y + 76), fill=TEAL)
            d.ellipse((993, y + 55, 999, y + 61), fill=TEAL)
        txt(d, (1004, y + 67), flow, 13, TEXT, True, "mm")
        score_x, score_size = (1093, 22) if index == 0 else (1072, 20)
        txt(d, (score_x, y + 100), score, score_size, ORANGE, True, "mm")
        txt(d, (1000, y + 123), "已发布快照 · 统一复测后替换", 11, MUTED, True, "mm")
    paths = ("设备驻留 / 批处理", "准备与内容缓存", "融合 / 直接写回", "并行 Scan / 归约", "score-only / 紧凑输出")
    for index, text in enumerate(paths):
        badge(d, (1230, 420 + index * 60, 1585, 460 + index * 60), f"{index + 1}. {text}", ORANGE, "#FFF7ED", 14)
    rr(d, (44, 840, 1628, 898), 10, NAVY)
    txt(d, (836, 869), "3 类通用机制 + 2 条应用构建 + 5 类组合路径", 24, WHITE, True, "ma")
    txt(d, (50, 921), "Task 速度为 2026-07-20 已发布快照；正式答辩用统一 L1–L6 新 L6 数字替换。", 14, MUTED)
    save(im, "P04_技术路线_通用机制_整页_v03.png")


def page_p10() -> None:
    im, d = base(
        "核心技术",
        "Task2 算法构建：批量生成四路 score",
        "保持 Device-resident 与 score-only 语义；统一 L1–L6 只改变输入规模，不改变算法路径。",
    )
    left = (44, 275, 726, 690)
    right = (825, 275, 1628, 690)
    panel(d, left, "CPU reference · 逐帧完整中间量", CPU)
    panel(d, right, "ZQ500 GPU · batched score-only", TEAL)
    for i, name in enumerate(("输入", "相关", "谱图", "CWT", "融合/track")):
        x = 84 + i * 126
        badge(d, (x, 410, x + 105, 475), name, TEXT, "#F0F3F6", 14)
        if i < 4:
            arrow(d, x + 108, 442, x + 121, 442, CPU, 3)
    for i, name in enumerate(("批输入", "滤波/解调", "相关", "谱图", "CWT", "融合/track")):
        x = 861 + i * 114
        badge(d, (x, 410, x + 95, 475), name, TEAL if i in (0, 5) else TEXT, "#ECF9F6", 13)
        if i < 5:
            arrow(d, x + 98, 442, x + 109, 442, TEAL, 3)
    txt(d, (383, 566), "完整中间张量物化与回传", 23, CPU, True, "ma")
    txt(d, (1226, 566), "仅保留任务所需 score 与状态轨迹", 23, TEAL, True, "ma")
    rr(d, (44, 733, 1628, 866), 12, PALE, BLUE, 2)
    txt(d, (84, 778), "统一测评约束", 22, NAVY, True)
    badge(d, (300, 748, 650, 813), "冻结：B=8 / score-only", TEAL, "#ECF9F6", 18)
    badge(d, (688, 748, 1038, 813), "改变：帧数、输入长度", ORANGE, "#FFF7ED", 18)
    badge(d, (1076, 748, 1588, 813), "P11：填入新 L1–L6 数据", BLUE, LIGHT, 18)
    txt(d, (50, 911), "流程依据：demo/task2_features/task2_features_demo.cpp；本页不展示旧 final-input 性能数。", 14, MUTED)
    save(im, "P10_Task2_Score_Only_统一协议_整页_v03.png")


def page_p11() -> None:
    im, d = base(
        "技术指标",
        "Task2 统一 L1–L6 性能验证（待复测）",
        "将原 final-input 作为新 L6；冻结 batch、score-only 与误差门限，只改变输入规模。",
    )
    pending_chart(d, (44, 265, 810, 652), "Task2 L1–L6 加速比（待填入）", "Task2")
    pending_l6_result(d, (854, 265, 1227, 652), "Task2")
    protocol = (1250, 265, 1628, 652)
    panel(d, protocol, "统一复测协议", ORANGE)
    for index, text in enumerate(("L6：原 final-input 配置", "固定：B=8 / score-only", "固定：feature 与 track 门限", "改变：帧数与输入长度")):
        badge(d, (1280, 352 + index * 62, 1598, 396 + index * 62), text, TEXT, "#FFF7ED", 15)
    pending_correctness(d, (44, 688, 790, 866), "Task2")
    rr(d, (824, 688, 1628, 866), 12, PALE, BLUE, 2)
    txt(d, (864, 730), "填表输出", 22, NAVY, True)
    txt(d, (864, 772), "CPU total · GPU total · 已计算 speedup · track RMSE · feature-score error", 19, TEXT, True)
    txt(d, (864, 817), "写入：task2_features/scales/L1…L6/metrics.json", 16, MUTED, True)
    txt(d, (50, 911), "本页不使用旧 final-input 或旧 L1–L6 数字；复测协议：ppt_work/unified_scale_retest_plan.md。", 14, MUTED)
    save(im, "P11_Task2_统一L1-L6待复测_整页_v02.png")


def page_p14() -> None:
    im, d = base(
        "技术指标",
        "正确性与任务运行验证：新统一 L6 复测结果预留",
        "81 个公开算子的代码与契约覆盖保留；Task1/Task2 的最终正确性以新 L6 运行报告为准。",
    )
    coverage = (44, 265, 560, 850)
    panel(d, coverage, "现有代码与契约覆盖", NAVY)
    for index, (num, label) in enumerate((("81/81", "公开算子"), ("2/2", "端到端任务"), ("14/14", "正式计算步骤"))):
        y = 350 + index * 132
        badge(d, (96, y, 508, y + 93), f"{num}  {label}", TEAL if index == 0 else BLUE, LIGHT, 26)
    txt(d, (302, 785), "新任务性能与误差待统一 L6 复测", 16, MUTED, True, "ma")
    pending_correctness(d, (602, 265, 1628, 522), "Task1")
    pending_correctness(d, (602, 552, 1628, 810), "Task2")
    rr(d, (602, 830, 1628, 876), 9, "#FFF7ED", ORANGE, 1)
    txt(d, (1115, 853), "填入规则：新 metrics.json 中的实际值 < 门限，才显示 PASS。", 17, ORANGE, True, "ma")
    txt(d, (50, 911), "不沿用旧 final-input 误差；新数据源是 task1/task2 的正式 scales/L6/metrics.json。", 14, MUTED)
    save(im, "P14_统一L6正确性待复测_整页_v03.png")


def page_p16() -> None:
    im, d = base(
        "技术指标",
        "统一 L1–L6 规模效应与主要耗时环节（待复测）",
        "新曲线只改变输入规模；新 L6 的 Top3 GPU 耗时步骤将直接决定后续优化优先级。",
    )
    pending_chart(d, (44, 265, 810, 548), "Task1 统一 L1–L6 加速比（待填入）", "Task1")
    pending_chart(d, (854, 265, 1628, 548), "Task2 统一 L1–L6 加速比（待填入）", "Task2")
    for box, title, task in (((44, 590, 810, 850), "Task1 新 L6 GPU 时间 Top3（待填入）", "Task1"), ((854, 590, 1628, 850), "Task2 新 L6 GPU 时间 Top3（待填入）", "Task2")):
        panel(d, box, title)
        for index in range(3):
            y = box[1] + 85 + index * 50
            badge(d, (box[0] + 52, y, box[2] - 52, y + 36), f"Top{index + 1}：名称 / GPU ms / 占比（待填）", TEXT, "#F0F4F8", 16)
        txt(d, ((box[0] + box[2]) // 2, box[3] - 22), f"{task}：热点 = GPU 时间占比最高步骤", 15, MUTED, True, "ma")
    txt(d, (50, 911), "不混入旧 L1–L6 或旧 final-input 数据；统一协议：ppt_work/unified_scale_retest_plan.md。", 14, MUTED)
    save(im, "P16_统一L1-L6规模与热点待复测_整页_v03.png")


def page_p17() -> None:
    im, d = base(
        "技术指标",
        "性能优势、边界与改进方向",
        "先用统一 L1–L6 协议验证端到端收益，再对分块、阈值和高占比步骤做独立 A/B。",
    )
    columns = ((44, 265, 578, 830), (602, 265, 1084, 830), (1108, 265, 1628, 830))
    panel(d, columns[0], "已实现的结构优势", TEAL)
    for index, text in enumerate(("Tile / Halo：邻域复用", "Affine Scan：递归转并行", "R2C + Fusion：减少写回", "Device-resident：减少回传")):
        badge(d, (84, 350 + index * 92, 538, 402 + index * 92), text, TEAL, "#ECF9F6", 18)
    panel(d, columns[1], "统一复测先解决的问题", "#7B8794")
    for index, text in enumerate(("L6 对齐 final-input", "L1–L5 仅变输入规模", "speedup 自动计算", "误差与性能同一 run")):
        badge(d, (642, 350 + index * 92, 1044, 402 + index * 92), text, TEXT, "#F0F3F6", 17)
    panel(d, columns[2], "后续参数优化方向", ORANGE)
    for index, text in enumerate(("Block / Halo：独立 A/B", "CFAR 参数：独立 A/B", "batch / shape：独立 A/B", "按新 L6 Top3 优先")):
        badge(d, (1148, 350 + index * 92, 1588, 402 + index * 92), text, ORANGE, "#FFF7ED", 17)
    rr(d, (44, 860, 1628, 907), 10, NAVY)
    txt(d, (836, 884), "结论：不把规模变化与参数调优混在同一曲线；先可比测量，再逐项优化。", 20, WHITE, True, "ma")
    save(im, "P17_统一测评与改进方向_整页_v03.png")


def page_p18() -> None:
    im, d = base(
        "创新点",
        "核心亮点：公共算法结构重构与任务级语义裁剪",
        "亮点在于把不适合 GPU 的访存、递归和中间量结构重写为可复用的 ZQ500 实现。",
    )
    cards = ((44, 265, 555, 760), (581, 265, 1092, 760), (1118, 265, 1628, 760))
    specs = (("① 邻域访存重构", "问题：相邻窗口重复读", "方法：Tile / Halo 复用", "价值：服务 Wiener 类算子"), ("② 递归与频谱重构", "问题：IIR 递归、双边频谱", "方法：Affine Scan / R2C", "价值：重写为并行结构"), ("③ 任务级语义裁剪", "问题：完整中间量物化", "方法：驻留 + score-only", "价值：只保留 score / 轨迹"))
    for box, spec in zip(cards, specs):
        panel(d, box, spec[0])
        for index, text in enumerate(spec[1:]):
            badge(d, (box[0] + 42, box[1] + 108 + index * 105, box[2] - 42, box[1] + 163 + index * 105), text, TEAL if index == 1 else TEXT, "#ECF9F6" if index == 1 else LIGHT, 17)
    rr(d, (44, 798, 1628, 880), 12, PALE, BLUE, 2)
    txt(d, (836, 830), "统一 L1–L6 复测完成后，再将新端到端收益填入各亮点的效果证据。", 23, NAVY, True, "ma")
    txt(d, (50, 911), "本页只保留已实现方法，不沿用旧独立 final-input 数字。", 14, MUTED)
    save(im, "P18_核心亮点_统一测评前_整页_v04.png")


if __name__ == "__main__":
    page_p04()
    page_p09()
    page_p10()
    page_p11()
    page_p14()
    page_p16()
    page_p17()
    page_p18()
