--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local rateprofile = {}

local runOnce = false

function rateprofile.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.utils.apiVersionCompare(">=", {22, 0, 0}) then
      -- wingflight only has one rate curve now
      wfsuite.config.defaultRateProfile = 0
      wfsuite.utils.log("Default Rate Profile: WINGFLIGHT", "console")
    else
      -- we use actual rates for below 12.09
      wfsuite.config.defaultRateProfile = 4 
      wfsuite.utils.log("Default Rate Profile: ACTUAL", "console")
    end  

    runOnce = true

end

function rateprofile.reset() runOnce = false end

function rateprofile.isComplete() return runOnce end

return rateprofile
