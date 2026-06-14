# 中科芯平台迁移计划

## 目标

将当前基于 CUDA 的 CETC 信号处理库迁移到中科芯 CUDA 兼容平台，同时保留现有 NVIDIA CUDA 路径。第一阶段优先保证 `task1_radar_demo` 和 `task2_features_demo` 在中科芯平台完成构建、运行并通过 correctness gate；公开 `cusignal::cpu` 和 `cusignal::cuda_backend` API 不变。

## 构建入口

默认 NVIDIA 构建保持不变：

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=80
cmake --build build --target cusignal_cpu cusignal_cuda --parallel
```

中科芯兼容构建：

```bash
cmake -S . -B build-zx \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CUDA_ARCHITECTURES=80
cmake --build build-zx --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel
```

如果中科芯兼容 FFT/BLAS/SOLVER 库没有暴露标准 CMake CUDA target，可显式传入库路径：

```bash
cmake -S . -B build-zx \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY=/path/to/libcufft_compat.so \
  -DCUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY=/path/to/libcublas_compat.so \
  -DCUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY=/path/to/libcusolver_compat.so
```

## 线程分工

线程 0，集成协调：

- 负责分支纪律、合并顺序和迁移状态更新。
- 在合并中科芯平台改动前冻结 NVIDIA baseline。
- 维护本文档和 `zhongkexin_migration_status.md`。

线程 1，工具链与探测：

- 负责 `CUSIGNAL_PLATFORM=ZHONGKEXIN` 的 CMake 配置。
- 负责 `scripts/platform/probe_zhongkexin.sh`。
- 确认编译器、runtime、event、memory、cuFFT、cuBLAS、cuSOLVER 的兼容情况。

线程 2，核心 runtime：

- 负责 `include/cusignal/core/platform_cuda_compat.hpp`。
- 保持 device container 跨平台可用，不改变类型名。
- 验证 host/device copy、zero-fill、storage cache 和复数 `float2` 打包。

线程 3，重库依赖：

- 负责 FFT/BLAS/SOLVER 兼容，以及重依赖模块：`spectral`、`radartools`、FFT-heavy `filtering`、FFT-heavy `filter_design`。
- fallback 只能限制在 `CUSIGNAL_PLATFORM=ZHONGKEXIN` 下，且必须明确标记。

线程 4，纯 kernel 和轻库模块：

- 负责轻量 CUDA 模块：`waveforms`、`windows`、`bsplines`、`correlate`、`demod`、`peak_finding`、`wavelets`、`estimation` 和非 FFT-heavy `filtering`。
- 修复中科芯编译器兼容问题，但不改变公开 API。

线程 5，demo 与验证：

- 负责 Task1/Task2 在 `build-zx` 下的构建、运行、报告和 correctness gate。
- 先跑 L3 默认规模，再扩展到 L1-L6 sweep。
- 如果平台 event timing 初期不稳定，先把性能指标降为记录项，correctness gate 保持强制。

## 阶段验收

阶段 0，平台探测：

```bash
scripts/platform/probe_zhongkexin.sh
```

阶段 1，构建：

```bash
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel
```

阶段 2，任务级 demo：

```bash
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3
```

阶段 3，聚焦单元测试扩展：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --module waveforms --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module radartools --operator pulse_compression
./scripts/test/run_all_tests.sh --build-dir build-zx --module spectral --operator spectrogram
```

## 硬性约束

- 第一阶段不要重命名 `cuda_backend`。
- 不允许破坏现有 NVIDIA 构建。
- 除非线程 0 记录并批准，否则不要修改公开 API。
- 中科芯 fallback 不得影响 NVIDIA 行为。
- 生成报告继续使用现有 `data/reports` 目录结构。
