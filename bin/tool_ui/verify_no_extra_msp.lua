-- Behaviour check for the MSP request pattern of the tool.
-- Ported from rotorflight-lua-ethos-suite#2421.
--
-- Run it from anywhere:
--     lua5.4 bin/tool_ui/verify_no_extra_msp.lua
--
-- Deferring the tool's UI to first open raises the obvious question: does it
-- add MSP traffic, and does anything accumulate per open/close cycle? This
-- counts every "msp.request" at bus.publish while driving the real tool.
--
-- What it drives, and why:
--   * The real src/wfsuite/app/tool.lua, including both real guards. Only the
--     Ethos widgets, the background task and the link are stubbed. The last two
--     have to report "running" and "connected", because the guards only request
--     then (their canRequest in tool.lua) -- without them the run passes on
--     0 == 0.
--   * Requests are counted at bus.publish, the source, with the real bus left
--     in place.
--   * Every request is answered the way a live FC would answer it. This is
--     load-bearing: without a reply the guard's `pending` stays true and blocks
--     every repeat no matter what its `attempted` latch does, so a harness
--     without the answering stub stays green with the latch removed. With the
--     stub, removing the latch floods the trace and this file goes red.
--
-- The path deliberately enters BOTH guarded menus:
--   root -> Hardware -> Servos                   (servo_bus_guard,    MSP 54)
--   root -> Hardware -> ESC & Motors -> ESC Tools (esc_protocol_guard, MSP 123)
-- and ticks wakeup() 100 times inside the second one, because a retry storm
-- can only arrive through wakeup(), which menu_container.lua forwards to the
-- current menu's guard.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local SUITE = (scriptDir() .. "/../../src/wfsuite"):gsub("\\", "/")
local SUITE_PREFIX = SUITE .. "/"

local checks, failures = 0, 0

-- The real print, held in a local BEFORE _G.print is silenced below.
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
local realLoadfile = loadfile
_G.loadfile = function(path, ...)
  if type(path) == "string" and path:match("%.lua$") then
    local absolute = (path:sub(1, 1) == "/" or path:match("^%a:")) and path or (SUITE_PREFIX .. path)
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

