#!/usr/bin/env bash

cd /CETC || exit 1
source /zq500/sdk/env.sh || exit 1
set -u -o pipefail
ulimit -c 0 2>/dev/null || true

RUN_ID="${V7_RUN_ID:-V7-0008}"
PHASE="${V7_DEMO_PHASE:-both}"
WALL_LIMIT_SECONDS="${V7_DEMO_WALL_LIMIT_SECONDS:-240}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/cetc_v7_0008_demo_budget_${STAMP}"
BACKUP="/tmp/cetc_v7_0008_backup_${STAMP}"
CONSOLE="/tmp/cetc_v7_0008_console.log"
ARCHIVE="/tmp/cetc_v7_0008_latest.tar.gz"
BUILD_DIR="${CETC_BUILD_DIR:-build-v7-demo}"
CACHE_DIR="${V7_DEMO_CACHE_DIR:-/tmp/cetc_v7_demo_cache}"
BASELINE_FILE="${CACHE_DIR}/top30_large_gpu_cpu_baseline.json"
DECISION_FILE="${CACHE_DIR}/cache_decision.json"
TASK1_REPORT="data/reports/demo/task1_radar"
TASK2_REPORT="data/reports/demo/task2_features"
TASK1_APP="${BUILD_DIR}/demo/task1_radar/task1_radar_demo"
TASK2_APP="${BUILD_DIR}/demo/task2_features/task2_features_demo"
MONITOR_PID=""
RESTORED=0
DEMO_START_NS=0

case "${PHASE}" in
  prepare|demo|both) ;;
  *)
    printf 'invalid V7_DEMO_PHASE=%s; expected prepare, demo, or both\n' "${PHASE}" >&2
    exit 2
    ;;
