add_library(filtering_test_support STATIC
    filtering_test_support.cu
)
target_link_libraries(filtering_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(filtering_test_support PUBLIC cxx_std_17)
target_compile_definitions(filtering_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(filtering_test_support)

function(add_filtering_test target)
    string(REPLACE "filtering_test_" "" op "${target}")
    cusignal_add_operator_test(
        ${target}
        "${CMAKE_CURRENT_SOURCE_DIR}/test_${op}.cpp"
        filtering_test_support
    )
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
