# READMEV4_6

## 版本目标

V4.6 将项目从“CUDA 迁移后的兼容工程”收口为“面向中科芯 ZQ500 GPU 的专用信号处理算子库”。本轮目标不是新增算子功能，而是在不损坏 V4.5 已验证功能的前提下，移除项目自有 API、目录、target、脚本和当前入口文档中的 CUDA/NVIDIA 命名。

## 核心改动

- GPU 源码目录从 `src/cuda/` 改为 `src/zhongkexin/`。
- 静态库 target 从 `cusignal_cuda` 改为 `cusignal_zx_gpu`。
- 公开 GPU namespace 从 `cusignal::cuda_backend` 改为 `cusignal::zx_gpu_backend`。
- device 类型从 `core::Cuda*` 改为 `core::ZxGpu*`。
- 构造 helper 从 `make_cuda_*` 改为 `make_zx_gpu_*`。
- 错误检查 helper 从 `throw_on_cuda_error` 改为 `throw_on_zx_gpu_error`。
- 平台兼容头从 `platform_cuda_*` 改为 `platform_zx_gpu_*`。
- Task1/Task2 GPU helper 从 `task*_cuda.*` 改为 `task*_zx_gpu.*`。
- `run_all_tests.sh` 和 `benchmark_all_ops_scales.py` 当前入口固定为 `ZHONGKEXIN`，不再提供 NVIDIA 当前执行路径。
- Stage1 统一入口改为透传 `CUSIGNAL_ZHONGKEXIN_CXX_GPU_FLAGS`，probe 选出的 dlcc 参数会进入主工程配置。
- probe 和 CMake 的 SDK 搜索路径只保留中科芯 SDK 路径，不再搜索 `/usr/local/cuda` 或 NVIDIA Toolkit 环境变量。
- Task1/Task2 demo CMake 删除旧平台分支和 `CUDA_SEPARABLE_COMPILATION` 残留。

## 保留的兼容符号

中科芯 SDK 当前仍通过 CUDA-like 兼容接口工作，因此以下外部符号保留：

- `cuda_runtime_api.h`
- `cudaMalloc`、`cudaMemcpy`、`cudaDeviceSynchronize`、`cudaEvent*`
- `cufft*`、`cublas*`、`cusolver*`
- `dlcc -x cuda --cuda-gpu-arch=dlgput64`
- `.cu` GPU 源文件后缀

这些不是项目自有 CUDA 命名，不能删除或改成自造名称，否则会破坏 ZQ500 SDK 编译、链接和运行。

## 解决的问题

- 避免后续协作者误以为还需要维护 NVIDIA 路径。
- 避免公开 API 继续暴露 `cuda_backend`、`Cuda*` 等旧迁移命名。
- 让 README、AGENT、CMake、脚本和源码目录均围绕 CPU reference + ZQ500 GPU 双链路组织。

## 验证状态

本轮已完成本地静态重命名、CMake configure 检查、脚本语法检查、文档更新和容器 Stage4 full after rename 复验。容器内执行命令为：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

复验结果：

- `stage4_full_after_rename.log` 显示 `[zx-stage4] PASS`。
- Stage4 summary 显示 `pass=true`、`benchmark_rows=486`、`benchmark_failed_rows=0`、`plot_status=passed`。
- benchmark 报告显示 `operators=81`、`rows=486`、`passed_rows=486`。
- benchmark 图件目录共 87 个文件。

## 完成判定

V4.6 已关闭，关闭条件确认如下：

- Task1/Task2 L1-L6 通过。
- 81 个公开算子 benchmark 486/486 行通过。
- benchmark 图件生成通过。
- 当前入口代码中不再出现旧项目命名 `cuda_backend`、`Cuda*`、`cusignal_cuda`、`src/cuda`。

归档证据：

- `stage4_full_after_rename.log`
- `data/reports/zhongkexin/stage4_after_rename_latest/latest_stage4_summary.json`
- `data/reports/unit/benchmarks/zhongkexin_stage4_full_after_rename/latest_report.md`
- `data/reports/unit/benchmarks/zhongkexin_stage4_full_after_rename/figures`

## 遗留风险

- 这是破坏性 API 重命名，外部旧代码若调用 `cuda_backend` 或 `Cuda*` 类型，需要迁移到 `zx_gpu_backend` 和 `ZxGpu*`。
- 外部 SDK 兼容符号仍包含 `cuda/cufft/cublas/cusolver` 字样，这是中科芯 SDK 当前接口形态，不属于可清理项目命名。
