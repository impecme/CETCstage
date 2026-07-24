#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${BUILD_DIR:-build-zx}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
JOBS="${JOBS:-}"
CHECK_DEPS=1
TARGETS=()
LIVE_DEMO=0

FFTW_VERSION="3.3.10"
FFTW_SHA256="56c932549852cddcfafdab3820b0200c7742675be92179e59e6215b340e26467"
FFTW_ROOT="${PROJECT_ROOT}/third_party/fftw"
FFTW_ARCHIVE="${FFTW_ROOT}/dist/fftw-${FFTW_VERSION}.tar.gz"
FFTW_SOURCE="${FFTW_ROOT}/src/fftw-${FFTW_VERSION}"
FFTW_INSTALL="${FFTW_ROOT}/install"

usage() {
  cat <<'USAGE'
Usage: scripts/build.sh [options]

Check the ZQ500 SDK, install the pinned offline FFTW dependency when needed,
then configure and build the final project.

Options:
  --build-dir PATH    Build directory (default: build-zx)
  --build-type TYPE   CMake build type (default: Release)
  --jobs N            Parallel build jobs (default: auto)
  --target NAME       Build one target; may be repeated (default: all)
  --live-demo         Build only the 53 core53 test targets plus Task1/Task2 demos;
                      do not run any measurement
  --skip-deps         Skip SDK/FFTW dependency checks
  -h, --help          Show this help

Environment:
  ZHONGKEXIN_CXX_COMPILER  Override the dlcc executable
  ZX_COMPAT_SOURCE_DIR     External directory containing compatibility XLSX files
  ZX_COMPAT_REQUIRE_FIXTURES=ON
                            Require the external fixtures during configure
USAGE
}

