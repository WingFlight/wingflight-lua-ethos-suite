-- Configuration -> Flight Tuning -> Tune Advisor page.
--
-- Reads the FC's in-flight rate-loop statistics (lib/msp_tune_advisor.lua,
-- wingflight-firmware flight/tune_advisor.c) and turns them into concrete
-- changes, one axis at a time: what was measured, which setting to change
-- (named by the page it lives on, in the units that page shows), and why.
-- The firmware only measures; the rules below are the advice, kept here so
-- they can change without a flash.
--
-- One axis at a time: the FC answers one axis per request so the reply
-- fits MSP over telemetry.
--
-- Rules, per axis:
-- - Feed-forward match (gyro / setpoint at the best delay), judged only
--   when the ratio is consistent (on a wing, rudder rarely is). Above FF_HOT the
--   aircraft outruns the stick: lower F and raise RC Rate by the same
--   factor, which keeps the stick-to-surface feel. Below FF_LOW, the
--   reverse. One step is capped at FF_STEP_MAX so the pilot flies and
--   re-checks rather than jumping.
-- - Full stick (roll only; 3D pitch parks at full elevator on purpose):
--   surfaces saturated and the rate reached well below the rate asked, so
--   RC Rate is suggested at what the model actually reaches.
-- - Throttle spread is shown as a fact, last, when there is room.
-- - Stick releases: the rebound after a stop. I-term pushing back points at
--   I-term Relax; with F still off, F comes first; otherwise the controller
--   is barely braking, so more P (or B).
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
  axis = "@i18n(app.modules.tune_advisor.axis)@",
  data = "@i18n(app.modules.tune_advisor.data)@",
  dataFmt = "@i18n(app.modules.tune_advisor.data_fmt)@",
  collecting = "@i18n(app.modules.tune_advisor.collecting)@",
  paused = "@i18n(app.modules.tune_advisor.paused)@",
  unsupported = "@i18n(app.modules.tune_advisor.unsupported)@",
  clearPrompt = "@i18n(app.modules.tune_advisor.clear_prompt)@",
  response = "@i18n(app.modules.tune_advisor.response)@",
  stops = "@i18n(app.modules.tune_advisor.stops)@",
  changes = "@i18n(app.modules.tune_advisor.changes)@",
  why = "@i18n(app.modules.tune_advisor.why)@",

  respMoreFmt = "@i18n(app.modules.tune_advisor.resp_more_fmt)@",
  respUneven = "@i18n(app.modules.tune_advisor.resp_uneven)@",
  respFastFmt = "@i18n(app.modules.tune_advisor.resp_fast_fmt)@",
  respSlowFmt = "@i18n(app.modules.tune_advisor.resp_slow_fmt)@",
  respOk = "@i18n(app.modules.tune_advisor.resp_ok)@",
  stopsMoreFmt = "@i18n(app.modules.tune_advisor.stops_more_fmt)@",
  stopsValueFmt = "@i18n(app.modules.tune_advisor.stops_value_fmt)@",

  actFlyRoll = "@i18n(app.modules.tune_advisor.act_fly_roll)@",
  actFlyPitch = "@i18n(app.modules.tune_advisor.act_fly_pitch)@",
  actFlyYaw = "@i18n(app.modules.tune_advisor.act_fly_yaw)@",
  actFFmt = "@i18n(app.modules.tune_advisor.act_f_fmt)@",
  actRateFmt = "@i18n(app.modules.tune_advisor.act_rate_fmt)@",
  actRelaxFmt = "@i18n(app.modules.tune_advisor.act_relax_fmt)@",
  actPFmt = "@i18n(app.modules.tune_advisor.act_p_fmt)@",
  actNone = "@i18n(app.modules.tune_advisor.act_none)@",

  whyMore = "@i18n(app.modules.tune_advisor.why_more)@",
  whyUneven = "@i18n(app.modules.tune_advisor.why_uneven)@",
  whyFast = "@i18n(app.modules.tune_advisor.why_fast)@",
  whySlow = "@i18n(app.modules.tune_advisor.why_slow)@",
  whyKeepFeel = "@i18n(app.modules.tune_advisor.why_keep_feel)@",
  whyFullFmt = "@i18n(app.modules.tune_advisor.why_full_fmt)@",
  whyThrHighFmt = "@i18n(app.modules.tune_advisor.why_thr_high_fmt)@",
  whyThrLowFmt = "@i18n(app.modules.tune_advisor.why_thr_low_fmt)@",
  whyRelax = "@i18n(app.modules.tune_advisor.why_relax)@",
  whyFixFFmt = "@i18n(app.modules.tune_advisor.why_fix_f_fmt)@",
  whyBrakeFmt = "@i18n(app.modules.tune_advisor.why_brake_fmt)@",
  whyOk = "@i18n(app.modules.tune_advisor.why_ok)@",
}

