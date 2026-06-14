# V3.8.0 Benchmark 混合误差与单 CSV 输出

## 目标

V3.8.0 将 benchmark 的主误差展示从原始相对误差切换为 `mixed_error`，避免参考值穿零时出现不直观的相对误差放大。C++ 单元测试原有 pass/fail 判断不放宽，原始 `max_abs_error`、`max_rel_error`、`rmse` 仍保留在单算子 `latest_metrics.json` 中用于追溯。

## 混合误差公式

对每个样本计算：

```text
expected_norm = abs(cpu_reference)
abs_diff      = abs(gpu_output - cpu_reference)
dynamic_floor = scale_factor * max(abs(cpu_reference))
effective_atol = max(case.atol, 1e-5f, dynamic_floor)

if expected_norm <= effective_atol:
    sample_error = abs_diff
else:
    sample_error = abs_diff / expected_norm

mixed_error = max(sample_error)
```

复数输出使用模长计算 `expected_norm` 与 `abs_diff`。`filtering` 与 `filter_design` 默认使用 `scale_factor = 1e-2`；`spectral` 中相位和 FFT 重构结果更容易在小幅值处放大相对误差，使用 `scale_factor = 1e-1`。该口径只改变 benchmark/报告的主展示指标，不改变单元测试判定阈值。若某个测试单元尚未提供逐样本 `mixed_error`，benchmark 汇总阶段会在“raw relative 很高但 `max_abs_error/RMSE` 很小”的近零形态下使用绝对误差作为兼容回退。

## 默认输出

全量 benchmark 默认只保留一份全量数据：

- `latest_all_ops_scale_benchmark.csv`
- `latest_report.md`

CSV 主字段收敛为：

```text
run_id,timestamp,scale_level,scale_value,scale_family,module,operator,
status,pass,return_code,warmup,repeat,mixed_error,error_class,
gpu_e2e_speedup,gpu_kernel_speedup,shape_note,metrics_json_path,
git_commit,gpu_name,error_note
```

以下输出仅在显式开启时生成：

- `--report-mode concise`：额外生成 `latest_report.md`
- `--report-mode full`：额外生成时间戳 CSV、分模块 CSV 和候选报告
- `plot_all_ops_benchmark.py`：额外生成 `figures/figure_1_accuracy_performance_overview.png` 与 `figures/latest_all_ops_plot_summary.csv`

## 运行命令

正式全量测试：

```bash
scripts/test/benchmark_all_ops_scales.py \
  --build --build-dir build \
  --warmup 5 --repeat 30 \
  --output-dir data/reports/unit/benchmarks/all_ops
```

可选生成总览图：

```bash
python3 scripts/test/plot_all_ops_benchmark.py \
  --csv data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv \
  --output-dir data/reports/unit/benchmarks/all_ops/figures \
  --dpi 450
```

## 结果解读

- `mixed_error` 是默认误差指标：近零区域看绝对误差，非近零区域看相对误差。
- `gpu_e2e_speedup` 是 CPU median / GPU 端到端 median。
- `gpu_kernel_speedup` 是 CPU median / GPU kernel median。
- 若需要追溯原始误差细节，查看对应算子的 `data/reports/unit/<module>/<operator>/latest_metrics.json`。
