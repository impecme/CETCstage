# V3.3.0 `scripts/test` 全量 6 规模性能与误差采集

## 版本信息

- 版本名称：`V3.3.0 scripts/test 全量 6 规模性能与误差采集`
- 版本定位：覆盖当前已启用 53 个算子的多规模 `perf` 自动化采集，不改公开算子 API，不改测试阈值。
- 完成状态：已完成脚本、代表性冒烟与文档入口。

## 版本目标

- 对 `run_all_tests.sh --list` 当前启用的 53 个算子统一执行 6 个规模点。
- 输出性能与误差 CSV，便于后续按 `scale_level=1..6` 直接作图对比。
- 同输入格式尽量使用同一规模族，不同复杂度算子使用更贴合计算量的规模族。
- 对特殊算子补齐稳定缩放字段，减少 skipped。

## 关键变更

- 新增脚本：`scripts/test/benchmark_all_ops_scales.py`
  - 自动读取 `run_all_tests.sh --list` 的启用算子清单。
  - 每个算子执行 6 个规模点。
  - 临时改写 `data/generated/unit/<module>/<operator>/manifest.json`，结束后 `finally` 恢复。
  - 失败行记录 `status=failed` 与 `error_note`，不阻塞后续算子。
- 删除历史专项规模脚本：
  - `scripts/test/benchmark_bsplines_scales.py`
  - `scripts/test/benchmark_modules_scales.py`
  - 后续按模块/算子筛选统一使用 `benchmark_all_ops_scales.py --modules ... --operators ...`
- 扩展 `filtering` 测试支持：
  - `lfilter_zi` 新增 perf 可选字段 `filter_order`。
  - `channelize_poly` 新增 perf 可选字段 `x_count/h_count`。
- 更新文档：`scripts/test/README.md`
  - 增补全量脚本命令、输出路径、字段解释、规模策略和作图建议。

## 运行命令

```bash
# 全量 53 算子 x 6 规模，先构建再执行
scripts/test/benchmark_all_ops_scales.py --build --warmup 5 --repeat 30

# 复用已有二进制执行
scripts/test/benchmark_all_ops_scales.py --no-build

# 单算子冒烟
scripts/test/benchmark_all_ops_scales.py \
  --modules bsplines \
  --operators cubic \
  --no-build \
  --warmup 1 \
  --repeat 1

# 特殊缩放算子冒烟
scripts/test/benchmark_all_ops_scales.py \
  --modules filtering,spectral \
  --operators lfilter_zi,channelize_poly,istft,lombscargle \
  --build \
  --warmup 1 \
  --repeat 1
```

## 输出产物

- `data/reports/unit/benchmarks/all_ops/all_ops_scale_benchmark_<run_id>.csv`
- `data/reports/unit/benchmarks/all_ops/latest_all_ops_scale_benchmark.csv`
- `data/reports/unit/benchmarks/all_ops/<module>_scale_benchmark_<run_id>.csv`
- `data/reports/unit/benchmarks/all_ops/latest_<module>_scale_benchmark.csv`

## CSV 字段

- `scale_level`：抽象规模级别，固定为 `1..6`，推荐作为跨算子作图横轴。
- `scale_value`：当前算子的实际规模值，例如点数、总元素数、tap 数或帧数。
- `scale_family`：规模族，说明该算子使用哪套规模阶梯。
- `status`：运行状态，当前为 `passed` / `failed`。
- `pass`：`return_code==0` 且 `summary.pass=true` 时为 `true`。
- `max_abs_error/max_rel_error/rmse`：GPU 输出相对 CPU 输出的误差，来自标准 `latest_metrics.json` 的 summary。
- `cpu_*_ms`：CPU 延迟统计，包含 `median/mean/p95/min/max/std`。
- `gpu_e2e_*_ms`：GPU 端到端延迟统计，包含 `median/mean/p95/min/max/std`。
- `gpu_kernel_*_ms`：GPU kernel 延迟统计，包含 `median/mean/p95/min/max/std`。
- `gpu_e2e_speedup/gpu_kernel_speedup`：CPU median 相对 GPU median 的速度比。
- `shape_note`：本行 manifest 实际改写的关键规模字段摘要。
- `metrics_json_path`：本行读取的 `latest_metrics.json` 绝对路径。
- `error_note`：失败诊断信息。

