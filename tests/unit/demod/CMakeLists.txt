add_library(demod_test_support STATIC
    demod_test_support.cu
)
target_link_libraries(demod_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(demod_test_support PUBLIC cxx_std_17)
target_compile_definitions(demod_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(demod_test_support)

cusignal_add_operator_test(
    demod_test_fm_demod
    "${CMAKE_CURRENT_SOURCE_DIR}/test_fm_demod.cpp"
    demod_test_support
)
