# V4.8 第八阶段：报告 schema 中性化

## 当前状态

- 状态：已完成，容器 Stage4 full 复验通过。
- 时间：2026-06-18。
- 进入依据：V4.7 已完成低风险 CUDA 遗留表述收口；当前剩余可迁移项集中在 demo/report 字段命名。
- 本阶段目标：把当前执行链路生成和消费的报告字段从 `cuda_*` / `cudart_version` 改为中性 `gpu_*` / `runtime_version`，避免报告 schema 继续暴露 NVIDIA/CUDA 命名。

## 本轮范围

### Task demo 报告

- `cuda_free_mib` -> `gpu_free_mib`
- `cuda_total_mib` -> `gpu_total_mib`
- `cuda_device` -> `gpu_device`
- `cuda_device_name` -> `gpu_device_name`
- `cuda_free_delta_mib` -> `gpu_free_delta_mib`
- `cuda_free_memory_drift_mib` -> `gpu_free_memory_drift_mib`
- `cuda_free_drift_mib` -> `gpu_free_drift_mib`

覆盖文件：

- `demo/task1_radar/task1_radar_demo.cpp`
- `demo/task2_features/task2_features_demo.cpp`
- `scripts/test/run_task_demos.sh`
- `scripts/test/plot_task_demo_scale_benchmark.py`

### 单算子 metrics 报告

- `compile_config.cudart_version` -> `compile_config.runtime_version`

覆盖文件：

- `tests/unit/common/report.hpp`
- `scripts/test/README.md`

## 明确不改的内容

- 不改 `cudaMemGetInfo`、`cudaGetDeviceProperties`、`CUDART_VERSION` 等 SDK 兼容 API/宏。
- 不改 `cuda_runtime.h`、`cudaMalloc`、`cudaMemcpy`、`cudaDeviceSynchronize`、`cudaEvent*`。
- 不改 `cufft*`、`cublas*`、`cusolver*`。
- 不改 `.cu` 源文件后缀和 `dlcc -x cuda --cuda-gpu-arch=dlgput64`。
- 不改 V1-V4.7 历史迁移过程文档中的历史字段描述。

## 验证要求

- `bash -n scripts/test/run_task_demos.sh`
- `python3 -m py_compile scripts/test/plot_task_demo_scale_benchmark.py`
- 本地定向扫描确认当前执行链路不再出现旧报告字段。
- 容器内运行 Stage4 full，作为正式关闭证据。

## 验证结果

- 本地 `bash -n scripts/test/run_task_demos.sh` 通过。
- 本地 `python3 -m py_compile scripts/test/plot_task_demo_scale_benchmark.py` 通过。
- 本地定向扫描确认 demo/report 生产端和消费端不再使用旧报告字段。
- 容器内执行 Stage4 full 通过，日志取回为 `stage4_full_v48.log`。
- 取回的 `data/reports/zhongkexin/stage4_v48_latest/` 与 `data/reports/unit/benchmarks/zhongkexin_stage4_full_v48/` 中，JSON/CSV/Markdown 报告未出现旧 `cuda_*` 报告键或 `cudart_version` 字段。

## 完成判定

- 当前 demo JSON/Markdown/CSV 报告输出使用 `gpu_*` 字段。
- 当前 task demo 汇总和 scale plot 消费 `gpu_*` 字段。
- 当前 unit metrics JSON 使用 `runtime_version`。
- SDK 兼容 API 保持原名，ZQ500 运行链路不受影响。
