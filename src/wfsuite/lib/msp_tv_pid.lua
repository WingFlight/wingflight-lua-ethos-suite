-- Schema + message-builders for the MSP2_WING_TV_PID_CONFIG / SET command
-- pair (cmd 0x5F0B read / 0x5F0C write) -- the independent Thrust Vector PID
-- loop's config (FEATURE_THRUST_VECTOR), a completely separate MSP command
-- from MSP_PID_PROFILE/MSP_PID_TUNING (lib/msp_pid_profile.lua/
-- lib/msp_pid_tuning.lua): tvPidProfile_t is a single master config, not
-- scoped to the active PID profile, and is deliberately a trimmed-down
-- sibling of pidProfile_t (see wingflight-firmware's pg/tv_pid.h) -- no
-- pid_mode, gain_curve, fw_tpa, leveling/trainer/autohover sub-modes, or
-- cross-axis relax. The one exception is `hold`: an independent attitude/
-- heading hold for this loop only (BOXTVHOLD / "THRUST VECTOR ATTITUDE
-- HOLD"), tacked on at the tail of the wire struct.
--
-- Field order/types verified against wingflight-firmware's actual wire
-- serializer (src/main/msp/msp.c, MSP2_WING_TV_PID_CONFIG/
-- MSP2_WING_SET_TV_PID_CONFIG cases) and its backing struct (pg/tv_pid.h's
-- tvPidProfile_t) -- there is no rotorflight equivalent to cross-check
-- against, unlike lib/msp_pid_profile.lua's history, since Thrust Vector is
-- wingflight-native.
--
-- Stateless: every function takes/returns plain tables, nothing is cached
-- here. Self-caches via package.loaded, same mechanism/reasoning as
-- lib/msp_pid_profile.lua's own header comment.
if package.loaded["wfsuite.lib.msp_tv_pid"] then
  return package.loaded["wfsuite.lib.msp_tv_pid"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F0B
local WRITE_COMMAND = 0x5F0C

-- roll_*/pitch_*/yaw_* (P/I/D/F/B, U16 each) match wingflight-firmware's
-- pid[PID_ROLL/PID_PITCH/PID_YAW] array, in that axis order -- same
-- P/I/D/F/B column order app/pages/pids.lua's own COLUMN_SUFFIXES uses for
-- the main loop's grid, reused here for naming consistency even though
-- this is a different MSP command.
local FIELDS = {
  {"roll_p", "U16"}, {"roll_i", "U16"}, {"roll_d", "U16"}, {"roll_f", "U16"}, {"roll_b", "U16"},
  {"pitch_p", "U16"}, {"pitch_i", "U16"}, {"pitch_d", "U16"}, {"pitch_f", "U16"}, {"pitch_b", "U16"},
  {"yaw_p", "U16"}, {"yaw_i", "U16"}, {"yaw_d", "U16"}, {"yaw_f", "U16"}, {"yaw_b", "U16"},
  {"master_gain_0", "U16"}, {"master_gain_1", "U16"}, {"master_gain_2", "U16"}, -- roll, pitch, yaw
  {"iterm_decay_time", "U8"},
  {"iterm_decay_limit", "U8"},
  {"iterm_relax_type", "U8"},
  {"iterm_relax_level_0", "U8"}, {"iterm_relax_level_1", "U8"}, {"iterm_relax_level_2", "U8"},
  {"iterm_relax_cutoff_0", "U8"}, {"iterm_relax_cutoff_1", "U8"}, {"iterm_relax_cutoff_2", "U8"},
  {"error_limit_0", "U8"}, {"error_limit_1", "U8"}, {"error_limit_2", "U8"},
  {"dterm_cutoff_0", "U8"}, {"dterm_cutoff_1", "U8"}, {"dterm_cutoff_2", "U8"},
  {"bterm_cutoff_0", "U8"}, {"bterm_cutoff_1", "U8"}, {"bterm_cutoff_2", "U8"},
  {"gyro_cutoff_0", "U8"}, {"gyro_cutoff_1", "U8"}, {"gyro_cutoff_2", "U8"},
  {"hold_gain", "U8"},
  {"hold_deadband", "U8"},
  {"hold_max_rate", "U16"},
}

-- Fixture reply used automatically when running in the Ethos simulator (see
-- tasks/msp/queue.lua) -- one entry per FIELDS entry, in order (U16 fields
-- as two little-endian bytes), using each field's firmware default (pg/
-- tv_pid.c's PG_RESET_TEMPLATE).
local SIMULATOR_RESPONSE = {
  50, 0,  16, 0,  0, 0,  100, 0,  0, 0,   -- roll_p/i/d/f/b
  50, 0,  16, 0,  0, 0,  100, 0,  0, 0,   -- pitch_p/i/d/f/b
  80, 0,  20, 0,  0, 0,  100, 0,  0, 0,   -- yaw_p/i/d/f/b
  100, 0, 100, 0, 100, 0, -- master_gain_0/1/2
  6,    -- iterm_decay_time
  35,   -- iterm_decay_limit
  2,    -- iterm_relax_type (RPY)
  22, 22, 22,   -- iterm_relax_level_0/1/2
  10, 10, 10,   -- iterm_relax_cutoff_0/1/2
  45, 45, 60,   -- error_limit_0/1/2
  15, 15, 20,   -- dterm_cutoff_0/1/2
  15, 15, 20,   -- bterm_cutoff_0/1/2
  50, 50, 100,  -- gyro_cutoff_0/1/2
  40,   -- hold_gain
  5,    -- hold_deadband
  44, 1, -- hold_max_rate (U16 LE: 300 = 0x012C -> 44, 1)
}

-- Per-field {min, max, default, decimals, suffix}, sourced from
-- wingflight-firmware's CLI settings.c (tv_* entries) and
-- wingflight-configurator's ThrustVector.svelte (same bounds this project's
-- own last-known-good schemas used for the main loop -- see
-- lib/msp_pid_profile.lua's own FIELD_META comment). `default` is in the
-- same raw wire domain as `min`/`max`, matching iterm_decay_time's
-- decimals=1 display (seconds) over its actual 0-250 (deciseconds) range.
local FIELD_META = {
  roll_p = {min = 0, max = 1000, default = 50},
  roll_i = {min = 0, max = 1000, default = 16},
  roll_d = {min = 0, max = 1000, default = 0},
  roll_f = {min = 0, max = 1000, default = 100},
  roll_b = {min = 0, max = 1000, default = 0},
  pitch_p = {min = 0, max = 1000, default = 50},
  pitch_i = {min = 0, max = 1000, default = 16},
  pitch_d = {min = 0, max = 1000, default = 0},
  pitch_f = {min = 0, max = 1000, default = 100},
  pitch_b = {min = 0, max = 1000, default = 0},
  yaw_p = {min = 0, max = 1000, default = 80},
  yaw_i = {min = 0, max = 1000, default = 20},
  yaw_d = {min = 0, max = 1000, default = 0},
  yaw_f = {min = 0, max = 1000, default = 100},
  yaw_b = {min = 0, max = 1000, default = 0},
  master_gain_0 = {min = 25, max = 1000, default = 100, suffix = "%"},
  master_gain_1 = {min = 25, max = 1000, default = 100, suffix = "%"},
  master_gain_2 = {min = 25, max = 1000, default = 100, suffix = "%"},
  iterm_decay_time = {min = 0, max = 250, default = 6, decimals = 1, suffix = "s"},
  iterm_decay_limit = {min = 0, max = 250, default = 35, suffix = "°/s"},
  iterm_relax_level_0 = {min = 10, max = 250, default = 22},
  iterm_relax_level_1 = {min = 10, max = 250, default = 22},
  iterm_relax_level_2 = {min = 10, max = 250, default = 22},
  iterm_relax_cutoff_0 = {min = 1, max = 100, default = 10, suffix = "Hz"},
  iterm_relax_cutoff_1 = {min = 1, max = 100, default = 10, suffix = "Hz"},
  iterm_relax_cutoff_2 = {min = 1, max = 100, default = 10, suffix = "Hz"},
  error_limit_0 = {min = 0, max = 180, default = 45, suffix = "°"},
  error_limit_1 = {min = 0, max = 180, default = 45, suffix = "°"},
  error_limit_2 = {min = 0, max = 180, default = 60, suffix = "°"},
  dterm_cutoff_0 = {min = 0, max = 250, default = 15},
  dterm_cutoff_1 = {min = 0, max = 250, default = 15},
  dterm_cutoff_2 = {min = 0, max = 250, default = 20},
  bterm_cutoff_0 = {min = 0, max = 250, default = 15},
  bterm_cutoff_1 = {min = 0, max = 250, default = 15},
  bterm_cutoff_2 = {min = 0, max = 250, default = 20},
  gyro_cutoff_0 = {min = 0, max = 250, default = 50},
  gyro_cutoff_1 = {min = 0, max = 250, default = 50},
  gyro_cutoff_2 = {min = 0, max = 250, default = 100},
  hold_gain = {min = 0, max = 250, default = 40},
  hold_deadband = {min = 0, max = 100, default = 5, suffix = "%"},
  hold_max_rate = {min = 0, max = 1800, default = 300, suffix = "°/s"},
}

local msp_tv_pid = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FIELDS = FIELDS,
  FIELD_META = FIELD_META,
}

function msp_tv_pid.decode(buf)
  -- Always start from byte 1, even if `buf` is a reused/shared table (e.g.
  -- the simulator fixture above) that a previous decode() left an `.offset`
  -- on -- same defensive reset lib/msp_pid_profile.lua's decode() uses.
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

function msp_tv_pid.encode(data)
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
function msp_tv_pid.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_tv_pid.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- Builds a ready-to-publish write message. `onWritten()` (optional) is
-- called once the FC acknowledges the write; `onError(reason)` on failure.
-- `data` should be a full field table (everything in FIELDS, not just the
-- ones app/pages/thrust_vector.lua exposes as editable widgets) -- fields
-- that page doesn't display still round-trip unchanged, same convention as
-- lib/msp_pid_profile.lua.
function msp_tv_pid.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_tv_pid.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_tv_pid"] = msp_tv_pid
return msp_tv_pid
