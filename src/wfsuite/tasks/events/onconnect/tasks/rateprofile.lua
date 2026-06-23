--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local wfsuite = require("wfsuite")

local rateprofile = {}

local runOnce = false

function rateprofile.wakeup()

    if wfsuite.session.apiVersion == nil then return end

    if wfsuite.utils.apiVersionCompare(">=", {12, 0, 9}) then
      -- we use rotorflight rates for 12.09 and above
      wfsuite.config.defaultRateProfile = 6
      wfsuite.utils.log("Default Rate Profile: ROTORFLIGHT", "console")
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
