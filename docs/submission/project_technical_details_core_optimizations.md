# CETC ZQ500 信号处理库技术细节与核心优化手段

## 口径

- 本文用于向技术评审说明项目实现、验证体系和性能优化方法。
- 已验证结论以 V5.5 终测为准：全库 81 算子、Task1/Task2 14 个计算步骤、dtype 覆盖和中科芯平台适配均通过。
- V6 为后续任务优先深度优化阶段；未完成容器复验的改动只记录机制，不记录收益。
- 正式报告只保留在 `data/reports/zhongkexin/v5_5_final/summary.*`；中间日志和 probe 产物不进入仓库。

## 工程目标

本项目把 cuSignal/SciPy 风格信号处理算子迁移到中科芯 ZQ500 平台，形成 CPU reference、ZQ500 GPU backend、任务 demo 和验证报告四层闭环。

核心约束：

- 每个公开算子独立声明、CPU 实现、GPU 实现、独立测试和性能统计。
- Task1/Task2 的计算步骤必须调用公共算子链路，任务 helper 只做编排、投影、融合、归一化或任务级打分。
- 每个任务计算步骤保留独立 CPU/GPU 时间和精度校验。
- 接口、类型、报告 schema 兼容 V5.5；不得通过删除算子、删除 dtype 或删除步骤换取通过率。

## 代码结构

```text
include/cusignal/<module>/        公开 C++ API、Doxygen 契约、类型约束
src/cpu/<module>.cpp              CPU reference 实现，作为正确性基线
src/zhongkexin/<module>.cu        ZQ500 GPU backend，包含 kernel、FFT/BLAS/SOLVER 调用和 workspace
src/common/*_detail.hpp           CPU/GPU 共用数学语义、参数解析、边界规则
demo/task1_radar/                 雷达 Task1 端到端 pipeline、可视化和 step report
demo/task2_features/              特征提取 Task2 端到端 pipeline、可视化和 step report
scripts/test/                     all81、dtype、接口、任务步骤和报告 schema 门禁
scripts/platform/                 ZQ500 构建、API 扫描、平台 probe、显存采样和阶段汇总
data/reports/zhongkexin/v5_5_final/  V5.5 最终机器可读报告和摘要
```

模块范围为 12 类、81 个公开算子：

| 模块 | 数量 | 代表算子 |
| --- | ---: | --- |
| `waveforms` | 5 | `chirp`, `gausspulse`, `sawtooth`, `square` |
| `bsplines` | 3 | `cubic`, `quadratic`, `gauss_spline` |
| `windows` | 23 | `hann`, `hamming`, `kaiser`, `chebwin`, `taylor` |
| `filter_design` | 5 | `firwin`, `firwin2`, `kaiser_beta`, `cmplx_sort` |
| `filtering` | 17 | `firfilter`, `sosfilt`, `lfilter`, `filtfilt`, `hilbert`, `wiener`, `resample_poly` |
| `radartools` | 6 | `pulse_compression`, `pulse_doppler`, `ca_cfar`, `ambgfun`, `mvdr` |
| `spectral` | 9 | `spectrogram`, `stft`, `periodogram`, `welch`, `coherence`, `lombscargle` |
| `wavelets` | 5 | `cwt`, `ricker`, `morlet`, `morlet2`, `qmf` |
| `correlate` | 3 | `correlate`, `correlate2d`, `correlation_lags` |
| `demod` | 1 | `fm_demod` |
| `estimation` | 1 | `kalman_filter` |
| `peak_finding` | 3 | `argrelextrema`, `argrelmin`, `argrelmax` |

优化优先级不是平均分配：Task1/Task2 直接依赖算子优先，其次是赛题核心非任务算子，最后是原 cuSignal 扩展算子。

## 类型与数值契约

正式支持类型：

- 实数：`float32`, `float16`, `int32`, `int16`, `int8`
- 复数：`complex64`

明确不支持：

- `float64`
- `complex128`
- `complex32`
- 复数整数类型

实现策略：

- `float16` 允许使用 `float32` 中间累加，输出按算子契约回写。
- 整数算子允许扩展累加，例如 `int8/int16` 使用 `int32`，`int32` 使用更宽累加或受控转换。
- 复数路径统一为 host `std::complex<float>` 和 device `cuFloatComplex/cuComplex`，通过 size static assert 保证 ABI 对齐。
- dtype 覆盖按“逐算子适用性”判断，不要求每个算子支持每一种 dtype。

V5.5 终测结果：

| 项 | 结果 |
| --- | --- |
| 公开算子 | 81/81 |
| 接口审计 | 81/81 |
| 类型兼容缺口 | 0 |
| dtype 缺口 | 0 |
| 覆盖 dtype | `complex64`, `float16`, `float32`, `int16`, `int32`, `int8` |

