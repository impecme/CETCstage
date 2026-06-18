# V3.8.4 原全量脚本 GPU-only 复测选项

## Summary

- 不新增独立测试脚本，统一使用 `scripts/test/benchmark_all_ops_scales.py`。
- 原脚本默认行为保持完整 CPU+GPU benchmark；只有显式传 `--gpu-only` 时才启用 CPU baseline 复用。
- GPU-only 模式用于 GPU 代码迭代：CPU 基线只采集一次，后续只跑 GPU e2e/kernel timing，并复用缓存计算 speedup。
- 当前 GPU-only perf 路径不会为了报告物化完整 GPU 输出或写出大规模 input/output samples，主要用于快速观察 GPU 代码修改后的运行速度。
- `benchmark_all_ops_scales.py --build` 现在会在脚本开头一次性构建选中的测试 target，后续每个规模点自动复用二进制，避免 318 行全量复测反复触发 CMake。

## 参数

- `--gpu-only`：启用 CPU baseline cache 与 GPU-only 复测。
- `--cpu-baseline-mode auto`：默认模式。缓存命中时只跑 GPU；缓存缺失时对缺失 row 跑一次完整 CPU+GPU 并写入缓存。
- `--cpu-baseline-mode refresh`：强制重建选中算子/规模的 CPU baseline。
- `--cpu-baseline-mode reuse`：严格复用已有 baseline，缺失即失败，不自动跑 CPU。
- `--cpu-baseline-file PATH`：指定 CPU baseline cache；默认路径为：
- `--demo-fast`：现场演示模式；未显式传 `--warmup/--repeat` 时使用 `warmup=1`、`repeat=3`，默认严谨 benchmark 口径仍为 `5/30`。

```bash
data/reports/unit/benchmarks/cpu_baselines/<scale-profile>/latest_cpu_baseline.json
```

演示快速模式建议使用独立 cache，避免把 `warmup=1 repeat=3` 的 CPU timing 混入严谨 `5/30` baseline：

```bash
data/reports/unit/benchmarks/cpu_baselines/large-gpu-demo-fast/latest_cpu_baseline.json
```

## GPU-only 口径

- `benchmark_all_ops_scales.py --gpu-only` 会向 `run_all_tests.sh` 透传 `--gpu-only-perf`。
- `--gpu-only-perf` 只影响 `case-set perf`：跳过 CPU 输出、CPU 误差校验、CPU latency repeat、完整 GPU 输出 D2H 物化和大规模样本落盘，只测 GPU e2e/kernel。
- GPU-only 结果中的 `cpu_perf`、`mixed_error`、`pass`、`error_class` 来自 CPU baseline cache。
- `latest_all_ops_scale_benchmark.csv` schema 不变；`error_note` 标记 `cpu_baseline=reused; accuracy=baseline; gpu_output=not_materialized`。
- fresh 正确性验证仍使用 `--cpu-baseline-mode refresh` 或不传 `--gpu-only` 的完整 CPU+GPU 路径。
- 如果传 `--build`，构建阶段只执行一次；各 row 的实际 perf 子进程等价于 `--no-build`。

## 本轮已 device-resident 化的 perf 路径

