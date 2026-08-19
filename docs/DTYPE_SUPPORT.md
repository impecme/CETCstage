# CETC Dtype 支持与数值契约

本文说明最终交付的 dtype 事实。必须区分三件事：core 层可表示的类型、逐算子
兼容契约，以及算子当前原生计算类型。`operator_dtype_missing_edges=0` 表示所有
声明的兼容 edge 都有测试证据，不表示 81 个算子各自拥有 6 套原生 kernel。

事实源为：

- `include/cusignal/core/types.hpp`
- `tests/contracts/operator_type_contracts.json`
- `tests/tools/dtype_contract_audit.py`
- `data/reference/unit/*/*/manifest.json`
- 当前容器验证使用的 dtype 合同与测试输出（不再发布到已删除的 `data/reports/validation/`）

## 1. 总体结论

| 检查 | 最终结果 |
| --- | ---: |
| 注册算子 | `81` |
| FP32 compatibility edges | `78/78` |
| FP16 compatibility edges | `69/69` |
| INT32 compatibility edges | `7/7` |
| INT16 compatibility edges | `5/5` |
| INT8 compatibility edges | `5/5` |
| complex64 compatibility edges | `21/21` |
| 缺失 edge | `0` |

赛题交付要求的实数类型为 FP32、FP16、INT32、INT16、INT8；复数只要求
complex64。FP64、complex128、complex32 和整数复数不在支持范围。

## 2. Core 类型

`core/types.hpp` 定义：

| 名称 | C++/SDK 类型 | 字节 | 默认累加类型 |
| --- | --- | ---: | --- |
| `Float32` | `float` | 4 | FP32 |
| `Float16` | `__half` | 2 | FP32 |
| `Int32` | `std::int32_t` | 4 | INT64 |
| `Int16` | `std::int16_t` | 2 | INT32 |
| `Int8` | `std::int8_t` | 1 | INT32 |
| `Complex` | `std::complex<float>` | 8 | FP32 real/imag |

默认别名仍然是：

- `Scalar = Float32`
- `RealSignal = Signal<Float32>`
- `RealArray = Array<Float32>`
- `ComplexSignal = Signal<Complex>`
- `ComplexArray = Array<Complex>`

因此，大部分当前公开签名中的 `RealSignal`/`RealArray` 是 FP32 具体类型，不是
运行时动态 dtype 容器。

core 层同时提供 `Float16Signal/Array`、`Int32Signal/Array`、
`Int16Signal/Array`、`Int8Signal/Array` 及对应 `ZxGpu*` device 别名。
complex64 在 device 侧映射为 `cuFloatComplex`，并通过静态检查保证 host/device
元素大小一致。

## 3. 三种支持层级

| 层级 | 含义 | 不能据此声称 |
| --- | --- | --- |
| core representable | core 有 host/device 类型、pack/unpack 和 roundtrip | 某个公开算子接受该类型 |
| compatibility edge | 机器契约声明该算子与 dtype 的输入/输出语义，且有 manifest/test edge | 该 edge 使用独立原生 kernel |
| current/native type | 当前公开实现直接使用的具体类型域 | 其他 compatibility edge 不存在 |

典型兼容方式包括：

- FP16 输入先量化，再拓宽到 FP32 计算；输出按 FP16 精度比较或受控转换。
- INT32 使用 INT64 扩展累加；INT16/INT8 使用 INT32 扩展累加。
- 整数结果在回写输入 dtype 前执行受控或饱和转换。
- complex64 保持 FP32 实部/虚部，不提供 FP16 复数、整数复数或 complex128。
- 某些测试通过兼容输入的量化/reference edge 验证；公开函数签名仍可能是
  FP32 `RealSignal`/`RealArray`。

所以“支持 FP16/整数”应表述为“逐算子兼容契约和覆盖通过”，不能统一表述为
“所有算子原生以 FP16/整数计算”。

## 4. 当前覆盖与当前具体类型

按 `operator_type_contracts.json` 的 `compatibility_types` 汇总：

