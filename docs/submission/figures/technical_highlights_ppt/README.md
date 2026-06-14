# CETC 技术亮点 PPT 融合图索引

本目录是面向答辩 PPT 的融合版图件：把 30 个逐算子技术亮点压缩为 7 张大字号复合示意图。每张图覆盖一组相关算子/工程机制，图内不放总标题，主标签字号更大，便于投影展示。

逐算子细节图仍保留在 `docs/submission/figures/technical_highlights/`，本目录优先用于 PPT 正文。

| 序号 | PPT 图件 | 覆盖亮点 | 视觉重点 | 证据路径 |
|---:|---|---|---|---|
| 1 | [`01_parallel_operator_fusion.png`](01_parallel_operator_fusion.png)<br>[`01_parallel_operator_fusion.svg`](01_parallel_operator_fusion.svg) | sosfilt prefix-scan<br>detrend two-stage reduction + Kahan<br>vectorstrength / lombscargle reduction<br>fm_demod phase-difference fusion | 把递推、归约、相位差等串行瓶颈合并讲成一条 CUDA 并行化方法论。 | `src/cuda/filtering.cu`<br>`src/cuda/spectral.cu`<br>`src/cuda/demod.cu` |
| 2 | [`02_frequency_radar_operator_fusion.png`](02_frequency_radar_operator_fusion.png)<br>[`02_frequency_radar_operator_fusion.svg`](02_frequency_radar_operator_fusion.svg) | batched FFT<br>pulse_doppler safe packing<br>CA-CFAR integral image<br>ambgfun tile FFT<br>MVDR cuBLAS/cuSOLVER path | 把 FFT 频域加速、雷达检测和线性代数路径整合为一张雷达算子簇图。 | `src/cuda/radartools.cu`<br>`tests/unit/radartools/`<br>`scripts/test/READMEV3_8_4.md` |
| 3 | [`03_workspace_cache_fusion.png`](03_workspace_cache_fusion.png)<br>[`03_workspace_cache_fusion.svg`](03_workspace_cache_fusion.svg) | DeviceStorage cache<br>FilteringWorkspace + LineBasesCache<br>resample / channelizer prepared cache<br>SpectralWorkspace plan reuse<br>firwin2 / chebwin / CWT cache | 把 DeviceStorage、Workspace、prepared cache、plan/cache 复用合并为数据驻留图。 | `include/cusignal/core/types.hpp`<br>`src/cuda/filtering.cu`<br>`src/cuda/spectral.cu`<br>`src/cuda/windows.cu` |
| 4 | [`04_task_pipeline_fusion.png`](04_task_pipeline_fusion.png)<br>[`04_task_pipeline_fusion.svg`](04_task_pipeline_fusion.svg) | Task1 radar pipeline<br>Task2 multidomain pipeline<br>CA-CFAR / ambgfun<br>spectrogram / CWT<br>Kalman gate | 把 Task1 与 Task2 端到端链路放到同一张图，对比算子组合、业务 gate 与证据产物。 | `demo/task1_radar/`<br>`demo/task2_features/`<br>`data/reports/demo/` |
| 5 | [`05_task2_postprocess_estimation_fusion.png`](05_task2_postprocess_estimation_fusion.png)<br>[`05_task2_postprocess_estimation_fusion.svg`](05_task2_postprocess_estimation_fusion.svg) | Task2 fused postprocessing<br>peak select CUB path<br>Kalman points-batched fast path<br>device-side score / track | 把 Task2 fused 后处理、峰值筛选和 Kalman 批处理合并展示为 device-side 后处理链。 | `demo/task2_features/task2_features_cuda.cu`<br>`src/cuda/peak_finding.cu`<br>`src/cuda/estimation.cu` |
| 6 | [`06_validation_benchmark_evidence_fusion.png`](06_validation_benchmark_evidence_fusion.png)<br>[`06_validation_benchmark_evidence_fusion.svg`](06_validation_benchmark_evidence_fusion.svg) | 81 unit test entries<br>53 ops L1-L6 benchmark<br>precision audit<br>demo self-validation<br>invalid input / resource drift gate<br>compute-sanitizer deep check<br>plot report pipeline | 把单测、六档 benchmark、自验收、sanitizer 和图件报告串成一条可复跑证据链。 | `tests/unit/`<br>`scripts/test/`<br>`data/reports/unit/`<br>`data/reports/demo/` |
| 7 | [`07_performance_precision_gate_fusion.png`](07_performance_precision_gate_fusion.png)<br>[`07_performance_precision_gate_fusion.svg`](07_performance_precision_gate_fusion.svg) | e2e speedup<br>kernel speedup<br>mixed_error / max_abs_error<br>RMSE task gate<br>GPU-only retest + CPU baseline cache | 把 e2e speedup、kernel speedup、mixed_error、RMSE 和业务 gate 的口径放在一张图里讲清。 | `scripts/test/benchmark_all_ops_scales.py`<br>`scripts/test/audit_all_ops_precision.py`<br>`docs/submission/` |

重新生成：

```bash
python3 scripts/figures/generate_technical_highlight_ppt_figures.py
```
