-- MSP_MOTOR_OVERRIDE (194, read) and MSP_SET_MOTOR_OVERRIDE (195, write).
--
-- Both numbers are the firmware's own: wingflight-firmware
-- src/main/msp/msp_protocol.h:249-250. The write is what makes the flight
-- controller drive a motor directly, so the constants below are transcribed
-- from the firmware rather than invented:
--
--   src/main/flight/motors.h:22-27   MOTOR_OVERRIDE_OFF/MIN/MAX,
--                                    MOTOR_OVERRIDE_TIMEOUT 1000000 (1.0 s)
--   src/main/msp/msp.c:3055-3063     `i = sbufReadU8(src)` then
--                                    `setMotorOverride(i, sbufReadU16(src),
--                                     MOTOR_OVERRIDE_TIMEOUT)`
--   src/main/flight/motors.c:114-120 writes only while the craft is DISARMED
--   src/main/flight/motors.c:298-300 resets every override once the deadline
--                                    passes
--
-- The 1.0 s deadline is why a caller must keep writing. It is NOT the timed
-- override of lib/override_keepalive.lua: that path exists for servo, mixer and
-- mode overrides, which carry their timeout in the payload from API 22.14 on a
-- 10 s window refreshed every 3 s. MSP_SET_MOTOR_OVERRIDE carries no timeout
-- field at all -- the firmware supplies its own one-second one -- so a 3 s
-- refresh would let the motor lapse between sends. The page owns its own
-- 250 ms heartbeat for that reason.

if package.loaded["wfsuite.lib.msp_motor_override"] then
  return package.loaded["wfsuite.lib.msp_motor_override"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 194
local WRITE_COMMAND = 195

local OVERRIDE_OFF = 0
local OVERRIDE_MIN = -1000
local OVERRIDE_MAX = 1000

-- How many motors MSP_MOTOR_OVERRIDE answers for. msp.c:1221-1230 writes
-- MAX_SUPPORTED_MOTORS values, one int16 each, and zero for a motor the board
-- does not have. target/common_defaults_post.h:674-675 defines
-- MAX_SUPPORTED_MOTORS as 4 unless the target overrides it, so 8 bytes is the
-- full answer.
local MOTOR_SLOTS = 4

local msp_motor_override = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  OVERRIDE_OFF = OVERRIDE_OFF,
  OVERRIDE_MIN = OVERRIDE_MIN,
  OVERRIDE_MAX = OVERRIDE_MAX,
  MOTOR_SLOTS = MOTOR_SLOTS,
}

--- Read the override the board currently holds for every motor.
---
--- The values are int16_t and a reverse override is negative, so they are read
--- signed: read unsigned, -100 comes back as 65436.
function msp_motor_override.parse(buf)
  if type(buf) ~= "table" then return nil end
  if #buf < MOTOR_SLOTS * 2 then return nil end
  buf.offset = 1
  local out = {}
  for idx = 1, MOTOR_SLOTS do
    out["motor_" .. idx] = mspcodec.readS16(buf)
  end
  return out
end

--- Build the write for ONE motor. `index` is 0-based, as the wire numbers them.
---
--- This is deliberately not the mirror image of the read: the read answers for
--- every motor, the write carries a single index/value pair, which is also what
--- the Configurator sends.
function msp_motor_override.buildWriteMessage(index, value, onWritten, onError)
  local payload = {}
  mspcodec.writeU8(payload, index or 0)
  mspcodec.writeS16(payload, value or OVERRIDE_OFF)
  return {
    command = WRITE_COMMAND,
    payload = payload,
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

--- Build a read for the override state, so a page can show what the board
--- already holds instead of claiming nothing is overridden.
function msp_motor_override.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    payload = {},
    isWrite = false,
    processReply = function(_, buf)
      if onData then onData(msp_motor_override.parse(buf)) end
    end,
    errorHandler = onError,
    simulatorResponse = {0, 0, 0, 0, 0, 0, 0, 0},
  }
end

package.loaded["wfsuite.lib.msp_motor_override"] = msp_motor_override
return msp_motor_override