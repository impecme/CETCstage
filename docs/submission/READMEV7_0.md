# V7.0 阶段说明

## 状态

- V6 最终交付保持关闭。
- V7.0 固定尺寸 FFT 平台探针已完成。
- V7.1 Task2 filter + correlate 共用 AOT FFT 候选待容器验证。

## 已确认结论

- AOT FFT 将 ZQ500 dlFFT 的首次执行从约 `3.5 s` 降到
  `3-11 ms`。
- AOT 稳态慢于 dlFFT，因此不替换 Task1 已有 FFT。
- Task2 filter/correlate 当前仍是直接卷积，具备频域替换收益空间。
- 当前周期停止其余算子性能优化，只保留 all81 correctness 回归。

## 证据

- V7-0004：
  `/home/usr_04/CETC_garbage/cetc_v7_0004_pull_GCi2l8LN/`
- 执行台账：
  `docs/performance/v7_0/optimization_change_log.md`
- 当前计划：
  `docs/performance/v7_0/plans/V7_0_plan.md`
