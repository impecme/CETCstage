# cuSignal C++ V2.1 README

## 版本信息

- 版本名称：`V2.1 接口重构`
- 完成时间：`2026-04-03`
- 创建者：`CICC1001212非诚勿扰`

## 版本定位

`V2.1` 的目标不是补齐全部数值算法，而是先把项目的公开接口稳定下来，使后续 CPU 基线实现、CUDA 加速实现、误差分析、性能分析和任务级流程都能在统一 API 上继续推进。

本轮以 Python cuSignal 的公开接口风格为参照，对整个 C++/CUDA 工程进行一次允许破坏旧骨架兼容性的接口收口，重点解决以下问题：

- 统一 `cpu` 与 `cuda_backend` 两条后端路径的公开签名。
- 用张量化 `core` 类型承载 ndarray 风格输入输出。
- 为多返回、分支返回接口补齐具名结果结构与 `std::variant` 建模。
- 为全部公开 API 补齐中文 Doxygen 注释，明确功能、输入、输出、异常和限制。

## 当前工程架构

当前仓库按“公开接口层 + 双后端实现层 + 任务预留目录 + 交付文档”组织，核心结构如下：

```text
project_root/
├─ CMakeLists.txt
├─ README.md
├─ docs/
│  └─ submission/
│     ├─ READMEV1.md
│     └─ READMEV2_1.md
├─ include/
│  ├─ cusignal.hpp
│  └─ cusignal/
│     ├─ core/
│     ├─ bsplines/
│     ├─ correlate/
│     ├─ demod/
│     ├─ estimation/
│     ├─ filter_design/
│     ├─ filtering/
│     ├─ peak_finding/
│     ├─ radartools/
│     ├─ spectral/
│     ├─ waveforms/
│     ├─ wavelets/
│     └─ windows/
├─ src/
│  ├─ cpu/
│  └─ cuda/
├─ demo/
│  ├─ task1_radar/
│  └─ task2_features/
├─ data/
│  ├─ generated/
│  ├─ reference/
│  └─ reports/
└─ deliverables/
```

当前顶层聚合头 `include/cusignal/cusignal.hpp` 已统一包含以下公开模块：

- `core`
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

## 本轮新增与调整内容

### 1. 工程标准升级到 C++17 / CUDA17

项目已统一升级到 `C++17 / CUDA17`。包括：

- `std::variant`：用于建模 `chirp`、`gausspulse`、`ambgfun` 等运行时分支返回。
- 更清晰的结构化返回包装：用于 tuple 风格 API 的具名结构体表达。
- 更自然的张量与参数规格组合：便于把 Python cuSignal 的多态接口迁移到 C++。

当前 CMake 工程名保持为 `cusignal_cpp_v2_1`，构建目标仅保留：

- `cusignal_cpu`
- `cusignal_cuda`

## `core` 类型层的收口

V2.1 不再只依赖一维 `RealSignal` / `ComplexSignal` 风格接口，而是在 `include/cusignal/core/` 中保留并完善张量化公共类型，作为整个 API 对齐的基础。

当前 `core` 层的职责包括：

- 提供 `Tensor<T>` 作为通用 N 维数组承载。
- 提供 `RealArray`、`ComplexArray`、`IndexArray` 等数组别名。
- 保留 `RealSignal`、`ComplexSignal`、`RealMatrix` 等便捷类型，服务自然的一维/二维接口。
- 提供 `WindowSpec`、`PassZeroSpec`、`DetrendSpec` 等参数规格类型，承接 Python cuSignal 的字符串、标量、tuple 等多态输入。
- 提供最小 shape 与数组辅助函数，供 CPU/GPU 占位实现复用。

## 与 Python cuSignal 的对齐情况

### 已对齐的方向

- 按模块重新组织公开头文件，接口命名与上游功能域保持一致。
- Python 的输入多态优先用 C++ 重载表达，而不是继续维持单一骨架签名。
- tuple 风格返回改为具名结果结构体，避免调用端依赖匿名位置语义。
- 运行时分支返回改为 `std::variant`，使返回类型在接口层就可判别。
- `mode`、`method`、`boundary`、`window`、`cut`、`scaling` 等语义参数优先保留字符串接口。
- CPU 与 CUDA 两条实现路径保持同构接口，便于后续做对照实现。

### 当前仍保留的差异

- 本轮只保证接口对齐，不保证数值结果与 Python cuSignal 完全一致。
- Python 侧 `callable` 风格参数当前不支持，仅保留字符串、标量、数组、tuple 等可静态表达形式。
- 某些复杂模块目前仍是“参数校验 + 返回类型/形状正确”的占位实现，真实算法尚未补入。
- 当前还没有恢复任务级 runner、单算子 runner、误差报告和性能报告输出链路。

## 各模块当前状态

### 已完成公开 API 收口的模块

- `waveforms`
- `windows`
- `bsplines`
- `correlate`
- `demod`
- `filter_design`
- `filtering`
- `peak_finding`
- `spectral`
- `radartools`
- `wavelets`
- `estimation`

### 接口层已经完成的内容

- 头文件中的公开 API 已按当前架构统一到 `cpu` / `cuda_backend` 双命名空间。
- 头文件中的公开 API 已补齐详细中文 Doxygen 注释。
- 所有公开声明都已在 `src/cpu/` 和 `src/cuda/` 中提供对应定义。
- 当前源文件已可作为后续真实算法实现的稳定落点。

### 当前尚未完成的内容

- 真实数值算法实现仍未全面补齐。
- 任务 1 / 任务 2 的完整 runner 仍未接入。
- CPU/GPU 误差统计和性能统计流程仍未接入。
- `data/generated/`、`data/reference/`、`data/reports/` 本轮不写入新增结果文件。

## 与赛题任务的关系

当前架构已经能支持后续按任务推进：

- 任务 1“雷达目标检测与多普勒分析”后续主要落在 `waveforms`、`windows`、`correlate`、`spectral`、`radartools`。
- 任务 2“多域特征提取定位”后续主要落在 `filter_design`、`filtering`、`bsplines`、`demod`、`correlate`、`spectral`、`wavelets`、`peak_finding`、`estimation`。

## 构建方式

当前工程不再保留 `smoke` 或 `unit` 测试目标，默认只编译两个静态库：

```bash
cmake -S . -B build
cmake --build build --target cusignal_cpu cusignal_cuda --parallel
```

构建成功后，当前阶段的验收标准：

- `cusignal_cpu` 成功编译
- `cusignal_cuda` 成功编译

## 下一阶段建议

1. 先为任务 1 关键链路补齐真实数值实现，优先形成最短闭环。
2. 再为任务 2 相关模块逐步替换占位实现。
3. 在真实实现稳定后恢复最小 demo 入口。
4. 最后补 CPU/GPU 误差统计、性能统计和 data 落盘链路。

## 结论

`V2.1` 已经把项目从“骨架目录阶段”推进到“接口可冻结阶段”。当前仓库最重要的价值不在于数值结果，而在于：

- 公开 API 已统一
- 模块边界已明确
- 头文件注释已补齐
- CPU/GPU 两套实现入口已稳定
