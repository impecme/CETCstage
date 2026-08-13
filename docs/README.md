# 文档索引

本目录包含当前交付文档与单独标记的历史资料。`data/reports/` 是当前性能入口写入或
从 ZQ500 容器取回的机器可读结果；每次运行的原始中间文件暂存于
`data/.reports_staging/`。

| 文档 | 内容 |
| --- | --- |
| [FINAL_DELIVERY.md](FINAL_DELIVERY.md) | 当前交付状态、仓库边界、本轮验证与待办 |
| [history/VERSION_HISTORY.md](history/VERSION_HISTORY.md) | 归档：V1-V7 里程碑摘要和兼容性变更 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 目录、双实现、内存模型和任务流水线 |
| [API_COMPATIBILITY.md](API_COMPATIBILITY.md) | 81 算子、公开接口、ZQ500 SDK/API 边界 |
| [DTYPE_SUPPORT.md](DTYPE_SUPPORT.md) | 支持类型、逐算子契约和限制 |
| [BUILD_AND_RUN.md](BUILD_AND_RUN.md) | 容器环境、依赖、构建、测试和报告生成 |
| [VALIDATION_AND_REPORTS.md](VALIDATION_AND_REPORTS.md) | 正确性烟测、性能结果、报告路径和独立平台检查 |
| [PERFORMANCE.md](PERFORMANCE.md) | 当前计时协议、性能选择器与报告路径 |
| [OPTIMIZATION_HIGHLIGHTS.md](OPTIMIZATION_HIGHLIGHTS.md) | 从历史台账提取的、具有明确 GPU before/after 数据的优化亮点 |

## 归档资料

`history/PROJECT_LEDGER.md`、`history/VERSION_HISTORY.md`、`history/PERFORMANCE_CORRECTION_IMPLEMENTATION.md`
和 `history/PERFORMANCE_FREEZE.md` 只用于追溯，不被当前脚本读取，也不替代本次运行生成的
报告。归档索引与用途见 [history/README.md](history/README.md)。

当前代码验证事实冲突时按以下顺序处理：当前运行生成的结构化报告、当前源码与 CMake、
本文档；历史台账只用于解释改动来源，不与当前结果混用。
