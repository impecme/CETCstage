# 中科芯平台迁移状态

## 总体状态

当前迁移的总目标是完成整个 CETC 项目到中科芯 ZQ500 兼容平台的迁移，而不是只跑通 `task1_radar_demo` 和 `task2_features_demo`。截至 2026-06-18，**第一阶段：平台打通与 Task1/Task2 任务级验证**、**第二阶段：Task1/Task2 依赖算子闭环**、**第三阶段：全量公开算子迁移**、**第四阶段：性能、资源与稳定性收敛**和**第五阶段：交付固化**均已按阶段范围内“全部功能迁移”的口径完成。

因此，当前状态表示项目已经形成面向中科芯 ZQ500 的完整交付基线：

- V4.0 全项目迁移总蓝图已建立。
- V4.1 第一阶段已在本队中科芯 docker 内通过统一验收脚本验证。
- V4.2 已在本队中科芯 docker 内通过全规模关闭验证：29/29 依赖算子通过，Task1/Task2 L1-L6 sweep 全部通过，报告和图件已生成。
- V4.3 已在本队中科芯 docker 内通过全量公开算子 accuracy 验证：12/12 模块通过，81/81 active 算子通过，报告已归档。
- V4.4 已在本队中科芯 docker 内通过 Stage4 full：Task1/Task2 L1-L6 12/12 行通过，81 个算子、486/486 行 benchmark 通过，benchmark 图件已生成。
- V4.5 已完成交付固化：README、AGENT、阶段计划、迁移状态、迁移台账和交付文档已收敛到同一 CPU reference + 容器内 ZQ500 GPU 验收口径。
- V4.6 已完成中科芯专用命名收口：项目自有 GPU 目录、target、namespace、device 类型、helper 和当前脚本入口已改为 ZQ500 命名；容器 Stage4 full after rename 已通过。
- V4.7 已完成低风险 CUDA 遗留表述收口：内部 helper、公开头文件注释、README/AGENT 当前说明和技术图脚本文案已改为 ZQ500 GPU 口径；未改中科芯 SDK 兼容符号和报告 schema。
- V4.8 已完成报告 schema 中性化：当前执行链路中的 `cuda_*` 资源字段改为 `gpu_*`，`cudart_version` 改为 `runtime_version`；容器 Stage4 full 复验已通过，当前 JSON/CSV/Markdown 报告未再生成旧报告键。
- 构建入口、compat 层和任务级验证路径已可用。
- 不兼容与修改台账已建立：`docs/migration/zhongkexin/change_log.md`。
- 复赛说明文件已发现并整理摘要：`docs/migration/zhongkexin/platform_notes.md`。
- 宿主机 shell 仍只作为文件中转、静态检查和脚本同步环境；完整验收结论以本队中科芯 docker 内取回的日志为准。
- `numpy/matplotlib/scipy` 已纳入并通过 V4.1 完整功能闭环；stage1 默认要求 demo 可视化依赖存在并生成图件。
- 后续每个阶段都按该阶段范围内的全部功能闭环关闭；报告、图件、数据生成、benchmark、边界输入和文档复现不能因缺依赖或 fallback 被静默跳过。

## 总阶段进度

