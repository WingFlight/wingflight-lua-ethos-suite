--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

-- Named WING_GOVERNOR_CONFIG (not bare GOVERNOR_CONFIG) because that name is already used by the
-- legacy Rotorflight heli main-rotor governor API elsewhere in this suite -- distinct feature,
-- distinct MSP command, just an unfortunate name clash to avoid.
local API_NAME = "WING_GOVERNOR_CONFIG"
local MSP_API_CMD_READ = 0x5F01
local MSP_API_CMD_WRITE = 0x5F02

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos
local FIELD_SPEC = {
    {"governor_mode", "U8", nil, nil, nil, nil, nil, nil, nil, nil, {"@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_off)@", "@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_rpm)@", "@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_throttle)@", "@i18n(api.WING_GOVERNOR_CONFIG.tbl_mode_rpm_range)@"}, -1},
    {"governor_rpm", "U16", 0, 50000, 0, "rpm"},
    {"governor_gain", "U16", 0, 20000, 20},
    {"governor_i_gain", "U16", 0, 200, 30},
    {"governor_throttle", "U8", 0, 100, 15, "%"},
    {"governor_handover", "U8", 0, 100, 10, "%"},
    {"governor_ceiling", "U8", 0, 100, 30, "%"},
    {"governor_rpm_min", "U16", 0, 50000, 0, "rpm"},
    {"governor_rpm_max", "U16", 0, 50000, 0, "rpm"}
}

local SIM_RESPONSE = core.simResponse({
    0,      -- governor_mode
    0, 0,   -- governor_rpm
    20, 0,  -- governor_gain
    30, 0,  -- governor_i_gain
    15,     -- governor_throttle
    10,     -- governor_handover
    30,     -- governor_ceiling
    0, 0,   -- governor_rpm_min
    0, 0    -- governor_rpm_max
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
