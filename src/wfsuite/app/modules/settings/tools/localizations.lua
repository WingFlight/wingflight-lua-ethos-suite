--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local enableWakeup = false

local config = {}

local function openPage(opts)

    local pageIdx = opts.idx
    local title = opts.title
    local script = opts.script
    enableWakeup = true
    if not wfsuite.app.navButtons then wfsuite.app.navButtons = {} end
    wfsuite.app.triggers.closeProgressLoader = true
    form.clear()

    wfsuite.app.lastIdx = pageIdx
    wfsuite.app.lastTitle = title
    wfsuite.app.lastScript = script

    wfsuite.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.dashboard)@" .. " / " .. "@i18n(app.modules.settings.localizations)@")
    wfsuite.app.formLineCnt = 0
    local formFieldCount = 0

    local saved = wfsuite.preferences.localizations or {}
    for k, v in pairs(saved) do config[k] = v end

    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formLines[wfsuite.app.formLineCnt] = form.addLine("@i18n(app.modules.settings.temperature_unit)@")
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(wfsuite.app.formLines[wfsuite.app.formLineCnt], nil, {{"@i18n(app.modules.settings.celcius)@", 0}, {"@i18n(app.modules.settings.fahrenheit)@", 1}}, function() return config.temperature_unit or 0 end, function(newValue) config.temperature_unit = newValue end)

    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formLines[wfsuite.app.formLineCnt] = form.addLine("@i18n(app.modules.settings.altitude_unit)@")
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(wfsuite.app.formLines[wfsuite.app.formLineCnt], nil, {{"@i18n(app.modules.settings.meters)@", 0}, {"@i18n(app.modules.settings.feet)@", 1}}, function() return config.altitude_unit or 0 end, function(newValue) config.altitude_unit = newValue end)

    for i, field in ipairs(wfsuite.app.formFields) do if field and field.enable then field:enable(true) end end
    wfsuite.app.navButtons.save = true
end

local function onNavMenu()
    pageRuntime.openMenuContext()
    return true
end

local function onSaveMenu()
    local buttons = {
        {
            label = "@i18n(app.btn_ok_long)@",
            action = function()
                local msg = "@i18n(app.modules.profile_select.save_prompt_local)@"
                wfsuite.app.ui.progressDisplaySave(msg:gsub("%?$", "."))
                for key, value in pairs(config) do wfsuite.preferences.localizations[key] = value end
                wfsuite.ini.save_ini_file("SCRIPTS:/" .. wfsuite.config.preferences .. "/preferences.ini", wfsuite.preferences)

                wfsuite.bus.notify("dashboard.reload_themes", {})

                wfsuite.app.triggers.closeSave = true
                return true
            end
        }, {label = "@i18n(app.modules.profile_select.cancel)@", action = function() return true end}
    }

    form.openDialog({width = nil, title = "@i18n(app.modules.profile_select.save_settings)@", message = "@i18n(app.modules.profile_select.save_prompt_local)@", buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})
end

local function event(widget, category, value, x, y)
    return pageRuntime.handleCloseEvent(category, value, {onClose = onNavMenu})
end

return {event = event, openPage = openPage, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = false}, API = {}}
