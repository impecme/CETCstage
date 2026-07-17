# V6.0 任务优先性能优化总交付文档

## 版本信息

- 当前状态：已关闭；V6-0138 硬门、V6-0141 性能终测和 V6-0142 最终
  汇总全部通过。
- 总计划：`docs/performance/v6_0/plans/V6_0_plan.md`。
- 优化台账：`docs/performance/v6_0/optimization_change_log.md`。
- 性能审计：`docs/performance/v6_0/performance_audit.md`。
- 最终交付：`docs/submission/READMEV6_8.md`。

## 小版本交付

| 阶段 | 交付文件 | 状态 |
| --- | --- | --- |
| V6.1 基线与平台探针 | `READMEV6_1.md` | 已关闭 |
| V6.2 Task2 主热点第一批 | `READMEV6_2.md` | 已技术收束 |
| V6.3 Task2 链路第二批 | `READMEV6_3.md` | 已技术收束 |
| V6.4 Task1 第一批 | `READMEV6_4.md` | 已技术收束 |
| V6.5 Task1 收口与公共 radartools | `READMEV6_5.md` | 已关闭 |
| V6.6 内部执行基础设施 | `READMEV6_6.md` | 已关闭 |
| V6.7 赛题算子库轻度优化 | `READMEV6_7.md` | 已关闭 |
| V6.8 全量回归与报告收束 | `READMEV6_8.md` | 已关闭 |

## 交付规则

- 每个 V6.x 小版本必须维护对应的 `docs/submission/READMEV6_x.md`。
- 每次小版本状态、保留优化或关闭结论变化时，同步更新计划、台账和交付文件。
- 小版本关闭前，交付文件必须写明范围、保留项、回退项、性能对照、correctness、证据路径和下一阶段。
- 未关闭阶段只写已验证事实和待交付门禁，不预写通过结论。
- 中间日志、probe、图件和容器归档只放 `/home/usr_04/CETC_garbage/`；`data/reports/` 只保留 V6.8 终测汇总。

## 总关闭条件

- all81 correctness `81/81`，dtype 缺口 0。
- Task1/Task2 共 14 个计算步骤保持独立计时和精度验证。
- V5.5 公共 API、类型和报告 schema 不破坏。
- Task1/Task2 最终收益使用 V6.1 同源码、同规模基线。
- V6.1-V6.8 交付文件与台账结论一致。

上述关闭条件均已满足，最终证据和报告路径见 `READMEV6_8.md`。
