if which nproc > /dev/null; then
    MAKEOPTS="-j$(nproc)"
else
    MAKEOPTS="-j$(sysctl -n hw.ncpu)"
fi

# Downloads the latest Qwiic release from the SparkFun Qwiic_Py repository and extracts the contents to the given directory
# Options:
    # $1: Output directory
function download_qwiic_release {
    local LATEST_RELEASE=`gh release -R sparkfun/Qwiic_Py list --json name,isLatest --jq '.[] | select(.isLatest)|.name'`
    curl -sL -o pylibs.zip https://github.com/sparkfun/Qwiic_Py/releases/latest/download/qwiic-py-py-${LATEST_RELEASE}.zip
    unzip pylibs.zip -d .

    mkdir -p $1
    cp -r qwiic-py-py-${LATEST_RELEASE}/lib/* $1
}

# Creates a frozen data filesystem for micropython using the freezefs python package
# This will search the qwiic directory for any modules that have data files that need to be frozen via firmware and extracted with boot.py or main.py
# Options:
    # $1: Qwiic directory
    # $2: Output py file of frozen data
    # $3: Ignored modules (optional, default: none)
function create_frozen_data_fs {
    local IGNORED_MODULES=${3:-""}
    
    # Add the freezefs python package for creating self-extracting/self-mounting archives for micropython
    pip install freezefs

    # create our "_frozen_data" directory
    local FROZEN_DATA_DIR="_frozen_data"
    mkdir ${FROZEN_DATA_DIR}

    # Iterate over all of the folders in the qwiic directory and check if they have another directory inside them
    # This represents that they have data files that we need to freeze with freezefs
    # Ignore the modules passed in the IGNORED_MODULES option
    for module in $(find $1 -mindepth 1 -maxdepth 1 -type d | grep -vE "${IGNORED_MODULES}"); do
        # Check if the module has a top-level directory inside it
        for data_dir in $(find $module -mindepth 1 -maxdepth 1 -type d); do
            # If it does, we will freeze the data directory
            echo "Freezing data for module: $data_dir"

            # Copy the data directory to the _frozen_data directory that we will freeze with freezefs
            # If the data directory name is already used in the _frozen_data directory, we'll prepend the module name to the directory when we copy it
            if [ -d "${FROZEN_DATA_DIR}/$(basename $data_dir)" ]; then
                cp -r $data_dir ${FROZEN_DATA_DIR}/$(basename $module)_$(basename $data_dir)
            else
                cp -r $data_dir ${FROZEN_DATA_DIR}/$(basename $data_dir)
            fi
        done
    done

    # Now we will use freezefs to create a self-extracting archive from the _frozen_data directory
    echo "Creating self-extracting archive from ${FROZEN_DATA_DIR}"
    python3 -m freezefs ${FROZEN_DATA_DIR} $2
    if [ $? -ne 0 ]; then
        echo "Error creating frozen data filesystem. Please check the freezefs documentation for more information."
        exit 1
    fi
}

# Adds the frozen data filesystem to the boot.py file for the given port
# Options:
    # $1: Port name
    # $2: Frozen data file path
function add_frozen_data_to_boot_for_port {
    local TARGET_PORT_NAME=$1
    local FROZEN_DATA_FILE=$2

    # Remove the ".py" extension from the frozen data file
    local FROZEN_DATA_BASENAME=$(basename $FROZEN_DATA_FILE .py)

    # Check if the _boot.py file exists in the port's modules directory and error out if it does not
    if [ ! -f ports/${TARGET_PORT_NAME}/modules/_boot.py ]; then
        echo "Error: _boot.py file not found in ports/${TARGET_PORT_NAME}/modules/"
        exit 1
    fi

    # Add the frozen data filesystem to the _boot.py file
    echo "Adding frozen data filesystem to _boot.py for port ${TARGET_PORT_NAME}"
    echo "import ${FROZEN_DATA_BASENAME}" >> ports/${TARGET_PORT_NAME}/modules/_boot.py
    echo "Content of _boot.py after adding frozen data filesystem:"
    cat ports/${TARGET_PORT_NAME}/modules/_boot.py
}

# Deletes all SparkFun build directories for the given port
# Options:
    # $1: Port name
function delete_build_directories_for_port {
    local TARGET_PORT_NAME=$1
    echo "TARGET_PORT_NAME: ${TARGET_PORT_NAME}"

    local SPARKFUN_BOARD_PREFIX="ports/${TARGET_PORT_NAME}/build-*"

    for build_dir in $SPARKFUN_BOARD_PREFIX; do
        echo "Deleting build directory: ${build_dir}"
        rm -rf ${build_dir}
    done
}

# Builds all SparkFun boards for the given port
# Options:
    # -n: Port name
    # -p: [Optional] Prefix for the SparkFun board directories for port (default: "SPARKFUN_")
    # -f: [Optional] Frozen manifest file to use (default: none)
    # -v: [Optional] Board variant to build (default: none)
    # -m: [Optional] User C modules to include (default: none)
function build_for_port {
    local TARGET_PORT_NAME
    local SPARKFUN_PREFIX="SPARKFUN_"
    local FROZEN_MANIFEST
    local BOARD_VARIANT
    local USER_C_MODULES

    OPTIND=1
    while getopts "n:p:f:v:m:" opt; do
        echo "Processing option: $opt with argument: $OPTARG"
        case ${opt} in
        n )
            TARGET_PORT_NAME=$OPTARG
            ;;
        p )
            SPARKFUN_PREFIX=$OPTARG
            ;;
        f )
            FROZEN_MANIFEST=$OPTARG
            ;;
        v )
            BOARD_VARIANT=$OPTARG
            ;;
        m )
            USER_C_MODULES=$OPTARG
            ;;
        esac
    done

    echo "TARGET_PORT_NAME: ${TARGET_PORT_NAME}"
    echo "SPARKFUN_PREFIX: ${SPARKFUN_PREFIX}"
    echo "FROZEN_MANIFEST: ${FROZEN_MANIFEST}"
    echo "BOARD_VARIANT: ${BOARD_VARIANT}"
    echo "USER_C_MODULES: ${USER_C_MODULES}"

    local SPARKFUN_BOARD_PREFIX="ports/${TARGET_PORT_NAME}/boards/${SPARKFUN_PREFIX}*"

    for board in $SPARKFUN_BOARD_PREFIX; do
        # If BOARD_VARIANT is set, check if the variant file exists. If not, skip this board.
        if [ -n "$BOARD_VARIANT" ] && [ ! -f "${board}/mpconfigvariant_${BOARD_VARIANT}.cmake" ]; then
            echo "Skipping $(basename $board)"
            continue
        fi
        echo "Building $(basename $board)"

        BOARD_TO_BUILD=${SPARKFUN_PREFIX}${board#$SPARKFUN_BOARD_PREFIX}
        make ${MAKEOPTS} -C ports/${TARGET_PORT_NAME} BOARD=$BOARD_TO_BUILD BOARD_VARIANT=$BOARD_VARIANT FROZEN_MANIFEST=$FROZEN_MANIFEST USER_C_MODULES=$USER_C_MODULES clean
        make ${MAKEOPTS} -C ports/${TARGET_PORT_NAME} BOARD=$BOARD_TO_BUILD BOARD_VARIANT=$BOARD_VARIANT FROZEN_MANIFEST=$FROZEN_MANIFEST USER_C_MODULES=$USER_C_MODULES submodules
        make ${MAKEOPTS} -C ports/${TARGET_PORT_NAME} BOARD=$BOARD_TO_BUILD BOARD_VARIANT=$BOARD_VARIANT FROZEN_MANIFEST=$FROZEN_MANIFEST USER_C_MODULES=$USER_C_MODULES
    done
}

# Builds all SparkFun RP2 boards
# Options:
    # See build_for_port function for options
function build_all_sparkfun_boards_rp2 {
    build_for_port -n rp2 $@
}

# Builds all SparkFun ESP32 boards
# Options:
    # See build_for_port function for options
function build_all_sparkfun_boards_esp32 {
    source esp-idf/export.sh

    build_for_port -n esp32 $@
}

# Builds all Teensy mimxrt boards
# Options:
    # See build_for_port function for options
function build_all_sparkfun_boards_mimxrt {
    build_for_port -n mimxrt -p TEENSY $@
}

# Copies all files with the given prefix from the SparkFun build directories to the output directory
# Options:
    # $1: Output directory
    # $2: Port directory
    # $3: Build prefix
    # $4: File basename
    # $5: Extension
    # $6: Prefix to put on output files
    # $7: [Optional] Convert file to hex (default: false)
function copy_all_for_prefix {
    local OUT_DIRECTORY=$1
    local PORT_DIRECTORY=$2 # The directory where the ports are located (e.g. ports/rp2)
    local BUILD_PREFIX=$3 # The prefix of the SparkFun build directories (e.g. build-SPARKFUN_)
    local FILE_BASENAME=$4 # the target base name of the file to copy from each SparkFun build directory (e.g. firmware)
    local EXTENSION=$5 # The extension of the file to copy (e.g. uf2)
    local OUTPUT_PREFIX=$6 # The prefix to put on the output files (e.g. MICROPYTHON_ or MINIMAL_MICROPYTHON_)
    local CONVERT_TO_HEX=${7:-false} # Whether to convert the file to hex (default: false)

    
    mkdir -p ${OUT_DIRECTORY}

    for file in $(find ${PORT_DIRECTORY} -wholename "*${BUILD_PREFIX}*/*${FILE_BASENAME}.${EXTENSION}"); do
        echo "Moving $file to ${OUT_DIRECTORY}"
        # First, add the check to see if we need to convert the file to hex
        if $CONVERT_TO_HEX; then
            echo "Converting $file to hex"
            # Convert the file to hex using hex using the command objcopy -O ihex <file> <output_file>
            # We need to get the output file name from the input file name
            OUTPUT_FILE=${OUT_DIRECTORY}/${OUTPUT_PREFIX}$(echo $file | sed -n "s/.*${BUILD_PREFIX}\([^/]*\)\/${FILE_BASENAME}.${EXTENSION}/\1/p").hex
            # Use objcopy to convert the file to hex and move it to the output directory (maybe unnecessary if the .hex file is already available from the build)
            objcopy -O ihex $file $OUTPUT_FILE
        else
            # Just move the file without converting it
            mv $file ${OUT_DIRECTORY}/${OUTPUT_PREFIX}$(echo $file | sed -n "s/.*${BUILD_PREFIX}\([^/]*\)\/${FILE_BASENAME}.${EXTENSION}/\1/p").${EXTENSION}
        fi
    done
}

