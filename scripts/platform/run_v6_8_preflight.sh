#!/usr/bin/env bash

set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${V6_8_BUILD_DIR:-${PROJECT_ROOT}/build-zx}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RUN_ID="${V6_8_RUN_ID:-V6-0138}"
OUT="${V6_8_OUT:-/tmp/cetc_v6_0138_v6_8_preflight_${STAMP}}"
LATEST_ARCHIVE="${V6_8_LATEST_ARCHIVE:-/tmp/cetc_v6_0138_latest.tar.gz}"
REPORT_ROOT="${PROJECT_ROOT}/data/reports"
GENERATED_DEMO_ROOT="${PROJECT_ROOT}/data/generated/demo"
REPORTS_OWNED=0
GENERATED_DEMO_OWNED=0
MONITOR_PID=""

mkdir -p \
  "${OUT}/fingerprint" \
  "${OUT}/logs" \
  "${OUT}/audits" \
  "${OUT}/platform" \
  "${OUT}/all81_reports" \
  "${OUT}/tasks/first_process" \
  "${OUT}/tasks/warm" \
  "${OUT}/task_schema_validation" \
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

stop_monitor() {
  if [[ -n "${MONITOR_PID}" ]]; then
    kill -TERM "${MONITOR_PID}" 2>/dev/null || true
    wait "${MONITOR_PID}" 2>/dev/null || true
    MONITOR_PID=""
  fi
}

finalize() {
  local rc=$?
  local manifest_rc=0
  local reports_rc=0
  local archive_rc=0
  trap - EXIT INT TERM
  set +e
  stop_monitor

  if [[ "${REPORTS_OWNED}" -eq 1 ]]; then
    rm -rf "${REPORT_ROOT}/unit" "${REPORT_ROOT}/demo"
  fi
  if [[ "${GENERATED_DEMO_OWNED}" -eq 1 ]]; then
    rm -rf "${GENERATED_DEMO_ROOT}"
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
    "data/reports must match the preflight inventory"
  if [[ "${reports_rc}" -ne 0 ]]; then
    rc=1
  fi

  cp "${BUILD_DIR}/CMakeCache.txt" "${OUT}/fingerprint/" 2>/dev/null || true
  cp "${BUILD_DIR}/compile_commands.json" "${OUT}/fingerprint/" 2>/dev/null || true
  if [[ -d "${BUILD_DIR}/reports/zx_compatibility" ]]; then
    cp -a "${BUILD_DIR}/reports/zx_compatibility" "${OUT}/platform/"
  fi

  record_status final overall "${rc}" \
    "${RUN_ID} hard-gate preflight"
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
  printf '[v6.8] phase=%s case=%s\n' "${phase}" "${case_name}"
  "$@" 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
  record_status "${phase}" "${case_name}" "${rc}" "${log}"
  return "${rc}"
}

run_monitored_phase() {
  local phase="$1"
  local case_name="$2"
  shift 2
  local prefix="${OUT}/telemetry/${case_name}"
  local log="${OUT}/logs/${phase}_${case_name}.log"
  local rc
  local monitor_rc
  local monitor_pid

  python3 scripts/platform/sample_gpu_memory.py \
    --csv "${prefix}.csv" \
    --json "${prefix}.json" \
    --interval 0.2 &
  monitor_pid=$!
  MONITOR_PID="${monitor_pid}"
  sleep 0.4
  printf '[v6.8] monitored phase=%s case=%s\n' "${phase}" "${case_name}"
  "$@" 2>&1 | tee "${log}"
  rc=${PIPESTATUS[0]}
  kill -TERM "${monitor_pid}" 2>/dev/null || true
  wait "${monitor_pid}" 2>/dev/null
  monitor_rc=$?
  MONITOR_PID=""
  record_status "${phase}" "${case_name}" "${rc}" "${log}"
  record_status telemetry "${case_name}" "${monitor_rc}" "${prefix}.json"
  return "${rc}"
}

