#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="${BUILD_DIR:-/CETC/build-zx}"
repeat="${REPEAT:-3}"

echo "[zx-stage1] script version: diagnostics-20260616-dlcc-cxx-python-v3"
echo "[zx-stage1] project root: ${root}"
echo "[zx-stage1] build dir: ${build}"

set +u
source /zq500/sdk/env.sh ""
set -u

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
    echo "[zx-stage1] probing dlcc flags: ${flags}" >&2
    # shellcheck disable=SC2086
    if "${compiler}" ${flags} -c "${probe_dir}/probe.cu" -o "${output}" >/tmp/zx_dlcc_probe.log 2>&1; then
      kind="$(file -b "${output}" 2>/dev/null || true)"
      echo "[zx-stage1] compiler output: ${kind}" >&2
      if [[ "${kind}" == *"ELF"* && "${kind}" == *"relocatable"* ]]; then
        printf '%s\n' "${flags}"
        return 0
      fi
    else
      sed -n '1,20p' /tmp/zx_dlcc_probe.log >&2
    fi
  done

  echo "[zx-stage1] dlcc did not produce an ELF relocatable object" >&2
  echo "[zx-stage1] SDK sample command hints" >&2
  find /zq500/sdk/samples -maxdepth 4 -type f \
    \( -name 'Makefile' -o -name 'CMakeLists.txt' -o -name '*.sh' \) \
    -exec grep -HnE 'dlcc|cuda-gpu-arch|offload-arch|-x cuda' {} \; 2>/dev/null | sed -n '1,120p' >&2 || true
  return 1
}

rm -rf "${build}"
dlcc="$(find_tool dlcc || true)"
if [[ -z "${dlcc}" ]]; then
  echo "[zx-stage1] dlcc was not found after sourcing /zq500/sdk/env.sh" >&2
  exit 1
fi
selected_flags="$(select_dlcc_flags "${dlcc}")"
cmake_flags="${selected_flags// /;}"

cd "${root}"

prepare_args=(--ensure-fftw)
[[ "${INSTALL_PYTHON_DEPS:-1}" != "0" ]] && prepare_args+=(--install-python)
[[ "${DOWNLOAD_PYTHON_WHEELS:-0}" == "1" ]] && prepare_args+=(--download-python-wheels)
"${root}/scripts/platform/prepare_zhongkexin_deps.sh" "${prepare_args[@]}"

scripts/platform/probe_zhongkexin.sh

cmake \
  -S . \
  -B "${build}" \
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER="${dlcc}" \
  -DCUSIGNAL_ZHONGKEXIN_CXX_CUDA_FLAGS="${cmake_flags}"

cmake --build "${build}" --target \
  cusignal_cpu \
  cusignal_cuda \
  task1_radar_demo \
  task2_features_demo \
  --parallel --verbose

task_demo_args=(--build-dir "${build}" --no-build --repeat "${repeat}")
[[ "${REQUIRE_VISUALIZATION_DEPS:-1}" != "0" ]] && task_demo_args+=(--require-visualization-deps)
scripts/test/run_task_demos.sh "${task_demo_args[@]}"
