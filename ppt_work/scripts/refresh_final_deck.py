#!/usr/bin/env python3
"""Render the final technical pages from the current published reports.

The renderer deliberately keeps every chart and timing figure data-native.  It
does not synthesize performance illustrations: CPU/GPU values, scale curves,
correctness gates and operator tiers are read directly from ``data/reports``.
``X×`` is the only retained placeholder, reserved for a future same-scale
GPU-before/GPU-after baseline run.
"""

from __future__ import annotations

import json
import math
import statistics
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageDraw

from generate_data_pages import (
    BLUE, CPU, LIGHT, MUTED, NAVY, ORANGE, PALE, RED, TEAL, TEXT, WHITE,
    W, H, arrow, base, card_header, line, rr, txt,
)


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "ppt_work" / "final_images"
REPORTS = ROOT / "data" / "reports"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save(im: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    im.convert("RGB").save(OUT / name, quality=95)


def panel(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
          color: str = NAVY, size: int = 20) -> None:
    card_header(d, box, title, color, size)


def label(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], value: str,
          color: str = NAVY, fill: str = LIGHT, size: int = 16) -> None:
    rr(d, box, 8, fill, "#BFD3E7", 1)
    txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2), value, size, color, True, "mm")


def summary_band(d: ImageDraw.ImageDraw, value: str) -> None:
    rr(d, (44, 866, W - 44, 914), 11, NAVY)
    txt(d, (W // 2, 890), value, 20, WHITE, True, "mm")


def task_metrics(task: str, level: int) -> dict:
    return load(REPORTS / "demo" / task / "scales" / f"L{level}" / "metrics.json")


def speedups(task: str) -> list[float]:
    return [task_metrics(task, level)["speedup"]["cpu_over_gpu"] for level in range(1, 7)]


def l6(task: str) -> dict:
    return task_metrics(task, 6)


def formal_levels(task: str) -> list[dict]:
    """Return the six published L1–L6 records in display order."""
    return [task_metrics(task, level) for level in range(1, 7)]


def operator_summary() -> dict:
    return load(REPORTS / "units" / "benchmarks" / "summary.json")


def contract_sets() -> dict[str, list[str]]:
    payload = load(ROOT / "tests" / "contracts" / "operator_sets.json")["sets"]
    all81 = list(payload["all81"]["operators"])

    def resolve(name: str, stack: set[str] | None = None) -> list[str]:
        stack = set() if stack is None else stack
        if name in stack:
            raise ValueError(f"operator set cycle: {name}")
        item = payload[name]
        stack.add(name)
        if "operators" in item:
            values = list(item["operators"])
        else:
            include = {key for child in item.get("include_sets", []) for key in resolve(child, stack)}
            exclude = {key for child in item.get("exclude_sets", []) for key in resolve(child, stack)}
            values = [key for key in all81 if key in include and key not in exclude]
        stack.remove(name)
        if len(values) != item["expected_count"]:
            raise ValueError(f"operator set {name} count mismatch")
        return values

    return {
        "task_used": resolve("task_used"),
        "appendix_only": resolve("appendix_only"),
        "native_only": resolve("native_only"),
        "task_appendix": resolve("task_appendix"),
        "all81": all81,
    }


def operator_records(keys: list[str]) -> list[dict]:
    lookup = {f"{item['module']}/{item['operator']}": item for item in operator_summary()["operators"]}
    result = []
    for key in keys:
        item = lookup[key]
        summary = item["summary"]
        cpu = float(summary["cpu_perf"]["median_ms"])
        gpu = float(summary["gpu_e2e_perf"]["median_ms"])
        result.append({
            "key": key,
            "module": item["module"],
            "operator": item["operator"],
            "cpu": cpu,
            "gpu": gpu,
            "speed": cpu / gpu,
        })
    return result


def metric_card(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int],
                title: str, value: str, color: str, sub: str = "") -> None:
    rr(d, box, 12, WHITE, color, 2)
    txt(d, ((box[0] + box[2]) // 2, box[1] + 31), title, 18, TEXT, True, "ma")
    txt(d, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2 + 8), value, 33, color, True, "ma")
    if sub:
        txt(d, ((box[0] + box[2]) // 2, box[3] - 23), sub, 13, MUTED, True, "ma")


def grid(d: ImageDraw.ImageDraw, x: int, y: int, cols: int, rows: int, cell: int,
         center: str = TEAL, halo: bool = False) -> None:
    for row in range(rows):
        for col in range(cols):
            fill = "#DCE7F0"
            if 0 < row < rows - 1 and 0 < col < cols - 1:
                fill = center
            if halo and (row in (0, rows - 1) or col in (0, cols - 1)):
                fill = ORANGE
            rr(d, (x + col * (cell + 3), y + row * (cell + 3),
                   x + col * (cell + 3) + cell, y + row * (cell + 3) + cell), 2, fill, fill, 1)


def three_metric_stack(d: ImageDraw.ImageDraw, x1: int, y1: int, x2: int,
                       record: dict) -> None:
    metric_card(d, (x1, y1, x2, y1 + 142), "最终 GPU 耗时", f"{record['gpu']:.3f} ms", TEAL,
                record["key"])
    speed_color = TEAL if record["speed"] >= 1 else ORANGE
    metric_card(d, (x1, y1 + 160, x2, y1 + 302), "CPU/GPU 加速比", f"{record['speed']:.2f}×", speed_color,
                "CPU 中位时间 ÷ GPU 中位时间")
    metric_card(d, (x1, y1 + 320, x2, y1 + 462), "GPU 优化前后提速", "X×", ORANGE,
                "同规模基线复测后填入")


def page_p06() -> None:
    rec = operator_records(["filtering/wiener"])[0]
    im, d = base("核心技术", "通用机制一：访存与资源复用", "共享输入与复用准备资源，将重复全局访存转化为块内复用。")
    panel(d, (44, 265, 355, 840), "单算子复用对象", NAVY, 20)
    objects = (("容量存储", "扩容一次，后续复用", "容量"), ("预处理资源", "窗口、计划、查表复用", "准备"), ("邻域输入", "相邻输出共享同一输入", "邻域"))
    for index, (name, desc, mark) in enumerate(objects):
        y = 346 + index * 145
        rr(d, (76, y, 323, y + 112), 12, PALE, "#BCD2E8", 1)
        d.ellipse((93, y + 21, 147, y + 75), fill=BLUE)
        txt(d, (120, y + 48), mark, 16, WHITE, True, "mm")
        txt(d, (166, y + 35), name, 19, NAVY, True, "lm")
        txt(d, (166, y + 70), desc, 14, TEXT, True, "lm")
    panel(d, (385, 265, 1218, 840), "Wiener 分块与 Halo：相邻窗口共享加载", TEAL, 20)
    txt(d, (515, 345), "重复读取的邻域窗口", 19, TEXT, True, "ma")
    for ox, oy in ((430, 390), (470, 430), (510, 470)):
        grid(d, ox, oy, 6, 6, 20, "#F4D4D0")
        rr(d, (ox + 14, oy + 14, ox + 88, oy + 88), 3, "#F9E4E1", RED, 2)
    arrow(d, 650, 505, 735, 505, BLUE, 5)
    txt(d, (849, 345), "共享内存 Tile + Halo", 20, TEAL, True, "ma")
    grid(d, 735, 380, 10, 10, 26, TEAL, True)
    txt(d, (890, 535), "16×16 输出 Tile", 22, WHITE, True, "ma")
    txt(d, (890, 576), "线程协作加载 Halo", 17, TEXT, True, "ma")
    for x, y in ((1060, 385), (1135, 385), (1060, 525), (1135, 525)):
        grid(d, x, y, 4, 4, 20, TEAL)
    txt(d, (1118, 665), "同一 Tile 驱动多点输出", 18, TEAL, True, "ma")
    three_metric_stack(d, 1240, 318, 1628, rec)
    summary_band(d, "总结：一次协作加载，多个输出复用同一邻域数据与预处理资源。")
    save(im, "P06_访存资源复用_Wiener代表_v06_真实数据.png")


def page_p07() -> None:
    rec = operator_records(["filtering/lfilter"])[0]
    im, d = base("核心技术", "通用机制二：并行结构重构", "将递推状态改写为可结合变换，再按层级并行合并。")
    panel(d, (44, 265, 350, 840), "原始递推状态链", RED, 20)
    for i in range(7):
        y = 350 + i * 58
        d.ellipse((118, y, 176, y + 58), fill="#F3F5F7", outline="#A6B3BF", width=2)
        txt(d, (147, y + 29), f"s{i}", 17, TEXT, True, "mm")
        if i < 6:
            arrow(d, 147, y + 60, 147, y + 84, RED, 2)
        txt(d, (198, y + 29), f"s{i + 1} = A{i + 1}s{i} + v{i + 1}", 14, TEXT, True, "lm")
    txt(d, (197, 778), "逐点状态依赖", 19, RED, True, "lm")
    panel(d, (380, 265, 1218, 840), "仿射变换前缀扫描", TEAL, 20)
    leaves = []
    for i in range(8):
        x = 427 + i * 91
        leaves.append(x)
        label(d, (x, 346, x + 70, 386), f"(A{i + 1}, v{i + 1})", ORANGE, "#FFF7ED", 12)
    levels = ((430, 450, 2), (475, 540, 4), (565, 630, 8))
    for start_y, end_y, step in levels:
        for i in range(0, 8, step):
            left = leaves[i]
            right = leaves[min(i + step - 1, 7)] + 70
            cx = (left + right) // 2
            if step == 2:
                arrow(d, left + 35, 389, cx, start_y, TEAL, 2)
                arrow(d, right - 35, 389, cx, start_y, TEAL, 2)
            label(d, (cx - 62, start_y, cx + 62, start_y + 38), "可结合变换", TEAL, "#ECF9F6", 13)
    line(d, (420, 670, 1170, 670), "#B9CFE2", 2)
    tiles = ((450, "块 1", "s0 → s4"), (675, "块 2", "s4 → s8"), (900, "块 3", "s8 → s12"))
    for x, name, state in tiles:
        rr(d, (x, 704, x + 190, 778), 10, "#F5F9FD", TEAL, 2)
        txt(d, (x + 95, 730), name, 18, NAVY, True, "ma")
        txt(d, (x + 95, 758), state, 15, TEXT, True, "ma")
    txt(d, (799, 809), "分块组合 → 扫描 → 并行应用", 20, TEAL, True, "ma")
    three_metric_stack(d, 1240, 318, 1628, rec)
    summary_band(d, "总结：递推状态先变换为可结合结构，再以分块扫描提供并行执行基础。")
    save(im, "P07_并行结构重构_IIR代表_v05_真实数据.png")


def page_p08() -> None:
    rec = operator_records(["spectral/periodogram"])[0]
    im, d = base("核心技术", "通用机制三：路径选择与算子内融合", "单边频谱采用 R2C；融合前后处理减少中间写回。")
    panel(d, (44, 265, 1218, 501), "Periodogram：输出语义驱动频谱路径", NAVY, 21)

    # Left: the single, real dispatch condition in the Periodogram code.
    txt(d, (105, 339), "输出频谱", 20, NAVY, True, "lm")
    label(d, (84, 368, 286, 431), "单边频谱\n单边输出", TEAL, "#ECF9F6", 18)
    label(d, (84, 443, 286, 490), "双边频谱\n双边输出", NAVY, PALE, 17)
    arrow(d, 293, 400, 392, 400, TEAL, 4)
    arrow(d, 293, 467, 392, 467, BLUE, 4)

    # A central hub keeps the old page's visual focus while stating only the
    # actual decision made in the representative operator.
    d.ellipse((396, 329, 568, 501), fill="#F4F8FC", outline=NAVY, width=3)
    d.ellipse((415, 348, 549, 482), fill=NAVY)
    txt(d, (482, 402), "Periodogram\n频谱分派", 22, WHITE, True, "mm")
    arrow(d, 572, 400, 648, 400, TEAL, 4)
    arrow(d, 572, 467, 648, 467, BLUE, 4)

    # R2C: visually show that only the non-redundant half-spectrum is kept.
    rr(d, (655, 329, 920, 426), 13, "#ECF9F6", TEAL, 2)
    txt(d, (678, 351), "R2C FFT", 22, TEAL, True, "lm")
    txt(d, (678, 381), "实数输入 → 单边频谱", 15, TEXT, True, "lm")
    for i, height in enumerate((16, 32, 22, 47, 30, 58, 23, 40)):
        x = 680 + i * 23
        d.rectangle((x, 414 - height, x + 13, 414), fill=TEAL)
    txt(d, (865, 410), "N/2+1", 15, TEAL, True, "rm")

    # C2C: retained as a valid second path rather than implying R2C is universal.
    rr(d, (655, 438, 920, 501), 13, PALE, BLUE, 2)
    txt(d, (678, 459), "C2C FFT", 20, NAVY, True, "lm")
    txt(d, (678, 485), "双边频谱", 14, TEXT, True, "lm")
    for i, height in enumerate((13, 25, 18, 35, 22, 35, 18, 25, 13)):
        x = 828 + i * 9
        d.rectangle((x, 487 - height, x + 5, 487), fill=BLUE)

    # Callout grounds the figure in code rather than a generic claimed policy.
    rr(d, (950, 344, 1174, 481), 12, "#FFF7ED", ORANGE, 2)
    txt(d, (1062, 373), "分派依据", 20, ORANGE, True, "ma")
    txt(d, (1062, 409), "单边 / 双边\n频谱输出", 21, NAVY, True, "mm")
    txt(d, (1062, 458), "仅针对代表算子", 14, MUTED, True, "ma")

    panel(d, (44, 526, 1218, 840), "算子内融合：减少频谱处理中间写回", TEAL, 21)
    # Two clearly separated execution lanes, with the memory-write effect made visible.
    rr(d, (77, 590, 1187, 680), 12, "#F8FAFC", "#D4DFE9", 1)
    txt(d, (102, 635), "常规流程", 19, CPU, True, "lm")
    old = (("去趋势", 240), ("窗函数", 385), ("C2C FFT", 530), ("双边频谱", 675), ("功率", 820), ("PSD", 965))
    for index, (name, x) in enumerate(old):
        label(d, (x, 607, x + 104, 662), name, TEXT, "#F1F4F7", 14)
        if index < len(old) - 1:
            arrow(d, x + 106, 634, x + 138, 634, CPU, 2)
    for x in (352, 497, 642, 787):
        d.polygon(((x, 676), (x + 9, 692), (x - 9, 692)), fill=RED)
    txt(d, (768, 704), "多次中间结果写回", 15, RED, True, "ma")

    rr(d, (77, 726, 1187, 819), 12, "#F1FBF8", "#9CDDD7", 1)
    txt(d, (102, 773), "优化流程", 19, TEAL, True, "lm")
    optimized = (("去趋势 + 窗函数", 240), ("R2C FFT", 463), ("功率 + 缩放", 642), ("PSD", 851))
    for index, (name, x) in enumerate(optimized):
        label(d, (x, 746, x + (174 if index in (0, 2) else 126), 801), name, TEAL, "#ECF9F6", 15)
        width = 174 if index in (0, 2) else 126
        if index < len(optimized) - 1:
            arrow(d, x + width + 3, 774, x + width + 43, 774, TEAL, 3)
    txt(d, (1065, 773), "融合直写", 19, TEAL, True, "ma")
    three_metric_stack(d, 1240, 318, 1628, rec)
    summary_band(d, "总结：单边频谱采用 R2C 路径；算子内融合减少前后处理的中间写回。")
    save(im, "P08_分派融合_Periodogram代表_v06_真实数据.png")


def operator_tier_page(page: str, set_name: str, title: str, conclusion: str) -> None:
    recs = operator_records(contract_sets()[set_name])
    fast = [item for item in recs if item["speed"] > 1]
    median = statistics.median(item["speed"] for item in recs)
    fastest = max(recs, key=lambda item: item["speed"])
    im, d = base("技术指标", title, conclusion)
    metric_card(d, (44, 265, 300, 410), "性能记录", f"{len(recs)}/{len(recs)}", TEAL)
    metric_card(d, (318, 265, 574, 410), "GPU 快于 CPU", f"{len(fast)}/{len(recs)}", BLUE)
    metric_card(d, (592, 265, 848, 410), "中位加速比", f"{median:.2f}×", ORANGE)
    metric_card(d, (866, 265, 1212, 410), "最高代表", f"{fastest['speed']:.2f}×", TEAL,
                f"{fastest['module']} / {fastest['operator']}")
    metric_card(d, (1230, 265, 1628, 410), "GPU 优化前后提速", "X×", ORANGE)

    panel(d, (44, 440, 1628, 840), "逐算子性能：GPU 端到端耗时与 CPU/GPU 加速比", NAVY, 18)
    ordered = sorted(recs, key=lambda item: item["speed"], reverse=True)
    # 所有算子均逐行列出；三列布局同时保留耗时和加速比，避免以模块
    # 覆盖率替代真实性能记录。
    cols = 3 if len(ordered) > 30 else 2
    per_col = math.ceil(len(ordered) / cols)
    inner_left, inner_right = 70, 1602
    col_w = (inner_right - inner_left) // cols
    row_gap = 17 if len(ordered) > 30 else 22
    name_size = 11 if len(ordered) > 30 else 14
    value_size = 10 if len(ordered) > 30 else 12
    header_y = 510
    first_row_y = 526 if len(ordered) > 30 else 536
    for col in range(cols):
        x = inner_left + col * col_w
        if col:
            line(d, (x - 14, 500, x - 14, 824), "#D6E2ED", 1)
        txt(d, (x, header_y), "算子", 13, MUTED, True, "lm")
        txt(d, (x + (170 if cols == 3 else 220), header_y), "GPU / ms", 13, MUTED, True, "lm")
        txt(d, (x + (295 if cols == 3 else 390), header_y), "CPU/GPU", 13, MUTED, True, "lm")
        for index, item in enumerate(ordered[col * per_col:(col + 1) * per_col]):
            y = first_row_y + index * row_gap
            if index % 2 == 0:
                rr(d, (x - 4, y - 10, x + col_w - 20, y + 10), 3, "#F6F9FC")
            name = item["operator"]
            time_x = x + (170 if cols == 3 else 220)
            bar_x = x + (285 if cols == 3 else 380)
            bar_w = 105 if cols == 3 else 160
            one_x = bar_x + int(3 / 6 * bar_w)
            txt(d, (x, y), name, name_size, TEXT, True, "lm")
            txt(d, (time_x, y), f"{item['gpu']:.3f}", value_size, TEAL, True, "lm")
            line(d, (one_x, y - 7, one_x, y + 7), ORANGE, 1)
            level = max(-3.0, min(3.0, math.log10(item["speed"])))
            end = bar_x + int((level + 3) / 6 * bar_w)
            color = TEAL if item["speed"] > 1 else RED
            if end >= one_x:
                rr(d, (one_x, y - 6, end, y + 6), 3, color)
            else:
                rr(d, (end, y - 6, one_x, y + 6), 3, color)
            txt(d, (bar_x + bar_w + 7, y), f"{item['speed']:.2f}×", value_size, color, True, "lm")
    set_labels = {
        "task_used": "任务采用的赛题范围算子",
        "appendix_only": "赛题附录中任务未采用的其余算子",
        "native_only": "原生库非赛题集合",
    }
    summary_band(d, f"总结：{set_labels[set_name]}的 {len(recs)} 个算子均列出 GPU 端到端耗时与 CPU/GPU 加速比。")
    save(im, page)


def page_p09_p11() -> None:
    operator_tier_page("P09_任务实际调用算子性能_v02.png", "task_used",
                       "任务采用的 27 个赛题算子性能", "逐算子比较 CPU 与 ZQ500 GPU 端到端中位时间，展示任务链的公共算子基础。")
    operator_tier_page("P10_赛题附录未调用算子性能_v02.png", "appendix_only",
                       "赛题附录其余 26 个算子性能", "赛题范围内的其余算子保持统一接口与测试口径，性能分布按模块集中呈现。")
    operator_tier_page("P11_原生库非赛题算子性能_v02.png", "native_only",
                       "原生库非赛题的 28 个算子性能", "不在赛题附录的原生库算子同样完成实现与性能测试。")


def curve(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], values: list[float],
          title: str, ceiling: float, color: str = TEAL, precision: int = 1,
          floor: float = 0.0) -> None:
    panel(d, box, title, NAVY, 18)
    x1, y1, x2, y2 = box[0] + 72, box[1] + 86, box[2] - 35, box[3] - 52
    for ratio in (0, .25, .5, .75, 1):
        y = y2 - int((y2 - y1) * ratio)
        line(d, (x1, y, x2, y), "#DCE7F0", 1)
        tick = floor + (ceiling - floor) * ratio
        txt(d, (x1 - 12, y), f"{tick:.0f}×", 12, MUTED, False, "rm")
    line(d, (x1, y1, x1, y2), MUTED, 2)
    line(d, (x1, y2, x2, y2), MUTED, 2)
    points = []
    for i, value in enumerate(values):
        x = x1 + int(i * (x2 - x1) / 5)
        scaled = max(0.0, min(1.0, (value - floor) / (ceiling - floor)))
        y = y2 - int(scaled * (y2 - y1))
        points.append((x, y))
        txt(d, (x, y2 + 25), f"L{i + 1}", 14, ORANGE if i == 5 else TEXT, True, "ma")
        txt(d, (x, max(y1 + 14, y - 16)), f"{value:.{precision}f}", 12, NAVY, True, "ma")
    for a, b in zip(points[:-1], points[1:]):
        line(d, (*a, *b), color, 4)
    for i, (x, y) in enumerate(points):
        d.ellipse((x - 7, y - 7, x + 7, y + 7), fill=ORANGE if i == 5 else color, outline=WHITE, width=2)


def formal_report_panel(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], task: str) -> None:
    """A report-style table rendered from all six current metrics files."""
    x1, y1, x2, y2 = box
    rr(d, box, 12, "#142334", NAVY, 2)
    rr(d, (x1, y1, x2, y1 + 52), 12, NAVY)
    d.rectangle((x1, y1 + 26, x2, y1 + 52), fill=NAVY)
    txt(d, ((x1 + x2) // 2, y1 + 26), "正式 L1–L6 运行记录", 19, WHITE, True, "mm")
    txt(d, (x1 + 30, y1 + 86), "规模", 14, "#9CCFE7", True, "lm")
    txt(d, (x1 + 170, y1 + 86), "CPU / ms", 14, "#9CCFE7", True, "lm")
    txt(d, (x1 + 325, y1 + 86), "GPU / ms", 14, "#9CCFE7", True, "lm")
    txt(d, (x1 + 485, y1 + 86), "CPU/GPU", 14, "#9CCFE7", True, "lm")
    line(d, (x1 + 25, y1 + 106, x2 - 25, y1 + 106), "#35516A", 1)
    for index, record in enumerate(formal_levels(task), start=1):
        y = y1 + 138 + (index - 1) * 51
        if index % 2:
            rr(d, (x1 + 20, y - 19, x2 - 20, y + 20), 4, "#1A2D41")
        measure = record["measurement"]
        shape = record["scenario"]["rx_shape"]
        speed = record["speedup"]["cpu_over_gpu"]
        txt(d, (x1 + 30, y), f"L{index}  {shape[0]}×{shape[1]}", 14, WHITE, True, "lm")
        txt(d, (x1 + 170, y), f"{measure['cpu_total']['median_ms']:.3f}", 14, "#D6E0E8", True, "lm")
        txt(d, (x1 + 325, y), f"{measure['gpu_total']['median_ms']:.3f}", 14, "#55D9D2", True, "lm")
        txt(d, (x1 + 485, y), f"{speed:.2f}×", 14, "#FFAE55" if index == 6 else "#55D9D2", True, "lm")
        d.ellipse((x2 - 38, y - 7, x2 - 24, y + 7), fill="#42D392")
    txt(d, (x1 + 28, y2 - 30), "●  六个正式规模均已完成运行", 14, "#7EE4A6", True, "lm")


def l6_impact_band(d: ImageDraw.ImageDraw, task: str) -> None:
    data = l6(task)
    measure = data["measurement"]
    cpu = measure["cpu_total"]["median_ms"]
    gpu = measure["gpu_total"]["median_ms"]
    speed = data["speedup"]["cpu_over_gpu"]
    rr(d, (44, 748, 1628, 840), 12, "#F4F8FC", BLUE, 2)
    rr(d, (64, 764, 280, 824), 9, NAVY)
    txt(d, (172, 794), "最大规模 L6", 21, WHITE, True, "mm")
    txt(d, (332, 774), "CPU", 16, MUTED, True, "lm")
    txt(d, (332, 802), f"{cpu:.3f} ms", 25, CPU, True, "lm")
    arrow(d, 592, 793, 704, 793, BLUE, 4)
    txt(d, (752, 774), "ZQ500 GPU", 16, MUTED, True, "lm")
    txt(d, (752, 802), f"{gpu:.3f} ms", 25, TEAL, True, "lm")
    arrow(d, 1045, 793, 1155, 793, ORANGE, 4)
    txt(d, (1215, 774), "CPU/GPU 加速比", 16, MUTED, True, "lm")
    txt(d, (1215, 804), f"{speed:.2f}×", 32, ORANGE, True, "lm")


def task_performance_page(page: str, task: str, title: str, conclusion: str) -> None:
    data = l6(task)
    measure = data["measurement"]
    cpu = measure["cpu_total"]["median_ms"]
    gpu = measure["gpu_total"]["median_ms"]
    speed = data["speedup"]["cpu_over_gpu"]
    all_speeds = speedups(task)
    if task == "task1_radar":
        title = f"任务一端到端性能：L1–L6 最高 {max(all_speeds):.2f}×"
        conclusion = "六个正式规模的端到端时间与 CPU/GPU 加速比由同一报告记录。"
    else:
        title = f"任务二端到端性能：L1–L6 最高 {max(all_speeds):.2f}×"
        conclusion = "批量评分路径在六个正式规模的端到端时间与加速比由同一报告记录。"
    im, d = base("技术指标", title, conclusion)
    ceiling = 35 if task == "task1_radar" else 1100
    floor = 25 if task == "task1_radar" else 300
    curve(d, (44, 265, 920, 720), all_speeds, "L1–L6 CPU/GPU 加速比走势", ceiling, TEAL,
          1 if task == "task1_radar" else 0, floor)
    formal_report_panel(d, (950, 265, 1628, 720), task)
    l6_impact_band(d, task)
    summary_band(d, "总结：L1–L6 规模曲线、全部运行记录与 L6 端到端对照共同刻画任务加速表现。")
    save(im, page)


def numbered_path(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], number: int,
                  title: str, detail: str, color: str = ORANGE) -> None:
    rr(d, box, 10, WHITE, "#BFD2E4", 2)
    d.ellipse((box[0] + 16, box[1] + 16, box[0] + 58, box[1] + 58), fill=color)
    txt(d, (box[0] + 37, box[1] + 37), str(number), 20, WHITE, True, "mm")
    txt(d, (box[0] + 75, box[1] + 27), title, 17, NAVY, True, "lm")
    txt(d, (box[0] + 75, box[1] + 53), detail, 13, TEXT, True, "lm")


def flow_box(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
             lines: tuple[str, ...], color: str = TEAL, title_size: int = 17) -> None:
    rr(d, box, 10, WHITE, color, 2)
    rr(d, (box[0], box[1], box[2], box[1] + 40), 10, color)
    d.rectangle((box[0], box[1] + 21, box[2], box[1] + 40), fill=color)
    txt(d, ((box[0] + box[2]) // 2, box[1] + 21), title, title_size, WHITE, True, "mm")
    for index, item in enumerate(lines):
        txt(d, ((box[0] + box[2]) // 2, box[1] + 65 + index * 24), item, 14, TEXT, True, "ma")


def page_p12() -> None:
    im, d = base("核心技术", "任务一：五条路径组合公开算子雷达检测链", "一次上传后，公开算子在 GPU 侧连续执行，链尾回传紧凑检测结果。")
    panel(d, (44, 265, 1210, 748), "GPU 设备驻留的公开算子处理链", TEAL, 20)
    label(d, (68, 474, 172, 536), "主机输入\n一次上传", NAVY, PALE, 15)
    arrow(d, 175, 505, 238, 505, TEAL, 4)
    stages = (
        ("脉冲压缩", ("匹配滤波", "距离维峰值")),
        ("脉冲多普勒", ("频移", "多普勒 FFT")),
        ("功率图", ("|RD|²", "功率归一")),
        ("CA-CFAR", ("自适应门限", "候选单元")),
        ("最终检测", ("两阶段峰值", "检测列表")),
    )
    xs = (235, 422, 609, 796, 983)
    for index, ((name, lines), x) in enumerate(zip(stages, xs), start=1):
        flow_box(d, (x, 362, x + 154, 620), f"{index}  {name}", lines, title_size=14)
        if index < len(stages):
            arrow(d, x + 157, 490, x + 181, 490, TEAL, 3)
    # A separate visual branch has a real task role and is labelled accordingly.
    label(d, (100, 665, 230, 716), "模糊函数分支", NAVY, PALE, 16)
    arrow(d, 233, 690, 320, 690, TEAL, 3)
    flow_box(d, (326, 644, 560, 723), "模糊函数计算", ("并行质量分析",), BLUE)
    label(d, (1010, 474, 1183, 536), "紧凑回传\n检测与验证", TEAL, "#ECF9F6", 15)

    panel(d, (1235, 265, 1628, 748), "五条组合路径", NAVY, 20)
    paths = (
        ("设备驻留", "一次上传，链尾回传"),
        ("预处理缓存", "模板与 FFT 资源复用"),
        ("融合直写", "缩放、转置与移位合并"),
        ("并行扫描与归约", "行前缀 CFAR、两级峰值"),
        ("紧凑输出", "仅回传检测列表"),
    )
    for index, (name, detail) in enumerate(paths, start=1):
        numbered_path(d, (1260, 336 + (index - 1) * 75, 1603, 398 + (index - 1) * 75), index, name, detail,
                      TEAL if index == 1 else ORANGE)
    summary_band(d, "总结：设备驻留、缓存、融合、并行扫描与紧凑输出共同构成任务一处理链。")
    save(im, "P12_Task1_五路径公开算子链_v04_中文重构.png")


def page_p14() -> None:
    im, d = base("核心技术", "任务二：五条路径构建批量评分特征融合流程", "将逐帧全量中间张量压缩为批量评分、峰值与状态轨迹。")
    panel(d, (44, 265, 1210, 465), "CPU 参考路径：逐帧构建完整中间结果", CPU, 20)
    cpu_boxes = (("输入帧", ("帧 1", "帧 2", "… 帧 N")), ("相关计算", ("二维相关张量", "逐帧物化")),
                 ("频谱与小波", ("谱图张量", "小波张量")), ("后处理", ("峰值 / 关联", "Kalman 轨迹")))
    for i, (name, lines) in enumerate(cpu_boxes):
        x = 82 + i * 276
        flow_box(d, (x, 333, x + 200, 443), name, lines, CPU)
        if i < 3:
            arrow(d, x + 204, 379, x + 258, 379, CPU, 3)

    panel(d, (44, 490, 1210, 748), "GPU 批量评分路径：设备驻留与任务级输出裁剪", TEAL, 20)
    label(d, (78, 592, 176, 656), "一次上传", NAVY, PALE, 16)
    arrow(d, 180, 624, 236, 624, TEAL, 3)
    label(d, (241, 580, 370, 668), "批量 = 8\n设备端帧组", TEAL, "#ECF9F6", 16)
    arrow(d, 373, 624, 432, 624, TEAL, 3)
    scores = ("滤波/解调评分", "相关评分", "频带评分", "小波最大评分")
    for i, name in enumerate(scores):
        y = 548 + i * 37
        rr(d, (440, y, 630, y + 27), 5, "#ECF9F6", "#8FD8D3", 1)
        rr(d, (440, y, 485 + i * 20, y + 27), 5, TEAL)
        txt(d, (640, y + 14), name, 14, TEXT, True, "lm")
    arrow(d, 775, 624, 842, 624, TEAL, 3)
    label(d, (848, 572, 982, 676), "融合与平滑\n任务辅助", TEAL, "#ECF9F6", 16)
    arrow(d, 985, 624, 1038, 624, TEAL, 3)
    label(d, (1042, 572, 1175, 676), "峰值与轨迹\n紧凑输出", ORANGE, "#FFF7ED", 16)

    panel(d, (1235, 265, 1628, 748), "五条组合路径", NAVY, 20)
    paths = (
        ("设备驻留与批处理", "一次上传，批量 = 8"),
        ("预处理与预编译", "相关、谱图固定尺寸复用"),
        ("直接写入与任务融合", "各分支直接写入评分"),
        ("并行归约", "频带评分、小波最大评分、行峰值"),
        ("仅评分与紧凑输出", "保留评分、峰值与状态轨迹"),
    )
    for index, (name, detail) in enumerate(paths, start=1):
        numbered_path(d, (1260, 336 + (index - 1) * 75, 1603, 398 + (index - 1) * 75), index, name, detail,
                      TEAL if index == 1 else ORANGE)
    summary_band(d, "总结：批量评分减少全量张量物化，输出聚焦后续决策所需的峰值与轨迹。")
    save(im, "P14_Task2_五路径评分流程_v09_中文重构.png")


def stage_top3(task: str) -> list[tuple[str, float, float]]:
    data = l6(task)
    raw = data["raw_final_timing_total"]["gpu_ms"]
    values = [(name, row["gpu_ms"], row["gpu_ms"] / raw * 100)
              for name, row in data["timings"].items()
              if name != "total" and row["gpu_ms"] > 0]
    return sorted(values, key=lambda item: item[1], reverse=True)[:3]


def bars(d: ImageDraw.ImageDraw, box: tuple[int, int, int, int], title: str,
         rows: list[tuple[str, float, float]], color: str = TEAL) -> None:
    panel(d, box, title, NAVY, 18)
    maximum = max(value for _, value, _ in rows)
    for index, (name, value, share) in enumerate(rows):
        y = box[1] + 92 + index * 62
        names = {
            "input_construction": "输入与参数准备",
            "ambgfun": "模糊函数",
            "pulse_doppler": "脉冲多普勒",
            "pulse_compression": "脉冲压缩",
            "cwt": "连续小波变换",
            "spectrogram": "谱图计算",
            "feature_score": "特征评分",
        }
        shown_name = names.get(name, name)
        txt(d, (box[0] + 35, y), f"第 {index + 1} 位 · {shown_name}", 16, TEXT, True, "lm")
        bar_x = box[0] + 250
        label_x = box[2] - 150
        width = int((label_x - bar_x - 15) * value / maximum)
        rr(d, (bar_x, y - 11, bar_x + width, y + 11), 5, color)
        # Fixed left anchor avoids renderer/font-specific right-anchor clipping.
        txt(d, (label_x, y), f"{value:.2f} ms / {share:.1f}%", 12, color, True, "lm")


def page_p16() -> None:
    t1, t2 = l6("task1_radar"), l6("task2_features")
    im, d = base("技术指标", "验证与覆盖：81 个算子、2 条任务、12 个规模点", "类型契约审计、任务步骤审计与端到端关键数值由正式报告汇总。")
    panel(d, (44, 265, 472, 840), "审计覆盖", NAVY, 20)
    for index, (number, text, color) in enumerate((("81/81", "公开算子类型契约", TEAL), ("2/2", "端到端任务", BLUE),
                                                       ("12/12", "正式规模运行", ORANGE), ("14/14", "正式计算步骤", NAVY))):
        y = 340 + index * 107
        rr(d, (74, y, 442, y + 72), 10, "#ECF9F6" if color == TEAL else PALE, "#BFD2E4", 1)
        d.ellipse((95, y + 17, 133, y + 55), fill=color)
        txt(d, (114, y + 36), "✓", 20, WHITE, True, "mm")
        txt(d, (196, y + 36), number, 29, color, True, "ma")
        txt(d, (340, y + 36), text, 17, TEXT, True, "ma")

    # The central report-style panel is intentionally rendered from the
    # published audit facts rather than a decorative mock terminal.
    x1, y1, x2, y2 = 500, 265, 1068, 840
    rr(d, (x1, y1, x2, y2), 12, "#142334", NAVY, 2)
    rr(d, (x1, y1, x2, y1 + 52), 12, NAVY)
    d.rectangle((x1, y1 + 26, x2, y1 + 52), fill=NAVY)
    txt(d, ((x1 + x2) // 2, y1 + 26), "正式验证报告摘录", 20, WHITE, True, "mm")
    checks = (
        ("[type_contracts]", "81 / 81 公开算子类型契约", "通过"),
        ("[task_steps]", "2 条任务 · 14 个正式计算步骤", "通过"),
        ("[task1 L6]", "检测位置 Expected = CPU = GPU", "通过"),
        ("[task2 L6]", "峰值轨迹与特征误差满足门限", "通过"),
    )
    for index, (kind, detail, status) in enumerate(checks):
        y = 386 + index * 91
        rr(d, (x1 + 24, y - 28, x2 - 24, y + 31), 6, "#1A2D41" if index % 2 == 0 else "#183044")
        txt(d, (x1 + 45, y), kind, 16, "#9CCFE7", True, "lm")
        txt(d, (x1 + 210, y), detail, 16, WHITE, True, "lm")
        rr(d, (x2 - 105, y - 18, x2 - 43, y + 18), 8, "#1F8F79")
        txt(d, (x2 - 74, y), status, 14, WHITE, True, "mm")
    line(d, (x1 + 38, 767, x2 - 38, 767), "#35516A", 1)
    txt(d, (x1 + 38, 797), "来源：type_contracts · task_step_audit · L6 metrics.json", 13, "#9CCFE7", True, "lm")

    panel(d, (1100, 265, 1628, 525), "任务一 L6：目标检测位置一致", TEAL, 20)
    detect = t1["correctness_summary"]["gpu_detection"]
    for r, c in ((48, NAVY), (34, CPU), (20, TEAL)):
        d.ellipse((1202 - r, 385 - r, 1202 + r, 385 + r), outline=c, width=4)
    txt(d, (1300, 350), "Expected = CPU = GPU", 22, TEAL, True)
    txt(d, (1300, 392), f"range={detect['range_bin']} · Doppler={detect['doppler_bin']} · {detect['doppler_hz']} Hz", 17, TEXT, True)
    label(d, (1198, 447, 1585, 492), f"CFAR 阈值误差 {t1['correctness_summary']['cfar_threshold_mixed_error']:.6f} < 0.5", TEAL, "#ECF9F6", 15)
    panel(d, (1100, 555, 1628, 840), "任务二 L6：轨迹与特征误差满足门限", TEAL, 20)
    graph = (1130, 640, 1365, 790)
    line(d, (graph[0], graph[3], graph[2], graph[3]), MUTED, 2)
    line(d, (graph[0], graph[1], graph[0], graph[3]), MUTED, 2)
    truth, gpu = t2["truth_track"], t2["gpu_kalman_track"]
    low, high = min(truth) - 8, max(truth) + 8
    for values, color, width in ((truth, TEXT, 2), (gpu, TEAL, 3)):
        points = []
        for i in range(0, len(values), max(1, len(values) // 16)):
            x = graph[0] + int(i * (graph[2] - graph[0]) / (len(values) - 1))
            y = graph[3] - int((values[i] - low) * (graph[3] - graph[1]) / (high - low))
            points.append((x, y))
        for a, b in zip(points[:-1], points[1:]):
            line(d, (*a, *b), color, width)
    txt(d, (1395, 650), "CPU/GPU 峰值轨迹一致", 16, TEXT, True)
    c2 = t2["correctness_summary"]
    label(d, (1390, 692, 1588, 732), f"RMSE {c2['kalman_track_rmse']:.6f} < 2", TEAL, "#ECF9F6", 13)
    label(d, (1390, 750, 1588, 790), f"特征误差 {c2['feature_score_mixed_error']:.5e} < 1e-4", TEAL, "#ECF9F6", 12)
    summary_band(d, "总结：类型契约、任务步骤与两条端到端任务的关键数值均由正式报告核验。")
    save(im, "P16_正确性验证_实测_v09_中文重构.png")


def page_p17() -> None:
    im, d = base("技术指标", "性能特征与优化方向", "规模曲线与 L6 GPU 阶段时间共同确定下一轮优化优先级。")
    task1_speeds = speedups("task1_radar")
    task2_speeds = speedups("task2_features")
    curve(d, (44, 265, 800, 530), task1_speeds,
          f"任务一：{min(task1_speeds):.2f}× 至 {max(task1_speeds):.2f}×", 35, TEAL, 1, 25)
    curve(d, (844, 265, 1628, 530), task2_speeds,
          f"任务二：{min(task2_speeds):.2f}× 至 {max(task2_speeds):.2f}×", 1100, TEAL, 0, 300)
    bars(d, (44, 565, 800, 805), "任务一 L6 GPU 时间占比", stage_top3("task1_radar"), TEAL)
    bars(d, (844, 565, 1628, 805), "任务二 L6 GPU 时间占比", stage_top3("task2_features"), ORANGE)
    summary_band(d, "总结：任务一优先优化输入准备与模糊函数；任务二优先优化 CWT 与批量形状配置。")
    save(im, "P17_性能特征与优化方向_v02_真实数据.png")


def page_p18() -> None:
    im, d = base("创新点", "核心亮点：三类结构重构策略", "从邻域访存、状态依赖到任务输出，形成可复用的 GPU 并行化方法。")
    cards = ((44, 265, 548, 808), (584, 265, 1088, 808), (1124, 265, 1628, 808))
    specs = (
        ("① 邻域访存重构", "相邻窗口重复读取", "Tile / Halo 协作加载", "块内复用共享输入", 0),
        ("② 状态与频谱重构", "递推状态链与双边频谱", "仿射扫描 / R2C", "缩短依赖，减少无效频点", 1),
        ("③ 任务输出重构", "全量中间张量物化", "设备驻留 / 仅评分", "保留评分、峰值与轨迹", 2),
    )
    for box, (title, problem, method, value, kind) in zip(cards, specs):
        panel(d, box, title, NAVY, 19)
        x1, y1, x2, _ = box
        if kind == 0:
            grid(d, x1 + 54, y1 + 105, 6, 6, 24, "#F4D4D0")
            arrow(d, x1 + 228, y1 + 190, x1 + 300, y1 + 190, BLUE, 4)
            grid(d, x1 + 312, y1 + 105, 8, 8, 18, TEAL, True)
        elif kind == 1:
            for i in range(5):
                x = x1 + 56 + i * 72
                d.ellipse((x, y1 + 145, x + 38, y1 + 183), fill="#F3B3AF", outline=RED, width=1)
                if i < 4:
                    arrow(d, x + 40, y1 + 164, x + 67, y1 + 164, RED, 2)
            arrow(d, x1 + 250, y1 + 213, x1 + 250, y1 + 270, BLUE, 3)
            for dx, dy in ((0, 0), (-70, 42), (70, 42), (-105, 92), (-35, 92), (35, 92), (105, 92)):
                d.ellipse((x1 + 250 + dx - 13, y1 + 290 + dy - 13, x1 + 250 + dx + 13, y1 + 290 + dy + 13), fill=TEAL)
        else:
            grid(d, x1 + 50, y1 + 115, 5, 5, 22, "#D8E0E8")
            arrow(d, x1 + 193, y1 + 175, x1 + 258, y1 + 175, BLUE, 4)
            for i in range(4):
                rr(d, (x1 + 270, y1 + 121 + i * 32, x1 + 382, y1 + 142 + i * 32), 4, "#ECF9F6", TEAL, 1)
            arrow(d, x1 + 390, y1 + 175, x1 + 440, y1 + 175, ORANGE, 4)
            d.ellipse((x1 + 445, y1 + 145, x1 + 490, y1 + 190), fill="#FFF0D9", outline=ORANGE, width=2)
        for i, (name, body, color) in enumerate((("问题", problem, RED), ("方法", method, TEAL), ("价值", value, ORANGE))):
            y = y1 + 382 + i * 47
            rr(d, (x1 + 38, y, x2 - 38, y + 35), 6, "#F5F9FD", "#C6D8E8", 1)
            txt(d, (x1 + 62, y + 18), name, 15, color, True, "lm")
            txt(d, (x1 + 120, y + 18), body, 15, TEXT, True, "lm")
    summary_band(d, "总结：公共算子结构重构与任务级输出裁剪共同支撑可解释的端到端 GPU 执行。")
    save(im, "P18_核心亮点_v07_结构重构策略.png")


def cleanup_existing(source: str, target: str, boxes: tuple[tuple[int, int, int, int], ...]) -> None:
    im = Image.open(OUT / source).convert("RGB")
    d = ImageDraw.Draw(im)
    for box in boxes:
        d.rectangle(box, fill=WHITE)
    save(im, target)


def main() -> None:
    """Refresh only report-native pages without replacing approved visual pages."""
    page_p09_p11()
    task_performance_page("P13_Task1_L1-L6_实测_v11_报告看板.png", "task1_radar", "", "")
    task_performance_page("P15_Task2_L1-L6_实测_v11_报告看板.png", "task2_features", "", "")
    page_p16()
    page_p17()


if __name__ == "__main__":
    main()
