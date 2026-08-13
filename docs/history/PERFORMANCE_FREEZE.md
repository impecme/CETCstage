# CETC 最终性能结论

本文汇总已经冻结的 V5.5、V6 和 V7 结果。三阶段均已关闭，不再启动 GPU
性能候选，也不修改既有结论。最终数字来自结构化证据和现有摘要，不是仓库收束
期间重新测量的结果。

本文件及 `docs/VERSION_HISTORY.md` 是历史性能结论的交付台账。历史结构化证据、
console 和候选记录留在仓库外的 `/home/usr_04/CETC_garbage/`，不是当前代码报告的
组成部分。`data/reports/` 只记录当前代码在 `gpu_04` 的完整验证，不能被用来
替换、重算或证明下文的 V5.5/V6/V7 冻结数据。

## 1. 结论总览

| 阶段 | 状态 | 核心结论 |
| --- | --- | --- |
| V5.5 | 已关闭 | 12 模块、81/81 算子、2 个任务、14 个计算步骤通过；dtype 缺口 0 |
| V6 | 已关闭 | Task1/Task2 L6 相对 V6.1 分别下降 `45.48%/66.75%`；最终 all81 runner `486/486` |
| V7 | 已关闭 | 最终执行编号 `V7-0011`；演示 wall `101.971095887/240 s`；Top30 `30/30` |

最终演示聚合值：

| 指标 | 值 |
| --- | ---: |
| Task1 L6 GPU median | `3.88566 ms` |
| Task2 L6 GPU median | `20.1547 ms` |
| Top30 median speedup | `109.918923x` |
| Top30 geometric mean speedup | `105.455382x` |
| Top30 minimum speedup | `33.971659x` |
| GPU memory peak | `2453 MiB` |
| GPU utilization peak | `99%` |

## 2. 测量口径

文档中的三类比例不能混用：

- `gpu_e2e_speedup = cpu_median_ms / gpu_e2e_median_ms`，比较 CPU 与 GPU E2E；E2E
  明确包含输入构造、H2D、算子链计算和最终 D2H/输出物化。
- `gpu_kernel_speedup = cpu_median_ms / gpu_kernel_median_ms`，比较 CPU 与 GPU
  kernel 阶段。
- “优化前后降低倍数/百分比”比较两个 GPU 版本，不是 CPU/GPU speedup。

V5.5 最终摘要是 81 个算子的阶段终测行。V6-0141 是 `81 x L1-L6 = 486`
行，协议为 warmup 5、repeat 30。V6.1 all81 使用 warmup 1、repeat 3，因此最终
报告不发布 V6.1 到 V6.8 的全库统一百分比；Task1/Task2 的固定基线与最终
warm median 可以按冻结任务政策比较。

GPU E2E、kernel、Task total 和现场 wall 是不同层级。kernel 仅统计已准备好的
设备输入上的 CUDA 事件，排除 H2D/D2H；任务报告按任务中实际调用的各个算子分别
记录 kernel 中位耗时，不能用“计算阶段总耗时”替代。现场 wall 包含最终演示编排，
不能用单算子 kernel 时间直接相加替代。

## 3. V5.5 最终结果

V5.5 建立全库优化和验收基线：

- all81：81 行、81/81 通过、失败 0。
- full correctness：12 个模块、81 个算子通过。
- Task smoke：2 个任务、14 个计算步骤通过，失败 0。
- interface/type contract：81/81。
- dtype：FP32、FP16、INT32、INT16、INT8、complex64 声明 edge 缺口 0。

V5.5 终测中 GPU E2E 绝对耗时较大的项目包括：

| 算子 | GPU E2E median | GPU kernel median | CPU/GPU E2E speedup |
| --- | ---: | ---: | ---: |
| `radartools/ambgfun` | `167.792 ms` | `167.264 ms` | `50.623x` |
| `spectral/lombscargle` | `12.500 ms` | `12.2929 ms` | `172.119x` |
| `radartools/mvdr` | `11.1482 ms` | `0.840534 ms` | `1.910x` |
| `filtering/wiener` | `3.52101 ms` | `3.38143 ms` | `194.237x` |
| `wavelets/cwt` | `3.50353 ms` | `3.37968 ms` | `215.174x` |

