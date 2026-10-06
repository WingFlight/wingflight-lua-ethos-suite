-- Behaviour check for the phased startup handshake (issue #2362), the
-- Wingflight parallel of rotorflight-lua-ethos-suite's
-- bin/handshake_gate/verify_handshake_gate.lua.
--
-- Run it:
--     lua5.4 bin/handshake_gate/verify_handshake_gate.lua
--     lua5.4 bin/handshake_gate/verify_handshake_gate.lua --self-test
--
-- The claim: tasks/session.lua's runHandshake() must put nothing but
-- MSP_API_VERSION on the wire until that read has answered *and* the answer
-- passed lib/msp_api_version.lua's compatibility check. Everything the
-- handshake used to queue in one burst ahead of that verdict -- FC_VERSION,
-- UID, NAME, the RTC sync, battery/smartfuel/rx-map -- is a post-connect read
-- an incompatible FC can never answer, and because the MSP queue is
-- single-in-flight, one such request at the head of the queue starves every
-- page read behind it for its whole retry budget.
--
-- How it is measured, and why that is not a fixture:
--   * tasks/session.lua is loaded the way tasks/background.lua loads it: as a
--     chunk that receives bus/settingsStore/debugLog as its arguments, with the
--     Ethos globals the module reads at load time stubbed (the same shape
--     bin/msp_gc/verify_msp_disconnect.lua uses). What is *not* stubbed is the
--     thing under test: the real lib/msp_handshake.lua, lib/msp_battery.lua,
--     lib/msp_api_version.lua, ... are loaded, so the command ids the spy sees
--     are the ones production would send, and the verdict is produced by the
--     real isSupported() -- major 22 / minor >= 13.
--   * The MSP queue is a spy that records every message session.lua hands it.
--     A reply is delivered by calling that message's own processReply, which is
--     exactly what the real queue does once a matching reply arrives.
--   * os.clock() is replaced by a controllable clock, so the 2s
--     handshake-retry window can be crossed without waiting.
--
-- --self-test loads a copy of session.lua with the gate's condition neutered
-- (`~= true` -> `false`) and requires the central check to go red on it. A
-- check that cannot fail proves nothing about the behaviour it passes.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SUITE = ROOT .. "/src/wfsuite"
local TASKS = SUITE .. "/tasks"
local SESSION_PATH = TASKS .. "/session.lua"

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

-- ---------------------------------------------------------------------------
-- Command ids, read from the real builder modules rather than typed here -- a
-- check anchored on a number copied from the same source it is checking would
-- pass on a changed source.
-- ---------------------------------------------------------------------------

package.loaded["wfsuite.lib.require"] = function(name)
  if name == "lib/mspcodec.lua" then
    return assert(loadfile(SUITE .. "/lib/mspcodec.lua"))()
  end
  error("unexpected dependency while reading command constants: " .. tostring(name))
end

local handshake = assert(loadfile(SUITE .. "/lib/msp_handshake.lua"))()
local battery = assert(loadfile(SUITE .. "/lib/msp_battery.lua"))()
local rxmap = assert(loadfile(SUITE .. "/lib/msp_rx_map.lua"))()
local apiVersion = assert(loadfile(SUITE .. "/lib/msp_api_version.lua"))()

local API_VERSION = apiVersion.READ_COMMAND
local API_MAJOR = apiVersion.EXPECTED_API_MAJOR
local API_MIN_MINOR = apiVersion.MIN_API_MINOR

-- Every read runHandshake() queues after the API-version gate. API_VERSION (1)
-- is deliberately absent -- it is the one read allowed before the verdict -- and
-- so is TELEMETRY_CONFIG, which the periodic block queues, not the handshake.
local IDENTITY = {
  [handshake.FC_VERSION_READ_COMMAND] = "FC_VERSION",
  [handshake.UID_READ_COMMAND] = "UID",
  [handshake.NAME_READ_COMMAND] = "NAME",
  [handshake.RTC_WRITE_COMMAND] = "RTC",
  [battery.BATTERY_CONFIG_READ_COMMAND] = "BATTERY_CONFIG",
  [battery.SMARTFUEL_CONFIG_READ_COMMAND] = "SMARTFUEL_CONFIG",
  [rxmap.READ_COMMAND] = "RX_MAP",
}

-- ---------------------------------------------------------------------------
-- Controllable clock. session.lua reads os.clock() as a global on every call,
-- so replacing the global is enough.
-- ---------------------------------------------------------------------------
local clockNow = 100.0
local realClock = os.clock
os.clock = function() return clockNow end

-- ---------------------------------------------------------------------------
-- A rig: the real session.lua, the stubbed world around it, and a spy queue.
-- ---------------------------------------------------------------------------

local REAL = {
  ["lib/mspcodec.lua"] = true,
  ["lib/msp_api_version.lua"] = true,
  ["lib/msp_handshake.lua"] = true,
  ["lib/msp_battery.lua"] = true,
  ["lib/msp_rx_map.lua"] = true,
  ["lib/msp_telemetry_config.lua"] = true,
  ["lib/msp_dataflash_summary.lua"] = true,
  ["lib/msp_flight_stats.lua"] = true,
  ["lib/msp_eeprom.lua"] = true,
  ["lib/system_status.lua"] = true,
  ["tasks/flight_timer.lua"] = true,
}

local function newRig(opts)
  opts = opts or {}
  local active = opts.telemetryActive

  local published = {}
  local spyQueue = {
    added = {},
    add = function(self, message)
      self.added[#self.added + 1] = message
      return true
    end,
    clear = function(self) end,
  }

  local noop = function() end
  local realModules = {}
  local function realModule(name)
    if realModules[name] == nil then
      realModules[name] = assert(loadfile(SUITE .. "/" .. name))()
    end
    return realModules[name]
  end

  -- The small modules session.lua only verifies through, which are not the
  -- behaviour under test. Kept as a strict map (not a catch-all): if a future
  -- change adds a require, this harness must fail by name, not by accident.
  local modules = {
    ["lib/battery_profile_index.lua"] = { fromTelemetrySensor = function() return nil end,
      index0 = function() return nil end, label = function() return nil end },
    ["lib/smartfuel_reserve.lua"] = {},
    ["lib/smartfuel_calc.lua"] = { new = function() return { reset = noop, update = function() return nil end } end },
    ["lib/diy_sensor.lua"] = { new = function() return { reset = noop, set = noop } end },
    ["lib/model_preferences.lua"] = { load = function() return {} end, stats = function() return {} end,
      timerTarget = function() return 300 end, smartfuelModelType = function() return 0 end,
      save = noop, setStats = noop },
    ["lib/frsky_sensors.lua"] = { new = function() return { provision = function() return true end } end },
    ["tasks/elrs_sensors.lua"] = { wakeup = function() return false end, reset = noop },
  }

  package.loaded["wfsuite.lib.require"] = function(path)
    if REAL[path] then return realModule(path) end
    if modules[path] then return modules[path] end
    error("unexpected dependency: " .. tostring(path))
  end

  CATEGORY_SYSTEM_EVENT, TELEMETRY_ACTIVE = 2, 0
  SMARTFUEL_APP_ID, UNIT_PERCENT = 0x5FE1, "%"
  system = {
    getVersion = function() return { simulation = false } end,
    getSource = function() return { state = function() return active end } end,
    -- Reached only on a compatible verdict, via playConnectBeep().
    playFile = noop,
    playHaptic = noop,
  }
  model = { name = function() return "Test" end, set = noop }

  local bus = {
    subscribe = noop,
    publish = function(topic, value) published[#published + 1] = { topic, value } end,
  }
  local settingsStore = {
    load = function() return {} end,
    simulatedApiVersionMode = function() return false end,
    syncNameEnabled = function() return false end,
  }
  local debugLog = { print = noop, msp = noop, enabled = function() return false end }

  local source = opts.source or readFile(SESSION_PATH)
  local session = assert(load(source, "@" .. SESSION_PATH))(bus, settingsStore, debugLog)
  -- setConnected()'s disconnect branch calls reset() on the sensor instance it
  -- holds; a stub without one would abort that branch before it finished.
  session.setTelemetrySensors({ getValue = function() return nil end, reset = noop })

  return {
    session = session,
    queue = spyQueue,
    published = published,
    -- One background-task tick. `value` is the telemetry-link state the tick
    -- sees; omitting it keeps the previous one.
    tick = function(value)
      if value ~= nil then active = value end
      clockNow = clockNow + 0.05
      session.wakeup(spyQueue, "sport")
    end,
    advance = function(seconds) clockNow = clockNow + seconds end,
  }
end

local function commandsOf(rig)
  local list = {}
  for i, message in ipairs(rig.queue.added) do
    list[i] = tostring(message.command)
  end
  return table.concat(list, ",")
end

local function findCommand(rig, command)
  for _, message in ipairs(rig.queue.added) do
    if message.command == command then return message end
  end
  return nil
end

local function countIdentity(rig)
  local names = {}
  for _, message in ipairs(rig.queue.added) do
    local name = IDENTITY[message.command]
    if name then names[#names + 1] = name end
  end
  return #names, table.concat(names, ",")
end

local function lastSnapshot(rig)
  for i = #rig.published, 1, -1 do
    local entry = rig.published[i]
    if entry[1] == "session.update" then return entry[2] end
  end
  return nil
end

local function deliver(rig, command, bytes)
  local message = findCommand(rig, command)
  if not message then return false end
  message.processReply(message, bytes)
  return true
end

-- The central measurement, reused by --self-test: how many of the
-- identity/config reads are queued before the API-version verdict.
local function identityReadsBeforeVerdict(source)
  local rig = newRig({ telemetryActive = true, source = source })
  rig.tick(true)
  return countIdentity(rig)
end

local SUPPORTED = { 0, API_MAJOR, API_MIN_MINOR }        -- this suite's family, at the floor
local WRONG_FAMILY = { 0, 12, 9 }                        -- Rotorflight's epoch
local TOO_OLD = { 0, API_MAJOR, API_MIN_MINOR - 4 }      -- same family, below the floor

-- ---------------------------------------------------------------------------
-- 1. Before the verdict, the only handshake read on the queue is API_VERSION.
-- ---------------------------------------------------------------------------
do
  local rig = newRig({ telemetryActive = true })
  rig.tick(true)
  local identityCount, names = countIdentity(rig)
  local apiReads = 0
  for _, message in ipairs(rig.queue.added) do
    if message.command == API_VERSION then apiReads = apiReads + 1 end
  end
  check("the handshake queues the API_VERSION read while connecting",
    apiReads == 1, "API_VERSION reads=" .. apiReads .. " (commands: " .. commandsOf(rig) .. ")")
  check("no identity/config read is queued before the API_VERSION verdict",
    identityCount == 0,
    identityCount .. " queued: " .. names .. " (commands: " .. commandsOf(rig) .. ")")
end

-- ---------------------------------------------------------------------------
-- 2. A compatible verdict releases the identity reads, in the same turn -- the
--    success callback resumes the handshake.
-- ---------------------------------------------------------------------------
do
  local rig = newRig({ telemetryActive = true })
  rig.tick(true)
  check("sanity: the API_VERSION read is on the queue to answer",
    findCommand(rig, API_VERSION) ~= nil)
  deliver(rig, API_VERSION, SUPPORTED)
  rig.tick(true) -- flush the publish() the verdict marked dirty

  local seen = {}
  for _, message in ipairs(rig.queue.added) do
    if IDENTITY[message.command] then seen[message.command] = true end
  end
  check("a compatible verdict releases the identity and config reads",
    seen[handshake.FC_VERSION_READ_COMMAND] and seen[handshake.UID_READ_COMMAND]
      and seen[handshake.NAME_READ_COMMAND] and seen[handshake.RTC_WRITE_COMMAND]
      and seen[battery.BATTERY_CONFIG_READ_COMMAND] and seen[rxmap.READ_COMMAND]
      and seen[battery.SMARTFUEL_CONFIG_READ_COMMAND],
    "commands after the verdict: " .. commandsOf(rig))
  local snapshot = lastSnapshot(rig)
  check("the compatible verdict is published as supported",
    snapshot ~= nil and snapshot.apiVersionSupported == true,
    "snapshot.apiVersionSupported=" .. tostring(snapshot and snapshot.apiVersionSupported))
end

-- ---------------------------------------------------------------------------
-- 3. An incompatible verdict blocks every post-connect read, and keeps blocking
--    it -- the retry tick must not re-enter the burst.
-- ---------------------------------------------------------------------------
do
  local rig = newRig({ telemetryActive = true })
  rig.tick(true)
  deliver(rig, API_VERSION, WRONG_FAMILY)
  rig.tick(true)

  local identityCount, names = countIdentity(rig)
  check("an incompatible verdict queues no identity/config read",
    identityCount == 0, identityCount .. " queued: " .. names)
  local snapshot = lastSnapshot(rig)
  check("the incompatible verdict is published as unsupported",
    snapshot ~= nil and snapshot.apiVersionSupported == false,
    "snapshot.apiVersionSupported=" .. tostring(snapshot and snapshot.apiVersionSupported))

  local before = #rig.queue.added
  for _ = 1, 10 do
    rig.advance(1.0) -- well past the 2s handshake-retry window
    rig.tick(true)
  end
  local late = 0
  for i = before + 1, #rig.queue.added do
    if IDENTITY[rig.queue.added[i].command] then late = late + 1 end
  end
  check("later ticks after an incompatible verdict queue no identity/config read",
    late == 0, late .. " queued after the verdict (commands: " .. commandsOf(rig) .. ")")
end

-- ---------------------------------------------------------------------------
-- 4. Same-family / too-old (minor below the floor) is also a hard stop.
-- ---------------------------------------------------------------------------
do
  local rig = newRig({ telemetryActive = true })
  rig.tick(true)
  deliver(rig, API_VERSION, TOO_OLD)
  rig.tick(true)
  local identityCount = countIdentity(rig)
  check("a too-old same-family verdict queues no identity/config read either",
    identityCount == 0, identityCount .. " queued (commands: " .. commandsOf(rig) .. ")")
  local snapshot = lastSnapshot(rig)
  check("the too-old verdict is published as unsupported",
    snapshot ~= nil and snapshot.apiVersionSupported == false,
    "snapshot.apiVersionSupported=" .. tostring(snapshot and snapshot.apiVersionSupported))
end

-- ---------------------------------------------------------------------------
-- 5. A failed API_VERSION read is retried on its own.
-- ---------------------------------------------------------------------------
do
  local rig = newRig({ telemetryActive = true })
  rig.tick(true)
  local apiMessage = findCommand(rig, API_VERSION)
  apiMessage.errorHandler("max_retries")

  local function apiReads()
    local n = 0
    for _, message in ipairs(rig.queue.added) do
      if message.command == API_VERSION then n = n + 1 end
    end
    return n
  end
  local before = apiReads()
  rig.advance(3.0) -- past the 2s handshake-retry window
  rig.tick(true)

  check("a failed API_VERSION read is retried",
    apiReads() == before + 1, "API_VERSION reads before=" .. before .. " after=" .. apiReads())
  local identityCount = countIdentity(rig)
  check("the retry queues no identity/config read",
    identityCount == 0, identityCount .. " queued (commands: " .. commandsOf(rig) .. ")")
end

-- ---------------------------------------------------------------------------
-- self-test: the central check must be able to go red.
-- ---------------------------------------------------------------------------

local selfTest = false
for _, a in ipairs(arg or {}) do
  if a == "--self-test" then selfTest = true end
end

if selfTest then
  print()
  print("--self-test: the gate check must go red without the gate")

  local source = readFile(SESSION_PATH)
  local mutated, replacements = source:gsub("if session%.apiVersionSupported ~= true then",
    "if false then", 1)
  check("self-test: the version gate was found in session.lua exactly once",
    replacements == 1, "replacements=" .. replacements ..
    " (the harness no longer tracks the code it checks)")

  if replacements == 1 then
    local n = identityReadsBeforeVerdict(mutated)
    check("self-test: without the gate the identity reads are queued before the verdict",
      n > 0, "identity reads before the verdict on the sabotaged copy=" .. n ..
      " (0 means the central check would have passed on the pre-fix code)")
  end
end

-- ---------------------------------------------------------------------------

os.clock = realClock
print()
if failures == 0 then
  print(string.format("all %d checks passed", checks))
  os.exit(0)
end
print(string.format("%d of %d checks FAILED", failures, checks))
os.exit(1)
