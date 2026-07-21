#!/usr/bin/env bash
set -euo pipefail

# Execute the formal-PPT task scale protocol.  Unlike scripts/demo.sh
# --scale-sweep, this freezes every algorithmic parameter at its L6 setting
# and changes only input dimensions across L1...L6.

BUILD_DIR="build-zx"
REPEAT=7
DO_BUILD=1

usage() {
  cat <<'USAGE'
Usage: scripts/unified_scale_benchmark.sh [options]

Options:
  --build-dir DIR       Build directory (default: build-zx)
  --repeat N            Per-level repeat count, minimum 3 (default: 7)
  --build               Build task targets before running (default)
  --no-build            Reuse an existing build
  -h, --help            Show this help

The first repeat is a warm-up.  The exporter uses the median of remaining
repeats, validates every task run, and writes the canonical task
data/reports/demo/<task>/scales/L1...L6 reports.
USAGE
}

die() {
  echo "[unified-scale] error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      [[ $# -ge 2 ]] || die "--build-dir requires a value"
      BUILD_DIR="$2"
      shift 2
      ;;
    --repeat)
      [[ $# -ge 2 ]] || die "--repeat requires a value"
      REPEAT="$2"
      shift 2
      ;;
    --build)
      DO_BUILD=1
      shift
      ;;
    --no-build)
      DO_BUILD=0
      shift
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

[[ "${REPEAT}" =~ ^[1-9][0-9]*$ ]] || die "--repeat must be a positive integer"
(( REPEAT >= 3 )) || die "--repeat must be >= 3 so one warm-up can be excluded"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ -f /zq500/sdk/env.sh ]]; then
  set +u
  # shellcheck source=/dev/null
  source /zq500/sdk/env.sh ""
  set -u
fi

if [[ "${BUILD_DIR}" = /* ]]; then
  BUILD_PATH="${BUILD_DIR}"
else
  BUILD_PATH="${REPO_ROOT}/${BUILD_DIR}"
fi
if [[ "${DO_BUILD}" -eq 1 ]]; then
  "${SCRIPT_DIR}/build.sh" --build-dir "${BUILD_PATH}" \
    --target task1_radar_demo --target task2_features_demo
fi

TASK1_EXE="${BUILD_PATH}/demo/task1_radar/task1_radar_demo"
TASK2_EXE="${BUILD_PATH}/demo/task2_features/task2_features_demo"
[[ -x "${TASK1_EXE}" ]] || die "missing executable: ${TASK1_EXE}"
[[ -x "${TASK2_EXE}" ]] || die "missing executable: ${TASK2_EXE}"

REPORT_ROOT="${REPO_ROOT}/data/.reports_staging/demo"
GENERATED_ROOT="${REPO_ROOT}/data/generated/demo"
RAW_ROOT="${REPORT_ROOT}/formal_scales_raw_$(date +%Y%m%d_%H%M%S)_$$"
mkdir -p "${RAW_ROOT}"

capture_level() {
  local task="$1"
  local executable="$2"
  local level="$3"
  local source_dir="${REPORT_ROOT}/${task}"
  local destination_dir="${RAW_ROOT}/${task}/L${level}"
  echo "[unified-scale] ${task} L${level}: fixed L6 algorithm, repeat=${REPEAT}"
  "${executable}" --repeat "${REPEAT}" --scale-level "${level}" \
    --unified-scale-protocol --invalid-input-checks
  mkdir -p "${destination_dir}"
  local artifact
  shopt -s nullglob
  for artifact in "${source_dir}"/latest_*; do
    cp "${artifact}" "${destination_dir}/"
  done
  shopt -u nullglob
  [[ -f "${destination_dir}/latest_metrics.json" ]] || die "missing latest_metrics for ${task} L${level}"
  [[ -f "${GENERATED_ROOT}/${task}/input/scenario.json" ]] || die "missing scenario for ${task} L${level}"
  cp "${GENERATED_ROOT}/${task}/input/scenario.json" "${destination_dir}/input_scenario.json"
}

for level in 1 2 3 4 5 6; do
  capture_level "task1_radar" "${TASK1_EXE}" "${level}"
  capture_level "task2_features" "${TASK2_EXE}" "${level}"
done

python3 "${SCRIPT_DIR}/export_unified_scale_reports.py" \
  --source-root "${RAW_ROOT}" \
  --output-root "${REPO_ROOT}/data/reports/demo"

echo "[unified-scale] PASS: data/reports/demo/task{1,2}_*/scales/L1...L6"
