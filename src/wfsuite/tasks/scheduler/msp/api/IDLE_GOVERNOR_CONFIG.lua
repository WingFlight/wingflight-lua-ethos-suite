--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "IDLE_GOVERNOR_CONFIG"
local MSP_API_CMD_READ = 0x5F01
local MSP_API_CMD_WRITE = 0x5F02

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos
local FIELD_SPEC = {
    {"idle_governor_mode", "U8", nil, nil, nil, nil, nil, nil, nil, nil, {"@i18n(api.IDLE_GOVERNOR_CONFIG.tbl_mode_off)@", "@i18n(api.IDLE_GOVERNOR_CONFIG.tbl_mode_rpm)@", "@i18n(api.IDLE_GOVERNOR_CONFIG.tbl_mode_throttle)@"}, -1},
    {"idle_governor_rpm", "U16", 0, 50000, 0, "rpm"},
    {"idle_governor_gain", "U16", 0, 20000, 20},
    {"idle_governor_i_gain", "U16", 0, 200, 30},
    {"idle_governor_throttle", "U8", 0, 100, 15, "%"},
    {"idle_governor_handover", "U8", 0, 100, 10, "%"},
    {"idle_governor_ceiling", "U8", 0, 100, 30, "%"}
}

local SIM_RESPONSE = core.simResponse({
    0,      -- idle_governor_mode
    0, 0,   -- idle_governor_rpm
    20, 0,  -- idle_governor_gain
    30, 0,  -- idle_governor_i_gain
    15,     -- idle_governor_throttle
    10,     -- idle_governor_handover
    30      -- idle_governor_ceiling
})

return core.createConfigAPI({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    fields = FIELD_SPEC,
    simulatorResponseRead = SIM_RESPONSE,
    writeUuidFallback = true,
    initialRebuildOnWrite = true,
    exports = {
        simulatorResponse = SIM_RESPONSE
    }
})
