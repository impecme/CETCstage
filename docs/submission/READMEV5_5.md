# V5.5 全库 81 算子交付文档

## 阶段状态

- V5.5 已关闭，最终 gate 状态为 `passed`。
- 全库 benchmark：81/81 算子通过，失败 0。
- full 回归：12 个模块、81 个算子通过。
- Task smoke：2 个任务、14 个步骤通过，失败 0。
- 接口和类型契约：81/81 通过。
- 图件按模块组合压缩为 12 张，覆盖全部 81 个算子。

## 终测报告

第五阶段只保留以下终测目录：

| 内容 | 路径 |
| --- | --- |
| 统一汇总 | `data/reports/zhongkexin/v5_5_final/summary.json`、`summary.md` |
| Stage4 与显存摘要 | `data/reports/zhongkexin/v5_5_final/stage4_summary.json`、`gpu_memory_summary.json` |
| 任务 smoke | `data/reports/zhongkexin/v5_5_final/task_smoke.json` |
| 接口审计 | `data/reports/zhongkexin/v5_5_final/interface_audit.json`、`interface_audit.md` |
| 类型契约 | `data/reports/zhongkexin/v5_5_final/type_contracts.json`、`type_contracts.md` |
| 81 算子性能明细 | `data/reports/unit/benchmarks/v5_5_final/latest_all_ops_scale_benchmark.csv` |
| 性能简报 | `data/reports/unit/benchmarks/v5_5_final/latest_report.md` |
| 组合图件 | `data/reports/unit/benchmarks/v5_5_final/figures/` |

`data/reports/unit/<module>/` 中的 current `latest_*` 文件是 full 回归输入，
由 gate 汇总读取，不再复制到第五阶段目录。逐轮优化 probe 不属于终测交付。

## 终测结果

- all81 最大 GPU E2E 项为 `radartools/ambgfun`，约 167.8 ms。
- 其次为 `spectral/lombscargle`，约 12.5 ms；`radartools/mvdr` 约 11.1 ms。
- GPU 显存峰值 2453 MiB，最大利用率 100%。
- V5.5 重点优化后的 `lfilter`、`filtfilt`、`periodogram`、`coherence` 和窗口生成路径均通过终测。

## 汇总复现

```bash
cd /CETC
source /zq500/sdk/env.sh

python3 scripts/platform/summarize_v5_5_gate.py
cat data/reports/zhongkexin/v5_5_final/summary.json
cat data/reports/zhongkexin/v5_5_final/summary.md
```

汇总脚本校验 all81 benchmark、模块 full 回归、任务 smoke、接口/类型契约和
12 张模块组合图；任一门禁失败时返回非零状态。
