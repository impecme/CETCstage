# V4.2 中科芯第二阶段交付文档

## 版本信息

- 版本名称：`V4.2 Task1/Task2 依赖算子闭环`
- 完成时间：`2026-06-17`
- 当前状态：已完成
- 对应计划：`docs/design/V4_2_plan.md`
- 依赖矩阵：`docs/design/zhongkexin_task_dependency_matrix.md`
- 状态记录：`docs/design/zhongkexin_migration_status.md`
- 修改台账：`docs/design/zhongkexin_migration_change_log.md`

## 版本目标

V4.2 承接 V4.1，把 Task1/Task2 从“任务级 demo 可运行”推进到“直接依赖算子可解释、可测试、可回归”。本版本的关闭范围包括：

- Task1/Task2 依赖算子 accuracy。
- Task1/Task2 L1-L6 全规模 sweep。
- scale CSV/JSON/Markdown 报告。
- Task1/Task2 可视化图件和 scale 图件。
- 中科芯容器内依赖准备、构建入口、测试入口和报告产物闭环。

本版本完成不代表全项目迁移完成。V4.3 继续扩展到全量公开算子。

## 核心改动

- 新增第二阶段统一入口：`scripts/platform/run_zhongkexin_stage2.sh`。
- 新增 Task1/Task2 依赖算子矩阵：`docs/design/zhongkexin_task_dependency_matrix.md`。
- `scripts/test/run_all_tests.sh` 增加 `--platform NVIDIA|ZHONGKEXIN`，中科芯路径配置时显式传入 `-DCMAKE_CXX_COMPILER=<dlcc>`。
- 顶层 CMake 新增 `cusignal_configure_cuda_source_target`，统一处理 unit test support `.cu` 在 NVIDIA CUDA language 与中科芯 `dlcc -x cuda` CXX 编译模型下的差异。
- 所有 `tests/unit/*/*_test_support.cu` 目标改为复用平台感知 helper，避免中科芯路径 support 静态库缺对象。
- `scripts/test/run_task_demos.sh` 修正 Task2 scale 图件检查路径，按绘图脚本实际输出检查 `data/reports/demo/task2_multidomain_l1_l6_scale_performance.png`。
- `src/cuda/spectral.cu` 在 `CUSIGNAL_PLATFORM_ZHONGKEXIN` 下禁用 spectrogram PSD 的 R2C 快路径，改走已验证通过的 C2C 后处理路径；NVIDIA 默认路径不变。
- Stage2 默认只运行 L3 单规模调试，保留 `STAGE2_SCALES=1,2,3,4,5,6` 作为阶段关闭全规模入口，避免中间调试过度占用中科芯 GPU。
- Stage2 在依赖算子失败时默认跳过 scale sweep，避免前置失败后继续占用 GPU；如需强制运行可设置 `RUN_SCALE_ON_OPERATOR_FAILURE=1`。
- `copy_to_container.sh` 和 `replace_container_project.sh` 增加版本核对与旧日志排除，降低宿主机/容器同步误判风险。

## 解决的问题

- 中科芯 Stage2 入口不再使用 `/usr/bin/c++` 误编译 `.cu` CXX 源，避免 `--cuda-gpu-arch=dlgput64` 被普通 C++ 编译器拒绝。
- unit support `.cu` 已稳定编译进各模块 support 静态库，解决 `run_*_tests(int, char**)` undefined symbol。
- `spectral/spectrogram` PSD accuracy 已通过，避免中科芯 `dlfft` R2C PSD 快路径带来的 reference 偏差。
- Task2 scale 图件检查路径与实际绘图产物一致。
- Task1/Task2 L1-L6 scale 报告和图件均可复现。

## 验证结果

容器内关闭命令：

```bash
cd /CETC
STAGE2_SCALES=1,2,3,4,5,6 scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2_full.log
```

关闭结果：

- 脚本版本：`diagnostics-20260616-stage2-deps-v5`
- 依赖准备：`cmake 3.22.1`、`dlcc /zq500/sdk/bin/dlcc`、SDK headers/libs、FFTW、Python modules 均满足。
- 依赖算子：`29/29` 通过，失败 `0`。
- Task1/Task2 L1-L6 sweep：全部通过，12 行 `validation=true`。
- 报告：CSV/JSON/Markdown 均已生成。
- 图件：Task1/Task2 可视化图件和 L1-L6 scale 图件均已生成。

