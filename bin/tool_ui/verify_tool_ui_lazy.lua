-- Behaviour check for the load timing of the tool's UI subtree.
-- Ported from rotorflight-lua-ethos-suite#2421.
--
-- Run it from anywhere:
--     lua5.4 bin/tool_ui/verify_tool_ui_lazy.lua
--
-- What it drives, and why:
--   * The real src/wfsuite/app/tool.lua under an Ethos stub environment. The
--     point is not to test the tool -- it is to establish WHICH modules appear
--     in package.loaded, and WHEN.
--   * Module paths resolve against src/wfsuite, because that is what the suite
--     itself does: on the radio the working directory is the script's own
--     folder, so tool.lua's loadfile("lib/require.lua") is relative to it.
--
-- Four cases, each against a false expectation:
--   1. After init() (create() has not run) NONE of the tool's UI subtree
--      modules are in package.loaded.
--   2. After create() they are ALL there.
--   3. close() loads nothing that was not there before, and still logs
--      app.close (start)/(end).
--   4. A second create() loads nothing again (requireModule caches).
--
-- Plus one case the port adds: close() without any create() -- Ethos owns
-- that call, and it must not pull the deferred modules in on its own.
--
-- Against a tool.lua with the requireModule() calls back at module scope,
-- case 1 goes RED.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local SUITE = (scriptDir() .. "/../../src/wfsuite"):gsub("\\", "/")
local SUITE_PREFIX = SUITE .. "/"

local checks, failures = 0, 0

-- The real print, held in a local BEFORE _G.print is silenced below -- the
-- suite prints throughout, and a harness that calls the global print after
-- that silences itself as well.
local out = print

local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    out(string.format("  ok    %s", label))
  else
    failures = failures + 1
    out(string.format("  FAIL  %s", label))
    if detail then out("        " .. tostring(detail)) end
  end
end

