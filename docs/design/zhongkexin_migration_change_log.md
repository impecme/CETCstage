# 中科芯平台迁移不兼容与修改台账

## 文档定位

本文档用于记录中科芯平台迁移过程中发现的所有不兼容点、需要修改点、已修改点、暂缓点和 fallback。它是迁移过程的强制台账，不是可选备忘录。

迁移期间不得只把问题记录在聊天记录、终端输出或个人笔记中。凡是影响构建、运行、数值、性能、报告、测试、文档或用户使用方式的差异，都必须进入本文档。

## 记录规则

- 发现中科芯与 NVIDIA CUDA 的不兼容点时，立即新增记录。
- 发现需要修改源码、CMake、脚本、测试、demo、报告或文档时，立即新增记录，即使暂时不修改。
- 实施修改后，必须补充实际修改、影响范围和验证结果。
- 若问题暂缓，必须写明阻塞原因、fallback 范围和计划处理阶段。
- 若确认某问题不需要修改，必须写明原因和验证依据。
- 每个阶段结束前，必须检查本阶段发现项是否全部入账。

## 状态枚举

- `待确认`：现象已发现，尚未完成原因定位。
- `待修改`：已确认需要改动，但尚未实施。
- `修改中`：正在实施改动。
- `待验证`：改动已完成，等待 NVIDIA 或中科芯验证。
- `已关闭`：验证通过，记录完整。
- `暂缓`：暂时不处理，但必须有明确原因和后续阶段。

## 记录模板

| ID | 阶段 | 模块/文件 | 类型 | 现象 | 原因判断 | 计划修改 | 实际修改 | NVIDIA 影响 | 验证命令 | 状态 | 后续处理 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ZX-XXXX | V4.x | 示例 | 编译/链接/运行/数值/性能/文档 | 示例现象 | 示例原因 | 示例计划 | 示例修改 | 无/有，说明范围 | 示例命令 | 待确认 | 示例后续 |

## 当前记录

