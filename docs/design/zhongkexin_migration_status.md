# 中科芯平台迁移状态

## 总体状态

当前迁移的总目标是完成整个 CETC 项目到中科芯 CUDA 兼容平台的迁移，而不是只跑通 `task1_radar_demo` 和 `task2_features_demo`。现阶段处于**第一阶段：平台打通与 Task1/Task2 任务级验证**。

因此，当前状态不能解读为“全项目已经迁移完成”。它表示：

- V4.0 全项目迁移总蓝图已建立。
- V4.1 第一阶段实施计划已明确。
- 构建入口、compat 层和任务级验证路径已有基础。
- 不兼容与修改台账已建立：`docs/design/zhongkexin_migration_change_log.md`。
- 复赛说明文件已发现并整理摘要：`docs/design/zhongkexin_rematch_notes.md`。
- 当前 shell 可运行 `dlsmi` 并看到 ZQ500-Q 设备，但缺少 `/zq500/sdk/env.sh`、CUDA 编译器和 CMake >= 3.18；普通用户无 Docker socket 权限，当前 `sudo -n docker exec/inspect` 需要密码，因此还不能作为完整 V4.1 验收环境。
- 真实中科芯 docker/SDK 环境内的 probe、编译、运行和 correctness 验证仍待执行。

## 总阶段进度

| 总阶段 | 文档 | 名称 | 当前状态 | 完成标准 |
| --- | --- | --- | --- | --- |
| 第一阶段 | `docs/design/V4_1_plan.md` | 平台打通与 Task1/Task2 任务级验证 | 进行中 | probe 通过，`task1_radar_demo` 和 `task2_features_demo` L3 默认规模 `validation.pass=true` |
| 第二阶段 | `docs/design/V4_2_plan.md` | Task1/Task2 依赖算子闭环 | 未开始 | 两个任务依赖算子 smoke/accuracy 通过，L1-L6 sweep 可运行 |
| 第三阶段 | `docs/design/V4_3_plan.md` | 全量公开算子迁移 | 未开始 | 全部 CUDA 算子和公开 API 相关测试逐模块通过 |
| 第四阶段 | `docs/design/V4_4_plan.md` | 性能、资源与稳定性收敛 | 未开始 | benchmark、resource、timing 和性能 gate 稳定可复现 |
| 第五阶段 | `docs/design/V4_5_plan.md` | 交付固化 | 未开始 | README、AGENT、迁移报告和回归流程完整可复现 |

## 阶段门禁状态

| 阶段 | 进入条件状态 | 退出条件状态 | 说明 |
| --- | --- | --- | --- |
| V4.1 | 部分满足 | 未满足 | 文档和台账已建立；当前 shell 的 `dlsmi` 可见 ZQ500-Q 设备，但 `/zq500/sdk/env.sh` 缺失，且当前无法无交互进入 docker，probe、build 和 demo 仍待在完整 SDK 环境执行 |
| V4.2 | 未满足 | 未满足 | 需要 V4.1 完成后进入 |
| V4.3 | 未满足 | 未满足 | 需要 V4.2 完成后进入 |
| V4.4 | 未满足 | 未满足 | 需要 V4.3 完成后进入 |
| V4.5 | 未满足 | 未满足 | 需要 V4.4 完成后进入 |

## 当前基线

- 平台策略：双路径，默认 `NVIDIA`，可选 `ZHONGKEXIN`。
- 公开 API 状态：保持不变。
- 当前阶段主目标：第一阶段跑通 `task1_radar_demo` 和 `task2_features_demo`。
- 当前实现状态：迁移脚手架已加入，目标硬件验证待执行。
- 参赛者服务器说明：已阅读并纳入 README、AGENT 和迁移计划。
- 复赛说明文件：已阅读 runtime API、driver API、科学计算库实现列表，并纳入 README、AGENT、V4 计划和迁移台账。
- 当前项目记录：用户 ID `usr_04`，UID `1006`，主机名 `supervisor-X7850H0`，项目路径 `/home/usr_04/CETC`。
- 目标验证环境：必须在本队 docker 内执行，且每次进入容器后先执行 `source /zq500/sdk/env.sh`。

## 第一阶段小阶段状态

当前第一阶段改为一个 Codex 会话内串行推进，不再按多个 Codex 并行会话拆分。每个小阶段完成后更新本表，再进入下一步。

| 小阶段 | 负责范围 | 当前状态 | 已有产出 | 下一步检查 |
| --- | --- | --- | --- | --- |
| A | 基线与环境确认 | 进行中 | README/AGENT 已纳入服务器说明和当前用户信息；当前 shell `dlsmi` 可见 ZQ500-Q 设备 | 在完整中科芯 SDK 环境内确认 `/zq500/sdk/env.sh`、CUDA 编译器、CMake >= 3.18 和库路径 |
| B | 平台构建入口 | 脚手架已就绪，preflight 已验证当前环境不完整，待完整 SDK 环境验证 | `CUSIGNAL_PLATFORM`、`scripts/platform/probe_zhongkexin.sh`、`scripts/platform/run_zhongkexin_stage1.sh`；probe 已补充环境 preflight、`cudaMemset` zero-fill 和复赛约束报告；当前 `build-zx-probe/probe_report.md` 显示 SDK/CMake/CUDA 编译器缺失 | 在完整中科芯 docker/SDK 环境内运行 `scripts/platform/run_zhongkexin_stage1.sh` |
| C | 核心 runtime 兼容层 | 脚手架已就绪，待平台验证 | runtime compat 头、library compat 头、smoke 自检 | 在 NVIDIA 和中科芯 docker 内分别构建运行 `smoke_demo1` |
| D | FFT/BLAS/SOLVER 重库依赖 | 待平台验证 | 库兼容挂点已提供 | 探测 cuFFT/cuBLAS/cuSOLVER 并编译 `spectral`、`radartools` |
| E | 轻量 CUDA 模块 | 待平台编译 | 保留现有 CUDA 源码 | 在中科芯 docker 内逐模块编译 `.cu` 文件 |
| F | Task1/Task2 demo 验收 | 未开始 | `run_task_demos.sh` 支持 `build-zx` | 构建并运行 L3 demo，确认 `validation.pass=true` |
| G | 第一阶段外延检查 | 未开始 | 现有测试和 benchmark 脚本可复用 | 对 Task1/Task2 依赖模块做聚焦 smoke/accuracy，为第二阶段准备 |

