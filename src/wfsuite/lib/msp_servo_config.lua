-- Indexed servo configuration helpers: MSP_GET_SERVO_CONFIG (125, read) and
-- MSP_SET_SERVO_CONFIGURATION (212, write). Command numbers as in
-- wingflight-firmware src/main/msp/msp_protocol.h.
--
-- One index space (MSP API 22.16): index N is servo S(N+1) in every servo
-- message, 0..23. A servo is sent on PWM output N+1 where the board has one
-- and on channel N+1 of a bus output (SBUS, F.Bus) when one is set up; it is
-- configured the same way either way. The read and the write both take any
-- index 0..23, in use or not. MSP_SET_SERVO_CONFIG (124) takes the same
-- payload and index as 212; this suite only sends 212.
--
-- Wire layout verified against wingflight-firmware's src/main/msp/msp.c
-- (MSP_GET_SERVO_CONFIG / MSP_SET_SERVO_CONFIGURATION): seven 16-bit fields,
-- mid U16, min S16, max S16, rneg U16, rpos U16, speed U16, flags U16. The
-- read reply is 14 bytes; the write is the U8 index and the same 14 bytes,
-- and the firmware refuses any other length. There is no per-servo rate any
-- more: the PWM update rate is one setting, servo_pwm_rate in
-- lib/msp_mixer_config.lua.
--
-- Limits from flight/servos.h, applied by validateAndFixServoConfig() on
-- every write: mid 1000..2000 (SERVO_CENTER_MIN/MAX), min -1000..0, max
-- 0..1000 (SERVO_LIMIT_MIN/MAX), scale 50..1000 (SERVO_SCALE_MIN/MAX), speed
-- 0..60000. min/max are stored as set; the output stays inside 880..2159 us
-- (SERVO_SIGNAL_MIN/MAX), so the travel used at a given mid is
-- max(min, 880 - mid) .. min(max, 2159 - mid). flags: bit 0 reverse, bit 1
-- geometry correction.

if package.loaded["wfsuite.lib.msp_servo_config"] then
  return package.loaded["wfsuite.lib.msp_servo_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 125   -- MSP_GET_SERVO_CONFIG
local WRITE_COMMAND = 212  -- MSP_SET_SERVO_CONFIGURATION

-- Defaults from wingflight-firmware flight/servos.h and pg/servos.c.
local SIMULATOR_RESPONSE = {
  220, 5,   -- mid = 1500
  168, 253, -- min = -600 (signed offset from mid, not an absolute pulse)
  88, 2,    -- max = 600
  244, 1,   -- rneg = 500
  244, 1,   -- rpos = 500
  0, 0,     -- speed = 0
  0, 0,     -- flags = 0
}

local msp_servo_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FIELD_META = {
    mid = {min = 1000, max = 2000, default = 1500},
    min = {min = -1000, max = 0, default = -600},
    max = {min = 0, max = 1000, default = 600},
    rneg = {min = 50, max = 1000, default = 500},
    rpos = {min = 50, max = 1000, default = 500},
    speed = {min = 0, max = 60000, default = 0, suffix = "ms"},
  },
}

local function clampIndex(index)
  index = tonumber(index) or 0
  if index < 0 then return 0 end
  return index
end

function msp_servo_config.decode(buf)
  buf.offset = 1
  return {
    mid = mspcodec.readU16(buf),
    min = mspcodec.readS16(buf),
    max = mspcodec.readS16(buf),
    rneg = mspcodec.readU16(buf),
    rpos = mspcodec.readU16(buf),
    speed = mspcodec.readU16(buf),
    flags = mspcodec.readU16(buf),
  }
end

function msp_servo_config.encode(index, data)
  data = data or {}
  local payload = {}
  mspcodec.writeU8(payload, clampIndex(index))
  mspcodec.writeU16(payload, data.mid or 1500)
  mspcodec.writeS16(payload, data.min or 0)
  mspcodec.writeS16(payload, data.max or 0)
  mspcodec.writeU16(payload, data.rneg or 0)
  mspcodec.writeU16(payload, data.rpos or 0)
  mspcodec.writeU16(payload, data.speed or 0)
  mspcodec.writeU16(payload, data.flags or 0)
  return payload
end

function msp_servo_config.buildReadMessage(index, onData, onError)
  return {
    command = READ_COMMAND,
    payload = {clampIndex(index)},
    processReply = function(_, buf)
      onData(msp_servo_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

function msp_servo_config.buildWriteMessage(index, data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_servo_config.encode(index, data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

function msp_servo_config.forIndex(index)
  return {
    FIELD_META = msp_servo_config.FIELD_META,
    buildReadMessage = function(onData, onError)
      return msp_servo_config.buildReadMessage(index, onData, onError)
    end,
    buildWriteMessage = function(data, onWritten, onError)
      return msp_servo_config.buildWriteMessage(index, data, onWritten, onError)
    end,
  }
end

package.loaded["wfsuite.lib.msp_servo_config"] = msp_servo_config
return msp_servo_config
