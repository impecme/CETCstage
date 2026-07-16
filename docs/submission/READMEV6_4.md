# V6.4 Task1 第一批交付文档

## 版本信息

- 当前状态：已技术收束。
- 对应计划：`docs/performance/v6_0/plans/V6_4_plan.md`。
- 基线：V6.1 Task1 L6 `7.19016 ms`。

## 保留优化

| 台账 | 内容 |
| --- | --- |
| V6-0045 | host template FFT cache |
| V6-0046/V6-0047 | Doppler transpose 与 fftshift 融合，更新步骤契约 |
| V6-0048 | CA-CFAR 行前缀并行化 |
| V6-0049 | final detection partial grid 上限 |
| V6-0057 | Task ambgfun 归一化输入 cache |
| V6-0058 | pulse 与 Doppler 双稳态 FFT plan |

V6.4 收束时 Task1 L6 为 `5.83322 ms`，相对 V6.1 下降 `18.87%`。

## 回退与止损

- 三槽 FFT plan、ambgfun 输入别名、跳过显存查询、detection 64/128 blocks、直接 2D H2D、event 复用和外层 sync 删除均未通过双档门禁。
- 命名 Doppler window cache 后续在 V6.5 再次验证失败，已永久停止。
- 阶段未达到 20%目标，不把后续 V6.5 收益回写为 V6.4 成果。

## 验证

- radartools 受影响算子 full、Task1 L1-L6 通过。
- all81 `81/81`，dtype 缺口 0，14 步 timing/accuracy 缺口 0。
- 逐候选证据见台账 V6-0044 至 V6-0060 对应仓库外归档。

## 完成判定

V6.4 技术收束；Task1 剩余 35%-50%累计目标和公共 ambgfun/mvdr 进入 V6.5。
