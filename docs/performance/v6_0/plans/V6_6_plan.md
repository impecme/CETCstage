# V6.6 内部执行基础设施与任务相关算子深化计划

## 状态与目标

- 状态：已关闭；V6-0098 有效 Graph 探针与 V6.6-01 至 07 关闭矩阵全部通过，进入 V6.7。
- 目标：把 V6.2-V6.5 已证明有效的 event、FFT plan、workspace 和 convolution/spectral core 深化为内部模块，再推广到任务相关 P1 算子。只新增内部接口，不改变 V5.5 公共 API。
- 阶段交付：`docs/submission/READMEV6_6.md`；已记录保留、回退、平台勘误和当前源码关闭证据。

## 工作包

| ID | 模块 | 内容 | 关闭条件 |
| --- | --- | --- | --- |
| V6.6-01 | internal runtime | `ExecutionContext`、复用 event、stream 和嵌套计时策略 | 公共 kernel timing 不丢；任务可关闭嵌套同步；小算子 E2E 固定开销下降 |
| V6.6-02 | internal FFT | 有界 multi-key plan/cache、create/hit/miss 统计和 stream 绑定 | Task1/Task2 稳态 plan create 为 0；cache 高水位受控 |
| V6.6-03 | internal memory | 统一热点 `DeviceBuffer`/workspace 与 allocation/copy telemetry；接入 `dlsmi` 容量/GPU/memory utilization sidecar | 不破坏 `DeviceSignal/DeviceArray`；显存峰值无失控增长；采样可关联 operator PID 和阶段 |
| V6.6-04 | convolution core | `firfilter/correlate/pulse_compression/CWT` 共享 direct/FFT/auto 基础块 | 只共享被两个以上调用方验证的逻辑；各公共语义保持 |
| V6.6-05 | spectral core | `spectrogram/stft/periodogram/welch/csd/coherence` 统一 segment/window/R2C/layout | 单算子 full、spectral full、Task2 smoke 通过 |
| V6.6-06 | `radartools/wavelets` | 推广模板/wavelet cache、CFAR 选择器和 FFT workspace | `radartools/wavelets` full 与 Task1/Task2 smoke 通过 |
| V6.6-07 | `correlate/estimation` | true direct/FFT auto；区分稳态算子、Task 私有主链和 validation 冷启动；Kalman 只处理固定开销 | correlate method 行为有 benchmark 证据，隐藏 validation 不冒充任务收益，small-state 路径不退化 |

## 执行规则

