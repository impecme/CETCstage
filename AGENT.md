# AGENT.md

本文是给后续编码代理和协作者使用的项目入口说明。它只保留高优先级规则、当前工作流和常用入口；详细操作步骤放在 `docs/` 下的专题文档中。

## 必读入口

- Skill 使用文档：`docs/agent_skills_usage.md`
- 多智能体分工：`docs/performance/v5_0/agent_collaboration.md`
- 平台与容器命令：`docs/platform/zhongkexin_runtime.md`
- 架构、目录、模块与测试入口：`docs/project_structure.md`
- 中科芯迁移硬规则：`docs/migration/zhongkexin/rules.md`
- 中科芯迁移状态：`docs/migration/zhongkexin/README.md` 和 `docs/migration/zhongkexin/status.md`
- 当前 V5.x 性能计划：`docs/performance/v5_0/README.md`

## Agent skills 自动路由

本项目已经安装并接入 `code-review`、`tdd`、`diagnosing-bugs` 和 `improve-codebase-architecture`。用户不需要记忆或显式输入 skill 名称；主智能体根据任务意图自动采用对应方法，并继续遵守本文件及当前阶段计划。

| 任务信号 | 自动采用 | 执行要求 |
| --- | --- | --- |
| 审查改动、提交前检查、确认是否满足阶段计划 | `code-review` | 分开检查项目规范和阶段目标；默认以当前阶段计划为 spec |
| 新功能、修复缺陷、优化单个算子 | `tdd` | 先确认公开测试 seam，按一个测试、一个最小实现的纵向切片推进 |
| 报错、失败、性能回退、显存增长、数值异常 | `diagnosing-bugs` | 先建立快速、确定、可判红的复现命令；没有复现闭环时不猜根因 |
| 大文件拆分、模块边界或长期架构治理 | `improve-codebase-architecture` | 先只生成候选和报告；V5.5 最终验收前不得实施大范围架构重构 |

自动路由不表示每轮都运行全部 skill。一个任务只采用能解决当前问题的最小集合：

```text
正常算子优化：tdd -> code-review
出现失败或回退：diagnosing-bugs -> tdd 回归测试 -> code-review
阶段最终关闭：code-review
最终验收后的架构治理：improve-codebase-architecture
```

多智能体仍沿用 `docs/performance/v5_0/agent_collaboration.md` 中的 Agent A-H 分工。角色决定“谁分析”，skill 决定“用什么方法分析”；辅助智能体默认只读，主智能体统一修改、验证和记录。

## 项目定位

本仓库是 `CETC`，面向第十届集创赛“中科芯”企业命题的中科芯 ZQ500 信号处理加速库。

项目目标是构建一个接近 cuSignal 风格的算子库，当前包含：

- 用于正确性对照的 CPU 参考实现。
- 用于加速的 ZQ500 GPU 实现。
- 面向雷达检测和多域特征定位的任务级 demo。
- 单元测试、smoke 测试、benchmark 脚本、运行报告和提交文档。

实际项目根目录是：

```bash
/home/usr_04/CETC
```

不要把 IDE 当前打开的 Windows SSH 配置文件路径误认为项目根目录。

## 禁止读取的错误 SDK 副本

严禁读取、搜索、索引或同步项目根目录下的错误 SDK 副本：

```bash
/home/usr_04/CETC/zq500_sdk_full
/home/usr_04/CETC/.zq500_sdk_full.delete_me
```

这两个路径是多余且错误的目录，不属于项目输入，也不应作为中科芯 SDK 参考来源。当前因 sudoers 限制，隐藏目录 `.zq500_sdk_full.delete_me` 可能暂时无法删除；后续代理必须忽略它。

需要参考从容器取出的 SDK 示例时，只能使用项目外部目录：

```bash
/home/usr_04/zq500_sdk_full
```

## 构建与验证原则

顶层构建入口是 `CMakeLists.txt`。关键目标包括：

- `cusignal_cpu`
- `cusignal_zx_gpu`
- `task1_radar_demo`
- `task2_features_demo`
- `smoke_demo1`
- `tests/unit` 下的单元测试可执行文件

依赖环境：

- CMake >= 3.18
- C++17
- 中科芯 ZQ500 SDK 与 `dlcc`
- 中科芯 ZQ500 runtime/FFT/BLAS/SOLVER 兼容库
- 安装在 `third_party/fftw/install` 下的 FFTW3

当前交付验收不再以 NVIDIA 路径为阶段关闭条件。验收链路为 CPU reference + 中科芯 GPU，GPU 专指本服务器容器内 ZQ500。

中科芯迁移的所有阶段都按“该阶段范围内的全部项目功能”关闭。不能只以核心 correctness 或单条 demo 通过作为阶段完成；凡属于当前阶段范围的构建、运行、数据生成、数值验证、非法/边界输入、报告字段、可视化图件、benchmark 图件和文档复现都必须实现、验证或作为明确平台限制入账。

缺依赖、缺图件、缺报告或静默跳过项不能作为阶段完成状态保留。

常用入口：