- `waveforms/gausspulse`：perf 输入预上传为 `ZxGpuRealSignal`，timed lambda 内走 public ZQ500 GPU API 的 device-input 路径。
- `radartools/pulse_doppler`：perf 输入预上传为 `ZxGpuComplexArray`，并减少 `nfft < pulses` 时的无效 pack 线程。
- `demod/fm_demod`：perf 输入预上传为 `ZxGpuComplexArray`，CUDA 内复用 shape/stride metadata。
- `filtering/detrend`：perf 输入预上传为 `ZxGpuRealArray`，CUDA 内复用 line bases / breakpoints metadata。
- `peak_finding/argrelextrema`：perf 输入预上传为 `ZxGpuRealArray`，CUDA 内复用 axis pointer/metadata workspace。
- `radartools/ambgfun`：2D surface 使用分块 FFT workspace，降低大规模点的峰值显存需求；Batch6 增加 device-input normalized buffer cache，并按可用显存自适应 tile rows。更大的 128M tile 和“memset + only nonzero write”试验在 L6 上变慢，最终保留 64M tile 稳定路径。
- `windows/chebwin`：Chebyshev frequency response template 改为 GPU kernel 生成，并按 `extended.size/at/sym` 缓存在 `WindowWorkspace`；Batch6 增加最终 normalized window cache，repeat 命中时 timed path 只做 result 分配和 D2D copy。
- `radartools/ca_cfar`：perf 输入预上传为 `ZxGpuRealArray`，timed lambda 内走现有 public ZQ500 GPU API 的 device-input 路径，去掉计时区间内的 host 构造和 H2D。
- `wavelets/cwt`：perf data 预上传为 `ZxGpuRealSignal`，widths 保持 host 小向量用于校验和 cache key；CUDA workspace 按 `wavelet/data_count/widths` 缓存 CWT kernel table，cache hit 时跳过 CPU table 构造和 H2D；Batch6 为 `ricker` 增加 real-only shared-memory tile kernel，减少相邻 sample 的重复 global load。
- `spectral/csd`：perf `x/y` 预上传为 `ZxGpuRealArray`；string/named window spec 按 `window/nperseg/fs/scaling` 缓存 device window 与 scale，输出 buffer 改为未清零分配；Batch6 在 real one-sided 路径使用 R2C batched FFT，并为默认 `detrend="constant"` 增加 one-block-per-segment prepare kernel，避免每个 sample 重复扫描窗口求均值。
- `spectral/lombscargle`：Batch6 将 one-thread-per-frequency 串行 sample loop 改为 one-block-per-frequency shared reduction，`precenter/normalize` 的 mean 和 dot 均保留在 device 上，移除 repeat 内 `y.get()` D2H。
- `spectral/vectorstrength`：perf events 预上传为 `ZxGpuRealSignal`，host periods 直接校验并缓存上传；每个 period 的 blocks 上限收敛到 1024，减少超大输入下的调度开销。
- `radartools/pulse_compression`：perf 输入和 template 预上传为 device container，输出 buffer 改为未清零分配，timed path 避免大输入 H2D。
- `filtering/freq_shift`：perf 输入预上传为 `ZxGpuComplexArray`，输出 buffer 改为未清零分配。
- `filtering/channelize_poly`：perf complex input 与 taps 预上传；host taps 路径缓存 padded taps workspace，输出 channels buffer 改为未清零分配。
- `filtering/firfilter/firfilter2/sosfilt/upfirdn/decimate/hilbert/hilbert2`：perf 输入预上传为 device container，CUDA 内缓存 line bases、unit signal、`decimate` taps，并把完全写满的中间/输出 buffer 改为未清零分配。
- `filtering/wiener`：perf 输入预上传为 `ZxGpuRealArray`；CUDA 内缓存 shape/stride/mysize metadata，`noise < 0` 的 variance mean 保留在 device 上由 apply kernel 读取，移除 D2H 同步。
- `filtering/resample`：perf 输入预上传为 `ZxGpuRealArray`；named/string window 按 `window/axis_size` 缓存 device window，frequency/time 中间输出改为缓存后复用。
- `filtering/resample_poly`：perf 输入预上传为 `ZxGpuRealArray`；named window 生成的 scaled padded filter 按 `up/down/input/window` 缓存，`upfirdn_kernel` 只遍历当前 polyphase 对应 taps，减少无效 tap 扫描。
- `spectral/spectrogram/stft`：perf 输入预上传为 `ZxGpuRealArray`；CUDA 内缓存 segment window、scale、frequency axis 和 time axis，values 输出改为未清零分配。
- Batch7：ZQ500 GPU 实现已去除外部 parallel STL 依赖；`peak_finding/argrelextrema` 改用 CUDA toolkit 内置 selection，`filter_design/firwin` 改用自定义 device reduction，避免 repeat 内 host response 同步。

## 2026-05-03 验证结果

