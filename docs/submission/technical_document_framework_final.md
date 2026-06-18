# CETC CUDA 信号处理加速库统一技术文档

更新时间：2026-06-01

> 本文件是项目当前唯一主技术文档。文件名保留 `technical_document_framework_final.md` 以兼容已有引用，但内容已从“框架”合并为“统一版完整技术文档”。`docs/design/*`、`docs/submission/READMEV*`、`scripts/test/READMEV*` 保留为历史设计和版本记录；提交、答辩和复盘时优先引用本文。

## 摘要

本项目面向第十届集创赛“中科芯”企业命题，围绕 GPU 芯片上的信号处理加速库与算法任务验证展开。当前阶段以 NVIDIA GPU / CUDA 为工程基线，完成 cuSignal 风格信号处理库的 CPU/CUDA 双后端迁移、赛题核心算子性能与精度验证、Task1/Task2 端到端任务 demo、自验收脚本、六档规模 benchmark 和报告图件链路。

本文不声称已经完成中科芯国产 GPU 实测。国产 GPU 相关内容仅作为第二阶段后端迁移策略：保持公开 API、测试数据、误差口径和报告脚本不变，替换底层 GPU 后端并重新验证。

| 项目成果 | 当前状态 | 主要证据 |
|---|---|---|
| 完整库迁移 | `tests/unit` 中已有 12 个模块、81 个测试入口 | `include/cusignal/`、`src/cpu/`、`src/zhongkexin/`、`tests/unit/` |
| 赛题核心算子验证 | `scripts/test` 当前启用 53 个核心算子，每个算子支持 6 档规模 benchmark | `scripts/test/run_all_tests.sh`、`scripts/test/benchmark_all_ops_scales.py` |
| 任务 1 | 雷达目标检测与多普勒分析端到端 demo | `demo/task1_radar/` |
| 任务 2 | 多域特征提取定位端到端 demo | `demo/task2_features/` |
| 任务级验收 | repeat、异常输入、资源漂移、可选 compute-sanitizer | `scripts/test/run_task_demos.sh`、`scripts/test/READMEV3_9.md` |
| 性能报告 | 53 算子六档 benchmark、全局图件、任务级规模扫测 | 运行后 `data/reports/unit/benchmarks/*`、`data/reports/demo/*` |

## 0. 阅读导引与主结论

本文按“先讲项目边界，再讲技术实现，最后讲证据闭环”的顺序组织。答辩时可优先抓住下面这条主线：

| 评委关注点 | 主结论 | 文档位置 | 证据入口 |
|---|---|---|---|
| 是否只是两个 demo | 不是。项目先建立 12 模块、81 测试入口的 CPU/CUDA 双后端库，再组合 Task1/Task2 | 第 2、3、5、6 章 | `include/cusignal/`、`src/cpu/`、`src/zhongkexin/`、`tests/unit/`、`demo/` |
| CUDA 加速是否可解释 | 可解释。每个亮点均落到具体 kernel、workspace、库原语或脚本口径 | 第 4、7、10 章 | `src/zhongkexin/`、`include/cusignal/core/types.hpp`、`scripts/test/READMEV3_8_*.md` |
| 精度是否可靠 | CPU 后端、公共 detail 层、单精度口径、`mixed_error` 和精度审计共同约束 | 第 4、8、9 章 | `tests/unit/common/`、`scripts/test/audit_all_ops_precision.py`、运行后 `data/reports/unit/audit/` |
| 性能是否有规模规律 | 53 算子按六档规模复测，区分 e2e speedup 与 kernel speedup | 第 3、8、10 章 | `scripts/test/benchmark_all_ops_scales.py`、运行后 `data/reports/unit/benchmarks/` |
| 任务链路是否自动验收 | Task1/Task2 写出 validation、repeat、资源漂移、异常输入和可选 sanitizer 结果 | 第 5、6、8 章 | `demo/task1_radar/`、`demo/task2_features/`、`scripts/test/run_task_demos.sh` |
| 国产 GPU 实测边界 | 当前是 CUDA 阶段基线，不声称已完成国产 GPU 实测；后续按同一 API 和测试闭环迁移 | 第 1、11 章 | `include/cusignal/`、`scripts/test/` |

## 1. 项目背景与技术路线

### 1.1 赛题定位

赛题关注雷达、通信、时频分析、滤波、检测和状态估计等典型信号处理算法在 GPU 平台上的工程化实现。这类算法通常具有数据量大、链路长、实时性要求高、频域变换密集等特点，适合通过 GPU 并行计算、批量 FFT、设备侧缓存、任务级流水和自动化验证提升吞吐能力。

### 1.2 两阶段边界

当前阶段是 CUDA 基线开发阶段：

- 使用 NVIDIA GPU / CUDA 建立可运行、可测试、可分析的加速库。
- 以 CPU 后端作为参考实现和误差基线。
- 以 ZQ500 GPU 后端验证 GPU 并行化、内存模型、任务链路和性能瓶颈。
- 输出可迁移的软件边界和验证口径。

第二阶段才面向中科芯国产 GPU 平台：

- 保持 `include/cusignal/` 中公开接口不变。
- 保持 `data/reference`、`data/generated`、`tests/unit` 和 `scripts/test` 的验证口径不变。
- 替换 ZQ500 GPU 后端中 cuFFT、cuBLAS、cuSOLVER、CUB、自定义 kernel 和运行时 API 的实现。
- 按“单算子正确性 -> 53 算子性能 -> Task1/Task2 端到端任务”的顺序重新验收。

### 1.3 三层技术路线

项目采用“完整库迁移、核心算子优化、任务链路验证”的三层路线。

| 层次 | 目标 | 技术意义 | 证据 |
|---|---|---|---|
| 完整 cuSignal 库迁移 | 建立 81 个算子的模块化 CPU/CUDA 双路径 | 证明项目不是一次性 demo，而是可复用库 | 12 个模块头文件、CPU/CUDA 源码和 81 个单测入口 |
| 53 个赛题核心算子优化 | 对评分相关算子建立统一精度、耗时、加速比评价 | 支撑性能分析和优化闭环 | `benchmark_all_ops_scales.py`、`plot_all_ops_benchmark.py` |
| Task1/Task2 任务验证 | 将算子组合成赛题任务链路并自动验收 | 检查算子组合后的业务正确性和 e2e 性能 | `run_task_demos.sh`、任务 metrics、summary、可视化 |

一句话答辩口径：

> 我们先把信号处理能力沉淀为 CPU/CUDA 双后端库，再对赛题核心算子做六档规模验证，最后把库函数组合成两个任务级 demo，形成从单算子到端到端任务的完整验证闭环。

## 2. 工程架构

### 2.1 目录分层

