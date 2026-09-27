-- Run from the repository root with Lua 5.3+: lua bin/tests/smartfuel_announce.lua
-- Drives the real tasks/audio_events.lua with a mocked bus, settings and
-- Ethos audio calls; never plays a sound. Pins the SmartFuel "low fuel" rules:
-- a first reading is only recorded, a reading while the FC reports no battery
-- is ignored, and a genuinely empty pack is still announced.

local ROOT = "src/wfsuite/"
local BATTERY = {OK = 0, NOT_PRESENT = 3, INIT = 4}

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("  ok    " .. label)
  else
    failures = failures + 1
    print("  FAIL  " .. label)
    if detail then print("        " .. tostring(detail)) end
  end
end

-- Real lib/ modules, loaded from the repository root instead of the radio's
-- script directory.
local cache = {}
package.loaded["wfsuite.lib.require"] = function(path)
  if cache[path] == nil then
    local result = assert(loadfile(ROOT .. path))()
    cache[path] = result == nil and true or result
  end
  return cache[path]
end

local played = {}
local haptics = 0
system = {
  playFile = function(path) played[#played + 1] = path end,
  playNumber = function(value) played[#played + 1] = "#" .. tostring(value) end,
  playHaptic = function() haptics = haptics + 1 end,
}

local function loadAudio()
  local handlers = {}
  local bus = {subscribe = function(event, fn) handlers[event] = fn end}
  local events = {smartfuel = true, smartfuelhaptic = true, smartfuelrepeats = 1, smartfuelcallout = 10}
  local settingsStore = {
    load = function() return {} end,
    audioEvents = function() return events end,
    audioTimer = function() return {} end,
  }
  local audio = assert(loadfile(ROOT .. "tasks/audio_events.lua"))(bus, settingsStore)
  return audio, handlers
end

-- Each step is {fuelPercent, batteryState}; batteryState nil means no
-- system_status reading. Returns the low-fuel and percentage callouts played.
local function run(steps)
  local audio, handlers = loadAudio()
  for i = #played, 1, -1 do played[i] = nil end
  haptics = 0
  local clock = 0
  local realClock = os.clock
  os.clock = function() return clock end
  for _, s in ipairs(steps) do
    clock = clock + 0.25
    handlers["session.update"]({
      connected = true,
      fuelPercent = s[1],
      systemStatus = s[2] and {raw = s[2], batteryState = s[2]} or nil,
    })
    audio.wakeup()
  end
  os.clock = realClock
  local low, percent = 0, {}
  for _, path in ipairs(played) do
    if path:match("lowfuel%.wav$") or path:match("lowbat%.wav$") then low = low + 1 end
    if path:sub(1, 1) == "#" then percent[#percent + 1] = path:sub(2) end
  end
  return low, percent, haptics
end

-- audio_events.wakeup() spends the first connected tick taking its baseline
-- and announces nothing, so every scenario's first step is that tick.

do
  -- The reported bug: a fresh connect whose first evaluated reading is 0.
  local low, _, h = run({{0}, {0}, {95}, {95}})
  check("a first reading of 0 is not announced", low == 0 and h == 0,
    "low=" .. low .. " haptics=" .. h)
end

do
  local low, _, h = run({{0}, {0}, {0}, {0}})
  check("a pack that stays at 0 is announced, once", low == 1 and h == 1,
    "low=" .. low .. " haptics=" .. h)
end

do
  local low, _, h = run({{0, BATTERY.INIT}, {0, BATTERY.INIT}, {0, BATTERY.NOT_PRESENT}, {0, BATTERY.NOT_PRESENT}})
  check("0 while the FC reports no battery is never announced", low == 0 and h == 0,
    "low=" .. low .. " haptics=" .. h)
end

do
  local low = run({{0, BATTERY.NOT_PRESENT}, {0, BATTERY.NOT_PRESENT}, {0, BATTERY.OK}, {0, BATTERY.OK}})
  check("an empty pack is announced once the FC detects it", low == 1, "low=" .. low)
end

do
  local low, percent = run({{0, BATTERY.INIT}, {0, BATTERY.INIT}, {85, BATTERY.OK}, {85, BATTERY.OK}})
  check("the first reading once a pack is detected is only recorded", low == 0 and #percent == 0,
    "low=" .. low .. " percent=" .. table.concat(percent, ","))
end

do
  local _, percent = run({{95}, {95}, {89}, {85}, {79}, {79}})
  check("thresholds are announced once each", #percent == 2 and percent[1] == "90" and percent[2] == "80",
    "percent=" .. table.concat(percent, ","))
end

print()
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
end
print(string.format("%d of %d checks FAILED", failures, checks))
os.exit(1)
