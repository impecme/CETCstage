add_library(wavelets_test_support STATIC
    wavelets_test_support.cu
)
target_link_libraries(wavelets_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(wavelets_test_support PUBLIC cxx_std_17)
target_compile_definitions(wavelets_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(wavelets_test_support)

function(add_wavelets_test target)
    string(REPLACE "wavelets_test_" "" op "${target}")
    cusignal_add_operator_test(
        ${target}
        "${CMAKE_CURRENT_SOURCE_DIR}/test_${op}.cpp"
        wavelets_test_support
    )
endfunction()

foreach(op
    qmf
    morlet
    ricker
    morlet2
    cwt
)
    add_wavelets_test(wavelets_test_${op})
endforeach()
