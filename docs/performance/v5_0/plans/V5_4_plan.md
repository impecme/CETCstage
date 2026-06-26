# V5.4 核心 53 算子计划

## 状态与目标

- 状态：已完成；进入条件：V5.3 已关闭；对应交付：`docs/submission/READMEV5_4.md`。
- 目标：在 task27 基础上完成核心非任务 26，达到核心 53/53 的工程、类型、测试和性能闭环。
- 提前完成：`filtering/wiener` 二维 tiled kernel 已通过 full，阶段回归时仍需重测。
- 阶段收口：`v5_4_gate_latest` passed，核心 53、模块回归、任务 smoke、接口/类型契约和组合图件均通过。

## 工作包

| ID | 工作包 | 操作 | 关闭条件 |
| --- | --- | --- | --- |
| V5.4-01 | core53 基线 | L6 1/3 probe 后执行批次收口 probe | 已关闭：53 行完整，无失败 |
| V5.4-02 | 工程契约补齐 | 复用 V5.2 审计并在关闭前复验 core53 | 关闭前复验 53/53 契约通过 |
| V5.4-03 | P0/P1 热点 | 按 L6 E2E 和任务价值排序逐项优化 | 已关闭：保留优化、回退候选和剩余项均已记录 |
| V5.4-04 | P1/P2 审计 | 任务 smoke、契约/类型复核、剩余项结论化 | 已关闭：任务和契约复核通过 |
| V5.4-05 | 模块回归 | 受影响模块 correctness 和 benchmark | 已关闭：7 个受影响模块全部通过 |
| V5.4-06 | 阶段关闭 | core53 stable、报告和交付 | 已关闭：gate summary passed |

## 当前收口命令

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

排序键依次为：任务复用价值、失败状态、GPU E2E、GPU/CPU speedup、kernel 占比、allocation/cache、显存峰值。每轮只处理排序后的一个算子。

当前批次已关闭的代表收益：

- `filter_design/firwin2`：0.383 ms 降至 0.121 ms。
- `spectral/csd`：3.019 ms 降至 0.876 ms。
- `windows/general_cosine`：约 5.97 ms 降至 0.454 ms。
- `windows/taylor`：约 5.94 ms 降至 0.563 ms。
- `bsplines/gauss_spline`：约 3.36 ms 降至 0.175 ms。
- `radartools/ambgfun`：约 175.96 ms 降至 167.99 ms。

Task1/Task2 smoke 已通过：`status=passed`、`task_count=2`、`step_count=14`、`failure_count=0`。
核心 53 契约/类型复核已通过：interface 81/81 passed，type contracts 81/81 passed。

受影响模块 full 回归已通过：

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

本轮结果：`filter_design` 5/5、`filtering` 17/17、`radartools` 6/6、`spectral` 9/9、`bsplines` 3/3、`wavelets` 5/5、`windows` 23/23 全部通过。V5.4-06 阶段关闭验证已通过。

阶段关闭汇总：

```bash
cd /CETC
source /zq500/sdk/env.sh

python3 scripts/platform/summarize_v5_4_gate.py
cat data/reports/zhongkexin/v5_4_gate_latest/summary.json
cat data/reports/zhongkexin/v5_4_gate_latest/summary.md
```

实测结果：`status=passed`、core53 `53/53`、模块回归 `passed`、任务 smoke `passed`、contracts `passed`、组合图件 `12` 个模块图覆盖 `53` 个算子。

## 单算子完成定义

- 声明注释、CPU/GPU 接口、类型契约和独立测试均通过。
- 默认复数输出算子只测试 `complex64`，并报告 real/imag/overall error；不实现 `complex128`、FP16 复数或整数复数。
- 适用实数类型全部验证；原生浮点专用算子不强制扩展整数，不适用类型具有拒绝用例或明确契约说明。
- FP16 实数路径允许 FP32 中间累加；整数路径必须保留整数语义并明确累加宽度、输出转换和溢出规则。
- 每个算子先复核 `target_types/current_types`，不得把未实现目标类型写成已支持。
- 优化项有修改前后 5/30 数据；无修改项有量化依据。
- 保留改动通过单算子 full、所属模块全算子回归及受影响任务回归。

## 阶段关闭与回传

用户回传 core53 CSV、失败行统计、53 状态汇总、受影响模块报告和显存 summary。关闭条件为 core53=53、最终状态=53、correctness 全通过、无未解释退化，且交付文档完整。当前阶段已满足上述条件，后续进入 V5.5 扩展 28 和全库 81 验收。
