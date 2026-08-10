-- Schema + message-builders for wingflight-firmware's own Throttle Range
-- Governor -- MSP2_WING_GOVERNOR_CONFIG / MSP2_WING_SET_GOVERNOR_CONFIG
-- (cmd 0x5F01/0x5F02, i.e. 24321/24322 -- see msp_protocol.h). Not the
-- pre-rewrite suite's heli engine-RPM governor (MSP_GOVERNOR_CONFIG is
-- gone from wingflight-firmware entirely, see lib/msp_pid_profile.lua's
-- header) -- this is a fixed-wing-only concept: closed/open-loop control
-- of a "throttle range" (idle hold, or an RPM target across the whole
-- stick), not a helicopter main-rotor RPM governor.
--
-- Field order/types verified directly against wingflight-firmware's own
-- wire serializer (src/main/msp/msp.c:1371-1381 for the read case,
-- :3901-3911 for the write case) and struct (src/main/pg/governor.h's
-- governorConfig_t): governor_mode (U8) -> governor_rpm (U16) ->
-- governor_gain (U16) -> governor_i_gain (U16) -> governor_throttle (U8)
-- -> governor_handover (U8) -> governor_ceiling (U8) -> governor_rpm_min
-- (U16) -> governor_rpm_max (U16). Also cross-checked against
-- wingflight-configurator's src/js/msp/MSPHelper.js (same field order) and
-- its src/tabs/motors/Governor.svelte (same 4-mode UI this codec's
-- MODE_CHOICES mirrors: Off/RPM/Throttle/RPM Range, src/main/pg/
-- governor.h's governorMode_e enum, string names from wingflight-
-- firmware's src/main/cli/settings.c's lookupTableGovernorMode).
--
-- Bounds/defaults come straight from settings.c's own governor_* CLI var
-- min/max and pg/governor.c's PG_RESET_TEMPLATE, not guessed.
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_governor_config"] then
  return package.loaded["wfsuite.lib.msp_governor_config"]
end

local mspcodec = assert(loadfile("lib/mspcodec.lua"))()

local READ_COMMAND = 0x5F01
local WRITE_COMMAND = 0x5F02

-- governorMode_e (src/main/pg/governor.h) -- string names from
-- wingflight-firmware's own lookupTableGovernorMode (src/main/cli/
-- settings.c). RPM/RPM_RANGE both need real RPM feedback (an ESC/sensor
-- protocol that reports headspeed) to mean anything -- app/pages/
-- governor.lua doesn't gate these out itself (unlike the configurator's
-- `rpmAvailable` prop), since this rebuild has no equivalent capability
-- flag threaded through to page-open time yet; picking either mode with
-- no RPM source just leaves governor_rpm/rpm_min/rpm_max inert, same as
-- firmware does with any other not-currently-relevant field.
local MODE_CHOICES = {
  {"@i18n(app.modules.governor.mode_off)@", 0},
  {"@i18n(app.modules.governor.mode_rpm)@", 1},
  {"@i18n(app.modules.governor.mode_throttle)@", 2},
  {"@i18n(app.modules.governor.mode_rpm_range)@", 3},
}

local FIELDS = {
  {"governor_mode", "U8"},
  {"governor_rpm", "U16"},
  {"governor_gain", "U16"},
  {"governor_i_gain", "U16"},
  {"governor_throttle", "U8"},
  {"governor_handover", "U8"},
  {"governor_ceiling", "U8"},
  {"governor_rpm_min", "U16"},
  {"governor_rpm_max", "U16"},
}

-- min/max: settings.c's own governor_* CLI var .config.minmaxUnsigned.
-- default: pg/governor.c's PG_RESET_TEMPLATE(governorConfig_t, ...).
-- governor_throttle is the powered idle floor for RPM idle hold and the
-- fixed idle output for Throttle mode.
local FIELD_META = {
  governor_mode = {choices = MODE_CHOICES, default = 0},
  governor_rpm = {min = 0, max = 50000, default = 0, suffix = "RPM"},
  governor_gain = {min = 0, max = 20000, default = 20},
  governor_i_gain = {min = 0, max = 200, default = 30},
  governor_throttle = {min = 0, max = 100, default = 15, suffix = "%"},
  governor_handover = {min = 0, max = 100, default = 10, suffix = "%"},
  governor_ceiling = {min = 0, max = 100, default = 30, suffix = "%"},
  governor_rpm_min = {min = 0, max = 50000, default = 0, suffix = "RPM"},
  governor_rpm_max = {min = 0, max = 50000, default = 0, suffix = "RPM"},
}

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua) -- matches pg/governor.c's own
-- PG_RESET_TEMPLATE defaults exactly (mode=OFF, gain=20, i_gain=30,
-- throttle=15, handover=10, ceiling=30, everything else 0).
local SIMULATOR_RESPONSE = {
  0,       -- governor_mode = OFF
  0, 0,    -- governor_rpm = 0
  20, 0,   -- governor_gain = 20
  30, 0,   -- governor_i_gain = 30
  15,      -- governor_throttle = 15
  10,      -- governor_handover = 10
  30,      -- governor_ceiling = 30
  0, 0,    -- governor_rpm_min = 0
  0, 0,    -- governor_rpm_max = 0
}

local msp_governor_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FIELDS = FIELDS,
  FIELD_META = FIELD_META,
  MODE_CHOICES = MODE_CHOICES,
}

local function readByType(buf, wireType)
  if wireType == "U16" then return mspcodec.readU16(buf) end
  return mspcodec.readU8(buf)
end

local function writeByType(buf, wireType, value)
  if wireType == "U16" then
    mspcodec.writeU16(buf, value or 0)
  else
    mspcodec.writeU8(buf, value or 0)
  end
end

function msp_governor_config.decode(buf)
  buf.offset = 1
  local data = {}
  for i = 1, #FIELDS do
    local name, wireType = FIELDS[i][1], FIELDS[i][2]
    data[name] = readByType(buf, wireType)
  end
  return data
end

function msp_governor_config.encode(data)
  local payload = {}
  data = data or {}
  for i = 1, #FIELDS do
    local name, wireType = FIELDS[i][1], FIELDS[i][2]
    writeByType(payload, wireType, data[name])
  end
  return payload
end

function msp_governor_config.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_governor_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

function msp_governor_config.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_governor_config.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_governor_config"] = msp_governor_config
return msp_governor_config