esac
if ! [[ "${WALL_LIMIT_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
  printf 'V7_DEMO_WALL_LIMIT_SECONDS must be a positive integer\n' >&2
  exit 2
fi

mkdir -p \
  "${OUT}/fingerprint" \
  "${OUT}/logs" \
  "${OUT}/audits" \
  "${OUT}/prepare" \
  "${OUT}/demo/tasks/task1_radar" \
  "${OUT}/demo/tasks/task2_features" \
  "${OUT}/demo/top30" \
  "${OUT}/demo/telemetry" \
  "${CACHE_DIR}" \
  "${BACKUP}"
rm -f "${CONSOLE}" "${ARCHIVE}"
exec > >(tee "${CONSOLE}") 2>&1

printf 'phase\tcase\trc\tdetail\n' >"${OUT}/status.tsv"
printf 'phase\tcase\tevent\tepoch_ns\n' >"${OUT}/markers.tsv"

record_status()
{
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${OUT}/status.tsv"
}

mark_event()
{
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$(date +%s%N)" \
    >>"${OUT}/markers.tsv"
}

hash_tree()
{
  local root="$1"
  local output="$2"
  if [[ ! -d "${root}" ]]; then
    : >"${output}"
    return
  fi
  find "${root}" -type f -print0 |
    sort -z |
    xargs -0 -r sha256sum >"${output}"
}

backup_path()
{
  local source="$1"
  local label="$2"
  if [[ -e "${source}" ]]; then
    mkdir -p "${BACKUP}/${label}"
    cp -a "${source}" "${BACKUP}/${label}/content"
    printf 'present\n' >"${BACKUP}/${label}/state"
  else
    printf 'absent\n' >"${BACKUP}/${label}.state"
  fi
}

restore_path()
{
  local destination="$1"
  local label="$2"
  rm -rf "${destination}"
  if [[ -f "${BACKUP}/${label}/state" ]]; then
    mkdir -p "$(dirname "${destination}")"
    mv "${BACKUP}/${label}/content" "${destination}"
  fi
}

stop_monitor()
{
  if [[ -n "${MONITOR_PID}" ]]; then
    kill -TERM "${MONITOR_PID}" 2>/dev/null || true
    wait "${MONITOR_PID}" 2>/dev/null || true
    MONITOR_PID=""
  fi
}

start_monitor()
{
  local csv_path="$1"
  local json_path="$2"
  local interval="$3"
  stop_monitor
  python3 scripts/platform/sample_gpu_memory.py \
    --csv "${csv_path}" \
    --json "${json_path}" \
    --interval "${interval}" &
  MONITOR_PID=$!
  sleep 1
}

restore_repository_outputs()
{
  if [[ "${RESTORED}" -eq 1 ]]; then
    return
  fi
  restore_path data/reports reports
  restore_path data/generated/unit generated_unit
  restore_path data/generated/demo/task1_radar generated_task1
  restore_path data/generated/demo/task2_features generated_task2
  hash_tree data/reports "${OUT}/reports_after.sha256"
  hash_tree data/generated/unit "${OUT}/manifests_after.sha256"
  diff -u "${OUT}/reports_before.sha256" "${OUT}/reports_after.sha256" \
    >"${OUT}/reports_restore.diff" || true
  diff -u "${OUT}/manifests_before.sha256" "${OUT}/manifests_after.sha256" \
    >"${OUT}/manifests_restore.diff" || true
  RESTORED=1
  rm -rf "${BACKUP}"
}

finalize()
{
  local final_rc=$?
  local integrity_rc=0
  local tar_rc
  local alias_rc=99
  trap - EXIT
  set +e
  stop_monitor
  if [[ -f "${BASELINE_FILE}" ]]; then
    mkdir -p "${OUT}/cache_evidence"
    cp "${BASELINE_FILE}" "${OUT}/cache_evidence/"
    sha256sum "${BASELINE_FILE}" >"${OUT}/cache_evidence/baseline.sha256"
  fi
  if [[ -f "${DECISION_FILE}" ]]; then
    mkdir -p "${OUT}/cache_evidence"
    cp "${DECISION_FILE}" "${OUT}/cache_evidence/"
  fi
  restore_repository_outputs
  [[ ! -s "${OUT}/reports_restore.diff" ]] || integrity_rc=1
  [[ ! -s "${OUT}/manifests_restore.diff" ]] || integrity_rc=1
  record_status integrity restore "${integrity_rc}" "reports/manifests"
  if [[ "${integrity_rc}" -ne 0 ]]; then
    final_rc=1
  fi
  record_status final overall "${final_rc}" \
    "${RUN_ID} phase=${PHASE} five-minute demo"
  tar -czf "${OUT}.tar.gz" -C /tmp "$(basename "${OUT}")"
  tar_rc=$?
  if [[ "${tar_rc}" -eq 0 ]]; then
    cp "${OUT}.tar.gz" "${ARCHIVE}"
    alias_rc=$?
  fi
  if [[ "${tar_rc}" -ne 0 || "${alias_rc}" -ne 0 ]]; then
    final_rc=1
  fi
  printf 'OUT=%s\nARCHIVE=%s\nCONSOLE=%s\nBASELINE=%s\nDECISION=%s\nRC=%s\n' \
    "${OUT}" "${ARCHIVE}" "${CONSOLE}" "${BASELINE_FILE}" \
    "${DECISION_FILE}" "${final_rc}"
  exit "${final_rc}"
}
trap finalize EXIT

hash_tree data/reports "${OUT}/reports_before.sha256"
hash_tree data/generated/unit "${OUT}/manifests_before.sha256"
backup_path data/reports reports
backup_path data/generated/unit generated_unit
backup_path data/generated/demo/task1_radar generated_task1
backup_path data/generated/demo/task2_features generated_task2

git rev-parse HEAD >"${OUT}/fingerprint/git_head.txt" 2>/dev/null || true
git status --short >"${OUT}/fingerprint/git_status.txt" 2>/dev/null || true
sha256sum \
  demo/task1_radar/task1_radar_demo.cpp \
  demo/task2_features/task2_features_demo.cpp \
  demo/task2_features/task2_features_zx_gpu.cu \
  demo/task2_features/task2_features_zx_gpu.hpp \
  scripts/test/operator_sets.json \
  scripts/test/benchmark_all_ops_scales.py \
  scripts/platform/select_v7_4_cache_mode.py \
  scripts/platform/summarize_v7_4_demo.py \
  "$0" \
  >"${OUT}/fingerprint/candidate_sources.sha256"
{
  printf 'run_id=%s\nphase=%s\nwall_limit_seconds=%s\n' \
    "${RUN_ID}" "${PHASE}" "${WALL_LIMIT_SECONDS}"
  date --iso-8601=seconds
  dlcc --version 2>&1
  cmake --version 2>&1
  dlsmi -L 2>&1
} >"${OUT}/fingerprint/toolchain.txt"

write_registry_and_audits()
{
  scripts/test/run_all_tests.sh \
    --list \
    --build-dir "${BUILD_DIR}" \
    --platform ZHONGKEXIN \
    >"${OUT}/all81_registry.raw.txt" 2>&1
  local registry_rc=$?
  if [[ "${registry_rc}" -eq 0 ]]; then
    awk -F '\t' 'NF == 4 && $1 != "" && $2 != "" && $3 != "" && $4 != ""' \
      "${OUT}/all81_registry.raw.txt" >"${OUT}/all81_registry.tsv"
    [[ "$(wc -l <"${OUT}/all81_registry.tsv")" -eq 81 ]] || registry_rc=1
  fi
  record_status audit registry "${registry_rc}" "81 operators"
  [[ "${registry_rc}" -eq 0 ]] || return 1

  python3 scripts/test/audit_dtype_test_coverage.py \
    --registry "${OUT}/all81_registry.tsv" \
    --contracts scripts/test/operator_type_contracts.json \
    --output-dir "${OUT}/audits/dtype" \
    --summary-markdown "${OUT}/audits/dtype.md"
  local dtype_rc=$?
  record_status audit dtype "${dtype_rc}" "compatibility gaps"
  [[ "${dtype_rc}" -eq 0 ]] || return 1

  python3 scripts/test/audit_task_steps.py \
    --contracts scripts/test/task_step_contracts.json \
    --output-dir "${OUT}/audits/task_steps" \
    --summary-markdown "${OUT}/audits/task_steps.md"
  local task_steps_rc=$?
  record_status audit task_steps "${task_steps_rc}" "14 calculation steps"
  [[ "${task_steps_rc}" -eq 0 ]] || return 1

  python3 - "${OUT}/audits" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
dtype = json.loads(
    (root / "dtype/latest_dtype_test_coverage.json").read_text()
)["summary"]
steps = json.loads(
    (root / "task_steps/latest_task_step_audit.json").read_text()
)["summary"]
checks = {
    "dtype": dtype.get("status") == "passed"
        and dtype.get("operator_count") == 81
        and dtype.get("operator_dtype_missing_edges") == 0,
    "task_steps": steps.get("status") == "passed"
        and steps.get("calculation_step_count") == 14
        and steps.get("timing_gap_count") == 0
        and steps.get("accuracy_gap_count") == 0
        and steps.get("failure_count") == 0,
}
(root / "assertions.json").write_text(
    json.dumps(checks, indent=2, sort_keys=True) + "\n"
)
raise SystemExit(0 if all(checks.values()) else 1)
PY
  local gate_rc=$?
  record_status gate static_audits "${gate_rc}" "dtype/task steps"
  return "${gate_rc}"
}

run_task_sweep()
{
  local task="$1"
  local app="$2"
  local report_source="$3"
  local aggregate_rc=0
  local scale
  local destination
  local rc
  for scale in 1 2 3 4 5 6; do
    destination="${OUT}/prepare/task_sweep/${task}/L${scale}"
    mkdir -p "${destination}"
    mark_event prepare_task "${task}_L${scale}" start
    if [[ "${task}" == "task2_features" ]]; then
      env \
        -u CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY \
        -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_CORRELATE \
        -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_SPECTROGRAM \
        CUSIGNAL_TASK2_DISABLE_FIXED_FFT_FILTER=1 \
        "${app}" --repeat 1 --scale-level "${scale}" \
          --invalid-input-checks --skip-timing-validation \
          >"${destination}/console.log" 2>&1
    else
      "${app}" --repeat 1 --scale-level "${scale}" \
        --invalid-input-checks --skip-timing-validation \
        >"${destination}/console.log" 2>&1
    fi
    rc=$?
    mark_event prepare_task "${task}_L${scale}" end
    record_status prepare_task "${task}_L${scale}" "${rc}" "repeat=1"
    if [[ -d "${report_source}" ]]; then
      cp -a "${report_source}/." "${destination}/"
    fi
    [[ "${rc}" -eq 0 ]] || aggregate_rc=1
  done
  return "${aggregate_rc}"
}

validate_baseline()
{
  python3 - "${OUT}/prepare/top30/latest_all_ops_scale_benchmark.csv" \
    "${BASELINE_FILE}" <<'PY'
import csv
import json
import sys
from pathlib import Path

csv_path = Path(sys.argv[1])
baseline_path = Path(sys.argv[2])
rows = list(csv.DictReader(csv_path.open()))
baseline = json.loads(baseline_path.read_text())
checks = {
    "row_count": len(rows) == 30,
    "rows_passed": all(
        row.get("status") == "passed" and row.get("pass", "").lower() == "true"
        for row in rows
    ),
    "baseline_entries": len(baseline.get("entries", {})) >= 30,
}
print(json.dumps(checks, sort_keys=True))
raise SystemExit(0 if all(checks.values()) else 1)
PY
}

run_cache_probe()
{
  local label="$1"
  local max_blocks="$2"
  local max_mb="$3"
  local max_single_mb="$4"
  local destination="${OUT}/prepare/cache_probe/${label}"
  mkdir -p "${destination}"
  start_monitor \
    "${destination}/dlsmi_samples.csv" \
    "${destination}/dlsmi_summary.json" \
    0.05
  mark_event cache_probe "${label}" start
  env \
    CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS="${max_blocks}" \
    CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB="${max_mb}" \
    CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB="${max_single_mb}" \
    CMAKE_BUILD_TYPE=Release \
    PYTHONUNBUFFERED=1 \
    python3 scripts/test/benchmark_all_ops_scales.py \
      --platform ZHONGKEXIN \
      --build-dir "${BUILD_DIR}" \
      --operator-set demo_cache_probe4 \
      --operator-sets-file scripts/test/operator_sets.json \
      --scale-profile large-gpu \
      --scale-levels 6 \
      --warmup 1 \
      --repeat 3 \
      --demo-fast \
      --no-build \
      --gpu-only \
      --cpu-baseline-mode reuse \
      --cpu-baseline-file "${BASELINE_FILE}" \
      --output-dir "${destination}" \
      --report-mode concise \
      --checkpoint \
      --progress-jsonl "${destination}/operator_windows.jsonl" \
      >"${destination}/console.log" 2>&1
  local rc=$?
  mark_event cache_probe "${label}" end
  stop_monitor
  record_status cache_probe "${label}" "${rc}" \
    "blocks=${max_blocks},max_mb=${max_mb},single_mb=${max_single_mb}"
  return "${rc}"
}

prepare_demo()
{
  rm -f "${BASELINE_FILE}" "${DECISION_FILE}"
  write_registry_and_audits || return 1

  mark_event regression all81 start
  scripts/test/run_all_tests.sh \
    --case-set full \
    --demo-fast \
    --emit-report \
    --build-dir "${BUILD_DIR}" \
    --platform ZHONGKEXIN \
    >"${OUT}/logs/all81_full.log" 2>&1
  local all81_rc=$?
  mark_event regression all81 end
  if ! grep -Fq '[cusignal-test] summary: passed 81/81' \
    "${OUT}/logs/all81_full.log"; then
    all81_rc=1
  fi
  record_status regression all81 "${all81_rc}" "81/81"
  [[ "${all81_rc}" -eq 0 ]] || return 1
  if [[ -d data/reports/unit ]]; then
    cp -a data/reports/unit "${OUT}/prepare/all81_reports"
  fi

  cmake --build "${BUILD_DIR}" --target \
    task1_radar_demo task2_features_demo --parallel \
    >"${OUT}/logs/build_task_demos.log" 2>&1
  local build_rc=$?
  record_status build task_demos "${build_rc}" "${BUILD_DIR}"
  [[ "${build_rc}" -eq 0 ]] || return 1

  run_task_sweep task1_radar "${TASK1_APP}" "${TASK1_REPORT}" || return 1
  run_task_sweep task2_features "${TASK2_APP}" "${TASK2_REPORT}" || return 1

  mkdir -p "${OUT}/prepare/top30"
  start_monitor \
    "${OUT}/prepare/top30/dlsmi_samples.csv" \
    "${OUT}/prepare/top30/dlsmi_summary.json" \
    0.1
  mark_event baseline top30_large_gpu start
  env \
    CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_BLOCKS=8 \
    CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_MB=512 \
    CUSIGNAL_DEVICE_STORAGE_CACHE_MAX_SINGLE_MB=256 \
    CMAKE_BUILD_TYPE=Release \
    PYTHONUNBUFFERED=1 \
    python3 scripts/test/benchmark_all_ops_scales.py \
      --platform ZHONGKEXIN \
      --build-dir "${BUILD_DIR}" \
      --operator-set demo_top30 \
      --operator-sets-file scripts/test/operator_sets.json \
      --scale-profile large-gpu \
      --scale-levels 6 \
      --warmup 1 \
      --repeat 3 \
      --demo-fast \
      --no-build \
      --gpu-only \
      --cpu-baseline-mode refresh \
      --cpu-baseline-file "${BASELINE_FILE}" \
      --output-dir "${OUT}/prepare/top30" \
      --report-mode concise \
      --checkpoint \
      --progress-jsonl "${OUT}/prepare/top30/operator_windows.jsonl" \
      >"${OUT}/prepare/top30/console.log" 2>&1
  local baseline_rc=$?
  mark_event baseline top30_large_gpu end
  stop_monitor
  if [[ "${baseline_rc}" -eq 0 ]]; then
    validate_baseline || baseline_rc=1
  fi
  record_status baseline top30_large_gpu "${baseline_rc}" \
    "large-gpu L6 warmup=1 repeat=3"
  [[ "${baseline_rc}" -eq 0 ]] || return 1

  run_cache_probe default 8 512 256 || return 1
  run_cache_probe expanded 16 4096 3072
  local expanded_rc=$?

  python3 scripts/platform/select_v7_4_cache_mode.py \
    --default-csv \
      "${OUT}/prepare/cache_probe/default/latest_all_ops_scale_benchmark.csv" \
    --expanded-csv \
      "${OUT}/prepare/cache_probe/expanded/latest_all_ops_scale_benchmark.csv" \
    --expanded-return-code "${expanded_rc}" \
    --default-telemetry \
      "${OUT}/prepare/cache_probe/default/dlsmi_summary.json" \
    --expanded-telemetry \
      "${OUT}/prepare/cache_probe/expanded/dlsmi_summary.json" \
    --output-json "${OUT}/prepare/cache_decision.json" \
    --output-tsv "${OUT}/prepare/cache_comparison.tsv"
  local decision_rc=$?
  if [[ "${decision_rc}" -eq 0 ]]; then
    cp "${OUT}/prepare/cache_decision.json" "${DECISION_FILE}"
  fi
  record_status prepare cache_decision "${decision_rc}" "${DECISION_FILE}"
  [[ "${decision_rc}" -eq 0 ]] || return 1
  return 0
}

load_selected_cache_environment()
{
  mapfile -t SELECTED_CACHE_ENV < <(
    python3 - "${DECISION_FILE}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
env = data.get("selected_environment", {})
for key in sorted(env):
    print(f"{key}={env[key]}")
PY
  )
  [[ "${#SELECTED_CACHE_ENV[@]}" -eq 3 ]]
}

run_budgeted()
{
  local now_ns
  local elapsed_seconds
  local remaining_seconds
  now_ns="$(date +%s%N)"
  elapsed_seconds="$(( (now_ns - DEMO_START_NS) / 1000000000 ))"
  remaining_seconds="$(( WALL_LIMIT_SECONDS - elapsed_seconds - 5 ))"
  if [[ "${remaining_seconds}" -le 0 ]]; then
    return 124
  fi
  timeout --signal=INT --kill-after=10 "${remaining_seconds}s" "$@"
}

run_live_demo()
{
  if [[ ! -f "${BASELINE_FILE}" || ! -f "${DECISION_FILE}" ]]; then
    record_status demo preflight 1 "missing baseline or cache decision"
    return 1
  fi
  if [[ ! -x "${TASK1_APP}" || ! -x "${TASK2_APP}" ]]; then
    record_status demo preflight 1 "missing task demo binaries"
    return 1
  fi
  load_selected_cache_environment || return 1
  sha256sum "${BASELINE_FILE}" "${DECISION_FILE}" \
    >"${OUT}/demo/cache_inputs.sha256"

  start_monitor \
    "${OUT}/demo/telemetry/dlsmi_samples.csv" \
    "${OUT}/demo/telemetry/dlsmi_summary.json" \
    0.05
  DEMO_START_NS="$(date +%s%N)"

  mark_event demo task1_L6 start
  run_budgeted env "${SELECTED_CACHE_ENV[@]}" \
    "${TASK1_APP}" --repeat 3 --scale-level 6 \
      --invalid-input-checks --skip-timing-validation \
      >"${OUT}/demo/tasks/task1_radar/console.log" 2>&1
  local task1_rc=$?
  mark_event demo task1_L6 end
  if [[ -d "${TASK1_REPORT}" ]]; then
    cp -a "${TASK1_REPORT}/." "${OUT}/demo/tasks/task1_radar/"
  fi
  record_status demo task1_L6 "${task1_rc}" "repeat=3"

  mark_event demo task2_L6 start
  run_budgeted env \
    -u CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY \
    -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_CORRELATE \
    -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_SPECTROGRAM \
    "${SELECTED_CACHE_ENV[@]}" \
    CUSIGNAL_TASK2_DISABLE_FIXED_FFT_FILTER=1 \
    "${TASK2_APP}" --repeat 3 --scale-level 6 \
      --invalid-input-checks --skip-timing-validation \
      >"${OUT}/demo/tasks/task2_features/console.log" 2>&1
  local task2_rc=$?
  mark_event demo task2_L6 end
  if [[ -d "${TASK2_REPORT}" ]]; then
    cp -a "${TASK2_REPORT}/." "${OUT}/demo/tasks/task2_features/"
  fi
  record_status demo task2_L6 "${task2_rc}" "repeat=3"

  mark_event demo top30_large_gpu start
  run_budgeted env \
    "${SELECTED_CACHE_ENV[@]}" \
    CMAKE_BUILD_TYPE=Release \
    PYTHONUNBUFFERED=1 \
    python3 scripts/test/benchmark_all_ops_scales.py \
      --platform ZHONGKEXIN \
      --build-dir "${BUILD_DIR}" \
      --operator-set demo_top30 \
      --operator-sets-file scripts/test/operator_sets.json \
      --scale-profile large-gpu \
      --scale-levels 6 \
      --warmup 1 \
      --repeat 3 \
      --demo-fast \
      --no-build \
      --gpu-only \
      --cpu-baseline-mode reuse \
      --cpu-baseline-file "${BASELINE_FILE}" \
      --output-dir "${OUT}/demo/top30" \
      --report-mode concise \
      --checkpoint \
      --progress-jsonl "${OUT}/demo/top30/operator_windows.jsonl" \
      >"${OUT}/demo/top30/console.log" 2>&1
  local top30_rc=$?
  mark_event demo top30_large_gpu end

  local demo_end_ns
  local wall_seconds
  demo_end_ns="$(date +%s%N)"
  stop_monitor
  wall_seconds="$(
    python3 - "${DEMO_START_NS}" "${demo_end_ns}" <<'PY'
import sys
print((int(sys.argv[2]) - int(sys.argv[1])) / 1_000_000_000)
PY
  )"
  printf '%s\n' "${wall_seconds}" >"${OUT}/demo/wall_seconds.txt"
  record_status demo top30_large_gpu "${top30_rc}" \
    "large-gpu L6 warmup=1 repeat=3"

  local summary_rc=1
  if [[ "${task1_rc}" -eq 0 && "${task2_rc}" -eq 0 && "${top30_rc}" -eq 0 ]]; then
    python3 scripts/platform/summarize_v7_4_demo.py \
      --task1-metrics \
        "${OUT}/demo/tasks/task1_radar/latest_metrics.json" \
      --task2-metrics \
        "${OUT}/demo/tasks/task2_features/latest_metrics.json" \
      --top30-csv \
        "${OUT}/demo/top30/latest_all_ops_scale_benchmark.csv" \
      --cache-decision "${DECISION_FILE}" \
      --telemetry-json "${OUT}/demo/telemetry/dlsmi_summary.json" \
      --wall-seconds "${wall_seconds}" \
      --wall-limit-seconds "${WALL_LIMIT_SECONDS}" \
      --output-json "${OUT}/demo/summary.json" \
      --output-markdown "${OUT}/demo/summary.md"
    summary_rc=$?
  fi
  record_status gate five_minute_demo "${summary_rc}" \
    "wall=${wall_seconds}s limit=${WALL_LIMIT_SECONDS}s"
  return "${summary_rc}"
}

if [[ "${PHASE}" == "prepare" || "${PHASE}" == "both" ]]; then
  prepare_demo || exit 1
fi

if [[ "${PHASE}" == "demo" || "${PHASE}" == "both" ]]; then
  run_live_demo || exit 1
fi

exit 0
