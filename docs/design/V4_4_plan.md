# V4.4 第四阶段：性能、资源与稳定性收敛

## Summary

- 本阶段在 correctness 和全量算子迁移基本稳定后进行。
- 目标是让中科芯路径的性能、资源采样、event timing、报告和 benchmark 能长期稳定复现。
- 第一阶段中被降级为记录项的性能 gate，应在本阶段恢复为正式验收项。

## 进入条件

- V4.3 已完成。
- 全量公开算子至少完成 smoke 覆盖，关键模块完成 accuracy 覆盖。
- correctness 失败项已关闭，或已作为平台限制/暂缓项记录。
- 当前报告字段结构已经稳定，后续只允许做兼容扩展。

## Scope

覆盖范围：

- Task1/Task2 stage timings。
- CPU/GPU correctness 与 `mixed_error` 报告。
- resource usage。
- benchmark 输出。
- 长时间运行稳定性。
- 不同规模 L1-L6 sweep。

## Key Changes

### 0. 台账与性能口径

- 所有性能阈值变化、resource 字段变化、timing 口径变化都必须记录到 `docs/design/zhongkexin_migration_change_log.md`。
- 中科芯性能 baseline 必须独立记录，不直接套用 NVIDIA/A100 阈值。
- 如性能 gate 不能恢复，必须记录平台限制、豁免范围和后续复查条件。

### 1. timing 稳定性

- 验证中科芯 event timing 行为。
- 对比 wall-clock 与 event timing 差异。
- 如果 event timing 有平台偏差，统一在 compat 层修正或在报告中明确标记。

### 2. resource usage

- 确认 device memory、free/total memory、峰值用量采样方法。
- 如果中科芯平台不支持 NVIDIA 等价采样接口，提供平台内替代或记录为 unsupported。
- 保持报告字段结构不变。

### 3. benchmark 与性能阈值

- 运行 Task1/Task2 L1-L6 sweep。
- 对核心算子运行 benchmark。
- 建立中科芯 baseline，不直接套用 A100 阈值。
- 将第一阶段记录项逐步恢复为正式性能 gate。

### 4. 稳定性回归

- 多次重复运行 demo 和单测。
- 记录非确定性失败、超时、内存泄漏、资源释放异常。
- 如果没有 `compute-sanitizer` 等价工具，记录跳过理由和替代检查方式。

## Test Plan

任务级重复验证：

```bash
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --repeat 10
scripts/test/run_task_demos.sh --build-dir build-zx --no-build --scale-sweep --repeat 5
```

全量测试：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --case-set full
```

benchmark：

```bash
./scripts/test/run_all_tests.sh --build-dir build-zx --case-set perf
```

## 完成判定

- Task1/Task2 重复运行无 correctness 抖动。
- L1-L6 sweep 可复现。
- resource 和 timing 报告字段结构稳定。
- 中科芯性能 baseline 已记录。
- 性能 gate 从记录项恢复为验收项，或明确记录平台限制和豁免范围。
- 本阶段发现的所有不兼容点、需要修改点、已修改点和暂缓点均已记录到 `docs/design/zhongkexin_migration_change_log.md`。
- `docs/design/zhongkexin_migration_status.md` 已更新到 V4.4 完成或明确阻塞状态。
