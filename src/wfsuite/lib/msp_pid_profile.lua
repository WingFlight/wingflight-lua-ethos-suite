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
-- cases), which is NOT the same layout as stock rotorflight-firmware: this
-- rebuild's own field order was originally cross-checked against
-- rotorflight-firmware only, which put it out of alignment with wingflight
-- in several places, corrected here --
--   * `error_decay_time_ground`, `error_decay_time_yaw`,
--     `error_decay_limit_yaw`, `yaw_cw_stop_gain`, `yaw_ccw_stop_gain`,
--     `yaw_precomp_cutoff`, `yaw_cyclic_ff_gain`, `yaw_collective_ff_gain`,
--     `yaw_collective_dynamic_gain`, `yaw_collective_dynamic_decay`,
--     `pitch_collective_ff_gain`, `cyclic_cross_coupling_gain/ratio/cutoff`,
--     `yaw_inertia_precomp_gain/cutoff` are heli-only: wingflight-firmware
--     still writes/reads a placeholder byte at each position (so the wire
--     offsets of every field after them stay correct) but the FC no longer
--     stores or acts on the value -- decoded/encoded in-place, never
--     skipped, never given a FIELD_META entry or a page widget.
--   * `error_rotation` is *hardcoded* to 1 on read and discarded on write --
--     same treatment, kept only for wire alignment.
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
--     dead cyclic-cross-coupling trio), `fw_tpa_gain`/`fw_tpa_curve`
--     (right after the dead inertia-precomp pair), `master_gain_0/1/2`
--     (U16 each), `autohover_gain`/`autohover_max_angle`/
--     `autohover_max_rate` (U16), `cross_axis_relax_strength/level/
--     cutoff/pitch_strength`, `gain_curve_0/1/2`, and a trailing
--     `atthold_max_rate` (U16). Matches this project's own last-known-good
--     schema (tasks/scheduler/msp/api/PID_PROFILE.lua as it stood at the
--     pre-rewrite HEAD) field-for-field, including field names and
--     min/max/default values -- that schema was itself already verified
--     against wingflight-firmware, so it is the authoritative source here,
--     not a fresh derivation.
--
-- Unlike lib/msp_pid_tuning.lua's MSP_PID_TUNING (all U16), this command
-- mixes U8 and U16 fields -- FIELDS entries are {name, wireType} pairs, not
-- bare names; see decode()/encode() below for the dispatch.
--
-- This rebuild's floor is API >= 12.09 (see AGENTS.md), so unlike the
-- pre-rewrite project this codec never version-branches: every field is
-- always present, always read/written.

