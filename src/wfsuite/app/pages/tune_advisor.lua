-- Configuration -> Flight Tuning -> Tune Advisor page.
--
-- Reads the FC's in-flight rate-loop statistics (lib/msp_tune_advisor.lua,
-- wingflight-firmware flight/tune_advisor.c) and turns them into one short
-- suggestion per topic per axis. The firmware only measures; the rules
-- below are the advice, kept here so they can change without a flash.
--
-- Rules, per axis (yaw's rudder response is not judged):
-- - Feed-forward match (gyro / setpoint at the best delay). Above FF_HOT the
--   aircraft outruns the stick: suggest lower F and higher rates by the
--   same factor, which keeps the stick-to-surface feel. Below FF_LOW it
--   lags: the reverse. One step is capped at FF_STEP_MAX so the pilot flies
--   and re-checks rather than jumping.
-- - Throttle spread and big-input fall-off are shown as facts, no action.
-- - Full stick (roll only; 3D pitch parks at full elevator on purpose):
--   surfaces saturated and the rate reached well below the rate asked.
-- - Stick releases: the rebound after a stop. I-term pushing back points
--   at I-term Relax; otherwise the controller is barely braking, so more P
--   (once F matches) or B.
--
-- Clear (header Tool button) resets the FC's statistics; they also reset
-- on their own when the tune changes.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local header = requireModule("app/header.lua")
local common = requireModule("app/diagnostics_common.lua")
local tuneAdvisor = requireModule("lib/msp_tune_advisor.lua")

local PAGE_TITLE = "@i18n(app.modules.tune_advisor.name)@"
local BTN_OK = "@i18n(app.btn_ok)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"

local T = {
  data = "@i18n(app.modules.tune_advisor.data)@",
  dataFmt = "@i18n(app.modules.tune_advisor.data_fmt)@",
  collecting = "@i18n(app.modules.tune_advisor.collecting)@",
  paused = "@i18n(app.modules.tune_advisor.paused)@",
  unsupported = "@i18n(app.modules.tune_advisor.unsupported)@",
  clearPrompt = "@i18n(app.modules.tune_advisor.clear_prompt)@",
  axes = {
    "@i18n(app.modules.tune_advisor.roll)@",
    "@i18n(app.modules.tune_advisor.pitch)@",
    "@i18n(app.modules.tune_advisor.yaw)@",
  },
  matchFmt = "@i18n(app.modules.tune_advisor.match_fmt)@",
  ffMoreFmt = "@i18n(app.modules.tune_advisor.ff_more_fmt)@",
  ffIrregular = "@i18n(app.modules.tune_advisor.ff_irregular)@",
  ffHotFmt = "@i18n(app.modules.tune_advisor.ff_hot_fmt)@",
  ffLowFmt = "@i18n(app.modules.tune_advisor.ff_low_fmt)@",
  ffOkFmt = "@i18n(app.modules.tune_advisor.ff_ok_fmt)@",
  throttleFmt = "@i18n(app.modules.tune_advisor.throttle_fmt)@",
  bigInputsFmt = "@i18n(app.modules.tune_advisor.big_inputs_fmt)@",
  fullStickFmt = "@i18n(app.modules.tune_advisor.full_stick_fmt)@",
  stopsMoreFmt = "@i18n(app.modules.tune_advisor.stops_more_fmt)@",
  stopsOkFmt = "@i18n(app.modules.tune_advisor.stops_ok_fmt)@",
  stopsRelaxFmt = "@i18n(app.modules.tune_advisor.stops_relax_fmt)@",
  stopsFixFFmt = "@i18n(app.modules.tune_advisor.stops_fix_f_fmt)@",
  stopsBrakeFmt = "@i18n(app.modules.tune_advisor.stops_brake_fmt)@",
  yawNotJudged = "@i18n(app.modules.tune_advisor.yaw_not_judged)@",
}

local REFRESH_INTERVAL_SECONDS = 2

local AXIS_ROLL, AXIS_PITCH, AXIS_YAW = 1, 2, 3

-- Feed-forward match
local FF_MIN_COUNT = 1000       -- 10 s of usable 40-200 deg/s stick
local FF_MIN_CORR = 0.85
local FF_HOT = 1.15
local FF_LOW = 0.85
local FF_STEP_MAX = 0.2         -- change F by at most 20% per step
local F_MIN, F_MAX = 0, 1000    -- PID_GAIN_MAX
local RC_RATE_MAX = 200         -- CONTROL_RATE_CONFIG_RC_RATES_MAX; deg/s = rc_rate x 5

-- Facts worth showing
local BAND_MIN_COUNT = 300
local THROTTLE_SPREAD = 1.25
local BIG_INPUT_FALLOFF = 1.3

-- Full stick
local FULL_MIN_COUNT = 100
local FULL_SAT_SHARE = 0.5
local FULL_REACH = 0.8

-- Stick releases
local STOPS_MIN = 10
local REBOUND_BAD = 0.12
local ITERM_PUSH = 0.03         -- I at release, surface units
local P_STEP = 1.2

local LINES_PER_AXIS = 3

local function round(v)
  return math.floor(v + 0.5)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function ratioText(v)
  return string.format("%.2f", v)
end

local function ffJudged(a)
  return a.ffCount >= FF_MIN_COUNT and a.ffCorr >= FF_MIN_CORR
end

local function ffAdvice(a, axis)
  if axis == AXIS_YAW then return T.yawNotJudged end
  if a.ffCount < FF_MIN_COUNT then
    return string.format(T.ffMoreFmt, math.floor(100 * a.ffCount / FF_MIN_COUNT))
  end
  if a.ffCorr < FF_MIN_CORR then return T.ffIrregular end

  local g = a.ffGain
  if g > FF_HOT or g < FF_LOW then
    local scale = clamp(1 / g, 1 - FF_STEP_MAX, 1 + FF_STEP_MAX)
    local newF = clamp(round(a.F * scale), F_MIN, F_MAX)
    -- Keep stick-to-surface the same: F x rate is what the pilot feels
    local newRate = (newF > 0) and clamp(round(a.rcRate * a.F / newF), 1, RC_RATE_MAX) or a.rcRate
    return string.format(g > FF_HOT and T.ffHotFmt or T.ffLowFmt, ratioText(g), a.F, newF, a.rcRate, newRate)
  end
  return string.format(T.ffOkFmt, ratioText(g))
end

-- Second line: the most useful fact about how the response varies
local function responseNote(a, axis)
  if axis == AXIS_YAW or not ffJudged(a) then return "" end

  if axis == AXIS_ROLL and a.fullCount >= FULL_MIN_COUNT
      and a.fullSatCount >= FULL_SAT_SHARE * a.fullCount
      and a.fullMaxRate < FULL_REACH * a.rcRate * 5 then
    return string.format(T.fullStickFmt, a.rcRate * 5, a.fullMaxRate)
  end

  local lo, hi = a.thrBands[1], a.thrBands[3]
  if lo.count >= BAND_MIN_COUNT and hi.count >= BAND_MIN_COUNT and lo.gain > 0 and hi.gain > 0 then
    local spread = math.max(lo.gain, hi.gain) / math.min(lo.gain, hi.gain)
    if spread >= THROTTLE_SPREAD then
      return string.format(T.throttleFmt, ratioText(lo.gain), ratioText(hi.gain))
    end
  end

  local small, mid = a.spBands[1], a.spBands[2]
  if small.count >= BAND_MIN_COUNT and mid.count >= BAND_MIN_COUNT and mid.gain > 0
      and small.gain / mid.gain >= BIG_INPUT_FALLOFF then
    return string.format(T.bigInputsFmt, ratioText(small.gain), ratioText(mid.gain))
  end

  return ""
end

local function stopsAdvice(a, axis)
  if axis == AXIS_YAW then return "" end
  if a.releases < STOPS_MIN then
    return string.format(T.stopsMoreFmt, a.releases, STOPS_MIN)
  end

  local rebound = round(a.meanRebound * 100)
  if a.meanRebound < REBOUND_BAD then
    return string.format(T.stopsOkFmt, rebound)
  end
  if a.meanIterm >= ITERM_PUSH then
    return string.format(T.stopsRelaxFmt, rebound)
  end
  if ffJudged(a) and (a.ffGain > FF_HOT or a.ffGain < FF_LOW) then
    return string.format(T.stopsFixFFmt, rebound)
  end
  return string.format(T.stopsBrakeFmt, rebound, a.P, clamp(round(a.P * P_STEP), a.P + 1, F_MAX))
end

local function open(opts)
  opts = opts or {}
  local disposed = false
  local headerHandle = nil
  local pending = false
  local lastPoll = 0
  local lastSignature = nil
  local fieldCache = {}

  local dataField = nil
  local axisFields = {}   -- [axis] = {match = field, lines = {field, field, field}}

  local function setField(field, value)
    if not field or fieldCache[field] == value then return end
    fieldCache[field] = value
    common.updateField(field, value)
  end

  local function setLine(field, value)
    if not field or fieldCache[field] == value then return end
    fieldCache[field] = value
    if field.value then field:value(value) end
  end

  local function showUnsupported()
    setField(dataField, T.unsupported)
    for axis = 1, tuneAdvisor.AXIS_COUNT do
      setField(axisFields[axis].match, "-")
      for i = 1, LINES_PER_AXIS do setLine(axisFields[axis].lines[i], "") end
    end
  end

  local function apply(data)
    -- Skip the rebuild when nothing new was collected
    local signature = data.seconds * 2 + (data.collecting and 1 or 0)
    for axis = 1, tuneAdvisor.AXIS_COUNT do
      local a = data.axes[axis]
      signature = signature * 31 + a.ffCount + a.releases + a.fullCount + a.F + a.P + a.rcRate
    end
    if signature == lastSignature then return end
    lastSignature = signature

    setField(dataField, string.format(T.dataFmt, math.floor(data.seconds / 60), data.seconds % 60,
      data.collecting and T.collecting or T.paused))

    for axis = 1, tuneAdvisor.AXIS_COUNT do
      local a = data.axes[axis]
      local f = axisFields[axis]
      if axis ~= AXIS_YAW and a.ffCount > 0 then
        setField(f.match, string.format(T.matchFmt, ratioText(a.ffGain), a.ffLagMs))
      else
        setField(f.match, "-")
      end
      setLine(f.lines[1], ffAdvice(a, axis))
      setLine(f.lines[2], responseNote(a, axis))
      setLine(f.lines[3], stopsAdvice(a, axis))
    end
  end

  local function poll()
    if disposed or pending then return end
    pending = true
    if headerHandle then headerHandle.setReloadEnabled(false) end
    bus.publish("msp.request", tuneAdvisor.buildReadMessage(function(data)
      pending = false
      if disposed then return end
      if headerHandle then headerHandle.setReloadEnabled(true) end
      apply(data)
    end, function()
      pending = false
      if disposed then return end
      if headerHandle then headerHandle.setReloadEnabled(true) end
      lastSignature = nil
      showUnsupported()
    end))
  end

  local function clear()
    if disposed then return end
    bus.publish("msp.request", tuneAdvisor.buildClearMessage(function()
      if disposed then return end
      lastSignature = nil
      poll()
    end))
  end

  local function confirmClear()
    form.openDialog({
      title = PAGE_TITLE,
      message = T.clearPrompt,
      buttons = {
        {label = BTN_OK, action = function() clear(); return true end},
        {label = BTN_CANCEL, action = function() return true end},
      },
      wakeup = function() end,
      paint = function() end,
    })
  end

  local function goBack()
    disposed = true
    if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
    if opts.setCleanupHandler then opts.setCleanupHandler(nil) end
    if opts.onBack then opts.onBack() end
  end

  form.clear()
  headerHandle = header.build(PAGE_TITLE, {
    onBack = goBack,
    onReload = function()
      lastSignature = nil
      poll()
      if headerHandle then headerHandle.focusReload() end
    end,
    onTool = confirmClear,
  })

  if opts.setEventHandler then
    opts.setEventHandler(function(category, value)
      if closeKey.shouldHandleClose(category, value) then
        goBack()
        return true
      end
      return false
    end)
  end
  if opts.setCleanupHandler then
    opts.setCleanupHandler(function()
      disposed = true
      for k in pairs(fieldCache) do fieldCache[k] = nil end
    end)
  end
  if opts.setWakeupHandler then
    opts.setWakeupHandler(function()
      local now = os.clock()
      if not pending and now - lastPoll >= REFRESH_INTERVAL_SECONDS then
        lastPoll = now
        poll()
      end
    end)
  end

  dataField = common.addValueLine(T.data, "-")
  for axis = 1, tuneAdvisor.AXIS_COUNT do
    local lines = {}
    local match = common.addValueLine(T.axes[axis], "-")
    for i = 1, LINES_PER_AXIS do
      lines[i] = common.addTextLine("", 8)
    end
    axisFields[axis] = {match = match, lines = lines}
  end

  poll()
end

return {open = open}
