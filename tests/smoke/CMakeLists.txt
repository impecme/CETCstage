add_executable(smoke_demo1 demo1.cpp)
target_link_libraries(smoke_demo1 PRIVATE cusignal_cuda)
target_compile_features(smoke_demo1 PRIVATE cxx_std_17)

add_test(NAME smoke_demo1 COMMAND smoke_demo1)
