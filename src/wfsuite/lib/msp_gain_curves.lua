-- Schema + message-builders for the MSP_GAIN_CURVES / MSP_SET_GAIN_CURVE
-- command pair (cmd 188 read / 189 write) -- the 8-slot pool of gain
-- curves referenced by app/pages/pid_controller.lua's `gain_curve_0/1/2`
-- (roll/pitch/yaw master-gain curve slots).
--
-- **Wire layout below is derived from wingflight-configurator's own
-- src/js/msp/MSPCodes.js + src/js/msp/MSPHelper.js (its GAIN_CURVES
-- parser / sendGainCurve encoder), NOT yet independently verified
-- against wingflight-firmware's actual src/main/msp/msp.c serializer** --
-- see lib/msp_mixer_curves.lua's header for the same caveat, which
-- applies here identically. Confirm against firmware before trusting
-- this in the field.
--
-- Same asymmetric GET-whole-pool/SET-one-curve shape as
-- lib/msp_mixer_curves.lua, differing only in point count and
-- signedness: POINT_COUNT=6 (vs. mixer's 9), and x/y are UNSIGNED here
-- (x = stick deflection magnitude 0..1000, y = percent gain 0..500,
-- NEUTRAL=100 -- a flat/unity gain curve), vs. mixer's signed
-- -1000..1000 on both axes.

if package.loaded["wfsuite.lib.msp_gain_curves"] then
  return package.loaded["wfsuite.lib.msp_gain_curves"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")
local curvePoints = requireModule("lib/curve_points.lua")

local READ_COMMAND = 188
local WRITE_COMMAND = 189
local POINT_COUNT = 6
local CURVE_COUNT = 8
local NEUTRAL = 100

local FIELD_META = {
  x = {min = 0, max = 1000, default = 0},
  y = {min = 0, max = 500, default = NEUTRAL},
  count = {min = 2, max = POINT_COUNT, default = 2},
}

local function defaultCurve()
  return curvePoints.nullCurve(POINT_COUNT, {{x = 0, y = NEUTRAL}, {x = 1000, y = NEUTRAL}})
end

-- One curve's worth of simulator fixture bytes: count=2, the two default
-- endpoints, then 0-filled padding for the remaining POINT_COUNT-2 slots
-- -- matches defaultCurve() byte-for-byte (U16 LE: 0 -> 0,0 ; 100 ->
-- 100,0 ; 1000 -> 232,3).
local function simulatorCurveBytes()
  local bytes = {2, 0, 0, 100, 0, 232, 3, 100, 0}
  for _ = 3, POINT_COUNT do
    bytes[#bytes + 1] = 0
    bytes[#bytes + 1] = 0
    bytes[#bytes + 1] = 0
    bytes[#bytes + 1] = 0
  end
  return bytes
end

local SIMULATOR_RESPONSE_POOL = {}
for _ = 1, CURVE_COUNT do
  local bytes = simulatorCurveBytes()
  for j = 1, #bytes do
    SIMULATOR_RESPONSE_POOL[#SIMULATOR_RESPONSE_POOL + 1] = bytes[j]
  end
end

local msp_gain_curves = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  POINT_COUNT = POINT_COUNT,
  CURVE_COUNT = CURVE_COUNT,
  NEUTRAL = NEUTRAL,
  FIELD_META = FIELD_META,
  SIMULATOR_RESPONSE_POOL = SIMULATOR_RESPONSE_POOL,
  defaultCurve = defaultCurve,
}

-- Decodes the whole 8-curve pool from one GET reply.
function msp_gain_curves.decodePool(buf)
  buf.offset = 1
  local pool = {}
  for i = 1, CURVE_COUNT do
    local curve = {count = mspcodec.readU8(buf), points = {}}
    for p = 1, POINT_COUNT do
      curve.points[p] = {x = mspcodec.readU16(buf), y = mspcodec.readU16(buf)}
    end
    pool[i] = curve
  end
  return pool
end

-- Encodes ONE curve for MSP_SET_GAIN_CURVE: index:U8, count:U8, then all
-- POINT_COUNT points (no truncation to `count`).
function msp_gain_curves.encodeCurve(index, curve)
  curve = curve or defaultCurve()
  local payload = {}
  mspcodec.writeU8(payload, index)
  mspcodec.writeU8(payload, curve.count or 2)
  for p = 1, POINT_COUNT do
    local point = curve.points[p] or {x = 0, y = 0}
    mspcodec.writeU16(payload, point.x or 0)
    mspcodec.writeU16(payload, point.y or 0)
  end
  return payload
end

-- Whole-pool GET. Parameterless -- see lib/msp_mixer_curves.lua's own
-- comment on this shape.
function msp_gain_curves.buildReadPoolMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_gain_curves.decodePool(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE_POOL,
  }
end

-- Single-curve SET.
function msp_gain_curves.buildWriteMessage(index, curve, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_gain_curves.encodeCurve(index, curve),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_gain_curves"] = msp_gain_curves
return msp_gain_curves
