-- Behaviour check for the flight record across a link loss.
--
-- Run from anywhere:
--     lua bin/flight_record/verify_flight_record.lua
--
-- What it drives, and why:
--   * tasks/flight_timer.lua is a pure function of (connected, armed, now), so
--     the state machine is stepped without a radio, an FC or Ethos.
--   * tasks/logging.lua decides between holding one CSV open and starting a
--     second one. It is loaded the way tasks/background.lua loads it, with
--     stub bus/settings/debug-log instances, and its LOGS:/ writes go to
--     in-memory handles, so the test counts the files a flight produces
--     without touching the disk.
--
-- Ported from rotorflight-lua-ethos-suite PR #2405. Against the code before
-- that change, the brief-drop cases below fail (one flight reported as its
-- last leg, and written as two CSVs); the pack-swap and disarmed-during-outage
-- cases pass on both, on purpose: they pin what the fix must not break.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local TASKS = scriptDir() .. "/../../src/wfsuite/tasks"

local failures = 0
local checks = 0

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print(string.format("  ok    %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL  %s", label))
    if detail then print("        " .. tostring(detail)) end
  end
end

local function loadTimer()
  return assert(loadfile(TASKS .. "/flight_timer.lua"))()
end

-- ---------------------------------------------------------------------------
-- tasks/flight_timer.lua
-- ---------------------------------------------------------------------------

