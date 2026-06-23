--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local timer = {}

local runOnce = false

function timer.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.session.mspBusy then return end

    wfsuite.session.timer = {}
    wfsuite.session.timer.start = nil
    wfsuite.session.timer.live = nil
    wfsuite.session.timer.lifetime = nil
    wfsuite.session.timer.session = 0
    runOnce = true

end

function timer.reset() runOnce = false end

function timer.isComplete() return runOnce end

return timer
