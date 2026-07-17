# V7.6 全量回归与最终交付

## 状态

- V7.6 与 V7 已关闭，后续停止性能候选并进入最终汇报。
- V5.5/V6/V7 最终报告留待后续实际跑代码时生成；本轮不单独补报告。
- 当前 `data/reports/` 为空；仓库外证据归档保持不变，中间结果不写回仓库。

## 最终保留

- Task2 AOT correlate：L3/L6 热点下降 `89.45%/61.66%`，端到端下降
  `39.71%/9.77%`。
- Task2 AOT spectrogram：L3/L5/L6 热点下降
  `47.49%/20.86%/43.37%`。
- 五分钟演示：Task1 L6、Task2 L6 与固定 Top30 总 wall
  `101.971/240 s`。
- Top30 全部通过，中位加速 `109.919x`，几何平均 `105.455x`。

## 默认关闭

- AOT filter：demod 精度失败。
- Morlet2 CWT 对称路径：L5/L6 端到端收益不足。
- 扩大 DeviceStorage cache：四算子总收益仅 `0.096%`。
- Task1 预热 buffer 释放：设备分配减少，但两轮合并 L6 退化 `2.38%`。

## 最终门禁

| 检查 | 结果 |
| --- | ---: |
| all81 correctness | `81/81` |
| dtype 缺口 | `0` |
| Task timing/accuracy 步骤 | `14/14` |
| Task1 L1-L6 | 全部通过 |
| Task2 L1-L6 | 全部通过 |
| Top30 | `30/30` |
| 报告/manifest 恢复 diff | `0` |

全量门来自 V7-0008；V7-0009/V7-0010 只修改 Task1 demo 的实验生命周期
选择，未修改公共算子、接口、类型或报告 schema。

## 证据

- V7-0005：
  `/home/usr_04/CETC_garbage/cetc_v7_0005_pull_nzySolcJ/`
- V7-0006：
  `/home/usr_04/CETC_garbage/cetc_v7_0006_pull_s3xISZIV/`
- V7-0007：
  `/home/usr_04/CETC_garbage/cetc_v7_0007_pull_5ivh74xt/`
- V7-0008：
  `/home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/`
- V7-0009：
  `/home/usr_04/CETC_garbage/cetc_v7_0009_pull_YiZwJVyu/`
- V7-0010：
  `/home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/`
- V7-0011 容器回读：
  `/home/usr_04/CETC_garbage/cetc_v7_0011_deploy_readback/`
- V7-0005 至 V7-0010 的精确根目录名、归档/console SHA256，以及
  V7-0011 两个回读文件 SHA256，冻结在
  `scripts/platform/v7_final_evidence_manifest.json`。
- V7-0008 归档内的 `fingerprint/candidate_sources.sha256` 已纳入归档成员绑定；
  其中 8 个最终保留的 Task2/benchmark/汇总文件必须与当前仓库逐项 SHA 一致。
  V7-0008 的 Task1 文件是唯一允许被后续证据覆盖的路径，并必须由 V7-0011
  manifest、容器回读和当前源码三方一致来关闭。

V7-0011 只有 Task1 源码与 runner 两文件的字节级容器回读，没有独立执行
manifest。因此最终编号由冻结交付政策、精确目录名和两文件 SHA 共同约束，
不能把它表述为一次具有完整独立执行 provenance 的新测试。

## 最终汇总生成

`scripts/platform/finalize_v7_delivery.py` 不运行 GPU，只读取并交叉校验
V7-0005 至 V7-0011 的结构化证据。V7-0005 的整体 gate 为预期失败，其中
correlate-only 分支通过，filter/combined 分支失败；V7-0006 的候选数值校验
通过但未达到原挑战门，后续按三档正收益且端到端无退化的书面口径保留。
汇总器必须分别验证这些事实，不能把任何整体 failed gate 改写成 passed。
V7-0006 的保留边界见
[V7.0 计划](../performance/v7_0/plans/V7_0_plan.md)与
[优化变更日志](../performance/v7_0/optimization_change_log.md)。

执行编号、验收门限、预期数量和冻结 SHA 是仓库内校验政策；wall、收益、通过数、
失败集合及保留/拒绝结果均由归档内原始 JSON/TSV/CSV/log 重算。manifest 是
交付校验配置，不是性能报告；本轮 `/tmp` dry-run 只验证生成链路，不向
`data/reports/` 补写报告。manifest 需随受审提交或最终可交付归档 SHA 固定后，
才构成仓库外部可引用的信任锚。

