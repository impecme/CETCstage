#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build-zx"
REPEAT=3
TASKS="both"
DO_BUILD=1
EXTENDED=0
EXTREME=0
ONLY_EXTREME=0

usage() {
  cat <<'USAGE'
Usage: scripts/explore_task_acceleration.sh [options]

Run a bounded set of custom task shapes and rank successful candidates by
measured end-to-end CPU/GPU speedup. Candidate results remain under /tmp and
are not promoted into the delivery reports.

Options:
  --build-dir DIR       Build directory (default: <repo>/build-zx)
  --repeat N            Measured repeats per candidate (default: 3)
  --task NAME           task1|task2|both (default: both)
  --extended            Include the largest valid workload candidates
  --extreme             Include the largest staged workload candidates
  --only-extreme        Run only the largest staged candidate for each task
  --no-build            Reuse existing task binaries
  -h, --help            Show this help
USAGE
}

die() {
  echo "[task-explore] error: $*" >&2
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
    --task)
      [[ $# -ge 2 ]] || die "--task requires a value"
      TASKS="$2"
      shift 2
      ;;
    --extended)
      EXTENDED=1
      shift
      ;;
    --extreme)
      EXTENDED=1
      EXTREME=1
      shift
      ;;
    --only-extreme)
      EXTENDED=1
      EXTREME=1
      ONLY_EXTREME=1
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
      die "unknown option: $1"
      ;;
  esac
done

[[ "${REPEAT}" =~ ^[1-9][0-9]*$ ]] || die "--repeat must be a positive integer"
case "${TASKS}" in
  task1|task2|both) ;;
  *) die "--task must be task1, task2, or both" ;;
