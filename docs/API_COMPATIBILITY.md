# CETC 接口与平台兼容说明

本文冻结最终交付的公开接口、81 算子注册范围和中科芯 ZQ500 兼容边界。
接口事实以 `include/cusignal/`、`tests/contracts/operator_sets.json`、
`tests/contracts/operator_type_contracts.json`、`tests/contracts/task_step_contracts.json`
和当前 CMake 为准；历史版本文档只用于解释迁移过程。

## 1. 当前公开入口

聚合头为：

```cpp
#include "cusignal/cusignal.hpp"
```

| 角色 | 当前名称 | 语义 |
| --- | --- | --- |
| CPU namespace | `cusignal::cpu::<module>` | host 输入、host 输出、reference 路径 |
| GPU namespace | `cusignal::zx_gpu_backend::<module>` | ZQ500 GPU 路径 |
| 公共类型 | `cusignal::core` | 标量、Tensor、device 容器和参数规格 |
| CPU target | `cusignal_cpu` | CPU 静态库 |
| GPU target | `cusignal_zx_gpu` | ZQ500 GPU 静态库 |
| GPU 源码 | `src/zhongkexin/*.cu` | dlcc 编译的产品实现 |

V4.6 完成过一次破坏性命名迁移：

| 历史名称 | 当前名称 |
| --- | --- |
| `cuda_backend` | `zx_gpu_backend` |
| `Cuda*` | `ZxGpu*` |
| `cusignal_cuda` | `cusignal_zx_gpu` |
| `src/cuda/` | `src/zhongkexin/` |
| `platform_cuda_*` | `platform_zx_gpu_*` |

旧名称不再是当前兼容 API。调用旧 namespace 或类型的外部代码需要迁移。

## 2. Host/Device 契约

CPU 和 GPU 后端保持同一功能域，但所有权边界不同：

- CPU 数组参数使用 `RealSignal`、`ComplexSignal`、`RealArray`、`ComplexArray` 等
  host 容器。
- GPU 数组参数通常使用 `*Like`，可接受 host 容器或同类型 device 容器。
- GPU 数组结果使用 `ZxGpu*` device 容器；只有调用 `.get()` 才下载到 host。
- host 输入由 GPU 入口自动上传；device 输入直接复用，便于串接多个算子。
- 标量、枚举式结果和具名结果结构按公开头的实际签名处理，不能机械套用
  “所有返回均为 device 数组”。
- 多返回和分支返回使用具名 `struct` 与 `std::variant`，不模拟 Python 动态 tuple。

性能口径中的 GPU E2E 通常覆盖 host 输入上传和 GPU 计算，不包含调用方为了
correctness 对照而显式执行的 `.get()`。具体 runner 口径以最终报告为准。

## 3. 81 算子注册矩阵

`all81` 是最终独立 test/benchmark 注册集合。12 个模块和精确条目如下：

| 模块 | 数量 | 注册算子 |
| --- | ---: | --- |
| `waveforms` | 5 | `chirp`, `gausspulse`, `sawtooth`, `square`, `unit_impulse` |
| `bsplines` | 3 | `cubic`, `quadratic`, `gauss_spline` |
| `windows` | 23 | `get_window`, `barthann`, `bartlett`, `blackman`, `blackmanharris`, `bohman`, `boxcar`, `chebwin`, `cosine`, `exponential`, `flattop`, `gaussian`, `general_cosine`, `general_gaussian`, `general_hamming`, `hamming`, `hann`, `kaiser`, `nuttall`, `parzen`, `taylor`, `triang`, `tukey` |
| `filter_design` | 5 | `kaiser_beta`, `kaiser_atten`, `cmplx_sort`, `firwin`, `firwin2` |
| `filtering` | 17 | `wiener`, `firfilter`, `lfilter`, `firfilter_zi`, `lfilter_zi`, `firfilter2`, `filtfilt`, `sosfilt`, `hilbert`, `hilbert2`, `detrend`, `freq_shift`, `channelize_poly`, `decimate`, `resample`, `resample_poly`, `upfirdn` |
| `radartools` | 6 | `pulse_compression`, `pulse_doppler`, `ambgfun`, `cfar_alpha`, `ca_cfar`, `mvdr` |
| `spectral` | 9 | `lombscargle`, `periodogram`, `welch`, `csd`, `spectrogram`, `stft`, `istft`, `coherence`, `vectorstrength` |
| `wavelets` | 5 | `qmf`, `morlet`, `ricker`, `morlet2`, `cwt` |
| `correlate` | 3 | `correlate`, `correlate2d`, `correlation_lags` |
| `demod` | 1 | `fm_demod` |
| `estimation` | 1 | `kalman_filter` |
| `peak_finding` | 3 | `argrelextrema`, `argrelmin`, `argrelmax` |

