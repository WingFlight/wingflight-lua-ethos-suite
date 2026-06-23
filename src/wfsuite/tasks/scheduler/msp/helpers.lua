--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")
local system = system


-- Optimized locals to reduce global/table lookups
local utils = wfsuite.utils
local helpers = {}

function helpers.governorMode(callback, owner)
    
    if (wfsuite.session.governorMode == nil ) then
        local msp = wfsuite.tasks.msp
        local API = msp and msp.api.load("GOVERNOR_CONFIG")
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        if API and owner and API.setOwner then API.setOwner(owner) end
        API.setCompleteHandler(function(self, buf)
            local governorMode = API.readValue("gov_mode")
            if governorMode then
                utils.log("Governor mode: " .. governorMode, "debug")
            end
            wfsuite.session.governorMode = governorMode
            API = nil
            if callback then callback(governorMode) end
        end)
        API.setUUID(utils.uuid and utils.uuid() or tostring(os.clock()))
        API.read()
    else
        if callback then callback(wfsuite.session.governorMode) end    
    end
end

function helpers.servoCount(callback, owner)
    if (wfsuite.session.servoCount == nil) then
        local msp = wfsuite.tasks.msp
        local API = msp and msp.api.load("STATUS")
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        if API and owner and API.setOwner then API.setOwner(owner) end
        API.setCompleteHandler(function(self, buf)
            wfsuite.session.servoCount = API.readValue("servo_count")
            if wfsuite.session.servoCount then
                utils.log("Servo count: " .. wfsuite.session.servoCount, "debug")
            end
            API = nil
            if callback then callback(wfsuite.session.servoCount) end
        end)
        API.setUUID(utils.uuid and utils.uuid() or tostring(os.clock()))
        API.read()
    else
        if callback then callback(wfsuite.session.servoCount) end    
    end
end

function helpers.servoOverride(callback, owner)
    if (wfsuite.session.servoOverride == nil) then
        local msp = wfsuite.tasks.msp
        local API = msp and msp.api.load("SERVO_OVERRIDE")
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        if API and owner and API.setOwner then API.setOwner(owner) end
        API.setCompleteHandler(function(self, buf)
            for i, v in pairs(API.data().parsed) do
                if v == 0 then
                    utils.log("Servo override: true (" .. i .. ")", "debug")
                    wfsuite.session.servoOverride = true
                end
            end
            if wfsuite.session.servoOverride == nil then wfsuite.session.servoOverride = false end
            API = nil
            if callback then callback(wfsuite.session.servoOverride) end
        end)
        API.setUUID(utils.uuid and utils.uuid() or tostring(os.clock()))
        API.read()
    else
        if callback then callback(wfsuite.session.servoOverride) end    
    end
end


function helpers.servoBusEnabled(callback, owner)

    local FBUS_FUNCTIONMASK = 524288
    local SBUS_FUNCTIONMASK = 262144

    local function hasServoBusFunction(api)
        local data = api and api.data and api.data()
        local parsed = data and data.parsed
        if not parsed then return false end

        for i = 1, 12 do
            local functionMask = parsed["port_" .. i .. "_function_mask"]
            if functionMask == FBUS_FUNCTIONMASK or functionMask == SBUS_FUNCTIONMASK then
                return true
            end
        end

        return false
    end

    if (wfsuite.session.servoBusEnabled == nil) then
        local msp = wfsuite.tasks.msp
        local API = msp and msp.api.load("SERIAL_CONFIG")
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        if API and owner and API.setOwner then API.setOwner(owner) end
        API.setCompleteHandler(function()
            wfsuite.session.servoBusEnabled = hasServoBusFunction(API)
            API = nil
            if callback then callback(wfsuite.session.servoBusEnabled) end
        end)
        API.setUUID(utils.uuid and utils.uuid() or tostring(os.clock()))
        API.read()
    else
        if callback then callback(wfsuite.session.servoBusEnabled) end
    end
end

function helpers.mixerConfig(callback, owner)
    if (wfsuite.session.tailMode == nil or wfsuite.session.swashMode == nil) then
        local msp = wfsuite.tasks.msp
        local API = msp and msp.api.load("MIXER_CONFIG")
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        if API and owner and API.setOwner then API.setOwner(owner) end
        API.setCompleteHandler(function(self, buf)
            wfsuite.session.tailMode = API.readValue("tail_rotor_mode")
            wfsuite.session.swashMode = API.readValue("swash_type")
            if system and system.getVersion and system.getVersion().simulation then
                local dev = wfsuite.preferences and wfsuite.preferences.developer
                local override = dev and dev.tailmode_override
                override = tonumber(override)
                if override == 0 or override == 1 then
                    wfsuite.session.tailMode = override
                    utils.log("Tail mode override (developer): " .. tostring(override), "debug")
                end
            end
            if wfsuite.session.tailMode and wfsuite.session.swashMode then
                utils.log("Tail mode: " .. wfsuite.session.tailMode, "debug")
                utils.log("Swash mode: " .. wfsuite.session.swashMode, "debug")
            end
            API = nil
            if callback then callback(wfsuite.session.tailMode, wfsuite.session.swashMode) end
        end)
        API.setUUID(utils.uuid and utils.uuid() or tostring(os.clock()))
        API.read()
    else
        if callback then callback(wfsuite.session.tailMode,wfsuite.session.swashMode) end    
    end
end

function helpers.tailMode(callback, owner)
    helpers.mixerConfig(function(tailMode, swashMode)
        if callback then callback(tailMode) end
    end, owner)
end

function helpers.swashMode(callback, owner)
    helpers.mixerConfig(function(tailMode, swashMode)
        if callback then callback(swashMode) end
    end, owner)
end


return helpers
