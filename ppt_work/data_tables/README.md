# PPT 数据表口径说明

## 可直接用于 P15 的全库表

`operator_performance_81.csv` 覆盖 81/81 个公开算子。每行都直接给出：CPU median、GPU E2E median 和由导出脚本计算的 `CPU/GPU` 加速比，不需要在 PPT 或答辩现场二次相除。

- 78 个 `case_detail` 来自 73 个算子；其中 69 个 case 大于 1×、9 个不大于 1×。
- 另有 8 个算子只提供 `summary_aggregate`；它们仍包含在 81 行总表中，但不进入 detailed-case 排名图。

## 正式 L1–L6 实测表

`task_scaling.csv`、`l6_correctness.csv` 和 `l6_hotspots.csv` 是 P09、P11、P14、P16 的正式数据源；每个速度列均已由导出器计算，不需要在 PPT 二次相除。

- 新 L6 使用原 `final-input` 配置。
- L1–L5 固定算法路径、分块/批处理、阈值、窗口和正确性门限，只改变输入规模。
- 数据来自 ZQ500 `final_l1_l6_v1` 实测，7 次运行、首轮 warm-up 排除，CPU/GPU total 取其余 6 次中位数。
- 正式报告落盘为 `data/reports/demo/task{1,2}_*/scales/L1…L6/metrics.json`，每个 metrics 记录 raw SHA-256、重复样本、P95、正确性门禁和直接加速比。
- 加速比由导出脚本直接写入：`speedup = CPU total median (ms) / GPU total median (ms)`。

旧 `task1_timing_speedup.csv`、`task2_timing_speedup.csv`、`correctness_metrics.csv` 和 `final_gpu_hotspots.csv` 是 2026-07-20 审计快照材料，已移至仓库外备份，不能回填正式 L1–L6 数据页。
