# V3.5.0 `scripts/test` 大规模 GPU 并行性复测与低速/高误差算子优化

## 版本信息

- 版本名称：`V3.5.0 scripts/test 大规模 GPU 并行性复测与低速/高误差算子优化`
- 版本定位：在 V3.4.0 CUDA 标准库候选分析和低速算子二次优化基础上，新增分层放大的 `large-gpu` profile，并针对大规模下仍低速或高误差的算子继续优化。
- 约束：不改公开 C++ API，不改主 CSV 字段，不放宽误差阈值。
- 验收口径：优先看最大规模 `gpu_kernel_speedup`、`gpu_e2e_speedup` 与 `max_rel_error`；同时识别 near-zero denominator 导致的相对误差放大。

## 更改思路

本轮的核心判断是：默认规模太小时，很多 GPU 算子看起来“不够快”，未必是算法没有并行化，也可能只是数据规模没有大到足以摊薄 H2D/D2H、kernel launch 和临时 workspace 开销。因此本版采用“分层放大”：

- 点式、轻量、批处理友好算子显著放大到百万级或千万级，观察 GPU 并行度能否展开。
- FFT、滤波、谱分析等中等一维路径放大到百万级，验证 cuFFT、自定义 direct FIR、scan/reduction 路径的真实吞吐。
- O(N^2) 重算子、filter-design taps、标量 helper 保持安全上限，避免全量复测时间失控。
- `kalman_filter` 单独使用 `kalman_points`，修正旧 perf case 固定 `points=64` 导致无法测试批处理规模的问题。

优化策略按瓶颈类型分流：

- `kernel-bound`：kernel 本身仍低速，优先做分块、批处理、prefix-scan、reduction 或 register-only fast path。
- `e2e-copy-bound`：kernel 已经很快，但 e2e 不高，优先移除内部 D2D copy；进一步提升需要 GPU resident pipeline 或批处理型 public API。
- `error-bound`：真实相对误差超阈值，优先统一 CPU/CUDA 数值口径、边界处理和规约顺序。
- `scalar-helper`：标量公式或 tiny helper 不作为 GPU kernel 优化对象。
- `already-fast`：速度与误差均满足当前口径，暂不作为优化优先级。

CUDA 标准库使用结论保持克制：

- `cuFFT`：继续用于 resample、频域雷达/谱分析等长序列路径。
- `cuBLAS/cuBLASLt`：不用于当前 tiny Kalman fast path，小矩阵库调用开销不划算。
- `cuSOLVER`：仍只适合作为一般 IIR 小型线性系统后备路径。
- `cuSPARSE`：当前算子没有真实稀疏矩阵计算，不引入。
- `cuDNN`：不适合这批信号处理算子，不引入。

## 关键变更

- `scripts/test/benchmark_all_ops_scales.py`
  - 新增 `--scale-profile default,large-gpu`。
  - `large-gpu` 对 `linear_points`、`medium_1d_fft`、`kalman_points` 分层放大。
  - 修正 `estimation/kalman_filter` perf 固定 `points=64` 的问题，使其读取 manifest 中的 `points`。
  - 新增 `latest_large_gpu_candidate_report.csv/md`。
- `scripts/test/plot_all_ops_benchmark.py`
  - 继续输出 5 张论文风格复合图。
  - 新增/同步 `latest_large_gpu_candidate_report.csv/md`。
  - 对 near-zero denominator 相对误差放大做单独标注，保留原始 `max_rel_error`。
- `filtering/sosfilt`
  - 将长轴 fast path 升级为分层 affine prefix-scan。
  - section 内沿样本维并行，section 间保持顺序，保留 `zi/zf` 和异常形态 fallback。
- `filtering/detrend`
  - 用 two-pass block reduction 替换单线 busy-wait 路径。
  - `constant` 与 `linear` 均使用并行规约，累加中间量使用 float，降低误差风险。
- `estimation/kalman_filter`
  - 利用已有 `points` 维度做批处理。
  - 当前小状态路径保持 register-only fast path，避免 cuBLAS/cuBLASLt tiny GEMM 开销。
- `waveforms/gausspulse` 与 `waveforms/sawtooth`
  - CPU/CUDA 共用更一致的 single-precision 数值实现，再 cast 到 float 输出。
- 额外大规模修正
  - `filtering/resample`：修正 cuFFT scatter scaling 的大规模整数溢出。
  - `radartools/pulse_doppler`：修正 `pulses > nfft` 时 padding/truncation pack 的越界/误差问题。
  - `spectral/vectorstrength`：将 per-period 串行求和改为 two-stage parallel reduction。

## 大规模 profile

推荐全量命令：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

推荐目标算子命令：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --operators sosfilt,detrend,kalman_filter,gausspulse,sawtooth,chirp,square,firfilter,fm_demod \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

`large-gpu` 覆盖的放大规模：