die() {
  echo "[build] error: $*" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

resolve_path() {
  if [[ "$1" = /* ]]; then
    printf '%s\n' "$1"
  else
    printf '%s\n' "${PROJECT_ROOT}/$1"
  fi
}

auto_jobs() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
  else
    getconf _NPROCESSORS_ONLN
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      [[ $# -ge 2 ]] || die "--build-dir requires a value"
      BUILD_DIR="$2"
      shift 2
      ;;
    --build-type)
      [[ $# -ge 2 ]] || die "--build-type requires a value"
      BUILD_TYPE="$2"
      shift 2
      ;;
    --jobs)
      [[ $# -ge 2 ]] || die "--jobs requires a value"
      JOBS="$2"
      shift 2
      ;;
    --target)
      [[ $# -ge 2 ]] || die "--target requires a value"
      TARGETS+=("$2")
      shift 2
      ;;
    --live-demo)
      LIVE_DEMO=1
      shift
      ;;
    --skip-deps)
      CHECK_DEPS=0
      shift
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

if [[ "${LIVE_DEMO}" -eq 1 ]]; then
  mapfile -t LIVE_DEMO_UNIT_TARGETS < <(
    python3 - "${PROJECT_ROOT}/tests/contracts/operator_sets.json" <<'PY'
import json
import sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
sets = payload.get("sets")
if not isinstance(sets, dict):
    raise SystemExit("operator_sets.json missing sets")
all81_item = sets.get("all81")
all81 = all81_item.get("operators") if isinstance(all81_item, dict) else None
if not isinstance(all81, list) or len(all81) != 81:
    raise SystemExit("operator_sets.json has invalid all81")

def resolve(name, resolving=None):
    resolving = set() if resolving is None else resolving
    if name in resolving:
        raise SystemExit(f"operator-set cycle: {name}")
    item = sets.get(name)
    if not isinstance(item, dict):
        raise SystemExit(f"unknown operator set: {name}")
    resolving.add(name)
    if "operators" in item:
        values = item["operators"]
        if not isinstance(values, list):
            raise SystemExit(f"invalid operators in {name}")
        result = list(values)
    else:
        included = set()
        for include in item.get("include_sets", []):
            included.update(resolve(include, resolving))
        excluded = set()
        for exclude in item.get("exclude_sets", []):
            excluded.update(resolve(exclude, resolving))
        result = [key for key in all81 if key in included and key not in excluded]
    resolving.remove(name)
    return result

core53 = resolve("core53")
if len(core53) != 53:
    raise SystemExit(f"core53 target count mismatch: {len(core53)}")
for key in core53:
    module, operator = key.split("/", 1)
    print(f"{module}_test_{operator}")
PY
  )
  [[ ${#LIVE_DEMO_UNIT_TARGETS[@]} -eq 53 ]] || die "expected 53 core53 test targets"
  TARGETS+=(task1_radar_demo task2_features_demo "${LIVE_DEMO_UNIT_TARGETS[@]}")
  echo "[build] live-demo targets: 53 core53 tests + 2 task demos"
fi

if [[ -n "${JOBS}" && ! "${JOBS}" =~ ^[1-9][0-9]*$ ]]; then
  die "--jobs must be a positive integer"
fi
JOBS="${JOBS:-$(auto_jobs)}"
BUILD_PATH="$(resolve_path "${BUILD_DIR}")"

if [[ -f /zq500/sdk/env.sh ]]; then
  set +u
  # shellcheck source=/dev/null
  source /zq500/sdk/env.sh ""
  set -u
fi

check_cmake_version() {
  local version
  version="$(cmake --version | sed -n '1s/.* version //p')"
  python3 - "${version}" <<'PY' || die "cmake ${version:-unknown} is below required 3.18"
import sys
parts = []
for value in sys.argv[1].split(".")[:3]:
    try:
        parts.append(int(value))
    except ValueError:
        parts.append(0)
parts.extend([0] * (3 - len(parts)))
raise SystemExit(0 if tuple(parts) >= (3, 18, 0) else 1)
PY
}

check_sdk() {
  local sdk_root="${SDK_DIR:-/zq500/sdk}"
  local required
  for required in \
    "${sdk_root}/include/cuda_runtime.h" \
    "${sdk_root}/include/cufft.h" \
    "${sdk_root}/include/cublas_v2.h" \
    "${sdk_root}/include/cusolverDn.h" \
    "${sdk_root}/lib/libcurt.so" \
    "${sdk_root}/lib/libdlfft.so" \
    "${sdk_root}/lib/libdlblas.so" \
    "${sdk_root}/lib/libdleol.so"; do
    [[ -f "${required}" ]] || die "missing ZQ500 SDK file: ${required}"
  done
  [[ -f "${sdk_root}/lib/libdlsolver.so" || -f "${sdk_root}/lib/libcusolver.so" ]] || \
    die "missing ZQ500 solver library"
}

invalidate_relocated_cmake_cache() {
  local cache_path="${BUILD_PATH}/CMakeCache.txt"
  # No build directory/cache is the normal first-build case.  Returning the
  # failed [[ -f ]] status under `set -e` used to abort before CMake ran.
  [[ -f "${cache_path}" ]] || return 0

  local cached_build_dir
  local cached_source_dir
  cached_build_dir="$(sed -n 's|^CMAKE_CACHEFILE_DIR:INTERNAL=||p' "${cache_path}" | head -n 1)"
  cached_source_dir="$(sed -n 's|^CMAKE_HOME_DIRECTORY:INTERNAL=||p' "${cache_path}" | head -n 1)"

  if [[ "${cached_build_dir}" == "${BUILD_PATH}" && "${cached_source_dir}" == "${PROJECT_ROOT}" ]]; then
    return
  fi

  echo "[build] clearing relocated CMake cache: ${cache_path}"
  echo "[build] cached source: ${cached_source_dir:-<missing>}"
  echo "[build] current source: ${PROJECT_ROOT}"
  rm -f -- "${cache_path}"
  rm -rf -- "${BUILD_PATH}/CMakeFiles"
}

install_fftw() {
  if [[ -f "${FFTW_INSTALL}/include/fftw3.h" && -f "${FFTW_INSTALL}/lib/libfftw3.a" ]]; then
    echo "[build] FFTW ${FFTW_VERSION}: ready"
    return
  fi

  require_command tar
  require_command make
  require_command gcc
  require_command sha256sum
  [[ -f "${FFTW_ARCHIVE}" ]] || die "missing pinned FFTW archive: ${FFTW_ARCHIVE}"
  local actual
  actual="$(sha256sum "${FFTW_ARCHIVE}" | awk '{print $1}')"
  [[ "${actual}" == "${FFTW_SHA256}" ]] || die "FFTW archive SHA256 mismatch"

  mkdir -p "${FFTW_ROOT}/src"
  rm -rf -- "${FFTW_SOURCE}"
  tar -xzf "${FFTW_ARCHIVE}" -C "${FFTW_ROOT}/src"
  (
    cd "${FFTW_SOURCE}"
    ./configure --prefix="${FFTW_INSTALL}" --disable-shared --enable-static --with-pic
    make -j"${JOBS}"
    make install
  )
  [[ -f "${FFTW_INSTALL}/include/fftw3.h" && -f "${FFTW_INSTALL}/lib/libfftw3.a" ]] || \
    die "FFTW installation did not produce the required files"
}

require_command cmake
require_command python3
check_cmake_version

COMPILER="${ZHONGKEXIN_CXX_COMPILER:-$(command -v dlcc || true)}"
[[ -n "${COMPILER}" ]] || die "dlcc was not found; source /zq500/sdk/env.sh first"

if [[ "${CHECK_DEPS}" -eq 1 ]]; then
  check_sdk
  install_fftw
fi

invalidate_relocated_cmake_cache

cmake_args=(
  -S "${PROJECT_ROOT}"
  -B "${BUILD_PATH}"
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN
  -DCMAKE_CXX_COMPILER="${COMPILER}"
  -DZX_COMPAT_SOURCE_DIR="${ZX_COMPAT_SOURCE_DIR:-${PROJECT_ROOT}/.external/zx_compatibility}"
  -DZX_COMPAT_REQUIRE_FIXTURES="${ZX_COMPAT_REQUIRE_FIXTURES:-OFF}"
)

echo "[build] root: ${PROJECT_ROOT}"
echo "[build] build: ${BUILD_PATH}"
echo "[build] compiler: ${COMPILER}"
cmake "${cmake_args[@]}"

build_args=(--build "${BUILD_PATH}" --parallel "${JOBS}")
if [[ ${#TARGETS[@]} -gt 0 ]]; then
  build_args+=(--target "${TARGETS[@]}")
fi
cmake "${build_args[@]}"

echo "[build] PASS"
