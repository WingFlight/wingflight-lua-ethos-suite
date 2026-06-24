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
local groundAltitude = nil

local tasks = wfsuite.tasks
local utils = wfsuite.utils

local throttleThreshold = 35
local altitudeGainThreshold = 3 -- meters climbed above the armed/launch baseline

function flightmode.inFlight()
    local telemetry = tasks.telemetry

    if not wfsuite.session.isArmed or not telemetry or (telemetry.active and not telemetry.active()) then return false end

    local altSource = telemetry.getSensorSource and telemetry.getSensorSource("altitude")
    local altitude = altSource and altSource:value()

    if altitude then
        if groundAltitude == nil then groundAltitude = altitude end
        return (altitude - groundAltitude) > altitudeGainThreshold
    end

    -- No altitude sensor available: fall back to throttle stick position.
    local rx = wfsuite.session.rx
    local throttle = rx and rx.values and rx.values.throttle

    if throttle and throttle > throttleThreshold then return true end

    return false
end

function flightmode.reset()
    lastFlightMode = nil
    hasBeenInFlight = false
    groundAltitude = nil
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
        groundAltitude = nil
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
