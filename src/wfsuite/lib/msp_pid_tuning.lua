-- Schema + message-builders for the MSP_PID_TUNING / MSP_SET_PID_TUNING
-- command pair (cmd 112 read / 202 write).
--
-- Stateless: every function takes/returns plain tables, nothing is cached
-- here. Used by app/pages/pids.lua to build request messages for
-- lib/bus.lua's "msp.request" topic (handled by tasks/background.lua's MSP
-- queue) -- this module never talks to tasks/msp/* directly itself.
--
-- Field order matches the flight controller wire format exactly (verified
-- against both rotorflight-lua-ethos-suite's PID_TUNING.lua and
-- rotorflight-lua-ethos's mspPidTuning.lua) -- do not reorder. Also
-- verified directly against wingflight-firmware's own wire serializer
-- (src/main/msp/msp.c, MSP_PID_TUNING/MSP_SET_PID_TUNING cases): field
-- count and order match there (3 axes x P/I/D/F, then 3 axes x B), so
-- unlike lib/msp_pid_profile.lua this codec needed no reshaping. The
-- trailing heli-only `roll_o`/`pitch_o` pair (always 0, discarded on
-- write) was dropped from the wire in MSP API 22.3.

-- Self-caches via package.loaded (same mechanism lib/bus.lua uses) --
-- app/pages/pids.lua reloads fresh via loadfile() on every open, so
-- without caching this stateless codec (and its module-level FIELDS/
-- FIELD_META/SIMULATOR_RESPONSE tables) was rebuilt on every single
-- navigation too. Added after a live memory investigation confirmed the
-- *bulk* of this rebuild's observed RAM growth is an Ethos platform
-- trait (see AGENTS.md's "Memory stats printing" section) that no
-- script-side change can eliminate -- but this redundant reload is a
-- separate, real, avoidable cost.
if package.loaded["wfsuite.lib.msp_pid_tuning"] then
  return package.loaded["wfsuite.lib.msp_pid_tuning"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 112
local WRITE_COMMAND = 202

local FIELDS = {
  "roll_p", "roll_i", "roll_d", "roll_f",
  "pitch_p", "pitch_i", "pitch_d", "pitch_f",
  "yaw_p", "yaw_i", "yaw_d", "yaw_f",
  "roll_b", "pitch_b", "yaw_b",
}

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua) -- one U16 pair per FIELDS entry, in order.
-- Values are the firmware's defaults (src/main/pg/pid.c resetPidProfile()).
local SIMULATOR_RESPONSE = {
  105, 0, 45, 0, 0, 0, 65, 0,
  105, 0, 45, 0, 0, 0, 65, 0,
  190, 0, 45, 0, 0, 0, 65, 0,
  35, 0, 35, 0, 35, 0,
}

-- Per-field {min, max, default}, same convention as lib/msp_pid_profile.lua's
-- own FIELD_META (see its comment) -- min/max is 0-1000 for every one of
-- these except the F gains, which the firmware floors at 50 (PID_F_GAIN_MIN
-- in src/main/flight/pid.h: MANUAL mode flies on the F-term alone, so F = 0
-- meant no surface movement). `default` is the firmware's reset value
-- (src/main/pg/pid.c resetPidProfile()) and differs per axis -- yaw P runs
-- higher than roll and pitch -- so it needs a per-field entry, not a single
-- shared constant.
local FIELD_META = {
  roll_p = {min = 0, max = 1000, default = 105},
  roll_i = {min = 0, max = 1000, default = 45},
  roll_d = {min = 0, max = 1000, default = 0},
  roll_f = {min = 50, max = 1000, default = 65},
  pitch_p = {min = 0, max = 1000, default = 105},
  pitch_i = {min = 0, max = 1000, default = 45},
  pitch_d = {min = 0, max = 1000, default = 0},
  pitch_f = {min = 50, max = 1000, default = 65},
  yaw_p = {min = 0, max = 1000, default = 190},
  yaw_i = {min = 0, max = 1000, default = 45},
  yaw_d = {min = 0, max = 1000, default = 0},
  yaw_f = {min = 50, max = 1000, default = 65},
  roll_b = {min = 0, max = 1000, default = 35},
  pitch_b = {min = 0, max = 1000, default = 35},
  yaw_b = {min = 0, max = 1000, default = 35},
}

local msp_pid_tuning = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FIELDS = FIELDS,
  FIELD_META = FIELD_META,
}

function msp_pid_tuning.decode(buf)
  -- Always start from byte 1, even if `buf` is a reused/shared table (e.g.
  -- the simulator fixture below) that a previous decode() left an
  -- `.offset` on.
  buf.offset = 1
  local data = {}
  for i = 1, #FIELDS do
    data[FIELDS[i]] = mspcodec.readU16(buf)
  end
  return data
end

function msp_pid_tuning.encode(data)
  local payload = {}
  for i = 1, #FIELDS do
    mspcodec.writeU16(payload, data[FIELDS[i]] or 0)
  end
  return payload
end

-- Builds a ready-to-publish message for lib/bus.lua's "msp.request" topic.
-- `onData(data)` is called with the decoded field table once the reply
-- arrives; `onError(reason)` (optional) on failure.
function msp_pid_tuning.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_pid_tuning.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- Builds a ready-to-publish write message. `onWritten()` (optional) is
-- called once the FC acknowledges the write; `onError(reason)` on failure.
function msp_pid_tuning.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_pid_tuning.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_pid_tuning"] = msp_pid_tuning
return msp_pid_tuning
