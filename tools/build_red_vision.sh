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

    # Clone the Red Vision submodule
    git submodule update --init --recursive micropython/lib/red_vision

    # Set Pico SDK path to $GITHUB_WORKSPACE/micropython/lib/pico-sdk if $GITHUB_WORKSPACE is set, otherwise use the current directory
    if [ -n "$GITHUB_WORKSPACE" ]; then
        export PICO_SDK_PATH="$GITHUB_WORKSPACE/micropython/lib/pico-sdk"
    else
        export PICO_SDK_PATH=$(dirname "$0")/micropython/lib/pico-sdk
    fi

    # Build MPY Cross compiler
    make -C micropython/mpy-cross ${MAKEOPTS}

    # Update necessary MicroPython submodules
    make -C micropython/ports/rp2 BOARD=SPARKFUN_XRP_CONTROLLER submodules

    # Build OpenCV
    make -C micropython/lib/red_vision/micropython-opencv PLATFORM=rp2350 --no-print-directory ${MAKEOPTS}

    # Build firmware
    make -C micropython/lib/red_vision PORT_DIR=micropython/ports/rp2 BOARD=SPARKFUN_XRP_CONTROLLER ${MAKEOPTS}

    # Rename firmware file to identify it as the Red Vision build and which board it's for
    mv micropython/ports/rp2/build-SPARKFUN_XRP_CONTROLLER-RED_VISION/firmware.uf2 micropython/ports/rp2/build-SPARKFUN_XRP_CONTROLLER-RED_VISION/RED_VISION_MICROPYTHON_SPARKFUN_XRP_CONTROLLER.uf2
}
