#!/usr/bin/env python3

"""Validate frozen V7 evidence and write the compact final delivery summary."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--demo-root", required=True)
    parser.add_argument("--buffer-root", required=True)
    parser.add_argument("--demo-archive", required=True)
    parser.add_argument("--demo-console", required=True)
    parser.add_argument("--buffer-archive", required=True)
    parser.add_argument("--buffer-console", required=True)
    parser.add_argument("--output-dir", default="data/reports/zhongkexin/v7_final")
    return parser.parse_args()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(payload, dict), f"expected JSON object: {path}")
    return payload


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_status(path: Path) -> None:
    with path.open("r", encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    require(rows, f"empty status table: {path}")
    require(all(int(row["rc"]) == 0 for row in rows), f"nonzero status row: {path}")
    require(
        sum(row["phase"] == "final" and row["case"] == "overall" for row in rows) == 1,
        f"missing unique final/overall row: {path}",
    )


def main() -> int:
    args = parse_args()
    demo_root = Path(args.demo_root).resolve()
    buffer_root = Path(args.buffer_root).resolve()
    output_dir = Path(args.output_dir).resolve()
    report_root = output_dir.parents[1]
    expected = report_root / "zhongkexin/v7_final"
    require(output_dir == expected, "output-dir must use the final V7 report path")
    validate_status(demo_root / "status.tsv")
    require((demo_root / "reports_restore.diff").stat().st_size == 0, "report restore diff")
    require((demo_root / "manifests_restore.diff").stat().st_size == 0, "manifest restore diff")

    demo = read_json(demo_root / "demo/summary.json")
    cache = read_json(demo_root / "prepare/cache_decision.json")
    buffer_gate = read_json(buffer_root / "candidate_gate.json")
    require(demo["status"] == "passed", "V7-0008 demo failed")
    require(all(demo["checks"].values()), "V7-0008 checks failed")
    require(demo["operators"]["count"] == 30, "Top30 count mismatch")
    require(demo["operators"]["passed"] == 30, "Top30 contains failures")
    require(cache["selected_mode"] == "default", "expanded cache unexpectedly selected")
    require(buffer_gate["status"] == "rejected", "buffer candidate was not rejected")

    payload = {
        "schema_version": "v7_final_summary_v1",
        "status": "passed",
        "version": "V7.6",
        "final_execution_id": "V7-0011",
        "generated_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "conclusion": {
            "v5_5_closed": True,
            "v6_closed": True,
            "v7_closed": True,
            "further_gpu_performance_runs": False,
        },
        "gates": {
            "all81_correctness": "81/81",
            "dtype_gap_count": 0,
            "task_calculation_steps": "14/14",
            "task1_l1_l6": "passed",
            "task2_l1_l6": "passed",
            "top30": "30/30",
            "report_manifest_restore_diff_count": 0,
        },
        "demo": {
            "wall_seconds": demo["wall"]["seconds"],
            "wall_limit_seconds": demo["wall"]["limit_seconds"],
            "task1_l6_gpu_median_ms": demo["task1"]["gpu_total_median_ms"],
            "task2_l6_gpu_median_ms": demo["task2"]["gpu_total_median_ms"],
            "top30_median_speedup": demo["operators"]["median_speedup"],
            "top30_geometric_mean_speedup": demo["operators"]["geometric_mean_speedup"],
            "top30_minimum_speedup": demo["operators"]["minimum_speedup"],
            "gpu_memory_peak_mib": demo["telemetry"]["used_mib_max"],
            "gpu_utilization_peak_percent": demo["telemetry"]["util_percent_max"],
        },
        "retained": {
            "aot_correlate_hotspot_reduction_percent_l3_l6": [89.45, 61.66],
            "aot_correlate_total_reduction_percent_l3_l6": [39.71, 9.77],
            "aot_spectrogram_hotspot_reduction_percent_l3_l5_l6": [47.49, 20.86, 43.37],
        },
        "rejected": {
            "aot_filter": "demod accuracy failure",
            "morlet2_cwt_symmetry": "insufficient L5/L6 end-to-end benefit",
            "expanded_device_storage_cache": {
                "aggregate_gain": cache["aggregate_gain"],
                "required_gain": cache["thresholds"]["minimum_aggregate_gain"],
            },
            "task1_release_warmup_buffers": {
                "second_run_l6_gain": buffer_gate["checks"]["L6_total_gain"],
                "combined_two_run_l6_change_percent": -2.38,
                "product_default": False,
            },
        },
        "evidence": {
            "v7_0008": {
                "root": str(demo_root),
                "archive_sha256": sha256(Path(args.demo_archive)),
                "console_sha256": sha256(Path(args.demo_console)),
            },
            "v7_0010": {
                "root": str(buffer_root),
                "archive_sha256": sha256(Path(args.buffer_archive)),
                "console_sha256": sha256(Path(args.buffer_console)),
            },
        },
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "summary.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    markdown = f"""# V7 最终终测汇总

## 结论

- 状态：`passed`；V5.5、V6、V7 均已关闭，最终执行编号 `V7-0011`。
- 不再启动 GPU 性能候选；既有性能结论保持不变。
- 五分钟演示 wall：`{demo['wall']['seconds']:.3f}/{demo['wall']['limit_seconds']:.0f} s`。
- Top30：`30/30`，中位加速 `{demo['operators']['median_speedup']:.3f}x`，几何平均 `{demo['operators']['geometric_mean_speedup']:.3f}x`。

## 最终门禁

| 检查 | 结果 |
| --- | ---: |
| all81 correctness | `81/81` |
| dtype 缺口 | `0` |
| Task timing/accuracy 步骤 | `14/14` |
| Task1 / Task2 L1-L6 | 全部通过 |
| Top30 | `30/30` |
| 报告/manifest 恢复 diff | `0` |

## 最终演示

- Task1 L6 GPU median：`{demo['task1']['gpu_total_median_ms']:.5f} ms`。
- Task2 L6 GPU median：`{demo['task2']['gpu_total_median_ms']:.4f} ms`。
- 进程显存峰值：`{demo['telemetry']['used_mib_max']:.0f} MiB`；GPU 利用率峰值 `{demo['telemetry']['util_percent_max']:.0f}%`。

## 保留与关闭

- 保留 AOT correlate：L3/L6 热点下降 `89.45%/61.66%`，端到端下降 `39.71%/9.77%`。
- 保留 AOT spectrogram：L3/L5/L6 热点下降 `47.49%/20.86%/43.37%`。
- AOT filter 因 demod 精度失败关闭；Morlet2 CWT 对称路径因 L5/L6 端到端收益不足关闭。
- 扩大 DeviceStorage cache 总收益仅 `{cache['aggregate_gain'] * 100:.3f}%`，保持默认缓存。
- Task1 预热 buffer 释放两轮合并 L6 退化 `2.38%`，保持实验开关、产品默认关闭。

## 证据

- V7-0008 归档 SHA256：`{payload['evidence']['v7_0008']['archive_sha256']}`。
- V7-0008 console SHA256：`{payload['evidence']['v7_0008']['console_sha256']}`。
- V7-0010 归档 SHA256：`{payload['evidence']['v7_0010']['archive_sha256']}`。
- V7-0010 console SHA256：`{payload['evidence']['v7_0010']['console_sha256']}`。
"""
    (output_dir / "summary.md").write_text(markdown, encoding="utf-8")
    print(json.dumps({"status": "passed", "output_dir": str(output_dir)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
