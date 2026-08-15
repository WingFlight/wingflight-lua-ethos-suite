-- Schema + message-builders for the MSP_MIXER_CURVES / MSP_SET_MIXER_CURVE
-- command pair (cmd 177 read / 178 write) -- the 8-slot pool of mixer
-- curves referenced by rule weight/output curve indices elsewhere on the
-- wire (not exposed by this rebuild yet).
--
-- **Wire layout below is derived from wingflight-configurator's own
-- src/js/msp/MSPCodes.js + src/js/msp/MSPHelper.js (its MIXER_CURVES
-- parser / sendMixerCurve encoder), NOT yet independently verified
-- against wingflight-firmware's actual src/main/msp/msp.c serializer** --
-- unlike every other codec in this directory (see lib/msp_pid_profile.lua's
-- header for what that verification looks like). Confirm against firmware
-- before trusting this in the field.
--
-- Unlike every other codec here, GET and SET are asymmetric: GET returns
-- the WHOLE 8-curve pool in one reply (no index argument on the read
-- side), while SET writes exactly ONE curve at a time, selected by a
-- leading index byte -- matching the ground station's own
-- sendMixerCurve(). Per curve: count:U8, then POINT_COUNT points of
-- (x:S16, y:S16), always all POINT_COUNT slots (points beyond `count` are
-- inert padding, still present on the wire, never truncated on write).

if package.loaded["wfsuite.lib.msp_mixer_curves"] then
  return package.loaded["wfsuite.lib.msp_mixer_curves"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")
local curvePoints = requireModule("lib/curve_points.lua")

local READ_COMMAND = 177
local WRITE_COMMAND = 178
local POINT_COUNT = 9
local CURVE_COUNT = 8

local FIELD_META = {
  x = {min = -1000, max = 1000, default = 0},
  y = {min = -1000, max = 1000, default = 0},
  count = {min = 2, max = POINT_COUNT, default = 2},
}

local function defaultCurve()
  return curvePoints.nullCurve(POINT_COUNT, {{x = -1000, y = -1000}, {x = 1000, y = 1000}})
end

-- One curve's worth of simulator fixture bytes: count=2, the two default
-- endpoints, then 0-filled padding for the remaining POINT_COUNT-2 slots
-- -- matches defaultCurve() byte-for-byte (S16 LE two's complement:
-- -1000 -> 0x18,0xFC ; 1000 -> 0xE8,0x03).
local function simulatorCurveBytes()
  local bytes = {2, 24, 252, 24, 252, 232, 3, 232, 3}
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

local msp_mixer_curves = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  POINT_COUNT = POINT_COUNT,
  CURVE_COUNT = CURVE_COUNT,
  FIELD_META = FIELD_META,
  SIMULATOR_RESPONSE_POOL = SIMULATOR_RESPONSE_POOL,
  defaultCurve = defaultCurve,
}

-- Decodes the whole 8-curve pool from one GET reply.
function msp_mixer_curves.decodePool(buf)
  buf.offset = 1
  local pool = {}
  for i = 1, CURVE_COUNT do
    local curve = {count = mspcodec.readU8(buf), points = {}}
    for p = 1, POINT_COUNT do
      curve.points[p] = {x = mspcodec.readS16(buf), y = mspcodec.readS16(buf)}
    end
    pool[i] = curve
  end
  return pool
end

-- Encodes ONE curve for MSP_SET_MIXER_CURVE: index:U8, count:U8, then all
-- POINT_COUNT points (no truncation to `count`).
function msp_mixer_curves.encodeCurve(index, curve)
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

-- Whole-pool GET. Parameterless, matching every other codec's
-- buildReadMessage shape (see lib/msp_pid_profile.lua) -- there is no
-- per-slot read on the wire, only a per-slot write.
function msp_mixer_curves.buildReadPoolMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_mixer_curves.decodePool(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE_POOL,
  }
end

-- Single-curve SET.
function msp_mixer_curves.buildWriteMessage(index, curve, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_mixer_curves.encodeCurve(index, curve),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_mixer_curves"] = msp_mixer_curves
return msp_mixer_curves
