# V6.5 Task1 ambgfun 与 mvdr 深化计划

## 状态与目标

- 状态：待开始；进入条件：V6.4 关闭。
- 目标：判断 `ambgfun` full surface 是否是 Task1 必需输出，并深化 `mvdr` 小矩阵路径。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.5-01 | `ambgfun` 约束审计 | full surface 消费链路和输出规模说明 | 明确 full surface 必留、可 ROI、或可 metrics 替代 |
| V6.5-02 | `ambgfun` 分解 probe | bytes/FFT/launch/plan/zero-fill 估算 | 若不改写，也有瓶颈证据 |
| V6.5-03 | `ambgfun_metrics` 候选 | peak/ROI/代表面校验公共接口 | 不破坏现有 `ambgfun` API |
| V6.5-04 | `mvdr` 深化 | covariance、diagonal loading、solve 路径 | 独立 full 通过，显式 inverse 风险可解释 |
| V6.5-05 | Task1 收口 | L1-L6 repeat=5 | Task1 L6 GPU total 达到 V6 目标或给出 full surface 限制证据 |

## 执行规则

- `ambgfun` 公共算子语义不降级；任务路径如用 metrics，必须保留 representative surface 校验。
- 若 full surface 必须全量落地，优化重点转为 batched FFT、extract、zero-fill 和 workspace，而不是删输出。
- `mvdr` 若非任务主链路热点，只按 radartools 深化项处理，不抢 Task1 主线资源。

## 回传与关闭条件

回传 `ambgfun` 单算子 benchmark、Task1 L1-L6、`mvdr` full 和台账结论。关闭条件：Task1 L6 相比 V5.5 下降 35%-50%，或已用 bytes/FFT/launch 分解证明剩余瓶颈。
