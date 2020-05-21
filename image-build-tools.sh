#!/bin/sh

#
# image-build-tools is a helper script to ease 
# the administrative burden of updating, building,
# and pushing updates for all of the image-build
# repositories.
#

# set debug to print out commands. this is set
# from an environment variable.
if [ "${DEBUG}" = "1" ]; then
    set -x
fi

USAGE="usage: $0 command sub-command

description:
    helper script to ease the administrative burden of updating, building, and pushing 
    updates for all of the image-build repositories.

flags:
    -h --help                               print this message

commands:
    get
        all-repos 
            local                           print out all local image-build repos
            remote                          print out all remote image-build repos

    update
        build-image <image-name:version>    update build-image for all repos
        ubi-image   <image-name:version>    update ubi-image for all repos

    commit
        all                                 commit changes for all image-build repos

    push
        all                                 commit changes for all image-build repos

    help                                    print this message

examples:
    $0 get all-repos local
    $0 udpate build-image ranchertest/build-base:v1.14.2
"

# return error codes
ERR_GEN=1
ERR_DEP=2
ERR_ARG=3

# make sure we have at least one argument to 
# process or die early.
if [ -z "$1" ]; then
    echo "${USAGE}"
    exit ${ERR_GEN}
fi

# make sure we have docker installed
GIT="$(command -v git)"
if [ -z "${GIT}" ]; then 
    echo "error: $0 requires git"
    exit ${ERR_DEP}
fi

# make sure we have docker installed
DOCKER="$(command -v docker)"
if [ -z "${DOCKER}" ]; then 
    echo "error: $0 requires docker"
    exit ${ERR_DEP}
fi

# make sure we have jq installed
JQ="$(command -v jq)"
if [ -z "${JQ}" ]; then 
    echo "error: $0 requires jq"
    exit ${ERR_DEP}
fi

# make sure we have curl installed
CURL="$(command -v curl)"
if [ -z "${CURL}" ]; then 
    echo "error: $0 requires curl"
    exit ${ERR_DEP}
fi

COMMAND="$1"

RANCHER_PATH="${GOPATH}/src/github.com/rancher"
INVALID_ARG_ERROR="error: update requires an argument"
IMAGE_BUILD_REPOS=$(find "${RANCHER_PATH}"    \
    -path "*image-build-*"                    \
    -type f -not -path "*image-build-tools/*" \
    -type f -not -path "*image-build-base/*"  \
    -type f -name "Dockerfile")

# list_local_repos prints out all of the local
# repos to STDOUT.
list_local_repos() {
    for i in ${IMAGE_BUILD_REPOS}; do
        echo "$i" | sed 's/\/Dockerfile//g'
    done
}

# list_remote_repos prints out all of the remote
# repos to STDOUT.
#list_remote_repos() {}

case ${COMMAND} in
    "help|-h|--help")
        echo "${USAGE}"
        exit 0
    ;;
    "get")
        if [ -z "$2" ]; then
            echo "error: get requires an argument"
            exit ${ERR_ARG}
        fi
        case ${2} in 
            "all-repos")
                if [ -z "${3}" ]; then
                    echo "error: all-repos requires an argument: {local|remote}"
                    exit ${ERR_GEN}
                fi
                case ${3} in
                    "local")
                        list_local_repos
                    ;;
                    "remote")
                        # list_remote_repos
                        echo "not implemented"
                    ;;
                    *)
                    echo "${INVALID_ARG_ERROR}"
                    exit ${ERR_ARG}
                    ;;
                esac
                exit 0
            ;;
            *)
                echo "${INVALID_ARG_ERROR}"
                exit ${ERR_ARG}
            ;;
        esac
    ;;
    "update")
        if [ -z "$2" ]; then
            echo "error: update requires an argument: {build-image|ubi-image}"
            exit ${ERR_ARG}
        fi
        case ${2} in 
            "build-image")
                if [ -z "$3" ]; then
                    echo "error: build-image requires an argument: {image_name:version}"
                    exit ${ERR_ARG}
                fi
                for i in ${IMAGE_BUILD_REPOS}; do 
                    image_name=$(awk -F '=' '/ARG GO_IMAGE/ {print $2}' "$i")
                    sed -i "s|${image_name}|$3|g" "${i}"
                done
                exit 0
            ;;
            "ubi-image")
                if [ -z "$3" ]; then
                    echo "error: ubi-image requires an argument: {image_name:version}"
                    exit ${ERR_ARG}
                fi
                for i in ${IMAGE_BUILD_REPOS}; do 
                    image_name=$(awk -F '=' '/ARG UBI_IMAGE/ {print $2}' "$i")
                    sed -i "s|${image_name}|$3|g" "${i}"
                done
                exit 0
            ;;
            *)
                echo "${INVALID_ARG_ERROR}"
                exit ${ERR_ARG}
            ;;
        esac
    ;;
    "commit")
        if [ -z "$2" ]; then
            echo "error: commit requires an argument: {all}"
            exit ${ERR_ARG}
        fi
        case ${2} in 
            "all")
                if [ -z "$3" ]; then
                    echo "error: all requires an argument: <git commit message>"
                    exit ${ERR_ARG}
                fi
                for i in ${IMAGE_BUILD_REPOS}; do 
                    target=$(echo "$i" | sed 's/\/Dockerfile//g')
                    echo "commiting ${target} ..."
                    cd "${target}" || exit ${ERR_GEN}
                    ${GIT} add .
                    ${GIT} commit -am "${3}"
                done
                exit 0
            ;;
            *)
                echo "${INVALID_ARG_ERROR}"
                exit ${ERR_ARG}
            ;;
        esac
    ;;
    "push")
        if [ -z "$2" ]; then
            echo "error: commit requires an argument: {all}"
            exit ${ERR_ARG}
        fi
        case ${2} in 
            "all")
                if [ -z "$3" ]; then
                    echo "error: all requires an argument: <git commit message>"
                    exit ${ERR_ARG}
                fi
                for i in ${IMAGE_BUILD_REPOS}; do 
                    target=$(echo "$i" | sed 's/\/Dockerfile//g')
                    echo "commiting ${target} ..."
                    cd "${target}" || exit ${ERR_GEN}
                    ${GIT} push 
                done
                exit 0
            ;;
            *)
                echo "${INVALID_ARG_ERROR}"
                exit ${ERR_ARG}
            ;;
        esac
    ;;
    "revert")
        if [ -z "$2" ]; then
            echo "error: revert requires an argument: {all}"
            exit ${ERR_ARG}
        fi
        case ${2} in
        "all")
            for i in ${IMAGE_BUILD_REPOS}; do
                target=$(echo "$i" | sed 's/\/Dockerfile//g')
                echo "reverting ${target} ..."
                cd "${target}" || exit ${ERR_GEN}
                ${GIT} stash
            done
        ;;
        *)
            echo "${INVALID_ARG_ERROR}"
            exit ${ERR_ARG}
        ;;
        esac
    ;;
    *)
        echo "${USAGE}"
        exit ${ERR_ARG}
    ;;
esac

exit 0
