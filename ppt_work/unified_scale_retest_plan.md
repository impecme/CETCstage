# 统一 L1–L6 复测协议与数据页填表规则

## 决策

正式答辩不再并列展示旧 `scales/L1…L6` 与独立 `final-input`。

- 新 **L6** 使用原 `final-input` 的任务配置作为验收配置。
- 新 **L1–L5** 与 L6 使用同一算法路径、分块/批处理策略、阈值、窗口和验证门限；只改变输入数据规模。
- 旧 2026-07-20 task scale/final 数据仅留在审计材料中，不进入正式任务性能页。
- 81 算子的单位 benchmark 与任务 L1–L6 是两套不同口径；前者可保留在 P15，后者必须重测。

## 固定配置（新 L6 的基准）

| 任务 | 固定算法与验证配置 | 只允许随 L1–L6 改变的量 |
|---|---|---|
| Task1 雷达检测 | `fs=1 MHz`、`prf=2000`、Hann Doppler 窗、CFAR `guard=[2,2]`、`reference=[8,8]`、`pfa=0.001`、相同公开算子链、相同检测语义与误差门限 | 输入脉冲数、每脉冲采样数，以及与输入长度一致的任务尺寸；L6 对齐原 `final-input` 的 `[128,4096]` |
| Task2 特征融合与跟踪 | Device-resident、`B=8` batch、score-only 输出、同一 filter/spectrogram/CWT/peak/Kalman 路径，`peak_order=8`、Kalman RMSE 门限 `<2` | 帧数和每帧输入长度；L6 对齐原 `final-input` 的 `[128,3072]` |

“分块、阈值等参数”本身的进一步调优属于 P17 改进方向；在本轮统一 L1–L6 性能测量中必须先冻结，避免同时改变规模与算法参数导致曲线不可解释。

## 新数据落盘约定

建议不要覆盖旧快照，使用下列新目录：

```text
data/reports/demo/task1_radar/unified_scales/L1/metrics.json
…
data/reports/demo/task1_radar/unified_scales/L6/metrics.json
data/reports/demo/task2_features/unified_scales/L1/metrics.json
…
data/reports/demo/task2_features/unified_scales/L6/metrics.json
```

每个 `metrics.json` 至少记录：`scenario`、`shapes`、`timings.total.cpu_ms`、`timings.total.gpu_ms`、`timings.total.gpu_kernel_ms`、任务正确性字段、`repeat_runs`。表格中的加速比固定按：

```text
speedup = timings.total.cpu_ms / timings.total.gpu_ms
```

不得由 PPT 人工相除；重测报告或导出脚本必须直接写入该列。

## 数据页填充位置

| 页面 | 新数据槽位 | 复测后填入内容 |
|---|---|---|
| P09 | Task1 L1–L6 曲线、L6 CPU/GPU 时间、L6 检测与误差 | 6 个已计算加速比；L6 时间；Expected/CPU/GPU 一致与 CFAR 误差 |
| P11 | Task2 L1–L6 曲线、L6 CPU/GPU 时间、L6 轨迹与误差 | 6 个已计算加速比；L6 时间；track RMSE、feature-score error |
| P14 | 新 L6 两任务正确性门禁 | Task1 检测位置/阈值；Task2 轨迹/特征误差；PASS/FAIL |
| P16 | 两任务 L1–L6 曲线、L6 GPU 时间 Top3 | 规模趋势和每个任务最主要耗时步骤 |
| P17 | 分块/阈值调优方向 | 固定统一协议后，对 block/halo、CFAR 阈值、batch/shape 的独立 A/B 结果 |

## 本轮交付边界

本轮只留下可直接填充的新页面和 CSV 模板；**不**把旧独立 `final-input` 的 `34.20×`、`1071.70×` 或旧 L1–L6 曲线伪装成新统一曲线。新数据必须由重新运行后生成的 JSON 填入。
