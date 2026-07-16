# V6.6 内部执行基础设施与任务相关算子交付文档

## 版本信息

- 当前状态：已关闭。
- 对应计划：`docs/performance/v6_0/plans/V6_6_plan.md`。
- 进入条件已满足：V6.2-V6.5 主链路均已关闭或技术收束。
- 已保留：V6-0077 公共 `correlate` true FFT/auto。
- 已保留：V6-0078 warmup/validation 计量修正；V6-0079 容器脚本兼容修复。
- 已回退：V6-0080 Task2 batched correlate FFT/direct auto，原因是首次执行约 7.3 s。
- 已回退：V6-0081 Task2 tiled-direct correlate ILP4，L5/L6 correlate 退化 `9.15%/3.10%`。
- 已保留：V6-0082 Task2 tiled-direct correlate 双输出线程，L5/L6 correlate 下降 `19.90%/19.52%`。
- 已保留：V6-0083 Task2 CWT shared-halo 双输出线程，L5/L6 CWT 下降 `23.07%/24.93%`。
- 已保留：V6-0085 使用绝对首轮门禁完成 V6-0084 同源码全量复验，L5/L6 spectrogram 下降 `78.20%/79.82%`。
- V6-0086 原门禁失败：CWT 和 median total 通过，但 L6 最后一轮 spectrogram 抖动使 final total 退化。
- 已保留：V6-0087 同源码、同门禁复验通过，确认 CWT 四输出稳定。
- 已回退：V6-0088 公共 complex FIR shared-halo 双输出，L6 E2E 收益未达门禁。
- 已回退：V6-0089 公共 complex FIR shared-halo 四输出，L5 E2E 收益未达门禁。
- V6-0090 按原 Task 双档门禁回退：公共 complex FIR 双/四输出自适应的 L5/L6 median total 收益未达 `2%`。
- 已保留：V6-0091 公共 spectral C2C 分段 buffer 冗余清零消除，重算子 E2E 合计下降 `2.55%`。
- 已保留：V6-0092 welch/spectrogram constant detrend 每段单次归约，spectrogram E2E 下降 `82.05%`。
- 已保留：V6-0093 按双层门禁复验自适应 FIR，L5/L6 filter 下降 `23.31%/10.75%`。
- 已保留：V6-0094 公共 Ricker CWT shared-halo 双输出，E2E/kernel 下降 `43.61%/43.71%`。
- 已回退：V6-0095 公共 Ricker CWT shared-halo 四输出，仅提升 `0.20%/0.53%`，未达门禁。
- 已回退：V6-0096 Task2 CWT 尺度分组并行，L5/L6 CWT 退化 `6.99%/5.94%`。
- 已回退：V6-0097 Task2 CWT 联合 halo 单次装载，L5/L6 CWT 退化 `1.94%/2.14%`。
- 已关闭：V6-0098 有效 Graph 探针、当前保留源码全量回归与 V6.6 七项关闭矩阵全部通过。

## 已验证交付

- 一维 `method="fft"` 使用 real/complex C2C FFT 相关；`auto` 在乘加工作量大于 4096 时选择 FFT。
- 双输入合并为 batch=2 前向 plan，乘积后用 batch=1 逆向 plan；同 `nfft/batch` 稳态复用。
- `direct`、多维相关、公共 API、共轭规则和 `full/same/valid` shape/crop 不变。
- 65x65 auto 真路径与 2048x257 perf surface 精度通过；E2E/kernel 分别下降 `58.27%/50.43%`。
- all81 `81/81`、dtype 缺口 0、14 步缺口 0；Task2 L6 退化 `0.64%`，未将其记为任务收益。

## 实施结论

