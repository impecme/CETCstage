# CETC 文档索引

## 当前阶段

| 入口 | 用途 |
| --- | --- |
| `docs/performance/v5_0/README.md` | V5.1-V5.5 性能优化阶段索引、当前执行点和门禁 |
| `docs/performance/v5_0/agent_collaboration.md` | V5.0 性能优化阶段的智能体分工、协作流和验证流 |
| `docs/performance/v5_0/optimization_change_log.md` | V5.0 性能优化台账，记录优化措施、验证结果和待处理项 |
| `docs/performance/v5_0/operator_optimization_matrix.md` | 两任务依赖 27、核心 53、全库 81 的类型、接口、测试和性能契约 |
| `docs/performance/v5_0/operator_contract_inventory.md` | 从测试注册表生成的 81 条算子真实路径和工作包状态 |
| `docs/performance/v5_0/operator_type_contracts.md` | 81 算子的输入输出类型、complex64 和整数数值策略 |
| `docs/performance/v5_0/platform_compatibility_matrix.md` | 三个复赛兼容表的覆盖摘要、状态口径和探针边界 |
| `docs/performance/v5_0/task_step_audit.md` | Task1/Task2 步骤公共化、计时和精度缺口审计 |

## 中科芯迁移基线

| 入口 | 用途 |
| --- | --- |
| `docs/migration/zhongkexin/README.md` | V4 中科芯迁移文档入口和阶段索引 |
| `docs/migration/zhongkexin/status.md` | 中科芯迁移当前完成状态 |
| `docs/migration/zhongkexin/change_log.md` | V4 迁移不兼容、修改和限制台账 |
| `docs/migration/zhongkexin/platform_notes.md` | 复赛说明文件中的平台约束摘要 |
| `docs/migration/zhongkexin/task_dependency_matrix.md` | V4.2 Task1/Task2 依赖算子矩阵 |
| `docs/migration/zhongkexin/full_operator_matrix.md` | V4.3 全量公开算子矩阵 |
| `docs/migration/zhongkexin/plans/` | V4.0-V4.8 阶段计划归档 |

## 交付材料

| 入口 | 用途 |
| --- | --- |
| `docs/submission/technical_document_framework_final.md` | 当前主技术文档 |
| `docs/submission/READMEV5_0.md` | V5 全算子库性能优化总交付文档 |
| `docs/submission/READMEV*.md` | 各历史版本交付说明 |
| `docs/submission/figures/` | 技术文档和 PPT 图件 |

## 历史计划

| 入口 | 用途 |
| --- | --- |
| `docs/archive/version_plans/v2/` | V2.x 模块接入和测试体系历史计划 |
| `docs/archive/version_plans/v3/` | V3.x 任务 demo 历史计划 |

## 维护规则

- 当前性能优化按 `docs/performance/v5_0/README.md` 的阶段门禁推进，新增记录写入 `docs/performance/v5_0/optimization_change_log.md`。
- V4 迁移基线只在发现迁移遗留问题时更新 `docs/migration/zhongkexin/change_log.md`。
- 历史计划默认只读归档，不再作为当前执行入口。
- 临时容器日志、一次性调试日志和 benchmark 产物不放入 `docs/`；需要留证时放在 `data/reports/` 或对应阶段台账中记录路径。
