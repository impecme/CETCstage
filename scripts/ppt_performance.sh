#!/usr/bin/env bash

set -euo pipefail

# Run the presentation-facing measurements, then print the three operator
# tiers and/or the two formal task-scale tables in the terminal.

BUILD_DIR="build-zx"
RUN_OPERATORS=1
RUN_TASKS=1
PRINT_ONLY=0
DO_BUILD=1
DEMO_FAST=0
LIVE_DEMO=0
OPERATOR_SET="all81"
OPERATOR_CASE_SET="full"
OPERATOR_WARMUP=5
OPERATOR_REPEAT=30
TASK_REPEAT=7
OPERATOR_SET_EXPLICIT=0
OPERATOR_CASE_SET_EXPLICIT=0
OPERATOR_WARMUP_EXPLICIT=0
OPERATOR_REPEAT_EXPLICIT=0
TASK_REPEAT_EXPLICIT=0

usage() {
  cat <<'USAGE'
Usage: scripts/ppt_performance.sh [options]

With no options, build once, measure all 81 operators and formal Task1/Task2
L1-L6 scales, then print the result tables in the terminal.

Options:
  --operators              Only measure and print task27/extended28/core53.
  --tasks                  Only measure and print Task1/Task2 L1-L6.
  --all                    Measure and print both categories (default).
  --print-only             Do not measure; print current published reports.
  --demo-fast              Demo preset: demo_top30 operators, perf cases, warmup=1, repeat=3.
  --live-demo              Live preset: core53 perf cases (warmup=1, repeat=1) plus
                           each task's highest-speedup formal scale (repeat=1). Results
                           are collected in staging, then snapshotted into existing reports/
                           units and reports/demo; only core53 and two task rows are printed.
  --operator-set NAME      Operator set from tests/contracts/operator_sets.json (default: all81).
  --operator-case-set NAME Operator case set: smoke|accuracy|perf|full (default: full).
  --build-dir DIR          Build directory (default: build-zx).
  --no-build               Reuse existing binaries.
  --operator-warmup N      Operator warm-up iterations (default: 5).
  --operator-repeat N      Operator repeats (default: 30).
  --task-repeat N          Task repeats including one warm-up (default: 7).
  -h, --help               Show this help.

Examples:
  /CETC/scripts/ppt_performance.sh
  /CETC/scripts/ppt_performance.sh --operators --no-build
  /CETC/scripts/ppt_performance.sh --tasks --no-build
  /CETC/scripts/ppt_performance.sh --print-only
  /CETC/scripts/ppt_performance.sh --operators --demo-fast --no-build
  /CETC/scripts/ppt_performance.sh --live-demo --no-build
USAGE
}

