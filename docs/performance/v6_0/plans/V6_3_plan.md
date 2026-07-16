# V6.3 Task2 链路第二批计划

## 状态与目标

- 状态：已技术收束。保留 V6-0042 公共 complex FIR shared-halo；V6-0041 fusion 与 V6-0043 双流未达门禁，ZQ500 对当前重计算分支并发结论为 `limited`，不继续扩展四流。
- 目标：建立 Task2 execution plan，在保留 8 步报告的前提下并行 filter 后的四个独立分支，再优化 `filter/demod/fusion` 固定成本，使 Task2 L6 GPU total 相比 V6.1 同源码基线累计下降 45%-65%。
- 阶段交付：`docs/submission/READMEV6_3.md`，记录 FIR 保留项和多 stream `limited` 结论。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.3-01 | stream/runtime probe | `concurrentKernels`、非默认 stream、event、`cufftSetStream` 支持结论 | supported/limited/unsupported 明确；失败不阻断串行优化 |
| V6.3-02 | Task2 execution context | 任务级 stream/event/workspace 和 buffer lifetime 表 | 中间结果 device resident；8 步 event timing 和 pipeline wall 都可解释 |
| V6.3-03 | 分支并行 | filter 后 `demod/correlate/spectrogram/cwt` 并行，fusion 统一 join | 结果确定；并行 wall 比串行 sum 有稳定收益，否则暂缓 |
| V6.3-04 | `filter` 路径 | shared halo direct 优先；再比较 FFT/overlap-save 阈值和 tap FFT cache | filtered error 通过；L6 目标下降 >=30%，L1/L2 不明显退化 |
| V6.3-05 | `demod` 融合 | 相位差、unwrap、score 合并 | demod error 通过，小规模不明显退化 |
| V6.3-06 | `feature_fusion_peak` | smoothing、weighted sum、argrelmax/top-k 融合 | peak 与 score 输出一致 |
| V6.3-07 | `measurement/kalman` 固定成本 | alias、冗余清零、allocation 和小矩阵 launch 清理 | 两步仍有独立误差和独立计时；不投入算法级重写 |
| V6.3-08 | Task2 收口 | cold=1、warm repeat=5、L1-L6 | Task2 累计收益达到 V6 目标区间，显存高水位无失控增长 |

## 执行规则

- `filter` 必须保持 complex64 主路径和 V5.5 类型口径。
- 多 stream 计时使用各 stream event；`gpu_total` 记录 pipeline wall，不能再用并行 stage 之和代替端到端时间。
- 公共算子的嵌套 `cudaEventSynchronize` 会阻断并行，需由 execution context 选择“记录但暂不等待”，最终在依赖 join 处同步。
- Kalman 小矩阵优化不得改变报告 schema；`measurement_conversion` 字段保留，即使 alias 后计时为 0。
- 若某一步 launch overhead 已是主因，优先合并相邻任务私有 kernel；公共算子 API 不因任务特化被破坏。
- setup 中的 widths/taps/template/B-spline 上传必须单列 cold/setup 计时，不再隐藏在 stage 外。

## 回传与关闭条件

回传 Task2 分步 CSV/JSON、stream probe、受影响算子 full、任务 L1-L6 和 all81 quick correctness。关闭条件：Task2 8 个计算步骤全部 pass，L6 pipeline wall 相比 V6.1 同源码暖基线累计下降 45%-65%，dtype 缺口仍为 0。
