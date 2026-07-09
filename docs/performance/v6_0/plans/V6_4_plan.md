# V6.4 Task1 第一批计划

## 状态与目标

- 状态：待开始；进入条件：V6.1 基线关闭，Task2 第一批不再阻塞主线。
- 目标：优化 Task1 `pulse_compression/pulse_doppler/power_map/ca_cfar/final_detection` device-resident 链路，使 Task1 L6 GPU total 至少下降 20%。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.4-01 | Task1 workspace plan | pulse/doppler/power/CFAR buffer 复用表 | 每步 timing 不丢，stage sum 可解释 |
| V6.4-02 | `pulse_compression` | template FFT device resident、plan/workspace 复用 | error 不回退，L5/L6 plan/copy 开销下降 |
| V6.4-03 | `pulse_doppler` | Doppler FFT 后 shift/power 候选融合 | `pulse_doppler` 和 `power_map` 仍可独立报告 |
| V6.4-04 | `ca_cfar` 探针 | naive shared、sliding window、prefix/SAT 三路比较 | 阈值误差和 peak 一致性通过 |
| V6.4-05 | detection device resident | mask、peak、最终标量回传 | final_detection 精度和业务 gate 通过 |

## 执行规则

- Task1 首批不改变 `ambgfun` 语义，避免 full surface 约束混入 CFAR 链路。
- CFAR 不预设 SAT 最优；按窗口半径、map 尺寸和显存读写实测选择。
- 若融合 `fftshift + power_map`，任务报告必须保留两个步骤的独立计时字段。

## 回传与关闭条件

回传 `radartools` 受影响算子 full、Task1 L3 smoke、Task1 L1-L6 repeat=3/5。关闭条件：Task1 L6 GPU total 下降至少 20%，`pulse_compression/pulse_doppler/ca_cfar` 三项合计下降明确，14 步报告完整。