- correlate kernel 汇总已剔除 warmup 样本；修正后 median/mean/p95=`0.194304/0.193283/0.196828 ms`。
- Task2 代表帧 public correlate 已改为 direct，L3/L6=`1.280625/2.252401 ms`；独立 CSV 明确标记不计入 pipeline。
- V6-0080 的 L3/L6 稳态 correlate 降至 `0.644318/0.993822 ms`，但 cold ratio=`997.90/153.72`，已完整回退。
- V6-0081 数值通过但双档性能退化，已恢复 `84cdb523...`。
- V6-0082 每线程计算两个相邻输出，共用模板值并让每个 block 覆盖 512 点；全量门禁通过，L6 total 下降 `2.14%`。
- V6-0083 将同一模式用于 CWT shared-halo，每线程计算两个相邻 sample，共用 wavelet 系数；L5/L6 total 下降 `8.50%/8.17%`，all81、dtype、14 步和 manifest 全部通过。
- V6-0084 将 256-thread block 划为 32 个 8-thread bin group，用 shuffle 树归约替代 large kernel 的 shared atomic；双档 total 下降 `41.40%/42.24%`，数值通过。
- V6-0085 不改产品源码；绝对首轮门禁和全量回归通过，双档 total 下降 `42.42%/41.44%`。
- V6-0086 对 L5/L6 每线程计算四个间隔 256 的 sample；CWT 下降 `22.68%/18.95%`，但未通过完整门禁。
- V6-0087 不修改源码或门禁；末轮非目标抖动未复现，完整回归通过。
- V6-0088 的 L5/L6 filter 下降 `12.91%/11.10%`，但 L6 final/median total 仅下降 `1.79%/0.40%`，全量回归未执行且源码已替换。
- V6-0089 四输出使 L5/L6 filter 下降 `20.19%/9.83%`；L6 E2E 通过，L5 final/median total 仅下降 `0.61%/1.54%`，全量未执行。
- V6-0090 的 L5/L6 filter 下降 `31.17%/12.07%`，但 median total 仅下降 `0.64%/1.11%`；已恢复 V6-0087 FIR 产品和测试源码。
- V6-0091 将 `periodogram/welch/csd/spectrogram/stft/coherence` C2C 路径的 8 次 `zero(total_fft)` 改为 `reserve(total_fft)`；all81、dtype、14 步和 manifest 全部通过。
- V6-0092 只将 welch/spectrogram 的 `detrend_code==1` 分支路由到现有 complex constant kernel，每段只求一次均值；welch/spectrogram E2E 分别下降 `52.89%/82.05%`，全量通过。
- V6-0093 恢复 193 taps 四输出、257 taps 双输出 selector；三批独立 L5/L6、公共 firfilter 和全量硬门禁全部通过，正式保留。
- V6-0094 让公共 Ricker CWT 每线程计算两个间隔 256 的输出，共用系数并将 grid.x 约减半；公共 full、双性能门禁和全量回归均通过。
- V6-0095 再增加两个相邻输出，使每 block 覆盖 1024 点；数值通过但相对 V6-0094 仅提升 `0.20%/0.53%`，已精确恢复双输出。
- V6-0096 的三组尺度并行增加重复 halo 访问、scratch 写回和 reduction，双档均退化并已精确恢复 `e0159beb...`。
- V6-0097 的联合 halo 数值通过但双档 CWT 均退化；说明长 FMA 链主导，已恢复 `e0159beb...` 并停止 CWT shared-memory 微调。
- V6-0098 不改产品算法；修正 Graph probe 的失效资源生命周期。有效生命周期下 capture begin/work/end、instantiate、launch、sync 状态均为 0，平台结论为 `graph=supported`。
- 当前保留源码 Task1/Task2 L1-L6、all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、DeviceStorage cache 和 manifest 全部通过，V6.6-01 至 07 关闭矩阵全绿。

## 已交付范围

- internal runtime：event、stream、嵌套计时和执行上下文。
- internal FFT：有界 multi-key plan/cache、stream 绑定和 hit/miss 统计。
- internal memory：统一 workspace、allocation/copy telemetry 和显存高水位。
- convolution/spectral core：只抽取已在两个以上调用方验证的共享逻辑。
- radartools/wavelets/correlate/estimation 的任务相关 P1 深化。
- V6.6-01 至 07 关闭矩阵、当前保留源码的 Task1/Task2 smoke，以及 runtime/FFT/memory 量化证据。

## 关闭门禁

- 不改变 V5.5 公共 API、类型或报告 schema。
- cache 有容量、淘汰、失效和高水位测试。
- 受影响模块 full、Task1/Task2 smoke 和重点 benchmark 通过。
- 每个 P1 算子有“已优化、暂缓或无需改动”结论。

## V6-0083 交付结论

