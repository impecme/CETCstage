# V4.1 第一阶段：平台打通与 Task1/Task2 任务级验证

## Summary

- 本阶段是全项目中科芯迁移的第一阶段，不代表整个项目完全迁移成功。
- 目标是证明中科芯平台路径可以被配置、编译、运行，并且 `task1_radar_demo`、`task2_features_demo` 的默认规模 correctness 能通过。
- 本阶段关闭前必须完成本阶段范围内的全部功能闭环：构建、Task1/Task2 L3 correctness、Python 依赖、报告输出和 demo 可视化图件都要可复现。
- 本阶段完成后，状态应更新为“第一阶段完整功能闭环完成，进入第二阶段 Task1/Task2 依赖算子闭环”。

## 进入条件

- 已确认当前操作是在本队中科芯 docker 内，或已明确当前只能做文档、静态检查和本地准备。
- 已阅读参赛者服务器使用说明，并确认统一验收脚本会自动以兼容方式执行 `source /zq500/sdk/env.sh ""`。
- 已阅读 `复赛说明文件/` 中的 runtime API、driver API 和科学计算库支持清单，或已阅读摘要 `docs/design/zhongkexin_rematch_notes.md`。
- 已确认当前迁移按单会话串行推进，不使用多个 Codex 对话窗口并行修改公共入口。
- 已建立 `docs/design/zhongkexin_migration_change_log.md`，后续发现项必须入账。

## Scope

本阶段覆盖：

- 中科芯 docker 环境确认。
- `CUSIGNAL_PLATFORM=ZHONGKEXIN` 构建入口。
- 平台探测脚本。
- runtime 和库 compat 骨架。
- Task1/Task2 demo 构建、运行、报告验证和可视化图件生成。
- Task1/Task2 直接依赖模块的最小 smoke/accuracy 外延检查。

本阶段不要求：

- 全部 80+ operator 一次性通过。
- 全量 benchmark 完成；但本阶段范围内的 demo 可视化和报告不能跳过。
- 性能 gate 达到最终阈值。
- 重命名或重构公开 API。

## Key Changes

### 0. 迁移记录台账

- 发现中科芯与 NVIDIA CUDA 不兼容时，立即记录到 `docs/design/zhongkexin_migration_change_log.md`。
- 发现需要修改源码、CMake、脚本、测试、demo、报告或文档时，即使暂时不改，也必须先记录。
- 每条记录至少包含：编号、发现阶段、模块/文件、现象、原因判断、计划修改、实际修改、NVIDIA 影响、验证命令、当前状态。
- 小阶段完成前，必须确认本阶段新增的不兼容点和待修改项已经入账。

### 1. 环境确认

- 确认当前 NVIDIA 路径仍可作为对照基线。
- 确认中科芯服务器链路、docker、SDK 初始化和 `dlsmi` 可用。
- 记录当前用户、路径、SDK 环境、CMake/ZQ500 GPU 编译器和库探测结果。
- 更新 `docs/design/zhongkexin_migration_status.md`。

### 2. 平台构建入口

- 维护 `CUSIGNAL_PLATFORM=NVIDIA|ZHONGKEXIN` 构建入口。
- 维护 `scripts/platform/probe_zhongkexin.sh`。
- probe 需要在配置 CMake 前执行环境 preflight，检查 `/zq500/sdk/env.sh`、`dlsmi`、CMake >= 3.18 和 ZQ500 兼容编译器。
- 确认 `build-zx` 能配置到至少生成构建系统。
- 若中科芯库 target 名称不同，使用 `CUSIGNAL_ZHONGKEXIN_*_LIBRARY` 显式传入。
- probe 必须覆盖复赛说明中当前项目直接依赖的 runtime、event、memory、cuFFT、cuBLAS、cuSOLVER 最小路径。

### 3. 核心 runtime 兼容层