-- Collects the flightCounted and finishedSegment events a scenario produces,
-- which is what session.lua turns into stats.flightcount and totalflighttime.
local function runTimer(steps)
  local timer = loadTimer()
  local counts, segments = 0, {}
  for _, s in ipairs(steps) do
    local _, _, event = timer.update(s[1], s[2], s[3])
    if event then
      if event.flightCounted then counts = counts + 1 end
      if event.finishedSegment then segments[#segments + 1] = event.finishedSegment end
    end
  end
  return {
    flightCounts = counts,
    finishedSegments = #segments,
    firstSegment = segments[1],
    lastSegment = segments[#segments],
  }
end

local GRACE = 30

-- 1. An ordinary flight, no link loss. The behaviour that has to stay put.
do
  local r = runTimer({
    {true, true, 0}, {true, true, 10}, {true, true, 30}, {true, false, 40},
  })
  check("plain flight: counted once at 25s", r.flightCounts == 1,
    "flightCounts=" .. r.flightCounts)
  check("plain flight: one finished segment of 40s", r.finishedSegments == 1 and r.lastSegment == 40,
    "segments=" .. r.finishedSegments .. " last=" .. tostring(r.lastSegment))
end

-- 2. A link drop mid-flight: the case the fix is for. 47s, not the 50s of wall
--    clock: the 3s without a link are not flight time.
do
  local r = runTimer({
    {true, true, 0}, {true, true, 30},
    {false, nil, 32},
    {true, true, 35}, {true, true, 45},
    {true, false, 50},
  })
  check("brief drop: the flight is still counted once", r.flightCounts == 1,
    "flightCounts=" .. r.flightCounts .. " (2 would double-count the same flight)")
  check("brief drop: one finished segment", r.finishedSegments == 1,
    "segments=" .. r.finishedSegments)
  check("brief drop: 32s plus 15s is one flight of 47s", r.lastSegment == 47,
    "lastSegment=" .. tostring(r.lastSegment))
end

-- 3. A drop before the count threshold: 22s of flight, under 25s, but still
--    one flight and one segment.
do
  local r = runTimer({
    {true, true, 0}, {true, true, 10},
    {false, nil, 12}, {true, true, 15}, {true, true, 20}, {true, false, 25},
  })
  check("brief drop early: 22s of flight stays under the 25s threshold", r.flightCounts == 0,
    "flightCounts=" .. r.flightCounts)
  check("brief drop early: one segment of 22s", r.finishedSegments == 1 and r.lastSegment == 22,
    "segments=" .. r.finishedSegments .. " last=" .. tostring(r.lastSegment))
end

-- 3b. The threshold is measured from the flight's start, not the resume point.
do
  local r = runTimer({
    {true, true, 0}, {true, true, 30},
    {false, nil, 32}, {true, true, 35}, {true, true, 40},
    {true, false, 45},
  })
  check("drop after the threshold: counted once", r.flightCounts == 1,
    "flightCounts=" .. r.flightCounts)
  check("drop after the threshold: one flight of 42s", r.finishedSegments == 1 and r.lastSegment == 42,
    "segments=" .. r.finishedSegments .. " last=" .. tostring(r.lastSegment))
end

-- 4. A gap longer than the grace window: two flights. The link stays down
--    across two ticks on purpose -- a later tick must not wipe the held flight.
do
  local r = runTimer({
    {true, true, 0}, {true, true, 30},
    {false, nil, 32},
    {false, nil, 32 + GRACE + 1},
    {true, true, 32 + GRACE + 2},
    {true, true, 62 + GRACE + 2},
    {true, false, 72 + GRACE + 2},
  })
  check("long gap: two finished segments", r.finishedSegments == 2,
    "segments=" .. r.finishedSegments)
  check("long gap: the first flight keeps its 32s", r.firstSegment == 32,
    "firstSegment=" .. tostring(r.firstSegment))
  check("long gap: the second flight is its own 40s", r.lastSegment == 40,
    "lastSegment=" .. tostring(r.lastSegment))
  check("long gap: the second flight is counted too", r.flightCounts == 2,
    "flightCounts=" .. r.flightCounts)
end

-- 5. A pack swap: armed, flight, land, disarm, unplug, new pack, arm. Always
--    two records.
do
  local r = runTimer({
    {true, true, 0}, {true, true, 30}, {true, false, 35},
    {false, nil, 40}, {true, false, 45},
    {true, true, 50}, {true, true, 75}, {true, false, 80},
  })
  check("pack swap: two finished segments", r.finishedSegments == 2,
    "segments=" .. r.finishedSegments .. " (1 would merge two flights)")
  check("pack swap: counted twice", r.flightCounts == 2,
    "flightCounts=" .. r.flightCounts)
  check("pack swap: the second flight reports its own 30s", r.lastSegment == 30,
    "lastSegment=" .. tostring(r.lastSegment))
end

-- 6. Disarmed while the link was down: the flight is over and stays over.
do
  local r = runTimer({
    {true, true, 0}, {true, true, 30},
    {false, nil, 32},
    {true, false, 34},
    {true, true, 40}, {true, true, 65}, {true, false, 70},
  })
  check("disarmed while down: the held flight is closed, not resumed", r.finishedSegments == 2,
    "segments=" .. r.finishedSegments)
  check("disarmed while down: the next flight counts on its own", r.flightCounts == 2,
    "flightCounts=" .. r.flightCounts)
end

-- 7. resumable()/inProgress() are what session.lua and the log writer read,
--    and they have to expire. A missing function is a failed check, not a
--    crashed run.
do
  local timer = loadTimer()
  timer.update(true, true, 0)
  timer.update(true, true, 30)
  timer.update(false, nil, 32)
  if type(timer.resumable) ~= "function" or type(timer.inProgress) ~= "function" then
    check("resumable()/inProgress() exist", false,
      "flight_timer cannot tell a held flight from a finished one")
  else
    check("resumable right after an armed link loss", timer.resumable(33) == true)
    check("not resumable once the grace window has passed", timer.resumable(32 + GRACE + 1) == false)
    check("inProgress right after an armed link loss", timer.inProgress(33) == true)
    check("not inProgress once the grace window has passed", timer.inProgress(32 + GRACE + 1) == false)
    local fresh = loadTimer()
    check("nothing resumable when nothing was held", fresh.resumable(0) == false)
    check("nothing in progress when nothing was held", fresh.inProgress(0) == false)
  end
end

-- 8. reset() still means reset.
do
  local timer = loadTimer()
  timer.update(true, true, 0)
  timer.update(true, true, 30)
  timer.reset()
  local s = timer.current()
  check("reset clears the session, the live time and the count",
    s.timerSession == 0 and s.timerLive == 0 and s.timerFlightCounted == false,
    "session=" .. s.timerSession .. " live=" .. s.timerLive .. " counted=" .. tostring(s.timerFlightCounted))
end

-- ---------------------------------------------------------------------------
-- tasks/logging.lua
-- ---------------------------------------------------------------------------

-- An in-memory stand-in for a file handle, enough for logging.lua.
local function fakeHandle()
  return {
    write = function(self) return self end,
    flush = function() end,
    close = function() end,
  }
end

-- Loads logging.lua with its three chunk args stubbed, and io.open answering
-- LOGS:/ paths in memory. Returns the module, the bus handlers it subscribed,
-- and the list of CSV files it opened for writing (a new record each).
local function loadLogging()
  local handlers = {}
  local bus = {subscribe = function(event, fn) handlers[event] = fn end}
  local settingsStore = {
    load = function() return {} end,
    loggingEnabled = function() return true end,
    loggingSampleInterval = function() return 0 end,
  }
  local debugLog = {print = function() end}

  local started = {}
  local realOpen = io.open
  io.open = function(path, mode)
    path = tostring(path)
    if path:sub(1, 5) ~= "LOGS:" then return realOpen(path, mode) end
    if mode == "w" and path:match("%.csv$") then started[#started + 1] = path end
    return fakeHandle()
  end

  local ok, mod = pcall(function()
    return assert(loadfile(TASKS .. "/logging.lua"))(bus, settingsStore, debugLog)
  end)
  if not ok then
    io.open = realOpen
    error(mod)
  end
  local function restore() io.open = realOpen end
  return mod, handlers, started, restore
end

-- Each step delivers the session the way session.lua would, then lets the
-- logger run its tick.
local function runLogScenario(steps)
  local logging, handlers, started, restore = loadLogging()
  logging.setSettings({})
  logging.setTelemetrySensors({getValue = function() return 0 end})
  for _, s in ipairs(steps) do
    handlers["session.update"]({
      connected = s[1],
      isArmed = s[2],
      flightResumable = s[3],
      mcuId = "FC123",
      craftName = "Test",
    })
    logging.wakeup("crsf")
  end
  restore()
  return #started
end

do
  local files = runLogScenario({
    {true, true, false},   -- armed, link up: one file opens
    {false, nil, true},    -- link lost mid-flight, flight held open
    {true, true, false},   -- reconnects armed: same file, resumed
    {true, true, false},
  })
  check("log: a brief armed link loss keeps one file", files == 1,
    "files opened=" .. files .. " (2 means one flight was split)")
end

do
  local files = runLogScenario({
    {true, true, false},   -- flight one
    {true, false, false},  -- landed and disarmed
    {false, nil, false},   -- unplugged
    {true, false, false},  -- new pack, still disarmed
    {true, true, false},   -- armed again: flight two
  })
  check("log: a pack swap produces a second file", files == 2,
    "files opened=" .. files .. " (1 would merge two flights)")
end

do
  local files = runLogScenario({
    {true, true, false},   -- flight one
    {false, nil, true},    -- link lost mid-flight
    {true, false, true},   -- reconnects, but the pilot had disarmed
    {true, true, false},   -- next flight
  })
  check("log: a flight that ended during the outage is not merged", files == 2,
    "files opened=" .. files)
end

do
  local files = runLogScenario({
    {true, true, false},   -- flight one
    {false, nil, true},    -- link lost, flight held open
    {false, nil, false},   -- the grace window expires
    {true, true, false},   -- reconnects armed: a new record
  })
  check("log: an expired grace window ends the record", files == 2,
    "files opened=" .. files .. " (1 would inherit an abandoned flight)")
end

-- ---------------------------------------------------------------------------

print()
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
end
print(string.format("%d of %d checks FAILED", failures, checks))
os.exit(1)