| 目录 | 职责 | 技术价值 |
|---|---|---|
| `include/cusignal/` | 公开 API、类型定义、模块接口 | 为后端迁移提供稳定边界 |
| `src/common/` | shape、stride、参数校验、通用算法细节 | 减少 CPU/CUDA 语义分叉 |
| `src/cpu/` | CPU 参考实现 | 提供精度基线和业务对照 |
| `src/zhongkexin/` | CUDA 加速实现 | 项目核心 GPU 后端 |
| `tests/unit/` | 81 个单算子测试入口与 support | 保证模块级正确性、性能和报告输出 |
| `demo/task1_radar/` | 雷达目标检测与多普勒分析 demo | 验证 Task1 端到端任务 |
| `demo/task2_features/` | 多域特征提取定位 demo | 验证 Task2 端到端任务 |
| `scripts/data/` | reference/generated 数据生成脚本 | 维护测试输入和期望输出 |
| `scripts/test/` | 单测、benchmark、任务验收、图件生成 | 统一验证和报告闭环 |
| `data/reference/` | 固定基准数据 | 用于可复现 accuracy 测试 |
| `data/generated/` | 运行期生成输入和样本 | 用于 demo、perf 和调试 |
| `data/reports/` | 运行后报告、metrics、CSV、图件 | 用于答辩和提交证据 |

### 2.2 软件栈

| 类型 | 组件 | 用途 |
|---|---|---|
| 语言 | C++17 / CUDA17 | CPU/ZQ500 GPU 后端实现 |
| 构建 | CMake | 构建核心库、单测和任务 demo |
| GPU Runtime | CUDA Runtime | 内存、事件、kernel launch、设备信息 |
| FFT | cuFFT | 频域滤波、谱分析、雷达处理、CWT/重计算路径 |
| 线性代数 | cuBLAS / cuSOLVER | MVDR 协方差和线性方程求解 |
| 并行原语 | CUB | 选择、归约、窗口归一化等高性能基础操作 |
| CPU 对照 | FFTW / 标准 C++ | CPU 参考和验证链路 |
| 可视化 | Python、numpy、matplotlib | 任务图件和 benchmark 图件生成 |

当前 README 记录的验证环境为 `2 x NVIDIA A100-SXM4-40GB`、CUDA 11.7、CMake 3.22.1，默认 CUDA 架构为 `sm80`。跨机器复测时应重新观察任务阈值和资源漂移。

### 2.3 CPU/CUDA 双后端模型

项目的核心工程原则是 CPU 与 ZQ500 GPU 后端同名接口、同语义输入、同误差口径：

- CPU 后端用于参考实现、误差基线、任务业务对照和迁移安全网。
- ZQ500 GPU 后端用于并行计算、设备缓存、批量 FFT、kernel 融合和任务链路加速。
- `tests/unit` 同时调用 CPU/ZQ500 GPU 路径，输出 `latest_metrics.json`。
- Task1/Task2 demo 同时记录 CPU/GPU 阶段耗时、业务结果、误差和资源状态。

这样做的价值是：CUDA 输出不是孤立结果，而是始终能回到 CPU 基线、单算子测试和任务业务 gate 中验证。

### 2.4 公共语义层、数据生成与报告支撑

项目不是把 CPU 和 CUDA 各写一套互不相关的逻辑，而是在公共层沉淀 shape、axis、窗口、频率轴、参数校验和报告 schema：

| 支撑层 | 关键文件 | 作用 | 答辩价值 |
|---|---|---|---|
| 公共 detail | `src/common/*_detail.hpp` | 统一 shape/stride/axis、窗口规范、滤波器设计约束、谱分析分段配置、雷达坐标轴等语义 | 降低 CPU/CUDA 结果分叉风险 |
| 核心类型与 helper | `include/cusignal/core/types.hpp`、`include/cusignal/core/helpers.hpp` | 定义 Host/Device 容器、复数映射、shape 工具、axis 规范化 | 形成后端迁移的稳定边界 |
| 单测报告层 | `tests/unit/common/report.hpp`、`tests/unit/common/json.hpp` | 写出 `latest_metrics.json`、`latest_summary.md`、`latest_cases.csv`，并解析 CPU baseline cache | 保证所有模块的证据格式一致 |
| 数据生成脚本 | `scripts/data/generate_*.py` | 生成 `data/reference/` 和 `data/generated/` 下的 accuracy/perf 输入与 manifest | 保证测试数据可复现、可扩展 |
| 测试汇总脚本 | `scripts/test/run_all_tests.sh`、`benchmark_all_ops_scales.py`、`run_task_demos.sh` | 串联构建、单测、benchmark、任务验收和图件 | 把源码实现转化为可展示证据 |

## 3. 算子覆盖与模块范围

### 3.1 12 个模块与 81 个测试入口

当前 `tests/unit` 中已登记 81 个 `test_*.cpp` 入口，覆盖如下：

| 模块 | 数量 | 算子/入口 |
|---|---:|---|
| `bsplines` | 3 | `cubic`, `gauss_spline`, `quadratic` |
| `correlate` | 3 | `correlate`, `correlate2d`, `correlation_lags` |
| `demod` | 1 | `fm_demod` |
| `estimation` | 1 | `kalman_filter` |
| `filter_design` | 5 | `cmplx_sort`, `firwin`, `firwin2`, `kaiser_atten`, `kaiser_beta` |
| `filtering` | 17 | `channelize_poly`, `decimate`, `detrend`, `filtfilt`, `firfilter`, `firfilter2`, `firfilter_zi`, `freq_shift`, `hilbert`, `hilbert2`, `lfilter`, `lfilter_zi`, `resample`, `resample_poly`, `sosfilt`, `upfirdn`, `wiener` |
| `peak_finding` | 3 | `argrelextrema`, `argrelmax`, `argrelmin` |
| `radartools` | 6 | `ambgfun`, `ca_cfar`, `cfar_alpha`, `mvdr`, `pulse_compression`, `pulse_doppler` |
| `spectral` | 9 | `coherence`, `csd`, `istft`, `lombscargle`, `periodogram`, `spectrogram`, `stft`, `vectorstrength`, `welch` |
| `waveforms` | 5 | `chirp`, `gausspulse`, `sawtooth`, `square`, `unit_impulse` |
| `wavelets` | 5 | `cwt`, `morlet`, `morlet2`, `qmf`, `ricker` |
| `windows` | 23 | `barthann`, `bartlett`, `blackman`, `blackmanharris`, `bohman`, `boxcar`, `chebwin`, `cosine`, `exponential`, `flattop`, `gaussian`, `general_cosine`, `general_gaussian`, `general_hamming`, `get_window`, `hamming`, `hann`, `kaiser`, `nuttall`, `parzen`, `taylor`, `triang`, `tukey` |

### 3.2 53 个核心算子 benchmark

`scripts/test/run_all_tests.sh --list` 当前启用 53 个算子作为全量 benchmark 对象。`scripts/test/benchmark_all_ops_scales.py` 会对每个算子执行 6 个规模点，输出 CPU/GPU median 耗时、e2e speedup、kernel speedup、误差指标和 pass/fail。

