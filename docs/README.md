# 文档索引

本目录只保留最终交付需要的按维度文档。版本计划、候选实验、协作记录和逐轮
交付说明已移出主仓库。`data/reports/` 是本队 ZQ500 容器对当前代码完整验证
通过后发布的机器可读数据；在首次验证前，它可以不存在。

| 文档 | 内容 |
| --- | --- |
| [FINAL_DELIVERY.md](FINAL_DELIVERY.md) | 当前交付状态、仓库边界、本轮验证与待办 |
| [VERSION_HISTORY.md](VERSION_HISTORY.md) | V1-V7 里程碑摘要和兼容性变更 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 目录、双实现、内存模型和任务流水线 |
| [API_COMPATIBILITY.md](API_COMPATIBILITY.md) | 81 算子、公开接口、ZQ500 SDK/API 边界 |
| [DTYPE_SUPPORT.md](DTYPE_SUPPORT.md) | 支持类型、逐算子契约和限制 |
| [BUILD_AND_RUN.md](BUILD_AND_RUN.md) | 容器环境、依赖、构建、测试和报告生成 |
| [VALIDATION_AND_REPORTS.md](VALIDATION_AND_REPORTS.md) | 门禁层级、当前报告发布流程和历史证据边界 |
| [PERFORMANCE.md](PERFORMANCE.md) | V5/V6/V7 冻结性能结论、保留项和关闭项 |

当前代码验证事实冲突时按以下顺序处理：已校验的结构化终版报告、当前源码与 CMake、
本文档。V5.5、V6、V7 的历史性能结论以 `PERFORMANCE.md` 为准，不与当前运行数据
混用；三阶段均已关闭，不再启动 GPU 性能候选。
