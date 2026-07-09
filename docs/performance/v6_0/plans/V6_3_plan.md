# V6.3 Task2 链路第二批计划

## 状态与目标

- 状态：待开始；进入条件：V6.2 关闭。
- 目标：优化 Task2 `filter -> demod -> feature_fusion -> measurement_conversion -> kalman`，使 Task2 L6 GPU total 累计下降 45%-65%。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.3-01 | Task2 workspace plan | 任务级 buffer 复用表 | 中间结果 device resident，步骤报告仍可解释 |
| V6.3-02 | `filter` 路径 | FIR direct/FFT/overlap-save 阈值和 tap cache | filtered error 通过，L6 明显下降 |
| V6.3-03 | `demod` 融合 | 相位差、unwrap、score 合并 | demod error 通过，小规模不明显退化 |
| V6.3-04 | `feature_fusion_peak` | smoothing、weighted sum、argrelmax/top-k 融合 | peak 与 score 输出一致 |
| V6.3-05 | `measurement/kalman` 小矩阵合并 | measurement prepare、Kalman update、RMSE 统计 | 两步仍有独立误差和独立计时 |
| V6.3-06 | Task2 收口 | L1-L6 repeat=5 | Task2 累计收益达到 V6 目标区间 |

## 执行规则

- `filter` 必须保持 complex64 主路径和 V5.5 类型口径。
- Kalman 小矩阵优化不得改变报告 schema；`measurement_conversion` 不得重新并回 Kalman 步骤。
- 若某一步 launch overhead 已是主因，优先合并相邻任务私有 kernel；公共算子 API 不因任务特化被破坏。

## 回传与关闭条件

回传 Task2 分步 CSV/JSON、受影响算子 full、任务 L1-L6 和 all81 quick correctness。关闭条件：Task2 8 个计算步骤全部 pass，L6 GPU total 相比 V5.5 下降 45%-65%，dtype 缺口仍为 0。