## 第一阶段完成判定

满足以下条件时，第一阶段才可标记为完成：

- 在中科芯 docker 内执行 `source /zq500/sdk/env.sh` 后，`dlsmi` 能看到可用设备。
- `scripts/platform/probe_zhongkexin.sh` 通过，至少覆盖 runtime、kernel launch、event、FFT、BLAS、SOLVER 探测。
- `build-zx` 能完成配置。
- `cusignal_cpu`、`cusignal_cuda`、`task1_radar_demo`、`task2_features_demo` 能完成构建。
- `scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3` 能运行完成。
- Task1/Task2 默认 L3 规模报告中 `validation.pass=true`。
- 本阶段发现的所有不兼容点、需要修改点、已修改点和暂缓点均已记录到 `docs/design/zhongkexin_migration_change_log.md`。

第一阶段完成后，状态应改为“第一阶段完成，进入第二阶段 Task1/Task2 依赖算子闭环”，不能直接标记为“全项目迁移完成”。

## 迁移记录台账

迁移期间必须维护 `docs/design/zhongkexin_migration_change_log.md`：

- 发现不兼容点必须记录。
- 发现需要修改的地方必须记录。
- 已实施的修改必须补充实际改动、影响范围和验证结果。
- 暂缓项必须写明阻塞原因、fallback 范围和后续处理阶段。
- 每个阶段关闭前必须核对台账，确认没有只存在于聊天记录或终端输出中的问题。

## 验证命令

NVIDIA sanity：

```bash
cmake -S . -B build -DCUSIGNAL_PLATFORM=NVIDIA -DCMAKE_BUILD_TYPE=Release
cmake --build build --target smoke_demo1 --parallel
ctest --test-dir build -R '^smoke_demo1$' --output-on-failure
```

中科芯平台探测：

```bash
sudo docker exec -it docker_name bash
source /zq500/sdk/env.sh
dlsmi
scripts/platform/probe_zhongkexin.sh
```

当前 shell 的 preflight 结果：

```text
fail: missing /zq500/sdk/env.sh
fail: cmake 3.16.3 is below required 3.18
fail: missing CUDA-compatible compiler
ok: dlsmi is available
```

中科芯第一阶段验证：

```bash
sudo docker exec -it docker_name bash
source /zq500/sdk/env.sh
dlsmi
scripts/platform/run_zhongkexin_stage1.sh
```

等价展开命令：

```bash
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3
```

## 未决风险

- 中科芯 SDK 的库名可能不同于标准 CMake CUDA targets。
- 当前 shell 不能完成 V4.1 验收；必须进入具备 `/zq500/sdk/env.sh`、CMake >= 3.18 和 CUDA 兼容编译器的完整 SDK 环境。
- 当前普通用户无法直接访问 Docker socket；如需由 Codex 继续完成 V4.1，需要先进入本队 docker，或提供一个已具备 SDK 环境的 shell。
- cuFFT static link 可能需要额外平台系统库。
- 复赛科学计算库说明显示 cuFFT 点数仅支持 2 的整数次幂；所有 FFT-heavy 算子需要确认 padding 和裁剪策略。
- 复赛科学计算库说明显示 cuSOLVER LU `devIpiv` 不支持 `nullptr`；所有 getrf 路径需要确认 pivot buffer。
- 复赛 runtime/driver API 为部分覆盖；不得引入未确认支持的 memory pool、stream ordered allocator、external memory、IPC event、NvSci、graph capture 等高级 API。
- 早期平台镜像上的 event timing 可能比 correctness 更不稳定。
- 模板较重或使用 `thread_local` workspace 的代码可能暴露 CUDA 编译器兼容问题。
- 中科芯平台可能没有 `compute-sanitizer`；如无等价工具，leak check 应记录为 skipped。
- VPN 每天 `1:00-8:00` 关闭，长时间构建、benchmark 和 scale sweep 需要避开该时段。
- 每次进入 docker 都必须重新执行 `source /zq500/sdk/env.sh`，否则编译器、库路径或 `dlsmi` 可能不可用。
- 服务器宿主机只做文件中转，不应在宿主机直接构建或运行本项目。

## 总体推进顺序

1. 完成第一阶段：平台打通与 Task1/Task2 任务级验证。
2. 进入第二阶段：Task1/Task2 依赖算子闭环。
3. 进入第三阶段：全量公开算子迁移。
4. 进入第四阶段：性能、资源与稳定性收敛。
5. 进入第五阶段：交付固化。
