# V4.2 第二阶段：Task1/Task2 依赖算子闭环

## Summary

- 本阶段承接第一阶段，目标是把 Task1/Task2 直接依赖的算子从“demo 能跑”推进到“依赖算子可解释、可测试、可回归”。
- 本阶段仍不要求全项目所有算子完成迁移，但要求两个任务链路涉及的核心模块具备 smoke、accuracy 和 scale sweep 证据。

## 进入条件

- V4.1 已完成。
- `scripts/platform/probe_zhongkexin.sh` 已在中科芯 docker 内通过，或所有失败项已记录到 `docs/design/zhongkexin_migration_change_log.md` 并有明确处置。
- `task1_radar_demo` 和 `task2_features_demo` 在 L3 默认规模下 `validation.pass=true`。
- V4.1 发现的不兼容点、修改点、fallback 和暂缓项均已入账。

## Scope

重点模块：

- Task1：`radartools`、`spectral`、FFT-heavy `filtering`、FFT-heavy `filter_design`、必要 `windows`。
- Task2：`waveforms`、`filter_design`、`filtering`、`bsplines`、`correlate`、`demod`、`spectral`、`wavelets`、`peak_finding`、`estimation`。
- 共享基础：device container、runtime compat、FFT/BLAS/SOLVER compat、报告输出。

## Key Changes

### 0. 台账与状态同步

- 本阶段发现的所有不兼容点和待修改点必须记录到 `docs/design/zhongkexin_migration_change_log.md`。
- 每完成一个依赖算子或一轮 scale sweep，更新 `docs/design/zhongkexin_migration_status.md`。
- 对仍保留的 fallback，必须记录影响任务、影响算子、NVIDIA 是否受影响和计划清理阶段。

### 1. 依赖清单冻结

- 从 `demo/task1_radar` 和 `demo/task2_features` 反向整理算子调用链。
- 建立 Task1/Task2 依赖矩阵，记录 CPU 路径、CUDA 路径、中科芯路径的覆盖状态。
- 对每个算子记录输入规模、容差、报告字段和现有测试入口。

### 2. 算子级 smoke 与 accuracy

- 为 Task1/Task2 依赖算子补齐小规模 smoke。
- 对 FFT-heavy 路径优先验证 C2C、R2C、batched FFT、plan cache 行为。
- 对 FFT-heavy 路径增加 2 的整数次幂约束检查：记录原始输入长度、实际 FFT 长度、是否补 0、输出裁剪方式和误差影响。
- 对 cuSOLVER LU 路径检查 pivot buffer，确认没有 `nullptr` pivot。
- 对轻量 kernel 路径优先验证边界输入、空输入、异常输入和 CPU/GPU 误差。

### 3. L1-L6 sweep

- 在第一阶段 L3 默认规模通过后，运行 L1-L6 sweep。
- 记录每个规模的 `validation.pass`、`mixed_error`、stage timings 和 resource usage。
- 如果 event timing 不稳定，保留 correctness 强制，性能指标继续作为记录项。

### 4. fallback 清理

- 检查第一阶段临时 fallback。
- 对可替换 fallback 改为真实中科芯兼容实现。
- 对暂时保留的 fallback 标记原因、影响范围、替换条件和风险。

## Test Plan

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
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --scale-sweep --repeat 3
```

## 完成判定

- Task1/Task2 依赖矩阵完整。
- 两个任务依赖的核心算子 smoke/accuracy 通过。
- L1-L6 sweep 可运行，默认规模继续 `validation.pass=true`。
- fallback 清单已更新，NVIDIA 路径行为不受影响。
- 本阶段发现的所有不兼容点、需要修改点、已修改点和暂缓点均已记录到 `docs/design/zhongkexin_migration_change_log.md`。
- `docs/design/zhongkexin_migration_status.md` 已更新到 V4.2 完成或明确阻塞状态。