最终接口审计检查声明、CPU 实现、ZQ500 GPU 实现、test target 和 Doxygen 映射，
结果为 `81/81`，失败 0，兼容缺口 0。

## 4. 冻结算子集合

机器集合只在 `tests/contracts/operator_sets.json` 维护，`module/operator` 是 canonical
key。最终集合关系如下：

| 集合 | 数量 | 定义 |
| --- | ---: | --- |
| `all81` | 81 | 全部注册算子 |
| `task27` | 27 | Task1/Task2 直接依赖算子 |
| `extended28` | 28 | V4.3 启用的原注释候选 |
| `core53` | 53 | `all81 - extended28` |
| `demo_top30` | 30 | V6-0141 L6 E2E speedup 固定排序的演示集合 |
| `demo_cache_probe4` | 4 | cache A/B 的固定探针集合 |

`task27` 精确包含：

```text
waveforms/chirp, waveforms/gausspulse, waveforms/unit_impulse,
bsplines/cubic, bsplines/quadratic,
windows/hamming, windows/kaiser,
filter_design/firwin, filter_design/firwin2,
filtering/firfilter, filtering/sosfilt, filtering/hilbert, filtering/hilbert2,
radartools/pulse_compression, radartools/pulse_doppler, radartools/ambgfun,
radartools/cfar_alpha, radartools/ca_cfar,
spectral/spectrogram, spectral/stft,
wavelets/ricker, wavelets/cwt,
correlate/correlate, correlate/correlate2d,
demod/fm_demod, estimation/kalman_filter, peak_finding/argrelextrema
```

`extended28` 精确包含：

```text
windows/get_window, windows/barthann, windows/bartlett, windows/blackman,
windows/blackmanharris, windows/bohman, windows/boxcar, windows/cosine,
windows/exponential, windows/flattop, windows/gaussian, windows/general_hamming,
windows/hann, windows/nuttall, windows/tukey,
filter_design/kaiser_beta, filter_design/kaiser_atten, filter_design/cmplx_sort,
filtering/lfilter, filtering/firfilter_zi, filtering/filtfilt,
radartools/mvdr,
spectral/periodogram, spectral/welch, spectral/coherence,
correlate/correlation_lags, peak_finding/argrelmin, peak_finding/argrelmax
```

历史上这 28 项曾是注释候选；V4.3 起已全部进入 active 集合并通过，不应再称为
未实现或静默候选。

## 5. 任务 public helper

`all81` 是注册算子集合，不是公开头中所有函数的总数。Task1 为避免私有数学和
冗余中间数组，在 `radartools` 公开了额外 helper：

- `fftshift_rows`
- `power_map`
- `detect_peak`
- `pulse_doppler_shifted`（GPU 融合入口；CPU 对照由 `pulse_doppler` 与
  `fftshift_rows` 两步组成）

`tests/contracts/task_step_contracts.json` 冻结 14 个计算步骤与 public operator 链：
Task1 为 6 个 public 步骤，Task2 为 8 个 mixed 步骤。mixed 表示核心计算调用
公开算子，任务 helper 只负责批处理、投影、归一化、融合或报告，并不表示该步骤
绕开算子库。

## 6. 与 Python cuSignal/SciPy 的对齐边界

项目保留 cuSignal 风格的模块划分、函数名、mode/method/window 等参数语义，
但 C++17 接口不是 Python 动态接口的逐字复制：

- Python tuple 返回改为具名结构；运行时分支返回使用 `std::variant`。
- callable window、callable detrend、callable wavelet 和 callable comparator 当前
  不支持；使用字符串、标量、数组或具名参数规格。
- `cwt` 当前公开子集支持 `"ricker"` 和 `"morlet2"`。
- spectral 多个接口按当前头文件覆盖实输入子集；复数边界以实际重载和 dtype
  契约为准。
- `unit_impulse` 当前 public dtype 参数仅接受 `float32`。
- API 支持范围以当前头文件为准，不因上游 Python 包存在某个动态组合而自动扩展。

## 7. Dtype 接口边界

公共 core 层提供 FP32、FP16、INT32、INT16、INT8 和 complex64 的 host/device
类型。逐算子支持不是“一刀切的 81 x 6 笛卡尔积”，而是由 14 类策略分配。

最终覆盖计数为：FP32 `78/78`、FP16 `69/69`、INT32 `7/7`、INT16 `5/5`、
INT8 `5/5`、complex64 `21/21`，`operator_dtype_missing_edges=0`。
兼容可能通过 FP32 中间计算、扩展整数累加、饱和转换或量化输入/输出测试实现；
这不等于每个 dtype 都有独立原生 kernel。完整规则见 `docs/DTYPE_SUPPORT.md`。

