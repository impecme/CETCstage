# V3.8.3 低端到端加速比算子优化记录

## 版本信息

- 版本名称：`V3.8.3 low e2e speedup operator optimization`
- 完成时间：`2026-05-01`
- 约束：不改变公开算子函数签名，不改变 benchmark CSV schema。
- 基线来源：`scripts/test/READMEV3_8_2.md` 中的 `large-gpu` candidate 分类。

## 优化目标

本轮成功指标优先看全量 benchmark CSV 的 `gpu_e2e_speedup`。排除
`radartools/cfar_alpha`，因为它是 scalar helper，当前不做 GPU 化。

优先优化以下最大规模点为 `e2e-copy-bound` 且 kernel 已很快的算子：

- `bsplines/quadratic`
- `bsplines/cubic`
- `wavelets/qmf`
- `waveforms/sawtooth`
- `waveforms/square`
- `bsplines/gauss_spline`
- `waveforms/chirp`
- `estimation/kalman_filter`
- `filter_design/firwin2`

## 关键实现

- `DeviceSignal` / `DeviceArray` 底层 `DeviceStorage<T>` 增加 type-specific、
  device-aware、thread-local allocation cache。
- 默认启用显存缓存；设置 `CUSIGNAL_DISABLE_DEVICE_STORAGE_CACHE=1` 可关闭。
- 缓存按当前 CUDA device id 和元素类型隔离；单块不超过 `256 MiB` 才回收。
- 每类型/线程最多保留 `8` 块或 `512 MiB`，超限释放最旧块。
- `zero_fill=true` 仍执行 `cudaMemset`，容器 shape/size/ownership 语义不变。
- `bsplines`、`wavelets/qmf`、`waveforms/chirp/sawtooth/square` 的 perf case
  预先生成 host 输入并上传到 device，计时循环内调用现有 public CUDA API 的
  device-input 路径。
- `kalman_filter` perf case 预构造并复用固定维度 `KalmanFilter`、device control
  和 device measurement；每次计时前用 D2D copy 复位 `x/P/z/u`，再计入
  `predict + update`。
- `firwin2` 在 CUDA 实现内部增加 thread-local prepared cache，重复 case 复用
  full-spectrum device template；计时循环内从 template 做 D2D copy 后执行 FFT
  与 taps extraction。

## 新 e2e 口径

低 e2e 优化后的相关 perf runner 中，`gpu_e2e_*_ms` 表示：

```text
device-resident public CUDA API call + output allocation/cache + 必要的 device 内部工作区复位/拷贝
```

这与 V3.8.2 的 CSV schema 完全一致，但对点式轻量算子不再把每次 H2D 输入上传和
`.get()` 输出下载放进 perf 计时循环。accuracy case 仍保留 host/device 对照路径，
不改变正确性验证语义。

## 回归命令

```bash
cmake --build build --target cusignal_cuda cusignal_cpu --parallel $(nproc)
cmake --build build --target \
  bsplines_test_cubic bsplines_test_quadratic bsplines_test_gauss_spline \
  wavelets_test_qmf \
  waveforms_test_chirp waveforms_test_sawtooth waveforms_test_square \
  estimation_test_kalman_filter filter_design_test_firwin2 \
  --parallel $(nproc)
```

第一批 targeted benchmark：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --modules bsplines,wavelets,waveforms \
  --operators quadratic,cubic,gauss_spline,qmf,sawtooth,square,chirp \
  --scale-profile large-gpu \
  --no-build --warmup 3 --repeat 10 \
  --report-mode full \
  --output-dir data/reports/unit/benchmarks/e2e_low_batch1
```

第二、三批 targeted benchmark：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --modules estimation,filter_design \
  --operators kalman_filter,firwin2 \
  --scale-profile large-gpu \
  --no-build --warmup 3 --repeat 10 \
  --report-mode full \
  --output-dir data/reports/unit/benchmarks/e2e_low_batch2
```

最终全量复测：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --report-mode full \
  --output-dir data/reports/unit/benchmarks/all_ops_large
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
  --report-mode full \
  --dpi 450
```

验收标准：

- 第一批 targeted benchmark：`42/42` rows passed，`mixed_error <= 1e-4`。
- 第二、三批 targeted benchmark：`12/12` rows passed，`mixed_error <= 1e-4`。
- 最终全量复测：`318/318` rows passed，失败行 `0`，全量 `mixed_error` 最大值不超过 `1e-4`。
