# V6.0 任务优先性能优化规划

## 目标

第六版不再扩大原 cuSignal 全量优化范围，优先把赛题两项任务和任务直接相关算子做深。

1. 深度优化 Task1、Task2 端到端性能。
2. 深度优化两任务直接调用或强相关的算子。
3. 轻度优化赛题中提到的算子库，重点处理低风险固定开销和明显热点。
4. 原 cuSignal 中存在、但赛题未提到且不影响任务链路的算子，暂不做进一步性能优化，只保持 correctness、接口和类型契约不回退。

## 范围分层

| 层级 | 范围 | 处理策略 |
| --- | --- | --- |
| P0 | Task1/Task2 端到端 pipeline | 深度优化，允许重排任务内 GPU 数据流、融合 helper、复用 workspace，但不降低精度门限 |
| P1 | 两任务直接相关公共算子 | 深度优化，优先 `radartools`、`filtering`、`spectral`、`wavelets`、`correlate`、`demod`、`estimation` |
| P2 | 赛题中提到但不在当前任务热路径的算子 | 轻度优化，处理小规模固定开销、重复拷贝、重复 workspace、明显串行循环 |
| P3 | 原 cuSignal 有、赛题未提到的算子 | 暂不优化；只维护构建、测试、类型兼容和回归通过 |

## Task1 深度优化方向

| 方向 | 目标 | 主要检查点 |
| --- | --- | --- |
| `ambgfun` | 降低 Task1 最大 GPU E2E 项和显存峰值 | 输出规模、分块策略、缓存复用、频域中间量复用 |
| `pulse_compression` / `pulse_doppler` | 减少 FFT 周边 copy 和 workspace 重建 | FFT plan/cache、模板频谱复用、Doppler 后处理融合 |
| `ca_cfar` / `detect_peak` | 降低小 kernel 和 host/device 往返 | 阈值、mask、peak 选择尽量 device resident |
| Task1 report | 保持 6 个计算步骤独立计时和独立精度 | schema v2、error_available、step pass 均不回退 |

## Task2 深度优化方向

| 方向 | 目标 | 主要检查点 |
| --- | --- | --- |
| `filter` | 降低 complex FIR + 实部投影阶段耗时 | 公共 `firfilter` 复数输出和实部投影融合、tap/cache 复用 |
| `demod` | 降低批量解调评分固定开销 | 公共 `fm_demod` 语义保持，任务批量 score 保持 device resident |
| `correlate` | 减少相关、幅值、归一化多 kernel 串联 | 相关输出后处理融合，避免中间数组反复分配 |
| `spectrogram` | 降低 segment/window/FFT 周边开销 | window cache、segment packing、band score 融合 |
| `cwt` | 降低尺度循环和 score reduction | wavelet cache、scale reduction 融合、避免无用完整矩阵落地 |
| `feature_fusion_peak` | 降低小数组固定开销 | 平滑、加权、peak selection 合并为少量 kernel |
| `measurement_conversion` / `kalman` | 降低小规模 tracking 启动开销 | measurement 准备、Kalman 更新和输出写回融合 |
| Task2 report | 保持 8 个计算步骤独立计时和独立精度 | schema v2、error_available、step pass 均不回退 |

## 赛题算子库轻度优化

轻度优化只处理收益明确、风险低、不会改变接口和报告格式的项：

- 移除多余 host/device copy。
- 复用公共 workspace/cache。
- 对小数组路径减少 kernel launch 数。
- 对窗口、波形、滤波设计、谱估计和雷达小矩阵路径补 fast path。
- 对 FP16/整数兼容路径只在有性能收益时补原生 kernel；V6 不要求把所有兼容路径改成原生 dtype kernel。

## 工作包

| 工作包 | 内容 | 关闭条件 |
| --- | --- | --- |
| V6.0-01 | 建立 Task1/Task2 L1-L6 repeat=3 基线和 all81 当前基线 | 任务 14 步全部 pass；all81 81/81 pass；热点排序明确 |
| V6.0-02 | Task1 深度优化第一批：`ambgfun`、CFAR、peak/device-resident 链路 | Task1 L5/L6 GPU total 明显下降，无精度回退 |
| V6.0-03 | Task2 深度优化第一批：filter、correlate、spectrogram、CWT | Task2 L5/L6 GPU total 明显下降，8 步精度全部通过 |
| V6.0-04 | Task2 小步骤融合：feature fusion、measurement、Kalman | 小步骤 kernel/launch 固定开销下降，任务报告 schema 不变 |
| V6.0-05 | 赛题相关算子库轻度优化 | 只合入有单算子和模块回归证据的低风险优化 |
| V6.0-06 | 类型和平台回归 | dtype 覆盖缺口 0；接口/类型契约 passed；ZQ500 项目使用范围兼容 passed |
| V6.0-07 | 第六版收口报告 | `data/reports/` 仍保持精简，只保留终测数据和汇总 |

## 指标

| 指标 | V6 目标 |
| --- | --- |
| Task1 L6 GPU total | 相比 V5.5 终测下降 20%-30%，若受输出规模限制则给出瓶颈解释 |
| Task2 L6 GPU total | 相比 V5.5 终测下降 20%-30% |
| 任务步骤 | 14/14 独立计时、14/14 独立精度、failure_count=0 |
| all81 correctness | 81/81 passed |
| dtype 覆盖 | `operator_dtype_missing_edges=0` |
| 报告目录 | `data/reports/` 只保留终测数据和汇总，日志放仓库外垃圾目录 |

## 验证阶梯

1. 单文件构建：改动模块对应 target 必须通过。
2. 单算子 CTest：改动算子对应独立测试必须通过。
3. 任务 smoke：Task1/Task2 必须通过 schema v2 校验。
4. 任务 L1-L6 sweep：深度优化批次必须跑对应任务全尺度。
5. all81 benchmark：阶段收口必须 81/81 passed。
6. full 回归：最终交付前跑全库 full、接口审计、类型契约和 dtype 覆盖。

## 风险控制

- 每次只优化一个热点或一个紧密相关的小批次。
- 不通过放宽误差阈值换性能；阈值变化必须有数值原因和容器复验证据。
- 不把赛题未提到的原 cuSignal 扩展语义作为 V6 性能主线。
- 所有容器日志、完整图件和中间 probe 放到 `/home/usr_04/CETC_garbage/`，不放入仓库。
- `data/reports/` 只保留最终汇总和必要机器可读摘要。
