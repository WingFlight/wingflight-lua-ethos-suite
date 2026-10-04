-- Behaviour and allocation check for the dashboard wakeup path.
-- Ported from rotorflight-lua-ethos-suite#2435 (issue #2384 there).
--
-- Run it from anywhere:
--     lua5.4 bin/allocation_churn/verify_allocation_churn.lua
--     lua5.4 bin/allocation_churn/verify_allocation_churn.lua --self-test
--
-- What it drives, and why:
--   * lib/bus.lua is self-contained -- no radio, no FC, no Ethos. The check
--     covers the per-publish subscriber snapshot going away: that a handler
--     unsubscribing during a publish cannot make the loop skip the next handler,
--     that a handler removed long ago cannot come back through the pooled
--     snapshot, and that a nested publish does not disturb the outer loop.
--   * widgets/dashboard/context.lua loads under stubs for lib/build_info.lua,
--     lib/engine_type.lua, lib/ethos_version.lua and lcd.RGB. It returns two
--     `utils` tables -- context.utils is the compatibility surface for theme
--     files, and the internal one that owns transformValue()/compileTransform()
--     is handed out as context.widgets.dashboard.utils.
--
-- Two things are measured, and they are kept apart on purpose:
--
--   * Allocation. collectgarbage("count") is the live heap PLUS whatever the
--     collector has not reclaimed yet, so a single reading says nothing. The
--     pause is pushed to 1000 for the duration of the loop and a ballast array
--     keeps the live heap far above the garbage the loop produces, so no
--     collection can start mid-measurement. Without the ballast this check
--     reports 6 subscribers cheaper than 3 -- the collector ran, the numbers
--     were cut, and they looked plausible. Every allocation assertion is
--     therefore paired with the removed implementation run through the very
--     same measurement: the fix has to come out below the bound AND the old
--     code has to come out above it. A bound that both sides pass proves
--     nothing.
--
--   * Behaviour. The semantics the snapshot had are pinned explicitly in the bus
--     section, because the pooled copy has to reproduce them exactly: a handler
--     that another handler unsubscribes during the same publish still gets its
--     turn in that publish and none in the next.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local BUS_LUA = ROOT .. "/src/wfsuite/lib/bus.lua"
local CONTEXT_LUA = ROOT .. "/src/wfsuite/widgets/dashboard/context.lua"

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

-- ---------------------------------------------------------------------------
-- Allocation measurement
-- ---------------------------------------------------------------------------

local ITERATIONS = 5000

-- Retained so the collector's "double the live heap" trigger stays far above the
-- garbage a measurement loop produces. See the header: without it the numbers
-- stop being monotonic and the measurement quietly undercounts.
local ballast = {}
for i = 1, 400000 do ballast[i] = i end

-- Bytes allocated per call of `fn`. Returns nil rather than a number if the
-- live heap moved during the loop, which would mean a collection slipped in and
-- the figure cannot be trusted.
local function bytesPerCall(fn)
  collectgarbage("collect")
  collectgarbage("collect")
  local liveBefore = collectgarbage("count")
  local previousPause = collectgarbage("setpause", 1000)
  local before = collectgarbage("count")
  fn()
  local after = collectgarbage("count")
  collectgarbage("setpause", previousPause)
  collectgarbage("collect")
  local liveAfter = collectgarbage("count")
  if liveAfter > liveBefore + 4096 then return nil end
  return (after - before) * 1024 / ITERATIONS
end

-- Asserts both directions: the measured code below `bound`, the removed code
-- above it.
--
-- With --self-test only the second direction is asserted. That is the "this
-- check can go red" step: a bound that the removed code also stays under would
-- pass on a suite that allocates nothing and prove nothing at all.
local SELF_TEST = arg and arg[1] == "--self-test"

local function checkAllocation(label, fn, bound, referenceFn)
  local actual = nil
  if not SELF_TEST then actual = bytesPerCall(fn) end
  local reference = bytesPerCall(referenceFn)
  if SELF_TEST then
    check(string.format("%s: removed version %.2f B is above the bound %.0f B",
      label, reference or -1, bound),
      reference ~= nil and reference > bound,
      string.format("only %.2f B -- the bound proves nothing", reference or -1))
    return
  end
  if not actual or not reference then
    check(label .. " (measurement reliable)", false, "heap moved during the measurement")
    return
  end
  check(string.format("%s: %.2f B/call, bound %.0f B", label, actual, bound),
    actual < bound, string.format("was %.2f B", actual))
  check(string.format("%s: removed version %.2f B is above the bound", label, reference),
    reference > bound, string.format("only %.2f B -- the bound proves nothing", reference))
