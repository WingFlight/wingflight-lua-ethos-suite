-- Behaviour check for the battery profile index bases and the profile guard.
-- Covers pull request #154 (fix(battery): stop re-basing the already-0-based
-- battery profile index), which replaced four copies of a helper that accepted
-- either base at once.
--
-- Run it from anywhere:
--     lua5.4 bin/battery_profile/verify_battery_profile_index.lua
--
-- What it drives, and why:
--   * lib/battery_profile_index.lua is pure validation code with no Ethos
--     dependency at all, so it runs on a workstation unchanged. Its
--     package.loaded guard is the only thing that touches global state, and
--     that is stubbed below.
--   * The defect it replaced was an off-by-one in BOTH directions, which is
--     why neither half can be checked on its own. normalizeBatteryProfile()
--     tested `>= 1 and <= 6` first and decremented, and only then tested
--     `>= 0 and <= 5` -- two ranges that overlap, so the first one swallowed
--     every internal index of 1..5:
--       - selecting pack 5 wrote pack 4's index to the flight controller, and
--         the session then applied pack 3's capacity and cells to SmartFuel;
--       - normalize(0) == normalize(1) == 0, so a real 1 -> 2 pack change
--         collapsed to "no change" and was dropped by the dashboard widget's
--         already-selected guard, silently.
--     Splitting the bases removes the second failure by construction: a
--     validator that accepts exactly one known base cannot get it wrong.
--   * Case 8 is the property the split exists for, and the only one that would
--     catch a converter that is individually correct but rounds to the wrong
--     base somewhere in the middle.
--   * Case 10 is the reason this file is more than a unit test of one module:
--     #154 shipped with no harness at all, so nothing checked that the four
--     call sites stopped calling the helper they used to define locally. A
--     future edit that reintroduces one of them is invisible to every other
--     case here, and it is the reintroduction -- not a new wrong value -- that
--     brought the original bug back into being reachable.
--
-- Which cases go red on the pre-fix sources (bd15c389, the commit before
-- #154): the module does not exist there, so the load check fails, the base
-- cases fail against the nil stand-in, and the call-site sweep fails on four
-- files -- which is the informative half, because it names the four call sites
-- that still had their own copy of the helper. Every case is written against a
-- false expectation: a check that cannot fail proves nothing about the
-- behaviour it passes.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = (scriptDir() .. "/../.."):gsub("\\", "/")
local SUITE = ROOT .. "/src/wfsuite"

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

local function readFile(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local content = handle:read("*a")
  handle:close()
  return content
end

-- ---------------------------------------------------------------------------
-- The real module
-- ---------------------------------------------------------------------------

local MODULE_PATH = SUITE .. "/lib/battery_profile_index.lua"
local chunk, loadErr = loadfile(MODULE_PATH)

local moduleLoaded = false
local batteryProfileIndex

if not chunk then
  print(string.format("  FAIL  lib/battery_profile_index.lua loads"))
  print("        " .. tostring(loadErr))
  checks = checks + 1
  failures = failures + 1
  print("        This harness pins pull request #154, which introduced that file.")
  print("        The remaining checks still run: the call-site sweep below is the")
  print("        half that stays meaningful while the module is missing.")
  -- A stand-in that answers nil, so every case below fails with a readable
  -- value instead of raising on the first call. Aborting here would leave the
  -- call-site sweep unreported, and that sweep is what names the four call
  -- sites the old helper still lived in.
  batteryProfileIndex = {
    index0 = function() return nil end,
    fromTelemetrySensor = function() return nil end,
    label = function() return nil end,
  }
else
  local ok, result = pcall(chunk)
  if ok then
    moduleLoaded = true
    batteryProfileIndex = result
  else
    print("  FAIL  loading lib/battery_profile_index.lua does not raise")
    print("        " .. tostring(result))
    checks = checks + 1
    failures = failures + 1
    batteryProfileIndex = {
      index0 = function() return nil end,
      fromTelemetrySensor = function() return nil end,
      label = function() return nil end,
    }
  end
end

-- The memoisation check needs the module to have registered itself; skipped
-- rather than failed, because case 9 is about bookkeeping the module does on
-- the way in, not about the bases.
local function checkLoaded()
  if not moduleLoaded then
    print("  skip  module not loaded, base cases report against a nil stand-in")
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Cases 1-3: index0() -- the internal, 0-based base
-- ---------------------------------------------------------------------------

print("index0 accepts the internal 0-based base and nothing else:")

for index = 0, 5 do
  check(string.format("index0(%d) is %d", index, index),
    batteryProfileIndex.index0(index) == index,
    "got " .. tostring(batteryProfileIndex.index0(index)))
end

check("index0(6) is nil, not 5",
  batteryProfileIndex.index0(6) == nil,
  "got " .. tostring(batteryProfileIndex.index0(6)))

check("index0(-1) is nil, not 0",
  batteryProfileIndex.index0(-1) == nil,
  "got " .. tostring(batteryProfileIndex.index0(-1)))

check("index0(nil) is nil",
  batteryProfileIndex.index0(nil) == nil)

check("index0('x') is nil, not 0",
  batteryProfileIndex.index0("x") == nil,
  "got " .. tostring(batteryProfileIndex.index0("x")))

-- The case the old helper got wrong: 5 is a valid internal index, and the old
-- helper decremented it because it tested the 1-based range first.
check("index0(5) keeps pack 5 (the old helper returned 4)",
  batteryProfileIndex.index0(5) == 5,
  "got " .. tostring(batteryProfileIndex.index0(5)))

check("index0 is not a re-baser: 1 stays 1",
  batteryProfileIndex.index0(1) == 1,
  "got " .. tostring(batteryProfileIndex.index0(1)))

-- Non-injectivity was the second half of the old defect: with the two ranges
-- overlapping, 0 and 1 both landed on 0, so a 1 -> 2 pack change read as "no
-- change" and the widget's already-selected guard swallowed it.
local distinct = {}
local collisions = {}
local rejected = {}
for index = 0, 5 do
  local got = batteryProfileIndex.index0(index)
  if got == nil then
    -- An index in 0..5 must not come back nil. Recorded separately so the
    -- collision count below cannot mistake "no answer" for "same answer".
    rejected[#rejected + 1] = index
  elseif distinct[got] ~= nil then
    collisions[#collisions + 1] = string.format("%d and %d both map to %s",
      distinct[got], index, tostring(got))
  else
    distinct[got] = index
  end
end
check("index0 answers for every index in 0..5",
  #rejected == 0,
  "returned nil for " .. table.concat(rejected, ", "))

check("index0 is injective over 0..5",
  #collisions == 0,
  table.concat(collisions, "; "))

-- ---------------------------------------------------------------------------
-- Cases 4-6: fromTelemetrySensor() -- the one 1-based reading
-- ---------------------------------------------------------------------------

print("")
print("fromTelemetrySensor converts the one 1-based reading:")

for reading = 1, 6 do
  check(string.format("fromTelemetrySensor(%d) is %d", reading, reading - 1),
    batteryProfileIndex.fromTelemetrySensor(reading) == reading - 1,
    "got " .. tostring(batteryProfileIndex.fromTelemetrySensor(reading)))
end

-- 0 is not a valid 1-based reading. Passing it through would reintroduce the
-- exact off-by-one this split exists to prevent, and the caller (session.lua's
-- updateProfiles) keeps its last known good value on nil.
check("fromTelemetrySensor(0) is nil -- 0 is not a 1-based reading",
  batteryProfileIndex.fromTelemetrySensor(0) == nil,
  "got " .. tostring(batteryProfileIndex.fromTelemetrySensor(0)))

check("fromTelemetrySensor(7) is nil, not 6",
  batteryProfileIndex.fromTelemetrySensor(7) == nil,
  "got " .. tostring(batteryProfileIndex.fromTelemetrySensor(7)))

check("fromTelemetrySensor(nil) is nil",
  batteryProfileIndex.fromTelemetrySensor(nil) == nil)

-- ---------------------------------------------------------------------------
-- Case 7: label() -- what the pilot is shown
-- ---------------------------------------------------------------------------

print("")
print("label shows the 1-based pack number:")

for index = 0, 5 do
  check(string.format("label(%d) is %d", index, index + 1),
    batteryProfileIndex.label(index) == index + 1,
    "got " .. tostring(batteryProfileIndex.label(index)))
end

check("label(6) is nil, not 6",
  batteryProfileIndex.label(6) == nil,
  "got " .. tostring(batteryProfileIndex.label(6)))

check("label(-1) is nil, not 0",
  batteryProfileIndex.label(-1) == nil,
  "got " .. tostring(batteryProfileIndex.label(-1)))

-- ---------------------------------------------------------------------------
-- Case 8: the round trip the split exists for
-- ---------------------------------------------------------------------------

-- A converter can be individually correct and still round to the wrong base if
-- the two bases drift apart. Feeding the internal base through the sensor
-- conversion and the label has to come back unchanged, for every pack.
print("")
print("internal base -> label -> sensor reading -> internal base is lossless:")

local roundTripFailures = {}
for index = 0, 5 do
  local label = batteryProfileIndex.label(index)
  if label == nil then
    roundTripFailures[#roundTripFailures + 1] =
      string.format("label(%d) is nil", index)
  else
    local back = batteryProfileIndex.fromTelemetrySensor(label)
    if back ~= index then
      roundTripFailures[#roundTripFailures + 1] =
        string.format("%d -> label %s -> %s", index, tostring(label), tostring(back))
    end
  end
end
check("every pack survives label and back",
  #roundTripFailures == 0,
  table.concat(roundTripFailures, "; "))

-- The firmware reports the telemetry reading as index + 1, so the pilot's pack
-- number and the reading agree on every pack. Off by one here is the difference
-- between announcing pack 5 while pack 4 is fitted, and being right.
local labelFailures = {}
for reading = 1, 6 do
  local index = batteryProfileIndex.fromTelemetrySensor(reading)
  local label = batteryProfileIndex.label(index)
  if label ~= reading then
    labelFailures[#labelFailures + 1] =
      string.format("reading %d shows as %s", reading, tostring(label))
  end
end
check("the pack shown always equals the reading the FC reports",
  #labelFailures == 0,
  table.concat(labelFailures, "; "))

-- ---------------------------------------------------------------------------
-- Case 9: the memoisation guard
-- ---------------------------------------------------------------------------

-- The module returns the same table on a second load, which is what keeps a
-- second requireModule() call site from building a second validator.
print("")
print("module bookkeeping:")

if checkLoaded() then
  check("loading twice returns the same table",
    package.loaded["wfsuite.lib.battery_profile_index"] == batteryProfileIndex,
    "package.loaded holds " .. tostring(package.loaded["wfsuite.lib.battery_profile_index"]))

  check("the module publishes itself under its own key",
    batteryProfileIndex ~= nil
      and type(batteryProfileIndex.index0) == "function"
      and type(batteryProfileIndex.fromTelemetrySensor) == "function"
      and type(batteryProfileIndex.label) == "function")
end

-- ---------------------------------------------------------------------------
-- Case 10: no call site kept the old helper
-- ---------------------------------------------------------------------------

-- #154 replaced four local copies of normalizeBatteryProfile(). A local helper
-- that survives next to the shared module is a duplicate that accepts either
-- base again, and it is the shape the bug had. Nothing else in this file would
-- notice it, because the module itself would still be correct.
print("")
print("no call site kept a base-accepting helper of its own:")

local CALL_SITES = {
  "src/wfsuite/tasks/session.lua",
  "src/wfsuite/tasks/audio_events.lua",
  "src/wfsuite/widgets/dashboard.lua",
  "src/wfsuite/app/pages/power_battery.lua",
}

local survivors = {}
local unreadable = {}
for _, relative in ipairs(CALL_SITES) do
  local content = readFile(ROOT .. "/" .. relative)
  if not content then
    unreadable[#unreadable + 1] = relative
  elseif content:find("normalizeBatteryProfile", 1, true) then
    survivors[#survivors + 1] = relative
  end
end

check("all four call sites are readable",
  #unreadable == 0,
  table.concat(unreadable, ", "))

check("normalizeBatteryProfile is gone from all four",
  #survivors == 0,
  "still defined or called in: " .. table.concat(survivors, ", "))

-- power_battery.lua had the same helper under a different name. The shared
-- module kept that local alias on purpose, so the alias is fine; a second
-- `function` definition behind it is not.
local powerBattery = readFile(ROOT .. "/src/wfsuite/app/pages/power_battery.lua")
if powerBattery then
  check("power_battery.lua takes normalizeProfile from the module, not its own body",
    not powerBattery:find("local function normalizeProfile", 1, true),
    "still defines its own normalizeProfile()")
else
  check("power_battery.lua is readable", false, "cannot read it")
end

-- ---------------------------------------------------------------------------

print("")
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
else
  print(string.format("%d of %d checks FAILED", failures, checks))
  os.exit(1)
end
