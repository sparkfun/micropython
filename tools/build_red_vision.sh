if which nproc > /dev/null; then
    MAKEOPTS="-j$(nproc)"
else
    MAKEOPTS="-j$(sysctl -n hw.ncpu)"
fi

# Installs necessary dependencies and builds OpenCV and the Red Vision firmware
# Also freezes the examples directory in a filesystem archive on the board
function build_micropython_red_vision {
    # Install necessary packages (Could move into an install_dependencies.sh if we want this to be more explicit/modular)
    sudo apt update
    sudo apt install cmake python3 build-essential gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib
    # Install necessary python packages (could also move this to a requirements.txt file)
    pip install freezefs

    # Set Pico SDK path to $GITHUB_WORKSPACE/micropython/lib/pico-sdk if $GITHUB_WORKSPACE is set, otherwise use the current directory
    # https://stackoverflow.com/a/246128/4783963
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    if [ -n "$GITHUB_WORKSPACE" ]; then
        export PICO_SDK_PATH="$GITHUB_WORKSPACE/lib/pico-sdk"
    else
        export PICO_SDK_PATH="$SCRIPT_DIR/../lib/pico-sdk"
    fi

    # Clone the Red Vision submodule
    git submodule update --init --recursive lib/red_vision

    # Build MPY Cross compiler
    make -C mpy-cross ${MAKEOPTS}

    # Update necessary MicroPython submodules
    make -C ports/rp2 \
        BOARD=SPARKFUN_XRP_CONTROLLER \
        BOARD_VARIANT=RED_VISION \
        submodules

    # Build OpenCV
    make -C lib/red_vision/micropython-opencv PLATFORM=rp2350 --no-print-directory ${MAKEOPTS}

    # Archive the examples directory
    python3 -m freezefs lib/red_vision/red_vision_examples lib/red_vision/extract_red_vision_examples.py  --on-import=extract --compress --overwrite always

    # Set CMake arguments for Pico SDK to use MicroPython-OpenCV malloc wrappers
    # and enable C++ exceptions
    export CMAKE_ARGS="-DSKIP_PICO_MALLOC=1 -DPICO_CXX_ENABLE_EXCEPTIONS=1"

    # Build firmware
    make -C ports/rp2 \
        BOARD=SPARKFUN_XRP_CONTROLLER \
        BOARD_VARIANT=RED_VISION \
        USER_C_MODULES="$SCRIPT_DIR/../lib/red_vision/micropython-opencv/micropython_opencv.cmake" \
        FROZEN_MANIFEST="$SCRIPT_DIR/../lib/red_vision/manifest.py" \
        --no-print-directory ${MAKEOPTS}
    
    # Unset CMake arguments to avoid affecting other builds
    unset CMAKE_ARGS

    # Rename firmware file to identify it as the Red Vision build and which board it's for
    mv ports/rp2/build-SPARKFUN_XRP_CONTROLLER-RED_VISION/firmware.uf2 ports/rp2/build-SPARKFUN_XRP_CONTROLLER-RED_VISION/RED_VISION_MICROPYTHON_SPARKFUN_XRP_CONTROLLER.uf2
}
