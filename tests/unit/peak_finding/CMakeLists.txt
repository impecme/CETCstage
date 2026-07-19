add_library(peak_finding_test_support STATIC
    peak_finding_test_support.cu
)
target_link_libraries(peak_finding_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(peak_finding_test_support PUBLIC cxx_std_17)
target_compile_definitions(peak_finding_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(peak_finding_test_support)

function(add_peak_finding_test target)
    string(REPLACE "peak_finding_test_" "" op "${target}")
    cusignal_add_operator_test(
        ${target}
        "${CMAKE_CURRENT_SOURCE_DIR}/test_${op}.cpp"
        peak_finding_test_support
    )
endfunction()

foreach(op
    argrelextrema
    argrelmin
    argrelmax
)
    add_peak_finding_test(peak_finding_test_${op})
endforeach()
