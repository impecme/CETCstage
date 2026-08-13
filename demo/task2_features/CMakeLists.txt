add_executable(
    task2_features_demo
    task2_features_demo.cpp
    task2_common.cpp
    task2_cpu.cpp
)

target_link_libraries(task2_features_demo PRIVATE cusignal_zx_gpu ${CUSIGNAL_ZX_GPU_RUNTIME_TARGET})
target_compile_features(task2_features_demo PRIVATE cxx_std_17)
target_include_directories(task2_features_demo PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(task2_features_demo PRIVATE CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
