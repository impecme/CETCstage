#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
requirements="${PY_REQUIREMENTS:-${root}/scripts/platform/zhongkexin_python_requirements.txt}"
wheel_dir="${PY_WHEEL_DIR:-${root}/third_party/python_wheels}"

check_sdk=1
ensure_fftw=0
install_python=0
download_python_wheels=0
strict=1

log() {
  echo "[zx-deps] $*"
}

warn() {
  echo "[zx-deps] warning: $*" >&2
}

fail() {
  if [[ "${strict}" == "1" ]]; then
    echo "[zx-deps] error: $*" >&2
    exit 2
  fi
  warn "$*"
}

usage() {
  cat <<'USAGE'
Usage: scripts/platform/prepare_zhongkexin_deps.sh [options]

Checks and prepares user-space dependencies for the Zhongkexin container.
No sudo or apt commands are used.

Options:
  --ensure-fftw              Build/install FFTW under third_party/fftw/install if missing.
  --install-python           Install missing Python modules with python3 -m pip install --user.
  --download-python-wheels   Download Python wheels into third_party/python_wheels.
  --skip-sdk-check           Skip /zq500 SDK header/library checks.
  --warn-only                Report missing required dependencies without failing.
  -h, --help                 Show this help.

Environment:
  INSTALL_PYTHON_DEPS=1      Same as --install-python.
  DOWNLOAD_PYTHON_WHEELS=1   Same as --download-python-wheels.
  PY_WHEEL_DIR=PATH          Override wheel cache directory.
  PY_REQUIREMENTS=PATH       Override Python requirements file.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ensure-fftw)
      ensure_fftw=1
      ;;
    --install-python)
      install_python=1
      ;;
    --download-python-wheels)
      download_python_wheels=1
      ;;
    --skip-sdk-check)
      check_sdk=0
      ;;
    --warn-only)
      strict=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

[[ "${INSTALL_PYTHON_DEPS:-0}" == "1" ]] && install_python=1
[[ "${DOWNLOAD_PYTHON_WHEELS:-0}" == "1" ]] && download_python_wheels=1

has_command() {
  command -v "$1" >/dev/null 2>&1
}

source_sdk_if_available() {
  [[ "${check_sdk}" == "1" ]] || return 0
  has_command dlcc && return 0
  [[ -f /zq500/sdk/env.sh ]] || return 0

  log "source sdk env: /zq500/sdk/env.sh"
  set +u
  # shellcheck disable=SC1091
  source /zq500/sdk/env.sh ""
  set -u
}

require_command() {
  local cmd="$1"
  has_command "${cmd}" || fail "missing required command: ${cmd}"
}

check_cmake_version() {
  require_command cmake
  local version
  version="$(cmake --version | sed -n '1s/.* version //p')"
  python3 - "${version}" <<'PY' || fail "cmake ${version:-unknown} is below required 3.18"
import sys
parts = sys.argv[1].split(".") if len(sys.argv) > 1 else ["0"]
nums = []
for part in parts[:3]:
    try:
        nums.append(int(part))
    except ValueError:
        nums.append(0)
while len(nums) < 3:
    nums.append(0)
sys.exit(0 if tuple(nums) >= (3, 18, 0) else 1)
PY
  log "cmake: ${version}"
}

check_required_commands() {
  require_command python3
  check_cmake_version
  require_command make

  if has_command dlcc; then
    log "dlcc: $(command -v dlcc)"
  elif [[ "${check_sdk}" == "1" ]]; then
    fail "missing dlcc; source /zq500/sdk/env.sh before building"
  else
    warn "dlcc not found"
  fi
}

check_sdk_files() {
  [[ "${check_sdk}" == "1" ]] || return 0

  local sdk_env="/zq500/sdk/env.sh"
  if [[ -f "${sdk_env}" ]]; then
    log "sdk env: ${sdk_env}"
  else
    fail "missing Zhongkexin SDK env: ${sdk_env}"
  fi

  local include_root="${SDK_DIR:-/zq500/sdk}/include"
  [[ -f "${include_root}/cuda_runtime.h" ]] || fail "missing SDK header: ${include_root}/cuda_runtime.h"
  [[ -f "${include_root}/cufft.h" ]] || fail "missing SDK header: ${include_root}/cufft.h"
  [[ -f "${include_root}/cublas_v2.h" ]] || fail "missing SDK header: ${include_root}/cublas_v2.h"
  [[ -f "${include_root}/cusolverDn.h" ]] || fail "missing SDK header: ${include_root}/cusolverDn.h"

  local lib_root="${SDK_DIR:-/zq500/sdk}/lib"
  [[ -f "${lib_root}/libcurt.so" ]] || fail "missing SDK library: ${lib_root}/libcurt.so"
  [[ -f "${lib_root}/libdlfft.so" ]] || fail "missing SDK library: ${lib_root}/libdlfft.so"
  [[ -f "${lib_root}/libdlblas.so" ]] || fail "missing SDK library: ${lib_root}/libdlblas.so"
  [[ -f "${lib_root}/libdlsolver.so" || -f "${lib_root}/libcusolver.so" ]] || \
    fail "missing SDK solver library: ${lib_root}/libdlsolver.so or libcusolver.so"
  [[ -f "${lib_root}/libdleol.so" ]] || fail "missing SDK library: ${lib_root}/libdleol.so"
  log "sdk headers/libs: ok"
}

