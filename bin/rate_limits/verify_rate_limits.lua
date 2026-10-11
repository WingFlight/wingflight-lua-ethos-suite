-- Behaviour check for the rate limits of the rates page (issue #2350, ported from
-- rotorflight-lua-ethos-suite).
--
-- Run it:
--     lua5.4 bin/rate_limits/verify_rate_limits.lua
--     lua5.4 bin/rate_limits/verify_rate_limits.lua --self-test
--
-- What it drives: the real lib/rate_curve_scale.lua. The expected limits are the
-- firmware's constants in src/main/fc/rc_rates.h:25-27 (CONTROL_RATE_CONFIG_RC_RATES_MAX,
-- _SUPER_RATE_MAX, _RC_EXPO_MAX), one set for every rate table, as
-- validateAndFixRatesSettings() clamps them (src/main/config/config.c:197-206).
--
-- --self-test puts back the flat 255 ceiling (the behaviour before this fix) and
-- requires the value checks to go red.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SELF_TEST = arg and arg[1] == "--self-test"

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print(string.format("  ok    %s", label))
  else
    failures = failures + 1
    print(string.format("  FAIL  %s", label))
    if detail then print("        " .. tostring(detail)) end
  end
  return ok
end

-- Firmware limits per role (raw bytes), from src/main/fc/rc_rates.h:25-27.
local FIRMWARE = {rcRate = 200, srate = 100, expo = 100}
local ROLES = {"rcRate", "srate", "expo"}
local AXIS_CLASSES = {"main", "col"}

local function loadModule(text)
  local chunk, err
  if text then
    chunk, err = load(text, "=rate_curve_scale", "t")
  else
    chunk, err = loadfile(ROOT .. "/src/wfsuite/lib/rate_curve_scale.lua")
  end
  assert(chunk, err)
  package.loaded["wfsuite.lib.rate_curve_scale"] = nil
  return chunk()
end

-- Module under test: the real file, or a copy with the flat ceiling for --self-test.
local function moduleUnderTest()
  if not SELF_TEST then return loadModule(nil) end
  local f = assert(io.open(ROOT .. "/src/wfsuite/lib/rate_curve_scale.lua", "r"))
  local text = f:read("a")
  f:close()
  local mutated, n = text:gsub("local RAW_LIMITS = {\n  rcRate = 200,\n  srate = 100,\n  expo = 100,\n}",
    "local RAW_LIMITS = {rcRate = 255, srate = 255, expo = 255}")
  assert(n == 1, "self-test could not find the RAW_LIMITS table")
  return loadModule(mutated)
end

local m = moduleUnderTest()

if SELF_TEST then
  -- The flat ceiling must fail the firmware-limit check on the rcRate maximum.
  local want = m.toDisplayInt(FIRMWARE.rcRate, "rcRate", "main")
  local _, shown = m.displayBounds("rcRate", "main")
  local caught = shown ~= want
  print(string.format("\nself-test: flat 255 ceiling %s the rcRate maximum check",
    caught and "is caught by" or "is NOT caught by"))
  print(string.format("%d checks, %d failed", checks, failures))
  os.exit(caught and 0 or 1)
end

print("Rate limits: lib/rate_curve_scale.lua")

do
  local allMatch, first = true, nil
  for _, role in ipairs(ROLES) do
    local got = m.rawMaxFor(role)
    if got ~= FIRMWARE[role] then
      allMatch = false
      first = first or string.format("%s: want %d got %s", role, FIRMWARE[role], tostring(got))
    end
  end
  check("the raw limits match the firmware constants for every role", allMatch, first)
end

do
  local allMatch, first = true, nil
  for _, role in ipairs(ROLES) do
    for _, axis in ipairs(AXIS_CLASSES) do
      local _, shown = m.displayBounds(role, axis)
      local want = m.toDisplayInt(FIRMWARE[role], role, axis)
      if shown ~= want then
        allMatch = false
        first = first or string.format("%s %s: want %s got %s", role, axis, tostring(want), tostring(shown))
      end
    end
  end
  check("the display maximum is the converted firmware limit for every role and axis class", allMatch, first)
end

do
  -- The page cannot store a value above the limit: typing a huge number stops at it.
  local allClamp, first = true, nil
  for _, role in ipairs(ROLES) do
    for _, axis in ipairs(AXIS_CLASSES) do
      local raw = m.fromDisplayInt(99999, role, axis)
      if raw ~= FIRMWARE[role] then
        allClamp = false
        first = first or string.format("%s %s: stored %s, limit %d", role, axis, tostring(raw), FIRMWARE[role])
      end
    end
  end
  check("a value above the limit is stored as the limit, not 255", allClamp, first)
end

do
  -- The firmware limit survives display and back, for every role and axis class.
  local allRound, first = true, nil
  for _, role in ipairs(ROLES) do
    for _, axis in ipairs(AXIS_CLASSES) do
      local back = m.fromDisplayInt(m.toDisplayInt(FIRMWARE[role], role, axis), role, axis)
      if back ~= FIRMWARE[role] then
        allRound = false
        first = first or string.format("%s %s: %d -> %s", role, axis, FIRMWARE[role], tostring(back))
      end
    end
  end
  check("the firmware limit round-trips through the display for every role and axis class", allRound, first)
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
