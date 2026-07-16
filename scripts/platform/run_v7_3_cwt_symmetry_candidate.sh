#!/usr/bin/env bash

cd /CETC || exit 1
source /zq500/sdk/env.sh || exit 1
set -u -o pipefail
ulimit -c 0 2>/dev/null || true

RUN_ID="${V7_RUN_ID:-V7-0007}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/cetc_v7_0007_cwt_symmetry_${STAMP}"
BACKUP="/tmp/cetc_v7_0007_backup_${STAMP}"
CONSOLE="/tmp/cetc_v7_0007_console.log"
ARCHIVE="/tmp/cetc_v7_0007_latest.tar.gz"
BUILD_DIR="${CETC_BUILD_DIR:-build-v7-task}"
TASK2_REPORT="data/reports/demo/task2_features"
TASK1_REPORT="data/reports/demo/task1_radar"
MONITOR_PID=""
RESTORED=0

mkdir -p \
  "${OUT}/fingerprint" \
  "${OUT}/logs" \
  "${OUT}/ab" \
  "${OUT}/task2_full" \
  "${OUT}/task1_smoke" \
  "${OUT}/audits" \
  "${OUT}/telemetry" \
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
  restore_repository_outputs
  [[ ! -s "${OUT}/reports_restore.diff" ]] || integrity_rc=1
  [[ ! -s "${OUT}/manifests_restore.diff" ]] || integrity_rc=1
  record_status integrity restore "${integrity_rc}" "reports/manifests"
  if [[ "${integrity_rc}" -ne 0 ]]; then
    final_rc=1
  fi
  record_status final overall "${final_rc}" \
    "${RUN_ID} Task2 Morlet2 CWT symmetry candidate"
  tar -czf "${OUT}.tar.gz" -C /tmp "$(basename "${OUT}")"
  tar_rc=$?
  if [[ "${tar_rc}" -eq 0 ]]; then
    cp "${OUT}.tar.gz" "${ARCHIVE}"
    alias_rc=$?
  fi
  if [[ "${tar_rc}" -ne 0 || "${alias_rc}" -ne 0 ]]; then
    final_rc=1
  fi
  printf 'OUT=%s\nARCHIVE=%s\nCONSOLE=%s\nRC=%s\nTAR_RC=%s\nALIAS_RC=%s\n' \
    "${OUT}" "${ARCHIVE}" "${CONSOLE}" "${final_rc}" "${tar_rc}" "${alias_rc}"
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
  demo/task2_features/task2_features_demo.cpp \
  demo/task2_features/task2_features_zx_gpu.cu \
  demo/task2_features/task2_features_zx_gpu.hpp \
  "$0" \
  >"${OUT}/fingerprint/candidate_sources.sha256"
{
  printf 'run_id=%s\n' "${RUN_ID}"
  date --iso-8601=seconds
  dlcc --version 2>&1
  cmake --version 2>&1
  dlsmi -L 2>&1
} >"${OUT}/fingerprint/toolchain.txt"

cmake -S . -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_CXX_COMPILER="$(command -v dlcc)" \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  >"${OUT}/logs/configure.log" 2>&1
CONFIGURE_RC=$?
record_status build configure "${CONFIGURE_RC}" "${BUILD_DIR}"
if [[ "${CONFIGURE_RC}" -ne 0 ]]; then
  exit 1
fi

cmake --build "${BUILD_DIR}" --target \
  task1_radar_demo task2_features_demo --parallel \
  >"${OUT}/logs/build.log" 2>&1
BUILD_RC=$?
record_status build task_demos "${BUILD_RC}" "task1/task2"
if [[ "${BUILD_RC}" -ne 0 ]]; then
  exit 1
fi

scripts/test/run_all_tests.sh \
  --list \
  --build-dir "${BUILD_DIR}" \
  --platform ZHONGKEXIN \
  >"${OUT}/all81_registry.raw.txt" 2>&1
REGISTRY_RC=$?
if [[ "${REGISTRY_RC}" -eq 0 ]]; then
  awk -F '\t' 'NF == 4 && $1 != "" && $2 != "" && $3 != "" && $4 != ""' \
    "${OUT}/all81_registry.raw.txt" >"${OUT}/all81_registry.tsv"
  [[ "$(wc -l <"${OUT}/all81_registry.tsv")" -eq 81 ]] || REGISTRY_RC=1
fi
record_status audit registry "${REGISTRY_RC}" "81 operators"
if [[ "${REGISTRY_RC}" -ne 0 ]]; then
  exit 1
fi

python3 scripts/test/audit_dtype_test_coverage.py \
  --registry "${OUT}/all81_registry.tsv" \
  --contracts scripts/test/operator_type_contracts.json \
  --output-dir "${OUT}/audits/dtype" \
  --summary-markdown "${OUT}/audits/dtype.md"