规模族包括：

| scale family | 默认规模 | large-gpu 规模 | 典型算子 |
|---|---|---|---|
| `linear_points` | `1024` 到 `1048576` | `65536` 到 `16777216` | 点式、窗口、波形、样条 |
| `medium_1d_fft` | `1024` 到 `32768` | `32768` 到 `1048576` | FFT、滤波、谱分析、CWT |
| `heavy_quadratic` | `256` 到 `8192` | 同默认 | `ambgfun`、`lombscargle`、`correlate` |
| `matrix_total` | `4096` 到 `1048576` | 同默认 | 雷达、二维相关、矩阵类算子 |
| `filter_design_taps` | `129` 到 `4097` | 同默认 | 滤波器设计 |
| `small_state` | `16` 到 `512` | 同默认 | 小状态 helper |
| `kalman_points` | `16` 到 `512` | `512` 到 `524288` | `kalman_filter` 批处理点数 |
| `istft_frames` | `9` 到 `257` | 同默认 | `istft` |

### 3.3 赛题任务与核心算子关系

| 任务 | 核心链路 | 代表算子 |
|---|---|---|
| Task1 雷达目标检测与多普勒分析 | 回波生成、脉冲压缩、脉冲多普勒、CA-CFAR、模糊函数 | `pulse_compression`, `pulse_doppler`, `ca_cfar`, `ambgfun` |
| Task2 多域特征提取定位 | 滤波、FM 解调、模板相关、时频分析、CWT、融合、峰值跟踪、Kalman 平滑 | `firfilter`, `fm_demod`, `correlate`, `spectrogram`, `cwt`, `kalman_filter` |

## 4. 数据结构、内存模型与误差口径

### 4.1 单精度与复数表示

当前主线统一采用单精度：

- 实数：`float32`，项目默认类型为 `cusignal::core::Scalar = float`。
- 复数：`complex64` 语义，Host 使用 `std::complex<float>`。
- Device 侧复数通过 `DeviceValueTraits<Complex>` 映射到 CUDA 友好的 `float2` 存储。

公开接口保留部分 `dtype` 参数以降低接口破坏面，但 CPU/CUDA 验证和 benchmark 口径已收敛到单精度。这样可以避免 double CPU 对 float GPU 的不公平比较，也更符合当前 A100 验证环境的吞吐特点。

### 4.2 Host/Device 容器

| 类型 | 位置 | 用途 |
|---|---|---|
| `RealSignal` / `ComplexSignal` | Host | 一维信号 |
| `RealArray` / `ComplexArray` | Host | N 维张量 |
| `ZxGpuRealSignal` / `ZxGpuComplexSignal` | Device | 一维设备信号 |
| `ZxGpuRealArray` / `ZxGpuComplexArray` | Device | N 维设备张量 |
| `DeviceSignal<T>` / `DeviceArray<T>` | Device 容器模板 | 管理设备存储、shape 和 H2D/D2H |

部分 ZQ500 GPU API 接受 Host 或 Device 输入，使 perf runner 和任务链路可以预上传数据，避免把 H2D/D2H 固定开销混入每次 timed path。

### 4.3 DeviceStorage 缓存

`include/cusignal/core/types.hpp` 中的 `DeviceStorage<T>`、`DeviceStorageCache<T>` 和 `make_device_storage` 为 device 容器底层提供 type-specific、device-aware、thread-local allocation cache。

关键机制：

- `DeviceStorage<T>` 记录 `data`、`capacity` 和 `device_id`。
- `device_storage_cache<T>()` 使用 thread-local 缓存，按类型隔离。
- `make_device_storage` 优先复用同设备、容量足够且最接近需求的缓存块。
- `recycle_device_storage` 将小于阈值的块回收到缓存，超过阈值或关闭缓存时释放。
- 环境变量 `CUSIGNAL_DISABLE_DEVICE_STORAGE_CACHE` 可关闭缓存。

技术价值：

- 减少反复 `cudaMalloc/cudaFree` 的开销。
- 降低轻量算子 e2e copy-bound 的影响。
- 支撑 Task1/Task2 中间结果和 workspace 的 device-resident 流程。

### 4.4 mixed_error 精度口径

传统相对误差在参考值接近零时容易被放大。项目保留 `max_abs_error`、`max_rel_error`、`rmse`，并在全量报告中使用 `mixed_error` 作为主误差展示。

| 指标 | 含义 | 使用场景 |
|---|---|---|
| `max_abs_error` | 最大绝对误差 | 参考值接近零时判断真实差异 |
| `max_rel_error` | 最大相对误差 | 非零参考值下判断比例偏差 |
| `rmse` | 均方根误差 | 描述整体误差水平 |
| `mixed_error` | 近零保护后的主误差 | benchmark 和任务报告的主要展示口径 |

答辩时要强调：`mixed_error` 不放宽单元测试阈值，它只是让报告中的主误差更符合数值直觉；原始误差仍保留在单算子 `latest_metrics.json` 中用于追溯。

### 4.5 e2e speedup 与 kernel speedup

| 指标 | 定义 | 解释 |
|---|---|---|
| CPU median | CPU 参考路径中位耗时 | 性能基线 |
| GPU e2e median | 包含必要数据搬运、同步和 API 包装的 GPU 总耗时 | 用户调用收益 |
| GPU kernel median | 主要设备计算耗时 | 并行计算本身收益 |
| e2e speedup | CPU median / GPU e2e median | 工程交付口径 |
| kernel speedup | CPU median / GPU kernel median | 算法并行化潜力 |

有些算子 kernel speedup 很高但 e2e speedup 一般，通常不是 kernel 失败，而是 API 粒度小、H2D/D2H 占比高、分配或阶段回传占比高。后续优化方向是算子融合、批处理和 device-resident pipeline。

### 4.6 Workspace 与缓存分层

ZQ500 GPU 后端大量使用 thread-local workspace，而不是在每次调用中重复创建临时对象。缓存分为三层：

| 层级 | 代表实现 | 缓存对象 | 解决的问题 |
|---|---|---|---|
| 底层分配缓存 | `DeviceStorageCache<T>` | device allocation block | 减少 `cudaMalloc/cudaFree` 固定开销 |
| 模块 workspace | `FilteringWorkspace`、`SpectralWorkspace`、`WindowWorkspace`、`AmbgfunWorkspace` | cuFFT plan、line bases、window/template、metadata、临时 buffer | 降低 repeat 与多规模 benchmark 中的重复准备成本 |
| 算子级 prepared cache | `firwin2_cache`、`resample_window_key`、`resample_poly_filter_key`、`segment_window_key`、`cwt_cache_*` | 频谱模板、窗口、polyphase filter、分段窗、小波核表 | 让计时路径更接近真实 device 计算，而不是反复构造固定数据 |

这种缓存设计的边界也很明确：公开 API 不依赖缓存命中，缓存只影响性能；精度和业务检查仍由 CPU/CUDA 对照、单元测试和任务 validation 决定。

