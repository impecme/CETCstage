add_library(spectral_test_support STATIC
    spectral_test_support.cu
)
target_link_libraries(spectral_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(spectral_test_support PUBLIC cxx_std_17)
target_compile_definitions(spectral_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(spectral_test_support)

function(add_spectral_test target)
    string(REPLACE "spectral_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            spectral_test_support
            cusignal_cpu
            cusignal_zx_gpu
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    lombscargle
    periodogram
    welch
    csd
    spectrogram
    stft
    istft
    coherence
    vectorstrength
)
    add_spectral_test(spectral_test_${op})
endforeach()
