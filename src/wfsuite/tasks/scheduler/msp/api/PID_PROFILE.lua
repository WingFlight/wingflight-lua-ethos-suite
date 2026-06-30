--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "PID_PROFILE"
local MSP_API_CMD_READ = 94
local MSP_API_CMD_WRITE = 95

local TBL_OFF_ON = {[0] = "@i18n(api.PID_PROFILE.tbl_off)@", "@i18n(api.PID_PROFILE.tbl_on)@"}
local TBL_ITERM_RELAX = {
    [0] = "@i18n(api.PID_PROFILE.tbl_off)@",
    "@i18n(api.PID_PROFILE.tbl_rp)@",
    "@i18n(api.PID_PROFILE.tbl_rpy)@"
}

-- Tuple layout:
--   field, type, min, max, default, unit,
--   decimals, scale, step, mult, table, tableIdxInc, mandatory, byteorder, tableEthos
local FIELD_SPEC = {
    {"pid_mode", "U8"},
    {"unused_error_decay_time_ground", "U8"}, -- heli-only, removed
    {"iterm_decay_time", "U8", 0, 250, 0.6, "s", 1, 10},
    {"unused_error_decay_time_yaw", "U8"}, -- heli-only, removed
    {"iterm_decay_limit", "U8", 0, 60, 35, "°"},
    {"unused_error_decay_limit_yaw", "U8"}, -- heli-only, removed
    {"error_rotation", "U8", 0, 1, nil, nil, nil, nil, nil, nil, TBL_OFF_ON},
    {"error_limit_0", "U8", 0, 180, 45, "°"},
    {"error_limit_1", "U8", 0, 180, 45, "°"},
    {"error_limit_2", "U8", 0, 180, 60, "°"},
    {"gyro_cutoff_0", "U8", 0, 250, 50},
    {"gyro_cutoff_1", "U8", 0, 250, 50},
    {"gyro_cutoff_2", "U8", 0, 250, 100},
    {"dterm_cutoff_0", "U8", 0, 250, 15},
    {"dterm_cutoff_1", "U8", 0, 250, 15},
    {"dterm_cutoff_2", "U8", 0, 250, 20},
    {"iterm_relax_type", "U8", 0, 2, nil, nil, nil, nil, nil, nil, TBL_ITERM_RELAX},
    {"iterm_relax_cutoff_0", "U8", 1, 100, 10},
    {"iterm_relax_cutoff_1", "U8", 1, 100, 10},
    {"iterm_relax_cutoff_2", "U8", 1, 100, 10},
    {"unused_yaw_cw_stop_gain", "U8"}, -- heli-only, removed
    {"unused_yaw_ccw_stop_gain", "U8"}, -- heli-only, removed
    {"unused_yaw_precomp_cutoff", "U8"}, -- heli-only, removed
    {"unused_yaw_cyclic_ff_gain", "U8"}, -- heli-only, removed
    {"unused_yaw_collective_ff_gain", "U8"}, -- heli-only, removed
    {"unused_yaw_collective_dynamic_gain", "U8"}, -- heli-only, removed
    {"unused_yaw_collective_dynamic_decay", "U8"}, -- heli-only, removed
    {"unused_pitch_collective_ff_gain", "U8"}, -- heli-only, removed
    {"angle_level_strength", "U8", 0, 200, 40},
    {"angle_level_limit", "U8", 10, 90, 55, "°"},
    {"horizon_level_strength", "U8", 0, 200, 40},
    {"trainer_gain", "U8", 25, 255, 75},
    {"trainer_angle_limit", "U8", 10, 80, 20, "°"},
    {"unused_cyclic_cross_coupling_gain", "U8"}, -- heli-only, removed
    {"unused_cyclic_cross_coupling_ratio", "U8"}, -- heli-only, removed
    {"unused_cyclic_cross_coupling_cutoff", "U8"}, -- heli-only, removed
    {"atthold_gain", "U8", 0, 200, 40},
    {"atthold_deadband", "U8", 0, 100, 5, "%"},
    {"bterm_cutoff_0", "U8", 0, 250, 15},
    {"bterm_cutoff_1", "U8", 0, 250, 15},
    {"bterm_cutoff_2", "U8", 0, 250, 20},
    {"unused_yaw_inertia_precomp_gain", "U8"}, -- heli-only, removed
    {"unused_yaw_inertia_precomp_cutoff", "U8"}, -- heli-only, removed
    {"fw_tpa_breakpoint", "U8", 0, 100, 100, "%"},
    {"fw_tpa_rate", "U8", 0, 100, 0, "%"},
    {"master_gain", "U8", 25, 200, 100, "%"}
}

local SIM_RESPONSE = core.simResponse({
    1,    -- pid_mode
    0,    -- unused_error_decay_time_ground
    6,    -- iterm_decay_time
    0,    -- unused_error_decay_time_yaw
    35,   -- iterm_decay_limit
    0,    -- unused_error_decay_limit_yaw
    1,    -- error_rotation
    45,   -- error_limit_0
    45,   -- error_limit_1
    60,   -- error_limit_2
    50,   -- gyro_cutoff_0
    50,   -- gyro_cutoff_1
    100,  -- gyro_cutoff_2
    15,   -- dterm_cutoff_0
    15,   -- dterm_cutoff_1
    20,   -- dterm_cutoff_2
    2,    -- iterm_relax_type
    10,   -- iterm_relax_cutoff_0
    10,   -- iterm_relax_cutoff_1
    15,   -- iterm_relax_cutoff_2
    0,    -- unused_yaw_cw_stop_gain
    0,    -- unused_yaw_ccw_stop_gain
    0,    -- unused_yaw_precomp_cutoff
    0,    -- unused_yaw_cyclic_ff_gain
    0,    -- unused_yaw_collective_ff_gain
    0,    -- unused_yaw_collective_dynamic_gain
    0,    -- unused_yaw_collective_dynamic_decay
    0,    -- unused_pitch_collective_ff_gain
    40,   -- angle_level_strength
    55,   -- angle_level_limit
    0,    -- horizon_level_strength
    75,   -- trainer_gain
    20,   -- trainer_angle_limit
    0,    -- unused_cyclic_cross_coupling_gain
    0,    -- unused_cyclic_cross_coupling_ratio
    0,    -- unused_cyclic_cross_coupling_cutoff
    40,   -- atthold_gain
    5,    -- atthold_deadband
    15,   -- bterm_cutoff_0
    15,   -- bterm_cutoff_1
    20,   -- bterm_cutoff_2
    0,    -- unused_yaw_inertia_precomp_gain
    0,    -- unused_yaw_inertia_precomp_cutoff
    100,  -- fw_tpa_breakpoint
    0,    -- fw_tpa_rate
    100   -- master_gain
})

return core.createConfigAPI({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    fields = FIELD_SPEC,
    simulatorResponseRead = SIM_RESPONSE,
    writeUuidFallback = true
})
