-- Display scaling for MSP_RC_TUNING's three "curve shape" fields per axis:
-- rcRates_N (RC Rate), rcExpo_N (RC Expo), rates_N ("Shape"). Used only by
-- app/pages/rates.lua; lib/msp_rc_tuning.lua itself stays raw-values-only
-- like every other codec (see its own header comment).
--
-- wingflight-firmware hardcodes a single rate-curve formula now --
-- `rates_type` is wire-present but dead (see lib/msp_rc_tuning.lua's own
-- header, and src/main/fc/rc_rates.c's applyWingflightRates(), the only
-- curve function the firmware still calls). The pre-rewrite project
-- supported 7 selectable rate tables (None/Betaflight/Raceflight/Kiss/
-- Actual/Quick/Rotorflight) via a runtime rates_type lookup; only the
-- last of those -- rotorflight-lua-ethos-suite's own "Rotorflight" native
-- table -- has ever matched wingflight-firmware's formula (renamed
-- "Wingflight" here, matching this project's wider rebrand), so the other
-- 6 are unreachable dead weight now, not just unused: there is no wire
-- value that selects them any more. Gutted rather than kept "just in
-- case" -- this project's own RAM-consciousness (see AGENTS.md) argues
-- against carrying six tables' worth of unreachable data.
--
-- The Wingflight scale/decimals values themselves are unchanged from the
-- pre-rewrite project's own RATE_TYPE_ROTORFLIGHT entry (renamed, not
-- re-derived) -- confirmed still correct against wingflight-firmware's
-- applyWingflightRates(): `rcRate = rcRates[axis] * 5` matches this
-- module's rcRate divisor of 500 (displayed = raw * 500/100 = raw * 5);
-- `rcExpo = rcExpo[axis] / 100.0` matches expo's divisor of 100
-- (displayed = raw, i.e. the wire byte shown directly as a 0-100 value).
--
-- The relationship: given a raw wire byte (0-255) and the divisor below,
-- the *true* human-friendly value is `raw * divisor / 100` (e.g. 1.20,
-- 12.5, 240). Ethos's own number-field widget works in an integer domain,
-- showing that integer divided by 10^decimals for the final render.

if package.loaded["wfsuite.lib.rate_curve_scale"] then
  return package.loaded["wfsuite.lib.rate_curve_scale"]
end

-- "main" = roll/pitch/yaw (axes 1-3, always share one scale); "col" =
-- collective (axis 4) -- wire-present but dead on wingflight-firmware
-- (see lib/msp_rc_tuning.lua), so app/pages/rates.lua no longer builds a
-- row for it, but the scale is kept here for completeness/symmetry with
-- the codec's own field shape.
local SCALE = {
  rcRate = {main = 500, col = 12.5},
  srate = {main = 100, col = 100},
  expo = {main = 100, col = 100},
}

local DECIMALS = {
  rcRate = {main = 0, col = 2},
  srate = {main = 0, col = 0},
  expo = {main = 0, col = 0},
}

-- Default raw wire bytes per axis (1 = roll, 2 = pitch, 3 = yaw), carried
-- over from the pre-rewrite project's own ratetables/wingflight.lua
-- defaults (see `git show 0a94e6f7` in this repo's history) -- RC Rate
-- runs yaw hotter than roll/pitch; Shape and RC Expo are the same raw
-- value on all three axes. Only "main" axes have an entry: no row is
-- ever built for the wire-present-but-dead collective axis (see this
-- file's own header and app/pages/rates.lua).
local DEFAULT_RAW = {
  rcRate = {50, 50, 70},
  srate = {5, 5, 5},
  expo = {30, 30, 30},
}

local rate_curve_scale = {}

-- role: "rcRate" | "srate" | "expo". axisClass: "main" | "col".
local function scaleFor(role, axisClass)
  return SCALE[role][axisClass]
end
rate_curve_scale.scaleFor = scaleFor

local function decimalsFor(role, axisClass)
  return DECIMALS[role][axisClass]
end
rate_curve_scale.decimalsFor = decimalsFor

-- Raw wire byte -> the integer Ethos's own number-field widget should
-- get()/be constructed with (still subject to the widget's own
-- field:decimals(n) call for final cosmetic display -- see decimalsFor()
-- above). displayInt = raw * divisor/100 (the true friendly value) *
-- 10^decimals.
function rate_curve_scale.toDisplayInt(raw, role, axisClass)
  local divisor = scaleFor(role, axisClass)
  local scale = 10 ^ decimalsFor(role, axisClass)
  return math.floor((raw or 0) * divisor / 100 * scale + 0.5)
end

-- The widget's edited integer (already in the same displayInt domain
-- toDisplayInt() produces) -> the raw wire byte to store/send. Clamped to
-- a real U8's range so mspcodec.writeU8() never silently wraps via
-- `value % 256`.
function rate_curve_scale.fromDisplayInt(displayInt, role, axisClass)
  local divisor = scaleFor(role, axisClass)
  local scale = 10 ^ decimalsFor(role, axisClass)
  local raw = math.floor((displayInt or 0) / scale * 100 / divisor + 0.5)
  if raw < 0 then return 0 end
  if raw > 255 then return 255 end
  return raw
end

-- Display-domain bounds AND decimals for a field's widget. Min is always
-- 0; max is derived from the same divisor the live conversion uses, so
-- it can never drift out of sync with it.
function rate_curve_scale.displayBounds(role, axisClass)
  return 0, rate_curve_scale.toDisplayInt(255, role, axisClass), decimalsFor(role, axisClass)
end

function rate_curve_scale.displayStep(role, axisClass)
  local step = rate_curve_scale.toDisplayInt(1, role, axisClass)
  return step > 0 and step or 1
end

-- role: "rcRate" | "srate" | "expo". axis: 1 (roll) | 2 (pitch) | 3 (yaw).
-- Same displayInt domain as toDisplayInt() above, so callers can pass
-- this straight to a number field's field:default().
function rate_curve_scale.defaultDisplayInt(role, axis, axisClass)
  return rate_curve_scale.toDisplayInt(DEFAULT_RAW[role][axis], role, axisClass)
end

package.loaded["wfsuite.lib.rate_curve_scale"] = rate_curve_scale
return rate_curve_scale