```bash
./scripts/test/run_all_tests.sh --list
./scripts/test/run_all_tests.sh --module spectral
scripts/test/run_task_demos.sh --no-build --repeat 5 --require-visualization-deps
scripts/platform/run_zhongkexin_stage1.sh
scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
```

当前中科芯全量 benchmark 与作图统一使用 Stage4 入口；完整命令见 `docs/platform/zhongkexin_runtime.md`。

每个中科芯迁移版本或阶段关闭时，必须在 `docs/submission/` 下新增或更新对应交付文档，命名采用 `READMEV<major>_<minor>.md` 风格，例如 `docs/submission/READMEV4_1.md`。交付文档必须包含版本目标、核心改动、解决的问题、验证结果、交付产物、完成判定和遗留风险。

## 核心架构约束

公开 API 位于 `include/cusignal`，聚合头文件是：

```cpp
#include "cusignal/cusignal.hpp"
```

主要命名空间：

- `cusignal::cpu::<module>`：CPU host 实现。
- `cusignal::zx_gpu_backend::<module>`：ZQ500 GPU 后端实现。
- `cusignal::core`：共享标量、张量和 device 容器类型。

当前公开 GPU 命名空间为 `zx_gpu_backend`。当前交付路径固定使用 `CUSIGNAL_PLATFORM=ZHONGKEXIN`；兼容差异应集中放在 `include/cusignal/core/platform_zx_gpu_compat.hpp` 或 `include/cusignal/core/platform_zx_gpu_libraries.hpp`。

项目采用统一单精度口径：

- `cusignal::core::Scalar = float`
- `cusignal::core::Complex = std::complex<float>`
- 实数数据语义为 `float32`
- 复数数据语义为 `complex64`

修改算子前先按这个结构理解代码：

- `include/cusignal/<module>/<module>.hpp`：公开 API 声明和结果结构。
- `src/common/<module>_detail.hpp`：共享参数校验、数学公式、shape/axis 逻辑。
- `src/cpu/<module>.cpp`：CPU 参考实现。
- `src/zhongkexin/<module>.cu`：ZQ500 GPU 实现、kernel、workspace 和 ZQ500 兼容库调用。
- `tests/unit/<module>`：单元测试支撑和算子测试入口。
- `data/reference/unit/<module>/<operator>`：静态 manifest、输入和期望输出数据。
- `scripts/data/generate_<module>_data.py`：reference/generated 数据生成脚本。

更完整的模块清单、demo 说明、数据目录和报告约定见 `docs/project_structure.md`。

## 实现约定

尽量沿用现有模式：

- 保持 CPU 和 ZQ500 GPU API 行为一致。
- CPU/ZQ500 GPU 都需要的公式和校验逻辑放到 `src/common/*_detail.hpp`。
- 公开声明放在对应的 `include/cusignal/<module>/<module>.hpp`。
- 除非任务明确要求，否则保持单精度策略。
- 保留近零参考值下的 `mixed_error` 报告口径。
- 优先复用现有 helper 类型和 shape/axis 工具。
- 修复算子时不要引入无关重构。

ZQ500 GPU 代码约定：

- 尽量使用现有 device container 类型。
- 检查 ZQ500 runtime、cuFFT、cuBLAS 和 cuSOLVER 兼容 API 返回值。
- 修改性能敏感路径时保留 thread-local workspace/cache 模式。
- 热路径中避免重复分配，优先扩展已有 workspace。

测试约定：

- 按需新增或更新 `tests/unit/<module>` 下的测试支撑。
- 行为变化时同步更新 reference manifest/data。
- 先跑最窄相关测试；涉及共享行为时再扩大测试范围。

## 中科芯迁移记录硬规则

中科芯迁移期间，发现的不兼容点、需要修改点、已修改点、暂缓点和 fallback，必须记录到 `docs/migration/zhongkexin/change_log.md`。完整字段和执行要求见 `docs/migration/zhongkexin/rules.md`。

至少以下情况必须记录：

- 发现平台、工具链、SDK、runtime、库 target、头文件、链接方式、数值结果、性能或运行行为差异。
- 发现需要修改源码、CMake、脚本、测试、demo、报告或文档的地方。
- 实施了任何中科芯相关修改。
- 引入、保留或删除 fallback。
- 调整 public API、报告字段、测试阈值、性能 gate、验证命令或构建入口。

每个阶段关闭前，必须核对台账，确认没有只存在于聊天记录或终端输出中的问题。更新 `docs/migration/zhongkexin/change_log.md` 后，同步检查 `docs/migration/zhongkexin/status.md` 是否需要更新。

## 项目注意事项

- 有些测试存在 CMake target，但在 `scripts/test/run_all_tests.sh` 的 shell 注册表中被注释掉；判断默认脚本是否会运行某测试时，要同时检查 CMake 和脚本。
- `README.md` 是最高层工程说明；构建、demo、benchmark、validation 出现重大变化时应保持同步。
- `docs` 下包含比赛设计和提交文档；除非任务与文档或交付物相关，否则不要随意修改。
