#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

DEFAULT_BUILD_DIR="${PROJECT_ROOT}/build"
DEFAULT_BUILD_TYPE="Release"
DEFAULT_PLATFORM="${CUSIGNAL_PLATFORM:-ZHONGKEXIN}"

MODULE_FILTER="all"
OPERATOR_FILTER="all"
CASE_SET="full"
EMIT_REPORT=0
VERBOSE=0
GPU_ONLY_PERF=0
DEMO_FAST=0
WARMUP=5
REPEAT=30
WARMUP_SET=0
REPEAT_SET=0
BUILD_DIR="${DEFAULT_BUILD_DIR}"
BUILD_TYPE="${DEFAULT_BUILD_TYPE}"
PLATFORM="${DEFAULT_PLATFORM}"
JOBS=""
DO_BUILD=1
LIST_ONLY=0
SHOW_HELP=0

TEST_REGISTRY=(
  "waveforms:chirp:waveforms_test_chirp:tests/unit/waveforms/waveforms_test_chirp"
  "waveforms:gausspulse:waveforms_test_gausspulse:tests/unit/waveforms/waveforms_test_gausspulse"
  "waveforms:sawtooth:waveforms_test_sawtooth:tests/unit/waveforms/waveforms_test_sawtooth"
  "waveforms:square:waveforms_test_square:tests/unit/waveforms/waveforms_test_square"
  "waveforms:unit_impulse:waveforms_test_unit_impulse:tests/unit/waveforms/waveforms_test_unit_impulse"
  "bsplines:cubic:bsplines_test_cubic:tests/unit/bsplines/bsplines_test_cubic"
  "bsplines:quadratic:bsplines_test_quadratic:tests/unit/bsplines/bsplines_test_quadratic"
  "bsplines:gauss_spline:bsplines_test_gauss_spline:tests/unit/bsplines/bsplines_test_gauss_spline"
  "windows:get_window:windows_test_get_window:tests/unit/windows/windows_test_get_window"
  "windows:barthann:windows_test_barthann:tests/unit/windows/windows_test_barthann"
  "windows:bartlett:windows_test_bartlett:tests/unit/windows/windows_test_bartlett"
  "windows:blackman:windows_test_blackman:tests/unit/windows/windows_test_blackman"
  "windows:blackmanharris:windows_test_blackmanharris:tests/unit/windows/windows_test_blackmanharris"
  "windows:bohman:windows_test_bohman:tests/unit/windows/windows_test_bohman"
  "windows:boxcar:windows_test_boxcar:tests/unit/windows/windows_test_boxcar"
  "windows:chebwin:windows_test_chebwin:tests/unit/windows/windows_test_chebwin"
  "windows:cosine:windows_test_cosine:tests/unit/windows/windows_test_cosine"
  "windows:exponential:windows_test_exponential:tests/unit/windows/windows_test_exponential"
  "windows:flattop:windows_test_flattop:tests/unit/windows/windows_test_flattop"
  "windows:gaussian:windows_test_gaussian:tests/unit/windows/windows_test_gaussian"
  "windows:general_cosine:windows_test_general_cosine:tests/unit/windows/windows_test_general_cosine"
  "windows:general_gaussian:windows_test_general_gaussian:tests/unit/windows/windows_test_general_gaussian"
  "windows:general_hamming:windows_test_general_hamming:tests/unit/windows/windows_test_general_hamming"
  "windows:hamming:windows_test_hamming:tests/unit/windows/windows_test_hamming"
  "windows:hann:windows_test_hann:tests/unit/windows/windows_test_hann"
  "windows:kaiser:windows_test_kaiser:tests/unit/windows/windows_test_kaiser"
  "windows:nuttall:windows_test_nuttall:tests/unit/windows/windows_test_nuttall"
  "windows:parzen:windows_test_parzen:tests/unit/windows/windows_test_parzen"
  "windows:taylor:windows_test_taylor:tests/unit/windows/windows_test_taylor"
  "windows:triang:windows_test_triang:tests/unit/windows/windows_test_triang"
  "windows:tukey:windows_test_tukey:tests/unit/windows/windows_test_tukey"
  "filter_design:kaiser_beta:filter_design_test_kaiser_beta:tests/unit/filter_design/filter_design_test_kaiser_beta"
  "filter_design:kaiser_atten:filter_design_test_kaiser_atten:tests/unit/filter_design/filter_design_test_kaiser_atten"
  "filter_design:cmplx_sort:filter_design_test_cmplx_sort:tests/unit/filter_design/filter_design_test_cmplx_sort"
  "filter_design:firwin:filter_design_test_firwin:tests/unit/filter_design/filter_design_test_firwin"
  "filter_design:firwin2:filter_design_test_firwin2:tests/unit/filter_design/filter_design_test_firwin2"
  "filtering:wiener:filtering_test_wiener:tests/unit/filtering/filtering_test_wiener"
  "filtering:firfilter:filtering_test_firfilter:tests/unit/filtering/filtering_test_firfilter"
  "filtering:lfilter:filtering_test_lfilter:tests/unit/filtering/filtering_test_lfilter"
  "filtering:firfilter_zi:filtering_test_firfilter_zi:tests/unit/filtering/filtering_test_firfilter_zi"
  "filtering:lfilter_zi:filtering_test_lfilter_zi:tests/unit/filtering/filtering_test_lfilter_zi"
  "filtering:firfilter2:filtering_test_firfilter2:tests/unit/filtering/filtering_test_firfilter2"
  "filtering:filtfilt:filtering_test_filtfilt:tests/unit/filtering/filtering_test_filtfilt"
  "filtering:sosfilt:filtering_test_sosfilt:tests/unit/filtering/filtering_test_sosfilt"
  "filtering:hilbert:filtering_test_hilbert:tests/unit/filtering/filtering_test_hilbert"
  "filtering:hilbert2:filtering_test_hilbert2:tests/unit/filtering/filtering_test_hilbert2"
  "filtering:detrend:filtering_test_detrend:tests/unit/filtering/filtering_test_detrend"
  "filtering:freq_shift:filtering_test_freq_shift:tests/unit/filtering/filtering_test_freq_shift"
  "filtering:channelize_poly:filtering_test_channelize_poly:tests/unit/filtering/filtering_test_channelize_poly"
  "filtering:decimate:filtering_test_decimate:tests/unit/filtering/filtering_test_decimate"
  "filtering:resample:filtering_test_resample:tests/unit/filtering/filtering_test_resample"
  "filtering:resample_poly:filtering_test_resample_poly:tests/unit/filtering/filtering_test_resample_poly"
  "filtering:upfirdn:filtering_test_upfirdn:tests/unit/filtering/filtering_test_upfirdn"
  "radartools:pulse_compression:radartools_test_pulse_compression:tests/unit/radartools/radartools_test_pulse_compression"
  "radartools:pulse_doppler:radartools_test_pulse_doppler:tests/unit/radartools/radartools_test_pulse_doppler"
  "radartools:ambgfun:radartools_test_ambgfun:tests/unit/radartools/radartools_test_ambgfun"
  "radartools:cfar_alpha:radartools_test_cfar_alpha:tests/unit/radartools/radartools_test_cfar_alpha"
  "radartools:ca_cfar:radartools_test_ca_cfar:tests/unit/radartools/radartools_test_ca_cfar"
  "radartools:mvdr:radartools_test_mvdr:tests/unit/radartools/radartools_test_mvdr"
  "spectral:lombscargle:spectral_test_lombscargle:tests/unit/spectral/spectral_test_lombscargle"
  "spectral:periodogram:spectral_test_periodogram:tests/unit/spectral/spectral_test_periodogram"
  "spectral:welch:spectral_test_welch:tests/unit/spectral/spectral_test_welch"
  "spectral:csd:spectral_test_csd:tests/unit/spectral/spectral_test_csd"
  "spectral:spectrogram:spectral_test_spectrogram:tests/unit/spectral/spectral_test_spectrogram"
  "spectral:stft:spectral_test_stft:tests/unit/spectral/spectral_test_stft"
  "spectral:istft:spectral_test_istft:tests/unit/spectral/spectral_test_istft"
  "spectral:coherence:spectral_test_coherence:tests/unit/spectral/spectral_test_coherence"
  "spectral:vectorstrength:spectral_test_vectorstrength:tests/unit/spectral/spectral_test_vectorstrength"
  "wavelets:qmf:wavelets_test_qmf:tests/unit/wavelets/wavelets_test_qmf"
  "wavelets:morlet:wavelets_test_morlet:tests/unit/wavelets/wavelets_test_morlet"
  "wavelets:ricker:wavelets_test_ricker:tests/unit/wavelets/wavelets_test_ricker"
  "wavelets:morlet2:wavelets_test_morlet2:tests/unit/wavelets/wavelets_test_morlet2"
  "wavelets:cwt:wavelets_test_cwt:tests/unit/wavelets/wavelets_test_cwt"
  "correlate:correlate:correlate_test_correlate:tests/unit/correlate/correlate_test_correlate"
  "correlate:correlate2d:correlate_test_correlate2d:tests/unit/correlate/correlate_test_correlate2d"
  "correlate:correlation_lags:correlate_test_correlation_lags:tests/unit/correlate/correlate_test_correlation_lags"
  "demod:fm_demod:demod_test_fm_demod:tests/unit/demod/demod_test_fm_demod"
  "estimation:kalman_filter:estimation_test_kalman_filter:tests/unit/estimation/estimation_test_kalman_filter"
  "peak_finding:argrelextrema:peak_finding_test_argrelextrema:tests/unit/peak_finding/peak_finding_test_argrelextrema"
  "peak_finding:argrelmin:peak_finding_test_argrelmin:tests/unit/peak_finding/peak_finding_test_argrelmin"
  "peak_finding:argrelmax:peak_finding_test_argrelmax:tests/unit/peak_finding/peak_finding_test_argrelmax"
)

