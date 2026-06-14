#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

BUILD_DIR="${PROJECT_ROOT}/build-zx"
BUILD_TYPE="Release"
CUDA_ARCH="${CUDA_ARCH:-80}"
REPEAT=3
RUN_PROBE=1

usage() {
  cat <<'USAGE'
Usage: scripts/platform/run_zhongkexin_stage1.sh [options]

Options:
  --build-dir DIR       Build directory (default: build-zx)
  --build-type TYPE     CMake build type (default: Release)
  --cuda-arch ARCH      CUDA architecture passed to CMake (default: CUDA_ARCH or 80)
  --repeat N            Repeat count for task demos (default: 3)
  --skip-probe          Skip scripts/platform/probe_zhongkexin.sh
  -h, --help            Show this help

Environment:
  CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY     Optional cuFFT-compatible library path
  CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY    Optional cuBLAS-compatible library path
  CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY  Optional cuSOLVER-compatible library path
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-dir)
      BUILD_DIR="$2"
      shift 2
      ;;
    --build-type)
      BUILD_TYPE="$2"
      shift 2
      ;;
    --cuda-arch)
      CUDA_ARCH="$2"
      shift 2
      ;;
    --repeat)
      REPEAT="$2"
      shift 2
      ;;
    --skip-probe)
      RUN_PROBE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[zx-stage1] unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "${BUILD_DIR}" != /* ]]; then
  BUILD_DIR="${PROJECT_ROOT}/${BUILD_DIR}"
fi

if ! [[ "${REPEAT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "[zx-stage1] --repeat must be a positive integer" >&2
  exit 2
fi

if [[ ! -f /zq500/sdk/env.sh ]]; then
  echo "[zx-stage1] missing /zq500/sdk/env.sh; enter the team docker before running V4.1 validation" >&2
  exit 2
fi

# shellcheck disable=SC1091
source /zq500/sdk/env.sh

if ! command -v dlsmi >/dev/null 2>&1; then
  echo "[zx-stage1] missing dlsmi after sourcing /zq500/sdk/env.sh" >&2
  exit 2
fi

echo "[zx-stage1] device status"
dlsmi

cd "${PROJECT_ROOT}"

if [[ "${RUN_PROBE}" -eq 1 ]]; then
  scripts/platform/probe_zhongkexin.sh --cuda-arch "${CUDA_ARCH}"
fi

CMAKE_ARGS=(
  -S "${PROJECT_ROOT}"
  -B "${BUILD_DIR}"
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN
  -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
  -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}"
)

if [[ -n "${CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY:-}" ]]; then
  CMAKE_ARGS+=("-DCUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY=${CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY}")
fi
if [[ -n "${CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY:-}" ]]; then
  CMAKE_ARGS+=("-DCUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY=${CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY}")
fi
if [[ -n "${CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY:-}" ]]; then
  CMAKE_ARGS+=("-DCUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY=${CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY}")
fi

echo "[zx-stage1] configure: ${CMAKE_ARGS[*]}"
cmake "${CMAKE_ARGS[@]}"

echo "[zx-stage1] build V4.1 targets"
cmake --build "${BUILD_DIR}" --target cusignal_cpu cusignal_cuda task1_radar_demo task2_features_demo --parallel

echo "[zx-stage1] run Task1/Task2 demos"
scripts/test/run_task_demos.sh --build-dir "${BUILD_DIR}" --no-build --repeat "${REPEAT}"

echo "[zx-stage1] V4.1 validation finished"
