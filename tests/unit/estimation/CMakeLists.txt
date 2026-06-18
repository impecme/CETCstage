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

add_executable(estimation_test_kalman_filter test_kalman_filter.cpp)
target_link_libraries(estimation_test_kalman_filter
    PRIVATE
        estimation_test_support
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(estimation_test_kalman_filter PRIVATE cxx_std_17)
add_test(NAME estimation_test_kalman_filter COMMAND estimation_test_kalman_filter)
