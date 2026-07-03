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

local utils = wfsuite.utils

-- "Are we actually flying" is decided by firmware and delivered as the INFLIGHT_MODE bit on the
-- flight_mode sensor (see sensor_table.lua's onchange handler, which sets session.isInFlight).
-- Firmware already latches this while armed, so no throttle/altitude re-derivation is needed here.
function flightmode.inFlight()
    return wfsuite.session.isInFlight == true
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

    -- Firmware already latches INFLIGHT_MODE through momentary throttle/mode dips (and now also
    -- clears it early -- while still armed -- when idle up was used this flight and gets switched
    -- off with throttle back at idle, read as "landed"). So flightmode.inFlight() going false here
    -- while still armed is a real transition, not sensor noise -- no Lua-side "hold while armed"
    -- override needed (or wanted: it would block that early postflight transition).
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