| ID | 阶段 | 模块/文件 | 类型 | 现象 | 原因判断 | 计划修改 | 实际修改 | NVIDIA 影响 | 验证命令 | 状态 | 后续处理 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| ZX-0001 | V4.1 | 本地环境 | 工具链/容器入口 | 当前 shell 可运行 `dlsmi` 并看到 ZQ500-Q 设备，但未发现 `/zq500/sdk/env.sh`、`nvcc/dlnvcc/dlcc`，且 `cmake` 版本为 `3.16.3`，低于项目要求的 `3.18`；普通用户无 Docker socket 权限，当前 `sudo -n docker exec/inspect` 需要密码 | 当前 shell 能看到中科芯设备，但不是复赛说明要求的完整 SDK 构建环境，不满足 CUDA/CMake 构建前置条件；Codex 当前无法无交互进入本队 docker | 在完整中科芯 docker/SDK 环境内执行 `source /zq500/sdk/env.sh` 后重新探测工具链；当前 shell 只作为硬件可见性和文档/静态检查环境 | 已在 README、AGENT、迁移计划和状态中强调必须进入本队 docker 验证；状态文档已补充当前 shell `dlsmi` 可见但 SDK 缺失、Docker 无交互进入受限 | 无 | `dlsmi`、`cmake --version`、`command -v nvcc`、`test -f /zq500/sdk/env.sh`、`docker ps -a`、`sudo -n docker exec gpu_04 ...`、中科芯 docker 内待执行 `scripts/platform/run_zhongkexin_stage1.sh` | 暂缓 | V4.1 阶段 A 在完整中科芯 docker/SDK 环境内关闭 |
| ZX-0002 | V4.0-V4.5 | `docs/design/V4_*_plan.md`、`docs/design/zhongkexin_migration_status.md` | 文档/流程 | 初版阶段计划有总阶段划分，但 V4.2-V4.5 缺少明确进入条件，后续阶段台账要求不够统一，最终验收命令未显式包含 SDK 初始化和 `dlsmi` 前置 | 文档从第一阶段计划扩展为全项目路线图后，阶段门禁和台账规则需要同步提升为跨阶段硬约束 | 补充 V4.0 阶段门禁；补充 V4.1-V4.5 进入条件、台账要求和完成判定；补充状态文档门禁状态 | 已更新 V4.0、V4.1、V4.2、V4.3、V4.4、V4.5 和迁移状态文档 | 无 | `rg -n "进入条件|阶段门禁|change_log|source /zq500/sdk/env.sh|dlsmi" docs/design/V4_*_plan.md docs/design/zhongkexin_migration_status.md` | 已关闭 | 后续每次阶段计划变化继续新增或更新台账记录 |
| ZX-0003 | V4.1-V4.3 | `复赛说明文件/`、FFT-heavy 算子、cuSOLVER LU 路径、平台 probe | 平台约束 | 复赛说明显示 runtime/driver API 为部分覆盖；cuFFT 点数仅支持 2 的整数次幂，不足需补 0；cuSOLVER `getrf` 的 pivot 参数不支持 `nullptr` | 当前迁移计划需要把复赛说明作为正式平台约束，避免后续引入未支持 API 或遗漏 FFT/SOLVER 限制 | 新增复赛说明摘要；更新 README、AGENT、V4.0、V4.1、V4.2、状态和索引；后续在 V4.1 probe 与 V4.2 依赖矩阵中验证 FFT 长度和 pivot buffer | 已新增 `docs/design/zhongkexin_rematch_notes.md`，并将关键约束写入 README、AGENT、V4 计划和状态文档 | 无 | `rg -n "复赛|2 的整数次幂|pivot|runtime API|driver API|zhongkexin_rematch_notes" README.md AGENT.md docs/design` | 待验证 | 在中科芯 docker 内执行 probe；V4.2 检查 Task1/Task2 FFT-heavy 算子和 cuSOLVER 路径 |
| ZX-0004 | V4.1 | `scripts/platform/probe_zhongkexin.sh` | 测试/探测 | 第一阶段要求验证 zero-fill/device container 基础行为，但 probe 只覆盖了 `cudaMalloc`、`cudaMemcpy`、event、kernel launch、cuFFT、cuBLAS、cuSOLVER，未显式验证 `cudaMemset` zero-fill | `cudaMemset` 是 device container `zero_fill` 的基础 runtime 能力，应在平台探测阶段直接覆盖 | 在 probe runtime 部分增加 `cudaMemset` zero-fill 校验；报告中注明复赛约束覆盖：zero-fill、power-of-two cuFFT、non-null cuSOLVER pivot | 已更新 `scripts/platform/probe_zhongkexin.sh`，新增 `cudaMemset(zero)` 校验和 `rematch_constraints` 报告字段 | 无 | `bash -n scripts/platform/probe_zhongkexin.sh scripts/test/run_task_demos.sh scripts/test/run_all_tests.sh`；完整运行待中科芯 SDK 环境执行 `scripts/platform/probe_zhongkexin.sh` | 待验证 | 在完整中科芯 docker/SDK 环境内运行 probe 后关闭 |
| ZX-0005 | V4.1 | `scripts/platform/probe_zhongkexin.sh`、当前 shell 环境 | 工具链/探测 | 当前 shell 直接运行 probe 会在 CMake 之前失败：缺少 `/zq500/sdk/env.sh`、CMake 只有 `3.16.3`、未找到 CUDA 兼容编译器；但 `dlsmi` 可用 | 需要把环境门禁前置到 probe，否则第一阶段失败会表现为低质量的 CMake 错误，不利于定位和复现 | 在 probe 中新增 preflight：检查 SDK env、`dlsmi`、CMake >= 3.18、CUDA 编译器，并在失败时写 `build-zx-probe/probe_report.md` | 已更新 probe；当前 shell 运行 probe 生成 preflight failed 报告，明确三项缺失和 `dlsmi` 可用 | 无 | `bash -n scripts/platform/probe_zhongkexin.sh`；`scripts/platform/probe_zhongkexin.sh` | 待验证 | 在完整中科芯 docker/SDK 环境内运行 probe，确认 preflight pass 并继续完成 runtime/libs 探测 |
| ZX-0006 | V4.1 | `scripts/platform/run_zhongkexin_stage1.sh` | 测试/验收 | 第一阶段验收命令分散在文档中，进入正确 docker 后仍需手动依次执行 source、dlsmi、probe、CMake configure/build、task demo，容易漏步骤 | V4.1 需要一个可重复的一键验收入口，降低人工执行错误，并保证验收顺序固定 | 新增统一验收脚本，自动 source SDK、检查 `dlsmi`、运行 probe、配置 `build-zx`、构建 V4.1 targets、运行 Task1/Task2 demo | 已新增 `scripts/platform/run_zhongkexin_stage1.sh` 并写入 README、AGENT、V4.1、状态文档；当前 shell 运行按预期因 `/zq500/sdk/env.sh` 缺失而停止 | 无 | `bash -n scripts/platform/run_zhongkexin_stage1.sh scripts/platform/probe_zhongkexin.sh`；`scripts/platform/run_zhongkexin_stage1.sh` | 待验证 | 在完整中科芯 docker/SDK 环境内运行统一验收脚本 |

## 阶段关闭检查

阶段关闭前必须确认：

- 本阶段所有发现项都有 ID。
- 每个 ID 都有明确状态。
- `待修改`、`待验证`、`暂缓` 项均有后续处理阶段。
- 涉及代码或构建修改的记录都说明是否影响 NVIDIA 路径。
- 涉及 correctness、性能或报告的记录都写明验证命令。
