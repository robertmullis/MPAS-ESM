#!/bin/bash

# SCOTCH is optional and detected automatically:
# the SCOTCH flag (-DMPAS_SCOTCH) is turned ON when the SCOTCH environment
# variable points to a SCOTCH build, and OFF when it is unset/empty.
SCOTCH="/glade/campaign/cesm/mpas_mom6/v0/libraries/scotch"
if [ -n "${SCOTCH}" ]; then
  export SCOTCH
  USE_SCOTCH=true
else
  USE_SCOTCH=false
fi

# usage instructions
usage () {
cat << EOF_USAGE
Usage: $0 --platform=PLATFORM [OPTIONS] ... [TARGETS]

OPTIONS
  --build-jobs=BUILD_JOBS
      number of build jobs; defaults to 4
  -b, --build_dir=BUILD_DIR
      build directory
  --component-list=COMPONENT_LIST
      list of component/s to couple with MPAS seperated with comma
      (e.g. mom6 | docn | cmeps)
  -c, --compiler=COMPILER
      compiler to use; default depends on platform
      (e.g. intel | gnu)
  -d, --debug
      enable debug mode
  -i, --install_dir=INSTALL_DIR
      installation directory
  -p, --platform=PLATFORM
      name of machine you are building on
      (e.g. derecho)
  --regional
      build with regional coupling support - MOM6
  --remove
      removes existing build
  -v, --verbose
      build with verbose output

NOTE: See User's Guide for detailed build instructions

EOF_USAGE
}

# print usage error and exit
usage_error () {
  printf "ERROR: $1\n" >&2
  usage >&2
  exit 1
}

# print settings
settings () {
cat << EOF_SETTINGS
Settings:

  BUILD_JOBS = ${BUILD_JOBS}
  BUILD_DIR = ${BUILD_DIR}
  COMPILER = ${COMPILER}
  COMPONENT_LIST = ${COMPONENT_LIST}
  DEBUG = ${DEBUG}
  INSTALL_DIR = ${INSTALL_DIR}
  PLATFORM = ${PLATFORM}
  REGIONAL = ${REGIONAL}
  REMOVE = ${REMOVE}
  VERBOSE = ${VERBOSE}
  USE_SCOTCH = ${USE_SCOTCH}

EOF_SETTINGS
}

# process required arguments
if [[ ("$1" == "--help") || ("$1" == "-h") ]]; then
  usage
  exit 0
fi

# default settings
APP_DIR=$(cd "$(dirname "$(readlink -f -n "${BASH_SOURCE[0]}" )" )" && pwd -P)
BUILD_DIR="${BUILD_DIR:-${APP_DIR}/build}"
BUILD_JOBS=4
COMPILER="gnu"
DEBUG=false
INSTALL_DIR=${INSTALL_DIR:-${APP_DIR}/install}
PLATFORM="derecho"
REGIONAL=false
REMOVE=false
VERBOSE=true

# check arguments and set their values
while :; do
  case $1 in
    --build-jobs=?*) BUILD_JOBS=$((${1#*=})) ;;
    --build-jobs|--build-jobs=) usage_error "$1 requires argument." ;;
    --build-dir=?*|-b=?*) BUILD_DIR=${1#*=} ;;
    --build-dir|--build-dir=|-b|-b=) usage_error "$1 argument ignored." ;;
    --compiler=?*|-c=?*) COMPILER=${1#*=} ;;
    --compiler|--compiler=|-c|-c=) usage_error "$1 requires argument." ;;
    --component-list=?*) COMPONENT_LIST=${1#*=} ;;
    --component-list=) usage_error "$1 argument ignored." ;;
    --debug|-d) DEBUG=true ;;
    --debug=?*|--debug=) usage_error "$1 argument ignored." ;;
    --install-dir=?*|-i=?*) INSTALL_DIR=${1#*=} ;;
    --install-dir|--install-dir=|-i|-i=) usage_error "$1 argument ignored." ;;
    --platform=?*|-p=?*) PLATFORM=${1#*=} ;;
    --platform|--platform=|-p|-p=) usage_error "$1 requires argument." ;;
    --regional) REGIONAL=true ;;
    --regional=?*|--regional=) usage_error "$1 argument ignored." ;;
    --remove) REMOVE=true ;;
    --remove=?*|--remove=) usage_error "$1 argument ignored." ;;
    --verbose|-v) VERBOSE=true ;;
    --verbose=?*|--verbose=) usage_error "$1 argument ignored." ;;
    # unknown
    -?*|?*) usage_error "Unknown option $1" ;;
    *) break
  esac
  shift