end

-- ---------------------------------------------------------------------------
-- Part 1 -- lib/bus.lua
-- ---------------------------------------------------------------------------

print("bus.lua")

-- bus.lua caches itself in package.loaded, so every scenario needs the cache
-- cleared first or it would get the previous scenario's instance.
local function newBus()
  package.loaded["wfsuite.bus"] = nil
  return assert(loadfile(BUS_LUA))()
end

local PAYLOAD = { connected = true }
local function ignore() end

-- The publish() that shipped before this change, kept here so the allocation
-- bound above it can be proven to have teeth.
local function oldPublishFactory(subscriberCount)
  local list = {}
  for _ = 1, subscriberCount do list[#list + 1] = ignore end
  return function(payload)
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
      local ok, err = pcall(snapshot[i], payload)
      if not ok then print("[bus] handler error on 't': " .. tostring(err)) end
    end
  end
end

do
  -- The removed snapshot scaled with the subscriber count, the replacement does
  -- not. This is the soundness guard for both measurements below: if the
  -- reference does not grow, the measurement is broken, not the code.
  local one = bytesPerCall(function() local p = oldPublishFactory(1); for _ = 1, ITERATIONS do p(PAYLOAD) end end)
  local three = bytesPerCall(function() local p = oldPublishFactory(3); for _ = 1, ITERATIONS do p(PAYLOAD) end end)
  local six = bytesPerCall(function() local p = oldPublishFactory(6); for _ = 1, ITERATIONS do p(PAYLOAD) end end)
  if one and three and six then
    check(string.format("measurement grows with the handler count (old: 1=%.0f 3=%.0f 6=%.0f B)",
      one, three, six),
      one < three and three < six,
      "the reference is not monotonic -- the collector ran mid-measurement")
  else
    check("measurement grows with the handler count", false, "heap moved")
  end

  local bus = newBus()
  for _ = 1, 6 do bus.subscribe("t", ignore) end
  checkAllocation("publish with 6 handlers",
    function() for _ = 1, ITERATIONS do bus.publish("t", PAYLOAD) end end, 8,
    function() local p = oldPublishFactory(6); for _ = 1, ITERATIONS do p(PAYLOAD) end end)

  -- "session.update" is retained, so it also writes lastPublished on the way.
  local retained = newBus()
  for _ = 1, 6 do retained.subscribe("session.update", ignore) end
  checkAllocation("publish on a retained topic (session.update)",
    function() for _ = 1, ITERATIONS do retained.publish("session.update", PAYLOAD) end end, 8,
    function() local p = oldPublishFactory(6); for _ = 1, ITERATIONS do p(PAYLOAD) end end)
end

do
  -- A failing handler must not cost the remaining handlers their turn.
  local bus = newBus()
  local seen = {}
  local realPrint = print
  local reported = {}
  print = function(...) reported[#reported + 1] = table.concat({ ... }, " ") end
  bus.subscribe("t", function() error("boom") end)
  bus.subscribe("t", function() seen[#seen + 1] = "second" end)
  bus.subscribe("t", function() seen[#seen + 1] = "third" end)
  bus.publish("t", PAYLOAD)
  print = realPrint
  check("a failing handler does not stop the remaining ones",
    #seen == 2 and seen[1] == "second" and seen[2] == "third",
    "seen: " .. #seen)
  check("the error is reported with its topic",
    #reported == 1 and tostring(reported[1]):find("boom", 1, true) ~= nil
    and tostring(reported[1]):find("'t'", 1, true) ~= nil,
    tostring(reported[1]))
end

do
  -- The reason the snapshot existed. Handler 1 removes handler 3 while the
  -- publish is running; handler 3 must still get this publish's turn.
  local bus = newBus()
  local seen = {}
  local third = function() seen[#seen + 1] = "third" end
  bus.subscribe("t", function()
    seen[#seen + 1] = "first"
    bus.unsubscribe("t", third)
  end)
  bus.subscribe("t", function() seen[#seen + 1] = "second" end)
  bus.subscribe("t", third)
  bus.publish("t", PAYLOAD)
  check("unsubscribing during a publish skips no handler",
    #seen == 3, "seen: " .. #seen .. " (expected 3)")
  check("the unsubscribed handler keeps its turn in this publish",
    seen[3] == "third", "seen: " .. tostring(seen[3]))

  -- And the documented difference: from the next publish on it is gone.
  seen = {}
  bus.publish("t", PAYLOAD)
  check("from the next publish on, the unsubscribed handler is not called",
    #seen == 2 and seen[1] == "first" and seen[2] == "second",
    "seen: " .. #seen)
end

do
  -- The pooled snapshot keeps its array between publishes, so only indices
  -- 1..count may ever be read. A handler that unsubscribed long ago sits in a
  -- slot that is still allocated; if the loop walked the whole array it would
  -- call that dead handler on every publish.
  local bus = newBus()
  local stale = 0
  local gone = function() stale = stale + 1 end
  bus.subscribe("t", ignore)
  bus.subscribe("t", gone)
  bus.publish("t", PAYLOAD)
  check("the handler ran while it was subscribed", stale == 1, "called: " .. stale)
  bus.unsubscribe("t", gone)
  stale = 0
  bus.publish("t", PAYLOAD)
  bus.publish("t", PAYLOAD)
  check("a handler unsubscribed long ago does not come back from the snapshot",
    stale == 0, "called: " .. stale)
end

do
  -- Snapshot slots must be cleared on loop exit so closures (e.g. closed pages)
  -- are not retained indefinitely in the snapshot pool.
  local bus = newBus()
  local pool = nil
  for i = 1, 20 do
    local name, val = debug.getupvalue(bus.publish, i)
    if name == nil then break end
    if name == "snapshots" then
      pool = val
      break
    end
  end
  bus.subscribe("t", function() end)
  bus.publish("t", PAYLOAD)
  local retained = false
  if pool and pool[0] then
    for i = 1, 10 do
      if pool[0][i] ~= nil then retained = true end
    end
  end
  check("snapshot pool is reachable from publish()", pool ~= nil and pool[0] ~= nil,
    "no 'snapshots' upvalue -- this check would be blind")
  check("snapshot slots are emptied after a publish (no closure retention)",
    not retained, "a slot still held a reference")
end

do
  -- Many open/close cycles -- which is what unsubscribes in this suite -- must
  -- not make a publish more expensive, and must not resurrect anything either.
  local bus = newBus()
  for _ = 1, 200 do
    local victim = function() end
    bus.subscribe("grow", victim)
    bus.subscribe("grow", function() bus.unsubscribe("grow", victim) end)
    bus.publish("grow", PAYLOAD)
  end
  local bytes = bytesPerCall(function() for _ = 1, ITERATIONS do bus.publish("grow", PAYLOAD) end end)
  check("after 200 unsubscribe cycles a publish has not become more expensive",
    bytes ~= nil and bytes < 8,
    string.format("%.2f B/call", bytes or -1))
  local called = 0
  bus.subscribe("grow", function() called = called + 1 end)
  bus.publish("grow", PAYLOAD)
  check("after the cycles exactly one new handler runs",
    called == 1, "called: " .. called)
end

do
  -- A publish nested inside another topic's handler takes the next pool level;
  -- it must not overwrite the outer publish's snapshot.
  local bus = newBus()
  local seen = {}
  local victim = function() seen[#seen + 1] = "victim" end
  bus.subscribe("other", function()
    bus.subscribe("t", victim)
    bus.subscribe("t", function() bus.unsubscribe("other", ignore) end)
    bus.publish("t", PAYLOAD)
  end)
  bus.subscribe("other", function() seen[#seen + 1] = "outer-second" end)
  bus.publish("other", PAYLOAD)
  check("a nested publish does not displace a handler",
    #seen == 2 and seen[1] == "victim" and seen[2] == "outer-second",
    "seen: " .. table.concat(seen, ","))
end

do
  -- Replay of the retained payload is what late-opening widgets depend on.
  local bus = newBus()
  bus.subscribe("task.status", ignore)
  bus.publish("task.status", { ran = true })
  local replayed
  bus.subscribe("task.status", function(payload) replayed = payload end)
  check("a retained topic is replayed to a late subscriber",
    replayed ~= nil and replayed.ran == true, tostring(replayed))
end

-- ---------------------------------------------------------------------------
-- Part 2 -- the transform dispatch
-- ---------------------------------------------------------------------------

print("")
print("widgets/dashboard/context.lua -- transform")

package.loaded["wfsuite.lib.require"] = function(name)
  if name == "lib/build_info.lua" then return { version = "harness" } end
  if name == "lib/engine_type.lua" then return {} end
  if name == "lib/ethos_version.lua" then return "1.0" end
  error("unexpected dependency: " .. tostring(name))
end
lcd = { RGB = function(r, g, b, a) return r end }

package.loaded["wfsuite.dashboard.context"] = nil
local context = assert(loadfile(CONTEXT_LUA))()
local utils = context.widgets.dashboard.utils

-- compileTransform() as it was before: the dispatch plus a closure per call.
local function oldCompileTransform(transform, decimals)
  return function(value)
    if value ~= nil and type(transform) == "function" then
      value = transform(value)
    elseif value ~= nil and transform == "floor" then
      value = math.floor(value)
    elseif value ~= nil and transform == "ceil" then
      value = math.ceil(value)
    elseif value ~= nil and transform == "round" then
      value = math.floor(value + 0.5)
    elseif value ~= nil and type(transform) == "number" then
      value = value * transform
    end
    if decimals ~= nil and value ~= nil then
      value = string.format("%." .. tostring(decimals) .. "f", value)
    end
    return value
  end
end

local function oldTransformValue(value, box)
  return oldCompileTransform(utils.getParam(box or {}, "transform"),
    utils.getParam(box or {}, "decimals"))(value)
end

do
  -- Same answers as before, over every branch the dispatch has.
  local half = function(v) return v / 2 end
  local cases = {
    { value = 21.567, transform = nil, decimals = nil, expect = 21.567 },
    { value = 21.567, transform = "floor", decimals = nil, expect = 21 },
    { value = 21.567, transform = "ceil", decimals = nil, expect = 22 },
    { value = 21.567, transform = "round", decimals = nil, expect = 22 },
    { value = 21.567, transform = -3.25, decimals = nil, expect = 21.567 * -3.25 },
    { value = 21.567, transform = half, decimals = nil, expect = 10.7835 },
    { value = 21.567, transform = "unknown", decimals = nil, expect = 21.567 },
    { value = 21.567, transform = nil, decimals = 0, expect = "22" },
    { value = 21.567, transform = nil, decimals = 1, expect = "21.6" },
    { value = 21.567, transform = nil, decimals = 3, expect = "21.567" },
    { value = 21.567, transform = "floor", decimals = 2, expect = "21.00" },
    { value = 21.567, transform = half, decimals = 1, expect = "10.8" },
    { value = 0, transform = "floor", decimals = 0, expect = "0" },
    { value = -21.567, transform = "round", decimals = nil, expect = -22 },
    { value = nil, transform = "floor", decimals = 2, expect = nil },
    { value = nil, transform = nil, decimals = nil, expect = nil },
    { value = 21.567, transform = function() return nil end, decimals = 2, expect = nil },
  }
  local mismatches = {}
  for _, case in ipairs(cases) do
    local box = { transform = case.transform, decimals = case.decimals }
    local viaValue = utils.transformValue(case.value, box)
    local viaClosure = utils.compileTransform(case.transform, case.decimals)(case.value)
    local viaOld = oldTransformValue(case.value, box)
    if viaValue ~= case.expect or viaClosure ~= case.expect or viaOld ~= case.expect then
      mismatches[#mismatches + 1] = string.format("transform=%s decimals=%s value=%s: new=%s closure=%s old=%s expected=%s",
        tostring(case.transform), tostring(case.decimals), tostring(case.value),
        tostring(viaValue), tostring(viaClosure), tostring(viaOld), tostring(case.expect))
    end
  end
  check(string.format("all %d transform branches answer as before", #cases),
    #mismatches == 0, table.concat(mismatches, "\n        "))

  -- decimals may be a function; getParam() evaluates it, and that has to keep
  -- working now that transformValue() no longer goes through a closure.
  local dynamic = { transform = nil, decimals = function(box) return box.wantDecimals end, wantDecimals = 2 }
  check("a decimals function is evaluated",
    utils.transformValue(1.239, dynamic) == "1.24",
    tostring(utils.transformValue(1.239, dynamic)))
  local compiled = utils.compileTransform(half, 2)
  check("compileTransform() keeps its closure across several values",
    compiled(10) == "5.00" and compiled(20) == "10.00")
end

do
  local box = { transform = 2 }
  checkAllocation("transformValue without decimals",
    function() for _ = 1, ITERATIONS do utils.transformValue(21.5, box) end end, 8,
    function() for _ = 1, ITERATIONS do oldTransformValue(21.5, box) end end)
end

-- ---------------------------------------------------------------------------
-- Part 3 -- getSensorStats()
-- ---------------------------------------------------------------------------

print("")
print("widgets/dashboard/context.lua -- getSensorStats")

local SUFFIX_KEYS = {
  "Rssi", "Link", "Vfr", "Voltage", "CellVoltage", "Consumption", "Current",
  "ThrottlePercent", "Rpm", "Motor2Speed", "FuelPercent", "TempMcu", "TempEsc",
  "BecVoltage", "Altitude", "Watts",
}

local function newWidget()
  local widget = {
    dashboardStats = {},
    flightmodeState = "inflight",
    connected = true,
  }
  context.setWidget(widget)
  return widget, context.tasks.telemetry.sensorStats
end

-- Every flat key gets its own value, so a lookup that picks the wrong one is
-- visible instead of coincidentally right.
local function seedDistinctStats(stats, base)
  for i, suffix in ipairs(SUFFIX_KEYS) do
    stats["min" .. suffix] = base + i
    stats["max" .. suffix] = base + 1000 + i
  end
end

-- getSensorStats() as it was before this change: an 18-entry table rebuilt per
-- call, plus a fresh result table. Kept for the allocation bound and as the
-- record of what was removed.
local function oldGetSensorStats(name, stats)
  local names = {
    voltage = "Voltage",
    cell_voltage = "CellVoltage",
    consumption = "Consumption",
    smartconsumption = "Consumption",
    current = "Current",
    throttle_percent = "ThrottlePercent",
    rpm = "Rpm",
    link = "Link",
    rssi = "Link",
    vfr = "Vfr",
    motor2speed = "Motor2Speed",
    smartfuel = "FuelPercent",
    fuel = "FuelPercent",
    temp_mcu = "TempMcu",
    temp_esc = "TempEsc",
    bec_voltage = "BecVoltage",
    altitude = "Altitude",
    watts = "Watts",
  }
  local suffix = names[name or ""]
  if not suffix then return nil end
  local minValue = stats["min" .. suffix]
  local maxValue = stats["max" .. suffix]
  if name == "temp_mcu" or name == "temp_esc" then
    local unit = 0
    if unit == 1 then
      minValue = minValue * 1.8 + 32
      maxValue = maxValue * 1.8 + 32
    end
  end
  return { min = minValue, max = maxValue, avg = nil, sum = nil, count = nil }
end

do
  -- Which flat key does the READING side use for which sensor? The two tables
  -- in the file disagreed about rssi, and rssi is exactly what a pilot reads.
  local _, stats = newWidget()
  seedDistinctStats(stats, 0)
  local rssi = context.tasks.telemetry.getSensorStats("rssi")
  local link = context.tasks.telemetry.getSensorStats("link")
  check("two sensors get two different tables",
    rssi ~= nil and rssi ~= link,
    "a shared table lets the second sensor overwrite the first")
  check("rssi does not read the link value",
    rssi ~= nil and link ~= nil and rssi.min ~= link.min,
    string.format("rssi.min=%s link.min=%s", tostring(rssi and rssi.min), tostring(link and link.min)))
  check("rssi reads the rssi value",
    rssi ~= nil and stats["minRssi"] ~= nil and rssi.min == stats["minRssi"],
    string.format("rssi.min=%s minRssi=%s", tostring(rssi and rssi.min), tostring(stats["minRssi"])))
  check("the removed table read the link value for rssi",
    oldGetSensorStats("rssi", stats).min == stats["minLink"],
    "the behaviour this change fixes")
end

do
  -- End-to-end against the recording side: whatever recordSensorStat() wrote,
  -- getSensorStats() has to find. Dropping only the record entry is what leaves
  -- a caller on the flat-key path.
  local widget, stats = newWidget()
  widget.voltage = 22.4
  widget.current = 12.5
  widget.consumption = 430
  widget.rpm = 1520
  widget.linkQuality = 88
  widget.fuelPercent = 61
  widget.throttlePercent = 42
  widget.tempMcu = 38
  widget.tempEsc = 44
  widget.becVoltage = 5.1
  widget.batteryConfig = { cellCount = 6 }

  local flatOnly = { "voltage", "cell_voltage", "current", "consumption", "smartconsumption",
    "rpm", "link", "fuel", "smartfuel", "throttle_percent", "temp_mcu", "temp_esc",
    "bec_voltage", "watts" }

  local problems = {}
  for _, name in ipairs(flatOnly) do
    -- Record once through the real path.
    local recorded = context.tasks.telemetry.getSensor(name)
    if recorded == nil then
      problems[#problems + 1] = name .. ": the sensor yields no value, the test would be blind"
    else
      -- The record exists, so drop only it: min<Suffix>/max<Suffix> survive.
      local key = ({ smartconsumption = "consumption", fuel = "smartfuel" })[name] or name
      stats[key] = nil
      local flat = context.tasks.telemetry.getSensorStats(name)
      if flat == nil or flat.min == nil or flat.max == nil then
        problems[#problems + 1] = string.format("%s: flat keys not found", name)
      elseif flat.min > flat.max then
        problems[#problems + 1] = string.format("%s: min=%s greater than max=%s", name, tostring(flat.min), tostring(flat.max))
      end
    end
  end
  check(string.format("all %d recorded sensors are found again through the flat keys", #flatOnly),
    #problems == 0, table.concat(problems, "\n        "))
end

do
  -- One table per sensor, reused. It must not carry a previous call's numbers
  -- over into the next one.
  local _, stats = newWidget()
  seedDistinctStats(stats, 0)
  stats["minVoltage"] = 11
  stats["maxVoltage"] = 22
  local first = context.tasks.telemetry.getSensorStats("voltage")
  check("voltage returns the flat keys",
    first ~= nil and first.min == 11 and first.max == 22,
    string.format("min=%s max=%s", tostring(first and first.min), tostring(first and first.max)))
  -- altitude was seeded too, so take its keys away to get a sensor with none.
  stats["minAltitude"] = nil
  stats["maxAltitude"] = nil
  local second = context.tasks.telemetry.getSensorStats("altitude")
  check("a sensor without its own keys returns nil, not a previous call's leftovers",
    second ~= nil and second.min == nil and second.max == nil,
    string.format("min=%s max=%s", tostring(second and second.min), tostring(second and second.max)))
  check("the previous result is left untouched",
    first.min == 11 and first.max == 22,
    string.format("min=%s max=%s", tostring(first.min), tostring(first.max)))
  check("an unknown sensor returns nil",
    context.tasks.telemetry.getSensorStats("doesnotexist") == nil)
  check("the flat-key path returns avg/sum/count as nil",
    first.avg == nil and first.sum == nil and first.count == nil
    and second.avg == nil and second.sum == nil and second.count == nil)
end

do
  -- The temperature path already reused a cached object; it must keep doing so.
  -- The record entry has to stay in place here -- that is what selects this path.
  local widget = newWidget()
  widget.tempMcu = 20
  context.preferences.general.temperature_unit = 0
  context.tasks.telemetry.getSensor("temp_mcu")
  local a = context.tasks.telemetry.getSensorStats("temp_mcu")
  local b = context.tasks.telemetry.getSensorStats("temp_mcu")
  check("the temperature cache returns the same object twice in a row",
    a ~= nil and a == b, "first=" .. tostring(a))
  check("the temperature value passes through unchanged in Celsius",
    a ~= nil and a.min == 20, "min=" .. tostring(a and a.min))
  context.preferences.general.temperature_unit = 1
  local fahrenheit = context.tasks.telemetry.getSensorStats("temp_mcu")
  check("a switch to Fahrenheit is followed by the temperature cache",
    fahrenheit ~= nil and fahrenheit.unit == 1 and fahrenheit.min == 20 * 1.8 + 32,
    string.format("unit=%s min=%s", tostring(fahrenheit and fahrenheit.unit),
      tostring(fahrenheit and fahrenheit.min)))
  context.preferences.general.temperature_unit = 0
end

do
  local _, stats = newWidget()
  seedDistinctStats(stats, 0)
  checkAllocation("getSensorStats on the flat keys",
    function() for _ = 1, ITERATIONS do context.tasks.telemetry.getSensorStats("voltage") end end, 8,
    function() for _ = 1, ITERATIONS do oldGetSensorStats("voltage", stats) end end)
end

-- ---------------------------------------------------------------------------

print("")
if failures == 0 then
  print(string.format("%d checks, all passed", checks))
  os.exit(0)
else
  print(string.format("%d of %d checks failed", failures, checks))
  os.exit(1)
end
