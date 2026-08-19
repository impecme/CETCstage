# CETC 最终架构说明

本文描述最终交付代码的稳定结构。当前产品是面向中科芯 ZQ500 的 C++17
信号处理库，采用 CPU reference 与 ZQ500 GPU 双后端。V5.5、V6、V7
性能阶段均已关闭；本文不定义新的性能候选，也不替代冻结报告中的测量结论。

## 1. 系统边界

| 层次 | 主要路径 | 职责 |
| --- | --- | --- |
| 公开接口 | `include/cusignal/` | 模块 API、结果结构、公共类型和聚合头 |
| 公共语义 | `src/common/` | 参数检查、shape/axis、窗口和数学语义 |
| CPU reference | `src/cpu/` | CPU 对照实现，FFT-heavy 路径使用 FFTW |
| ZQ500 GPU | `src/zhongkexin/` | kernel、workspace、ZQ500 兼容库调用和设备缓存 |
| 任务 demo | `demo/task1_radar/`、`demo/task2_features/` | 两条端到端任务链及分步验收 |
| 单元测试 | `tests/unit/` | 12 模块、81 个注册算子的独立测试入口 |
| 平台测试 | `tests/platform/` | ZQ500 compile/runtime/library probe 和禁止 API 扫描 |
| 数据与证据 | `data/reference/`、`data/generated/`、`data/baseline/`、`data/reports/` | 固定参考数据、可再生输入、CPU/GPU 基线和终版结构化报告 |
| 工具脚本 | `scripts/*.sh` | 构建、验证、演示、同步、取回和运行产物清理 |

顶层 CMake 只接受 `CUSIGNAL_PLATFORM=ZHONGKEXIN`，并生成两个核心静态库：

- `cusignal_cpu`：CPU reference。
- `cusignal_zx_gpu`：ZQ500 GPU 后端，公开依赖 `cusignal_cpu` 以支持统一工程链接。

任务可执行文件为 `task1_radar_demo` 和 `task2_features_demo`。unit 与 platform
test 由顶层 CMake 的测试开关统一接入。

## 2. 公开接口模型

调用方可使用聚合头：

```cpp
#include "cusignal/cusignal.hpp"
```

公开实现按后端分为：

- `cusignal::cpu::<module>`：host 输入与 host 输出。
- `cusignal::zx_gpu_backend::<module>`：通常接受 host/device 双态输入，数组输出保持
  device resident。
- `cusignal::core`：标量、张量、device 容器和参数规格。

GPU 数组接口使用 `RealSignalLike`、`ComplexSignalLike`、`RealArrayLike`、
`ComplexArrayLike` 等 `std::variant` 输入。host 输入在入口上传，device 输入直接
复用；`DeviceSignal<T>` 和 `DeviceArray<T>` 只有在调用 `.get()` 时才执行 D2H。
标量接口和部分任务摘要结构按各自公开签名返回。

多返回和分支返回不依赖匿名 tuple：项目使用具名结果结构和 `std::variant`。
例如 chirp 的 real/complex 分支、gausspulse 的单路/多路结果、spectral 结果和
ambgfun 的二维/切片结果均在公开头中显式建模。

## 3. 模块组成

机器注册表 `tests/contracts/operator_sets.json` 的 `all81` 集合覆盖 12 个模块；
赛题范围由 `算子表.xlsx` 的 `task_appendix=53` 冻结。
这里的 81 是独立测试和 benchmark 条目数，不是对所有辅助 public helper 的计数。
其中两个任务源码实际调用的注册算子为 18 项（任务专用 Helper/变体另行记录），
附录中未被任务采用的其余注册算子为 37 项，原生库中不在赛题附录且未被任务采用的
算子为 26 项，三层互斥覆盖 81 项。

| 模块 | 条目数 | 主要职责 |
| --- | ---: | --- |
| `waveforms` | 5 | chirp、脉冲和周期波形生成 |
| `bsplines` | 3 | 样条基函数 |
| `windows` | 23 | 通用窗函数和窗口分发 |
| `filter_design` | 5 | FIR 设计、Kaiser 参数和复数排序 |
| `filtering` | 17 | FIR/IIR、Hilbert、重采样、通道化和去趋势 |
| `radartools` | 6 | 脉冲压缩、多普勒、模糊函数、CFAR 和 MVDR |
| `spectral` | 9 | periodogram、Welch、CSD、STFT 和相关谱估计 |
| `wavelets` | 5 | QMF、Morlet、Ricker 和 CWT |
| `correlate` | 3 | N 维/二维互相关和 lag 元数据 |
| `demod` | 1 | FM 解调 |
| `estimation` | 1 | Kalman filter |
| `peak_finding` | 3 | 相对极值索引 |

