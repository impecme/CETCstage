# 中科芯平台迁移状态

## 当前基线

- 平台策略：双路径，默认 `NVIDIA`，可选 `ZHONGKEXIN`。
- 公开 API 状态：保持不变。
- 第一阶段主目标：`task1_radar_demo` 和 `task2_features_demo`。
- 当前实现状态：迁移脚手架已加入，目标硬件验证待执行。

## 线程状态

| 线程 | 负责范围 | 状态 | 当前产出 | 下一步检查 |
| --- | --- | --- | --- | --- |
| 0 | 集成和合并纪律 | 已就绪 | 计划/状态文档已创建 | 在真实迁移分支冻结 NVIDIA baseline |
| 1 | 工具链和平台探测 | 已就绪 | `CUSIGNAL_PLATFORM`、探测脚本 | 在中科芯平台运行 `scripts/platform/probe_zhongkexin.sh` |
| 2 | 核心 runtime | 已就绪 | runtime compat 头和 smoke 自检 | 在两个平台构建 `smoke_demo1` |
| 3 | FFT/BLAS/SOLVER | 已就绪 | 库兼容挂点已提供 | 探测 cuFFT/cuBLAS/cuSOLVER |
| 4 | kernel 模块 | 待平台编译 | 保留现有 CUDA 源码 | 使用中科芯编译器编译全部 `.cu` 文件 |
| 5 | demo/test/report | 已就绪 | `run_task_demos.sh` 支持 `build-zx` | 执行 L3 demo 验证 |

## 验证命令

NVIDIA sanity：

```bash
cmake -S . -B build -DCUSIGNAL_PLATFORM=NVIDIA -DCMAKE_BUILD_TYPE=Release
cmake --build build --target smoke_demo1 --parallel
ctest --test-dir build -R '^smoke_demo1$' --output-on-failure
```

中科芯平台探测：

```bash
scripts/platform/probe_zhongkexin.sh
```

中科芯第一阶段验证：

```bash
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3
```

## 未决风险

- 中科芯 SDK 的库名可能不同于标准 CMake CUDA targets。
- cuFFT static link 可能需要额外平台系统库。
- 早期平台镜像上的 event timing 可能比 correctness 更不稳定。
- 模板较重或使用 `thread_local` workspace 的代码可能暴露 CUDA 编译器兼容问题。
- 中科芯平台可能没有 `compute-sanitizer`；如无等价工具，leak check 应记录为 skipped。

## 合并顺序

1. 工具链和 CMake profile。
2. 核心 runtime 兼容层。
3. FFT/BLAS/SOLVER 兼容层。
4. kernel 模块编译修复。
5. demo/test/report 调整。
6. 文档和最终状态更新。
