# V6 性能优化计划索引

## 当前目标

V6 从 V5 的全库迁移、类型兼容和全量验收中独立出来，单独面向任务优先性能优化。

第六版目标：

- 强化优化 Task1/Task2 端到端性能；最终收益以 V6.1 同源码、同规模基线为分母，不再用 V5.5 L3 任务报告推算 L6。
- 深度优化两任务直接相关算子；当前保留版 Task2 热点顺序为 `cwt/filter/spectrogram/correlate`，Task1 已完成 `pulse_compression/pulse_doppler/CFAR/ambgfun` 主线深化。
- 轻度优化赛题中提到的算子库。
- 原 cuSignal 中存在、但赛题未提到且不影响任务链路的算子，暂不做进一步性能优化。
- 优化策略同时参考开源实现和论文，候选措施必须先通过 ZQ500 平台探针和台账记录。

## 阶段入口

| 阶段 | 计划 | 交付文件 | 状态 | 关闭门禁 |
| --- | --- | --- | --- | --- |
| V6.0 | `plans/V6_0_plan.md` | `../../submission/READMEV6_0.md` | 规划已复核 | V6 总体目标、范围、量化预算、论文/开源策略和验证阶梯明确 |
| V6.1 | `plans/V6_1_plan.md` | `../../submission/READMEV6_1.md` | 已关闭 | Task1/Task2 基线、all81、dtype、14 步、Release、device/stream/FFT 和 manifest 已关闭；V6-0098 有效生命周期确认 CUDA Graph 六阶段均成功 |
| V6.2 | `plans/V6_2_plan.md` | `../../submission/READMEV6_2.md` | 已技术收束 | 保留 CWT/correlate，L6 累计下降 29.69%；距 30%目标差 0.31 个百分点，spectrogram/CWT 候选按止损停止 |
| V6.3 | `plans/V6_3_plan.md` | `../../submission/READMEV6_3.md` | 已技术收束 | 保留公共 FIR shared-halo；fusion 与双流未达门禁，多 stream 对重计算分支结论为 limited |
| V6.4 | `plans/V6_4_plan.md` | `../../submission/READMEV6_4.md` | 已技术收束 | 保留六项 Task1 优化；L6 累计下降 18.87%，未虚报 20%，连续反向候选已止损 |
| V6.5 | `plans/V6_5_plan.md` | `../../submission/READMEV6_5.md` | 已关闭 | Task1 L6 累计下降 41.14%；公共 `ambgfun` 扩容回退；公共 `mvdr` E2E 下降 78.41% |
| V6.6 | `plans/V6_6_plan.md` | `../../submission/READMEV6_6.md` | 已关闭 | V6-0098 当前保留源码关闭包通过：七项矩阵全绿、all81 `81/81`、dtype/步骤缺口 0、双任务 L1-L6 与 manifest 通过 |
| V6.7 | `plans/V6_7_plan.md` | `../../submission/READMEV6_7.md` | 已关闭 | V6-0134 增采样确认 E2E/kernel 下降 30.64%/4.04%，原 `4/5` kernel 稳定门、all81、dtype、14 步、双任务和 manifest 全部通过 |
| V6.8 | `plans/V6_8_plan.md` | `../../submission/READMEV6_8.md` | 已关闭 | V6-0138 硬门、V6-0141 的 486/486 性能终测和 V6-0142 最终报告收束全部通过；V6 最终交付完成 |

## 台账入口

| 文档 | 用途 |
|---|---|
| `agent_collaboration.md` | V6 动态角色、文件所有权、Skill 路由、双轴审查和 `gpu_04` 串行测量规则 |
| `performance_audit.md` | V6 全项目热点、结构性固定开销、Amdahl 预算和版本路线审计 |
| `optimization_change_log.md` | V6 来源调研、候选方案、实际改动、验证结果和回退记录 |
| `plans/V6_0_plan.md` | V6 强化目标、P0/P1/P2 范围、任务与算子深度优化工作包 |
| `plans/V6_1_plan.md` 至 `plans/V6_8_plan.md` | V6 小版本执行计划、命令、回传材料和关闭条件 |

## 执行规则

- V6 报告、计划和台账后续写入 `docs/performance/v6_0/`，不再追加到 V5 目录。
- 每个 V6.x 小版本同步维护 `docs/submission/READMEV6_x.md`；计划、台账和交付文件三者状态必须一致。
- 小版本交付文件必须列出保留项、回退项、性能对照、correctness 和仓库外证据路径；未关闭阶段不得预写通过结论。
- V5.5 交付结论只作为基线引用，不继续在 V5 目录中记录第六版执行过程。
- 中间日志、完整图件和容器取回缓存仍放在仓库外 `/home/usr_04/CETC_garbage/`。
- correctness 未通过时不得登记性能收益；每个日志包必须包含 stderr、真实退出码、源码 SHA 和编译信息。
- 协作采用“主智能体单一落地、阶段 Owner 分析、证据守门验收、Review Pair 临时审查”；辅助智能体默认只读。
- `gpu_04` 是全局串行测量资源；同一时刻只运行一个正式 probe/benchmark，详细规则见 `agent_collaboration.md`。
