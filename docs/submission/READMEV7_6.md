# V7.6 全量回归与最终交付

## 状态

- V7.6 与 V7 已关闭，后续停止性能候选并进入最终汇报。
- V6 最终报告保持不变；V7 结果由独立文档和仓库外证据归档承载。
- `data/reports/` 只保留既有终测汇总，中间结果未写入仓库。

## 最终保留

- Task2 AOT correlate：L3/L6 热点下降 `89.45%/61.66%`，端到端下降
  `39.71%/9.77%`。
- Task2 AOT spectrogram：L3/L5/L6 热点下降
  `47.49%/20.86%/43.37%`。
- 五分钟演示：Task1 L6、Task2 L6 与固定 Top30 总 wall
  `101.971/240 s`。
- Top30 全部通过，中位加速 `109.919x`，几何平均 `105.455x`。

## 默认关闭

- AOT filter：demod 精度失败。
- Morlet2 CWT 对称路径：L5/L6 端到端收益不足。
- 扩大 DeviceStorage cache：四算子总收益仅 `0.096%`。
- Task1 预热 buffer 释放：设备分配减少，但两轮合并 L6 退化 `2.38%`。

## 最终门禁

| 检查 | 结果 |
| --- | ---: |
| all81 correctness | `81/81` |
| dtype 缺口 | `0` |
| Task timing/accuracy 步骤 | `14/14` |
| Task1 L1-L6 | 全部通过 |
| Task2 L1-L6 | 全部通过 |
| Top30 | `30/30` |
| 报告/manifest 恢复 diff | `0` |

全量门来自 V7-0008；V7-0009/V7-0010 只修改 Task1 demo 的实验生命周期
选择，未修改公共算子、接口、类型或报告 schema。

## 证据

- V7-0008：
  `/home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/`
- V7-0009：
  `/home/usr_04/CETC_garbage/cetc_v7_0009_pull_YiZwJVyu/`
- V7-0010：
  `/home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/`
- V7-0011 容器回读：
  `/home/usr_04/CETC_garbage/cetc_v7_0011_deploy_readback/`
- V7-0010 归档 SHA256：
  `b9fed6960cb81088fee8593cb1c92ce19e636e36bc69a199ebca7495d8049f99`
- V7-0010 控制台 SHA256：
  `3fbbfa2869b5038bcd25fe511b00d1e992737f9b5cd0af3b6c1a7bfd1393b73a`