全规模关键结果：

| task | scale | gpu_ms | cpu_ms | speedup | max_mixed_error |
| --- | --- | ---: | ---: | ---: | ---: |
| task1_radar | L1 | 2.149660 | 1.890680 | 0.880 | 0.000278533 |
| task1_radar | L2 | 2.269280 | 5.100420 | 2.248 | 0.00211334 |
| task1_radar | L3 | 2.274380 | 5.362980 | 2.358 | 0.00248718 |
| task1_radar | L4 | 2.599530 | 15.462900 | 5.948 | 0.0208969 |
| task1_radar | L5 | 3.916170 | 34.183100 | 8.729 | 0.0544498 |
| task1_radar | L6 | 7.370410 | 82.197000 | 11.152 | 0.335136 |
| task2_features | L1 | 30.124100 | 122.021000 | 4.051 | 0.00393563 |
| task2_features | L2 | 62.493000 | 413.167000 | 6.611 | 0.00523943 |
| task2_features | L3 | 102.655000 | 909.636000 | 8.861 | 0.0031292 |
| task2_features | L4 | 162.932000 | 2368.090000 | 14.534 | 0.00308792 |
| task2_features | L5 | 251.587000 | 4033.720000 | 16.033 | 0.00206816 |
| task2_features | L6 | 388.660000 | 9487.570000 | 24.411 | 0.000853242 |

## 交付产物

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| 全规模日志 | `stage2_full.log` | V4.2 关闭日志 |
| 依赖算子报告 | `data/reports/zhongkexin/stage2_runs/20260617_full/` | 29 个依赖算子 accuracy 汇总和单算子日志 |
| 全规模 scale 证据 | `data/reports/demo/stage2_full_20260617/` | L1-L6 scale 报告和关键图件归档 |
| 当前 scale 报告 | `data/reports/demo/latest_task_demo_scale_report.md` | 最新 Task1/Task2 L1-L6 表格 |
| Task1 scale 图件 | `data/reports/demo/task1_radar/task1_l1_l6_scale_performance.*` | Task1 L1-L6 图件 |
| Task2 scale 图件 | `data/reports/demo/task2_multidomain_l1_l6_scale_performance.*` | Task2 L1-L6 图件 |

## 本地校验

宿主机完成的静态校验：

```bash
bash -n copy_to_container.sh replace_container_project.sh scripts/platform/prepare_zhongkexin_deps.sh scripts/platform/run_zhongkexin_stage1.sh scripts/platform/run_zhongkexin_stage2.sh scripts/test/run_all_tests.sh scripts/test/run_task_demos.sh
git diff --check -- CMakeLists.txt tests/unit scripts/test/run_all_tests.sh scripts/platform/run_zhongkexin_stage2.sh docs/design/zhongkexin_task_dependency_matrix.md docs/design/V4_2_plan.md docs/design/zhongkexin_migration_status.md docs/design/zhongkexin_migration_change_log.md README.md AGENT.md copy_to_container.sh replace_container_project.sh
scripts/test/run_all_tests.sh --platform ZHONGKEXIN --module radartools --operator pulse_compression --case-set accuracy --list
```

## 完成判定

V4.2 已满足关闭条件：

- 依赖矩阵内算子 accuracy 通过：`29/29`。
- Task1/Task2 L1-L6 sweep 通过。
- scale CSV/JSON/Markdown 和 Task1/Task2 图件已生成。
- Stage2 期间出现的构建、链接、算子 accuracy、scale 图件问题均已入账并关闭。
- `docs/design/zhongkexin_migration_status.md` 和 `docs/design/zhongkexin_migration_change_log.md` 已根据关闭证据更新。

## 遗留风险

- 中科芯 spectrogram PSD 当前使用 C2C 路径保证 correctness；R2C PSD 快路径性能优化留到 V4.4 评估。
- V4.2 覆盖 Task1/Task2 直接依赖范围，不覆盖全量公开算子；V4.3 已新增 `docs/design/zhongkexin_full_operator_matrix.md` 和 `scripts/platform/run_zhongkexin_stage3.sh` 继续推进。
- 后续仍需确认 NVIDIA 默认路径的构建 sanity，避免中科芯兼容改动影响默认平台。

## 下一步

进入 V4.3：全量公开算子迁移。下一步在容器内同步最新项目后运行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage3.sh 2>&1 | tee stage3_accuracy.log
```
