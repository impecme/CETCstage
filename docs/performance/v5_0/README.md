# V5 性能优化计划索引

## 总目标

V5 在 CPU reference 与中科芯 ZQ500 GPU 正确性不退化的前提下，完成工程规范、平台兼容、任务性能和全库 81 算子优化。性能结论必须同时具备耗时、误差、显存/cache 和复现证据。

总计划见 `plans/V5_0_plan.md`，算子范围和契约状态见 `operator_optimization_matrix.md`。

## 阶段划分

| 阶段 | 计划 | 交付文件 | 状态 | 关闭门禁 |
| --- | --- | --- | --- | --- |
| V5.1 | `plans/V5_1_plan.md` | `docs/submission/READMEV5_1.md` | 已完成 | cache、显存和 benchmark schema 可复现 |
| V5.2 | `plans/V5_2_plan.md` | `docs/submission/READMEV5_2.md` | 进行中 | 目录、81 算子契约、类型矩阵和完整平台兼容审计完成 |
| V5.3 | `plans/V5_3_plan.md` | `docs/submission/READMEV5_3.md` | 待开始 | 两任务每步调用算子库，27 个依赖算子和逐步计时/精度闭环 |
| V5.4 | `plans/V5_4_plan.md` | `docs/submission/READMEV5_4.md` | 待开始 | 核心 53/53 完成规范化、独立测试和性能结论 |
| V5.5 | `plans/V5_5_plan.md` | `docs/submission/READMEV5_5.md` | 待开始 | 全库 81/81、486 行 benchmark、任务和平台最终验收完成 |

## 当前执行点

- 当前阶段：V5.2 工程规范与平台兼容。
- 已完成基线：V5.1 可观测性、cache 统计和整卡显存采样。
- 已提前完成：`filtering/wiener` 二维 shared-memory tiled 快路径，归入 V5.4 核心 53。
- 下一门禁：完成目录职责、81 算子契约字段、类型适用性和三个复赛表的全量兼容矩阵设计。
- 后续顺序：V5.3 两任务与 27 依赖，V5.4 核心 53，V5.5 扩展 28 和全库最终验收。

## 当前执行队列

1. `V5.2-01`：从现有测试注册表生成并校验 `task27/core53/extended28/all81` 四个机器可读集合。
2. `V5.2-02`：把模块级矩阵展开为 81 条真实路径契约。
3. `V5.2-03`：在现有模板容器上补齐五种实数与 complex64 类型基础测试。
4. `V5.2-04` 至 `V5.2-07`：类型契约、复赛表解析、平台探针和阶段回归。

当前只执行 `V5.2-01`，通过并回填台账后才进入 `V5.2-02`。计划中出现但仓库尚不存在的 `OPERATOR_SET`、兼容矩阵脚本和 CMake probe target，分别由 V5.2-01、V5.2-05 和 V5.2-06 创建，不得提前作为现有能力使用。

## 类型原则

- 正式实数类型：FP32、FP16、INT32、INT16、INT8，按算子语义确定适用范围。
- 复数只支持 `complex64`，CPU 为 `std::complex<float>`，GPU 为 `cuFloatComplex`/`cuComplex`。
- 不实现 FP64、`complex128`、FP16 复数或整数复数。
- 纯浮点算子不强制实现整数版本，但必须记录不适用理由并验证拒绝行为。

## 执行规则

1. 未满足当前阶段关闭门禁，不进入下一阶段。
2. 计划能力与已实现能力分开记录，不允许把“待实现”写成“已支持”。
3. 核心算子修改至少通过单算子 full；阶段关闭必须通过对应模块或任务回归。
4. 所有措施和结果写入 `optimization_change_log.md`，不得只保留在终端日志中。
5. 辅助智能体并行分析，主智能体统一修改、同步、记录和发布验证命令。

## 文档入口

| 文档 | 用途 |
| --- | --- |
| `agent_collaboration.md` | 智能体职责、文件所有权和阶段协作流程 |
| `optimization_change_log.md` | 优化措施、工程变更、验证证据和状态台账 |
| `operator_optimization_matrix.md` | 81 算子范围、类型/接口/测试契约和性能状态 |
| `plans/V5_0_plan.md` 至 `plans/V5_5_plan.md` | 总计划与各阶段门禁 |
