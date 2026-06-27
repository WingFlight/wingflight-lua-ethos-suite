--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "PID_TUNING"
local MSP_API_CMD_READ = 112
local MSP_API_CMD_WRITE = 202

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos
local FIELD_SPEC = {
    {"pid_0_P", "U16", 0, 1000, 50},
    {"pid_0_I", "U16", 0, 1000, 20},
    {"pid_0_D", "U16", 0, 1000, 0},
    {"pid_0_F", "U16", 0, 1000, 100},

    {"pid_1_P", "U16", 0, 1000, 50},
    {"pid_1_I", "U16", 0, 1000, 20},
    {"pid_1_D", "U16", 0, 1000, 0},
    {"pid_1_F", "U16", 0, 1000, 100},

    {"pid_2_P", "U16", 0, 1000, 80},
    {"pid_2_I", "U16", 0, 1000, 25},
    {"pid_2_D", "U16", 0, 1000, 0},
    {"pid_2_F", "U16", 0, 1000, 100},

    {"pid_0_B", "U16", 0, 1000, 0},
    {"pid_1_B", "U16", 0, 1000, 0},
    {"pid_2_B", "U16", 0, 1000, 0},

    {"unused_pid_0_O", "U16"}, -- heli-only HSI offset term, removed
    {"unused_pid_1_O", "U16"} -- heli-only HSI offset term, removed
}

local SIM_RESPONSE = core.simResponse({
    50, 0,   -- pid_0_P
    20, 0,   -- pid_0_I
    0, 0,    -- pid_0_D
    100, 0,  -- pid_0_F

    50, 0,   -- pid_1_P
    20, 0,   -- pid_1_I
    0, 0,    -- pid_1_D
    100, 0,  -- pid_1_F

    80, 0,   -- pid_2_P
    25, 0,   -- pid_2_I
    0, 0,    -- pid_2_D
    100, 0,  -- pid_2_F

    0, 0,    -- pid_0_B
    0, 0,    -- pid_1_B
    0, 0,    -- pid_2_B

    0, 0,    -- unused_pid_0_O
    0, 0     -- unused_pid_1_O
})

return core.createConfigAPI({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    fields = FIELD_SPEC,
    simulatorResponseRead = SIM_RESPONSE,
    writeUuidFallback = true
})
