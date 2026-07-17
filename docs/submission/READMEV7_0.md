# V7.0 阶段说明

## 状态

- V6 最终交付保持关闭。
- V7.0 固定尺寸 FFT 平台探针已完成。
- V7.1-V7.6 已完成，V7 已关闭。
- 最终演示口径为 Task1/Task2 L6 与固定 large-gpu Top30。

## 已确认结论

- AOT FFT 将 ZQ500 dlFFT 的首次执行从约 `3.5 s` 降到
  `3-11 ms`。
- AOT 稳态慢于 dlFFT，因此不替换 Task1 已有 FFT。
- Task2 保留 AOT correlate 与 AOT spectrogram；AOT filter 默认关闭。
- Morlet2 CWT 对称路径和 Task1 预热 buffer 释放路径均保留为实验开关，
  因 L5/L6 稳定收益门失败而不进入产品默认。
- V7-0008 最终演示 wall=`101.971/240 s`，Top30 中位加速
  `109.919x`，all81=`81/81`。

## 证据

- V7-0004：
  `/home/usr_04/CETC_garbage/cetc_v7_0004_pull_GCi2l8LN/`
- V7-0008：
  `/home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/`
- V7-0010：
  `/home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/`
- 执行台账：
  `docs/performance/v7_0/optimization_change_log.md`
- 当前计划：
  `docs/performance/v7_0/plans/V7_0_plan.md`