preflight_guard() {
  if [[ -e "${REPORT_ROOT}/unit" || -e "${REPORT_ROOT}/demo" ]]; then
    echo "[v6.8] refusing to remove pre-existing data/reports/unit or data/reports/demo" >&2
    return 2
  fi
  if [[ -e "${GENERATED_DEMO_ROOT}" ]]; then
    echo "[v6.8] refusing to remove pre-existing data/generated/demo" >&2
    return 2
  fi
  REPORTS_OWNED=1
  GENERATED_DEMO_OWNED=1
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
  {
    printf 'timestamp=%s\n' "$(date --iso-8601=seconds)"
    printf 'hostname=%s\n' "$(hostname)"
    uname -a
    command -v dlcc || true
    dlcc --version 2>&1 || true
    cmake --version 2>&1 || true
    python3 --version 2>&1 || true
    dlsmi -L 2>&1 || true
    env | sort | grep -E '^(PATH|LD_LIBRARY_PATH|CMAKE|CUDA|ZX|ZQ)' || true
  } >"${OUT}/fingerprint/toolchain.txt"
}

configure_release() {
  local compiler="${ZHONGKEXIN_CXX_COMPILER:-$(command -v dlcc || true)}"
  if [[ -z "${compiler}" ]]; then
    echo "[v6.8] dlcc was not found" >&2
    return 2
  fi
  cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
    -DCMAKE_CXX_COMPILER="${compiler}" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
}

write_registry() {
  local raw="${OUT}/all81_registry.raw.txt"
  scripts/test/run_all_tests.sh \
    --list \
    --build-dir "${BUILD_DIR}" \
    --platform ZHONGKEXIN \
    >"${raw}"
  local rc=$?
  [[ "${rc}" -eq 0 ]] || return "${rc}"

  awk -F '\t' 'NF == 4 && $1 != "" && $2 != "" && $3 != "" && $4 != ""' \
    "${raw}" >"${OUT}/all81_registry.tsv"
  [[ "$(wc -l <"${OUT}/all81_registry.tsv")" -eq 81 ]]
}

run_static_audits() {
  python3 scripts/test/validate_operator_sets.py \
    --registry "${OUT}/all81_registry.tsv" \
    --sets scripts/test/operator_sets.json \
    --summary-json "${OUT}/audits/operator_sets.json"
  local rc=$?
  [[ "${rc}" -eq 0 ]] || return "${rc}"

  python3 scripts/test/audit_operator_interfaces.py \
    --registry "${OUT}/all81_registry.tsv" \
    --sets scripts/test/operator_sets.json \
    --output-dir "${OUT}/audits/interface" \
    --contract-markdown "${OUT}/audits/operator_contract_inventory.md"
  rc=$?
  [[ "${rc}" -eq 0 ]] || return "${rc}"

  python3 scripts/test/validate_operator_type_contracts.py \
    --registry "${OUT}/all81_registry.tsv" \
    --contracts scripts/test/operator_type_contracts.json \
    --output-dir "${OUT}/audits/types" \
    --contract-markdown "${OUT}/audits/operator_type_contracts.md"
  rc=$?
  [[ "${rc}" -eq 0 ]] || return "${rc}"

  python3 scripts/test/audit_dtype_test_coverage.py \
    --registry "${OUT}/all81_registry.tsv" \
    --contracts scripts/test/operator_type_contracts.json \
    --output-dir "${OUT}/audits/dtype" \
    --summary-markdown "${OUT}/audits/dtype.md"
  rc=$?
  [[ "${rc}" -eq 0 ]] || return "${rc}"

  python3 scripts/test/audit_task_steps.py \
    --contracts scripts/test/task_step_contracts.json \
    --output-dir "${OUT}/audits/task_steps" \
    --summary-markdown "${OUT}/audits/task_steps.md"
}

