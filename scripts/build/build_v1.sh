#!/usr/bin/env bash

rm -rf build

set -euo pipefail

# 一键编译脚本。
# 默认在仓库根目录下生成 build/，并完成 configure + build 两个步骤。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
BUILD_TYPE="${1:-Release}"
CUDA_ARCH="${CUDA_ARCH:-80}"
CUSIGNAL_PLATFORM="${CUSIGNAL_PLATFORM:-NVIDIA}"

if command -v nproc >/dev/null 2>&1; then
    JOBS="$(nproc)"
else
    JOBS="$(getconf _NPROCESSORS_ONLN)"
fi

echo "[cusignal] project root: ${PROJECT_ROOT}"
echo "[cusignal] build dir   : ${BUILD_DIR}"
echo "[cusignal] build type  : ${BUILD_TYPE}"
echo "[cusignal] cuda arch   : ${CUDA_ARCH}"
echo "[cusignal] platform    : ${CUSIGNAL_PLATFORM}"
echo "[cusignal] jobs        : ${JOBS}"

cmake -S "${PROJECT_ROOT}" \
      -B "${BUILD_DIR}" \
      -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH}" \
      -DCUSIGNAL_PLATFORM="${CUSIGNAL_PLATFORM}"

cmake --build "${BUILD_DIR}" --parallel "${JOBS}"

echo "[cusignal] build finished"
