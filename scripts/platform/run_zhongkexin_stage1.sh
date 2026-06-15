#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="${BUILD_DIR:-/CETC/build-zx}"
arch="${CUDA_ARCH:-OFF}"
repeat="${REPEAT:-3}"

echo "[zx-stage1] script version: diagnostics-20260615-compiler-flags-v3"
echo "[zx-stage1] project root: ${root}"
echo "[zx-stage1] build dir: ${build}"

set +u
source /zq500/sdk/env.sh ""
set -u

find_cuda_root() {
  for dir in "${CUDA_ROOT:-}" "${CUDA_HOME:-}" "${CUDA_PATH:-}" /zq500/cuda11 /zq500/sdk /usr/local/cuda; do
    [[ -n "${dir}" ]] || continue
    [[ -d "${dir}/nvvm/libdevice" || -f "${dir}/include/cuda_runtime.h" ]] && printf '%s\n' "${dir}" && return
  done
}

find_tool() {
  local tool
  local dir
  for dir in "${real_cuda_compiler_dir:-}" /zq500/sdk/bin /zq500/cuda11/bin /usr/bin; do
    [[ -n "${dir}" && -d "${dir}" ]] || continue
    for tool in "$@"; do
      [[ -x "${dir}/${tool}" ]] && printf '%s\n' "${dir}/${tool}" && return
    done
  done
  for tool in "$@"; do
    command -v "${tool}" 2>/dev/null && return
  done
}

select_cuda_compiler() {
  local probe_dir="${build}/compiler-probe"
  local candidate
  local flags
  local output
  local kind
  local flags_file="${probe_dir}/selected_flags"
  rm -rf "${probe_dir}"
  mkdir -p "${probe_dir}"
  cat >"${probe_dir}/probe.cu" <<'CU'
#include <cuda_runtime.h>
__global__ void probe_kernel(float *x) { x[threadIdx.x] = 1.0f; }
CU

  for candidate in "$@"; do
    [[ -n "${candidate}" && -x "${candidate}" ]] || continue
    for flags in \
      "-std=c++17 -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/cuda11 -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/sdk -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/cuda11 -nocudalib -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/sdk -nocudalib -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/sdk -nocudalib --cuda-host-only -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/sdk -nocudalib --cuda-device-only -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/sdk -nocudalib --cuda-gpu-arch=sm_80 -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 --cuda-path=/zq500/sdk -nocudalib -allow-unsupported-compiler -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 -nocudalib -nocudainc -I/zq500/cuda11/include -I/zq500/sdk/include" \
      "-std=c++17 -D__CUDACC__ -nocudalib -nocudainc -I/zq500/cuda11/include -I/zq500/sdk/include"; do
      output="${probe_dir}/$(basename "${candidate}").$(printf '%s' "${flags}" | tr -cs 'A-Za-z0-9_' '_').o"
      echo "[zx-stage1] probing CUDA compiler: ${candidate} ${flags}" >&2
      # shellcheck disable=SC2086
      if "${candidate}" ${flags} -c "${probe_dir}/probe.cu" -o "${output}" >/tmp/zx_cuda_compiler_probe.log 2>&1; then
        kind="$(file -b "${output}" 2>/dev/null || true)"
        echo "[zx-stage1] compiler output: ${kind}" >&2
        if [[ "${kind}" == *"ELF"* && "${kind}" == *"relocatable"* ]]; then
          printf '%s\n' "${flags}" >"${flags_file}"
          printf '%s\n' "${candidate}"
          return 0
        fi
      else
        sed -n '1,12p' /tmp/zx_cuda_compiler_probe.log >&2
      fi
    done
  done

  echo "[zx-stage1] SDK compiler hint files" >&2
  find /zq500/sdk/samples /zq500/cuda11 -maxdepth 4 -type f \
    \( -name 'Makefile' -o -name 'CMakeLists.txt' -o -name '*.sh' \) 2>/dev/null | sed -n '1,40p' >&2 || true
  echo "[zx-stage1] SDK compiler command hints" >&2
  find /zq500/sdk/samples /zq500/cuda11 -maxdepth 4 -type f \
    \( -name 'Makefile' -o -name 'CMakeLists.txt' -o -name '*.sh' \) \
    -exec grep -HnE 'dlcc|dlnvcc|nvcc|cuda-gpu-arch|cuda-path|nocudalib|nocudainc|arch' {} \; 2>/dev/null | sed -n '1,120p' >&2 || true
  echo "[zx-stage1] no CUDA compiler produced an ELF relocatable object" >&2
  return 1
}

