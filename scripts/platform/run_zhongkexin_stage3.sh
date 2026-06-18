#!/usr/bin/env bash
set -euo pipefail

VERSION="diagnostics-20260617-stage3-full-ops-v2"
BUILD_DIR="${BUILD_DIR:-build-zx}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
OP_CASE_SET="${OP_CASE_SET:-accuracy}"
INSTALL_PYTHON_DEPS="${INSTALL_PYTHON_DEPS:-1}"
RESET_BUILD="${RESET_BUILD:-1}"
STAGE3_REPORT_ROOT="${STAGE3_REPORT_ROOT:-data/reports/zhongkexin/stage3}"
DIAGNOSE_OPERATORS_ON_FAILURE="${DIAGNOSE_OPERATORS_ON_FAILURE:-1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

echo "[zx-stage3] script version: ${VERSION}"
echo "[zx-stage3] build dir: ${BUILD_DIR}"
echo "[zx-stage3] case set: ${OP_CASE_SET}"
echo "[zx-stage3] report root: ${STAGE3_REPORT_ROOT}"

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
  echo "[zx-stage3] resetting build dir: ${build_path}"
  rm -rf "${build_path}"
fi

mkdir -p "${STAGE3_REPORT_ROOT}/modules" "${STAGE3_REPORT_ROOT}/operators"
MODULE_CSV="${STAGE3_REPORT_ROOT}/latest_full_operator_module_report.csv"
MODULE_JSON="${STAGE3_REPORT_ROOT}/latest_full_operator_module_report.json"
MODULE_MD="${STAGE3_REPORT_ROOT}/latest_full_operator_module_report.md"
OPERATOR_CSV="${STAGE3_REPORT_ROOT}/latest_full_operator_detail_report.csv"
OPERATOR_JSON="${STAGE3_REPORT_ROOT}/latest_full_operator_detail_report.json"
OPERATOR_MD="${STAGE3_REPORT_ROOT}/latest_full_operator_detail_report.md"

cat >"${MODULE_CSV}" <<'CSV'
module,case_set,active_count,status,log_path
CSV
cat >"${OPERATOR_CSV}" <<'CSV'
module,operator,case_set,status,log_path
CSV

MODULES=(
  waveforms
  bsplines
  windows
  filter_design
  filtering
  radartools
  spectral
  wavelets
  correlate
  demod
  estimation
  peak_finding
)

module_failures=0
operator_failures=0
for module in "${MODULES[@]}"; do
  mapfile -t operator_rows < <(
    scripts/test/run_all_tests.sh \
      --platform ZHONGKEXIN \
      --module "${module}" \
      --case-set "${OP_CASE_SET}" \
      --list | awk 'NF == 4 {print $2}'
  )
  active_count="${#operator_rows[@]}"
  log_path="${STAGE3_REPORT_ROOT}/modules/${module}_${OP_CASE_SET}.log"
  echo "[zx-stage3] module ${module} case_set=${OP_CASE_SET} active=${active_count}"

  set +e
  scripts/test/run_all_tests.sh \
    --platform ZHONGKEXIN \
    --build-dir "${BUILD_DIR}" \
    --build-type "${BUILD_TYPE}" \
    --module "${module}" \
    --case-set "${OP_CASE_SET}" \
    --emit-report \
    --demo-fast \
    >"${log_path}" 2>&1
  rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    status="passed"
    for operator in "${operator_rows[@]}"; do
      printf '%s,%s,%s,%s,%s\n' \
        "${module}" "${operator}" "${OP_CASE_SET}" "passed_by_module" "${log_path}" >>"${OPERATOR_CSV}"
    done
  else
    status="failed"
    module_failures=$((module_failures + 1))
    if [[ "${DIAGNOSE_OPERATORS_ON_FAILURE}" == "1" ]]; then
      for operator in "${operator_rows[@]}"; do
        op_log_path="${STAGE3_REPORT_ROOT}/operators/${module}_${operator}_${OP_CASE_SET}.log"
        echo "[zx-stage3] diagnose ${module}/${operator} case_set=${OP_CASE_SET}"
        set +e
        scripts/test/run_all_tests.sh \
          --platform ZHONGKEXIN \
          --build-dir "${BUILD_DIR}" \
          --build-type "${BUILD_TYPE}" \
          --module "${module}" \
          --operator "${operator}" \
          --case-set "${OP_CASE_SET}" \
          --emit-report \
          --demo-fast \
          >"${op_log_path}" 2>&1
        op_rc=$?
        set -e
        if [[ "${op_rc}" -eq 0 ]]; then
          op_status="passed"
        else
          op_status="failed"
          operator_failures=$((operator_failures + 1))
        fi
        printf '%s,%s,%s,%s,%s\n' \
          "${module}" "${operator}" "${OP_CASE_SET}" "${op_status}" "${op_log_path}" >>"${OPERATOR_CSV}"
      done
    else
      for operator in "${operator_rows[@]}"; do
        printf '%s,%s,%s,%s,%s\n' \
          "${module}" "${operator}" "${OP_CASE_SET}" "unknown_module_failed" "${log_path}" >>"${OPERATOR_CSV}"
      done
    fi
  fi

  printf '%s,%s,%s,%s,%s\n' \
    "${module}" "${OP_CASE_SET}" "${active_count}" "${status}" "${log_path}" >>"${MODULE_CSV}"
