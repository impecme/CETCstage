#!/usr/bin/env python3
"""Render evidence-backed PNG pages from the published report snapshot.

Only data in data/reports/ is used.  The script intentionally labels all
performance figures as the 2026-07-20 published snapshot; it does not claim
the numbers were measured from the current worktree.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ppt_work" / "generated"
W, H = 1672, 941

NAVY = "#0B5CAD"
BLUE = "#1677D2"
LIGHT = "#EAF3FB"
PALE = "#F5F9FD"
TEAL = "#00A6A6"
ORANGE = "#F28C28"
RED = "#D94841"
CPU = "#788796"
TEXT = "#243447"
MUTED = "#6B7B8C"
WHITE = "#FFFFFF"
REG = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
BOLD = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(BOLD if bold else REG, size)


def txt(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, size: int,
        color: str = TEXT, bold: bool = False, anchor: str = "la") -> None:
    draw.text(xy, text, font=font(size, bold), fill=color, anchor=anchor)


def rr(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], radius: int,
       fill: str, outline: str | None = None, width: int = 2) -> None:
    if hasattr(draw, "rounded_rectangle"):
        draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)
    else:
        draw.rectangle(box, fill=fill, outline=outline, width=width)


def line(draw: ImageDraw.ImageDraw, coords: tuple[int, int, int, int], color: str,
         width: int = 3) -> None:
    draw.line(coords, fill=color, width=width)


def arrow(draw: ImageDraw.ImageDraw, x1: int, y1: int, x2: int, y2: int,
          color: str = BLUE, width: int = 3) -> None:
    line(draw, (x1, y1, x2, y2), color, width)
    if abs(x2 - x1) >= abs(y2 - y1):
        sign = 1 if x2 >= x1 else -1
        draw.polygon([(x2, y2), (x2 - 12 * sign, y2 - 7), (x2 - 12 * sign, y2 + 7)], fill=color)
    else:
        sign = 1 if y2 >= y1 else -1
        draw.polygon([(x2, y2), (x2 - 7, y2 - 12 * sign), (x2 + 7, y2 - 12 * sign)], fill=color)


def base(active: str, title: str, conclusion: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(im)
    # Header and navigation: the same structural system as P03-P08.
    d.polygon([(25, 31), (48, 18), (71, 31), (71, 56), (48, 69), (25, 56)], fill=NAVY)
    d.polygon([(34, 34), (48, 26), (62, 34), (48, 42)], fill=WHITE)
    txt(d, (110, 38), "信号处理算子库", 30, NAVY, True, "lm")
    nav = ["团队介绍", "赛题解析", "技术路线", "核心技术", "技术指标", "创新点"]
    # Keep the active-tab highlight within its navigation slot.  The original
    # 250 px active tab overlapped the next label at 16:9 export size, which
    # made otherwise clean technical pages look cramped.
    xs = [525, 725, 925, 1125, 1325, 1525]
    for item, x in zip(nav, xs):
        if item == active:
            rr(d, (x - 82, 16, x + 82, 61), 12, BLUE)
            txt(d, (x, 39), item, 20, WHITE, True, "mm")
        else:
            txt(d, (x, 39), item, 20, NAVY, True, "mm")
    line(d, (18, 73, 1655, 73), BLUE, 3)
    txt(d, (48, 112), title, 54, TEXT, True)
    line(d, (50, 178, 140, 178), BLUE, 7)
    txt(d, (50, 205), conclusion, 24, NAVY, True)
    return im, d


def card_header(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
                fill: str = NAVY, size: int = 23) -> None:
    x1, y1, x2, y2 = box
    rr(d, box, 12, WHITE, BLUE, 2)
    rr(d, (x1, y1, x2, y1 + 50), 12, fill)
    # Cover rounded lower corners of the header.
    d.rectangle((x1, y1 + 25, x2, y1 + 50), fill=fill)
    txt(d, ((x1 + x2) // 2, y1 + 25), title, size, WHITE, True, "mm")


def save(im: Image.Image, filename: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / filename, quality=95)


def load_json(*parts: str) -> dict:
    return json.loads((ROOT.joinpath(*parts)).read_text())


def page_p09() -> None:
    im, d = base(
        "技术指标",
        "Task1：已发布 final-input 34.20×，五项优化沿链累积",
        "端到端收益来自持续删除准备、矩阵、prefix 与回传开销，而非单个 kernel。",
    )
    vals = []
    for level in range(1, 7):
        m = load_json("data", "reports", "demo", "task1_radar", "scales", f"L{level}", "metrics.json")
        t = m["timings"]["total"]
        vals.append(t["cpu_ms"] / t["gpu_ms"])
    final = load_json("data", "reports", "demo", "task1_radar", "final", "metrics.json")
    total = final["timings"]["total"]
    target = final["expected_detection"]

    # Scaling chart.
    box = (44, 265, 790, 725)
    card_header(d, box, "Task1 L1-L6 · application-total", size=19)
    x1, y1, x2, y2 = 112, 350, 745, 655
    for v in range(0, 26, 5):
        yy = y2 - int((v / 25) * (y2 - y1))
        line(d, (x1, yy, x2, yy), "#DDE8F3", 1)
        txt(d, (94, yy), f"{v}×", 16, MUTED, False, "rm")
    line(d, (x1, y1, x1, y2), MUTED, 2)
    line(d, (x1, y2, x2, y2), MUTED, 2)
    pts = []
    for i, value in enumerate(vals):
        xx = x1 + int(i * (x2 - x1) / 5)
        yy = y2 - int((value / 25) * (y2 - y1))
        pts.append((xx, yy))
        txt(d, (xx, y2 + 32), f"L{i + 1}", 18, TEXT, True, "ma")
        txt(d, (xx, yy - 19), f"{value:.2f}", 15, NAVY, True, "ma")
    for a, b in zip(pts[:-2], pts[1:-1]):
        line(d, (*a, *b), TEAL, 5)
    line(d, (*pts[-2], *pts[-1]), ORANGE, 5)
    for i, (xx, yy) in enumerate(pts):
        d.ellipse((xx - 8, yy - 8, xx + 8, yy + 8), fill=ORANGE if i == 5 else TEAL, outline=WHITE, width=2)
    txt(d, (417, 692), "L5→L6 回落：规模与固定成本共同变化", 17, ORANGE, True, "ma")

    # Final time comparison.
    mid = (818, 265, 1153, 725)
    card_header(d, mid, "已发布 final-input", size=18)
    txt(d, (985, 356), "34.20×", 48, BLUE, True, "ma")
    txt(d, (985, 414), "RUN 2026-07-20 SNAPSHOT", 14, MUTED, True, "ma")
    max_ms = total["cpu_ms"]
    for label, value, color, yy in [("CPU reference", total["cpu_ms"], CPU, 490), ("ZQ500 GPU", total["gpu_ms"], TEAL, 585)]:
        txt(d, (852, yy - 20), label, 19, TEXT, True)
        bw = max(20, int(235 * value / max_ms))
        rr(d, (852, yy, 852 + bw, yy + 30), 8, color)
        txt(d, (852, yy + 52), f"{value:.6g} ms", 18, color, True)
    txt(d, (985, 661), "application-total，含 input construction", 14, RED, False, "ma")

    # Historical A/B panel.
    right = (1180, 265, 1628, 725)
    card_header(d, right, "五项历史 A/B 证据", size=18)
    ab = [
        ("template FFT cache", "pulse -7.43%"),
        ("frequency scale fusion", "pulse -4.79%"),
        ("transpose + fftshift", "Doppler -11.57%"),
        ("row prefix", "CA-CFAR -28.68%"),
        ("two-stage peak", "4.052 → 0.096 ms"),
    ]
    for i, (name, value) in enumerate(ab):
        yy = 344 + i * 68
        rr(d, (1202, yy, 1607, yy + 51), 8, LIGHT if i % 2 == 0 else PALE, "#C5D9EE", 1)
        txt(d, (1220, yy + 25), name, 14, TEXT, True, "lm")
        txt(d, (1465, yy + 25), value, 14, ORANGE, True, "lm")
    txt(d, (1404, 686), "分别说明来源，不相乘", 15, RED, False, "ma")

    # Correctness strip.
    rr(d, (44, 751, 1628, 872), 12, PALE, BLUE, 2)
    txt(d, (80, 786), "最终检测正确性", 22, NAVY, True)
    txt(d, (80, 821), f"Expected / CPU / GPU：range={target['range_bin']}，Doppler={target['doppler_bin']}，{target['doppler_hz']} Hz", 20, TEXT, True)
    cx, cy = 1450, 811
    for rad, color, label in [(37, NAVY, "Expected"), (27, CPU, "CPU"), (17, TEAL, "GPU")]:
        d.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), outline=color, width=4)
    txt(d, (1587, 790), "三者重合", 17, TEAL, True, "rm")
    txt(d, (50, 908), "数据：RUN 2026-07-20 SNAPSHOT · Task1 final/L1-L6 metrics；无独立传统 GPU 基线。", 14, MUTED)
    save(im, "P09_Task1_性能与正确性_整页_v01.png")


def page_p11() -> None:
    im, d = base(
        "技术指标",
        "Task2：已发布 final-input 1071.70×，候选必须通过双门",
        "高倍数来自逐帧完整 CPU 流程与 batched score-only GPU 特化的结构差异。",
    )
    vals = []
    for level in range(1, 7):
        m = load_json("data", "reports", "demo", "task2_features", "scales", f"L{level}", "metrics.json")
        t = m["timings"]["total"]
        vals.append(t["cpu_ms"] / t["gpu_ms"])
    final = load_json("data", "reports", "demo", "task2_features", "final", "metrics.json")
    total = final["timings"]["total"]

    box = (44, 265, 790, 725)
    card_header(d, box, "Task2 L1-L6 · application-total", size=19)
    x1, y1, x2, y2 = 112, 350, 745, 655
    for v in (0, 250, 500, 750, 950):
        yy = y2 - int((v / 950) * (y2 - y1))
        line(d, (x1, yy, x2, yy), "#DDE8F3", 1)
        txt(d, (94, yy), f"{v}×", 16, MUTED, False, "rm")
    line(d, (x1, y1, x1, y2), MUTED, 2)
    line(d, (x1, y2, x2, y2), MUTED, 2)
    pts = []
    for i, value in enumerate(vals):
        xx = x1 + int(i * (x2 - x1) / 5)
        yy = y2 - int((value / 950) * (y2 - y1))
        pts.append((xx, yy))
        txt(d, (xx, y2 + 32), f"L{i + 1}", 18, TEXT, True, "ma")
        label_y = max(y1 + 15, yy - 18)
        txt(d, (xx, label_y), f"{value:.0f}", 15, NAVY, True, "ma")
    for a, b in zip(pts[:-1], pts[1:]):
        line(d, (*a, *b), TEAL, 5)
    for xx, yy in pts:
        d.ellipse((xx - 8, yy - 8, xx + 8, yy + 8), fill=TEAL, outline=WHITE, width=2)
    txt(d, (417, 692), "L1-L6 同时改变帧数、样本、模板和 FFT 长度", 17, ORANGE, True, "ma")

    mid = (818, 265, 1153, 725)
    card_header(d, mid, "已发布 final-input", size=18)
    txt(d, (985, 356), "1071.70×", 42, BLUE, True, "ma")
    txt(d, (985, 414), "RUN 2026-07-20 SNAPSHOT", 14, MUTED, True, "ma")
    max_ms = total["cpu_ms"]
    for label, value, color, yy in [("CPU reference", total["cpu_ms"], CPU, 490), ("ZQ500 GPU", total["gpu_ms"], TEAL, 585)]:
        txt(d, (852, yy - 20), label, 19, TEXT, True)
        bw = max(20, int(235 * value / max_ms))
        rr(d, (852, yy, 852 + bw, yy + 30), 8, color)
        txt(d, (852, yy + 52), f"{value:.6g} ms", 18, color, True)
    txt(d, (985, 661), "application-total，含 input construction", 14, RED, False, "ma")

    right = (1180, 265, 1628, 725)
    card_header(d, right, "A/B 正确性与 E2E 门禁", size=18)
    rows = [
        ("保留", "AOT correlate", "hotspot -61.66% · E2E -9.77%", TEAL),
        ("保留", "AOT spectrogram", "hotspot -43.37% · E2E -7.78%", TEAL),
        ("回退", "AOT filter", "精度失败", RED),
        ("回退", "CWT symmetry", "L5/L6 E2E 退化", RED),
        ("回退", "expanded cache", "聚合收益仅 0.0958%", RED),
    ]
    for i, (status, name, desc, color) in enumerate(rows):
        yy = 340 + i * 68
        rr(d, (1202, yy, 1607, yy + 52), 8, LIGHT if i % 2 == 0 else PALE, "#C5D9EE", 1)
        rr(d, (1212, yy + 10, 1262, yy + 42), 6, color)
        txt(d, (1237, yy + 26), status, 14, WHITE, True, "mm")
        txt(d, (1275, yy + 18), name, 14, TEXT, True)
        txt(d, (1275, yy + 36), desc, 12, color, True)

    rr(d, (44, 751, 1628, 872), 12, PALE, BLUE, 2)
    txt(d, (80, 786), "最终业务正确性", 22, NAVY, True)
    txt(d, (80, 821), "CPU/GPU peak track 一致；truth RMSE 0.477855 < 2", 20, TEXT, True)
    # Short evidence-backed track sketch; sample real points at a readable interval.
    truth = final["truth_track"]
    gpu = final["gpu_kalman_track"]
    cx1, cy1, cx2, cy2 = 1110, 775, 1510, 846
    line(d, (cx1, cy2, cx2, cy2), MUTED, 1)
    line(d, (cx1, cy1, cx1, cy2), MUTED, 1)
    lo, hi = min(truth) - 5, max(truth) + 5
    for seq, color, width in [(truth, TEXT, 2), (gpu, TEAL, 3)]:
        pts2 = []
        for i in range(0, len(seq), 4):
            xx = cx1 + int(i * (cx2 - cx1) / (len(seq) - 1))
            yy = cy2 - int((seq[i] - lo) * (cy2 - cy1) / (hi - lo))
            pts2.append((xx, yy))
        for a, b in zip(pts2[:-1], pts2[1:]):
            line(d, (*a, *b), color, width)
    txt(d, (1518, 786), "truth", 13, TEXT, True)
    txt(d, (1518, 817), "GPU", 13, TEAL, True)
    txt(d, (50, 908), "数据：RUN 2026-07-20 SNAPSHOT · Task2 final/L1-L6 metrics；无独立传统 GPU 基线。", 14, MUTED)
    save(im, "P11_Task2_性能与门禁_整页_v01.png")


def page_p14() -> None:
    im, d = base(
        "技术指标",
        "已发布运行与正确性：算子、任务、步骤、业务结果形成闭环",
        "报告快照同时验证 81 算子、两条任务、14 个步骤以及最终业务输出。",
    )
    task1 = load_json("data", "reports", "demo", "task1_radar", "final", "metrics.json")
    task2 = load_json("data", "reports", "demo", "task2_features", "final", "metrics.json")

    # Left validation coverage.
    rr(d, (44, 265, 626, 850), 12, PALE, BLUE, 2)
    txt(d, (76, 303), "RUN 2026-07-20 SNAPSHOT", 22, NAVY, True)
    items = [("81/81", "公开算子", TEAL), ("2/2", "端到端任务", BLUE), ("14/14", "正式计算步骤", ORANGE), ("12/12", "L1-L6 任务运行", NAVY)]
    for i, (num, label, color) in enumerate(items):
        x = 84 + (i % 2) * 265
        y = 355 + (i // 2) * 205
        rr(d, (x, y, x + 230, y + 156), 14, WHITE, "#C5D9EE", 2)
        txt(d, (x + 115, y + 58), num, 42, color, True, "ma")
        txt(d, (x + 115, y + 112), label, 20, TEXT, True, "ma")
    rr(d, (84, 766, 578, 817), 8, LIGHT, "#C5D9EE", 1)
    txt(d, (331, 791), "contracts · unit · demo · reports", 18, NAVY, True, "ma")

    # Task1 detection panel.
    top = (662, 265, 1628, 526)
    card_header(d, top, "Task1 · Expected / CPU / GPU 检测一致", size=20)
    gx1, gy1, gx2, gy2 = 715, 348, 1120, 480
    for i in range(9):
        xx = gx1 + int(i * (gx2 - gx1) / 8)
        line(d, (xx, gy1, xx, gy2), "#DDE8F3", 1)
    for i in range(5):
        yy = gy1 + int(i * (gy2 - gy1) / 4)
        line(d, (gx1, yy, gx2, yy), "#DDE8F3", 1)
    # energy cells and exact coincident target.
    for ix, iy, intensity in [(4, 2, "#6FB1E8"), (5, 2, "#9DC9F1"), (4, 3, "#5A9DE0"), (5, 3, "#B9D8F5")]:
        x = gx1 + int(ix * (gx2 - gx1) / 8)
        y = gy1 + int(iy * (gy2 - gy1) / 4)
        d.rectangle((x + 2, y + 2, x + 48, y + 29), fill=intensity)
    cx, cy = gx1 + int(6 * (gx2 - gx1) / 8), gy1 + int(2 * (gy2 - gy1) / 4)
    for rad, color in [(25, NAVY), (18, CPU), (11, TEAL)]:
        d.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), outline=color, width=3)
    txt(d, (1165, 355), "Expected = CPU = GPU", 22, TEAL, True)
    txt(d, (1165, 400), f"range={task1['expected_detection']['range_bin']}\nDoppler={task1['expected_detection']['doppler_bin']}\n{task1['expected_detection']['doppler_hz']} Hz", 20, TEXT, True)

    # Task2 track panel.
    bottom = (662, 548, 1628, 850)
    card_header(d, bottom, "Task2 · truth / CPU / GPU 轨迹与误差", size=20)
    tx1, ty1, tx2, ty2 = 725, 625, 1375, 792
    line(d, (tx1, ty2, tx2, ty2), MUTED, 2)
    line(d, (tx1, ty1, tx1, ty2), MUTED, 2)
    truth = task2["truth_track"]
    cpu = task2["cpu_kalman_track"]
    gpu = task2["gpu_kalman_track"]
    lo = min(truth) - 8
    hi = max(truth) + 8
    for seq, color, width in [(truth, TEXT, 2), (cpu, CPU, 2), (gpu, TEAL, 3)]:
        ps = []
        for i in range(0, len(seq), 3):
            xx = tx1 + int(i * (tx2 - tx1) / (len(seq) - 1))
            yy = ty2 - int((seq[i] - lo) * (ty2 - ty1) / (hi - lo))
            ps.append((xx, yy))
        for a, b in zip(ps[:-1], ps[1:]):
            line(d, (*a, *b), color, width)
    txt(d, (1415, 638), "truth", 18, TEXT, True)
    txt(d, (1415, 678), "CPU", 18, CPU, True)
    txt(d, (1415, 718), "GPU", 18, TEAL, True)
    txt(d, (1415, 767), "RMSE\n0.477855 < 2", 21, NAVY, True)

    rr(d, (44, 872, 1628, 914), 8, LIGHT, "#C5D9EE", 1)
    txt(d, (68, 893), "误差边界：Task1 CFAR mixed error 0.276398 < 0.5；Task2 feature-score mixed error 9.83703e-5 < 1e-4。", 16, TEXT, True, "lm")
    txt(d, (50, 928), "报告为已发布 source snapshot；当前源树有 4 项 drift，正式答辩前需在冻结 commit 复验。", 13, RED)
    save(im, "P14_已发布运行与正确性_整页_v01.png")


def detailed_cases() -> list[dict]:
    summary = load_json("data", "reports", "units", "benchmarks", "summary.json")
    rows = []
    for op in summary["operators"]:
        for case in op.get("performance_cases", []):
            if case.get("source") == "case_detail":
                rows.append({
                    "module": op["module"],
                    "operator": op["operator"],
                    "case": case["case_id"],
                    "speedup": case["gpu_e2e_speedup"],
                })
    return sorted(rows, key=lambda item: item["speedup"])


def page_p15() -> None:
    import math

    im, d = base(
        "技术指标",
        "全库性能分布：69/78 个 detailed case 加速，跨度由结构决定",
        "大规模 stencil、频谱与批处理路径收益高；极小标量和固定 setup 主导的 case 仍可能慢于 CPU。",
    )
    rows = detailed_cases()
    fast = sum(r["speedup"] > 1 for r in rows)
    slow = len(rows) - fast
    values = [r["speedup"] for r in rows]
    median = sorted(values)[len(values) // 2 - 1:len(values) // 2 + 1]
    median_value = sum(median) / len(median)
    geomean = math.exp(sum(math.log(x) for x in values) / len(values))

    box = (44, 265, 1125, 820)
    card_header(d, box, "78 条 source=case_detail · GPU E2E speedup（log Y）", size=19)
    x1, y1, x2, y2 = 112, 350, 1070, 740
    lo_log, hi_log = -4, 3
    ticks = [(-3, "0.001×"), (-2, "0.01×"), (-1, "0.1×"), (0, "1×"), (1, "10×"), (2, "100×"), (3, "1000×")]
    for lv, label in ticks:
        yy = y2 - int((lv - lo_log) * (y2 - y1) / (hi_log - lo_log))
        line(d, (x1, yy, x2, yy), "#DDE8F3" if lv != 0 else ORANGE, 2 if lv == 0 else 1)
        txt(d, (96, yy), label, 15, ORANGE if lv == 0 else MUTED, True if lv == 0 else False, "rm")
    line(d, (x1, y1, x1, y2), MUTED, 2)
    line(d, (x1, y2, x2, y2), MUTED, 2)
    annotate = {"wiener": "Wiener", "lfilter": "lfilter", "cwt": "CWT"}
    for idx, row in enumerate(rows):
        xx = x1 + int(idx * (x2 - x1) / (len(rows) - 1))
        lv = math.log10(row["speedup"])
        yy = y2 - int((lv - lo_log) * (y2 - y1) / (hi_log - lo_log))
        color = TEAL if row["speedup"] > 1 else RED
        radius = 5 if row["operator"] not in annotate else 8
        d.ellipse((xx - radius, yy - radius, xx + radius, yy + radius), fill=color, outline=WHITE, width=1)
        if row["operator"] in annotate:
            tx = min(x2 - 20, xx + 9)
            ty = yy - 15 if yy > y1 + 35 else yy + 16
            txt(d, (tx, ty), f"{annotate[row['operator']]} {row['speedup']:.3g}×", 14, NAVY, True)
    txt(d, ((x1 + x2) // 2, 778), "按 speedup 升序；橙线为 1×；红点 = 慢于 CPU", 16, MUTED, True, "ma")

    right = (1155, 265, 1628, 820)
    card_header(d, right, "分布结论", size=20)
    for i, (num, label, color) in enumerate([(f"{fast} / {slow}", "快 / 慢", TEAL), (f"{median_value:.3f}×", "median", BLUE), (f"{geomean:.3f}×", "geomean", NAVY)]):
        yy = 350 + i * 118
        rr(d, (1188, yy, 1595, yy + 94), 10, LIGHT if i % 2 == 0 else PALE, "#C5D9EE", 1)
        txt(d, (1391, yy + 36), num, 34, color, True, "ma")
        txt(d, (1391, yy + 70), label, 18, TEXT, True, "ma")
    rr(d, (1188, 714, 1595, 782), 8, "#FFF7ED", ORANGE, 1)
    txt(d, (1207, 735), "Wiener：邻域复用", 16, TEXT, True)
    txt(d, (1207, 760), "lfilter：event 快，E2E 仍慢", 16, RED, True)
    txt(d, (50, 892), "数据：RUN 2026-07-20 SNAPSHOT · 仅 78 detailed cases；另有 8 条 summary_aggregate 未混入主图。", 14, MUTED)
    save(im, "P15_全库性能分布_整页_v01.png")


def page_p16() -> None:
    im, d = base(
        "技术指标",
        "Scaling 与热点：并行度释放后，瓶颈转向输入与重算子",
        "两条任务随规模增大获得更多并行度；Task1 L6 回落，Task2 CWT 仍是最大热点。",
    )
    def speeds(task: str) -> list[float]:
        out = []
        for level in range(1, 7):
            m = load_json("data", "reports", "demo", task, "scales", f"L{level}", "metrics.json")
            t = m["timings"]["total"]
            out.append(t["cpu_ms"] / t["gpu_ms"])
        return out
    t1, t2 = speeds("task1_radar"), speeds("task2_features")

    def chart(box: tuple[int, int, int, int], title: str, vals: list[float], ymax: float, accent_last: bool = False) -> None:
        card_header(d, box, title, size=19)
        bx1, by1, bx2, by2 = box
        x1, y1, x2, y2 = bx1 + 60, by1 + 88, bx2 - 35, by2 - 55
        for frac, label in [(0, "0×"), (0.5, f"{ymax/2:.0f}×"), (1, f"{ymax:.0f}×")]:
            yy = y2 - int(frac * (y2 - y1))
            line(d, (x1, yy, x2, yy), "#DDE8F3", 1)
            txt(d, (x1 - 8, yy), label, 14, MUTED, False, "rm")
        line(d, (x1, y1, x1, y2), MUTED, 2); line(d, (x1, y2, x2, y2), MUTED, 2)
        ps = []
        for i, value in enumerate(vals):
            xx = x1 + int(i * (x2 - x1) / 5); yy = y2 - int(value / ymax * (y2 - y1)); ps.append((xx, yy))
            txt(d, (xx, y2 + 23), f"L{i+1}", 15, TEXT, True, "ma")
            txt(d, (xx, max(y1 + 12, yy - 15)), f"{value:.1f}", 13, NAVY, True, "ma")
        for i, (a, b) in enumerate(zip(ps[:-1], ps[1:])): line(d, (*a, *b), ORANGE if accent_last and i == 4 else TEAL, 4)
        for i, (xx, yy) in enumerate(ps): d.ellipse((xx-6, yy-6, xx+6, yy+6), fill=ORANGE if accent_last and i == 5 else TEAL, outline=WHITE, width=1)

    chart((44, 265, 810, 550), "Task1 L1-L6 speedup", t1, 25, True)
    chart((854, 265, 1628, 550), "Task2 L1-L6 speedup", t2, 950)

    task1_parts = [("input", 30.17, CPU), ("ambgfun", 27.46, NAVY), ("Doppler", 15.20, BLUE), ("pulse", 12.40, TEAL), ("CFAR", 11.00, ORANGE), ("other", 3.77, MUTED)]
    task2_parts = [("CWT", 45.94, NAVY), ("input", 19.12, CPU), ("spectrogram", 13.95, BLUE), ("filter", 8.77, TEAL), ("correlate", 8.07, ORANGE), ("other", 4.15, MUTED)]
    def stack(box: tuple[int, int, int, int], title: str, parts: list[tuple[str, float, str]]) -> None:
        card_header(d, box, title, size=19)
        bx1, by1, bx2, by2 = box
        barx1, bary, barx2 = bx1 + 55, by1 + 100, bx2 - 55
        cur = barx1
        for name, value, color in parts:
            nxt = cur + int((barx2 - barx1) * value / 100)
            d.rectangle((cur, bary, nxt, bary + 48), fill=color)
            if value >= 8: txt(d, ((cur+nxt)//2, bary+24), f"{name}\n{value:.2f}%", 13, WHITE, True, "mm")
            cur = nxt
        for idx, (name, value, color) in enumerate(parts):
            xx = bx1 + 60 + (idx % 3) * 215; yy = by1 + 185 + (idx // 3) * 48
            d.rectangle((xx, yy, xx+16, yy+16), fill=color)
            txt(d, (xx+24, yy+8), f"{name} {value:.2f}%", 14, TEXT, True, "lm")

    stack((44, 585, 810, 850), "Task1 final-input GPU 时间构成", task1_parts)
    stack((854, 585, 1628, 850), "Task2 final-input GPU 时间构成", task2_parts)
    txt(d, (50, 908), "数据：RUN 2026-07-20 SNAPSHOT · L1-L6 同时改变多维输入；GPU event 是 stream work，不是单 kernel profiler 时间。", 14, MUTED)
    save(im, "P16_Scaling与热点_整页_v01.png")


if __name__ == "__main__":
    page_p09()
    page_p11()
    page_p14()
    page_p15()
    page_p16()
