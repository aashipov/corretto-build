#!/bin/sh

set -e

environment() {
    _SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$0")")
    cd ${_SCRIPT_DIR}

    JAVA_VERSION=${1}
    JDK="jdk"
    JRE="jre"
    JTREG="jtreg"
    GTEST="googletest"
    JDK_FLAVOR="${JDK}${JAVA_VERSION}u"
    JRE_FLAVOR="${JRE}${JAVA_VERSION}u"
    INSTRUCTION_SET="x86_64"
    CORRETTO=corretto

    TAG_TO_BUILD=$(cat ${_SCRIPT_DIR}/.tag_to_build_${JAVA_VERSION})
    if [ "${TAG_TO_BUILD}" == "" ]
    then
        printf "Can not find ${_SCRIPT_DIR}/.tag_to_build_${JAVA_VERSION} file or it is empty\n"
        exit 1
    fi

    local OS_TYPE="linux"
    TOP_DIR=${HOME}
    # https://github.com/archlinux/svntogit-packages/blob/packages/java11-openjdk/trunk/PKGBUILD
    # Avoid optimization of HotSpot being lowered from O3 to O2
    _CFLAGS="-O3 -pipe"
    if [ "${OSTYPE}" = "cygwin" ]
    then
        TOP_DIR="/cygdrive/c"
        OS_TYPE="windows"
        _CFLAGS="/O2"
    fi
    if [ -z ${JAVA_HOME+x} ] || [ "" = "${JAVA_HOME}" ]
    then
        export JAVA_HOME=${TOP_DIR}/dev/tools/openjdk${JAVA_VERSION}
    fi
    JDK_DIR="${TOP_DIR}/${CORRETTO}-${JAVA_VERSION}"
    JTREG_DIR="${TOP_DIR}/${JTREG}"
    GTEST_DIR="${TOP_DIR}/${GTEST}"
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

    if [ "${JAVA_VERSION}" = "11" ]
    then
        RELEASE_IMAGE_DIR=${JDK_DIR}/build/${OS_TYPE_AND_INSTRUCTION_SET}-normal-server-release/images/
        # if [ ! -d "${JTREG_DIR}/.git" ]; then
        #     cd ${TOP_DIR}
        #     git clone https://github.com/openjdk/${JTREG}.git
        #     cd ${JTREG_DIR}
        # else
        #     cd ${JTREG_DIR}
        #     git pull -r
        # fi
        # sh make/build.sh --jdk ${JAVA_HOME}
    elif [ "${JAVA_VERSION}" = "17" ] || [ "${JAVA_VERSION}" = "21" ] || [ "${JAVA_VERSION}" = "25" ]
    then
        RELEASE_IMAGE_DIR=${JDK_DIR}/build/${OS_TYPE_AND_INSTRUCTION_SET}-server-release/images/
        # if [ ! -d "${GTEST_DIR}/.git" ]; then
        #     cd ${TOP_DIR}
        #     git clone https://github.com/google/googletest
        #     cd ${GTEST_DIR}
        # else
        #     cd ${GTEST_DIR}
        #     git checkout main
        #     git pull -r
        # fi
        # git checkout tags/release-1.8.1
    else
        printf "Version 11, 17, 21 or 25 only\n"
        exit 1
    fi
}

checkout() {
    DEFAULT_BRANCH=develop
    if [ ! -d "${JDK_DIR}/.git" ]
    then
        cd ${TOP_DIR}
        git clone https://github.com/${CORRETTO}/${CORRETTO}-${JAVA_VERSION}.git
        cd ${JDK_DIR}
    else
        cd ${JDK_DIR}
        git checkout ${DEFAULT_BRANCH}
        git pull
    fi

    if [ $(git tag -l "${TAG_TO_BUILD}") ]
    then
        git checkout tags/${TAG_TO_BUILD}
    else
        printf "Can not find tag ${TAG_TO_BUILD}\n"
        exit 1
    fi
}

build() {
    VERSION_BUILD=$(printf ${TAG_TO_BUILD} | cut -d '.' -f 4)

    CONFIGURE_DETAILS="--verbose --with-debug-level=release --with-native-debug-symbols=none --with-jvm-variants=server --with-freetype=bundled --with-version-pre=\"\" --with-version-opt=\"\" --with-extra-cflags=\"${_CFLAGS}\" --with-extra-cxxflags=\"${_CFLAGS}\" --with-extra-ldflags=\"${_CFLAGS}\" --enable-unlimited-crypto --disable-warnings-as-errors --with-version-build=\"${VERSION_BUILD}\" --with-version-pre= --with-vendor-version-string=Corretto-O3-\"${TAG_TO_BUILD}\""
    #CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-toolchain-type=clang"
    #CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-jtreg=${JTREG_DIR}/build/images/jtreg"
    #CONFIGURE_DETAILS="${CONFIGURE_DETAILS} --with-gtest=${GTEST_DIR}"
    sh -c "sh configure ${CONFIGURE_DETAILS}"

    make clean
    STARTTIME=$(date +%s)
    make images legacy-jre-image docs
    ENDTIME=$(date +%s)
    echo "Compilation took $((${ENDTIME} - ${STARTTIME})) seconds"
}

publish() {
    if [ ${?} -eq 0 ]
    then
        cd ${RELEASE_IMAGE_DIR}
        local DOT_TAR_DOT_GZ=".tar.gz"
        local JDK_FILE_NAME=${JDK_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TAG_TO_BUILD}${ALPINE}${DOT_TAR_DOT_GZ}
        local JRE_FILE_NAME=${JRE_FLAVOR}-${OS_TYPE_AND_INSTRUCTION_SET}-${TAG_TO_BUILD}${ALPINE}${DOT_TAR_DOT_GZ}
        find "${PWD}" -type f -name '*.debuginfo' -exec rm {} \;
        find "${PWD}" -type f -name '*.diz' -exec rm {} \;
        GZIP=-9 tar -czhf ${JDK_FILE_NAME} jdk/
        GZIP=-9 tar -czhf ${JRE_FILE_NAME} jre/

        local GITHUB_TOKEN=$(cat ${HOME}/.github_token)
        if [[ "${GITHUB_TOKEN}" != "" ]]; then
            local GITHUB_OWNER=aashipov
            local GITHUB_REPO=corretto-build
            local GITHUB_RELEASE_ID=80394672

            local FILES_TO_UPLOAD="${JDK_FILE_NAME} ${JRE_FILE_NAME}"
            for file_to_upload in ${FILES_TO_UPLOAD}; do
                #https://stackoverflow.com/a/7506695
                FILE_NAME_URL_ENCODED=$(printf "${file_to_upload}" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g')
                curl \
                    https://uploads.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/${GITHUB_RELEASE_ID}/assets?name=${FILE_NAME_URL_ENCODED} \
                    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                    -H "Content-type: application/gzip" \
                    --data-binary @${RELEASE_IMAGE_DIR}/${file_to_upload}
            done
        fi
    fi
}

do_test() {
    if [ ${?} -eq 0 ]
    then
        cd ${JDK_DIR}
        make run-test-tier1
    fi
}

closure() {
    environment ${1}
    checkout
    build
    #do_test
    publish
}

# Main procedure
closure ${1}