done

python3 - <<'PY' "${MODULE_CSV}" "${MODULE_JSON}" "${MODULE_MD}" "${OPERATOR_CSV}" "${OPERATOR_JSON}" "${OPERATOR_MD}"
import csv
import json
import sys
from pathlib import Path


def load_rows(path: Path):
    return list(csv.DictReader(path.open(newline="", encoding="utf-8")))


def write_payload(rows, json_path: Path, md_path: Path, title: str, columns):
    payload = {
        "pass": all(row["status"] in {"passed", "passed_by_module"} for row in rows),
        "total": len(rows),
        "passed": sum(1 for row in rows if row["status"] in {"passed", "passed_by_module"} for _ in [0]),
        "failed": sum(1 for row in rows if row["status"] not in {"passed", "passed_by_module"}),
        "rows": rows,
    }
    json_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    lines = [f"# {title}", ""]
    lines.append(f"- pass: `{str(payload['pass']).lower()}`")
    lines.append(f"- total: `{payload['total']}`")
    lines.append(f"- passed: `{payload['passed']}`")
    lines.append(f"- failed: `{payload['failed']}`")
    lines.append("")
    lines.append("| " + " | ".join(columns) + " |")
    lines.append("| " + " | ".join(["---"] * len(columns)) + " |")
    for row in rows:
        values = [row[col] for col in columns]
        if "log_path" in columns:
          values[columns.index("log_path")] = f"`{row['log_path']}`"
        lines.append("| " + " | ".join(values) + " |")
    md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[zx-stage3] wrote {json_path}")
    print(f"[zx-stage3] wrote {md_path}")
    return payload


module_csv, module_json, module_md, operator_csv, operator_json, operator_md = map(Path, sys.argv[1:])
module_rows = load_rows(module_csv)
operator_rows = load_rows(operator_csv)
write_payload(
    module_rows,
    module_json,
    module_md,
    "Zhongkexin V4.3 Full Operator Module Report",
    ["module", "case_set", "active_count", "status", "log_path"],
)
write_payload(
    operator_rows,
    operator_json,
    operator_md,
    "Zhongkexin V4.3 Full Operator Detail Report",
    ["module", "operator", "case_set", "status", "log_path"],
)
PY

echo "[zx-stage3] module failures: ${module_failures}"
echo "[zx-stage3] operator failures: ${operator_failures}"

if [[ "${module_failures}" -ne 0 || "${operator_failures}" -ne 0 ]]; then
  echo "[zx-stage3] failed: full operator accuracy failures detected" >&2
  exit 1
fi

echo "[zx-stage3] PASS"
