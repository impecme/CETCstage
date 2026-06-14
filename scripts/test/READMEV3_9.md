# V3.9 任务级 Demo 验收增强

## Summary

- 本版将 Task1/Task2 demo 从“生成报告 + 部分业务 PASS”升级为任务级自验收入口。
- 验收覆盖检测/轨迹一致性、分阶段耗时、计算误差、稳定性、资源占用、异常输入报错和可选深度内存/显存泄露检查。
- 公共算子 API 不变；单算子 benchmark CSV 追加兼容耗时列，改动集中在两个 demo、任务级汇总脚本、全量绘图脚本和文档。

## 实现方式

- C++ demo 内部新增 `ValidationResult` / `ValidationThresholds`，每轮运行后把检查项写入 `latest_metrics.json` 的 `validation` 区块；任一检查失败时可执行程序返回非零，并在 stderr 输出失败项、实际值和阈值。
- C++ demo 支持 `--scale-level 1..6`，默认不传时固定为 `L3`，保持历史任务场景和最新可视化输入兼容；`latest_metrics.json` 的 `scenario` 写出 `scale_level` 与 `scale_value`。
- `--repeat N` 用于稳定性复跑。每轮都会完整执行业务链路和数值检查，最终报告写出 `repeat_runs`，包含每轮 `cpu_total_ms`、`gpu_total_ms`、CUDA free memory 和当前 RSS。
- 资源采样由 demo 内部完成：读取 `/proc/self/statm` / `getrusage` 获取当前/峰值 RSS，通过 `cudaMemGetInfo` 和 `cudaGetDeviceProperties` 获取 CUDA free/total memory、device id 和 device name，写入 `resource_usage.before/after`。
- 稳定性 gate 使用 repeat 样本计算：业务与数值检查每轮都必须通过；`repeat > 2` 时 GPU timing jitter 统计跳过首轮预热样本；最终 CUDA free memory drop 不超过 `32 MiB`，当前 RSS 增长不超过 `64 MiB`。
- 异常输入通过 `--invalid-input-checks` 触发。demo 内部构造固定非法配置矩阵，要求 `validate_config` 抛出 `std::invalid_argument`，且错误信息包含对应字段名；未报错或报错不明确都会失败。
- 深度泄露检查由 `scripts/test/run_task_demos.sh --leak-check` 触发。脚本在可用时调用 `compute-sanitizer --tool memcheck` 分别包裹两个 demo，并把日志写入 `data/reports/demo/leak_check/`。
- `compute-sanitizer` 会显著放大 GPU timing，因此深检子进程使用内部参数 `--skip-timing-validation` 跳过性能 gate，但仍保留业务、误差、异常输入和资源字段检查；深检完成后脚本恢复正常运行生成的 latest metrics，避免 sanitizer timing 污染任务级汇总。
- demo 末尾使用 `cudaDeviceSynchronize()` 确保异步工作完成。当前库存在设备缓存/静态 CUDA 资源，强制 `cudaDeviceReset()` 会与进程结束时的缓存析构冲突，因此不在 demo 内主动 reset；泄露风险由 repeat 漂移和 compute-sanitizer 覆盖。

## 任务级 6 档规模

Task1 雷达检测规模：

| level | pulses | samples/pulse | template | pulse_compression_nfft | pulse_doppler_nfft | scale_value |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| L1 | 32 | 128 | 32 | 128 | 32 | 4096 |
| L2 | 48 | 256 | 64 | 256 | 64 | 12288 |
| L3 | 64 | 256 | 64 | 256 | 64 | 16384 |
| L4 | 96 | 512 | 128 | 512 | 128 | 49152 |
| L5 | 128 | 1024 | 256 | 1024 | 128 | 131072 |
| L6 | 192 | 1536 | 384 | 2048 | 256 | 294912 |

Task2 多域特征定位规模：

