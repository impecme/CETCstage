cmake_minimum_required(VERSION 3.18)

set(CUSIGNAL_PLATFORM "ZHONGKEXIN" CACHE STRING "Target GPU platform: ZHONGKEXIN")
set_property(CACHE CUSIGNAL_PLATFORM PROPERTY STRINGS ZHONGKEXIN)
string(TOUPPER "${CUSIGNAL_PLATFORM}" CUSIGNAL_PLATFORM_UPPER)
if(NOT CUSIGNAL_PLATFORM_UPPER STREQUAL "ZHONGKEXIN")
    message(FATAL_ERROR "CUSIGNAL_PLATFORM must be ZHONGKEXIN, got: ${CUSIGNAL_PLATFORM}")
endif()
set(CUSIGNAL_PLATFORM "${CUSIGNAL_PLATFORM_UPPER}" CACHE STRING "Target GPU platform: ZHONGKEXIN" FORCE)

set(CUSIGNAL_ZHONGKEXIN_CXX_GPU_FLAGS
    "-fPIC;-x;cuda;--cuda-gpu-arch=dlgput64"
    CACHE STRING "Compile flags used by dlcc when compiling ZQ500 GPU sources as CXX for Zhongkexin")

if(NOT DEFINED CMAKE_AR)
    find_program(CUSIGNAL_ZHONGKEXIN_AR NAMES llvm-ar ar
        PATHS /zq500/sdk/bin /zq500/cuda11/bin
        NO_DEFAULT_PATH)
    find_program(CUSIGNAL_ZHONGKEXIN_AR_FALLBACK NAMES llvm-ar ar)
    if(CUSIGNAL_ZHONGKEXIN_AR)
        set(CMAKE_AR "${CUSIGNAL_ZHONGKEXIN_AR}" CACHE FILEPATH "Archive tool for Zhongkexin" FORCE)
    elseif(CUSIGNAL_ZHONGKEXIN_AR_FALLBACK)
        set(CMAKE_AR "${CUSIGNAL_ZHONGKEXIN_AR_FALLBACK}" CACHE FILEPATH "Archive tool for Zhongkexin" FORCE)
    endif()
endif()
if(NOT DEFINED CMAKE_RANLIB)
    find_program(CUSIGNAL_ZHONGKEXIN_RANLIB NAMES llvm-ranlib ranlib
        PATHS /zq500/sdk/bin /zq500/cuda11/bin
        NO_DEFAULT_PATH)
    find_program(CUSIGNAL_ZHONGKEXIN_RANLIB_FALLBACK NAMES llvm-ranlib ranlib)
    if(CUSIGNAL_ZHONGKEXIN_RANLIB)
        set(CMAKE_RANLIB "${CUSIGNAL_ZHONGKEXIN_RANLIB}" CACHE FILEPATH "Ranlib tool for Zhongkexin" FORCE)
    elseif(CUSIGNAL_ZHONGKEXIN_RANLIB_FALLBACK)
        set(CMAKE_RANLIB "${CUSIGNAL_ZHONGKEXIN_RANLIB_FALLBACK}" CACHE FILEPATH "Ranlib tool for Zhongkexin" FORCE)
    endif()
endif()
project(cusignal_zx LANGUAGES CXX)

if(CMAKE_AR)
    set(CMAKE_CXX_ARCHIVE_CREATE "\"${CMAKE_AR}\" rcs <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_CXX_ARCHIVE_APPEND "\"${CMAKE_AR}\" rcs <TARGET> <LINK_FLAGS> <OBJECTS>")
endif()
find_program(CUSIGNAL_ZHONGKEXIN_LLD NAMES ld.lld lld
    PATHS /zq500/sdk/bin /zq500/cuda11/bin
    NO_DEFAULT_PATH)
find_program(CUSIGNAL_ZHONGKEXIN_LLD_FALLBACK NAMES ld.lld lld)
if(CUSIGNAL_ZHONGKEXIN_LLD)
    get_filename_component(CUSIGNAL_ZHONGKEXIN_LLD_DIR "${CUSIGNAL_ZHONGKEXIN_LLD}" DIRECTORY)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=lld -B${CUSIGNAL_ZHONGKEXIN_LLD_DIR}")
elseif(CUSIGNAL_ZHONGKEXIN_LLD_FALLBACK)
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -fuse-ld=lld")
endif()
if(CMAKE_RANLIB)
    set(CMAKE_CXX_ARCHIVE_FINISH "\"${CMAKE_RANLIB}\" <TARGET>")