assert_static_audits() {
  python3 - "${OUT}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
registry = [
    fields
    for line in (root / "all81_registry.tsv").read_text().splitlines()
    if len(fields := line.split("\t")) == 4 and all(fields)
]
registry_keys = {(fields[0], fields[1]) for fields in registry}
operator_sets = json.loads((root / "audits/operator_sets.json").read_text())
interface = json.loads(
    (root / "audits/interface/latest_interface_audit.json").read_text()
)["summary"]
types = json.loads(
    (root / "audits/types/latest_type_contracts.json").read_text()
)["summary"]
dtype = json.loads(
    (root / "audits/dtype/latest_dtype_test_coverage.json").read_text()
)["summary"]
steps = json.loads(
    (root / "audits/task_steps/latest_task_step_audit.json").read_text()
)["summary"]

checks = {
    "registry_81": len(registry) == 81 and len(registry_keys) == 81,
    "operator_sets": operator_sets.get("status") == "passed",
    "interface": interface.get("status") == "passed"
        and interface.get("operator_count") == 81
        and interface.get("failed_count") == 0,
    "types": types.get("status") == "passed"
        and types.get("operator_count") == 81
        and types.get("compatibility_gap_count", 0) == 0,
    "dtype": dtype.get("status") == "passed"
        and dtype.get("operator_count") == 81
        and dtype.get("operator_dtype_missing_edges") == 0,
    "task_steps": steps.get("status") == "passed"
        and steps.get("calculation_step_count") == 14
        and steps.get("timing_gap_count") == 0
        and steps.get("accuracy_gap_count") == 0
        and steps.get("failure_count") == 0,
}
(root / "audits/assertions.json").write_text(
    json.dumps(checks, indent=2, sort_keys=True) + "\n"
)
print(json.dumps(checks, sort_keys=True))
raise SystemExit(0 if all(checks.values()) else 1)
PY
}

run_all81_full() {
  scripts/test/run_all_tests.sh \
    --case-set full \
    --demo-fast \
    --emit-report \
    --build-dir "${BUILD_DIR}" \
    --platform ZHONGKEXIN
}

assert_all81() {
  local log="${OUT}/logs/regression_all81_full.log"
  grep -Fq '[cusignal-test] summary: passed 81/81' "${log}"
}

copy_all81_reports() {
  if [[ ! -d "${REPORT_ROOT}/unit" ]]; then
    echo "[v6.8] all81 report directory is missing" >&2
    return 1
  fi
  cp -a "${REPORT_ROOT}/unit/." "${OUT}/all81_reports/"
}

build_task_and_platform_targets() {
  cmake --build "${BUILD_DIR}" --target \
    task1_radar_demo \
    task2_features_demo \
    cusignal_type_contract_tests \
    zx_compat_compile_probes \
    zx_compat_runtime_probes \
    zx_forbidden_api_scan \
    --parallel
}

assert_release_build() {
  grep -Fq 'CMAKE_BUILD_TYPE:STRING=Release' "${BUILD_DIR}/CMakeCache.txt"
  grep -Eq 'CMAKE_CXX_FLAGS_RELEASE:STRING=.*-O3.*-DNDEBUG|CMAKE_CXX_FLAGS_RELEASE:STRING=.*-DNDEBUG.*-O3' \
    "${BUILD_DIR}/CMakeCache.txt"
}

run_platform_ctest() {
  ctest --test-dir "${BUILD_DIR}" \
    -R '^(cusignal_type_contract|zx_compat_runtime_safe|zx_forbidden_api_scan_test)$' \
    --output-on-failure
}

run_runtime_probe() {
  "${BUILD_DIR}/tests/platform/zx_compat_runtime_probes"
}

