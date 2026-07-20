#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-build-zx}"
FIXTURE_DIR="${ZX_COMPAT_SOURCE_DIR:-}"
DO_BUILD=1
RUN_TASKS=1
REPORT_ROOT="${DELIVERY_REPORT_ROOT:-data/.reports_staging/runtime}"
RUN_ID="${DELIVERY_RUN_ID:-delivery-$(date -u +%Y%m%dT%H%M%SZ)}"

usage() {
  cat <<'USAGE'
Usage: scripts/validate.sh [options]

Run one current-code ZQ500 delivery validation. Complete mode clears staging
data, runs all gates, then publishes data/reports/ atomically.
No plotting or candidate selection is performed.

Options:
  --build-dir PATH       Build directory (default: build-zx)
  --fixtures PATH        Directory containing the three frozen compatibility XLSX files
  --no-build             Reuse an existing build
  --skip-tasks           Skip Task1 and Task2 demos
  --run-id ID            Published run identifier (default: DELIVERY_RUN_ID or UTC time)
  -h, --help             Show this help

Raw reports are written under data/.reports_staging/unit,
data/.reports_staging/demo, and DELIVERY_REPORT_ROOT
(default: data/.reports_staging/runtime). Complete validation publishes
data/reports/ only after every gate succeeds. --skip-tasks or a custom
DELIVERY_REPORT_ROOT is diagnostic-only and never replaces published reports.
USAGE
}

die() {
  echo "[delivery-validation] error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      [[ $# -ge 2 ]] || die "--build-dir requires a value"
      BUILD_DIR="$2"
      shift 2
      ;;
    --fixtures)
      [[ $# -ge 2 ]] || die "--fixtures requires a value"
      FIXTURE_DIR="$2"
      shift 2
      ;;
    --no-build)
      DO_BUILD=0
      shift
      ;;
    --skip-tasks)
      RUN_TASKS=0
      shift
      ;;
    --run-id)
      [[ $# -ge 2 ]] || die "--run-id requires a value"
      RUN_ID="$2"
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

cd "${PROJECT_ROOT}"

# The SDK environment is required by platform probe binaries below.  Do this in
# the validation process itself so direct invocation does not rely on a caller
# having already sourced the SDK environment.
if [[ -f /zq500/sdk/env.sh ]]; then
  set +u
  # shellcheck source=/dev/null
  source /zq500/sdk/env.sh ""
  set -u
fi

PUBLISHED_REPORT_ROOT="$(realpath -m data/reports)"
REPORT_ROOT="$(realpath -m "${REPORT_ROOT}")"
case "${REPORT_ROOT}" in
  "${PUBLISHED_REPORT_ROOT}"|"${PUBLISHED_REPORT_ROOT}"/*)
    die "DELIVERY_REPORT_ROOT must not be data/reports or one of its subdirectories"
    ;;
esac
AUDIT_ROOT="${REPORT_ROOT}/audits"
DEFAULT_RUNTIME_ROOT="$(realpath -m data/.reports_staging/runtime)"
PUBLISH_REPORTS=1
if [[ "${RUN_TASKS}" -eq 0 || "${REPORT_ROOT}" != "${DEFAULT_RUNTIME_ROOT}" ]]; then
  PUBLISH_REPORTS=0
fi
if [[ "${BUILD_DIR}" = /* ]]; then
  BUILD_PATH="${BUILD_DIR}"
else
  BUILD_PATH="${PROJECT_ROOT}/${BUILD_DIR}"
fi

scripts/clean.sh
mkdir -p "${AUDIT_ROOT}"

if [[ -n "${FIXTURE_DIR}" ]]; then
  python3 tests/platform/tools/validate_zx_compat_fixtures.py \
    --source-dir "${FIXTURE_DIR}" \
    --manifest tests/platform/config/zx_compat_fixture_manifest.json \
    --output "${AUDIT_ROOT}/fixture_validation.json"
fi

if [[ "${DO_BUILD}" -eq 1 ]]; then
  if [[ -n "${FIXTURE_DIR}" ]]; then
    ZX_COMPAT_SOURCE_DIR="${FIXTURE_DIR}" ZX_COMPAT_REQUIRE_FIXTURES=ON \
      scripts/build.sh --build-dir "${BUILD_DIR}"
  else
    scripts/build.sh --build-dir "${BUILD_DIR}"
  fi
fi

registry_file="$(mktemp)"
trap 'rm -f -- "${registry_file}"' EXIT
scripts/test_operators.sh --list >"${registry_file}"

python3 tests/tools/operator_contract_audit.py \
  --registry "${registry_file}" \
  --sets tests/contracts/operator_sets.json \
  --summary-json "${AUDIT_ROOT}/operator_sets.json" \
  --output-dir "${AUDIT_ROOT}/interfaces" \
  --contract-markdown "${AUDIT_ROOT}/interfaces.md"
python3 tests/tools/dtype_contract_audit.py \
  --registry "${registry_file}" \
  --contracts tests/contracts/operator_type_contracts.json \
  --output-dir "${AUDIT_ROOT}/type_contracts" \
  --contract-markdown "${AUDIT_ROOT}/type_contracts.md" \
  --coverage-output-dir "${AUDIT_ROOT}/dtype_coverage" \
  --coverage-summary-markdown "${AUDIT_ROOT}/dtype_coverage.md"

if [[ "${RUN_TASKS}" -eq 0 ]]; then
  python3 tests/tools/task_contract_audit.py \
    --contracts tests/contracts/task_step_contracts.json \
    --output-dir "${AUDIT_ROOT}/task_steps" \
    --summary-markdown "${AUDIT_ROOT}/task_steps.md"
fi

if [[ -n "${FIXTURE_DIR}" ]]; then
  cmake --build "${BUILD_DIR}" --target zx_compat_fixture_check zx_forbidden_api_scan
fi

"${BUILD_PATH}/tests/platform/zx_compat_runtime_probes"
"${BUILD_PATH}/tests/unit/core_types/cusignal_type_contract_tests"
"${BUILD_PATH}/tests/unit/radartools/radartools_task_test_fftshift_rows"
"${BUILD_PATH}/tests/unit/radartools/radartools_task_test_power_map"
"${BUILD_PATH}/tests/unit/radartools/radartools_task_test_detect_peak"

scripts/test_operators.sh \
  --build-dir "${BUILD_DIR}" \
  --no-build \
  --case-set full \
  --emit-report

if [[ "${RUN_TASKS}" -eq 1 ]]; then
  scripts/demo.sh --build-dir "${BUILD_DIR}" --no-build --repeat 5 --scale-sweep
  python3 tests/tools/task_contract_audit.py \
    --contracts tests/contracts/task_step_contracts.json \
    --output-dir "${AUDIT_ROOT}/task_steps" \
    --summary-markdown "${AUDIT_ROOT}/task_steps.md" \
    --report-root data/.reports_staging/demo \
    --report-output "${AUDIT_ROOT}/task_step_reports.json"
fi

if [[ "${PUBLISH_REPORTS}" -eq 1 ]]; then
  scripts/finalize_reports.py \
    --repo-root "${PROJECT_ROOT}" \
    --source-root "${PROJECT_ROOT}/data/.reports_staging" \
    --output "${PUBLISHED_REPORT_ROOT}" \
    --run-id "${RUN_ID}"
else
  echo "[delivery-validation] report publication skipped (diagnostic-only mode)"
fi

echo "[delivery-validation] PASS"
