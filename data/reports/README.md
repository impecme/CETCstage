# 当前代码报告

本目录只保存当前交付代码在本队 ZQ500 容器上的完整验证结果，不存放历史报告、
候选实验、日志、图件、缓存或中间归档。

完整验证成功后，`scripts/finalize_reports.py` 会原子发布以下结构：

- `units/<module>/<operator>/`：每个算子的 `metrics.json`、`cases.csv` 和
  `summary.md`；
- `units/benchmarks/summary.json` 和 `summary.csv`：81 个算子的运行时间、加速比、
  误差和性能 case 汇总；未定义性能 case 的算子明确标记 `available: false`，不补造数据；
- `demo/task1_radar/`、`demo/task2_features/`：两个任务的最终场景和 L1-L6 数据；
- `validation/`：接口、dtype、算子集合和任务步骤审计；
- `summary.json`、`summary.md`、`provenance.json`、`SOURCE_FILES.sha256` 与
  `FILES.sha256`：本次报告范围、来源和完整性校验。

计时口径：单算子的 `gpu_kernel_perf` 统计 GPU kernel 计时；任务步骤的
`gpu_kernel_ms` 由 CUDA event 记录该步骤在 GPU stream 上排队并完成的工作时间，
不含主机端准备和调度开销。任务步骤可能由多个算子、多个 kernel 或 GPU stream 内部
传输组成，因此该值是步骤级 GPU 执行时间，不应当解释为某一个公共算子的单 kernel 耗时；
不发起 CUDA 工作的步骤记录为 `0`。

运行期原始证据临时写在被 Git 忽略的 `data/.reports_staging/`，只要门禁失败就不会替换
本目录。报告不包含历史性能结论。