assert_runtime_probe() {
  python3 - "${OUT}/logs/platform_runtime_probe.log" \
    "${OUT}/platform/runtime_probe.tsv" <<'PY'
import sys
from pathlib import Path

source = Path(sys.argv[1])
output = Path(sys.argv[2])
line = next(
    (
        raw for raw in source.read_text(errors="replace").splitlines()
        if raw.startswith("[zx/compat] PASS")
    ),
    "",
)
tokens = {}
for token in line.split():
    if "=" in token:
        key, value = token.split("=", 1)
        tokens[key] = value
status_keys = [
    "graph_capture_begin_status",
    "graph_capture_work_status",
    "graph_capture_end_status",
    "graph_instantiate_status",
    "graph_launch_status",
    "graph_sync_status",
]
required = [
    "device",
    "concurrent_kernels",
    "async_engines",
    "single_plan_ms",
    "batch8_plan_ms",
    "single_workspace_bytes",
    "batch8_workspace_bytes",
    "nondefault_stream",
    "cufft_set_stream",
    "graph",
    *status_keys,
]
valid = bool(line) and all(key in tokens for key in required)
if valid:
    try:
        statuses = [int(tokens[key]) for key in status_keys]
    except ValueError:
        valid = False
        statuses = []
else:
    statuses = []
if valid and tokens["graph"] == "supported":
    valid = all(value == 0 for value in statuses)
elif valid and tokens["graph"] == "unsupported":
    called = [value for value in statuses if value != -1]
    valid = bool(called) and any(value != 0 for value in called)
else:
    valid = False
with output.open("w") as handle:
    handle.write("field\tvalue\n")
    for key in required:
        handle.write(f"{key}\t{tokens.get(key, 'missing')}\n")
    handle.write(f"valid_lifecycle_result\t{str(valid).lower()}\n")
raise SystemExit(0 if valid else 1)
PY
}

run_task_matrix() {
  local mode="$1"
  local task="$2"
  local app="$3"
  local report_source="$4"
  local repeat="$5"
  local aggregate_rc=0
  local scale
  local rc
  local destination
  local start_ns
  local end_ns

  for scale in 1 2 3 4 5 6; do
    destination="${OUT}/tasks/${mode}/${task}/L${scale}"
    mkdir -p "${destination}"
    start_ns="$(date +%s%N)"
    "${app}" \
      --repeat "${repeat}" \
      --scale-level "${scale}" \
      --invalid-input-checks \
      2>&1 | tee "${destination}/console.log"
    rc=${PIPESTATUS[0]}
    end_ns="$(date +%s%N)"
    printf '%s\n' "$((end_ns - start_ns))" \
      >"${destination}/process_wall_ns.txt"
    record_status task "${mode}_${task}_L${scale}" "${rc}" \
      "repeat=${repeat}"
    if [[ -d "${report_source}" ]]; then
      cp -a "${report_source}/." "${destination}/"
    fi
    if [[ "${rc}" -ne 0 ]]; then
      aggregate_rc=1
    fi
  done
  return "${aggregate_rc}"
}

validate_task_schemas() {
  local mode
  local scale
  local validation_root
  local output
  local rc
  local aggregate_rc=0
  for mode in first_process warm; do
    for scale in 1 2 3 4 5 6; do
      validation_root="${OUT}/task_schema_validation/${mode}/L${scale}/reports"
      output="${OUT}/task_schema_validation/${mode}/L${scale}/summary.json"
      mkdir -p \
        "${validation_root}/task1_radar" \
        "${validation_root}/task2_features"
      cp "${OUT}/tasks/${mode}/task1_radar/L${scale}/latest_step_metrics.json" \
        "${OUT}/tasks/${mode}/task1_radar/L${scale}/latest_step_metrics.csv" \
        "${validation_root}/task1_radar/"
      cp "${OUT}/tasks/${mode}/task2_features/L${scale}/latest_step_metrics.json" \
        "${OUT}/tasks/${mode}/task2_features/L${scale}/latest_step_metrics.csv" \
        "${validation_root}/task2_features/"
      python3 scripts/test/validate_task_step_reports.py \
        --report-root "${validation_root}" \
        --output "${output}"
      rc=$?
      record_status schema "${mode}_L${scale}" "${rc}" "${output}"
      if [[ "${rc}" -ne 0 ]]; then
        aggregate_rc=1
      fi
    done
  done
  return "${aggregate_rc}"
}