fill_cuda_compat_root() {
  local dst="$1"
  mkdir -p "${dst}/bin" "${dst}/lib64" "${dst}/nvvm/libdevice"
  for dir in "${CUDA_ROOT:-}" "${CUDA_HOME:-}" "${CUDA_PATH:-}" /zq500/cuda11 /zq500/sdk /usr/local/cuda; do
    [[ -n "${dir}" && -d "${dir}" ]] || continue
    [[ -d "${dir}/include" && ! -e "${dst}/include" ]] && ln -sfn "${dir}/include" "${dst}/include"
    for libdir in "${dir}/lib64" "${dir}/lib" "${dir}/lib/x86_64-linux-gnu"; do
      [[ -d "${libdir}" ]] || continue
      for lib in "${libdir}"/*; do
        [[ -e "${lib}" ]] || continue
        ln -sfn "${lib}" "${dst}/lib64/$(basename "${lib}")"
      done
    done
  done
}

ensure_fftw() {
  [[ -f "${root}/third_party/fftw/install/include/fftw3.h" ]] && \
    [[ -f "${root}/third_party/fftw/install/lib/libfftw3.a" ]] && return
  "${root}/scripts/build/install_fftw.sh"
}

diagnose_cuda_archive() {
  local archive="${build}/libcusignal_cuda.a"
  local object="${build}/CMakeFiles/cusignal_cuda.dir/src/cuda/radartools.cu.o"
  echo "[zx-stage1] cuda archive diagnostics"
  command -v file >/dev/null 2>&1 && file "${archive}" "${object}" || true
  if [[ -n "${archive_tool}" && -x "${archive_tool}" ]]; then
    "${archive_tool}" t "${archive}" | sed -n '1,20p' || true
  elif command -v ar >/dev/null 2>&1; then
    ar t "${archive}" | sed -n '1,20p' || true
  fi
  if command -v readelf >/dev/null 2>&1; then
    readelf -h "${object}" 2>&1 | sed -n '1,40p' || true
  fi
}

rm -rf "${build}"
mapfile -t cuda_compiler_candidates < <(
  for tool in "${CUDACXX:-}" \
      "$(command -v dlnvcc 2>/dev/null || true)" \
      "$(command -v dlcc 2>/dev/null || true)" \
      "$(command -v nvcc 2>/dev/null || true)"; do
    [[ -n "${tool}" ]] && printf '%s\n' "${tool}"
  done
)
real_cuda_compiler="$(select_cuda_compiler "${cuda_compiler_candidates[@]}")"
real_cuda_compiler_dir=""
[[ -n "${real_cuda_compiler}" ]] && real_cuda_compiler_dir="$(dirname "${real_cuda_compiler}")"
cuda_compiler_flags=""
[[ -f "${build}/compiler-probe/selected_flags" ]] && cuda_compiler_flags="$(<"${build}/compiler-probe/selected_flags")"
archive_tool="${AR:-$(find_tool llvm-ar ar || true)}"
ranlib_tool="${RANLIB:-$(find_tool llvm-ranlib ranlib || true)}"
cuda_root="${build}/cuda-compat"
fill_cuda_compat_root "${cuda_root}"
cuda_compiler=""
if [[ -n "${real_cuda_compiler}" ]]; then
  cuda_compiler="${cuda_root}/bin/nvcc"
  printf '#!/usr/bin/env bash\nexec %q %s "$@"\n' "${real_cuda_compiler}" "${cuda_compiler_flags}" >"${cuda_compiler}"
  chmod +x "${cuda_compiler}"
fi

cd "${root}"

scripts/platform/probe_zhongkexin.sh
ensure_fftw

cmake_args=(
  -S .
  -B "${build}"
  -DCUSIGNAL_PLATFORM=ZHONGKEXIN
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
  -DCMAKE_CUDA_COMPILER_FORCED=ON
  -DCMAKE_CUDA_COMPILER_WORKS=ON
  -DCMAKE_CUDA_FLAGS=-std=c++17
)
cmake_args+=("-DCMAKE_CUDA_ARCHITECTURES=${arch}")
if [[ -n "${cuda_root}" ]]; then
  cmake_args+=(
    "-DCUDAToolkit_ROOT=${cuda_root}"
    "-DCUDA_TOOLKIT_ROOT_DIR=${cuda_root}"
    "-DCMAKE_CUDA_COMPILER_TOOLKIT_ROOT=${cuda_root}"
    "-DCMAKE_CUDA_COMPILER_LIBRARY_ROOT=${cuda_root}"
  )
fi
if [[ -n "${cuda_compiler}" ]]; then
  cmake_args+=("-DCMAKE_CUDA_COMPILER=${cuda_compiler}")
  cmake_args+=("-DCMAKE_CUDA_HOST_LINK_LAUNCHER=${cuda_compiler}")
fi
if [[ -n "${archive_tool}" ]]; then
  cmake_args+=("-DCMAKE_AR=${archive_tool}")
  cmake_args+=("-DCMAKE_CUDA_COMPILER_AR=${archive_tool}")
fi
if [[ -n "${ranlib_tool}" ]]; then
  cmake_args+=("-DCMAKE_RANLIB=${ranlib_tool}")
  cmake_args+=("-DCMAKE_CUDA_COMPILER_RANLIB=${ranlib_tool}")
fi

cmake "${cmake_args[@]}"

cmake --build "${build}" --target \
  cusignal_cpu \
  cusignal_cuda \
  --parallel

diagnose_cuda_archive

cmake --build "${build}" --target \
  task1_radar_demo \
  task2_features_demo \
  --parallel --verbose

scripts/test/run_task_demos.sh --build-dir "${build}" --no-build --repeat "${repeat}"
