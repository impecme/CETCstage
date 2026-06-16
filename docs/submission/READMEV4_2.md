# V4.2 中科芯第二阶段入口交付文档

## 版本信息

- 版本名称：`V4.2 Task1/Task2 依赖算子闭环入口`
- 完成时间：`2026-06-16`
- 当前状态：Stage2 v5 单规模调试已通过；29/29 依赖算子通过，Task1/Task2 L3 scale 通过，下一步执行 L1-L6 全规模闭环
- 对应计划：`docs/design/V4_2_plan.md`
- 依赖矩阵：`docs/design/zhongkexin_task_dependency_matrix.md`
- 状态记录：`docs/design/zhongkexin_migration_status.md`
- 修改台账：`docs/design/zhongkexin_migration_change_log.md`

## 阶段目标

V4.2 承接 V4.1，目标是把 Task1/Task2 直接依赖的算子从“任务 demo 能跑”推进到“依赖算子可解释、可测试、可回归”。本阶段需要覆盖依赖算子 accuracy、Task1/Task2 L1-L6 sweep、报告字段和可视化图件。

本交付文档记录 V4.2 的入口建设和容器日志修复。V4.2 尚未关闭，关闭条件仍以容器内 `stage2.log` 和 `data/reports/zhongkexin/stage2/` 报告为准。

## 本轮新增

- 新增第二阶段统一入口：`scripts/platform/run_zhongkexin_stage2.sh`。
- 新增依赖算子矩阵：`docs/design/zhongkexin_task_dependency_matrix.md`。
- `run_all_tests.sh` 增加 `--platform NVIDIA|ZHONGKEXIN`，中科芯路径配置时传入 `-DCUSIGNAL_PLATFORM=ZHONGKEXIN`，且不传 NVIDIA `CMAKE_CUDA_ARCHITECTURES`。
- 顶层 CMake 新增 `cusignal_configure_cuda_source_target`，统一处理 unit test support `.cu` 在 NVIDIA 与中科芯路径下的差异。
- 所有 `tests/unit/*/*_test_support.cu` 目标改为复用平台感知 helper。
- `replace_container_project.sh` 替换后会打印 stage1 和 stage2 脚本版本。
- `copy_to_container.sh` 排除旧 `stage2.log`，避免旧日志污染新一轮判断。
- README、AGENT、V4.2 计划、迁移状态和迁移台账已同步第二阶段入口。

## 第一轮容器验证

已从容器取回：

- `stage2.log`
- `data/reports/zhongkexin/stage2/latest_dependency_operator_report.*`
- `data/reports/zhongkexin/stage2/operators/*.log`

Stage2 v1 日志显示：

- 脚本版本：`diagnostics-20260616-stage2-deps-v1`
- 依赖准备通过：`cmake 3.22.1`、`dlcc /zq500/sdk/bin/dlcc`、SDK headers/libs、FFTW 和 Python modules 均满足。
- 29 个依赖算子全部失败，L1-L6 scale sweep 未完成。
- 首个失败日志显示 CMake 选择 `/usr/bin/c++` 作为 CXX 编译器，随后 `.cu` 源按 CXX 规则编译时收到 `--cuda-gpu-arch=dlgput64`，报 `c++: error: unrecognized command-line option`。

本轮判断：这是统一构建入口未强制中科芯 CXX 编译器导致的共性失败，不是 29 个独立 accuracy 失败。

## 第二轮容器验证

Stage2 v3 日志显示：

- 脚本版本：`diagnostics-20260616-stage2-deps-v3`
- scale 调试规模：`task demo scales: 3`
- CMake 已选择 `/zq500/sdk/bin/dlcc`，`/usr/bin/c++` 误编译问题已关闭。
- 29 个依赖算子仍失败，但失败共性变为 unit support 静态库缺少 `run_*_tests` 符号，例如 `undefined symbol: run_pulse_compression_tests(int, char**)`。
- Task1/Task2 L3 单规模均通过，并写出 `latest_task_demo_scale_report.*`。
- Stage2 最终失败在 scale 图件检查路径：绘图脚本写出 `data/reports/demo/task2_multidomain_l1_l6_scale_performance.png`，检查脚本误查 `data/reports/demo/task2_features/task2_multidomain_l1_l6_scale_performance.png`。

