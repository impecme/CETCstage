find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(ZX_COMPAT_REPORT_DIR "${CMAKE_BINARY_DIR}/reports/zx_compatibility")
set(ZX_COMPAT_MATRIX_JSON "${ZX_COMPAT_REPORT_DIR}/compatibility.json")
set(ZX_COMPAT_FORBIDDEN_APIS "${ZX_COMPAT_REPORT_DIR}/forbidden_apis.txt")
set(ZX_COMPAT_USAGE_JSON "${ZX_COMPAT_REPORT_DIR}/api_usage.json")

add_custom_command(
    OUTPUT "${ZX_COMPAT_MATRIX_JSON}" "${ZX_COMPAT_FORBIDDEN_APIS}"
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/platform/generate_zx_compat_matrix.py"
        --driver "${CMAKE_SOURCE_DIR}/复赛说明文件/CUDA 11.7 driver api.xlsx"
        --runtime "${CMAKE_SOURCE_DIR}/复赛说明文件/CUDA 11.7 runtime API.xlsx"
        --libraries "${CMAKE_SOURCE_DIR}/复赛说明文件/科学计算库实现列表.xlsx"
        --output "${ZX_COMPAT_REPORT_DIR}"
    DEPENDS
        "${CMAKE_SOURCE_DIR}/scripts/platform/generate_zx_compat_matrix.py"
        "${CMAKE_SOURCE_DIR}/复赛说明文件/CUDA 11.7 driver api.xlsx"
        "${CMAKE_SOURCE_DIR}/复赛说明文件/CUDA 11.7 runtime API.xlsx"
        "${CMAKE_SOURCE_DIR}/复赛说明文件/科学计算库实现列表.xlsx"
    COMMENT "Generating the ZQ500 compatibility matrix"
    VERBATIM
)

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

add_custom_target(zx_forbidden_api_scan
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/platform/scan_zx_api_usage.py"
        --matrix "${ZX_COMPAT_MATRIX_JSON}"
        --forbidden "${ZX_COMPAT_FORBIDDEN_APIS}"
        --exceptions "${CMAKE_SOURCE_DIR}/scripts/platform/zx_api_usage_exceptions.json"
        --roots "${CMAKE_SOURCE_DIR}/include" "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/demo" "${CMAKE_SOURCE_DIR}/tests"
        --output "${ZX_COMPAT_USAGE_JSON}"
    DEPENDS
        "${ZX_COMPAT_MATRIX_JSON}"
        "${ZX_COMPAT_FORBIDDEN_APIS}"
        "${CMAKE_SOURCE_DIR}/scripts/platform/scan_zx_api_usage.py"
        "${CMAKE_SOURCE_DIR}/scripts/platform/zx_api_usage_exceptions.json"
    COMMENT "Scanning project sources for unsupported ZQ500 APIs"
    VERBATIM
)

add_test(NAME zx_compat_runtime_safe COMMAND zx_compat_runtime_probes)
add_test(
    NAME finalize_v6_delivery_evidence_test
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_finalize_v6_8_delivery.py"
)
add_test(
    NAME finalize_v7_delivery_evidence_test
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_finalize_v7_delivery.py"
)
add_test(
    NAME zx_forbidden_api_scan_test
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/scripts/platform/scan_zx_api_usage.py"
        --matrix "${ZX_COMPAT_MATRIX_JSON}"
        --forbidden "${ZX_COMPAT_FORBIDDEN_APIS}"
        --exceptions "${CMAKE_SOURCE_DIR}/scripts/platform/zx_api_usage_exceptions.json"
        --roots "${CMAKE_SOURCE_DIR}/include" "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/demo" "${CMAKE_SOURCE_DIR}/tests"
        --output "${ZX_COMPAT_USAGE_JSON}"
)
set_tests_properties(zx_forbidden_api_scan_test PROPERTIES
    DEPENDS zx_compat_runtime_safe
    REQUIRED_FILES "${ZX_COMPAT_MATRIX_JSON};${ZX_COMPAT_FORBIDDEN_APIS}"
)
