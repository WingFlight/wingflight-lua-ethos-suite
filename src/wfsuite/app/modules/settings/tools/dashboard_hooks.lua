--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 -- https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local prevConnectedState = nil
local initTime = os.clock()

return {
    onWakeup = function()
        if os.clock() - initTime < 0.25 then return end

        local currState = (wfsuite.session.isConnected and wfsuite.session.mcu_id) and true or false
        if currState ~= prevConnectedState then
            if wfsuite.app.formFields and wfsuite.app.formFields[2] and wfsuite.app.formFields[2].enable then
                wfsuite.app.formFields[2]:enable(currState)
            end
            if not currState and wfsuite.app.formNavigationFields and wfsuite.app.formNavigationFields["menu"] then
                wfsuite.app.formNavigationFields["menu"]:focus()
            end
            prevConnectedState = currState
        end
    end
}
