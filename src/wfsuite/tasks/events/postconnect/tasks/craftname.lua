--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local craftname = {}

local mspCallMade = false
local API_NAME = "NAME"

local function clearApiEntry()
    local api = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api
    if api and type(api.clearEntry) == "function" then
        api.clearEntry(API_NAME)
    end
end

function craftname.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.session.mspBusy then return end

    if (wfsuite.session.craftName == nil) and (mspCallMade == false) then
        mspCallMade = true
        local API = wfsuite.tasks.msp.api.load(API_NAME)
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        API.setCompleteHandler(function(self, buf)
            wfsuite.session.craftName = API.readValue("name")
            if wfsuite.preferences.general.syncname == true and model.name and wfsuite.session.craftName ~= nil then
                if not wfsuite.session.originalModelName then
                    wfsuite.session.originalModelName = model.name()
                end
                wfsuite.utils.log("Setting model name to: " .. wfsuite.session.craftName, "info")
                model.name(wfsuite.session.craftName)
                wfsuite.session.dashboardInvalidatePending = true
            end
            if wfsuite.session.craftName and wfsuite.session.craftName ~= "" then
                wfsuite.utils.log("Craft name: " .. wfsuite.session.craftName, "info")
                wfsuite.utils.log("Craft name: " .. wfsuite.session.craftName, "connect")
            else
                wfsuite.session.craftName = model.name()
            end
            clearApiEntry()
        end)
        API.setErrorHandler(function() clearApiEntry() end)
        API.setUUID("postconnect-craftname-read")
        API.read()
    end

end

function craftname.reset()
    clearApiEntry()
    wfsuite.session.craftName = nil
    mspCallMade = false
end

function craftname.isComplete() if wfsuite.session.craftName ~= nil then return true end end

return craftname
