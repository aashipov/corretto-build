#!/bin/bash

set -ex

environment() {
  _SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$0")")
  cd ${_SCRIPT_DIR}

  JAVA_VERSION="8"
  JDK="jdk"
  JRE="jre"
  JTREG="jtreg"
  JDK_FLAVOR="${JDK}${JAVA_VERSION}u"
  JRE_FLAVOR="${JRE}${JAVA_VERSION}u"
  INSTRUCTION_SET="x86_64"
  CORRETTO=corretto
  DOT_TAR_DOT_GZ=".tar.gz"

  TAG_TO_BUILD=$(cat ${_SCRIPT_DIR}/.tag_to_build_${JAVA_VERSION})
  if [[ "${TAG_TO_BUILD}" == "" ]]; then
    printf "Can not find ${_SCRIPT_DIR}/.tag_to_build_${JAVA_VERSION} file or it is empty\n"
    exit 1
  fi

  local OS_TYPE="linux"
  TOP_DIR=${HOME}
  # https://raw.githubusercontent.com/archlinux/svntogit-packages/packages/java8-openjdk/trunk/PKGBUILD
  # Avoid optimization of HotSpot being lowered from O3 to O2
  _CFLAGS="-O3 -pipe"
  if [[ "${OSTYPE}" == "cygwin" || "${OSTYPE}" == "msys" ]]; then
    if [[ "${OSTYPE}" == "cygwin" ]]; then
      TOP_DIR="/cygdrive/c"
    elif [[ "${OSTYPE}" == "msys" ]]; then
      TOP_DIR="/c"
    fi
    OS_TYPE="windows"
    export JAVA_HOME=${TOP_DIR}/dev/tools/openjdk${JAVA_VERSION}
    _CFLAGS="/O2"
    local FREETYPE=freetype
    local FREETYPE_AND_VERSION=${FREETYPE}-2.5.3
    FREETYPE_SRC_DIR=${TOP_DIR}/dev/VCS/${FREETYPE_AND_VERSION}
    if [ ! -d "${FREETYPE_SRC_DIR}" ]; then
      FREETYPE_TAR_GZ=${FREETYPE_AND_VERSION}.tar.gz
      FREETYPE_TAR_GZ_IN_TMP=/tmp/${FREETYPE_TAR_GZ}
      rm -rf ${FREETYPE_SRC_DIR}
      mkdir -p ${FREETYPE_SRC_DIR}
      curl -L https://download-mirror.savannah.gnu.org/releases/${FREETYPE}/${FREETYPE}-old/${FREETYPE_TAR_GZ} -o ${FREETYPE_TAR_GZ_IN_TMP}
      tar -xzf ${FREETYPE_TAR_GZ_IN_TMP} -C ${FREETYPE_SRC_DIR} --strip-components=1
      rm -rf ${FREETYPE_TAR_GZ_IN_TMP}
    fi
  fi
  JDK_DIR="${TOP_DIR}/${CORRETTO}-${JAVA_VERSION}"
  JTREG_DIR="${TOP_DIR}/${JTREG}"
  OS_TYPE_AND_INSTRUCTION_SET="${OS_TYPE}-${INSTRUCTION_SET}"

  ALPINE=""
  if [ -f /etc/alpine-release ]; then
    ALPINE="-alpine"
  elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]; then
    source /opt/rh/devtoolset-10/enable
  #  source /opt/rh/llvm-toolset-7/enable
  fi
}

checkout() {
  DEFAULT_BRANCH=develop
  if [ ! -d "${JDK_DIR}/.git" ]; then
    cd ${TOP_DIR}
    git clone https://github.com/${CORRETTO}/${CORRETTO}-${JAVA_VERSION}.git
    cd ${JDK_DIR}
  else
    cd ${JDK_DIR}
    git checkout ${DEFAULT_BRANCH}
    git pull
  fi

  if [ $(git tag -l "${TAG_TO_BUILD}") ]; then
    git checkout tags/${TAG_TO_BUILD}
  else
    printf "Can not find tag ${TAG_TO_BUILD}\n"
    exit 1
  fi
}

build() {
  MINOR_VER=$(printf ${TAG_TO_BUILD} | cut -d '.' -f 2)
  UPDATE_VER=$(printf ${TAG_TO_BUILD} | cut -d '.' -f 3)
  CORRETTO_REVISION=$(printf ${TAG_TO_BUILD} | cut -d '.' -f 4)

  CONFIGURE_DETAILS="--verbose --with-debug-level=release --with-native-debug-symbols=none --with-jvm-variants=server --with-milestone=\"fcs\" --enable-unlimited-crypto --with-extra-cflags=\"${_CFLAGS}\" --with-extra-cxxflags=\"${_CFLAGS}\" --with-extra-ldflags=\"${_CFLAGS}\" --enable-jfr=yes --with-update-version=\"${MINOR_VER}\" --with-build-number=\"${UPDATE_VER}\" --with-corretto-revision=\"${CORRETTO_REVISION}\""
  if [[ "${OSTYPE}" == "cygwin" || "${OSTYPE}" == "msys" ]]; then
    CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-freetype-src=${FREETYPE_SRC_DIR} --with-toolchain-version=2017"
  else
    CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --disable-freetype-bundling"
    #CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-toolchain-type=clang"
  fi
  bash -c "bash configure ${CONFIGURE_DETAILS}"

  make clean
  make all
}

publish() {
  if [[ $? -eq 0 ]]; then
    local RELEASE_IMAGE_DIR=${JDK_DIR}/build/${OS_TYPE_AND_INSTRUCTION_SET}-normal-server-release/images/
    cd ${RELEASE_IMAGE_DIR}
    local JDK_FILE_NAME=${JDK_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TAG_TO_BUILD}${ALPINE}${DOT_TAR_DOT_GZ}
    local JRE_FILE_NAME=${JRE_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TAG_TO_BUILD}${ALPINE}${DOT_TAR_DOT_GZ}
    find "${PWD}" -type f -name '*.debuginfo' -exec rm {} \;
    find "${PWD}" -type f -name '*.diz' -exec rm {} \;
    GZIP=-9 tar -czhf ${JDK_FILE_NAME} j2sdk-image/
    GZIP=-9 tar -czhf ${JRE_FILE_NAME} j2re-image/

    local GITHUB_TOKEN=$(cat ${HOME}/.github_token)
    if [[ "${GITHUB_TOKEN}" != "" ]]; then
      local GITHUB_OWNER=aashipov
      local GITHUB_REPO=corretto-build
      local GITHUB_RELEASE_ID=80394672

      local FILES_TO_UPLOAD=(${JDK_FILE_NAME} ${JRE_FILE_NAME})
      for file_to_upload in "${FILES_TO_UPLOAD[@]}"; do
        #https://stackoverflow.com/a/7506695
        local FILE_NAME_URL_ENCODED=$(printf "${file_to_upload}" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g')
        curl \
          https://uploads.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/${GITHUB_RELEASE_ID}/assets?name=${FILE_NAME_URL_ENCODED} \
          -H "Authorization: Bearer ${GITHUB_TOKEN}" \
          -H "Content-type: application/gzip" \
          --data-binary @${RELEASE_IMAGE_DIR}/${file_to_upload}
      done
    fi
  fi
}

closure() {
  environment
  checkout
  build
  publish
}

# Main procedure
closure