elseif(CMAKE_AR)
    set(CMAKE_CXX_ARCHIVE_FINISH "\"${CMAKE_AR}\" s <TARGET>")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# 最终交付默认采用 Release，与冻结验证口径一致。
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(CUSIGNAL_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(CUSIGNAL_THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(CUSIGNAL_FFTW_ROOT ${CUSIGNAL_THIRD_PARTY_DIR}/fftw/install)

find_path(
    CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIR
    NAMES cuda_runtime.h
    PATHS
        "$ENV{SDK_DIR}/include"
        "$ENV{DLICC_PATH}/../include"
        /zq500/sdk/include
        /zq500/cuda11/include
)
if(NOT CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIR)
    message(FATAL_ERROR "cuda_runtime.h was not found for ZHONGKEXIN build.")
endif()
set(CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIRS "${CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIR}")
add_library(CUSIGNAL::zx_gpu_headers INTERFACE IMPORTED)
set_target_properties(CUSIGNAL::zx_gpu_headers PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIRS}"
)
message(STATUS "Using Zhongkexin ZQ500 compatibility headers: ${CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIRS}")

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
        "Run scripts/build.sh first.")
endif()

find_package(Threads REQUIRED)

set(CUSIGNAL_ZX_GPU_RUNTIME_TARGET CUSIGNAL::zx_gpu_runtime)
set(CUSIGNAL_ZX_GPU_FFT_TARGET CUSIGNAL::zx_gpu_fft)
set(CUSIGNAL_ZX_GPU_BLAS_TARGET CUSIGNAL::zx_gpu_blas)
set(CUSIGNAL_ZX_GPU_SOLVER_TARGET CUSIGNAL::zx_gpu_solver)
set(CUSIGNAL_ZX_GPU_DNN_TARGET CUSIGNAL::zx_gpu_dnn)
set(CUSIGNAL_ZX_GPU_SPARSE_TARGET CUSIGNAL::zx_gpu_sparse)
set(CUSIGNAL_ZX_GPU_RAND_TARGET CUSIGNAL::zx_gpu_rand)
set(CUSIGNAL_ZHONGKEXIN_EXTRA_LINK_LIBRARIES "")

set(CUSIGNAL_ZHONGKEXIN_RUNTIME_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin runtime-compatible library")
set(CUSIGNAL_ZHONGKEXIN_FFT_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin FFT-compatible library")
set(CUSIGNAL_ZHONGKEXIN_BLAS_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin BLAS-compatible library")
set(CUSIGNAL_ZHONGKEXIN_SOLVER_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin solver-compatible library")
set(CUSIGNAL_ZHONGKEXIN_DNN_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin DNN-compatible library")
set(CUSIGNAL_ZHONGKEXIN_SPARSE_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin sparse-compatible library")
set(CUSIGNAL_ZHONGKEXIN_RAND_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin random-compatible library")
set(CUSIGNAL_ZHONGKEXIN_DLEOL_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin DLEOL support library")

set(CUSIGNAL_ZHONGKEXIN_SDK_ROOT_CANDIDATES
    "$ENV{SDK_DIR}"
    /zq500/sdk
    /zq500/cuda11
)
if(DEFINED ENV{DLICC_PATH})
    list(APPEND CUSIGNAL_ZHONGKEXIN_SDK_ROOT_CANDIDATES "$ENV{DLICC_PATH}/..")
endif()
list(REMOVE_DUPLICATES CUSIGNAL_ZHONGKEXIN_SDK_ROOT_CANDIDATES)

function(cusignal_find_zhongkexin_library cache_library message_name)
    if(DEFINED ${cache_library} AND NOT "${${cache_library}}" STREQUAL "")
        return()
    endif()

    find_library(
        CUSIGNAL_FOUND_ZHONGKEXIN_LIBRARY
        NAMES ${ARGN}
        PATHS ${CUSIGNAL_ZHONGKEXIN_SDK_ROOT_CANDIDATES}
        PATH_SUFFIXES lib lib64
        NO_DEFAULT_PATH
    )
    if(NOT CUSIGNAL_FOUND_ZHONGKEXIN_LIBRARY)
        find_library(CUSIGNAL_FOUND_ZHONGKEXIN_LIBRARY NAMES ${ARGN})
    endif()
    if(NOT CUSIGNAL_FOUND_ZHONGKEXIN_LIBRARY)
        message(FATAL_ERROR
            "${message_name} compatibility library was not found. "
            "Set ${cache_library} explicitly if the SDK uses a non-standard location.")
    endif()
    set(${cache_library} "${CUSIGNAL_FOUND_ZHONGKEXIN_LIBRARY}" CACHE FILEPATH
        "Resolved ${message_name} compatibility library" FORCE)
    unset(CUSIGNAL_FOUND_ZHONGKEXIN_LIBRARY CACHE)
endfunction()

cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_RUNTIME_LIBRARY "ZQ500 runtime" curt)
cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_FFT_LIBRARY "ZQ500 FFT" dlfft cufft)
cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_BLAS_LIBRARY "ZQ500 BLAS" dlblas cublas)
cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_SOLVER_LIBRARY "ZQ500 solver" dlsolver cusolver)
cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_DNN_LIBRARY "ZQ500 DNN" dldnn cudnn)
cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_SPARSE_LIBRARY "ZQ500 sparse" dlsparse cusparse)
cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_RAND_LIBRARY "ZQ500 random" dlrand curand)
cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_DLEOL_LIBRARY "DLEOL" dleol)

