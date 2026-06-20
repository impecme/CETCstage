# V4.6 第六阶段：中科芯专用命名收口

## 当前状态

- 状态：已完成，容器 Stage4 full after rename 已通过。
- 时间：2026-06-18。
- 进入依据：V4.1-V4.5 已完成，项目已经形成 CPU reference + 容器内中科芯 ZQ500 GPU 的完整交付基线。
- 本阶段目标：把项目自有的 CUDA/NVIDIA 命名从当前工程入口中移除，改成专门面向中科芯 ZQ500 GPU 的算子库命名，同时不破坏已经通过的功能、测试、报告和 benchmark 链路。

## 命名边界

本阶段的“移除 CUDA”限定为项目自有抽象层和当前入口，不包括中科芯 SDK 对外提供的兼容 ABI/API 名称。

已重命名的项目自有抽象：

| 原命名 | 新命名 |
| --- | --- |
| `src/cuda/` | `src/zhongkexin/` |
| `cusignal_cuda` | `cusignal_zx_gpu` |
| `cusignal::cuda_backend` | `cusignal::zx_gpu_backend` |
| `core::CudaRealSignal` 等 `Cuda*` 类型 | `core::ZxGpuRealSignal` 等 `ZxGpu*` 类型 |
| `make_cuda_*` | `make_zx_gpu_*` |
| `throw_on_cuda_error` | `throw_on_zx_gpu_error` |
| `platform_cuda_compat.hpp` | `platform_zx_gpu_compat.hpp` |
| `platform_cuda_libraries.hpp` | `platform_zx_gpu_libraries.hpp` |
| `task*_cuda.cu/.hpp` | `task*_zx_gpu.cu/.hpp` |

必须保留的外部兼容符号：

| 符号类别 | 示例 | 保留原因 |
| --- | --- | --- |
| SDK 头文件 | `cuda_runtime_api.h`、`cublas_v2.h`、`cufft.h`、`cusolverDn.h` | 中科芯 SDK 以兼容接口提供 runtime/FFT/BLAS/SOLVER 能力 |
| runtime 函数 | `cudaMalloc`、`cudaMemcpy`、`cudaDeviceSynchronize`、`cudaEvent*` | 当前 ZQ500 编译和运行依赖这些外部符号 |
| 编译器参数 | `dlcc -x cuda --cuda-gpu-arch=dlgput64` | 中科芯编译器要求用该 CUDA-like 语义解析 `.cu` GPU 源 |
| 科学计算库 API | `cufft*`、`cublas*`、`cusolver*` | 中科芯库以兼容 API 暴露功能，源码不能擅自改名 |

因此，当前工程可以做到“项目 API、目录、target 和文档入口不再使用 CUDA/NVIDIA 作为自有命名”，但不能把外部 SDK 符号改名成项目自造符号，否则会破坏编译和链接。

## 已实施改动

### A. 构建系统

- 顶层 CMake 默认平台固定为 `ZHONGKEXIN`。
- 删除当前构建入口中的 NVIDIA 平台选择和 `CMAKE_CUDA_ARCHITECTURES=80` 分支。
- CMake SDK 搜索路径只保留 `SDK_DIR`、`DLICC_PATH`、`/zq500/sdk` 和 `/zq500/cuda11`，避免误吸入 `/usr/local/cuda` 或 NVIDIA Toolkit 环境变量。
- CMake 只启用 `LANGUAGES CXX`，`.cu` GPU 源作为 CXX source 交给 `dlcc` 编译。
- 项目 target 改为 `cusignal_zx_gpu`。
- 中科芯库解析保留 `libcurt.so`、`libdlfft.so`、`libdlblas.so`、`libdlsolver.so` 等真实 SDK 库名。
- 项目内部 imported target 命名收敛为 `CUSIGNAL::zx_gpu_*`，避免当前入口继续暴露 `CUDA::...` target。

### B. 源码与公开 API

- GPU 源码目录改为 `src/zhongkexin/`。
- 公开 GPU namespace 改为 `cusignal::zx_gpu_backend`。
- device 类型改为 `ZxGpu*` 命名。
- 任务级 GPU helper 文件改为 `task1_radar_zx_gpu.*`、`task2_features_zx_gpu.*`。
- 平台兼容头改为 `platform_zx_gpu_compat.hpp` 和 `platform_zx_gpu_libraries.hpp`。