-- ── Ethos stubs ─────────────────────────────────────────────────────────────
-- Every relative .lua path is resolved against src/wfsuite and recorded, so
-- the checks can count loadfile() calls per module as well as package.loaded.
local loadOrder = {}
local realLoadfile = loadfile
_G.loadfile = function(path, ...)
  if type(path) == "string" and path:match("%.lua$") then
    local absolute = (path:sub(1, 1) == "/" or path:match("^%a:")) and path or (SUITE_PREFIX .. path)
    loadOrder[#loadOrder + 1] = absolute
    return realLoadfile(absolute, ...)
  end
  return realLoadfile(path, ...)
end

local registeredTool = nil
_G.system = {
  getVersion = function() return { simulation = false, radio = { name = "stub" } } end,
  registerSystemTool = function(tool) registeredTool = tool return tool end,
  getMemoryUsage = function() return {} end,
  formatBytes = function(n) return tostring(n) end,
}

-- loadMask is the expensive call on the radio (the bitmap arena). Here it
-- only counts, so no result hinges on it.
local maskCalls = 0
_G.lcd = {
  loadMask = function(p) maskCalls = maskCalls + 1; return { path = p } end,
  loadImage = function(p) return { path = p } end,
  getWindowSize = function() return 480, 320 end,
  getTextSize = function(t) return #tostring(t) * 7, 12 end,
  drawRectangle = function() end,
  drawText = function() end,
  drawBitmap = function() end,
  setColor = function() end,
  font = function() end,
  color = function() end,
  RGB = function() return 0 end,
}
_G.model = { get = function() return 0 end, name = function() return "stub" end }
_G.print = function() end

local function fieldStub(slot)
  return {
    slot = slot,
    focus = function() end,
    enable = function() end,
    value = function() end,
    setText = function() end,
    setEnabled = function() end,
    setValue = function() end,
    getValue = function() return nil end,
    show = function() end,
    hide = function() end,
    isShown = function() return true end,
    isEnabled = function() return true end,
  }
end

_G.form = {
  addButton = function(_, slot) return fieldStub(slot) end,
  addLine = function() return 1 end,
  addStaticText = function(_, rect) return fieldStub(rect) end,
  addTextButton = function(_, slot) return fieldStub(slot) end,
  clear = function() end,
  getFieldSlots = function(_, hints)
    local n = type(hints) == "table" and #hints or 6
    local w = 480 / math.max(n, 1)
    local slots = {}
    for i = 1, n do slots[i] = { x = (i - 1) * w, y = 0, w = w, h = 30 } end
    return slots
  end,
  height = function() return 320 end,
  openProgressDialog = function() return { close = function() end } end,
  openDialog = function() return { close = function() end } end,
}

-- Ethos platform constants, used as values (header.lua adds font and
-- alignment together, so they have to be numbers).
_G.TEXT_LEFT, _G.LEFT, _G.CENTERED, _G.RIGHT = 1, 2, 4, 8
_G.FONT_XS, _G.FONT_S, _G.FONT_STD, _G.FONT_L, _G.FONT_XL = 16, 32, 64, 128, 256
_G.EVT_CLOSE, _G.EVT_KEY = 0x01, 0x02
_G.KEY_RTN_BREAK, _G.KEY_EXIT_BREAK, _G.KEY_ENTER_LONG = 0x06, 0x07, 0x05

-- ── Under test ──────────────────────────────────────────────────────────────
local UNDER_TEST = {
  "app/menu_container.lua",
  "app/navigation.lua",
  "app/header.lua",
  "app/tile_grid.lua",
  "app/close_key.lua",
  "app/esc_protocol_guard.lua",
  "app/servo_bus_guard.lua",
  "lib/memstats.lua",
  "lib/msp_esc_sensor_config.lua",
  "lib/msp_serial_config.lua",
}

local function countUnder(name)
  local target = SUITE_PREFIX .. name
  local n = 0
  for _, path in ipairs(loadOrder) do
    if path == target then n = n + 1 end
  end
  return n
end

-- lib/require.lua caches under "wfsuite." .. path without .lua
local function moduleLoaded(name)
  local key = "wfsuite." .. name:gsub("%.lua$", ""):gsub("/", ".")
  return package.loaded[key] ~= nil
end

local function snapshot()
  local counts = {}
  for _, name in ipairs(UNDER_TEST) do counts[name] = countUnder(name) end
  return counts
end

out("loading app/tool.lua ...")
local tool = dofile(SUITE_PREFIX .. "app/tool.lua")
local handle = tool.init()
check("init() returns a handle", handle ~= nil)

out("")
out("case 1: after init(), before create() -- nothing may be loaded")
for _, name in ipairs(UNDER_TEST) do
  check(string.format("%-34s not loaded", name),
    not moduleLoaded(name) and countUnder(name) == 0,
    string.format("loaded=%s, loadfile calls=%d",
      tostring(moduleLoaded(name)), countUnder(name)))
end

out("")
out("case 1b: close() before any create() loads nothing")
registeredTool.close()
for _, name in ipairs(UNDER_TEST) do
  check(string.format("%-34s still not loaded", name),
    not moduleLoaded(name) and countUnder(name) == 0,
    string.format("loaded=%s, loadfile calls=%d",
      tostring(moduleLoaded(name)), countUnder(name)))
end

out("")
out("case 2: after create() -- the tool's UI subtree must be complete")
registeredTool.create()
for _, name in ipairs(UNDER_TEST) do
  check(string.format("%-34s loaded", name), moduleLoaded(name),
    "still not loaded after create()")
end

out("")
out("case 3: close() loads nothing further and logs memstats")
local before = snapshot()

local memstatsPrints = {}
local memstatsMod = package.loaded["wfsuite.lib.memstats"]
local origMemstatsPrint = memstatsMod and memstatsMod.print
if memstatsMod then
  memstatsMod.print = function(tag)
    memstatsPrints[#memstatsPrints + 1] = tag
    return origMemstatsPrint(tag)
  end
end

registeredTool.close()

if memstatsMod then memstatsMod.print = origMemstatsPrint end

for _, name in ipairs(UNDER_TEST) do
  check(string.format("%-34s unchanged", name), countUnder(name) == before[name],
    string.format("newly loaded: %d", countUnder(name) - before[name]))
end
check("close() logged app.close (start)", memstatsPrints[1] == "app.close (start)",
  string.format("got %s", tostring(memstatsPrints[1])))
check("close() logged app.close (end)", memstatsPrints[2] == "app.close (end)",
  string.format("got %s", tostring(memstatsPrints[2])))

out("")
out("case 4: a second create() loads nothing again")
before = snapshot()
registeredTool.create()
for _, name in ipairs(UNDER_TEST) do
  check(string.format("%-34s no second load", name), countUnder(name) == before[name],
    string.format("loaded again: %d", countUnder(name) - before[name]))
end
registeredTool.close()

out("")
out(string.rep("-", 60))
out(string.format("checks: %d   failures: %d", checks, failures))
out("lcd.loadMask calls: " .. maskCalls)
if failures > 0 then
  out("")
  out("FAILED")
  os.exit(1)
end
out("ALL CHECKS PASSED")