| 总阶段 | 文档 | 名称 | 当前状态 | 完成标准 |
| --- | --- | --- | --- | --- |
| 第一阶段 | `docs/migration/zhongkexin/plans/V4_1_plan.md` | 平台打通与 Task1/Task2 任务级验证 | 已完成 | probe 通过，`task1_radar_demo` 和 `task2_features_demo` L3 默认规模 `validation.pass=true`，Python 依赖可 import，并生成 demo 可视化图件 |
| 第二阶段 | `docs/migration/zhongkexin/plans/V4_2_plan.md` | Task1/Task2 依赖算子闭环 | 已完成 | 两个任务依赖算子 smoke/accuracy 通过，L1-L6 sweep、报告和任务级图件可复现 |
| 第三阶段 | `docs/migration/zhongkexin/plans/V4_3_plan.md` | 全量公开算子迁移 | 已完成 | 全部 ZQ500 GPU 算子和公开 API 相关测试、数据生成、报告输出逐模块通过或明确入账 |
| 第四阶段 | `docs/migration/zhongkexin/plans/V4_4_plan.md` | 性能、资源与稳定性收敛 | 已完成 | benchmark、resource、timing、性能 gate 和 benchmark 图件稳定可复现 |
| 第五阶段 | `docs/migration/zhongkexin/plans/V4_5_plan.md` | 交付固化 | 已完成 | README、AGENT、迁移报告、回归流程、报告和图件从零完整可复现 |
| 第六阶段 | `docs/migration/zhongkexin/plans/V4_6_plan.md` | 中科芯专用命名收口 | 已完成 | 当前入口、脚本、构建和文档只保留 CPU + 中科芯 ZQ500 双链路；项目自有 CUDA 命名已改为 ZQ500 命名，Stage4 full after rename 已通过 |
| 第七阶段 | `docs/migration/zhongkexin/plans/V4_7_plan.md` | 低风险 CUDA 遗留表述收口 | 已完成 | 内部 helper、公开头文件注释、README/AGENT 和技术图脚本文案改为 ZQ500 GPU 口径；SDK 兼容符号和报告 schema 不变 |
| 第八阶段 | `docs/migration/zhongkexin/plans/V4_8_plan.md` | 报告 schema 中性化 | 已完成 | 当前 demo/report 字段从 `cuda_*` / `cudart_version` 改为 `gpu_*` / `runtime_version`；SDK 兼容 API 不变，容器 Stage4 full 复验已通过 |

## 阶段门禁状态

| 阶段 | 进入条件状态 | 退出条件状态 | 说明 |
| --- | --- | --- | --- |
| V4.1 | 已满足 | 已满足 | `stage1.log` 显示脚本版本 `diagnostics-20260616-dlcc-cxx-python-v3` 已完成依赖准备、probe、`build-zx` 配置、`cusignal_cpu/cusignal_zx_gpu` 和两个 demo 构建；Task1/Task2 L3 均 `PASS repeat=3`，并完成可视化图件生成 |
| V4.2 | 已满足 | 已满足 | `stage2_full.log` 显示脚本版本 `diagnostics-20260616-stage2-deps-v5`，29/29 依赖算子通过，Task1/Task2 L1-L6 全规模 sweep、报告和图件均通过 |
| V4.3 | 已满足 | 已满足 | Stage3 v2 active 81 条 accuracy 已通过；模块级 12/12、算子级 81/81，验收口径为 CPU reference + 中科芯 GPU |
| V4.4 | 已满足 | 已满足 | Stage4 full 已通过：Task1/Task2 L1-L6、81 算子 486/486 benchmark、图件生成均通过 |
| V4.5 | 已满足 | 已满足 | README、AGENT、V4.5 交付文档、迁移状态和台账已完成一致性收敛；2026-06-18 Stage4 full 复验 PASS |
| V4.6 | 已满足 | 已满足 | 已实施项目自有 CUDA 命名到 ZQ500 命名的重构；容器 Stage4 full after rename PASS，81 个算子、486/486 行 benchmark 和图件链路通过 |
| V4.7 | 已满足 | 已满足 | 只清理低风险表述和内部 helper 名；未改算法、构建、SDK ABI/API 或报告 schema |
| V4.8 | 已满足 | 已满足 | 已迁移当前报告 schema；容器 Stage4 full PASS，取回的 JSON/CSV/Markdown 报告未出现旧 `cuda_*` 报告键或 `cudart_version` 字段 |

## 当前基线

