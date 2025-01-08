// Board and hardware specific configuration
#define MICROPY_HW_BOARD_NAME          "SparkFun IoT Node LoRaWAN"
#define MICROPY_HW_FLASH_STORAGE_BYTES (14 * 1024 * 1024)

#define MICROPY_HW_USB_VID (0x1B4F)
#define MICROPY_HW_USB_PID (0x0044)

#define MICROPY_HW_I2C0_SDA  (20)
#define MICROPY_HW_I2C0_SCL  (21)

#define MICROPY_HW_I2C1_SDA  (6)
#define MICROPY_HW_I2C1_SCL  (7)

#define MICROPY_HW_SPI0_SCK  (2)
#define MICROPY_HW_SPI0_MOSI (3)
#define MICROPY_HW_SPI0_MISO (4)

#define MICROPY_HW_SPI1_SCK  (14)
#define MICROPY_HW_SPI1_MOSI (15)
#define MICROPY_HW_SPI1_MISO (12)

#define MICROPY_HW_UART0_TX (18)
#define MICROPY_HW_UART0_RX (19)
#define MICROPY_HW_UART0_CTS (2)
#define MICROPY_HW_UART0_RTS (3)

#define MICROPY_HW_UART1_TX (4)
#define MICROPY_HW_UART1_RX (5)
#define MICROPY_HW_UART1_CTS (6)
#define MICROPY_HW_UART1_RTS (7)

#define MICROPY_HW_PSRAM_CS_PIN (0)
#define MICROPY_HW_ENABLE_PSRAM (1)
#define MICROPY_GC_SPLIT_HEAP (1)
#define MICROPY_ALLOC_GC_STACK_SIZE (1024)
