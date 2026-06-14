# V3.8.2 `large-gpu` 全量基线与 Task2 回归记录

## 版本信息

- 版本名称：`V3.8.2 scripts/test large-gpu full benchmark and task2 regression`
- 版本定位：仅覆盖 `scripts/test` 测试、benchmark、plot 与回归记录。
- 完成时间：`2026-05-01`
- 约束：不改公开算子 API，不改测试阈值，不改根目录 README。

## 本轮目标

- 使用 `large-gpu` profile 全量运行当前启用的 53 个算子。
- 对每个算子运行 6 个规模点，形成 318 行性能与精度结果。
- 生成全量 benchmark 图表和 `large-gpu` candidate 报告。
- 针对 Task2 相关算子执行 `fm_demod / kalman_filter / argrelextrema` 回归。
- 为 Task2 端到端优化后的性能评估提供测试侧基线。

## 全量基线命令

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --scale-profile large-gpu \
  --warmup 5 --repeat 30 \
  --report-mode full \
  --output-dir data/reports/unit/benchmarks/all_ops_large
```

输出目录：

```text
data/reports/unit/benchmarks/all_ops_large/
```

关键输出：

- `latest_all_ops_scale_benchmark.csv`
- `latest_report.md`
- `latest_large_gpu_candidate_report.csv`
- `latest_large_gpu_candidate_report.md`
- `<module>_scale_benchmark_<run_id>.csv`
- `latest_<module>_scale_benchmark.csv`

## 图表生成命令

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops_large/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops_large/figures \
  --report-mode full \
  --dpi 450
```

图表输出：

- `data/reports/unit/benchmarks/all_ops_large/figures/latest_all_ops_plot_summary.csv`
- `data/reports/unit/benchmarks/all_ops_large/figures/figure_1_accuracy_performance_overview.png`

## 全量基线结果

本轮全量基线结果：

- CSV 行数：`318`
- 覆盖算子：`53`
- 每算子规模点：`6`
- `status=passed`：`318/318`
- `pass=true`：`318/318`
- 失败行：`0`
- `mixed_error` 最大值：`8.03277e-05`
- `gpu_e2e_speedup`：min `0.000641844x`，median `16.28065x`，max `3928.82x`
- `gpu_kernel_speedup`：min `0x`，median `197.1185x`，max `39715.4x`

`error_class` 统计：

| error_class | 行数 |
| --- | ---: |
| `ok` | 245 |
| `performance-bound` | 73 |

最大 `mixed_error` 观测项：

| 算子 | mixed_error | 说明 |
| --- | ---: | --- |
| `filtering/detrend` | `8.03277e-05` | 通过阈值 |
| `spectral/vectorstrength` | `7.66851e-05` | 通过阈值 |
| `filtering/resample` | `6.26596e-05` | 通过阈值 |
| `filtering/channelize_poly` | `5.85883e-05` | 通过阈值 |
| `filtering/hilbert2` | `5.18630e-05` | 通过阈值 |

最高 e2e speedup 观测项：

| 算子 | e2e speedup |
| --- | ---: |
| `wavelets/cwt` | `3928.82x` |
| `wavelets/cwt` | `3025.08x` |
| `wavelets/cwt` | `2270.39x` |
| `wavelets/cwt` | `1828.98x` |
| `wavelets/cwt` | `1441.91x` |

## Candidate 分类

Candidate 报告：

```text
data/reports/unit/benchmarks/all_ops_large/latest_large_gpu_candidate_report.csv
```

分类统计：

| bottleneck_type | 算子数 |
| --- | ---: |
| `already-fast` | 42 |
| `e2e-copy-bound` | 9 |
| `kernel-bound` | 1 |
| `scalar-helper` | 1 |

需要后续关注的非 `already-fast` / 非纯 `kernel-bound` 项：