| dtype | compatibility 算子数 | 当前契约语义 |
| --- | ---: | --- |
| `float32` | 78 | 默认实数计算和实数诊断 |
| `float16` | 69 | FP16-compatible，通常通过 FP32 中间计算 |
| `int32` | 7 | 数值相关、索引输出或元数据 |
| `int16` | 5 | 数值相关和峰值比较输入 |
| `int8` | 5 | 数值相关和峰值比较输入 |
| `complex64` | 21 | 复数生成、变换、雷达、相关和复数到实数链 |

按同一文件的 `current_types` 汇总，当前具体类型覆盖为 FP32 78、complex64 21、
INT32 5。这里的 INT32 包含索引/元数据结果，不表示 5 个算子都以 INT32 进行
主体数学运算。

## 5. 逐算子策略

当前机器契约共有 14 类策略，81 个算子唯一分配一次。

| 策略 | 数量 | 核心规则 |
| --- | ---: | --- |
| `floating_generator_real_or_complex64` | 1 | real 模式 FP32/FP16-compatible，complex 模式 complex64 |
| `floating_generator_real` | 29 | 生成 FP32 或 FP16-compatible 实数输出 |
| `floating_real` | 26 | FP32/FP16-compatible 实数输入输出，FP32 累加 |
| `floating_real_to_complex64` | 4 | FP32/FP16-compatible 实输入，complex64 输出 |
| `floating_real_or_complex64` | 1 | 实数或 complex64 输入域保持 |
| `floating_real_to_real_or_complex64` | 2 | mode 决定实数或 complex64 输出 |
| `floating_generator_complex64` | 2 | 原生 complex64 生成 |
| `complex64_pipeline` | 6 | complex64 主链，实数诊断为 FP32 |
| `complex64_to_real` | 2 | complex64 输入，FP32 输出 |
| `float32_generator_real` | 1 | 仅 FP32 public dtype |
| `numeric_correlate` | 2 | 浮点、整数、complex64；扩展累加后保持输入域 |
| `numeric_to_indices` | 3 | 实数/整数输入比较，返回 INT32 索引 |
| `index_metadata` | 1 | INT32 元数据，长度运算使用 INT64 |
| `sort_real_or_complex` | 1 | FP16-compatible 或 complex64 值排序，索引为 INT32 |

精确分配如下：

| 策略 | 算子 |
| --- | --- |
| `floating_generator_real_or_complex64` | `waveforms/chirp` |
| `floating_generator_real` | `waveforms/gausspulse`; `windows/get_window`, `barthann`, `bartlett`, `blackman`, `blackmanharris`, `bohman`, `boxcar`, `chebwin`, `cosine`, `exponential`, `flattop`, `gaussian`, `general_cosine`, `general_gaussian`, `general_hamming`, `hamming`, `hann`, `kaiser`, `nuttall`, `parzen`, `taylor`, `triang`, `tukey`; `filter_design/kaiser_beta`, `kaiser_atten`, `firwin`, `firwin2`; `wavelets/ricker` |
| `floating_real` | `waveforms/sawtooth`, `square`; `bsplines/cubic`, `quadratic`, `gauss_spline`; `filtering/wiener`, `lfilter`, `firfilter_zi`, `lfilter_zi`, `firfilter2`, `filtfilt`, `sosfilt`, `detrend`, `decimate`, `resample`, `resample_poly`, `upfirdn`; `radartools/cfar_alpha`, `ca_cfar`; `spectral/lombscargle`, `periodogram`, `welch`, `coherence`, `vectorstrength`; `wavelets/qmf`; `estimation/kalman_filter` |
| `floating_real_to_complex64` | `filtering/hilbert`, `hilbert2`; `spectral/stft`; `wavelets/cwt` |
| `floating_real_or_complex64` | `filtering/firfilter` |
| `floating_real_to_real_or_complex64` | `spectral/spectrogram`, `csd` |
| `floating_generator_complex64` | `wavelets/morlet`, `morlet2` |
| `complex64_pipeline` | `filtering/freq_shift`, `channelize_poly`; `radartools/pulse_compression`, `pulse_doppler`, `ambgfun`, `mvdr` |
| `complex64_to_real` | `spectral/istft`; `demod/fm_demod` |
| `float32_generator_real` | `waveforms/unit_impulse` |
| `numeric_correlate` | `correlate/correlate`, `correlate2d` |
| `numeric_to_indices` | `peak_finding/argrelextrema`, `argrelmin`, `argrelmax` |
| `index_metadata` | `correlate/correlation_lags` |
| `sort_real_or_complex` | `filter_design/cmplx_sort` |