# The esp32 has 3 different binaries that we need to put into a directory and then zip and then move to the output directory
# Options:
    # $1: Output directory
    # $2: Port directory
    # $3: Build prefix
    # $4: Prefix to put on output files
# We need to copy 
function copy_all_for_prefix_esp32 {
    local OUT_DIRECTORY=$1
    local PORT_DIRECTORY=$2 # The directory where the ports are located (e.g. ports/esp32)
    local BUILD_PREFIX=$3 # The prefix of the SparkFun build directories (e.g. build-SPARKFUN_)
    local OUTPUT_PREFIX=$4 # The prefix to put on the output files (e.g. MICROPYTHON_ or MINIMAL_MICROPYTHON_)

    mkdir -p ${OUT_DIRECTORY}

    for board in $(find ${PORT_DIRECTORY} -type d -name "${BUILD_PREFIX}*"); do
        BOARD_NAME=$(echo $board | sed -n "s/.*${BUILD_PREFIX}\([^/]*\)/\1/p")
        echo "Copying binaries for $BOARD_NAME"
        ZIP_DIR=${OUTPUT_PREFIX}${BOARD_NAME}
        mkdir -p ${ZIP_DIR}
        cp ${board}/micropython.bin ${ZIP_DIR}/micropython.bin
        cp ${board}/bootloader/bootloader.bin ${ZIP_DIR}/bootloader.bin
        cp ${board}/partition_table/partition-table.bin ${ZIP_DIR}/partition-table.bin

        echo "Zipping binaries for $BOARD_NAME"
        zip -r ${ZIP_DIR}.zip ${ZIP_DIR}
        
        echo "Moving zip file for $BOARD_NAME to ${OUT_DIRECTORY}"
        mv ${ZIP_DIR}.zip ${OUT_DIRECTORY}
    done
}