V5 阶段保留的代表性 GPU 版本优化如下。这里的倍数是优化前后 GPU 时间比，
不等于上表的 CPU/GPU speedup。

| 路径 | 主要措施 | 优化前 | 优化后 | 冻结结论 |
| --- | --- | ---: | ---: | --- |
| `filtering/filtfilt` | BA 到单节 SOS，正反向复用 prefix scan | `909.94 ms` | `0.679 ms` | 约 `1340x` 降低 |
| `filtering/lfilter` | BA 到 SOS fast path，扩展保留通用 fallback | `455.17 ms` | `0.359 ms` | 约 `1268x` 降低 |
| `windows/cosine` 等 | direct write，移除通用分发和冗余 copy | 约 `52.3 ms` | 约 `0.25 ms` | cosine 约 `209x` 降低 |
| `spectral/periodogram` | R2C FFT，融合 constant detrend 与 PSD output | `72.91 ms` | `0.669 ms` | 约 `109x` 降低 |
| `filtering/wiener` | 16x16 shared-memory tiled stencil | `214.44 ms` | `3.50 ms` | 约 `61x` 降低 |
| `radartools/mvdr` | triangular covariance、block mean、8x8 solve | E2E `52.48 ms` | E2E `11.17 ms` | E2E 约 `4.7x` 降低 |
| `spectral/coherence` | 共享 x/y FFT，融合 Pxx/Pyy/Pxy | `5.27 ms` | `0.751 ms` | 约 `7x` 降低 |

## 4. V6 最终结果

### 4.1 最终硬门

V6-0138 在同一产品源码上完成：

| 检查 | 结果 |
| --- | ---: |
| all81 correctness | `81/81` |
| interface | `81/81`，兼容缺口 0 |
| dtype | `operator_dtype_missing_edges=0` |
| Task cases | `24/24` |
| Task step rows | `168/168` |
| 计算步骤 | `14`，public 6、mixed 8 |
| Task schema | `12/12` |
| manifest/report diff | `0/0` |

Graph 有效生命周期探针的 capture begin、work、end、instantiate、launch、sync
六项状态均为 0。该结论只覆盖当前探针路径。

### 4.2 Task 收益

| Task/步骤 | V6.1 基线 | V6.8 最终 | 下降 |
| --- | ---: | ---: | ---: |
| Task1 total | `7.19016 ms` | `3.91998 ms` | `45.48%` |
| Task1 pulse compression | `3.27254 ms` | `0.879486978 ms` | `73.13%` |
| Task1 pulse Doppler | `1.56758 ms` | `1.23025 ms` | `21.52%` |
| Task1 CA-CFAR | `0.997072 ms` | `0.733305991 ms` | `26.45%` |
| Task2 total | `76.0695 ms` | `25.2926 ms` | `66.75%` |
| Task2 CWT | `34.0065 ms` | `9.57086277 ms` | `71.86%` |
| Task2 spectrogram | `25.4401 ms` | `5.07821798 ms` | `80.04%` |
| Task2 correlate | `9.75641 ms` | `4.37071419 ms` | `55.20%` |

total 使用 warm repeat=5 median；分步骤当前值来自 warm report final iteration。
这两种 measurement 标签已在 JSON 中保留，不应把分步骤值误写为五次中位数。

### 4.3 All81 L1-L6

V6-0141 最终性能 terminal：

- runner status/pass：`486/486` 行、81/81 算子、失败 0。
- start/end progress：均为 486。
- dlsmi：2679 个样本，覆盖 400/486 个算子时间窗。
- 显存峰值：`2453/16384 MiB`。
- 瞬时利用率最大：`100%`。
- 产品源码指纹一致，manifest/report diff 为 0。

跨全部规模最大的 GPU E2E 项：