set(CUSIGNAL_ZX_GPU_RUNTIME_TARGET "${CUSIGNAL_ZHONGKEXIN_RUNTIME_LIBRARY}")
set(CUSIGNAL_ZX_GPU_FFT_TARGET "${CUSIGNAL_ZHONGKEXIN_FFT_LIBRARY}")
set(CUSIGNAL_ZX_GPU_BLAS_TARGET "${CUSIGNAL_ZHONGKEXIN_BLAS_LIBRARY}")
set(CUSIGNAL_ZX_GPU_SOLVER_TARGET "${CUSIGNAL_ZHONGKEXIN_SOLVER_LIBRARY}")
set(CUSIGNAL_ZX_GPU_DNN_TARGET "${CUSIGNAL_ZHONGKEXIN_DNN_LIBRARY}")
set(CUSIGNAL_ZX_GPU_SPARSE_TARGET "${CUSIGNAL_ZHONGKEXIN_SPARSE_LIBRARY}")
set(CUSIGNAL_ZX_GPU_RAND_TARGET "${CUSIGNAL_ZHONGKEXIN_RAND_LIBRARY}")
set(CUSIGNAL_ZHONGKEXIN_EXTRA_LINK_LIBRARIES
    "${CUSIGNAL_ZHONGKEXIN_DLEOL_LIBRARY}"
    Threads::Threads
)
message(STATUS "Using Zhongkexin ZQ500 runtime compatibility library: ${CUSIGNAL_ZHONGKEXIN_RUNTIME_LIBRARY}")
message(STATUS "Using Zhongkexin ZQ500 FFT compatibility library: ${CUSIGNAL_ZHONGKEXIN_FFT_LIBRARY}")
message(STATUS "Using Zhongkexin ZQ500 BLAS compatibility library: ${CUSIGNAL_ZHONGKEXIN_BLAS_LIBRARY}")
message(STATUS "Using Zhongkexin ZQ500 solver compatibility library: ${CUSIGNAL_ZHONGKEXIN_SOLVER_LIBRARY}")
message(STATUS "Using Zhongkexin ZQ500 DNN compatibility library: ${CUSIGNAL_ZHONGKEXIN_DNN_LIBRARY}")
message(STATUS "Using Zhongkexin ZQ500 sparse compatibility library: ${CUSIGNAL_ZHONGKEXIN_SPARSE_LIBRARY}")
message(STATUS "Using Zhongkexin ZQ500 random compatibility library: ${CUSIGNAL_ZHONGKEXIN_RAND_LIBRARY}")

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

set(CUSIGNAL_ZHONGKEXIN_GPU_SOURCES
    src/zhongkexin/bsplines.cu
    src/zhongkexin/correlate.cu
    src/zhongkexin/demod.cu
    src/zhongkexin/estimation.cu
    src/zhongkexin/filter_design.cu
    src/zhongkexin/filtering.cu
    src/zhongkexin/peak_finding.cu
    src/zhongkexin/radartools.cu
    src/zhongkexin/spectral.cu
    src/zhongkexin/waveforms.cu
    src/zhongkexin/wavelets.cu
    src/zhongkexin/windows.cu
)

