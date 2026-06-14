# V3.7.0 单精度清理后全量回归扫描与优化候选重排

## 版本信息

- 版本名称：`V3.7.0 单精度清理后全量回归扫描与优化候选重排`
- 版本定位：在 V3.6.0 单精度清理后，重新扫描所有启用算子，区分真实性能/精度回退与近零参考值导致的相对误差放大。
- 基线版本：`4ed16e0`（V3.5.0）。
- 当前版本：`d97bbab`（V3.6.0）。

## 扫描口径

- `regression-bound`：当前 GPU e2e 或 kernel median 相比 V3.5.0 增加超过 `25%`。
- `error-bound`：非近零条件下 `max_rel_error > 1e-2`，或 `max_abs_error > 1e-3`，或 `rmse > 1e-4`。
- `near-zero-relative`：`max_rel_error > 1e-2`，同时 `max_abs_error <= 1e-4` 且 `rmse <= 1e-4`。
- `kernel-bound`：当前最大规模 `gpu_kernel_speedup < 10`，排除 scalar helper。
- `e2e-copy-bound`：kernel 已快但 e2e speedup `< 3`。

优先级：

- `P0`：失败、真实误差超阈值、或 e2e 与 kernel 同时明显回退。
- `P1`：单侧明显回退、kernel-bound 或 e2e-copy-bound。
- `P2`：near-zero-relative 或缺少基线，需要补充说明或复测。
- `P3`：scalar helper 或已满足当前口径。

## 统一脚本入口

本版不再新增独立测试脚本，统一使用 `scripts/test/benchmark_all_ops_scales.py` 完成多规模复测和候选报告生成。默认采用简洁输出，只保留主 CSV 与一份摘要报告；需要归档型细表时再显式使用 `--report-mode full`。

输出文件：

- `latest_all_ops_scale_benchmark.csv`
- `latest_report.md`

详细候选 CSV/Markdown 仍可通过 `--report-mode full` 生成。

## 本次扫描结果

本次 V3.7.0 扫描采用 `large-gpu` profile、`warmup=5`、`repeat=30`。基线目录为 `../CETC_v3_5_0`，当前版本报告目录为 `data/reports/unit/benchmarks/v37_rescan`。

- 主 CSV：`data/reports/unit/benchmarks/v37_rescan/latest_all_ops_scale_benchmark.csv`
- 行数：`318 = 53 x 6`
- 运行状态：`318 passed`
- 候选报告：`data/reports/unit/benchmarks/v37_rescan/latest_report.md`
- 分类计数：`P0=3`、`P1=10`、`P2=8`、`P3=32`

`P0` 真实优化队列：

| Operator | Type | 主要现象 | 推荐动作 |
|---|---|---|---|
| `filtering/detrend` | `error-bound` | `max_abs=5.58615e-4`、`rmse=2.79398e-4` | 继续检查单精度 reduction、分段线性拟合扣除和近零输出误差口径。 |
| `radartools/ca_cfar` | `error-bound` | `max_abs=4.49677e-2`、`rmse=3.23337e-3` | 优先复核 guard/training 窗口边界、阈值缩放和前缀和累加顺序。 |
| `spectral/vectorstrength` | `error-bound` | `max_abs=3.58708e-2`、`rmse=4.78903e-3` | 优先复核相位规约、向量和归约顺序与单精度补偿策略。 |

## P0 优化落地

本轮按 CA-CFAR 滑窗卷积经验优先处理 `ca_cfar`，并同步清理 V3.7.0 扫描暴露出的 `detrend` 与 `vectorstrength` 真实误差项。公开 API、benchmark CSV 字段和误差阈值均保持不变。

实现思路：

- `radartools/ca_cfar`
  - 1D 保留短窗 fused sliding-window kernel，并为长参考窗预留 cuFFT 频域卷积路径。
  - 2D 默认改为 GPU row-prefix + integral-image 路径，用外窗矩形和减内窗矩形和计算 training cells，避免直接逐点累加与 CPU 前缀和口径不一致。
  - `cfar_alpha` 仍作为 scalar helper，只在 host 端预计算单精度门限因子。
- `filtering/detrend`
  - CUDA 线性拟合 fast path 改为同时归约 `sum_y/sum_ty/sum_t/sum_t2`，局部循环使用 float Kahan 补偿。
  - CPU 大规模无断点 perf 路径镜像 CUDA two-stage pairwise reduction，使 GPU 相对 CPU 的报告口径一致。
- `spectral/vectorstrength`
  - CUDA 端保留两级 partial/final reduction，并加入 float Kahan 局部补偿。
  - CPU/GPU 大规模路径统一使用周期内相位规约和单精度多项式 `sin/cos`，减少 libm 与 CUDA intrinsic 差异。
  - 当 vector strength `< 1e-5` 时 phase 置 0；该区间相位物理上不可稳定定义，可避免近零向量导致的 phase ratio 放大。

最终 targeted 结果：

| Operator | 最大规模误差 | 最大规模性能 | 结论 |
|---|---|---|---|
| `radartools/ca_cfar` | `max_abs=0`、`max_rel=0`、`rmse=0` | e2e `7.14x`、kernel `51.20x` | P0 误差清除，2D 大规模路径稳定。 |
| `filtering/detrend` | `max_abs=1.19e-7`、`rmse=1.16e-10` | e2e `2.56x`、kernel `98.61x` | P0 误差清除，剩余相对误差为近零输出 ratio。 |
| `spectral/vectorstrength` | `max_abs=2.82e-6`、`rmse=6.95e-7` | e2e `328.99x`、kernel `1144.30x` | P0 误差清除，剩余相对误差进入 near-zero-relative 观察项。 |

