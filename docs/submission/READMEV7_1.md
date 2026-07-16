# V7.1 阶段交付

## 状态

- V7-0005 A/B 已完成。
- AOT correlate 保留；AOT filter 和 combined 频谱复用关闭。
- 最终全规模 correctness 随 V7-0006 一并执行。

## 结果

| 规模 | correlate 基线 | AOT | 热点下降 | Task2 total 下降 |
| --- | ---: | ---: | ---: | ---: |
| L3 | `6.33735 ms` | `0.668634 ms` | `89.45%` | `39.71%` |
| L6 | `4.45944 ms` | `1.70953 ms` | `61.66%` | `9.77%` |

- correlate 精度和业务验证通过。
- AOT filter 导致 FM demod 误差放大，不进入产品默认路径。
- `data/reports/` 与 generated manifest 恢复 diff 均为 0。

## 证据

- `/home/usr_04/CETC_garbage/cetc_v7_0005_pull_nzySolcJ/`
- `docs/performance/v7_0/optimization_change_log.md`
