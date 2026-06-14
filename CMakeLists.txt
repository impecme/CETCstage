cmake_minimum_required(VERSION 3.18)

# V2.1 统一采用 C++17 / CUDA17，并以公开 API 对齐为本轮交付重点。
project(cusignal_cpp_v2_1 LANGUAGES CXX CUDA)

set(CUSIGNAL_PLATFORM "NVIDIA" CACHE STRING "Target GPU platform: NVIDIA or ZHONGKEXIN")
set_property(CACHE CUSIGNAL_PLATFORM PROPERTY STRINGS NVIDIA ZHONGKEXIN)
string(TOUPPER "${CUSIGNAL_PLATFORM}" CUSIGNAL_PLATFORM_UPPER)
if(NOT CUSIGNAL_PLATFORM_UPPER STREQUAL "NVIDIA" AND
   NOT CUSIGNAL_PLATFORM_UPPER STREQUAL "ZHONGKEXIN")
    message(FATAL_ERROR "CUSIGNAL_PLATFORM must be NVIDIA or ZHONGKEXIN, got: ${CUSIGNAL_PLATFORM}")
endif()
set(CUSIGNAL_PLATFORM "${CUSIGNAL_PLATFORM_UPPER}" CACHE STRING "Target GPU platform: NVIDIA or ZHONGKEXIN" FORCE)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_CUDA_STANDARD 17)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)
set(CMAKE_CUDA_EXTENSIONS OFF)

# 默认采用 Release，便于后续继续扩展性能测试时保持一个稳定起点。
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# 赛题环境以 A800 / CUDA 11.7 为主，这里给出一个明确的默认架构值。
if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES 80 CACHE STRING "Default CUDA architecture" FORCE)
endif()

set(CUSIGNAL_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(CUSIGNAL_THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(CUSIGNAL_FFTW_ROOT ${CUSIGNAL_THIRD_PARTY_DIR}/fftw/install)

find_package(CUDAToolkit REQUIRED)

message(STATUS "CUSIGNAL_PLATFORM=${CUSIGNAL_PLATFORM}")

find_path(
    FFTW3_INCLUDE_DIR
    NAMES fftw3.h
    PATHS ${CUSIGNAL_FFTW_ROOT}/include
    NO_DEFAULT_PATH
)
find_library(
    FFTW3_LIBRARY
    NAMES fftw3 libfftw3.a
    PATHS ${CUSIGNAL_FFTW_ROOT}/lib
    NO_DEFAULT_PATH
)

if(NOT FFTW3_INCLUDE_DIR OR NOT FFTW3_LIBRARY)
    message(FATAL_ERROR
        "FFTW was not found under ${CUSIGNAL_FFTW_ROOT}. "
        "Run scripts/build/install_fftw.sh first.")
endif()

set(CUSIGNAL_CUDART_TARGET CUDA::cudart)
set(CUSIGNAL_CUFFT_TARGET CUDA::cufft_static)
set(CUSIGNAL_CUBLAS_TARGET CUDA::cublas)
set(CUSIGNAL_CUSOLVER_TARGET CUDA::cusolver)

set(CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin cuFFT-compatible library")
set(CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin cuBLAS-compatible library")
set(CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin cuSOLVER-compatible library")

function(cusignal_require_or_alias_cuda_library target_name cache_library message_name)
    if(TARGET ${target_name})
        return()
    endif()

    if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN" AND DEFINED ${cache_library} AND NOT "${${cache_library}}" STREQUAL "")
        add_library(${target_name} UNKNOWN IMPORTED)
        set_target_properties(${target_name} PROPERTIES
            IMPORTED_LOCATION "${${cache_library}}"
            INTERFACE_INCLUDE_DIRECTORIES "${CUDAToolkit_INCLUDE_DIRS}"
        )
        message(STATUS "Using ${message_name} compatibility library: ${${cache_library}}")
        return()
    endif()

    message(FATAL_ERROR
        "${target_name} is not available. "
        "For NVIDIA builds, install a CUDA Toolkit that provides ${message_name}. "
        "For ZHONGKEXIN builds, set ${cache_library} to a compatible library path if the target is named differently.")
endfunction()

cusignal_require_or_alias_cuda_library(CUDA::cufft_static CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY "cuFFT")
cusignal_require_or_alias_cuda_library(CUDA::cublas CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY "cuBLAS")
cusignal_require_or_alias_cuda_library(CUDA::cusolver CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY "cuSOLVER")

# 显式列出源文件，避免文件结构变化时出现不可预期的自动收集行为。
set(CUSIGNAL_CPU_SOURCES
    src/cpu/bsplines.cpp
    src/cpu/correlate.cpp
    src/cpu/demod.cpp
    src/cpu/estimation.cpp
    src/cpu/filter_design.cpp
    src/cpu/filtering.cpp
    src/cpu/peak_finding.cpp
    src/cpu/radartools.cpp
    src/cpu/spectral.cpp
    src/cpu/waveforms.cpp
    src/cpu/wavelets.cpp
    src/cpu/windows.cpp
)

set(CUSIGNAL_CUDA_SOURCES
    src/cuda/bsplines.cu
    src/cuda/correlate.cu
    src/cuda/demod.cu
    src/cuda/estimation.cu
    src/cuda/filter_design.cu
    src/cuda/filtering.cu
    src/cuda/peak_finding.cu
    src/cuda/radartools.cu
    src/cuda/spectral.cu
    src/cuda/waveforms.cu
    src/cuda/wavelets.cu
    src/cuda/windows.cu
)

add_library(cusignal_cpu STATIC ${CUSIGNAL_CPU_SOURCES})
target_include_directories(cusignal_cpu PUBLIC ${CUSIGNAL_INCLUDE_DIR})
target_compile_features(cusignal_cpu PUBLIC cxx_std_17)
target_compile_definitions(cusignal_cpu PUBLIC CUSIGNAL_PLATFORM_${CUSIGNAL_PLATFORM})
target_include_directories(
    cusignal_cpu
    PUBLIC ${CUDAToolkit_INCLUDE_DIRS}
    PRIVATE ${FFTW3_INCLUDE_DIR}
)
target_link_libraries(cusignal_cpu PRIVATE ${FFTW3_LIBRARY})

add_library(cusignal_cuda STATIC ${CUSIGNAL_CUDA_SOURCES})
target_include_directories(cusignal_cuda PUBLIC ${CUSIGNAL_INCLUDE_DIR} ${CUDAToolkit_INCLUDE_DIRS})
target_compile_features(cusignal_cuda PUBLIC cxx_std_17)
target_compile_definitions(cusignal_cuda PUBLIC CUSIGNAL_PLATFORM_${CUSIGNAL_PLATFORM})
target_link_libraries(cusignal_cuda PUBLIC cusignal_cpu)
target_link_libraries(cusignal_cuda PRIVATE
    ${CUSIGNAL_CUDART_TARGET}
    ${CUSIGNAL_CUFFT_TARGET}
    ${CUSIGNAL_CUBLAS_TARGET}
    ${CUSIGNAL_CUSOLVER_TARGET}
)
set_target_properties(cusignal_cuda PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    POSITION_INDEPENDENT_CODE ON
)

add_subdirectory(demo/task1_radar)
add_subdirectory(demo/task2_features)

include(CTest)

if(BUILD_TESTING)
    add_subdirectory(tests/smoke)
    add_subdirectory(tests/unit)
endif()
