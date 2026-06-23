--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local arg = {...}

local flightmode = {}
local lastFlightMode = nil
local hasBeenInFlight = false
local lastArmed = false

local tasks = wfsuite.tasks
local utils = wfsuite.utils

local throttleThreshold = 35

local function isGovernorActive(value) return type(value) == "number" and value >= 4 and value <= 8 end

function flightmode.inFlight()
    local telemetry = tasks.telemetry

    if not wfsuite.session.isArmed or not telemetry or (telemetry.active and not telemetry.active()) then return false end

    local governor = telemetry.getSensor("governor")
    if isGovernorActive(governor) then return true end

    local rx = wfsuite.session.rx
    local throttle = rx and rx.values and rx.values.throttle

    if throttle and throttle > throttleThreshold then return true end

    return false
end

function flightmode.reset()
    lastFlightMode = nil
    hasBeenInFlight = false
end

local function determineMode()
    local armed = wfsuite.session.isArmed
    local connected = wfsuite.session.isConnected
    local current = wfsuite.flightmode.current

    if current == "inflight" and not connected then
        hasBeenInFlight = false
        lastArmed = armed
        return "postflight"
    end

    if armed and not lastArmed then
        hasBeenInFlight = false
        lastArmed = armed
        return "preflight"
    end

    if flightmode.inFlight() then
        hasBeenInFlight = true
        lastArmed = armed
        return "inflight"
    end

    -- Hold inflight while the model remains armed after flight has started.
    -- This avoids transient sensor/telemetry gaps flipping to postflight mid-flight,
    -- which can reset dashboard/runtime state and Smart Fuel tracking.
    if armed and hasBeenInFlight then
        lastArmed = armed
        return "inflight"
    end

    lastArmed = armed
    return hasBeenInFlight and "postflight" or "preflight"
end

function flightmode.wakeup()
    local mode = determineMode()
    
    if lastFlightMode ~= mode then
        utils.log("Flight mode: " .. mode, "info")
        wfsuite.flightmode.current = mode
        lastFlightMode = mode
    end
end

return flightmode