## 平台适配

ZQ500 后端以 CUDA 11.7 兼容路径为约束，但结论只覆盖项目实际使用 API，不宣称覆盖完整 CUDA API 面。

已验证内容：

- 项目实际使用 CUDA API：39 个。
- 禁止项命中：0。
- 未解析 API：0。
- Runtime/BLAS/FFT/DNN/SOLVER/SPARSE/RAND handle probe 可创建、执行必要路径并销毁。
- 构建路径使用 `dlcc -x cuda --cuda-gpu-arch=dlgput64`。

平台层代码集中在：

- `include/cusignal/core/platform_zx_gpu_compat.hpp`
- `include/cusignal/core/platform_zx_gpu_libraries.hpp`
- `scripts/platform/scan_zx_api_usage.py`
- `scripts/platform/probe_zhongkexin.sh`

## 任务链路

### Task1 Radar

Task1 是脉冲压缩、脉冲多普勒、CFAR 和模糊函数组成的雷达检测链路。

14 个正式计算步骤中的 Task1 部分：

| 步骤 | 公共算子链路 | 计算要点 |
| --- | --- | --- |
| `pulse_compression` | `radartools/pulse_compression` | 匹配滤波、模板能量归一化、距离向压缩 |
| `pulse_doppler_fftshift` | `radartools/pulse_doppler`, `fftshift_rows` | 慢时间 FFT、Doppler 维重排 |
| `power_map` | `radartools/power_map` | 复数距离多普勒图转功率图 |
| `ca_cfar` | `radartools/ca_cfar` | guard/reference cell 滑窗背景估计和门限检测 |
| `ambgfun` | `radartools/ambgfun` | delay-Doppler 模糊函数面 |
| `final_detection` | `radartools/detect_peak` | 检测峰值定位 |

Task1 主要瓶颈来自二维谱面生成、CFAR 邻域访问和 `ambgfun` 全 delay-Doppler surface。V5.5 终测中 all81 最大 GPU E2E 项为 `radartools/ambgfun`，约 167.8 ms，因此 V6 将其列为 Task1 深化目标。

### Task2 Features

Task2 是多域特征提取和轨迹估计链路。

14 个正式计算步骤中的 Task2 部分：

| 步骤 | 公共算子链路 | 计算要点 |
| --- | --- | --- |
| `filter` | `filter_design/firwin`, `filtering/firfilter` | 复数帧 FIR 滤波、实部投影 |
| `demod` | `demod/fm_demod` | 相位差调频解调和 score 生成 |
| `correlate` | `correlate/correlate` | 模板相关、幅值、非负归一化 |
| `spectrogram` | `spectral/spectrogram` | 分段窗函数、频带能量、时间投影 |
| `cwt` | `wavelets/cwt` | 多尺度小波响应、尺度归约 |
| `feature_fusion_peak` | `bsplines/cubic`, `peak_finding/argrelmax` | 多源 score 加权、平滑、峰值选择 |
| `measurement_conversion` | `estimation/kalman_filter` | 峰值轨迹转 measurement vector |
| `kalman` | `estimation/kalman_filter` | 一维状态预测、更新和平滑轨迹 |

Task2 优化重点不是单个公共 API 的孤立耗时，而是跨步骤的数据驻留、score-only fast path 和重复表项复用。V5.5 中 Task2 L3 端到端从曾约 3553 ms 收敛到约 25 ms，主要来自计时口径修正、validation-only 开销剥离和 GPU helper 融合。

## 核心优化手段

### 1. Shared-memory tiled stencil

适用算子：`filtering/wiener`。

原始 Wiener 局部统计会对相邻窗口重复读取 global memory。GPU 版本改为 16x16 tile，并把 halo 区域加载到 shared memory；每个线程复用邻域数据计算局部均值、方差和自适应输出。

效果：

| 算子 | 优化前 GPU | 优化后 GPU | 结果 |
| --- | ---: | ---: | ---: |
| `filtering/wiener` | 214.44 ms | 3.50 ms | 约 61x 降低 |

该优化的关键不是减少 FLOPs，而是减少重叠窗口的 global load，提升 cache locality。

### 2. Prefix-scan IIR fast path

适用算子：`filtering/lfilter`, `filtering/filtfilt`。

针对二阶单行 BA 滤波，先转换为单节 SOS，再用并行 prefix scan 表达递推依赖。`filtfilt` 的正向和反向阶段复用同一条 scan 路径，通用高阶情况保留 fallback。

效果：

| 算子 | 优化前 GPU | 优化后 GPU | 结果 |
| --- | ---: | ---: | ---: |
| `filtering/lfilter` | 455.17 ms | 0.359 ms | 约 1268x 降低 |
| `filtering/filtfilt` | 909.94 ms | 0.679 ms | 约 1340x 降低 |

