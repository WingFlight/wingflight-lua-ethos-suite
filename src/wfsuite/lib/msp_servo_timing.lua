-- MSP2_WING_SERVO_TIMING (cmd 0x5F27, read-only): the PWM servo outputs of
-- the board.
--
-- Wire layout verified against wingflight-firmware's src/main/msp/msp.c
-- (MSP2_WING_SERVO_TIMING) and flight/servos.c getPwmServoCount(): U8 count,
-- then per output U16 rate the output is running at (Hz) and U8 timer group
-- (the index of the first output on the same hardware timer).
--
-- The count is the number of PWM outputs: servos S1 up to it have a PWM
-- output, the rest are sent on a bus output only. Nothing else differs
-- between servos, so the count is the only thing the Servos page takes from
-- here, to offer the PWM update rate only where there is an output to run
-- at it. The running rate is servo_pwm_rate (lib/msp_mixer_config.lua) as it
-- was at boot.

if package.loaded["wfsuite.lib.msp_servo_timing"] then
  return package.loaded["wfsuite.lib.msp_servo_timing"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F27

-- Four PWM outputs at 50 Hz on two timers, matching MSP_STATUS's four servos.
local SIMULATOR_RESPONSE = {
  4,
  50, 0, 0,
  50, 0, 0,
  50, 0, 2,
  50, 0, 2,
}

local msp_servo_timing = {READ_COMMAND = READ_COMMAND}

-- {count = n, outputs = {{rate = Hz, group = index}, ...}}. A reply shorter
-- than its count says is cut to the outputs that are there.
function msp_servo_timing.decode(buf)
  buf.offset = 1
  local count = mspcodec.readU8(buf) or 0
  local available = math.floor((#buf - 1) / 3)
  if count > available then count = math.max(available, 0) end
  local outputs = {}
  for i = 1, count do
    outputs[i] = {rate = mspcodec.readU16(buf), group = mspcodec.readU8(buf)}
  end
  return {count = count, outputs = outputs}
end

function msp_servo_timing.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_servo_timing.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

package.loaded["wfsuite.lib.msp_servo_timing"] = msp_servo_timing
return msp_servo_timing
