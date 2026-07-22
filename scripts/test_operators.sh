#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_BUILD_DIR="${PROJECT_ROOT}/build-zx"
DEFAULT_BUILD_TYPE="Release"
DEFAULT_PLATFORM="${CUSIGNAL_PLATFORM:-ZHONGKEXIN}"
OPERATOR_CONTRACT="${PROJECT_ROOT}/tests/contracts/operator_sets.json"

MODULE_FILTER="all"
OPERATOR_FILTER="all"
OPERATOR_SET="all81"
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

TEST_REGISTRY=()

usage() {
  cat <<EOF
Usage: scripts/test_operators.sh [options]

Options:
  --module NAME          Filter module, default: all
  --operator NAME        Filter operator, default: all
  --operator-set NAME    Filter by tests/contracts/operator_sets.json set, default: all81
  --case-set NAME        smoke|accuracy|perf|full, default: full
  --emit-report          Write reports and generated samples
  --verbose              Enable verbose runner output
  --gpu-only-perf        Perf mode only: skip CPU reference/timing and run GPU timings
  --demo-fast            Use warmup=1 repeat=3 unless --warmup/--repeat are explicit
  --warmup N             Warmup iterations for perf runners, default: 5
  --repeat N             Repeat iterations for perf runners, default: 30
  --build-dir PATH       Build directory, default: <repo>/build-zx
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

load_test_registry() {
  require_command python3
  [[ -f "${OPERATOR_CONTRACT}" ]] || die "missing operator contract: ${OPERATOR_CONTRACT}"

  mapfile -t TEST_REGISTRY < <(
    python3 - "${OPERATOR_CONTRACT}" "${OPERATOR_SET}" <<'PY'
import json
import pathlib
import sys

contract_path = pathlib.Path(sys.argv[1])
operator_set_name = sys.argv[2]
contract = json.loads(contract_path.read_text(encoding="utf-8"))
sets = contract.get("sets", {})
if not isinstance(sets, dict):
    raise SystemExit("operator contract is missing sets")

all81_item = sets.get("all81", {})
all81 = all81_item.get("operators") if isinstance(all81_item, dict) else None
expected_count = all81_item.get("expected_count") if isinstance(all81_item, dict) else None
if expected_count != 81 or not isinstance(all81, list) or len(all81) != expected_count or len(set(all81)) != len(all81):
    raise SystemExit("all81 operator contract is invalid")

resolving = set()


def resolve_set(name):
    if name in resolving:
        raise SystemExit(f"operator set cycle: {name}")
    item = sets.get(name)
    if not isinstance(item, dict):
        raise SystemExit(f"unknown operator set: {name}")
    resolving.add(name)
    if "operators" in item:
        operators = item.get("operators")
        if not isinstance(operators, list) or not all(isinstance(value, str) for value in operators):
            raise SystemExit(f"operator set {name} has invalid operators")
        resolved = list(operators)
    else:
        include_names = item.get("include_sets", [])
        exclude_names = item.get("exclude_sets", [])
        if not isinstance(include_names, list) or not isinstance(exclude_names, list):
            raise SystemExit(f"operator set {name} has invalid include/exclude sets")
        include = set()
        for include_name in include_names:
            include.update(resolve_set(include_name))
        exclude = set()
        for exclude_name in exclude_names:
            exclude.update(resolve_set(exclude_name))
        resolved = [key for key in all81 if key in include and key not in exclude]
    resolving.remove(name)
    expected = item.get("expected_count")
    if not isinstance(expected, int) or len(resolved) != expected or len(set(resolved)) != len(resolved):
        raise SystemExit(f"operator set {name} expected_count mismatch")
    unknown = sorted(set(resolved) - set(all81))
    if unknown:
        raise SystemExit(f"operator set {name} contains unknown operators: {', '.join(unknown)}")
    return resolved


selected = resolve_set(operator_set_name)

for key in selected:
    parts = key.split("/")
    if len(parts) != 2 or not all(parts):
        raise SystemExit(f"invalid operator key: {key!r}")
    module, operator = parts
    target = f"{module}_test_{operator}"
    binary = f"tests/unit/{module}/{target}"
    print(f"{module}:{operator}:{target}:{binary}")
PY
  )
  [[ ${#TEST_REGISTRY[@]} -gt 0 ]] || die "operator contract did not produce any tests"
}

load_zhongkexin_sdk_env() {
  if [[ -f /zq500/sdk/env.sh ]]; then
    set +u
    # shellcheck source=/dev/null
    source /zq500/sdk/env.sh ""
    set -u
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
      --operator-set)
        [[ $# -ge 2 ]] || die "--operator-set requires a value"
        OPERATOR_SET="$2"
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
  [[ "${REPEAT}" =~ ^[1-9][0-9]*$ ]] || die "--repeat must be a positive integer"
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
  local jobs="${JOBS:-$(auto_jobs)}"
  local build_args=(
    --build-dir "${BUILD_DIR}"
    --build-type "${BUILD_TYPE}"
    --jobs "${jobs}"
  )
  local target
  for target in "${SELECTED_TARGETS[@]}"; do
    build_args+=(--target "${target}")
  done
  "${SCRIPT_DIR}/build.sh" "${build_args[@]}"
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
  load_test_registry
  if [[ "${PLATFORM}" == "ZHONGKEXIN" ]]; then
    load_zhongkexin_sdk_env
  fi
  collect_selected_tests

  if [[ "${LIST_ONLY}" -eq 1 ]]; then
    list_selected_tests
    exit 0
  fi

  log "timing       : warmup=${WARMUP} repeat=${REPEAT}$([[ ${DEMO_FAST} -eq 1 ]] && printf ' (demo-fast)')"
  log "operator set : ${OPERATOR_SET}"

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
