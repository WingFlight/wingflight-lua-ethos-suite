--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

return core.createWriteOnlyAPI({
    name = "SET_SERVO_CENTER",
    writeCmd = 213,
    fields = {
        {"index", "U8"},
        {"mid", "U16"}
    },
    simulatorResponseWrite = {},
    writeUuidFallback = true
})
