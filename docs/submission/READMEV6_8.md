# V6.8 全量回归与最终交付文档

## 版本信息

- 当前状态：已关闭；V6-0138 硬门、V6-0141 性能终测和 V6-0142 最终汇总全部通过。
- 对应计划：`docs/performance/v6_0/plans/V6_8_plan.md`。
- 对应执行编号：V6-0136 至 V6-0142；当前台账已记录至 V6-0142。
- 进入条件：V6.2-V6.4 已技术收束，V6.5-V6.7 已关闭。

本文件是 V6 最终交付说明文件。V6.8 和 V6 的历史终测结论均已关闭；当前
`data/reports/` 为空，V5.5/V6/V7 最终摘要留待后续实际跑代码时生成，本轮
不单独补报告。

## 关闭顺序

| 台账 ID | 内容 | 当前状态 |
| --- | --- | --- |
| V6-0136 | 首次命令执行 | 容器缺少脚本，测试未启动，已关闭 |
| V6-0137 | 静态门首跑 | 五类审计通过，注册表断言误计提示行，已关闭 |
| V6-0138 | correctness、契约、平台、任务 L1-L6 和目录治理预验收 | 全部通过，已关闭 |
| V6-0139 | all81 L1-L6 性能终测首跑 | generated unit 旧样本阻断，benchmark 未启动，已关闭 |
| V6-0140 | generated unit 清理与所有权修复 | 已实现、回放并同步，已关闭 |
| V6-0141 | all81 L1-L6 最终性能与 GPU 占用终测 | runner 用例门 486/486、81/81、失败 0；另有 5 条全局精度诊断边界，已关闭 |
| V6-0142 | 生成最终汇总、交付审计和 V6 关闭 | 历史执行当时生成 5 个最终报告文件，已关闭 |

## 最终交付门禁

| 项目 | 要求 |
| --- | --- |
| all81 correctness | `81/81` |
| 接口和类型 | 接口 81/81；兼容缺口 0；V5.5 API/type 不破坏 |
| dtype 覆盖 | `operator_dtype_missing_edges=0` |
| Task1/Task2 | L1-L6 共 24 个模式用例；14 个计算步骤（public 6、mixed 8）、168 条分步记录、failure count 0 |
| 任务统计 | 首次进程测量、warm repeat=5、median/P95、进程 wall、逐步骤精度和资源快照 |
| 算子性能 | all81 × L1-L6 共 486 行，warmup=5、repeat=30；runner gate 与全局 `error_class` 分开统计 |
| 平台 | compile/runtime/forbidden probes 无新增问题 |
| 完整性 | manifest 前后不变，源码和编译指纹完整 |
| V6 阶段报告治理 | 当时 `data/reports/` 只保留 V5.5 与 V6 终测汇总 |

## 最终报告路径

- 后续生成 Markdown：`data/reports/zhongkexin/v6_final/summary.md`。
- 后续生成 JSON：`data/reports/zhongkexin/v6_final/summary.json`。
- 完整日志、长表和图件：`/home/usr_04/CETC_garbage/`。

## V6-0138 已确认结果

| 项目 | 结果 |
| --- | --- |
| all81 / 接口 / dtype | `81/81`；接口 `81/81`；兼容缺口 0；dtype 缺口 0 |
| 任务矩阵 | 24/24 用例、168/168 分步记录、12/12 schema，失败 0 |
| Task1 L6 | warm median `3.91998 ms`；相对 V6.1 下降 `45.48%` |
| Task2 L6 | warm median `25.2926 ms`；相对 V6.1 下降 `66.75%` |
| 平台 | Release `-O3 -DNDEBUG`；Graph 生命周期六项状态均为 0 |
| 完整性 | manifest diff 0；reports diff 0 |

证据：`/home/usr_04/CETC_garbage/cetc_v6_0138_pull_2NAQ58kr/`，归档/console
SHA256=`be1fed49bd06e5edc6af8f75f54a509e0db632d2340bcd80b6f9d3adc8cff8eb` /
`499805429b2a8aabd6c33927824fff831bbb712ac16fd766268275ba0d22bb6f`。

## V6-0141 性能终测

| 项目 | 结果 |
| --- | --- |
| all81 L1-L6 | runner `status/pass` 为 486/486 行、81/81 算子，失败 0 |
| 精度诊断边界 | `spectral/coherence` L1-L5 共 5 行为 `error_class=true-error`；独立 accuracy case 按历史校准容差通过，但 perf runner 本身不以误差判失败 |
| 原始明细能力 | L6 绑定 81 份聚合 `latest_metrics.json`，73 份有 case 聚合明细、8 份仅 summary，但无 30 次 timing 样本/输出数组；L1-L5 仅有 CSV/progress/console |
| 计时协议 | warmup=5，repeat=30，完整 CPU 参考与 GPU timing |
| 逐行进度 | start/end 均为 486 |
| dlsmi | 2679 个样本，覆盖 400/486 个时间窗 |
| GPU 资源 | 显存峰值 2453/16384 MiB；瞬时利用率最大 100% |
| 完整性 | 产品源码指纹一致；manifest/report diff 0 |

证据：`/home/usr_04/CETC_garbage/cetc_v6_0141_pull_L11ItB5U/`。归档/console
SHA256=`5dbb7c2efaea9409b021c485d085f1db1e57a459df9792cdbb28a5b09facd9d5` /
`b4342fdc1cf581386b93acb299dcbaf4ca53b6ddd3de29ebe94278048d86df66`。

## 最终性能

- Task1 L6 warm median：`7.19016 -> 3.91998 ms`，下降 `45.48%`。
- Task2 L6 warm median：`76.0695 -> 25.2926 ms`，下降 `66.75%`。
- Task1 关键步骤：pulse compression 下降 `73.13%`，pulse Doppler 下降
  `21.52%`，CA-CFAR 下降 `26.45%`。