- 平台策略：当前迁移验收只面向 `ZHONGKEXIN`；CPU 链路作为 reference，GPU 链路指容器内 ZQ500。
- 公开 API 状态：V4.6 已将公开 GPU namespace 从 `cuda_backend` 改为 `zx_gpu_backend`，device 类型从 `Cuda*` 改为 `ZxGpu*`。
- 当前阶段主目标：V4.8 报告 schema 中性化已关闭；后续若继续清理，只处理项目自有报告/文档命名，不改中科芯 SDK 兼容 API/ABI。
- 当前实现状态：中科芯 stage1 构建、链接、Task1/Task2 L3 验证、Python 依赖检查和可视化图件生成均已通过；V4.2 统一入口和依赖矩阵已完成，Stage2 full 已确认 29 个依赖算子全部通过，Task1/Task2 L1-L6 全规模、报告和图件通过；V4.3 Stage3 v2 active 81 条 accuracy 已通过，模块级 12/12、算子级 81/81；V4.4 Stage4 full 已通过，81 个算子、486/486 行 benchmark 和图件生成通过；V4.5 交付固化已完成；V4.6 重命名后 Stage4 full after rename 已通过；V4.7 未触碰执行链路；V4.8 报告 schema 中性化后 Stage4 full 已通过。
- 参赛者服务器说明：已阅读并纳入 README、AGENT 和迁移计划。
- 复赛说明文件：已阅读 runtime API、driver API、科学计算库实现列表，并纳入 README、AGENT、V4 计划和迁移台账。
- 当前项目记录：用户 ID `usr_04`，UID `1006`，主机名 `supervisor-X7850H0`，项目路径 `/home/usr_04/CETC`。
- 目标验证环境：必须在本队 docker 内执行；统一验收脚本会自动用兼容方式执行 `source /zq500/sdk/env.sh ""`。

## 第一阶段小阶段状态

当前第一阶段已完成。下表保留第一阶段推进记录，并把后续需要扩展的检查转入 V4.2。

| 小阶段 | 负责范围 | 当前状态 | 已有产出 | 下一步检查 |
| --- | --- | --- | --- | --- |
| A | 基线与环境确认 | 已完成 | README/AGENT 已纳入服务器说明和当前用户信息；本队 docker 内依赖准备通过，`cmake 3.22.1`、`dlcc`、SDK headers/libs、FFTW 均满足 | 新环境变化时复查 |
| B | 平台构建入口 | 已完成 | `CUSIGNAL_PLATFORM=ZHONGKEXIN` 路径改为 `dlcc` CXX 编译模型，`.cu` 通过 `-x cuda --cuda-gpu-arch=dlgput64` 编译；`run_zhongkexin_stage1.sh` 统一验收通过 | 后续按 V4.2 增量扩展 |
| C | 核心 runtime 兼容层 | 已完成 | 中科芯 headers/runtime 库解析可用，probe 静态库编译通过 | V4.2 继续覆盖依赖算子 smoke |
| D | FFT/BLAS/SOLVER 重库依赖 | 已完成第一阶段验证 | `dlfft`、`dlblas`、`dlsolver`、`curt`、`dleol` 链接路径已解析，Task1/Task2 demo 已完成链接运行 | V4.2 逐算子验证 FFT 长度、SOLVER pivot 等平台约束 |
| E | 轻量 CUDA 模块 | 已完成第一阶段验证 | `cusignal_zx_gpu` 在中科芯路径完成构建和归档 | V4.2 继续模块级 smoke/accuracy |
| F | Task1/Task2 demo 验收 | 已完成 | `task1_radar` 与 `task2_features` L3 均 `PASS repeat=3`，报告已写出；Python 依赖可 import，Task1/Task2 可视化图件已生成 | V4.2 扩展到 L1-L6 sweep |
| G | 第一阶段外延检查 | 转入 V4.2 | 现有测试、demo 报告和 benchmark 脚本可复用 | 在 V4.2 执行依赖算子 smoke/accuracy 和 L1-L6 sweep |

## 第一阶段完成判定

满足以下条件时，第一阶段才可标记为完成：

