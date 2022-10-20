#!/bin/bash

# Build vanilla openJDK upstream from source

usage() {
    if [ $# -ne 2 ]; then
        echo "usage: $(basename $0) distro java_version"
        echo "  distro  - centos, opensuse, debian, alpine"
        echo "  version - java version to build (7, 8, 11, 17)"
        exit 1
    fi
}

distro_jdk_version() {
    TAG="${DISTRO}${JDK}${JAVA_VERSION}u"
    IMAGE="${DOCKER_HUB_USER_AND_REPOSITORY}:${TAG}"

    docker stop ${TAG}
    docker rm ${TAG}
    docker pull ${IMAGE}
    if [[ $? -ne 0 ]]; then
        printf "Build docker images in openjdk-build first\n"
        exit 1
    fi
}

mounts() {
    if [[ "${JAVA_VERSION}" = "11" ]] || [[ "${JAVA_VERSION}" = "17" ]]; then
        ENTRYPOINT_FILENAME="entrypoint9plus.bash"
        CMD="bash /${DUMMY_USER}/${ENTRYPOINT_FILENAME} ${JAVA_VERSION}"
    else
        ENTRYPOINT_FILENAME="entrypoint${JAVA_VERSION}.bash"
        CMD="bash /${DUMMY_USER}/${ENTRYPOINT_FILENAME}"
    fi
    VOLUMES="-v ${HOME}/${JDK_AND_JAVA_VERSION}/:/${DUMMY_USER}/${JDK_AND_JAVA_VERSION} -v ${HOME}/${JTREG}/:/${DUMMY_USER}/${JTREG} -v ${HOME}/${GTEST}/:/${DUMMY_USER}/${GTEST} -v ${_SCRIPT_DIR}/${ENTRYPOINT_FILENAME}:/${DUMMY_USER}/${ENTRYPOINT_FILENAME}"

    mkdir -p ${HOME}/${JDK_AND_JAVA_VERSION} ${HOME}/${JTREG} ${HOME}/${GTEST}
}

main() {
    docker run -it --name=${TAG} --hostname=${TAG} --user=${DUMMY_USER} --workdir=/${DUMMY_USER}/ ${VOLUMES} ${IMAGE} ${CMD}
}

set -x

# https://stackoverflow.com/a/1482133
# Consistent across Linux bash, Cygwin terminal and Git Bash
_SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$0")")

DISTRO=${1}
JAVA_VERSION=${2}
JDK="jdk"
JDK_AND_JAVA_VERSION=corretto-${JAVA_VERSION}
JTREG="jtreg"
GTEST="googletest"
JDK_BUILDER="${JDK}builder"
DOCKER_HUB_USER_AND_REPOSITORY="aashipov/openjdk-build"
DUMMY_USER="dummy"

usage ${DISTRO} ${JAVA_VERSION}
distro_jdk_version
mounts
main
