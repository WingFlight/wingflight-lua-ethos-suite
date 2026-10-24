-- Pure helpers for the Setup Wizard: which servos are control surfaces, how
-- far full stick drives each one, and the scale that keeps full stick inside
-- a servo's limits.
--
-- A port of wingflight-configurator src/tabs/setup_wizard/surfaces.js. Keep
-- the two in step: the cases in bin/tests/setup_wizard_surfaces.lua are the
-- ones in the configurator's scripts/tests/setup-wizard-surfaces.test.mjs.
-- Differences from the JS:
--   * rules have the shape lib/msp_mixer_rules.lua decodes: `input` and
--     `output` where the configurator has `src` and `dst`.
--   * a surface's axes are a table keyed by axis, plus `axisOrder` (the axes
--     in the order their rules came), which stands in for the JS object's key
--     order wherever that order matters (primaryAxis()).
--   * travelReach() leaves out the servo balance curve for now; the Travel
--     step adds it when it is ported.
--
-- Mirrors the firmware signal chain (wingflight-firmware flight/mixer.c
-- mixerUpdateRules() and flight/servos.c servoUpdate()):
--
--   input (+-1) * axis throw -> rule weight (input >= 0) / weightNeg (< 0)
--   -> sum on the output -> balance curve -> servo reverse
--   -> scale rpos/rneg (us) -> min/max

if package.loaded["wfsuite.lib.setup_wizard_surfaces"] then
  return package.loaded["wfsuite.lib.setup_wizard_surfaces"]
end

local M = {}

-- Stabilized mixer inputs (MIXER_IN_STABILIZED_ROLL/PITCH/YAW).
M.AXES = {
  {key = "roll", input = 1},
  {key = "pitch", input = 2},
  {key = "yaw", input = 3},
}

local OP_SET = 1
local OP_ADD = 2

-- MIXER_IN_RC_CHANNEL_AUX1, the channel the Mixer setup drives flaps from.
-- The wizard takes channel centre as flaps up and positive as flaps down.
M.FLAP_INPUT = 13

-- Servo config flags (SERVO_FLAG_REVERSED).
M.SERVO_FLAG_REVERSE = 1

