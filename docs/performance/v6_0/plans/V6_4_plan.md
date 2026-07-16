# V6.4 Task1 第一批计划

## 状态与目标

- 状态：已技术收束。保留 V6-0045/V6-0046/V6-0048/V6-0049/V6-0057/V6-0058；V6.1 L6 `7.19016 -> 5.83322 ms`，累计下降 18.87%，低于 20%目标 1.13 个百分点；连续 L6 反向候选按止损停止。
- 目标：先消除 Task1 FFT plan 抖动和模板重复准备，再优化 `pulse_compression/pulse_doppler/power_map/ca_cfar/final_detection` device-resident 链路，使 Task1 L6 GPU total 相比 V6.1 同源码基线至少下降 20%。
- 旧部署 L6 预算：pulse compression、pulse Doppler、CFAR 合计 `6.106/7.463 ms`，占 81.8%；阶段建议目标分别为 >=50%、>=35%、>=35%。
- 阶段交付：`docs/submission/READMEV6_4.md`，仅记录 V6.4 收束时的 18.87%累计收益。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.4-01 | FFT/handle 分解 | 每次任务的 plan create/destroy/hit/miss、template prepare、handle init 计数 | 证明固定开销位置，不只看总时间 |
| V6.4-02 | multi-key FFT plan | template、pulse batch、Doppler 按 type/nfft/batch/layout/stream 缓存 | 稳态任务不再因 batch 切换重建 plan；有界 cache 不导致显存失控 |
| V6.4-03 | `pulse_compression` 模板缓存 | window key、norm、device template 和 template spectrum 复用；拆除无关 cuSOLVER 初始化 | error 不回退；L5/L6 目标下降 >=50% |
| V6.4-04 | `pulse_doppler` | 转置/layout 探针，Doppler FFT 后 shift/power 候选融合 | `pulse_doppler` 与 `power_map` 字段保留；L6 目标下降 >=35% |
| V6.4-05 | `ca_cfar` 探针 | exact Task1 shape 下比较 naive shared、sliding window、prefix/SAT | 阈值误差和 peak 一致；L6 目标下降 >=35% |
| V6.4-06 | detection device resident | mask、peak、最终标量回传；复用已上传 template 给 ambgfun | final_detection 精度和业务 gate 通过，H2D 次数下降 |

## 执行规则

- Task1 首批不改变 `ambgfun` 语义，避免 full surface 约束混入 CFAR 链路。
- `PulseWorkspace` 不再用一个 plan 槽覆盖 `(nfft,1)`、`(nfft,num_pulses)` 和 `(doppler_nfft,samples)`；先关闭该问题再做 kernel 微调。
- 模板 cache key 至少包含指针/内容版本、长度、nfft、window 和 normalize；命中错误比重算更危险，必须有 cache invalidation 单测。
- CFAR 不预设 SAT 最优；按窗口半径、map 尺寸和显存读写实测选择。
- 当前 SAT 的 column-prefix 已按列并行并保持跨列合并访问；V6-0048 只处理每行单线程的 row-prefix，避免为列方向增加 block 数和跨行 stride 访问。
- 若融合 `fftshift + power_map`，任务报告必须保留两个步骤的独立计时字段。
- 单 stage 收益低于 5%且 Task1 total 低于 2%时停止该候选；L1/L2 退化超过 10%时增加 shape threshold。

## 回传与关闭条件

回传 plan/cache 计数、`radartools` 受影响算子 full、Task1 L3 smoke、Task1 L1-L6 repeat=3/5。关闭条件：Task1 L6 pipeline wall 相比 V6.1 同源码暖基线下降至少 20%，三项合计下降明确，14 步报告完整。
