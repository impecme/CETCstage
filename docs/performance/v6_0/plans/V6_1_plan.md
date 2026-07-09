# V6.1 基线与平台探针计划

## 状态与目标

- 状态：待分析；进入条件：V5.5 已关闭，V6.0 总规划已建立。
- 当前日志状态：未在 `/home/usr_04/CETC_garbage/` 定位到本轮 `cetc_v6_0_01_02` 容器包、`task_l1_l6_repeat5.log` 或 `focus_operator_benchmark` 产物；待补充具体路径后记录实测结论。
- 目标：建立 Task1/Task2 L1-L6 repeat=5、all81 correctness、重点算子 L1-L6 benchmark 和 ZQ500 平台探针基线。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.1-01 | 日志取回与归档 | `/home/usr_04/CETC_garbage/v6_1_baseline_*` | 日志、CSV、JSON、探针输出均在仓库外，`data/reports/` 无新增中间文件 |
| V6.1-02 | Task1/Task2 基线 | L1-L6 scale report、14 步 step metrics | 2 个任务、14 个计算步骤全部 pass，计时和精度字段完整 |
| V6.1-03 | all81 correctness | all81 full correctness 日志和摘要 | 81/81 passed，失败 0 |
| V6.1-04 | 重点算子 benchmark | Task2/Task1 相关算子 L1-L6 CSV | 热点排序明确，能区分任务路径和独立算子热点 |
| V6.1-05 | 平台探针 | runtime/FFT/Graph/显存/manifest 校验 | CUDA Graph、FFT plan/cache、workspace 和 manifest 恢复状态有结论 |
| V6.1-06 | 基线台账 | `optimization_change_log.md` 记录 | V6.2/V6.4 的第一批优化对象有证据支持 |

## 基线命令

容器内执行，日志根目录必须在 `/tmp`；回传后放到仓库外垃圾目录。

```bash
cd /CETC
source /zq500/sdk/env.sh

OUT="/tmp/cetc_v6_1_baseline_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${OUT}/repo_snapshots"

scripts/test/run_task_demos.sh \
  --build-dir "${OUT}/build-zx-v6" \
  --build \
  --scale-sweep \
  --scales 1,2,3,4,5,6 \
  --repeat 5 \
  --require-visualization-deps \
  2>&1 | tee "${OUT}/task_l1_l6_repeat5.log"
cp -a data/reports/demo "${OUT}/repo_snapshots/demo_reports"

python3 scripts/test/benchmark_all_ops_scales.py \
  --platform ZHONGKEXIN \
  --build-dir "${OUT}/build-zx-v6" \
  --no-build \
  --modules filtering,correlate,spectral,wavelets,demod,estimation,peak_finding,radartools \
  --operators firfilter,correlate,spectrogram,cwt,fm_demod,kalman_filter,argrelmax,argrelextrema,pulse_compression,pulse_doppler,ca_cfar,cfar_alpha,ambgfun,mvdr \
  --operator-set all81 \
  --scale-levels 1,2,3,4,5,6 \
  --warmup 1 \
  --repeat 5 \
  --output-dir "${OUT}/focus_operator_benchmark" \
  --report-mode concise \
  2>&1 | tee "${OUT}/focus_operator_benchmark.log"
cp -a data/reports/unit "${OUT}/repo_snapshots/unit_reports_focus" || true

scripts/test/run_all_tests.sh \
  --case-set full \
  --demo-fast \
  --emit-report \
  --build-dir "${OUT}/build-zx-v6" \
  --platform ZHONGKEXIN \
  2>&1 | tee "${OUT}/all81_full_correctness.log"
cp -a data/reports/unit "${OUT}/repo_snapshots/unit_reports_correctness" || true

find data/generated/unit -name manifest.json -print0 | sort -z | xargs -0 sha256sum \
  > "${OUT}/unit_manifest_sha_after.txt"

rm -rf data/reports/demo data/reports/unit data/generated/demo
find data/generated/unit -type d \( -name input -o -name output_samples \) -prune -exec rm -rf {} +
tar -czf "${OUT}.tgz" -C /tmp "$(basename "${OUT}")"
echo "${OUT}.tgz"
```

宿主机归档：

```bash
mkdir -p /home/usr_04/CETC_garbage/v6_1_baseline
tar -xzf /path/to/cetc_v6_1_baseline_*.tgz -C /home/usr_04/CETC_garbage/v6_1_baseline
```

## 分析口径

- Task 热点按 L6 GPU total、L5/L6 单步耗时和 14 步占比排序。
- Task2 第一批只从 `spectrogram/cwt/correlate` 里选第一个可执行热点。
- Task1 第一批只从 `pulse_compression/pulse_doppler/ca_cfar` 里选第一个可执行热点；`ambgfun` 先做 full surface 约束判断。
- correctness 未通过时不记录性能收益。
- CUDA Graph 探针失败不阻断 V6；结论转为手工 fusion/workspace resident 路线。

## 回传与关闭条件

用户回传 `/home/usr_04/CETC_garbage/v6_1_baseline*/` 下日志、CSV、JSON。关闭条件：任务 L1-L6 全通过、all81 81/81、dtype 缺口仍为 0、manifest 恢复无差异、热点排序和下一阶段优化对象写入台账。