esac
if [[ "${BUILD_DIR}" != /* ]]; then
  BUILD_DIR="${REPO_ROOT}/${BUILD_DIR}"
fi

if [[ -f /zq500/sdk/env.sh ]]; then
  set +u
  # shellcheck source=/dev/null
  source /zq500/sdk/env.sh ""
  set -u
fi

if [[ "${DO_BUILD}" -eq 1 ]]; then
  "${SCRIPT_DIR}/build.sh" --build-dir "${BUILD_DIR}" \
    --target task1_radar_demo --target task2_features_demo
fi

TASK1_EXE="${BUILD_DIR}/demo/task1_radar/task1_radar_demo"
TASK2_EXE="${BUILD_DIR}/demo/task2_features/task2_features_demo"
[[ -x "${TASK1_EXE}" ]] || die "missing ${TASK1_EXE}; omit --no-build or build first"
[[ -x "${TASK2_EXE}" ]] || die "missing ${TASK2_EXE}; omit --no-build or build first"

RUN_ROOT="/tmp/cetc_task_acceleration_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${RUN_ROOT}"
RESULTS_TSV="${RUN_ROOT}/results.tsv"
printf 'task\tlabel\tshape\tcpu_ms\tgpu_ms\tkernel_ms\tspeedup\texit_code\tvalidation\tlog\n' >"${RESULTS_TSV}"

record_result() {
  local task="$1"
  local label="$2"
  local log_path="$3"
  local exit_code="$4"
  local metrics_path="${REPO_ROOT}/data/.reports_staging/demo/${task}/latest_metrics.json"
  python3 - "${RESULTS_TSV}" "${task}" "${label}" "${metrics_path}" "${exit_code}" "${log_path}" <<'PY'
import json
import pathlib
import sys

output, task, label, metrics_path, exit_code, log_path = sys.argv[1:]
metrics = pathlib.Path(metrics_path)
row = [task, label, "unknown", "", "", "", "", exit_code, "missing", log_path]
if metrics.is_file():
    try:
        data = json.loads(metrics.read_text(encoding="utf-8"))
        scenario = data.get("scenario", {})
        if task == "task1_radar":
            shape = f"{scenario.get('num_pulses', '?')}x{scenario.get('samples_per_pulse', '?')}"
        else:
            shape = f"{scenario.get('num_frames', '?')}x{scenario.get('samples_per_frame', '?')}"
        timing = data.get("timings", {}).get("total", {})
        cpu = float(timing.get("cpu_ms", 0.0))
        gpu = float(timing.get("gpu_ms", 0.0))
        kernel = float(timing.get("gpu_kernel_ms", 0.0))
        checks = data.get("validation", {}).get("checks", [])
        numeric = all(item.get("business_numeric_pass", False) for item in data.get("repeat_runs", []))
        validation = "pass" if int(exit_code) == 0 and numeric else "fail"
        row = [task, label, shape, f"{cpu:.6f}", f"{gpu:.6f}", f"{kernel:.6f}",
               f"{cpu / gpu:.6f}" if gpu > 0 else "0.000000", exit_code, validation, log_path]
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        pass
with pathlib.Path(output).open("a", encoding="utf-8") as handle:
    handle.write("\t".join(row) + "\n")
PY
}

run_candidate() {
  local task="$1"
  local label="$2"
  local exe="$3"
  shift 3
  local log_path="${RUN_ROOT}/${task}_${label}.log"
  local args=(--repeat "${REPEAT}" --invalid-input-checks --skip-timing-validation "$@")
  echo "[task-explore] ${task}/${label}: ${exe} ${args[*]}"
  set +e
  "${exe}" "${args[@]}" 2>&1 | tee "${log_path}"
  local status=${PIPESTATUS[0]}
  set -e
  record_result "${task}" "${label}" "${log_path}" "${status}"
}

if [[ "${TASKS}" == "task1" || "${TASKS}" == "both" ]]; then
  if [[ "${ONLY_EXTREME}" -eq 0 ]]; then
  run_candidate task1_radar l5 "${TASK1_EXE}" --scale-level 5
  run_candidate task1_radar l6 "${TASK1_EXE}" --scale-level 6
  run_candidate task1_radar p192_s2048 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 192 --samples-per-pulse 2048 \
    --template-length 384 --pulse-compression-nfft 2048 --pulse-doppler-nfft 256
  run_candidate task1_radar p256_s1536 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 256 --samples-per-pulse 1536 \
    --template-length 384 --pulse-compression-nfft 2048 --pulse-doppler-nfft 256
  run_candidate task1_radar p128_s2048 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 128 --samples-per-pulse 2048 \
    --template-length 512 --pulse-compression-nfft 2048 --pulse-doppler-nfft 128
  run_candidate task1_radar p192_s1536_t512 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 192 --samples-per-pulse 1536 \
    --template-length 512 --pulse-compression-nfft 2048 --pulse-doppler-nfft 256
  run_candidate task1_radar p160_s2048 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 160 --samples-per-pulse 2048 \
    --template-length 512 --pulse-compression-nfft 2048 --pulse-doppler-nfft 256
  run_candidate task1_radar p128_s3072 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 128 --samples-per-pulse 3072 \
    --template-length 768 --pulse-compression-nfft 4096 --pulse-doppler-nfft 128
  run_candidate task1_radar p160_s4096 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 160 --samples-per-pulse 4096 \
    --template-length 1024 --pulse-compression-nfft 4096 --pulse-doppler-nfft 256
  run_candidate task1_radar p128_s6144 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 128 --samples-per-pulse 6144 \
    --template-length 1536 --pulse-compression-nfft 8192 --pulse-doppler-nfft 128
  run_candidate task1_radar p128_s8192 "${TASK1_EXE}" \
    --scale-level 6 --num-pulses 128 --samples-per-pulse 8192 \
    --template-length 2048 --pulse-compression-nfft 8192 --pulse-doppler-nfft 128
  if [[ "${EXTENDED}" -eq 1 ]]; then
    run_candidate task1_radar p128_s12288 "${TASK1_EXE}" \
      --scale-level 6 --num-pulses 128 --samples-per-pulse 12288 \
      --template-length 3072 --pulse-compression-nfft 16384 --pulse-doppler-nfft 128
    run_candidate task1_radar p128_s16384 "${TASK1_EXE}" \
      --scale-level 6 --num-pulses 128 --samples-per-pulse 16384 \
      --template-length 4096 --pulse-compression-nfft 16384 --pulse-doppler-nfft 128
  fi
  fi
  if [[ "${EXTREME}" -eq 1 ]]; then
    run_candidate task1_radar p128_s32768 "${TASK1_EXE}" \
      --scale-level 6 --num-pulses 128 --samples-per-pulse 32768 \
      --template-length 8192 --pulse-compression-nfft 32768 --pulse-doppler-nfft 128
  fi
fi

if [[ "${TASKS}" == "task2" || "${TASKS}" == "both" ]]; then
  if [[ "${ONLY_EXTREME}" -eq 0 ]]; then
  run_candidate task2_features l5 "${TASK2_EXE}" --scale-level 5
  run_candidate task2_features l6 "${TASK2_EXE}" --scale-level 6
  run_candidate task2_features f96_s3072 "${TASK2_EXE}" \
    --scale-level 6 --num-frames 96 --samples-per-frame 3072 --template-length 768
  run_candidate task2_features f160_s2048 "${TASK2_EXE}" \
    --scale-level 6 --num-frames 160 --samples-per-frame 2048 --template-length 512 \
    --spectrogram-nperseg 256 --spectrogram-noverlap 192 --spectrogram-nfft 512
  run_candidate task2_features f160_s3072 "${TASK2_EXE}" \
    --scale-level 6 --num-frames 160 --samples-per-frame 3072 --template-length 1024 \
    --filter-numtaps 257 --spectrogram-nperseg 384 --spectrogram-noverlap 288 --spectrogram-nfft 512
  run_candidate task2_features f128_s4096 "${TASK2_EXE}" \
    --scale-level 6 --num-frames 128 --samples-per-frame 4096 --template-length 1024 \
    --filter-numtaps 257 --spectrogram-nperseg 512 --spectrogram-noverlap 384 --spectrogram-nfft 512
  run_candidate task2_features f128_s4096_t1536 "${TASK2_EXE}" \
    --scale-level 6 --num-frames 128 --samples-per-frame 4096 --template-length 1536 \
    --filter-numtaps 321 --spectrogram-nperseg 512 --spectrogram-noverlap 384 --spectrogram-nfft 512
  if [[ "${EXTENDED}" -eq 1 ]]; then
    run_candidate task2_features f128_s6144 "${TASK2_EXE}" \
      --scale-level 6 --num-frames 128 --samples-per-frame 6144 --template-length 1536 \
      --filter-numtaps 321 --spectrogram-nperseg 768 --spectrogram-noverlap 576 --spectrogram-nfft 1024
    run_candidate task2_features f128_s8192 "${TASK2_EXE}" \
      --scale-level 6 --num-frames 128 --samples-per-frame 8192 --template-length 2048 \
      --filter-numtaps 385 --spectrogram-nperseg 1024 --spectrogram-noverlap 768 --spectrogram-nfft 1024
  fi
  fi
  if [[ "${EXTREME}" -eq 1 ]]; then
    run_candidate task2_features f128_s16384 "${TASK2_EXE}" \
      --scale-level 6 --num-frames 128 --samples-per-frame 16384 --template-length 4096 \
      --filter-numtaps 513 --spectrogram-nperseg 2048 --spectrogram-noverlap 1536 --spectrogram-nfft 2048
  fi
fi

python3 - "${RESULTS_TSV}" <<'PY'
import csv
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
rows = list(csv.DictReader(path.open(encoding="utf-8"), delimiter="\t"))
rows.sort(key=lambda row: float(row["speedup"] or 0.0), reverse=True)
print("\n[task-explore] ranked candidates")
print("task\tlabel\tshape\tcpu_ms\tgpu_ms\tkernel_ms\tspeedup\texit_code\tvalidation")
for row in rows:
    print("\t".join(row[key] for key in (
        "task", "label", "shape", "cpu_ms", "gpu_ms", "kernel_ms", "speedup",
        "exit_code", "validation")))
print(f"[task-explore] artifacts: {path.parent}")
PY
