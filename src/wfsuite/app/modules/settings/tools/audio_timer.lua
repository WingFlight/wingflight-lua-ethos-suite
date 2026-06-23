--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local enableWakeup = false
local onNavMenu

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

    wfsuite.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.audio)@" .. " / " .. "@i18n(app.modules.settings.txt_audio_timer)@")

    wfsuite.app.formLineCnt = 0
    local formFieldCount = 0

    local saved = wfsuite.preferences.timer or {}
    for k, v in pairs(saved) do config[k] = v end

    local intervalChoices = {{"10s", 10}, {"15s", 15}, {"30s", 30}}
    local periodChoices = {{"30s", 30}, {"60s", 60}, {"90s", 90}}

    local idxAudio, idxChoice, idxPre, idxPrePeriod, idxPreInterval, idxPost, idxPostPeriod, idxPostInterval

    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formLines[wfsuite.app.formLineCnt] = form.addLine("@i18n(app.modules.settings.timer_alerting)@")
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(wfsuite.app.formLines[wfsuite.app.formLineCnt], nil, function() return config.timeraudioenable or false end, function(newValue)
        config.timeraudioenable = newValue
        wfsuite.app.formFields[idxChoice]:enable(newValue)
        wfsuite.app.formFields[idxPre]:enable(newValue)
        wfsuite.app.formFields[idxPost]:enable(newValue)
        wfsuite.app.formFields[idxPrePeriod]:enable(newValue and (config.prealerton or false))
        wfsuite.app.formFields[idxPreInterval]:enable(newValue and (config.prealerton or false))
        wfsuite.app.formFields[idxPostPeriod]:enable(newValue and (config.postalerton or false))
        wfsuite.app.formFields[idxPostInterval]:enable(newValue and (config.postalerton or false))
    end)
    idxAudio = formFieldCount

    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formLines[wfsuite.app.formLineCnt] = form.addLine("@i18n(app.modules.settings.timer_elapsed_alert_mode)@")
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(wfsuite.app.formLines[wfsuite.app.formLineCnt], nil, {{"@i18n(app.modules.settings.timer_elapsed_beep)@", 0}, {"@i18n(app.modules.settings.timer_elapsed_multi_beep)@", 1}, {"@i18n(app.modules.settings.timer_elapsed_elapsed)@", 2}, {"@i18n(app.modules.settings.timer_elapsed_seconds)@", 3}}, function() return config.elapsedalertmode or 0 end, function(newValue) config.elapsedalertmode = newValue end)
    idxChoice = formFieldCount

    local prePanel = form.addExpansionPanel("@i18n(app.modules.settings.timer_prealert_options)@")
    prePanel:open(config.prealerton or false)

    formFieldCount = formFieldCount + 1
    idxPre = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(prePanel:addLine("@i18n(app.modules.settings.timer_prealert)@"), nil, function() return config.prealerton or false end, function(newValue)
        config.prealerton = newValue
        local audioEnabled = config.timeraudioenable or false
        wfsuite.app.formFields[idxPrePeriod]:enable(audioEnabled and newValue)
        wfsuite.app.formFields[idxPreInterval]:enable(audioEnabled and newValue)
    end)

    formFieldCount = formFieldCount + 1
    idxPrePeriod = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(prePanel:addLine("@i18n(app.modules.settings.timer_alert_period)@"), nil, periodChoices, function() return config.prealertperiod or 30 end, function(newValue) config.prealertperiod = newValue end)
    wfsuite.app.formFields[formFieldCount]:enable((config.timeraudioenable or false) and (config.prealerton or false))

    formFieldCount = formFieldCount + 1
    idxPreInterval = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(prePanel:addLine("@i18n(app.modules.settings.timer_alert_interval)@"), nil, intervalChoices, function() return config.prealertinterval or 10 end, function(newValue) config.prealertinterval = newValue end)
    wfsuite.app.formFields[formFieldCount]:enable((config.timeraudioenable or false) and (config.prealerton or false))

    local postPanel = form.addExpansionPanel("@i18n(app.modules.settings.timer_postalert_options)@")
    postPanel:open(config.postalerton or false)

    formFieldCount = formFieldCount + 1
    idxPost = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(postPanel:addLine("@i18n(app.modules.settings.timer_postalert)@"), nil, function() return config.postalerton or false end, function(newValue)
        config.postalerton = newValue
        local audioEnabled = config.timeraudioenable or false
        wfsuite.app.formFields[idxPostPeriod]:enable(audioEnabled and newValue)
        wfsuite.app.formFields[idxPostInterval]:enable(audioEnabled and newValue)
    end)

    formFieldCount = formFieldCount + 1
    idxPostPeriod = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(postPanel:addLine("@i18n(app.modules.settings.timer_alert_period)@"), nil, periodChoices, function() return config.postalertperiod or 60 end, function(newValue) config.postalertperiod = newValue end)
    wfsuite.app.formFields[formFieldCount]:enable((config.timeraudioenable or false) and (config.postalerton or false))

    formFieldCount = formFieldCount + 1
    idxPostInterval = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(postPanel:addLine("@i18n(app.modules.settings.timer_postalert_interval)@"), nil, intervalChoices, function() return config.postalertinterval or 10 end, function(newValue) config.postalertinterval = newValue end)
    wfsuite.app.formFields[formFieldCount]:enable((config.timeraudioenable or false) and (config.postalerton or false))

    wfsuite.app.formFields[idxChoice]:enable(config.timeraudioenable or false)
    wfsuite.app.formFields[idxPre]:enable(config.timeraudioenable or false)
    wfsuite.app.formFields[idxPrePeriod]:enable((config.timeraudioenable or false) and (config.prealerton or false))
    wfsuite.app.formFields[idxPreInterval]:enable((config.timeraudioenable or false) and (config.prealerton or false))
    wfsuite.app.formFields[idxPost]:enable(config.timeraudioenable or false)
    wfsuite.app.formFields[idxPostPeriod]:enable((config.timeraudioenable or false) and (config.postalerton or false))
    wfsuite.app.formFields[idxPostInterval]:enable((config.timeraudioenable or false) and (config.postalerton or false))
    wfsuite.app.navButtons.save = true
end

local function onSaveMenu()

    local function doSave()
        local msg = "@i18n(app.modules.profile_select.save_prompt_local)@"
        wfsuite.app.ui.progressDisplaySave(msg:gsub("%?$", "."))
        for key, value in pairs(config) do wfsuite.preferences.timer[key] = value end
        wfsuite.ini.save_ini_file("SCRIPTS:/" .. wfsuite.config.preferences .. "/preferences.ini", wfsuite.preferences)
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

onNavMenu = function()
    pageRuntime.openMenuContext()
    return true
end

return {event = event, openPage = openPage, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = false}, API = {}}