usage() {
  cat <<EOF
Usage: scripts/test/run_all_tests.sh [options]

Options:
  --module NAME          Filter module, default: all
  --operator NAME        Filter operator, default: all
  --case-set NAME        smoke|accuracy|perf|full, default: full
  --emit-report          Write reports and generated samples
  --verbose              Enable verbose runner output
  --gpu-only-perf        Perf mode only: skip CPU reference/timing and run GPU timings
  --demo-fast            Use warmup=1 repeat=3 unless --warmup/--repeat are explicit
  --warmup N             Warmup iterations for perf runners, default: 5
  --repeat N             Repeat iterations for perf runners, default: 30
  --build-dir PATH       Build directory, default: <repo>/build
  --build-type TYPE      CMake build type, default: Release
  --platform NAME        CUSIGNAL platform: ZHONGKEXIN, default: ${PLATFORM}
  --jobs N               Parallel build jobs, default: auto-detect
  --no-build             Skip configure/build and reuse existing binaries
  --list                 List the registered test entries after filtering
  --help                 Show this help message
EOF
}

log() {
  echo "[cusignal-test] $*"
}

die() {
  echo "[cusignal-test] error: $*" >&2
  exit 2
}

auto_jobs() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  else
    getconf _NPROCESSORS_ONLN
  fi
}

