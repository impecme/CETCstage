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

function(add_waveforms_test target source)
    add_executable(${target} ${source})
    target_link_libraries(${target}
        PRIVATE
            waveforms_test_support
            cusignal_cpu
            cusignal_zx_gpu
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

add_waveforms_test(waveforms_test_chirp test_chirp.cpp)
add_waveforms_test(waveforms_test_gausspulse test_gausspulse.cpp)
add_waveforms_test(waveforms_test_sawtooth test_sawtooth.cpp)
add_waveforms_test(waveforms_test_square test_square.cpp)
add_waveforms_test(waveforms_test_unit_impulse test_unit_impulse.cpp)