DTYPE_RC=$?
record_status audit dtype "${DTYPE_RC}" "compatibility gaps"
if [[ "${DTYPE_RC}" -ne 0 ]]; then
  exit 1
fi

python3 scripts/test/audit_task_steps.py \
  --contracts scripts/test/task_step_contracts.json \
  --output-dir "${OUT}/audits/task_steps" \
  --summary-markdown "${OUT}/audits/task_steps.md"
TASK_STEPS_RC=$?
record_status audit task_steps "${TASK_STEPS_RC}" "14 calculation steps"
if [[ "${TASK_STEPS_RC}" -ne 0 ]]; then
  exit 1
fi

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
AUDIT_GATE_RC=$?
record_status gate static_audits "${AUDIT_GATE_RC}" "dtype/task steps"
if [[ "${AUDIT_GATE_RC}" -ne 0 ]]; then
  exit 1
fi

python3 scripts/platform/sample_gpu_memory.py \
  --csv "${OUT}/telemetry/dlsmi_samples.csv" \
  --json "${OUT}/telemetry/dlsmi_summary.json" \
  --interval 0.05 &
MONITOR_PID=$!
sleep 1

TASK2_APP="${BUILD_DIR}/demo/task2_features/task2_features_demo"
TASK1_APP="${BUILD_DIR}/demo/task1_radar/task1_radar_demo"

run_task2_ab()
{
  local mode="$1"
  local scale="$2"
  local destination="${OUT}/ab/${mode}/L${scale}"
  local rc
  mkdir -p "${destination}"
  mark_event task2_ab "${mode}_L${scale}" start
  if [[ "${mode}" == "baseline" ]]; then
    env -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_CORRELATE \
      -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_SPECTROGRAM \
      -u CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY \
      CUSIGNAL_TASK2_DISABLE_FIXED_FFT_FILTER=1 \
      "${TASK2_APP}" --repeat 5 --scale-level "${scale}" \
        --invalid-input-checks --skip-timing-validation \
        >"${destination}/console.log" 2>&1
  else
    env -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_CORRELATE \
      -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_SPECTROGRAM \
      CUSIGNAL_TASK2_DISABLE_FIXED_FFT_FILTER=1 \
      CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY=1 \
      "${TASK2_APP}" --repeat 5 --scale-level "${scale}" \
        --invalid-input-checks --skip-timing-validation \
        >"${destination}/console.log" 2>&1
  fi
  rc=$?
  mark_event task2_ab "${mode}_L${scale}" end
  record_status task2_ab "${mode}_L${scale}" "${rc}" "repeat=5"
  if [[ -d "${TASK2_REPORT}" ]]; then
    cp -a "${TASK2_REPORT}/." "${destination}/"
  fi
  return "${rc}"
}

AB_RC=0
for scale in 3 5 6; do
  run_task2_ab baseline "${scale}" || AB_RC=1
  run_task2_ab candidate "${scale}" || AB_RC=1
done

python3 - "${OUT}/ab" "${OUT}/candidate_summary.tsv" \
  "${OUT}/candidate_gate.json" <<'PY'
import json
import statistics
import sys
from pathlib import Path

root = Path(sys.argv[1])
tsv_path = Path(sys.argv[2])
json_path = Path(sys.argv[3])
scales = (3, 5, 6)
records = {}
passed = True

for mode in ("baseline", "candidate"):
    for scale in scales:
        path = root / mode / f"L{scale}" / "latest_metrics.json"
        if not path.exists():
            records[(mode, scale)] = {"available": False}
            passed = False
            continue
        data = json.loads(path.read_text())
        timings = data["timings"]
        repeats = [
            float(item["gpu_total_ms"])
            for item in data.get("repeat_runs", [])
            if "gpu_total_ms" in item
        ]
        records[(mode, scale)] = {
            "available": True,
            "validation": bool(data["validation"]["pass"]),
            "total_ms": statistics.median(repeats),
            "cwt_ms": float(timings["cwt"]["gpu_ms"]),
            "spectrogram_ms": float(timings["spectrogram"]["gpu_ms"]),
            "correlate_ms": float(timings["correlate"]["gpu_ms"]),
            "cwt_mixed": float(data["cwt_error"]["mixed_error"]),
            "spectrogram_mixed": float(data["spectrogram_error"]["mixed_error"]),
            "correlate_mixed": float(data["correlate_error"]["mixed_error"]),
        }
        passed = passed and bool(data["validation"]["pass"])

