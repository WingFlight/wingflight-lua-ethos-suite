--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local sync = {}

local fetchData = false
local saveData  = false
local isComplete = false

local FBL_STATS = {} -- holder for fbl stats to sync
local LOCAL_STATS = {} -- holder for local stats to sync
local API_NAME = "FLIGHT_STATS"

local function clearApiEntry()
    local api = wfsuite.tasks and wfsuite.tasks.msp and wfsuite.tasks.msp.api
    if api and type(api.clearEntry) == "function" then
        api.clearEntry(API_NAME)
    end
end

local function copyTable(src)
    if type(src) ~= "table" then return src end
    local dst = {}
    for k, v in pairs(src) do dst[k] = v end
    return dst
end

local function saveToEeprom()
    local ok, reason = wfsuite.utils.queueEepromWrite({
        uuid = "eeprom.syncstats.postconnect",
        logMessage = "EEPROM write command sent"
    })
    if not ok then
        wfsuite.utils.log("EEPROM enqueue rejected (" .. tostring(reason) .. ")", "info")
    end
end

local function toNumber(v, dflt)
    local n = tonumber(v)
    if n == nil then return dflt end
    return n
end

function sync.wakeup()

    -- no api version info yet
    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.session.mspBusy then return end

    if wfsuite.session.mcu_id == nil then
        -- we need MCU ID first
        return
    end

    local prefs = wfsuite.session.modelPreferences
    if not prefs then return end

    -- we dont support this feature on older firmwares
    if wfsuite.utils.apiVersionCompare("<", {12, 0, 9}) then
        wfsuite.utils.log("Skip stats sync as your firmware version is below 12.09", "info")
        isComplete = true
        return
    end


    -- fetch data from FC
    if fetchData == false then

        wfsuite.utils.log("Loading flight stats from RADIO before load", "info")
        LOCAL_STATS['totalflighttime'] = toNumber(wfsuite.ini.getvalue(prefs, "general", "totalflighttime"), 0)
        LOCAL_STATS['flightcount']     = toNumber(wfsuite.ini.getvalue(prefs, "general", "flightcount"), 0)

        local API = wfsuite.tasks.msp.api.load(API_NAME)
        if API and API.enableDeltaCache then API.enableDeltaCache(false) end
        API.setUUID("syncstats-read")
        API.setCompleteHandler(function(self, buf)
            FBL_STATS = copyTable(API.data().parsed) 

            wfsuite.utils.log("Loaded flight stats from FBL", "info")

            -- let's proceed to save
            saveData = true
            clearApiEntry()
        end)
        API.setErrorHandler(function() clearApiEntry() end)
        API.read()
    
        fetchData = true
    end

    if saveData == true then
    
        -- compare and decide which way we should sync
        local totalflighttimeRemote = toNumber(FBL_STATS['totalflighttime'], 0)
        local flightcountRemote     = toNumber(FBL_STATS['flightcount'], 0)

        local totalflighttimeLocal = LOCAL_STATS['totalflighttime']
        local flightcountLocal     = LOCAL_STATS['flightcount']

        wfsuite.utils.log("Total flight time - Remote: " .. tostring(totalflighttimeRemote) .. ", Local: " .. tostring(totalflighttimeLocal), "info")
        wfsuite.utils.log("Flight count - Remote: " .. tostring(flightcountRemote) .. ", Local: " .. tostring(flightcountLocal), "info")

        if totalflighttimeRemote > totalflighttimeLocal or flightcountRemote > flightcountLocal then
            -- remote is higher, update local
            wfsuite.ini.setvalue(prefs, "general", "totalflighttime", tostring(totalflighttimeRemote))
            wfsuite.ini.setvalue(prefs, "general", "flightcount", tostring(flightcountRemote))
            wfsuite.ini.save_ini_file(wfsuite.session.modelPreferencesFile, prefs)

            wfsuite.utils.log("Updated radio flight stats from FBL", "info")

            isComplete = true

        elseif totalflighttimeRemote < totalflighttimeLocal or flightcountRemote < flightcountLocal then
            -- local is higher, update remote
            local API = wfsuite.tasks.msp.api.load(API_NAME)
            if API and API.enableDeltaCache then API.enableDeltaCache(false) end
            API.setRebuildOnWrite(true)
            API.setUUID("syncstats-write")

            for i,v in pairs(FBL_STATS) do
                API.setValue(i, v)
            end

            API.setValue("totalflighttime", totalflighttimeLocal)
            API.setValue("flightcount", flightcountLocal)

            API.setCompleteHandler(function()
                wfsuite.utils.log("Updated FBL flight stats from radio", "info")
                saveToEeprom()
                isComplete = true
                clearApiEntry()
            end)
            API.setErrorHandler(function() clearApiEntry() end)
            API.write()
        else
            wfsuite.utils.log("Flight stats are already synchronized", "info")
            isComplete = true    
        end    
        
        saveData = false
    end

end

function sync.reset()
    clearApiEntry()
    isComplete = false
end

function sync.isComplete()
    return isComplete
end

return sync
