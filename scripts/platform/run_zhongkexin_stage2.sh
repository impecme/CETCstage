#!/usr/bin/env bash
set -euo pipefail

VERSION="diagnostics-20260616-stage2-deps-v5"
BUILD_DIR="${BUILD_DIR:-build-zx}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
REPEAT="${REPEAT:-3}"
OP_CASE_SET="${OP_CASE_SET:-accuracy}"
RUN_OPERATOR_TESTS="${RUN_OPERATOR_TESTS:-1}"
RUN_SCALE_SWEEP="${RUN_SCALE_SWEEP:-1}"
RUN_SCALE_ON_OPERATOR_FAILURE="${RUN_SCALE_ON_OPERATOR_FAILURE:-0}"
STAGE2_SCALES="${STAGE2_SCALES:-3}"
INSTALL_PYTHON_DEPS="${INSTALL_PYTHON_DEPS:-1}"
STAGE2_REPORT_ROOT="${STAGE2_REPORT_ROOT:-data/reports/zhongkexin/stage2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

echo "[zx-stage2] script version: ${VERSION}"
echo "[zx-stage2] build dir: ${BUILD_DIR}"
echo "[zx-stage2] operator case set: ${OP_CASE_SET}"
echo "[zx-stage2] task demo scales: ${STAGE2_SCALES}"

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
echo "[zx-stage2] resetting build dir: ${build_path}"
rm -rf "${build_path}"

mkdir -p "${STAGE2_REPORT_ROOT}/operators"
OPERATOR_CSV="${STAGE2_REPORT_ROOT}/latest_dependency_operator_report.csv"
OPERATOR_JSON="${STAGE2_REPORT_ROOT}/latest_dependency_operator_report.json"
OPERATOR_MD="${STAGE2_REPORT_ROOT}/latest_dependency_operator_report.md"

cat >"${OPERATOR_CSV}" <<'CSV'
task,module,operator,case_set,status,log_path
CSV

DEPENDENCY_TESTS=(
  "task1,radartools,pulse_compression,accuracy"
  "task1,radartools,pulse_doppler,accuracy"
  "task1,radartools,ambgfun,accuracy"
  "task1,radartools,ca_cfar,accuracy"
  "task1,radartools,cfar_alpha,accuracy"
  "task1,spectral,spectrogram,accuracy"
  "task1,filter_design,firwin,accuracy"
  "task1,filter_design,firwin2,accuracy"
  "task1,windows,hamming,accuracy"
  "task1,windows,kaiser,accuracy"
  "task2,waveforms,chirp,accuracy"
  "task2,waveforms,gausspulse,accuracy"
  "task2,waveforms,unit_impulse,accuracy"
  "task2,filter_design,firwin,accuracy"
  "task2,filtering,firfilter,accuracy"
  "task2,filtering,sosfilt,accuracy"
  "task2,filtering,hilbert,accuracy"
  "task2,filtering,hilbert2,accuracy"
  "task2,bsplines,cubic,accuracy"
  "task2,bsplines,quadratic,accuracy"
  "task2,correlate,correlate,accuracy"
  "task2,correlate,correlate2d,accuracy"
  "task2,demod,fm_demod,accuracy"
  "task2,spectral,spectrogram,accuracy"
  "task2,spectral,stft,accuracy"
  "task2,wavelets,cwt,accuracy"
  "task2,wavelets,ricker,accuracy"
  "task2,peak_finding,argrelextrema,accuracy"
  "task2,estimation,kalman_filter,accuracy"
)

