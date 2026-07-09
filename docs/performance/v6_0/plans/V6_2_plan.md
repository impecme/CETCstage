# V6.2 Task2 主热点第一批计划

## 状态与目标

- 状态：待开始；进入条件：V6.1 基线关闭。
- 目标：优先优化 Task2 L5/L6 的 `spectrogram + cwt + correlate`，累计至少让 Task2 L6 GPU total 下降 30%。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.2-01 | 热点拆解 | 三步骤 L1-L6 stage/step/operator 对照 | 明确第一改动点和保留/暂缓候选 |
| V6.2-02 | `correlate_score` 候选 | direct/FFT/overlap-save 阈值探针 | score 与原 correlate 报告一致，L5/L6 不退化 |
| V6.2-03 | `spectrogram` score-only | segment/window/R2C/reduce 融合路径 | spectrogram step 误差通过，L5/L6 至少下降 40% |
| V6.2-04 | `cwt_score` 候选 | wavelet cache、fCWT 式尺度复用、abs/reduce 融合 | cwt step 误差通过，L5/L6 至少下降 50% |
| V6.2-05 | Task2 L1-L6 回归 | repeat=3 和 repeat=5 任务报告 | 8 个 Task2 计算步骤计时/精度不丢，failure_count=0 |

## 执行规则

- 每次只改一个公共算子或一个 task helper 公共 fused operator。
- 不改变现有 `spectrogram`、`cwt`、`correlate` 公共 API 语义；任务路径可新增 score-only 公共接口。
- 完整矩阵输出只保留代表帧/报告校验；任务默认不得落无用全量中间矩阵。
- fCWT、overlap-save、FFT auto threshold 失败要登记为 `暂缓`，不能重复试探。

## 单热点验证模板

```bash
cd /CETC
source /zq500/sdk/env.sh

scripts/test/run_all_tests.sh \
  --platform ZHONGKEXIN \
  --module <module> \
  --operator <operator> \
  --case-set full \
  --warmup 1 \
  --repeat 3 \
  --build-dir build-zx \
  --emit-report

scripts/test/run_task_demos.sh \
  --build-dir build-zx \
  --no-build \
  --scale-sweep \
  --scales 1,2,3,4,5,6 \
  --repeat 3 \
  --require-visualization-deps
```

## 回传与关闭条件

回传单算子 full、Task2 L3 smoke、Task2 L1-L6 repeat=3、阶段收口 repeat=5 日志。关闭条件：Task2 L6 GPU total 下降至少 30%，`spectrogram/cwt/correlate` 三项合计下降趋势明确，all81 correctness 不破坏。
