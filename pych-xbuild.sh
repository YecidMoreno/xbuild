#!/bin/bash
#
# xbuild - Cross-platform build helper script using Docker
#
# Author: Yecid Moreno <GitHub @YecidMoreno> <Email yecidmoreno@alumni.usp.br>
# Created: 2025-07-18
# Description: Automates building C++ projects for Linux, musl, and Windows targets
# License: MIT
#
# Usage:
#   ./xbuild <target> [options]
#   Targets: host, aarch64, musl, windows
#   Options: --debug, --src <dir>, --post-script "<cmd>", clean

# Get the absolute path of this script directory
XBUILD_DIR="$(dirname "$(readlink -f "$0")")"

# Set default debug mode to 0 if not already set
: "${DEBUG:=0}"

# Set target from first positional argument, default to 'host'
TARGET=${1:-host}
# shift
# Set source directory to current directory by default
SRC_DIR="$(pwd)"

# Initialize post-script as empty
POST_SCRIPT=""

# Array to store non-option positional arguments
POSITIONAL_ARGS=()

# Function to parse command-line arguments
read_args() {
    while (($# > 0)); do
        case "${1}" in
        --debug)
            # Enable debug mode
            DEBUG=1
            shift
            ;;
        --src)
            # Set custom source directory
            numOfArgs=1
            if (($# < numOfArgs + 1)); then
                shift $#
            else
                echo "switch: ${1} with value: ${2}"
                SRC_DIR="$(realpath ${2})"
                shift $((numOfArgs + 1))
            fi
            ;;
        -ps | --post-script)
            # Capture post-script command (with spaces)
            shift
            POST_SCRIPT="$1"
            shift
            while [[ $# -gt 0 && "$1" != --* ]]; do
                POST_SCRIPT+=" $1"
                shift
            done
            echo "switch: --post-script with value: $POST_SCRIPT"
            ;;
        clean)
            # Clean build and release directories and exit
            echo "Cleaning build and release directories..."
            rm -rf "$SRC_DIR/release"
            rm -rf "$SRC_DIR/build"
            rm -rf "$SRC_DIR/debug"
            exit 0
            ;;
        *)
            # Unrecognized positional argument
            POSITIONAL_ARGS+=("${1}")
            shift
            ;;
        esac
    done
}

# Parse arguments
read_args "$@"
set -- "${POSITIONAL_ARGS[@]}"
shift

# Define docker image and build command based on the target
DOCKER_IMAGE=""

case "$TARGET" in
host | x86_64-linux-gnu)
    TARGET="x86_64-linux-gnu"
    CMD="export TARGET=$TARGET && export BIN=./release/$TARGET/bin"
    CMD+=" && cmake -G Ninja -B ./build/$TARGET -S . "
    CMD+="-DCMAKE_INSTALL_PREFIX=./release/$TARGET "
    if ((DEBUG)); then
        CMD+=" -DCMAKE_BUILD_TYPE=Debug "
    fi
    CMD+=" && cmake --build build/$TARGET "
    CMD+=" && cmake --install build/$TARGET"
    DOCKER_IMAGE="pych-xbuild-linux:v0.1"
    ;;
aarch64 | aarch64-unknown-linux-gnu | pi)
    TARGET="aarch64-unknown-linux-gnu"
    CMD="export TARGET=$TARGET && export BIN=./release/$TARGET/bin "
    CMD+=" && cmake -G Ninja -B ./build/$TARGET -S . -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/toolchain-$TARGET.cmake "
    CMD+=" -DCMAKE_INSTALL_PREFIX=./release/$TARGET "
    if ((DEBUG)); then
        CMD+=" -DCMAKE_BUILD_TYPE=Debug "
    fi
    CMD+=" && cmake --build ./build/$TARGET "
    CMD+=" && cmake --install ./build/$TARGET"
    DOCKER_IMAGE="pych-xbuild-linux:v0.1"
    ;;
musl | x86_64-alpine-linux-musl)
    TARGET="x86_64-alpine-linux-musl"
    CMD="export TARGET=$TARGET && export BIN=./release/$TARGET/bin "
    CMD+=" && cmake -G Ninja -B ./build/$TARGET -S . -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/toolchain-$TARGET.cmake "
    CMD+="-DCMAKE_INSTALL_PREFIX=./release/$TARGET "
    if ((DEBUG)); then
        CMD+=" -DCMAKE_BUILD_TYPE=Debug "
    fi
    CMD+=" && cmake --build build/$TARGET "
    CMD+=" && cmake --install build/$TARGET"
    DOCKER_IMAGE="pych-xbuild-musl:v0.1"
    ;;
*)
    echo "Build not defined for: $TARGET" >&2
    exit 1
    ;;
esac

# Add post-build message or post-script execution
if [[ -z "$POST_SCRIPT" ]]; then
    CMD+=" && echo '----------------------' "
    CMD+=" && echo '  Done' "
    CMD+=" && echo '----------------------' "
else
    CMD+=" && echo '---------------------------------' "
    CMD+=" && echo '  Done, Running post script...' "
    CMD+=" && echo '  >> $POST_SCRIPT' "
    CMD+=" && echo '---------------------------------' "
    CMD+=" && $POST_SCRIPT "
fi

DOCER_CMD="docker run --rm -it -v \"$SRC_DIR\":/app $@ -w /app \"$DOCKER_IMAGE\" bash -c "

# Print final command
echo '---------------------------------'
echo "$DOCER_CMD"
echo "$CMD"
echo '---------------------------------'

# Run the build inside Docker container with mounted volume
FINAL_CMD="$DOCER_CMD \"$CMD\" "
eval "$FINAL_CMD"