## 5. 任务 1：雷达目标检测与多普勒分析

### 5.1 任务链路

Task1 位于 `demo/task1_radar/`，核心流程如下：

1. 生成或读取脉冲回波场景。
2. 执行脉冲压缩，将回波与模板做频域匹配滤波。
3. 执行脉冲多普勒处理，生成距离-多普勒响应。
4. 执行 CA-CFAR，输出阈值和检测结果。
5. 执行 `ambgfun`，生成模糊函数曲面。
6. 写出 metrics、summary、阶段耗时、CSV 样本和可视化图件。

### 5.2 关键算子

| 阶段 | 实现要点 | 证据 |
|---|---|---|
| `pulse_compression` | 频域模板共轭、批量 cuFFT、频域乘法、IFFT | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_pulse_compression.cpp` |
| `pulse_doppler` | 脉冲维 FFT、矩阵 packing、padding/truncation 安全处理 | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_pulse_doppler.cpp` |
| `ca_cfar` | 1D 短窗 direct kernel、长窗 FFT 卷积、2D row-prefix + integral-image | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_ca_cfar.cpp` |
| `ambgfun` | 时延-多普勒二维搜索、归一化缓存、tile FFT workspace | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_ambgfun.cpp` |

### 5.3 Task1 验收

Task1 demo 内部写出：

- `validation.pass`
- `validation.checks`
- `resource_usage.before/after`
- `repeat_runs`
- CPU/GPU 阶段耗时
- `pulse_compression`、`pulse_doppler`、`cfar_threshold`、`ambgfun_surface` 等误差指标

核心 gate：

- CPU/GPU 检测结果一致。
- GPU 检测命中注入目标。
- 关键阶段 `mixed_error` 达到阈值。
- repeat 运行中业务和数值检查均通过。
- GPU timing jitter、CUDA free memory drift 和 RSS drift 在阈值内。

## 6. 任务 2：多域特征提取定位

### 6.1 任务链路

Task2 位于 `demo/task2_features/`，核心流程如下：

1. 生成多帧接收信号和目标/干扰场景。
2. 进行滤波和 FM 解调。
3. 执行模板相关匹配。
4. 对代表帧执行 `spectrogram` 时频分析。
5. 执行 CWT 多尺度特征提取。
6. 在 GPU 侧融合相关、解调、谱分析和小波特征。
7. 进行逐行峰值跟踪和 Kalman 轨迹平滑。
8. 写出 metrics、summary、阶段耗时、CSV 样本和可视化图件。

### 6.2 关键算子与后处理

| 阶段 | 实现要点 | 证据 |
|---|---|---|
| `fm_demod` | `fm_demod_phase_difference_kernel` 融合相邻复样本相位差，减少 angle/unwrap/diff 多阶段开销 | `src/zhongkexin/demod.cu`、`tests/unit/demod/test_fm_demod.cpp` |
| `correlate` | 模板匹配，当前 N 维 direct kernel 仍是后续优化对象 | `src/zhongkexin/correlate.cu`、`tests/unit/correlate/test_correlate.cpp` |
| `spectrogram` | 分段、去均值、加窗、批量 R2C/C2C FFT、PSD kernel | `src/zhongkexin/spectral.cu`、`tests/unit/spectral/test_spectrogram.cpp` |
| `cwt` | 小波核表缓存、`ricker` shared-memory tile kernel | `src/zhongkexin/wavelets.cu`、`tests/unit/wavelets/test_cwt.cpp` |
| fused 后处理 | `fused_feature_smooth_kernel`、`row_peak_track_kernel`、`kalman_track_from_peaks_kernel` | `demo/task2_features/task2_features_zx_gpu.cu` |
| Kalman | points-batched fixed-dim register fast path，任务级使用 RMSE / track match gate | `src/zhongkexin/estimation.cu`、`tests/unit/estimation/test_kalman_filter.cpp` |

### 6.3 Task2 验收

核心 gate：

- CPU/GPU track 一致。
- GPU Kalman track 在 truth 容差内。
- `filtered`、`correlate`、`spectrogram`、`cwt`、`feature_score` 的 `mixed_error` 达标。
- `kalman_track` 的正式 gate 是 track match 与 RMSE 容差，不简单套用单算子 `1e-4`。
- repeat 稳定性、资源漂移和异常输入检查通过。

## 7. 技术亮点与创新点

本节是答辩重点。每个亮点都落到具体实现锚点，不把空泛的“GPU 加速”“工程优化”单独作为亮点。

### 7.1 算法并行化亮点

