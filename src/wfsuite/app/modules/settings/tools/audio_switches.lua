--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local system = system

local config = {}
local enableWakeup = false

local function sensorNameMap(sensorList)
    local nameMap = {}
    for _, sensor in ipairs(sensorList) do nameMap[sensor.key] = sensor.name end
    return nameMap
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

    wfsuite.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.audio)@" .. " / " .. "@i18n(app.modules.settings.txt_audio_switches)@")
    wfsuite.app.formLineCnt = 0

    local formFieldCount = 0

    local function sortSensorListByName(sensorList)
        table.sort(sensorList, function(a, b) return a.name:lower() < b.name:lower() end)
        return sensorList
    end

    local sensorList = sortSensorListByName(wfsuite.tasks.telemetry.listSwitchSensors())

    local saved = wfsuite.preferences.switches or {}
    for k, v in pairs(saved) do config[k] = v end

    for i, v in ipairs(sensorList) do
        formFieldCount = formFieldCount + 1
        wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
        wfsuite.app.formLines[wfsuite.app.formLineCnt] = form.addLine(v.name or "unknown")

        wfsuite.app.formFields[formFieldCount] = form.addSwitchField(wfsuite.app.formLines[wfsuite.app.formLineCnt], nil, function()
            local value = config[v.key]
            if value then
                local scategory, smember = value:match("([^,]+),([^,]+)")
                if scategory and smember then
                    local source = system.getSource({category = tonumber(scategory), member = tonumber(smember)})
                    return source
                end
            end
            return nil
        end, function(newValue)
            if newValue then
                local cat_member = newValue:category() .. "," .. newValue:member()
                config[v.key] = cat_member
            else
                config[v.key] = nil
            end
        end)
    end

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
        for key, value in pairs(config) do wfsuite.preferences.switches[key] = value end
        wfsuite.ini.save_ini_file("SCRIPTS:/" .. wfsuite.config.preferences .. "/preferences.ini", wfsuite.preferences)
        wfsuite.tasks.events.switches.reset()
        wfsuite.app.triggers.closeSave = true
    end

    if wfsuite.preferences.general.save_confirm == false or wfsuite.preferences.general.save_confirm == "false" then
        doSave()
        return
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
