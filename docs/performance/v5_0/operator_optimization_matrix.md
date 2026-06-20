# V5 全算子库优化与契约矩阵

## 统计口径

- 全库：12 个模块、81 个公开算子。
- 赛题核心集合：53 个，等于全库 81 减去原扩展候选 28。
- 两任务依赖：29 条矩阵记录，去重后 27 个算子；这些算子包含在核心 53 中。
- 优先级：`A-任务` > `B-核心非任务` > `C-扩展`。
- 每个算子最终必须标记为已优化、已审计-无需修改、已审计-平台受限或已回滚。
- 每个算子还必须登记声明、CPU 实现、GPU 实现、独立测试、适用类型、输出域、平台库和任务依赖。

## 类型与契约口径

- 正式实数类型集合：FP32、FP16、INT32、INT16、INT8。
- 类型采用逐算子适用性，不要求纯浮点算法实现整数路径。
- 复数域只允许 `complex64`；CPU 为 `std::complex<float>`，GPU 为 `cuFloatComplex`/`cuComplex`。
- 不允许 `complex128`、FP16 复数和整数复数进入实现或测试矩阵。
- 当前模块清单已覆盖 81/81；逐算子的适用类型和接口审计是 V5.2 关闭项，未审计前统一标记为 `待 V5.2 审计`，不得推定支持。

## 单算子契约字段

| 字段 | 要求 |
| --- | --- |
| 声明 | 位于 `include/cusignal/<module>/<module>.hpp`，包含 Doxygen 功能、输入、输出、类型、异常和平台限制 |
| CPU/GPU | `src/cpu/<module>.cpp` 与 `src/zhongkexin/<module>.cu` 接口和语义对应 |
| 类型 | 在五种实数中列出适用项；复数算子固定为 `complex64` |
| 数值策略 | FP16 累加精度、整数累加宽度、转换和溢出规则明确 |
| 测试 | 独立 correctness、边界、非法参数、适用类型、拒绝类型和性能用例 |
| 平台 | 标记 Runtime/Driver/BLAS/FFT/DNN/SOLVER/SPARSE/RAND 依赖及兼容状态 |
| 性能 | 记录基线、措施、前后数据、误差、显存/cache 和最终状态 |

## 模块覆盖矩阵

| 模块 | 总数 | A-任务算子 | B-核心非任务算子 | C-扩展算子 | 契约阶段 | 性能阶段 |
| --- | ---: | --- | --- | --- | --- | --- |
| `waveforms` | 5 | `chirp`, `gausspulse`, `unit_impulse` | `sawtooth`, `square` | - | V5.2 | V5.3/V5.4 |
| `bsplines` | 3 | `cubic`, `quadratic` | `gauss_spline` | - | V5.2 | V5.3/V5.4 |
| `windows` | 23 | `hamming`, `kaiser` | `chebwin`, `general_cosine`, `general_gaussian`, `parzen`, `taylor`, `triang` | `get_window`, `barthann`, `bartlett`, `blackman`, `blackmanharris`, `bohman`, `boxcar`, `cosine`, `exponential`, `flattop`, `gaussian`, `general_hamming`, `hann`, `nuttall`, `tukey` | V5.2 | V5.3-V5.5 |
| `filter_design` | 5 | `firwin`, `firwin2` | - | `kaiser_beta`, `kaiser_atten`, `cmplx_sort` | V5.2 | V5.3/V5.5 |
| `filtering` | 17 | `firfilter`, `sosfilt`, `hilbert`, `hilbert2` | `wiener`, `lfilter_zi`, `firfilter2`, `detrend`, `freq_shift`, `channelize_poly`, `decimate`, `resample`, `resample_poly`, `upfirdn` | `lfilter`, `firfilter_zi`, `filtfilt` | V5.2 | V5.3-V5.5 |
| `radartools` | 6 | `pulse_compression`, `pulse_doppler`, `ambgfun`, `cfar_alpha`, `ca_cfar` | - | `mvdr` | V5.2 | V5.3/V5.5 |
| `spectral` | 9 | `spectrogram`, `stft` | `lombscargle`, `csd`, `istft`, `vectorstrength` | `periodogram`, `welch`, `coherence` | V5.2 | V5.3-V5.5 |
| `wavelets` | 5 | `ricker`, `cwt` | `qmf`, `morlet`, `morlet2` | - | V5.2 | V5.3/V5.4 |
| `correlate` | 3 | `correlate`, `correlate2d` | - | `correlation_lags` | V5.2 | V5.3/V5.5 |
| `demod` | 1 | `fm_demod` | - | - | V5.2 | V5.3 |
| `estimation` | 1 | `kalman_filter` | - | - | V5.2 | V5.3 |
| `peak_finding` | 3 | `argrelextrema` | - | `argrelmin`, `argrelmax` | V5.2 | V5.3/V5.5 |

## 数量校验

| 集合 | 数量 | 校验 |
| --- | ---: | --- |
| A-任务唯一算子 | 27 | Task1 10 条 + Task2 19 条，扣除 `firwin`、`spectrogram` 两项重复 |
| B-核心非任务 | 26 | 核心 53 - A 任务 27 |
| 核心集合 A+B | 53 | 与赛题核心 active 范围一致 |
| C-扩展 | 28 | 原注释候选，已纳入 active 81 |
| 全库 A+B+C | 81 | 与 `run_all_tests.sh --list` 和全量矩阵一致 |

## 更新规则

- 每完成一个算子，在 V5 台账记录具体措施与证据，并更新本矩阵“当前说明”。
- 阶段交付文件汇总本阶段算子的最终状态和前后性能。
- 阶段关闭时必须重新核对集合数量，不允许通过删除注册项满足通过率。
- V5.2 必须把模块级范围展开为 81 条逐算子契约记录；本表的模块清单是数量源，不替代逐项审计结果。
