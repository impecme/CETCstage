# V7.3 阶段交付

## 状态

- V7-0007 Morlet2 CWT 对称成对卷积已完成 A/B。
- 数值结果通过，但 L5/L6 端到端收益不足，产品默认关闭。
- 原 CWT 路径保持默认；实验路径仅由
  `CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY=1` 启用。

## 结果

| 规模 | CWT 变化 | Task2 total 变化 |
| --- | ---: | ---: |
| L3 | 下降 `10.14%` | 下降 `6.48%` |
| L5 | 退化 `1.28%` | 退化 `1.73%` |
| L6 | 下降 `3.13%` | 退化 `1.29%` |

- 六组任务运行均通过精度和业务验证。
- CWT mixed error 与原路径完全一致。
- `data/reports/` 与 generated manifest 恢复 diff 均为 0。

## 证据

- `/home/usr_04/CETC_garbage/cetc_v7_0007_pull_5ivh74xt/`
- `docs/performance/v7_0/optimization_change_log.md`
