# 答辩 PPT 技术证据索引（当前口径）

本索引只指向当前代码、当前合同和当前报告路径；历史性能与旧 PPT 草稿已归档到 `docs/history/`，不作为当前运行口径。

## 1. 当前覆盖口径

| 集合 | 数量 | 定义 | 权威来源 |
|---|---:|---|---|
| `all81` | 81 | 全部注册公开算子 | `tests/contracts/operator_sets.json`、`scripts/performance.sh --operators --operator-set all81` |
| `task_appendix` | 53 | `算子表.xlsx` 的全部唯一算子 | `算子表.xlsx`、合同审计 |
| `task_used` | 27 | 两条任务采用的赛题范围算子 | `tests/contracts/operator_sets.json`、任务链代码 |
| `appendix_only` | 26 | 赛题表中任务未采用的其余算子 | 合同派生集合 |
| `native_only` | 28 | 原生库中不在赛题表的算子 | 合同派生集合 |

集合关系：`task_used + appendix_only = task_appendix = 53`；`task_used + appendix_only + native_only = all81 = 81`。任务私有 helper（如 `power_map`、`detect_peak`、`pulse_doppler_shifted`）只记录在任务步骤契约，不重复计入 81 个公开算子。

## 2. PPT 数据入口

| PPT 内容 | 当前数据入口 | 展示口径 |
|---|---|---|
| 单算子分层性能 | `data/reports/units/benchmarks/operator_scales.{json,csv,md}` | 81 个算子 × L1–L6，共 486 行；CPU/GPU E2E、GPU kernel、两种加速比、PASS |
| 单算子常规汇总 | `data/reports/units/benchmarks/summary.{json,csv}` | 每个算子的正式 performance case |
| Task1 L1–L6 | `data/reports/demo/task1_radar/scales/L1…L6/metrics.json` | CPU total、GPU total、GPU kernel、CPU/GPU 加速比、验证状态 |
| Task2 L1–L6 | `data/reports/demo/task2_features/scales/L1…L6/metrics.json` | 同上 |
| 任务步骤与误差 | `data/reports/validation/task_steps/`、两任务 `metrics.json` | 步骤覆盖、误差阈值、关键输出一致性 |
| 覆盖与类型审计 | `data/reports/validation/operator_sets.json`、`type_contracts/` | 集合、接口和类型门禁 |

## 3. 计时口径

- CPU E2E：输入构造 + CPU 计算 + 最终输出物化。
- GPU E2E：每次重新构造输入 + H2D + GPU 执行 + 最终输出物化；多算子任务内部保持 Device 驻留，仅在任务边界按需回传。
- GPU kernel：GPU event 包围的设备工作时间，不包含 H2D；复合任务步骤统计该步骤实际调用的算子与 helper 的设备工作。
- 中位数：排除 warm-up 后对重复运行取 median；加速比直接记录为 `CPU total / GPU total`，不把 CPU/GPU 加速比写成 GPU 优化前后倍率。
- GPU 优化前后倍率当前统一保留 `X×`，只有同规模 Git 基线复测后才能替换。

## 4. 现场演示入口

```bash
scripts/performance.sh --operators --operator-set task_appendix --scale all
scripts/performance.sh --tasks --task both --scale all
```

现场 53 项按 `task_used=27` 与 `appendix_only=26` 展示；三层性能页再补充 `native_only=28`，完整覆盖 81 个公开算子。

## 5. 历史资料

历史台账、版本记录、冻结性能和旧 PPT 审计均位于 `docs/history/`；可用于提取有明确 before/after 数据的优化亮点，但不参与当前构建、当前报告和容器同步。
