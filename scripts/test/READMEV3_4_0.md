# V3.4.0 `scripts/test` CUDA 标准库适配分析与低速算子二次优化

## 版本信息

- 版本名称：`V3.4.0 scripts/test CUDA 标准库适配分析与低速算子二次优化`
- 版本定位：在 V3.3.0 全量 6 规模采集基础上，补齐论文风格作图、CUDA 标准库候选分析，并对低速算子做第二轮 GPU 并行化优化。
- 约束：不改公开 C++ API，不改 CSV 字段，不放宽误差阈值。
- 验收口径：同时观察 `gpu_kernel_speedup` 与 `gpu_e2e_speedup`。第一阶段优先解决真实 kernel 瓶颈，第二阶段记录 host-device 搬运型瓶颈。

## 更改思路

本轮优化先用全量 benchmark 找到低速来源，再决定是否引入 CUDA 标准库或自定义 kernel。判断逻辑如下：

- `kernel-bound`：`gpu_kernel_speedup` 仍低，说明算子内部并行性没有展开，优先重构 kernel。
- `e2e-copy-bound`：kernel 已经很快，但 `gpu_e2e_speedup` 不高，说明主要消耗在 H2D/D2H、临时 workspace、D2D copy 或 launch 上。
- `scalar-helper`：本质是标量公式或 tiny helper，不适合作为 GPU kernel 优化对象。
- `already-fast`：kernel 与 e2e 均已有足够收益，暂不改动。

标准库选择采用“能减少算法复杂度或显著提高并行度才引入”的原则：

- `cuFFT`：适合长 FIR、卷积、频域滤波；当前 33-tap `firfilter` 先用 direct parallel FIR，长 taps 后续再接 cuFFT。
- `cuSOLVER`：适合一般 IIR `lfilter_zi` 的小型线性系统后备路径；当前主瓶颈不依赖它。
- `cuBLAS/cuBLASLt`：不用于 tiny Kalman fast path。矩阵太小，库调用和 handle/launch 开销大于收益。
- `cuSPARSE`：当前算子没有真实稀疏矩阵计算，不引入。
- `cuDNN`：面向深度学习卷积/张量算子，不适合这批信号处理路径，不引入。

## 关键变更

- `scripts/test/plot_all_ops_benchmark.py`
  - 新增论文风格图生成，默认输出 PDF/SVG/PNG。
  - 新增 `latest_all_ops_plot_summary.csv`，每个算子一行。
  - 新增 `latest_cuda_library_candidate_report.csv/md`，输出瓶颈类型和 CUDA 库建议。
- `filtering/firfilter`
  - 对 FIR、无 `zi/zf`、短 taps 路径新增 direct parallel FIR kernel。
  - 每个输出样本一个线程，覆盖当前 perf case 的短 FIR。
  - IIR、stateful、长 taps 保留 fallback。
- `filtering/sosfilt`
  - 对连续轴、无 `zi/zf`、长序列路径新增二阶 SOS affine prefix-scan。
  - section 间保持顺序，section 内沿样本维并行。
  - 其他形态保留原 line-serial fallback，保证语义不变。
- `demod/fm_demod`
  - 将 `angle + unwrap + diff` 串行链路替换为 fused phase-difference kernel。
  - 直接使用相邻复样本计算相位增量，避免 unwrap 前缀依赖。
- `estimation/kalman_filter`
  - 增加小状态 register-only fast path，覆盖当前 `dim_x=4, dim_z=2, dim_u=2` 与小维度场景。
  - 保留 separate `predict()` / `update()` API，因此 e2e 仍受 launch 和数据搬运限制。
- 点式算子内部拷贝
  - `bsplines/*` 与 `wavelets/*` 能安全直接写返回对象的路径已去除 workspace 后的内部 D2D copy。

## 作图脚本

默认读取：

```bash
data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv
```

推荐命令：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops/figures \
  --formats pdf,svg,png \
  --dpi 450
```

输出文件：

- `figure_1_accuracy_performance_overview.*`
- `figure_2_module_timing_facets.*`
- `figure_3_speedup_ranking.*`
- `figure_4_error_distribution.*`
- `figure_5_pareto_speed_accuracy.*`
- `latest_all_ops_plot_summary.csv`
- `latest_cuda_library_candidate_report.csv`
- `latest_cuda_library_candidate_report.md`

## 全量回归命令

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops
```

