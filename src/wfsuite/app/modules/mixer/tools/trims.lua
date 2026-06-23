--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local pageRuntime = assert(loadfile("app/lib/page_runtime.lua"))()

local labels = {}
local fields = {}

local triggerOverRide = false
local inOverRide = false
local lastChangeTime = os.clock()
local currentRollTrim
local currentRollTrimLast
local currentPitchTrim
local currentPitchTrimLast
local currentCollectiveTrim
local currentCollectiveTrimLast
local currentYawTrim
local currentYawTrimLast
local currentIdleThrottleTrim
local currentIdleThrottleTrimLast
local clear2send = true

local function queueMixerOverride(index, value, uuid)
    local API = wfsuite.tasks.msp.api.loadPage("MIXER_OVERRIDE")
    if not API then return false, "api_unavailable" end

    API.setUUID(uuid)
    API.setValue("index", index)
    API.setValue("value", value)
    return API.write()
end

local apidata = {
    api = {[1] = "MIXER_CONFIG"},
    formdata = {
        labels = {},
        fields = {
            {t = "@i18n(app.modules.trim.roll_trim)@",         mspapi = 1, apikey = "swash_trim_0", },
            {t = "@i18n(app.modules.trim.pitch_trim)@",        mspapi = 1, apikey = "swash_trim_1"},
            {t = "@i18n(app.modules.trim.collective_trim)@",    mspapi = 1, apikey = "swash_trim_2"},
            {t = "@i18n(app.modules.trim.yaw_trim)@",          mspapi = 1, apikey = "tail_center_trim", enablefunction = function() return (wfsuite.session.tailMode == 0) end},
        }
    }
}

local function saveData()
    clear2send = true
    wfsuite.app.triggers.triggerSaveNoProgress = true
end

local function mixerOn(self)

    wfsuite.app.audio.playMixerOverideEnable = true

    for i = 1, 4 do
        queueMixerOverride(i, 0, string.format("mixer.override.%d.on", i))

        if wfsuite.preferences.developer.logmsp then
            local logData = "mixerOn: {index=" .. tostring(i) .. ", value=0}"
            wfsuite.utils.log(logData, "info")
        end

    end

    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function mixerOff(self)

    wfsuite.app.audio.playMixerOverideDisable = true

    for i = 1, 4 do
        queueMixerOverride(i, 2501, string.format("mixer.override.%d.off", i))

        if wfsuite.preferences.developer.logmsp then
            local logData = "mixerOff: {index=" .. tostring(i) .. ", value=2501}"
            wfsuite.utils.log(logData, "info")
        end

    end

    wfsuite.app.triggers.isReady = true
    wfsuite.app.triggers.closeProgressLoader = true
end

local function postLoad(self)

    if wfsuite.session.tailMode == nil then
        local v = wfsuite.app.Page.values['MIXER_CONFIG']["tail_rotor_mode"]
        wfsuite.session.tailMode = math.floor(v)
        wfsuite.app.triggers.reload = true
        return
    end

    currentRollTrim = wfsuite.app.Page.apidata.formdata.fields[1].value
    currentPitchTrim = wfsuite.app.Page.apidata.formdata.fields[2].value
    currentCollectiveTrim = wfsuite.app.Page.apidata.formdata.fields[3].value

    if wfsuite.session.tailModeActive == 1 or wfsuite.session.tailModeActive == 2 then currentIdleThrottleTrim = wfsuite.app.Page.apidata.formdata.fields[4].value end

    if wfsuite.session.tailModeActive == 0 then currentYawTrim = wfsuite.app.Page.apidata.formdata.fields[4].value end
    wfsuite.app.triggers.closeProgressLoader = true
end

