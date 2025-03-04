#!/usr/bin/env bash
# This script builds the OpenROAD Flow tools locally or in a Docker image.

# Exit on first error, do not allow unbound variables
set -eu

# Make sure we are on the correct folder before beginning
cd "$(dirname $(readlink -f $0))"

# Defaults variable values
NICE=""
PROC=$(nproc --all)
DOCKER_TAG="openroad/flow-scripts"
OPENROAD_APP_REMOTE="origin"
OPENROAD_APP_BRANCH="master"

INSTALL_PATH="$(pwd)/tools/install"

DOCKER_USER_ARGS=""
DOCKER_ARGS="--no-cache"

YOSYS_USER_ARGS=""
YOSYS_ARGS="\
CONFIG=gcc \
ABCREV=bafd2a7 ABCURL=https://github.com/berkeley-abc/abc \
"

OPENROAD_APP_USER_ARGS=""
OPENROAD_APP_ARGS=""

LSORACLE_USER_ARGS=""
LSORACLE_ARGS="\
-D CMAKE_BUILD_TYPE=RELEASE \
-D YOSYS_INCLUDE_DIR=$(pwd)/tools/yosys \
-D YOSYS_PLUGIN=ON \
"

function usage() {
        cat << EOF

Usage: $0 [-h|--help] [-o|--local] [-l|--latest]
          [--or_branch BRANCH_NAME] [--or_repo REPO_URL] [--no_init]
          [-n|--nice] [-t|--threads N]
          [--yosys-args-overwrite] [--yosys-args STRING]
          [--openroad-args-overwrite] [--openroad-args STRING]
          [--lsoracle-args-overwrite] [--lsoracle-args STRING]
          [--install-path PATH] [--clean] [--clean-force]

          [-c|--copy-platforms]
          [--docker-args-overwrite] [--docker-args STRING]

Options:
    -h, --help              Print this help message.

    -o, --local             Build locally instead of building a Docker image.

    -l, --latest            Use the head of branch --or_branch or 'master'
                            by default for tools/OpenROAD.

    --or_branch BRANCH_NAME Use the head of branch BRANCH for tools/OpenROAD.

    --or_repo REPO_URL      Use a fork at REPO-URL (https/ssh) for tools/OpenROAD.

    --no_init               Skip initializing submodules.

    -t, --threads N         Use N cpus when compiling software.

    -n, --nice              Nice all jobs. Use all cpus unless --threads is
                            also given, then use N threads.

    --yosys-args-overwrite  Do not use default flags set by this scrip during
                            Yosys comilation.

    --yosys-args STRING      Aditional compilation flags for Yosys compilation.

    --openroad-args-overwrite
                            Do not use default flags set by this scrip during
                            OpenROAD app compilation.

    --openroad-args STRING  Aditional compilation flags for OpenROAD app
                            compilation.

    --lsoracle-args-overwrite
                            Do not use default flags set by this scrip during
                            LSOracle compilation.

    --lsoracle-args STRING    Aditional compilation flags for LSOracle
                            compilation.

    --install-path PATH     Path to install tools. Default is ${INSTALL_PATH}.

    --clean                 Call git clean interactively before compile.
                            Useful to remove old build files.

    --clean-force           Call git clean before compile. WARNING: this option
                            will not ask for confirmation. Useful to remove
                            old build files.


Options valid only for Docker builds:
    -c, --copy-platforms    Copy platforms to inside docker image.

    --docker-args-overwrite Do not use default flags set by this scrip for
                            Docker builds.

    --docker-args STRING    Aditional compilation flags for Docker build.

    This script builds the OpenROAD tools: openroad, yosys and yosys plugins.
    By default, the tools will be built from the linked submodule hashes.

EOF
}