| level | frames | samples/frame | template | filter_taps | spectrogram nperseg/noverlap/nfft | scale_value |
| ---: | ---: | ---: | ---: | ---: | --- | ---: |
| L1 | 16 | 512 | 128 | 65 | 64 / 48 / 128 | 8192 |
| L2 | 32 | 768 | 192 | 97 | 96 / 72 / 128 | 24576 |
| L3 | 48 | 1024 | 256 | 129 | 128 / 96 / 256 | 49152 |
| L4 | 64 | 1536 | 384 | 161 | 192 / 144 / 256 | 98304 |
| L5 | 80 | 2048 | 512 | 193 | 256 / 192 / 512 | 163840 |
| L6 | 96 | 3072 | 768 | 257 | 384 / 288 / 512 | 294912 |

- `scripts/test/run_task_demos.sh --scale-sweep --repeat N` 会依次运行选定规模，将每档报告归档到 `data/reports/demo/<task>/scales/L<N>/`，并生成 `latest_task_demo_scale_benchmark.csv/json/md`。
- scale sweep 结束后脚本会再跑一次 L3 并生成可视化，确保 `latest_*` 与默认样例图仍代表兼容场景，而不是最后一个 L6 压测场景。
- Task2 的 L4-L6 使用到 `161/193/257` taps。CUDA filtering 的内部 `lfilter` order 上限已提升到 `256`，以覆盖 L6 的 257-tap FIR。

## 验收口径

- Task1：
  - `cpu_gpu_detection_match=true`
  - `gpu_matches_expected_detection=true`
  - GPU total <= baseline multiplier/hard limit
  - `pulse_compression`、`ambgfun_surface` 的 `mixed_error <= 1e-4`
  - `pulse_doppler` 默认 L1-L4 使用 `mixed_error <= 1e-4`，L5/L6 按大规模 FFT 单精度差异放宽到 `3e-4/5e-4`
  - `cfar_threshold` 是任务级中间输出，默认 L1-L3 使用 `mixed_error <= 5e-3`，L4/L5/L6 按规模放宽到 `5e-2/1e-1/5e-1`
- Task2：
  - `cpu_gpu_track_match=true`
  - `gpu_matches_truth_within_tolerance=true`
  - `kalman_track_error.rmse <= scenario.kalman_rmse_tolerance`
  - GPU total <= baseline multiplier/hard limit
  - `filtered`、`correlate`、`spectrogram`、`cwt`、`feature_score` 的 `mixed_error <= 1e-4`
  - `kalman_track` mixed error 仅用于诊断，正式 gate 是 track match 与 RMSE 容差
- 稳定性与资源：
  - repeat 内所有业务/数值检查通过
  - GPU total 相对中位数抖动 <= `35%`
  - CUDA free memory drop <= `32 MiB`
  - 当前 RSS 增长 <= `64 MiB`
- 泄露检查：
  - `compute-sanitizer` 日志要求 `ERROR SUMMARY: 0 errors`
  - 当前未配置 ASAN/LSAN 专用构建时，汇总报告标记 `asan_lsan=skipped`，不伪装成通过

## 命令与报告

构建：

```bash
cmake --build build --target task1_radar_demo task2_features_demo --parallel
```

单 demo 任务级验收：

```bash
CUDA_VISIBLE_DEVICES=1 ./build/demo/task1_radar/task1_radar_demo --repeat 5 --invalid-input-checks
CUDA_VISIBLE_DEVICES=1 ./build/demo/task2_features/task2_features_demo --repeat 5 --invalid-input-checks
```

统一任务级验收：

```bash
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --repeat 5
```

任务级 6 档扫测：

```bash
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 3
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --scale-sweep --scales 3,4,5,6 --repeat 3
```

深度泄露检查：

```bash
CUDA_VISIBLE_DEVICES=1 scripts/test/run_task_demos.sh --no-build --repeat 2 --leak-check
```

主要输出：

- `data/reports/demo/task1_radar/latest_metrics.json`
- `data/reports/demo/task1_radar/latest_summary.md`
- `data/reports/demo/task2_features/latest_metrics.json`
- `data/reports/demo/task2_features/latest_summary.md`
- `data/reports/demo/latest_task_demo_report.json`
- `data/reports/demo/latest_task_demo_report.md`
- `data/reports/demo/latest_task_demo_scale_benchmark.csv`
- `data/reports/demo/latest_task_demo_scale_report.json`
- `data/reports/demo/latest_task_demo_scale_report.md`
- `data/reports/demo/leak_check/*_compute_sanitizer.log`

