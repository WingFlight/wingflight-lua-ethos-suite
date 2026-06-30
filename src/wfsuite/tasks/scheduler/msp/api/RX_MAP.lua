--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "RX_MAP"
local MSP_API_CMD_READ = 64
local MSP_API_CMD_WRITE = 65

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos
local FIELD_SPEC = {
    {"aileron", "U8"},
    {"elevator", "U8"},
    {"rudder", "U8"},
    {"throttle", "U8"},
    {"aux1", "U8"},
    {"aux2", "U8"},
    {"aux3", "U8"},
    {"aux4", "U8"}
}

local SIM_RESPONSE = core.simResponse({
    0, -- aileron  (AETR1234 default)
    1, -- elevator
    3, -- rudder
    2, -- throttle
    4, -- aux1
    5, -- aux2
    6, -- aux3
    7  -- aux4
})

return core.createConfigAPI({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    fields = FIELD_SPEC,
    simulatorResponseRead = SIM_RESPONSE,
    exports = {
        simulatorResponse = SIM_RESPONSE
    }
})
