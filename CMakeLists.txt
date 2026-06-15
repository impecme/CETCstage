cmake_minimum_required(VERSION 3.18)

set(CUSIGNAL_PLATFORM "NVIDIA" CACHE STRING "Target GPU platform: NVIDIA or ZHONGKEXIN")
set_property(CACHE CUSIGNAL_PLATFORM PROPERTY STRINGS NVIDIA ZHONGKEXIN)
string(TOUPPER "${CUSIGNAL_PLATFORM}" CUSIGNAL_PLATFORM_UPPER)
if(NOT CUSIGNAL_PLATFORM_UPPER STREQUAL "NVIDIA" AND
   NOT CUSIGNAL_PLATFORM_UPPER STREQUAL "ZHONGKEXIN")
    message(FATAL_ERROR "CUSIGNAL_PLATFORM must be NVIDIA or ZHONGKEXIN, got: ${CUSIGNAL_PLATFORM}")
endif()
set(CUSIGNAL_PLATFORM "${CUSIGNAL_PLATFORM_UPPER}" CACHE STRING "Target GPU platform: NVIDIA or ZHONGKEXIN" FORCE)

if(CUSIGNAL_PLATFORM STREQUAL "NVIDIA" AND NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES 80 CACHE STRING "Default CUDA architecture" FORCE)
elseif(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN" AND NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES OFF CACHE STRING "Disable NVIDIA CUDA architecture flags for Zhongkexin" FORCE)
endif()
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN" AND NOT DEFINED CMAKE_TRY_COMPILE_TARGET_TYPE)
    set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY CACHE STRING "Avoid CUDA executable try-compile links on Zhongkexin" FORCE)
endif()
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    set(CMAKE_CUDA_COMPILER_FORCED ON CACHE BOOL "Skip CUDA compiler working test for Zhongkexin" FORCE)
    set(CMAKE_CUDA_COMPILER_WORKS ON CACHE BOOL "Assume CUDA compiler works for Zhongkexin" FORCE)
    set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -std=c++17" CACHE STRING "CUDA flags for Zhongkexin" FORCE)
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
    if(CMAKE_AR)
        set(CMAKE_CUDA_COMPILER_AR "${CMAKE_AR}" CACHE FILEPATH "CUDA archive tool for Zhongkexin" FORCE)
    endif()
    if(CMAKE_RANLIB)
        set(CMAKE_CUDA_COMPILER_RANLIB "${CMAKE_RANLIB}" CACHE FILEPATH "CUDA ranlib tool for Zhongkexin" FORCE)
    endif()
endif()
# V2.1 统一采用 C++17 / CUDA17，并以公开 API 对齐为本轮交付重点。
project(cusignal_cpp_v2_1 LANGUAGES CXX CUDA)

if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    if(CMAKE_AR)
        set(CMAKE_CUDA_ARCHIVE_CREATE "\"${CMAKE_AR}\" rcs <TARGET> <LINK_FLAGS> <OBJECTS>")
        set(CMAKE_CUDA_ARCHIVE_APPEND "\"${CMAKE_AR}\" rcs <TARGET> <LINK_FLAGS> <OBJECTS>")
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
        set(CMAKE_CUDA_ARCHIVE_FINISH "\"${CMAKE_RANLIB}\" <TARGET>")
        set(CMAKE_CXX_ARCHIVE_FINISH "\"${CMAKE_RANLIB}\" <TARGET>")
    elseif(CMAKE_AR)
        set(CMAKE_CUDA_ARCHIVE_FINISH "\"${CMAKE_AR}\" s <TARGET>")
        set(CMAKE_CXX_ARCHIVE_FINISH "\"${CMAKE_AR}\" s <TARGET>")
    endif()
endif()

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

set(CUSIGNAL_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/include)
set(CUSIGNAL_THIRD_PARTY_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party)
set(CUSIGNAL_FFTW_ROOT ${CUSIGNAL_THIRD_PARTY_DIR}/fftw/install)

if(CUSIGNAL_PLATFORM STREQUAL "NVIDIA")
    find_package(CUDAToolkit REQUIRED)
else()
    find_package(CUDAToolkit QUIET)
    if(NOT CUDAToolkit_FOUND)
        find_path(
            CUSIGNAL_ZHONGKEXIN_CUDA_INCLUDE_DIR
            NAMES cuda_runtime.h
            PATHS
                "$ENV{CUDA_ROOT}/include"
                "$ENV{CUDA_HOME}/include"
                "$ENV{CUDA_PATH}/include"
                /zq500/cuda11/include
                /zq500/sdk/include
                /usr/local/cuda/include
        )
        if(NOT CUSIGNAL_ZHONGKEXIN_CUDA_INCLUDE_DIR)
            message(FATAL_ERROR "cuda_runtime.h was not found for ZHONGKEXIN build.")
        endif()
        set(CUDAToolkit_INCLUDE_DIRS "${CUSIGNAL_ZHONGKEXIN_CUDA_INCLUDE_DIR}")
        add_library(CUDA::cudart INTERFACE IMPORTED)
        set_target_properties(CUDA::cudart PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${CUDAToolkit_INCLUDE_DIRS}"
        )
        message(STATUS "Using Zhongkexin CUDA headers without CUDAToolkit cudart target: ${CUDAToolkit_INCLUDE_DIRS}")
    endif()
endif()

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

    if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
        add_library(${target_name} INTERFACE IMPORTED)
        set_target_properties(${target_name} PROPERTIES
            INTERFACE_INCLUDE_DIRECTORIES "${CUDAToolkit_INCLUDE_DIRS}"
        )
        message(STATUS "Deferring ${message_name} compatibility library resolution to Zhongkexin compiler/linker")
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

if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    list(APPEND CUSIGNAL_CUDA_SOURCES
        demo/task1_radar/task1_radar_cuda.cu
        demo/task2_features/task2_features_cuda.cu
    )
endif()

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
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    target_include_directories(cusignal_cuda PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/demo/task1_radar
        ${CMAKE_CURRENT_SOURCE_DIR}/demo/task2_features
    )
    target_compile_options(cusignal_cuda PUBLIC $<$<COMPILE_LANGUAGE:CUDA>:-std=c++17>)
endif()
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
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    set_target_properties(cusignal_cuda PROPERTIES LINKER_LANGUAGE CUDA)
    if(CMAKE_RANLIB)
        add_custom_command(
            TARGET cusignal_cuda
            POST_BUILD
            COMMAND "${CMAKE_RANLIB}" "$<TARGET_FILE:cusignal_cuda>"
            COMMENT "Indexing Zhongkexin CUDA static library"
            VERBATIM
        )
    elseif(CMAKE_AR)
        add_custom_command(
            TARGET cusignal_cuda
            POST_BUILD
            COMMAND "${CMAKE_AR}" s "$<TARGET_FILE:cusignal_cuda>"
            COMMENT "Indexing Zhongkexin CUDA static library"
            VERBATIM
        )
    endif()
endif()

add_subdirectory(demo/task1_radar)
add_subdirectory(demo/task2_features)

include(CTest)

if(BUILD_TESTING)
    add_subdirectory(tests/smoke)
    add_subdirectory(tests/unit)
endif()