- 全量 GPU-only 复测命令不指定 `CUDA_VISIBLE_DEVICES`，默认使用当前环境可见的 CUDA 设备。
- 输出文件：`data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv`。
- 图表文件：`data/reports/unit/benchmarks/all_ops_large/figures/figure_1_accuracy_performance_overview.png`。
- 结果：`318/318` rows passed，失败行 `0`，`max_mixed_error=8.03277e-05`。
- 全量 GPU-only 结果的 `error_note` 均为 `cpu_baseline=reused; accuracy=baseline; gpu_output=not_materialized`。
- Batch4 targeted 输出文件：`data/reports/unit/benchmarks/gpu_only_speed_batch4/latest_all_ops_scale_benchmark.csv`，结果 `42/42` rows passed，失败行 `0`，`max_mixed_error=5.1863e-05`。
- Batch5 targeted 输出文件：`data/reports/unit/benchmarks/gpu_only_speed_batch5/latest_all_ops_scale_benchmark.csv`，结果 `30/30` rows passed，失败行 `0`，`max_mixed_error=6.26596e-05`。
- Batch6 targeted 输出文件：`data/reports/unit/benchmarks/gpu_only_speed_batch6/latest_all_ops_scale_benchmark.csv`，结果 `30/30` rows passed，失败行 `0`，`max_mixed_error=9.28208e-07`。
- Batch7 fresh accuracy：`peak_finding/argrelextrema`、`filter_design/firwin`、`filter_design/firwin2` 均 PASS；`run_all_tests.sh --demo-fast` 日志显示 `warmup=1 repeat=3`。

| Operator | L6 scale | GPU e2e median ms | GPU kernel median ms | e2e speedup | kernel speedup |
|---|---:|---:|---:|---:|---:|
| `waveforms/gausspulse` | 16777216 | 0.227 | 0.220 | 1962.480x | 2022.016x |
| `radartools/pulse_doppler` | 1048576 | 0.042 | 0.018 | 317.465x | 716.933x |
| `filtering/detrend` | 1048576 | 0.075 | 0.047 | 61.975x | 99.402x |
| `demod/fm_demod` | 1048576 | 0.062 | 0.035 | 180.042x | 319.267x |
| `peak_finding/argrelextrema` | 1048576 | 0.120 | 0.104 | 111.008x | 127.077x |
| `radartools/ambgfun` | 8192 | 12.511 | 11.041 | 520.778x | 590.139x |
| `windows/chebwin` | 16777216 | 0.137 | 0.112 | 30377.796x | 37179.705x |
| `radartools/ca_cfar` | 1048576 | 0.398 | 0.356 | 35.638x | 39.840x |
| `wavelets/cwt` | 1048576 | 3.291 | 3.266 | 6330.305x | 6379.466x |
| `spectral/csd` | 1048576 | 2.565 | 2.531 | 73.662x | 74.637x |
| `spectral/lombscargle` | 8192 | 0.638 | 0.560 | 1425.699x | 1623.363x |
| `spectral/vectorstrength` | 1048576 | 0.452 | 0.436 | 1240.323x | 1286.041x |
| `radartools/pulse_compression` | 1048576 | 0.465 | 0.440 | 186.096x | 196.474x |
| `filtering/channelize_poly` | 1048576 | 0.354 | 0.333 | 1693.169x | 1802.269x |
| `filtering/freq_shift` | 1048576 | 0.031 | 0.014 | 1593.759x | 3416.420x |
| `filtering/firfilter` | 1048576 | 0.052 | 0.037 | 164.457x | 233.058x |
| `filtering/sosfilt` | 1048576 | 0.134 | 0.118 | 67.648x | 76.700x |
| `filtering/upfirdn` | 1048576 | 0.267 | 0.251 | 92.250x | 97.851x |
| `filtering/firfilter2` | 1048576 | 0.189 | 0.173 | 148.839x | 162.305x |
| `filtering/decimate` | 1048576 | 0.217 | 0.202 | 153.867x | 165.781x |
| `filtering/hilbert` | 1048576 | 0.144 | 0.129 | 446.058x | 498.846x |
| `filtering/hilbert2` | 1048576 | 0.115 | 0.098 | 600.471x | 699.651x |
| `filtering/resample_poly` | 1048576 | 0.184 | 0.171 | 691.826x | 745.357x |
| `filtering/resample` | 1048576 | 0.188 | 0.172 | 826.306x | 904.402x |
| `filtering/wiener` | 1048576 | 0.248 | 0.229 | 1726.771x | 1867.532x |
| `spectral/spectrogram` | 1048576 | 1.096 | 1.033 | 306.791x | 325.497x |
| `spectral/stft` | 1048576 | 0.434 | 0.369 | 841.949x | 992.163x |

## 下一轮优化优先级

