# V4.0 中科芯平台全项目迁移总蓝图

## Summary

- 总目标是将当前基于 NVIDIA CUDA 的 CETC 信号处理库完整迁移到中科芯 CUDA 兼容平台，同时保留现有 NVIDIA CUDA 路径。
- 完整迁移成功不等于只跑通 `task1_radar_demo` 和 `task2_features_demo`；最终需要覆盖公开 API、核心算子、任务 demo、单元测试、性能报告和交付文档。
- 公开 `cusignal::cpu` 与 `cusignal::cuda_backend` API 保持兼容，用户代码不应修改 include、namespace 或公开函数名。
- 平台差异集中收敛到构建入口、platform compat 层、runtime/FFT/BLAS/SOLVER 封装和验证脚本。
- 迁移按单会话、分阶段方式推进。当前优先执行第一阶段，后续阶段必须在前一阶段验收通过后继续。

## 完整迁移成功判定

- 默认 `NVIDIA` 构建继续可用。
- `ZHONGKEXIN` 构建可独立配置、编译和运行。
- 中科芯路径通过 Task1/Task2 demo correctness gate。
- 中科芯路径逐步通过全量单算子 smoke、accuracy 和必要 perf 测试。
- runtime、FFT、BLAS、SOLVER、event timing、device memory 等平台差异均通过内部 compat 层收敛。
- `data/reports` 报告结构保持稳定。
- README、AGENT、迁移状态、平台操作说明和回归命令能够支撑新环境复现。

## 总阶段划分

| 总阶段 | 文档 | 名称 | 目标 | 完成判定 |
| --- | --- | --- | --- | --- |
| 第一阶段 | `docs/design/V4_1_plan.md` | 平台打通与 Task1/Task2 任务级验证 | 建立中科芯构建入口、探测脚本和 compat 骨架，优先跑通两个任务 demo | probe 通过，两个 demo 在 L3 默认规模 `validation.pass=true` |
| 第二阶段 | `docs/design/V4_2_plan.md` | Task1/Task2 依赖算子闭环 | 对两个任务直接依赖的 runtime、FFT-heavy、轻量 kernel 模块做针对性修复和小规模 accuracy 验证 | 两个任务依赖算子 smoke/accuracy 通过，L1-L6 sweep 可运行 |
| 第三阶段 | `docs/design/V4_3_plan.md` | 全量公开算子迁移 | 从任务依赖扩展到项目全部 CUDA 算子和公开 API 覆盖面 | `run_all_tests.sh` 按模块逐步通过 smoke、accuracy、full |
| 第四阶段 | `docs/design/V4_4_plan.md` | 性能、资源与稳定性收敛 | 对齐报告字段，恢复性能阈值，补齐 resource/timing/benchmark 稳定性 | benchmark 和报告长期可复现，性能 gate 从记录项恢复为验收项 |
| 第五阶段 | `docs/design/V4_5_plan.md` | 交付固化 | 固化 README、AGENT、迁移报告、平台说明和回归流程 | 新环境可按文档从零配置、构建、验证和复现报告 |

## 阶段门禁

迁移阶段按顺序推进。除非用户明确要求临时插队处理阻塞项，否则不得跳过前一阶段的完成判定。

| 阶段 | 进入条件 | 退出条件 |
| --- | --- | --- |
| V4.1 | 已进入中科芯 docker，或已明确本机只能做文档/静态准备 | probe、构建、Task1/Task2 L3 correctness 通过，台账完整 |
| V4.2 | V4.1 完成，两个 demo 默认规模可运行 | Task1/Task2 依赖矩阵完整，依赖算子 smoke/accuracy 通过，L1-L6 sweep 可运行 |
| V4.3 | V4.2 完成，任务依赖路径稳定 | 全量公开 CUDA 算子映射完整，模块级 smoke/accuracy/full 推进完成或有明确处置 |
| V4.4 | V4.3 完成，correctness 基本稳定 | timing/resource/benchmark 可复现，性能 gate 恢复或有明确平台豁免 |
| V4.5 | V4.4 完成，功能和性能验收口径稳定 | 新环境可按文档复现完整构建、测试和报告 |

## 执行环境前置条件

中科芯平台迁移验证必须按参赛者服务器链路执行：

```text
Windows VPN -> SSH 登录服务器 -> 进入本队 docker -> 初始化 SDK 环境 -> 构建和验证
```

关键约束：

