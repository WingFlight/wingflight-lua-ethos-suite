--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 -- https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()

local enableWakeup = false
local config = {}

local function prefBool(value, default)
    if value == nil then return default end
    if value == true or value == "true" or value == 1 or value == "1" then return true end
    if value == false or value == "false" or value == 0 or value == "0" then return false end
    return default
end

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

    wfsuite.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.features)@")
    wfsuite.app.formLineCnt = 0
    local formFieldCount = 0

    config = {}
    local saved = wfsuite.preferences.general or {}
    config.feature_dashboard = saved.feature_dashboard
    config.feature_toolbox = saved.feature_toolbox
    config.feature_activelook = saved.feature_activelook

    local function addFieldLine(label)
        formFieldCount = formFieldCount + 1
        wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
        local line = form.addLine(label)
        wfsuite.app.formLines[wfsuite.app.formLineCnt] = line
        return line
    end

    local line = addFieldLine("@i18n(app.modules.settings.feature_dashboard)@")
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(line, nil, function()
        return prefBool(config.feature_dashboard, true)
    end, function(newValue) config.feature_dashboard = newValue end)

    line = addFieldLine("@i18n(app.modules.settings.feature_toolbox)@")
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(line, nil, function()
        return prefBool(config.feature_toolbox, false)
    end, function(newValue) config.feature_toolbox = newValue end)

    line = addFieldLine("@i18n(app.modules.settings.feature_activelook)@")
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(line, nil, function()
        return prefBool(config.feature_activelook, false)
    end, function(newValue) config.feature_activelook = newValue end)

    for i, field in ipairs(wfsuite.app.formFields) do if field and field.enable then field:enable(true) end end
    wfsuite.app.navButtons.save = true
end

local function onNavMenu()
    pageRuntime.openMenuContext()
    return true
end

local function onSaveMenu()
    local function doSave()
        local msg = "@i18n(app.modules.profile_select.save_prompt_local)@"
        wfsuite.app.ui.progressDisplaySave(msg:gsub("%?$", "."))
        wfsuite.preferences.general = wfsuite.preferences.general or {}
        for key, value in pairs(config) do wfsuite.preferences.general[key] = value end
        wfsuite.ini.save_ini_file("SCRIPTS:/" .. wfsuite.config.preferences .. "/preferences.ini", wfsuite.preferences)
        wfsuite.app.MainMenu = assert(loadfile("app/modules/init.lua"))()
        wfsuite.app.triggers.closeSave = true
        return true
    end

    local confirm = wfsuite.preferences.general and wfsuite.preferences.general.save_confirm
    if confirm == false or confirm == "false" then
        doSave()
        return true
    end

    local buttons = {
        {
            label = "@i18n(app.btn_ok_long)@",
            action = function()
                doSave()
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