- L5/L6 CWT=`6.78367/11.5499 ms`，下降 `23.07%/24.93%`；total=`25.1812/47.4006 ms`，下降 `8.50%/8.17%`。
- cold ratio=`1.270/1.045`；all81 `81/81`、dtype 缺口 0、14 步缺口 0、manifest 不变。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0083_pull_20260713_next/`，归档 SHA=`61b6bbc5...`。

## V6-0084 结论

- ZQ500 构建和 L1/L5/L6 correctness 通过；L5/L6 spectrogram=`3.1683/5.0754 ms`，total=`14.7567/27.3789 ms`。
- L5 首轮=`21.3853 ms`，低于 V6-0083 首轮 `33.1102 ms`，但 `first/median=1.459` 超过原 `1.35` 门限；V6-0084 按原规则关闭为失败，不补写全量通过。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0084_pull_20260713_next/`，归档 SHA=`2e00861d...`。

## V6-0085 交付结论

- 产品源码 SHA=`4bc3fe41...`，未增加 pipeline 外预热。
- L5/L6 spectrogram=`3.09442/5.13381 ms`，total=`14.4987/27.7578 ms`；绝对首轮门禁通过。
- L1-L6 repeat3、all81 `81/81`、dtype 缺口 0、14 步缺口 0、manifest 不变。

## V6-0086 结论

- L1/L5/L6 correctness、目标 CWT、median total 和首轮门禁通过。
- L6 最后一轮 spectrogram=`10.6948 ms`，final total=`31.0448 ms`，原 final total 门禁失败；all81/dtype/14 步未执行。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0086_pull_20260714_next/`，归档 SHA=`0af92da9...`。

## V6-0087 交付结论

- 产品源码保持 SHA=`e0159beb...`，不修改 V6-0086 的任何阈值。
- L5/L6 CWT=`5.32646/9.51472 ms`，下降 `22.48%/18.73%`；final total=`13.4162/25.6517 ms`，下降 `7.47%/7.59%`。
- L1-L6 repeat3、all81 `81/81`、dtype 缺口 0、14 步缺口 0、manifest 不变。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0087_pull_20260714_1153/`，归档 SHA=`0a0f544c...`。

## V6-0088 结论

- 源码指纹、`filtering/firfilter full` 和 L1/L5/L6 correctness 通过。
- L5 filter/total 下降 `12.91%/2.98%`；L6 filter 下降 `11.10%`，但 final/median total 仅下降 `1.79%/0.40%`，未达到双项 2% 门禁。
- 全量回归按止损未执行；证据：`/home/usr_04/CETC_garbage/cetc_v6_0088_pull_20260714_122650/`，归档 SHA=`25bb21a2...`。

## V6-0089 结论

- 源码指纹、`filtering/firfilter full` 和 L1/L5/L6 correctness 通过。
- L5 filter 下降 `20.19%`，但 final/median total 仅下降 `0.61%/1.54%`；L6 filter 和 final/median total 分别下降 `9.83%`、`2.13%/2.01%`。
- 全量回归按止损未执行；证据：`/home/usr_04/CETC_garbage/cetc_v6_0089_pull_20260714_124625/`，归档 SHA=`e3c8514a...`。

## V6-0090 结论

- 源码指纹、构建、`filtering/firfilter full` 和 L1/L5/L6 correctness 通过。
- L5 filter/final/median total=`1.61520/12.8976/13.3299 ms`；L6=`4.97126/24.9732/25.3683 ms`。两档 median total 分别只下降 `0.64%/1.11%`，未达 2% 门禁。
- all81/dtype/14 步按止损未执行；证据：`/home/usr_04/CETC_garbage/cetc_v6_0090_pull_20260714_125626/`，归档 SHA=`e3686a9e...`。

## V6-0091 交付结论

- 产品源码 SHA=`70f43cb4...`；保留 C2C 数值路径，只消除会被 prepare kernel 覆盖的预清零。
- repeat10 下 6 个受影响算子全部通过；`welch/csd/spectrogram/stft` E2E 合计下降 `2.55%`。
- Task2 L1/L6 correctness、all81 `81/81`、dtype 缺口 0、14 步缺口 0、manifest 全部通过。公共 spectrogram dlsmi GPU P95/active median 均为 `99%`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0091_pull_20260714_132703/`，归档 SHA=`3c6c5617...`。

## V6-0092 交付结论

- 产品源码 SHA=`59b715ca...`；相对 V6-0091 仅新增 welch/spectrogram 两处 constant-detrend 分支路由。
- welch E2E/kernel=`0.949640/0.617918 ms`，下降 `52.89%/62.51%`；spectrogram=`6.93723/6.81270 ms`，下降 `82.05%/82.32%`。
- Task2 L1/L6、公共算子 full、all81 `81/81`、dtype 缺口 0、14 步缺口 0、manifest 全部通过。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0092_pull_20260714_135926/`，归档 SHA=`beb35cd1...`。