## 第三轮容器验证

Stage2 v4 日志显示：

- 脚本版本：`diagnostics-20260616-stage2-deps-v4`
- 依赖算子结果：`27/29` 通过。
- unit support `.cu` 已开始正常编译，例如日志中出现 `Building CXX object tests/unit/radartools/.../radartools_test_support.cu.o`，`run_*_tests` 链接缺符号问题已关闭。
- 失败项只剩 `spectral/spectrogram`，Task1/Task2 两条矩阵记录对应同一个测试目标。
- `complex_case` 通过，`psd_case` 失败；CPU 对 reference 误差约 `1e-8`，GPU PSD 对 reference `max_abs=0.0553979`、`rmse=0.0101726`。
- Stage2 v4 因依赖算子失败按策略跳过 L3 scale sweep，避免继续占用 GPU。

## 第四轮容器验证

Stage2 v5 日志显示：

- 脚本版本：`diagnostics-20260616-stage2-deps-v5`
- 依赖算子结果：`29/29` 通过。
- `spectral/spectrogram` 已通过，确认中科芯路径禁用 R2C PSD 快路径后 correctness 闭环。
- Task1/Task2 `L3` 单规模 scale sweep 通过。
- Task1 `L3`：`gpu_ms=2.273990`、`cpu_ms=5.373260`、`speedup=2.363`、`max_mixed_error=0.00248718`。
- Task2 `L3`：`gpu_ms=122.090000`、`cpu_ms=895.219000`、`speedup=7.332`、`max_mixed_error=0.0031292`。
- demo 聚合报告通过，Task1/Task2 可视化图件生成，scale 图件检查通过。
- 宿主机已归档 L3 证据到 `data/reports/demo/stage2_l3_20260616/`。

## 本轮修复

- `scripts/test/run_all_tests.sh --platform ZHONGKEXIN` 配置 CMake 时显式传入 `-DCMAKE_CXX_COMPILER=<dlcc>`。
- 支持通过 `ZHONGKEXIN_CXX_COMPILER` 覆盖编译器；未设置时自动查找 `dlcc`。
- `scripts/platform/run_zhongkexin_stage2.sh` 版本升级为 `diagnostics-20260616-stage2-deps-v5`。
- Stage2 v5 在依赖准备后删除实际 `build-zx` 目录，避免旧 CMakeCache 继续使用 `/usr/bin/c++`。
- Stage2 v5 默认只运行 Task1/Task2 `L3` 一个规模的 scale 报告链路，降低中科芯 GPU 调试耗时；单规模已通过，下一步用 `STAGE2_SCALES=1,2,3,4,5,6` 打开全规模。
- Stage2 v5 在依赖算子失败时默认跳过 scale sweep，避免前置失败后继续占用 GPU；如需强制运行，设置 `RUN_SCALE_ON_OPERATOR_FAILURE=1`。
- 顶层 CMake helper 已在 target 创建后重新标记该 target 的 `.cu` 源为 CXX，避免 unit support 库成为空库。
- `run_task_demos.sh` 已按绘图脚本实际输出路径检查 Task2 scale 图件。
- 中科芯路径已禁用 spectrogram PSD 的 R2C 快路径，改走已验证通过的 C2C spectrogram 后处理路径；NVIDIA 默认路径不变。

## 统一执行命令