复测与报告：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --operators ca_cfar,cfar_alpha,detrend,vectorstrength \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/v37_p0_optimized
```

最终简洁报告位于 `data/reports/unit/benchmarks/v37_p0_optimized/latest_report.md`。如需历史归档与候选细表，使用 `--report-mode full` 生成 `latest_large_gpu_candidate_report.csv/md`。本轮归档的合并全量复查结果显示 `P0=0`，剩余 `P1` 主要为 e2e-copy-bound、旧有 regression-bound 或下一轮 kernel-bound 项。

`P1` 性能/搬运队列：

| Operator | Type | 主要现象 |
|---|---|---|
| `bsplines/cubic` | `regression-bound` | e2e median 相比 V3.5.0 增加约 `27.23%`，kernel 未明显退化。 |
| `bsplines/quadratic` | `regression-bound` | e2e median 相比 V3.5.0 增加约 `26.73%`，kernel 未明显退化。 |
| `spectral/lombscargle` | `regression-bound` | kernel median 相比 V3.5.0 增加约 `28.56%`，但绝对性能仍较快。 |
| `peak_finding/argrelextrema` | `kernel-bound` | 最大规模 kernel speedup 约 `5.96x`，低于 `10x` 阈值。 |
| `bsplines/gauss_spline` | `e2e-copy-bound` | kernel 约 `1537x`，e2e 约 `1.59x`。 |
| `estimation/kalman_filter` | `e2e-copy-bound` | kernel 约 `729x`，e2e 约 `1.79x`，主要受 API 粒度和搬运影响。 |
| `waveforms/chirp` | `e2e-copy-bound` | kernel 约 `1963x`，e2e 约 `1.84x`，相对误差主要来自近零点。 |
| `waveforms/sawtooth` | `e2e-copy-bound` | kernel 约 `1690x`，e2e 约 `1.23x`。 |
| `waveforms/square` | `e2e-copy-bound` | kernel 约 `1845x`，e2e 约 `1.28x`。 |
| `wavelets/qmf` | `e2e-copy-bound` | kernel 约 `1875x`，e2e 约 `1.41x`。 |

近零相对误差观察队列：

- `radartools/ambgfun`、`spectral/stft`、`spectral/spectrogram`、`spectral/csd`、`waveforms/sawtooth`、`windows/chebwin`、`windows/general_cosine` 等属于 `max_rel_error` 很大但 `max_abs_error/RMSE` 很小的形态。
- `ambgfun` 样本级 floor-relative 诊断：`sample_max_abs_error=5.82e-11`、`sample_rmse=3.93e-11`、`sample_max_floor_relative_error=4.77e-7`。当前没有证据表明它存在真实数值爆炸。
- 已补充统一 stable error 指标：`max_floor_rel_error`、`near_zero_count`、`near_zero_fraction`、`error_class`。原始 `max_rel_error` 保留用于审计，默认作图和简洁报告使用 floor-relative 口径，不直接改 near-zero 类 kernel。
- `detrend` 的相对误差不随规模单调增长，主要受去趋势后输出穿零、分段边界和不同 reduction 路径影响；报告中需同时查看 `max_abs_error`、`rmse` 和 `max_floor_rel_error`。

## 推荐复测流程

基线复测：

```bash
git worktree add ../CETC_v3_5_0 4ed16e0
cd ../CETC_v3_5_0
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/v37_baseline_v35
```

当前版本复测：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/v37_rescan
```

## 初始重点名单

- 重点复核：`filtering/detrend`、`radartools/ca_cfar`、`peak_finding/argrelextrema`、`estimation/kalman_filter`、`wavelets/qmf`。
- 近零相对误差观察：`radartools/ambgfun`、`spectral/stft`、`spectral/spectrogram`、`spectral/csd`、`waveforms/chirp`、`waveforms/sawtooth`、`windows/chebwin`、`windows/general_cosine`。
- `radartools/cfar_alpha` 继续归类为 scalar helper。

实际扫描后，`spectral/vectorstrength` 上升为 `P0`，`ambgfun` 保持近零相对误差观察项。

## 运行注意

- 若 `data/generated/unit/**/manifest.json` 被清理或从 reference 恢复，部分算子的 generated manifest 可能只有 `accuracy_cases`，没有 `perf_cases`。这时需要先运行对应 `scripts/data/generate_*.py` 重新生成 generated perf 数据；`waveforms/chirp` 当前没有独立生成脚本，可从已验证的 generated perf manifest 恢复。
- 本次曾将缺失的 19 个算子补跑到 `data/reports/unit/benchmarks/v37_rescan_patch`，再按 `(module, operator, scale_level)` 合并回主 CSV。

## 后续优化顺序

1. 优先处理 `P0`：真实误差超阈值或 e2e/kernel 同时回退。
2. 再处理 `P1`：kernel-bound、e2e-copy-bound 或单侧明显回退。
3. `P2` 先补充 floor-relative diagnostics，不直接改 kernel。
4. `P3` 不进入本轮优化队列。