## 6. Complex64 范围

当前契约中的 21 个 complex64 对齐项为：

```text
waveforms/chirp,
filtering/firfilter, filtering/hilbert, filtering/hilbert2,
filtering/freq_shift, filtering/channelize_poly,
radartools/pulse_compression, radartools/pulse_doppler,
radartools/ambgfun, radartools/mvdr,
spectral/stft, spectral/spectrogram, spectral/csd, spectral/istft,
wavelets/morlet, wavelets/morlet2, wavelets/cwt,
correlate/correlate, correlate/correlate2d,
demod/fm_demod, filter_design/cmplx_sort
```

这里包含 complex64 输入、complex64 输出、real-to-complex64、complex64-to-real
和带 INT32 索引的复数排序，不表示 21 项具有完全相同的输入输出方向。

V5.5 的历史摘要曾记录聚合字段 `policy_count=13`、`complex64_operators=20`；当前
机器契约为 14 类、21 个 complex64 edge，dtype 覆盖审计记录 `complex64 21/21`。
历史字段只保留在版本台账语义中；当前支持表以机器契约和当前运行发布的 dtype
审计中 `missing_edges=0` 门禁为准。

## 7. 整数范围

整数支持集中在数学上有明确离散语义的路径：

- `correlate/correlate`、`correlate/correlate2d`：INT32/INT16/INT8 输入使用扩展
  累加，结果按输入域受控转换。
- `peak_finding/argrelextrema`、`argrelmin`、`argrelmax`：支持实数或整数比较，
  输出 INT32 索引。
- `correlate/correlation_lags`：INT32 索引元数据，长度计算使用 INT64。
- `filter_design/cmplx_sort`：值域为实数或 complex64，排序索引为 INT32；其
  INT32 compatibility edge 指索引结果，不应误写成 INT32 复数排序输入。

其他滤波、FFT、窗口或雷达算子没有因为 core 存在整数容器就自动获得整数
主体数学语义。

## 8. FP16 范围

FP16 compatibility 的标准模式是：

1. 输入或生成目标按 FP16 可表示精度量化。
2. 主计算使用 FP32 中间值和 FP32 累加。
3. 输出按策略保留 FP16-compatible 语义或进入 complex64。
4. accuracy 使用对应 dtype edge 的 reference/tolerance 校验。

`estimation::KalmanFilter(dtype="float16")` 明确使用 FP32 中间计算。
`unit_impulse` 是例外，其当前 public dtype 只接受 `float32`。

`spectral/coherence` 的 FP16 compatibility case 使用稳定的自相干输入，避免把
两路独立信号的量化敏感性误判为 dtype 搬运缺陷。该 dtype case 与 V6-0141
性能 runner 的 L1-L5 `true-error` 诊断不是同一测试口径。

## 9. 禁止类型

机器契约显式禁止：

- `float64`
- `complex128`
- `complex32`
- `complex_int32`
- `complex_int16`
- `complex_int8`

此外，不应自行把 FP16 两分量打包称为官方 complex32 支持。最终复数交付口径
只承诺 complex64。

## 10. 覆盖门禁

dtype 覆盖审计按以下关系判定：

- 81 个注册算子必须全部且唯一出现在策略分配中。
- 每个 `compatibility_types` edge 必须有对应 manifest/test case。
- 禁止类型不得出现在 public 契约或测试声明中。
- FP16、整数和 complex64 case 必须说明输入量化、累加和输出规则。
- accuracy-only case 的 timing 状态是 `not_run`，不是性能失败。
- core type test 验证五种实数和 complex64 的 host/device roundtrip。

V5.5 dtype 审计、V6-0138 最终硬门和 V7-0008 最终门均记录缺口 0。后续新增
算子、重载或 dtype 时，必须先更新机器契约和 reference edge，不能只修改文档
或在汇总器中写死通过状态。
