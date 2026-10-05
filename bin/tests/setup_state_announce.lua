-- Run from the repository root with Lua 5.3+: lua bin/tests/setup_state_announce.lua
-- Drives the real tasks/audio_events.lua with a mocked bus, settings and
-- Ethos audio calls; never plays a sound. Pins the setup-state callouts: while
-- a setup tool holds the model (system_status overrideActive) "Setup" is
-- spoken instead of the mode it forces, even when the forced mode arrives a
-- moment before the setup bit, and leaving setup only speaks a mode that
-- really changed. Pilot mode switches are still announced.

local ROOT = "src/wfsuite/"
local ANGLE, PASSTHROUGH = 2 ^ 1, 2 ^ 7

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

local cache = {}
package.loaded["wfsuite.lib.require"] = function(path)
  if cache[path] == nil then
    local result = assert(loadfile(ROOT .. path))()
    cache[path] = result == nil and true or result
  end
  return cache[path]
end

local played = {}
system = {
  playFile = function(path) played[#played + 1] = path:match("([^/]+)%.wav$") or path end,
  playNumber = function() end,
  playHaptic = function() end,
}

local function loadAudio()
  local handlers = {}
  local bus = {subscribe = function(event, fn) handlers[event] = fn end}
  local events = {flight_mode = true}
  local settingsStore = {
    load = function() return {} end,
    audioEvents = function() return events end,
    audioTimer = function() return {} end,
  }
  local audio = assert(loadfile(ROOT .. "tasks/audio_events.lua"))(bus, settingsStore)
  return audio, handlers
end

-- Each step is {flightModeFlags, setup, armed}, 0.25 s apart. The first step
-- is the baseline tick, which announces nothing. Returns the callouts played.
local function run(steps)
  local audio, handlers = loadAudio()
  for i = #played, 1, -1 do played[i] = nil end
  local clock = 0
  local realClock = os.clock
  os.clock = function() return clock end
  for _, s in ipairs(steps) do
    clock = clock + 0.25
    handlers["session.update"]({
      connected = true,
      isArmed = s[3] == true,
      flightModeFlags = s[1],
      systemStatus = {raw = s[2] and 1 or 0, overrideActive = s[2] == true},
    })
    audio.wakeup()
  end
  os.clock = realClock
  return table.concat(played, ",")
end

local function hold(step, n)
  local steps = {}
  for i = 1, n do steps[i] = step end
  return steps
end

local function concat(...)
  local out = {}
  for _, part in ipairs({...}) do
    for _, s in ipairs(part) do out[#out + 1] = s end
  end
  return out
end

do
  local said = run(concat({{0}}, hold({ANGLE, true}, 8), hold({0, false}, 8)))
  check("forced ANGLE says Setup, and nothing when it ends", said == "setup", said)
end

do
  local said = run(concat({{0}}, {{ANGLE, false}}, hold({ANGLE, true}, 8), hold({0, false}, 8)))
  check("a forced mode arriving before the setup bit is not announced", said == "setup", said)
end

do
  local said = run(concat({{0}}, hold({PASSTHROUGH, true}, 8), hold({0, false}, 8)))
  check("forced PASSTHROUGH says Setup too", said == "setup", said)
end

do
  local said = run(concat({{0}}, hold({ANGLE, false}, 8)))
  check("a pilot ANGLE switch on the bench is announced", said == "angle", said)
end

do
  local said = run(concat({{0}}, hold({PASSTHROUGH, false}, 8)))
  check("the PASSTHROUGH mode is announced as Passthrough", said == "passthrough", said)
end

do
  local said = run(concat({{0, false, true}}, {{ANGLE, false, true}}))
  check("armed, a mode switch is announced at once", said == "angle", said)
end

do
  -- Pilot switches to ANGLE while the wizard holds the model in setup.
  local said = run(concat({{0}}, hold({PASSTHROUGH, true}, 8), hold({ANGLE, false}, 8)))
  check("leaving setup into a different mode announces it", said == "setup,angle", said)
end

print()
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
end
print(string.format("%d of %d checks FAILED", failures, checks))
os.exit(1)
