add_library(common OBJECT uart.c printf.c printf_io.c sim_ctrl.c crt0.S)
target_include_directories(common INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_definitions(common PRIVATE PRINTF_DISABLE_SUPPORT_LONG_LONG)
