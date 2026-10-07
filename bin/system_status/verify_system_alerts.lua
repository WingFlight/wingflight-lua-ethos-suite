-- Behaviour check for lib/system_alerts.lua with only one of the two packed
-- status words present.
--
-- Run it:
--     lua5.4 bin/system_status/verify_system_alerts.lua
--     lua5.4 bin/system_status/verify_system_alerts.lua --self-test
--
-- System Status and System Config are separate telemetry sensors, and a pilot
-- may select only one. Reboot required and Blackbox full come from System
-- Config alone, yet topBanner() and isActive() returned "nothing active"
-- whenever System Status was missing, so those alerts never showed on a model
-- sending only System Config. Every rule is now evaluated against whichever
-- words are present, with an empty table standing in for the missing one; that
-- is only safe while no rule reads true against an empty table, which this
-- check also pins.
--
-- Ported from rotorflight-lua-ethos-suite PR #2488's review.
--
-- --self-test loads a copy of system_alerts.lua with topBanner() gated on
-- System Status again and requires the config-only check to go red.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SRC = ROOT .. "/src/wfsuite"
local ALERTS_PATH = SRC .. "/lib/system_alerts.lua"

local SELF_TEST = arg and arg[1] == "--self-test"

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
  local f = assert(io.open(path, "rb"))
  local data = f:read("*a")
  f:close()
  return data
end

local function mutate(source, old, new)
  local first = source:find(old, 1, true)
  assert(first, "self-test mutation not found: " .. old)
  assert(not source:find(old, first + 1, true), "self-test mutation not unique: " .. old)
  return source:sub(1, first - 1) .. new .. source:sub(first + #old)
end

local function loadAlerts(source)
  package.loaded["wfsuite.lib.system_status"] = nil
  package.loaded["wfsuite.lib.system_alerts"] = nil
  package.loaded["wfsuite.lib.require"] = function(name)
    local path = SRC .. "/" .. name
    return assert(loadfile(path))()
  end
  return assert(load(source or readFile(ALERTS_PATH), "@" .. ALERTS_PATH))()
end

local function findRule(alerts, id)
  for _, rule in ipairs(alerts.RULES) do
    if rule.id == id then return rule end
  end
  return nil
end

-- The central measurement, reused by --self-test.
local function configOnlyBanner(source)
  local alerts = loadAlerts(source)
  local rule, count = alerts.topBanner(nil, { rebootRequired = true })
  return rule and rule.id, count
end

local function run()
  local alerts = loadAlerts()

  local id, count = configOnlyBanner()
  check("System Config alone raises the reboot-required banner",
    id == "reboot_required" and count == 1, "top=" .. tostring(id) .. " count=" .. tostring(count))

  local blackbox = findRule(alerts, "blackbox_full")
  check("System Config alone drives the Blackbox full callout",
    blackbox ~= nil and alerts.isActive(blackbox, nil, { blackboxFull = true }) == true)

  local gyro = findRule(alerts, "gyro_overflow")
  check("System Status alone still drives its own rules",
    gyro ~= nil and alerts.isActive(gyro, { gyroOverflow = true }, nil) == true)

  local rule, n = alerts.topBanner(nil, nil)
  check("no words means no banner", rule == nil and n == 0)

  -- The empty table that stands in for a missing word must never make a rule
  -- fire on its own (a `not s.flag` predicate would).
  local fired = {}
  for _, r in ipairs(alerts.RULES) do
    if r.active({}, {}) == true then fired[#fired + 1] = r.id end
  end
  check("no rule is active against two empty words", #fired == 0, table.concat(fired, ","))

  rule = alerts.topBanner({}, { rebootRequired = true })
  check("with both words present the config rule still shows",
    rule ~= nil and rule.id == "reboot_required")
end

local function selfTest()
  local statusOnly = mutate(readFile(ALERTS_PATH),
    "if status == nil and config == nil then return nil, 0 end",
    "if status == nil then return nil, 0 end")
  local id = configOnlyBanner(statusOnly)
  check("self-test: gating topBanner() on System Status hides the config-only banner",
    id == nil, "top=" .. tostring(id))
end

if SELF_TEST then
  print("system alerts self-test")
  selfTest()
else
  print("system alerts with one packed word")
  run()
end

print(string.format("%d/%d checks passed", checks - failures, checks))
if failures > 0 then os.exit(1) end
