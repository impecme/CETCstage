find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(ZX_COMPAT_REPORT_DIR "${CMAKE_BINARY_DIR}/reports/zx_compatibility")
set(ZX_COMPAT_MATRIX_JSON "${ZX_COMPAT_REPORT_DIR}/compatibility.json")
set(ZX_COMPAT_FORBIDDEN_APIS "${ZX_COMPAT_REPORT_DIR}/forbidden_apis.txt")
set(ZX_COMPAT_USAGE_JSON "${ZX_COMPAT_REPORT_DIR}/api_usage.json")
set(ZX_COMPAT_FIXTURE_VALIDATION_JSON "${ZX_COMPAT_REPORT_DIR}/fixture_validation.json")
set(ZX_COMPAT_FIXTURE_MANIFEST "${CMAKE_SOURCE_DIR}/tests/platform/config/zx_compat_fixture_manifest.json")
option(
    ZX_COMPAT_REQUIRE_FIXTURES
    "Fail configure when the external ZQ500 compatibility XLSX fixtures are unavailable"
    OFF
)
set(ZX_COMPAT_SOURCE_DIR_DEFAULT "${CMAKE_SOURCE_DIR}/复赛说明文件")
if(DEFINED ENV{ZX_COMPAT_SOURCE_DIR} AND NOT "$ENV{ZX_COMPAT_SOURCE_DIR}" STREQUAL "")
    set(ZX_COMPAT_SOURCE_DIR_DEFAULT "$ENV{ZX_COMPAT_SOURCE_DIR}")
endif()
set(
    ZX_COMPAT_SOURCE_DIR
    "${ZX_COMPAT_SOURCE_DIR_DEFAULT}"
    CACHE PATH
    "External directory containing the three competition compatibility XLSX files"
)
unset(ZX_COMPAT_SOURCE_DIR_DEFAULT)
set(ZX_COMPAT_DRIVER_XLSX "${ZX_COMPAT_SOURCE_DIR}/CUDA 11.7 driver api.xlsx")
set(ZX_COMPAT_RUNTIME_XLSX "${ZX_COMPAT_SOURCE_DIR}/CUDA 11.7 runtime API.xlsx")
set(ZX_COMPAT_LIBRARIES_XLSX "${ZX_COMPAT_SOURCE_DIR}/科学计算库实现列表.xlsx")
set(ZX_COMPAT_INPUTS_AVAILABLE TRUE)
foreach(input IN ITEMS
    "${ZX_COMPAT_FIXTURE_MANIFEST}"
    "${ZX_COMPAT_DRIVER_XLSX}"
    "${ZX_COMPAT_RUNTIME_XLSX}"
    "${ZX_COMPAT_LIBRARIES_XLSX}"
)
    if(NOT EXISTS "${input}")
        set(ZX_COMPAT_INPUTS_AVAILABLE FALSE)
    endif()
endforeach()
if(ZX_COMPAT_REQUIRE_FIXTURES AND NOT ZX_COMPAT_INPUTS_AVAILABLE)
    message(FATAL_ERROR
        "ZQ500 compatibility fixtures are required but unavailable under: ${ZX_COMPAT_SOURCE_DIR}"
    )
endif()

if(ZX_COMPAT_INPUTS_AVAILABLE)
    add_custom_command(
        OUTPUT "${ZX_COMPAT_MATRIX_JSON}" "${ZX_COMPAT_FORBIDDEN_APIS}"
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/platform/tools/generate_zx_compat_matrix.py"
            --driver "${ZX_COMPAT_DRIVER_XLSX}"
            --runtime "${ZX_COMPAT_RUNTIME_XLSX}"
            --libraries "${ZX_COMPAT_LIBRARIES_XLSX}"
            --source-manifest "${ZX_COMPAT_FIXTURE_MANIFEST}"
            --output "${ZX_COMPAT_REPORT_DIR}"
        DEPENDS
            "${CMAKE_SOURCE_DIR}/tests/platform/tools/generate_zx_compat_matrix.py"
            "${CMAKE_SOURCE_DIR}/tests/platform/tools/validate_zx_compat_fixtures.py"
            "${ZX_COMPAT_FIXTURE_MANIFEST}"
            "${ZX_COMPAT_DRIVER_XLSX}"
            "${ZX_COMPAT_RUNTIME_XLSX}"
            "${ZX_COMPAT_LIBRARIES_XLSX}"
        COMMENT "Generating the ZQ500 compatibility matrix"
        VERBATIM
    )