Task1 后续增加了 `fftshift_rows`、`power_map`、`detect_peak` 和
`pulse_doppler_shifted` 等 public helper。它们用于让任务步骤调用库接口并减少
中间数组，但不改变 `all81` 的冻结集合。

## 4. 类型与内存模型

项目默认数值域为：

- `core::Scalar = float`，即 FP32。
- `core::Complex = std::complex<float>`，即 complex64。
- device 复数存储映射为 `cuFloatComplex`，并有 host/device 大小静态检查。

`core::Tensor<T>` 承载 N 维 host 数据；`DeviceSignal<T>` 和 `DeviceArray<T>`
通过共享 `DeviceStorage` 管理设备内存。`SignalLike<T>`、`ArrayLike<T>` 使同一
GPU 入口可以接受 host 或 device 容器。FP16 和整数的类型别名、累加规则及兼容
边界见 `docs/DTYPE_SUPPORT.md`。

设备存储缓存具有以下稳定边界：

- 按元素类型、device id 和线程隔离。
- best-fit 复用容量足够的 block。
- 默认最多缓存 8 个 block、总计 512 MiB、单 block 256 MiB。
- 可通过 `CUSIGNAL_DISABLE_DEVICE_STORAGE_CACHE` 关闭。
- `CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS`、`CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB`
  和 `CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB` 仅调整缓存策略，不改变 API
  或数值语义。

V7 已验证扩大缓存对演示四算子聚合收益只有 `0.096%`，最终默认仍使用上述配置。

## 5. CPU 与 ZQ500 GPU 分工

CPU 与 GPU 后端共享参数和 shape 语义，但实现职责不同：

| 组件 | CPU reference | ZQ500 GPU |
| --- | --- | --- |
| 数组所有权 | STL/Tensor host 容器 | `DeviceSignal`/`DeviceArray` |
| FFT | FFTW | ZQ500 FFT 兼容库 |
| 线性代数 | host 数值实现 | ZQ500 BLAS/SOLVER 兼容库和定制小矩阵 kernel |
| 并行计算 | 标准 C++ 循环 | `.cu` 源、ZQ500 kernel、归约和 scan |
| 中间数据 | host 临时数组 | thread-local workspace、plan 和 prepared cache |
| 验证角色 | reference 与业务对照 | 被测加速路径 |

`src/common/*_detail.hpp` 应保存两后端必须一致的规则，例如参数合法性、输出
shape、axis、窗口规格和频率轴构造。平台差异应集中在
`platform_zx_gpu_compat.hpp`、`platform_zx_gpu_libraries.hpp` 或 ZQ500 实现层，
不应渗透为两套相互矛盾的公开语义。

## 6. Task1 架构

Task1 模拟雷达目标检测与多普勒分析。输入构造属于 demo orchestration，正式
计算链共有 6 步，全部有独立 timing 和 accuracy 字段。

| 步骤 | CPU 路径 | ZQ500 GPU 路径 | 分类 |
| --- | --- | --- | --- |
| pulse compression | `radartools::pulse_compression` | 同名 public API | public |
| pulse Doppler + shift | `pulse_doppler` + `fftshift_rows` | `pulse_doppler_shifted` | public |
| power map | `radartools::power_map` | 同名 public API | public |
| CA-CFAR | `radartools::ca_cfar` | 同名 public API | public |
| ambiguity function | `radartools::ambgfun` | 同名 public API | public |
| final detection | `radartools::detect_peak` | 同名 public API | public |

GPU 任务链尽量让脉冲压缩、多普勒矩阵、功率图和检测结果保持 device resident，
只在报告和 CPU/GPU 对照需要时回读。

## 7. Task2 架构

Task2 模拟多域特征提取和定位。输入构造同样不计入 8 个正式计算步骤。每一步
均链接至少一个公开算子，任务 helper 只负责批处理、投影、归一化、融合或紧凑
计时，不替代核心库语义。

| 步骤 | 公开算子链 | 任务侧职责 | 分类 |
| --- | --- | --- | --- |
| filter | `filter_design/firwin`、`filtering/firfilter` | 批量复数帧和实部投影 | mixed |
| demod | `demod/fm_demod` | batched score | mixed |
| correlate | `correlate/correlate` | 模值与非负归一化 | mixed |
| spectrogram | `spectral/spectrogram` | band score 与采样轴投影 | mixed |
| CWT | `wavelets/cwt` | scale reduction 与归一化 | mixed |
| feature fusion + peak | `bsplines/cubic`、`peak_finding/argrelmax` | 加权融合、平滑和候选选择 | mixed |
| measurement conversion | `estimation/kalman_filter` | 构造独立计时的观测向量 | mixed |
| Kalman | `estimation/kalman_filter` | batched track 输出 | mixed |