done

# ensure uppercase/lowercase
COMPILER=$(echo ${COMPILER} | tr '[A-Z]' '[a-z]')
COMPONENT_LIST=$(echo ${COMPONENT_LIST} | tr '[A-Z]' '[a-z]')
PLATFORM=$(echo ${PLATFORM} | tr '[A-Z]' '[a-z]')

# check requested components and create dictionary
declare -A dict_comps
dict_comps["mom6"]="false"
dict_comps["docn"]="false"
dict_comps["cmeps"]="false"
OLD_IFS="$IFS"
IFS=','
for key in $COMPONENT_LIST; do
  read -r key <<< "$key"
  if [[ -v dict_comps["$key"] ]]; then
    dict_comps["$key"]="true"
  else
    printf "\nERROR: Given component ($key) is not supported!\n\n"
    usage
    exit 0
  fi
done
IFS="$OLD_IFS"

# add CDEPS if MOM6 is requested
# MOM6 requires CDEPS shared code
if [[ "${dict_comps["mom6"]}" == "true" ]]; then
  COMPONENT_LIST="${COMPONENT_LIST},docn"
  dict_comps["docn"]="true"
fi

set -eu

# print settings
if [ "${VERBOSE}" = true ] ; then
  settings
fi

# Load environment
if [ -f "envs/${PLATFORM}_env_${COMPILER}.sh" ]; then
  source envs/${PLATFORM}_env_${COMPILER}.sh
else
  printf "\nERROR: ${PLATFORM} with ${COMPILER} compiler is not supported!\n\n"
  usage
  exit 0
fi

# Check build and installation directories. They need to be absolute path
if [[ ! "$BUILD_DIR" =~ ^/ ]]; then
  printf "\nERROR: Build directory $BUILD_DIR is not absolute path! Exiting...\n"
  exit 0
fi
if [[ ! "$INSTALL_DIR" =~ ^/ ]]; then
  printf "\nERROR: Install directory $INSTALL_DIR is not absolute path! Exiting...\n"
  exit 0
fi

# Clean build
if [ "${REMOVE}" = true ]; then
  # Clean build and install directories
  if [ -d "${BUILD_DIR}" ]; then
    printf "Build directory already exists! Removing ${BUILD_DIR} ...\n"
    rm -rf ${BUILD_DIR}
  fi
  if [ -d "${INSTALL_DIR}" ]; then
    printf "Install directory already exists! Removing ${INSTALL_DIR} ...\n"
    rm -rf ${INSTALL_DIR}
  fi
else
  if [ -d "${BUILD_DIR}" ]; then
    # Remove cache to prevent hanging
    find ${BUILD_DIR}/. -name "CMakeCache.txt" -type f -delete
  fi
fi

# Remove exiting esmxBuild.yaml
if [ -f "esmxBuild.yaml" ]; then
  rm -rf esmxBuild.yaml
fi

# Compiler specific flags
if [ "${COMPILER}" == "gnu" ]; then
  export FFLAGS="-DCPRGNU"
else
  export FFLAGS=""
fi

# Check ESMF version
esmf_ver=`cat $ESMFMKFILE | grep "ESMF_VERSION_STRING=" | awk -F= '{print $2}'`
IFS='.' read -r -a arr <<< "$esmf_ver"
echo "ESMF Major  : ${arr[0]}"
echo "ESMF Minor  : ${arr[1]}"
echo "ESMF Patch  : ${arr[2]}"
build_type="cmake"
if [[ ${arr[0]} -ge 8 && ${arr[1]} -ge 9 ]]; then
   build_type="cmake.external"
