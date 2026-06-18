# READMEV4_8

## 版本目标

V4.8 单独迁移报告 schema，将当前执行链路中的 `cuda_*` 资源字段和 `cudart_version` 编译配置字段改为中性 GPU 命名。该版本不改算法、不改 kernel、不改中科芯 SDK 兼容 API。

## 核心改动

- Task demo 资源字段改为 `gpu_free_mib`、`gpu_total_mib`、`gpu_device`、`gpu_device_name`。
- Task demo 资源漂移字段改为 `gpu_free_delta_mib`、`gpu_free_memory_drift_mib`、`gpu_free_drift_mib`。
- Task demo 汇总脚本和 scale 绘图脚本同步读取 `gpu_*` 字段。
- Unit metrics 的 `compile_config.cudart_version` 改为 `compile_config.runtime_version`。
- 当前测试 README 的标准 JSON 示例同步为 `runtime_version`。

## 保留内容

以下仍是中科芯 SDK 兼容接口或编译语义，不属于报告 schema：

- `cudaMemGetInfo`、`cudaGetDeviceProperties`、`CUDART_VERSION`
- `cuda_runtime.h`、`cudaMalloc`、`cudaMemcpy`、`cudaDeviceSynchronize`、`cudaEvent*`
- `cufft*`、`cublas*`、`cusolver*`
- `.cu` 后缀
- `dlcc -x cuda --cuda-gpu-arch=dlgput64`

## 验证状态

本轮已完成本地 schema 修改，并在容器内完成 Stage4 full 复验。

- 容器命令：`scripts/platform/run_zhongkexin_stage4.sh`
- 复验配置：`TASK_SCALES=1,2,3,4,5,6`、`BENCH_MODULES=all`、`BENCH_SCALE_LEVELS=1,2,3,4,5,6`、`BENCH_WARMUP=5`、`BENCH_REPEAT=30`
- 结果：`stage4_full_v48.log` 显示 `PASS`
- 取回报告：`data/reports/zhongkexin/stage4_v48_latest/`、`data/reports/unit/benchmarks/zhongkexin_stage4_full_v48/`
- schema 检查：取回的 JSON/CSV/Markdown 报告未出现旧 `cuda_*` 报告键或 `cudart_version` 字段

说明：Stage4 full 生成的编译日志中仍可能出现中科芯 SDK 兼容头文件路径和 API 名称，例如 `cuda_device_runtime_api.h`、`cudaDeviceSynchronize`。这些属于 SDK 兼容层诊断信息，不是项目报告 schema。
