--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local simevent = {}

-- Localize globals
local loadfile = loadfile
local pcall = pcall
local pairs = pairs
local print = print

-- Cache simulation state
local isSim = system.getVersion().simulation

-- Ensure wfsuite.simevent exists
wfsuite.simevent = wfsuite.simevent or {}

local source = "SCRIPTS:/" .. wfsuite.config.baseDir .. "/sim/sensors/"

local handlers = {
    simevent_telemetry_state = function(value) wfsuite.simevent.telemetry_state = (value == 0) end
}

-- Pre-calculate paths
local handlerPaths = {}
for name, _ in pairs(handlers) do
    handlerPaths[name] = source .. name .. ".lua"
end

local lastValues = {}

function simevent.wakeup()
    if not isSim then return end

    for name, handler in pairs(handlers) do
        local path = handlerPaths[name]

        local chunk, loadErr = loadfile(path)
        if not chunk then
            print(("sim: could not load %s.lua: %s"):format(name, loadErr))
        else
            local success, result = pcall(chunk)

            if success then
                if result ~= lastValues[name] then
                    lastValues[name] = result
                    handler(result)
                end
            else
                print("sim: error executing " .. name .. ": " .. tostring(result))
            end
        end
    end
end


return simevent
