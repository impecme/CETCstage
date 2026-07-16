# V6.8 全量回归与最终交付文档

## 版本信息

- 当前状态：已关闭；V6-0138 硬门、V6-0141 性能终测和 V6-0142 最终汇总全部通过。
- 对应计划：`docs/performance/v6_0/plans/V6_8_plan.md`。
- 对应执行编号：V6-0136 至 V6-0142；当前台账已记录至 V6-0142。
- 进入条件：V6.2-V6.4 已技术收束，V6.5-V6.7 已关闭。

本文件是 V6 最终交付说明文件。`v6_final` 终测结果已生成，V6.8 和 V6
均已关闭。

## 关闭顺序

| 台账 ID | 内容 | 当前状态 |
| --- | --- | --- |
| V6-0136 | 首次命令执行 | 容器缺少脚本，测试未启动，已关闭 |
| V6-0137 | 静态门首跑 | 五类审计通过，注册表断言误计提示行，已关闭 |
| V6-0138 | correctness、契约、平台、任务 L1-L6 和目录治理预验收 | 全部通过，已关闭 |
| V6-0139 | all81 L1-L6 性能终测首跑 | generated unit 旧样本阻断，benchmark 未启动，已关闭 |
| V6-0140 | generated unit 清理与所有权修复 | 已实现、回放并同步，已关闭 |
| V6-0141 | all81 L1-L6 最终性能与 GPU 占用终测 | 486/486，81/81，失败 0，已关闭 |
| V6-0142 | 生成最终汇总、交付审计和 V6 关闭 | 5 个最终报告文件，已关闭 |

## 最终交付门禁

| 项目 | 要求 |
| --- | --- |
| all81 correctness | `81/81` |
| 接口和类型 | 接口 81/81；兼容缺口 0；V5.5 API/type 不破坏 |
| dtype 覆盖 | `operator_dtype_missing_edges=0` |
| Task1/Task2 | L1-L6 共 24 个模式用例；14 步、168 条分步记录、failure count 0 |
| 任务统计 | 首次进程测量、warm repeat=5、median/P95、进程 wall、逐步骤精度和资源快照 |
| 算子性能 | all81 × L1-L6 共 486 行，warmup=5、repeat=30 |
| 平台 | compile/runtime/forbidden probes 无新增问题 |
| 完整性 | manifest 前后不变，源码和编译指纹完整 |
| 报告治理 | `data/reports/` 只保留 V5.5 与 V6 终测汇总 |

## 最终报告路径

- Markdown：`data/reports/zhongkexin/v6_final/summary.md`。
- JSON：`data/reports/zhongkexin/v6_final/summary.json`。
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

证据：`/home/usr_04/CETC_garbage/cetc_v6_0138_pull_2NAQ58kr/`，归档
SHA256=`be1fed49bd06e5edc6af8f75f54a509e0db632d2340bcd80b6f9d3adc8cff8eb`。

## V6-0141 性能终测

| 项目 | 结果 |
| --- | --- |
| all81 L1-L6 | 486/486 行，81/81 算子，失败 0 |
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

- 新增 `scripts/platform/finalize_v6_8_delivery.py`，强校验两个终测证据后生成最终摘要。
- V5.5 `summary.md/json` 已按历史 SHA 原样恢复。
- `data/reports/` 只含 README、V5.5 两份摘要和 V6 两份摘要，共 5 个文件。
- 完整 486 行、168 条任务步骤、telemetry、日志和归档仍在仓库外。

## 报告内容

- `summary.md` 列出硬门、任务 L1-L6、14 个 L6 步骤、全规模热点、GPU 资源和剩余瓶颈。
- `summary.json` 使用 `v6_final_summary_v1`，保留机器可读 gate、任务、热点、资源、限制和证据 SHA。
- 所有失败候选仍保留在 V6 台账，不因最终报告收束而删除。

最终结论：V6.8 已关闭，V6 最终交付完成。
