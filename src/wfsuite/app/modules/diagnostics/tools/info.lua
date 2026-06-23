--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local lcd = lcd
local system = system
local app = wfsuite.app
local tasks = wfsuite.tasks
local session = wfsuite.session

local version = wfsuite.version().version
local ethosVersion = wfsuite.config.environment.major .. "." .. wfsuite.config.environment.minor .. "." .. wfsuite.config.environment.revision
local apiVersion = session.apiVersion
local fcVersion = session.fcVersion
local rfVersion = session.rfVersion
local mspTransport = (tasks and tasks.msp and tasks.msp.protocol and tasks.msp.protocol.mspProtocol) or "-"
local closeProgressLoader = true
local simulation

local supportedMspVersion = ""
for i, v in ipairs(wfsuite.config.supportedMspApiVersion) do
    if i == 1 then
        supportedMspVersion = v
    else
        supportedMspVersion = supportedMspVersion .. "," .. v
    end
end

if system.getVersion().simulation == true then
    simulation = "ON"
else
    simulation = "OFF"
end

local displayType = 0
local disableType = false
local displayPos
local w, h = lcd.getWindowSize()
local buttonW = 100
local buttonWs = buttonW - (buttonW * 20) / 100
local x = w - 15

displayPos = {x = x - buttonW - buttonWs - 5 - buttonWs, y = app.radio.linePaddingTop, w = 300, h = app.radio.navbuttonHeight}

local apidata = {
    api = {[1] = nil},
    formdata = {
        labels = {},
        fields = {
            {t = "@i18n(app.modules.info.version)@", value = version, type = displayType, disable = disableType, position = displayPos}, {t = "@i18n(app.modules.info.ethos_version)@", value = ethosVersion, type = displayType, disable = disableType, position = displayPos}, {t = "@i18n(app.modules.info.rf_version)@", value = rfVersion, type = displayType, disable = disableType, position = displayPos},
            {t = "@i18n(app.modules.info.fc_version)@", value = fcVersion, type = displayType, disable = disableType, position = displayPos}, {t = "@i18n(app.modules.info.msp_version)@", value = apiVersion, type = displayType, disable = disableType, position = displayPos}, {t = "@i18n(app.modules.info.msp_transport)@", value = string.upper(mspTransport), type = displayType, disable = disableType, position = displayPos},
            {t = "@i18n(app.modules.info.supported_versions)@", value = supportedMspVersion, type = displayType, disable = disableType, position = displayPos}, {t = "@i18n(app.modules.info.simulation)@", value = simulation, type = displayType, disable = disableType, position = displayPos}
        }
    }
}

local function wakeup()
    if closeProgressLoader == false then
        app.triggers.closeProgressLoader = true
        closeProgressLoader = true
    end
end

local function event(widget, category, value, x, y)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})
end

local function onNavMenu()
    pageRuntime.openMenuContext()
    return true
end

return {apidata = apidata, reboot = false, eepromWrite = false, minBytes = 0, wakeup = wakeup, refreshswitch = false, simulatorResponse = {}, onNavMenu = onNavMenu, event = event, navButtons = {menu = true, save = false, reload = false, tool = false, help = false}, API = {}}
