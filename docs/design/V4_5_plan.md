# V4.5 第五阶段：交付固化

## Summary

- 本阶段已把已经完成的中科芯迁移固化成可交付、可复现、可维护的项目状态。
- 目标是让新环境、新会话或新的维护者可以按文档从零完成配置、构建、测试和报告复现。
- 本阶段必须固化全部项目功能，而不是只固化核心构建命令；从零复现应覆盖 demo、单测、数据生成、报告、图件、benchmark 和已知限制说明。

## 进入条件

- V4.4 完整功能闭环已完成。
- 中科芯 correctness、全量测试、性能/resource/timing 口径均已稳定，或剩余问题已经作为已知限制记录。
- `docs/design/zhongkexin_migration_change_log.md` 中没有无归属的 `待确认` 或 `待修改` 项。

## Scope

覆盖范围：

- README。
- AGENT。
- 迁移总蓝图和阶段计划。
- 迁移状态文档。
- 平台操作说明。
- 测试和报告复现说明。
- Python 依赖、可视化图件和 benchmark 图件复现说明。
- 最终风险清单和已知限制。

## Key Changes

### 0. 台账关闭

- 清点 `docs/design/zhongkexin_migration_change_log.md`。
- 所有记录必须处于 `已关闭`、`暂缓` 或有明确后续维护阶段的状态。
- 交付文档必须能解释所有保留 fallback、跳过项和平台限制。

### 1. 文档固化

- README 保留用户入口和中科芯快速验证命令。
- AGENT 保留给 Codex 的项目约束、平台约束、验证命令和禁止事项。
- `docs/design/V4_0_plan.md` 作为总蓝图。
- `docs/design/V4_1_plan.md` 至 `docs/design/V4_5_plan.md` 保留阶段执行计划。
- `docs/design/zhongkexin_migration_status.md` 保留最新状态。
- `docs/design/zhongkexin_migration_change_log.md` 保留最终不兼容、修改和限制台账。

### 2. 操作流程固化

- 固化从 Windows VPN 到 SSH、docker、SDK 初始化、构建、测试的完整链路。
- 明确当前服务器本队容器名为 `gpu_04`，并保留 `sudo docker ps -a` 作为状态确认命令。
- 明确统一平台脚本会自动执行兼容形式的 SDK 初始化；运行脚本前不要手动 source SDK。
- 明确宿主机只做文件中转，不在宿主机直接构建运行。

### 3. 验证流程固化

- 固化中科芯第一阶段验证。
- 固化全量算子测试。
- 固化 benchmark 和报告生成。
- 固化 demo 可视化图件、scale 图件和全量 benchmark 图件生成。
- 固化失败项记录格式。

### 4. 交付风险关闭

- 清理临时 fallback 或记录保留理由。
- 清理无用 build 产物和临时探测目录。
- 确认 `.gitignore` 覆盖本地 build/report 临时产物。
- 对仍未解决的平台限制给出明确说明。

## Test Plan

从零复现：

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

- 已满足。新环境可以按 README/AGENT 完成构建、验证、报告和图件生成。
- 已满足。总蓝图、阶段计划和状态文档一致。
- 已满足。中科芯路径有明确回归命令；CPU reference + 容器内 ZQ500 GPU 为当前交付验收口径。
- 已满足。已知限制、跳过项和 fallback 都有记录。
- 已满足。Python 依赖准备、demo 图件、scale 图件和 benchmark 图件复现路径完整。
- 已满足。项目可交付，无需依赖当前 Codex 会话上下文理解迁移状态。
- 已满足。`docs/design/zhongkexin_migration_change_log.md` 无遗漏项，所有记录都有状态和处理结论。
