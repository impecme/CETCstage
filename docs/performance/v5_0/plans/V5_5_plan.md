# V5.5 全库 81 算子与最终交付计划

## 状态与目标

- 状态：待开始；进入条件：V5.4 关闭；对应交付：`docs/submission/READMEV5_5.md`。
- 目标：完成扩展 28，达到 81/81，并执行类型、平台、任务、correctness、性能和资源最终验收。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V5.5-01 | extended28 基线与契约 | 28 行 stable baseline 和契约状态 | 28/28 完整 |
| V5.5-02 | extended28 优化 | 逐项措施或审计结论 | 28/28 最终状态 |
| V5.5-03 | all81 类型回归 | 五种实数适用组合和 complex64 报告 | 全部适用组合通过 |
| V5.5-04 | all81 性能回归 | L1-L6 共 486 行 | 486/486 通过 |
| V5.5-05 | 任务与资源回归 | 两任务 L1-L6、显存/cache、稳定性 | 所有 gate 通过 |
| V5.5-06 | 平台最终回归 | 完整兼容探针和禁止 API 扫描 | 与 V5.2 矩阵一致 |
| V5.5-07 | 文档交付 | 总表、图件、台账、READMEV5_0/5 | 可从新容器复现 |

## 扩展 28 执行

- `windows` 15、`filter_design` 3、`filtering` 3、`radartools` 1、`spectral` 3、`correlate` 1、`peak_finding` 2。
- 使用 `OPERATOR_SET=extended28` 先跑 1/3 probe，再跑 5/30 stable。
- 单热点沿用 V5.3 的 full -> 模块 -> 必要任务回归阶梯。
- 扩展算子不得因不属于赛题核心而只做 smoke。

## 最终验证顺序

1. `validate_operator_sets.py` 断言 27/53/28/81 数量。
2. 类型契约测试覆盖所有适用组合和拒绝组合。
3. 12 模块 full correctness。
4. 两任务 L1-L6 repeat=5，逐步计时和精度完整。
5. all81 L1-L6 5/30 benchmark，确认 486 行。
6. 重复运行、显存/cache、资源漂移和可用的 memcheck。
7. 平台 compile/runtime probes 与 forbidden API scan。

## 全量命令

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
RUN_TASK_SWEEP=1 \
OPERATOR_SET=all81 \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage5_full \
STAGE4_REPORT_ROOT=data/reports/zhongkexin/stage5_full_latest \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_full.log
```

全量运行后执行：

```bash
cmake --build build-zx --target zx_compat_compile_probes zx_forbidden_api_scan --parallel
ctest --test-dir build-zx -R '^(cusignal_type_contract|zx_compat_runtime_)' --output-on-failure
scripts/test/run_task_demos.sh --no-build --scale-sweep --repeat 5 --require-visualization-deps
```

## 回传与关闭条件

用户回传 `stage5_full.log`、Stage5 JSON/Markdown、486 行 CSV、类型报告、任务步骤报告、显存 summary、兼容探针结果和图件清单。

关闭要求：81/81 契约和最终状态完整；486/486 通过；12 模块与两任务通过；五种实数适用组合及 complex64 通过；平台矩阵无新增未解释差异；台账无待修改/待验证项；`READMEV5_0.md` 和 `READMEV5_5.md` 可供新容器复现。