# Adds the line freeze("<DIRECTORY_WHERE_WE_DOWNLOADED_QWIIC_STUFF>") to the manifest.py for each board
# Options:
    # $1: Qwiic directory
    # $2: BOARD directory
    # $3: Board prefix
    # $4: The file to add the frozen manifest line to (e.g. mpconfigboard.cmake or mpconfigboard.mk.) Default: mpconfigboard.cmake
function add_qwiic_manifest {
    local QWIIC_DIRECTORY=$1 # The directory where the Qwiic drivers are located to be frozen
    local BOARD_DIRECTORY=$2 # The directory where the boards are located (e.g. ports/rp2/boards)
    local BOARD_PREFIX=$3 # The prefix of the SparkFun board directories (e.g. SPARKFUN_)
    local MPCONFIG_FILE="${4:-mpconfigboard.cmake}" # The file to add the frozen manifest line to (e.g. mpconfigboard.cmake or mpconfigboard.mk. )

    echo "Called add_qwiic_manifest with $QWIIC_DIRECTORY, $BOARD_DIRECTORY, $BOARD_PREFIX"

    for board in $(find ${BOARD_DIRECTORY} -type d -name "${BOARD_PREFIX}*"); do
        echo "Adding Qwiic drivers to manifest.py for $board"
        if [ ! -f ${board}/manifest.py ]; then
            echo "Creating manifest.py for $board"
            echo "include(\"\$(PORT_DIR)/boards/manifest.py\")" > ${board}/manifest.py

            # also add the necessary frozen manifest line to mpconfigboard.cmake: set(MICROPY_FROZEN_MANIFEST ${MICROPY_BOARD_DIR}/manifest.py)
            # We will use the optional MPCONFIG_FILE argument to determine if we should add this line

            if [ -n "$MPCONFIG_FILE" ]; then
                if [[ $MPCONFIG_FILE == *.mk ]]; then
                    # For TEENSY which use mpconfigboard.mk instead of mpconfigboard.cmake
                    echo "Adding frozen manifest line to mpconfigboard.mk for $board"
                    printf "\nFROZEN_MANIFEST ?= \$(BOARD_DIR)/manifest.py" >> ${board}/mpconfigboard.mk
                elif [[ $MPCONFIG_FILE == *.cmake ]]; then
                    echo "Adding frozen manifest line to mpconfigboard.cmake for $board"
                    printf "\nset(MICROPY_FROZEN_MANIFEST \"\${MICROPY_BOARD_DIR}/manifest.py\")" >> ${board}/mpconfigboard.cmake
                fi
            fi
        fi

        echo "Adding freeze line to manifest.py for $board"
        printf "\nfreeze(\"${QWIIC_DIRECTORY}\")" >> ${board}/manifest.py



        echo "Manifest.py for $board:"
        cat ${board}/manifest.py
    done
}

