# 中科芯平台迁移计划索引

## 文档定位

本文档是中科芯平台迁移计划的入口索引。完整迁移计划已经按 V4 大版本拆分为一个总蓝图和八个阶段计划，当前均已完成并归档。

迁移目标不是只完成 `task1_radar_demo` 和 `task2_features_demo`，而是以整个 CETC 项目完整迁移到中科芯 ZQ500 兼容平台为总目标。当前项目已经形成 CPU reference + 中科芯 ZQ500 GPU 的完整交付基线；后续性能优化记录已转入 `docs/performance/v5_0/`。

## V4 文档结构

| 文件 | 内容 | 状态 |
| --- | --- | --- |
| `docs/migration/zhongkexin/plans/V4_0_plan.md` | V4.0 中科芯平台全项目迁移总蓝图 | 总纲 |
| `docs/migration/zhongkexin/plans/V4_1_plan.md` | V4.1 第一阶段：平台打通与 Task1/Task2 任务级验证 | 已完成 |
| `docs/migration/zhongkexin/plans/V4_2_plan.md` | V4.2 第二阶段：Task1/Task2 依赖算子闭环 | 已完成 |
| `docs/migration/zhongkexin/plans/V4_3_plan.md` | V4.3 第三阶段：全量公开算子迁移 | 已完成 |
| `docs/migration/zhongkexin/plans/V4_4_plan.md` | V4.4 第四阶段：性能、资源与稳定性收敛 | 已完成 |
| `docs/migration/zhongkexin/plans/V4_5_plan.md` | V4.5 第五阶段：交付固化 | 已完成 |
| `docs/migration/zhongkexin/plans/V4_6_plan.md` | V4.6 第六阶段：中科芯专用命名收口 | 已完成 |
| `docs/migration/zhongkexin/plans/V4_7_plan.md` | V4.7 第七阶段：低风险 CUDA 遗留表述收口 | 已完成 |
| `docs/migration/zhongkexin/plans/V4_8_plan.md` | V4.8 第八阶段：报告 schema 中性化 | 已完成 |
| `docs/migration/zhongkexin/status.md` | 中科芯平台迁移状态 | 已完成，按需维护 |
| `docs/migration/zhongkexin/platform_notes.md` | 复赛说明文件解读 | 迁移依据 |
| `docs/migration/zhongkexin/change_log.md` | 不兼容与修改台账 | 持续更新 |

## 基线复验入口

迁移基线复验使用 Stage4 统一入口：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

V5.0 性能优化阶段不继续写入迁移台账，除非发现 V4 迁移基线本身存在遗留问题。