### C. 测试与脚本

- `scripts/test/run_all_tests.sh` 默认且唯一接受 `ZHONGKEXIN` 平台。
- `scripts/test/run_all_tests.sh` 移除当前入口的 `--cuda-arch` 和 NVIDIA 构建分支。
- `scripts/test/benchmark_all_ops_scales.py` 默认且唯一接受 `ZHONGKEXIN` 平台。
- `scripts/platform/run_zhongkexin_stage1.sh` 透传 `CUSIGNAL_ZHONGKEXIN_CXX_GPU_FLAGS`，确保 dlcc probe 选出的参数真正进入主工程 CMake。
- `scripts/platform/probe_zhongkexin.sh` 的临时 CMake 变量改为 `ZX_CXX_GPU_FLAGS` / `ZX_GPU_INCLUDE_DIRS`，并去除 `/usr/local/cuda/include` 搜索路径。
- 所有 unit test CMake target 已链接 `cusignal_zx_gpu`。
- smoke 示例已改为 `zx_gpu_backend` 与 `ZxGpu*` 类型。
- Task1/Task2 demo CMake 已删除非 ZHONGKEXIN 分支和 `CUDA_SEPARABLE_COMPILATION` 残留。

### D. 当前入口文档

- README 和 AGENT 已改为中科芯 ZQ500 专用口径。
- README 当前示例使用 `cusignal::zx_gpu_backend`。
- AGENT 明确后续协作只面向 CPU reference + ZQ500 GPU 双链路。

## 风险控制

本阶段属于破坏性 API 重命名，不能只依赖文本替换判断完成。已按以下顺序完成验证：

1. 本地静态检查：
   - `bash -n` 检查 shell 脚本。
   - `python3 -m py_compile` 检查 Python benchmark/plot 脚本。
   - `git diff --check` 检查空白和 patch 格式。
   - `rg` 检查当前入口代码中是否仍有旧 `cuda_backend`、`Cuda*`、`cusignal_cuda`、`src/cuda`。
2. 容器功能复验：
   - 已在本队中科芯容器内执行 Stage4 full after rename。
   - Stage4 full 确认 81 个算子、486 行 benchmark、Task1/Task2 L1-L6 和图件链路仍通过。

## 容器复验命令

同步后进入容器，先执行替换脚本，再运行：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full_after_rename.log
```

## 完成判定

- 当前入口代码不再出现旧项目命名：`cuda_backend`、`Cuda*`、`cusignal_cuda`、`src/cuda`。
- 当前构建和测试脚本不再提供 NVIDIA 执行路径。
- README、AGENT 和 V4.6 交付文档均使用 ZQ500 专用命名。
- 容器 Stage4 full after rename 通过。
- 迁移台账新增 V4.6 重命名记录。

## 关闭证据

- 容器命令：按上节 Stage4 full 命令执行，日志显示 `[zx-stage4] PASS`。
- 取回日志：`stage4_full_after_rename.log`。
- Stage4 summary：`data/reports/zhongkexin/stage4_after_rename_latest/latest_stage4_summary.json`，其中 `pass=true`、`benchmark_rows=486`、`benchmark_failed_rows=0`、`plot_status=passed`。
- benchmark 汇总：`data/reports/unit/benchmarks/zhongkexin_stage4_full_after_rename/latest_report.md`，其中 `operators=81`、`rows=486`、`passed_rows=486`。
- 图件目录：`data/reports/unit/benchmarks/zhongkexin_stage4_full_after_rename/figures`，共 87 个文件。

## 残余约束

- 外部 SDK 兼容符号仍会出现 `cuda*`、`cufft*`、`cublas*`、`cusolver*`。这些不是项目自有 CUDA 命名，不能删除或重命名。
- `.cu` 后缀暂时保留，因为中科芯 `dlcc -x cuda` 当前按该语义编译 GPU 源。
- 历史 V1-V4.5 文档和迁移台账中仍会保留 NVIDIA/CUDA 字样，作为迁移过程证据，不作为当前执行入口。
