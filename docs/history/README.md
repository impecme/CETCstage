# 历史资料索引

本目录保存迁移过程中的完整台账和冻结报告，只用于追溯设计决策、性能变化和回退原因，
不参与当前构建、当前验证或容器源代码同步。

| 文件 | 用途 |
| --- | --- |
| `PROJECT_LEDGER.md` | 逐轮改动、验证命令与回退记录 |
| `VERSION_HISTORY.md` | 版本里程碑与兼容性变更摘要 |
| `PERFORMANCE_FREEZE.md` | 旧计时协议、历史规模和历史性能冻结结果 |
| `PERFORMANCE_CORRECTION_IMPLEMENTATION.md` | 计时协议修正的实施记录 |
| `ppt_work/` | 初赛/旧答辩方案、旧提示词和历史 PPT 证据审计；不参与当前技术页构建 |

当前口径只读取 `tests/contracts/operator_sets.json`、当前源码和
`data/reports/`；需要把历史改动用于答辩时，引用
[`docs/OPTIMIZATION_HIGHLIGHTS.md`](../OPTIMIZATION_HIGHLIGHTS.md) 中已核对的 before/after
数据，不把 CPU/GPU 加速比误写成 GPU 版本前后倍率。