- 在中科芯 docker 内完成 SDK 初始化后，`dlsmi` 能看到可用设备。
- `scripts/platform/probe_zhongkexin.sh` 通过，至少覆盖 runtime、kernel launch、event、FFT、BLAS、SOLVER 探测。
- `build-zx` 能完成配置。
- `cusignal_cpu`、`cusignal_zx_gpu`、`task1_radar_demo`、`task2_features_demo` 能完成构建。
- `scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3 --require-visualization-deps` 能运行完成。
- Task1/Task2 默认 L3 规模报告中 `validation.pass=true`。
- Task1/Task2 可视化图件能生成，`numpy/matplotlib/scipy` 均可 import。
- 本阶段发现的所有不兼容点、需要修改点、已修改点和暂缓点均已记录到 `docs/migration/zhongkexin/change_log.md`。

第一阶段已按“全部功能迁移”的口径完成。当前不能解读为“全项目迁移完成”，后续仍需按 V4.2-V4.5 继续关闭全项目范围内的功能。

## V4.1 最新完成证据

- 2026-06-16 取回的 `stage1.log` 开头为 `[zx-stage1] script version: diagnostics-20260616-dlcc-cxx-python-v3`，确认容器内执行的是完整功能闭环版本统一验收脚本。
- 依赖准备完成：`cmake 3.22.1`、`dlcc /zq500/sdk/bin/dlcc`、SDK headers/libs 和 FFTW 均满足；`python modules: already installed`。
- `scripts/platform/probe_zhongkexin.sh` 路径通过，`dlcc` 参数 `-std=c++17 -fPIC -x cuda --cuda-gpu-arch=dlgput64 -I/zq500/sdk/include -I/zq500/cuda11/include` 能产出 ELF relocatable。
- `build-zx` 完成配置，`cusignal_cpu`、`cusignal_zx_gpu`、`task1_radar_demo`、`task2_features_demo` 均完成构建和链接。
- `task1_radar` 通过：`PASS repeat=3 scale_level=L3 invalid_input_checks=true skip_timing_validation=false`。
- `task1_radar` 可视化完成，图件输出到 `data/reports/demo/task1_radar/figures`。
- `task2_features` 通过：`PASS repeat=3 scale_level=L3 invalid_input_checks=true skip_timing_validation=false`。
- `task2_features` 可视化完成，图件输出到 `data/reports/demo/task2_features/figures`。
- 报告已写出：`data/reports/demo/latest_task_demo_report.json` 和 `data/reports/demo/latest_task_demo_report.md`。
- 结论：V4.1 第一阶段完整功能闭环已满足，可进入 V4.2。

## 迁移记录台账

迁移期间必须维护 `docs/migration/zhongkexin/change_log.md`：

- 发现不兼容点必须记录。
- 发现需要修改的地方必须记录。
- 已实施的修改必须补充实际改动、影响范围和验证结果。
- 暂缓项必须写明阻塞原因、fallback 范围和后续处理阶段。
- 每个阶段关闭前必须核对台账，确认没有只存在于聊天记录或终端输出中的问题。

## 验证命令

当前迁移验收只看 CPU reference + 中科芯 ZQ500 GPU 双链路。中科芯平台探测在进入本队 docker 后执行：

```bash
cd /CETC
scripts/platform/probe_zhongkexin.sh
```

当前 shell 的 preflight 结果：

```text
fail: missing /zq500/sdk/env.sh
fail: cmake 3.16.3 is below required 3.18
fail: missing CUDA-compatible compiler
ok: dlsmi is available
```

中科芯第一阶段验证在本队 docker 内执行；2026-06-16 已通过完整功能闭环：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

如果当前在服务器宿主机上，先执行项目同步：

```bash
cd /home/usr_04/CETC
./copy_to_container.sh gpu_04
```

该命令会复制项目到容器中的全新临时目录，并打印容器端替换脚本命令，例如：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

进入容器后先执行打印的 `replace_container_project.sh` 命令，完成 `/CETC` 完全替换。例如：

