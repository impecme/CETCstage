add_library(filter_design_test_support STATIC
    filter_design_test_support.cu
)
target_link_libraries(filter_design_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(filter_design_test_support PUBLIC cxx_std_17)
target_compile_definitions(filter_design_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(filter_design_test_support)

function(add_filter_design_test target)
    string(REPLACE "filter_design_test_" "" op "${target}")
    cusignal_add_operator_test(
        ${target}
        "${CMAKE_CURRENT_SOURCE_DIR}/test_${op}.cpp"
        filter_design_test_support
    )
endfunction()

foreach(op
    kaiser_beta
    kaiser_atten
    cmplx_sort
    firwin
    firwin2
)
    add_filter_design_test(filter_design_test_${op})
endforeach()
