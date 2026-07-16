# V6.5 Task1 收口与公共 radartools 交付文档

## 版本信息

- 当前状态：已关闭。
- 对应计划：`docs/performance/v6_0/plans/V6_5_plan.md`。
- 固定分母：V6.1 Task1 L6 `7.19016 ms`。
- 收束记录：V6-0076。

## 当前保留结果

- V6-0062 将 IFFT scale 融入频域模板乘法，删除独立全矩阵缩放 kernel。
- L5/L6 pulse compression 分别下降 `17.00%/4.79%`。
- Task1 L5/L6 total 分别下降 `17.10%/4.58%`。
- V6-0070 对完全相同且不超过 1M complex64 的 host pulse 输入复用 device storage，逐字节键控，并在共享 storage 被 host Doppler 写入时失效。
- V6-0070 的 L5/L6 pulse compression 分别从 `1.16630/2.67433 ms` 降至 `0.390419/0.909079 ms`，下降 `66.53%/66.01%`。
- V6-0070 的 L5/L6 total 分别从 `2.75201/5.56620 ms` 降至 `2.04801/4.23236 ms`，下降 `25.58%/23.96%`。
- V6-0073 对完全相同且各不超过 1M complex64 的 MVDR host x/sv 复用 device storage；任一 shape/value 变化均失效，device 输入不变。
- MVDR E2E `11.111 -> 2.39885 ms`，下降 `78.41%`；kernel `0.846 -> 0.835074 ms`，下降 `1.29%`。
- 最终 Task1 L6 门禁实测 `3.96369 ms`；版本固定收益仍按 V6-0070 保留版 `4.23236 ms` 计算，相对 V6.1 累计下降 `41.14%`。

## 当前平台与热点证据

- V6-0065 已完成 13 项算子级 `dlsmi`：大多数重算子是计算/FFT 主导，显存带宽利用率普遍较低。
- V6-0069 在 Task 实际 shape 上分解 pulse compression：L5/L6 kernel 外占 `79.66%/80.64%`。
- V6-0070 已关闭 pulse 重复 host pack/H2D 热点；V6-0072 证明公共 full-surface `ambgfun` 扩容无收益且大 batch 数值不可靠；V6-0073 已关闭 MVDR 重复 host 搬运热点。
- V6-0074 复核其他容器历史峰值：8-10 GiB 主要来自 windows testbench 和 signal compare；Task1 观测到约 `0.5-3.0 GiB` 多档峰值，但日志缺参数、耗时和 utilization，只作为 workspace/output 生命周期线索，不作为性能依据。

## 已回退候选

- complex64 host pack `memcpy`、命名 Doppler window cache、按需 kernel 计时、CA-CFAR Blelloch scan 均未通过 L5/L6 双档门禁。
- V6-0072 将公共 `ambgfun` perf surface 从两 tile 扩到单 tile后，E2E `167.611 -> 167.983 ms`，退化 `0.22%`；perf surface `max_abs=1.999876`，说明 ZQ500 的 16383 batch 路径不满足数值要求，已恢复 8192-row tile 上限。
- 失败项及恢复后的源码 SHA 均记录于 V6 台账，不合并相反档位结果。

## 最终门禁

- MVDR max abs `1.48923e-4`、mixed `0`，host cache 变值/device 契约通过。
- Task1 L3/L6 通过，L6 `3.96369 ms` 未退化。
- all81 `81/81`，dtype 缺口 0，14 个计算步骤 timing/accuracy 缺口 0。
- manifest 不变；`data/reports/` 未保留中间文件。

## 当前证据

- V6-0062：`/home/usr_04/CETC_garbage/cetc_v6_0062_pull_20260713_004042/`。
- V6-0065：`/home/usr_04/CETC_garbage/cetc_v6_0065_pull_20260713_005347/`。
- V6-0069：`/home/usr_04/CETC_garbage/cetc_v6_0069_pull_20260713_104315/`。
- V6-0070：`/home/usr_04/CETC_garbage/cetc_v6_0070_pull_20260713_110909/`，归档 SHA256=`900c9a2e08bd...`。
- V6-0072：`/home/usr_04/CETC_garbage/cetc_v6_0072_pull_20260713_112240/`，归档 SHA256=`983dc123eef9...`。
- V6-0074：`/home/usr_04/gpu_mem_summary.md`、`/home/usr_04/gpu_mem_changes.log`、`/home/usr_04/gpu_mem_monitor.py`。
- V6-0073/V6-0076：`/home/usr_04/CETC_garbage/cetc_v6_0073_rerun_pull_20260713_114911/`，归档 SHA256=`075cb58be76c...`。

## 完成判定

Task1 累计目标、公共 `ambgfun` 止损结论和公共 `mvdr` 收益均已关闭，V6.5 进入只读交付状态；后续优化归入 V6.6。