| `scale_family` | 6 个规模点 | 说明 |
|---|---:|---|
| `linear_points` | `65536,262144,1048576,4194304,8388608,16777216` | 点式、轻量、批处理友好算子 |
| `medium_1d_fft` | `32768,65536,131072,262144,524288,1048576` | 一维 FFT、滤波、谱分析路径 |
| `kalman_points` | `512,2048,8192,32768,131072,524288` | `kalman_filter` 批处理点数 |
| 其他规模族 | 继承 `default` | O(N^2)、filter-design taps、标量 helper 保持安全上限 |

## 作图与报告

推荐命令：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
  --formats pdf,svg,png \
  --dpi 450
```

主要输出：

- `latest_all_ops_plot_summary.csv`
- `latest_cuda_library_candidate_report.csv/md`
- `latest_large_gpu_candidate_report.csv/md`
- `figure_1_accuracy_performance_overview.*`
- `figure_2_module_timing_facets.*`
- `figure_3_speedup_ranking.*`
- `figure_4_error_distribution.*`
- `figure_5_pareto_speed_accuracy.*`

## 关键结果

最新大规模 CSV：

```bash
data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv
```

全量结果为 `318` 行，即 `53` 个启用算子乘 `6` 个规模点，全部 `passed`。`data/generated/unit/**/manifest.json` 在全量运行前后 hash 一致。

| 算子 | 最大规模 | e2e speedup | kernel speedup | max abs error | max rel error | 结论 |
|---|---:|---:|---:|---:|---:|---|
| `filtering/sosfilt` | `1048576` | `4.81x` | `76.27x` | `2.98e-7` | `7.63e-4` | 分层 affine prefix-scan 生效 |
| `filtering/detrend` | `1048576` | `2.02x` | `79.51x` | `0` | `0` | two-pass block reduction 生效 |
| `estimation/kalman_filter` | `524288` | `2.00x` | `715x` | `0` | `0` | points 批处理与 register fast path 生效 |
| `waveforms/gausspulse` | `16777216` | `8.71x` | `2152x` | `0` | `0` | single-precision 数值路径生效 |
| `waveforms/sawtooth` | `16777216` | `1.68x` | `882x` | `0` | `0` | single-precision 数值路径生效 |
| `demod/fm_demod` | `1048576` | `4.45x` | `500x` | `0` | `0` | 大规模下并行度充分展开 |
| `filtering/resample` | `1048576` | `80.65x` | `447.2x` | `1.25e-6` | `6.96e-2` | scaling 溢出已修正，相对误差为 near-zero 放大 |
| `radartools/pulse_doppler` | `1048576` | `3.09x` | `584.8x` | `1.08e-5` | `8.64e-6` | padding/truncation pack 已修正 |
| `spectral/vectorstrength` | `1048576` | `398.2x` | `983x` | `8.89e-5` | `9.76e-2` | two-stage reduction 生效，相对误差为 near-zero 放大 |

候选报告分类：

| 类型 | 数量 | 说明 |
|---|---:|---|
| `already-fast` | `41` | 当前速度与误差均满足大规模口径 |
| `e2e-copy-bound` | `9` | kernel 已快，端到端受 H2D/D2H、launch 或 API 粒度限制 |
| `kernel-bound` | `1` | `peak_finding/argrelextrema`，最大规模 kernel speedup 约 `5.75x` |
| `error-bound` | `1` | `radartools/ca_cfar`，最大规模 `max_rel_error` 约 `0.012` |
| `scalar-helper` | `1` | `radartools/cfar_alpha`，标量公式 helper |

## 剩余瓶颈与后续方向

- `peak_finding/argrelextrema`：当前仍是唯一 kernel-bound 算子。后续可考虑窗口比较的 tile/block 化，减少全局访存和分支开销。
- `radartools/ca_cfar`：唯一真实 error-bound。后续应单独检查 guard/training 窗口边界、CPU/CUDA 累加顺序和阈值计算口径。
- `bsplines/*`、`wavelets/qmf`、`waveforms/chirp/square/sawtooth`：主要是 e2e-copy-bound。kernel 已很快，继续提升端到端速度需要上层支持 GPU resident 数据流或批处理 API。
- `detrend` 与 `kalman_filter`：kernel 已大幅加速，但 e2e 约 `2x`。这类算子更适合放入 GPU pipeline 中与前后处理融合，而不是作为单次 host API 调用单独测。

## 验收记录

- `cmake --build build --target cusignal_zx_gpu`：通过。
- `python3 -m py_compile scripts/test/benchmark_all_ops_scales.py scripts/test/plot_all_ops_benchmark.py`：通过。
- 源码范围 `git diff --check`：通过。
- 精准单测：`filtering_test_sosfilt`、`filtering_test_detrend`、`filtering_test_resample`、`estimation_test_kalman_filter`、`waveforms_test_gausspulse`、`waveforms_test_sawtooth`、`waveforms_test_chirp`、`waveforms_test_square`、`demod_test_fm_demod`、`radartools_test_pulse_doppler`、`spectral_test_vectorstrength` 均通过。
- 全量 large-gpu benchmark：`318/318` 行全部 `passed`。
- 最终作图：PDF/SVG/PNG 均生成成功。
- `data/generated/unit/**/manifest.json`：全量运行前后 hash 一致。