-- {label, axis}: axis is the FC's 1-based axis (1 roll, 2 pitch, 3 yaw)
local AXES = {
  {"@i18n(app.modules.tune_advisor.roll)@", 1},
  {"@i18n(app.modules.tune_advisor.pitch)@", 2},
  {"@i18n(app.modules.tune_advisor.yaw)@", 3},
}
local AXIS_ROLL, AXIS_PITCH = 1, 2

local REFRESH_INTERVAL_SECONDS = 2

-- Feed-forward match
local FF_MIN_COUNT = 1000       -- 10 s of usable 40-200 deg/s stick
local FF_MIN_CORR = 0.85
local FF_HOT = 1.15
local FF_LOW = 0.85
local FF_STEP_MAX = 0.2         -- change F by at most 20% per step
local F_MAX = 1000              -- PID_GAIN_MAX
local RC_RATE_MAX = 200         -- CONTROL_RATE_CONFIG_RC_RATES_MAX
local RC_RATE_DPS = 5           -- the Rates page shows RC Rate as raw x 5 deg/s

-- Throttle fact
local BAND_MIN_COUNT = 300
local THROTTLE_SPREAD = 1.25

-- Full stick
local FULL_MIN_COUNT = 100
local FULL_SAT_SHARE = 0.5
local FULL_REACH = 0.8

-- Stick releases
local STOPS_MIN = 10
local REBOUND_BAD = 0.12
local ITERM_PUSH = 0.03         -- I at release, surface units
local P_STEP = 1.2
local RELAX_MAX = 10

local MAX_ACTIONS = 3
local MAX_WHYS = 3

local function round(v)
  return math.floor(v + 0.5)
end

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function ffJudged(a)
  return a.ffCount >= FF_MIN_COUNT and a.ffCorr >= FF_MIN_CORR
end

local function ffOff(a)
  return ffJudged(a) and (a.ffGain > FF_HOT or a.ffGain < FF_LOW)
end

-- Fills actions/whys (cleared by the caller) for one axis; returns the
-- Response and Stops values.
local function advise(a, axis, name, actions, whys)
  local function act(s) if #actions < MAX_ACTIONS then actions[#actions + 1] = s end end
  local function why(s) if #whys < MAX_WHYS then whys[#whys + 1] = s end end

  -- Response: feed-forward match
  local response
  if a.ffCount < FF_MIN_COUNT then
    response = string.format(T.respMoreFmt, math.floor(100 * a.ffCount / FF_MIN_COUNT))
    act(axis == AXIS_ROLL and T.actFlyRoll or axis == AXIS_PITCH and T.actFlyPitch or T.actFlyYaw)
    why(T.whyMore)
  elseif a.ffCorr < FF_MIN_CORR then
    response = T.respUneven
    why(T.whyUneven)
  elseif ffOff(a) then
    local g = a.ffGain
    local hot = g > FF_HOT
    response = string.format(hot and T.respFastFmt or T.respSlowFmt, round(math.abs(g - 1) * 100))
    local newF = clamp(round(a.F * clamp(1 / g, 1 - FF_STEP_MAX, 1 + FF_STEP_MAX)), 1, F_MAX)
    -- Keep stick-to-surface the same: F x rate is what the pilot feels
    local newRate = clamp(round(a.rcRate * a.F / newF), 1, RC_RATE_MAX)
    act(string.format(T.actFFmt, name, a.F, newF))
    act(string.format(T.actRateFmt, name, a.rcRate * RC_RATE_DPS, newRate * RC_RATE_DPS))
    why(hot and T.whyFast or T.whySlow)
    why(T.whyKeepFeel)
  else
    response = T.respOk
    if axis == AXIS_ROLL and a.fullCount >= FULL_MIN_COUNT
        and a.fullSatCount >= FULL_SAT_SHARE * a.fullCount
        and a.fullMaxRate < FULL_REACH * a.rcRate * RC_RATE_DPS then
      local newRate = clamp(round(a.fullMaxRate / RC_RATE_DPS), 1, RC_RATE_MAX)
      act(string.format(T.actRateFmt, name, a.rcRate * RC_RATE_DPS, newRate * RC_RATE_DPS))
      why(string.format(T.whyFullFmt, a.rcRate * RC_RATE_DPS, a.fullMaxRate))
    end
  end

  -- Stops: rebound after a release
  local stops
  if a.releases < STOPS_MIN then
    stops = string.format(T.stopsMoreFmt, a.releases, STOPS_MIN)
  else
    local rebound = round(a.meanRebound * 100)
    stops = string.format(T.stopsValueFmt, rebound)
    if a.meanRebound >= REBOUND_BAD then
      if a.meanIterm >= ITERM_PUSH and a.relax < RELAX_MAX then
        act(string.format(T.actRelaxFmt, name, a.relax, a.relax + 1))
        why(T.whyRelax)
      elseif ffOff(a) then
        why(string.format(T.whyFixFFmt, rebound))
      else
        act(string.format(T.actPFmt, name, a.P, clamp(round(a.P * P_STEP), a.P + 1, F_MAX)))
        why(string.format(T.whyBrakeFmt, rebound))
      end
    end
  end

  -- Least important last: a fact, no action
  if ffJudged(a) then
    local lo, hi = a.thrBands[1], a.thrBands[3]
    if lo.count >= BAND_MIN_COUNT and hi.count >= BAND_MIN_COUNT and lo.gain > 0 and hi.gain > 0 then
      local spread = math.max(lo.gain, hi.gain) / math.min(lo.gain, hi.gain)
      if spread >= THROTTLE_SPREAD then
        why(string.format(hi.gain > lo.gain and T.whyThrHighFmt or T.whyThrLowFmt, round((spread - 1) * 100)))
      end
    end
  end

  if #actions == 0 then
    act(T.actNone)
    if #whys == 0 then why(T.whyOk) end
  end

  return response, stops
