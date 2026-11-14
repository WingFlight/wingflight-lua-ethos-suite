-- MSP_SERVO_TRIM (cmd 233, read-only): the trim of every servo in use, in us.
--
-- Wire layout verified against wingflight-firmware's src/main/msp/msp.c
-- (MSP_SERVO_TRIM): U8 count, then one S16 per servo of the live trim (from
-- a trim knob, never saved), then one S16 per servo of the saved trim (from
-- trim buttons and AUTO TRIM). Index N is servo S(N+1), as in every servo
-- message.
--
-- Only the saved trim is decoded. The flight controller adds it to the
-- servo's output before holding that inside Min/Max, so it takes travel from
-- one side and gives it to the other (servoUpdate() in flight/servos.c).

if package.loaded["wfsuite.lib.msp_servo_trim"] then
  return package.loaded["wfsuite.lib.msp_servo_trim"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 233

-- Four servos, no live trim, no saved trim: matching MSP_STATUS's
-- servo_count fixture.
local SIMULATOR_RESPONSE = {4}
for i = 2, 1 + 4 * 2 * 2 do SIMULATOR_RESPONSE[i] = 0 end

local msp_servo_trim = {READ_COMMAND = READ_COMMAND}

-- Saved trim of servo i (0-based) lands in out[i]. A reply without the saved
-- block leaves every servo at 0. Returns the servo count.
function msp_servo_trim.decode(buf)
  buf.offset = 1
  local out = {}
  local count = mspcodec.readU8(buf) or 0
  local hasSaved = #buf >= 1 + count * 4
  for _ = 1, count do mspcodec.readS16(buf) end
  for i = 0, count - 1 do
    out[i] = hasSaved and (mspcodec.readS16(buf) or 0) or 0
  end
  return out, count
end

function msp_servo_trim.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      local out, count = msp_servo_trim.decode(buf)
      if onData then onData(out, count) end
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

package.loaded["wfsuite.lib.msp_servo_trim"] = msp_servo_trim
return msp_servo_trim