容器内执行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
```

脚本默认行为：

- 检查基础依赖、FFTW 和 Python 可视化依赖。
- 批量运行 Task1/Task2 依赖算子 `accuracy`。
- 为每个算子生成独立日志。
- 写出 `data/reports/zhongkexin/stage2/latest_dependency_operator_report.csv/json/md`。
- 默认运行 Task1/Task2 `L3` 单规模 scale sweep。
- 强制检查 Task1/Task2 单规模 sweep 报告和可视化图件。
- 阶段关闭前用 `STAGE2_SCALES=1,2,3,4,5,6` 运行 Task1/Task2 L1-L6 全规模 sweep。

## 预期输出

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| stage2 日志 | `stage2.log` | 第二阶段统一入口完整日志 |
| 算子汇总 CSV | `data/reports/zhongkexin/stage2/latest_dependency_operator_report.csv` | 依赖算子状态表 |
| 算子汇总 JSON | `data/reports/zhongkexin/stage2/latest_dependency_operator_report.json` | 机器可读汇总 |
| 算子汇总 Markdown | `data/reports/zhongkexin/stage2/latest_dependency_operator_report.md` | 可读汇总 |
| 单算子日志 | `data/reports/zhongkexin/stage2/operators/*.log` | 每个依赖算子的构建/运行日志 |
| 任务级 sweep CSV | `data/reports/demo/latest_task_demo_scale_benchmark.csv` | 调试默认 L3；阶段关闭前 L1-L6 |
| 任务级 sweep JSON | `data/reports/demo/latest_task_demo_scale_report.json` | 调试默认 L3；阶段关闭前 L1-L6 |
| 任务级 sweep Markdown | `data/reports/demo/latest_task_demo_scale_report.md` | 调试默认 L3；阶段关闭前 L1-L6 |
| Task1 sweep 图件 | `data/reports/demo/task1_radar/task1_l1_l6_scale_performance.*` | 调试默认 L3；阶段关闭前 L1-L6 图件 |
| Task2 sweep 图件 | `data/reports/demo/task2_multidomain_l1_l6_scale_performance.*` | 调试默认 L3；阶段关闭前 L1-L6 图件 |

## 本地校验结果

已完成以下宿主机静态校验：

```bash
bash -n copy_to_container.sh replace_container_project.sh scripts/platform/prepare_zhongkexin_deps.sh scripts/platform/run_zhongkexin_stage1.sh scripts/platform/run_zhongkexin_stage2.sh scripts/test/run_all_tests.sh scripts/test/run_task_demos.sh
git diff --check -- CMakeLists.txt tests/unit scripts/test/run_all_tests.sh scripts/platform/run_zhongkexin_stage2.sh docs/design/zhongkexin_task_dependency_matrix.md docs/design/V4_2_plan.md docs/design/zhongkexin_migration_status.md docs/design/zhongkexin_migration_change_log.md README.md AGENT.md copy_to_container.sh replace_container_project.sh
scripts/test/run_all_tests.sh --platform ZHONGKEXIN --module radartools --operator pulse_compression --case-set accuracy --list
```

同时已批量确认 `scripts/platform/run_zhongkexin_stage2.sh` 中的依赖算子条目均能被 `scripts/test/run_all_tests.sh --list` 命中。

## 完成判定

本轮完成的是 V4.2 入口建设，不是 V4.2 阶段关闭。V4.2 关闭仍需满足：

- 依赖矩阵内算子 accuracy 通过或失败项全部入账。
- Task1/Task2 L1-L6 sweep 通过。
- scale CSV/JSON/Markdown 和 Task1/Task2 图件生成。
- 失败项按构建失败、算子 accuracy 失败、scale sweep 失败分类处理。
- `docs/design/zhongkexin_migration_status.md` 和 `docs/design/zhongkexin_migration_change_log.md` 根据容器日志更新。

## 下一步

当前单规模已通过。下一步直接在容器内执行全规模闭环：

```bash
cd /CETC
STAGE2_SCALES=1,2,3,4,5,6 scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2_full.log
```

取回 `stage2_full.log` 后，优先查看：

- `[zx-stage2] script version`
- `[zx-stage2] task demo scales`
- 首个算子日志中的 `The CXX compiler identification` 和 `cxx compiler`
- `data/reports/zhongkexin/stage2/latest_dependency_operator_report.md`
- `data/reports/zhongkexin/stage2/operators/*.log`
- `data/reports/demo/latest_task_demo_scale_report.md`
