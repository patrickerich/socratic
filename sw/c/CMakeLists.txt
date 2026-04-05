cmake_minimum_required(VERSION 3.12)

if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
  set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/gcc_toolchain.cmake")
endif()

project(socratic_sw LANGUAGES C ASM)

if(CMAKE_BUILD_TYPE STREQUAL "")
  get_property(helpstring CACHE CMAKE_BUILD_TYPE PROPERTY HELPSTRING)
  set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "${helpstring}" FORCE)
endif()

option(UART_OUTPUT "Route output to the APB UART" ON)

if(UART_OUTPUT)
  add_compile_definitions(UART_OUTPUT=1)
endif()

add_subdirectory(common)
add_subdirectory(hello_world)
