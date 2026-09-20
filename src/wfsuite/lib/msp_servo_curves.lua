-- Schema + message-builders for the MSP_SERVO_CURVES / MSP_SET_SERVO_CURVE
-- command pair (cmd 231 read / 232 write) -- one optional "balance" curve
-- per physical servo, added on top of that servo's own output on the FC
-- (servoUpdate() in flight/servos.c, after mixing and geometry
-- correction) so one servo's travel can be trimmed to match a paired servo
-- driving the same control surface (e.g. dual ailerons).
--
-- Wire layout verified against wingflight-firmware's src/main/msp/msp.c
-- (MSP_SERVO_CURVES serializer / MSP_SET_SERVO_CURVE parser, commit
-- aa362d09a) and src/main/pg/servo_curve.h -- see AGENTS.md Section 8.
--
-- Same asymmetric GET/SET shape as lib/msp_mixer_curves.lua (whole-pool
-- GET, one-curve-at-a-time SET selected by a leading index byte), with
-- two differences:
--   * There is no fixed pool size: GET is prefixed with a servo-count U8
--     (PWM servos, plus BUS_SERVO_CHANNELS more when bus servos are
--     configured -- the same count/remap MSP_SERVO_CONFIGURATIONS uses),
--     so the number of curves is read off the wire, not a CURVE_COUNT
--     constant here. SET's index is in that same 0-based count space; the
--     firmware does the PWM/bus-servo remap itself.
--   * Y is a small corrective delta (-100..100, i.e. +-10%), not a
--     replacement value: the neutral/default curve is flat at y=0, not
--     the x==y diagonal. X is the servo's own output, -1000..1000.
--
-- Per curve: count:U8, then POINT_COUNT points of (x:S16, y:S16), always
-- all POINT_COUNT slots (points beyond `count` are inert padding, still
-- present on the wire, never truncated on write). The firmware rejects a
-- SET whose count is outside 2..POINT_COUNT.

if package.loaded["wfsuite.lib.msp_servo_curves"] then
  return package.loaded["wfsuite.lib.msp_servo_curves"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")
local curvePoints = requireModule("lib/curve_points.lua")

local READ_COMMAND = 231
local WRITE_COMMAND = 232
local POINT_COUNT = 9

local FIELD_META = {
  x = {min = -1000, max = 1000, default = 0},
  y = {min = -100, max = 100, default = 0},
  count = {min = 2, max = POINT_COUNT, default = 2},
}

local function defaultCurve()
  return curvePoints.nullCurve(POINT_COUNT, {{x = -1000, y = 0}, {x = 1000, y = 0}})
end

-- Simulator fixture: 4 servos, each the default flat curve. Per curve:
-- count=2, the two default endpoints (S16 LE: -1000 -> 0x18,0xFC ; 1000 ->
-- 0xE8,0x03; y=0 -> 0,0), then 0-filled padding for the remaining
-- POINT_COUNT-2 slots -- matches defaultCurve() byte-for-byte.
local SIMULATOR_SERVO_COUNT = 4

local SIMULATOR_RESPONSE_POOL = {SIMULATOR_SERVO_COUNT}
for _ = 1, SIMULATOR_SERVO_COUNT do
  local bytes = {2, 24, 252, 0, 0, 232, 3, 0, 0}
  for _ = 3, POINT_COUNT do
    bytes[#bytes + 1] = 0
    bytes[#bytes + 1] = 0
    bytes[#bytes + 1] = 0
    bytes[#bytes + 1] = 0
  end
  for j = 1, #bytes do
    SIMULATOR_RESPONSE_POOL[#SIMULATOR_RESPONSE_POOL + 1] = bytes[j]
  end
end

local msp_servo_curves = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  POINT_COUNT = POINT_COUNT,
  FIELD_META = FIELD_META,
  SIMULATOR_RESPONSE_POOL = SIMULATOR_RESPONSE_POOL,
  defaultCurve = defaultCurve,
}

-- Decodes every servo's curve from one GET reply: servo-count U8, then that
-- many curves. The result's length is the live servo count.
function msp_servo_curves.decodePool(buf)
  buf.offset = 1
  local servoCount = mspcodec.readU8(buf)
  local pool = {}
  for i = 1, servoCount do
    local curve = {count = mspcodec.readU8(buf), points = {}}
    for p = 1, POINT_COUNT do
      curve.points[p] = {x = mspcodec.readS16(buf), y = mspcodec.readS16(buf)}
    end
    pool[i] = curve
  end
  return pool
end

-- Encodes ONE curve for MSP_SET_SERVO_CURVE: index:U8, count:U8, then all
-- POINT_COUNT points (no truncation to `count`).
function msp_servo_curves.encodeCurve(index, curve)
  curve = curve or defaultCurve()
  local payload = {}
  mspcodec.writeU8(payload, index)
  mspcodec.writeU8(payload, curve.count or 2)
  for p = 1, POINT_COUNT do
    local point = curve.points[p] or {x = 0, y = 0}
    mspcodec.writeS16(payload, point.x or 0)
    mspcodec.writeS16(payload, point.y or 0)
  end
  return payload
end

-- Whole-pool GET. Parameterless, matching lib/msp_mixer_curves.lua's
-- buildReadPoolMessage shape -- no per-servo read on the wire, only a
-- per-servo write.
function msp_servo_curves.buildReadPoolMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_servo_curves.decodePool(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE_POOL,
  }
end

-- Single-curve SET.
function msp_servo_curves.buildWriteMessage(index, curve, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_servo_curves.encodeCurve(index, curve),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_servo_curves"] = msp_servo_curves
return msp_servo_curves
