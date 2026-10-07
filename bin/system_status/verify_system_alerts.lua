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
-- The callouts (tasks/audio_events.lua) must also wait for the words a rule
-- reads before recording its starting state. With System Status first, a
-- Blackbox already full when System Config arrives was recorded as "not full"
-- and then announced as new; it must stay silent (the banner shows it), and a
-- later fill must still be announced.
--
-- Ported from rotorflight-lua-ethos-suite PR #2488's review.
--
-- --self-test reverts each fix in a copy of the source (topBanner() gated on
-- System Status again; the callouts no longer waiting for their words) and
-- requires its check to go red.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SRC = ROOT .. "/src/wfsuite"
local ALERTS_PATH = SRC .. "/lib/system_alerts.lua"
local AUDIO_PATH = SRC .. "/tasks/audio_events.lua"

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

-- The real audio_events.lua and alert rules; the bus, settings and Ethos
-- audio calls are stubbed.
local function newAudioRig(source)
  package.loaded["wfsuite.lib.system_status"] = nil
  package.loaded["wfsuite.lib.system_alerts"] = nil
  package.loaded["wfsuite.lib.require"] = function(name)
    if name == "lib/engine_type.lua" then
      return { isElectric = function() return true end }
    end
    return assert(loadfile(SRC .. "/" .. name))()
  end
  local onSession
  local played = {}
  local bus = { publish = function() end,
    subscribe = function(topic, fn) if topic == "session.update" then onSession = fn end end }
  local enabled = setmetatable({}, { __index = function() return false end })
  enabled.status_blackbox = true
  enabled.status_rx_backup = true
  local settingsStore = setmetatable({
    load = function() return {} end,
    audioEvents = function() return enabled end,
  }, { __index = function() return function() return {} end end })
  system = setmetatable({
    playFile = function(path) played[#played + 1] = path end,
    getAudioVoice = function() return "en/default" end,
  }, { __index = function() return function() end end })
  local audio = assert(load(source or readFile(AUDIO_PATH), "@" .. AUDIO_PATH))(bus, settingsStore)

  local rig = {}
  function rig.step(status, config)
    onSession({ connected = true, systemStatus = status, systemConfig = config })
    audio.wakeup()
  end
  function rig.count(file)
    local n = 0
    for _, path in ipairs(played) do
      if path:sub(-#file) == file then n = n + 1 end
    end
    return n
  end
  return rig
end

-- Status first, then a config word that already reports a full Blackbox.
-- Returns how many times bbfull.wav played on its arrival.
local function blackboxAnnouncedOnArrival(source)
  local rig = newAudioRig(source)
  local status = { raw = 0 }
  for _ = 1, 3 do rig.step(status, nil) end
  rig.step(status, { raw = 1, blackboxFull = true })
  rig.step(status, { raw = 1, blackboxFull = true })
  return rig.count("bbfull.wav"), rig
end

local function calloutChecks()
  local count, rig = blackboxAnnouncedOnArrival()
  check("a Blackbox already full when System Config arrives after System Status is not announced",
    count == 0, "bbfull.wav played " .. count .. "x")
  local status = { raw = 0 }
  rig.step(status, { raw = 2, blackboxFull = false })
  rig.step(status, { raw = 1, blackboxFull = true })
  check("a Blackbox that fills later is announced", rig.count("bbfull.wav") == 1,
    "bbfull.wav played " .. rig.count("bbfull.wav") .. "x")

  local cfgFirst = newAudioRig()
  for _ = 1, 3 do cfgFirst.step(nil, { raw = 2, blackboxFull = false }) end
  cfgFirst.step(nil, { raw = 1, blackboxFull = true })
  check("with System Config alone, a Blackbox that fills is announced",
    cfgFirst.count("bbfull.wav") == 1, "bbfull.wav played " .. cfgFirst.count("bbfull.wav") .. "x")

  local alerts = loadAlerts()
  local down = findRule(alerts, "rx_backup_down")
  check("the backup-RX-down rule waits for both words",
    down ~= nil and not alerts.hasWords(down, {}, nil) and not alerts.hasWords(down, nil, {})
      and alerts.hasWords(down, {}, {}))
end

local function selfTest()
  local statusOnly = mutate(readFile(ALERTS_PATH),
    "if status == nil and config == nil then return nil, 0 end",
    "if status == nil then return nil, 0 end")
  local id = configOnlyBanner(statusOnly)
  check("self-test: gating topBanner() on System Status hides the config-only banner",
    id == nil, "top=" .. tostring(id))

  local noWait = mutate(readFile(AUDIO_PATH),
    "if (rule.enterSound or rule.exitSound) and systemAlerts.hasWords(rule, status, config) then",
    "if rule.enterSound or rule.exitSound then")
  local count = blackboxAnnouncedOnArrival(noWait)
  check("self-test: without waiting for the word, the existing full Blackbox is announced",
    count == 1, "bbfull.wav played " .. count .. "x")
end

if SELF_TEST then
  print("system alerts self-test")
  selfTest()
else
  print("system alerts with one packed word")
  run()
  print("system alert callouts")
  calloutChecks()
end

print(string.format("%d/%d checks passed", checks - failures, checks))
if failures > 0 then os.exit(1) end