这个路径解决的是 IIR 串行依赖问题：只在满足低阶可重写条件时进入 fast path，避免牺牲通用语义。

### 3. R2C FFT 与 PSD fused output

适用算子：`spectral/periodogram`，并影响 `spectrogram/stft/csd/welch/coherence` 的设计。

实数单边谱不再走完整 C2C 频谱。GPU 后端使用 R2C FFT，只生成必要频点，并把 constant detrend、窗归一化和 PSD 输出融合到后处理 kernel。

效果：

| 算子 | 优化前 GPU | 优化后 GPU | 结果 |
| --- | ---: | ---: | ---: |
| `spectral/periodogram` | 72.91 ms | 0.669 ms | 约 109x 降低 |

同类谱分析算子还缓存 frequency axis、segment times、window scale 和 FFT plan 相关 workspace，避免重复构造。

### 4. Cross-spectrum fused accumulation

适用算子：`spectral/coherence`。

coherence 需要 `Pxx/Pyy/Pxy`。优化前容易重复执行窗口、FFT 和功率谱归约。GPU 后端共享 x/y 分段 FFT，一次 fused kernel 计算自谱、互谱和 coherence。

效果：

| 算子 | 优化前 GPU | 优化后 GPU | 结果 |
| --- | ---: | ---: | ---: |
| `spectral/coherence` | 5.27 ms | 0.751 ms | 约 7x 降低 |

### 5. Window direct write

适用算子：`windows/cosine` 等窗口族。

窗口生成类算子输出规模固定、访存线性。优化策略是直接写最终输出，移除通用分发、extended workspace 和冗余 copy。

效果：

| 算子 | 优化前 GPU | 优化后 GPU | 结果 |
| --- | ---: | ---: | ---: |
| `windows/cosine` | 约 52.3 ms | 约 0.25 ms | 约 209x 降低 |

窗口族优化收益来自减少固定开销，尤其对小中规模输入明显。

### 6. Small-matrix radar linear algebra

适用算子：`radartools/mvdr`。

MVDR 的主要代价是协方差估计和小矩阵求解。GPU 后端针对小传感器数路径实现 direct triangular covariance、block mean reduction 和 8x8 单 kernel solve，避免把小矩阵问题拆成大量高开销库调用。

效果：

| 口径 | 优化前 | 优化后 | 结果 |
| --- | ---: | ---: | ---: |
| E2E | 52.48 ms | 11.17 ms | 约 4.7x 降低 |
| kernel | 42.12 ms | 0.847 ms | 约 49.7x 降低 |

### 7. Device-resident workspace/cache

适用范围：谱分析、滤波、窗口、小波、Task2 pipeline。

优化原则：

- 固定参数的窗函数、频率轴、segment times、FFT scratch、CWT kernel table、direct spectrogram 三角表放入 workspace。
- 重复运行、scale sweep 和 task repeat 中相同 key 命中后不再 host 构造、不再 H2D 上传、不再重新分配 device buffer。
- cache key 必须包含影响数值输出的参数；不完整 key 会导致错误复用，不能接受。

典型缓存项：

| 路径 | 缓存对象 | key |
| --- | --- | --- |
| `spectral` | window scale、frequency axis、segment times | `window/nfft/fs/scaling/mode` |
| `filter_design/firwin2` | full-spectrum template | `freq/gain/numtaps/window` |
| `windows/chebwin` | window workspace | `M/atten/sym` |
| `wavelets/cwt` | wavelet kernel table | `widths/sample_count/wavelet` |
| Task2 direct spectrogram | cos/sin table、scale | `nperseg/nfft/band/fs/window` |

V6 已加入的两项 Task2 cache 仍待容器复验：

- `V6-0200`: direct spectrogram band score 的 cos/sin 表和 scale 复用。
- `V6-0201`: batched CWT score 的 morlet2 kernel table 复用。

### 8. Task-level fused post-processing

适用范围：Task2 `correlate/spectrogram/cwt/feature_fusion/kalman`。

公共算子负责核心数学语义，Task helper 负责把任务只需要的结果压缩到 score 或 track：

- `batched_correlate_score_*`: 相关、幅值和归一化的任务级 score。
- `direct_spectrogram_band_score_*`: 不生成完整 spectrogram 时直接计算目标频带能量。
- `batched_cwt_max_score_*`: 小波响应直接跨尺度取最大 score。
- `fuse_feature_scores_*`: 多源 score 加权、平滑和候选峰值选择。
- `kalman_track_from_peaks_*`: 峰值轨迹直接进入一维 Kalman 状态更新。

该策略避免把完整中间矩阵落回 host，再由 CPU 重新做任务级投影。约束是每个 helper 对应步骤仍必须保留 CPU/GPU 对照误差和 step timing。

## 验证体系

V5.5 通过的门禁：