## 全量算子性能图

- `scripts/test/benchmark_all_ops_scales.py` 的主 CSV 追加 `cpu_median_ms`、`gpu_e2e_median_ms`、`gpu_kernel_median_ms`、`gpu_e2e_min_ms`、`gpu_e2e_max_ms`；旧 speedup/error 字段保持不变。
- `scripts/test/plot_all_ops_benchmark.py --figure-set all` 会输出 5 张全局总览图，并额外为每个算子生成一张独立图到 `figures/operator_figures/`。
- 全局热图 y 轴直接使用完整 `module/operator` 算子名，并在每个热图 panel 内重复标注，便于单独截取任一 panel 时仍能对应具体算子。
- `scripts/test/plot_all_ops_benchmark.py --figure-set word --formats png,svg --dpi 300` 会输出 Word 友好版图件到 `figures/word_figures/`：按模块拆分，A4 纵向正文宽度，每个模块输出 5 类图，并生成 `latest_word_figure_manifest.csv`。
- 当前图件的含义：
  - `figure_1_accuracy_performance_overview.*`：每个 panel 的 y 轴直接标注完整算子名，列是 L1-L6，四个 panel 分别是 e2e speedup、kernel speedup、mixed error 和 pass/fail 状态，颜色使用 `log10` 便于压缩数量级。
  - `figure_2_cpu_gpu_e2e_time_heatmaps.*`：CPU/GPU e2e median 耗时热图，用于看各算子随规模增长的耗时分布；每个 panel 的 y 轴直接标注完整算子名。
  - `figure_3_e2e_speedup_heatmap.*`：e2e 加速比热图，用于看哪些算子在哪些规模下 GPU 加速明显；y 轴直接标注完整算子名。
  - `figure_4_largest_scale_cpu_vs_gpu_scatter.*`：每个算子取最大规模点，横轴 CPU、纵轴 GPU，虚线 `CPU=GPU`，点越低于虚线表示 GPU 越快。
  - `figure_5_largest_scale_speedup_rank.*`：每个算子最大规模的加速比排序。
- 每个算子的独立图命名为 `figures/operator_figures/<module>__<operator>.*`，上半部分是 L1-L6 的 CPU/GPU e2e median 耗时，下半部分是 e2e/kernel speedup。
- Word 版图件命名为 `figures/word_figures/figure_<N>_*_<module>.*`，不使用编号索引，图内直接显示完整 `module/operator`；插入 Word 时优先使用 `svg`，`png` 作为兼容备份。

## 当前验证结果

- `cmake --build build --target task1_radar_demo task2_features_demo --parallel` 通过。
- `scripts/test/run_task_demos.sh --no-build --repeat 5` 通过，两个 demo 均 `validation.pass=true`。
- `scripts/test/run_task_demos.sh --no-build --repeat 2 --leak-check` 通过，Task1/Task2 的 `compute-sanitizer` 日志均为 `ERROR SUMMARY: 0 errors`。
- 最新汇总报告：`data/reports/demo/latest_task_demo_report.md`。

## 注意事项

- 任务级 demo 的资源与性能阈值按当前 `NVIDIA A100-SXM4-40GB` 环境校准；跨机器复测时应先观察正常 `--repeat 5` 或 `--scale-sweep --repeat 3` 报告，再决定是否刷新 baseline。
- `data/reports/demo/latest_*` 始终代表最近一次运行结果；`--leak-check` 会保留 sanitizer 日志，并恢复正常 demo metrics 作为 latest 汇总来源。
- 若 GPU 被其他进程占用，资源漂移和 timing stability 可能失败；最终验收建议显式设置空闲设备，例如 `CUDA_VISIBLE_DEVICES=1`。
- `cfar_threshold_error` 和 `kalman_track_error.mixed_error` 不应简单套用单算子 `1e-4` 口径：前者是任务级中间阈值，后者是轨迹业务量，正式 gate 分别是任务级中间阈值和 RMSE/track 容差。
- `--skip-timing-validation` 仅供 sanitizer 深检子进程使用，不作为常规验收入口。
