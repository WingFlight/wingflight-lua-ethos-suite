-- Schema + message-builders for MSP_MIXER_CONFIG (cmd 42) and
-- MSP_SET_MIXER_CONFIG (cmd 43). The read gives the model type, the bus
-- output channel counts and the PWM update rate of the servo outputs; the
-- Setup Wizard writes the model type, and it and the Servos page write the
-- PWM update rate.
--
-- Wire layout, MSP API 22.16 (wingflight-firmware src/main/msp/msp.c,
-- MSP_MIXER_CONFIG case): U8 model_type -> U8 reserved (always 0; it was
-- bus_servo_clone_pwm, which no longer exists) -> U8 sbus_out_channels ->
-- U8 fbus_master_channels -> U8 bus servo output count (the channels the
-- configured bus output sends: 8, 12, 16 or 24; 0 without a bus output
-- port) -> U16 servo_pwm_rate (Hz).
--
-- servo_pwm_rate is the update rate of every PWM servo output, 25..333 Hz
-- (SERVO_RATE_MIN/MAX in flight/servos.h), default 50. The firmware applies
-- it at boot, so a change needs a save and a restart.
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_mixer_config"] then
  return package.loaded["wfsuite.lib.msp_mixer_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 42

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua): regular airplane, SBUS 16, F.Bus 24, no bus
-- output port, 50 Hz.
local SIMULATOR_RESPONSE = {0, 0, 16, 24, 0, 50, 0}

local msp_mixer_config = {
  READ_COMMAND = READ_COMMAND,
  PWM_RATE_STANDARD = 50,
  PWM_RATE_HIGH_SPEED = 333,
  FIELD_META = {
    servo_pwm_rate = {min = 25, max = 333, default = 50, suffix = "@i18n(app.unit_hertz)@"},
  },
}

function msp_mixer_config.decode(buf)
  buf.offset = 1
  local data = {model_type = mspcodec.readU8(buf) or 0}
  mspcodec.readU8(buf) -- reserved, was bus_servo_clone_pwm
  data.sbus_out_channels = mspcodec.readU8(buf) or 0
  data.fbus_master_channels = mspcodec.readU8(buf) or 0
  data.bus_servo_output_count = mspcodec.readU8(buf) or 0
  -- Left nil on a short reply, so encode() falls back to the short form
  -- rather than writing a rate of 0, which the firmware refuses.
  if #buf >= 7 then data.servo_pwm_rate = mspcodec.readU16(buf) end
  return data
end

function msp_mixer_config.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_mixer_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- MSP_SET_MIXER_CONFIG (cmd 43): U8 model_type, U8 reserved (ignored), then
-- two optional tails that msp.c reads only when the bytes are there: U8
-- sbus_out_channels + U8 fbus_master_channels, then U16 servo_pwm_rate.
--
-- The rate comes after the channel counts, so writing it means sending them
-- too. encode() does that only for a table that carries all three, which is
-- what decode() returns: read first, change servo_pwm_rate, write the same
-- table back. Anything else goes out as the two-byte short form, which
-- changes the model type and leaves the bus outputs and the rate alone.
-- The firmware answers with an error for a channel count that is not 8, 12,
-- 16 or 24 (SBUS: not 24) or a rate outside 25..333, and then keeps nothing
-- that came after the bad value.
msp_mixer_config.WRITE_COMMAND = 43

function msp_mixer_config.encode(data)
  local payload = {}
  mspcodec.writeU8(payload, data.model_type or 0)
  mspcodec.writeU8(payload, 0)
  if data.servo_pwm_rate and data.sbus_out_channels and data.fbus_master_channels then
    mspcodec.writeU8(payload, data.sbus_out_channels)
    mspcodec.writeU8(payload, data.fbus_master_channels)
    mspcodec.writeU16(payload, data.servo_pwm_rate)
  end
  return payload
end

function msp_mixer_config.buildWriteMessage(data, onWritten, onError)
  return {
    command = msp_mixer_config.WRITE_COMMAND,
    payload = msp_mixer_config.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_mixer_config"] = msp_mixer_config
return msp_mixer_config
