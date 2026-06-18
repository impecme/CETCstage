#!/usr/bin/env bash
set -euo pipefail

VERSION="diagnostics-20260617-stage4-perf-full-v4"
BUILD_DIR="${BUILD_DIR:-build-zx}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
INSTALL_PYTHON_DEPS="${INSTALL_PYTHON_DEPS:-1}"
RESET_BUILD="${RESET_BUILD:-0}"

STAGE4_REPORT_ROOT="${STAGE4_REPORT_ROOT:-data/reports/zhongkexin/stage4}"
TASK_REPEAT="${TASK_REPEAT:-3}"
TASK_SCALES="${TASK_SCALES:-3}"
RUN_TASK_SWEEP="${RUN_TASK_SWEEP:-1}"

BENCH_MODULES="${BENCH_MODULES:-waveforms}"
BENCH_OPERATORS="${BENCH_OPERATORS:-all}"
BENCH_SCALE_PROFILE="${BENCH_SCALE_PROFILE:-default}"
BENCH_SCALE_LEVELS="${BENCH_SCALE_LEVELS:-3}"
BENCH_WARMUP="${BENCH_WARMUP:-1}"
BENCH_REPEAT="${BENCH_REPEAT:-3}"
BENCH_REPORT_MODE="${BENCH_REPORT_MODE:-concise}"
BENCH_OUTPUT_DIR="${BENCH_OUTPUT_DIR:-data/reports/unit/benchmarks/zhongkexin_stage4_pilot}"
RUN_BENCHMARK_PLOTS="${RUN_BENCHMARK_PLOTS:-1}"
PLOT_FORMATS="${PLOT_FORMATS:-png}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

echo "[zx-stage4] script version: ${VERSION}"
echo "[zx-stage4] build dir: ${BUILD_DIR}"
echo "[zx-stage4] task scales: ${TASK_SCALES}"
echo "[zx-stage4] run task sweep: ${RUN_TASK_SWEEP}"
echo "[zx-stage4] benchmark modules: ${BENCH_MODULES}"
echo "[zx-stage4] benchmark operators: ${BENCH_OPERATORS}"
echo "[zx-stage4] benchmark scale levels: ${BENCH_SCALE_LEVELS}"
echo "[zx-stage4] report root: ${STAGE4_REPORT_ROOT}"

run_logged() {
  local label="$1"
  local log_path="$2"
  shift 2
  if ! "$@" >"${log_path}" 2>&1; then
    echo "[zx-stage4] error: ${label} failed, log: ${log_path}" >&2
    tail -n 80 "${log_path}" >&2 || true
    exit 1
  fi
}

if [[ -f /zq500/sdk/env.sh ]]; then
  set +u
  # shellcheck source=/dev/null
  source /zq500/sdk/env.sh ""
  set -u
fi

prepare_args=(--ensure-fftw)
if [[ "${INSTALL_PYTHON_DEPS}" == "1" ]]; then
  prepare_args+=(--install-python)
fi
"${SCRIPT_DIR}/prepare_zhongkexin_deps.sh" "${prepare_args[@]}"