else()
    message(STATUS "ZQ500 compatibility XLSX fixtures are external; compatibility matrix tests are disabled")
endif()

add_library(zx_compat_compile_probes OBJECT zx_compat_compile_probes.cu)
target_link_libraries(zx_compat_compile_probes PRIVATE CUSIGNAL::zx_gpu_headers)
target_compile_features(zx_compat_compile_probes PRIVATE cxx_std_17)
cusignal_configure_zx_gpu_source_target(zx_compat_compile_probes)

add_executable(zx_compat_runtime_probes zx_compat_runtime_probes.cu)
target_link_libraries(zx_compat_runtime_probes PRIVATE
    CUSIGNAL::zx_gpu_headers
    ${CUSIGNAL_ZX_GPU_RUNTIME_TARGET}
    ${CUSIGNAL_ZX_GPU_FFT_TARGET}
    ${CUSIGNAL_ZX_GPU_BLAS_TARGET}
    ${CUSIGNAL_ZX_GPU_SOLVER_TARGET}
    ${CUSIGNAL_ZX_GPU_DNN_TARGET}
    ${CUSIGNAL_ZX_GPU_SPARSE_TARGET}
    ${CUSIGNAL_ZX_GPU_RAND_TARGET}
    ${CUSIGNAL_ZHONGKEXIN_EXTRA_LINK_LIBRARIES}
)
target_compile_features(zx_compat_runtime_probes PRIVATE cxx_std_17)
cusignal_configure_zx_gpu_source_target(zx_compat_runtime_probes)

if(ZX_COMPAT_INPUTS_AVAILABLE)
    add_custom_target(zx_compat_fixture_check
        COMMAND "${CMAKE_COMMAND}" -E rm -f "${ZX_COMPAT_USAGE_JSON}"
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/platform/tools/validate_zx_compat_fixtures.py"
            --source-dir "${ZX_COMPAT_SOURCE_DIR}"
            --manifest "${ZX_COMPAT_FIXTURE_MANIFEST}"
            --output "${ZX_COMPAT_FIXTURE_VALIDATION_JSON}"
        COMMENT "Validating frozen ZQ500 compatibility fixture identities"
        VERBATIM
    )
    add_custom_target(zx_forbidden_api_scan
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/platform/tools/scan_zx_api_usage.py"
            --matrix "${ZX_COMPAT_MATRIX_JSON}"
            --forbidden "${ZX_COMPAT_FORBIDDEN_APIS}"
            --source-dir "${ZX_COMPAT_SOURCE_DIR}"
            --source-manifest "${ZX_COMPAT_FIXTURE_MANIFEST}"
            --exceptions "${CMAKE_SOURCE_DIR}/tests/platform/config/zx_api_usage_exceptions.json"
            --roots "${CMAKE_SOURCE_DIR}/include" "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/demo" "${CMAKE_SOURCE_DIR}/tests"
            --output "${ZX_COMPAT_USAGE_JSON}"
        DEPENDS
            "${ZX_COMPAT_MATRIX_JSON}"
            "${ZX_COMPAT_FORBIDDEN_APIS}"
            "${CMAKE_SOURCE_DIR}/tests/platform/tools/scan_zx_api_usage.py"
            "${CMAKE_SOURCE_DIR}/tests/platform/config/zx_api_usage_exceptions.json"
        COMMENT "Scanning project sources for unsupported ZQ500 APIs"
        VERBATIM
    )
    add_dependencies(zx_forbidden_api_scan zx_compat_fixture_check)
endif()

add_test(NAME zx_compat_runtime_safe COMMAND zx_compat_runtime_probes)

