#!/usr/bin/env python3
"""Render the six refreshed mechanism pages into ppt_work/new.

The page language follows the existing technical-deck visual system.  This
script deliberately does not touch the approved performance-page assets.
Performance values are embedded from the current PPT evidence tables and are
labelled by metric scope so CPU-to-GPU speedups are not confused with GPU
before/after ratios.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from generate_data_pages import (  # noqa: E402
    BLUE,
    CPU,
    LIGHT,
    MUTED,
    NAVY,
    ORANGE,
    PALE,
    RED,
    TEAL,
    TEXT,
    WHITE,
    arrow,
    base,
    font,
    line,
    rr,
    txt,
)


ROOT = SCRIPT_DIR.parents[1]
OUT = ROOT / "ppt_work" / "new"
W, H = 1672, 941


def panel(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
          color: str = NAVY, size: int = 21) -> None:
    x1, y1, x2, y2 = box
    rr(d, box, 12, WHITE, BLUE, 2)
    rr(d, (x1, y1, x2, y1 + 52), 12, color)
    d.rectangle((x1, y1 + 25, x2, y1 + 52), fill=color)
    txt(d, ((x1 + x2) // 2, y1 + 26), title, size, WHITE, True, "mm")


def chip(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str,
         fill: str = LIGHT, color: str = TEXT, size: int = 14,
         edge: str | None = None) -> None:
    rr(d, box, 8, fill, edge or fill, 1)
    txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), label,
        size, color, True, "mm")


def label(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], text: str,
          color: str, fill: str, size: int = 15,
          edge: str | None = None) -> None:
    rr(d, box, 9, fill, edge or fill, 2)
    d.multiline_text(
        ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2),
        text,
        font=font(size, True),
        fill=color,
        anchor="mm",
        align="center",
        spacing=4,
    )


def metric_card(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                title: str, value: str, color: str = TEAL,
                detail: str = "", value_size: int = 31,
                title_size: int = 17) -> None:
    x1, y1, x2, y2 = box
    rr(d, box, 12, WHITE, color, 2)
    txt(d, ((x1 + x2) // 2, y1 + 29), title, title_size, NAVY, True, "mm")
    txt(d, ((x1 + x2) // 2, (y1 + y2) // 2 + 4), value, value_size, color, True, "mm")
    if detail:
        txt(d, ((x1 + x2) // 2, y2 - 20), detail, 12, MUTED, True, "mm")


def speed_badge(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                label: str, value: str, color: str = ORANGE,
                detail: str = "", value_size: int = 27) -> None:
    x1, y1, x2, y2 = box
    rr(d, box, 12, "#FFF7ED", color, 2)
    short = y2 - y1 < 65
    text_y = y1 + (18 if short else 25)
    txt(d, (x1 + 18, text_y), label, 13 if short else 15, NAVY, True, "lm")
    txt(d, (x2 - 18, text_y), value, value_size if not short else min(value_size, 22), color, True, "rm")
    if detail and not short:
        txt(d, (x1 + 18, y2 - 18), detail, 12, MUTED, True, "lm")


def footer(d: ImageDraw.ImageDraw, text: str) -> None:
    rr(d, (24, 829, 1648, 913), 14, NAVY)
    txt(d, (836, 871), text, 24, WHITE, True, "mm")


def numbered_card(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                 number: str, title: str, detail: str,
                 accent: str = TEAL) -> None:
    x1, y1, x2, y2 = box
    rr(d, box, 10, "#FBFDFF", "#BBD2E8", 2)
    d.ellipse((x1 + 17, y1 + 18, x1 + 58, y1 + 59), fill=accent)
    txt(d, (x1 + 37, y1 + 38), number, 18, WHITE, True, "mm")
    txt(d, (x1 + 75, y1 + 28), title, 18, NAVY, True, "lm")
    txt(d, (x1 + 75, y1 + 57), detail, 13, TEXT, True, "lm")


def tile_grid(d: ImageDraw.ImageDraw, x: int, y: int, cols: int,
              rows: int, cell: int, active: str = TEAL,
              halo: bool = False) -> None:
    for row in range(rows):
        for col in range(cols):
            fill = active if 0 < row < rows - 1 and 0 < col < cols - 1 else "#DCE8F3"
            if halo and (row in (0, rows - 1) or col in (0, cols - 1)):
                fill = ORANGE
            rr(d, (x + col * (cell + 3), y + row * (cell + 3),
                   x + col * (cell + 3) + cell,
                   y + row * (cell + 3) + cell), 2, fill, fill, 1)


def route_node(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
               number: str, title: str, lines: tuple[str, ...],
               color: str = TEAL) -> None:
    x1, y1, x2, y2 = box
    rr(d, box, 10, WHITE, color, 2)
    rr(d, (x1, y1, x2, y1 + 39), 10, color)
    d.rectangle((x1, y1 + 20, x2, y1 + 39), fill=color)
    txt(d, (x1 + 12, y1 + 20), f"{number}  {title}", 14, WHITE, True, "lm")
    for i, value in enumerate(lines):
        txt(d, ((x1 + x2) // 2, y1 + 76 + i * 23), value, 13, TEXT, True, "ma")


def page_p05() -> None:
    im, d = base(
        "技术路线",
        "3 + 2 + 5 技术路线",
        "三类公共算子机制 + 两条应用任务链 + 五类任务级路径。",
    )
    left = (44, 265, 730, 808)
    mid = (748, 265, 1244, 808)
    right = (1262, 265, 1628, 808)
    panel(d, left, "3 类公共算子机制", NAVY, 21)
    numbered_card(d, (68, 339, 706, 455), "1", "离线自动调优与形状分派",
                  "exact key → 候选筛选 → cache / fallback", BLUE)
    chip(d, (430, 400, 676, 432), "threads · tile · route", "#E9F9F7", TEAL, 13, "#9CDDD8")
    numbered_card(d, (68, 472, 706, 588), "2", "分层 Tile / Scan / FFT",
                  "layout、shared tile、分层归约与输出写回", TEAL)
    chip(d, (430, 533, 676, 565), "Tile · Halo · Scan", "#E9F9F7", TEAL, 13, "#9CDDD8")
    numbered_card(d, (68, 605, 706, 721), "3", "执行资源与数据流复用",
                  "buffer、workspace、plan、event 与 direct-copy", ORANGE)
    chip(d, (430, 666, 676, 698), "E2E 主指标", "#FFF7ED", ORANGE, 13, "#F4C17A")
    speed_badge(d, (68, 744, 706, 793), "pulse_compression CPU/GPU E2E", "59.17×",
                ORANGE, "", 19)

    panel(d, mid, "2 条应用任务链", NAVY, 21)
    # Task 1 mini flow.
    rr(d, (774, 339, 1218, 548), 12, "#FBFDFF", "#BBD2E8", 2)
    chip(d, (794, 358, 1002, 396), "任务一 · 雷达检测", BLUE, WHITE, 17)
    tile_grid(d, 800, 430, 4, 4, 17, BLUE)
    arrow(d, 884, 466, 952, 466, BLUE, 3)
    tile_grid(d, 968, 425, 5, 5, 15, TEAL)
    arrow(d, 1058, 466, 1116, 466, TEAL, 3)
    for cx, cy in ((1150, 435), (1170, 468), (1147, 500)):
        d.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=ORANGE)
    txt(d, (995, 528), "脉冲矩阵 → 距离-多普勒 → 检测", 14, TEXT, True, "mm")
    speed_badge(d, (1050, 361, 1198, 404), "L6", "32.53×", ORANGE, "CPU/GPU E2E", 20)

    # Task 2 mini flow.
    rr(d, (774, 570, 1218, 793), 12, "#FBFDFF", "#BBD2E8", 2)
    chip(d, (794, 589, 1018, 627), "任务二 · 特征融合与跟踪", BLUE, WHITE, 16)
    tile_grid(d, 802, 668, 4, 4, 15, BLUE)
    arrow(d, 885, 700, 950, 700, BLUE, 3)
    for i, color in enumerate((BLUE, TEAL, ORANGE, "#7B61A8")):
        rr(d, (966, 655 + i * 22, 1068, 670 + i * 22), 3, color)
    arrow(d, 1080, 700, 1125, 700, TEAL, 3)
    line(d, (1135, 725, 1184, 671), TEAL, 3)
    line(d, (1135, 725, 1184, 748), TEAL, 3)
    d.ellipse((1180, 666, 1194, 680), fill=ORANGE)
    d.ellipse((1180, 743, 1194, 757), fill=ORANGE)
    txt(d, (984, 773), "帧序列 → 多维评分 → 轨迹", 14, TEXT, True, "mm")
    speed_badge(d, (1050, 611, 1198, 654), "L6", "1053.33×", ORANGE, "CPU/GPU E2E", 18)

    panel(d, right, "5 类任务级路径", NAVY, 20)
    routes = (
        "设备驻留 / 批处理",
        "准备与内容缓存",
        "融合 / 直接写回",
        "并行扫描 / 归约",
        "仅评分 / 紧凑输出",
    )
    for i, value in enumerate(routes, 1):
        y = 338 + (i - 1) * 87
        rr(d, (1284, y, 1608, y + 65), 10, "#FBFDFF", ORANGE, 2)
        d.ellipse((1300, y + 15, 1341, y + 56), fill=ORANGE)
        txt(d, (1320, y + 35), str(i), 18, WHITE, True, "mm")
        parts = value.split(" / ", 1)
        txt(d, (1360, y + 24), parts[0], 16, NAVY, True, "lm")
        if len(parts) == 2:
            txt(d, (1360, y + 47), "/" + parts[1], 14, TEXT, True, "lm")
    footer(d, "公共算子机制提供基础，任务链负责组合、驻留与紧凑输出。")
    im.save(OUT / "P05_技术路线_三加二加五_v12_机制更新.png")


def page_p06() -> None:
    im, d = base(
        "核心技术",
        "算子机制①：离线自动调优与形状感知分派",
        "有限候选、精确匹配、离线筛选；运行时只查表，不在线试跑。",
    )
    panel(d, (44, 265, 470, 808), "输入与候选键", NAVY, 20)
    numbered_card(d, (70, 340, 444, 455), "1", "工作负载键",
                  "operator / shape / dtype / layout", BLUE)
    chip(d, (95, 416, 414, 443), "device fingerprint + semantic params", LIGHT, NAVY, 12, "#BBD2E8")
    numbered_card(d, (70, 474, 444, 589), "2", "有限候选集",
                  "threads / tile / route / plan", TEAL)
    chip(d, (95, 550, 414, 577), "M50 · M75 · M90 = actual workset", "#E9F9F7", TEAL, 12, "#9CDDD8")
    numbered_card(d, (70, 608, 444, 723), "3", "资源与正确性门",
                  "workspace / error / input-refresh", ORANGE)
    chip(d, (95, 684, 414, 711), "不满足 → static / legacy", "#FFF7ED", ORANGE, 12, "#F4C17A")

    panel(d, (492, 265, 1192, 808), "离线筛选 → 运行时选择", TEAL, 20)
    # Offline path.
    chip(d, (530, 340, 760, 380), "offline tuning", NAVY, WHITE, 17)
    labels = ("screening", "Top-3 / formal", "winner vs static")
    for i, label_text in enumerate(labels):
        x = 530 + i * 190
        rr(d, (x, 423, x + 158, 479), 8, "#F7FBFE", "#9CCCE8", 2)
        txt(d, (x + 79, 451), label_text, 13, NAVY, True, "mm")
        if i < len(labels) - 1:
            arrow(d, x + 161, 451, x + 184, 451, BLUE, 2)
    txt(d, (862, 360), "only E2E winner", 15, ORANGE, True, "lm")
    rr(d, (760, 492, 1138, 560), 10, "#FFF7ED", ORANGE, 2)
    txt(d, (949, 515), "correctness PASS", 16, NAVY, True, "mm")
    txt(d, (949, 540), "optimized E2E < static E2E", 13, TEXT, True, "mm")
    arrow(d, 830, 480, 830, 492, TEAL, 3)
    chip(d, (694, 580, 965, 622), "tuning cache", TEAL, WHITE, 16)
    arrow(d, 965, 601, 1030, 601, TEAL, 3)
    chip(d, (1032, 580, 1148, 622), "runtime", BLUE, WHITE, 13)
    rr(d, (552, 650, 1138, 754), 10, "#F7FBFE", "#BBD2E8", 2)
    txt(d, (578, 679), "cache hit + resource valid", 16, TEAL, True, "lm")
    arrow(d, 790, 695, 855, 695, TEAL, 3)
    chip(d, (873, 671, 1045, 719), "candidate route", TEAL, WHITE, 15)
    arrow(d, 1055, 695, 1105, 695, TEAL, 3)
    chip(d, (1109, 671, 1130, 719), "✓", TEAL, WHITE, 21)
    txt(d, (578, 734), "cache miss / device mismatch / OOM → static or legacy fallback", 13, RED, True, "lm")

    panel(d, (1214, 265, 1628, 808), "代表算子：CA-CFAR", NAVY, 20)
    metric_card(d, (1240, 340, 1602, 452), "CPU/GPU E2E 加速比", "7.81×", TEAL,
                "summary perf case")
    metric_card(d, (1240, 474, 1602, 586), "tiled scan kernel 前后", "1.29–1.34×", ORANGE,
                "有效形状范围")
    rr(d, (1240, 610, 1602, 735), 10, "#ECF9F6", "#9CDDD8", 2)
    txt(d, (1421, 640), "保留条件", 18, NAVY, True, "mm")
    txt(d, (1421, 677), "correctness PASS", 15, TEAL, True, "mm")
    txt(d, (1421, 704), "E2E 主指标不下降", 15, TEAL, True, "mm")
    footer(d, "自动调优决定算子路径；不改变公共 API，失败时回退安全路径。")
    im.save(OUT / "P06_算子机制_离线自动调优_v01.png")


def page_p07() -> None:
    im, d = base(
        "核心技术",
        "算子机制②：分层 Tile、布局与归约重构",
        "把重复全局访存和串行归约改写为 shape-aware 的块内协作路径。",
    )
    panel(d, (44, 265, 394, 808), "旧路径：重复访问", RED, 20)
    txt(d, (219, 344), "输入矩阵", 19, NAVY, True, "ma")
    tile_grid(d, 92, 400, 8, 8, 23, "#F4D4D0")
    for ox, oy in ((80, 386), (122, 434), (164, 482)):
        rr(d, (ox, oy, ox + 112, oy + 112), 4, "#F9E4E1", RED, 2)
    txt(d, (219, 625), "相邻输出重复读取 halo", 17, RED, True, "ma")
    line(d, (219, 665, 219, 730), RED, 3)
    txt(d, (219, 754), "串行 / 重复写回", 17, RED, True, "ma")

    panel(d, (414, 265, 1194, 808), "新路径：Tile + Halo + 分层归约", TEAL, 20)
    txt(d, (465, 343), "输入 tile + halo", 18, NAVY, True)
    tile_grid(d, 470, 390, 10, 10, 25, TEAL, True)
    txt(d, (602, 675), "共享内存协作加载", 16, TEAL, True, "ma")
    arrow(d, 742, 510, 810, 510, TEAL, 4)
    txt(d, (835, 343), "16×16 output tile", 18, NAVY, True, "ma")
    for ox, oy in ((820, 392), (969, 392), (820, 533), (969, 533)):
        tile_grid(d, ox, oy, 4, 4, 25, TEAL)
    txt(d, (955, 675), "一次加载 → 多点输出", 16, TEAL, True, "ma")
    # Route chips.
    chip(d, (472, 718, 640, 756), "direct", LIGHT, NAVY, 15, "#BBD2E8")
    chip(d, (657, 718, 828, 756), "shared-halo", "#E9F9F7", TEAL, 15, "#9CDDD8")
    chip(d, (845, 718, 1014, 756), "FFT route", "#FFF7ED", ORANGE, 15, "#F4C17A")
    txt(d, (1041, 737), "按 shape / layout 选择", 14, TEXT, True, "lm")

    panel(d, (1214, 265, 1628, 808), "代表算子：correlate2d", NAVY, 17)
    metric_card(d, (1240, 340, 1602, 448), "CPU/GPU E2E 加速比", "2.74×", TEAL,
                "summary perf case")
    metric_card(d, (1240, 466, 1602, 574), "GPU E2E 前后提速", "1.18–1.34×", ORANGE,
                "L1–L6 fresh A/B")
    metric_card(d, (1240, 592, 1602, 700), "GPU kernel 前后提速", "1.52×", BLUE,
                "1.518–1.527×")
    chip(d, (1240, 727, 1602, 765), "6/6 correctness PASS", "#ECF9F6", TEAL, 15, "#9CDDD8")
    footer(d, "Tile、layout 与归约共同决定路径；不满足条件的 shape 保留 legacy。")
    im.save(OUT / "P07_算子机制_Tile布局归约_v01.png")


def page_p08() -> None:
    im, d = base(
        "核心技术",
        "算子机制③：非内核执行开销与资源复用",
        "优化 E2E 的关键是减少准备、拷贝、分配、plan、同步与中间物化。",
    )
    panel(d, (44, 265, 530, 808), "可复用执行资源", NAVY, 20)
    resources = (
        ("Device buffer", "容量复用", BLUE),
        ("Workspace", "算子临时区复用", TEAL),
        ("FFT plan", "shape / batch / stride cache", BLUE),
        ("Timing event", "thread-local 复用", ORANGE),
    )
    for i, (name, detail, color) in enumerate(resources):
        y = 342 + i * 96
        rr(d, (74, y, 500, y + 72), 10, "#FBFDFF", "#BBD2E8", 2)
        d.ellipse((94, y + 17, 145, y + 68), fill=color)
        txt(d, (120, y + 42), "↻", 27, WHITE, True, "mm")
        txt(d, (170, y + 27), name, 17, NAVY, True, "lm")
        txt(d, (170, y + 52), detail, 13, TEXT, True, "lm")
    chip(d, (74, 744, 500, 780), "缓存上限 15 GiB；不做预分配", "#FFF7ED", ORANGE, 12, "#F4C17A")

    panel(d, (550, 265, 1192, 808), "E2E 时间轴：准备开销也必须被测量", TEAL, 20)
    # Before lane.
    txt(d, (584, 355), "常规路径", 17, CPU, True)
    before = ((584, "host pack"), (704, "H2D"), (790, "malloc"),
              (880, "plan"), (954, "kernel"), (1068, "D2H"))
    for i, (x, label) in enumerate(before):
        width = 90 if label != "kernel" else 92
        rr(d, (x, 382, x + width, 427), 7, "#F1F4F7", CPU, 1)
        txt(d, (x + width // 2, 405), label, 12, TEXT, True, "mm")
        if i < len(before) - 1:
            arrow(d, x + width + 4, 405, before[i + 1][0] - 5, 405, CPU, 2)
    txt(d, (584, 485), "复用路径", 17, TEAL, True)
    after = ((584, "input"), (704, "H2D"), (790, "buffer pool"),
             (928, "plan/workspace"), (1082, "kernel"))
    for i, (x, label) in enumerate(after):
        width = 92 if label not in ("buffer pool", "plan/workspace") else 124
        rr(d, (x, 512, x + width, 557), 7, "#ECF9F6", TEAL, 1)
        txt(d, (x + width // 2, 535), label, 12, TEAL, True, "mm")
        if i < len(after) - 1:
            arrow(d, x + width + 4, 535, after[i + 1][0] - 5, 535, TEAL, 2)
    txt(d, (584, 613), "每轮仍 fresh host input + 完整 H2D/D2H；只复用容量与准备资源。", 14, TEXT, True)
    rr(d, (584, 660, 1155, 755), 10, "#FFF7ED", ORANGE, 2)
    txt(d, (869, 688), "E2E 主指标优先", 18, NAVY, True, "mm")
    txt(d, (869, 720), "kernel 单独变快 ≠ 算子最终有效", 15, ORANGE, True, "mm")

    panel(d, (1214, 265, 1628, 808), "实测代表：direct-copy", NAVY, 17)
    metric_card(d, (1240, 340, 1602, 438), "CPU/GPU E2E 加速比", "10.816× → 11.574×", TEAL,
                "spectrogram fixed case", 20, 15)
    metric_card(d, (1240, 456, 1602, 554), "GPU E2E 前后提速", "1.07×", ORANGE,
                "+7.01%")
    metric_card(d, (1240, 572, 1602, 670), "GPU kernel 前后提速", "0.93×", BLUE,
                "kernel 未变快")
    chip(d, (1240, 700, 1602, 755), "收益：host pack/unpack 消除", "#ECF9F6", TEAL, 14, "#9CDDD8")
    footer(d, "非内核优化只有在 CPU→GPU E2E 加速比变大时才保留。")
    im.save(OUT / "P08_算子机制_非内核开销复用_v01.png")


def page_p12() -> None:
    im, d = base(
        "核心技术",
        "任务一：五类路径组合雷达检测链",
        "公共算子在设备侧连续执行；任务边界只回传检测与验证所需结果。",
    )
    speed_badge(d, (1276, 102, 1608, 155), "Task1 L6 E2E", "32.53×", ORANGE,
                "", 22)
    panel(d, (44, 265, 1210, 808), "GPU 设备驻留：公开算子组合链", TEAL, 20)
    label_boxes = (
        ("1", "脉冲压缩", ("template FFT", "matched filter")),
        ("2", "脉冲多普勒", ("batch FFT", "transpose / shift")),
        ("3", "Power Map", ("|RD|²", "normalize")),
        ("4", "CA-CFAR", ("row prefix", "threshold")),
        ("5", "峰值 / 紧凑", ("two-stage", "detection list")),
    )
    xs = (205, 395, 585, 775, 965)
    label(d, (68, 454, 166, 516), "主机输入\n一次上传", NAVY, PALE, 15)
    arrow(d, 168, 485, 202, 485, TEAL, 3)
    for i, ((number, title, lines), x) in enumerate(zip(label_boxes, xs)):
        route_node(d, (x, 360, x + 150, 610), number, title, lines, TEAL)
        if i < len(xs) - 1:
            arrow(d, x + 153, 485, xs[i + 1] - 8, 485, TEAL, 3)
    arrow(d, 1118, 485, 1178, 485, TEAL, 3)
    label(d, (1125, 534, 1190, 598), "紧凑\n回传", ORANGE, "#FFF7ED", 14)
    # Side branch.
    rr(d, (116, 668, 1098, 763), 10, "#FBFDFF", "#9CDDD8", 2)
    chip(d, (137, 687, 305, 727), "旁路 ambgfun", BLUE, WHITE, 14)
    arrow(d, 322, 707, 376, 707, BLUE, 3)
    chip(d, (390, 687, 600, 727), "并行矩阵 / FFT batch", "#E9F9F7", TEAL, 15, "#9CDDD8")
    arrow(d, 615, 707, 671, 707, TEAL, 3)
    chip(d, (686, 687, 915, 727), "质量分析，不进入检测回传", LIGHT, NAVY, 14, "#BBD2E8")
    speed_badge(d, (925, 680, 1078, 742), "代表算子", "59.17×", ORANGE,
                "", 20)

    panel(d, (1235, 265, 1628, 808), "五类路径映射", NAVY, 20)
    paths = (
        ("设备驻留", "一次上传，链尾回传"),
        ("预处理缓存", "模板、window、FFT plan"),
        ("融合直写", "pack / padding / output reuse"),
        ("并行扫描", "CFAR prefix、峰值归约"),
        ("紧凑输出", "检测列表与验证结果"),
    )
    for i, (name, detail) in enumerate(paths, 1):
        y = 340 + (i - 1) * 86
        rr(d, (1260, y, 1603, y + 67), 9, "#FBFDFF", ORANGE, 2)
        d.ellipse((1276, y + 14, 1317, y + 55), fill=ORANGE)
        txt(d, (1297, y + 34), str(i), 18, WHITE, True, "mm")
        txt(d, (1337, y + 24), name, 16, NAVY, True, "lm")
        txt(d, (1337, y + 47), detail, 12, TEXT, True, "lm")
    footer(d, "设备驻留、缓存、算子内复用、CFAR 扫描与紧凑输出共同支撑任务一。")
    im.save(OUT / "P12_任务一_五类路径机制_v06.png")


def page_p14() -> None:
    im, d = base(
        "核心技术",
        "任务二：五类路径构建批量评分与跟踪",
        "从逐帧全量中间张量转向设备驻留、批量评分和紧凑状态输出。",
    )
    speed_badge(d, (1276, 102, 1608, 155), "Task2 L6 E2E", "1053.33×", ORANGE,
                "", 19)
    panel(d, (44, 265, 1210, 474), "CPU reference：逐帧完整中间结果", CPU, 20)
    cpu_steps = ((84, "frame"), (320, "full correlate"), (560, "full spectrogram"), (800, "full CWT"), (1040, "host track"))
    for i, (x, step_name) in enumerate(cpu_steps):
        rr(d, (x, 350, x + 154, 414), 8, "#F1F4F7", CPU, 1)
        txt(d, (x + 77, 382), step_name, 14, TEXT, True, "mm")
        if i < len(cpu_steps) - 1:
            arrow(d, x + 158, 382, cpu_steps[i + 1][0] - 8, 382, CPU, 2)
    txt(d, (617, 442), "full tensors / B=1 / host postprocess", 14, RED, True, "ma")

    panel(d, (44, 500, 1210, 808), "GPU path：B=8 device batch + score-only", TEAL, 20)
    label(d, (72, 622, 167, 684), "一次 H2D", NAVY, PALE, 15)
    arrow(d, 170, 653, 220, 653, TEAL, 3)
    label(d, (232, 607, 355, 699), "B = 8\nDevice batch", TEAL, "#ECF9F6", 16)
    arrow(d, 362, 653, 424, 653, TEAL, 3)
    scores = ("filter / demod score", "correlate score", "spectrogram band-score", "CWT max-score")
    for i, value in enumerate(scores):
        y = 554 + i * 45
        rr(d, (445, y, 735, y + 34), 6, "#ECF9F6", "#8FD8D3", 1)
        rr(d, (445, y, 540 + i * 21, y + 34), 6, TEAL)
        txt(d, (560, y + 17), value, 13, TEXT, True, "lm")
    arrow(d, 755, 653, 810, 653, TEAL, 3)
    label(d, (824, 602, 950, 705), "并行归约\nweighted / smooth", TEAL, "#ECF9F6", 15)
    arrow(d, 958, 653, 1007, 653, TEAL, 3)
    label(d, (1019, 602, 1169, 705), "peak + Kalman\ncompact output", ORANGE, "#FFF7ED", 15)

    panel(d, (1235, 265, 1628, 808), "五类路径与代表加速", NAVY, 20)
    paths = (
        ("设备驻留 / 批处理", "Task2 L6 1053.33×"),
        ("预处理与 plan 复用", "spectrogram 50.64×"),
        ("直接写入评分", "fm_demod 3.75×"),
        ("并行归约", "CWT 412.12×"),
        ("score-only / 紧凑输出", "correlate2d 2.74×"),
    )
    for i, (name, detail) in enumerate(paths, 1):
        y = 338 + (i - 1) * 88
        rr(d, (1260, y, 1603, y + 69), 9, "#FBFDFF", ORANGE, 2)
        d.ellipse((1276, y + 15, 1317, y + 56), fill=ORANGE)
        txt(d, (1297, y + 36), str(i), 18, WHITE, True, "mm")
        txt(d, (1337, y + 24), name, 14, NAVY, True, "lm")
        txt(d, (1337, y + 48), detail, 12, TEXT, True, "lm")
    footer(d, "批量评分减少全量张量物化，输出聚焦评分、峰值、状态与轨迹。")
    im.save(OUT / "P14_任务二_五类路径机制_v13.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    page_p05()
    page_p06()
    page_p07()
    page_p08()
    page_p12()
    page_p14()
    print(f"generated 6 mechanism pages in {OUT}")


if __name__ == "__main__":
    main()