operator_failures=0
if [[ "${RUN_OPERATOR_TESTS}" == "1" ]]; then
  for entry in "${DEPENDENCY_TESTS[@]}"; do
    IFS=',' read -r task module operator default_case_set <<<"${entry}"
    case_set="${OP_CASE_SET:-${default_case_set}}"
    log_path="${STAGE2_REPORT_ROOT}/operators/${task}_${module}_${operator}_${case_set}.log"
    echo "[zx-stage2] operator ${task}/${module}/${operator} case_set=${case_set}"
    set +e
    scripts/test/run_all_tests.sh \
      --platform ZHONGKEXIN \
      --build-dir "${BUILD_DIR}" \
      --build-type "${BUILD_TYPE}" \
      --module "${module}" \
      --operator "${operator}" \
      --case-set "${case_set}" \
      --emit-report \
      --demo-fast \
      >"${log_path}" 2>&1
    rc=$?
    set -e
    if [[ "${rc}" -eq 0 ]]; then
      status="passed"
    else
      status="failed"
      operator_failures=$((operator_failures + 1))
    fi
    printf '%s,%s,%s,%s,%s,%s\n' \
      "${task}" "${module}" "${operator}" "${case_set}" "${status}" "${log_path}" >>"${OPERATOR_CSV}"
  done
fi

python3 - <<'PY' "${OPERATOR_CSV}" "${OPERATOR_JSON}" "${OPERATOR_MD}"
import csv
import json
import sys
from pathlib import Path

csv_path = Path(sys.argv[1])
json_path = Path(sys.argv[2])
md_path = Path(sys.argv[3])
rows = list(csv.DictReader(csv_path.open(newline="", encoding="utf-8")))
payload = {
    "pass": all(row["status"] == "passed" for row in rows),
    "total": len(rows),
    "passed": sum(1 for row in rows if row["status"] == "passed"),
    "failed": sum(1 for row in rows if row["status"] != "passed"),
    "rows": rows,
}
json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
lines = ["# Zhongkexin V4.2 Dependency Operator Report", ""]
lines.append(f"- pass: `{str(payload['pass']).lower()}`")
lines.append(f"- total: `{payload['total']}`")
lines.append(f"- passed: `{payload['passed']}`")
lines.append(f"- failed: `{payload['failed']}`")
lines.append("")
lines.append("| task | module | operator | case_set | status | log |")
lines.append("| --- | --- | --- | --- | --- | --- |")
for row in rows:
    lines.append(
        f"| {row['task']} | {row['module']} | {row['operator']} | "
        f"{row['case_set']} | {row['status']} | `{row['log_path']}` |"
    )
md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"[zx-stage2] wrote {json_path}")
print(f"[zx-stage2] wrote {md_path}")
PY

scale_status="skipped"
if [[ "${RUN_SCALE_SWEEP}" == "1" ]]; then
  if [[ "${operator_failures}" -ne 0 && "${RUN_SCALE_ON_OPERATOR_FAILURE}" != "1" ]]; then
    echo "[zx-stage2] skipping Task1/Task2 scale sweep because dependency operator failures were detected"
    scale_status="skipped_operator_failures"
  else
    echo "[zx-stage2] running Task1/Task2 scale sweep for scales: ${STAGE2_SCALES}"
    scripts/test/run_task_demos.sh \
      --build-dir "${BUILD_DIR}" \
      --build \
      --scale-sweep \
      --scales "${STAGE2_SCALES}" \
      --repeat "${REPEAT}" \
      --require-visualization-deps

    # Full-scale validation is intentionally kept here for the final V4.2 closure.
    # Enable it after the single-scale debug run passes:
    # STAGE2_SCALES=1,2,3,4,5,6 scripts/platform/run_zhongkexin_stage2.sh 2>&1 | tee stage2.log
    #
    # Equivalent expanded command:
    # scripts/test/run_task_demos.sh \
    #   --build-dir "${BUILD_DIR}" \
    #   --build \
    #   --scale-sweep \
    #   --scales "1,2,3,4,5,6" \
    #   --repeat "${REPEAT}" \
    #   --require-visualization-deps
    scale_status="passed"
  fi
fi

echo "[zx-stage2] operator failures: ${operator_failures}"
echo "[zx-stage2] scale sweep: ${scale_status}"

if [[ "${operator_failures}" -ne 0 ]]; then
  echo "[zx-stage2] failed: dependency operator failures detected" >&2
  exit 1
fi

echo "[zx-stage2] PASS"
