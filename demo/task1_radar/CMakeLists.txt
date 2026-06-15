add_executable(
    task1_radar_demo
    task1_radar_demo.cpp
)
if(NOT CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    target_sources(task1_radar_demo PRIVATE task1_radar_cuda.cu)
endif()

target_link_libraries(task1_radar_demo PRIVATE cusignal_cuda CUDA::cudart)
target_compile_features(task1_radar_demo PRIVATE cxx_std_17)
target_include_directories(task1_radar_demo PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(task1_radar_demo PRIVATE CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
set_target_properties(task1_radar_demo PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    set_target_properties(task1_radar_demo PROPERTIES LINKER_LANGUAGE CUDA)
endif()