| 类型 | 算子 | 最大规模 | e2e speedup | kernel speedup | 推荐动作 |
| --- | --- | ---: | ---: | ---: | --- |
| `scalar-helper` | `radartools/cfar_alpha` | 512 | `0.000769369x` | `0x` | scalar helper，无需 GPU 化 |
| `e2e-copy-bound` | `filter_design/firwin2` | 4097 | `2.79079x` | `34.7995x` | 减少内部 copy 或提升数据驻留 |
| `e2e-copy-bound` | `estimation/kalman_filter` | 524288 | `2.39286x` | `600.764x` | points-batched register kernel |
| `e2e-copy-bound` | `bsplines/quadratic` | 16777216 | `0.944157x` | `881.948x` | 减少内部 copy 或提升数据驻留 |
| `e2e-copy-bound` | `bsplines/cubic` | 16777216 | `1.03282x` | `999.635x` | 减少内部 copy 或提升数据驻留 |
| `e2e-copy-bound` | `wavelets/qmf` | 16777216 | `1.42317x` | `1165.45x` | 减少内部 copy 或提升数据驻留 |
| `e2e-copy-bound` | `waveforms/sawtooth` | 16777216 | `1.47825x` | `1381.33x` | 单精度数值路径 |
| `e2e-copy-bound` | `bsplines/gauss_spline` | 16777216 | `2.18980x` | `1387.93x` | 减少内部 copy 或提升数据驻留 |
| `e2e-copy-bound` | `waveforms/chirp` | 16777216 | `2.83120x` | `1919.62x` | 减少内部 copy 或提升数据驻留 |
| `e2e-copy-bound` | `waveforms/square` | 16777216 | `1.59323x` | `2015.85x` | 减少内部 copy 或提升数据驻留 |

## Task2 相关算子回归

回归命令：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --modules demod,estimation,peak_finding \
  --operators fm_demod,kalman_filter,argrelextrema \
  --scale-profile large-gpu \
  --no-build --warmup 3 --repeat 10 \
  --output-dir data/reports/unit/benchmarks/task2_regression
```

输出文件：

```text
data/reports/unit/benchmarks/task2_regression/latest_all_ops_scale_benchmark.csv
```

回归结果：

- CSV 行数：`18`
- `status=passed`：`18/18`
- `pass=true`：`18/18`
- 最大 `mixed_error`：`0`

最大规模点摘要：

| 算子 | 行数 | 最大 mixed_error | 最大规模 e2e speedup | 最大规模 kernel speedup |
| --- | ---: | ---: | ---: | ---: |
| `demod/fm_demod` | 6 | `0` | `5.49970x` | `476.753x` |
| `estimation/kalman_filter` | 6 | `0` | `2.03356x` | `600.888x` |
| `peak_finding/argrelextrema` | 6 | `0` | `4.97447x` | `7.58540x` |

## Task2 Demo 关联结果

Task2 demo 不是 `scripts/test` 的一部分，但本轮测试结果用于支撑优化后回归判断。

最新 demo 报告：

```text
data/reports/demo/task2_features/latest_metrics.json
```

关键结果：

- CPU total：`1156.530 ms`
- GPU total：`39.0923 ms`
- 端到端 speedup：`29.5846x`
- `cpu_gpu_track_match=true`
- `gpu_matches_truth_within_tolerance=true`
- Kalman track RMSE：`0.637415` samples

该结果说明 Task2 端到端 GPU 总耗时已低于 `40 ms`，同时 `scripts/test` 中 Task2 相关算子回归全部通过。

## 验收结论

`V3.8.2` 保持 `scripts/test` 既有脚本入口和 CSV schema 不变，在 `large-gpu` profile 下完成了全量 `53 x 6 = 318` 行基线采集、图表生成和 candidate 分类报告。全量基线、图表输入、Task2 相关算子回归均通过，可作为下一轮 e2e-copy-bound 与 Task2 pipeline 优化的测试侧基线。
