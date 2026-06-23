--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local clocksync = {}
local API_NAME = "RTC"

local function clearApiEntry()
    local api = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api
    if api and type(api.clearEntry) == "function" then
        api.clearEntry(API_NAME)
    end
end

function clocksync.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.session.mspBusy then return end

    if wfsuite.session.clockSet == nil then

        local API = wfsuite.tasks.msp.api.load(API_NAME, 1)
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        API.setCompleteHandler(function(self, buf)
            wfsuite.session.clockSet = true
            wfsuite.utils.log("Sync clock: " .. os.date("%c"), "info")
            wfsuite.utils.log("Sync clock: " .. os.date("%c"), "connect")
            clearApiEntry()
        end)
        API.setErrorHandler(function() clearApiEntry() end)
        API.setUUID("postconnect-clocksync")
        API.setValue("seconds", os.time())
        API.setValue("milliseconds", 0)
        API.write()
    end

end

function clocksync.reset()
    clearApiEntry()
    wfsuite.session.clockSet = nil
end

function clocksync.isComplete() if wfsuite.session.clockSet ~= nil then return true end end

return clocksync
