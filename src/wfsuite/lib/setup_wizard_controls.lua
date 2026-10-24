-- Pure helpers for the Setup Wizard's radio controls: the Receiver step's
-- channel order, the Mode switches step's switch ranges, and the Trim and
-- gain step's adjustment ranges.
--
-- A port of wingflight-configurator src/tabs/setup_wizard/receiver.js,
-- modeRanges.js and trimGain.js. Keep them in step: the cases in
-- bin/tests/setup_wizard_controls.lua are the configurator's own, from
-- scripts/tests/setup-wizard-receiver.test.mjs,
-- setup-wizard-trim-gain.test.mjs and setup-wizard-surfaces.test.mjs.
-- Differences from the JS: lists are 1-based Lua arrays, but the values in
-- them (channels, AUX indexes) are the firmware's 0-based numbers, as in the
-- JS; ranges use ["end"] for end, as lib/msp_adjustments.lua and
-- lib/msp_modes.lua do.

if package.loaded["wfsuite.lib.setup_wizard_controls"] then
  return package.loaded["wfsuite.lib.setup_wizard_controls"]
end

local floor = math.floor

local M = {}

local function round(x) return floor(x + 0.5) end

---------------------------------------------------------------------------
-- Receiver: channel order (receiver.js)
--
-- map[function + 1] = receiver channel, functions in the order roll, pitch,
-- yaw, throttle, aux 1-4 (firmware rxConfig()->rcmap).
---------------------------------------------------------------------------

-- Letters for roll, pitch, yaw, throttle, as in "AETR".
local LETTERS = {"A", "E", "R", "T"}

local function indexOf(list, value)
  for i = 1, #list do
    if list[i] == value then return i - 1 end
  end
  return -1
end