checks = {}
required_cwt = {3: 0.20, 5: 0.20, 6: 0.20}
required_total = {3: 0.03, 5: 0.05, 6: 0.05}
for scale in scales:
    baseline = records.get(("baseline", scale), {})
    candidate = records.get(("candidate", scale), {})
    available = baseline.get("available") and candidate.get("available")
    checks[f"L{scale}_available"] = bool(available)
    if not available:
        passed = False
        continue
    cwt_gain = 1.0 - candidate["cwt_ms"] / baseline["cwt_ms"]
    total_gain = 1.0 - candidate["total_ms"] / baseline["total_ms"]
    numeric = (
        candidate["cwt_mixed"] <= 1.0e-4
        and candidate["spectrogram_mixed"] <= 1.0e-4
        and candidate["correlate_mixed"] <= 1.0e-4
    )
    checks[f"L{scale}_cwt_gain"] = cwt_gain
    checks[f"L{scale}_total_gain"] = total_gain
    checks[f"L{scale}_numeric"] = numeric
    passed = passed and numeric
    passed = passed and cwt_gain >= required_cwt[scale]
    passed = passed and total_gain >= required_total[scale]

with tsv_path.open("w") as handle:
    handle.write(
        "mode\tscale\tvalidation\ttotal_ms\tcwt_ms\tspectrogram_ms\t"
        "correlate_ms\tcwt_mixed\tspectrogram_mixed\tcorrelate_mixed\n"
    )
    for mode in ("baseline", "candidate"):
        for scale in scales:
            item = records[(mode, scale)]
            handle.write(
                f"{mode}\tL{scale}\t{item.get('validation', False)}\t"
                f"{item.get('total_ms', '')}\t{item.get('cwt_ms', '')}\t"
                f"{item.get('spectrogram_ms', '')}\t"
                f"{item.get('correlate_ms', '')}\t"
                f"{item.get('cwt_mixed', '')}\t"
                f"{item.get('spectrogram_mixed', '')}\t"
                f"{item.get('correlate_mixed', '')}\n"
            )

json_path.write_text(json.dumps(
    {"status": "passed" if passed else "failed", "checks": checks},
    indent=2,
    sort_keys=True,
) + "\n")
raise SystemExit(0 if passed else 1)
PY
GATE_RC=$?
record_status gate task2_cwt_symmetry "${GATE_RC}" "${OUT}/candidate_gate.json"
if [[ "${AB_RC}" -ne 0 || "${GATE_RC}" -ne 0 ]]; then
  exit 1
fi

TASK2_FULL_RC=0
for scale in 1 2 4; do
  destination="${OUT}/task2_full/L${scale}"
  mkdir -p "${destination}"
  mark_event task2_full "L${scale}" start
  env -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_CORRELATE \
    -u CUSIGNAL_TASK2_DISABLE_FIXED_FFT_SPECTROGRAM \
    -u CUSIGNAL_TASK2_ENABLE_CWT_SYMMETRY \
    CUSIGNAL_TASK2_DISABLE_FIXED_FFT_FILTER=1 \
    "${TASK2_APP}" --repeat 3 --scale-level "${scale}" \
      --invalid-input-checks --skip-timing-validation \
      >"${destination}/console.log" 2>&1
  rc=$?
  mark_event task2_full "L${scale}" end
  record_status task2_full "L${scale}" "${rc}" "repeat=3"
  if [[ -d "${TASK2_REPORT}" ]]; then
    cp -a "${TASK2_REPORT}/." "${destination}/"
  fi
  [[ "${rc}" -eq 0 ]] || TASK2_FULL_RC=1
done
if [[ "${TASK2_FULL_RC}" -ne 0 ]]; then
  exit 1
fi

TASK1_RC=0
for scale in 1 6; do
  destination="${OUT}/task1_smoke/L${scale}"
  mkdir -p "${destination}"
  mark_event task1_smoke "L${scale}" start
  "${TASK1_APP}" --repeat 2 --scale-level "${scale}" \
    --invalid-input-checks --skip-timing-validation \
      >"${destination}/console.log" 2>&1
  rc=$?
  mark_event task1_smoke "L${scale}" end
  record_status task1_smoke "L${scale}" "${rc}" "repeat=2"
  if [[ -d "${TASK1_REPORT}" ]]; then
    cp -a "${TASK1_REPORT}/." "${destination}/"
  fi
  [[ "${rc}" -eq 0 ]] || TASK1_RC=1
done
if [[ "${TASK1_RC}" -ne 0 ]]; then
  exit 1
fi

mark_event regression all81 start
scripts/test/run_all_tests.sh \
  --case-set full \
  --demo-fast \
  --emit-report \
  --build-dir "${BUILD_DIR}" \
  --platform ZHONGKEXIN \
  >"${OUT}/logs/all81_full.log" 2>&1
ALL81_RC=$?
mark_event regression all81 end
if ! grep -Fq '[cusignal-test] summary: passed 81/81' "${OUT}/logs/all81_full.log"; then
  ALL81_RC=1
fi
record_status regression all81 "${ALL81_RC}" "81/81"
if [[ "${ALL81_RC}" -ne 0 ]]; then
  exit 1
fi

if [[ -d data/reports/unit ]]; then
  cp -a data/reports/unit "${OUT}/all81_reports"
fi

stop_monitor
exit 0
