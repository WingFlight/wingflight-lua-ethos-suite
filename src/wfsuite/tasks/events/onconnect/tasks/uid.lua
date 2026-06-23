--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local uid = {}

local mspCallMade = false
local API_NAME = "UID"

local function clearApiEntry()
    local api = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api
    if api and type(api.clearEntry) == "function" then
        api.clearEntry(API_NAME)
    end
end

function uid.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.session.mspBusy then return end

    if (wfsuite.session.mcu_id == nil and mspCallMade == false) then

        mspCallMade = true

        local API = wfsuite.tasks.msp.api.load(API_NAME)
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        API.setCompleteHandler(function(self, buf)
            local U_ID_0 = API.readValue("U_ID_0")
            local U_ID_1 = API.readValue("U_ID_1")
            local U_ID_2 = API.readValue("U_ID_2")

            if U_ID_0 and U_ID_1 and U_ID_2 then
                local function u32_to_hex_le(u32)
                    local b1 = u32 & 0xFF
                    local b2 = (u32 >> 8) & 0xFF
                    local b3 = (u32 >> 16) & 0xFF
                    local b4 = (u32 >> 24) & 0xFF
                    return string.format("%02x%02x%02x%02x", b1, b2, b3, b4)
                end

                local uid = u32_to_hex_le(U_ID_0) .. u32_to_hex_le(U_ID_1) .. u32_to_hex_le(U_ID_2)
                if uid then 
                    wfsuite.utils.log("MCU ID: " .. uid, "info") 
                    wfsuite.utils.log("MCU ID: " .. uid, "connect")
                end
                wfsuite.session.mcu_id = uid
            end

            clearApiEntry()
        end)
        API.setErrorHandler(function() clearApiEntry() end)
        API.setUUID("onconnect-uid-read")
        API.read()
    end

end

function uid.reset()
    clearApiEntry()
    wfsuite.session.mcu_id = nil
    mspCallMade = false
end

function uid.isComplete() if wfsuite.session.mcu_id ~= nil then return true end end

return uid
