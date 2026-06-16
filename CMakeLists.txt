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
endif()
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    set(CUSIGNAL_ZHONGKEXIN_CXX_CUDA_FLAGS
        "-fPIC;-x;cuda;--cuda-gpu-arch=dlgput64"
        CACHE STRING "Compile flags used by dlcc when compiling .cu sources as CXX for Zhongkexin")
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
endif()
# V2.1 统一采用 C++17 / CUDA17，并以公开 API 对齐为本轮交付重点。
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    project(cusignal_cpp_v2_1 LANGUAGES CXX)
else()
    project(cusignal_cpp_v2_1 LANGUAGES CXX CUDA)
endif()

if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
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
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(NOT CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    set(CMAKE_CUDA_STANDARD 17)
    set(CMAKE_CUDA_STANDARD_REQUIRED ON)
    set(CMAKE_CUDA_EXTENSIONS OFF)
endif()

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
                /zq500/sdk/include
                /zq500/cuda11/include
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

find_package(Threads REQUIRED)

set(CUSIGNAL_CUDART_TARGET CUDA::cudart)
set(CUSIGNAL_CUFFT_TARGET CUDA::cufft_static)
set(CUSIGNAL_CUBLAS_TARGET CUDA::cublas)
set(CUSIGNAL_CUSOLVER_TARGET CUDA::cusolver)
set(CUSIGNAL_ZHONGKEXIN_EXTRA_LINK_LIBRARIES "")

set(CUSIGNAL_ZHONGKEXIN_CUDART_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin CUDA runtime-compatible library")
set(CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin cuFFT-compatible library")
set(CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin cuBLAS-compatible library")
set(CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin cuSOLVER-compatible library")
set(CUSIGNAL_ZHONGKEXIN_DLEOL_LIBRARY "" CACHE FILEPATH "Optional Zhongkexin DLEOL support library")

if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    set(CUSIGNAL_ZHONGKEXIN_SDK_ROOT_CANDIDATES
        "$ENV{SDK_DIR}"
        /zq500/sdk
        /zq500/cuda11
        /usr/local/cuda
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

    cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_CUDART_LIBRARY "CUDA runtime" curt)
    cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY "cuFFT" dlfft cufft)
    cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY "cuBLAS" dlblas cublas)
    cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY "cuSOLVER" dlsolver cusolver)
    cusignal_find_zhongkexin_library(CUSIGNAL_ZHONGKEXIN_DLEOL_LIBRARY "DLEOL" dleol)

    set(CUSIGNAL_CUDART_TARGET "${CUSIGNAL_ZHONGKEXIN_CUDART_LIBRARY}")
    set(CUSIGNAL_CUFFT_TARGET "${CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY}")
    set(CUSIGNAL_CUBLAS_TARGET "${CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY}")
    set(CUSIGNAL_CUSOLVER_TARGET "${CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY}")
    set(CUSIGNAL_ZHONGKEXIN_EXTRA_LINK_LIBRARIES
        "${CUSIGNAL_ZHONGKEXIN_DLEOL_LIBRARY}"
        Threads::Threads
    )
    message(STATUS "Using Zhongkexin CUDA runtime compatibility library: ${CUSIGNAL_ZHONGKEXIN_CUDART_LIBRARY}")
    message(STATUS "Using Zhongkexin cuFFT compatibility library: ${CUSIGNAL_ZHONGKEXIN_CUFFT_LIBRARY}")
    message(STATUS "Using Zhongkexin cuBLAS compatibility library: ${CUSIGNAL_ZHONGKEXIN_CUBLAS_LIBRARY}")
    message(STATUS "Using Zhongkexin cuSOLVER compatibility library: ${CUSIGNAL_ZHONGKEXIN_CUSOLVER_LIBRARY}")
endif()

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
    set_source_files_properties(${CUSIGNAL_CUDA_SOURCES} PROPERTIES LANGUAGE CXX)
    file(GLOB_RECURSE CUSIGNAL_UNIT_TEST_CUDA_SUPPORT_SOURCES CONFIGURE_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/*/*_test_support.cu"
        "${CMAKE_CURRENT_SOURCE_DIR}/tests/unit/*/waveform_test_support.cu"
    )
    if(CUSIGNAL_UNIT_TEST_CUDA_SUPPORT_SOURCES)
        set_source_files_properties(${CUSIGNAL_UNIT_TEST_CUDA_SUPPORT_SOURCES} PROPERTIES LANGUAGE CXX)
    endif()
endif()

function(cusignal_configure_cuda_source_target target_name)
    set_target_properties(${target_name} PROPERTIES POSITION_INDEPENDENT_CODE ON)
    if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
        get_target_property(cusignal_target_sources ${target_name} SOURCES)
        foreach(cusignal_target_source IN LISTS cusignal_target_sources)
            if(cusignal_target_source MATCHES "\\.cu$")
                set_source_files_properties(${cusignal_target_source} PROPERTIES LANGUAGE CXX)
            endif()
        endforeach()
        target_compile_options(${target_name} PRIVATE ${CUSIGNAL_ZHONGKEXIN_CXX_CUDA_FLAGS})
    else()
        set_target_properties(${target_name} PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
    endif()
endfunction()

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
    target_compile_options(cusignal_cuda PRIVATE ${CUSIGNAL_ZHONGKEXIN_CXX_CUDA_FLAGS})
endif()
target_link_libraries(cusignal_cuda PUBLIC cusignal_cpu)
target_link_libraries(cusignal_cuda PRIVATE
    ${CUSIGNAL_CUDART_TARGET}
    ${CUSIGNAL_CUFFT_TARGET}
    ${CUSIGNAL_CUBLAS_TARGET}
    ${CUSIGNAL_CUSOLVER_TARGET}
    ${CUSIGNAL_ZHONGKEXIN_EXTRA_LINK_LIBRARIES}
)
set_target_properties(cusignal_cuda PROPERTIES POSITION_INDEPENDENT_CODE ON)
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
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
else()
    set_target_properties(cusignal_cuda PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
endif()

add_subdirectory(demo/task1_radar)
add_subdirectory(demo/task2_features)

include(CTest)

if(BUILD_TESTING)
    add_subdirectory(tests/smoke)
    add_subdirectory(tests/unit)
endif()