误差口径：
- `max_abs_error/max_rel_error/rmse` 固定表示 GPU 相对 CPU，不包含 reference error。
- `max_rel_error` 保存 ratio 小数，不保存百分数。
- 若需要百分比图，在绘图阶段使用 `max_rel_error * 100`。

## 规模策略

| `scale_family` | 6 个规模点 | `scale_value` 含义 | 对应算子 |
|---|---:|---|---|
| `linear_points` | `1024,4096,16384,65536,262144,1048576` | 一维点数或样本数 | `waveforms/chirp`、`waveforms/gausspulse`、`waveforms/sawtooth`、`waveforms/square`、`waveforms/unit_impulse`、`bsplines/cubic`、`bsplines/quadratic`、`bsplines/gauss_spline`、`windows/chebwin`、`windows/general_cosine`、`windows/general_gaussian`、`windows/hamming`、`windows/kaiser`、`windows/parzen`、`windows/taylor`、`windows/triang`、`wavelets/qmf`、`wavelets/morlet`、`wavelets/ricker`、`wavelets/morlet2` |
| `medium_1d_fft` | `1024,2048,4096,8192,16384,32768` | 中等规模一维长度或事件数 | `filtering/firfilter2`、`filtering/sosfilt`、`filtering/hilbert`、`filtering/detrend`、`filtering/freq_shift`、`filtering/channelize_poly`、`filtering/decimate`、`filtering/resample`、`filtering/resample_poly`、`filtering/upfirdn`、`spectral/csd`、`spectral/spectrogram`、`spectral/stft`、`spectral/vectorstrength`、`wavelets/cwt` |
| `heavy_quadratic` | `256,512,1024,2048,4096,8192` | 重计算输入长度 | `radartools/ambgfun`、`spectral/lombscargle`、`correlate/correlate` |
| `matrix_total` | `4096,16384,65536,262144,524288,1048576` | 矩阵/图像总元素数 | `filtering/wiener`、`filtering/firfilter`、`filtering/hilbert2`、`radartools/pulse_compression`、`radartools/pulse_doppler`、`radartools/ca_cfar`、`correlate/correlate2d`、`demod/fm_demod`、`peak_finding/argrelextrema` |
| `filter_design_taps` | `129,257,513,1025,2049,4097` | FIR tap 数 | `filter_design/firwin`、`filter_design/firwin2` |
| `small_state` | `16,32,64,128,256,512` | 小状态数、滤波阶数或点数 | `filtering/lfilter_zi`、`radartools/cfar_alpha`、`estimation/kalman_filter` |
| `istft_frames` | `9,17,33,65,129,257` | `istft` 时间帧数 | `spectral/istft` |

## `lfilter_zi` 说明

原计划中的 `16,32,64,128,256,512` 在第一次 `--no-build` 冒烟中看起来可以跑，是因为当时复用了旧二进制。旧二进制还没有编译进 `filter_order` 解析逻辑，所以脚本虽然改写了 manifest，但测试程序没有读取这个新字段，实际仍在跑原来的固定小阶数默认用例。

带 `--build` 重新编译后，新二进制开始读取 `filter_order`，于是 `256/512` 会触发旧 CUDA 实现里的 `kMaxFilterOrder=128` 边界，并报错 `filter order exceeds CUDA zi solver limit`。V3.3.0 已将 `lfilter_zi` 求解器上限单独提高到 `512`，普通 `lfilter` 的每线程状态上限仍保持 `128`，因此 `lfilter_zi` 继续使用原计划的 `16,32,64,128,256,512`。

注意：当前 `lfilter_zi` CUDA 求解器仍是单 kernel 单线程高斯消元，高阶性能会明显变慢。实测 `filter_order=512` 的 GPU kernel 单次约 `6551 ms`，该数据可用于展示实现瓶颈，但不代表并行优化后的最终性能。

## 验收结果

- `benchmark_all_ops_scales.py --help`：通过。
- `python3 -m py_compile scripts/test/benchmark_all_ops_scales.py`：通过。
- 启用算子清单：53 个。
- manifest 映射检查：53 个算子均存在 manifest，且均有 scale mapping。
- `bsplines/cubic`：6 行全部 `passed`，manifest 前后哈希一致。
- `filtering/lfilter_zi`：带构建重跑原计划 `16,32,64,128,256,512` 后 6 行全部 `passed`，manifest 前后哈希一致。
- `filtering/channelize_poly`：带构建代表性冒烟通过，manifest 前后哈希一致。
- `spectral/istft,lombscargle`：12 行全部 `passed`，manifest 前后哈希一致。
