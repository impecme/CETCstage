#!/usr/bin/env bash

set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${V6_8_BUILD_DIR:-${PROJECT_ROOT}/build-zx}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_ID="${V6_8_RUN_ID:-V6-0141}"
OUT="${V6_8_OUT:-/tmp/cetc_v6_0141_v6_8_performance_${STAMP}}"
LATEST_ARCHIVE="${V6_8_LATEST_ARCHIVE:-/tmp/cetc_v6_0141_latest.tar.gz}"
PREFLIGHT_ARCHIVE="${V6_8_PREFLIGHT_ARCHIVE:-/tmp/cetc_v6_0138_latest.tar.gz}"
REPORT_ROOT="${PROJECT_ROOT}/data/reports"
REPORTS_OWNED=0
GENERATED_SAMPLES_OWNED=0
MONITOR_PID=""

mkdir -p \
  "${OUT}/fingerprint" \
  "${OUT}/logs" \
  "${OUT}/benchmark" \
  "${OUT}/preflight" \
  "${OUT}/summary" \
  "${OUT}/telemetry"
printf 'phase\tcase\trc\tnote\n' >"${OUT}/status.tsv"

cd "${PROJECT_ROOT}" || exit 1
if [[ -f /zq500/sdk/env.sh ]]; then
  set +u
  # shellcheck source=/dev/null
  source /zq500/sdk/env.sh ""
  set -u
fi

record_status() {
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}" >>"${OUT}/status.tsv"
}

hash_manifests() {
  local output="$1"
  find data/reference data/generated -type f -name manifest.json -print0 2>/dev/null \
    | sort -z \
    | xargs -0 -r sha256sum >"${output}"
}

hash_reports() {
  local output="$1"
  find data/reports -type f -print0 2>/dev/null \
    | sort -z \
    | xargs -0 -r sha256sum >"${output}"
}

remove_generated_samples() {
  find data/generated/unit -type d \
    \( -name input -o -name output_samples \) -prune -print0 2>/dev/null \
    | xargs -0 -r rm -rf
}

inventory_generated_samples() {
  local dirs="${OUT}/preexisting_generated_sample_dirs.txt"
  local files="${OUT}/preexisting_generated_sample_files.tsv"
  find data/generated/unit -type d \
    \( -name input -o -name output_samples \) -prune -print 2>/dev/null \
    | sort >"${dirs}"
  : >"${files}"
  while IFS= read -r directory; do
    find "${directory}" -type f -printf '%s\t%p\n' 2>/dev/null
  done <"${dirs}" | sort -k2 >>"${files}"
}

stop_monitor() {
  local rc=0
  if [[ -n "${MONITOR_PID}" ]]; then
    kill -TERM "${MONITOR_PID}" 2>/dev/null || true
    wait "${MONITOR_PID}" 2>/dev/null
    rc=$?
    MONITOR_PID=""
  fi
  return "${rc}"
}

finalize() {
  local rc=$?
  local manifest_rc=0
  local reports_rc=0
  local archive_rc=0
  trap - EXIT INT TERM
  set +e
  stop_monitor
  if [[ "${GENERATED_SAMPLES_OWNED}" -eq 1 ]]; then
    remove_generated_samples
  fi

  if [[ "${REPORTS_OWNED}" -eq 1 ]]; then
    rm -rf "${REPORT_ROOT}/unit" "${REPORT_ROOT}/demo"
  fi

  hash_manifests "${OUT}/manifest_after.sha256"
  diff -u "${OUT}/manifest_before.sha256" "${OUT}/manifest_after.sha256" \
    >"${OUT}/manifest_diff.log"
  manifest_rc=$?
  record_status integrity manifest_unchanged "${manifest_rc}" \
    "all reference/generated manifests"
  if [[ "${manifest_rc}" -ne 0 ]]; then
    rc=1
  fi

  hash_reports "${OUT}/reports_after.sha256"
  diff -u "${OUT}/reports_before.sha256" "${OUT}/reports_after.sha256" \
    >"${OUT}/reports_diff.log"
  reports_rc=$?
  record_status integrity reports_restored "${reports_rc}" \
    "data/reports must match the pre-run inventory"
  if [[ "${reports_rc}" -ne 0 ]]; then
    rc=1
  fi

  cp "${BUILD_DIR}/CMakeCache.txt" "${OUT}/fingerprint/" 2>/dev/null || true
  cp "${BUILD_DIR}/compile_commands.json" "${OUT}/fingerprint/" 2>/dev/null || true
  record_status final overall "${rc}" "${RUN_ID} performance terminal"

  tar -C "$(dirname "${OUT}")" -czf "${OUT}.tar.gz" "$(basename "${OUT}")"
  archive_rc=$?
  if [[ "${archive_rc}" -eq 0 ]]; then
    cp -f "${OUT}.tar.gz" "${LATEST_ARCHIVE}"
    sha256sum "${OUT}.tar.gz" "${LATEST_ARCHIVE}" >"${OUT}.archive.sha256"
  else
    rc=1
  fi

  printf 'OUT=%s\nARCHIVE=%s.tar.gz\nLATEST_ARCHIVE=%s\nARCHIVE_RC=%s\nOVERALL_RC=%s\n' \
    "${OUT}" "${OUT}" "${LATEST_ARCHIVE}" "${archive_rc}" "${rc}"
  exit "${rc}"
}