# Parse arguments
while (( "$#" )); do
        case "$1" in
                -h|--help)
                        usage 2> /dev/null
                        exit
                        ;;
                -o|--local)
                        LOCAL_BUILD=1
                        ;;
                -l|--latest)
                        USE_OPENROAD_APP_LATEST=1
                        ;;
                --or_branch)
                        OPENROAD_APP_BRANCH="$2"
                        shift
                        ;;
                --or_repo)
                        OPENROAD_APP_GIT_URL="$2"
                        shift
                        ;;
                --no_init)
                        OPENROAD_FLOW_NO_GIT_INIT=1
                        ;;
                -t|--threads)
                        PROC="$2"
                        shift
                        ;;
                -n|--nice)
                        NICE="nice"
                        ;;
                -c|--copy-platforms)
                        DOCKER_COPY_PLATFORMS=1
                        ;;
                --docker-args-overwrite)
                        DOCKER_OVERWIRTE_ARGS=1
                        ;;
                --docker-args)
                        DOCKER_USER_ARGS="$2"
                        shift
                        ;;
                --yosys-args-overwrite)
                        YOSYS_OVERWIRTE_ARGS=1
                        ;;
                --yosys-args)
                        YOSYS_USER_ARGS="$2"
                        shift
                        ;;
                --openroad-args-overwrite)
                        OPENROAD_APP_OVERWIRTE_ARGS=1
                        ;;
                --openroad-args)
                        OPENROAD_APP_USER_ARGS="$2"
                        shift
                        ;;
                --lsoracle-args-overwrite)
                        LSORACLE_OVERWIRTE_ARGS=1
                        ;;
                --lsoracle-args)
                        LSORACLE_USER_ARGS="$2"
                        shift
                        ;;
                --install-path)
                        INSTALL_PATH="$2"
                        shift
                        ;;
                --clean)
                        CLEAN_BEFORE=1
                        ;;
                --clean-force)
                        CLEAN_BEFORE=1
                        CLEAN_FORCE=1
                        ;;
                -*|--*) # unsupported flags
                        echo "[ERROR FLW-0005] Unsupported flag $1." >&2
                        usage 2> /dev/null
                        exit 1
                        ;;
        esac
        shift
done

# Only add install prefix variables after parsing arguments.
YOSYS_ARGS+=" PREFIX=${INSTALL_PATH}/yosys"
OPENROAD_APP_ARGS+=" -D CMAKE_INSTALL_PREFIX=${INSTALL_PATH}/OpenROAD"
LSORACLE_ARGS+=" \
-D YOSYS_SHARE_DIR=${INSTALL_PATH}/yosys/share/yosys \
-D CMAKE_INSTALL_PREFIX=${INSTALL_PATH}/LSOracle \
"

if [ ! -z "${DOCKER_OVERWIRTE_ARGS+x}" ]; then
        echo "[INFO FLW-0015] Overwriting Docker build flags."
        DOCKER_ARGS="${DOCKER_USER_ARGS}"
else
        DOCKER_ARGS+=" ${DOCKER_USER_ARGS}"
fi

if [ ! -z "${YOSYS_OVERWIRTE_ARGS+x}" ]; then
        echo "[INFO FLW-0013] Overwriting Yosys compilation flags."
        YOSYS_ARGS="${YOSYS_USER_ARGS}"
else
        YOSYS_ARGS+=" ${YOSYS_USER_ARGS}"
fi

if [ ! -z "${OPENROAD_APP_OVERWIRTE_ARGS+x}" ]; then
        echo "[INFO FLW-0014] Overwriting OpenROAD app compilation flags."
        OPENROAD_APP_ARGS="${OPENROAD_APP_USER_ARGS}"
else
        OPENROAD_APP_ARGS+=" ${OPENROAD_APP_USER_ARGS}"
fi

if [ ! -z "${LSORACLE_OVERWIRTE_ARGS+x}" ]; then
        echo "[INFO FLW-0013] Overwriting LSOracle compilation flags."
        LSORACLE_ARGS="${LSORACLE_USER_ARGS}"
else
        LSORACLE_ARGS+=" ${LSORACLE_USER_ARGS}"
fi

__docker_build()
{
        echo "[INFO FLW-0020] Building docker image for Yosys."
        docker pull "openroad/yosys-dev"
        ${NICE} docker build \
                ${DOCKER_ARGS} \
                --tag openroad/yosys \
                --file tools/yosys_util/Dockerfile \
                --target builder \
                tools/yosys

        echo "[INFO FLW-0021] Building docker image for LSOracle."
        docker pull "openroad/centos7-dev"
        ${NICE} docker build \
                ${DOCKER_ARGS} \
                --tag openroad/lsoracle \
                --file tools/LSOracle/Dockerfile.openroad \
                tools

        echo "[INFO FLW-0022] Building docker image for OpenROAD app."
        ${NICE} ./tools/OpenROAD/etc/DockerHelper.sh create \
                -target=builder \
                -threads=${PROC}

        echo "[INFO FLW-0023] Building docker image for OpenROAD Flow."
        if [ ! -z "${DOCKER_COPY_PLATFORMS+x}" ]; then
                cp .dockerignore{,.bak}
                sed -i '/flow\/platforms/d' .dockerignore
        fi
        docker pull "openroad/flow-runtime"
        ${NICE} docker build \
                ${DOCKER_ARGS} \
                --tag "${DOCKER_TAG}" \
                --file Dockerfile \
                .
        if [ ! -z "${DOCKER_COPY_PLATFORMS+x}" ]; then
                mv .dockerignore{.bak,}
        fi
}