| 亮点 | 难点 | 方案 | 价值 | 证据 |
|---|---|---|---|---|
| `sosfilt` 递推算子 prefix-scan | IIR / SOS 有前后样本依赖，不能简单逐点并行 | 将状态转移改写为 affine transform，使用 `sosfilt_prefix_tiles_kernel`、`sosfilt_scan_tile_transform_blocks_kernel`、`sosfilt_apply_tile_initials_kernel` 做分层 scan | 把长序列递推转化为可并行组合的 tile 状态传播 | `src/zhongkexin/filtering.cu`、`tests/unit/filtering/test_sosfilt.cpp`、`scripts/test/READMEV3_5_0.md` |
| `detrend` 两级 reduction 与 Kahan 补偿 | 常量/线性去趋势要按 axis 归约，单精度下累积顺序影响 CPU/CUDA 一致性 | 使用 `detrend_constant_partials_kernel`、`detrend_linear_partials_kernel`、`detrend_linear_coefficients_kernel`、`detrend_*_apply_kernel`，局部循环采用 float Kahan 补偿 | 在保持单精度口径的同时降低真实误差，并支持多行批量处理 | `src/zhongkexin/filtering.cu`、`tests/unit/filtering/test_detrend.cpp`、`scripts/test/READMEV3_7_0.md` |
| 批量 FFT 频域加速 | 雷达、重采样和谱分析需要长序列 FFT、分段 FFT、复实路径和 PSD 后处理 | 使用 cuFFT batch plan、`cufftExecC2C`、`cufftExecR2C`、`prepare_segments_*_kernel`、`spectrogram_psd_r2c_kernel` 等设备侧准备和后处理 | 在大规模输入下释放 FFT 吞吐，减少 Host 侧循环 | `src/zhongkexin/radartools.cu`、`src/zhongkexin/filtering.cu`、`src/zhongkexin/spectral.cu` |
| CA-CFAR 多策略实现 | 训练窗/保护窗边界复杂，1D/2D、短窗/长窗适合的算法不同 | 1D 短窗走 direct kernel，长窗走 FFT 卷积；2D 大窗口走 row-prefix + integral-image，用外窗减内窗计算 training cells | 兼顾小窗口低开销与大窗口吞吐，且保持 CPU 语义一致 | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_ca_cfar.cpp`、`scripts/test/READMEV3_7_0.md` |
| `vectorstrength` / `lombscargle` 并行归约 | 每个 period/frequency 上存在 sample 维串行循环，且 near-zero relative error 容易放大 | `vectorstrength_partial_kernel` + `vectorstrength_finalize_kernel` 做 two-stage reduction；`lombscargle_parallel_kernel` 改为 one-block-per-frequency shared reduction，mean/dot 保留在 device 上 | 提升重计算类算子的 GPU 并行度，并减少 repeat 内 D2H 同步 | `src/zhongkexin/spectral.cu`、`tests/unit/spectral/test_vectorstrength.cpp`、`tests/unit/spectral/test_lombscargle.cpp`、`scripts/test/READMEV3_8_4.md` |
| `fm_demod` 相位差融合 | 传统 phase -> unwrap -> diff 多阶段会产生中间数组和同步开销 | `fm_demod_phase_difference_kernel` 直接计算相邻复样本相位差，保留 fallback phase/unwrap/diff 路径 | 降低 Task2 解调阶段中间数据量和 e2e 开销 | `src/zhongkexin/demod.cu`、`tests/unit/demod/test_fm_demod.cpp` |
| `pulse_doppler` 安全 packing | 多脉冲矩阵需要处理 padding、truncation 和 FFT 维度对齐，越界风险高 | 在 CUDA packing kernel 中显式处理脉冲/采样维边界，并用 cuFFT 批量处理脉冲维 | 支撑 Task1 距离-多普勒响应的稳定生成 | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_pulse_doppler.cpp`、`scripts/test/README.md` |
| MVDR 线性代数路径 | 波束形成涉及复数协方差、矩阵分解和线性方程求解，手写 kernel 风险高 | 用 `cublasCgemm` 构造协方差，用 `cusolverDnCgetrf/getrs` 求解，用 `cublasCdotc` 计算响应 | 用成熟库原语处理高风险线性代数，降低数值和实现复杂度 | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_mvdr.cpp` |

### 7.2 内存、缓存与数据驻留亮点

| 亮点 | 难点 | 方案 | 价值 | 证据 |
|---|---|---|---|---|
| `DeviceStorage` 分配缓存 | 轻量算子 e2e 易被 `cudaMalloc/cudaFree`、清零和 H2D/D2H 掩盖 | `DeviceStorage<T>`、`DeviceStorageCache<T>`、`make_device_storage` 提供 type-specific、device-aware、thread-local allocation cache，并保留 `CUSIGNAL_DISABLE_DEVICE_STORAGE_CACHE` 开关 | 降低固定分配开销，使 benchmark 更能反映计算本身 | `include/cusignal/core/types.hpp`、`scripts/test/READMEV3_8_3.md` |
| `FilteringWorkspace` 与 line bases cache | `lfilter`、`filtfilt`、`detrend` 等多 axis 线处理需要重复上传 line base/shape 元数据 | 使用 `LineBasesCache`、`upload_line_bases_cached`、`cached_detrend_*`、`wiener_*_buffer` 缓存行基址、breaks、shape/stride/mysize | 减少 repeat 内的 metadata H2D 和准备开销 | `src/zhongkexin/filtering.cu` |
| 重采样与 channelizer prepared cache | `resample`、`resample_poly`、`channelize_poly` 重复构造窗口、polyphase filter 或 padded taps | 缓存 `resample_window_key`、`resample_poly_filter_key`、`cached_channelize_taps`，并在 `upfirdn_kernel` 中只遍历当前 polyphase taps | 降低滤波和重采样类算子的准备成本，提升 large-gpu 复测稳定性 | `src/zhongkexin/filtering.cu`、`scripts/test/READMEV3_8_4.md` |
| `wiener` deterministic reduction | 自动噪声估计如果使用非确定性全局原子累加，误差和复测稳定性都会受影响 | 局部统计和噪声估计保留在 device 上，两级求和后由 `wiener_apply_auto_noise_kernel` 使用稳定单精度结果 | 兼顾性能和可复现精度，避免 repeat 间随机抖动 | `src/zhongkexin/filtering.cu`、`tests/unit/filtering/test_wiener.cpp`、`scripts/test/READMEV3_8_1.md` |
| `SpectralWorkspace` 分段窗与 plan 复用 | `spectrogram`、`csd`、`stft` 要反复构造 window、time/frequency axis 和 FFT plan | 缓存 `segment_window_storage/key/scale`，复用 `real_forward_plan`，实输入优先走 R2C fast path | 提升批量谱分析吞吐，减少重复 window H2D | `src/zhongkexin/spectral.cu`、`tests/unit/spectral/test_spectrogram.cpp`、`tests/unit/spectral/test_csd.cpp` |
| `firwin2` full-spectrum template cache | FIR 设计需要插值频响、构造全频谱、执行 FFT，计时循环内重复准备代价高 | `Firwin2PreparedCache` 缓存参数、window、`spectrum_template` 和 `firwin2_window_template`，命中时只做 D2D copy 后 FFT | 让 filter design benchmark 的 timed path 更接近 device 计算 | `src/zhongkexin/filter_design.cu`、`tests/unit/filter_design/test_firwin2.cpp`、`scripts/test/READMEV3_8_3.md` |
| `WindowWorkspace` 与 `chebwin` 缓存 | Chebyshev window 的频响模板和归一化窗口构造成本高 | GPU kernel 生成 frequency response template，缓存 `chebwin_template_*` 和 `chebwin_final_*`，归一化使用 `cub::DeviceReduce::Max` | 大规模窗口生成 repeat 命中时主要是分配和 D2D copy | `src/zhongkexin/windows.cu`、`tests/unit/windows/test_chebwin.cpp`、`scripts/test/READMEV3_8_4.md` |
| `ambgfun` tile FFT 与归一化缓存 | 时延-多普勒二维 surface 输出大，L6 存在显存和写回压力 | `AmbgfunWorkspace` 缓存 normalized input，按可用显存选择 tile rows，并复用 2D tile FFT workspace | 控制峰值显存，把瓶颈收敛到 tile FFT 和大 surface 写回 | `src/zhongkexin/radartools.cu`、`tests/unit/radartools/test_ambgfun.cpp`、`scripts/test/READMEV3_8_4.md` |
| CWT 小波核缓存与 shared-memory tile | 多尺度卷积重复生成 kernel table，`ricker` 相邻 sample global load 重复 | 缓存 `cwt_cache_wavelet`、`cwt_cache_widths`、`cwt_cache_valid`，`ricker` 使用 `cwt_ricker_shared_kernel` | 减少 CPU table 构造、H2D 和重复 global load | `src/zhongkexin/wavelets.cu`、`tests/unit/wavelets/test_cwt.cpp`、`scripts/test/READMEV3_8_4.md` |

### 7.3 任务级融合与业务闭环亮点

| 亮点 | 难点 | 方案 | 价值 | 证据 |
|---|---|---|---|---|
| Task2 fused 后处理 | 多域特征如果逐阶段回传 Host，会削弱 e2e 加速 | `fused_feature_smooth_kernel`、`row_peak_track_kernel`、`kalman_track_from_peaks_kernel` 在 device 侧完成融合、峰值跟踪和轨迹平滑 | 证明项目不只做单算子，也能做任务级 device pipeline | `demo/task2_features/task2_features_zx_gpu.cu`、`demo/task2_features/task2_features_demo.cpp` |
| Kalman points-batched fast path | 单条 Kalman 轨迹状态小、递推强，单实例并行度有限 | 对 `kalman_points` 扩展批量点数，固定小维度使用 `predict_fixed_kernel<4, 2>`、`update_fixed_kernel<4, 2>` 等寄存器 fast path | 让状态估计在任务和 benchmark 中具备足够 GPU 并行度 | `src/zhongkexin/estimation.cu`、`tests/unit/estimation/test_kalman_filter.cpp`、`scripts/test/benchmark_all_ops_scales.py` |
| 峰值筛选 CUB 路径 | 极值检测需要按比较结果收集索引，手写 compact 易低效 | 使用 `cub::DeviceSelect::Flagged` 进行 device 侧筛选 | 为 Task2 峰值定位和独立 peak finding 算子提供高效基础 | `src/zhongkexin/peak_finding.cu`、`tests/unit/peak_finding/` |
| Task1 雷达链路组合 | 单个雷达算子通过不等于链路业务正确 | 将 `pulse_compression`、`pulse_doppler`、`ca_cfar`、`ambgfun` 串成端到端 demo，并检查检测命中、误差、阶段耗时和图件 | 把算子能力转化为赛题可展示任务 | `demo/task1_radar/`、运行后 `data/reports/demo/task1_radar/` |
| Task2 多域链路组合 | 滤波、解调、相关、谱分析、CWT、Kalman 的误差口径不同 | 任务级 gate 区分 `mixed_error`、track match 和 RMSE，不把所有输出简单套同一阈值 | 更符合真实业务指标，也避免误把 Kalman 轨迹评估当逐点数组误差 | `demo/task2_features/`、运行后 `data/reports/demo/task2_features/` |

### 7.4 验证、报告与复测亮点

| 亮点 | 难点 | 方案 | 价值 | 证据 |
|---|---|---|---|---|
| 81 个单测入口统一报告 | 模块多、输出类型多，如果报告 schema 不一致就难以汇总 | `tests/unit/common/report.hpp` 统一写出 `latest_metrics.json`、`latest_summary.md`、`latest_cases.csv` | 让每个算子的误差、耗时和 case 细节都可追溯 | `tests/unit/**/test_*.cpp`、`tests/unit/common/report.hpp` |
| 53 算子六档 benchmark | 单一规模无法解释小规模 copy-bound 与大规模吞吐差异 | `DEFAULT_SCALE_FAMILIES`、`LARGE_GPU_SCALE_FAMILIES`、`scale_level=1..6` 统一采集 e2e/kernel timing 和误差 | 可以讲清楚规模效应，而不是只展示一个最好数字 | `scripts/test/benchmark_all_ops_scales.py`、运行后 `data/reports/unit/benchmarks/` |
| GPU-only 复测与 CPU baseline cache | 全量 `53 x 6 x repeat30` CPU 计时成本高，现场复测不现实 | `--gpu-only` 复用 `latest_cpu_baseline.json`，`--cpu-baseline-mode auto/refresh/reuse` 控制补齐、重建或严格复用 | 支持现场快速复测 GPU timing，同时保持 CPU baseline 口径可追踪 | `scripts/test/README.md`、`scripts/test/benchmark_all_ops_scales.py` |
| 全量精度审计 | 单个 benchmark 通过后仍需要发现高误差队列和修复状态 | `audit_all_ops_precision.py` 生成 `latest_precision_baseline.csv`、`latest_precision_fix_queue.csv`、`latest_precision_perf_snapshot.csv`、`latest_precision_fix_report.md` | 把误差风险从人工抽查变成可复跑清单 | `scripts/test/audit_all_ops_precision.py`、运行后 `data/reports/unit/audit/` |
| Task demo 自验收 | demo 不能只生成图，必须自动判断是否通过 | C++ demo 写 `ValidationResult`、`ValidationThresholds`、`resource_usage`、`repeat_runs`；失败时可执行程序返回非零 | 让 Task1/Task2 具备 CI/验收属性 | `demo/task1_radar/task1_radar_demo.cpp`、`demo/task2_features/task2_features_demo.cpp`、`scripts/test/run_task_demos.sh` |
| 异常输入与资源漂移 gate | 正常路径通过不足以证明工程稳健性 | `--invalid-input-checks` 要求非法配置抛出明确字段名；repeat 检查 GPU timing jitter、CUDA free memory drop 和 RSS growth | 覆盖鲁棒性、稳定性和资源泄露早期信号 | `scripts/test/READMEV3_9.md`、`demo/task1_radar/`、`demo/task2_features/` |
| compute-sanitizer 深检 | sanitizer 会放大 GPU timing，直接进入性能 gate 会误判 | `run_task_demos.sh --leak-check` 调用 `compute-sanitizer --tool memcheck`，子进程使用 `--skip-timing-validation` | 深检内存/显存错误，同时不污染正常 latest metrics | `scripts/test/run_task_demos.sh`、运行后 `data/reports/demo/leak_check/` |
| 图件与 Word 友好报告链路 | CSV 难以直接用于答辩和文档 | `plot_all_ops_benchmark.py` 输出全局图和单算子图；`run_task_demos.sh --scale-sweep` 自动调用 `plot_task_demo_scale_benchmark.py` | 从 benchmark 数据直接生成可展示图件，减少手工制图误差 | `scripts/test/plot_all_ops_benchmark.py`、`scripts/test/plot_task_demo_scale_benchmark.py` |

不建议包装成核心亮点的内容：

- `radartools/cfar_alpha` 是 scalar helper，应作为 CA-CFAR 公式组成部分说明，不作为 GPU kernel 亮点。
- `lfilter_zi`、`firfilter_zi` 等小状态辅助函数更适合作为接口完整性说明。
- 简单逐点映射类算子如果没有融合、缓存或任务流水支撑，应归入覆盖面，不单独宣称算法创新。

## 8. 验证体系与运行命令

### 8.1 单算子测试

```bash
./scripts/test/run_all_tests.sh --emit-report
./scripts/test/run_all_tests.sh --module spectral --emit-report
./scripts/test/run_all_tests.sh --module radartools --operator ca_cfar --emit-report
```

输出：

- 运行后 `data/reports/unit/<module>/<operator>/latest_metrics.json`
- 运行后 `data/reports/unit/<module>/<operator>/latest_summary.md`

### 8.2 全量 53 算子六档 benchmark

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

输出：

- 运行后 `data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv`
- 可选报告和分模块 CSV，取决于 `--report-mode`

常用口径：

- `--report-mode csv`：只保留主 CSV，适合日常复测。
- `--report-mode concise`：额外生成 Markdown 简表，适合快速查看。
- `--report-mode full`：生成时间戳归档、分模块 CSV 和候选细表，适合提交前归档。
- `--demo-fast`：未显式指定时使用较小 `warmup/repeat`，适合现场冒烟，不作为严谨性能结论。

### 8.3 GPU-only 复测与 CPU baseline cache

```bash
scripts/test/benchmark_all_ops_scales.py \
  --no-build --build-dir build \
  --scale-profile large-gpu \
  --gpu-only \
  --cpu-baseline-mode reuse \
  --cpu-baseline-file data/reports/unit/benchmarks/cpu_baselines/large-gpu/latest_cpu_baseline.json \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large_gpu_only
