# V7.4 五分钟演示负载交付

## 状态

- V7-0008 已关闭，容器完整运行 `rc=0`。
- 现场阶段 wall=`101.971 s / 240 s`，保留约 `138 s` 波动与讲解余量。
- 扩大 DeviceStorage cache 未达到收益门，产品保持默认缓存。

## 结果

| 项目 | 结果 |
| --- | ---: |
| Task1 L6 GPU total 中位数 | `3.88566 ms` |
| Task2 L6 GPU total 中位数 | `20.1547 ms` |
| Top30 通过数 | `30/30` |
| Top30 加速比中位数 | `109.919x` |
| Top30 加速比几何平均 | `105.455x` |
| 进程显存峰值 | `2453 MiB` |
| GPU 利用率峰值 | `99%` |

- 准备阶段通过 all81 `81/81`、dtype 缺口 `0`、任务步骤 `14/14` 和
  Task1/Task2 L1-L6。
- 扩大缓存相对默认缓存的四算子总收益为 `0.096%`，低于 `2%` 门；
  `ambgfun` 多保留约 `1 GiB` 仅下降 `0.146%`。
- `data/reports/` 与 generated manifest 恢复 diff 均为 `0`。

## 演示口径

- Task1、Task2 使用 L6。
- Top30 固定使用 `large-gpu` L6；线性算子 `16777216` 点，FFT 类
  `1048576` 点，二次复杂度算子保持安全规模。
- 准备阶段生成并校验 CPU baseline；现场只重新采集 GPU timing。

## 证据

- `/home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/`
- 归档 SHA256：
  `50045f157fb5b10438d42b29d67a6bbc9b2477df36d97a80ec630808c4ea1c92`
- 控制台 SHA256：
  `248f07692a924257f483c08aa2a17d0ad4d1fcf7ed76997e921ef251500f5c36`
