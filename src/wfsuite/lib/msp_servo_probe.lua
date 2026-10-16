-- MSP2_WING_SET_SERVO_PROBE (cmd 0x5F1C, write, API 22.14): holds one PWM
-- servo at its Mid plus an offset in us, ignoring its Min/Max, so the Setup
-- Wizard's Limits step can look for where a surface binds without widening
-- the stored limits.
--
-- Wire layout verified against wingflight-firmware's src/main/msp/msp.c and
-- flight/servos.c setServoProbe(): exactly 5 bytes, U8 servo, S16 offset us
-- (-1000..1000, SERVO_LIMIT_MIN/MAX), U16 timeout ms. Timeout 0 clears the
-- probe; otherwise the FC clamps it to 500-30000 and drops the probe unless
-- it is re-sent in time. Refused while armed, or for a servo past the PWM
-- servos.
--
-- hold() keeps it alive through lib/override_keepalive.lua, as the servo and
-- mixer overrides do; release() clears it.

if package.loaded["wfsuite.lib.msp_servo_probe"] then
  return package.loaded["wfsuite.lib.msp_servo_probe"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")
local bus = requireModule("lib/bus.lua")
local keepalive = requireModule("lib/override_keepalive.lua")

local WRITE_COMMAND = 0x5F1C

local M = {
  WRITE_COMMAND = WRITE_COMMAND,
  OFFSET_MIN = -1000,
  OFFSET_MAX = 1000,
}

function M.encode(servo, offsetUs, timeoutMs)
  local payload = {}
  mspcodec.writeU8(payload, servo or 0)
  mspcodec.writeS16(payload, offsetUs or 0)
  mspcodec.writeU16(payload, timeoutMs or 0)
  return payload
end

function M.buildWriteMessage(servo, offsetUs, timeoutMs, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = M.encode(servo, offsetUs, timeoutMs),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

local keys = {}
local function key(servo)
  local k = keys[servo]
  if not k then
    k = "servo_probe_" .. servo
    keys[servo] = k
  end
  return k
end

-- Needs timed overrides: returns false without sending on older firmware.
function M.hold(servo, offsetUs)
  if not keepalive.supported() then return false end
  if offsetUs < M.OFFSET_MIN then
    offsetUs = M.OFFSET_MIN
  elseif offsetUs > M.OFFSET_MAX then
    offsetUs = M.OFFSET_MAX
  end
  keepalive.set(key(servo), function()
    return M.buildWriteMessage(servo, offsetUs, keepalive.TIMEOUT_MS)
  end)
  return true
end

function M.release(servo)
  keepalive.clear(key(servo))
  bus.publish("msp.request", M.buildWriteMessage(servo, 0, 0))
end

package.loaded["wfsuite.lib.msp_servo_probe"] = M
return M
