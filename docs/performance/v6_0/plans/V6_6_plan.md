# V6.6 任务相关算子库深化计划

## 状态与目标

- 状态：待开始；进入条件：V6.2 至 V6.5 的任务主链路收益已关闭或明确暂缓。
- 目标：对任务相关 P1 算子做深度优化，避免只优化 demo helper 而留下公共算子热点。

## 工作包

| ID | 模块 | 算子 | 关闭条件 |
| --- | --- | --- | --- |
| V6.6-01 | `radartools` | `ambgfun`, `pulse_compression`, `pulse_doppler`, `ca_cfar`, `mvdr` | 单算子 full、模块 full、Task1 smoke 通过 |
| V6.6-02 | `spectral` | `spectrogram`, `stft`, `periodogram`, `welch`, `csd`, `coherence` | STFT core、R2C、window/cache 路线有收益或暂缓证据 |
| V6.6-03 | `filtering` | `firfilter`, `upfirdn`, `resample_poly`, `decimate`, `hilbert` | 任务相关 dtype 和 complex64 路径不退化 |
| V6.6-04 | `wavelets` | `cwt`, `morlet`, `morlet2`, `ricker` | wavelet cache/fusion 候选关闭 |
| V6.6-05 | `correlate/estimation` | `correlate`, `correlate2d`, `kalman_filter` | direct/FFT 阈值和 small-state 路径关闭 |

## 执行规则

- 排序键：任务复用价值、L6 GPU E2E、kernel 占比、allocation/cache、显存峰值。
- 每轮只处理一个模块内的一个主题。
- 不属于 Task1/Task2 且赛题未提到的 cuSignal 算子不进入本阶段深度优化。

## 回传与关闭条件

回传受影响模块 full、任务 smoke 和重点 benchmark CSV。关闭条件：P1 任务相关算子均有“已优化/暂缓/无需改动”结论，且结论写入台账。
