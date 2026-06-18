# V4.2 第二阶段：Task1/Task2 依赖算子闭环

## 当前状态

- 状态：已完成。
- 关闭时间：2026-06-17。
- 关闭证据：`stage2_full.log` 显示 `diagnostics-20260616-stage2-deps-v5` 通过；29/29 依赖算子 accuracy 通过；Task1/Task2 L1-L6 全规模 sweep 全部通过；报告和图件已生成。
- 证据归档：`data/reports/zhongkexin/stage2_runs/20260617_full/`、`data/reports/demo/stage2_full_20260617/`。
- 后续阶段：进入 `docs/design/V4_3_plan.md`，推进全量公开算子迁移。

## Summary

- 本阶段承接第一阶段，目标是把 Task1/Task2 直接依赖的算子从“demo 能跑”推进到“依赖算子可解释、可测试、可回归”。
- 本阶段仍不要求全项目所有算子完成迁移，但要求两个任务链路涉及的核心模块具备 smoke、accuracy 和 scale sweep 证据。
- 调试期间默认只运行一个任务规模，避免中科芯 GPU 调试耗时过长；一个规模跑通后再打开 L1-L6 全规模 sweep。
- 本阶段范围内的全部功能必须闭环：Task1/Task2 依赖算子的构建、运行、accuracy、边界输入、L1-L6 sweep、报告字段和任务级图件都不能因缺依赖或 fallback 被静默跳过。单规模调试通过不等于 V4.2 阶段关闭。

## 进入条件

- V4.1 完整功能闭环已完成。
- `scripts/platform/probe_zhongkexin.sh` 已在中科芯 docker 内通过，或所有失败项已记录到 `docs/design/zhongkexin_migration_change_log.md` 并有明确处置。
- `task1_radar_demo` 和 `task2_features_demo` 在 L3 默认规模下 `validation.pass=true`，且 demo 可视化图件已生成。
- V4.1 发现的不兼容点、修改点、fallback 和暂缓项均已入账。

## Scope

重点模块：

- Task1：`radartools`、`spectral`、FFT-heavy `filtering`、FFT-heavy `filter_design`、必要 `windows`。
- Task2：`waveforms`、`filter_design`、`filtering`、`bsplines`、`correlate`、`demod`、`spectral`、`wavelets`、`peak_finding`、`estimation`。
- 共享基础：device container、runtime compat、FFT/BLAS/SOLVER compat、报告输出。
- Python 数据生成、任务级可视化和 scale benchmark 图件。

## Key Changes

### 0. 台账与状态同步

- 本阶段发现的所有不兼容点和待修改点必须记录到 `docs/design/zhongkexin_migration_change_log.md`。
- 每完成一个依赖算子或一轮 scale sweep，更新 `docs/design/zhongkexin_migration_status.md`。
- 对仍保留的 fallback，必须记录影响任务、影响算子、NVIDIA 是否受影响和计划清理阶段。

### 1. 依赖清单冻结

- 从 `demo/task1_radar` 和 `demo/task2_features` 反向整理算子调用链。
- 建立 Task1/Task2 依赖矩阵，记录 CPU 路径、ZQ500 GPU 路径、中科芯路径的覆盖状态。
- 对每个算子记录输入规模、容差、报告字段和现有测试入口。

### 2. 算子级 smoke 与 accuracy

- 为 Task1/Task2 依赖算子补齐小规模 smoke。
- 对 FFT-heavy 路径优先验证 C2C、R2C、batched FFT、plan cache 行为。
- 对 FFT-heavy 路径增加 2 的整数次幂约束检查：记录原始输入长度、实际 FFT 长度、是否补 0、输出裁剪方式和误差影响。
- 对 cuSOLVER LU 路径检查 pivot buffer，确认没有 `nullptr` pivot。
- 对轻量 kernel 路径优先验证边界输入、空输入、异常输入和 CPU/GPU 误差。

### 3. 单规模调试与 L1-L6 sweep

- 在第一阶段 L3 默认规模通过后，先运行 L3 单规模 sweep，确认构建、报告和图件链路可用。
- 单规模通过后，运行 L1-L6 sweep。
- 记录每个规模的 `validation.pass`、`mixed_error`、stage timings、resource usage 和图件产物。
- 如果 event timing 不稳定，保留 correctness 强制，性能指标继续作为记录项。
- scale sweep 结束后必须生成 `latest_task_demo_scale_report.*` 和 Task1/Task2 L1-L6 图件。

### 4. fallback 清理

- 检查第一阶段临时 fallback。
- 对可替换 fallback 改为真实中科芯兼容实现。
- 对暂时保留的 fallback 标记原因、影响范围、替换条件和风险。

## Test Plan

统一入口：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
```

该脚本会按 `docs/design/zhongkexin_task_dependency_matrix.md` 执行依赖算子 `accuracy`，生成 `data/reports/zhongkexin/stage2/latest_dependency_operator_report.*`。为降低中科芯 GPU 调试耗时，当前默认只执行 Task1/Task2 L3 单规模 sweep 并强制检查可视化图件；单规模通过后再通过 `STAGE2_SCALES=1,2,3,4,5,6` 执行全规模 sweep。

Task1 依赖算子：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --module radartools --operator pulse_compression
./scripts/test/run_all_tests.sh --build-dir build-zx --module radartools --operator pulse_doppler
./scripts/test/run_all_tests.sh --build-dir build-zx --module spectral --operator spectrogram
```

Task2 依赖算子：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --module waveforms --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module correlate --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module demod --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module wavelets --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module peak_finding --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module estimation --case-set smoke
```

任务级 sweep：

```bash
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --scale-sweep --scales 3 --repeat 3 --require-visualization-deps
```

全规模关闭验证：

```bash
STAGE2_SCALES=1,2,3,4,5,6 scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2_full.log
```

## 完成判定

- Task1/Task2 依赖矩阵完整。
- 两个任务依赖的核心算子 smoke/accuracy 通过，边界输入和非法输入检查有结果。
- 默认 L3 单规模 sweep 可运行，且全规模关闭验证中 L1-L6 sweep 可运行。
- Task1/Task2 scale 报告、CSV、JSON、Markdown 和 L1-L6 图件均已生成。
- Python 数据生成/可视化依赖已纳入容器准备流程，无静默跳过项。
- fallback 清单已更新，NVIDIA 路径行为不受影响。
- 本阶段发现的所有不兼容点、需要修改点、已修改点和暂缓点均已记录到 `docs/design/zhongkexin_migration_change_log.md`。
- `docs/design/zhongkexin_migration_status.md` 已更新到 V4.2 完成或明确阻塞状态。
