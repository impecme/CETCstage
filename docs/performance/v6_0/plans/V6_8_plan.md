# V6.8 全量回归与报告收束计划

## 状态与目标

- 状态：待开始；进入条件：V6.2 至 V6.7 已关闭。
- 目标：完成 V6 最终验收，保持 V5.5 接口、类型、报告 schema 和报告目录治理。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.8-01 | all81 correctness | 81 算子 full | 81/81 passed |
| V6.8-02 | dtype 覆盖 | dtype audit | `operator_dtype_missing_edges=0` |
| V6.8-03 | Task1/Task2 全规模 | L1-L6 repeat=5、14 步报告 | 2 任务、14 步、failure_count=0 |
| V6.8-04 | 性能终测 | all81 L1-L6、Task L1-L6 | V6 目标收益或瓶颈证据成立 |
| V6.8-05 | 平台回归 | compile/runtime/forbidden probes | 与 V5.5 平台口径一致，无新增禁止 API |
| V6.8-06 | 报告收束 | `data/reports/zhongkexin/v6_final/summary.*` | `data/reports/` 只保留终测汇总 |

## 全量命令

```bash
cd /CETC
source /zq500/sdk/env.sh

TASK_SCALES=1,2,3,4,5,6 \
RUN_TASK_SWEEP=1 \
OPERATOR_SET=all81 \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=/tmp/cetc_v6_final/all81_benchmark \
STAGE4_REPORT_ROOT=/tmp/cetc_v6_final/stage4_summary \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee /tmp/cetc_v6_final/stage4_full.log

scripts/test/run_all_tests.sh \
  --list \
  --build-dir build-zx \
  --platform ZHONGKEXIN \
  > /tmp/cetc_v6_final/all81_registry.tsv

python3 scripts/test/audit_task_steps.py \
  --contracts scripts/test/task_step_contracts.json \
  --output-dir /tmp/cetc_v6_final/task_step_audit \
  --summary-markdown /tmp/cetc_v6_final/task_step_audit.md

python3 scripts/test/audit_dtype_test_coverage.py \
  --registry /tmp/cetc_v6_final/all81_registry.tsv \
  --contracts scripts/test/operator_type_contracts.json \
  --output-dir /tmp/cetc_v6_final/dtype_coverage \
  --summary-markdown /tmp/cetc_v6_final/dtype_coverage.md
```

正式报告只从 `/tmp/cetc_v6_final` 摘要生成，长日志和图件移到 `/home/usr_04/CETC_garbage/`。

## 关闭条件

- all81 correctness 81/81。
- dtype 缺口 0。
- Task1/Task2 14 个计算步骤均有独立计时和精度。
- V5.5 接口、类型和报告 schema 不破坏。
- V6 所有优化、probe、回退和暂缓均已记录台账。
- `data/reports/` 只保留终测汇总。
