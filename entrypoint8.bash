#!/bin/bash

set -ex

JAVA_VERSION="8"
JDK="jdk"
JRE="jre"
JTREG="jtreg"
JDK_FLAVOR="corretto-${JAVA_VERSION}"
JRE_FLAVOR="corretto-${JAVA_VERSION}-${JRE}"
INSTRUCTION_SET="x86_64"
GIT_CLONE_URL=https://github.com/corretto/${JDK_FLAVOR}.git

OS_TYPE="linux"
TOP_DIR=${HOME}
# https://raw.githubusercontent.com/archlinux/svntogit-packages/packages/java8-openjdk/trunk/PKGBUILD
# Avoid optimization of HotSpot being lowered from O3 to O2
_CFLAGS="-O3 -pipe"
if [[ "${OSTYPE}" == "cygwin" || "${OSTYPE}" == "msys" ]]; then
  OS_TYPE="windows"
  TOP_DIR="/cygdrive/c"
  export JAVA_HOME=${TOP_DIR}/dev/tools/openjdk${JAVA_VERSION}
  _CFLAGS="/O2"
  FREETYPE=freetype
  FREETYPE_AND_VERSION=${FREETYPE}-2.5.3
  FREETYPE_SRC_DIR=${TOP_DIR}/dev/VCS/${FREETYPE_AND_VERSION}
  FREETYPE_TAR_GZ=${FREETYPE_AND_VERSION}.tar.gz
  FREETYPE_TAR_GZ_IN_TMP=/tmp/${FREETYPE_TAR_GZ}
  rm -rf ${FREETYPE_SRC_DIR}
  mkdir -p ${FREETYPE_SRC_DIR}
  curl -L https://download-mirror.savannah.gnu.org/releases/${FREETYPE}/${FREETYPE}-old/${FREETYPE_TAR_GZ} -o ${FREETYPE_TAR_GZ_IN_TMP}
  tar -xzf ${FREETYPE_TAR_GZ_IN_TMP} -C ${FREETYPE_SRC_DIR} --strip-components=1
  rm -rf ${FREETYPE_TAR_GZ_IN_TMP}
fi
JDK_DIR="${TOP_DIR}/${JDK_FLAVOR}"
JTREG_DIR="${TOP_DIR}/${JTREG}"
OS_TYPE_AND_INSTRUCTION_SET="${OS_TYPE}-${INSTRUCTION_SET}"

ALPINE=""
if [ -f /etc/alpine-release ]; then
  ALPINE="-alpine"
fi

if [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
  source /opt/rh/devtoolset-7/enable
#  source /opt/rh/llvm-toolset-7/enable
fi

DEFAULT_BRANCH=develop
if [ ! -d "${JDK_DIR}/.git" ]; then
  cd ${TOP_DIR}
  git clone ${GIT_CLONE_URL}
  cd ${JDK_DIR}
else
  cd ${JDK_DIR}
  git checkout ${DEFAULT_BRANCH}
  git pull
fi

# https://gist.github.com/rponte/fdc0724dd984088606b0 or commit sha
TOP_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
TOP_TAG="release-8.352.08.1"
git checkout tags/${TOP_TAG}
git pull -r

MINOR_VER=$(printf ${TOP_TAG} | cut -d'-' -f 1)
MINOR_VER=${MINOR_VER#${JDK_FLAVOR}}

UPDATE_VER=$(printf ${TOP_TAG} | cut -d'-' -f 2)
UPDATE_VER=${UPDATE_VER#"b"}

CONFIGURE_DETAILS="--verbose --with-debug-level=release --with-native-debug-symbols=none --with-jvm-variants=server --with-milestone=\"fcs\" --enable-unlimited-crypto --with-extra-cflags=\"${_CFLAGS}\" --with-extra-cxxflags=\"${_CFLAGS}\" --with-extra-ldflags=\"${_CFLAGS}\" --enable-jfr=yes --with-update-version=\"${MINOR_VER}\" --with-build-number=\"${UPDATE_VER}\""
if [[ "${OSTYPE}" == "cygwin" || "${OSTYPE}" == "msys" ]]; then
  CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-freetype-src=${FREETYPE_SRC_DIR}"
else
  CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --disable-freetype-bundling"
  #CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-toolchain-type=clang"
fi
bash -c "bash configure ${CONFIGURE_DETAILS}"

make clean
make all

if [[ $? -eq 0 ]]; then
  cd ${JDK_DIR}/build/${OS_TYPE_AND_INSTRUCTION_SET}-normal-server-release/images/
  RELEASE_FILE=j2sdk-image/release
  touch ${RELEASE_FILE}
  printf "$(git rev-parse --verify HEAD)\n${TOP_TAG}\n" >> ${RELEASE_FILE}
  RELEASE_FILE=j2re-image/release
  touch ${RELEASE_FILE}
  printf "$(git rev-parse --verify HEAD)\n${TOP_TAG}\n" >> ${RELEASE_FILE}
  find "${PWD}" -type f -name '*.debuginfo' -exec rm {} \;
  find "${PWD}" -type f -name '*.diz' -exec rm {} \;
  GZIP=-9 tar -czhf ./${JDK_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TOP_TAG}${ALPINE}.tar.gz j2sdk-image/
  GZIP=-9 tar -czhf ./${JRE_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TOP_TAG}${ALPINE}.tar.gz j2re-image/
fi