| 算子/规模 | GPU E2E | GPU kernel | 说明 |
| --- | ---: | ---: | --- |
| `radartools/ambgfun` L6 | `167.855 ms` | `167.303 ms` | 最终 compute-bound 主热点 |
| `filtering/hilbert2` L5 | `97.5338 ms` | `97.4722 ms` | 非友好 FFT 尺寸陡坡，V6.1 已存在 |
| `radartools/ambgfun` L5 | `43.4002 ms` | `43.0139 ms` | 二次复杂度路径 |
| `spectral/lombscargle` L6 | `11.4974 ms` | `11.2932 ms` | 主要剩余成本为 kernel arithmetic |
| `radartools/mvdr` L6 | `2.48138 ms` | `0.793792 ms` | E2E 固定开销 `1.687588 ms` |

### 4.4 486/486 的精度边界

`486/486` 是 runner 用例和计时协议通过，不等同于全局误差诊断全部为 `ok`。
V6-0141 的 benchmark-wide 分类为：

- `performance-bound`: 290 行
- `ok`: 191 行
- `true-error`: 5 行

5 条 `true-error` 均为 `spectral/coherence` L1-L5，mixed error 分别为：

| 规模 | mixed error |
| --- | ---: |
| L1 | `0.172711` |
| L2 | `0.150273` |
| L3 | `0.0992084` |
| L4 | `0.125139` |
| L5 | `0.0997772` |

独立 all81 accuracy case 按历史校准的 float32 容差通过；V6-0141 perf runner
本身不以 mixed error 判行失败。最终报告保留 runner 通过结论，同时单列五条
诊断，不能隐藏或把二者合并成“全局误差为零”。

## 5. V6.7 保留方向

V6.7 正式保留 21 个方向。下表保留最终方向和台账 ID，不重复中间命令：

| 台账 ID | 保留方向 |
| --- | --- |
| V6-0099 | `windows/taylor` 低阶余弦递推 |
| V6-0100 | `windows/general_cosine` 低阶余弦递推 |
| V6-0101/V6-0103 | `waveforms/gausspulse` envelope 复用与四输出变体 |
| V6-0104 | `windows/kaiser` Bessel FP32 精确停机 |
| V6-0105 | `waveforms/chirp` 线性斜率预计算与测量对齐 |
| V6-0107 | `wavelets/ricker` 偶对称成对输出 |
| V6-0108 | `wavelets/morlet2` 共轭对称成对输出 |
| V6-0111 | `windows/general_gaussian` 对称成对计算 |
| V6-0112 | `windows/parzen` 位级对称成对计算 |
| V6-0113 | `windows/hamming` 精确混合成对计算 |
| V6-0115 | `windows/triang` 位级对称成对输出 |
| V6-0118 | `spectral/lombscargle` 双频 block 与归约同步 |
| V6-0119 | `spectral/vectorstrength` partial 归约同步 |
| V6-0120 | `spectral/vectorstrength` 双 period block |
| V6-0121 | `filtering/channelize_poly` 8 通道 point kernel |
| V6-0122 | `filtering/firfilter2` 反向直写 |
| V6-0123 | `filtering/resample` 频谱重排融合 |
| V6-0124 至 V6-0128 | `filtering/resample` 窗乘融合及平台边界重验 |
| V6-0132 | `spectral/periodogram` 窗口、scale、频率轴缓存 |
| V6-0133 | `spectral/welch` setup cache 与精确 key |
| V6-0134 | `spectral/istft` 窗口、窗口和、时间轴缓存 |

失败、严格精度失败或收益不足的候选已回退或暂缓。代表性关闭组包括：

- Task2 spectrogram 替代 FFT/映射方案、CWT 纹理/联合 halo、execution overlap。
- Task1 单槽 FFT plan、Doppler window/padding、ambgfun 搬运/固定开销、event
  精简和 grid 调参。
- public complex FIR shared-halo、public CWT 四输出和 Task2 CWT 分组并行。
- Morlet sin/cos 或对称候选的严格精度失败、sawtooth/square 快路径退化、QMF
  `float2` 无收益。
- STFT 分段准备、CSD packed-C2C/连续 batch 的精度或性能门失败。

