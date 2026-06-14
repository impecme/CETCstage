add_library(windows_test_support STATIC
    windows_test_support.cu
)
target_link_libraries(windows_test_support
    PRIVATE
        cusignal_cpu
        cusignal_cuda
)
target_compile_features(windows_test_support PUBLIC cxx_std_17)
target_compile_definitions(windows_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
set_target_properties(windows_test_support PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    POSITION_INDEPENDENT_CODE ON
)

function(add_windows_test target)
    add_executable(${target} windows_test_main.cpp)
    target_link_libraries(${target}
        PRIVATE
            windows_test_support
            cusignal_cpu
            cusignal_cuda
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    get_window
    barthann
    bartlett
    blackman
    blackmanharris
    bohman
    boxcar
    chebwin
    cosine
    exponential
    flattop
    gaussian
    general_cosine
    general_gaussian
    general_hamming
    hamming
    hann
    kaiser
    nuttall
    parzen
    taylor
    triang
    tukey
)
    add_windows_test(windows_test_${op})
endforeach()
