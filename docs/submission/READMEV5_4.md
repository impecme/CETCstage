# V5.4 核心 53 算子交付文档

## 版本信息

- 当前状态：待开始。
- 对应计划：`docs/performance/v5_0/plans/V5_4_plan.md`。
- 进入条件：V5.3 已关闭。

## 交付要求

- 核心 53/53 算子的接口注释、CPU/GPU 对应、类型契约和独立测试状态。
- correctness、边界、非法参数、适用类型和稳定 benchmark 证据。
- 保留优化的耗时、误差、显存/cache 前后对比。
- 无收益、平台受限和回滚项的明确依据。

## 提前完成项

- `filtering/wiener`：二维 shared-memory tiled 快路径已通过 full，归入本阶段核心 53。
