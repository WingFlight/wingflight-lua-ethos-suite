-- Behaviour check, ported from rfsuite #2809: a save of a profile page stops,
-- unsent, as soon as the active profile is not the one the page read.
--
-- Run it:
--     lua5.4 bin/save_profile_switch/verify_save_profile_switch.lua
--
-- The FC writes a PID or rate profile record into whichever profile is active
-- when the write arrives. Every Wingflight profile page writes one record, so the
-- risk is a switch the telemetry has not shown yet, and the MSP queue resending
-- a write whose reply was lost after the pilot switched.
--
-- What it drives: the real src/wfsuite/app/pages/pids.lua (PID profile) and
-- rates.lua (rate profile) through the real app/page_runtime.lua, with the real
-- codecs (lib/msp_pid_tuning.lua, lib/msp_rc_tuning.lua, lib/msp_status.lua)
-- against a mocked FC that holds one record per profile and answers MSP_STATUS
-- with the active ones. It pins that MSP_STATUS is asked before the write; that
-- a switch the telemetry has not shown sends nothing; that a write leaves the
-- queue once and is resent only after the profile is checked again; that
-- without a telemetry profile the FC's first answer is taken; and that a page
-- with profileField "none" is not checked.

local function scriptDir()
  local src = debug.getinfo(1, "S").source
  local path = src:sub(1, 1) == "@" and src:sub(2) or src
  return (path:match("^(.*)[/\\][^/\\]*$")) or "."
end

local ROOT = scriptDir() .. "/../.."
local SUITE = (ROOT .. "/src/wfsuite"):gsub("\\", "/")
local SUITE_PREFIX = SUITE .. "/"

local checks, failures = 0, 0
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

-- ── Ethos environment ──────────────────────────────────────────────────

package.path = SUITE_PREFIX .. "?.lua;" .. package.path
_G.PREFIX = SUITE_PREFIX

local realLoadfile = loadfile
_G.loadfile = function(path, ...)
  if type(path) == "string" and path:match("%.lua$") then
    local absolute = path:sub(1, 1) == "/" and path or (SUITE_PREFIX .. path)
    return realLoadfile(absolute, ...)
  end
  return realLoadfile(path, ...)
end

_G.print = function() end
_G.model = { get = function() return 0 end, name = function() return "stub" end }
_G.radio = { getActiveProfileId = function() return 1 end, getProfileId = function() return 1 end }
_G.system = {
  getVersion = function() return { simulation = false, radio = { name = "stub" } } end,
  playHaptic = function() end,
}
_G.lcd = {
  loadMask = function(p) return {path = p} end,
  getWindowSize = function() return 800, 480 end,
  getTextSize = function(text) return #tostring(text) * 8, 16 end,
  font = function() end,
  color = function() end,
  RGB = function(r, g, b, a) return r, g, b, a end,
  drawFilledRectangle = function() end,
  drawText = function() end,
  invalidate = function() end,
}

local function newWidget(name)
  local w = { name = name }
  setmetatable(w, { __index = function() return function() return w end end })
  w.enable = function(_, v) w.enabled = v end
  return w
end