- 当前项目记录的用户 ID 为 `usr_04`，UID 为 `1006`，当前主机名为 `supervisor-X7850H0`，项目路径为 `/home/usr_04/CETC`。
- VPN、服务器账号和 docker 均按参赛队分配，账号密码不得写入仓库。
- VPN 客户端当前仅支持 Windows，每天 `1:00-8:00` 关闭，迁移验证应避开该时段并及时保存代码。
- 服务器宿主机只作为文件中转和 docker 入口；项目代码应放在个人用户目录 `/home/usr_04`。
- 代码编译、运行和调试必须在本队 docker 内完成。
- 每次进入 docker 后都要执行 `source /zq500/sdk/env.sh`。
- 使用 `dlsmi` 确认 docker 已绑定可用 GPU。
- SDK 示例位于 `/zq500/sdk/samples/`，兼容头文件可参考 `/zq500/cuda11/include`。
- 复赛说明文件位于 `复赛说明文件/`，摘要见 `docs/design/zhongkexin_rematch_notes.md`。

## 总体技术策略

- 构建入口：使用 `CUSIGNAL_PLATFORM=NVIDIA|ZHONGKEXIN` 区分平台，默认仍为 `NVIDIA`。
- 公开 API：保留 `cuda_backend` 命名，不新增用户侧平台 namespace。
- runtime：通过 `include/cusignal/core/platform_cuda_compat.hpp` 收敛错误检查、内存 API、device query 和 event timing。
- 库依赖：通过 FFT/BLAS/SOLVER compat 入口收敛 cuFFT、cuBLAS、cuSOLVER 差异。
- fallback：只允许在 `CUSIGNAL_PLATFORM=ZHONGKEXIN` 下启用，并且必须标记原因、范围和后续替换计划。
- 验证策略：先任务级 correctness，再依赖算子 accuracy，再全量单测，最后恢复性能 gate。

## 复赛平台约束

- CUDA runtime 和 driver API 均为部分覆盖；迁移中不得引入复赛说明未确认支持的高级 API。
- V4.1/V4.2 不主动把 runtime 路径改成 driver API 路径；如必须使用 driver API，需要先新增 probe 并入账。
- cuFFT 点数仅支持 2 的整数次幂，不足需要补 0；所有 FFT-heavy 算子都必须检查 FFT 长度、padding、输出裁剪和误差影响。
- cuFFT 不支持双精度执行路径；当前项目单精度策略与此约束一致。
- cuSOLVER `getrf` 的 pivot 参数不能传入 `nullptr`，LU 路径必须分配 pivot buffer。
- 当前主迁移路径不依赖 cuDNN、cuSPARSE、cuRAND；如后续引入，必须先对照复赛说明文件并新增台账记录。

## 迁移记录硬规则

迁移过程中发现的所有不兼容点、需要修改点、已修改点和暂缓点，都必须记录到 `docs/design/zhongkexin_migration_change_log.md`。不得只依赖聊天记录、终端输出或个人记忆。

必须记录的内容包括：

- 中科芯平台与 NVIDIA CUDA 行为、编译器、runtime、库 target、头文件、链接方式、数值结果或工具链的差异。
- 为适配中科芯平台而需要修改的源码、CMake、脚本、测试、demo、报告或文档。
- 已经实施的修改、影响范围、是否影响 NVIDIA 路径、验证命令和验证结果。
- 暂时没有修改的兼容问题、阻塞原因、fallback 范围、后续处理阶段。
- 任何 public API、报告字段、测试阈值、性能 gate 或 fallback 策略的变化。

每次完成一个迁移小步骤后，必须同步更新：

- `docs/design/zhongkexin_migration_change_log.md`
- `docs/design/zhongkexin_migration_status.md`
- 当前阶段计划文件中对应的完成状态或风险说明

## 总体验收命令

第一阶段最低验收：

```bash
source /zq500/sdk/env.sh
dlsmi
scripts/platform/probe_zhongkexin.sh
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3
```

最终全项目验收：

```bash
source /zq500/sdk/env.sh
dlsmi
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --parallel
./scripts/test/run_all_tests.sh --build-dir build-zx --case-set full
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --scale-sweep --repeat 3
```

NVIDIA 回归验收：

```bash
cmake -S . -B build -DCUSIGNAL_PLATFORM=NVIDIA -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

## 硬性约束

- 全部阶段都不要重命名 `cuda_backend`。
- 不允许破坏现有 NVIDIA 构建。
- 不要修改公开 API；确需修改时必须记录原因、影响范围和兼容策略。
- 中科芯 fallback 不得影响 NVIDIA 行为。
- 发现不兼容点必须记录，发现需要修改的地方也必须记录，即使暂时不修。
- 生成报告继续使用现有 `data/reports` 目录结构。
- 中科芯验证命令必须在本队 docker 内执行，且每次进入容器后先执行 `source /zq500/sdk/env.sh`。
