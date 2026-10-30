-- Schema + message-builders for wingflight-firmware's tune advisor
-- statistics: MSP2_WING_TUNE_ADVISOR (cmd 0x5F18, read) and
-- MSP2_WING_TUNE_ADVISOR_CLEAR (cmd 0x5F19, write, empty payload). Both
-- are new messages with no MSP API version change: an FC without them
-- answers with an error, which the page reports as "needs newer firmware".
--
-- One axis per request: the request payload is U8 axis (0 roll, 1 pitch,
-- 2 yaw). The reply is 48 bytes: one CRSF frame, and 11 S.Port/FBUS frames.
--
-- Wire layout verified against wingflight-firmware's own serializer
-- (src/main/msp/msp.c, MSP2_WING_TUNE_ADVISOR case), payload version 2:
--   U8 version, U8 flags (bits 0-1 axis, bit 2 collecting), U16 seconds of
--   usable flight, then:
--     U32 P | F << 10 | B << 20, U8 iterm_relax, U8 rc_rate (the tune measured)
--     U16 ffCount, U8 ffGain x64, S8 ffCorr x100, U8 ffLagMs
--     3 x {U8 gain x64, U16 count}  by request 40-100, 100-200, 200+ deg/s
--     3 x {U8 gain x64, U16 count}  by throttle <30%, 30-60%, 60%+
--     U16 fullCount, U16 fullSatCount, U8 fullRatio x100,
--     U8 fullMaxRate in 10 deg/s
--     U16 releases, U16 bigRebounds, U8 meanRebound x100,
--     U8 meanOvershoot x64, U8 meanCounter x100, S16 meanIterm x1000
-- Scaled values are decoded to plain numbers here; the firmware saturates
-- each at its byte's range. Counts saturate at 65535.
--
-- Payload version 1 (65 bytes, snapshots 0.0.32 to 0.0.38) is still read:
--   U8 version, U8 collecting, U16 seconds, U8 axis, U16 P, U16 F, U16 B,
--   U8 iterm_relax, U8 rc_rate, U16 ffCount, S16 ffGain, S16 ffCorr,
--   U16 ffLagMs, 3 + 3 x {S16 gain, U16 count}, U16 fullCount,
--   U16 fullSatCount, S16 fullRatio, U16 fullMaxRate, U16 releases,
--   U16 bigRebounds, then S16 meanRebound, meanOvershoot, meanCounter and
--   meanIterm, every S16 a ratio x1000.
-- See src/main/flight/tune_advisor.c for what each value measures.
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_tune_advisor"] then
  return package.loaded["wfsuite.lib.msp_tune_advisor"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F18
local CLEAR_COMMAND = 0x5F19
local AXIS_COUNT = 3
local BAND_COUNT = 3

local msp_tune_advisor = {
  READ_COMMAND = READ_COMMAND,
  CLEAR_COMMAND = CLEAR_COMMAND,
  AXIS_COUNT = AXIS_COUNT,
}

-- Simulator fixture, one reply per axis: the roll numbers of a real log (a
-- 3D airframe with F hot and the usual stop bounce), pitch too irregular to
-- judge, yaw quiet. The tune (P, F, B, relax, rate) is the other fixtures'
-- (lib/msp_pid_tuning.lua, msp_pid_profile.lua, msp_rc_tuning.lua), so the
-- Tune Advisor's Apply finds the FC still on the tune that was flown.
local SIM_AXES = {
  {p = 105, f = 65, b = 35, relax = 5, rate = 18, ffCount = 1491, ff = 1.53, corr = 0.97, lag = 90,
   sp = {{1.52, 1341}, {1.54, 163}, {1.03, 50}}, thr = {{1.24, 385}, {1.54, 763}, {1.73, 356}},
   full = {87, 25, 0.38, 395}, rel = {35, 18, 0.15, 1.47, 0.020, 0.003}},
  {p = 105, f = 65, b = 35, relax = 5, rate = 18, ffCount = 1172, ff = 0.79, corr = 0.78, lag = 70,
   sp = {{1.06, 999}, {0.45, 194}, {0, 54}}, thr = {{0.28, 446}, {1.27, 629}, {1.59, 118}},
   full = {105, 72, 0, 23}, rel = {10, 2, 0.09, 1.33, 0.019, 0.011}},
  {p = 190, f = 65, b = 35, relax = 5, rate = 18, ffCount = 404, ff = 0.27, corr = 0.84, lag = 250,
   sp = {{0.26, 300}, {0.30, 109}, {0, 0}}, thr = {{0.29, 409}, {0, 0}, {0, 0}},
   full = {29, 29, 0.09, 42}, rel = {0, 0, 0, 0, 0, 0}},
}

-- Payload versions this codec reads: reply length by version. Version 2
-- (firmware msp.c, MSP2_WING_TUNE_ADVISOR) writes its one-byte values as
-- value x scale.
local PAYLOAD_VERSION = 2
local REPLY_LENGTHS = {[1] = 65, [2] = 48}
local GAIN_SCALE = 64        -- ffGain, band gains, meanOvershoot: U8, 0..3.98
local CORR_SCALE = 100       -- ffCorr: S8, -1.27..1.27
local FRACTION_SCALE = 100   -- fullRatio, meanRebound, meanCounter: U8, 0..2.55
local RATE_STEP = 10         -- fullMaxRate: U8 in steps of 10 deg/s
local ITERM_SCALE = 1000     -- meanIterm, and every version 1 ratio: S16
local GAIN_BITS = 1024       -- P, F and B: 10 bits each of one U32

local function scaled(v, scale, lo, hi)
  local n = math.floor(v * scale + 0.5)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function buildSimulatorResponse(axis)
  local buf = {}
  local a = SIM_AXES[axis]
  local function u8(v, scale) mspcodec.writeU8(buf, scaled(v, scale, 0, 255)) end
  mspcodec.writeU8(buf, PAYLOAD_VERSION)
  mspcodec.writeU8(buf, axis - 1)    -- not collecting
  mspcodec.writeU16(buf, 147)
  mspcodec.writeU32(buf, a.p + a.f * GAIN_BITS + a.b * GAIN_BITS * GAIN_BITS)
  mspcodec.writeU8(buf, a.relax)
  mspcodec.writeU8(buf, a.rate)
  mspcodec.writeU16(buf, a.ffCount)
  u8(a.ff, GAIN_SCALE)
  mspcodec.writeS8(buf, scaled(a.corr, CORR_SCALE, -128, 127))
  mspcodec.writeU8(buf, a.lag)
  for i = 1, BAND_COUNT do u8(a.sp[i][1], GAIN_SCALE); mspcodec.writeU16(buf, a.sp[i][2]) end
  for i = 1, BAND_COUNT do u8(a.thr[i][1], GAIN_SCALE); mspcodec.writeU16(buf, a.thr[i][2]) end
  mspcodec.writeU16(buf, a.full[1])
  mspcodec.writeU16(buf, a.full[2])
  u8(a.full[3], FRACTION_SCALE)
  u8(a.full[4], 1 / RATE_STEP)
  mspcodec.writeU16(buf, a.rel[1])
  mspcodec.writeU16(buf, a.rel[2])
  u8(a.rel[3], FRACTION_SCALE)
  u8(a.rel[4], GAIN_SCALE)
  u8(a.rel[5], FRACTION_SCALE)
  mspcodec.writeS16(buf, scaled(a.rel[6], ITERM_SCALE, -32768, 32767))
  return buf
end

local function readRatio(buf)
  return (mspcodec.readS16(buf) or 0) / ITERM_SCALE
end

local function readScaled(buf, scale)
  return (mspcodec.readU8(buf) or 0) / scale
end

-- readGain reads one band gain in the reply's encoding
local function readBands(buf, readGain)
  local bands = {}
  for i = 1, BAND_COUNT do
    bands[i] = {gain = readGain(buf), count = mspcodec.readU16(buf) or 0}
  end
  return bands
end

local function readGainV2(buf) return readScaled(buf, GAIN_SCALE) end

-- Version 1: every value 16-bit, axis and collecting in bytes of their own
local function decodeV1(buf)
  local data = {
    version = mspcodec.readU8(buf),
    collecting = mspcodec.readU8(buf) ~= 0,
    seconds = mspcodec.readU16(buf) or 0,
    axis = (mspcodec.readU8(buf) or 0) + 1,
  }
  local a = {}
  a.P = mspcodec.readU16(buf) or 0
  a.F = mspcodec.readU16(buf) or 0
  a.B = mspcodec.readU16(buf) or 0
  a.relax = mspcodec.readU8(buf) or 0
  a.rcRate = mspcodec.readU8(buf) or 0
  a.ffCount = mspcodec.readU16(buf) or 0
  a.ffGain = readRatio(buf)
  a.ffCorr = readRatio(buf)
  a.ffLagMs = mspcodec.readU16(buf) or 0
  a.spBands = readBands(buf, readRatio)
  a.thrBands = readBands(buf, readRatio)
  a.fullCount = mspcodec.readU16(buf) or 0
  a.fullSatCount = mspcodec.readU16(buf) or 0
  a.fullRatio = readRatio(buf)
  a.fullMaxRate = mspcodec.readU16(buf) or 0
  a.releases = mspcodec.readU16(buf) or 0
  a.bigRebounds = mspcodec.readU16(buf) or 0
  a.meanRebound = readRatio(buf)
  a.meanOvershoot = readRatio(buf)
  a.meanCounter = readRatio(buf)
  a.meanIterm = readRatio(buf)
  data.a = a
  return data
end

-- Version 2: the packed layout described at the top
local function decodeV2(buf)
  local version = mspcodec.readU8(buf)
  local flags = mspcodec.readU8(buf) or 0
  local data = {
    version = version,
    collecting = (flags // 4) % 2 == 1,
    seconds = mspcodec.readU16(buf) or 0,
    axis = flags % 4 + 1,
  }
  local gains = mspcodec.readU32(buf) or 0
  local a = {
    P = gains % GAIN_BITS,
    F = (gains // GAIN_BITS) % GAIN_BITS,
    B = (gains // (GAIN_BITS * GAIN_BITS)) % GAIN_BITS,
  }
  a.relax = mspcodec.readU8(buf) or 0
  a.rcRate = mspcodec.readU8(buf) or 0
  a.ffCount = mspcodec.readU16(buf) or 0
  a.ffGain = readScaled(buf, GAIN_SCALE)
  a.ffCorr = (mspcodec.readS8(buf) or 0) / CORR_SCALE
  a.ffLagMs = mspcodec.readU8(buf) or 0
  a.spBands = readBands(buf, readGainV2)
  a.thrBands = readBands(buf, readGainV2)
  a.fullCount = mspcodec.readU16(buf) or 0
  a.fullSatCount = mspcodec.readU16(buf) or 0
  a.fullRatio = readScaled(buf, FRACTION_SCALE)
  a.fullMaxRate = (mspcodec.readU8(buf) or 0) * RATE_STEP
  a.releases = mspcodec.readU16(buf) or 0
  a.bigRebounds = mspcodec.readU16(buf) or 0
  a.meanRebound = readScaled(buf, FRACTION_SCALE)
  a.meanOvershoot = readScaled(buf, GAIN_SCALE)
  a.meanCounter = readScaled(buf, FRACTION_SCALE)
  a.meanIterm = readRatio(buf)
  data.a = a
  return data
end

-- Returns {version, collecting, seconds, axis (1-3), a = {per-axis fields}},
-- or nil, a reason, and true when the reply was REFUSED rather than lost.
-- A reply of another version, or of another length than its version's, is
-- refused, not decoded: a reworded record would otherwise come out as
-- plausible numbers, and tune_history saves them.
--
-- The third value is what separates the two reasons a caller can do nothing about differently.
-- `true` from the transport means the firmware has no tune advisor at all; a refusal means it has
-- one and answered, in a layout this suite does not know. Both are deterministic -- asking again
-- cannot change either -- so a caller retries neither. The reason text stays a string, so a log
-- line and a pilot-facing message can name what came back.
function msp_tune_advisor.decode(buf)
  local length = #buf
  local expected = REPLY_LENGTHS[buf[1]]
  if not expected then
    return nil, "tune advisor payload version " .. tostring(buf[1]) .. ", expected 1 or 2", true
  end
  if length ~= expected then
    return nil, "tune advisor reply is " .. length .. " bytes, expected " .. expected, true
  end

  buf.offset = 1
  if buf[1] == 1 then return decodeV1(buf) end
  return decodeV2(buf)
end

local simulatorResponses = {}

-- axis: 1 roll, 2 pitch, 3 yaw
function msp_tune_advisor.buildReadMessage(axis, onData, onError)
  simulatorResponses[axis] = simulatorResponses[axis] or buildSimulatorResponse(axis)
  return {
    command = READ_COMMAND,
    payload = {axis - 1},
    processReply = function(_, buf)
      local data, reason, refused = msp_tune_advisor.decode(buf)
      if not data then
        -- `errorHandler` below answers an MSP error reply with `reason` alone, so a caller
        -- that tests the third value sees nil there and can still tell the two apart.
        if onError then onError(reason, refused) end
        return
      end
      onData(data)
    end,
    errorHandler = onError,
    -- Three sends, not the queue's six: the queue holds every other request
    -- while this one is out, and an 11-frame reply over S.Port or FBUS is the
    -- one most often lost. tasks/tune_history.lua asks again later anyway.
    maxRetries = 2,
    simulatorResponse = simulatorResponses[axis],
  }
end

function msp_tune_advisor.buildClearMessage(onDone, onError)
  return {
    command = CLEAR_COMMAND,
    payload = {},
    isWrite = true,
    processReply = function()
      if onDone then onDone() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_tune_advisor"] = msp_tune_advisor
return msp_tune_advisor