## V6-0093 交付结论

- 产品/测试源码 SHA=`0227a1fe.../7951c6ab...`，叠加在 V6-0092 spectral SHA=`59b715ca...` 上。
- 三批 L5/L6 filter 中位数=`1.79973/4.94043 ms`，下降 `23.31%/10.75%`；Task total 中位数=`12.8773/25.0597 ms`，下降 `4.02%/1.71%`。
- 公共 firfilter full、Task2 correctness/cold、dlsmi、all81 `81/81`、dtype、14 步和 manifest 全部通过。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0093_pull_20260714_144051/`，归档 SHA=`a93dd852...`。

## V6-0094 交付结论

- 产品源码 SHA=`1af1ab0f...`；只改公共 Ricker CWT shared kernel 和对应 launch，不改公共契约。
- CWT E2E/kernel=`59.7988/59.6650 ms`，下降 `43.61%/43.71%`；GPU 输出 max abs/RMSE 均为 0。
- Task2 L1/L6、dlsmi、all81 `81/81`、dtype、14 步和 manifest 全部通过。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0094_pull_20260714_152346/`，归档 SHA=`a8cb912a...`。

## V6-0095 结论

- 候选源码 SHA=`29c8b233...`；源码指纹、构建和公共 CWT full 数值通过，GPU 输出 max abs/RMSE 均为 0。
- E2E/kernel=`59.6766/59.3471 ms`，仅下降 `0.20%/0.53%`，未达到双项 `8%` 门禁；后续阶梯按止损跳过。
- 已恢复 V6-0094 SHA=`1af1ab0f...`；证据：`/home/usr_04/CETC_garbage/cetc_v6_0095_pull_20260714_154234/`，归档 SHA=`91046b13...`。

## V6-0096 结论

- 产品源码 SHA=`ab328bfc...`；L1/L5/L6 correctness 通过，CWT mixed error 均低于 `1.4e-6`。
- L5/L6 CWT=`5.71031/10.0577 ms`，相对基线退化 `6.99%/5.94%`；L6 total 退化 `9.04%`，全量阶梯按止损跳过。
- 已恢复 Task2 SHA=`e0159beb...`；证据：`/home/usr_04/CETC_garbage/cetc_v6_0096_pull_20260714_161405/`。

## V6-0097 结论

- 产品源码 SHA=`1812d61a...`；L1/L5/L6 correctness 通过，CWT mixed error 均低于 `1.4e-6`。
- L5 CWT/total=`5.44092/13.3755 ms`，退化 `1.94%/5.09%`；L6=`9.69727/25.1850 ms`，退化 `2.14%/1.04%`，首轮退化 `7.96%`。
- 算子和硬门禁失败，全量阶梯按止损跳过；已恢复 `e0159beb...`。证据：`/home/usr_04/CETC_garbage/cetc_v6_0097_pull_20260714_162900/`。

## V6-0098 交付结论

- 只改 `tests/platform/zx_compat_runtime_probes.cu` 的资源生命周期与分阶段状态输出，产品算法、公共接口和报告 schema 不变。
- runtime probe：`concurrent_kernels=1`、`async_engines=2`、非默认 stream 与 `cufftSetStream` 通过；single/batch8 plan=`39.8576/0.258982 ms`；Graph 六阶段状态均为 0。
- Task1/Task2 L6 total=`5.16545/25.3138 ms`，所有 L1-L6 timing/accuracy 通过；Task2 L6 当前热点为 CWT `9.51130 ms`、filter `5.40830 ms`、spectrogram `5.05780 ms`、correlate `4.38224 ms`。
- 双任务 L6 dlsmi 进程峰值=`160/64 MiB`，全卡峰值=`453/357 MiB`；all81 中 DeviceStorage 单算子最高缓存峰值为 CWT `260.002 MiB`，未出现失控增长。
- all81 `81/81`、dtype 缺口 0、14 步 timing/accuracy 缺口 0、manifest 无差异，`status.tsv` 最终 `overall=0`。
- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0098_pull_20260714_165704/`；归档/console SHA256=`0a2367f2.../f340f44c...`。
