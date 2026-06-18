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

add_executable(demod_test_fm_demod test_fm_demod.cpp)
target_link_libraries(demod_test_fm_demod
    PRIVATE
        demod_test_support
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(demod_test_fm_demod PRIVATE cxx_std_17)
add_test(NAME demod_test_fm_demod COMMAND demod_test_fm_demod)