# Explicit, opt-in C500 offline autotuning target.  It depends on the unit
# operator binaries discovered from tests/unit, but is never part of the
# default build or ctest suite.  The script runs performance.sh with the
# frozen baseline and writes the device-specific JSON outside the source tree.
set(
    ZX_AUTOTUNE_BASELINE
    "${CMAKE_SOURCE_DIR}/operator_gpu_baseline_75a700d_protocol"
    CACHE PATH
    "Frozen operator baseline used by zx_operator_autotune"
)
set(
    ZX_AUTOTUNE_OUTPUT_ROOT
    "${CMAKE_BINARY_DIR}/reports/zx_operator_autotune"
    CACHE PATH
    "Working reports for zx_operator_autotune"
)
set(
    ZX_AUTOTUNE_CACHE_OUTPUT
    "${CMAKE_BINARY_DIR}/zx_tuning.json"
    CACHE FILEPATH
    "External device-specific cache emitted by zx_operator_autotune"
)
set(ZX_AUTOTUNE_WARMUP 5 CACHE STRING "Offline autotuning warmup iterations")
set(ZX_AUTOTUNE_REPEAT 30 CACHE STRING "Offline autotuning measured repetitions")
file(GLOB ZX_AUTOTUNE_TEST_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/tests/unit/*/test_*.cpp"
)
set(ZX_AUTOTUNE_TEST_TARGETS)
foreach(test_source IN LISTS ZX_AUTOTUNE_TEST_SOURCES)
    get_filename_component(test_module_dir "${test_source}" DIRECTORY)
    get_filename_component(test_module "${test_module_dir}" NAME)
    get_filename_component(test_name "${test_source}" NAME_WE)
    string(REGEX REPLACE "^test_" "" test_operator "${test_name}")
    set(test_target "${test_module}_test_${test_operator}")
    if(TARGET "${test_target}")
        list(APPEND ZX_AUTOTUNE_TEST_TARGETS "${test_target}")
    endif()
endforeach()
list(REMOVE_DUPLICATES ZX_AUTOTUNE_TEST_TARGETS)
add_custom_target(
    zx_operator_autotune
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/zx_operator_autotune.py"
        --frozen-baseline "${ZX_AUTOTUNE_BASELINE}"
        --output-root "${ZX_AUTOTUNE_OUTPUT_ROOT}"
        --cache-output "${ZX_AUTOTUNE_CACHE_OUTPUT}"
        --build-dir "${CMAKE_BINARY_DIR}"
        --warmup "${ZX_AUTOTUNE_WARMUP}"
        --repeat "${ZX_AUTOTUNE_REPEAT}"
        --skip-cpu-timing
        --selection-validation "winner-against-static"
    WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
    DEPENDS
        ${ZX_AUTOTUNE_TEST_TARGETS}
        "${CMAKE_SOURCE_DIR}/scripts/zx_operator_autotune.py"
    COMMENT "Running the opt-in C500 offline operator autotuner"
    VERBATIM
)

add_test(
    NAME zx_compat_fixture_validation_test
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_validate_zx_compat_fixtures.py"
)
if(ZX_COMPAT_INPUTS_AVAILABLE)
    add_test(
        NAME zx_forbidden_api_scan_test
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tests/platform/tools/scan_zx_api_usage.py"
            --matrix "${ZX_COMPAT_MATRIX_JSON}"
            --forbidden "${ZX_COMPAT_FORBIDDEN_APIS}"
            --source-dir "${ZX_COMPAT_SOURCE_DIR}"
            --source-manifest "${ZX_COMPAT_FIXTURE_MANIFEST}"
            --exceptions "${CMAKE_SOURCE_DIR}/tests/platform/config/zx_api_usage_exceptions.json"
            --roots "${CMAKE_SOURCE_DIR}/include" "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/demo" "${CMAKE_SOURCE_DIR}/tests"
            --output "${ZX_COMPAT_USAGE_JSON}"
    )
    set_tests_properties(zx_forbidden_api_scan_test PROPERTIES
        DEPENDS zx_compat_runtime_safe
        REQUIRED_FILES "${ZX_COMPAT_MATRIX_JSON};${ZX_COMPAT_FORBIDDEN_APIS}"
    )
endif()