-- The order as the receiver sends it, e.g. {0, 1, 3, 2, ...} -> "AETR1234".
function M.orderLabel(map)
  local out = {}
  for channel = 0, #map - 1 do
    local fn = indexOf(map, channel)
    if fn < 0 then
      out[#out + 1] = "-"
    elseif fn < 4 then
      out[#out + 1] = LETTERS[fn + 1]
    else
      out[#out + 1] = tostring(fn - 3)
    end
  end
  return table.concat(out)
end

-- A full map from the channels found for roll, pitch, yaw and throttle (in
-- that order); the aux functions take the remaining channels in order.
function M.mapFromDetected(found, length)
  local map = {}
  for i = 1, #found do map[i] = found[i] end
  for channel = 0, length - 1 do
    if indexOf(found, channel) < 0 then map[#map + 1] = channel end
  end
  while #map > length do map[#map] = nil end
  return map
end

-- Minimum movement (us) that counts as "this stick moved", and how much
-- further it must have moved than any other channel.
M.DETECT_MIN_US = 300
local DETECT_RATIO = 2

-- Given each channel's largest movement from its starting value so far
-- (peaks[channel + 1]), the one channel that clearly moved, or -1 while it
-- isn't clear yet. Channels in `exclude` (already found) are ignored.
-- `minUs` is lower for a radio trim, which moves its channel only a little.
function M.movedChannel(peaks, exclude, minUs)
  exclude = exclude or {}
  minUs = minUs or M.DETECT_MIN_US
  local best, second = -1, 0
  for channel = 0, #peaks - 1 do
    if indexOf(exclude, channel) < 0 then
      local peak = peaks[channel + 1]
      if best < 0 or peak > peaks[best + 1] then
        if best >= 0 then second = math.max(second, peaks[best + 1]) end
        best = channel
      else
        second = math.max(second, peak)
      end
    end
  end
  if best < 0 or peaks[best + 1] < minUs then return -1 end
  return peaks[best + 1] >= second * DETECT_RATIO and best or -1
end

---------------------------------------------------------------------------
-- Mode switches (modeRanges.js)
---------------------------------------------------------------------------

M.CHANNEL_MIN = 900
M.CHANNEL_MAX = 2100

-- Mode range for a switch the pilot just flicked from `from` to `to` (us):
-- centred on where it landed, reaching half-way back towards where it
-- started, and out to the end stop when the switch is at an end. Gives
-- 1500-2100 for a 2-position switch and the right band on a 3-position one.
function M.rangeForSwitch(from, to)
  local half = math.abs(to - from) / 2
  local start = round((to - half) / 25) * 25
  local finish = round((to + half) / 25) * 25
  if to > 1900 then finish = M.CHANNEL_MAX end
  if to < 1100 then start = M.CHANNEL_MIN end
  return {start = math.max(M.CHANNEL_MIN, start), ["end"] = math.min(M.CHANNEL_MAX, finish)}
end

---------------------------------------------------------------------------
-- Trim and gain (trimGain.js): the adjustment ranges the wizard writes
-- (firmware fc/rc_adjustments.c) and reading them back.
---------------------------------------------------------------------------

-- Enable channel meaning "always on".
local ALWAYS_ON_CH = 255

-- Adjustment functions, roll/pitch/yaw (fc/rc_adjustments.h).
M.SERVO_TRIM = {roll = 89, pitch = 90, yaw = 91}
M.MASTER_GAIN = {roll = 85, pitch = 84, yaw = 86}
M.AXES = {"roll", "pitch", "yaw"}

-- Values the full channel travel maps to. A trim channel at center adds
-- nothing. A gain knob covers 0-150% master gain: fully down turns the
-- stabilizer off and center is 75%.
M.TRIM_US = 100
M.GAIN_MIN = 0
M.GAIN_MAX = 150

-- The channel span mapped onto min-max: 25 us past 1000-2000 at each end,
-- so a radio's full travel stays inside the range and reaches both ends.
local CHANNEL_LOW = 975
local CHANNEL_HIGH = 2025

-- An always-on, mapped ("absolute") range: the position of AUX channel `aux`
-- (0 = AUX1) is the value, from `min` at CHANNEL_LOW to `max` at
-- CHANNEL_HIGH.
function M.mappedRange(adjFunction, aux, min, max)
  return {
    adjFunction = adjFunction,
    enaChannel = ALWAYS_ON_CH,
    enaRange = {start = 1500, ["end"] = 1500},
    adjChannel = aux,
    adjRange1 = {start = CHANNEL_LOW, ["end"] = CHANNEL_HIGH},
    adjRange2 = {start = 1500, ["end"] = 1500},
    adjMin = min,
    adjMax = max,
    adjStep = 0,
  }
end

function M.trimRange(axis, aux)
  return M.mappedRange(M.SERVO_TRIM[axis], aux, -M.TRIM_US, M.TRIM_US)
end

function M.gainRange(axis, aux)
  return M.mappedRange(M.MASTER_GAIN[axis], aux, M.GAIN_MIN, M.GAIN_MAX)
end

-- Index (1-based) of the slot already holding `adjFunction`, else the first
-- free one, else -1.
function M.slotFor(ranges, adjFunction)
  for i = 1, #ranges do
    if ranges[i] and ranges[i].adjFunction == adjFunction then return i end
  end
  for i = 1, #ranges do
    if not ranges[i] or ranges[i].adjFunction == 0 then return i end
  end
  return -1
end

-- The AUX channel driving `adjFunction`, or nil.
function M.channelOf(ranges, adjFunction)
  for i = 1, #ranges do
    if ranges[i] and ranges[i].adjFunction == adjFunction then return ranges[i].adjChannel end
  end
  return nil
end

-- How the gain is set up now: "single" (all three axes on one channel),
-- "separate", or "none".
function M.gainMode(ranges)
  local channels = {}
  local any = false
  for i, axis in ipairs(M.AXES) do
    channels[i] = M.channelOf(ranges, M.MASTER_GAIN[axis])
    if channels[i] ~= nil then any = true end
  end
  if not any then return "none" end
  for i = 2, #channels do
    if channels[i] ~= channels[1] then return "separate" end
  end
  return "single"
end

-- The value a mapped range gives for a channel position (us), as the
-- firmware computes it.
function M.mappedValue(range, position)
  local width = range.adjRange1["end"] - range.adjRange1.start
  local span = range.adjMax - range.adjMin
  if not (width > 0) or not (span > 0) then return range.adjMin end
  local value = range.adjMin + floor(((position - range.adjRange1.start) * span + width / 2) / width)
  return math.max(range.adjMin, math.min(range.adjMax, value))
end

-- Stepped trim from the trim buttons, all on one channel (Ethos): one free
-- mix on a spare channel, source Maximum, operation Add, and an action per
-- trim button that sets the mix weight while the button is pressed.

-- Trim per press, us. Holding a button repeats.
M.STEPPED_TRIM_STEP = 2
-- The furthest a stepped trim may go.
M.STEPPED_TRIM_US = 200

-- dir -1 steps the trim down (the range's first sub-range), +1 up.
M.TRIM_BUTTONS = {
  {button = "T4 Left", axis = "yaw", dir = -1, weight = 30},
  {button = "T4 Right", axis = "yaw", dir = 1, weight = 40},
  {button = "T2 Down", axis = "pitch", dir = 1, weight = 50},
  {button = "T2 Up", axis = "pitch", dir = -1, weight = 60},
  {button = "T1 Left", axis = "roll", dir = -1, weight = 70},
  {button = "T1 Right", axis = "roll", dir = 1, weight = 80},
}

-- Channel value for a mix weight of the Maximum source: 100% is 1500 +
-- 512 us on Ethos.
function M.buttonValue(weight)
  return 1500 + weight * 5.12
end

-- Ranges are stored in 5 us steps.
local function roundToStep(us)
  return round(us / 5) * 5
end

-- The channel window each button's value falls in (index 1-based): from
-- half-way to the button below to half-way to the one above (the same
-- half-gap past the first and last).
function M.buttonWindow(index)
  local values = {}
  for i, b in ipairs(M.TRIM_BUTTONS) do values[i] = M.buttonValue(b.weight) end
  local value = values[index]
  local below = index > 1 and values[index - 1] or (2 * value - values[index + 1])
  local above = index < #values and values[index + 1] or (2 * value - values[index - 1])
  return {start = roundToStep((below + value) / 2), ["end"] = roundToStep((value + above) / 2)}
end

-- The button the channel is showing at `position` (us), or nil.
function M.buttonAt(position)
  if not (position and position > 0) then return nil end
  for i, b in ipairs(M.TRIM_BUTTONS) do
    local window = M.buttonWindow(i)
    if position >= window.start and position < window["end"] then return b end
  end
  return nil
end

-- An always-on stepped range for `axis` on AUX channel `aux`.
function M.steppedTrimRange(axis, aux)
  local function window(dir)
    for i, b in ipairs(M.TRIM_BUTTONS) do
      if b.axis == axis and b.dir == dir then return M.buttonWindow(i) end
    end
  end
  return {
    adjFunction = M.SERVO_TRIM[axis],
    enaChannel = ALWAYS_ON_CH,
    enaRange = {start = 1500, ["end"] = 1500},
    adjChannel = aux,
    adjRange1 = window(-1),
    adjRange2 = window(1),
    adjMin = -M.STEPPED_TRIM_US,
    adjMax = M.STEPPED_TRIM_US,
    adjStep = M.STEPPED_TRIM_STEP,
  }
end

-- How the trims are set up now: "buttons" (stepped), "programmable" (mapped,
-- a channel each) or nil.
function M.trimMode(ranges)
  local found, stepped = false, false
  for _, axis in ipairs(M.AXES) do
    for i = 1, #ranges do
      local r = ranges[i]
      if r and r.adjFunction == M.SERVO_TRIM[axis] then
        found = true
        if (r.adjStep or 0) > 0 then stepped = true end
        break
      end
    end
  end
  if not found then return nil end
  return stepped and "buttons" or "programmable"
end

-- The slot turned off, as the configurator's resetToOff() does: function,
-- min, max and step reset, channels and ranges kept. Returns a new table.
function M.resetToOff(range)
  local out = {}
  for k, v in pairs(range or {}) do out[k] = v end
  out.adjFunction, out.adjMin, out.adjMax, out.adjStep = 0, 0, 100, 0
  return out
end

package.loaded["wfsuite.lib.setup_wizard_controls"] = M
return M
