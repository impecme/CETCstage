# 中科芯平台迁移计划索引

## 文档定位

本文档是中科芯平台迁移计划的入口索引。完整迁移计划已经按新的 V4 大版本拆分为一个总蓝图和五个阶段计划。

当前迁移不是只完成 `task1_radar_demo` 和 `task2_features_demo`，而是以整个 CETC 项目完整迁移到中科芯 CUDA 兼容平台为总目标。当前正在推进的是 V4.1 第一阶段。

## V4 文档结构

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `docs/design/V4_0_plan.md` | V4.0 中科芯平台全项目迁移总蓝图 | 总纲 |
| `docs/design/V4_1_plan.md` | V4.1 第一阶段：平台打通与 Task1/Task2 任务级验证 | 当前阶段 |
| `docs/design/V4_2_plan.md` | V4.2 第二阶段：Task1/Task2 依赖算子闭环 | 后续阶段 |
| `docs/design/V4_3_plan.md` | V4.3 第三阶段：全量公开算子迁移 | 后续阶段 |
| `docs/design/V4_4_plan.md` | V4.4 第四阶段：性能、资源与稳定性收敛 | 后续阶段 |
| `docs/design/V4_5_plan.md` | V4.5 第五阶段：交付固化 | 后续阶段 |
| `docs/design/zhongkexin_migration_status.md` | 中科芯平台迁移状态 | 持续更新 |
| `docs/design/zhongkexin_rematch_notes.md` | 复赛说明文件解读 | 迁移依据 |
| `docs/design/zhongkexin_migration_change_log.md` | 不兼容与修改台账 | 持续更新 |

## 当前执行入口

当前只执行 V4.1 第一阶段：

```bash
source /zq500/sdk/env.sh
dlsmi
scripts/platform/probe_zhongkexin.sh
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3
```

V4.1 完成后，只能说明“平台路径打通，Task1/Task2 默认任务级 correctness 通过”，不能标记为“全项目迁移完成”。全项目完成还需要继续执行 V4.2 至 V4.5。