__local_build()
{
        echo "[INFO FLW-0017] Compiling Yosys."
        ${NICE} make install -C tools/yosys -j "${PROC}" ${YOSYS_ARGS}

        echo "[INFO FLW-0018] Compiling OpenROAD."
        ${NICE} cmake tools/OpenROAD -B tools/OpenROAD/build ${OPENROAD_APP_ARGS}
        ${NICE} cmake --build tools/OpenROAD/build --target install -j "${PROC}"

        echo "[INFO FLW-0019] Compiling LSOracle."
        ${NICE} cmake tools/LSOracle -B tools/LSOracle/build ${LSORACLE_ARGS}
        ${NICE} cmake --build tools/LSOracle/build --target install -j "${PROC}"
}

__update_openroad_app_remote()
(
        cd tools/OpenROAD
        remotes=$(git remote)
        SAVEIFS=$IFS
        IFS=$'\n'
        remotes=($remotes)
        IFS=$SAVEIFS
        if [[ ! " ${remotes[@]} " =~ " ${OPENROAD_APP_REMOTE} " ]]; then
                git remote add "${OPENROAD_APP_REMOTE}" "${OPENROAD_APP_GIT_URL}"
        fi
)

__change_openroad_app_remote()
{
        base_url=$(dirname "${OPENROAD_APP_GIT_URL}")
        if [[ ${base_url##*/} = $base_url ]]; then
                OPENROAD_APP_REMOTE=${base_url##*:}
        else
                OPENROAD_APP_REMOTE=${base_url##*/}
        fi
        __update_openroad_app_remote
}

__update_openroad_app_latest()
(
        cd tools/OpenROAD
        git fetch "${OPENROAD_APP_REMOTE}"
        git checkout "${OPENROAD_APP_REMOTE}/${OPENROAD_APP_BRANCH}"
        git pull "${OPENROAD_APP_REMOTE}" "${OPENROAD_APP_BRANCH}"
        git submodule update --init --recursive
)

__common_setup()
{
        # Clone repositories
        if [ -z "${OPENROAD_FLOW_NO_GIT_INIT+x}" ]; then
                echo "[INFO FLW-0002] Updating git submodules."
                git submodule update --init --recursive
        fi

        if [ ! -z "${OPENROAD_APP_GIT_URL+x}" ]; then
                echo -n "[INFO FLW-0003] Changing OpenROAD app remote to"
                echo " ${OPENROAD_APP_GIT_URL}."
                __change_openroad_app_remote
        fi

        if [ ! -z "${USE_OPENROAD_APP_LATEST+x}" ] || [ "${OPENROAD_APP_BRANCH}" != "master" ]; then
                echo -n "[INFO FLW-0004] Updating OpenROAD app to the HEAD"
                echo "  of ${OPENROAD_APP_REMOTE}/${OPENROAD_APP_BRANCH}."
                __update_openroad_app_latest
        fi
}

__common_setup

if [ ! -z "${CLEAN_FORCE+x}" ]; then
        CLEAN_CMD="-x -d --force"
else
        CLEAN_CMD="-x -d --interactive"
fi
if [ ! -z "${CLEAN_BEFORE+x}" ]; then
        echo "[INFO FLW-0016] Cleaning up previous binaries and build files."
        git clean ${CLEAN_CMD} tools
        git submodule foreach --recursive git clean ${CLEAN_CMD}
fi

# Choose install method
if [ -z "${LOCAL_BUILD+x}" ] && command -v docker &> /dev/null; then
        echo -n "[INFO FLW-0000] Using docker build method."
        echo " This will create a docker image tagged '${DOCKER_TAG}'."
        __docker_build
else
        echo -n "[INFO FLW-0001] Using local build method."
        echo " This will create binaries at 'tools/install unless overwritten."
        __local_build
fi
