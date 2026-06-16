add_library(filtering_test_support STATIC
    filtering_test_support.cu
)
target_link_libraries(filtering_test_support
    PRIVATE
        cusignal_cpu
        cusignal_cuda
)
target_compile_features(filtering_test_support PUBLIC cxx_std_17)
target_compile_definitions(filtering_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_cuda_source_target(filtering_test_support)

function(add_filtering_test target)
    string(REPLACE "filtering_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            filtering_test_support
            cusignal_cpu
            cusignal_cuda
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    wiener
    firfilter
    lfilter
    firfilter_zi
    lfilter_zi
    firfilter2
    filtfilt
    sosfilt
    hilbert
    hilbert2
    detrend
    freq_shift
    channelize_poly
    decimate
    resample
    resample_poly
    upfirdn
)
    add_filtering_test(filtering_test_${op})
endforeach()