## 关键结果

最新全量 CSV：

```bash
data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv
```

全量结果为 `318` 行，即 `53` 个启用算子乘 `6` 个规模点，全部 `passed`。

| 算子 | 最大规模 | e2e speedup | kernel speedup | 结论 |
|---|---:|---:|---:|---|
| `filtering/lfilter_zi` | `512` | `121.47x` | `254.96x` | 已摆脱旧高阶串行瓶颈 |
| `filtering/firfilter` | `1048576` | `4.93x` | `68.93x` | direct FIR kernel 生效 |
| `filtering/firfilter2` | `32768` | `3.86x` | `7.69x` | 当前短 FIR filtfilt 路径可用 |
| `demod/fm_demod` | `1048576` | `2.98x` | `57.76x` | fused phase-difference kernel 生效 |
| `estimation/kalman_filter` | `512` | `0.16x` | `1.58x` | kernel 过线，e2e 受 API/launch 限制 |
| `filtering/sosfilt` | `32768` | `0.97x` | `2.55x` | prefix-scan 改善明显，但仍偏 overhead-bound |
| `filtering/detrend` | `32768` | `0.57x` | `2.54x` | CPU 太快，适合后续融合到 GPU pipeline |

相对上一轮全量基线的最大规模变化：

| 算子 | e2e median | kernel median | kernel speedup |
|---|---:|---:|---:|
| `filtering/firfilter` | `8.831 -> 2.577 ms` | `5.987 -> 0.184 ms` | `2.21x -> 68.93x` |
| `filtering/sosfilt` | `0.218 -> 0.141 ms` | `0.130 -> 0.053 ms` | `1.05x -> 2.55x` |
| `demod/fm_demod` | `0.490 -> 0.218 ms` | `0.283 -> 0.011 ms` | `2.28x -> 57.76x` |
| `estimation/kalman_filter` | `0.248 -> 0.190 ms` | `0.065 -> 0.019 ms` | `0.48x -> 1.58x` |

## 候选报告解读

`latest_cuda_library_candidate_report.csv/md` 将 53 个算子分为：

- `already-fast`：37 个。
- `e2e-copy-bound`：12 个。典型是 `bsplines/*`、点式 `wavelets/waveforms`、部分 window 算子，kernel 很快但 e2e 受数据搬运影响。
- `kernel-bound`：3 个。当前主要为 `kalman_filter`、`detrend`、`sosfilt`。
- `scalar-helper`：1 个。`radartools/cfar_alpha` 是标量公式 helper，不作为 GPU kernel 优化对象。

## 剩余瓶颈与后续方向

- `sosfilt`：IIR 递推天然有前后依赖，prefix-scan 已把 section 内样本并行化；若要继续提升，需要减少 scan 中间写回、合并 section launch，或针对固定 SOS 数做更激进模板化。
- `detrend`：计算量太小，CPU 最大规模仅约 `0.070 ms`。后续更适合与前后处理融合，避免单独 launch 和单独搬运。
- `kalman_filter`：小矩阵和时间递推导致 cuBLAS/cuBLASLt 不划算。后续真正有效的方向是 batched 多实例、融合多步 predict/update，或提供 GPU resident pipeline。
- `e2e-copy-bound` 点式算子：已移除部分内部 D2D copy，但 benchmark 仍包含必要 H2D/D2H。要进一步拉开 e2e，需要上层 API 支持数据驻留或批处理。

## 验收记录

- `cmake --build build --target cusignal_zx_gpu`：通过。
- `python3 -m py_compile scripts/test/benchmark_all_ops_scales.py scripts/test/plot_all_ops_benchmark.py`：通过。
- `git diff --check`：通过。
- 精准单测：`filtering_test_firfilter`、`filtering_test_firfilter2`、`filtering_test_sosfilt`、`filtering_test_detrend`、`demod_test_fm_demod`、`estimation_test_kalman_filter`、`bsplines_test_cubic`、`bsplines_test_quadratic` 均通过。
- 全量 benchmark：`318/318` 行全部 `passed`。
- `latest_all_ops_plot_summary.csv`：`53/53` 行全部 `passed`。
- `data/generated/unit/**/manifest.json`：全量运行前后 hash 一致。
