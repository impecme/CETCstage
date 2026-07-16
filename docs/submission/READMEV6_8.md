# V6.8 全量回归与最终交付文档

## 版本信息

- 当前状态：进行中；V6-0139 首跑被旧 generated unit 样本阻断，V6-0140 已修复，V6-0141 已同步并待执行。
- 对应计划：`docs/performance/v6_0/plans/V6_8_plan.md`。
- 对应执行编号：V6-0136 至 V6-0142；当前台账已记录至 V6-0141。
- 进入条件：V6.2-V6.4 已技术收束，V6.5-V6.7 已关闭。

本文件是 V6 最终交付说明文件。当前只完成验收流程和报告结构，尚未生成
`v6_final` 终测结果，因此现在不代表 V6.8 已关闭。

## 关闭顺序

| 台账 ID | 内容 | 当前状态 |
| --- | --- | --- |
| V6-0136 | 首次命令执行 | 容器缺少脚本，测试未启动，已关闭 |
| V6-0137 | 静态门首跑 | 五类审计通过，注册表断言误计提示行，已关闭 |
| V6-0138 | correctness、契约、平台、任务 L1-L6 和目录治理预验收 | 全部通过，已关闭 |
| V6-0139 | all81 L1-L6 性能终测首跑 | generated unit 旧样本阻断，benchmark 未启动，已关闭 |
| V6-0140 | generated unit 清理与所有权修复 | 已实现、回放并同步 |
| V6-0141 | all81 L1-L6 最终性能与 GPU 占用终测 | 待容器重跑 |
| V6-0142 | 生成最终汇总、交付审计和 V6 关闭 | 未开始 |

## 最终交付门禁

| 项目 | 要求 |
| --- | --- |
| all81 correctness | `81/81` |
| 接口和类型 | 接口 81/81；兼容缺口 0；V5.5 API/type 不破坏 |
| dtype 覆盖 | `operator_dtype_missing_edges=0` |
| Task1/Task2 | L1-L6 共 24 个模式用例；14 步、168 条分步记录、failure count 0 |
| 任务统计 | 首次进程测量、warm repeat=5、median/P95、进程 wall、逐步骤精度和资源快照 |
| 算子性能 | all81 × L1-L6 共 486 行，warmup=5、repeat=30 |
| 平台 | compile/runtime/forbidden probes 无新增问题 |
| 完整性 | manifest 前后不变，源码和编译指纹完整 |
| 报告治理 | `data/reports/` 只保留 V5.5 与 V6 终测汇总 |

## 最终报告路径

- Markdown：`data/reports/zhongkexin/v6_final/summary.md`。
- JSON：`data/reports/zhongkexin/v6_final/summary.json`。
- 完整日志、长表和图件：`/home/usr_04/CETC_garbage/`。

## V6-0138 已确认结果

| 项目 | 结果 |
| --- | --- |
| all81 / 接口 / dtype | `81/81`；接口 `81/81`；兼容缺口 0；dtype 缺口 0 |
| 任务矩阵 | 24/24 用例、168/168 分步记录、12/12 schema，失败 0 |
| Task1 L6 | warm median `3.91998 ms`；相对 V6.1 下降 `45.48%` |
| Task2 L6 | warm median `25.2926 ms`；相对 V6.1 下降 `66.75%` |
| 平台 | Release `-O3 -DNDEBUG`；Graph 生命周期六项状态均为 0 |
| 完整性 | manifest diff 0；reports diff 0 |

证据：`/home/usr_04/CETC_garbage/cetc_v6_0138_pull_2NAQ58kr/`，归档
SHA256=`be1fed49bd06e5edc6af8f75f54a509e0db632d2340bcd80b6f9d3adc8cff8eb`。

## 报告要求

- 列出 V6.1 固定分母与 V6.8 终值，明确 scale、输入、seed、Release flags 和源码指纹。
- 列出 Task1/Task2 L1-L6 total、主要步骤、first/median/P95 和相对收益。
- 列出 all81 L1-L6 绝对耗时、最大规模热点和剩余瓶颈。
- 汇总保留、回退、暂缓优化，不删除失败候选事实。
- plan/cache/copy/allocation 只引用直接证据；未直接测量的字段明确标注限制。
- 给出 all81、dtype、14 步、平台、manifest 和报告目录证据路径。

当前结论：V6.8 硬门已关闭；还需完成 V6-0141 的 486 行性能终测和 V6-0142
最终汇总，因此尚未代表最终交付完成。