summarize_task_matrix() {
  python3 scripts/platform/summarize_v6_8_tasks.py \
    --first-root "${OUT}/tasks/first_process" \
    --warm-root "${OUT}/tasks/warm" \
    --output-dir "${OUT}/task_summary"
}

assert_telemetry() {
  python3 - "${OUT}/telemetry" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
names = (
    "first_process_task1_radar",
    "first_process_task2_features",
    "warm_task1_radar",
    "warm_task2_features",
)
rows = []
passed = True
for name in names:
    path = root / f"{name}.json"
    if not path.exists():
        rows.append((name, False, 0, None, None))
        passed = False
        continue
    data = json.loads(path.read_text())
    valid = bool(data.get("available")) and int(data.get("sample_count", 0)) > 0
    passed = passed and valid
    rows.append((
        name,
        valid,
        data.get("sample_count", 0),
        data.get("used_mib_max"),
        data.get("util_percent_max"),
    ))
with (root / "summary.tsv").open("w") as handle:
    handle.write("phase\tavailable\tsample_count\tused_mib_max\tutil_percent_max\n")
    for row in rows:
        handle.write("\t".join(str(value).lower() for value in row) + "\n")
raise SystemExit(0 if passed else 1)
PY
}

main() {
  hash_manifests "${OUT}/manifest_before.sha256"
  hash_reports "${OUT}/reports_before.sha256"

  run_phase guard clean_report_roots preflight_guard || return 1
  REPORTS_OWNED=1
  GENERATED_DEMO_OWNED=1
  run_phase fingerprint source_and_toolchain collect_fingerprint || return 1
  run_phase build configure_release configure_release || return 1
  run_phase audit registry write_registry || return 1
  run_phase audit static_contracts run_static_audits || return 1
  run_phase audit static_assertions assert_static_audits || return 1
  run_phase regression all81_full run_all81_full || return 1
  run_phase regression all81_assert assert_all81 || return 1
  run_phase evidence copy_all81_reports copy_all81_reports || return 1
  run_phase build task_platform_targets build_task_and_platform_targets || return 1
  run_phase build release_flags assert_release_build || return 1
  run_phase platform ctest run_platform_ctest || return 1
  run_phase platform runtime_probe run_runtime_probe || return 1
  run_phase platform runtime_probe_assert assert_runtime_probe || return 1

  run_monitored_phase task first_process_task1_radar \
    run_task_matrix first_process task1_radar \
    "${BUILD_DIR}/demo/task1_radar/task1_radar_demo" \
    "${REPORT_ROOT}/demo/task1_radar" 1 || return 1
  run_monitored_phase task first_process_task2_features \
    run_task_matrix first_process task2_features \
    "${BUILD_DIR}/demo/task2_features/task2_features_demo" \
    "${REPORT_ROOT}/demo/task2_features" 1 || return 1
  run_monitored_phase task warm_task1_radar \
    run_task_matrix warm task1_radar \
    "${BUILD_DIR}/demo/task1_radar/task1_radar_demo" \
    "${REPORT_ROOT}/demo/task1_radar" 5 || return 1
  run_monitored_phase task warm_task2_features \
    run_task_matrix warm task2_features \
    "${BUILD_DIR}/demo/task2_features/task2_features_demo" \
    "${REPORT_ROOT}/demo/task2_features" 5 || return 1

  run_phase schema task_reports validate_task_schemas || return 1
  run_phase summary task_matrix summarize_task_matrix || return 1
  run_phase telemetry assert assert_telemetry || return 1
  return 0
}

main
