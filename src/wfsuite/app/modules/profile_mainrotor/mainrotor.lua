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
            { t = "@i18n(app.modules.profile_mainrotor.collective_pitch_comp)@", t2 = "@i18n(app.modules.profile_mainrotor.collective_pitch_comp_short)@", label = 1, inline_size = 40.15 },
            { t = "@i18n(app.modules.profile_mainrotor.cyclic_cross_coupling)@", label = 2, inline_size = 40.15 },
            { t = "", label = 3, inline_size = 40.15 },
            { t = "", label = 4, inline_size = 40.15 }
        },
        fields = {
            { t = "", inline = 1, label = 1, mspapi = 1, apikey = "pitch_collective_ff_gain" },
            { t = "@i18n(app.modules.profile_mainrotor.gain)@", inline = 1, label = 2, mspapi = 1, apikey = "cyclic_cross_coupling_gain" },
            { t = "@i18n(app.modules.profile_mainrotor.ratio)@", inline = 1, label = 3, mspapi = 1, apikey = "cyclic_cross_coupling_ratio" },
            { t = "@i18n(app.modules.profile_mainrotor.cutoff)@", inline = 1, label = 4, mspapi = 1, apikey = "cyclic_cross_coupling_cutoff" }
        }
    }
}

local function postLoad(self)
    wfsuite.app.triggers.closeProgressLoader = true
    activateWakeup = true
end

local function wakeup()
    if activateWakeup == true and wfsuite.tasks.msp.mspQueue:isProcessed() then
        local activeProfile = wfsuite.session and wfsuite.session.activeProfile
        if activeProfile ~= nil then
            local baseTitle = wfsuite.app.lastTitle or (wfsuite.app.Page and wfsuite.app.Page.title) or ""
            wfsuite.app.ui.setHeaderTitle(baseTitle .. " #" .. activeProfile, nil, wfsuite.app.Page and wfsuite.app.Page.navButtons)
        end
        activateWakeup = false
    end
end

return {apidata = apidata, title = "@i18n(app.modules.profile_mainrotor.name)@", refreshOnProfileChange = true, reboot = false, eepromWrite = true, postLoad = postLoad, wakeup = wakeup, API = {}}
