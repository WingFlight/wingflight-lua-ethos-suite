--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 -- https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local prevConnectedState = nil
local initTime = os.clock()
local focused = false

return {
    onWakeup = function()
        if os.clock() - initTime < 0.25 then return end

        if wfsuite.session.governorMode == nil then
            if wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.helpers then
                wfsuite.tasks.msp.helpers.governorMode(function(governorMode)
                    wfsuite.utils.log("Received governor mode: " .. tostring(governorMode), "info")
                end, wfsuite.app and wfsuite.app.lastScript)
            end
            return
        end

        local enabled = wfsuite.session.governorMode ~= 0
        if wfsuite.app.formFields then
            for i, v in pairs(wfsuite.app.formFields) do
                if v and v.enable then v:enable(enabled) end
            end
        end

        if enabled and not focused then
            focused = true
            local idx = tonumber(wfsuite.preferences.menulastselected["profile_governor"]) or 1
            local btn = wfsuite.app.formFields and wfsuite.app.formFields[idx] or nil
            if btn and btn.focus then btn:focus() end
        end

        wfsuite.app.triggers.closeProgressLoader = true

        local currState = (wfsuite.session.isConnected and wfsuite.session.mcu_id) and true or false
        if currState ~= prevConnectedState then
            if not currState and wfsuite.app.formNavigationFields and wfsuite.app.formNavigationFields["menu"] then
                wfsuite.app.formNavigationFields["menu"]:focus()
            end
            prevConnectedState = currState
        end
    end
}