die() {
  echo "[ppt-performance] error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --operators)
      RUN_OPERATORS=1
      RUN_TASKS=0
      shift
      ;;
    --tasks)
      RUN_OPERATORS=0
      RUN_TASKS=1
      shift
      ;;
    --all)
      RUN_OPERATORS=1
      RUN_TASKS=1
      shift
      ;;
    --print-only)
      PRINT_ONLY=1
      shift
      ;;
    --demo-fast)
      DEMO_FAST=1
      shift
      ;;
    --live-demo)
      LIVE_DEMO=1
      shift
      ;;
    --operator-set)
      [[ $# -ge 2 ]] || die "--operator-set requires a value"
      OPERATOR_SET="$2"
      OPERATOR_SET_EXPLICIT=1
      shift 2
      ;;
    --operator-case-set)
      [[ $# -ge 2 ]] || die "--operator-case-set requires a value"
      OPERATOR_CASE_SET="$2"
      OPERATOR_CASE_SET_EXPLICIT=1
      shift 2
      ;;
    --build-dir)
      [[ $# -ge 2 ]] || die "--build-dir requires a value"
      BUILD_DIR="$2"
      shift 2
      ;;
    --no-build)
      DO_BUILD=0
      shift
      ;;
    --operator-warmup)
      [[ $# -ge 2 ]] || die "--operator-warmup requires a value"
      OPERATOR_WARMUP="$2"
      OPERATOR_WARMUP_EXPLICIT=1
      shift 2
      ;;
    --operator-repeat)
      [[ $# -ge 2 ]] || die "--operator-repeat requires a value"
      OPERATOR_REPEAT="$2"
      OPERATOR_REPEAT_EXPLICIT=1
      shift 2
      ;;
    --task-repeat)
      [[ $# -ge 2 ]] || die "--task-repeat requires a value"
      TASK_REPEAT="$2"
      TASK_REPEAT_EXPLICIT=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ "${LIVE_DEMO}" -eq 1 && "${PRINT_ONLY}" -eq 1 ]]; then
  die "--live-demo cannot be combined with --print-only"
fi
if [[ "${LIVE_DEMO}" -eq 1 && "${DEMO_FAST}" -eq 1 ]]; then
  die "--live-demo cannot be combined with --demo-fast"
fi

if [[ "${LIVE_DEMO}" -eq 1 ]]; then
  RUN_OPERATORS=1
  RUN_TASKS=1
  [[ "${OPERATOR_SET_EXPLICIT}" -eq 1 ]] || OPERATOR_SET="core53"
  [[ "${OPERATOR_CASE_SET_EXPLICIT}" -eq 1 ]] || OPERATOR_CASE_SET="perf"
  [[ "${OPERATOR_WARMUP_EXPLICIT}" -eq 1 ]] || OPERATOR_WARMUP=1
  [[ "${OPERATOR_REPEAT_EXPLICIT}" -eq 1 ]] || OPERATOR_REPEAT=1
  [[ "${TASK_REPEAT_EXPLICIT}" -eq 1 ]] || TASK_REPEAT=1
fi

if [[ "${DEMO_FAST}" -eq 1 ]]; then
  [[ "${OPERATOR_SET_EXPLICIT}" -eq 1 ]] || OPERATOR_SET="demo_top30"
  [[ "${OPERATOR_CASE_SET_EXPLICIT}" -eq 1 ]] || OPERATOR_CASE_SET="perf"
  [[ "${OPERATOR_WARMUP_EXPLICIT}" -eq 1 ]] || OPERATOR_WARMUP=1
  [[ "${OPERATOR_REPEAT_EXPLICIT}" -eq 1 ]] || OPERATOR_REPEAT=3
  [[ "${TASK_REPEAT_EXPLICIT}" -eq 1 ]] || TASK_REPEAT=3
fi

[[ "${OPERATOR_WARMUP}" =~ ^[0-9]+$ ]] || die "--operator-warmup must be a non-negative integer"
[[ "${OPERATOR_REPEAT}" =~ ^[1-9][0-9]*$ ]] || die "--operator-repeat must be a positive integer"
[[ "${TASK_REPEAT}" =~ ^[1-9][0-9]*$ ]] || die "--task-repeat must be a positive integer"
if [[ "${LIVE_DEMO}" -eq 0 ]]; then
  (( TASK_REPEAT >= 3 )) || die "--task-repeat must be >= 3 so one warm-up can be excluded"
fi
case "${OPERATOR_CASE_SET}" in
  smoke|accuracy|perf|full) ;;
  *) die "--operator-case-set must be one of: smoke, accuracy, perf, full" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [[ -f /zq500/sdk/env.sh ]]; then
  set +u
  # shellcheck source=/dev/null
  source /zq500/sdk/env.sh ""
  set -u
fi

if [[ "${PRINT_ONLY}" -eq 0 && "${DO_BUILD}" -eq 1 ]]; then
  "${SCRIPT_DIR}/build.sh" --build-dir "${BUILD_DIR}"
fi

if [[ "${PRINT_ONLY}" -eq 0 && "${RUN_OPERATORS}" -eq 1 ]]; then
  "${SCRIPT_DIR}/test_operators.sh" \
    --build-dir "${BUILD_DIR}" \
    --no-build \
    --operator-set "${OPERATOR_SET}" \
    --case-set "${OPERATOR_CASE_SET}" \
    --warmup "${OPERATOR_WARMUP}" \
    --repeat "${OPERATOR_REPEAT}" \
    --emit-report
fi

if [[ "${PRINT_ONLY}" -eq 0 && "${RUN_TASKS}" -eq 1 ]]; then
  if [[ "${LIVE_DEMO}" -eq 1 ]]; then
    task_level_for_highest_speedup() {
      local task="$1"
      python3 - "${PROJECT_ROOT}" "${task}" <<'PY'
import json
import math
import sys
from pathlib import Path

root = Path(sys.argv[1])
task = sys.argv[2]
best = None
for level in range(1, 7):
    path = root / "data" / "reports" / "demo" / task / "scales" / f"L{level}" / "metrics.json"
    try:
        metrics = json.loads(path.read_text(encoding="utf-8"))
        scenario = metrics["scenario"]
        speedup = float(metrics["speedup"]["cpu_over_gpu"])
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"cannot select live-demo scale from {path}: {error}")
    if scenario.get("unified_scale_protocol") is not True or not math.isfinite(speedup):
        raise SystemExit(f"invalid formal scale report: {path}")
    candidate = (speedup, level)
    if best is None or candidate > best:
        best = candidate

assert best is not None
print(best[1])
PY
    }

    TASK1_LEVEL="$(task_level_for_highest_speedup task1_radar)"
    TASK2_LEVEL="$(task_level_for_highest_speedup task2_features)"
    if [[ "${BUILD_DIR}" = /* ]]; then
      BUILD_PATH="${BUILD_DIR}"
    else
      BUILD_PATH="${PROJECT_ROOT}/${BUILD_DIR}"
    fi
    TASK1_EXE="${BUILD_PATH}/demo/task1_radar/task1_radar_demo"
    TASK2_EXE="${BUILD_PATH}/demo/task2_features/task2_features_demo"
    [[ -x "${TASK1_EXE}" ]] || die "missing executable: ${TASK1_EXE}"
    [[ -x "${TASK2_EXE}" ]] || die "missing executable: ${TASK2_EXE}"

    echo "[ppt-performance] live-demo task1_radar: selected highest formal speedup L${TASK1_LEVEL}"
    "${TASK1_EXE}" --repeat "${TASK_REPEAT}" --scale-level "${TASK1_LEVEL}" \
      --unified-scale-protocol --invalid-input-checks
    echo "[ppt-performance] live-demo task2_features: selected highest formal speedup L${TASK2_LEVEL}"
    "${TASK2_EXE}" --repeat "${TASK_REPEAT}" --scale-level "${TASK2_LEVEL}" \
      --unified-scale-protocol --invalid-input-checks
  else
    "${SCRIPT_DIR}/unified_scale_benchmark.sh" \
      --build-dir "${BUILD_DIR}" \
      --no-build \
      --repeat "${TASK_REPEAT}"
  fi
fi

report_args=()
if [[ "${RUN_OPERATORS}" -eq 1 ]]; then
  report_args+=(--operators)
  report_args+=(--operator-set "${OPERATOR_SET}")
  if [[ "${PRINT_ONLY}" -eq 1 ]]; then
    report_args+=(--operator-source published)
  else
    report_args+=(--operator-source staging)
  fi
fi
if [[ "${RUN_TASKS}" -eq 1 ]]; then
  report_args+=(--tasks)
  if [[ "${LIVE_DEMO}" -eq 1 ]]; then
    report_args+=(--task-source staging)
  fi
fi
if [[ "${LIVE_DEMO}" -eq 1 ]]; then
  report_args+=(--write-live-reports)
fi

python3 "${SCRIPT_DIR}/ppt_performance.py" "${report_args[@]}"
