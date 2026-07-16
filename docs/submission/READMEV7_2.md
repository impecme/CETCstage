# V7.2 阶段交付

## 状态

- V7-0006 AOT spectrogram 已保留为 Task2 默认路径。
- L3/L5/L6 精度与业务验证全部通过。
- 完整回归因原 L5 挑战门止损未执行，合并到 V7-0007。

## 结果

| 规模 | spectrogram 基线 | AOT | 热点下降 | Task2 total 下降 |
| --- | ---: | ---: | ---: | ---: |
| L3 | `2.55566 ms` | `1.34205 ms` | `47.49%` | `25.08%` |
| L5 | `3.00601 ms` | `2.37907 ms` | `20.86%` | `3.79%` |
| L6 | `5.08862 ms` | `2.88187 ms` | `43.37%` | `7.78%` |

- spectrogram mixed error 与基线一致，为 `9.14e-7~1.23e-6`。
- correlate 精度保持通过。
- `data/reports/` 与 generated manifest 恢复 diff 均为 0。

## 证据

- `/home/usr_04/CETC_garbage/cetc_v7_0006_pull_s3xISZIV/`
- `docs/performance/v7_0/optimization_change_log.md`
