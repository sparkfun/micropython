freeze("$(PORT_DIR)/modules/$(MCU_CORE)")
include("$(MPY_DIR)/extmod/asyncio")
require("dht")
require("neopixel")
require("onewire")
require("bundle-networking")