这些方向没有进入默认产品；不能只保留候选数字而忽略回退结论。

## 6. V7 最终结果

### 6.1 最终保留

| 方向 | 热点收益 | 端到端收益 | 结论 |
| --- | --- | --- | --- |
| Task2 AOT correlate | L3 `89.45%`、L6 `61.66%` | L3 `39.71%`、L6 `9.77%` | 保留 |
| Task2 AOT spectrogram | L3/L5/L6 `47.49%/20.86%/43.37%` | L3/L5/L6 `25.08%/3.79%/7.78%` | 保留 |

V7-0005 的整体 gate 原本为 failed：correlate-only 分支通过，filter/combined
分支失败。V7-0006 的原 challenge gate 也为 failed，失败项是 L5 hotspot/total
目标；后续按“数值通过且 L3/L5/L6 hotspot 与 E2E 均为正收益”的书面保留政策
保留 AOT spectrogram。最终汇总器必须保留这些原始 gate 状态。

### 6.2 默认关闭

| 候选 | 结构化结果 | 最终选择 |
| --- | --- | --- |
| AOT filter | demod L3/L6 mixed error `1.10305/2.02626`，限制 `0.0005` | 关闭 |
| Morlet2 CWT symmetry | L5/L6 E2E 退化 `1.73%/1.29%` | 关闭 |
| expanded DeviceStorage cache | 四算子聚合收益 `0.0958%`，要求 `2%` | 保留默认 cache |
| Task1 release warmup buffers | 两轮合并 L6 `4.183365 -> 4.282725 ms`，退化 `2.38%` | 保留预热 buffer |

V6-0108 保留的是独立 `wavelets/morlet2` 波形生成器的共轭对称计算；V7-0007
关闭的是 Task2 CWT 内的 Morlet2 成对卷积实验。二者不是同一个候选或代码路径。

Task1 buffer 候选虽然减少设备分配，但两轮 L6 median 和进程 wall 没有形成稳定
收益，因此不能按 allocation 次数单独判定保留。

### 6.3 最终演示

V7-0008 提供最终演示测量，V7-0011 是最终交付执行编号。最终门禁为：

- all81 `81/81`
- dtype 缺口 0
- 14/14 timing/accuracy 步骤
- Task1 L1-L6 `6/6`
- Task2 L1-L6 `6/6`
- Top30 `30/30`
- restore diff 0

V7-0009 有一个明确的历史 timing 例外：补充 Task2 L1 smoke 使用
`--skip-timing-validation`，其 `gpu_total_stability=0.506849` 超过内部限制 0.35。
它不是 V7-0008 最终演示门，也不参与候选收益选择；最终 JSON 单独披露该例外。

## 7. 固定 Top30

Top30 来自 V6-0141 的 L6 `gpu_e2e_speedup` 降序，并冻结在
`operator_sets.json`。现场采用 large-gpu L6，不做运行时重新排序。

| 排名 | 算子 | V6 L6 E2E speedup |
| ---: | --- | ---: |
| 1 | `wavelets/cwt` | `375.788x` |
| 2 | `windows/general_gaussian` | `226.150x` |
| 3 | `windows/kaiser` | `199.113x` |
| 4 | `filtering/wiener` | `196.179x` |
| 5 | `spectral/lombscargle` | `187.117x` |
| 6 | `windows/taylor` | `102.560x` |
| 7 | `windows/flattop` | `93.479x` |
| 8 | `windows/general_cosine` | `90.827x` |
| 9 | `waveforms/gausspulse` | `83.320x` |
| 10 | `windows/gaussian` | `81.505x` |
| 11 | `wavelets/morlet` | `75.676x` |
| 12 | `windows/blackmanharris` | `75.112x` |
| 13 | `windows/nuttall` | `73.254x` |
| 14 | `waveforms/chirp` | `65.604x` |
| 15 | `radartools/pulse_compression` | `65.456x` |
| 16 | `windows/cosine` | `60.641x` |
| 17 | `windows/exponential` | `59.731x` |
| 18 | `filtering/channelize_poly` | `55.752x` |
| 19 | `windows/blackman` | `52.134x` |
| 20 | `radartools/ambgfun` | `51.099x` |
| 21 | `wavelets/morlet2` | `50.138x` |
| 22 | `windows/hamming` | `50.138x` |
| 23 | `waveforms/square` | `49.233x` |
| 24 | `spectral/vectorstrength` | `45.289x` |
| 25 | `bsplines/gauss_spline` | `43.084x` |
| 26 | `windows/bohman` | `41.491x` |
| 27 | `filtering/lfilter_zi` | `41.483x` |
| 28 | `peak_finding/argrelmin` | `41.131x` |
| 29 | `peak_finding/argrelextrema` | `40.842x` |
| 30 | `peak_finding/argrelmax` | `38.179x` |