```

说明：

- `--gpu-only` 只重新采集 GPU e2e/kernel timing。
- `cpu_perf`、`mixed_error`、`pass`、`error_class` 来自 CPU baseline cache。
- `--cpu-baseline-mode refresh` 用于重建 baseline；`reuse` 要求 cache 已完整存在，适合最终验收时固定口径。

### 8.4 全量精度审计

```bash
scripts/test/audit_all_ops_precision.py --no-build --build-dir build
```

输出：

- 运行后 `data/reports/unit/audit/latest_precision_baseline.csv`
- 运行后 `data/reports/unit/audit/latest_precision_fix_queue.csv`
- 运行后 `data/reports/unit/audit/latest_precision_perf_snapshot.csv`
- 运行后 `data/reports/unit/audit/latest_precision_perf_delta.csv`
- 运行后 `data/reports/unit/audit/latest_precision_fix_report.md`

该脚本用于把所有算子的精度风险、修复队列和性能快照集中起来，不替代单测和 benchmark，而是作为提交前误差体检。

### 8.5 全量 benchmark 图件

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
  --figure-set all \
  --dpi 450
```

典型图件：

- `figure_1_accuracy_performance_overview.png`
- `figure_2_cpu_gpu_e2e_time_heatmaps.png`
- `figure_3_e2e_speedup_heatmap.png`
- `figure_4_largest_scale_cpu_vs_gpu_scatter.png`
- `figure_5_largest_scale_speedup_rank.png`
- `operator_figures/<module>__<operator>.png`

