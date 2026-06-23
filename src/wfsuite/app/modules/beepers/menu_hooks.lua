--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 -- https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local prevConnectedState = nil
local initTime = os.clock()
local prereqRequested = false
local prereqReady = false
local beepersConfigReady = false
local beepersFocused = false
local beepersConfigParsed = {}

local function copyTable(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = type(v) == "table" and copyTable(v) or v end
    return dst
end

local function setButtonsEnabled(enabled)
    if not wfsuite.app.formFields then return end
    for i, f in pairs(wfsuite.app.formFields) do
        if type(i) == "number" and f and f.enable then f:enable(enabled) end
    end
end

local function updateMenuAvailability()
    local connected = (wfsuite.session.isConnected and wfsuite.session.mcu_id) and true or false
    local canOpen = prereqReady and connected

    setButtonsEnabled(canOpen)

    if canOpen and not beepersFocused then
        beepersFocused = true
        local idx = tonumber(wfsuite.preferences.menulastselected["beepers"]) or 1
        local btn = wfsuite.app.formFields and wfsuite.app.formFields[idx] or nil
        if btn and btn.focus then btn:focus() end
    end
end

local function onPrereqDone()
    prereqReady = beepersConfigReady
    if prereqReady then
        wfsuite.session.beepers = {
            config = copyTable(beepersConfigParsed or {}),
            ready = true
        }
        updateMenuAvailability()
        wfsuite.app.triggers.closeProgressLoader = true
    end
end

local function requestPrereqs()
    if prereqRequested then return end
    prereqRequested = true
    prereqReady = false
    beepersConfigReady = false
    beepersFocused = false
    beepersConfigParsed = {}

    local API = wfsuite.tasks.msp.api.loadPage("BEEPER_CONFIG")
    API.setUUID("beepers-menu-config")
    API.setCompleteHandler(function()
        local d = API.data()
        beepersConfigParsed = copyTable((d and d.parsed) or {})
        beepersConfigReady = true
        onPrereqDone()
    end)
    API.setErrorHandler(function()
        beepersConfigParsed = {}
        beepersConfigReady = true
        onPrereqDone()
    end)
    API.read()
end

return {
    onOpenPost = function()
        prereqRequested = false
        setButtonsEnabled(false)
        requestPrereqs()
    end,
    onWakeup = function()
        if os.clock() - initTime < 0.25 then return end

        if not prereqRequested then requestPrereqs() end
        updateMenuAvailability()

        local currState = (wfsuite.session.isConnected and wfsuite.session.mcu_id) and true or false
        if currState ~= prevConnectedState then
            if not currState and wfsuite.app.formNavigationFields and wfsuite.app.formNavigationFields["menu"] then
                wfsuite.app.formNavigationFields["menu"]:focus()
            end
            prevConnectedState = currState
        end
    end
}