## 8. ZQ500 SDK 符号边界

项目自有 CUDA 命名已迁移为 ZQ500 命名，但中科芯 SDK 通过 CUDA-like ABI/API
提供能力。下列内容是外部平台接口，必须保留：

- `.cu` 文件和 `dlcc -x cuda --cuda-gpu-arch=dlgput64`。
- `cuda_runtime.h`、`cudaMalloc`、`cudaFree`、`cudaMemcpy`、`cudaMemset`、
  device/event/launch 等基础 runtime API。
- `cufft*`、`cublas*`、`cusolver*` 兼容接口。
- SDK 实际库 `curt`、`dlfft`、`dlblas`、`dlsolver`、`dldnn`、`dlsparse`、
  `dlrand` 和 `dleol`，由 CMake 解析为项目内部 target/路径。

这些符号含有 `cuda` 字样不代表仍支持 NVIDIA 当前执行路径。顶层 CMake 只允许
`ZHONGKEXIN`。

## 9. 外部兼容 fixture

三份复赛 XLSX 是外部验证输入，不进入最终归档：

| 键 | 文件 | 字节 | SHA256 |
| --- | --- | ---: | --- |
| driver | `CUDA 11.7 driver api.xlsx` | 41892 | `112d1e5fb7f38530e4f4f27a7e64f4597fb503d5dee4d8e2b249c1bd6c71fcb5` |
| runtime | `CUDA 11.7 runtime API.xlsx` | 24510 | `069dbb6419c49c3c2a0c63a694a6b5960e8e01eb7336481c9102f77c9b1a10ab` |
| libraries | `科学计算库实现列表.xlsx` | 26784 | `0017a3719a59943d856a7d1a27127946df8f904a3a743386cde13f7554f5eb06` |

身份与派生政策冻结在 `tests/platform/config/zx_compat_fixture_manifest.json`：

- source rows `900`
- API rows `816`
- unique APIs `830`
- forbidden APIs `315`
- unique set SHA256 `ccb9839afb0c7a8de0c11f07b894a688566ace3ec0f79383af2439b816ca2435`
- forbidden set SHA256 `c697b238061de8074fef2ffc2f02155432d8095fe8973e9e10daab51510d4ea3`

通过 `ZX_COMPAT_SOURCE_DIR` 环境变量或 CMake cache 指向 fixture 目录。普通构建在
fixture 缺失时仍可配置；V5/V6 强门设置 `ZX_COMPAT_REQUIRE_FIXTURES=ON`，缺失、
额外 schema key、路径穿越、symlink、字节篡改、派生计数或集合 SHA 不一致均
fail-closed。最终兼容扫描的 violation/unresolved 为 `0/0`。

## 10. 科学计算库限制

| 能力 | 最终边界 |
| --- | --- |
| cuFFT-compatible | FFT 点数仅支持 2 的整数次幂；其他长度必须显式 pad 到 next power-of-two 并按算子语义裁剪 |
| FFT dtype | 支持单精度实数/复数执行；不声明双精度 FFT 路径 |
| cuBLAS-compatible | 当前主路径使用已探测的 handle 和复数矩阵运算；新增 API 前必须对照 fixture |
| cuSOLVER-compatible | `getrf` 必须分配 pivot buffer，不能传 `nullptr`；SVD 不得依赖无效的 `VT` 输出 |
| cuDNN/cuSPARSE/cuRAND-compatible | 当前产品主链非核心依赖；只对项目安全探针和实际链接范围作兼容声明 |

runtime/driver 表是部分覆盖，不能假设完整 CUDA 11.7。未经 fixture 和平台 probe
确认，不得引入 memory pool、stream-ordered allocator、external memory、IPC event、
NvSci、graph capture 扩展或其他高级 API。CUDA Graph 的六个已测生命周期状态为
0，只证明当前探针路径通过，不将整套 CUDA API 扩展为无条件支持。

## 11. 报告 schema 兼容

V4.8 将当前报告资源字段从历史 `cuda_*` 改为中性 `gpu_*`，并将
`cudart_version` 改为 `runtime_version`。当前生产端和消费端只保证新 schema；
历史冻结报告可以保留旧字段，不能据此反向修改当前产品 schema。

## 12. 最终状态

- all81 interface audit：`81/81`。
- CPU/ZQ500 GPU 映射缺口：`0`。
- dtype edge 缺口：`0`。
- Task 计算步骤 public operator 链声明：`14/14`。
- 外部兼容矩阵：`900/816/830/315`，禁止 API violation/unresolved `0/0`。
- V5.5、V6、V7 已关闭；后续不得通过改接口、dtype 或 schema 来重写冻结性能结论。
