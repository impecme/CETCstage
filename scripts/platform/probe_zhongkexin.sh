#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="${BUILD_DIR:-${root}/build-zx-probe}"
arch="${CUDA_ARCH:-OFF}"
src="${build}/src"

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
      echo "[zx-probe] probing CUDA compiler: ${candidate} ${flags}" >&2
      # shellcheck disable=SC2086
      if "${candidate}" ${flags} -c "${probe_dir}/probe.cu" -o "${output}" >/tmp/zx_cuda_compiler_probe.log 2>&1; then
        kind="$(file -b "${output}" 2>/dev/null || true)"
        echo "[zx-probe] compiler output: ${kind}" >&2
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

  echo "[zx-probe] SDK compiler hint files" >&2
  find /zq500/sdk/samples /zq500/cuda11 -maxdepth 4 -type f \
    \( -name 'Makefile' -o -name 'CMakeLists.txt' -o -name '*.sh' \) 2>/dev/null | sed -n '1,40p' >&2 || true
  echo "[zx-probe] SDK compiler command hints" >&2
  find /zq500/sdk/samples /zq500/cuda11 -maxdepth 4 -type f \
    \( -name 'Makefile' -o -name 'CMakeLists.txt' -o -name '*.sh' \) \
    -exec grep -HnE 'dlcc|dlnvcc|nvcc|cuda-gpu-arch|cuda-path|nocudalib|nocudainc|arch' {} \; 2>/dev/null | sed -n '1,120p' >&2 || true
  echo "[zx-probe] no CUDA compiler produced an ELF relocatable object" >&2
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

rm -rf "${build}"
mkdir -p "${src}"

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

cat >"${src}/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.18)
project(zhongkexin_probe LANGUAGES CXX CUDA)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CUDA_STANDARD 17)

find_package(CUDAToolkit QUIET)
if(CUDAToolkit_FOUND)
  set(ZX_CUDA_INCLUDE_DIRS ${CUDAToolkit_INCLUDE_DIRS})
  set(ZX_CUDA_LIBS CUDA::cudart CUDA::cufft_static CUDA::cublas CUDA::cusolver)
else()
  find_path(
    ZX_CUDA_INCLUDE_DIRS
    NAMES cuda_runtime.h
    PATHS
      "$ENV{CUDA_ROOT}/include"
      "$ENV{CUDA_HOME}/include"
      "$ENV{CUDA_PATH}/include"
      /zq500/cuda11/include
      /zq500/sdk/include
      /usr/local/cuda/include
  )
  if(NOT ZX_CUDA_INCLUDE_DIRS)
    message(FATAL_ERROR "cuda_runtime.h was not found")
  endif()
  set(ZX_CUDA_LIBS "")
endif()

add_library(zx_probe STATIC probe.cu)
target_include_directories(zx_probe PRIVATE ${ZX_CUDA_INCLUDE_DIRS})
target_link_libraries(zx_probe PRIVATE ${ZX_CUDA_LIBS})
CMAKE

cat >"${src}/probe.cu" <<'CU'
#include <cuda_runtime.h>
#include <cufft.h>
#include <cublas_v2.h>
#include <cusolverDn.h>

#include <cstdio>
#include <cstdlib>

__global__ void add_one(float *x) { x[threadIdx.x] += 1.0f; }

void ok(bool v, const char *name)
{
    if (!v)
    {
        std::fprintf(stderr, "probe failed: %s\n", name);
        std::exit(1);
    }
}

int main()
{
    int device = -1;
    ok(cudaGetDevice(&device) == cudaSuccess, "cudaGetDevice");

    float host[4] = {0, 1, 2, 3};
    float *dev = nullptr;
    ok(cudaMalloc(&dev, sizeof(host)) == cudaSuccess, "cudaMalloc");
    ok(cudaMemcpy(dev, host, sizeof(host), cudaMemcpyHostToDevice) == cudaSuccess, "cudaMemcpy H2D");
    add_one<<<1, 4>>>(dev);
    ok(cudaDeviceSynchronize() == cudaSuccess, "kernel launch");
    ok(cudaMemcpy(host, dev, sizeof(host), cudaMemcpyDeviceToHost) == cudaSuccess, "cudaMemcpy D2H");
    ok(host[0] == 1.0f && host[3] == 4.0f, "kernel result");
    ok(cudaMemset(dev, 0, sizeof(host)) == cudaSuccess, "cudaMemset");

    cudaEvent_t start{}, stop{};
    ok(cudaEventCreate(&start) == cudaSuccess, "cudaEventCreate start");
    ok(cudaEventCreate(&stop) == cudaSuccess, "cudaEventCreate stop");
    ok(cudaEventRecord(start) == cudaSuccess, "cudaEventRecord start");
    ok(cudaEventRecord(stop) == cudaSuccess, "cudaEventRecord stop");
    ok(cudaEventSynchronize(stop) == cudaSuccess, "cudaEventSynchronize");
    float ms = 0.0f;
    ok(cudaEventElapsedTime(&ms, start, stop) == cudaSuccess, "cudaEventElapsedTime");
    cudaEventDestroy(start);
    cudaEventDestroy(stop);
    cudaFree(dev);

    cufftHandle fft{};
    ok(cufftPlan1d(&fft, 8, CUFFT_C2C, 1) == CUFFT_SUCCESS, "cufftPlan1d");
    cufftDestroy(fft);

    cublasHandle_t blas{};
    ok(cublasCreate(&blas) == CUBLAS_STATUS_SUCCESS, "cublasCreate");
    cublasDestroy(blas);

    cusolverDnHandle_t solver{};
    ok(cusolverDnCreate(&solver) == CUSOLVER_STATUS_SUCCESS, "cusolverDnCreate");
    cusolverDnDestroy(solver);

    std::puts("zhongkexin probe passed");
    return 0;
}
CU

cmake_args=(
  -S "${src}"
  -B "${build}"
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
cmake --build "${build}" --target zx_probe --parallel
