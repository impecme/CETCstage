# V6.3 Task2 链路第二批交付文档

## 版本信息

- 当前状态：已技术收束。
- 对应计划：`docs/performance/v6_0/plans/V6_3_plan.md`。
- 进入基线：V6.2 Task2 L6 `53.4843 ms`。

## 保留优化

- V6-0042 将公共 complex `firfilter` 改为 input halo 与 taps shared cache。
- L5 filter `2.5168 -> 2.02112 ms`，下降 `19.69%`。
- L6 filter `6.27164 -> 5.46384 ms`，下降 `12.88%`。
- L6 total `53.4843 -> 52.7586 ms`，阶段下降 `1.36%`。

## 回退与平台结论

- 私有 causal FIR helper 不在正式计时链路，候选已清理。
- feature fusion 合并未达到双档门禁，已回退。
- correlate 与 CWT 双流并行的 L6 收益仅 `1.03%`，资源竞争使两分支 event 膨胀，已回退。
- ZQ500 对当前重计算分支的多 stream 结论为 `limited`，不扩展到四流。

## 验证与证据

- filtering full、Task2 L1-L6、all81 `81/81`、dtype 和 14 步均通过。
- 保留项：`/home/usr_04/CETC_garbage/cetc_v6_0042_pull_20260712_094036/`。
- 双流回退：`/home/usr_04/CETC_garbage/cetc_v6_0043_pull_20260712_095540/`。

## 完成判定

V6.3 保留公共 FIR 优化并停止当前多流方案，Task1 主线进入 V6.4。