local function wakeup(self)

    -- we are compromised without this - go back to main
    if wfsuite.session.tailMode == nil then
        pageRuntime.openMenuContext()
        return
    end    


    if inOverRide == true then

        currentRollTrim = wfsuite.app.Page.apidata.formdata.fields[1].value
        local now = os.clock()
        local settleTime = 0.85
        if ((now - lastChangeTime) >= settleTime) and wfsuite.tasks.msp.mspQueue:isProcessed() and clear2send == true then
            if currentRollTrim ~= currentRollTrimLast then
                currentRollTrimLast = currentRollTrim
                lastChangeTime = now
                wfsuite.utils.log("save trim", "debug")
                self.saveData(self)
            end
        end

        currentPitchTrim = wfsuite.app.Page.apidata.formdata.fields[2].value
        local now = os.clock()
        local settleTime = 0.85
        if ((now - lastChangeTime) >= settleTime) and wfsuite.tasks.msp.mspQueue:isProcessed() and clear2send == true then
            if currentPitchTrim ~= currentPitchTrimLast then
                currentPitchTrimLast = currentPitchTrim
                lastChangeTime = now
                self.saveData(self)
            end
        end

        currentCollectiveTrim = wfsuite.app.Page.apidata.formdata.fields[3].value
        local now = os.clock()
        local settleTime = 0.85
        if ((now - lastChangeTime) >= settleTime) and wfsuite.tasks.msp.mspQueue:isProcessed() and clear2send == true then
            if currentCollectiveTrim ~= currentCollectiveTrimLast then
                currentCollectiveTrimLast = currentCollectiveTrim
                lastChangeTime = now
                self.saveData(self)
            end
        end

        if wfsuite.session.tailMode == 1 or wfsuite.session.tailMode == 2 then
            currentIdleThrottleTrim = wfsuite.app.Page.apidata.formdata.fields[4].value
            local now = os.clock()
            local settleTime = 0.85
            if ((now - lastChangeTime) >= settleTime) and wfsuite.tasks.msp.mspQueue:isProcessed() and clear2send == true then
                if currentIdleThrottleTrim ~= currentIdleThrottleTrimLast then
                    currentIdleThrottleTrimLast = currentIdleThrottleTrim
                    lastChangeTime = now
                    self.saveData(self)
                end
            end
        end

        if wfsuite.session.tailMode == 0 then
            currentYawTrim = wfsuite.app.Page.apidata.formdata.fields[4].value
            local now = os.clock()
            local settleTime = 0.85
            if ((now - lastChangeTime) >= settleTime) and wfsuite.tasks.msp.mspQueue:isProcessed() then
                if currentYawTrim ~= currentYawTrimLast then
                    currentYawTrimLast = currentYawTrim
                    lastChangeTime = now
                    self.saveData(self)
                end
            end
        end

    end

    if triggerOverRide == true then
        triggerOverRide = false

        if inOverRide == false then

            wfsuite.app.audio.playMixerOverideEnable = true

            wfsuite.app.ui.progressDisplay("@i18n(app.modules.trim.mixer_override)@", "@i18n(app.modules.trim.mixer_override_enabling)@")

            wfsuite.app.Page.mixerOn(self)
            inOverRide = true
        else

            wfsuite.app.audio.playMixerOverideDisable = true

            wfsuite.app.ui.progressDisplay("@i18n(app.modules.trim.mixer_override)@", "@i18n(app.modules.trim.mixer_override_disabling)@")

            wfsuite.app.Page.mixerOff(self)
            inOverRide = false
        end
    end

end

local function onToolMenu(self)

    local buttons = {
        {
            label = "@i18n(app.btn_ok)@",
            action = function()

                triggerOverRide = true
                return true
            end
        }, {label = "@i18n(app.btn_cancel)@", action = function() return true end}
    }
    local message
    local title
    if inOverRide == false then
        title = "@i18n(app.modules.trim.enable_mixer_override)@"
        message = "@i18n(app.modules.trim.enable_mixer_message)@"
    else
        title = "@i18n(app.modules.trim.disable_mixer_override)@"
        message = "@i18n(app.modules.trim.disable_mixer_message)@"
    end

    form.openDialog({width = nil, title = title, message = message, buttons = buttons, wakeup = function() end, paint = function() end, options = TEXT_LEFT})

end

local function onNavMenu(self)

    if inOverRide == true or inFocus == true then
        wfsuite.app.audio.playMixerOverideDisable = true

        inOverRide = false
        inFocus = false

        wfsuite.app.ui.progressDisplay("@i18n(app.modules.trim.mixer_override)@", "@i18n(app.modules.trim.mixer_override_disabling)@")

        mixerOff(self)
        wfsuite.app.triggers.closeProgressLoader = true
    end

    pageRuntime.openMenuContext()

end


return {apidata = apidata, eepromWrite = true, reboot = false, mixerOff = mixerOff, mixerOn = mixerOn, postLoad = postLoad, onToolMenu = onToolMenu, onNavMenu = onNavMenu, wakeup = wakeup, saveData = saveData, navButtons = {menu = true, save = true, reload = true, tool = true, help = true}, API = {}}
