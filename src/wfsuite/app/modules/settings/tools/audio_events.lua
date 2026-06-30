--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()

local config = {}
local enableWakeup = false

local function setFieldEnabled(field, enabled) if field and field.enable then field:enable(enabled) end end

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

    wfsuite.app.ui.fieldHeader("@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.audio)@" .. " / " .. "@i18n(app.modules.settings.txt_audio_events)@")
    wfsuite.app.formLineCnt = 0

    local formFieldCount = 0

    local app = wfsuite.app
    if app.formFields then for k in pairs(app.formFields) do app.formFields[k] = nil end end
    if app.formLines then for k in pairs(app.formLines) do app.formLines[k] = nil end end

    local savedEvents = wfsuite.preferences.events or {}
    for k, v in pairs(savedEvents) do config[k] = v end

    local escFields, becFields, fuelFields = {}, {}, {}

    local statusEnabled = (config.armflags == true) or (config.flight_mode == true)
    local statusPanel = form.addExpansionPanel("@i18n(telemetry.group_status)@")
    statusPanel:open(statusEnabled)
    local armLine = statusPanel:addLine("@i18n(app.modules.settings.arming_flags)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(armLine, nil, function() return config.armflags end, function(val) config.armflags = val end)
    local flightModeLine = statusPanel:addLine("@i18n(app.modules.settings.flight_mode_event)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(flightModeLine, nil, function() return config.flight_mode end, function(val) config.flight_mode = val end)

    local voltEnabled = config.voltage == true
    local voltPanel = form.addExpansionPanel("@i18n(app.modules.settings.voltage)@")
    voltPanel:open(voltEnabled)
    local voltLine = voltPanel:addLine("@i18n(app.modules.settings.voltage)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(voltLine, nil, function() return config.voltage end, function(val) config.voltage = val end)

    local ratesEnabled = (config.pid_profile == true) or (config.rate_profile == true)
    local ratesPanel = form.addExpansionPanel("@i18n(app.modules.settings.pid_rates_profile)@")
    ratesPanel:open(ratesEnabled)
    local pidLine = ratesPanel:addLine("@i18n(app.modules.settings.pid_profile)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(pidLine, nil, function() return config.pid_profile end, function(val) config.pid_profile = val end)
    local rateLine = ratesPanel:addLine("@i18n(app.modules.settings.rate_profile)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(rateLine, nil, function() return config.rate_profile end, function(val) config.rate_profile = val end)

    local escEnabled = config.temp_esc == true
    local escPanel = form.addExpansionPanel("@i18n(app.modules.settings.esc_temperature)@")
    escPanel:open(escEnabled)
    local escEnable = escPanel:addLine("@i18n(app.modules.settings.esc_temperature)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    escFields.enable = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(escEnable, nil, function() return config.temp_esc end, function(val)
        config.temp_esc = val
        setFieldEnabled(wfsuite.app.formFields[escFields.thresh], val)
    end)
    local escThresh = escPanel:addLine("@i18n(app.modules.settings.esc_threshold)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    escFields.thresh = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addNumberField(escThresh, nil, 60, 300, function() return config.escalertvalue or 90 end, function(val) config.escalertvalue = val end, 1)
    wfsuite.app.formFields[formFieldCount]:suffix("°")
    setFieldEnabled(wfsuite.app.formFields[escFields.thresh], escEnabled)

    local adjEnabled = (config.adj_f == true) or (config.adj_v == true)
    local adjPanel = form.addExpansionPanel("@i18n(app.modules.settings.adj_callouts)@")
    adjPanel:open(adjEnabled)

    local adjFuncLine = adjPanel:addLine("@i18n(app.modules.settings.adj_function)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(adjFuncLine, nil, function() return config.adj_f == true end, function(val) config.adj_f = val end)

    local adjValueLine = adjPanel:addLine("@i18n(app.modules.settings.adj_value)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(adjValueLine, nil, function() return config.adj_v == true end, function(val) config.adj_v = val end)

    local fuelEnabled = config.smartfuel == true
    local fuelPanel = form.addExpansionPanel("@i18n(app.modules.settings.fuel)@")
    fuelPanel:open(fuelEnabled)
    local fuelEnable = fuelPanel:addLine("@i18n(app.modules.settings.fuel)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    fuelFields.enable = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(fuelEnable, nil, function() return config.smartfuel end, function(val)
        config.smartfuel = val
        setFieldEnabled(wfsuite.app.formFields[fuelFields.callout], val)
        setFieldEnabled(wfsuite.app.formFields[fuelFields.repeats], val)
        setFieldEnabled(wfsuite.app.formFields[fuelFields.haptic], val)
    end)
    local calloutChoices = {{"@i18n(app.modules.settings.fuel_callout_default)@", 0}, {"@i18n(app.modules.settings.fuel_callout_5)@", 5}, {"@i18n(app.modules.settings.fuel_callout_10)@", 10}, {"@i18n(app.modules.settings.fuel_callout_20)@", 20}, {"@i18n(app.modules.settings.fuel_callout_25)@", 25}, {"@i18n(app.modules.settings.fuel_callout_50)@", 50}}
    local fuelThresh = fuelPanel:addLine("@i18n(app.modules.settings.fuel_callout_percent)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    fuelFields.callout = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addChoiceField(fuelThresh, nil, calloutChoices, function()
        local v = config.smartfuelcallout
        if v == nil or v == false then return 10 end
        return v
    end, function(val) config.smartfuelcallout = val end)
    setFieldEnabled(wfsuite.app.formFields[fuelFields.callout], fuelEnabled)

    local fuelRepeats = fuelPanel:addLine("@i18n(app.modules.settings.fuel_repeats_below)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    fuelFields.repeats = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addNumberField(fuelRepeats, nil, 1, 10, function() return config.smartfuelrepeats or 1 end, function(val) config.smartfuelrepeats = val end, 1)
    wfsuite.app.formFields[formFieldCount]:suffix("x")
    setFieldEnabled(wfsuite.app.formFields[fuelFields.repeats], fuelEnabled)

    local fuelHaptic = fuelPanel:addLine("@i18n(app.modules.settings.fuel_haptic_below)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    fuelFields.haptic = formFieldCount
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(fuelHaptic, nil, function() return config.smartfuelhaptic == true end, function(val) config.smartfuelhaptic = val end)
    setFieldEnabled(wfsuite.app.formFields[fuelFields.haptic], fuelEnabled)

    setFieldEnabled(wfsuite.app.formFields[escFields.enable], true)
    setFieldEnabled(wfsuite.app.formFields[becFields.enable], true)
    setFieldEnabled(wfsuite.app.formFields[fuelFields.enable], true)

    local batteryProfileEnabled = config.battery_profile == true
    local batteryPanel = form.addExpansionPanel("@i18n(app.modules.settings.battery_profile_event)@")
    batteryPanel:open(batteryProfileEnabled)
    local batteryLine = batteryPanel:addLine("@i18n(app.modules.settings.battery_capacity_callout)@")
    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(batteryLine, nil, function() return config.battery_profile end, function(val)
        config.battery_profile = val
    end)

    local otherEnabled = config.otherSoundCfg == true
    local otherPanel = form.addExpansionPanel("@i18n(app.modules.settings.otherSoundSettings)@")
    otherPanel:open(otherEnabled)

    local w = wfsuite.app.lcdWidth
    local otherModelAnnouncement = otherPanel:addLine("@i18n(app.modules.settings.modelAnnouncement)@")

    formFieldCount = formFieldCount + 1
    wfsuite.app.formLineCnt = wfsuite.app.formLineCnt + 1
    wfsuite.app.formFields[formFieldCount] = form.addBooleanField(otherModelAnnouncement, nil, function() return config.otherModelAnnounce == true end, function(val) config.otherModelAnnounce = val end)
    if wfsuite.app.formFields[formFieldCount].help then
        wfsuite.app.formFields[formFieldCount]:help("@i18n(app.modules.settings.help_modelAnnouncement)@")
    end

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
        for key, value in pairs(config) do wfsuite.preferences.events[key] = value end
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

local function onHelpMenu()

    local helpPath = "app/modules/settings/tools/help.lua"
    local help = assert(loadfile(helpPath))()

    wfsuite.app.ui.openPageHelp(help.help["audio_events"], "@i18n(app.modules.settings.name)@" .. " / " .. "@i18n(app.modules.settings.audio)@" .. " / " .. "@i18n(app.modules.settings.txt_audio_events)@")

end

return {event = event, openPage = openPage, onNavMenu = onNavMenu, onSaveMenu = onSaveMenu,  onHelpMenu = onHelpMenu, navButtons = {menu = true, save = true, reload = false, tool = false, help = true}, API = {}}
