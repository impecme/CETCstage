# V6.1 基线与平台探针计划

## 状态与目标

- 状态：已关闭。Task1/Task2 当前源码基线、all81、dtype、14 步、Release flags、device/runtime/stream/FFT/Graph 和 manifest 均已有归档结论。
- 当前证据：V6-0208R 关闭 Task2 基线和全量 correctness；V6-0035 关闭 Task1 L1-L6/repeat=5、Release flags、device、stream、FFT 和 manifest，L6 repeat=5 total 为 `7.19016 ms`。V6-0036 的 Graph probe 因资源生命周期错误产生假阴性；V6-0098 在有效 stream/device buffer 上确认 capture begin/work/end、instantiate、launch、sync 六阶段状态均为 0，结论修正为 `supported`，不改变既有性能分母。
- 目标：先关闭当前源码 correctness，再建立 Task1/Task2 L1-L6 冷/暖基线、all81 correctness、重点算子 benchmark 和 ZQ500 编译/runtime/stream/FFT 探针。
- 阶段交付：`docs/submission/READMEV6_1.md`，已按基线和平台证据关闭。

## 工作包

| ID | 工作包 | 交付物 | 关闭条件 |
| --- | --- | --- | --- |
| V6.1-01 | 日志取回与归档 | `/home/usr_04/CETC_garbage/v6_1_baseline_*` | 日志、CSV、JSON、探针输出均在仓库外，`data/reports/` 无新增中间文件 |
| V6.1-02 | 分段 correctness | Task2 L3 -> L5 -> L6、Task1 L3/L6 | 先小规模定位；stdout/stderr、退出码和失败报告完整 |
| V6.1-03 | all81 correctness | all81 full correctness 日志和摘要 | 81/81 passed，失败 0 |
| V6.1-04 | Task1/Task2 基线 | L1-L6 repeat=3，收口 repeat=5 | 14 步、setup、pipeline wall、cold/warm 和显存高水位完整 |
| V6.1-05 | 重点算子 benchmark | Task2/Task1 相关算子 L1-L6 CSV | 热点排序明确，能区分任务路径和公共算子热点 |
| V6.1-06 | 平台探针 | verbose compile、device props、stream/concurrent kernel、FFT plan/cache、manifest | 每项有 supported/limited/unsupported 结论；Graph 只做一次低优先级探针 |
| V6.1-07 | 基线台账 | `optimization_change_log.md` 记录 | V6.2/V6.4 的第一批优化对象有同源码证据支持 |

## 基线命令

容器内执行。先分段 correctness，再跑全规模和 all81；日志根目录在 `/tmp`，build 不打进归档。每个命令保留 stderr 和真实退出码。