_G.lcd = {
  loadMask = function(p) return { path = p } end,
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

-- Every tile is recorded. Navigation goes through the press callback that
-- menu_container.lua builds -- the same path a button press takes. A tile is
-- identified by its icon path, which comes from the menu data in tool.lua.
local tiles = {}
_G.form = {
  addButton = function(_, slot, button)
    tiles[#tiles + 1] = {
      icon = button and button.icon and button.icon.path,
      press = button and button.press,
    }
    return fieldStub(slot)
  end,
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

_G.TEXT_LEFT, _G.LEFT, _G.CENTERED, _G.RIGHT = 1, 2, 4, 8
_G.FONT_XS, _G.FONT_S, _G.FONT_STD, _G.FONT_L, _G.FONT_XL = 16, 32, 64, 128, 256
_G.EVT_CLOSE, _G.EVT_KEY = 0x01, 0x02
_G.KEY_RTN_BREAK, _G.KEY_EXIT_BREAK, _G.KEY_ENTER_LONG = 0x06, 0x07, 0x05

-- ── MSP counting at the source ──────────────────────────────────────────────
-- The real bus is loaded (and cached by lib/require.lua) BEFORE the tool, and
-- its publish is wrapped. Every holder of that table sees the wrapper.
local requireModule = assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")

-- Reply payloads sized from the real decoders:
--   123  msp_esc_sensor_config -- U8,U8,U16,U16,U8,S8,S8,S8 (11 bytes),
--        protocol = 1
--   54   msp_serial_config     -- one 9-byte port record (U8,U32,U8,U8,U8,U8)
local REPLY = {
  [123] = function() return { 1, 0, 200, 0, 0, 0, 0, 0, 0, 0, 0 } end,
  [54] = function() return { 1, 0, 0, 0, 0, 0, 0, 0, 0 } end,
}

local trace = {}
local realPublish = bus.publish
bus.publish = function(topic, message)
  if topic == "msp.request" and type(message) == "table" then
    trace[#trace + 1] = message.command or "?"
    local reply = REPLY[message.command]
    if reply and message.processReply then
      local buf = reply()
      buf.offset = 1
      message.processReply(nil, buf)
    end
  end
  return realPublish(topic, message)
end

-- ── Run ─────────────────────────────────────────────────────────────────────
local HW_ICON = "app/gfx/hardware.png"
local SERVO_ICON = "app/gfx/servos.png"
local ESC_MOTORS_ICON = "app/gfx/esc_motors.png"
local ESC_ICON = "app/gfx/esc_tools.png"

-- The newest tile with this icon: after every menu change the tiles of the new
-- screen are at the end of the list.
local function press(iconPath)
  for i = #tiles, 1, -1 do
    if tiles[i].icon == iconPath and tiles[i].press then
      tiles[i].press()
      return true
    end
  end
  return false
end

local function traceSince(from)
  local parts = {}
  for i = from + 1, #trace do parts[#parts + 1] = tostring(trace[i]) end
  return table.concat(parts, ",")
end

out("loading app/tool.lua ...")
local tool = dofile(SUITE_PREFIX .. "app/tool.lua")
local handle = tool.init()
check("init() returns a handle", handle ~= nil)

-- Announced over the real bus, so the tool's own subscriptions run.
bus.publish("task.status", { running = true, updatedAt = os.clock() })
bus.publish("session.update", { connected = true, apiVersionSupported = true })

local CYCLES = 3
local TICKS = 100
local tracePerCycle = {}

for cycle = 1, CYCLES do
  registeredTool.create()

  -- Each section's text is captured immediately; later steps append to trace.
  local markServos = #trace
  check(string.format("cycle %d  Hardware menu is reachable", cycle), press(HW_ICON))
  check(string.format("cycle %d  Servos menu is reachable", cycle), press(SERVO_ICON))
  local afterServos = #trace - markServos
  local textServos = traceSince(markServos)

  -- Back out of Servos into Hardware before going on to ESC & Motors.
  registeredTool.event({}, EVT_KEY, KEY_RTN_BREAK)

  local markEsc = #trace
  check(string.format("cycle %d  ESC & Motors menu is reachable", cycle), press(ESC_MOTORS_ICON))
  check(string.format("cycle %d  ESC Tools menu is reachable", cycle), press(ESC_ICON))
  local afterEsc = #trace - markEsc
  local textEsc = traceSince(markEsc)

  local markTick = #trace
  for _ = 1, TICKS do
    registeredTool.wakeup({})
  end
  local inTick = #trace - markTick

  registeredTool.close()

  tracePerCycle[#tracePerCycle + 1] = string.format("Servos=%d(%s) ESC=%d(%s) Tick=%d",
    afterServos, textServos, afterEsc, textEsc, inTick)
end

-- ── Verdict ─────────────────────────────────────────────────────────────────
local ESC_READ = 123      -- msp_esc_sensor_config.READ_COMMAND
local SERIAL_READ = 54    -- msp_serial_config.READ_COMMAND

out("")
out("trace per cycle:")
for i, t in ipairs(tracePerCycle) do
  out(string.format("  %d  %s", i, t))
end
out("")

-- Each guarded menu issues exactly ONE request on entry: the guard reads once
-- and holds the answer.
for i = 1, #tracePerCycle do
  local t = tracePerCycle[i]
  check(string.format("cycle %d  exactly one Servos read (MSP %d)", i, SERIAL_READ),
    t:find("Servos=1%(" .. SERIAL_READ .. "%)") ~= nil, t)
  check(string.format("cycle %d  exactly one ESC read (MSP %d)", i, ESC_READ),
    t:find("ESC=1%(" .. ESC_READ .. "%)") ~= nil, t)
end

-- The trace must be the same in EVERY cycle. If it grows, something is
-- accumulating.
for i = 2, #tracePerCycle do
  check(string.format("cycle %d is identical to cycle 1", i),
    tracePerCycle[i] == tracePerCycle[1],
    string.format("%s  vs.  %s", tracePerCycle[i], tracePerCycle[1]))
end

check(TICKS .. " ticks inside the ESC menu produce no request",
  tracePerCycle[1]:find("Tick=0$") ~= nil, tracePerCycle[1])

check("the same total number of requests in every cycle",
  #trace == 2 * #tracePerCycle,
  "trace holds " .. #trace .. " entries for " .. #tracePerCycle .. " cycles")

out("")
out(string.rep("-", 60))
out(string.format("checks: %d   failures: %d", checks, failures))
out("MSP requests total: " .. #trace .. "   trace: " .. traceSince(0))
if failures > 0 then
  out("")
  out("FAILED")
  os.exit(1)
end
out("ALL CHECKS PASSED")
