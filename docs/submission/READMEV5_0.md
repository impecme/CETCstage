# V5.0 全算子库性能优化总交付文档

## 版本信息

- 当前状态：进行中。
- 总计划：`docs/performance/v5_0/plans/V5_0_plan.md`。
- 算子矩阵：`docs/performance/v5_0/operator_optimization_matrix.md`。
- 优化台账：`docs/performance/v5_0/optimization_change_log.md`。

## 交付范围

- 代码目录、算子封装、CPU/GPU 对应和独立测试规范。
- FP32、FP16、INT32、INT16、INT8 实数适用性及 `complex64` 唯一复数类型。
- CUDA 11.7 Driver/Runtime 与六类科学计算库完整兼容性审计。
- Task1/Task2 两条任务流水线及 27 个唯一依赖算子。
- 赛题核心 53 算子与全库 81 算子。

## 阶段交付

| 阶段 | 交付文件 | 状态 |
| --- | --- | --- |
| V5.1 可观测性与基线 | `READMEV5_1.md` | 已完成 |
| V5.2 工程规范与平台兼容 | `READMEV5_2.md` | 进行中 |
| V5.3 两任务与 27 依赖 | `READMEV5_3.md` | 待开始 |
| V5.4 核心 53 | `READMEV5_4.md` | 待开始 |
| V5.5 全库 81 与最终验收 | `READMEV5_5.md` | 待开始 |

## 当前成果

- cache 与整卡显存可观测链路已建立。
- `filtering/wiener` 二维 tiled kernel 已提前完成，归入 V5.4 核心 53。
- V5 阶段、类型和平台兼容验收口径已经重排并固化。

## 最终关闭要求

- 81/81 算子契约和性能状态完整。
- 两任务每步调用公共算子库，并具备 CPU/GPU 计时和精度。
- 81 算子 L1-L6 共 486 行 benchmark、12 模块和任务回归通过。
- 类型矩阵、平台兼容矩阵、报告、图件、台账和复现命令完整。