### 8.6 Task1/Task2 任务级验收

```bash
scripts/test/run_task_demos.sh --no-build --repeat 5
```

输出：

- 运行后 `data/reports/demo/task1_radar/latest_metrics.json`
- 运行后 `data/reports/demo/task2_features/latest_metrics.json`
- 运行后 `data/reports/demo/latest_task_demo_report.md`

### 8.7 Task1/Task2 六档规模扫测

```bash
scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 3
```

输出：

- 运行后 `data/reports/demo/latest_task_demo_scale_benchmark.csv`
- 运行后 `data/reports/demo/latest_task_demo_scale_report.json`
- 运行后 `data/reports/demo/latest_task_demo_scale_report.md`
- 运行后 `data/reports/demo/task1_radar/scales/L<N>/`
- 运行后 `data/reports/demo/task2_features/scales/L<N>/`
- 运行后 `data/reports/demo/task1_radar/task1_l1_l6_scale_performance.[png|svg|pdf]`
- 运行后 `data/reports/demo/task1_radar/task1_l1_l6_scale_performance_word.[png|svg|pdf]`
- 运行后 `data/reports/demo/task2_multidomain_l1_l6_scale_performance.[png|svg]`

`--scale-sweep` 写完 CSV 后会自动调用 `plot_task_demo_scale_benchmark.py`，覆盖生成 Word 友好的 Task1/Task2 L1-L6 性能图。

### 8.8 深度内存/显存检查

```bash
scripts/test/run_task_demos.sh --no-build --repeat 2 --leak-check
```

行为：

- 若 `compute-sanitizer` 可用，脚本会分别包裹 Task1/Task2 demo。
- sanitizer 子进程使用 `--skip-timing-validation`，避免 timing gate 被放大耗时污染。
- 正常 latest metrics 会在深检后恢复。

输出：

- 运行后 `data/reports/demo/leak_check/*_compute_sanitizer.log`

## 9. 报告与证据索引

| 证据类型 | 路径 | 说明 |
|---|---|---|
| 项目总览 | `README.md` | 项目能力、环境、快速开始、测试和报告入口 |
| 统一主技术文档 | `docs/submission/technical_document_framework_final.md` | 本文 |
| 历史提交说明 | `docs/submission/READMEV*.md` | 版本记录，不作为主技术文档 |
| 历史设计计划 | `docs/design/*.md` | 方案演进，不作为主技术文档 |
| 测试脚本总览 | `scripts/test/README.md` | 当前测试脚本和 benchmark 使用说明 |
| 任务级验收说明 | `scripts/test/READMEV3_9.md` | repeat、scale sweep、compute-sanitizer 等最新验收口径 |
| 公开 API | `include/cusignal/` | 后端迁移边界 |
| CPU 参考 | `src/cpu/` | 精度和业务基线 |
| 公共 detail 层 | `src/common/` | CPU/CUDA 共用 shape、axis、窗口、频率轴和参数校验语义 |
| ZQ500 GPU 实现 | `src/zhongkexin/` | GPU 技术亮点落点 |
| 单元测试 | `tests/unit/` | 81 个测试入口 |
| 单测公共报告层 | `tests/unit/common/` | 统一 metrics、summary、cases CSV 和 CPU baseline JSON 读写 |
| Task1 demo | `demo/task1_radar/` | 雷达任务源码和可视化 |
| Task2 demo | `demo/task2_features/` | 多域特征定位源码和可视化 |
| 数据生成脚本 | `scripts/data/` | 生成 reference/generated 数据和 manifest |
| 全量 benchmark 脚本 | `scripts/test/benchmark_all_ops_scales.py` | 53 算子六档规模、GPU-only 和 CPU baseline cache 入口 |
| 精度审计脚本 | `scripts/test/audit_all_ops_precision.py` | 误差基线、修复队列和性能快照入口 |
| benchmark 作图脚本 | `scripts/test/plot_all_ops_benchmark.py` | 全局图、单算子图和 Word 友好图件入口 |
| 任务规模作图脚本 | `scripts/test/plot_task_demo_scale_benchmark.py` | Task1/Task2 L1-L6 规模图件入口 |
| 固定基准数据 | `data/reference/` | 仓库内维护的 accuracy reference |
| 运行期生成数据 | `data/generated/` | demo/perf 运行生成的输入和样本 |
| 运行报告 | `data/reports/` | 运行后 metrics、summary、CSV、图件 |

## 10. 性能分析与当前不足

### 10.1 小规模瓶颈

小规模或点式算子的 e2e speedup 可能不明显，主要原因是：