list(APPEND CUSIGNAL_ZHONGKEXIN_GPU_SOURCES
    demo/task1_radar/task1_gpu.cu
    demo/task2_features/task2_gpu.cu
    demo/task2_features/task2_features_zx_gpu.cu
)
set_source_files_properties(${CUSIGNAL_ZHONGKEXIN_GPU_SOURCES} PROPERTIES LANGUAGE CXX)
file(GLOB_RECURSE CUSIGNAL_UNIT_TEST_ZX_GPU_SUPPORT_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/*/*_test_support.cu"
    "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/*/waveform_test_support.cu"
)
if(CUSIGNAL_UNIT_TEST_ZX_GPU_SUPPORT_SOURCES)
    set_source_files_properties(${CUSIGNAL_UNIT_TEST_ZX_GPU_SUPPORT_SOURCES} PROPERTIES LANGUAGE CXX)
endif()

function(cusignal_configure_zx_gpu_source_target target_name)
    set_target_properties(${target_name} PROPERTIES POSITION_INDEPENDENT_CODE ON)
    get_target_property(cusignal_target_sources ${target_name} SOURCES)
    foreach(cusignal_target_source IN LISTS cusignal_target_sources)
        if(cusignal_target_source MATCHES "\\.cu$")
            set_source_files_properties(${cusignal_target_source} PROPERTIES LANGUAGE CXX)
        endif()
    endforeach()
    target_compile_options(${target_name} PRIVATE ${CUSIGNAL_ZHONGKEXIN_CXX_GPU_FLAGS})
    target_compile_definitions(${target_name} PRIVATE __CDPRT_SUPPRESS_SYNC_DEPRECATION_WARNING)
endfunction()

add_library(cusignal_cpu STATIC ${CUSIGNAL_CPU_SOURCES})
target_include_directories(cusignal_cpu PUBLIC ${CUSIGNAL_INCLUDE_DIR})
target_compile_features(cusignal_cpu PUBLIC cxx_std_17)
target_compile_definitions(cusignal_cpu PUBLIC CUSIGNAL_PLATFORM_${CUSIGNAL_PLATFORM})
target_include_directories(
    cusignal_cpu
    PUBLIC ${CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIRS}
    PRIVATE ${FFTW3_INCLUDE_DIR}
)
target_link_libraries(cusignal_cpu PRIVATE ${FFTW3_LIBRARY})

add_library(cusignal_zx_gpu STATIC ${CUSIGNAL_ZHONGKEXIN_GPU_SOURCES})
target_include_directories(cusignal_zx_gpu PUBLIC ${CUSIGNAL_INCLUDE_DIR} ${CUSIGNAL_ZHONGKEXIN_COMPAT_INCLUDE_DIRS})
target_compile_features(cusignal_zx_gpu PUBLIC cxx_std_17)
target_compile_definitions(cusignal_zx_gpu PUBLIC CUSIGNAL_PLATFORM_${CUSIGNAL_PLATFORM})
target_compile_definitions(cusignal_zx_gpu PRIVATE __CDPRT_SUPPRESS_SYNC_DEPRECATION_WARNING)
target_include_directories(cusignal_zx_gpu PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/demo/task1_radar
    ${CMAKE_CURRENT_SOURCE_DIR}/demo/task2_features
)
target_compile_options(cusignal_zx_gpu PRIVATE ${CUSIGNAL_ZHONGKEXIN_CXX_GPU_FLAGS})
target_link_libraries(cusignal_zx_gpu PUBLIC cusignal_cpu)
target_link_libraries(cusignal_zx_gpu PRIVATE
    ${CUSIGNAL_ZX_GPU_RUNTIME_TARGET}
    ${CUSIGNAL_ZX_GPU_FFT_TARGET}
    ${CUSIGNAL_ZX_GPU_BLAS_TARGET}
    ${CUSIGNAL_ZX_GPU_SOLVER_TARGET}
    ${CUSIGNAL_ZHONGKEXIN_EXTRA_LINK_LIBRARIES}
)
set_target_properties(cusignal_zx_gpu PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(CMAKE_RANLIB)
    add_custom_command(
        TARGET cusignal_zx_gpu
        POST_BUILD
        COMMAND "${CMAKE_RANLIB}" "$<TARGET_FILE:cusignal_zx_gpu>"
        COMMENT "Indexing Zhongkexin ZQ500 static library"
        VERBATIM
    )
elseif(CMAKE_AR)
    add_custom_command(
        TARGET cusignal_zx_gpu
        POST_BUILD
        COMMAND "${CMAKE_AR}" s "$<TARGET_FILE:cusignal_zx_gpu>"
        COMMENT "Indexing Zhongkexin ZQ500 static library"
        VERBATIM
    )
endif()

add_subdirectory(demo/task1_radar)
add_subdirectory(demo/task2_features)

include(CTest)

if(BUILD_TESTING)
    add_subdirectory(tests/unit)
    add_subdirectory(tests/platform)
endif()
