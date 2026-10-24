-- Flying-style starting points for the Setup Wizard's Flying style step,
-- applied to roll, pitch and yaw: rates (deg/s at full stick and expo
-- percent) and I-term relax (score 1-10 and level in deg/s).
--
-- A port of wingflight-configurator src/tabs/setup_wizard/styles.js; the
-- style cases in bin/tests/setup_wizard_controls.lua are the configurator's
-- own. The JS works on the configurator's scaled RC_TUNING (rate as deg/s /
-- 500, expo as a fraction); this works on the wire values lib/msp_rc_tuning.lua
-- decodes, which are those times 100: rcRates_n = deg/s / 5, rcExpo_n =
-- expo percent. lib/msp_pid_profile.lua's bounceback_n and
-- iterm_relax_level_n are already the score and the level. n is 1/2/3 for
-- roll/pitch/yaw in the rate codec and 0/1/2 in the PID profile codec.

if package.loaded["wfsuite.lib.setup_wizard_styles"] then
  return package.loaded["wfsuite.lib.setup_wizard_styles"]
end

local M = {}

M.STYLES = {
  {key = "trainer", rate = {roll = 150, pitch = 120, yaw = 90}, expo = 20, relax = 3, relaxLevel = 30},
  {key = "sport", rate = {roll = 250, pitch = 200, yaw = 150}, expo = 30, relax = 5, relaxLevel = 22},
  {key = "3d", rate = {roll = 500, pitch = 400, yaw = 300}, expo = 60, relax = 7, relaxLevel = 15},
}

M.AXES = {"roll", "pitch", "yaw"}
local RATE_N = {roll = 1, pitch = 2, yaw = 3}
local PID_N = {roll = 0, pitch = 1, yaw = 2}

local function round(x) return math.floor(x + 0.5) end

function M.rateOf(rcTuning, axis)
  return round((rcTuning["rcRates_" .. RATE_N[axis]] or 0) * 5)
end

function M.expoOf(rcTuning, axis)
  return rcTuning["rcExpo_" .. RATE_N[axis]] or 0
end

function M.relaxOf(pidProfile, axis)
  return pidProfile["bounceback_" .. PID_N[axis]]
end

function M.relaxLevelOf(pidProfile, axis)
  return pidProfile["iterm_relax_level_" .. PID_N[axis]]
end

function M.matchingStyle(rcTuning, pidProfile)
  for _, style in ipairs(M.STYLES) do
    local all = true
    for _, a in ipairs(M.AXES) do
      if M.rateOf(rcTuning, a) ~= style.rate[a] or M.expoOf(rcTuning, a) ~= style.expo
          or M.relaxOf(pidProfile, a) ~= style.relax or M.relaxLevelOf(pidProfile, a) ~= style.relaxLevel then
        all = false
        break
      end
    end
    if all then return style end
  end
  return nil
end

function M.applyStyle(style, rcTuning, pidProfile)
  for _, axis in ipairs(M.AXES) do
    rcTuning["rcRates_" .. RATE_N[axis]] = round(style.rate[axis] / 5)
    rcTuning["rcExpo_" .. RATE_N[axis]] = style.expo
    pidProfile["bounceback_" .. PID_N[axis]] = style.relax
    pidProfile["iterm_relax_level_" .. PID_N[axis]] = style.relaxLevel
  end
end

package.loaded["wfsuite.lib.setup_wizard_styles"] = M
return M