Top30 的 V7 聚合 median/geometric mean 使用 V7 最终演示结构化结果，分别为
`109.918923x/105.455382x`；不能用表中显示到三位小数的值手工重算后覆盖摘要。

## 8. 剩余瓶颈

V6/V7 关闭时保留的解释为：

- `radartools/ambgfun` L6：最终 compute-bound；继续优化需要算法或生命周期重设。
- `filtering/hilbert2` L5：非友好 FFT 尺寸，陡坡在 V6.1 已存在，不是 V6.8
  回归。
- `spectral/lombscargle` L6：pair-input 与 reduction 后主要剩余 kernel arithmetic。
- `radartools/mvdr` L6：kernel 已较低，继续降低 E2E 需要跨调用生命周期或输出/
  同步设计。
- 小规模算子仍可能由 launch、event、setup 和 H2D 固定开销主导。

这些是关闭时的剩余风险说明，不是继续启动 V6/V7 候选的授权。

## 9. 证据能力与报告修正

V6/V7 finalizer 曾存在把当前测量值或 `passed` 直接写入摘要、反向校验不足的
fail-open 缺陷。生成当前最终摘要的修正版已经：

- 用冻结 SHA manifest 绑定归档、console、提取副本和当前源码。
- 从 audit、manifest、task metrics/steps、benchmark CSV/progress、telemetry 和
  readback 重算当前结论。
- 用负向回归验证替换归档、篡改状态、缺行、负误差、symlink 和回读不一致会
  判红。
- 保留原始 failed gate、`true-error` 集合和证据能力限制。

最终精简仓库以已生成的 Markdown/JSON 和其中的 `evidence` SHA 为交付证据，
不要求保留性能候选 runner、历史 finalizer 或仓库内 evidence manifest 才能读取
结论。需要重新生成摘要时，应从仓库外冻结证据和受审版本的生成工具恢复完整
信任链，不能手工编辑 JSON 冒充重算。

没有证据证明有人手工篡改原始日志或故意隐藏算法错误。能够确认的问题是旧
汇总逻辑可能让上游自称通过的结果继续通过；修复发生在报告生成和信任链，不在
产品算法或性能阈值。

V6-0141 的证据限制：

- L1-L5 只有冻结 CSV、progress 和 console，不能从 raw repeat 重建统计量。
- L6 绑定 81 份聚合 metrics；73 份有 case 聚合明细，8 份只有 summary。
- L6 同样没有 30 次原始 timing 数组和输出数组，不能独立重算 median/P95 或误差。
- dlsmi 是低频外部采样，只覆盖 400/486 个时间窗，不是 kernel profiler。

V7-0011 只有 Task1 源码和 runner 两个文件的字节级容器回读，没有独立执行
manifest。最终编号由冻结交付政策、精确目录名和两文件 SHA 共同约束，不能
表述为一次具有完整独立执行 provenance 的新 benchmark。

## 10. 冻结政策

- V5.5、V6、V7 全部关闭。
- 最终执行编号是 `V7-0011`。
- 不再运行 GPU 性能优化，不改变候选保留/回退和最终测量结论。
- 仓库收束期间未重新运行 benchmark；任何静态检查或报告恢复都不能表述成新的
  ZQ500 性能执行。
