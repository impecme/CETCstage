add_executable(
    task2_features_demo
    task2_features_demo.cpp
)
if(NOT CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    target_sources(task2_features_demo PRIVATE task2_features_cuda.cu)
endif()

target_link_libraries(task2_features_demo PRIVATE cusignal_cuda CUDA::cudart)
target_compile_features(task2_features_demo PRIVATE cxx_std_17)
target_include_directories(task2_features_demo PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_compile_definitions(task2_features_demo PRIVATE CUSIGNAL_SOURCE_DIR="${CMAKE_SOURCE_DIR}")
set_target_properties(task2_features_demo PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
if(CUSIGNAL_PLATFORM STREQUAL "ZHONGKEXIN")
    set_target_properties(task2_features_demo PROPERTIES LINKER_LANGUAGE CUDA)
endif()
