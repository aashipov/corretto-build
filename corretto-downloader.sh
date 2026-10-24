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

download() {
    printf 'Downloading %s to %s\n' "${SRC_URL}" "${TGT_FILE}"
    if ! curl -fL --retry 3 -o "${TGT_FILE}.part" "${SRC_URL}"
    then
        rm -f "${TGT_FILE}.part"
        printf 'Failed to download %s' "${SRC_URL}"
        exit 1
    fi
    mv "${TGT_FILE}.part" "${TGT_FILE}"
}

closure() {
    set -e
    if [ -z "${1}" ]
    then
        printf 'Specify java version to download, e.g. corretto-downloader.sh 25\n'
        exit 1
    fi

    JAVA_VERSION="${1}"

    BASE_DIR="$(get_base_dir)"
    cd "${BASE_DIR}"

    SRC_URL="https://raw.githubusercontent.com/aashipov/corretto-build/refs/heads/main/.env"
    TGT_FILE="${BASE_DIR}/corretto.env"
    download
    TAG_TO_BUILD="$(cat ${TGT_FILE} | grep TAG_TO_BUILD_${JAVA_VERSION} | cut -d '=' -f 2)"

    INSTRUCTION_SET="x86_64"
    OS_TYPE="linux"
    if [ "${OSTYPE}" = "msys" ] || [ "${OSTYPE}" = "cygwin" ]
    then
        OS_TYPE="windows"
    fi
    PRODUCT_WITH_PLATFORM="jdk${JAVA_VERSION}u-${OS_TYPE}-${INSTRUCTION_SET}"

    CORRETTO="corretto"

    ALPINE=""
    if [ -f /etc/alpine-release ]
    then
        ALPINE="-alpine"
    fi

    SRC_URL="https://github.com/aashipov/corretto-build/releases/latest/download/${PRODUCT_WITH_PLATFORM}-${TAG_TO_BUILD}${ALPINE}.tar.gz"
    TGT_FILE="${BASE_DIR}/${CORRETTO}${JAVA_VERSION}.tar.gz"
    download

    TARGET_DIR_NAME="${CORRETTO}${JAVA_VERSION}"
    rm -rf "${BASE_DIR}/${TARGET_DIR_NAME}"
    mkdir -p "${BASE_DIR}/${TARGET_DIR_NAME}"
    tar -xzf "${TGT_FILE}" -C "${BASE_DIR}/${TARGET_DIR_NAME}"  --strip-components=1
}

closure "${1}"
