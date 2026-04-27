cmake_minimum_required(VERSION 3.19)
project(mom6 LANGUAGES Fortran)

# GNU Compiler options
message("CMAKE_Fortran_COMPILER_ID = ${CMAKE_Fortran_COMPILER_ID}")
if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -g -fbacktrace")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fdefault-real-8 -fdefault-double-8")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Waliasing -fcray-pointer -fconvert=big-endian -ffree-line-length-none -fno-range-check -fbacktrace")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -O2")
  list(APPEND MOM6_SHARE_DEFS "CPRGNU")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "^(Intel)$")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -g -traceback")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -i4 -r8")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fno-alias -auto -safe-cray-ptr -ftz -assume byterecl -sox")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -O2 -debug minimal -fp-model source")
  list(APPEND MOM6_SHARE_DEFS "CPRINTEL")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "^(IntelLLVM)$")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -g -traceback")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -i4 -r8")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fno-alias -auto -safe-cray-ptr -ftz -assume byterecl")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -O2 -debug minimal -fp-model precise")
  list(APPEND MOM6_SHARE_DEFS "CPRINTEL")
else()
  message(WARNING "Fortran compiler with ID ${CMAKE_Fortran_COMPILER_ID} will be used with CMake default options")
endif()

include("mom6_files.cmake")
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)

option(CESMCOUPLED "Enable CESM specific code" OFF)
option(REGIONAL_MOM6 "Enable regioanl MOM6 specific code" OFF)

if(CESMCOUPLED)
  add_definitions(-DCESMCOUPLED)
endif()

# Find NetCDF
if(NOT NetCDF_FOUND)
  find_package(NetCDF REQUIRED C Fortran)
endif()

# Find ESMF
if(NOT ESMF_FOUND)
  find_package(ESMF 8.6.0 REQUIRED)
endif()

# Core model
add_library(mom6_obj OBJECT ${mom6_src_files})
set_target_properties(mom6_obj PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod)
target_include_directories(mom6_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>)
if(REGIONAL_MOM6)
target_include_directories(mom6_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/config_src/memory/dynamic_symmetric>)
else()
target_include_directories(mom6_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/config_src/memory/dynamic_nonsymmetric>)
endif()
target_include_directories(mom6_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/src/framework>)
target_include_directories(mom6_obj PRIVATE ${NetCDF_Fortran_INCLUDE_DIRS})
target_link_libraries(mom6_obj PUBLIC fms_r8 esmf stochastic_physics NetCDF::NetCDF_Fortran)

# NUOPC cap
add_library(mom6_nuopc_obj OBJECT ${mom6_nuopc_src_files})
set_target_properties(mom6_nuopc_obj PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod)
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>)
if(REGIONAL_MOM6)
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/config_src/memory/dynamic_symmetric>)
else()
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/config_src/memory/dynamic_nonsymmetric>)
endif()
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/MOM6/src/framework>)
target_include_directories(mom6_nuopc_obj PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/shared>)
target_compile_definitions(mom6_nuopc_obj PRIVATE ${MOM6_SHARE_DEFS})
target_include_directories(mom6_nuopc_obj PRIVATE ${ESMF_F90COMPILEPATHS})
target_link_libraries(mom6_nuopc_obj PUBLIC mom6_obj fms_r8 esmf stochastic_physics)

# Create dummy source to prevent No SOURCES given to target error
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/mom6_dummy.F90" "subroutine mom6_dummy()\nend subroutine mom6_dummy\n")
set(mom6_src_files "${CMAKE_CURRENT_BINARY_DIR}/mom6_dummy.F90")

# Define static library that has model and NUOPC cap
add_library(mom6 STATIC ${mom6_src_files})
target_link_libraries(mom6 PRIVATE mom6_obj mom6_nuopc_obj)
target_include_directories(mom6 PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>)

# Export/Install targets
install(
  TARGETS mom6 mom6_obj mom6_nuopc_obj
  EXPORT  mom6-config
  RUNTIME DESTINATION bin
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  COMPONENT Library
)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod/ DESTINATION include)

install(
  EXPORT mom6-config
  DESTINATION lib/cmake
)