trap finalize EXIT
trap 'exit 130' INT TERM

run_phase() {
  local phase="$1"
  local case_name="$2"
  shift 2
  local log="${OUT}/logs/${phase}_${case_name}.log"
  local rc
  printf '[v6.8-perf] phase=%s case=%s\n' "${phase}" "${case_name}"
  "$@" 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
  record_status "${phase}" "${case_name}" "${rc}" "${log}"
  return "${rc}"
}

preflight_guard() {
  local remaining="${OUT}/remaining_generated_sample_dirs.txt"
  if [[ -e "${REPORT_ROOT}/unit" || -e "${REPORT_ROOT}/demo" ]]; then
    echo "[v6.8-perf] refusing to remove pre-existing data/reports/unit or data/reports/demo" >&2
    return 2
  fi
  inventory_generated_samples || return 2
  if [[ -s "${OUT}/preexisting_generated_sample_dirs.txt" ]]; then
    echo "[v6.8-perf] removing stale generated unit samples after inventory"
    remove_generated_samples || return 2
    find data/generated/unit -type d \
      \( -name input -o -name output_samples \) -prune -print 2>/dev/null \
      | sort >"${remaining}"
    if [[ -s "${remaining}" ]]; then
      echo "[v6.8-perf] stale generated unit samples remain after cleanup" >&2
      return 2
    fi
  fi
  REPORTS_OWNED=1
  GENERATED_SAMPLES_OWNED=1
}

collect_fingerprint() {
  git rev-parse HEAD >"${OUT}/fingerprint/git_head.txt" 2>/dev/null || true
  git status --short >"${OUT}/fingerprint/git_status.txt" 2>/dev/null || true
  git diff --binary >"${OUT}/fingerprint/worktree.patch" 2>/dev/null || true
  git ls-files --others --exclude-standard \
    >"${OUT}/fingerprint/untracked_files.txt" 2>/dev/null || true
  find CMakeLists.txt cmake include src demo tests scripts -type f -print0 2>/dev/null \
    | sort -z \
    | xargs -0 -r sha256sum >"${OUT}/fingerprint/source_sha256.txt"
  find CMakeLists.txt cmake include src demo tests -type f -print0 2>/dev/null \
    | sort -z \
    | xargs -0 -r sha256sum >"${OUT}/fingerprint/product_source_sha256.txt"
  {
    printf 'timestamp=%s\n' "$(date --iso-8601=seconds)"
    printf 'hostname=%s\n' "$(hostname)"
    uname -a
    command -v dlcc || true
    dlcc --version 2>&1 || true
    cmake --version 2>&1 || true
    python3 --version 2>&1 || true
    dlsmi -L 2>&1 || true
  } >"${OUT}/fingerprint/toolchain.txt"
}

extract_preflight() {
  if [[ ! -f "${PREFLIGHT_ARCHIVE}" ]]; then
    echo "[v6.8-perf] missing V6-0138 archive: ${PREFLIGHT_ARCHIVE}" >&2
    return 2
  fi
  sha256sum "${PREFLIGHT_ARCHIVE}" >"${OUT}/preflight/archive.sha256"
  tar -xzf "${PREFLIGHT_ARCHIVE}" -C "${OUT}/preflight"
}