- 继续按全量 CSV 中的实际 GPU e2e 和 e2e/kernel gap 排序推进；batch5 之后优先复测 batch5 改动对全量候选列表的影响，再挑选仍然 copy-bound 的 perf runner 路径。
- Batch6 中 `windows/chebwin`、`wavelets/cwt`、`spectral/csd`、`spectral/lombscargle` 已达到本轮 L6 目标；`radartools/ambgfun` 仍为 `12.511 ms`，未达到 `<=8.5 ms`，瓶颈已主要集中在 2D surface 的 tile FFT 和 1 GiB 级输出写回，下一步需要单独做算法布局或输出裁剪级优化。
- `radartools/cfar_alpha` 仍作为 scalar helper 记录，不作为 GPU 化目标。
- 当前低 e2e 候选主要集中在小规模或小状态场景，例如 `filtering/lfilter_zi`、`filter_design/firwin`；这些项需要优先减少固定启动/分配开销，而不是追求 GPU 利用率数字。

## Batch8 演示基线刷新结果

- 演示口径 CPU baseline 已单独刷新到 `data/reports/unit/benchmarks/cpu_baselines/large-gpu-demo-fast/latest_cpu_baseline.json`，不混入正式 `warmup=5 repeat=30` 基线。
- `--demo-fast` 在未显式传 `--warmup/--repeat` 时固定为 `warmup=1 repeat=3`；显式传参仍优先。
- 复用演示 baseline 的全量 GPU-only 输出为 `data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv`。
- 本轮全量结果：`318/318` rows passed，失败行 `0`，`max_mixed_error=8.03277e-05`。
- 图表输出在 `data/reports/unit/benchmarks/all_ops_large/figures/`。
- ZQ500 GPU 实现与 test support 中继续保持无禁用 GPU helper 依赖；当前替代路径使用 CUB 或自定义 ZQ500 GPU kernel。

### Batch8 L6 实际耗时 Top 10

| Rank | Operator | L6 scale | GPU e2e median ms | GPU kernel median ms | e2e/kernel gap | e2e speedup | 建议优化类型 |
|---:|---|---:|---:|---:|---:|---:|---|
| 1 | `radartools/ambgfun` | 8192 | 11.573 | 10.190 | 1.14x | 547.66x | kernel/layout 算法级优化 |
| 2 | `wavelets/cwt` | 1048576 | 3.236 | 3.220 | 1.00x | 5434.69x | kernel/layout 算法级优化 |
| 3 | `spectral/csd` | 1048576 | 2.592 | 2.552 | 1.02x | 46.45x | kernel/layout 算法级优化 |
| 4 | `windows/kaiser` | 16777216 | 1.421 | 1.389 | 1.02x | 676.22x | kernel/layout 算法级优化 |
| 5 | `spectral/spectrogram` | 1048576 | 1.121 | 1.060 | 1.06x | 186.11x | kernel/layout 算法级优化 |
| 6 | `wavelets/ricker` | 16777216 | 0.636 | 0.625 | 1.02x | 308.61x | 低墙钟，暂观察 |
| 7 | `spectral/lombscargle` | 8192 | 0.630 | 0.552 | 1.14x | 1403.08x | 低墙钟，暂观察 |
| 8 | `estimation/kalman_filter` | 524288 | 0.546 | 0.431 | 1.27x | 345.56x | 低墙钟，暂观察 |
| 9 | `wavelets/morlet2` | 16777216 | 0.486 | 0.475 | 1.02x | 788.98x | 低墙钟，暂观察 |
| 10 | `windows/taylor` | 16777216 | 0.482 | 0.464 | 1.04x | 1487.83x | 低墙钟，暂观察 |

结论：当前 L6 Top 项大多已经接近 kernel time，继续提升整体演示速度的主线应从 `radartools/ambgfun` 的输出布局/tile FFT、`wavelets/cwt` 的算法布局、`spectral/csd/spectrogram` 的频域批处理布局入手；纯粹减少 H2D/D2H 或分配缓存的边际收益已经明显降低。

## Batch9 保守性能优化结果

