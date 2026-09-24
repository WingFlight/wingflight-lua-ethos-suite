-- Schema + message-builder for MSP_MIXER_CONFIG (cmd 42). Read-only here:
-- the suite only needs the bus servo output count, to know how many bus
-- servos the configured SBUS/F.Bus output drives.
--
-- Wire layout (wingflight-firmware src/main/msp/msp.c, MSP_MIXER_CONFIG
-- case): U8 model_type -> U8 bus_servo_clone_pwm -> U8 sbus_out_channels ->
-- U8 fbus_master_channels -> U8 bus servo output count (8, 12, 16 or 24;
-- 0 without a bus output port).
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_mixer_config"] then
  return package.loaded["wfsuite.lib.msp_mixer_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 42

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua): regular airplane, clone on, SBUS 16, F.Bus 24,
-- no bus output port.
local SIMULATOR_RESPONSE = {0, 1, 16, 24, 0}

local msp_mixer_config = {
  READ_COMMAND = READ_COMMAND,
}

function msp_mixer_config.decode(buf)
  buf.offset = 1
  return {
    model_type = mspcodec.readU8(buf) or 0,
    bus_servo_clone_pwm = mspcodec.readU8(buf) or 0,
    sbus_out_channels = mspcodec.readU8(buf) or 0,
    fbus_master_channels = mspcodec.readU8(buf) or 0,
    bus_servo_output_count = mspcodec.readU8(buf) or 0,
  }
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

package.loaded["wfsuite.lib.msp_mixer_config"] = msp_mixer_config
return msp_mixer_config