# Builds Red Vision firmware for RP2 boards
function build_micropython_red_vision_rp2 {
    # Set Pico SDK path to $GITHUB_WORKSPACE/micropython/lib/pico-sdk if $GITHUB_WORKSPACE is set, otherwise use the current directory
    # https://stackoverflow.com/a/246128/4783963
    SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
    if [ -n "$GITHUB_WORKSPACE" ]; then
        export PICO_SDK_PATH="$GITHUB_WORKSPACE/lib/pico-sdk"
    else
        export PICO_SDK_PATH="$SCRIPT_DIR/lib/pico-sdk"
    fi

    # Clone the Red Vision submodule
    # git submodule update --init --recursive lib/red_vision

    # Build OpenCV
    make -C lib/red_vision/micropython-opencv PLATFORM=rp2350 --no-print-directory ${MAKEOPTS}

    # Archive the examples directory
    python3 -m freezefs lib/red_vision/red_vision_examples lib/red_vision/extract_red_vision_examples.py  --on-import=extract --compress --overwrite always

    # Set CMake arguments for Pico SDK to use MicroPython-OpenCV malloc wrappers
    # and enable C++ exceptions
    export CMAKE_ARGS="-DSKIP_PICO_MALLOC=1 -DPICO_CXX_ENABLE_EXCEPTIONS=1"

    build_all_sparkfun_boards_rp2 -f "$SCRIPT_DIR/lib/red_vision/manifest.py" -v "RED_VISION" -m "$SCRIPT_DIR/lib/red_vision/micropython-opencv/micropython_opencv.cmake"

    # Unset CMake arguments to avoid affecting other builds
    unset CMAKE_ARGS
}

# Assumes that MAKEOPTS environment variable is set
# This is designed to be the user-facing function that will build all SparkFun boards
# Options: 
    # -p: Output file prefix
    # -o: Output directory
    # -q: Qwiic directory