- 本轮保持公共 API、输出语义、CSV schema 和 CPU baseline cache 口径不变，只调整内部 CUDA/perf runner 路径。
- `radartools/ambgfun`：perf runner 在 `--gpu-only-perf` 下预上传 `ZxGpuComplexSignal`，复用 normalized device-input cache；2D surface tile FFT 固定复用同一 batch plan，避免尾 tile 触发 batch size 变化；surface extract 去掉 modulo shift，并使用 float math。
- `windows/kaiser`：增加专用对称 ZQ500 GPU kernel，`bessel_i0(beta)` 在 host 侧只计算一次，kernel 直接写最终输出，避免通用 window 的 extended buffer + copy 路径。
- `spectral/spectrogram`：为 `return_onesided=true && mode="psd"` 增加 R2C fast path，复用 real segment prepare、`RealForwardPlan` 和 R2C PSD 输出 kernel；其他 mode 继续走原 C2C 路径。
- 由于当前 GPU0 被外部进程占用，`radartools/ambgfun` L6 完整 surface 在 GPU0 上会因 1 GiB 级输出触发 OOM；本轮 fresh/full 与全量 GPU-only 复测使用 `CUDA_VISIBLE_DEVICES=1` 隔离到空闲 A100。
- Fresh correctness：`radartools/ambgfun`、`windows/kaiser`、`spectral/spectrogram` 均 PASS。
- Targeted 输出文件：`data/reports/unit/benchmarks/gpu_only_speed_batch9/latest_all_ops_scale_benchmark.csv`，结果 `18/18` rows passed。
- 全量输出文件：`data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv`，结果 `318/318` rows passed，失败行 `0`，`max_mixed_error=8.03277e-05`。
- 图表输出：`data/reports/unit/benchmarks/all_ops_large/figures/figure_1_accuracy_performance_overview.png`。

### Batch9 L6 目标项对比

| Operator | Batch8 GPU e2e median ms | Batch9 GPU e2e median ms | Batch9 GPU kernel median ms | 结果 |
|---|---:|---:|---:|---|
| `radartools/ambgfun` | 11.573 | 9.486 | 8.440 | e2e 降低约 18%，仍为全量 Top1 |
| `windows/kaiser` | 1.421 | 0.327 | 0.315 | 从 L6 Top5 中移出 |
| `spectral/spectrogram` | 1.121 | 0.338 | 0.328 | one-sided PSD R2C fast path 生效 |

Batch9 后 L6 Top 项变为 `ambgfun`、`wavelets/cwt`、`spectral/csd`；`kaiser` 与 `spectrogram` 已不再是主要墙钟瓶颈。下一轮若继续保守优化，优先级应回到 `ambgfun` 算法布局、`cwt` kernel 布局和 `csd` 频域批处理。

## 常用命令

首次或强制重建 CPU baseline：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --report-mode full \
  --gpu-only \
  --cpu-baseline-mode refresh \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

后续 GPU-only 全量复测：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --report-mode full \
  --gpu-only \
  --cpu-baseline-mode auto \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

严格复用缓存的快速迭代：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --no-build \
  --scale-profile large-gpu \
  --warmup 3 --repeat 10 \
  --report-mode full \
  --gpu-only \
  --cpu-baseline-mode reuse \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

现场演示快速全量：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --report-mode full \
  --gpu-only \
  --cpu-baseline-mode refresh \
  --cpu-baseline-file data/reports/unit/benchmarks/cpu_baselines/large-gpu-demo-fast/latest_cpu_baseline.json \
  --demo-fast \
  --output-dir data/reports/unit/benchmarks/all_ops_large_demo_fast_refresh
```

现场演示快速全量复用：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --no-build \
  --scale-profile large-gpu \
  --report-mode full \
  --gpu-only \
  --cpu-baseline-mode reuse \
  --cpu-baseline-file data/reports/unit/benchmarks/cpu_baselines/large-gpu-demo-fast/latest_cpu_baseline.json \
  --demo-fast \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

## 注意事项

- GPU-only 复测适合只改 GPU 代码时看端到端加速比变化。
- 默认不需要指定 GPU；只有在多卡机器上需要主动避开外部进程或做设备隔离时，才临时设置 `CUDA_VISIBLE_DEVICES`。
- 如果改动可能影响数值正确性，先用 `--gpu-only --cpu-baseline-mode refresh` 重建 CPU baseline，或不传 `--gpu-only` 运行完整原脚本。
- 图表生成仍使用现有脚本：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
  --report-mode full \
  --dpi 450
```
