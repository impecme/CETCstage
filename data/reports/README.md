# 当前代码报告

本目录只保存当前交付代码在本队 ZQ500 容器上的完整验证结果，不存放历史报告、
候选实验、日志、图件、缓存或中间归档。

正式全量复测由 `scripts/performance.sh` 直接发布，不再经过旧的
`finalize_reports.py` 汇总口径。当前最终结果只有以下几类：

- `units/benchmarks/operator_scales.json`、`operator_scales.csv`、`operator_scales.md`：
  81 个算子 × L1-L6 的 486 行端到端性能，CPU/GPU E2E 加速比直接写入；
- `demo/task1_radar/`、`demo/task2_features/`：两个任务的 summary.csv、各规模公共注册算子
  `operators/L1.csv` ... `L6.csv`、任务阶段 `stages/L1.csv` ... `L6.csv` 和对应的输入/误差数据；
  operators 只统计 Task1 的 5 项、Task2 的 14 项，两个任务去重并集为 18 项；阶段和私有
  Helper 不计入公共算子数量；
- `validation/`：接口、dtype、算子集合和任务步骤审计；
- `FILES.sha256`：当前报告文件完整性校验。

旧的 `units/benchmarks/summary.csv`、`summary.json` 已从正式报告目录移除，
不再作为性能结论来源。

计时口径：单算子的 `gpu_kernel_perf` 统计 GPU kernel 计时；任务步骤的
`gpu_kernel_ms` 由 CUDA event 记录该步骤在 GPU stream 上排队并完成的工作时间，
不含主机端准备和调度开销。任务步骤可能由多个算子、多个 kernel 或 GPU stream 内部
传输组成，因此该值是步骤级 GPU 执行时间，不应当解释为某一个公共算子的单 kernel 耗时；
不发起 CUDA 工作的步骤记录为 `0`。

运行期原始数据临时写在被 Git 忽略的 `data/.reports_staging/`，只要门禁失败就不会替换
本目录。报告不包含历史性能结论。
