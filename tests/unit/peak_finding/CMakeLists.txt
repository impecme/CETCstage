add_library(peak_finding_test_support STATIC
    peak_finding_test_support.cu
)
target_link_libraries(peak_finding_test_support
    PRIVATE
        cusignal_cpu
        cusignal_cuda
)
target_compile_features(peak_finding_test_support PUBLIC cxx_std_17)
target_compile_definitions(peak_finding_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
set_target_properties(peak_finding_test_support PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    POSITION_INDEPENDENT_CODE ON
)

function(add_peak_finding_test target)
    string(REPLACE "peak_finding_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            peak_finding_test_support
            cusignal_cpu
            cusignal_cuda
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    argrelextrema
    argrelmin
    argrelmax
)
    add_peak_finding_test(peak_finding_test_${op})
endforeach()
