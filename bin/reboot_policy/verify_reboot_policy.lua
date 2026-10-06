-- Behaviour check for the save-and-reboot pipeline (ported from
-- rotorflight-lua-ethos-suite #2361).
--
-- Run it:
--     lua5.4 bin/reboot_policy/verify_reboot_policy.lua
--
-- What it drives, and why:
--   * The real src/wfsuite/app/page_runtime.lua, to drive a save that DOES
--     restart the board and pin what the page does while it waits. The MSP
--     answers are delivered inline (a queue that drains at once), which is
--     enough here because the subject is the UI wait, not read ordering.
--
-- Why there is no governor-page part here (the sibling suite's harness has one):
--   Wingflight's Setup -> Governor page is its own fixed-wing Throttle Range
--   Governor (lib/msp_governor_config.lua), not Rotorflight's heli governor, so
--   #2361's "no governor page may request a reboot" check has no counterpart to
--   pin on this side -- the four pages that check names do not exist here, and
--   the port must not invent them. What IS shared, and what this pins, is the
--   pipeline: a save that restarts the flight controller must hold its page
--   until the link is back, instead of closing the dialog and reporting the
--   save done while the board is still booting.
--
-- Which checks are gates, and how --self-test proves it:
--   "the restart dialog is held after the save" and "the page reloads after
--   the link returns" both go red on the pre-fix page_runtime, where the save
--   path closed the dialog and reported the save done immediately. The
--   self-test loads a copy of page_runtime.lua with `self_.pendingReboot =
--   true` spliced to `false` -- the one line that arms the wait -- and requires
--   both checks to fail.
--   The remaining checks are pinned as controls: a page whose rebootAfterSave
--   is false must NOT hold a dialog, an armed save must NOT publish a reboot,
--   and a board that never returns must still end the wait. Those are what stop
--   the wait from becoming unconditional.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SUITE = (ROOT .. "/src/wfsuite"):gsub("\\", "/")

local checks, failures = 0, 0
local out = print

-- The i18n tag, not its resolved text: tags are substituted by the deploy step,
-- so the Lua-under-test carries the raw tag and the harness compares like for
-- like (see bin/i18n/check-tags.py and .vscode/scripts/resolve_i18n_tags.py).
local RESTART_TITLE = "@i18n(app.msg_restarting)@"

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

-- ── Ethos environment ──────────────────────────────────────────────────────

local SUITE_PREFIX = SUITE .. "/"
package.path = SUITE_PREFIX .. "?.lua;" .. package.path
_G.PREFIX = SUITE_PREFIX

local realLoadfile = loadfile

-- requireModule() calls loadfile() with a path that carries no directory part;
-- on the radio the working directory is src/wfsuite.
_G.loadfile = function(path, ...)
  if type(path) == "string" and path:match("%.lua$") then
    local absolute = path:sub(1, 1) == "/" and path or (SUITE_PREFIX .. path)
    return realLoadfile(absolute, ...)
  end
  return realLoadfile(path, ...)
end

_G.package = package
_G.package.loaded = package.loaded
_G.os = os
_G.math = math
_G.string = string
_G.table = table
_G.print = function() end
_G.model = { get = function() return 0 end, name = function() return "stub" end }
_G.system = { getVersion = function() return { simulation = false, radio = { name = "stub" } } end }
_G.radio = { getActiveProfileId = function() return 1 end, getProfileId = function() return 1 end }

-- Controllable clock: page_runtime's reboot wait measures with os.clock(), and
-- the timeout case below must reach 20 s without the harness sleeping for it.
local fakeClock = 0
os.clock = function() return fakeClock end

local widgetStub, fieldStub

_G.form = {
  addButton = function() return widgetStub("button") end,
  addTextButton = function() return widgetStub("textbutton") end,
  addStaticText = function() return widgetStub("text") end,
  addNumberField = function() return fieldStub() end,
  addLine = function() return 1 end,
  clear = function() end,
  height = function() return 320 end,
  openDialog = function() return widgetStub("dialog") end,
  openProgressDialog = function() return widgetStub("progressdialog") end,
}

widgetStub = function(name)
  local w
  w = {
    name = name,
    focus = function() end,
    enable = function() end,
    value = function() end,
    setValue = function() end,
    setText = function() end,
    getValue = function() return 0 end,
    show = function() end,
    hide = function() end,
  }
  return w
end

fieldStub = function()
  local f = {}
  f.suffix = function() return f end
  f.default = function() return f end
  f.onFocus = function() return f end
  f.enable = function() return f end
  f.value = function() return 0 end
  return f
end

_G.TIME_LEFT = 1
_G.TEXT_LEFT = 2
_G.LEFT = 3
_G.CENTERED = 4
_G.RIGHT = 5
_G.TOP_LEFT = 6
_G.FONT_XS = 10
_G.FONT_S = 20
_G.FONT_M = 30
_G.FONT_L = 40
_G.FONT_XL = 50
_G.EVT_CLOSE = 0x01
_G.EVT_KEY = 0x02
_G.EVT_EXIT_BREAK = 0x03
_G.EVT_KEY_DOWN_BREAK = 0x04
_G.KEY_ENTER_LONG = 0x05
_G.KEY_RTN_BREAK = 0x06
_G.KEY_EXIT_BREAK = 0x07
_G.KEY_ENTER_BREAK = 0x08

_G.lcd = {
  getWindowSize = function() return 800, 480 end,
  invalidate = function() end,
  drawLine = function() end,
  color = function() end,
  GREY = function(v) return v end,
  RGB = function(r, g, b) return r, g, b end,
}

-- ── shared seams ───────────────────────────────────────────────────────────

local sessionHandlers = {}
local dialogs = {}
local reboots = 0
local reads = 0

local function resetTrace()
  fakeClock = 0
  reboots = 0
  reads = 0
  dialogs = {}
end

local function currentDialog()
  for i = #dialogs, 1, -1 do
    if not dialogs[i].closed then return dialogs[i] end
  end
  return nil
end

local function publishSession(connected, apiVersion, isArmed)
  for _, handler in ipairs(sessionHandlers) do
    handler({
      pidProfile = 1,
      isArmed = isArmed,
      mcuId = "0123456789",
      connected = connected,
      handshake = { apiVersion = apiVersion },
    })
  end
end

local function mspModuleStub()
  return {
    buildReadMessage = function(onData, onError)
      return { isRead = true, onData = onData, onError = onError }
    end,
    buildWriteMessage = function(_, onData, onError)
      return { onData = onData, onError = onError }
    end,
  }
end

-- ── module stubs ───────────────────────────────────────────────────────────

package.loaded["wfsuite.lib.bus"] = {
  subscribe = function(topic, handler)
    if topic == "session.update" then sessionHandlers[#sessionHandlers + 1] = handler end
  end,
  unsubscribe = function() end,
  publish = function(topic, message)
    if topic ~= "msp.request" or type(message) ~= "table" then return end
    if message.isReboot then
      -- A board that is rebooting does not acknowledge the command that reboots
      -- it (lib/msp_reboot.lua's maxRetries = 0, and its own comment says the
      -- lost ack is the expected outcome). Do not answer it here either.
      reboots = reboots + 1
      return
    end
    if message.isRead then reads = reads + 1 end
    -- The read's success branch assigns the payload to runtime.data, so it has
    -- to be a table (a codec's decoded struct); the write/eeprom callbacks
    -- ignore it.
    if message.onData then message.onData({}) end
  end,
}
package.loaded["wfsuite.lib.memstats"] = { print = function() end }
package.loaded["wfsuite.lib.debug_log"] = {
  print = function() end,
  format = function() end,
  msp = function() end,
  enabled = function() return false end,
  mspEnabled = function() return false end,
}
package.loaded["wfsuite.lib.settings_store"] = {
  saveConfirmEnabled = function() return false end,
  reloadConfirmEnabled = function() return false end,
  load = function() return {} end,
  save = function() end,
  DEFAULTS = {},
}
package.loaded["wfsuite.lib.msp_eeprom"] = {
  buildWriteMessage = function(onWritten, onError)
    return { onData = onWritten, onError = onError }
  end,
}
package.loaded["wfsuite.lib.msp_reboot"] = {
  buildWriteMessage = function(onWritten, onError)
    return { isReboot = true, onData = onWritten, onError = onError }
  end,
}
package.loaded["wfsuite.app.header"] = {
  build = function()
    return {
      setTitle = function() end,
      setSaveEnabled = function() end,
      setReloadEnabled = function() end,
      focusMenu = function() end,
      focusSave = function() end,
      focusReload = function() end,
      focusTool = function() end,
    }
  end,
}
package.loaded["wfsuite.app.progress_dialog"] = {
  SPEED = { DEFAULT = 1.0, FAST = 2.0, SLOW = 0.75, VSLOW = 0.5 },
  open = function(opts)
    local d = {
      dialogTitle = opts.title,
      dialogMessage = opts.message,
      closed = false,
    }
    function d:value() end
    function d:close() self.closed = true end
    function d:closeAllowed() end
    function d:message(m) self.dialogMessage = m end
    function d:wakeup() end
    dialogs[#dialogs + 1] = d
    return d
  end,
}

-- ── the save-and-reboot pipeline ───────────────────────────────────────────

-- One page on the supplied PageRuntime class. Returns the runtime and a tick()
-- that runs its wakeup handler, which is where every dialog below is opened.
local function newPage(PageRuntimeClass, rebootAfterSave)
  local opts = {}
  local function setter(name)
    return function(handler) opts[name] = handler end
  end
  opts.setEventHandler = setter("setEventHandler")
  opts.setWakeupHandler = setter("setWakeupHandler")
  opts.setPaintHandler = setter("setPaintHandler")
  opts.setCleanupHandler = setter("setCleanupHandler")
  opts.onBack = function() end

  local runtime = PageRuntimeClass.new({
    pageTitle = "RebootHarness",
    logTag = "reboot-harness",
    profileField = "pidProfile",
    mspModule = mspModuleStub(),
    opts = opts,
    rebootAfterSave = rebootAfterSave,
  })
  runtime:buildChrome()
  runtime:registerField("default", widgetStub("field"))

  local function tick()
    if opts.setWakeupHandler then opts.setWakeupHandler() end
  end
  return runtime, tick
end

-- Loads the page, clears the load dialog, and leaves it loaded but not dirty.
local function loadPage(runtime, tick)
  runtime:loadInitial()
  tick()
end

local function savePage(runtime, tick)
  runtime:markDirty()
  runtime:performSave(function() end)
  tick() -- pendingReboot is consumed here: the restart dialog opens (or not)
end

-- The state machine for the reboot scenario. Returns a trace the checks read.
local function rebootTrace(PageRuntimeClass, rebootAfterSave, opts)
  opts = opts or {}
  resetTrace()
  sessionHandlers = {}
  local runtime, tick = newPage(PageRuntimeClass, rebootAfterSave)
  loadPage(runtime, tick)

  if opts.armedBeforeSave then
    publishSession(true, true, true)
    tick()
  end

  local requestsBeforeSave = reads
  savePage(runtime, tick)

  local dialogAfterSave = currentDialog()
  local trace = {
    runtime = runtime,
    rebootsAfterSave = reboots,
    dialogTitleAfterSave = dialogAfterSave and dialogAfterSave.dialogTitle or nil,
    requestsAfterSave = reads,
    requestsBeforeSave = requestsBeforeSave,
  }

  -- The link drops and comes back. No session.update is sent before this point
  -- in the reboot case, so the wait cannot have ended by accident.
  publishSession(false, false, opts.isArmed)
  tick()
  trace.heldAfterDrop = currentDialog() and currentDialog().dialogTitle or nil
  trace.requestsWhileWaiting = reads

  -- Back, but the handshake has not answered yet: the wait must still hold.
  publishSession(true, false, opts.isArmed)
  tick()
  trace.heldAfterReturnWithoutHandshake = currentDialog() and currentDialog().dialogTitle or nil

  -- The handshake answers: now the wait ends and the page re-reads.
  publishSession(true, true, opts.isArmed)
  tick()
  trace.reloadAfterReturn = reads > trace.requestsAfterSave
  trace.waitEnded = runtime.rebootWait == nil
  tick() -- settle the reload's own async success branch

  trace.finalDialog = currentDialog() and currentDialog().dialogTitle or nil
  return trace
end

-- Same shape, but the board never comes back: the wait must end on its bound.
local function timeoutTrace(PageRuntimeClass)
  resetTrace()
  sessionHandlers = {}
  local runtime, tick = newPage(PageRuntimeClass, true)
  loadPage(runtime, tick)

  savePage(runtime, tick)
  local requestsAfterSave = reads
  -- No session.update at all: the link never visibly drops or returns.
  fakeClock = 21
  tick()

  return {
    waitEnded = runtime.rebootWait == nil,
    reloaded = reads > requestsAfterSave,
  }
end

-- ── run ────────────────────────────────────────────────────────────────────

local realPageRuntime = dofile(SUITE .. "/app/page_runtime.lua")

out("the save-and-reboot pipeline: a save that restarts the FC waits for it")
do
  local trace = rebootTrace(realPageRuntime, true)
  check("the save publishes the MSP_REBOOT", trace.rebootsAfterSave == 1,
    "reboots=" .. tostring(trace.rebootsAfterSave))
  check("the restart dialog is held after the save",
    trace.dialogTitleAfterSave == RESTART_TITLE,
    "dialog after save: " .. tostring(trace.dialogTitleAfterSave))
  check("no read happens while the link is still up",
    trace.requestsWhileWaiting == trace.requestsAfterSave and trace.requestsAfterSave == trace.requestsBeforeSave,
    "requests " .. tostring(trace.requestsBeforeSave) .. " -> " .. tostring(trace.requestsWhileWaiting))
  check("the wait survives the link coming back without a handshake",
    trace.heldAfterReturnWithoutHandshake == RESTART_TITLE,
    "dialog while waiting: " .. tostring(trace.heldAfterReturnWithoutHandshake))
  check("the page reloads after the link returns", trace.reloadAfterReturn == true,
    "requests " .. tostring(trace.requestsAfterSave) .. " -> " .. tostring(trace.requestsWhileWaiting))
  check("the wait ends once the flight controller is back", trace.waitEnded == true)
  check("the restart dialog is gone once the page has reloaded", trace.finalDialog == nil,
    "dialog at rest: " .. tostring(trace.finalDialog))
end

out("")
out("control: a page whose save does not restart the board finishes at once")
do
  local trace = rebootTrace(realPageRuntime, false)
  check("no MSP_REBOOT is published", trace.rebootsAfterSave == 0,
    "reboots=" .. tostring(trace.rebootsAfterSave))
  check("no restart dialog is shown", trace.dialogTitleAfterSave == nil,
    "dialog after save: " .. tostring(trace.dialogTitleAfterSave))
end

out("")
out("control: an armed save does not restart the board")
do
  local trace = rebootTrace(realPageRuntime, true, { armedBeforeSave = true, isArmed = true })
  check("no MSP_REBOOT is published while armed", trace.rebootsAfterSave == 0,
    "reboots=" .. tostring(trace.rebootsAfterSave))
  check("and the save closes without a restart dialog", trace.dialogTitleAfterSave == nil,
    "dialog after save: " .. tostring(trace.dialogTitleAfterSave))
end

out("")
out("timeout: a board that never returns does not hold the page forever")
do
  local trace = timeoutTrace(realPageRuntime)
  check("the wait ends when the board does not come back", trace.waitEnded == true)
  check("and the page reloads so its own error path can report", trace.reloaded == true)
end

-- ── self-test ──────────────────────────────────────────────────────────────

local selfTest = false
for _, arg in ipairs(arg or {}) do
  if arg == "--self-test" then selfTest = true end
end

if selfTest then
  out("")
  out("--self-test: the gates below must be able to go red")

  -- The pre-fix page_runtime: one line short of arming the wait, which is what
  -- the pre-fix save path was -- it closed the dialog and reported the save
  -- done. Loading a spliced copy also proves the wait comes from this file and
  -- not from something ambient.
  local f = assert(io.open(SUITE .. "/app/page_runtime.lua", "r"))
  local source = f:read("*a")
  f:close()
  local sabotagedSource, replacementCount = source:gsub("self_%.pendingReboot = true", "self_.pendingReboot = false", 1)
  assert(replacementCount == 1, "splice did not apply to page_runtime")
  package.loaded["wfsuite.app.page_runtime"] = nil
  local sabotaged = assert(load(sabotagedSource, "@page_runtime_pre_fix"))()

  local heldTrace = rebootTrace(sabotaged, true)
  check("the hold gate goes red on the pre-fix page_runtime",
    heldTrace.dialogTitleAfterSave ~= RESTART_TITLE,
    "the spliced page_runtime still held a restart dialog")
  check("and the reload gate goes red with it",
    heldTrace.reloadAfterReturn == false,
    "the spliced page_runtime still reloaded after the reconnect")

  package.loaded["wfsuite.app.page_runtime"] = realPageRuntime
end

out("")
out(string.rep("-", 60))
out(string.format("checks: %d   failures: %d", checks, failures))
if failures > 0 then
  out("")
  out("FAILED")
  os.exit(1)
end
out("ALL CHECKS PASSED")
