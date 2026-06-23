--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local core = wfsuite.tasks.msp.getApiCore()

local API_NAME = "REBOOT"

local function validateWrite()
    local armed = wfsuite.utils and wfsuite.utils.resolveArmedState and wfsuite.utils.resolveArmedState()
    if armed then
        if wfsuite.utils and wfsuite.utils.log then
            wfsuite.utils.log("REBOOT API blocked while armed", "info")
        end
        if wfsuite.utils and wfsuite.utils.signalArmedWriteBlocked then
            wfsuite.utils.signalArmedWriteBlocked()
        end
        return false, "armed_blocked"
    end
    return true
end

local function buildWritePayload(payloadData)
    local rebootMode = payloadData.rebootMode
    if rebootMode == nil then rebootMode = 0 end
    return {rebootMode}
end

return core.createWriteOnlyAPI({
    name = API_NAME,
    writeCmd = 68,
    buildWritePayload = buildWritePayload,
    validateWrite = validateWrite,
    writeUuidFallback = true,
    initialRebuildOnWrite = false
})
