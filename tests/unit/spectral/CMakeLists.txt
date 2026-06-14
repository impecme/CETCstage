add_library(spectral_test_support STATIC
    spectral_test_support.cu
)
target_link_libraries(spectral_test_support
    PRIVATE
        cusignal_cpu
        cusignal_cuda
)
target_compile_features(spectral_test_support PUBLIC cxx_std_17)
target_compile_definitions(spectral_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
set_target_properties(spectral_test_support PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    POSITION_INDEPENDENT_CODE ON
)

function(add_spectral_test target)
    string(REPLACE "spectral_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            spectral_test_support
            cusignal_cpu
            cusignal_cuda
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