require_command() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "missing required command: ${cmd}"
}

load_zhongkexin_sdk_env() {
  if command -v dlcc >/dev/null 2>&1; then
    return 0
  fi
  if [[ -n "${ZHONGKEXIN_CXX_COMPILER:-}" && -x "${ZHONGKEXIN_CXX_COMPILER}" ]]; then
    return 0
  fi
  if [[ -f /zq500/sdk/env.sh ]]; then
    set +u
    # shellcheck source=/dev/null
    source /zq500/sdk/env.sh ""
    set -u
    return 0
  fi
}

resolve_path() {
  local value="$1"
  if [[ "${value}" = /* ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${PROJECT_ROOT}/${value}"
  fi
}

matches_filter() {
  local module="$1"
  local operator="$2"
  [[ "${MODULE_FILTER}" = "all" || "${MODULE_FILTER}" = "${module}" ]] &&
    [[ "${OPERATOR_FILTER}" = "all" || "${OPERATOR_FILTER}" = "${operator}" ]]
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --module)
        [[ $# -ge 2 ]] || die "--module requires a value"
        MODULE_FILTER="$2"
        shift 2
        ;;
      --operator)
        [[ $# -ge 2 ]] || die "--operator requires a value"
        OPERATOR_FILTER="$2"
        shift 2
        ;;
      --case-set)
        [[ $# -ge 2 ]] || die "--case-set requires a value"
        CASE_SET="$2"
        shift 2
        ;;
      --warmup)
        [[ $# -ge 2 ]] || die "--warmup requires a value"
        WARMUP="$2"
        WARMUP_SET=1
        shift 2
        ;;
      --repeat)
        [[ $# -ge 2 ]] || die "--repeat requires a value"
        REPEAT="$2"
        REPEAT_SET=1
        shift 2
        ;;
      --build-dir)
        [[ $# -ge 2 ]] || die "--build-dir requires a value"
        BUILD_DIR="$(resolve_path "$2")"
        shift 2
        ;;
      --build-type)
        [[ $# -ge 2 ]] || die "--build-type requires a value"
        BUILD_TYPE="$2"
        shift 2
        ;;
      --platform)
        [[ $# -ge 2 ]] || die "--platform requires a value"
        PLATFORM="$2"
        shift 2
        ;;
      --jobs)
        [[ $# -ge 2 ]] || die "--jobs requires a value"
        JOBS="$2"
        shift 2
        ;;
      --emit-report)
        EMIT_REPORT=1
        shift
        ;;
      --verbose)
        VERBOSE=1
        shift
        ;;
      --gpu-only-perf)
        GPU_ONLY_PERF=1
        shift
        ;;
      --demo-fast)
        DEMO_FAST=1
        shift
        ;;
      --no-build)
        DO_BUILD=0
        shift
        ;;
      --list)
        LIST_ONLY=1
        shift
        ;;
      --help)
        SHOW_HELP=1
        shift
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

apply_demo_fast_defaults() {
  if (( DEMO_FAST )); then
    (( WARMUP_SET )) || WARMUP=1
    (( REPEAT_SET )) || REPEAT=3
  fi
}

validate_args() {
  case "${CASE_SET}" in
    smoke|accuracy|perf|full) ;;
    *) die "invalid --case-set: ${CASE_SET}" ;;
  esac

  PLATFORM="$(printf '%s' "${PLATFORM}" | tr '[:lower:]' '[:upper:]')"
  case "${PLATFORM}" in
    ZHONGKEXIN) ;;
    *) die "invalid --platform: ${PLATFORM}" ;;
  esac

  [[ "${WARMUP}" =~ ^[0-9]+$ ]] || die "--warmup must be a non-negative integer"
  [[ "${REPEAT}" =~ ^[0-9]+$ ]] || die "--repeat must be a non-negative integer"
  if [[ -n "${JOBS}" ]]; then
    [[ "${JOBS}" =~ ^[1-9][0-9]*$ ]] || die "--jobs must be a positive integer"
  fi
}

collect_selected_tests() {
  SELECTED_ENTRIES=()
  SELECTED_TARGETS=()
  local entry
  for entry in "${TEST_REGISTRY[@]}"; do
    IFS=: read -r module operator target binary_rel <<<"${entry}"
    if matches_filter "${module}" "${operator}"; then
      SELECTED_ENTRIES+=("${entry}")
      SELECTED_TARGETS+=("${target}")
    fi
  done

  [[ ${#SELECTED_ENTRIES[@]} -gt 0 ]] || die "no registered tests matched the requested filters"
}

list_selected_tests() {
  local entry
  for entry in "${SELECTED_ENTRIES[@]}"; do
    IFS=: read -r module operator target binary_rel <<<"${entry}"
    printf '%s\t%s\t%s\t%s\n' "${module}" "${operator}" "${target}" "${binary_rel}"
  done
}

configure_and_build() {
  require_command cmake
  local jobs="${JOBS:-$(auto_jobs)}"

  log "project root : ${PROJECT_ROOT}"
  log "build dir    : ${BUILD_DIR}"
  log "build type   : ${BUILD_TYPE}"
  log "platform     : ${PLATFORM}"
  log "gpu arch     : ZQ500 dlgput64 via dlcc"
  log "jobs         : ${jobs}"

  local cmake_args=(
    -S "${PROJECT_ROOT}"
    -B "${BUILD_DIR}"
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
    -DCUSIGNAL_PLATFORM="${PLATFORM}"
  )
  local zhongkexin_cxx="${ZHONGKEXIN_CXX_COMPILER:-}"
  if [[ -z "${zhongkexin_cxx}" ]]; then
    zhongkexin_cxx="$(command -v dlcc || true)"
  fi
  [[ -n "${zhongkexin_cxx}" ]] || die "dlcc was not found for ZHONGKEXIN build"
  log "cxx compiler : ${zhongkexin_cxx}"
  cmake_args+=(-DCMAKE_CXX_COMPILER="${zhongkexin_cxx}")

  cmake "${cmake_args[@]}"

  cmake --build "${BUILD_DIR}" --target "${SELECTED_TARGETS[@]}" --parallel "${jobs}"
}

verify_binaries() {
  local entry
  for entry in "${SELECTED_ENTRIES[@]}"; do
    IFS=: read -r module operator target binary_rel <<<"${entry}"
    local binary_path="${BUILD_DIR}/${binary_rel}"
    [[ -x "${binary_path}" ]] || die "missing test binary: ${binary_path}"
  done
}

run_selected_tests() {
  local entry
  local total=0
  local passed=0
  local failed=()

  for entry in "${SELECTED_ENTRIES[@]}"; do
    IFS=: read -r module operator target binary_rel <<<"${entry}"
    local binary_path="${BUILD_DIR}/${binary_rel}"
    local cmd=("${binary_path}" "--case-set" "${CASE_SET}" "--warmup" "${WARMUP}" "--repeat" "${REPEAT}")
    (( EMIT_REPORT )) && cmd+=("--emit-report")
    (( VERBOSE )) && cmd+=("--verbose")
    (( GPU_ONLY_PERF )) && cmd+=("--gpu-only-perf")

    log "running ${module}/${operator}"
    ((total += 1))
    if "${cmd[@]}"; then
      ((passed += 1))
    else
      failed+=("${module}/${operator}")
    fi
  done

  log "summary: passed ${passed}/${total}"
  if [[ ${#failed[@]} -gt 0 ]]; then
    log "failed : ${failed[*]}"
    return 1
  fi
  return 0
}

main() {
  parse_args "$@"

  if [[ "${SHOW_HELP}" -eq 1 ]]; then
    usage
    exit 0
  fi

  apply_demo_fast_defaults
  validate_args
  if [[ "${PLATFORM}" == "ZHONGKEXIN" ]]; then
    load_zhongkexin_sdk_env
  fi
  collect_selected_tests

  if [[ "${LIST_ONLY}" -eq 1 ]]; then
    list_selected_tests
    exit 0
  fi

  log "timing       : warmup=${WARMUP} repeat=${REPEAT}$([[ ${DEMO_FAST} -eq 1 ]] && printf ' (demo-fast)')"

  if [[ "${DO_BUILD}" -eq 1 ]]; then
    configure_and_build
  fi

  verify_binaries

  if run_selected_tests; then
    exit 0
  fi
  exit 1
}

main "$@"
