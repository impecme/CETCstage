add_library(windows_test_support STATIC
    windows_test_support.cu
)
target_link_libraries(windows_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(windows_test_support PUBLIC cxx_std_17)
target_compile_definitions(windows_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(windows_test_support)

function(add_windows_test target)
    string(REPLACE "windows_test_" "" op "${target}")
    add_executable(${target} "test_${op}.cpp")
    target_link_libraries(${target}
        PRIVATE
            windows_test_support
            cusignal_cpu
            cusignal_zx_gpu
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