fftw_installed() {
  [[ -f "${root}/third_party/fftw/install/include/fftw3.h" ]] &&
    [[ -f "${root}/third_party/fftw/install/lib/libfftw3.a" ]]
}

ensure_fftw_installed() {
  if fftw_installed; then
    log "fftw: already installed"
    return 0
  fi
  [[ "${ensure_fftw}" == "1" ]] || fail "missing FFTW under third_party/fftw/install; rerun with --ensure-fftw"
  require_command tar
  require_command gcc
  if ! has_command wget && ! has_command curl; then
    fail "missing downloader: install wget or curl, or pre-place FFTW archive under third_party/fftw/dist"
  fi
  log "fftw: installing under third_party/fftw/install"
  "${root}/scripts/build/install_fftw.sh"
}

read_python_packages() {
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${requirements}"
}

python_has_module() {
  python3 - "$1" <<'PY' >/dev/null 2>&1
import importlib.util
import sys
sys.exit(0 if importlib.util.find_spec(sys.argv[1]) else 1)
PY
}

missing_python_packages() {
  local package module
  while IFS= read -r package; do
    module="${package%%[<>=!~ ]*}"
    python_has_module "${module}" || printf '%s\n' "${package}"
  done < <(read_python_packages)
}

ensure_pip() {
  if python3 -m pip --version >/dev/null 2>&1; then
    return 0
  fi
  warn "python3 -m pip is missing; trying ensurepip --user"
  python3 -m ensurepip --user >/dev/null 2>&1 || \
    fail "missing pip; install python3-pip in the container or provide a Python with ensurepip"
}

download_wheels() {
  ensure_pip
  mkdir -p "${wheel_dir}"
  log "python wheels: download cache ${wheel_dir}"
  python3 -m pip download --dest "${wheel_dir}" -r "${requirements}"
}

install_missing_python() {
  mapfile -t missing < <(missing_python_packages)
  if [[ "${#missing[@]}" -eq 0 ]]; then
    log "python modules: already installed"
    return 0
  fi

  log "python modules missing: ${missing[*]}"
  [[ "${install_python}" == "1" ]] || {
    warn "Python modules required for full visualization/data functionality are missing; set INSTALL_PYTHON_DEPS=1 or rerun with --install-python to install"
    return 0
  }

  ensure_pip
  if compgen -G "${wheel_dir}/*.whl" >/dev/null; then
    log "python modules: installing from wheel cache first"
    if python3 -m pip install --user --no-index --find-links "${wheel_dir}" "${missing[@]}"; then
      mapfile -t missing < <(missing_python_packages)
      if [[ "${#missing[@]}" -eq 0 ]]; then
        log "python modules: installed"
        return 0
      fi
      warn "wheel cache install completed but modules are still missing: ${missing[*]}"
      [[ "${strict}" == "1" ]] && fail "failed to import installed Python modules: ${missing[*]}"
      return 0
    fi
    warn "wheel cache install failed; falling back to normal pip index"
  fi
  python3 -m pip install --user "${missing[@]}"
  mapfile -t missing < <(missing_python_packages)
  if [[ "${#missing[@]}" -ne 0 ]]; then
    fail "failed to import installed Python modules: ${missing[*]}"
  fi
  log "python modules: installed"
}

main() {
  [[ -f "${requirements}" ]] || fail "missing Python requirements file: ${requirements}"

  source_sdk_if_available
  check_required_commands
  check_sdk_files
  ensure_fftw_installed

  if [[ "${download_python_wheels}" == "1" ]]; then
    download_wheels
  fi
  install_missing_python

  log "dependency preparation complete"
}

main "$@"