- 维护 `include/cusignal/core/platform_zx_gpu_compat.hpp`。
- 保持 `ZxGpuRealSignal`、`ZxGpuComplexSignal`、`ZxGpuRealArray`、`ZxGpuComplexArray` 等公开类型名不变。
- 验证 host/device copy、zero-fill、storage cache 和复数 `float2` 打包。
- 用 `smoke_demo1` 作为最小验证入口。

### 4. 重库依赖适配

- 维护 FFT/BLAS/SOLVER 兼容入口。
- 优先验证 `spectral`、`radartools`、FFT-heavy `filtering`、FFT-heavy `filter_design`。
- 所有 FFT-heavy 路径必须检查 FFT 点数是否为 2 的整数次幂；非 2 的整数次幂输入必须显式补 0，并记录裁剪和误差影响。
- 所有 cuSOLVER LU 路径必须分配 pivot buffer，不得传入 `nullptr`。
- fallback 只能限制在 `CUSIGNAL_PLATFORM=ZHONGKEXIN` 下，且必须明确标记。
- 优先保证 Task1 依赖的 pulse compression、pulse doppler、CFAR、ambgfun 路径。

### 5. 轻量 CUDA 模块适配

- 逐步验证 `waveforms`、`windows`、`bsplines`、`correlate`、`demod`、`peak_finding`、`wavelets`、`estimation` 和非 FFT-heavy `filtering`。
- 处理 `__host__ __device__`、`thread_local`、math intrinsic、模板等可能的编译器兼容问题。
- 每次只处理一组模块，先跑 smoke/accuracy 小规模测试，再更新状态文档。

### 6. 任务级 demo 验收

- 构建 `task1_radar_demo` 和 `task2_features_demo`。
- 先跑 L3 默认规模并要求 `validation.pass=true`。
- L3 通过后再运行 L1-L6 scale sweep。
- 如果平台 event timing 初期不稳定，先把性能指标降为记录项，correctness gate 保持强制。

## Test Plan

容器内统一入口：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

如果当前在服务器宿主机上，先把项目完整复制进容器。该脚本会复制到容器中的全新 incoming 目录，并在终端打印容器端替换命令：

```bash
cd /home/usr_04/CETC
./copy_to_container.sh gpu_04
```

进入容器后，先执行上一步打印的命令，例如：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

该命令会删除旧 `/CETC` 并移动 incoming 目录成为新的 `/CETC`，因此宿主机已删除的文件也会从容器项目中消失。替换完成后执行统一入口：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

统一入口会自动初始化 SDK、运行 probe、配置 `build-zx`、构建目标并运行 Task1/Task2 demo。当前中科芯路径默认使用 `CUDA_ARCH=OFF`，不要手动设置 `CUDA_ARCH=80`，否则 CMake 可能生成 NVIDIA 专用的 `sm_80` 参数。

平台探测：

```bash
scripts/platform/probe_zhongkexin.sh
```

构建：

```bash
set +u
source /zq500/sdk/env.sh ""
set -u
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_zx_gpu task1_radar_demo task2_features_demo --parallel
```

任务级 demo：

```bash
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3 --require-visualization-deps
```

聚焦单元测试外延：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --module waveforms --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module radartools --operator pulse_compression
./scripts/test/run_all_tests.sh --build-dir build-zx --module spectral --operator spectrogram
```

## 完成判定

- 在中科芯 docker 内完成 SDK 初始化后，`dlsmi` 能看到可用设备。
- `scripts/platform/probe_zhongkexin.sh` 通过，至少覆盖 runtime、kernel launch、event、FFT、BLAS、SOLVER 探测。
- `build-zx` 能完成配置。
- `cusignal_cpu`、`cusignal_zx_gpu`、`task1_radar_demo`、`task2_features_demo` 能完成构建。
- `scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3 --require-visualization-deps` 能运行完成。
- Task1/Task2 默认 L3 规模报告中 `validation.pass=true`。
- `numpy/matplotlib/scipy` 均可 import，Task1/Task2 的 `figures/*.png` 和 `figures/README.md` 已生成。
- 本阶段发现的所有不兼容点、需要修改点、已修改点和暂缓点均已记录到 `docs/design/zhongkexin_migration_change_log.md`。
