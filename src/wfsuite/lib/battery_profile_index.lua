-- Battery profile index bases.
--
-- Two different bases meet in this suite for the *same* number, and mixing
-- them up is an off-by-one in both directions -- so this file keeps the two
-- apart instead of letting one helper "accept either base".
--
-- 0-based is the canonical internal representation, and everything the suite
-- itself stores or hands to the flight controller is in it:
--   - lib/msp_battery_profile.lua's PROFILE_CHOICES maps the labels
--     "1".."6" onto the values 0..5.
--   - lib/msp_battery.lua decodes the six capacities into profiles[0]..[5]
--     and the per-profile cells into profileCells[0]..[5].
--   - MSP 175 (MSP_BATTERY_PROFILE) replies with the raw 0-based
--     `batteryConfig()->batteryProfile`, and MSP 176
--     (MSP_SET_BATTERY_PROFILE) takes a 0-based index
--     (wingflight-firmware src/main/msp/msp.c).
--   - session.batteryProfile, widget.batteryProfile and the dashboard
--     selector's own profile.idx are all in this base too.
--
-- 1-based exists in exactly one place: the battery profile field of the
-- packed `system_config` telemetry word, which the firmware reports as
-- `getCurrentBatteryProfileIndex() + 1` (wingflight-firmware
-- src/main/telemetry/status.c telemetrySystemConfig()) -- the same `+ 1` as
-- the PID/rate/TV profile fields beside it. That conversion is done once, at
-- its single ingress point (tasks/session.lua's updateProfiles()), via
-- fromTelemetrySensor() below, and nowhere else.
--
-- Why the separation is load-bearing: the old normalizeBatteryProfile() was a
-- single "accept either base" helper that checked `>= 1 and <= 6` first and
-- decremented. Applied to an already-0-based 1..5 it subtracted one, so
-- selecting pack 3 in the dashboard wrote pack 2's index to the FC, and the
-- session then shifted it again and applied pack 1's capacity and cells to
-- SmartFuel. It was also not injective -- normalize(0) == normalize(1) == 0.
-- Ported from rotorflight-lua-ethos-suite #2397.

if package.loaded["wfsuite.lib.battery_profile_index"] then
  return package.loaded["wfsuite.lib.battery_profile_index"]
end

local battery_profile_index = {}

local PROFILE_COUNT = 6

-- Validates an internal 0-based profile index. Returns the index as an
-- integer, or nil for anything out of range / non-numeric -- never a
-- silently adjusted value.
function battery_profile_index.index0(value)
  local index = tonumber(value)
  if index == nil then return nil end
  index = math.floor(index)
  if index >= 0 and index < PROFILE_COUNT then return index end
  return nil
end

-- The one 1-based -> 0-based conversion, for the telemetry reading only. A
-- valid reading is always 1..6, so 0 is *not* accepted: the caller keeps its
-- last known good value instead.
function battery_profile_index.fromTelemetrySensor(value)
  local index = tonumber(value)
  if index == nil then return nil end
  index = math.floor(index)
  if index >= 1 and index <= PROFILE_COUNT then return index - 1 end
  return nil
end

-- 1-based label for a 0-based index -- the pack number the pilot is shown.
function battery_profile_index.label(index)
  index = battery_profile_index.index0(index)
  if index == nil then return nil end
  return index + 1
end

package.loaded["wfsuite.lib.battery_profile_index"] = battery_profile_index
return battery_profile_index
