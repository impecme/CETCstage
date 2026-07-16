#!/usr/bin/env bash

cd /CETC || exit 1
source /zq500/sdk/env.sh || exit 1
set -u -o pipefail
ulimit -c 0 2>/dev/null || true

RUN_ID="${V7_RUN_ID:-V7-0004}"
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/cetc_v7_0004_fixed_fft_${STAMP}"
CONSOLE="/tmp/cetc_v7_0004_console.log"
ARCHIVE="/tmp/cetc_v7_0004_latest.tar.gz"
SOURCE="tests/platform/zx_fixed_fft_probe.cu"
OBJECT="${OUT}/zx_fixed_fft_probe.o"
BINARY="${OUT}/zx_fixed_fft_probe"
BUILD_DIR="${CETC_BUILD_DIR:-build-zx}"
MONITOR_PID=""

mkdir -p "${OUT}/fingerprint" "${OUT}/runs" "${OUT}/telemetry"
rm -f "${CONSOLE}" "${ARCHIVE}"
exec > >(tee "${CONSOLE}") 2>&1

printf 'phase\tcase\trc\tdetail\n' >"${OUT}/status.tsv"

record_status()
{
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"${OUT}/status.tsv"
}

stop_monitor()
{
  if [[ -n "${MONITOR_PID}" ]]; then
    kill -TERM "${MONITOR_PID}" 2>/dev/null || true
    wait "${MONITOR_PID}" 2>/dev/null || true
    MONITOR_PID=""
  fi
}

finalize()
{
  stop_monitor
  local alias_rc=99
  tar -czf "${OUT}.tar.gz" -C /tmp "$(basename "${OUT}")"
  local tar_rc=$?
  if [[ "${tar_rc}" -eq 0 ]]; then
    cp "${OUT}.tar.gz" "${ARCHIVE}"
    alias_rc=$?
  fi
  printf 'OUT=%s\nARCHIVE=%s\nCONSOLE=%s\nTAR_RC=%s\nALIAS_RC=%s\n' \
    "${OUT}" "${ARCHIVE}" "${CONSOLE}" "${tar_rc}" "${alias_rc}"
}
trap finalize EXIT

git rev-parse HEAD >"${OUT}/fingerprint/git_head.txt" 2>/dev/null || true
git status --short >"${OUT}/fingerprint/git_status.txt" 2>/dev/null || true
sha256sum "${SOURCE}" "$0" >"${OUT}/fingerprint/probe_sources.sha256"
dlsmi -L >"${OUT}/fingerprint/dlsmi_devices.txt" 2>&1 || true

COMPILER="$(command -v dlcc 2>/dev/null || true)"
RUNTIME_LIBRARY="$(
  sed -n 's/^CUSIGNAL_ZHONGKEXIN_RUNTIME_LIBRARY:FILEPATH=//p' \
    "${BUILD_DIR}/CMakeCache.txt" 2>/dev/null | head -n 1
)"
FFT_LIBRARY="$(
  sed -n 's/^CUSIGNAL_ZHONGKEXIN_FFT_LIBRARY:FILEPATH=//p' \
    "${BUILD_DIR}/CMakeCache.txt" 2>/dev/null | head -n 1
)"
DLEOL_LIBRARY="$(
  sed -n 's/^CUSIGNAL_ZHONGKEXIN_DLEOL_LIBRARY:FILEPATH=//p' \
    "${BUILD_DIR}/CMakeCache.txt" 2>/dev/null | head -n 1
)"

if [[ -z "${RUNTIME_LIBRARY}" ]]; then
  RUNTIME_LIBRARY="/zq500/sdk/lib/libcurt.so"
fi
if [[ -z "${FFT_LIBRARY}" ]]; then
  FFT_LIBRARY="/zq500/sdk/lib/libdlfft.so"
fi
if [[ -z "${DLEOL_LIBRARY}" ]]; then
  DLEOL_LIBRARY="/zq500/sdk/lib/libdleol.so"
fi

{
  printf 'run_id=%s\n' "${RUN_ID}"
  printf 'compiler=%s\n' "${COMPILER}"
  printf 'runtime=%s\n' "${RUNTIME_LIBRARY}"
  printf 'fft=%s\n' "${FFT_LIBRARY}"
  printf 'dleol=%s\n' "${DLEOL_LIBRARY}"
  "${COMPILER}" --version 2>&1 || true
} >"${OUT}/fingerprint/toolchain.txt"

BUILD_RC=1
if [[ -x "${COMPILER}" && -f "${RUNTIME_LIBRARY}" && -f "${FFT_LIBRARY}" &&
      -f "${DLEOL_LIBRARY}" ]]; then
  "${COMPILER}" -O3 -DNDEBUG -I/zq500/sdk/include -x cuda \
    --cuda-gpu-arch=dlgput64 -std=c++17 -c "${SOURCE}" -o "${OBJECT}" \
    >"${OUT}/compile.log" 2>&1
  COMPILE_RC=$?
  record_status build compile "${COMPILE_RC}" "${SOURCE}"
  if [[ "${COMPILE_RC}" -eq 0 ]]; then
    "${COMPILER}" -O3 -DNDEBUG -fuse-ld=lld -B/zq500/sdk/bin \
      "${OBJECT}" -o "${BINARY}" \
      "${RUNTIME_LIBRARY}" "${FFT_LIBRARY}" "${DLEOL_LIBRARY}" -pthread \
      >"${OUT}/link.log" 2>&1
    LINK_RC=$?
    record_status build link "${LINK_RC}" "${BINARY}"
    if [[ "${LINK_RC}" -eq 0 ]]; then
      BUILD_RC=0
    fi
  else
    record_status build link 99 "compile failed"
  fi
else
  printf 'missing compiler or SDK libraries\n' >"${OUT}/compile.log"
  record_status build prerequisites 1 "compiler/runtime/fft/dleol"
fi

if [[ "${BUILD_RC}" -ne 0 ]]; then
  record_status summary overall 1 "build failed"
  exit 1
fi

python3 scripts/platform/sample_gpu_memory.py \
  --csv "${OUT}/telemetry/dlsmi_samples.csv" \
  --json "${OUT}/telemetry/dlsmi_summary.json" \
  --interval 0.05 &
MONITOR_PID=$!
sleep 1

run_case()
{
  local label="$1"
  local fft_size="$2"
  local batch="$3"
  local profile_repeat="$4"
  local log="${OUT}/runs/${label}.log"

  timeout 240s "${BINARY}" \
    "${fft_size}" "${batch}" 2 10 "${profile_repeat}" \
    >"${log}" 2>&1
  local rc=$?
  record_status probe "${label}" "${rc}" "fft=${fft_size},batch=${batch}"
  grep '^RESULT ' "${log}" >>"${OUT}/results.txt" 2>/dev/null || true
  grep '^MARK ' "${log}" >>"${OUT}/markers.txt" 2>/dev/null || true
  return "${rc}"
}

OVERALL_RC=0
run_case task2_spectrogram 512 2784 400 || OVERALL_RC=1
run_case task2_correlate 4096 97 400 || OVERALL_RC=1
run_case task2_cwt 4096 1440 80 || OVERALL_RC=1
run_case task1_pulse_compression 2048 192 400 || OVERALL_RC=1
run_case task1_pulse_doppler 256 2048 400 || OVERALL_RC=1

stop_monitor
record_status summary overall "${OVERALL_RC}" "probe execution"
exit "${OVERALL_RC}"
