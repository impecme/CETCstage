add_library(correlate_test_support STATIC
    correlate_test_support.cu
)
target_link_libraries(correlate_test_support
    PRIVATE
        cusignal_cpu
        cusignal_cuda
)
target_compile_features(correlate_test_support PUBLIC cxx_std_17)
target_compile_definitions(correlate_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
set_target_properties(correlate_test_support PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    POSITION_INDEPENDENT_CODE ON
)

function(add_correlate_test target)
    string(REPLACE "correlate_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            correlate_test_support
            cusignal_cpu
            cusignal_cuda
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    correlate
    correlate2d
    correlation_lags
)
    add_correlate_test(correlate_test_${op})
endforeach()
