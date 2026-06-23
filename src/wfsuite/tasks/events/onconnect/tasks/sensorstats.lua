--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local sensorstats = {}

local runOnce = false

function sensorstats.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.session.mspBusy then return end

    if wfsuite.tasks.telemetry then
        wfsuite.tasks.telemetry.sensorStats = {}
        runOnce = true
    end
end

function sensorstats.reset() runOnce = false end

function sensorstats.isComplete() return runOnce end

return sensorstats
