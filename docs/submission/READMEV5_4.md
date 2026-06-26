# V5.4 核心 53 算子交付文档

## 版本信息

- 当前状态：已完成。
- 对应计划：`docs/performance/v5_0/plans/V5_4_plan.md`。
- 进入条件：V5.3 已关闭。
- 阶段收口：`v5_4_gate_latest` 已完成，核心 53、模块回归、任务 smoke、接口/类型契约和组合图件均通过。

## 交付要求

- 核心 53/53 算子的接口注释、CPU/GPU 对应、类型契约和独立测试状态。
- correctness、边界、非法参数、适用类型和稳定 benchmark 证据。
- 保留优化的耗时、误差、显存/cache 前后对比。
- 无收益、平台受限和回滚项的明确依据。

## 类型执行口径

- 五种实数是库级正式类型集合，不代表每个算子都必须支持五种。
- 以原 cuSignal/SciPy 语义为准：原生浮点专用算子不扩展整数，但必须记录不适用并验证拒绝行为。
- 语义允许的算子需要补齐所有适用实数类型，例如比较/索引、identity、相关/卷积类整数路径。
- 默认复数输出只实现 `complex64`，即两个 FP32；不实现 `complex128`、FP16 复数或整数复数。
- FP16 实数路径允许内部使用 FP32 中间累加；整数路径必须使用明确的整数累加宽度和输出转换规则。
- `current_types` 表示当前已实现能力，`input_types/output_types` 表示目标适用范围，二者不得混写。

## 提前完成项

- `filtering/wiener`：二维 shared-memory tiled 快路径已通过 full，归入本阶段核心 53。

## 当前工作包

- `V5.4-01`：已关闭，core53 L6 probe 和当前优化批次收口完成。
- `V5.4-02`：已由 V5.2 契约审计打底，V5.4 关闭前复验核心 53。
- `V5.4-03`：已关闭，P0/P1 热点已完成保留优化、回退候选和剩余项记录。
- `V5.4-04`：已关闭，任务 smoke 和核心 53 契约/类型状态复核均通过。
- `V5.4-05`：已关闭，受影响模块 full 回归通过。
- `V5.4-06`：已关闭，阶段关闭验证与交付收口通过。

## 当前优化批次结论

- 报告目录：`data/reports/unit/benchmarks/v5_4_core53_batch_close_probe`。
- 阶段报告：`data/reports/zhongkexin/v5_4_core53_batch_close_probe_latest`。
- 结果：核心 53 行全部 `passed`，失败 0。
- 显存：`gpu_memory_used_mib_max=2453`，`gpu_memory_used_mib_avg=688.46`，`gpu_memory_util_percent_max=99`。
- 主要收益：
  - `filter_design/firwin2`：0.383 ms 降至 0.121 ms。
  - `spectral/csd`：3.019 ms 降至 0.876 ms。
  - `windows/general_cosine`：约 5.97 ms 降至 0.454 ms。
  - `windows/taylor`：约 5.94 ms 降至 0.563 ms。
  - `bsplines/gauss_spline`：约 3.36 ms 降至 0.175 ms。
  - `radartools/ambgfun`：约 175.96 ms 降至 167.99 ms，并将峰值显存提高到 2453 MiB。
- 暂缓项：`radartools/ca_cfar` direct-path 阈值候选导致退化，已回退并记录为暂缓。
- 剩余低 speedup 项：`radartools/cfar_alpha`、`filtering/detrend`、`filtering/sosfilt`、`estimation/kalman_filter`。
- 剩余高耗时项：`radartools/ambgfun`、`spectral/lombscargle`、`filtering/hilbert2`、`filtering/wiener`、`wavelets/cwt`。
- 任务 smoke：Task1/Task2 均 PASS，`status=passed`、`task_count=2`、`step_count=14`、`failure_count=0`。
- 契约复核：interface 81/81 passed，type contracts 81/81 passed；实数集合为 FP32、FP16、INT32、INT16、INT8，复数仅 complex64。
- 模块回归：`filter_design` 5/5、`filtering` 17/17、`radartools` 6/6、`spectral` 9/9、`bsplines` 3/3、`wavelets` 5/5、`windows` 23/23 全部通过。
- 阶段 gate：`python3 scripts/platform/summarize_v5_4_gate.py` 输出 `status=passed`；summary 记录 core53 `53/53`、模块回归 `passed`、任务 smoke `passed`、contracts `passed`、组合图件 `12` 个模块图覆盖 `53` 个算子。

## V5.4 复现命令

```bash
cd /CETC
source /zq500/sdk/env.sh

OPERATOR_SET=core53 \
RUN_TASK_SWEEP=0 \
BENCH_SCALE_LEVELS=6 \
BENCH_WARMUP=1 \
BENCH_REPEAT=3 \
BENCH_REPORT_MODE=concise \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/v5_4_core53_batch_close_probe \
STAGE4_REPORT_ROOT=data/reports/zhongkexin/v5_4_core53_batch_close_probe_latest \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_4_core53_batch_close_probe.log
```

任务 smoke、契约/类型复核和受影响模块 full 回归已通过。受影响模块 full 回归复现命令：

```bash
cd /CETC
source /zq500/sdk/env.sh

for module in filter_design filtering radartools spectral bsplines wavelets windows; do
  echo "===== ${module} full ====="
  scripts/test/run_all_tests.sh \
    --platform ZHONGKEXIN \
    --module "${module}" \
    --operator all \
    --case-set full \
    --warmup 1 \
    --repeat 3 \
    --build-dir build-zx \
    --emit-report
done
```

阶段关闭汇总复现命令：

```bash
cd /CETC
source /zq500/sdk/env.sh

python3 scripts/platform/summarize_v5_4_gate.py
cat data/reports/zhongkexin/v5_4_gate_latest/summary.json
cat data/reports/zhongkexin/v5_4_gate_latest/summary.md
```

V5.4 已关闭，下一步进入 V5.5 扩展 28 和全库 81 验收。

## V5.4 回传内容

- 当前 core53 CSV 和 summary。
- 任务 smoke 的 `v5_4_task_smoke_after_core53.json`。
- 核心 53 复核对应的 interface/type summary。
- 受影响模块 full 回归输出。
- 若有失败行，回传失败 task/operator、status、mixed_error、CPU/GPU 耗时和日志尾部。
