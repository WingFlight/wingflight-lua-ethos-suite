-- Standalone tests for Issue #2302 armed-state menu gating.
--
-- Run (through bin/armed_gating/verify_armed_gating.lua): lua5.4 bin/armed_gating/verify_armed_gating.lua
--
-- Two suites:
--   1. app/armed_gating.lua's derivation rules, on synthetic trees.
--   2. The REAL menu tree from app/tool.lua, checked against an explicit
--      expected classification -- the part that actually protects a pilot,
--      and the part a synthetic tree cannot cover.
--
-- app/tool.lua is loaded with a sandboxed environment (loadfile's "t" mode
-- plus a metatable-backed stub table) so its eager lcd.loadMask calls
-- and its requireModule chain resolve without a radio. Only the module
-- table is needed; the test never calls create().

local ROOT = arg and arg[1] or "."
package.path = ROOT .. "/src/?.lua;" .. package.path

local passed, failed = 0, 0
local failures = {}

local function check(name, cond, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    failures[#failures + 1] = name .. (detail and (" -- " .. tostring(detail)) or "")
  end
end

local function eq(name, actual, expected)
  check(name, actual == expected, string.format("expected %s, got %s", tostring(expected), tostring(actual)))
end

--------------------------------------------------------------------
-- 1. Derivation rules
--------------------------------------------------------------------

local gating = assert(loadfile(ROOT .. "/src/wfsuite/app/armed_gating.lua"))()

local function tree()
  -- lockedLeaf / openLeaf / mixedMenu / lockedMenu / dynamicEntry
  local t
  t = {
    {title = "lockedLeaf", script = "x", lockedWhileArmed = true},
    {title = "openLeaf", script = "y"},
    {title = "mixedMenu", menuId = "mixed"},
    {title = "lockedMenu", menuId = "allLocked"},
    {title = "dynamicEntry", menuId = "hidden", visibleWhen = function() return false end},
  }
  t.menus = {
    mixed = {entries = {
      {title = "a", script = "a", lockedWhileArmed = true},
      {title = "b", script = "b"},
    }},
    allLocked = {entries = {
      {title = "c", script = "c", lockedWhileArmed = true},
      {title = "d", script = "d", lockedWhileArmed = true},
    }},
    hidden = {entries = {
      {title = "e", script = "e", lockedWhileArmed = true},
    }},
  }
  return t
end

-- 1a. all children locked -> container locked, entry locked
do
  local t = tree()
  gating.resolve(t, t.menus)
  eq("allLocked menu derived as locked", t.menus.allLocked.lockedWhileArmed, true)
  eq("allLocked entry derived as locked", t[4].lockedWhileArmed, true)
end

-- 1b. mixed children -> container open, entry open, locked child stays locked
do
  local t = tree()
  gating.resolve(t, t.menus)
  eq("mixed menu derived as open", t.menus.mixed.lockedWhileArmed, false)
  eq("mixed entry derived as open", t[3].lockedWhileArmed, nil)
  eq("mixed child a stays locked", t.menus.mixed.entries[1].lockedWhileArmed, true)
  eq("mixed child b stays open", t.menus.mixed.entries[2].lockedWhileArmed, nil)
end

-- 1c. hand-marked entry wins over derived value
do
  local t = tree()
  t[3].lockedWhileArmed = true -- hand-mark mixedMenu
  gating.resolve(t, t.menus)
  eq("mixed menu container still open", t.menus.mixed.lockedWhileArmed, false)
  eq("hand-marked mixed entry stays locked", t[3].lockedWhileArmed, true)
end

-- 1d. dynamic children do NOT lock their parent container
do
  local t = tree()
  gating.resolve(t, t.menus)
  eq("dynamic entry stays unlocked", t[5].lockedWhileArmed, nil)
  -- But its own children were still resolved so opening it later is consistent.
  eq("hidden submenu's own entries still resolved", t.menus.hidden.lockedWhileArmed, true)
end

-- 1e. empty menu is not locked
do
  local t = {{title = "empty", menuId = "empty"}}
  local menus = {empty = {entries = {}}}
  gating.resolve(t, menus)
  eq("empty menu is open", menus.empty.lockedWhileArmed, false)
  eq("empty entry is open", t[1].lockedWhileArmed, nil)
end

-- 1f. nil/empty inputs are safe
do
  check("nil entries: returns false without error", gating.resolve(nil, nil) == false)
  check("empty entries: returns false without error", gating.resolve({}, {}) == false)
end

-- 1g. a cycle must not hang (depth guard)
do
  local t = {{title = "a", menuId = "a"}, {title = "b", menuId = "a"}}
  local menus = {}
  menus.a = {entries = {{title = "a2", menuId = "a"}}}
  local ok = pcall(gating.resolve, t, menus)
  check("cycle: terminates without error", ok)
end

--------------------------------------------------------------------
-- 2. The real tree, from app/tool.lua
--------------------------------------------------------------------

-- Sandbox: everything tool.lua touches resolves to a harmless stub, except
-- the pieces the test actually reads back.
-- Forward declaration on purpose: stubIndex's body closes over
-- stubTable, and a name is only captured as an upvalue from its `local`
-- declaration onward. Declaring stubIndex first would compile that
-- reference as a global lookup and blow up on the first stub call.
local stubTable
local stubIndex = {
  -- requireModule("x") must return a table, else `x.something` blows up.
  __index = function(t, k)
    local fn = function() return stubTable() end
    rawset(t, k, fn)
    return fn
  end,
}
stubTable = function() return setmetatable({}, stubIndex) end

local REAL = {
  lcd = {loadMask = function() return {} end, getWindowSize = function() return 800, 480 end},
  -- tool.lua returns only {init = init}; the table carrying create/wakeup/
  -- paint/event/close is handed to system.registerSystemTool() from inside
  -- init(), so that call is where the test gets hold of it.
  system = {
    playHaptic = function() end,
    getVersion = function() return {simulation = true} end,
    registerSystemTool = function(t) return t end,
  },
  form = {clear = function() end},
  -- tool.lua's very first line indexes package.loaded, so this has to be the
  -- real table rather than a stub function.
  package = package,
  os = os, math = math, string = string, table = table, io = io,
  tonumber = tonumber, tostring = tostring, type = type, pcall = pcall,
  pairs = pairs, ipairs = ipairs, print = print, assert = assert,
  setmetatable = setmetatable, getmetatable = getmetatable,
  rawget = rawget, rawset = rawset, unpack = table.unpack,
}

local realGating = assert(loadfile(ROOT .. "/src/wfsuite/app/armed_gating.lua"))()
local moduleStubs = {}
local function stubModule(path)
  if path == "app/armed_gating.lua" then return realGating end
  if not moduleStubs[path] then
    moduleStubs[path] = setmetatable({}, stubIndex)
  end
  return moduleStubs[path]
end
package.loaded["wfsuite.lib.require"] = stubModule

local captured = {}
stubModule("app/menu_container.lua").openRoot = function(_, rootEntries, _, _, _, _, menus, _, armedState)
  captured.rootEntries = rootEntries
  captured.menus = menus
  captured.armedState = armedState
end

setmetatable(REAL, {__index = function(t, k)
  local fn = function() return stubTable() end
  rawset(t, k, fn)
  return fn
end})

local env = setmetatable({_G = REAL}, {__index = REAL})

local registeredTool = nil
REAL.system.registerSystemTool = function(t) registeredTool = t return t end

local toolChunk = assert(loadfile(ROOT .. "/src/wfsuite/app/tool.lua", "t", env))
local toolModule = toolChunk()
check("tool.lua loads in sandbox", type(toolModule) == "table")

toolModule.init()
check("init() registered the system tool", type(registeredTool) == "table")
if type(registeredTool) == "table" and type(registeredTool.create) == "function" then
  registeredTool.create()
end

local ROOT_ENTRIES = captured.rootEntries
local MENUS = captured.menus
check("create() passed ROOT_ENTRIES to openRoot", ROOT_ENTRIES ~= nil)
check("create() passed MENUS to openRoot", MENUS ~= nil)
check("create() passed an armedState accessor", type(captured.armedState) == "function")
if captured.armedState then
  eq("armedState defaults to false before any session", captured.armedState(), false)
end

if ROOT_ENTRIES and MENUS then
  -- 2a. The safety-critical set that MUST be gated. Written out
  --     explicitly: this is the assertion that a new FC-write page cannot
  --     be added without someone deciding whether it belongs here.
  --
  --     setup_menu is deliberately absent -- it contains controls_menu,
  --     which stays open because Controls > Stats is a local read, so the
  --     "all children locked" rule leaves Hardware Setup reachable and lets
  --     its own write pages badge individually. Asserted separately below.
  local MUST_LOCK = {
    servos_menu = true,
    esc_motors_menu = true, esc_forward_menu = true,
    beepers_menu = true, blackbox_menu = true, failsafe_menu = true,
    flight_tuning_menu = true, thrust_vector_menu = true,
    autolevel_menu = true,
  }
  for menuId in pairs(MUST_LOCK) do
    local sub = MENUS[menuId]
    check("locked menu present: " .. menuId, sub ~= nil)
    if sub then
      eq("submenu locked: " .. menuId, sub.lockedWhileArmed, true)
    end
  end

  -- power_menu is deliberately absent from MUST_LOCK. Power > Preferences saves the radio's own
  -- model file, not a flight-controller write, so it stays open. The "all children locked" rule
  -- therefore leaves the menu open, and its four flight-controller pages badge individually.
  local powerEntries = MENUS.power_menu and MENUS.power_menu.entries or {}
  check("power menu present", #powerEntries > 0)
  check("power menu stays open while armed", MENUS.power_menu ~= nil and MENUS.power_menu.lockedWhileArmed ~= true)
  local lockedPower = 0
  for _, entry in ipairs(powerEntries) do
    if entry.script == "app/pages/power_preferences.lua" then
      check("power preferences stays open while armed", entry.lockedWhileArmed ~= true)
    elseif entry.lockedWhileArmed == true then
      lockedPower = lockedPower + 1
    end
  end
  check("the four flight-controller power pages are locked", lockedPower == 4, "locked=" .. lockedPower)

  -- 2b. Mixed containers must stay OPEN, so read-only pages a pilot wants
  --     while armed (Stats, Diagnostics) are not locked out by a sibling.
  --     setup_menu joins them for the same reason -- see above.
  local MUST_STAY_OPEN = {
    controls_menu = true, tools_menu = true, settings_menu = true,
    setup_menu = true, diagnostics_menu = true,
  }
  for menuId in pairs(MUST_STAY_OPEN) do
    local sub = MENUS[menuId]
    check("open menu present: " .. menuId, sub ~= nil)
    if sub then
      eq("submenu open: " .. menuId, sub.lockedWhileArmed, false)
    end
  end

  -- 2b-bis. Inside a mixed container, every write page must still be gated
  --       individually -- this is the case a "lock the container" shortcut
  --       would have silently skipped.
  do
    local controls = MENUS.controls_menu
    local byName = {}
    for i = 1, #controls.entries do
      local e = controls.entries[i]
      local key = e.script and e.script:match("([^/]+)%.lua$") or e.menuId
      if key then byName[key] = e end
    end
    for _, key in ipairs({"modes", "adjustments", "failsafe_menu", "beepers_menu", "blackbox_menu"}) do
      local e = byName[key]
      check("controls_menu: " .. key .. " present", e ~= nil)
      if e then eq("controls_menu: " .. key .. " locked", e.lockedWhileArmed, true) end
    end
    local stats = byName["stats"]
    check("controls_menu: stats present", stats ~= nil)
    if stats then eq("controls_menu: stats stays open", stats.lockedWhileArmed, nil) end
  end

  -- 2b-ter. Same for setup_menu: open itself, but its direct FC-write
  --        leaves are all gated.
  do
    local setup = MENUS.setup_menu
    local unlocked = {}
    for i = 1, #setup.entries do
      local e = setup.entries[i]
      if e.lockedWhileArmed ~= true then unlocked[#unlocked + 1] = tostring(e.menuId or e.title) end
    end
    -- power_menu stays open too: it has no direct FC write, and its own pages badge individually.
    table.sort(unlocked)
    check("setup_menu: only controls_menu and power_menu are left open",
          #unlocked == 2 and unlocked[1] == "controls_menu" and unlocked[2] == "power_menu",
          table.concat(unlocked, ", "))
  end

  -- 2b-quater. The Advanced pages inside flight_tuning_menu.
  do
    local ft = MENUS.flight_tuning_menu
    local advanced = {}
    for i = 1, #ft.entries do
      local e = ft.entries[i]
      if e.group == "@i18n(app.menu_section_advanced)@" and e.script then
        advanced[#advanced + 1] = e
      end
    end
    check("flight_tuning_menu still lists the Advanced pages", #advanced >= 5,
          "#advanced=" .. #advanced)
    local unlocked = {}
    for _, e in ipairs(advanced) do
      if e.lockedWhileArmed ~= true then unlocked[#unlocked + 1] = e.script end
    end
    check("every Advanced page is locked", #unlocked == 0, table.concat(unlocked, ", "))
  end

  -- 2c. Root tiles: Flight Tuning is gated; Setup (mixed), Tools, Logs and
  --     Settings are not.
  local rootLocked, rootOpen = 0, 0
  for i = 1, #ROOT_ENTRIES do
    local e = ROOT_ENTRIES[i]
    if e.offline == true then
      eq("offline root entry stays open: " .. e.title, e.lockedWhileArmed, nil)
      rootOpen = rootOpen + 1
    elseif e.lockedWhileArmed == true then
      rootLocked = rootLocked + 1
    else
      rootOpen = rootOpen + 1
    end
  end
  check("root has both locked and open tiles", rootLocked > 0 and rootOpen > 0,
        string.format("locked=%d open=%d", rootLocked, rootOpen))

  -- 2d. No entry anywhere may claim lockedWhileArmed on a page that is
  --     offline -- an offline page cannot touch the FC, so gating it would
  --     be pure loss of function for the pilot.
  local offlineViolations = {}
  local function audit(entries, path)
    for i = 1, #entries do
      local e = entries[i]
      if e.offline == true and e.lockedWhileArmed == true then
        offlineViolations[#offlineViolations + 1] = path .. "/" .. tostring(e.title)
      end
      if e.menuId then
        local sub = MENUS[e.menuId]
        if sub and sub.entries then audit(sub.entries, path .. "/" .. tostring(e.menuId)) end
      end
    end
  end
  audit(ROOT_ENTRIES, "root")
  check("no offline entry is gated", #offlineViolations == 0, table.concat(offlineViolations, ", "))

  -- 2e. Every connected leaf page is explicitly classified one way or the
  --     other -- i.e. someone looked at it. Reported as an inventory so a
  --     newly added page shows up in the list instead of silently defaulting.
  local classified, unclassified = {}, {}
  local function inventory(entries)
    for i = 1, #entries do
      local e = entries[i]
      if not e.visibleWhen then
        local key = e.script or ("menu:" .. tostring(e.menuId))
        if e.menuId then
          local sub = MENUS[e.menuId]
          if sub and sub.entries then inventory(sub.entries) end
        end
        if e.script then
          if e.lockedWhileArmed == true then
            classified[#classified + 1] = key
          else
            unclassified[#unclassified + 1] = key
          end
        end
      end
    end
  end
  inventory(ROOT_ENTRIES)
  check("leaf inventory non-trivial", #classified + #unclassified > 30,
        string.format("locked=%d open=%d", #classified, #unclassified))
end

--------------------------------------------------------------------
-- Result
--------------------------------------------------------------------

print(string.format("passed: %d   failed: %d", passed, failed))
if failed > 0 then
  for i = 1, #failures do print("  FAIL  " .. failures[i]) end
  os.exit(1)
end
os.exit(0)