机器契约 `tests/contracts/task_step_contracts.json` 是步骤名称、CPU/GPU symbol、public
operator 链和 timing/accuracy 要求的事实源。最终门禁为 Task1 public 6 步、
Task2 mixed 8 步，共 14 个计算步骤。

## 8. 核心优化结构

最终代码保留的优化以不改变公开 API、dtype 契约和报告 schema 为前提：

| 模式 | 典型落点 | 作用 |
| --- | --- | --- |
| shared-memory tile | Wiener、CWT、局部 stencil | 复用重叠邻域，降低全局访存 |
| prefix scan | SOS、lfilter、filtfilt | 将递推状态改写为可组合的 affine transform |
| FFT 路径选择 | periodogram、spectral、radar | R2C/C2C 选择、power-of-two padding 和批量 plan |
| fused output/reduction | PSD、cross spectrum、Task2 score | 减少中间数组、launch 和同步 |
| direct-write generator | windows、waveforms、wavelets | 直接写最终 device 输出，去除冗余 copy |
| small-matrix specialization | MVDR、Kalman 辅助链 | 适配固定小维度，减少通用库固定开销 |
| workspace/prepared cache | filtering、spectral、radartools | 复用 plan、窗口、频率轴、模板和 scratch |
| task AOT preparation | Task2 correlate、spectrogram | 将固定准备从重复执行路径移出 |

缓存只影响性能。所有 cache hit/miss 路径必须保持相同输出，且 device 输入、host
变值、shape 变化和显式 window 等绕过条件必须有契约或 A/B 验证。

## 9. 验证与证据分层

架构对应四层验证：

1. 公共类型、接口和静态契约审计。
2. 12 模块、81 个注册算子的独立 correctness。
3. `all81 x L1-L6` 性能 runner 与平台 telemetry。
4. Task1/Task2 L1-L6、14 步 timing/accuracy 和最终演示。

`data/reports/autotune/` 保存当前默认 Auto 结果：正式算子汇总位于
`units/benchmarks/`，单算子明细按 `units/<module>/<operator>/<L1-L6>/` 保存
`metrics.json`、`cases.csv`、`summary.md`，两个任务的最终场景与 L1-L6 数据位于 `demo/`。
运行期原始文件仍先写入 `data/.reports_staging/.../raw/reports/<scale>/<module>/<operator>/`。
`data/reports/zx_operator_gpu_final_static/` 是静态策略 A/B 对照报告；GPU 冻结
基线和原始 CPU/GPU 参考数据位于 `data/baseline/`。逐轮 console、候选/探针、历史版本
逐文件副本、图件和外层归档不属于最终仓库。V6 的 486/486 是 runner 用例门，不应被解释为
所有 benchmark 诊断值均无异常；完整证据能力边界
见 `docs/PERFORMANCE.md`。

## 10. ZQ500 平台边界

项目自有命名已经收敛为 `zx_gpu_backend`、`ZxGpu*`、`cusignal_zx_gpu` 和
`src/zhongkexin/`。以下名称属于中科芯 SDK 的 CUDA-like 兼容 ABI/API，仍是
当前架构的一部分，不能按字符串清理：

- `.cu` 源文件和 `dlcc -x cuda --cuda-gpu-arch=dlgput64`。
- `cuda_runtime.h`、`cudaMalloc`、`cudaMemcpy`、event 等 runtime 符号。
- `cufft*`、`cublas*`、`cusolver*` 兼容接口。

当前报告 schema 使用中性 `gpu_*` 和 `runtime_version` 字段；历史报告中的
`cuda_*` 字段不代表当前 schema。平台 API、FFT/SOLVER 限制和外部 fixture
规则见 `docs/API_COMPATIBILITY.md`。

## 11. 维护原则

- 公开语义优先落在头文件和 `src/common/`，后端只实现同一契约。
- 新算子必须同时补声明、CPU、ZQ500 GPU、独立测试、reference manifest 和注册项。
- Task helper 可以保留编排职责，但不得静默替代公开算子的核心数学。
- 不以降低精度、删减 dtype edge 或修改报告口径换取性能结论。
- V5.5、V6、V7 已关闭；任何新性能工作必须作为新的、明确授权的版本处理。
