add_library(bsplines_test_support STATIC
    bsplines_test_support.cu
)
target_link_libraries(bsplines_test_support
    PRIVATE
        cusignal_cpu
        cusignal_zx_gpu
)
target_compile_features(bsplines_test_support PUBLIC cxx_std_17)
target_compile_definitions(bsplines_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_zx_gpu_source_target(bsplines_test_support)

function(add_bsplines_test target)
    string(REPLACE "bsplines_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            bsplines_test_support
            cusignal_cpu
            cusignal_zx_gpu
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    cubic
    quadratic
    gauss_spline
)
    add_bsplines_test(bsplines_test_${op})
endforeach()
