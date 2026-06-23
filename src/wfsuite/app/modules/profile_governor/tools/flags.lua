--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()
local navHandlers = pageRuntime.createMenuHandlers({showProgress = true})

local activateWakeup = false
local governorDisabledMsg = false

local FIELD_FALLBACK_PRECOMP = 1
local FIELD_PID_SPOOLUP = 2
local FIELD_VOLTAGE_COMP = 3
local FIELD_DYN_MIN_THROTTLE = 4


local apidata = {
    api = {
        {id = 1, name = "GOVERNOR_PROFILE", enableDeltaCache = false, rebuildOnWrite = true},
    },    
    formdata = {
        labels = {},
        fields = {
            {t = "@i18n(app.modules.profile_governor.fallback_precomp)@", mspapi = 1, apikey = "governor_flags->fallback_precomp", type = 1},
            {t = "@i18n(app.modules.profile_governor.pid_spoolup)@", mspapi = 1, apikey = "governor_flags->pid_spoolup", type = 1}, 
            {t = "@i18n(app.modules.profile_governor.voltage_comp)@", mspapi = 1, apikey = "governor_flags->voltage_comp", type = 1}, 
            {t = "@i18n(app.modules.profile_governor.dyn_min_throttle)@", mspapi = 1, apikey = "governor_flags->dyn_min_throttle", type = 1},
        }
    }
}

local function postLoad(self)
    wfsuite.app.triggers.closeProgressLoader = true
    activateWakeup = true
end

local function setNavEnabled(id, enabled)
    local navFields = wfsuite.app and wfsuite.app.formNavigationFields
    local nav = navFields and navFields[id]
    if nav and nav.enable then nav:enable(enabled) end
end

local function setFieldEnabled(index, enabled)
    local fields = wfsuite.app and wfsuite.app.formFields
    local field = fields and fields[index]
    if field and field.enable then field:enable(enabled) end
end

local function canSave()
    local govEnabled = (wfsuite.session.governorMode ~= nil and wfsuite.session.governorMode ~= 0)
    if not govEnabled then return false end
    local pref = wfsuite.preferences and wfsuite.preferences.general and wfsuite.preferences.general.save_dirty_only
    if pref == false or pref == "false" then return true end
    return wfsuite.app.pageDirty == true
end

local function wakeup()

    -- we are compromised if we don't have governor mode known
    if wfsuite.session.governorMode == nil then
        pageRuntime.openMenuContext()
        return
    end

    local mspQueue = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.mspQueue
    if activateWakeup ~= true or not (mspQueue and mspQueue.isProcessed and mspQueue:isProcessed()) then
        return
    end

    local activeProfile = wfsuite.session and wfsuite.session.activeProfile
    if activeProfile ~= nil then
        local baseTitle = wfsuite.app.lastTitle or (wfsuite.app.Page and wfsuite.app.Page.title) or ""
        wfsuite.app.ui.setHeaderTitle(baseTitle .. " #" .. activeProfile, nil, wfsuite.app.Page and wfsuite.app.Page.navButtons)
    end

    -- Enable/disable fields based on firmware/session state.
    local govEnabled = (wfsuite.session.governorMode ~= nil and wfsuite.session.governorMode ~= 0)
    local adcVoltage = (wfsuite.session.batteryConfig ~= nil and wfsuite.session.batteryConfig.voltageMeterSource == 1)

    -- Navigation buttons (if present)
    setNavEnabled("save", canSave())
    setNavEnabled("reload", govEnabled)

    -- If governor is disabled in firmware, lock the page.
    if not govEnabled then
        setFieldEnabled(FIELD_FALLBACK_PRECOMP, false)
        setFieldEnabled(FIELD_PID_SPOOLUP, false)
        setFieldEnabled(FIELD_VOLTAGE_COMP, false)
        setFieldEnabled(FIELD_DYN_MIN_THROTTLE, false)
        return
    end

    -- Governor enabled: field availability.
    setFieldEnabled(FIELD_FALLBACK_PRECOMP, true)
    setFieldEnabled(FIELD_PID_SPOOLUP, true)
    setFieldEnabled(FIELD_DYN_MIN_THROTTLE, true)

    -- Voltage compensation requires an ADC voltage source.
    setFieldEnabled(FIELD_VOLTAGE_COMP, adcVoltage)
end

local function event(widget, category, value, x, y)
    return navHandlers.event(widget, category, value)
end

local function onNavMenu()
    return navHandlers.onNavMenu()
end

return {apidata = apidata, title = "@i18n(app.modules.profile_governor.name)@", reboot = false, event = event, onNavMenu = onNavMenu, refreshOnProfileChange = true, eepromWrite = true, postLoad = postLoad, wakeup = wakeup, canSave = canSave, API = {}}