```bash
/CETC.incoming.20260615124530/replace_container_project.sh /CETC
```

当前已由宿主机成功复制到容器 incoming 目录：

```bash
/CETC.incoming.20260616171638/replace_container_project.sh /CETC
```

然后执行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh
```

统一验收脚本内部会兼容当前 SDK `env.sh` 的 `$1` 读取行为，运行前不需要手动 source。如需覆盖默认值，使用 `BUILD_DIR`、`REPEAT` 等当前脚本支持的环境变量。V4.6 后当前构建入口固定使用中科芯 `dlcc --cuda-gpu-arch=dlgput64`，不再提供 NVIDIA 架构参数入口。

等价展开命令：

```bash
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_zx_gpu task1_radar_demo task2_features_demo --parallel
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3 --require-visualization-deps
```

V4.2 后续建议从以下验证开始：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
```

取回 Stage2 v1 日志后的当前结论：

- `diagnostics-20260616-stage2-deps-v1` 依赖准备通过，说明基础工具、FFTW 和 Python 可视化依赖不再是当前阻塞。
- 29 个依赖算子全部失败和 scale sweep 构建失败同源：CMake 选择 `/usr/bin/c++` 编译中科芯 `.cu` CXX 源，无法识别 `--cuda-gpu-arch=dlgput64`。
- Stage2 v3 已修复 `run_all_tests.sh --platform ZHONGKEXIN` 的 `CMAKE_CXX_COMPILER=dlcc` 传参，并在完整 Stage2 运行前删除旧 `build-zx`，避免复用错误 CMakeCache。
- Stage2 v3 日志显示 CMake 已使用 `/zq500/sdk/bin/dlcc`，但 29 个依赖算子因 `run_*_tests` 未定义而失败；根因判断为 unit support `.cu` 没有编译进 support 静态库。
- Stage2 v3 的 Task1/Task2 `L3` 单规模均通过：Task1 `gpu_ms=2.301120`、Task2 `gpu_ms=102.415000`，scale JSON/Markdown 已写出。
- Stage2 v3 最终还暴露 Task2 scale 图件检查路径不一致：实际输出为 `data/reports/demo/task2_multidomain_l1_l6_scale_performance.png`。
- Stage2 v4 日志显示 27/29 依赖算子通过，unit support `.cu` 已出现编译行；剩余失败为 `spectral/spectrogram` 的 `psd_case`，GPU PSD `max_abs=0.0553979`、`rmse=0.0101726`。
- Stage2 v5 日志显示 29/29 依赖算子通过，Task1/Task2 `L3` 单规模通过，demo 聚合报告和 scale 报告均通过；Task1 `gpu_ms=2.273990`，Task2 `gpu_ms=122.090000`。
- Stage2 full 日志显示 `task demo scales: 1,2,3,4,5,6`，29/29 依赖算子通过，Task1/Task2 L1-L6 全规模均 `PASS`，scale 报告和图件已写出；V4.2 已关闭。

V4.2 全规模关闭证据：

- 2026-06-17 取回 `stage2_full.log`，脚本版本为 `diagnostics-20260616-stage2-deps-v5`。
- 依赖准备通过：`cmake 3.22.1`、`dlcc /zq500/sdk/bin/dlcc`、SDK headers/libs、FFTW 和 Python modules 均满足。
- 依赖算子报告：`pass=true`、`total=29`、`passed=29`、`failed=0`。
- Task1/Task2 L1-L6 scale sweep 全部通过，`data/reports/demo/latest_task_demo_scale_report.md` 中 12 行 validation 均为 `true`。
- 全规模证据已归档到 `data/reports/demo/stage2_full_20260617/` 和 `data/reports/zhongkexin/stage2_runs/20260617_full/`。

V4.3 当前证据：