fi
if [[ ${arr[0]} -ge 9 ]]; then
   build_type="cmake.external"
fi

# SCOTCH build/link fragments, populated based on whether SCOTCH was detected
if [ "${USE_SCOTCH}" = true ]; then
  SCOTCH_ARGS="-DMPAS_SCOTCH=ON -DSCOTCH_ROOT=${SCOTCH} -DSCOTCH_INCLUDE_DIR=${SCOTCH}/src/include -DSCOTCH_LIBRARY=${SCOTCH}/lib/libptscotch.a -DSCOTCHERR_LIBRARY=${SCOTCH}/lib/libptscotcherr.a"
  SCOTCH_LINK_PATH=" ${SCOTCH}/lib"
  SCOTCH_LINK_LIBS=" ptscotch ptscotcherr scotch scotcherr"
  SCOTCH_LINK_LIBS_MOM=" ptscotch ptscotcherr"
else
  SCOTCH_ARGS="-DMPAS_SCOTCH=OFF"
  SCOTCH_LINK_PATH=""
  SCOTCH_LINK_LIBS=""
  SCOTCH_LINK_LIBS_MOM=""
fi

# Create esmxBuild.yaml
echo "application:" >> esmxBuild.yaml
echo "  disable_comps: ESMX_Data" >> esmxBuild.yaml
echo "  link_libraries: piof" >> esmxBuild.yaml
if [ "${REGIONAL}" = true ] ; then
echo "  exe_name: esmx_app_regional" >> esmxBuild.yaml
fi
if [ "${DEBUG}" = true ]; then
echo "  cmake_build_args: -DCMAKE_Fortran_FLAGS=-g -DCMAKE_BUILD_TYPE=Debug" >> esmxBuild.yaml
fi
echo "components:" >> esmxBuild.yaml
# MPAS
echo "  mpas_atm_nuopc:" >> esmxBuild.yaml
echo "    source_dir: src/MPAS-Model" >> esmxBuild.yaml
echo "    build_type: $build_type" >> esmxBuild.yaml
if [ "${DEBUG}" = true ]; then
echo "    build_args: \"-DBUILD_SHARED_LIBS=OFF -DMPAS_NUOPC=ON -DMPAS_DOUBLE_PRECISION=OFF -DMPAS_USE_PIO=ON -DDEBUG=ON ${SCOTCH_ARGS}\"" >> esmxBuild.yaml
else
echo "    build_args: \"-DBUILD_SHARED_LIBS=OFF -DMPAS_NUOPC=ON -DMPAS_DOUBLE_PRECISION=OFF -DMPAS_USE_PIO=ON ${SCOTCH_ARGS}\"" >> esmxBuild.yaml
fi
echo "    link_paths: ${ESMF_ROOT}/lib${SCOTCH_LINK_PATH}" >> esmxBuild.yaml
echo "    link_libraries: esmf${SCOTCH_LINK_LIBS}" >> esmxBuild.yaml
# DOCN
if [[ "${dict_comps["docn"]}" == "true" ]]; then
  echo "  docn:" >> esmxBuild.yaml
  echo "    source_dir: src/CDEPS" >> esmxBuild.yaml
  echo "    build_type: $build_type" >> esmxBuild.yaml
  if [[ "${COMPILER}" == "gnu" ]]; then
    echo "    build_args: \"-DDISABLE_FoX=ON -DPIO_C_LIBRARY=$PIO_C_LIBRARY -DPIO_C_INCLUDE_DIR=$PIO_C_INCLUDE_DIR -DPIO_Fortran_LIBRARY=$PIO_Fortran_LIBRARY -DPIO_Fortran_INCLUDE_DIR=$PIO_Fortran_INCLUDE_DIR -DCMAKE_Fortran_FLAGS='-ffree-line-length-none'\"" >> esmxBuild.yaml
  else
    echo "    build_args: \"-DDISABLE_FoX=ON -DPIO_C_LIBRARY=$PIO_C_LIBRARY -DPIO_C_INCLUDE_DIR=$PIO_C_INCLUDE_DIR -DPIO_Fortran_LIBRARY=$PIO_Fortran_LIBRARY -DPIO_Fortran_INCLUDE_DIR=$PIO_Fortran_INCLUDE_DIR\"" >> esmxBuild.yaml
  fi
  echo "    fort_module: cdeps_docn_comp.mod" >> esmxBuild.yaml
  echo "    libraries: docn dshr streams cdeps_share" >> esmxBuild.yaml
