-- Schema + message-builders for the MSP_PID_PROFILE / MSP_SET_PID_PROFILE
-- command pair (cmd 94 read / 95 write).
--
-- Stateless: every function takes/returns plain tables, nothing is cached
-- here. Used by app/pages/pid_controller.lua to build request messages for
-- lib/bus.lua's "msp.request" topic (handled by tasks/background.lua's MSP
-- queue) -- this module never talks to tasks/msp/* directly itself.
--
-- Field order/types verified against wingflight-firmware's actual wire
-- serializer (src/main/msp/msp.c, MSP_PID_PROFILE/MSP_SET_PID_PROFILE
-- cases), which is NOT the same layout as stock rotorflight-firmware.
-- Wingflight MSP API 22.3 dropped the always-zero heli-only placeholder
-- bytes (error decay, error_rotation, yaw stop/precomp/collective FF,
-- cyclic cross-coupling, yaw inertia precomp) from this message, so none
-- of them are here: every FIELDS entry is a live field.
--   * the two `error_decay_time/limit_cyclic` fields the rotorflight-based
--     guess used are live fields, just renamed: wingflight-firmware's
--     struct calls them `iterm_decay_time`/`iterm_decay_limit` (no more
--     "cyclic" -- that was heli terminology).
--   * `offset_limit_0`/`offset_limit_1` ("HSI offset limit") do not exist
--     on wingflight-firmware's wire at all -- a rotorflight-only pair that
--     was wrongly inserted between `trainer_angle_limit` and
--     `atthold_gain`, corrupting every field after it. Removed.
--   * wingflight-firmware's struct also carries fields the rotorflight-
--     based guess never knew about, present here now at their correct
--     wire position: `atthold_gain`/`atthold_deadband` (right after the
--     trainer fields), `fw_tpa_gain`/`fw_tpa_curve`
--     (right after `bterm_cutoff_*`), `master_gain_0/1/2`
--     (U16 each), `autohover_gain`/`autohover_max_angle`/
--     `autohover_max_rate` (U16), `cross_axis_relax_strength/level/
--     cutoff/pitch_strength`, `gain_curve_0/1/2`, and a trailing
--     `atthold_max_rate` (U16). Matches this project's own last-known-good
--     schema (tasks/scheduler/msp/api/PID_PROFILE.lua as it stood at the
--     pre-rewrite HEAD) field-for-field, including field names and
--     min/max/default values -- that schema was itself already verified
--     against wingflight-firmware, so it is the authoritative source here,
--     not a fresh derivation.
--   * `autohover_roll_deadband` (U8) was appended after `atthold_max_rate`
--     by wingflight-firmware's PG_PID_PROFILE v9->v10 (see pg/pid.c): Auto
--     Hover previously left roll as a bare pass-through the whole time
--     (torque roll and other disturbances went uncorrected even with the
--     stick centered); now it holds roll once the stick is inside this
--     deadband, same track/freeze idea atthold_deadband already used.
--     Unconditionally in FIELDS like everything else here (see this file's
--     no-version-branching floor above) -- talking to firmware older than
--     v10 isn't a case this codec handles.
--   * `autohover_throttle_assist_gain`/`_max` (U8) and
--     `_trigger_ms` (U16) were appended after `autohover_roll_deadband` by
--     wingflight-firmware's PG_PID_PROFILE v10->v11 (see pg/pid.c): an
--     optional, opt-in nudge (0 gain = disabled/default) that adds throttle,
--     capped hard at `_max` percent and ramped in over `_trigger_ms`, only
--     while Auto Hover's pitch correction stays pinned at max_rate. Same
--     no-version-branching treatment as every other field in this file.
--
-- Unlike lib/msp_pid_tuning.lua's MSP_PID_TUNING (all U16), this command
-- mixes U8 and U16 fields -- FIELDS entries are {name, wireType} pairs, not
-- bare names; see decode()/encode() below for the dispatch.
--
-- This rebuild's floor is MSP API 22.3 (see lib/msp_api_version.lua), so
-- this codec never version-branches: every field is always present,
-- always read/written.

-- Self-caches via package.loaded (same mechanism lib/bus.lua uses) --
-- multiple pages share this codec and each reloads fresh via loadfile() on
-- every open, so without caching this was rebuilt on every navigation
-- too. See lib/msp_pid_tuning.lua's own comment for the full reasoning
-- (added after a live memory investigation, see AGENTS.md's "Memory
-- stats printing" section).
if package.loaded["wfsuite.lib.msp_pid_profile"] then
  return package.loaded["wfsuite.lib.msp_pid_profile"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 94
local WRITE_COMMAND = 95

local FIELDS = {
  {"pid_mode", "U8"},
  {"iterm_decay_time", "U8"},
  {"iterm_decay_limit", "U8"},
  {"error_limit_0", "U8"}, {"error_limit_1", "U8"}, {"error_limit_2", "U8"}, -- roll, pitch, yaw
  {"gyro_cutoff_0", "U8"}, {"gyro_cutoff_1", "U8"}, {"gyro_cutoff_2", "U8"},
  {"dterm_cutoff_0", "U8"}, {"dterm_cutoff_1", "U8"}, {"dterm_cutoff_2", "U8"},
  {"iterm_relax_type", "U8"},
  {"iterm_relax_cutoff_0", "U8"}, {"iterm_relax_cutoff_1", "U8"}, {"iterm_relax_cutoff_2", "U8"},
  {"angle_level_strength", "U8"},
  {"angle_level_limit", "U8"},
  {"horizon_level_strength", "U8"},
  {"trainer_gain", "U8"},
  {"trainer_angle_limit", "U8"},
  {"atthold_gain", "U8"},
  {"atthold_deadband", "U8"},
  {"bterm_cutoff_0", "U8"}, {"bterm_cutoff_1", "U8"}, {"bterm_cutoff_2", "U8"},
  {"fw_tpa_gain", "U8"},
  {"fw_tpa_curve", "U8"},
  {"master_gain_0", "U16"}, {"master_gain_1", "U16"}, {"master_gain_2", "U16"}, -- roll, pitch, yaw
  {"autohover_gain", "U8"},
  {"autohover_max_angle", "U8"},
  {"autohover_max_rate", "U16"},
  {"cross_axis_relax_strength", "U8"},
  {"cross_axis_relax_level", "U8"},
  {"cross_axis_relax_cutoff", "U8"},
  {"cross_axis_relax_pitch_strength", "U8"},
  {"gain_curve_0", "U8"}, {"gain_curve_1", "U8"}, {"gain_curve_2", "U8"}, -- roll, pitch, yaw
  {"atthold_max_rate", "U16"},
  {"autohover_roll_deadband", "U8"},
  {"autohover_throttle_assist_gain", "U8"},
  {"autohover_throttle_assist_max", "U8"},
  {"autohover_throttle_assist_trigger_ms", "U16"},
}

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua) -- one entry per FIELDS entry, in order (U16
-- fields as two little-endian bytes), using each field's firmware default.
-- Matches this project's own last-known-good SIM_RESPONSE byte-for-byte.
local SIMULATOR_RESPONSE = {
  1,    -- pid_mode
  6,    -- iterm_decay_time (0.6s, decimals=1)
  35,   -- iterm_decay_limit
  45, 45, 60,   -- error_limit_0/1/2 (roll, pitch, yaw)
  50, 50, 100,  -- gyro_cutoff_0/1/2
  15, 15, 20,   -- dterm_cutoff_0/1/2
  2,    -- iterm_relax_type
  10, 10, 15,   -- iterm_relax_cutoff_0/1/2
  40,   -- angle_level_strength
  55,   -- angle_level_limit
  0,    -- horizon_level_strength
  75,   -- trainer_gain
  20,   -- trainer_angle_limit
  40,   -- atthold_gain
  5,    -- atthold_deadband
  15, 15, 20,   -- bterm_cutoff_0/1/2
  100,  -- fw_tpa_gain
  0,    -- fw_tpa_curve
  100, 0, 100, 0, 100, 0, -- master_gain_0/1/2 (U16 LE: 100 -> 100, 0)
  50,   -- autohover_gain
  30,   -- autohover_max_angle
  44, 1, -- autohover_max_rate (U16 LE: 300 = 0x012C -> 44, 1)
  0,    -- cross_axis_relax_strength
  100,  -- cross_axis_relax_level
  10,   -- cross_axis_relax_cutoff
  0,    -- cross_axis_relax_pitch_strength
  0, 0, 0, -- gain_curve_0/1/2
  44, 1, -- atthold_max_rate (U16 LE: 300 = 0x012C -> 44, 1)
  5,    -- autohover_roll_deadband
  0,    -- autohover_throttle_assist_gain (disabled by default)
  15,   -- autohover_throttle_assist_max
  44, 1, -- autohover_throttle_assist_trigger_ms (U16 LE: 300 = 0x012C -> 44, 1)
}

-- Per-field {min, max, default, decimals, suffix}, sourced from this
-- project's own last-known-good tasks/scheduler/msp/api/PID_PROFILE.lua
-- FIELD_SPEC (field, type, min, max, default, unit, decimals, scale, ...).
-- `default` here is in the same *raw wire* domain as `min`/`max` (matching
-- how this rebuild's own app/field_layout.lua already treats decimals --
-- e.g. iterm_decay_time displays as "0.6s" but its actual field range/
-- value is 0-250 with decimals=1), not the display-scaled value the
-- original schema's own `default` column shows for that field.
--
-- Only fields an app/pages/*.lua page actually builds a widget for need an
-- entry to matter, but every field with a real (non-bare, non-choice,
-- non-bare) min/max/default is included, so a future page (e.g. Auto
-- Hover, Cross Axis Relax, Master Gain adjusters) can reuse this without a
-- second research pass. `pid_mode` and `iterm_relax_type` (choice/table
-- fields, never take a plain `:default()`) are deliberately absent.
local FIELD_META = {
  iterm_decay_time = {min = 0, max = 250, default = 6, decimals = 1, suffix = "s"},
  iterm_decay_limit = {min = 0, max = 60, default = 35, suffix = "°"},
  error_limit_0 = {min = 0, max = 180, default = 45, suffix = "°"},
  error_limit_1 = {min = 0, max = 180, default = 45, suffix = "°"},
  error_limit_2 = {min = 0, max = 180, default = 60, suffix = "°"},
  gyro_cutoff_0 = {min = 0, max = 250, default = 50},
  gyro_cutoff_1 = {min = 0, max = 250, default = 50},
  gyro_cutoff_2 = {min = 0, max = 250, default = 100},
  dterm_cutoff_0 = {min = 0, max = 250, default = 15},
  dterm_cutoff_1 = {min = 0, max = 250, default = 15},
  dterm_cutoff_2 = {min = 0, max = 250, default = 20},
  iterm_relax_cutoff_0 = {min = 1, max = 100, default = 10},
  iterm_relax_cutoff_1 = {min = 1, max = 100, default = 10},
  iterm_relax_cutoff_2 = {min = 1, max = 100, default = 15},
  angle_level_strength = {min = 0, max = 200, default = 40},
  angle_level_limit = {min = 10, max = 90, default = 55, suffix = "°"},
  horizon_level_strength = {min = 0, max = 200, default = 40},
  trainer_gain = {min = 25, max = 255, default = 75},
  trainer_angle_limit = {min = 10, max = 80, default = 20, suffix = "°"},
  atthold_gain = {min = 0, max = 250, default = 40},
  atthold_deadband = {min = 0, max = 100, default = 5, suffix = "%"},
  bterm_cutoff_0 = {min = 0, max = 250, default = 15},
  bterm_cutoff_1 = {min = 0, max = 250, default = 15},
  bterm_cutoff_2 = {min = 0, max = 250, default = 20},
  fw_tpa_gain = {min = 25, max = 200, default = 100, suffix = "%"},
  fw_tpa_curve = {min = 0, max = 8, default = 0},
  master_gain_0 = {min = 25, max = 1000, default = 100, suffix = "%"},
  master_gain_1 = {min = 25, max = 1000, default = 100, suffix = "%"},
  master_gain_2 = {min = 25, max = 1000, default = 100, suffix = "%"},
  autohover_gain = {min = 0, max = 250, default = 50},
  autohover_max_angle = {min = 0, max = 90, default = 30, suffix = "°"},
  autohover_max_rate = {min = 0, max = 1800, default = 300, suffix = "°/s"},
  cross_axis_relax_strength = {min = 0, max = 100, default = 0, suffix = "%"},
  cross_axis_relax_level = {min = 10, max = 250, default = 100},
  cross_axis_relax_cutoff = {min = 1, max = 100, default = 10, suffix = "Hz"},
  cross_axis_relax_pitch_strength = {min = 0, max = 100, default = 0, suffix = "%"},
  gain_curve_0 = {min = 0, max = 8, default = 0},
  gain_curve_1 = {min = 0, max = 8, default = 0},
  gain_curve_2 = {min = 0, max = 8, default = 0},
  atthold_max_rate = {min = 0, max = 1800, default = 300, suffix = "°/s"},
  autohover_roll_deadband = {min = 0, max = 100, default = 5, suffix = "%"},
  autohover_throttle_assist_gain = {min = 0, max = 100, default = 0, suffix = "%/s"},
  autohover_throttle_assist_max = {min = 0, max = 50, default = 15, suffix = "%"},
  autohover_throttle_assist_trigger_ms = {min = 0, max = 2000, default = 300, suffix = "ms"},
}

local msp_pid_profile = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FIELDS = FIELDS,
  FIELD_META = FIELD_META,
}

function msp_pid_profile.decode(buf)
  -- Always start from byte 1, even if `buf` is a reused/shared table (e.g.
  -- the simulator fixture above) that a previous decode() left an
  -- `.offset` on.
  buf.offset = 1
  local data = {}
  for i = 1, #FIELDS do
    local name, wireType = FIELDS[i][1], FIELDS[i][2]
    if wireType == "U16" then
      data[name] = mspcodec.readU16(buf)
    else
      data[name] = mspcodec.readU8(buf)
    end
  end
  return data
end

function msp_pid_profile.encode(data)
  local payload = {}
  for i = 1, #FIELDS do
    local name, wireType = FIELDS[i][1], FIELDS[i][2]
    if wireType == "U16" then
      mspcodec.writeU16(payload, data[name] or 0)
    else
      mspcodec.writeU8(payload, data[name] or 0)
    end
  end
  return payload
end

-- Builds a ready-to-publish message for lib/bus.lua's "msp.request" topic.
-- `onData(data)` is called with the decoded field table once the reply
-- arrives; `onError(reason)` (optional) on failure.
function msp_pid_profile.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_pid_profile.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- Builds a ready-to-publish write message. `onWritten()` (optional) is
-- called once the FC acknowledges the write; `onError(reason)` on failure.
-- `data` should be a full field table (everything in FIELDS, not just the
-- ones app/pages/pid_controller.lua exposes as editable widgets) -- see
-- that file's loadData()/performSave() for how the fields it doesn't
-- display are still round-tripped unchanged.
function msp_pid_profile.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_pid_profile.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_pid_profile"] = msp_pid_profile
return msp_pid_profile
