# V4.1 中科芯第一阶段迁移交付文档

## 版本信息

- 版本名称：`V4.1 平台打通与 Task1/Task2 任务级验证`
- 完成时间：`2026-06-16`
- 验证平台：中科芯 ZQ500-Q docker 环境
- 项目路径：`/CETC`
- 对应计划：`docs/migration/zhongkexin/plans/V4_1_plan.md`
- 状态记录：`docs/migration/zhongkexin/status.md`
- 修改台账：`docs/migration/zhongkexin/change_log.md`

## 阶段目标

本阶段目标是打通 CETC 项目在中科芯 ZQ500 兼容平台上的第一条完整任务级链路。完成范围包括平台探测、构建入口、核心库构建、Task1/Task2 默认规模运行、报告输出、Python 依赖检查和可视化图件生成。

本阶段完成不代表全项目迁移完成。后续仍需按 V4.2-V4.5 继续关闭依赖算子、全量公开算子、性能稳定性和最终交付复现。

## 本轮关键修改

- 新增并固化 `CUSIGNAL_PLATFORM=ZHONGKEXIN` 平台构建路径。
- 中科芯路径改用 SDK 官方示例式 `dlcc` CXX 编译模型，`.cu` 源通过 `-x cuda --cuda-gpu-arch=dlgput64` 编译。
- 增加 `scripts/platform/run_zhongkexin_stage1.sh` 统一验收入口，脚本版本为 `diagnostics-20260616-dlcc-cxx-python-v3`。
- 增加 `scripts/platform/prepare_zhongkexin_deps.sh`，用于检查 CMake、dlcc、SDK headers/libs、FFTW 和 Python 可视化依赖。
- 将 `numpy/matplotlib/scipy` 纳入完整功能验收，Task1/Task2 可视化不再作为可长期跳过项。
- 更新 `scripts/test/run_task_demos.sh`，在 `--require-visualization-deps` 模式下强制检查 Python 依赖和 `figures` 产物。
- 中科芯路径显式解析 `curt`、`dlfft`、`dlblas`、`dlsolver/cusolver`、`dleol` 等 SDK 库。
- 移除/规避不适配中科芯平台的 CUDA CMake language、自检、NVIDIA `sm_*` 架构参数和 CUB/Thrust 依赖路径。
- 调整 Task1/Task2 中科芯 L3 timing gate，使第一阶段以实测平台性能作为记录与验收口径。
- 同步更新 README、AGENT、V4 计划、迁移状态和迁移台账。

## 验证命令

容器内执行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage1.sh 2>&1 | tee stage1.log
```

统一脚本内部执行以下核心步骤：

```bash
scripts/platform/prepare_zhongkexin_deps.sh --ensure-fftw --install-python
scripts/platform/probe_zhongkexin.sh
cmake -S . -B build-zx -DCUSIGNAL_PLATFORM=ZHONGKEXIN -DCMAKE_BUILD_TYPE=Release
cmake --build build-zx --target cusignal_cpu cusignal_zx_gpu task1_radar_demo task2_features_demo --parallel
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 3 --require-visualization-deps
```

宿主机静态检查：

```bash
bash -n copy_to_container.sh replace_container_project.sh scripts/platform/prepare_zhongkexin_deps.sh scripts/platform/run_zhongkexin_stage1.sh scripts/test/run_task_demos.sh
git diff --check -- docs/migration/zhongkexin/status.md docs/migration/zhongkexin/change_log.md
```

## 验证结果

取回的 `stage1.log` 关键结果如下：

- `[zx-stage1] script version: diagnostics-20260616-dlcc-cxx-python-v3`
- `python modules: already installed`
- `dlcc` probe 产出 `ELF 64-bit LSB relocatable`
- `Built target zx_probe`
- `Built target cusignal_cpu`
- `Built target cusignal_zx_gpu`
- `Built target task1_radar_demo`
- `Built target task2_features_demo`
- `[task1_radar] PASS repeat=3 scale_level=L3 invalid_input_checks=true skip_timing_validation=false`
- `[task1_radar] visualization complete`
- `[task2_features] PASS repeat=3 scale_level=L3 invalid_input_checks=true skip_timing_validation=false`
- `[task2_features] visualization complete`
- `[task-demos] wrote data/reports/demo/latest_task_demo_report.json`
- `[task-demos] wrote data/reports/demo/latest_task_demo_report.md`

## 交付产物

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| 第一阶段完整日志 | `stage1.log` | 中科芯容器内统一验收日志 |
| 汇总 JSON 报告 | `data/reports/demo/latest_task_demo_report.json` | Task1/Task2 默认规模验证汇总 |
| 汇总 Markdown 报告 | `data/reports/demo/latest_task_demo_report.md` | 可读版任务验证报告 |
| Task1 metrics | `data/reports/demo/task1_radar/latest_metrics.json` | Task1 correctness、timing、资源和稳定性指标 |
| Task1 阶段耗时 | `data/reports/demo/task1_radar/latest_stage_timings.csv` | Task1 CPU/GPU 分阶段耗时 |
| Task1 图件 | `data/reports/demo/task1_radar/figures/` | Task1 可视化 PNG 和 README |
| Task2 metrics | `data/reports/demo/task2_features/latest_metrics.json` | Task2 correctness、timing、资源和稳定性指标 |
| Task2 阶段耗时 | `data/reports/demo/task2_features/latest_stage_timings.csv` | Task2 CPU/GPU 分阶段耗时 |
| Task2 图件 | `data/reports/demo/task2_features/figures/` | Task2 可视化 PNG 和 README |
| 迁移状态 | `docs/migration/zhongkexin/status.md` | V4.1 已完成，V4.2 进入条件已满足 |
| 迁移台账 | `docs/migration/zhongkexin/change_log.md` | V4.1 修改、验证和遗留项记录 |

## 完成判定

V4.1 第一阶段已满足以下完成条件：

- 中科芯 docker 内依赖准备通过。
- 平台 probe 通过，最小 ZQ500 GPU 编译产物为 ELF relocatable。
- `build-zx` 配置完成。
- `cusignal_cpu`、`cusignal_zx_gpu`、`task1_radar_demo`、`task2_features_demo` 构建完成。
- Task1/Task2 L3 默认规模均通过 `PASS repeat=3`。
- `numpy/matplotlib/scipy` 可 import。
- Task1/Task2 可视化脚本执行完成并生成 `figures`。
- 汇总 JSON/Markdown 报告写出。
- 本阶段不兼容点、修改点和验证结果已写入迁移台账。

结论：V4.1 第一阶段完整功能闭环已完成，可以进入 V4.2 Task1/Task2 依赖算子闭环。

## 遗留风险与后续工作

- V4.2 需要扩展到 Task1/Task2 依赖算子 smoke/accuracy 和 L1-L6 sweep。
- FFT-heavy 路径仍需按复赛说明确认 2 的整数次幂 padding 与裁剪策略。
- cuSOLVER LU 路径仍需逐项确认 pivot buffer 不传 `nullptr`。
- V4.3 以后需要覆盖全量公开 API、全量 ZQ500 GPU 算子、数据生成和报告输出。
- V4.4 需要恢复更完整的 benchmark、资源、timing 和性能稳定性验收。
- V4.5 需要完成从零复现、最终提交文档和交付物整理。

