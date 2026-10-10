-- Schema + message-builders for wingflight-firmware's tune advisor
-- statistics: MSP2_WING_TUNE_ADVISOR (cmd 0x5F18, read) and
-- MSP2_WING_TUNE_ADVISOR_CLEAR (cmd 0x5F19, write, empty payload). Both
-- are new messages with no MSP API version change: an FC without them
-- answers with an error, which the page reports as "needs newer firmware".
--
-- One axis per request so the reply (65 bytes) fits MSP over telemetry:
-- the request payload is U8 axis (0 roll, 1 pitch, 2 yaw).
--
-- Wire layout verified against wingflight-firmware's own serializer
-- (src/main/msp/msp.c, MSP2_WING_TUNE_ADVISOR case), payload version 1:
--   U8 version, U8 collecting, U16 seconds of usable flight, U8 axis, then:
--     U16 P, U16 F, U16 B, U8 iterm_relax, U8 rc_rate   (the tune measured)
--     U16 ffCount, S16 ffGain, S16 ffCorr, U16 ffLagMs
--     3 x {S16 gain, U16 count}  by request 40-100, 100-200, 200+ deg/s
--     3 x {S16 gain, U16 count}  by throttle <30%, 30-60%, 60%+
--     U16 fullCount, U16 fullSatCount, S16 fullRatio, U16 fullMaxRate
--     U16 releases, U16 bigRebounds, S16 meanRebound, S16 meanOvershoot,
--     S16 meanCounter, S16 meanIterm
-- Ratios are x1000 on the wire and decoded to plain numbers here. Counts
-- saturate at 65535. See src/main/flight/tune_advisor.c for what each one
-- measures.
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

local function buildSimulatorResponse(axis)
  local buf = {}
  local function ratio(v) mspcodec.writeS16(buf, math.floor(v * 1000 + 0.5)) end
  local a = SIM_AXES[axis]
  mspcodec.writeU8(buf, 1)
  mspcodec.writeU8(buf, 0)
  mspcodec.writeU16(buf, 147)
  mspcodec.writeU8(buf, axis - 1)
  mspcodec.writeU16(buf, a.p)
  mspcodec.writeU16(buf, a.f)
  mspcodec.writeU16(buf, a.b)
  mspcodec.writeU8(buf, a.relax)
  mspcodec.writeU8(buf, a.rate)
  mspcodec.writeU16(buf, a.ffCount)
  ratio(a.ff)
  ratio(a.corr)
  mspcodec.writeU16(buf, a.lag)
  for i = 1, BAND_COUNT do ratio(a.sp[i][1]); mspcodec.writeU16(buf, a.sp[i][2]) end
  for i = 1, BAND_COUNT do ratio(a.thr[i][1]); mspcodec.writeU16(buf, a.thr[i][2]) end
  mspcodec.writeU16(buf, a.full[1])
  mspcodec.writeU16(buf, a.full[2])
  ratio(a.full[3])
  mspcodec.writeU16(buf, a.full[4])
  mspcodec.writeU16(buf, a.rel[1])
  mspcodec.writeU16(buf, a.rel[2])
  ratio(a.rel[3])
  ratio(a.rel[4])
  ratio(a.rel[5])
  ratio(a.rel[6])
  return buf
end

local function readRatio(buf)
  return (mspcodec.readS16(buf) or 0) / 1000
end

local function readBands(buf)
  local bands = {}
  for i = 1, BAND_COUNT do
    bands[i] = {gain = readRatio(buf), count = mspcodec.readU16(buf) or 0}
  end
  return bands
end

-- Returns {version, collecting, seconds, axis (1-3), a = {per-axis fields}}
function msp_tune_advisor.decode(buf)
  buf.offset = 1
  local data = {
    version = mspcodec.readU8(buf),
    collecting = mspcodec.readU8(buf) ~= 0,
    seconds = mspcodec.readU16(buf) or 0,
    axis = (mspcodec.readU8(buf) or 0) + 1,
  }

  data.a = {
    P = mspcodec.readU16(buf) or 0,
    F = mspcodec.readU16(buf) or 0,
    B = mspcodec.readU16(buf) or 0,
    relax = mspcodec.readU8(buf) or 0,
    rcRate = mspcodec.readU8(buf) or 0,
    ffCount = mspcodec.readU16(buf) or 0,
    ffGain = readRatio(buf),
    ffCorr = readRatio(buf),
    ffLagMs = mspcodec.readU16(buf) or 0,
    spBands = readBands(buf),
    thrBands = readBands(buf),
    fullCount = mspcodec.readU16(buf) or 0,
    fullSatCount = mspcodec.readU16(buf) or 0,
    fullRatio = readRatio(buf),
    fullMaxRate = mspcodec.readU16(buf) or 0,
    releases = mspcodec.readU16(buf) or 0,
    bigRebounds = mspcodec.readU16(buf) or 0,
    meanRebound = readRatio(buf),
    meanOvershoot = readRatio(buf),
    meanCounter = readRatio(buf),
    meanIterm = readRatio(buf),
  }

  return data
end

local simulatorResponses = {}

-- axis: 1 roll, 2 pitch, 3 yaw
function msp_tune_advisor.buildReadMessage(axis, onData, onError)
  simulatorResponses[axis] = simulatorResponses[axis] or buildSimulatorResponse(axis)
  return {
    command = READ_COMMAND,
    payload = {axis - 1},
    processReply = function(_, buf)
      onData(msp_tune_advisor.decode(buf))
    end,
    errorHandler = onError,
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
