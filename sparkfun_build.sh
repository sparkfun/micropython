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

# Builds all SparkFun boards for the given port
# Options:
    # $1: Port name
function build_for_port {
    local TARGET_PORT_NAME=$1
    local SPARKFUN_PREFIX="SPARKFUN_"
    local SPARKFUN_BOARD_PREFIX="ports/${TARGET_PORT_NAME}/boards/${SPARKFUN_PREFIX}*"

    for board in $SPARKFUN_BOARD_PREFIX; do
        BOARD_TO_BUILD=${SPARKFUN_PREFIX}${board#$SPARKFUN_BOARD_PREFIX}
        make ${MAKEOPTS} -C ports/${TARGET_PORT_NAME} BOARD=$BOARD_TO_BUILD clean
        make ${MAKEOPTS} -C ports/${TARGET_PORT_NAME} BOARD=$BOARD_TO_BUILD submodules
        make ${MAKEOPTS} -C ports/${TARGET_PORT_NAME} BOARD=$BOARD_TO_BUILD
    done
}

# Builds all SparkFun RP2 boards (might break into a build_for_port function that we pass the port to later if ESP32 takes the exact same build coms)
# Options:
    # $1: Whether to build the cross compiler
function build_all_sparkfun_boards_rp2 {
    if $1; then
        make ${MAKEOPTS} -C mpy-cross
    fi

    build_for_port "rp2"
}

# Builds all SparkFun ESP32 boards
# Options:
    # $1: Whether to build the cross compiler
function build_all_sparkfun_boards_esp32 {
    source esp-idf/export.sh

    if $1; then
        make ${MAKEOPTS} -C mpy-cross
    fi

    build_for_port "esp32"
}

# Copies all files with the given prefix from the SparkFun build directories to the output directory
# Options:
    # $1: Output directory
    # $2: Port directory
    # $3: Build prefix
    # $4: File basename
    # $5: Extension
    # $6: Prefix to put on output files
function copy_all_for_prefix {
    local OUT_DIRECTORY=$1
    local PORT_DIRECTORY=$2 # The directory where the ports are located (e.g. ports/rp2)
    local BUILD_PREFIX=$3 # The prefix of the SparkFun build directories (e.g. build-SPARKFUN_)
    local FILE_BASENAME=$4 # the target base name of the file to copy from each SparkFun build directory (e.g. firmware)
    local EXTENSION=$5 # The extension of the file to copy (e.g. uf2)
    local OUTPUT_PREFIX=$6 # The prefix to put on the output files (e.g. MICROPYTHON_ or MINIMAL_MICROPYTHON_)
    
    mkdir -p ${OUT_DIRECTORY}

    for file in $(find ${PORT_DIRECTORY} -wholename "*${BUILD_PREFIX}*/*${FILE_BASENAME}.${EXTENSION}"); do
        echo "Moving $file to ${OUT_DIRECTORY}"
        mv $file ${OUT_DIRECTORY}/${OUTPUT_PREFIX}$(echo $file | sed -n "s/.*${BUILD_PREFIX}\([^/]*\)\/${FILE_BASENAME}.${EXTENSION}/\1/p").${EXTENSION}
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
function add_qwiic_manifest {
    local QWIIC_DIRECTORY=$1 # The directory where the Qwiic drivers are located to be frozen
    local BOARD_DIRECTORY=$2 # The directory where the boards are located (e.g. ports/rp2/boards)
    local BOARD_PREFIX=$3 # The prefix of the SparkFun board directories (e.g. SPARKFUN_)

    for board in $(find ${BOARD_DIRECTORY} -type d -name "${BOARD_PREFIX}*"); do
        if [ ! -f ${board}/manifest.py ]; then
            echo "Creating manifest.py for $board"
            echo "include(\"${BOARD_DIRECTORY}/manifest.py\")" > ${board}/manifest.py
        fi

        echo "Adding freeze line to manifest.py for $board"
        printf "\nfreeze(\"${QWIIC_DIRECTORY}\")" >> ${board}/manifest.py

        echo "Manifest.py for $board:"
        cat ${board}/manifest.py
    done
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

    # Perform minimal build for ESP32
    build_all_sparkfun_boards_esp32 true

    # Perform minimal build for RP2
    build_all_sparkfun_boards_rp2 false

    # Copy all esp32 binary files to the output directory
    copy_all_for_prefix_esp32 ${OUTPUT_DIRECTORY} "ports/esp32" "build-SPARKFUN_" "MINIMAL_${OUTPUT_FILE_PREFIX}"

    # Copy all rp2 binary files to the output directory
    copy_all_for_prefix ${OUTPUT_DIRECTORY} "ports/rp2" "build-SPARKFUN_" "firmware" "uf2" "MINIMAL_${OUTPUT_FILE_PREFIX}"

    echo "Downloading Qwiic library and adding to manifest.py for SparkFun boards"
    # Perform Qwiic download 
    download_qwiic_release ${QWIIC_DIRECTORY}

    # This is an ugly way to pass the qwiic path. Should make it cleaner than a relative path...
    # Add the downloaded Qwiic drivers to the manifest.py for each esp32 board
    add_qwiic_manifest "../../../../${QWIIC_DIRECTORY}" "ports/esp32/boards" "SPARKFUN_"

    # Add the downloaded Qwiic drivers to the manifest.py for each rp2 board
    add_qwiic_manifest "../../../../${QWIIC_DIRECTORY}" "ports/rp2/boards" "SPARKFUN_"
    
    echo "Performing full SparkFun build for ESP32 and RP2"
    
    # Perform Qwiic Build for ESP32
    build_all_sparkfun_boards_esp32 false

    # Perform Qwiic Build for RP2
    build_all_sparkfun_boards_rp2 false

    # Copy all esp32 binary files to the output directory
    copy_all_for_prefix_esp32 ${OUTPUT_DIRECTORY} "ports/esp32" "build-SPARKFUN_" ${OUTPUT_FILE_PREFIX}

    # Copy all rp2 binary files to the output directory
    copy_all_for_prefix ${OUTPUT_DIRECTORY} "ports/rp2" "build-SPARKFUN_" "firmware" "uf2" ${OUTPUT_FILE_PREFIX}
}