end

local function open(opts)
  opts = opts or {}
  local disposed = false
  local headerHandle = nil
  local pending = false
  local lastPoll = 0
  local lastData = nil
  local lastSignature = nil
  local selected = 1              -- index into AXES
  local fieldCache = {}
  local actions, whys = {}, {}

  local dataField, responseField, stopsField
  local actionFields, whyFields = {}, {}

  local function setValue(field, value)
    if not field or fieldCache[field] == value then return end
    fieldCache[field] = value
    common.updateField(field, value)
  end

  local function setText(field, value)
    if not field or fieldCache[field] == value then return end
    fieldCache[field] = value
    if field.value then field:value(value) end
  end

  local function clearList(list)
    for i = #list, 1, -1 do list[i] = nil end
  end

  local function showUnsupported()
    setValue(dataField, T.unsupported)
    setValue(responseField, "-")
    setValue(stopsField, "-")
    for i = 1, MAX_ACTIONS do setText(actionFields[i], "") end
    for i = 1, MAX_WHYS do setText(whyFields[i], "") end
  end

  local function render()
    local data = lastData
    local axis = AXES[selected][2]
    if not data or data.axis ~= axis then return end
    local a = data.a

    setValue(dataField, string.format(T.dataFmt, math.floor(data.seconds / 60), data.seconds % 60,
      data.collecting and T.collecting or T.paused))

    clearList(actions)
    clearList(whys)
    local response, stops = advise(a, axis, AXES[selected][1], actions, whys)
    setValue(responseField, response)
    setValue(stopsField, stops)
    for i = 1, MAX_ACTIONS do setText(actionFields[i], actions[i] or "") end
    for i = 1, MAX_WHYS do setText(whyFields[i], whys[i] or "") end
  end

  local function apply(data)
    -- Skip the rebuild when nothing new was collected
    local a = data.a
    local signature = ((data.seconds * 2 + (data.collecting and 1 or 0)) * 4 + data.axis) * 31
      + a.ffCount + a.releases + a.fullCount + a.F + a.P + a.rcRate + a.relax
    if signature == lastSignature then return end
    lastSignature = signature
    lastData = data
    render()
  end

  local function poll()
    if disposed or pending then return end
    pending = true
    if headerHandle then headerHandle.setReloadEnabled(false) end
    bus.publish("msp.request", tuneAdvisor.buildReadMessage(AXES[selected][2], function(data)
      pending = false
      if disposed then return end
      if headerHandle then headerHandle.setReloadEnabled(true) end
      if data.axis ~= AXES[selected][2] then
        poll()      -- the axis changed while this request was out
        return
      end
      apply(data)
    end, function()
      pending = false
      if disposed then return end
      if headerHandle then headerHandle.setReloadEnabled(true) end
      lastSignature = nil
      lastData = nil
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
      lastData = nil
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

  local axisLine = form.addLine(T.axis)
  form.addChoiceField(axisLine, nil, AXES,
    function() return AXES[selected][2] end,
    function(value)
      for i, entry in ipairs(AXES) do
        if entry[2] == value then selected = i end
      end
      -- Each axis is its own request: fetch the new one now
      lastSignature = nil
      lastPoll = os.clock()
      poll()
    end)

  dataField = common.addValueLine(T.data, "-")
  responseField = common.addValueLine(T.response, "-")
  stopsField = common.addValueLine(T.stops, "-")

  common.addTextLine(T.changes)
  for i = 1, MAX_ACTIONS do actionFields[i] = common.addTextLine("", 16) end
  common.addTextLine(T.why)
  for i = 1, MAX_WHYS do whyFields[i] = common.addTextLine("", 16) end

  poll()
end

return {open = open}