```bash
cd /CETC
source /zq500/sdk/env.sh
set -u -o pipefail

OUT="/tmp/cetc_v6_1_baseline_$(date +%Y%m%d_%H%M%S)"
BUILD="/CETC/build-zx"
mkdir -p "${OUT}/repo_snapshots" "${OUT}/fingerprint"
: > "${OUT}/statuses.txt"

run_logged() {
  local name="$1"
  shift
  "$@" 2>&1 | tee "${OUT}/${name}.log"
  local rc=${PIPESTATUS[0]}
  printf '%s=%s\n' "${name}" "${rc}" | tee -a "${OUT}/statuses.txt"
  return "${rc}"
}

snapshot_reports() {
  local name="$1"
  mkdir -p "${OUT}/repo_snapshots/${name}"
  cp -a data/reports/demo "${OUT}/repo_snapshots/${name}/" 2>/dev/null || true
  cp -a data/reports/unit "${OUT}/repo_snapshots/${name}/" 2>/dev/null || true
}

git rev-parse HEAD > "${OUT}/fingerprint/git_head.txt"
git status --short > "${OUT}/fingerprint/git_status.txt"
git diff -- demo/task2_features/task2_features_zx_gpu.cu \
  docs/performance/v6_0/optimization_change_log.md \
  > "${OUT}/fingerprint/target_diff.patch"
sha256sum CMakeLists.txt \
  demo/task1_radar/task1_radar_demo.cpp \
  demo/task2_features/task2_features_demo.cpp \
  demo/task2_features/task2_features_zx_gpu.cu \
  src/zhongkexin/radartools.cu \
  > "${OUT}/fingerprint/source_sha256.txt"

run_logged configure cmake -S . -B "${BUILD}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_CXX_COMPILER="$(command -v dlcc)"
run_logged build cmake --build "${BUILD}" \
  --target task1_radar_demo task2_features_demo --parallel --verbose
cp "${BUILD}/CMakeCache.txt" "${OUT}/fingerprint/"
cp "${BUILD}/compile_commands.json" "${OUT}/fingerprint/"

TASK2="${BUILD}/demo/task2_features/task2_features_demo"
TASK1="${BUILD}/demo/task1_radar/task1_radar_demo"
TASK2_OK=0
TASK2_L3_OK=0
if run_logged task2_l3 "${TASK2}" --repeat 3 --scale-level 3 --invalid-input-checks; then
  TASK2_L3_OK=1
fi
snapshot_reports task2_l3
if [[ "${TASK2_L3_OK}" -eq 1 ]]; then
  if run_logged task2_l5 "${TASK2}" --repeat 3 --scale-level 5 --invalid-input-checks && \
     run_logged task2_l6 "${TASK2}" --repeat 3 --scale-level 6 --invalid-input-checks; then
    TASK2_OK=1
  fi
fi
snapshot_reports task2_l5_l6

run_logged task1_l3 "${TASK1}" --repeat 3 --scale-level 3 --invalid-input-checks || true
run_logged task1_l6 "${TASK1}" --repeat 3 --scale-level 6 --invalid-input-checks || true
snapshot_reports task1_l3_l6

if [[ "${TASK2_OK}" -eq 1 ]]; then
  run_logged task_l1_l6_repeat3 scripts/test/run_task_demos.sh \
    --build-dir "${BUILD}" --no-build --scale-sweep \
    --scales 1,2,3,4,5,6 --repeat 3 --require-visualization-deps
  snapshot_reports task_l1_l6_repeat3

  ALL81_OK=0
  if run_logged all81_full_correctness scripts/test/run_all_tests.sh \
    --case-set full --demo-fast --emit-report \
    --build-dir "${BUILD}" --platform ZHONGKEXIN; then
    ALL81_OK=1
  fi
  snapshot_reports all81_full_correctness
  if [[ "${ALL81_OK}" -eq 1 ]]; then
    run_logged focus_operator_benchmark \
      python3 scripts/test/benchmark_all_ops_scales.py \
      --platform ZHONGKEXIN --build-dir "${BUILD}" --no-build \
      --modules filtering,correlate,spectral,wavelets,demod,estimation,peak_finding,radartools \
      --operators firfilter,correlate,spectrogram,cwt,fm_demod,kalman_filter,argrelmax,argrelextrema,pulse_compression,pulse_doppler,ca_cfar,cfar_alpha,ambgfun,mvdr \
      --scale-levels 1,2,3,4,5,6 --warmup 2 --repeat 5 \
      --output-dir "${OUT}/focus_operator_benchmark" --report-mode concise
  fi
fi

find data/generated/unit -name manifest.json -print0 | sort -z | xargs -0 sha256sum \
  > "${OUT}/unit_manifest_sha_after.txt"

rm -rf data/reports/demo data/reports/unit data/generated/demo
find data/generated/unit -type d \( -name input -o -name output_samples \) -prune -exec rm -rf {} +
tar -czf "${OUT}.tgz" -C /tmp "$(basename "${OUT}")"
echo "${OUT}.tgz"
```

## 平台探针要求

| Probe | 必须输出 | 用途 |
|---|---|---|
| device/runtime | device 名称、显存、`concurrentKernels`、async engine、stream/event API 结果 | 决定 V6.3 是否并行四分支 |
| FFT | create/destroy、相同 key 复用、不同 batch 切换、`cufftSetStream`、workspace bytes | 决定 V6.2/V6.4 plan/cache 和多 stream 路线 |
| memory | cold/warm allocation、cache hit/miss、GPU/RSS current 与 high-water | 防止只看 first/last 漏掉首次增长 |
| build | verbose compile、`CMAKE_CXX_FLAGS_RELEASE`、目标源 SHA | 证明优化级别和日志源码一致 |
| Graph | 最小 capture/launch 支持结果 | 低优先级；失败不阻断 V6 |

宿主机归档：

```bash
mkdir -p /home/usr_04/CETC_garbage/v6_1_baseline
tar -xzf /path/to/cetc_v6_1_baseline_*.tgz -C /home/usr_04/CETC_garbage/v6_1_baseline
```

## 分析口径

- Task 热点按 L6 pipeline wall、L5/L6 单步耗时和 14 步占比排序；setup/validation 另列，不能藏在计时外。
- Task2 第一批顺序固定为 correctness、`cwt`、`spectrogram`、`correlate`；缓存类小改动不替代算法级目标。
- Task1 第一批只从 `pulse_compression/pulse_doppler/ca_cfar` 里选第一个可执行热点；`ambgfun` 先做 full surface 约束判断。
- correctness 未通过时不记录性能收益。
- 基线必须区分 cold=1 与 warm，记录 median/p95、GPU/RSS 高水位、plan create/hit/miss、copy/allocation 和源码 fingerprint。
- CUDA Graph 探针失败不阻断 V6；先验证 stream、workspace 和 plan，不让 Graph 阻塞主线。

## 回传与关闭条件

用户回传 `/home/usr_04/CETC_garbage/v6_1_baseline*/` 下日志、CSV、JSON。关闭条件：当前源码任务 L1-L6 全通过、all81 81/81、dtype 缺口仍为 0、manifest 恢复无差异、verbose compile 与平台探针已归档、热点排序和下一阶段优化对象写入台账。repeat=5 只在该基线收口时执行。
