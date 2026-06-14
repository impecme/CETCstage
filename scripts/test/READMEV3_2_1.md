# V3.2.1 `scripts/test` 算子精度提升、全量体检与报告格式统一

## 版本信息

- 版本名称：`V3.2.1 scripts/test 算子精度提升、全量体检与报告格式统一`
- 版本定位：仅覆盖 `scripts/test` 测试与审计链路，不改公开算子 API，不改总 README。
- 完成状态：已完成。

## 版本目标

- 在现有阈值口径下，对已启用算子执行全量精度体检并结构化输出结果。
- 区分“真实精度失败”和“基础设施失败”，避免把环境问题误判为算子误差问题。
- 为后续算子实现侧修正提供固定输入与固定性能口径的对比基线。
- 统一旧版 operator-level `latest_metrics.json`，避免顶层 `pass` 与 `summary.pass` 两种结构并存。

## 关键变更

- 新增脚本：`scripts/test/audit_all_ops_precision.py`
  - 自动读取 `run_all_tests.sh --list` 的启用算子清单。
  - 阶段 A：逐算子执行 `accuracy` 并输出基线 CSV。
  - 仅把 `status=failed`（阈值不通过）放入修正队列。
  - `status=infra_failed`（如缺失二进制）单独归类，不进入修正队列。
  - 支持修正后 `perf` 快照与前后 `perf delta` 对比。
- 更新文档：`scripts/test/README.md`
  - 增补新脚本使用方式、输出文件、字段说明与状态语义。
- 统一报告格式：
  - 新增 summary-only metrics writer，输出顶层元数据 + `summary` + `cases`。
  - 已迁移 `correlate/correlate`、`correlate/correlate2d`、`demod/fm_demod`、`estimation/kalman_filter`、`peak_finding/argrelextrema`。
  - 旧模块仍保留原 `latest_summary.md` 与 `latest_cases.csv` 口径。
  - `audit_all_ops_precision.py` 仅读取标准 `summary` 结构，不再兼容旧版顶层 `pass` 格式。

## 运行口径

- 判定口径：沿用现有 `manifest` 的 `atol/rtol` 与测试支持代码逻辑。
- 诊断指标：`max_rel_error`（ratio 小数）为主，`max_abs_error` / `rmse` 同步记录。
- 性能口径：对比时固定同输入与同 `warmup/repeat`，记录 `cpu/gpu_e2e/gpu_kernel` 中位值与 speedup。

## 输出产物

- `data/reports/unit/audit/precision_baseline_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_baseline.csv`
- `data/reports/unit/audit/precision_fix_queue_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_fix_queue.csv`
- `data/reports/unit/audit/precision_perf_snapshot_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_perf_snapshot.csv`
- `data/reports/unit/audit/precision_perf_delta_<run_id>.csv`
- `data/reports/unit/audit/latest_precision_perf_delta.csv`
- `data/reports/unit/audit/latest_precision_fix_report.md`

## 验收结果

- 全量审计：`passed=53, failed=0, infra_failed=0`
- 修正队列：0 个算子
- 报告结构扫描：53 个 operator-level `latest_metrics.json` 均存在 `summary`，无旧版顶层 `pass` 结构残留
- 说明：部分旧模块当前写入 `cases: []`，表示只统一 summary 级 metrics，尚未迁移逐 case JSON
