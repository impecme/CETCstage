# V6.8 全量回归与报告收束计划

## 状态与目标

- 状态：已关闭；V6-0138 硬门、V6-0141 性能终测和 V6-0142 报告收束均已通过。
- 目标：完成 V6 最终验收，保持 V5.5 接口、类型、报告 schema 和报告目录治理。
- 阶段交付：`docs/submission/READMEV6_8.md`。
- 最终结果：`data/reports/zhongkexin/v6_final/summary.md` 和 `summary.json`。

`READMEV6_8.md` 是 V6 最终交付说明文件。V6-0138、V6-0141 和 V6-0142
已全部关闭，V6 最终交付完成。

## 执行分段

| 台账 ID | 阶段 | 内容 | 关闭条件 |
| --- | --- | --- | --- |
| V6-0136 | 首次部署 | 执行预验收命令 | 容器缺少新脚本，测试未启动；失败事实已归档 |
| V6-0137 | 静态门首跑 | configure、注册表和五类静态审计 | 实际审计全绿；自定义断言误计 SDK 提示行，后续门未启动 |
| V6-0138 | 硬门预验收 | all81 full、接口/类型/dtype/步骤审计、平台探针、Task1/Task2 L1-L6 首次进程测量和 warm repeat=5、dlsmi、manifest/report 治理 | 已通过：全部状态为 0；81/81；dtype 缺口 0；24 个任务用例和 168 条分步记录通过 |
| V6-0139 | 性能终测首跑 | 启动 all81 L1-L6 正式终测 | guard 发现前序 `data/generated/unit/**/input|output_samples` 后停止；benchmark 未运行，失败事实已归档 |
| V6-0140 | 验收器修复 | generated unit 样本所有权、清理和证据化 | 旧样本先记录路径/大小再清理；guard 与 finalize 所有权一致；本地回放和容器回读通过 |
| V6-0141 | 性能终测重跑 | all81 L1-L6，warmup=5、repeat=30；任务终值复核；逐算子 GPU 占用采样；V6.1 固定分母对照 | 已通过：486/486，81/81，失败 0；显存峰值 2453 MiB；manifest/report diff 0 |
| V6-0142 | 汇总关闭 | 生成 `v6_final/summary.*`，填写本交付文件，核对台账和报告目录 | 已通过：最终 JSON/Markdown 一致；仓库报告目录仅保留 5 个允许文件 |

V6-0138 与 V6-0141 分开运行。硬门失败时不启动长时间的 486 行性能终测。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.8-01 | all81 correctness | 81 算子 full | `81/81 passed` |
| V6.8-02 | 接口、类型和 dtype | interface/type/dtype audit | 接口 81/81，兼容缺口 0，`operator_dtype_missing_edges=0` |
| V6.8-03 | Task1/Task2 全规模 | L1-L6 `first_process=1`、warm repeat=5、14 步报告 | 24 个用例、168 条分步记录、failure count 0 |
| V6.8-04 | 性能终测 | all81 L1-L6、Task L1-L6、V6.1 固定分母对照 | 绝对 ms、median/P95、收益和剩余瓶颈成立 |
| V6.8-05 | 平台回归 | compile/runtime/forbidden probes | 与 V5.5 平台口径一致，无新增禁止 API |
| V6.8-06 | 报告收束 | `data/reports/zhongkexin/v6_final/summary.*` | 只保留终测汇总，不保留中间日志和图件 |

## 测量口径

- `first_process` 表示新进程内首次计量结果。Task demo 内部仍执行必要的 GPU
  预热，因此不写成“未初始化裸冷启动”。
- warm 使用 repeat=5，报告 first、median 和 nearest-rank P95；repeat=5 时
  P95 等于五次测量最大值。
- 任务直接报告 GPU pipeline total、逐步骤 E2E、进程 wall、精度和资源快照。
- plan/cache/copy/allocation 使用当前算子报告和 V6.6/V6.7 已验证证据补充。
  当前任务报告没有直接暴露的字段必须写明“未直接测量”，不得推算或伪造。
- all81 正式终测执行完整 CPU 参考与 GPU timing，不复用历史 CPU cache；每行完成后写
  checkpoint，外部 `dlsmi` 以 0.5 秒间隔采样，并通过算子 start/end 时间窗生成逐算子资源表。
- V6.1 对照必须保持平台、scale、输入、seed、Release flags 和计时协议可比。
  源码指纹分别记录基线版与优化版；无法确认同口径的百分比不发布，只报告绝对值。

## V6-0138 结果

- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0138_pull_2NAQ58kr/`。
- 归档 SHA256：`be1fed49bd06e5edc6af8f75f54a509e0db632d2340bcd80b6f9d3adc8cff8eb`。
- all81 `81/81`，接口 `81/81`，兼容缺口 0，dtype 缺口 0，14 步 timing/accuracy 缺口 0。
- 平台、24 个任务用例、168 条分步记录、12 组 schema、manifest/report 恢复全部通过。
- Task1 L6 warm median `3.91998 ms`，相对 V6.1 下降 `45.48%`。
- Task2 L6 warm median `25.2926 ms`，相对 V6.1 下降 `66.75%`。

## V6-0139 首跑结论

- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0139_pull_4oIRJ8Sw/`。
- 归档/console SHA256：`b458d1effa873e43242243a7af5207649b658e67f612534a7042861a7ffe41f6` /
  `96ea02dd24ca41586f31d6667f748892a76c9212080a73eadfbce89186d22d43`。
- guard 返回 2，原因是前序测试遗留 generated unit 样本；最终 `overall=1`。
- benchmark、dlsmi 和性能汇总均未启动，不能登记 486 行或性能收益。
- manifest/report diff 均为 0；旧脚本 finalize 已清除这些生成样本，事后清单含 81 个
  manifest、0 个 `input/output_samples`。

## V6-0141 结果

- 证据：`/home/usr_04/CETC_garbage/cetc_v6_0141_pull_L11ItB5U/`。
- 归档/console SHA256：`5dbb7c2efaea9409b021c485d085f1db1e57a459df9792cdbb28a5b09facd9d5` /
  `b4342fdc1cf581386b93acb299dcbaf4ca53b6ddd3de29ebe94278048d86df66`。
- `status.tsv` 全部为 0；all81 L1-L6 `486/486`，81 个算子、6 个规模、失败 0。
- 正式计时为 warmup=5、repeat=30；逐行 start/end 均为 486，完整 CPU 参考和 GPU timing 已执行。
- dlsmi 共 2679 个样本，覆盖 400/486 个算子时间窗；显存峰值 `2453/16384 MiB`，
  瞬时 GPU utilization 最大 100%。
- 产品源码与 V6-0138 指纹一致；manifest/report diff 均为 0。
- 全规模主要剩余热点为 `ambgfun L6=167.855 ms`、`hilbert2 L5=97.534 ms` 和
  `lombscargle L6=11.497 ms`。前两项分别需要算法/FFT 重写，不属于 V6.8 低风险收口改动。

## V6-0141 复现命令

```bash
cd /CETC
source /zq500/sdk/env.sh
set -u -o pipefail

chmod +x scripts/platform/run_v6_8_performance.sh
V6_8_RUN_ID=V6-0141 \
V6_8_PREFLIGHT_ARCHIVE=/tmp/cetc_v6_0138_latest.tar.gz \
scripts/platform/run_v6_8_performance.sh \
  2>&1 | tee /tmp/cetc_v6_0141_console.log
RC=${PIPESTATUS[0]}

sha256sum \
  /tmp/cetc_v6_0141_latest.tar.gz \
  /tmp/cetc_v6_0141_console.log
printf 'RC=%s\nARCHIVE=%s\nCONSOLE=%s\n' \
  "${RC}" \
  /tmp/cetc_v6_0141_latest.tar.gz \
  /tmp/cetc_v6_0141_console.log
```

固定取回文件：

- `/tmp/cetc_v6_0141_latest.tar.gz`
- `/tmp/cetc_v6_0141_console.log`

脚本要求 `/tmp/cetc_v6_0138_latest.tar.gz` 存在且硬门为 0，并核对当前
`CMakeLists.txt/cmake/include/src/demo/tests` 与预验收产品源码指纹一致。中间报告只写入
`/tmp`。旧 generated unit 样本先记录路径和大小后清理；退出时只删除脚本已取得所有权的
unit/demo 报告和样本，并用运行前后 SHA256 证明 `data/reports/` 与全部 manifest 已恢复。

## V6-0142 结果

- 新增 `scripts/platform/finalize_v6_8_delivery.py`，从 V6-0138/0141 仓库外证据生成紧凑终测汇总。
- 恢复 V5.5 最终摘要且 SHA256 与历史归档一致：
  `summary.md=fcf879e4...`、`summary.json=e4719263...`。
- 已生成 `data/reports/zhongkexin/v6_final/summary.md` 和 `summary.json`。
- `data/reports/` 最终只有 README、V5.5 两份摘要和 V6 两份摘要，共 5 个文件。
- V6.1 all81 历史包为 warmup=1/repeat=3，本轮为 warmup=5/repeat=30；
  因协议不同不发布全库百分比，只发布 486 行绝对终值。

## 关闭结果

- all81 correctness 81/81：通过。
- 接口 81/81、类型兼容缺口 0、dtype 缺口 0：通过。
- Task1/Task2 14 个计算步骤独立计时和精度，L1-L6 首次进程与 warm 报告：通过。
- 平台 compile/runtime/forbidden probes 和 CUDA Graph 生命周期：通过。
- all81 L1-L6 486 行、manifest/report 恢复和同产品源码指纹：通过。
- V5.5 API、类型和报告 schema：未破坏。
- V6 优化、probe、回退和暂缓：已全部记录台账。
- `data/reports/` 治理：通过。