V7 汇总器会校验实际 V5.5 `summary.md/json` 的冻结 SHA，而不是只相信 V6
摘要中的声明。V6 `summary.md/json` 已移除生成时间和临时报告根等动态字段；
两个独立 `/tmp` 目录生成的文件字节级一致，其双 SHA、V6 evidence manifest SHA
和报告目录 README SHA 均冻结在 V7 manifest。V7 还会对 V6 内容做语义复核：
24/168/14、public/mixed 步骤分类、486 行 runner 协议、精确的
`spectral/coherence` L1-L5 五条 `true-error` 诊断和 Graph 六阶段状态都必须匹配。
因此修改 V6 正文、嵌套测量值或任一前置文件都会判红；这不会改变 V6/V7
性能结论。

历史证据另有一个明确边界：V7-0009 的多个补充用例使用了
`--skip-timing-validation`；其中只有 Task2 L1 smoke 的
`gpu_total_stability` 超过内部 limit，且原始值仍保留。该项不是 V7-0008
最终演示门，也不参与候选收益结论；汇总器只允许这一个由冻结 manifest
声明的超限豁免，并在派生 JSON 中单独披露。

生成 V7 汇总前先生成 V5.5/V6 汇总，然后执行：

```bash
python3 scripts/platform/finalize_v7_delivery.py \
  --correlate-root /home/usr_04/CETC_garbage/cetc_v7_0005_pull_nzySolcJ/extracted/cetc_v7_0005_task2_fft_20260716_155059 \
  --correlate-archive /home/usr_04/CETC_garbage/cetc_v7_0005_pull_nzySolcJ/cetc_v7_0005_latest.tar.gz \
  --correlate-console /home/usr_04/CETC_garbage/cetc_v7_0005_pull_nzySolcJ/cetc_v7_0005_console.log \
  --spectrogram-root /home/usr_04/CETC_garbage/cetc_v7_0006_pull_s3xISZIV/extracted/cetc_v7_0006_spectrogram_20260716_160737 \
  --spectrogram-archive /home/usr_04/CETC_garbage/cetc_v7_0006_pull_s3xISZIV/cetc_v7_0006_latest.tar.gz \
  --spectrogram-console /home/usr_04/CETC_garbage/cetc_v7_0006_pull_s3xISZIV/cetc_v7_0006_console.log \
  --cwt-root /home/usr_04/CETC_garbage/cetc_v7_0007_pull_5ivh74xt/extracted/cetc_v7_0007_cwt_symmetry_20260716_162507 \
  --cwt-archive /home/usr_04/CETC_garbage/cetc_v7_0007_pull_5ivh74xt/cetc_v7_0007_latest.tar.gz \
  --cwt-console /home/usr_04/CETC_garbage/cetc_v7_0007_pull_5ivh74xt/cetc_v7_0007_console.log \
  --demo-root /home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/extracted/cetc_v7_0008_demo_budget_20260717_002730 \
  --buffer-first-root /home/usr_04/CETC_garbage/cetc_v7_0009_pull_YiZwJVyu/extracted/cetc_v7_0009_task1_buffer_reuse_20260717_010926 \
  --buffer-second-root /home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/extracted/cetc_v7_0010_task1_buffer_reuse_20260717_012214 \
  --final-readback-root /home/usr_04/CETC_garbage/cetc_v7_0011_deploy_readback \
  --demo-archive /home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/cetc_v7_0008_latest.tar.gz \
  --demo-console /home/usr_04/CETC_garbage/cetc_v7_0008_pull_ze3a63s8/cetc_v7_0008_console.log \
  --buffer-first-archive /home/usr_04/CETC_garbage/cetc_v7_0009_pull_YiZwJVyu/cetc_v7_0009_latest.tar.gz \
  --buffer-first-console /home/usr_04/CETC_garbage/cetc_v7_0009_pull_YiZwJVyu/cetc_v7_0009_console.log \
  --buffer-second-archive /home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/cetc_v7_0010_latest.tar.gz \
  --buffer-second-console /home/usr_04/CETC_garbage/cetc_v7_0010_pull_bR3cnvq7/cetc_v7_0010_console.log \
  --v5-summary-json data/reports/zhongkexin/v5_5_final/summary.json \
  --v6-summary-json data/reports/zhongkexin/v6_final/summary.json \
  --evidence-manifest scripts/platform/v7_final_evidence_manifest.json \
  --output-dir data/reports/zhongkexin/v7_final
```

负向回归入口：

```bash
python3 tests/platform/test_finalize_v7_delivery.py
```
