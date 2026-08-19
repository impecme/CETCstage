# 性能基线与最终结果

本目录按“冻结基线、运行时缓存、最终报告、调优证据”分层保存。性能比较必须使用同一设备、同一规模和同一 `warmup/repeat` 口径。

## Canonical locations

| 内容 | 路径 | 用途 |
| --- | --- | --- |
| 固定 accuracy 参考数据 | `reference/` | 81 个算子的固定输入、expected 输出和 manifest；供单元正确性与 dtype 合同测试使用 |
| CPU/GPU 冻结基线 | `baseline/` | ZQ500 `gpu_04`、all81、L1-L6、486 条 workload 的统一基线目录；不可覆盖 |
| GPU 性能结果基线 | `baseline/gpu_baseline.csv`、`baseline/gpu_baseline.json` | 冻结 GPU E2E/kernel 计时与正确性结果 |
| CPU 性能结果基线 | `baseline/cpu_baseline.csv` | 与 GPU 基线逐 workload 对齐的 CPU 中位时间 |
| CPU/GPU 原始复现数据 | `baseline/gpu_reference/`、`baseline/cpu_reference/` | GPU 冻结 manifest、原始 metrics/logs，以及 486 个 workload 的完整 CPU/GPU 输出参考 |
| Auto 运行时缓存 | `tuning/zx_tuning.json` | 当前 C500 `zx-c500-all81-v2` 的 exact-key 离线选择结果 |
| 最终静态报告 | `reports/static/` | 静态算子与 Task1/Task2 对照报告；目录结构与 `reports/autotune/` 对齐 |
| 最终 Auto/任务目录 | `reports/autotune/` | Auto 算子报告和后续 Task1/Task2 `demo/` 报告的统一入口 |
| 调优过程证据 | `/home/usr_04/CETC_runs/repo_cleanup_20260818/autotune_evidence/` | round1 全候选、round2 复核及原始候选报告；已移出仓库归档 |

每个最终报告目录中的 `operator_scales.csv/json/md` 是同一批结果的三种格式；最终性能结论引用
`reports/static/units/benchmarks/` 与 `reports/autotune/units/benchmarks/`；任务对照位于两者各自的 `demo/`。

## 目录约定

```text
CETC/
└── data/
    ├── baseline/                            # CPU/GPU 冻结基线与原始复现数据
    │   ├── cpu_baseline.csv
    │   ├── gpu_baseline.csv
    │   ├── gpu_baseline.json
    │   ├── gpu_reference/                   # 未优化 GPU 冻结运行的原始数据
    │   │   ├── inputs/                      # 486 个冻结输入 manifest
    │   │   ├── raw/ logs/                   # GPU 原始运行证据
    │   │   └── L1/ ... L6/                  # 按 workload 组织的 GPU 参考视图
    │   └── cpu_reference/                   # 完整 CPU/GPU 输出参考缓存
    ├── reports/                             # 当前性能报告
    │   ├── autotune/                        # Auto 结果与任务结果
    │   │   ├── units/benchmarks/            # 81 × L1-L6 算子汇总
    │   │   ├── units/<module>/<operator>/  # 后续运行保留的单算子 L1-L6 明细
    │   │   └── demo/                        # 后续 Task1/Task2 报告
    │   ├── static/                          # 静态 A/B：算子与任务
    │   │   ├── units/benchmarks/            # 静态算子汇总
    │   │   └── demo/                        # 静态 Task1/Task2 对照
    │   └── ...
    ├── tuning/zx_tuning.json                # Auto 运行时查表缓存
    └── ...                                   # reference/、generated/
```

`baseline/` 是新的冻结基线固定入口，`data/baseline/gpu_reference/` 是未优化 GPU
基线的原始数据，根目录的 CSV/JSON 是对应汇总表。`tests/`、`scripts/` 和 CMake 均使用该路径。
`performance.sh` 默认把新算子报告和任务报告写入 `data/reports/autotune/`，旧的分散默认输出目录
不再生成。`data/reports/static/` 是当前静态策略的最终 A/B 报告，不是 GPU 冻结基线；
Auto 报告统一位于 `data/reports/autotune/`。旧的
`data/reports/zx_operator_gpu_final_static/` 仅作为历史快照并被忽略。

`data/reference/` 不能用 `data/baseline/cpu_reference/` 替代：前者是小规模固定 accuracy
参考集，后者是离线性能运行产生的 486 workload 完整输出缓存，两者用途和文件集合不同。
