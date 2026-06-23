--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local flightmode = {}

local runOnce = false

function flightmode.wakeup()

    wfsuite.flightmode.current = "preflight"
    if wfsuite.tasks and wfsuite.tasks.events and wfsuite.tasks.events.flightmode then
      wfsuite.tasks.events.flightmode.reset()
    end

    runOnce = true

end

function flightmode.reset() runOnce = false end

function flightmode.isComplete() return runOnce end

return flightmode
