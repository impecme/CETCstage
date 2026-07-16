# V6.2 Task2 主热点第一批交付文档

## 版本信息

- 当前状态：已技术收束。
- 对应计划：`docs/performance/v6_0/plans/V6_2_plan.md`。
- 基线：V6.1 Task2 L6 `76.0695 ms`。

## 保留优化

| 台账 | 优化 | L6 结果 |
| --- | --- | --- |
| V6-0026 | CWT shared-halo fused kernel | CWT `34.0065 -> 15.2658 ms`，下降 `55.1%` |
| V6-0033 | correlate input halo/template shared tile | correlate `9.79323 -> 5.51089 ms`，下降 `43.73%` |

Task2 L6 GPU total 为 `53.4843 ms`，相对 V6.1 累计下降 `29.69%`。

## 回退与止损

- spectrogram 逐频点、全矩阵 C2C FFT、bin-parallel direct DFT 均明显退化，已回退。
- spectrogram 最近 segment 整数映射收益未达门禁，已回退。
- CWT 系数 shared cache 导致 L5/L6 退化约 `90%`，已回退。
- 阶段距 30%目标差 0.31 个百分点，不降低门禁、不虚报达标。

## 验证

- CWT/correlate 受影响算子 full 通过。
- Task2 L1-L6 通过。
- all81 `81/81`，dtype 缺口 0，14 步审计通过。

## 证据

- CWT：`/home/usr_04/CETC_garbage/cetc_v6_0210_pull_20260711/`。
- correlate：`/home/usr_04/CETC_garbage/cetc_v6_0033_pull_20260712_082553/`。
- 其余候选和回退路径见 V6 台账 V6-0028 至 V6-0039。

## 完成判定

V6.2 以两项稳定收益技术收束，剩余 filter 和执行计划进入 V6.3。
