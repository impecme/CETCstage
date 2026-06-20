# V5.4 核心 53 算子计划

## 状态与目标

- 状态：待开始；进入条件：V5.3 关闭；对应交付：`docs/submission/READMEV5_4.md`。
- 目标：在 task27 基础上完成核心非任务 26，达到核心 53/53 的工程、类型、测试和性能闭环。
- 提前完成：`filtering/wiener` 二维 tiled kernel 已通过 full，阶段回归时仍需重测。

## 工作包

| ID | 工作包 | 操作 | 关闭条件 |
| --- | --- | --- | --- |
| V5.4-01 | core53 基线 | L6 1/3 probe 后执行 5/30 stable | 53 行完整，无失败或缺字段 |
| V5.4-02 | 工程契约补齐 | Doxygen、CPU/GPU、类型、独立测试 | 53/53 契约通过 |
| V5.4-03 | P0 热点 | 按 L6 E2E 和任务价值排序逐项优化 | 每项 full + 模块回归 |
| V5.4-04 | P1/P2 审计 | 优化或给出无需修改/平台受限结论 | 53/53 有最终状态 |
| V5.4-05 | 模块回归 | 受影响模块 correctness 和 benchmark | 相关模块全部通过 |
| V5.4-06 | 阶段关闭 | core53 stable、报告和交付 | 无待处理核心项 |

## 基线与排序

```bash
cd /CETC
OPERATOR_SET=core53 \
RUN_TASK_SWEEP=0 \
BENCH_SCALE_LEVELS=6 \
BENCH_WARMUP=5 \
BENCH_REPEAT=30 \
BENCH_REPORT_MODE=concise \
BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/v5_4_core53 \
STAGE4_REPORT_ROOT=data/reports/zhongkexin/v5_4_core53 \
scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage5_4_core53.log
```

排序键依次为：任务复用价值、失败状态、GPU E2E、GPU/CPU speedup、kernel 占比、allocation/cache、显存峰值。每轮只处理排序后的一个算子。

## 单算子完成定义

- 声明注释、CPU/GPU 接口、类型契约和独立测试均通过。
- complex 算子只测试 complex64，并报告 real/imag/overall error。
- 适用实数类型全部验证；不适用类型具有拒绝用例。
- 优化项有修改前后 5/30 数据；无修改项有量化依据。
- 保留改动通过单算子 full、所属模块全算子回归及受影响任务回归。

## 阶段关闭与回传

用户回传 core53 CSV、失败行统计、53 状态汇总、受影响模块报告和显存 summary。关闭条件为 core53=53、最终状态=53、correctness 全通过、无未解释退化，且交付文档完整。
