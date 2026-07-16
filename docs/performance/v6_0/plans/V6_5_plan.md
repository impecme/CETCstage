# V6.5 Task1 收口与公共 ambgfun/mvdr 计划

## 状态与目标

- 状态：已关闭。V6-0070 pulse host-input/device-copy cache 已保留，Task1 L6 从 V6.1 的 `7.19016 ms` 降至 `4.23236 ms`，累计下降 `41.14%`；V6-0072 公共 `ambgfun` 单 tile 因大 batch 数值错误且无性能收益已回退；V6-0073 公共 `mvdr` host-input cache 已保留，E2E `11.111 -> 2.39885 ms`，下降 `78.41%`。
- 目标：先关闭 Task1 35%-50% 累计目标，再分开处理任务内 `ambgfun` 与公共 full-surface `ambgfun/mvdr`。公共算子收益不得替代 Task1 端到端收益。
- 已知差异：旧部署 Task1 L6 `ambgfun=0.926 ms`；V5.5 all81 公共 `ambgfun=167.792 ms`。`mvdr` E2E `11.148 ms`，kernel 仅 `0.841 ms`，首要问题是 kernel 外固定开销。
- 阶段交付：`docs/submission/READMEV6_5.md`；V6-0076 已完成最终日志核对和阶段收束。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.5-01 | Task1 收口 | L1-L6 cold/warm repeat=5、stage 与 wall | 相比 V6.1 同源码基线累计下降 35%-50% |
| V6.5-02 | 两类 `ambgfun` 约束审计 | 任务消费链路、公共 full surface 语义和输出 bytes | 明确任务可复用模板、可 ROI/metrics，或 full surface 必留 |
| V6.5-03 | 公共 `ambgfun` 分解 | pack/zero-fill/FFT/extract/plan/launch/bytes | 先定位算法量和固定开销，再选 batched FFT/layout/cache |
| V6.5-04 | `ambgfun_metrics` 候选 | peak/ROI/代表面校验接口 | 不破坏现有公共 `ambgfun` API；仅在任务确实不消费 full surface 时启用 |
| V6.5-05 | 公共 `mvdr` E2E 分解 | handle、allocation、H2D/D2H、sync、kernel 占比 | 先把 92% kernel 外开销归因，再决定 small-matrix kernel 是否值得改 |
| V6.5-06 | `mvdr` 算法候选 | covariance、diagonal loading、Hermitian solve | 独立 full 通过；只有 kernel 成为主因后才替换算法 |

## 执行规则

- `ambgfun` 公共算子语义不降级；任务路径如用 metrics，必须保留 representative surface 校验。
- 若 full surface 必须全量落地，优化重点转为 batched FFT、extract、zero-fill 和 workspace，而不是删输出。
- Task1 优先复用 pulse compression 已上传的 device template，避免为 ambgfun 再次 H2D。
- `mvdr` 非任务主链路热点，只按 radartools P1 处理；未证明 kernel 主导前不重写求解器。

## 显存换时间策略

- `dlsmi` 只负责运行期容量、GPU utilization 和 memory utilization 旁证；每 200 ms 采样并与 operator PID、阶段时间、allocation 统计对齐，禁止用单点 0% 或低占用判断瓶颈。
- 首个容量 A/B 仅限公共 `ambgfun`：perf surface 当前约 1 GiB，matrix tile 上限约 1 GiB、需要两批；允许增加约 1 GiB matrix 做单 tile 探针。只有 full accuracy 通过、E2E 至少下降 5%、无 OOM 且峰值受控才保留。
- Task1 L6 工作集只有数 MiB，不通过填满 16 GiB 提速；优先 kernel 融合、FFT/layout、device resident 和减少同步。
- `mvdr` E2E/kernel 差距约 13 倍，扩大 device buffer 无效；应拆 host copy、handle、同步和测试输入副本。
- 不为 CWT/spectrogram 物化任务不消费的全量中间矩阵；额外显存必须替代重算、搬运、allocation 或 launch，否则按退化候选处理。
- 外部容器峰值只作候选线索：`gpu_08/gpu_16` 的 8 GiB 级峰值来自 windows 测试，`gpu_10` 的 10 GiB 级峰值来自 signal compare；缺少参数、耗时和 utilization，不能替代本项目同数据量 A/B。其他队伍 Task1 曾出现约 `0.5/0.8/2.0/3.0 GiB` 多档峰值，可用于提醒大规模档检查 workspace/output 生命周期，但不能推断更快。

## 回传与关闭条件

已回传 Task1 L1-L6、公共 `ambgfun` 容量 A/B、`mvdr` full/E2E 和全量门禁。Task1 L6 累计下降 `41.14%`；公共 `ambgfun` 以数值错误和无收益证据回退；公共 `mvdr` E2E 下降 `78.41%`。all81 `81/81`、dtype 缺口 0、14 步缺口 0，阶段关闭。
