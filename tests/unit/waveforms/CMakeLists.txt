add_library(waveforms_test_support STATIC
    waveform_test_support.cu
)
target_link_libraries(waveforms_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(waveforms_test_support PUBLIC cxx_std_17)
target_compile_definitions(waveforms_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(waveforms_test_support)

function(add_waveforms_test op)
    cusignal_add_operator_test(
        waveforms_test_${op}
        "${CMAKE_CURRENT_SOURCE_DIR}/test_${op}.cpp"
        waveforms_test_support
    )
endfunction()

foreach(op chirp gausspulse sawtooth square unit_impulse)
    add_waveforms_test(${op})
endforeach()