assert_preflight() {
  local root="$1"
  local filtered="${OUT}/preflight/product_source_sha256.txt"
  local current="${OUT}/fingerprint/product_source_sha256.sorted.txt"
  awk '$2 == "CMakeLists.txt" || $2 ~ /^(cmake|include|src|demo|tests)\//' \
    "${root}/fingerprint/source_sha256.txt" \
    | sort -k2 >"${filtered}"
  sort -k2 "${OUT}/fingerprint/product_source_sha256.txt" >"${current}"
  diff -u "${filtered}" "${current}" \
    >"${OUT}/preflight/product_source_diff.log" || return 1
  awk -F '\t' '$1 == "final" && $2 == "overall" && $3 == "0" { found=1 } END { exit !found }' \
    "${root}/status.tsv" || return 1
  grep -Fq '"status": "passed"' "${root}/task_summary/task_matrix.json" || return 1
  grep -Fq '"case_count": 24' "${root}/task_summary/task_matrix.json" || return 1
  grep -Fq '"step_row_count": 168' "${root}/task_summary/task_matrix.json" || return 1
  grep -Fq '[cusignal-test] summary: passed 81/81' \
    "${root}/logs/regression_all81_full.log"
}

start_monitor() {
  rm -f \
    "${OUT}/telemetry/dlsmi_samples.csv" \
    "${OUT}/telemetry/dlsmi_summary.json"
  python3 scripts/platform/sample_gpu_memory.py \
    --csv "${OUT}/telemetry/dlsmi_samples.csv" \
    --json "${OUT}/telemetry/dlsmi_summary.json" \
    --interval 0.5 &
  MONITOR_PID=$!
  sleep 1
}

run_benchmark() {
  CMAKE_BUILD_TYPE=Release PYTHONUNBUFFERED=1 \
  python3 scripts/test/benchmark_all_ops_scales.py \
    --platform ZHONGKEXIN \
    --build-dir "${BUILD_DIR}" \
    --operator-set all81 \
    --operator-sets-file scripts/test/operator_sets.json \
    --scale-profile default \
    --scale-levels 1,2,3,4,5,6 \
    --warmup 5 \
    --repeat 30 \
    --build \
    --output-dir "${OUT}/benchmark" \
    --report-mode full \
    --checkpoint \
    --progress-jsonl "${OUT}/telemetry/operator_windows.jsonl"
}

copy_l6_reports() {
  if [[ ! -d "${REPORT_ROOT}/unit" ]]; then
    echo "[v6.8-perf] unit reports are missing after benchmark" >&2
    return 1
  fi
  mkdir -p "${OUT}/benchmark/l6_reports"
  cp -a "${REPORT_ROOT}/unit/." "${OUT}/benchmark/l6_reports/"
}

summarize_performance() {
  local preflight_root="$1"
  python3 scripts/platform/summarize_v6_8_performance.py \
    --benchmark-csv "${OUT}/benchmark/latest_all_ops_scale_benchmark.csv" \
    --progress-jsonl "${OUT}/telemetry/operator_windows.jsonl" \
    --telemetry-csv "${OUT}/telemetry/dlsmi_samples.csv" \
    --telemetry-json "${OUT}/telemetry/dlsmi_summary.json" \
    --task-totals "${preflight_root}/task_summary/task_totals.tsv" \
    --task-steps "${preflight_root}/task_summary/task_steps.tsv" \
    --output-dir "${OUT}/summary" \
    --gpu-index 0 \
    --expected-operators 81 \
    --expected-scales 6 \
    --warmup 5 \
    --repeat 30
}

main() {
  local preflight_root
  local benchmark_rc
  local evidence_rc
  local monitor_rc
  local summary_rc

  hash_manifests "${OUT}/manifest_before.sha256"
  hash_reports "${OUT}/reports_before.sha256"

  run_phase guard clean_report_roots preflight_guard || return 1
  REPORTS_OWNED=1
  run_phase fingerprint source_and_toolchain collect_fingerprint || return 1
  run_phase preflight extract extract_preflight || return 1
  preflight_root="$(
    find "${OUT}/preflight" -mindepth 1 -maxdepth 1 -type d -print -quit
  )"
  if [[ -z "${preflight_root}" ]]; then
    echo "[v6.8-perf] extracted V6-0138 root is missing" >&2
    return 1
  fi
  run_phase preflight hard_gate_and_source_match \
    assert_preflight "${preflight_root}" || return 1

  start_monitor
  run_phase benchmark all81_l1_l6 run_benchmark
  benchmark_rc=$?
  stop_monitor
  monitor_rc=$?
  record_status telemetry dlsmi "${monitor_rc}" \
    "${OUT}/telemetry/dlsmi_summary.json"
  run_phase evidence copy_l6_reports copy_l6_reports
  evidence_rc=$?
  run_phase summary performance summarize_performance "${preflight_root}"
  summary_rc=$?
  if [[ "${benchmark_rc}" -ne 0 || "${evidence_rc}" -ne 0 || \
        "${monitor_rc}" -ne 0 || "${summary_rc}" -ne 0 ]]; then
    return 1
  fi
  return 0
}

main
