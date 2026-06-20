# V5.3 Task1/Task2 与依赖算子交付文档

## 版本信息

- 当前状态：待开始。
- 对应计划：`docs/performance/v5_0/plans/V5_3_plan.md`。
- 进入条件：V5.2 已关闭。

## 交付要求

- Task1/Task2 每个计算步骤均调用公共算子库。
- 任务私有算法完成公共 CPU/GPU 算子化和独立测试。
- 每步报告算子、shape、dtype、CPU/GPU 耗时、speedup 和精度。
- `complex64` 步骤报告实部、虚部和复数整体误差。
- 27/27 依赖算子有 full、性能和最终状态证据。
- 两任务 L1-L6 correctness、业务 validation、性能、显存和图件通过。