-- Scale range the wizard will set (us per unit of output). Below the minimum
-- a side has almost no travel; the maximum is the servo travel limit
-- (SERVO_LIMIT_MAX in the firmware's flight/servos.h).
M.SCALE_MIN = 50
M.SCALE_MAX = 1000

-- Mixer outputs 1..n are servos 0..n-1 (MIXER_SERVO_OFFSET).
local SERVO_OUTPUT_OFFSET = 1

local function axisForInput(input)
  for i = 1, #M.AXES do
    if M.AXES[i].input == input then return M.AXES[i] end
  end
  return nil
end

local function moves(w)
  return w ~= nil and (w.pos ~= 0 or w.neg ~= 0)
end

function M.surfaceKind(axes, flap, base)
  local roll = moves(axes.roll)
  local pitch = moves(axes.pitch)
  local yaw = moves(axes.yaw)
  -- A flap servo, alone or with roll ADDed on (flaps that follow the ailerons).
  if moves(flap) and not pitch and not yaw and (not roll or base == "flap") then
    return "flap"
  end
  if roll and pitch and not yaw then return "elevon" end
  if pitch and yaw and not roll then return "ruddervator" end
  if roll and not pitch and not yaw then
    return moves(flap) and "flaperon" or "aileron"
  end
  if pitch and not roll and not yaw then return "elevator" end
  if yaw and not roll and not pitch then return "rudder" end
  return "mixed"
end

-- Contribution of each stabilized axis to each servo output, as weight
-- fractions for positive and negative input. Only SET/ADD rules count; MUL
-- rules and conditions are ignored, since the wizard sets up the plain
-- surface mix. The flap channel is kept apart as `flap` (in the same pos/neg
-- form). `base` is the input of the servo's last SET rule (an axis key or
-- "flap"): the input the servo is built on, which the rest are ADDed onto.
-- Returns a list sorted by servo (0-based).
function M.surfacesFromRules(rules, servoCount)
  local byServo = {}
  local servos = {}

  for i = 1, #rules do
    local rule = rules[i]
    local oper = rule.oper
    local axis = axisForInput(rule.input)
    local servo = (rule.output or 0) - SERVO_OUTPUT_OFFSET
    if (oper == OP_SET or oper == OP_ADD)
        and (axis or rule.input == M.FLAP_INPUT)
        and servo >= 0 and servo < servoCount then
      local entry = byServo[servo]
      if not entry then
        entry = {servo = servo, axes = {}, axisOrder = {}, flap = nil, base = nil}
        byServo[servo] = entry
        servos[#servos + 1] = servo
      end
      local prev
      if axis then prev = entry.axes[axis.key] else prev = entry.flap end
      prev = prev or {pos = 0, neg = 0}
      local set = oper == OP_SET
      local nextWeights = {
        pos = (set and 0 or prev.pos) + (rule.weight or 0) / 1000,
        neg = (set and 0 or prev.neg) + (rule.weightNeg or 0) / 1000,
      }
      if axis then
        if entry.axes[axis.key] == nil then
          entry.axisOrder[#entry.axisOrder + 1] = axis.key
        end
        entry.axes[axis.key] = nextWeights
      else
        entry.flap = nextWeights
      end
      if set then entry.base = axis and axis.key or "flap" end
    end
  end

  table.sort(servos)
  local out = {}
  for i = 1, #servos do
    local s = byServo[servos[i]]
    local anyAxis = false
    for _, w in pairs(s.axes) do
      if moves(w) then anyAxis = true end
    end
    if moves(s.flap) or anyAxis then
      s.kind = M.surfaceKind(s.axes, s.flap, s.base)
      out[#out + 1] = s
    end
  end
  return out
end

-- Servo numbers (1-based) that the surface mix drives but that are past the
-- board's servo outputs (up to `slots`), so surfacesFromRules() leaves them
-- out. The firmware only counts servo pins with a timer assigned (servoInit()
-- in flight/servos.c), so a flap mixed onto servo 5 of a board with 4 servo
-- pins never moves.
function M.servosPastCount(rules, servoCount, slots)
  local seen, out = {}, {}
  for i = 1, #rules do
    local rule = rules[i]
    local dst = rule.output or 0
    if (rule.oper == OP_SET or rule.oper == OP_ADD)
        and (axisForInput(rule.input) or rule.input == M.FLAP_INPUT)
        and not ((rule.weight or 0) == 0 and (rule.weightNeg or 0) == 0)
        and dst > servoCount and dst <= slots and not seen[dst] then
      seen[dst] = true
      out[#out + 1] = dst
    end
  end
  table.sort(out)
  return out
end

-- The input the wizard uses to move a surface on its own: an axis key, or
-- "flap" for the flap channel.
function M.primaryAxis(surface)
  local kind = surface.kind
  if kind == "flap" then return "flap" end
  if kind == "aileron" or kind == "flaperon" then return "roll" end
  if kind == "rudder" then return "yaw" end
  if surface.axes.pitch then return "pitch" end
  return surface.axisOrder[1]
end

-- Mixer output for this surface with the given axis held at +1 or -1 (stick
-- = +1 / -1) and every other axis at 0.
function M.outputForAxis(surface, axisKey, stick, axisGains)
  local w = surface.axes[axisKey]
  if not w then return 0 end
  local gain = axisGains[axisKey] or 1
  local input = stick * gain
  if input >= 0 then return input * w.pos end
  return input * w.neg
end

-- Mixer output for this surface with the flap channel at +1 (full flap) or -1
-- and every axis at 0.
function M.outputForFlap(surface, stick)
  local w = surface.flap
  if not w then return 0 end
  if stick >= 0 then return stick * w.pos end
  return stick * w.neg
end

-- Servo side ("pos" uses rpos/max, "neg" uses rneg/min) that a mixer output
-- lands on after the servo's reverse flag.
function M.servoSide(output, reversed)
  local signed = reversed and -output or output
  return signed >= 0 and "pos" or "neg"
end

-- Worst-case reach of each servo side with every axis at full stick in the
-- direction that pushes that side furthest (and the flap channel, if the
-- surface has one, at whichever end does the same), in us and as a fraction
-- of the side's travel limit. fraction > 1 means the surface hits its limit
-- before full stick on every axis at once.
function M.travelReach(surface, servoConfig, axisGains)
  local reversed = ((servoConfig.flags or 0) & M.SERVO_FLAG_REVERSE) ~= 0
  -- Highest and lowest mixer output, before reverse.
  local hi, lo = 0, 0

  for axisKey in pairs(surface.axes) do
    local up = M.outputForAxis(surface, axisKey, 1, axisGains)
    local down = M.outputForAxis(surface, axisKey, -1, axisGains)
    hi = hi + math.max(up, down, 0)
    lo = lo + math.min(up, down, 0)
  end

  if surface.flap then
    -- Flap channel at +1 (weight) and -1 (weightNeg).
    local up = surface.flap.pos
    local down = -surface.flap.neg
    hi = hi + math.max(up, down, 0)
    lo = lo + math.min(up, down, 0)
  end

  local pos = reversed and -lo or hi
  local neg = reversed and -hi or lo

  local posUs = pos * servoConfig.rpos
  local negUs = -neg * servoConfig.rneg
  local posLimit = math.max(servoConfig.max, 0)
  local negLimit = math.max(-servoConfig.min, 0)

  return {
    pos = {us = posUs, limit = posLimit, fraction = posLimit > 0 and posUs / posLimit or 0},
    neg = {us = negUs, limit = negLimit, fraction = negLimit > 0 and negUs / negLimit or 0},
  }
end

-- Axis Throw of each stabilized axis as a multiplier, from the mixer input
-- rates (per mille, negative when the axis is inverted), keyed by axis.
function M.axisGainsFromRates(rates)
  local gains = {}
  for i = 1, #M.AXES do
    local key = M.AXES[i].key
    gains[key] = ((rates and rates[key]) or 1000) / 1000
  end
  return gains
end

-- Largest scale (us) for one servo side at which full stick (mixer output
-- `output` on that side) still stays inside the side's binding limit. Past it
-- the surface would stop at the limit before full stick.
function M.maxScale(output, sideLimit)
  local out = math.abs(output)
  if not (out > 0) or not (sideLimit > 0) then return M.SCALE_MAX end
  return math.max(M.SCALE_MIN, math.min(M.SCALE_MAX, math.floor(sideLimit / out)))
end

package.loaded["wfsuite.lib.setup_wizard_surfaces"] = M
return M