fi
# MOM6
if [[ "${dict_comps["mom6"]}" == "true" ]]; then
  echo "  mom6:" >> esmxBuild.yaml
  echo "    source_dir: src/MOM6_interface" >> esmxBuild.yaml
  echo "    build_type: $build_type" >> esmxBuild.yaml
  if [ "${REGIONAL}" = true ] ; then
    echo "    build_args: \"-DCESMCOUPLED=ON -DREGIONAL_MOM6=ON -DCMAKE_Fortran_FLAGS=-I${FMS_ROOT}/include_r8 ${SCOTCH_ARGS}\"" >> esmxBuild.yaml
  else
    echo "    build_args: \"-DCMAKE_Fortran_FLAGS=-I${FMS_ROOT}/include_r8\"" >> esmxBuild.yaml
  fi
  echo "    fort_module: mom_cap_mod.mod" >> esmxBuild.yaml
  echo "    libraries: mom6" >> esmxBuild.yaml
  echo "    link_paths: $FMS_ROOT${SCOTCH_LINK_PATH}" >> esmxBuild.yaml
  echo "    link_libraries: fms_r8 cdeps_share${SCOTCH_LINK_LIBS_MOM}" >> esmxBuild.yaml
fi
# CMEPS
if [[ "${dict_comps["cmeps"]}" == "true" ]]; then
  echo "  cmeps:" >> esmxBuild.yaml
  echo "    source_dir: src/CMEPS-interface" >> esmxBuild.yaml
  echo "    build_type: $build_type" >> esmxBuild.yaml
  if [ "${REGIONAL}" = true ] ; then
    echo "    build_args: \"-DCESMCOUPLED=ON -DCDEPS_INLINE=ON -DPIO_C_LIBRARY=$PIO_C_LIBRARY -DPIO_C_INCLUDE_DIR=$PIO_C_INCLUDE_DIR -DPIO_Fortran_LIBRARY=$PIO_Fortran_LIBRARY -DPIO_Fortran_INCLUDE_DIR=$PIO_Fortran_INCLUDE_DIR -DCMAKE_Fortran_FLAGS=-I${INSTALL_DIR}/include ${SCOTCH_ARGS}\"" >> esmxBuild.yaml
  else
    echo "    build_args: \"-DCESMCOUPLED=ON -DPIO_C_LIBRARY=$PIO_C_LIBRARY -DPIO_C_INCLUDE_DIR=$PIO_C_INCLUDE_DIR -DPIO_Fortran_LIBRARY=$PIO_Fortran_LIBRARY -DPIO_Fortran_INCLUDE_DIR=$PIO_Fortran_INCLUDE_DIR -DCMAKE_Fortran_FLAGS=-I${INSTALL_DIR}/include\"" >> esmxBuild.yaml
  fi
  echo "    fort_module: med.mod" >> esmxBuild.yaml
  echo "    libraries: cmeps dshr streams cdeps_share" >> esmxBuild.yaml
  echo "    link_paths: ${ESMF_ROOT}/lib${SCOTCH_LINK_PATH}" >> esmxBuild.yaml
  echo "    link_libraries: esmf${SCOTCH_LINK_LIBS}" >> esmxBuild.yaml
fi

# Build application
ESMX_Builder -v --prefix=$INSTALL_DIR --build-jobs=${BUILD_JOBS} --cmake-args="-DCMAKE_Fortran_FLAGS=-I${INSTALL_DIR}/include"
