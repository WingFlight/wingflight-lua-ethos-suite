--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "MIXER_CONFIG"
local MSP_API_CMD_READ = 42
local MSP_API_CMD_WRITE = 43

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos
local FIELD_SPEC = {
    {"tail_rotor_mode", "U8", nil, nil, nil, nil, nil, nil, nil, nil, {"@i18n(api.MIXER_CONFIG.tbl_tail_variable_pitch)@", "@i18n(api.MIXER_CONFIG.tbl_tail_motororized_tail)@", "@i18n(api.MIXER_CONFIG.tbl_tail_bidirectional)@"}, -1},
}

local SIM_RESPONSE = core.simResponse({
    0,        -- tail_rotor_mode
})

return core.createConfigAPI({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    fields = FIELD_SPEC,
    simulatorResponseRead = SIM_RESPONSE,
    writeUuidFallback = true,
    exports = {
        simulatorResponse = SIM_RESPONSE
    }
})