| 门禁 | 结果 |
| --- | --- |
| 全库 benchmark | 81/81 passed |
| full 回归 | 12 模块、81 算子 passed |
| Task smoke | 2 任务、14 计算步骤 passed |
| 任务步骤计时 | 缺口 0 |
| 任务步骤精度 | 缺口 0 |
| dtype 覆盖 | `operator_dtype_missing_edges=0` |
| 类型兼容 | `compatibility_gap_count=0` |

关键验证脚本：

```bash
scripts/test/run_all_tests.sh --list
scripts/test/audit_operator_interfaces.py
scripts/test/audit_dtype_test_coverage.py
scripts/test/audit_task_steps.py
scripts/test/validate_task_step_reports.py
scripts/test/run_task_demos.sh
scripts/test/benchmark_all_ops_scales.py
scripts/platform/scan_zx_api_usage.py
scripts/platform/probe_zhongkexin.sh
scripts/platform/sample_gpu_memory.py
```

ZQ500 容器复现入口：

```bash
cd /CETC
source /zq500/sdk/env.sh
scripts/test/run_all_tests.sh --list > /tmp/all81.tsv
scripts/test/run_task_demos.sh --build-dir build-zx --build --scale-sweep --scales 1,2,3,4,5,6 --repeat 3 --require-visualization-deps
```

## 已验证性能结论

以下为 V5.5 阶段可引用的代表性优化结果，单位为 GPU E2E 或明确标注的 kernel 时间。

| 路径 | 核心手段 | 优化前 | 优化后 | 口径 |
| --- | --- | ---: | ---: | --- |
| `filtering/filtfilt` | SOS + prefix scan 正反向复用 | 909.94 ms | 0.679 ms | GPU 优化前后 |
| `filtering/lfilter` | BA 到 SOS fast path + prefix scan | 455.17 ms | 0.359 ms | GPU 优化前后 |
| `windows/cosine` | direct write、移除冗余 workspace/copy | 约 52.3 ms | 约 0.25 ms | GPU 优化前后 |
| `spectral/periodogram` | R2C FFT + detrend/PSD fused output | 72.91 ms | 0.669 ms | GPU 优化前后 |
| `filtering/wiener` | shared-memory tiled stencil | 214.44 ms | 3.50 ms | GPU 优化前后 |
| `radartools/mvdr` | 小矩阵 direct covariance + 8x8 solve | 52.48 ms | 11.17 ms | E2E |
| `radartools/mvdr` | 小矩阵 direct covariance + 8x8 solve | 42.12 ms | 0.847 ms | kernel |
| `spectral/coherence` | 共享 x/y FFT + fused Pxx/Pyy/Pxy | 5.27 ms | 0.751 ms | GPU 优化前后 |
| Task2 L3 | validation-only 开销剥离 + helper 融合 | 曾约 3553 ms | 最终约 25 ms | 任务端到端 |

V5.5 终测 all81 中：

- 实际 CPU/GPU E2E 加速比最高的是 `wavelets/cwt`，约 215x。
- 其次为 `windows/kaiser`，约 196x。
- `filtering/wiener` 约 194x。
- 最大 GPU E2E 项仍是 `radartools/ambgfun`，约 167.8 ms，是 V6 Task1 重点。
- GPU 显存峰值约 2453 MiB，最大利用率 100%。

## V6 后续优化路线

V6 不再扩展 V5 文档，所有计划和台账只写入 `docs/performance/v6_0/`。

第一优先级：

- Task2 `filter/correlate/spectrogram/cwt/feature_fusion/kalman`：减少完整中间结果、重复预计算、H2D/D2H 和 device allocation。
- Task1 `pulse_compression/pulse_doppler/ca_cfar/ambgfun/mvdr`：推进 device-resident 链路，评估 FFT layout、CFAR 积分图/前缀和、`ambgfun` 分块和 MVDR 小矩阵路径。

第二优先级：

- 赛题提到但不在任务主链路上的核心算子做轻度优化。
- 原 cuSignal 有但赛题未提到且不影响任务链路的扩展算子暂不深度优化。

候选技术：

- overlap-save convolution
- fCWT 思路下的 wavelet table/cache 和频域批处理
- CUDA Graph 降低小 kernel launch overhead
- prefix-sum/scan 用于递推、CFAR 和滑窗统计
- CA-CFAR 二维积分图或分块前缀和
- MVDR 小矩阵专用求解路径
- FFT plan/layout/cache 复用

V6 收益只有在以下门禁全部通过后才能写成结论：

- all81 correctness 通过。
- dtype 兼容缺口为 0。
- Task1/Task2 每一步独立计时和精度验证完整。
- V5.5 接口、类型和报告 schema 不破坏。
- 相关容器日志路径记录到 `docs/performance/v6_0/optimization_change_log.md`。
