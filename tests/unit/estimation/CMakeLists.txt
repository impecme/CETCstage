add_library(estimation_test_support STATIC
    estimation_test_support.cu
)
target_link_libraries(estimation_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(estimation_test_support PUBLIC cxx_std_17)
target_compile_definitions(estimation_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(estimation_test_support)

cusignal_add_operator_test(
    estimation_test_kalman_filter
    "${CMAKE_CURRENT_SOURCE_DIR}/test_kalman_filter.cpp"
    estimation_test_support
)
