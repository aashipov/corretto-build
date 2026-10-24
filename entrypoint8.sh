#!/bin/sh

# ------------------------------------------------------------
# Script/base dir
# ------------------------------------------------------------
get_base_dir() {
    if [ -f "${0}" ]
    then
        # $0 points to a file on disk
        printf '%s\n' "$(cd -- "$(dirname -- "${0}")" && pwd -P)"
    else
        # The script was sourced in a shell where $0 is not the script path
        # Fallback to the current working directory
        printf '%s\n' "$(pwd -P)"
    fi
}

environment() {
  BASE_DIR="$(get_base_dir)"
  cd ${BASE_DIR}

  JAVA_VERSION="8"
  JDK="jdk"
  JRE="jre"
  JTREG="jtreg"
  JDK_FLAVOR="${JDK}${JAVA_VERSION}u"
  JRE_FLAVOR="${JRE}${JAVA_VERSION}u"
  INSTRUCTION_SET="x86_64"
  CORRETTO=corretto
  DOT_TAR_DOT_GZ=".tar.gz"

  TAG_TO_BUILD="$(cat ${BASE_DIR}/.env | grep TAG_TO_BUILD_${JAVA_VERSION} | cut -d '=' -f 2)"
  if [ -z "${TAG_TO_BUILD}" ]
  then
    printf 'Can not find TAG_TO_BUILD_%s in .env\n' "${JAVA_VERSION}"
    exit 1
  fi

  OS_TYPE="linux"
  TOP_DIR=${HOME}
  # https://raw.githubusercontent.com/archlinux/svntogit-packages/packages/java8-openjdk/trunk/PKGBUILD
  # Avoid optimization of HotSpot being lowered from O3 to O2
  _CFLAGS="-O3 -pipe -Wno-error"
  if [ "${OSTYPE}" = "cygwin" ]
  then
      TOP_DIR="/cygdrive/c"
      OS_TYPE="windows"
      _CFLAGS="/O2"
  fi
  if [ -z "${JAVA_HOME+x}" ] || [ -z "${JAVA_HOME}" ]
  then
      export JAVA_HOME=${TOP_DIR}/dev/tools/openjdk${JAVA_VERSION}
  fi
  JDK_DIR="${TOP_DIR}/${CORRETTO}-${JAVA_VERSION}"
  JTREG_DIR="${TOP_DIR}/${JTREG}"
  OS_TYPE_AND_INSTRUCTION_SET="${OS_TYPE}-${INSTRUCTION_SET}"

  ALPINE=""
  if [ -f /etc/alpine-release ]
  then
    ALPINE="-alpine"
  elif [ -f /etc/centos-release ] || [ -f /etc/redhat-release ]
  then
    if [ ! -f /etc/fedora-release ]
    then
      source /opt/rh/devtoolset-10/enable
    #    source /opt/rh/llvm-toolset-7/enable
    fi
  fi
}

checkout() {
  DEFAULT_BRANCH=develop
  if [ ! -d "${JDK_DIR}/.git" ]; then
    cd ${TOP_DIR}
    git clone "https://github.com/${CORRETTO}/${CORRETTO}-${JAVA_VERSION}.git"
    cd "${JDK_DIR}"
  else
    cd "${JDK_DIR}"
    git checkout "${DEFAULT_BRANCH}"
    git pull
  fi

  if [ $(git tag -l "${TAG_TO_BUILD}") ]
  then
    git checkout tags/"${TAG_TO_BUILD}"
  else
    printf "Can not find tag ${TAG_TO_BUILD}\n"
    exit 1
  fi
}

build() {
  MINOR_VER="$(printf ${TAG_TO_BUILD} | cut -d '.' -f 2)"
  UPDATE_VER="$(printf ${TAG_TO_BUILD} | cut -d '.' -f 3)"
  CORRETTO_REVISION="$(printf ${TAG_TO_BUILD} | cut -d '.' -f 4)"

  CONFIGURE_DETAILS="--verbose --with-debug-level=release --with-native-debug-symbols=none --with-jvm-variants=server --with-milestone=\"fcs\" --enable-unlimited-crypto --with-extra-cflags=\"${_CFLAGS}\" --with-extra-cxxflags=\"${_CFLAGS}\" --with-extra-ldflags=\"${_CFLAGS}\" --enable-jfr=yes --with-update-version=\"${MINOR_VER}\" --with-build-number=\"${UPDATE_VER}\" --with-corretto-revision=\"${CORRETTO_REVISION}\""
  if [ "${OSTYPE}" == "cygwin" ]
  then
    CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-toolchain-version=2017"
  else
    echo
    #CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-toolchain-type=clang"
  fi
  sh -c "sh configure ${CONFIGURE_DETAILS}"

  make clean
  make all
}

publish() {
  if [ ${?} -eq 0 ]
  then
    RELEASE_IMAGE_DIR="${JDK_DIR}/build/${OS_TYPE_AND_INSTRUCTION_SET}-normal-server-release/images/"
    cd "${RELEASE_IMAGE_DIR}"
    JDK_FILE_NAME="${JDK_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TAG_TO_BUILD}${ALPINE}${DOT_TAR_DOT_GZ}"
    JRE_FILE_NAME="${JRE_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TAG_TO_BUILD}${ALPINE}${DOT_TAR_DOT_GZ}"
    find "${PWD}" -type f -name '*.debuginfo' -exec rm {} \;
    find "${PWD}" -type f -name '*.diz' -exec rm {} \;
    GZIP=-9 tar -czhf "${JDK_FILE_NAME}" j2sdk-image/
    GZIP=-9 tar -czhf "${JRE_FILE_NAME}" j2re-image/

    GITHUB_TOKEN="$(cat ${HOME}/.github_token)"
    if [ -n "${GITHUB_TOKEN}" ]
    then
      GITHUB_OWNER=aashipov
      GITHUB_REPO=corretto-build
      GITHUB_RELEASE_ID=80394672

      FILES_TO_UPLOAD="${JDK_FILE_NAME} ${JRE_FILE_NAME}"
      for file_to_upload in ${FILES_TO_UPLOAD}
      do
        #https://stackoverflow.com/a/7506695
        FILE_NAME_URL_ENCODED="$(printf "${file_to_upload}" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g')"
        curl \
          "https://uploads.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/${GITHUB_RELEASE_ID}/assets?name=${FILE_NAME_URL_ENCODED}" \
          -H "Authorization: Bearer ${GITHUB_TOKEN}" \
          -H "Content-type: application/gzip" \
          --data-binary @"${RELEASE_IMAGE_DIR}/${file_to_upload}"
      done
    fi
  fi
}

closure() {
  set -e
  environment
  checkout
  build
  publish
}

# Main procedure
closure