-- Self-caches via package.loaded (same mechanism lib/bus.lua uses) --
-- multiple pages share this codec and each reloads fresh via loadfile() on
-- every open, so without caching this was rebuilt on every navigation
-- too. See lib/msp_pid_tuning.lua's own comment for the full reasoning
-- (added after a live memory investigation, see AGENTS.md's "Memory
-- stats printing" section).
if package.loaded["wfsuite.lib.msp_pid_profile"] then
  return package.loaded["wfsuite.lib.msp_pid_profile"]
end

local mspcodec = assert(loadfile("lib/mspcodec.lua"))()

local READ_COMMAND = 94
local WRITE_COMMAND = 95

local FIELDS = {
  {"pid_mode", "U8"},
  {"error_decay_time_ground", "U8"}, -- dead: heli-only, FC ignores
  {"iterm_decay_time", "U8"},
  {"error_decay_time_yaw", "U8"}, -- dead: heli-only, FC ignores
  {"iterm_decay_limit", "U8"},
  {"error_decay_limit_yaw", "U8"}, -- dead: heli-only, FC ignores
  {"error_rotation", "U8"}, -- dead: FC always reads back 1, write discarded
  {"error_limit_0", "U8"}, {"error_limit_1", "U8"}, {"error_limit_2", "U8"}, -- roll, pitch, yaw
  {"gyro_cutoff_0", "U8"}, {"gyro_cutoff_1", "U8"}, {"gyro_cutoff_2", "U8"},
  {"dterm_cutoff_0", "U8"}, {"dterm_cutoff_1", "U8"}, {"dterm_cutoff_2", "U8"},
  {"iterm_relax_type", "U8"},
  {"iterm_relax_cutoff_0", "U8"}, {"iterm_relax_cutoff_1", "U8"}, {"iterm_relax_cutoff_2", "U8"},
  {"yaw_cw_stop_gain", "U8"}, -- dead: heli-only, FC ignores
  {"yaw_ccw_stop_gain", "U8"}, -- dead: heli-only, FC ignores
  {"yaw_precomp_cutoff", "U8"}, -- dead: heli-only, FC ignores
  {"yaw_cyclic_ff_gain", "U8"}, -- dead: heli-only, FC ignores
  {"yaw_collective_ff_gain", "U8"}, -- dead: heli-only, FC ignores
  {"yaw_collective_dynamic_gain", "U8"}, -- dead: heli-only, FC ignores
  {"yaw_collective_dynamic_decay", "U8"}, -- dead: heli-only, FC ignores
  {"pitch_collective_ff_gain", "U8"}, -- dead: heli-only, FC ignores
  {"angle_level_strength", "U8"},
  {"angle_level_limit", "U8"},
  {"horizon_level_strength", "U8"},
  {"trainer_gain", "U8"},
  {"trainer_angle_limit", "U8"},
  {"cyclic_cross_coupling_gain", "U8"}, -- dead: heli-only, FC ignores
  {"cyclic_cross_coupling_ratio", "U8"}, -- dead: heli-only, FC ignores
  {"cyclic_cross_coupling_cutoff", "U8"}, -- dead: heli-only, FC ignores
  {"atthold_gain", "U8"},
  {"atthold_deadband", "U8"},
  {"bterm_cutoff_0", "U8"}, {"bterm_cutoff_1", "U8"}, {"bterm_cutoff_2", "U8"},
  {"yaw_inertia_precomp_gain", "U8"}, -- dead: heli-only, FC ignores
  {"yaw_inertia_precomp_cutoff", "U8"}, -- dead: heli-only, FC ignores
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
}

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua) -- one entry per FIELDS entry, in order (U16
-- fields as two little-endian bytes), using each field's firmware default.
-- Matches this project's own last-known-good SIM_RESPONSE byte-for-byte.
local SIMULATOR_RESPONSE = {
  1,    -- pid_mode
  0,    -- error_decay_time_ground (dead)
  6,    -- iterm_decay_time (0.6s, decimals=1)
  0,    -- error_decay_time_yaw (dead)
  35,   -- iterm_decay_limit
  0,    -- error_decay_limit_yaw (dead)
  1,    -- error_rotation (dead, FC always reads back 1)
  45, 45, 60,   -- error_limit_0/1/2 (roll, pitch, yaw)
  50, 50, 100,  -- gyro_cutoff_0/1/2
  15, 15, 20,   -- dterm_cutoff_0/1/2
  2,    -- iterm_relax_type
  10, 10, 15,   -- iterm_relax_cutoff_0/1/2
  0,    -- yaw_cw_stop_gain (dead)
  0,    -- yaw_ccw_stop_gain (dead)
  0,    -- yaw_precomp_cutoff (dead)
  0,    -- yaw_cyclic_ff_gain (dead)
  0,    -- yaw_collective_ff_gain (dead)
  0,    -- yaw_collective_dynamic_gain (dead)
  0,    -- yaw_collective_dynamic_decay (dead)
  0,    -- pitch_collective_ff_gain (dead)
  40,   -- angle_level_strength
  55,   -- angle_level_limit
  0,    -- horizon_level_strength
  75,   -- trainer_gain
  20,   -- trainer_angle_limit
  0,    -- cyclic_cross_coupling_gain (dead)
  0,    -- cyclic_cross_coupling_ratio (dead)
  0,    -- cyclic_cross_coupling_cutoff (dead)
  40,   -- atthold_gain
  5,    -- atthold_deadband
  15, 15, 20,   -- bterm_cutoff_0/1/2
  0,    -- yaw_inertia_precomp_gain (dead)
  0,    -- yaw_inertia_precomp_cutoff (dead)
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
-- non-dead) min/max/default is included, so a future page (e.g. Auto
-- Hover, Cross Axis Relax, Master Gain adjusters) can reuse this without a
-- second research pass. `pid_mode`, `error_rotation`, `iterm_relax_type`
-- (choice/table fields, never take a plain `:default()`), and every dead
-- heli-only field are deliberately absent.
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