if [[ "${BUILD_DIR}" = /* ]]; then
  build_path="${BUILD_DIR}"
else
  build_path="${REPO_ROOT}/${BUILD_DIR}"
fi
if [[ "${RESET_BUILD}" == "1" ]]; then
  echo "[zx-stage4] resetting build dir: ${build_path}"
  rm -rf "${build_path}"
fi

if [[ ! -f "${build_path}/CMakeCache.txt" ]]; then
  zhongkexin_cxx="${ZHONGKEXIN_CXX_COMPILER:-}"
  if [[ -z "${zhongkexin_cxx}" ]]; then
    zhongkexin_cxx="$(command -v dlcc || true)"
  fi
  if [[ -z "${zhongkexin_cxx}" ]]; then
    echo "[zx-stage4] error: dlcc was not found for ZHONGKEXIN configure" >&2
    exit 2
  fi
  echo "[zx-stage4] configuring build dir: ${build_path}"
  cmake \
    -S "${REPO_ROOT}" \
    -B "${build_path}" \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
    -DCMAKE_CXX_COMPILER="${zhongkexin_cxx}"
fi

mkdir -p "${STAGE4_REPORT_ROOT}"
TASK_LOG="${STAGE4_REPORT_ROOT}/latest_task_scale_pilot.log"
BENCH_LOG="${STAGE4_REPORT_ROOT}/latest_operator_benchmark_pilot.log"
PLOT_LOG="${STAGE4_REPORT_ROOT}/latest_operator_benchmark_plot.log"
SUMMARY_JSON="${STAGE4_REPORT_ROOT}/latest_stage4_summary.json"
SUMMARY_MD="${STAGE4_REPORT_ROOT}/latest_stage4_summary.md"

if [[ "${RUN_TASK_SWEEP}" == "1" ]]; then
  echo "[zx-stage4] running Task1/Task2 scale sweep"
  run_logged "Task1/Task2 scale sweep" "${TASK_LOG}" \
    scripts/test/run_task_demos.sh \
    --build-dir "${BUILD_DIR}" \
    --build \
    --scale-sweep \
    --scales "${TASK_SCALES}" \
    --repeat "${TASK_REPEAT}" \
    --require-visualization-deps
else
  echo "[zx-stage4] skipping Task1/Task2 scale sweep"
  printf '[zx-stage4] skipped by RUN_TASK_SWEEP=0\n' >"${TASK_LOG}"
fi

echo "[zx-stage4] running operator benchmark pilot"
run_logged "operator benchmark" "${BENCH_LOG}" \
  python3 scripts/test/benchmark_all_ops_scales.py \
  --platform ZHONGKEXIN \
  --build-dir "${BUILD_DIR}" \
  --modules "${BENCH_MODULES}" \
  --operators "${BENCH_OPERATORS}" \
  --scale-profile "${BENCH_SCALE_PROFILE}" \
  --scale-levels "${BENCH_SCALE_LEVELS}" \
  --warmup "${BENCH_WARMUP}" \
  --repeat "${BENCH_REPEAT}" \
  --build \
  --output-dir "${BENCH_OUTPUT_DIR}" \
  --report-mode "${BENCH_REPORT_MODE}"

BENCH_CSV="${BENCH_OUTPUT_DIR}/latest_all_ops_scale_benchmark.csv"
FIGURE_DIR="${BENCH_OUTPUT_DIR}/figures"
plot_status="skipped"
if [[ "${RUN_BENCHMARK_PLOTS}" == "1" ]]; then
  echo "[zx-stage4] plotting operator benchmark"
  run_logged "operator benchmark plotting" "${PLOT_LOG}" \
    python3 scripts/test/plot_all_ops_benchmark.py \
    --csv "${BENCH_CSV}" \
    --output-dir "${FIGURE_DIR}" \
    --figure-set all \
    --formats "${PLOT_FORMATS}"
  plot_status="passed"
fi

python3 - \
  "${SUMMARY_JSON}" \
  "${SUMMARY_MD}" \
  "${VERSION}" \
  "${TASK_SCALES}" \
  "${TASK_LOG}" \
  "${BENCH_MODULES}" \
  "${BENCH_OPERATORS}" \
  "${BENCH_SCALE_LEVELS}" \
  "${BENCH_LOG}" \
  "${BENCH_CSV}" \
  "${plot_status}" \
  "${FIGURE_DIR}" <<'PY'
import csv
import json
import sys
from pathlib import Path

(
    summary_json,
    summary_md,
    version,
    task_scales,
    task_log,
    bench_modules,
    bench_operators,
    bench_scale_levels,
    bench_log,
    bench_csv,
    plot_status,
    figure_dir,
) = sys.argv[1:]

rows = []
csv_path = Path(bench_csv)
if csv_path.exists():
    with csv_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
failed_rows = [row for row in rows if str(row.get("status", "")).lower() != "passed"]

payload = {
    "pass": not failed_rows and bool(rows),
    "version": version,
    "task_scales": task_scales,
    "task_log": task_log,
    "benchmark_modules": bench_modules,
    "benchmark_operators": bench_operators,
    "benchmark_scale_levels": bench_scale_levels,
    "benchmark_log": bench_log,
    "benchmark_csv": bench_csv,
    "benchmark_rows": len(rows),
    "benchmark_failed_rows": len(failed_rows),
    "plot_status": plot_status,
    "figure_dir": figure_dir,
}
Path(summary_json).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = ["# Zhongkexin V4.4 Stage4 Pilot Summary", ""]
for key, value in payload.items():
    lines.append(f"- {key}: `{value}`")
Path(summary_md).write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"[zx-stage4] wrote {summary_json}")
print(f"[zx-stage4] wrote {summary_md}")

if not payload["pass"]:
    raise SystemExit(1)
PY

# Full expansion after pilot passes:
# TASK_SCALES=1,2,3,4,5,6 \
# BENCH_MODULES=all \
# BENCH_SCALE_LEVELS=1,2,3,4,5,6 \
# BENCH_WARMUP=5 \
# BENCH_REPEAT=30 \
# BENCH_REPORT_MODE=full \
# BENCH_OUTPUT_DIR=data/reports/unit/benchmarks/zhongkexin_stage4_full \
# scripts/platform/run_zhongkexin_stage4.sh 2>&1 | tee stage4_full.log

echo "[zx-stage4] PASS"
