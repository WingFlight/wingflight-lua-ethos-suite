--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 -- https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local MENU_ID = {PWM = 1, BUS = 2}

local prevConnectedState = nil
local fieldFocusSet = false
local chainInFlight = false

local function requestServoInfoChain()
    if chainInFlight then return end
    if not (wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.helpers) then return end

    local msp = wfsuite.tasks.msp
    local session = wfsuite.session

    if session.servoCount == nil then
        chainInFlight = true
        msp.helpers.servoCount(function(servoCount)
            wfsuite.utils.log("Received servo count: " .. tostring(servoCount), "info")
            chainInFlight = false
            requestServoInfoChain()
        end, wfsuite.app and wfsuite.app.lastScript)
        return
    end

    if session.servoOverride == nil then
        chainInFlight = true
        msp.helpers.servoOverride(function(servoOverride)
            wfsuite.utils.log("Received servo override: " .. tostring(servoOverride), "info")
            chainInFlight = false
            requestServoInfoChain()
        end, wfsuite.app and wfsuite.app.lastScript)
        return
    end

    if session.tailMode == nil or session.swashMode == nil then
        chainInFlight = true
        msp.helpers.mixerConfig(function(tailMode, swashMode)
            wfsuite.utils.log("Received tail mode: " .. tostring(tailMode), "info")
            wfsuite.utils.log("Received swash mode: " .. tostring(swashMode), "info")
            chainInFlight = false
            requestServoInfoChain()
        end, wfsuite.app and wfsuite.app.lastScript)
        return
    end

    if session.servoBusEnabled == nil then
        chainInFlight = true
        msp.helpers.servoBusEnabled(function(servoBusEnabled)
            wfsuite.utils.log("Received servo bus enabled: " .. tostring(servoBusEnabled), "info")
            chainInFlight = false
            requestServoInfoChain()
        end, wfsuite.app and wfsuite.app.lastScript)
        return
    end
end

return {
    onOpenPost = function()
        fieldFocusSet = false
        chainInFlight = false
        if wfsuite.app.formFields then
            for i, v in pairs(wfsuite.app.formFields) do
                if v and v.enable then v:enable(false) end
            end
        end
    end,
    onWakeup = function()
        requestServoInfoChain()

        if not fieldFocusSet and
            wfsuite.session.servoCount ~= nil and
            wfsuite.session.servoOverride ~= nil and
            wfsuite.session.tailMode ~= nil and
            wfsuite.session.swashMode ~= nil and
            wfsuite.session.servoBusEnabled ~= nil then

            if wfsuite.app.formFields[MENU_ID.PWM] then
                wfsuite.app.formFields[MENU_ID.PWM]:enable(true)
                if wfsuite.preferences.menulastselected["servos_type"] == MENU_ID.PWM then
                    wfsuite.app.formFields[MENU_ID.PWM]:focus()
                end
            end

            if wfsuite.utils.apiVersionCompare(">", {22, 0, 0}) and
                wfsuite.app.formFields[MENU_ID.BUS] and
                wfsuite.session.servoBusEnabled == true then
                wfsuite.app.formFields[MENU_ID.BUS]:enable(true)
                if wfsuite.preferences.menulastselected["servos_type"] == MENU_ID.BUS then
                    wfsuite.app.formFields[MENU_ID.BUS]:focus()
                end
            end

            wfsuite.app.triggers.closeProgressLoader = true
            fieldFocusSet = true
        end

        local currState = (wfsuite.session.isConnected and wfsuite.session.mcu_id) and true or false
        if currState ~= prevConnectedState then
            if not currState and wfsuite.app.formNavigationFields and wfsuite.app.formNavigationFields["menu"] then
                wfsuite.app.formNavigationFields["menu"]:focus()
            end
            prevConnectedState = currState
        end
    end
}