- 排序键：任务复用价值、L6 GPU E2E、kernel 占比、allocation/cache、显存峰值。
- 每轮只处理一个模块内的一个主题。
- 算子库与任务收益分层验收：correctness、全量回归、兼容性、冷启动、资源和非目标路径为硬门禁；目标算子稳定提速可独立保留；Task 总时延收益单独标注，不因未超过噪声阈值自动回退算子优化。
- 只有在 Task 私有实现中已获得稳定收益的机制才抽取；不为“统一”提前建大框架。
- `ExecutionContext`、plan cache 和 workspace 是内部深模块；调用方只表达 shape、依赖和计时需求，不直接管理 handle 生命周期。
- cache 必须有容量、淘汰、失效和高水位测试；线程局部 cache 也要记录总显存成本。
- 不属于 Task1/Task2 且赛题未提到的 cuSignal 算子不进入本阶段深度优化。
- radartools event 复用在 V6-0055、按需计时在 V6-0067 均未达到 L6 门禁，V6.6 不重复该组合。
- V6-0077 已证明公共 correlate 稳态 FFT 有收益，但 Task2 主阶段仍调用私有 batched direct；V6-0078 先修正 warmup/validation 口径，下一候选只接受直接降低 batched correlate 阶段的方案。
- V6-0080 的 L3/L6 FFT 稳态 correlate 下降 `89.90%/82.05%`，但 shape 首次初始化使 cold ratio 达 `997.90/153.72`，不得用 pipeline 外预热掩盖，Task 私有 FFT 路线停止。
- V6-0081 四路独立累加使 L5/L6 correlate 退化 `9.15%/3.10%`，说明寄存器/调度成本更高；同输出多路归约停止。
- V6-0082 让每线程计算两个相邻输出，共用模板读取并把 block 数减半；全量通过后保留，L6 total 进一步下降 `2.14%`。
- V6-0083 把已验证的双输出模式用于 CWT shared-halo，共用 wavelet 系数并把每帧 block 数减半；全量门禁通过后保留，L6 CWT 和 total 分别下降 `24.93%/8.17%`。
- V6-0084 针对当前首要热点 spectrogram，以 8-thread bin group 和 shuffle 树归约替代 shared atomic；L5/L6 spectrogram 下降 `77.68%/80.05%`，total 下降 `41.40%/42.24%`，但 L5 `first/median=1.459` 使原门禁失败，全量回归未执行。
- V6-0085 不修改产品源码；改用绝对首轮门禁后全量通过并保留，all81/dtype/14 步/manifest 均闭环。
- V6-0086 只对 L5/L6 将 CWT shared-halo 从双输出扩为四输出；CWT 下降 `22.68%/18.95%`、median total 下降 `13.67%/8.03%`，但 L6 最后一轮 spectrogram 单点抖动使 final total 门禁失败，全量回归未执行。
- V6-0087 不改源码或阈值，独立重跑同一候选；L5/L6 CWT 再次下降 `22.48%/18.73%`，final total 下降 `7.47%/7.59%`，全量门禁通过后正式保留。
- V6-0088 将公共 complex FIR shared-halo 扩为双输出；L5/L6 filter 下降 `12.91%/11.10%`，但 L6 final/median total 仅下降 `1.79%/0.40%`，未达门禁并已回退。
- V6-0089 四输出使 L5/L6 filter 下降 `20.19%/9.83%`；L6 E2E 通过，但 L5 final/median total 仅下降 `0.61%/1.54%`，未达门禁并回退 quad-only 路由。
- V6-0090 按实测 tap 长度选择：L5/L6 filter 下降 `31.17%/12.07%`，但 median total 仅下降 `0.64%/1.11%`，未达双档门禁并已恢复 V6-0087 FIR；FIR 输出倍增方向停止。
- V6-0091 去掉 6 个公共 spectral C2C 分段路径中、会被 prepare kernel 完整覆盖的 8 次 buffer 清零；重算子 E2E 合计下降 `2.55%`，all81/dtype/14 步/manifest 全量通过，正式保留。
- V6-0092 对 welch/spectrogram 默认 constant detrend 复用现有每段单次 block reduction；welch E2E/kernel 下降 `52.89%/62.51%`，spectrogram 下降 `82.05%/82.32%`，全量通过后正式保留。
- V6-0093 在 V6-0092 上恢复 V6-0090 自适应 FIR，并用三批独立 L5/L6 验证稳定性；filter 中位数下降 `23.31%/10.75%`，Task total 中位数下降 `4.02%/1.71%`，全量门禁通过后正式保留。
- V6-0094 将任务私有 CWT 已验证的 shared-halo 双输出机制用于公共 Ricker CWT；E2E/kernel 下降 `43.61%/43.71%`，Task2 与全量门禁通过后正式保留。
- V6-0095 在 V6-0094 上继续验证四输出；数值逐位一致，但 E2E/kernel 仅下降 `0.20%/0.53%`，未达双项 `8%` 门禁并已恢复双输出，不再增加公共 CWT 单线程输出数。
- V6-0096 把 15 个 Morlet2 尺度按 5 个一组并行；L5/L6 CWT 分别退化 `6.99%/5.94%`，L6 total 退化 `9.04%`，已恢复 V6-0094 Task2 源码并停止尺度拆分。
- V6-0097 将 quad kernel 的 15 次输入 halo 装载合并为一次；L5/L6 CWT 仍退化 `1.94%/2.14%`，L5 total 退化 `5.09%`，已恢复 `e0159beb...`。CWT shared-memory 微调停止。
- V6-0098 修正 V6-0036 Graph probe 在 stream/device buffer 销毁后 capture 的生命周期错误；有效生命周期下六阶段状态均为 0，结论为 `graph=supported`。当前保留源码 Task1/Task2 L1-L6、all81 `81/81`、dtype/步骤缺口 0、manifest、双任务 dlsmi 和 DeviceStorage cache 全部通过，七个工作包关闭矩阵全绿。

## 回传与关闭条件

关闭证据：`/home/usr_04/CETC_garbage/cetc_v6_0098_pull_20260714_165704/`，归档/console SHA256=`0a2367f2.../f340f44c...`。Task1/Task2 L6 total=`5.16545/25.3138 ms`；进程显存峰值=`160/64 MiB`；DeviceStorage 单算子最高缓存峰值=`260.002 MiB`，均低于 `1 GiB` 门禁。V6.6 已关闭。