- 2026-06-17 取回 `stage3_accuracy.log`，脚本版本为 `diagnostics-20260617-stage3-full-ops-v1`。
- 首轮模块级报告：12 个模块中 10 个通过，`filtering` 和 `spectral` 失败。
- 首轮算子级报告：active 53 条中 51 条通过，失败项为 `filtering/wiener` 和 `spectral/csd`。
- 已实施修复：中科芯 `csd` 禁用 R2C 快路径改走 C2C；中科芯 `wiener` 自动噪声估计改为 D2H 标量后继续 GPU apply。
- 复验结果：`spectral/csd` 已通过，`filtering/wiener` 单算子复验已通过，完整 Stage3 汇总已通过，模块级 12/12、算子级 53/53。
- 已继续修复：`wiener_local_stats_kernel` 的无符号倒序窗口遍历改为显式有符号倒序循环；`run_all_tests.sh --platform ZHONGKEXIN` 已自动加载 SDK，单算子入口无需手动 source。
- 当前证据归档：`data/reports/zhongkexin/stage3_runs/20260617_102953/`。
- Stage3 v2 初次证据归档：`data/reports/zhongkexin/stage3_runs/20260617_105517/`，模块级 10/12，算子级 79/81；失败项为 `radartools/mvdr`、`spectral/coherence`。
- Stage3 v2 关闭证据归档：`data/reports/zhongkexin/stage3_runs/20260617_110827/`，模块级 12/12，算子级 81/81，失败项为 0。
- 当前验收口径：CPU reference + 中科芯 GPU；GPU 专指本服务器容器内 ZQ500。
- 结论：V4.3 已关闭；后续进入 V4.4 性能、资源与稳定性收敛。

V4.4 当前证据：

- 2026-06-17 取回 `stage4_pilot.log`，脚本版本为 `diagnostics-20260617-stage4-perf-pilot-v2`。
- Stage4 入口在空 `build-zx` 场景下完成中科芯 CMake configure，编译器为 `/zq500/sdk/bin/dlcc`。
- Task1/Task2 L3 scale sweep 均 `PASS`，demo 报告和图件已生成。
- `waveforms` L3 benchmark 5/5 通过：`chirp`、`gausspulse`、`sawtooth`、`square`、`unit_impulse`。
- benchmark CSV、Markdown、总览 PNG 和 5 个单算子 PNG 已生成。
- 当前证据归档：`data/reports/zhongkexin/stage4_runs/20260617_pilot_v2/`。
- 结论：V4.4 pilot 链路已关闭，后续已完成 L1-L6 与全模块 full benchmark。
- full benchmark 首次展开停在 Task2 L1 timing gate：`gpu_total_ms=37.6259`，旧限制为 `37.5ms`；已按中科芯平台校准 Task2 L1/L2 timing gate，并升级 Stage4 失败日志输出。
- full benchmark 第二次展开已通过 Task1/Task2 L1-L6，operator benchmark 生成 486 行 CSV：401 行通过、85 行失败；失败已归类为 78 行缺 scale mapping 与 7 行中科芯资源规模超限。
- 已补齐 benchmark scale mapping，并为中科芯 `chebwin`、`firwin2` 配置保守规模族；下一步复跑失败算子子集。
- 失败算子子集复验已通过：15 个算子、90 行 benchmark 全部通过，图件生成通过。
- Stage4 full 最终通过：脚本版本 `diagnostics-20260617-stage4-perf-full-v4`，Task1/Task2 L1-L6 12/12 行通过，81 个算子、486/486 行 benchmark 通过，`plot_status=passed`，生成 87 个 benchmark 图件文件。
- 当前证据归档：`data/reports/zhongkexin/stage4_full_latest/` 和 `data/reports/unit/benchmarks/zhongkexin_stage4_full/`。
- 结论：V4.4 已关闭；V4.5 交付固化已完成。

V4.5 关闭证据：

