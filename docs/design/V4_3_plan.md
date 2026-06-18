# V4.3 第三阶段：全量公开算子迁移

## 当前状态

- 状态：已关闭。
- 进入时间：2026-06-17。
- 进入依据：V4.2 已通过 `stage2_full.log` 关闭验证；29/29 Task1/Task2 依赖算子通过，Task1/Task2 L1-L6 sweep、报告和图件均通过。
- 关闭证据：Stage3 v2 active 81 条 accuracy 已通过，模块级 12/12、算子级 81/81。
- 全量矩阵：`docs/design/zhongkexin_full_operator_matrix.md`。

## Summary

- 本阶段从 Task1/Task2 依赖范围扩展到整个 CETC 公开 ZQ500 GPU 算子范围。
- 目标是让中科芯路径覆盖所有公开 API 对应的 ZQ500 GPU 实现，并逐模块通过 smoke、accuracy 和 full 测试。
- 本阶段范围内的全部功能必须闭环：公开 API 对应的 CPU reference、中科芯 GPU 实现、测试数据生成、smoke/accuracy/full、报告输出、失败/跳过项处置都要有证据。

## 进入条件

- V4.2 完整功能闭环已完成。
- Task1/Task2 依赖矩阵完整，两个任务 L1-L6 sweep、报告和图件可复现。
- 仍未关闭的 fallback、跳过项和平台限制均已记录到 `docs/design/zhongkexin_migration_change_log.md`。
- 本阶段验收链路为 CPU reference + 中科芯 GPU；GPU 专指本服务器容器内 ZQ500。

## Scope

覆盖范围包括但不限于：

- `waveforms`
- `windows`
- `bsplines`
- `correlate`
- `demod`
- `filter_design`
- `filtering`
- `peak_finding`
- `radartools`
- `spectral`
- `wavelets`
- `estimation`
- core/device container 相关公共能力
- `scripts/data/` 中各模块测试数据生成链路
- `data/reports` 中单算子 metrics、summary 和 benchmark 输入输出结构

## Key Changes

### 0. 台账与模块推进纪律

- 每个模块开始前，先确认该模块在 `run_all_tests.sh --list` 中的注册状态。
- 每个模块结束后，记录通过的 case-set、失败项、跳过项和下一步处理。
- 所有编译兼容、数值差异、测试阈值调整都必须进入 `docs/design/zhongkexin_migration_change_log.md`。

### 1. 全量模块清单

- 从 `include/cusignal`、`src/zhongkexin`、`tests` 生成公开 API 与 ZQ500 GPU 实现映射。
- 当前已新增 `docs/design/zhongkexin_full_operator_matrix.md`；`run_all_tests.sh` 原 active 53 条已通过，原注释候选 28 条已启用并随 active 81 条完成容器验证。
- 标记每个模块的依赖类型：runtime-only、FFT-heavy、BLAS/SOLVER-heavy、mixed。
- 为每个模块指定最低验证集：smoke、accuracy、edge cases、full。
- 为每个模块指定数据生成入口、报告产物和允许的跳过项处置方式。

### 2. 编译兼容修复

- 逐模块处理中科芯编译器对模板、lambda、`__host__ __device__`、`std::complex`、math intrinsic、`thread_local` 的兼容问题。
- 修复必须尽量局部化，优先使用 compat/helper，不扩大公开接口。
- 每个修复都要确认 CPU reference 与中科芯 GPU 双链路不回退。

### 3. 数值一致性

- 对 CPU/GPU 输出建立模块级容差。
- 对 FFT/BLAS/SOLVER 相关路径记录兼容库差异和可接受误差。
- 对随机输入固定 seed，保证报告可复现。

### 4. 全量测试推进

- 先 smoke，再 accuracy，再 full。
- 一个模块通过后更新状态文档，再进入下一个模块。
- 对不能通过的测试记录失败原因、阻塞条件和临时降级策略。
- 对任何跳过的测试、缺失的数据生成脚本或缺失报告字段都必须入账，不能作为完成项。

## Test Plan

逐模块 smoke：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --module waveforms --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module windows --case-set smoke
./scripts/test/run_all_tests.sh --build-dir build-zx --module filtering --case-set smoke
```

逐模块 accuracy：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --module spectral --case-set accuracy
./scripts/test/run_all_tests.sh --build-dir build-zx --module radartools --case-set accuracy
./scripts/test/run_all_tests.sh --build-dir build-zx --module wavelets --case-set accuracy
```

全量：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --case-set full
```

中科芯 V4.3 accuracy 统一入口：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage3.sh 2>&1 | tee stage3_accuracy.log
```

## 完成判定

- 公开 API 与 ZQ500 GPU 实现映射完整。
- 全量模块 accuracy 已通过，模块级 12/12。
- active 81 条公开算子 accuracy 已通过，算子级 81/81。
- 所有失败项已有明确处置并完成复验。
- 各模块测试数据生成、metrics、summary 和报告字段均可复现；不存在未记录的缺依赖、缺数据或缺报告项。
- CPU reference 与中科芯 GPU 路径均可配置、构建和运行。
- 本阶段发现的所有不兼容点、需要修改点、已修改点和暂缓点均已记录到 `docs/design/zhongkexin_migration_change_log.md`。
- `docs/design/zhongkexin_migration_status.md` 已更新到 V4.3 完成状态。