- Task2 关键步骤：CWT 下降 `71.86%`，spectrogram 下降 `80.04%`，
  correlate 下降 `55.20%`。
- all81 最大绝对项为 `ambgfun L6=167.855 ms`；`hilbert2 L5=97.534 ms`
  是 V6.1 已存在的非友好 FFT 尺寸性能陡坡，不是 V6.8 回归。
- V6.1 all81 的 warmup/repeat 与 V6.8 不同，因此最终报告不发布全库百分比。

## 报告收束

- `scripts/platform/finalize_v6_8_delivery.py` 已改为绑定冻结 SHA，并从两个终测
  归档的 audit、162 份 manifest、ctest、task metrics/steps、benchmark CSV、
  progress、L6 metrics 和 telemetry 交叉生成最终摘要。
- 486 行 runner gate 仍保持历史 `passed` 结论，但不再把它等同于“全局精度
  诊断无异常”：`coherence` L1-L5 的 5 条 `true-error` 会在 JSON/Markdown
  单列披露并按冻结集合校验。
- L1-L5 没有足够 raw repeat 可独立重建 median/min/max；汇总器只校验冻结
  CSV、逐行 progress、console 和归档绑定，不再宣称从 486 份 raw repeat 重算。
- L6 的 `latest_metrics.json` 也只允许交叉校验聚合 timing/error 和 case 统计，
  不能从 30 次原始 timing 样本重建 median/P95，也不能按输出数组重算误差。
- V5.5 `summary.md/json` 后续只允许按冻结历史 SHA 原样恢复。
- 本轮不恢复报告；后续生成时 `data/reports/` 只允许保留 README 和
  V5.5/V6/V7 的最终 `summary.md/json`。
- 完整 486 行、168 条任务步骤、telemetry、日志和归档仍在仓库外。

V6.1 的 Task 基线、21 个保留方向、验收数量和瓶颈叙述是冻结的历史政策；
V6.8 当前 ms、收益、runner 通过数、诊断分类、热点和完整性结果来自证据。
V6-0138/0141 的精确目录名、archive/console SHA，以及 V5.5 摘要 SHA，记录在
`scripts/platform/v6_final_evidence_manifest.json`。该 manifest 是仓库内交付
校验配置，不是性能报告；只有随受审提交或最终可交付归档 SHA 固定后，才能
作为仓库外部可引用的信任锚。

## 硬编码复核结论

- 旧 finalizer 的问题是把当前测量值和 `passed` 直接写入汇总，同时缺少反向
  校验，属于 fail-open 报告生成缺陷。
- 没有证据证明有人手工篡改原始日志或故意隐藏算法错误。可以确认的是，旧
  逻辑会造成“上游汇总自称通过，最终报告继续通过”的隐藏效果。
- 当前 finalizer 固定验收政策、历史基线、预期拓扑、冻结 SHA、已知诊断集合
  和证据能力边界；Task 当前 timing/error、benchmark timing/speedup/
  error_class 和 gate 均从证据校验。
- `v6_final_summary_v2` 不写生成时间或临时报告根；同一冻结证据在不同输出目录
  生成的 `summary.md/json` 必须字节级一致，供 V7 manifest 固定双 SHA。
- V6 只允许在 V5.5 已恢复、V7 尚未生成时运行；若报告根已有 V7 文件则拒绝，
  避免重跑 V6 后留下与前置 SHA 不一致的旧 V7 摘要。

后续严格按 V5.5 -> V6 -> V7 顺序生成；V6 摘要执行：

```bash
python3 scripts/platform/finalize_v6_8_delivery.py \
  --preflight-root /home/usr_04/CETC_garbage/cetc_v6_0138_pull_2NAQ58kr/extracted/cetc_v6_0138_v6_8_preflight_20260716_122947 \
  --preflight-archive /home/usr_04/CETC_garbage/cetc_v6_0138_pull_2NAQ58kr/cetc_v6_0138_latest.tar.gz \
  --preflight-console /home/usr_04/CETC_garbage/cetc_v6_0138_pull_2NAQ58kr/cetc_v6_0138_console.log \
  --performance-root /home/usr_04/CETC_garbage/cetc_v6_0141_pull_L11ItB5U/extracted/cetc_v6_0141_v6_8_performance_20260716_131750 \
  --performance-archive /home/usr_04/CETC_garbage/cetc_v6_0141_pull_L11ItB5U/cetc_v6_0141_latest.tar.gz \
  --performance-console /home/usr_04/CETC_garbage/cetc_v6_0141_pull_L11ItB5U/cetc_v6_0141_console.log \
  --v5-source-dir /home/usr_04/CETC_garbage/manual_20260707235136/CETC_removed_20260627/reports/CETC-reports-pre-clean-20260627/zhongkexin/v5_5_final \
  --v5-summary-markdown data/reports/zhongkexin/v5_5_final/summary.md \
  --v5-summary-json data/reports/zhongkexin/v5_5_final/summary.json \
  --evidence-manifest scripts/platform/v6_final_evidence_manifest.json \
  --report-root data/reports \
  --output-dir data/reports/zhongkexin/v6_final
```

本轮 `/tmp` dry-run 只验证生成链路，不属于报告恢复。

## 报告内容

- `summary.md` 列出硬门、任务 L1-L6、14 个 L6 步骤、全规模热点、GPU 资源和剩余瓶颈。
- `summary.json` 使用 `v6_final_summary_v2`，保留机器可读 gate、任务、热点、资源、限制和证据 SHA。
- 所有失败候选仍保留在 V6 台账，不因最终报告收束而删除。

最终结论：V6.8 历史阶段已关闭；当前 V6 摘要待后续按上述顺序生成。
