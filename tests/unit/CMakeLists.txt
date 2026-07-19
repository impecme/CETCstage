function(cusignal_add_operator_test target source support_target)
    add_executable(${target} "${source}")
    target_link_libraries(${target}
        PRIVATE
            ${support_target}
            cusignal_cpu
            cusignal_zx_gpu
    )
    target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_features(${target} PRIVATE cxx_std_17)
    add_test(NAME ${target} COMMAND ${target})
endfunction()

add_subdirectory(core_types)
add_subdirectory(waveforms)
add_subdirectory(windows)
add_subdirectory(filter_design)
add_subdirectory(filtering)
add_subdirectory(bsplines)
add_subdirectory(radartools)
add_subdirectory(spectral)
add_subdirectory(wavelets)
add_subdirectory(correlate)
add_subdirectory(demod)
add_subdirectory(estimation)
add_subdirectory(peak_finding)
