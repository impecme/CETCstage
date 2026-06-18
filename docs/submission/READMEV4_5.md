# V4.5 中科芯第五阶段交付文档

## 版本信息

- 版本名称：`V4.5 交付固化`
- 当前日期：`2026-06-18`
- 当前状态：已完成
- 对应计划：`docs/design/V4_5_plan.md`
- 修改台账：`docs/design/zhongkexin_migration_change_log.md`

## 版本目标

V4.5 在 V4.1-V4.4 均已按阶段范围关闭后，负责把中科芯迁移固化为可交付、可复现、可维护的项目状态。当前交付验收口径为 CPU reference + 容器内中科芯 ZQ500 GPU；不再要求 NVIDIA 路径作为阶段关闭条件。

## 进入依据

- V4.1 已完成平台打通、Task1/Task2 L3、Python 依赖和可视化图件闭环。
- V4.2 已完成 29/29 Task1/Task2 依赖算子、Task1/Task2 L1-L6、报告和图件闭环。
- V4.3 已完成 12/12 模块、81/81 active 算子 accuracy 闭环。
- V4.4 已完成 Stage4 full：Task1/Task2 L1-L6 12/12 行通过，81 个算子、486/486 行 benchmark 通过，benchmark 图件生成通过。

## 当前基线

| 范围 | 当前结论 | 证据 |
| --- | --- | --- |
| Stage1 | 已通过 | `stage1.log`、`docs/submission/READMEV4_1.md` |
| Stage2 | 已通过 | `data/reports/zhongkexin/stage2_runs/20260617_full/` |
| Stage3 | 已通过 | `data/reports/zhongkexin/stage3_runs/20260617_110827/` |
| Stage4 | 已通过 | `data/reports/zhongkexin/stage4_full_latest/` |
| Full benchmark | 486/486 通过 | `data/reports/unit/benchmarks/zhongkexin_stage4_full/latest_all_ops_scale_benchmark.csv` |
| Benchmark figures | 已生成 | `data/reports/unit/benchmarks/zhongkexin_stage4_full/figures/` |

## V4.5 固化内容

- README 已保留最方便的一版中科芯复现命令。
- AGENT 已保留中科芯迁移约束、禁止读取错误 SDK 目录、容器同步与验证入口。
- 迁移状态文档已更新到 V4.5 完成状态。
- 变更台账已确认无实际未归属 `待确认` 或 `待修改` 项；状态枚举和模板中的示例不计入未关闭项。
- 最终报告已明确平台限制、性能 baseline、图件和报告产物位置。
- 从零复现路径已覆盖依赖准备、构建、Stage1-Stage4 验证、报告和图件生成。

## 当前推荐复现命令

容器内执行：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

## 完成判定

- README、AGENT、V4 计划、迁移状态和迁移台账一致。
- 最终交付文档可独立说明如何复现构建、验证、报告和图件。
- 所有保留的中科芯平台限制或性能偏慢项已有明确说明。
- 所有阶段交付文档已按版本而不是容器轮次记录核心改动和验证结果。
- 2026-06-18 容器复验 Stage4 full 再次 PASS，脚本版本 `diagnostics-20260617-stage4-perf-full-v4`，486/486 benchmark 通过，图件生成通过。
