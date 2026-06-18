# cuSignal C++11 V1 README

## 版本信息

- 版本名称：`V1 骨架实现`
- 完成时间：`2026-04-01`
- 创建者：`CICC1001212非诚勿扰`

## 本次实现内容

本次版本完成了赛题附录中 53 个算子的 C++11 接口骨架搭建，并按照 `cpu` 与 `zx_gpu_backend` 两条实现路径分别补齐了空实现。

除接口和实现骨架外，本次对运行入口目录职责做了精简调整，不再保留旧的多层运行入口划分方式，而是统一改为按对象组织：

- `demo/task1_radar/`
- `demo/task2_features/`
- `tests/smoke/`
- `tests/unit/`

其中：

- `demo/` 用于任务级目录框架。
- `tests/smoke/` 用于最小编译与链接验证。
- `tests/unit/` 作为单算子运行与验证目录框架，后续单个 runner 将在一次运行中同时输出演示结果、CPU 对照误差结果和性能统计结果。

## 当前接口组织方式

为了让 CPU 和 CUDA 两套骨架能够同时存在并一起链接，当前版本采用以下命名空间方式：

```cpp
cusignal::cpu::模块名::函数名(...)
cusignal::zx_gpu_backend::模块名::函数名(...)
```

示例：

```cpp
cusignal::cpu::waveforms::chirp(...);
cusignal::zx_gpu_backend::filtering::resample(...);
```

## 已覆盖的赛题模块

- `bsplines`
- `correlate`
- `demod`
- `estimation`
- `filter_design`
- `filtering`
- `peak_finding`
- `radartools`
- `spectral`
- `waveforms`
- `wavelets`
- `windows`

## 目录职责调整说明

本次目录调整的核心原则是减少重叠：

- 不再按“任务入口”和“验证类型”分别建立多套平行目录。
- 单算子和任务入口后续都在各自目录中同时输出演示、误差和性能结果。
- 所有结果文件统一写入 `data/reports/`，通过不同文件名区分用途。

当前阶段完成的是目录框架调整和文档口径统一，不额外补新的 demo 或 unit 实现代码。

## 构建方式

### 方式一：使用一键脚本

```bash
./scripts/build/build_v1.sh
```

如果需要指定构建类型：

```bash
./scripts/build/build_v1.sh Debug
```

### 方式二：手动使用 CMake

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=80
cmake --build build --parallel
```

## 构建产物

- `cusignal_cpu`：CPU 骨架静态库
- `cusignal_zx_gpu`：CUDA 骨架静态库
- `cusignal_smoke`：轻量级编译与链接验证程序

## 后续工作

- 在 `demo/task1_radar/` 下补充任务 1 的流程级运行入口。
- 在 `demo/task2_features/` 下补充任务 2 的流程级运行入口。
- 在 `tests/unit/` 下按模块补充单算子 runner。
- 让任务入口和单算子入口在一次运行中同时输出演示结果、CPU 对照误差结果和性能统计结果，并统一写入 `data/reports/`。
