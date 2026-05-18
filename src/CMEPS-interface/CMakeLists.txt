cmake_minimum_required(VERSION 3.19)
project(cmeps LANGUAGES Fortran C)

###############################################################################
### CMEPS compiler flags
###############################################################################

if(CMAKE_Fortran_COMPILER_ID MATCHES "GNU")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -g -fbacktrace -ffree-line-length-none")
  list(APPEND CDEPS_SHARE_DEFS "CPRGNU")
  if(${CMAKE_Fortran_COMPILER_VERSION} VERSION_GREATER_EQUAL 10)
    set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -fallow-argument-mismatch -fallow-invalid-boz")
  endif()
  set(CMAKE_Fortran_FLAGS_RELEASE "-O2")
  set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -fcheck=bounds -ffpe-trap=invalid,zero,overflow,underflow" )
  set(CMAKE_Fortran_LINK_FLAGS "")
elseif(CMAKE_Fortran_COMPILER_ID MATCHES "Intel")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -g -traceback")
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -assume realloc_lhs")
  set(CMAKE_Fortran_FLAGS_RELEASE "-O2 -fp-model precise")
  set(CMAKE_Fortran_FLAGS_DEBUG "-O0 -check all -check noarg_temp_created -check nopointer -fpe0 -ftrapuv -init=snan,arrays")
  set(CMAKE_Fortran_LINK_FLAGS "")
  list(APPEND CDEPS_SHARE_DEFS "CPRINTEL")
else()
  message(WARNING "Fortran compiler with ID ${CMAKE_Fortran_COMPILER_ID} will be used with CMake default options")
endif()

###############################################################################
### Options
###############################################################################

option(CDEPS_INLINE "Enable CDEPS Inline capability" OFF)
option(CESMCOUPLED "Enable CESM specific code" OFF)
option(PIO_INIT "Initialize PIO inside of CMEPS" ON)

message("PROJECT_SOURCE_DIR = ${PROJECT_SOURCE_DIR}")
list(APPEND CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/../CDEPS/cmake)

###############################################################################
### Source files
###############################################################################

list(APPEND _shared_files
  ${PROJECT_SOURCE_DIR}/shared/perf_mod.F90
  ${PROJECT_SOURCE_DIR}/shared/shr_pio_mod.F90
  ${PROJECT_SOURCE_DIR}/shared/shr_wv_sat_mod.F90
  CMEPS/ufs/wtracers_mod.F90)

list(APPEND _mediator_files
  CMEPS/mediator/med_field_info_mod.F90
  CMEPS/mediator/med_phases_restart_mod.F90
  CMEPS/mediator/med_map_mod.F90
  CMEPS/mediator/med_methods_mod.F90
  CMEPS/mediator/med_phases_prep_ice_mod.F90
  CMEPS/mediator/med_phases_history_mod.F90
  CMEPS/mediator/med_phases_prep_glc_mod.F90
  CMEPS/mediator/med_internalstate_mod.F90
  CMEPS/mediator/med_phases_profile_mod.F90
  CMEPS/mediator/esmFldsExchange_hafs_mod.F90
  CMEPS/mediator/med_phases_prep_rof_mod.F90
  CMEPS/mediator/esmFldsExchange_cesm_mod.F90
  CMEPS/mediator/med_merge_mod.F90
  CMEPS/mediator/med_constants_mod.F90
  CMEPS/mediator/med_kind_mod.F90
  CMEPS/mediator/esmFldsExchange_ufs_mod.F90
  CMEPS/mediator/med_phases_prep_lnd_mod.F90
  CMEPS/mediator/med_phases_prep_atm_mod.F90
  CMEPS/mediator/med_phases_prep_ocn_mod.F90
  CMEPS/mediator/esmFlds.F90
  CMEPS/mediator/med.F90
  CMEPS/mediator/med_phases_ocnalb_mod.F90
  CMEPS/mediator/med_phases_prep_wav_mod.F90
  CMEPS/mediator/med_utils_mod.F90
  CMEPS/mediator/med_fraction_mod.F90
  CMEPS/mediator/med_phases_aofluxes_mod.F90
  CMEPS/mediator/med_io_mod.F90
  CMEPS/mediator/med_diag_mod.F90
  CMEPS/mediator/med_phases_post_atm_mod.F90
  CMEPS/mediator/med_phases_post_ice_mod.F90
  CMEPS/mediator/med_phases_post_ocn_mod.F90
  CMEPS/mediator/med_phases_post_lnd_mod.F90
  CMEPS/mediator/med_phases_post_glc_mod.F90
  CMEPS/mediator/med_phases_post_rof_mod.F90
  CMEPS/mediator/med_phases_post_wav_mod.F90)

list(APPEND _aoflux_files
  CMEPS/cesm/flux_atmocn/flux_atmocn_COARE_mod.F90
  CMEPS/cesm/flux_atmocn/flux_atmocn_Diurnal_mod.F90
  CMEPS/cesm/flux_atmocn/flux_atmocn_driver_mod.F90
  CMEPS/cesm/flux_atmocn/flux_atmocn_Large.F90
  CMEPS/cesm/flux_atmocn/flux_atmocn_UA_mod.F90
  CMEPS/cesm/flux_atmocn/shr_flux_mod.F90)

if(CDEPS_INLINE)
  list(APPEND _mediator_files CMEPS/mediator/med_phases_cdeps_mod.F90)
  add_definitions(-DCDEPS_INLINE)
endif()

if(CESMCOUPLED)
  add_definitions(-DCESMCOUPLED)
endif()

if(PIO_INIT)
  add_definitions(-DPIO_INIT)
endif()

###############################################################################
### Libraries
###############################################################################

# Find ESMF
if(NOT ESMF_FOUND)
  find_package(ESMF 8.6.0 REQUIRED)
endif()

# Find PIO
if (DEFINED ENV{PIO_ROOT})
  message("PIO_ROOT is $ENV{PIO_ROOT}")
else()
  if (DEFINED PIO)
    set(PIO_PATH ${PIO})
  else()
    set(PIO_PATH $ENV{PIO})
  endif()
  find_package(PIO REQUIRED COMPONENT C Fortran PATH ${PIO_PATH})
endif()

### Create target library
add_library(cmeps STATIC ${_shared_files} ${_mediator_files} ${_aoflux_files})

### Set PUBLIC interfaces on the library
set_target_properties(cmeps PROPERTIES Fortran_MODULE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod)
target_include_directories(cmeps PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/mod>
                                        $<INSTALL_INTERFACE:mod>)
target_compile_definitions(cmeps PRIVATE ${CDEPS_SHARE_DEFS})
target_link_libraries(cmeps PUBLIC esmf)

###############################################################################
### Install
###############################################################################

install(
  TARGETS cmeps
  EXPORT  cmeps-config
  LIBRARY DESTINATION lib
  ARCHIVE DESTINATION lib
  COMPONENT Library)

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/mod/ DESTINATION include)

install(EXPORT      cmeps-config
        DESTINATION lib/cmake)