- 2026-06-18，容器内按 README/AGENT 推荐 Stage4 full 命令复验，脚本版本为 `diagnostics-20260617-stage4-perf-full-v4`。
- 依赖准备通过：`cmake 3.22.1`、`dlcc /zq500/sdk/bin/dlcc`、SDK headers/libs、FFTW 和 Python modules 均满足。
- Stage4 summary 显示 `pass=true`、`benchmark_rows=486`、`benchmark_failed_rows=0`、`plot_status=passed`。
- benchmark CSV 统计为 81 个算子、486 行全部通过，图件目录共 87 个文件。
- README、AGENT、V4.5 计划、V4.5 交付文档、迁移状态和迁移台账已收敛到 CPU reference + 容器内 ZQ500 GPU 单一验收口径。
- 结论：V4.5 已关闭；当前项目进入提交材料整理和必要的维护性复验。

V4.6 关闭证据：

- 2026-06-18，容器内同步重命名版本后执行 Stage4 full after rename，脚本版本为 `diagnostics-20260617-stage4-perf-full-v4`。
- CMake configure 使用 `/zq500/sdk/bin/dlcc`，解析中科芯 ZQ500 compatibility headers 和 `libcurt.so`、`libdlfft.so`、`libdlblas.so`、`libdlsolver.so`。
- 取回日志 `stage4_full_after_rename.log` 显示 `[zx-stage4] PASS`。
- 取回 summary `data/reports/zhongkexin/stage4_after_rename_latest/latest_stage4_summary.json` 显示 `pass=true`、`benchmark_rows=486`、`benchmark_failed_rows=0`、`plot_status=passed`。
- 取回 benchmark 报告 `data/reports/unit/benchmarks/zhongkexin_stage4_full_after_rename/latest_report.md` 显示 `operators=81`、`rows=486`、`passed_rows=486`。
- 图件目录 `data/reports/unit/benchmarks/zhongkexin_stage4_full_after_rename/figures` 共 87 个文件。
- 结论：V4.6 已关闭；项目当前交付口径为 CPU reference + 容器内中科芯 ZQ500 GPU。

## 未决风险

- 中科芯 SDK 的库名可能不同于标准 CMake CUDA targets。
- 宿主机 shell 不能代表中科芯 SDK 验收环境；后续维护性复验仍必须以本队 docker 内日志为准。
- 当前普通用户无法直接访问 Docker socket；如需由 Codex 直接执行容器验证，需要先进入本队 docker，或提供一个已具备 SDK 环境的 shell。
- cuFFT static link 可能需要额外平台系统库。
- 复赛科学计算库说明显示 cuFFT 点数仅支持 2 的整数次幂；所有 FFT-heavy 算子需要确认 padding 和裁剪策略。
- 复赛科学计算库说明显示 cuSOLVER LU `devIpiv` 不支持 `nullptr`；所有 getrf 路径需要确认 pivot buffer。
- 复赛 runtime/driver API 为部分覆盖；不得引入未确认支持的 memory pool、stream ordered allocator、external memory、IPC event、NvSci、graph capture 等高级 API。
- 早期平台镜像上的 event timing 可能比 correctness 更不稳定。
- 模板较重或使用 `thread_local` workspace 的代码可能暴露 ZQ500 GPU 编译器兼容问题。
- 中科芯平台可能没有 `compute-sanitizer`；如无等价工具，leak check 应记录为 skipped。
- VPN 每天 `1:00-8:00` 关闭，长时间构建、benchmark 和 scale sweep 需要避开该时段。
- 每次进入 docker 都需要初始化 SDK；当前统一验收脚本内部已用 `source /zq500/sdk/env.sh ""` 处理 `$1` 未绑定问题。
- 服务器宿主机只做文件中转，不应在宿主机直接构建或运行本项目。

## 总体推进顺序

1. 已完成第一阶段：平台打通与 Task1/Task2 任务级验证。
2. 已完成第二阶段：Task1/Task2 依赖算子闭环。
3. 已完成第三阶段：全量公开算子迁移。
4. 已完成第四阶段：性能、资源与稳定性收敛。
5. 当前推进第五阶段：交付固化。
5. 进入第五阶段：交付固化。
