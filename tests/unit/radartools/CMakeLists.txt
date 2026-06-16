add_library(radartools_test_support STATIC
    radartools_test_support.cu
)
target_link_libraries(radartools_test_support
    PRIVATE
        cusignal_cpu
        cusignal_cuda
)
target_compile_features(radartools_test_support PUBLIC cxx_std_17)
target_compile_definitions(radartools_test_support
    PRIVATE
        CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}"
)
cusignal_configure_cuda_source_target(radartools_test_support)

function(add_radartools_test target)
    string(REPLACE "radartools_test_" "" op "${target}")
    add_executable(${target} test_${op}.cpp)
    target_link_libraries(${target}
        PRIVATE
            radartools_test_support
            cusignal_cpu
            cusignal_cuda
    )
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

foreach(op
    pulse_compression
    pulse_doppler
    ambgfun
    cfar_alpha
    ca_cfar
    mvdr
)
    add_radartools_test(radartools_test_${op})
endforeach()
