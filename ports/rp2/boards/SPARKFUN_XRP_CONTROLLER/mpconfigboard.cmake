# cmake file for SparkFun XRP Controller

# TODO: DELETE THIS LINE WHEN SUBMODULED PICO-SDK INCLUDES THIS BOARD
set(PICO_BOARD_HEADER_DIRS ${MICROPY_PORT_DIR}/boards/${MICROPY_BOARD})

set(PICO_BOARD "sparkfun_xrp_controller")
set(PICO_PLATFORM "rp2350")

set(PICO_NUM_GPIOS 48)

set(MICROPY_PY_LWIP ON)
set(MICROPY_PY_NETWORK_CYW43 ON)

# Bluetooth
set(MICROPY_PY_BLUETOOTH ON)
set(MICROPY_BLUETOOTH_BTSTACK ON)
set(MICROPY_PY_BLUETOOTH_CYW43 ON)

# Board specific version of the frozen manifest
set(MICROPY_FROZEN_MANIFEST ${MICROPY_BOARD_DIR}/manifest.py)
