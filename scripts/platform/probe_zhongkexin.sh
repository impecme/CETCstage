#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="${BUILD_DIR:-${root}/build-zx-probe}"
src="${build}/src"

find_tool() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" 2>/dev/null && return
  done
}

select_dlcc_flags() {
  local compiler="$1"
  local probe_dir="${build}/compiler-probe"
  local flags
  local output
  local kind

  rm -rf "${probe_dir}"
  mkdir -p "${probe_dir}"
  cat >"${probe_dir}/probe.cu" <<'CU'
#include <cuda_runtime.h>
__global__ void probe_kernel(float *x) { x[threadIdx.x] = 1.0f; }
CU

  for flags in \
    "-std=c++17 -fPIC -x cuda --cuda-gpu-arch=dlgput64 -I/zq500/sdk/include -I/zq500/cuda11/include" \
    "-std=c++17 -fPIC -x cuda --cuda-gpu-arch=dlgpuc64 -I/zq500/sdk/include -I/zq500/cuda11/include" \
    "-std=c++17 -fPIC -x cuda --offload-arch=dlgput64,dlgpux64 -I/zq500/sdk/include -I/zq500/cuda11/include"; do
    output="${probe_dir}/probe.o"
    echo "[zx-probe] probing dlcc flags: ${flags}" >&2
    # shellcheck disable=SC2086
    if "${compiler}" ${flags} -c "${probe_dir}/probe.cu" -o "${output}" >/tmp/zx_dlcc_probe.log 2>&1; then
      kind="$(file -b "${output}" 2>/dev/null || true)"
      echo "[zx-probe] compiler output: ${kind}" >&2
      if [[ "${kind}" == *"ELF"* && "${kind}" == *"relocatable"* ]]; then
        printf '%s\n' "${flags}"
        return 0
      fi
    else
      sed -n '1,20p' /tmp/zx_dlcc_probe.log >&2
    fi
  done

  echo "[zx-probe] dlcc did not produce an ELF relocatable object" >&2
  return 1
}

rm -rf "${build}"
mkdir -p "${src}"

dlcc="$(find_tool dlcc || true)"
if [[ -z "${dlcc}" ]]; then
  echo "[zx-probe] dlcc was not found" >&2
  exit 1
fi
selected_flags="$(select_dlcc_flags "${dlcc}")"
cmake_flags="${selected_flags// /;}"

cat >"${src}/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.18)
project(zhongkexin_probe LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(ZX_CXX_CUDA_FLAGS "" CACHE STRING "dlcc flags for .cu sources")
find_path(
  ZX_CUDA_INCLUDE_DIRS
  NAMES cuda_runtime.h
  PATHS /zq500/sdk/include /zq500/cuda11/include /usr/local/cuda/include
)
if(NOT ZX_CUDA_INCLUDE_DIRS)
  message(FATAL_ERROR "cuda_runtime.h was not found")
endif()

add_library(zx_probe STATIC probe.cu)
set_source_files_properties(probe.cu PROPERTIES LANGUAGE CXX)
target_include_directories(zx_probe PRIVATE ${ZX_CUDA_INCLUDE_DIRS})
target_compile_options(zx_probe PRIVATE ${ZX_CXX_CUDA_FLAGS})
CMAKE

cat >"${src}/probe.cu" <<'CU'
#include <cuda_runtime.h>

__global__ void add_one(float *x) { x[threadIdx.x] += 1.0f; }

void compile_only_probe()
{
    float *dev = nullptr;
    cudaMalloc(&dev, sizeof(float) * 4);
    cudaMemset(dev, 0, sizeof(float) * 4);
    add_one<<<1, 4>>>(dev);
    cudaDeviceSynchronize();
    cudaFree(dev);
}
CU

cmake \
  -S "${src}" \
  -B "${build}" \
  -DCMAKE_CXX_COMPILER="${dlcc}" \
  -DZX_CXX_CUDA_FLAGS="${cmake_flags}"
cmake --build "${build}" --target zx_probe --parallel --verbose
