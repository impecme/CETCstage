add_library(radartools_test_support STATIC
    radartools_test_support.cu
)
target_link_libraries(radartools_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(radartools_test_support PUBLIC cxx_std_17)
target_compile_definitions(radartools_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(radartools_test_support)

function(add_radartools_test target)
    string(REPLACE "radartools_test_" "" op "${target}")
    cusignal_add_operator_test(
        ${target}
        "${CMAKE_CURRENT_SOURCE_DIR}/test_${op}.cpp"
        radartools_test_support
    )
endfunction()

foreach(op
    pulse_compression
    pulse_doppler
    ambgfun
    cfar_alpha
    ca_cfar
    mvdr
)
    add_radartools_test(radartools_test_${op})
endforeach()

foreach(op fftshift_rows power_map detect_peak)
    add_executable(radartools_task_test_${op} test_${op}.cpp)
    target_link_libraries(radartools_task_test_${op} PRIVATE cusignal_cpu cusignal_zx_gpu)
    target_compile_features(radartools_task_test_${op} PRIVATE cxx_std_17)
    add_test(NAME radartools_task_test_${op} COMMAND radartools_task_test_${op})
endforeach()