- H2D/D2H 固定开销占比高。
- kernel launch 和同步开销不可忽略。
- API 粒度较小，单次调用计算量不足。
- 为了可解释和 CPU/GPU 对照，部分链路保留阶段式回传。

应对方向：

- 将轻量算子放入更长 GPU pipeline 中评估。
- 增加批处理接口和 device-resident fast path。
- 对任务链路做算子融合，减少 Host 中间回传。

### 10.2 大规模吞吐

大规模场景中 GPU 优势更明显，原因是：

- 批量 FFT 释放更高并行度。
- prefix-scan、归约、积分图、CUB 原语等减少串行瓶颈。
- DeviceStorage 和 thread-local workspace 降低重复分配成本。
- Task1/Task2 的多阶段链路更适合 device 侧缓存和流水。

可讲述的具体落点包括：

| 方向 | 代表实现 | 说明 |
|---|---|---|
| reduction 单精度对齐 | `detrend`、`vectorstrength`、`wiener` | 通过两级 reduction、shared memory、Kahan 补偿或 deterministic sum 降低误差和 repeat 抖动 |
| FFT 路径精简 | `resample`、`spectrogram`、`pulse_compression`、`pulse_doppler` | 复用 plan，区分 R2C/C2C，设备侧完成频谱复制、Nyquist 调整、PSD 或 packing |
| prepared cache | `firwin2`、`chebwin`、`resample_poly`、`cwt` | 把重复构造的 template/window/filter/kernel table 移出 timed path |
| 大输出控制 | `ambgfun`、Task demo scale sweep | tile workspace 和 scale sweep 暴露大 surface 写回瓶颈，后续可按任务需求裁剪输出范围 |
| device-resident 后处理 | Task2 fused kernels、Kalman track | 减少中间 Host 回传，把多域特征直接转成业务轨迹 |

### 10.3 当前不足

| 不足 | 原因 | 后续方向 |
|---|---|---|
| 小规模 e2e 加速不稳定 | 固定开销占比高 | 批处理、融合、device-resident pipeline |
| 部分任务仍按阶段回传 | 为了可视化、调试和 CPU/GPU 对照 | 增加纯设备侧 fast path，同时保留 debug 模式 |
| 部分 copy-bound 算子 kernel 很快但 e2e 一般 | 数据搬运和 API 包装主导 | 减少 H2D/D2H，合并相邻算子 |
| `ambgfun` 等重输出算子仍有布局瓶颈 | L6 surface 输出和 tile FFT workspace 压力大 | 研究输出裁剪、分块布局和任务需求驱动的计算范围 |
| 国产 GPU 尚未实测 | 当前阶段是 CUDA 基线 | 按统一 API 和测试闭环替换后端并复测 |

## 11. 国产 GPU 迁移策略

迁移目标不是重写上层算法，而是替换底层后端。

| 迁移对象 | CUDA 当前依赖 | 迁移风险 | 应对策略 |
|---|---|---|---|
| FFT | cuFFT | plan、batch、R2C/C2C 行为和数值误差差异 | 建立 FFT wrapper，先验证 spectral/radartools/wavelets |
| BLAS | cuBLAS | 复数 GEMM、dot、norm 差异 | 用小矩阵和 MVDR 单测建立基线 |
| SOLVER | cuSOLVER | LU 分解、info 返回、workspace 差异 | 先验证 `mvdr`，再扩展线性代数路径 |
| 并行原语 | CUB | select/reduce/scan 替代能力 | 抽象选择和归约 helper，逐个替换 |
| 自定义 kernel | ZQ500 GPU kernel | 线程模型、shared memory、同步语义差异 | 逐模块移植，保持测试和报告不变 |
| Runtime | CUDA Runtime | 内存、事件、设备信息 API 差异 | 封装内存与 timing 层，保持 metrics schema |

迁移验证顺序：

1. 编译公开 API 和核心类型。
2. 跑 smoke demo。
3. 跑单模块 accuracy。
4. 跑 53 算子 benchmark。
5. 跑 Task1/Task2 默认 L3。
6. 跑 Task1/Task2 L1-L6 scale sweep。
7. 跑资源漂移和可选 sanitizer/平台等价检查。

## 12. 答辩问答要点

| 问题 | 回答要点 |
|---|---|
| 为什么不是只做两个 demo？ | 赛题需要可复用信号处理库。项目先完成 81 个测试入口和 CPU/CUDA 双后端，再用 Task1/Task2 证明库函数可组合成业务链路。 |
| 为什么保留 CPU 后端？ | CPU 是参考实现、误差基线和迁移安全网。没有 CPU 后端就很难证明 CUDA 输出正确。 |
| 如何保证 CPU/CUDA 一致？ | 同名接口、公共参数语义、单精度口径、`mixed_error`、单算子测试和任务级 validation 共同约束。 |
| 为什么有些算子 e2e 加速不高？ | e2e 包含搬运、同步和 API 包装，小规模算子容易 copy-bound；kernel speedup 和 e2e speedup 必须分开解释。 |
| `mixed_error` 是不是降低精度要求？ | 不是。原始 `max_abs_error`、`max_rel_error`、`rmse` 仍保留并参与追溯；`mixed_error` 只是避免参考值接近零时相对误差被放大成误导性主指标。 |
| 为什么需要 GPU-only benchmark？ | 全量 CPU 基线很耗时，现场复测适合复用固定 CPU baseline cache，只重新采 GPU e2e/kernel timing；最终报告要说明 baseline 来源和 warmup/repeat。 |
| 为什么强调 task validation 而不是只看图？ | 图件用于展示，但验收必须由 `validation.pass`、业务 gate、误差 gate、repeat、资源漂移和异常输入检查自动判断。 |
| 最大技术亮点是什么？ | 不是单个 kernel，而是 CPU/CUDA 双后端、81 算子覆盖、53 算子六档 benchmark、Task1/Task2 自验收和报告可追溯形成的完整工程闭环。 |
| 如何迁移到中科芯 GPU？ | 保持 API、测试数据和报告口径，替换 FFT/BLAS/SOLVER/CUB/runtime/custom kernel 后端，再按单算子到任务级顺序复测。 |

## 13. 文档合并说明

为避免技术文档分散，当前提交材料按以下规则组织：

- 本文是唯一主技术文档，集中说明背景、架构、算子覆盖、任务链路、技术亮点、验证体系、性能分析和迁移策略。
- `docs/submission/technical_defense_whitepaper.md` 的答辩亮点内容已并入本文，不再单独保留。
- `docs/submission/technical_doc_revision_notes.md` 的旧 Word 改稿清单已被本文取代，不再单独保留。
- `docs/submission/READMEV*.md`、`docs/design/*.md` 和 `scripts/test/READMEV*.md` 作为历史版本记录保留，用于追溯具体迭代，但不作为提交或答辩时的主技术文档。
- 若后续继续补充技术亮点，应优先更新本文第 7 章，并确保每个亮点都能落到具体源码、脚本、测试或运行报告路径。
