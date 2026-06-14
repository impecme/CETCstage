add_library(filter_design_test_support STATIC
    filter_design_test_support.cu
)
target_link_libraries(filter_design_test_support
    PRIVATE
        cusignal_cpu
        cusignal_cuda
)
target_compile_features(filter_design_test_support PUBLIC cxx_std_17)
target_compile_definitions(filter_design_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
set_target_properties(filter_design_test_support PROPERTIES
    CUDA_SEPARABLE_COMPILATION ON
    POSITION_INDEPENDENT_CODE ON
)

function(add_filter_design_test target)
    string(REPLACE "filter_design_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            filter_design_test_support
            cusignal_cpu
            cusignal_cuda
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    kaiser_beta
    kaiser_atten
    cmplx_sort
    firwin
    firwin2
)
    add_filter_design_test(filter_design_test_${op})
endforeach()