local lineCounter = 0
local dialogs = {}   -- every dialog's message, in order
_G.form = {
  addLine = function() lineCounter = lineCounter + 1; return lineCounter end,
  getFieldSlots = function(_, hints)
    local slots = {}
    for i = 1, #hints do slots[i] = { x = (i - 1) * 60, y = 0, w = 60, h = 20 } end
    return slots
  end,
  addStaticText = function() return newWidget("text") end,
  addButton = function() return newWidget("button") end,
  addTextButton = function() return newWidget("textbutton") end,
  addNumberField = function() return newWidget("number") end,
  addChoiceField = function() return newWidget("choice") end,
  addBooleanField = function() return newWidget("boolean") end,
  clear = function() end,
  height = function() return 320 end,
  openDialog = function(d)
    dialogs[#dialogs + 1] = d and d.message or ""
    return newWidget("dialog")
  end,
  openProgressDialog = function() return newWidget("progressdialog") end,
}

_G.TIME_LEFT, _G.TEXT_LEFT, _G.LEFT, _G.CENTERED, _G.RIGHT, _G.TOP_LEFT = 1, 2, 3, 4, 5, 6
_G.FONT_XS, _G.FONT_S, _G.FONT_M, _G.FONT_L, _G.FONT_XL = 10, 20, 30, 40, 50
_G.EVT_CLOSE, _G.EVT_KEY, _G.EVT_EXIT_BREAK, _G.EVT_KEY_DOWN_BREAK = 1, 2, 3, 4
_G.KEY_ENTER_LONG, _G.KEY_RTN_BREAK, _G.KEY_EXIT_BREAK, _G.KEY_ENTER_BREAK = 5, 6, 7, 8

-- ── the FC ─────────────────────────────────────────────────────────────

local STATUS, PID_READ, PID_WRITE, RATE_READ, RATE_WRITE, EEPROM = 101, 112, 202, 111, 204, 250
local WRITE_TO_READ = { [PID_WRITE] = PID_READ, [RATE_WRITE] = RATE_READ }

local codecs = {
  [PID_READ] = assert(loadfile("lib/msp_pid_tuning.lua"))(),
  [RATE_READ] = assert(loadfile("lib/msp_rc_tuning.lua"))(),
}
local statusCodec = assert(loadfile("lib/msp_status.lua"))()

local function copy(t)
  local c = {}
  for i, v in ipairs(t) do c[i] = v end
  return c
end

local function fixture(cmd)
  return copy(codecs[cmd].buildReadMessage(function() end).simulatorResponse)
end

-- fc.records[readCommand][p] = the record's bytes in profile p (1-based);
-- fc.pid / fc.rate are the active profiles
local fc
local function resetFc()
  fc = { pid = 1, rate = 1, records = { [PID_READ] = {}, [RATE_READ] = {} } }
  for p = 1, 2 do
    fc.records[PID_READ][p] = fixture(PID_READ)
    fc.records[RATE_READ][p] = fixture(RATE_READ)
  end
end

local function activeOf(cmd)
  return cmd == PID_READ and fc.pid or fc.rate
end

local function statusReply()
  local buf = copy(statusCodec.buildReadMessage(function() end).simulatorResponse)
  buf[24] = fc.pid - 1    -- current_pid_profile_index
  buf[26] = fc.rate - 1   -- current_control_rate_profile_index
  return buf
end

-- ── module stubs ───────────────────────────────────────────────────────

local queue, sessionHandlers = {}, {}
package.loaded["wfsuite.lib.bus"] = {
  subscribe = function(topic, handler)
    if topic == "session.update" then sessionHandlers[#sessionHandlers + 1] = handler end
  end,
  unsubscribe = function() end,
  publish = function(topic, message)
    if topic == "msp.request" and type(message) == "table" then queue[#queue + 1] = message end
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
}
package.loaded["wfsuite.app.close_key"] = { shouldHandleClose = function() return false end }
package.loaded["wfsuite.app.progress_dialog"] = {
  SPEED = { DEFAULT = 1.0, FAST = 2.0, SLOW = 0.75, VSLOW = 0.5 },
  open = function() return { value = function() end, close = function() end, message = function() end } end,
}

-- Answers the queued requests in order, as the radio's queue would. hook(msg)
-- runs first and may return "lost" (the FC acts on a write but its reply is
-- lost) or "error" (the request fails), and true as a second value to switch
-- both profiles to 2 once the request has been acted on.
local function pump(hook, wakeup)
  local sent, maxRetries = {}, {}
  for _ = 1, 200 do
    if wakeup then wakeup() end
    if #queue == 0 then
      if wakeup then wakeup() end
      if #queue == 0 then break end
    end
    local m = table.remove(queue, 1)
    sent[#sent + 1] = m.command
    if WRITE_TO_READ[m.command] then maxRetries[#maxRetries + 1] = m.maxRetries end
    local action, switchAfter
    if hook then action, switchAfter = hook(m) end
    if action == "error" then
      m.errorHandler("timeout")
    elseif m.command == STATUS then
      m.processReply(m, statusReply())
    elseif WRITE_TO_READ[m.command] then
      local r = WRITE_TO_READ[m.command]
      fc.records[r][activeOf(r)] = copy(m.payload)
      if switchAfter then fc.pid, fc.rate = 2, 2 end
      if action == "lost" then m.errorHandler("max_retries") else m.processReply(m, {}) end
    elseif codecs[m.command] then
      m.processReply(m, copy(fc.records[m.command][activeOf(m.command)]))
    else
      m.processReply(m, {})   -- EEPROM
    end
  end
  return sent, maxRetries
end

local function has(list, value)
  for _, v in ipairs(list) do if v == value then return true end end
  return false
end

local function count(list, value)
  local n = 0
  for _, v in ipairs(list) do if v == value then n = n + 1 end end
  return n
end

-- ── the pages ──────────────────────────────────────────────────────────

local PageRuntime = assert(loadfile("app/page_runtime.lua"))()
package.loaded["wfsuite.app.page_runtime"] = PageRuntime
local realNew = PageRuntime.new
local lastRuntime
PageRuntime.new = function(config)
  lastRuntime = realNew(config)
  return lastRuntime
end

local session = { pidProfile = 1, rateProfile = 1, isArmed = false, connected = true, mcuId = "0123456789" }
local function publishSession()
  for _, h in ipairs(sessionHandlers) do h(session) end
end

-- Each save changes one field of the page's record to NEW
local NEW = 77
local PAGES = {
  pids = { file = "app/pages/pids.lua", read = PID_READ, write = PID_WRITE, field = "roll_p" },
  rates = { file = "app/pages/rates.lua", read = RATE_READ, write = RATE_WRITE, field = "rcRates_1" },
}

local function openPage(name)
  local page = PAGES[name]
  resetFc()
  queue, sessionHandlers = {}, {}
  for i = #dialogs, 1, -1 do dialogs[i] = nil end
  lastRuntime = nil
  local module = assert(loadfile(page.file))()
  local opts = {}
  opts.onBack = function() end
  opts.setEventHandler = function(fn) opts.event = fn end
  opts.setWakeupHandler = function(fn) opts.wakeup = fn end
  opts.setPaintHandler = function() end
  opts.setCleanupHandler = function(fn) opts.cleanup = fn end
  module.open(opts)
  publishSession()
  pump(nil, opts.wakeup)
  local rt = lastRuntime
  rt.data[page.field] = NEW
  rt:markDirty()
  return rt, opts, page
end

local function save(rt, opts, hook)
  rt:performSave(function() end)
  return pump(hook, opts.wakeup)
end

local function wrote(page, p)
  return codecs[page.read].decode(copy(fc.records[page.read][p]))[page.field] == NEW
end

local SAVE_FAILED = "app.msg_save_failed_body"
local function lastDialog()
  return dialogs[#dialogs] or ""
end
local function reported(key)
  return lastDialog():find(key, 1, true) ~= nil
end

-- ── cases ──────────────────────────────────────────────────────────────

for _, name in ipairs({ "pids", "rates" }) do
  out(name .. ": a save with no switch")
  do
    local rt, opts, page = openPage(name)
    check("the page loaded", rt.loaded == true)
    local sent, retries = save(rt, opts)
    check("the record lands in profile 1", wrote(page, 1))
    check("MSP_STATUS is asked before the write, then the commit",
      table.concat(sent, ",") == "101," .. page.write .. ",250", table.concat(sent, ","))
    check("the write leaves the queue once", #retries == 1 and retries[1] == 0)
    check("no save error", not reported(SAVE_FAILED), lastDialog())
    if opts.cleanup then opts.cleanup() end
  end

  out(name .. ": the FC is on another profile the telemetry has not shown")
  do
    local rt, opts, page = openPage(name)
    fc.pid, fc.rate = 2, 2
    local sent = save(rt, opts)
    check("nothing is written", not wrote(page, 1) and not wrote(page, 2) and not has(sent, page.write),
      table.concat(sent, ","))
    check("nothing is committed", not has(sent, EEPROM))
    check("reported as a failed save", reported(SAVE_FAILED), lastDialog())
    if opts.cleanup then opts.cleanup() end
  end

  out(name .. ": a lost write reply followed by a switch")
  do
    local rt, opts, page = openPage(name)
    local sent = save(rt, opts, function(m)
      if m.command == page.write then return "lost", true end
    end)
    check("the write is not resent into profile 2", count(sent, page.write) == 1 and not wrote(page, 2),
      table.concat(sent, ","))
    check("nothing is committed", not has(sent, EEPROM))
    if opts.cleanup then opts.cleanup() end
  end
end

out("pids: telemetry already shows the switch")
do
  local rt, opts, page = openPage("pids")
  session.pidProfile = 2
  publishSession()
  session.pidProfile = 1
  local sent = save(rt, opts)
  check("nothing is sent", not has(sent, page.write) and not has(sent, EEPROM), table.concat(sent, ","))
  if opts.cleanup then opts.cleanup() end
end

out("pids: a lost write reply is resent after the profile is checked again")
do
  local rt, opts, page = openPage("pids")
  local lost = false
  local sent = save(rt, opts, function(m)
    if m.command == page.write and not lost then lost = true return "lost" end
  end)
  check("the save completes", wrote(page, 1) and has(sent, EEPROM) and not reported(SAVE_FAILED),
    table.concat(sent, ","))
  check("the resend follows a status check", table.concat(sent, ","):find("101,202,101,202,250", 1, true) ~= nil,
    table.concat(sent, ","))
  if opts.cleanup then opts.cleanup() end
end

out("pids: a write that keeps failing ends the save")
do
  local rt, opts, page = openPage("pids")
  local sent = save(rt, opts, function(m) if m.command == page.write then return "error" end end)
  check("tried a bounded number of times", count(sent, page.write) == 6 and not has(sent, EEPROM),
    count(sent, page.write) .. " attempts")
  check("reported as a failed save", reported(SAVE_FAILED), lastDialog())
  if opts.cleanup then opts.cleanup() end
end

out("pids: a status request that fails stops the save")
do
  local rt, opts, page = openPage("pids")
  local sent = save(rt, opts, function(m) if m.command == STATUS then return "error" end end)
  check("nothing is written", not has(sent, page.write) and not has(sent, EEPROM), table.concat(sent, ","))
  check("reported as a failed save", reported(SAVE_FAILED), lastDialog())
  if opts.cleanup then opts.cleanup() end
end

out("pids: no telemetry profile")
do
  session.pidProfile = nil
  local rt, opts, page = openPage("pids")
  local sent = save(rt, opts)
  check("the FC's first answer lets the save through", wrote(page, 1) and has(sent, EEPROM),
    table.concat(sent, ","))
  if opts.cleanup then opts.cleanup() end
  session.pidProfile = 1
end

out("A page whose data has no profile is not checked")
do
  resetFc()
  queue, sessionHandlers = {}, {}
  local rt = PageRuntime.new({
    pageTitle = "Test",
    mspModule = codecs[PID_READ],
    profileField = "none",
    opts = { onBack = function() end, setEventHandler = function() end, setWakeupHandler = function() end,
      setPaintHandler = function() end, setCleanupHandler = function() end },
  })
  rt.loaded, rt.data = true, codecs[PID_READ].decode(fixture(PID_READ))
  rt:markDirty()
  rt:performSave(function() end)
  local sent = pump()
  check("no MSP_STATUS is asked", not has(sent, STATUS) and has(sent, PID_WRITE) and has(sent, EEPROM),
    table.concat(sent, ","))
end

out(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
