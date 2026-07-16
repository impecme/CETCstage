# V6.2 Task2 主热点第一批计划

## 状态与目标

- 状态：已技术收束。保留 V6-0026 CWT shared-halo 和 V6-0033 correlate shared tile，L6 `76.0695 -> 53.4843 ms`，累计下降 29.69%，距 30%目标差 0.31 个百分点；spectrogram 与 CWT 后续候选连续止损，不降低门禁、不伪报达标，转 V6.3 filter/execution plan。
- 目标：按实测占比依次优化 Task2 L5/L6 的 `cwt -> spectrogram -> correlate`，累计至少让 Task2 L6 GPU total 下降 30%。
- V6-0026 当前 L6 预算：spectrogram/CWT/correlate 为 `50.5303/57.6454 ms`，占 87.7%；阶段建议目标仍为 CWT >=60%、spectrogram >=60%、correlate >=40%。
- 阶段交付：`docs/submission/READMEV6_2.md`，记录 29.69% 技术收束和未达目标说明。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.2-00 | correctness 前置 | V6-0208R 全门禁日志 | 已通过：Task2 L1-L6、all81 `81/81`、dtype 缺口 0、14 步完整 |
| V6.2-01 | 热点拆解 | 三步骤 L1-L6 stage/step/operator 对照 | 明确第一改动点和保留/暂缓候选 |
| V6.2-02 | `cwt_score` 第一热点 | prepare/kernel/normalize 分解；shared halo、FFT/fCWT、downsampled wavelet 三路 probe | cwt step 误差通过；选中路径 L5/L6 目标下降 >=60% |
| V6.2-03 | `spectrogram` 第二热点 | 全 frame batched segment/R2C/band reduce，并复用同一结果生成代表帧 | spectrogram step 误差通过；L5/L6 目标下降 >=60% |
| V6.2-04 | `correlate_score` 第三热点 | true FFT/auto 与 tiled direct 阈值；必要时再评估 overlap-save | score 与原报告一致；L5/L6 目标下降 >=40% |
| V6.2-05 | Task2 L1-L6 回归 | repeat=3 和 repeat=5 任务报告 | 8 个 Task2 计算步骤计时/精度不丢，failure_count=0 |

## 执行规则

- 每次只改一个公共算子或一个 task helper 公共 fused operator。
- 不改变现有 `spectrogram`、`cwt`、`correlate` 公共 API 语义；任务路径可新增 score-only 公共接口。
- 完整矩阵输出只保留代表帧/报告校验；任务默认不得落无用全量中间矩阵。
- 先复用已有公共 batched R2C/FFT 能力，再决定是否增加 task 私有 kernel；公共 `correlate(method="fft")` 最终必须真正选择 FFT 路径。
- CWT 先测 shared halo，若算术量仍主导再进入 FFT/fCWT；不得直接同时实现三套完整路径。
- fCWT、overlap-save、FFT auto threshold 失败要登记为 `暂缓`，不能重复试探。
- 单 stage 收益低于 5%且 Task2 total 低于 2%，连续三轮后停止；L1/L2 退化超过 10%则增加 shape threshold。

## 单热点验证模板

```bash
cd /CETC
source /zq500/sdk/env.sh
set -u -o pipefail

MODULE="${MODULE:-wavelets}"
OPERATOR="${OPERATOR:-cwt}"
CANDIDATE="${CANDIDATE:-cwt_probe}"
OUT="/tmp/cetc_v6_2_${CANDIDATE}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT}"

scripts/test/run_all_tests.sh \
  --platform ZHONGKEXIN \
  --module "${MODULE}" \
  --operator "${OPERATOR}" \
  --case-set full \
  --warmup 1 \
  --repeat 3 \
  --build-dir build-zx \
  --emit-report \
  2>&1 | tee "${OUT}/operator_full.log"
OP_RC=${PIPESTATUS[0]}

scripts/test/run_task_demos.sh \
  --build-dir build-zx \
  --no-build \
  --scale-sweep \
  --scales 1,2,3,4,5,6 \
  --repeat 3 \
  --require-visualization-deps \
  2>&1 | tee "${OUT}/task_l1_l6_repeat3.log"
TASK_RC=${PIPESTATUS[0]}

printf 'operator=%s\ntask=%s\n' "${OP_RC}" "${TASK_RC}" > "${OUT}/statuses.txt"
cp -a data/reports/unit data/reports/demo "${OUT}/" 2>/dev/null || true
rm -rf data/reports/unit data/reports/demo data/generated/demo
tar -czf "${OUT}.tgz" -C /tmp "$(basename "${OUT}")"
```

## 回传与关闭条件

回传单算子 full、Task2 L3 smoke、Task2 L1-L6 repeat=3、阶段收口 repeat=5 日志。关闭条件：当前源码 correctness 通过，Task2 L6 GPU total 相比 V6.1 同源码暖基线下降至少 30%，三项合计达到可解释的算法级收益，all81 correctness 不破坏。
