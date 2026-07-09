# V6 性能优化计划索引

## 当前目标

V6 从 V5 的全库迁移、类型兼容和全量验收中独立出来，单独面向任务优先性能优化。

第六版目标：

- 强化优化 Task1/Task2 端到端性能，目标不低于 V5.5 的 35%-65% 级下降。
- 深度优化两任务直接相关算子，优先处理 `spectrogram/cwt/correlate/filter/ambgfun/CFAR/FFT` 链路。
- 轻度优化赛题中提到的算子库。
- 原 cuSignal 中存在、但赛题未提到且不影响任务链路的算子，暂不做进一步性能优化。
- 优化策略同时参考开源实现和论文，候选措施必须先通过 ZQ500 平台探针和台账记录。

## 阶段入口

| 阶段 | 计划 | 状态 | 关闭门禁 |
| --- | --- | --- | --- |
| V6.0 | `plans/V6_0_plan.md` | 规划中 | V6 总体目标、范围、论文/开源策略和验证阶梯明确 |
| V6.1 | `plans/V6_1_plan.md` | 待分析 | Task1/Task2 L1-L6 基线、平台探针、all81 当前基线和热点排序明确 |
| V6.2 | `plans/V6_2_plan.md` | 待开始 | Task2 `spectrogram + cwt + correlate` 第一批收益关闭 |
| V6.3 | `plans/V6_3_plan.md` | 待开始 | Task2 `filter/demod/fusion/kalman` 第二批收益关闭 |
| V6.4 | `plans/V6_4_plan.md` | 待开始 | Task1 `pulse_compression/pulse_doppler/ca_cfar` device-resident 链路关闭 |
| V6.5 | `plans/V6_5_plan.md` | 待开始 | Task1 `ambgfun` 算法评估和 `mvdr` 深化关闭 |
| V6.6 | `plans/V6_6_plan.md` | 待开始 | 任务相关算子库 P1 深化关闭 |
| V6.7 | `plans/V6_7_plan.md` | 待开始 | 赛题算子库 P2 轻度优化关闭 |
| V6.8 | `plans/V6_8_plan.md` | 待开始 | all81、dtype、Task1/Task2 和报告收束关闭 |

## 台账入口

| 文档 | 用途 |
|---|---|
| `optimization_change_log.md` | V6 来源调研、候选方案、实际改动、验证结果和回退记录 |
| `plans/V6_0_plan.md` | V6 强化目标、P0/P1/P2 范围、任务与算子深度优化工作包 |
| `plans/V6_1_plan.md` 至 `plans/V6_8_plan.md` | V6 小版本执行计划、命令、回传材料和关闭条件 |

## 执行规则

- V6 报告、计划和台账后续写入 `docs/performance/v6_0/`，不再追加到 V5 目录。
- V5.5 交付结论只作为基线引用，不继续在 V5 目录中记录第六版执行过程。
- 中间日志、完整图件和容器取回缓存仍放在仓库外 `/home/usr_04/CETC_garbage/`。
