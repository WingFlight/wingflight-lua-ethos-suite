--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local activateWakeup = false

local apidata = {
    api = {
        {id = 1, name = "PID_PROFILE", enableDeltaCache = false, rebuildOnWrite = true},
    },  
    formdata = {
        labels = {
            { t = "@i18n(app.modules.profile_autolevel.acro_trainer)@", inline_size = 13.6, label = 1 },
            { t = "@i18n(app.modules.profile_autolevel.angle_mode)@", inline_size = 13.6, label = 2 },
            { t = "@i18n(app.modules.profile_autolevel.horizon_mode)@", inline_size = 13.6, label = 3 },
            { t = "@i18n(app.modules.profile_autolevel.auto_hover)@", inline_size = 10.15, label = 4 },
            { t = "@i18n(app.modules.profile_autolevel.att_hold)@", inline_size = 10.15, label = 5 }
        },
        fields = {
            { t = "@i18n(app.modules.profile_autolevel.gain)@", inline = 2, label = 1, mspapi = 1, apikey = "trainer_gain" },
            { t = "@i18n(app.modules.profile_autolevel.max)@", inline = 1, label = 1, mspapi = 1, apikey = "trainer_angle_limit" },
            { t = "@i18n(app.modules.profile_autolevel.gain)@", inline = 2, label = 2, mspapi = 1, apikey = "angle_level_strength" },
            { t = "@i18n(app.modules.profile_autolevel.max)@", inline = 1, label = 2, mspapi = 1, apikey = "angle_level_limit" },
            { t = "@i18n(app.modules.profile_autolevel.gain)@", inline = 2, label = 3, mspapi = 1, apikey = "horizon_level_strength" },
            { t = "@i18n(app.modules.profile_autolevel.gain)@", inline = 3, label = 4, mspapi = 1, apikey = "autohover_gain" },
            { t = "@i18n(app.modules.profile_autolevel.max)@", inline = 2, label = 4, mspapi = 1, apikey = "autohover_max_angle" },
            { t = "@i18n(app.modules.profile_autolevel.rate)@", inline = 1, label = 4, mspapi = 1, apikey = "autohover_max_rate" },
            { t = "@i18n(app.modules.profile_autolevel.gain)@", inline = 3, label = 5, mspapi = 1, apikey = "atthold_gain" },
            { t = "@i18n(app.modules.profile_autolevel.deadband)@", inline = 2, label = 5, mspapi = 1, apikey = "atthold_deadband" },
            { t = "@i18n(app.modules.profile_autolevel.rate)@", inline = 1, label = 5, mspapi = 1, apikey = "atthold_max_rate" }
        }
    }
}

local function postLoad(self)
    wfsuite.app.triggers.closeProgressLoader = true
    activateWakeup = true
end

local function wakeup()
    if activateWakeup and wfsuite.tasks.msp.mspQueue:isProcessed() then
        local activeProfile = wfsuite.session and wfsuite.session.activeProfile
        if activeProfile ~= nil then
            local baseTitle = wfsuite.app.lastTitle or (wfsuite.app.Page and wfsuite.app.Page.title) or ""
            wfsuite.app.ui.setHeaderTitle(baseTitle .. " #" .. activeProfile, nil, wfsuite.app.Page and wfsuite.app.Page.navButtons)
        end
        activateWakeup = false
    end
end

return {apidata = apidata, title = "@i18n(app.modules.profile_autolevel.name)@", refreshOnProfileChange = true, reboot = false, eepromWrite = true, postLoad = postLoad, wakeup = wakeup, API = {}}
