--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local apiversion = {}

local mspCallMade = false
local API_NAME = "API_VERSION"

local function clearApiEntry()
    local api = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api
    if api and type(api.clearEntry) == "function" then
        api.clearEntry(API_NAME)
    end
end

local function version_ge(a, b)
    local function split(v)
        local t = {}

        local function appendParts(value)
            if value == nil then return end

            if type(value) == "table" then
                local arrayValues = {}
                for _, token in ipairs(value) do arrayValues[#arrayValues + 1] = token end

                if #arrayValues == 3 then
                    local major = tonumber(arrayValues[1])
                    local middle = tonumber(arrayValues[2])
                    local minor = tonumber(arrayValues[3])
                    if major and middle == 0 and minor then
                        t[#t + 1] = major
                        t[#t + 1] = minor
                        return
                    end
                end

                if #arrayValues > 0 then
                    for i = 1, #arrayValues do appendParts(arrayValues[i]) end
                elseif value[0] ~= nil then
                    appendParts(value[0])
                end
                return
            end

            for part in tostring(value):gmatch("(%d+)") do t[#t + 1] = tonumber(part) end
        end

        appendParts(v)

        return t
    end

    local A, B = split(a), split(b)
    local len = math.max(#A, #B)
    for i = 1, len do
        local ai = A[i] or 0
        local bi = B[i] or 0
        if ai < bi then return false end
        if ai > bi then return true end
    end
    return true
end

function apiversion.wakeup()
    if wfsuite.session.apiVersion == nil and mspCallMade == false then
        mspCallMade = true

        local originalProto = wfsuite.config.mspProtocolVersion
        local probeProto = (wfsuite.config.msp and wfsuite.config.msp.probeProtocol) or 1
        wfsuite.config.mspProtocolVersion = probeProto

        local API = wfsuite.tasks.msp.api.load(API_NAME)
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        API.setCompleteHandler(function(self, buf)
            local version = API.readVersion()

            local restoreProto = originalProto

            if version then
                local apiVersionString = string.format("%.2f", version)

                if not wfsuite.utils.stringInArray(wfsuite.config.supportedMspApiVersion, apiVersionString) then
                    wfsuite.utils.log("Incompatible API version detected: " .. apiVersionString, "info")
                    wfsuite.utils.log("Incompatible API version detected: " .. apiVersionString, "connect")
                    wfsuite.session.apiVersionInvalid = true
                    wfsuite.session.apiVersion = apiVersionString

                    wfsuite.config.mspProtocolVersion = restoreProto
                    clearApiEntry()
                    return
                end

                local wantProto = probeProto
                local policy = wfsuite.config.msp or {}
                if policy.allowAutoUpgrade and policy.maxProtocol and policy.maxProtocol >= 2 then
                    if policy.v2MinApiVersion and version_ge(apiVersionString, policy.v2MinApiVersion) then
                        wantProto = 2
                    end
                end

                if wantProto ~= wfsuite.config.mspProtocolVersion then
                    wfsuite.config.mspProtocolVersion = wantProto
                    wfsuite.session.mspProtocolVersion = wantProto

                    if wfsuite.tasks.msp.common.setProtocolVersion then
                        wfsuite.tasks.msp.common.setProtocolVersion(wantProto)
                    elseif wfsuite.tasks.msp.reset then
                        wfsuite.tasks.msp.reset()
                    end

                    wfsuite.utils.log(string.format("MSP protocol upgraded to v%d (api %s)", wantProto, apiVersionString), "info")
                    wfsuite.utils.log(string.format("MSP protocol upgraded to v%d (api %s)", wantProto, apiVersionString), "connect")
                else
                    wfsuite.config.mspProtocolVersion = wantProto
                end
            else
                wfsuite.config.mspProtocolVersion = restoreProto
                wfsuite.utils.log(string.format("MSP protocol restored to v%d", restoreProto), "info")
                wfsuite.utils.log(string.format("MSP protocol restored to v%d", restoreProto), "connect")
                wfsuite.session.mspProtocolVersion = restoreProto
                if wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.common and wfsuite.tasks.msp.common.setProtocolVersion then
                    wfsuite.tasks.msp.common.setProtocolVersion(restoreProto)
                end
                mspCallMade = false
                clearApiEntry()
                return
            end

            wfsuite.session.apiVersion = version and string.format("%.2f", version) or nil
            wfsuite.session.apiVersionInvalid = false
            if wfsuite.session.apiVersion then
                wfsuite.utils.log("API version: " .. wfsuite.session.apiVersion, "info")
                wfsuite.utils.log("API version: " .. wfsuite.session.apiVersion, "connect")
            end
            clearApiEntry()
        end)
        API.setErrorHandler(function()
            wfsuite.config.mspProtocolVersion = originalProto
            wfsuite.session.mspProtocolVersion = originalProto
            if wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.common and wfsuite.tasks.msp.common.setProtocolVersion then
                wfsuite.tasks.msp.common.setProtocolVersion(originalProto)
            end
            mspCallMade = false
            clearApiEntry()
        end)
        API.setUUID("onconnect-apiversion-read")
        API.read()
    end
end

function apiversion.reset()
    clearApiEntry()
    wfsuite.session.apiVersion = nil
    wfsuite.session.apiVersionInvalid = nil
    mspCallMade = false
end

function apiversion.isComplete()
    if wfsuite.session.apiVersion ~= nil then
        if wfsuite.utils and type(wfsuite.utils.playConnectBeep) == "function" then
            wfsuite.utils.playConnectBeep()
        else
            wfsuite.utils.playFileCommon("beep.wav")
        end
        return true
    end
end

return apiversion