function build_sparkfun {
    local OUTPUT_FILE_PREFIX="MICROPYTHON_"
    local OUTPUT_DIRECTORY="sparkfun_release"
    local QWIIC_DIRECTORY="qwiic_lib"

    while getopts "p:o:q:" opt; do
        case ${opt} in
        p )
            OUTPUT_FILE_PREFIX=$OPTARG
            ;;
        o )
            OUTPUT_DIRECTORY=$OPTARG
            ;;
        q )
            QWIIC_DIRECTORY=$OPTARG
            ;;
        esac
    done

    echo "OUTPUT_DIRECTORY: ${OUTPUT_DIRECTORY}"
    echo "Performing minimal SparkFun build for ESP32 and RP2"

    # Build the MicroPython cross compiler
    make ${MAKEOPTS} -C mpy-cross

    # Perform minimal build for ESP32
    build_all_sparkfun_boards_esp32

    # Perform minimal build for RP2
    build_all_sparkfun_boards_rp2

    # Perform minimal build for mimxrt
    build_all_sparkfun_boards_mimxrt

    # Copy all esp32 binary files to the output directory
    copy_all_for_prefix_esp32 ${OUTPUT_DIRECTORY} "ports/esp32" "build-SPARKFUN_" "MINIMAL_${OUTPUT_FILE_PREFIX}"

    # Copy all rp2 binary files to the output directory
    copy_all_for_prefix ${OUTPUT_DIRECTORY} "ports/rp2" "build-SPARKFUN_" "firmware" "uf2" "MINIMAL_${OUTPUT_FILE_PREFIX}"

    # Copy all mimxrt teensy binary files to the output directory
    copy_all_for_prefix ${OUTPUT_DIRECTORY} "ports/mimxrt" "build-TEENSY" "firmware" "elf" "MINIMAL_${OUTPUT_FILE_PREFIX}TEENSY_" true

    echo "Downloading Qwiic library and adding to manifest.py for SparkFun boards"
    # Perform Qwiic download 
    download_qwiic_release ${QWIIC_DIRECTORY}

    # Create the frozen (data) filesystem for micropython (for non .py files)
    # Ignore modules we don't care about the data of (or that have unnecessary files that seem like data files)
    # For now, we are doing this for only the qwiic_vl53l5cx module to cut down the size for testing
    create_frozen_data_fs ${QWIIC_DIRECTORY} "${QWIIC_DIRECTORY}/_frozen_qwiic_data.py" "qwiic_vl53l5cx"

    # Add the frozen (data) filesystem to the boot.py file for each port
    add_frozen_data_to_boot_for_port "esp32" "${QWIIC_DIRECTORY}/_frozen_qwiic_data.py"
    add_frozen_data_to_boot_for_port "rp2" "${QWIIC_DIRECTORY}/_frozen_qwiic_data.py"
    add_frozen_data_to_boot_for_port "mimxrt" "${QWIIC_DIRECTORY}/_frozen_qwiic_data.py"

    # This is an ugly way to pass the qwiic path. Should make it cleaner than a relative path...
    # Add the downloaded Qwiic drivers to the manifest.py for each esp32 board
    add_qwiic_manifest "../../../../${QWIIC_DIRECTORY}" "ports/esp32/boards" "SPARKFUN_"

    # Add the downloaded Qwiic drivers to the manifest.py for each rp2 board
    add_qwiic_manifest "../../../../${QWIIC_DIRECTORY}" "ports/rp2/boards" "SPARKFUN_"

    # Add the downloaded Qwiic drivers to the manifest.py for each mimxrt teensy board (this might not work because they might lose their 40 vs. 41 when added)
    add_qwiic_manifest "../../../../${QWIIC_DIRECTORY}" "ports/mimxrt/boards" "TEENSY40" "mpconfigboard.mk"
    add_qwiic_manifest "../../../../${QWIIC_DIRECTORY}" "ports/mimxrt/boards" "TEENSY41" "" # We don't need to add the frozen manifest line to mpconfigboard.mk for TEENSY41, it is already there
    
    echo "Performing full SparkFun build for ESP32, RP2, and mimxrt"
    
    # Perform Qwiic Build for ESP32
    build_all_sparkfun_boards_esp32

    # Perform Qwiic Build for RP2
    build_all_sparkfun_boards_rp2

    # Perform Qwiic build for mimxrt
    build_all_sparkfun_boards_mimxrt

    # Copy all esp32 binary files to the output directory
    copy_all_for_prefix_esp32 ${OUTPUT_DIRECTORY} "ports/esp32" "build-SPARKFUN_" ${OUTPUT_FILE_PREFIX}

    # Copy all rp2 binary files to the output directory
    copy_all_for_prefix ${OUTPUT_DIRECTORY} "ports/rp2" "build-SPARKFUN_" "firmware" "uf2" ${OUTPUT_FILE_PREFIX}

    # Copy all mimxrt teensy binary files to the output directory
    copy_all_for_prefix ${OUTPUT_DIRECTORY} "ports/mimxrt" "build-TEENSY" "firmware" "elf" "${OUTPUT_FILE_PREFIX}TEENSY_" true

    Remove all builds to prepare for Red Vision build
    delete_build_directories_for_port esp32
    delete_build_directories_for_port rp2
    delete_build_directories_for_port mimxrt

    # Build Red Vision
    build_micropython_red_vision_rp2

    # Copy all rp2 binary files to the output directory
    copy_all_for_prefix ${OUTPUT_DIRECTORY} "ports/rp2" "build-SPARKFUN_" "firmware" "uf2" "RED_VISION_${OUTPUT_FILE_PREFIX}"
}

