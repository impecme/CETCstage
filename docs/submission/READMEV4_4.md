# V4.4 中科芯第四阶段交付文档

## 版本信息

- 版本名称：`V4.4 性能、资源与稳定性收敛`
- 当前日期：`2026-06-17`
- 当前状态：已关闭
- 对应计划：`docs/migration/zhongkexin/plans/V4_4_plan.md`
- 修改台账：`docs/migration/zhongkexin/change_log.md`

## 版本目标

V4.4 在 V4.3 全量公开算子 accuracy 关闭后，收敛中科芯平台的性能、资源、timing、benchmark CSV/Markdown/JSON 和图件链路。本版本已经完成 Stage4 full：Task1/Task2 L1-L6、81 个公开算子、6 档 benchmark、CSV/Markdown 报告和 PNG 图件全部通过。

## 核心改动

- `scripts/test/benchmark_all_ops_scales.py` 新增 `--platform`，可显式传入 `ZHONGKEXIN`。
- `benchmark_all_ops_scales.py` 新增 `--scale-levels`，支持只运行指定规模，例如只跑 L3。
- 新增 `scripts/platform/run_zhongkexin_stage4.sh`。
- Stage4 入口在 `build-zx` 不存在时会先执行中科芯 CMake configure，再构建 Task1/Task2 demo。
- Stage4 入口在 Task sweep、operator benchmark 或绘图失败时会打印对应内层日志尾部，避免外层只显示静默退出。
- Stage4 默认 pilot 只运行：
  - Task1/Task2 L3 scale sweep。
  - `waveforms` 模块 L3 benchmark。
  - benchmark CSV/Markdown 和 PNG 图件生成。
- 保留全量展开入口：通过环境变量打开 L1-L6、全模块、完整 repeat 和 full report。
- Task2 中科芯 L1/L2 timing gate 已按 full sweep 暴露的 ZQ500 实测抖动校准；该调整仅在 `CUSIGNAL_PLATFORM_ZHONGKEXIN` 下生效。
- 全量 benchmark 首次展开已生成 486 行 CSV，其中 401 行通过；失败已分为 benchmark scale mapping 覆盖缺口和 `chebwin`/`firwin2` 中科芯资源规模过大两类，并已在 benchmark 编排层修复。
- 失败子集复验已通过：15 个算子、90 行 benchmark 全部通过，并生成总览图和单算子图。
- Stage4 full 最终通过：81 个算子、486 行 benchmark 全部通过，生成 87 个 benchmark 图件文件。

## 当前验证结果

容器内已执行：

```bash
cd /CETC
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_pilot.log
```

结果摘要：

- 脚本版本：`diagnostics-20260617-stage4-perf-pilot-v2`。
- Stage4 pilot：`PASS`。
- Task1/Task2：L3 scale sweep 均通过，并生成 demo 报告与图件。
- 算子 benchmark：`waveforms` 模块 L3，5/5 条通过。
- benchmark 图件：总览图和 5 个单算子图均生成。
- 归档目录：`data/reports/zhongkexin/stage4_runs/20260617_pilot_v2/`。

`waveforms` pilot 性能摘要：

| Operator | L3 scale | E2E speedup | Kernel speedup | 结论 |
| --- | --- | --- | --- | --- |
| `chirp` | 16384 | 4.697x | 9.657x | 通过 |
| `gausspulse` | 16384 | 6.024x | 11.254x | 通过 |
| `sawtooth` | 16384 | 2.270x | 4.669x | 通过 |
| `square` | 16384 | 2.282x | 4.651x | 通过 |
| `unit_impulse` | 16384 | 0.057x | 0.234x | 通过，性能偏 CPU 侧，后续全量 baseline 中记录 |

## Stage4 Full 验证

容器内已执行：

```bash
cd /CETC
TASK_SCALES=1,2,3,4,5,6 \
BENCH_MODULES=all \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log
```

最终结果：

- 脚本版本：`diagnostics-20260617-stage4-perf-full-v4`。
- Stage4 full：`PASS`。
- Task1/Task2 L1-L6：12/12 行通过。
- 全量 benchmark：81 个算子、486/486 行通过。
- benchmark 图件：总览图、plot summary 和 81 个单算子图均生成，共 87 个文件。
- 归档目录：`data/reports/zhongkexin/stage4_full_final/`。
- 全量 benchmark 目录：`data/reports/unit/benchmarks/zhongkexin_stage4_full/`。

如果后续 full sweep 在 Task1/Task2、operator benchmark 或绘图阶段失败，Stage4 v4 会直接在终端打印对应内层日志尾部，优先据此判断是 timing gate、correctness、资源限制还是图件生成问题。

失败子集已通过，命令保留为局部复验入口：

```bash
cd /CETC
RUN_TASK_SWEEP=0 \
BENCH_MODULES=windows,filter_design,filtering,radartools,spectral,correlate,peak_finding \
BENCH_OPERATORS=chebwin,kaiser_beta,kaiser_atten,cmplx_sort,firwin2,lfilter,firfilter_zi,filtfilt,mvdr,periodogram,welch,coherence,correlation_lags,argrelmin,argrelmax \
BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=full \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_retry \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_retry.log
```

局部复验结果：

- 脚本版本：`diagnostics-20260617-stage4-perf-full-v4`。
- benchmark rows：90。
- failed rows：0。
- plot status：passed。
- 归档目录：`data/reports/zhongkexin/stage4_retry_latest/`。

## 预期产物

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| Stage4 final summary | `data/reports/zhongkexin/stage4_full_final/latest_stage4_summary.md` | Stage4 full 汇总 |
| Stage4 full log | `data/reports/zhongkexin/stage4_full_final/stage4_full.log` | 完整外层日志 |
| Task scale report | `data/reports/zhongkexin/stage4_full_final/latest_task_demo_scale_report.md` | Task1/Task2 L1-L6 报告 |
| Benchmark CSV | `data/reports/unit/benchmarks/zhongkexin_stage4_full/latest_all_ops_scale_benchmark.csv` | 81 算子、486 行全量 benchmark |
| Benchmark report | `data/reports/unit/benchmarks/zhongkexin_stage4_full/latest_report.md` | 全量 benchmark Markdown |
| Benchmark figures | `data/reports/unit/benchmarks/zhongkexin_stage4_full/figures/` | 全量 benchmark 图件 |

## 完成判定

V4.4 已关闭：

- pilot 入口在容器内通过。
- L1-L6 Task1/Task2 性能 sweep 可复现。
- 全量算子 benchmark CSV/Markdown/JSON 可复现。
- benchmark 图件可复现。
- 中科芯性能 baseline 已入账。
- 本阶段发现项已写入并关闭或明确记录在迁移台账中。
