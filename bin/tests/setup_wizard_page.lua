-- Run from the repository root with Lua 5.4: lua5.4 bin/tests/setup_wizard_page.lua
--
-- Drives the real Setup Wizard shell (app/pages/setup_wizard.lua) and its
-- Direction step with a stubbed Ethos form, header and bus. The real MSP
-- codecs, lib/override_keepalive.lua and lib/setup_wizard_surfaces.lua run
-- unchanged. Every read is answered with its codec's simulator reply, so the
-- model is the firmware's default glider mix (two ailerons, elevator,
-- rudder; lib/msp_mixer_rules.lua). The checks read the bytes the page
-- puts on the wire:
--   * opening holds the setup state and clears overrides other pages left on;
--   * Move holds the checked axis at the test movement, the other axes and
--     the flap channel at zero, all timed; Stop releases them;
--   * Wrong reverses the servo, Invert axis negates the axis throw, and both
--     mark the wizard dirty;
--   * arming lets everything go and greys out Move;
--   * Discard writes back what was loaded; Save writes EEPROM;
--   * leaving releases the setup state;
--   * firmware without timed overrides gets an explanation and no writes.

local ROOT = "src/wfsuite/"

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("  ok    " .. label)
  else
    failures = failures + 1
    print("  FAIL  " .. label)
    if detail then print("        " .. tostring(detail)) end
  end
end

-- Ethos environment -------------------------------------------------------

local realLoadfile = loadfile
_G.loadfile = function(path, ...)
  if type(path) == "string" and path:sub(1, #ROOT) ~= ROOT and path:match("%.lua$") then
    return realLoadfile(ROOT .. path, ...)
  end
  return realLoadfile(path, ...)
end

local clock = 0
os.clock = function() return clock end

_G.FONT_S, _G.FONT_STD, _G.FONT_XS = 20, 25, 10
_G.LEFT, _G.CENTERED, _G.RIGHT, _G.TEXT_LEFT = 3, 4, 5, 2
_G.lcd = {
  getWindowSize = function() return 480, 320 end,
  font = function() end,
  getTextSize = function(text) return #text * 10, 20 end,
}

local fields, dialogs
local function newField(kind, props)
  local f = {kind = kind, enabled = true}
  for k, v in pairs(props or {}) do f[k] = v end
  function f.enable(_, v) f.enabled = v end
  function f.value(_, v) if v ~= nil then f.text = v end return f.text end
  function f.focus() f.focused = true end
  fields[#fields + 1] = f
  return f
end

-- MSP replies and bus events run in the background task, where Ethos refuses
-- to build a form ("Lua::Form::clear() error: forbidden"); a page that does it
-- there never leaves or rebuilds on the radio. Updating an existing field is
-- allowed. inBackground is raised while the harness delivers either.
local inBackground = false
local forbidden = {}
local function foreground(name)
  if inBackground then forbidden[#forbidden + 1] = name end
end

_G.form = {
  clear = function() foreground("clear") fields = {} end,
  addLine = function(label) foreground("addLine") return {label = label} end,
  getFieldSlots = function() return {{x = 0, y = 0, w = 200, h = 30}} end,
  addStaticText = function(line, _, text)
    foreground("addStaticText")
    return newField("static", {line = line, text = text})
  end,
  addButton = function(line, _, opts)
    foreground("addButton")
    return newField("button", {line = line, text = opts.text, press = opts.press})
  end,
  addChoiceField = function(line, _, choices, get, set)
    foreground("addChoiceField")
    return newField("choice", {line = line, choices = choices, get = get, set = set})
  end,
  openDialog = function(opts)
    foreground("openDialog")
    local d = {opts = opts, closed = false}
    function d.close() d.closed = true end
    dialogs[#dialogs + 1] = d
    return d
  end,
}

-- Stubbed modules ----------------------------------------------------------

local sent = {}
local subscribers = {}
local headers = {}

local stubs = {
  ["lib/bus.lua"] = {
    publish = function(event, message)
      if event == "msp.request" then sent[#sent + 1] = message end
    end,
    subscribe = function(event, fn)
      subscribers[event] = subscribers[event] or {}
      table.insert(subscribers[event], fn)
      return fn
    end,
    unsubscribe = function(event, fn)
      local list = subscribers[event] or {}
      for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
    end,
  },
  ["app/header.lua"] = {
    build = function(title, opts)
      local h = {title = title, opts = opts, saveEnabled = nil}
      h.setSaveEnabled = function(v) h.saveEnabled = v end
      h.setReloadEnabled = function() end
      h.focusMenu = function() end
      headers[#headers + 1] = h
      return h
    end,
  },
  ["app/progress_dialog.lua"] = {
    open = function() return {value = function() end, close = function() end} end,
  },
  ["app/close_key.lua"] = {shouldHandleClose = function() return false end},
}

local cache = {}
package.loaded["wfsuite.lib.require"] = function(path)
  if stubs[path] then return stubs[path] end
  if cache[path] == nil then
    local result = assert(realLoadfile(ROOT .. path))()
    cache[path] = result == nil and true or result
  end
  return cache[path]
end
local requireModule = package.loaded["wfsuite.lib.require"]

local function session(data)
  inBackground = true
  for _, fn in ipairs(subscribers["session.update"] or {}) do fn(data) end
  inBackground = false
end

-- Answers every message sent so far, in order, with its simulator reply (a
-- copy, as the queue hands out a fresh buffer).
local answeredUpTo = 0
local function answerAll()
  inBackground = true
  while answeredUpTo < #sent do
    answeredUpTo = answeredUpTo + 1
    local m = sent[answeredUpTo]
    if m.processReply then
      local buf = {}
      for i, b in ipairs(m.simulatorResponse or {}) do buf[i] = b end
      m.processReply(nil, buf)
    end
  end
  inBackground = false
end

-- Helpers over what reached the wire -----------------------------------------

local function bytes(t) return table.concat(t, ",") end
local function u16(p, i) return p[i] + p[i + 1] * 256 end
local function s16(p, i) local v = u16(p, i) return v >= 32768 and v - 65536 or v end

local function writesOf(command, from)
  local out = {}
  for i = (from or 1), #sent do
    if sent[i].command == command then out[#out + 1] = sent[i] end
  end
  return out
end

-- Last mixer override value per input since `from`: {value =, timed =}.
local function mixerState(from)
  local state = {}
  for _, m in ipairs(writesOf(191, from)) do
    local p = m.payload
    state[p[1]] = {value = s16(p, 2), timed = #p >= 5}
  end
  return state
end

local function find(kind, text)
  for _, f in ipairs(fields) do
    if f.kind == kind and (text == nil or f.text == text or (f.line and f.line.label == text)) then return f end
  end
end
local function findAll(kind, text)
  local out = {}
  for _, f in ipairs(fields) do
    if f.kind == kind and (f.text == text or (f.line and f.line.label == text)) then out[#out + 1] = f end
  end
  return out
end
local function buttonOnLine(lineLabel, text)
  for _, f in ipairs(fields) do
    if f.kind == "button" and f.text == text and f.line and f.line.label == lineLabel then return f end
  end
end
local function staticWith(text)
  for _, f in ipairs(fields) do
    if f.kind == "static" and f.text == text then return f end
  end
end

local T = function(key) return "@i18n(app.modules.setup_wizard." .. key .. ")@" end

-- Opening ---------------------------------------------------------------------

local function openPage(apiMinor)
  fields, dialogs, sent, headers = {}, {}, {}, {}
  answeredUpTo = 0
  subscribers["session.update"] = nil
  for k in pairs(cache) do cache[k] = nil end
  for k in pairs(package.loaded) do
    if type(k) == "string" and k:match("^wfsuite%.") and k ~= "wfsuite.lib.require" then package.loaded[k] = nil end
  end
  local page = assert(realLoadfile(ROOT .. "app/pages/setup_wizard.lua"))()
  local ctx = {back = 0}
  page.open({
    -- The real menu rebuilds itself here (app/menu_container.lua).
    onBack = function() ctx.back = ctx.back + 1; form.clear() end,
    setWakeupHandler = function(fn) ctx.wakeup = fn end,
    setEventHandler = function() end,
    setCleanupHandler = function(fn) ctx.cleanup = fn end,
  })
  -- keepalive.lua subscribes when it is first required, by the page.
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = apiMinor})
  for _ = 1, 4 do
    answerAll()
    if ctx.wakeup then ctx.wakeup() end
  end
  return ctx
end

local function tick(ctx, seconds)
  clock = clock + (seconds or 0.3)
  answerAll()
  ctx.wakeup()
  answerAll()
end

-- 22.14: the wizard opens on Direction --------------------------------------

local ctx = openPage(14)
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local modeWrites = writesOf(0x5F1B)
check("opening holds the setup state, nothing forced, 10 s timeout",
  #modeWrites == 1 and bytes(modeWrites[1].payload) == "16,39,0", modeWrites[1] and bytes(modeWrites[1].payload))
local cleared = mixerState()
check("opening clears mixer overrides on roll, pitch, yaw and flap",
  cleared[1] and cleared[1].value == 2501 and cleared[2] and cleared[3] and cleared[13]
  and cleared[13].value == 2501)
check("opening clears every servo override", #writesOf(196) == 1 and bytes(writesOf(196)[1].payload) == "209,7")
check("the title names the step", headers[#headers].title == T("name") .. " / " .. T("step_direction"),
  headers[#headers].title)
local emptyRow = false
for _, f in ipairs(fields) do
  if f.kind == "static" and f.line and f.line.label == "" and f.text == "" then emptyRow = true end
end
check("no notice row while there is nothing to say", not emptyRow)

local checkField = find("choice", T("dir_check"))
check("a check per axis the mix uses: pitch, roll, yaw (no flap)",
  checkField and #checkField.choices == 3 and checkField.choices[1][1] == T("dir_check_pitch")
  and checkField.choices[3][1] == T("dir_check_yaw"))
local rows = findAll("button", T("dir_identify"))
check("pitch check lists the elevator only", #rows == 1 and rows[1].line.label == string.format(T("surface_label_fmt"), 3, T("surface_elevator")),
  #rows)

-- Move and Stop
local before = #sent
buttonOnLine(T("dir_surfaces"), T("dir_move")).press()
local held = mixerState(before + 1)
check("Move holds pitch up at 15 %, timed", held[2] and held[2].value == -150 and held[2].timed,
  held[2] and held[2].value)
check("Move holds roll, yaw and flap at zero, timed",
  held[1].value == 0 and held[3].value == 0 and held[13] and held[13].value == 0 and held[13].timed)
check("Move greys out while held, Stop is live",
  not buttonOnLine(T("dir_surfaces"), T("dir_move")).enabled and buttonOnLine(T("dir_surfaces"), T("dir_stop")).enabled)

before = #sent
find("choice", T("dir_movement")).set(50)
held = mixerState(before + 1)
check("changing the movement while held moves to it at once", held[2] and held[2].value == -500,
  held[2] and held[2].value)

before = #sent
buttonOnLine(T("dir_surfaces"), T("dir_stop")).press()
held = mixerState(before + 1)
check("Stop releases all four inputs, untimed OFF",
  held[1].value == 2501 and held[2].value == 2501 and held[3].value == 2501 and held[13].value == 2501
  and not held[2].timed)

clock = clock + 20
local refreshed = #sent
requireModule("lib/override_keepalive.lua").tick(clock)
local refreshedMixer = writesOf(191, refreshed + 1)
check("released inputs are not refreshed; the setup state is",
  #refreshedMixer == 0 and #writesOf(0x5F1B, refreshed + 1) == 1)

-- Live value: the read goes out on one wakeup, the row shows it on the next.
tick(ctx)
tick(ctx)
local elevatorLabel = string.format(T("surface_label_fmt"), 3, T("surface_elevator"))
local value
for _, f in ipairs(fields) do
  if f.kind == "static" and f.line and f.line.label == elevatorLabel then value = f end
end
check("the row shows the servo's live output", value and value.text == "1500", value and value.text)
check("servo outputs are read while the step is open", #writesOf(103) >= 1)

-- Wrong reverses the elevator servo
before = #sent
buttonOnLine(elevatorLabel, T("dir_wrong")).press()
local cfg = writesOf(212, before + 1)
check("Wrong writes servo 3's config with the reverse flag",
  #cfg == 1 and cfg[1].payload[1] == 2 and u16(cfg[1].payload, 16) == 1,
  cfg[1] and bytes(cfg[1].payload))
check("the row then shows Fixed", value.text == T("dir_fixed"), value.text)
check("Save is offered once something changed", headers[#headers].saveEnabled == true)

-- Switch to roll: the ailerons, Wrong enabled on both
checkField.set(2)
tick(ctx)
rows = findAll("button", T("dir_identify"))
check("roll check lists both ailerons", #rows == 2)
local leftWrong = buttonOnLine(string.format(T("surface_label_fmt"), 1, T("surface_aileron")), T("dir_wrong"))
check("Wrong is live for a surface on its own axis", leftWrong and leftWrong.enabled)
check("the check field keeps the focus after the rebuild", find("choice", T("dir_check")).focused == true)

-- Invert axis
before = #sent
buttonOnLine(T("dir_all_wrong"), T("dir_invert")).press()
local inputWrites = writesOf(171, before + 1)
check("Invert axis negates roll's axis throw",
  #inputWrites == 1 and inputWrites[1].payload[1] == 1 and s16(inputWrites[1].payload, 2) == -1000,
  inputWrites[1] and bytes(inputWrites[1].payload))

-- Identify wiggles one servo, then lets go
before = #sent
rows[1].press()
for _ = 1, 8 do tick(ctx, 0.3) end
local wiggles = writesOf(193, before + 1)
local values = {}
for i, m in ipairs(wiggles) do values[i] = s16(m.payload, 2) end
check("Wiggle moves servo 1 six times and then releases it",
  #wiggles >= 7 and values[1] == 300 and values[2] == -300 and values[7] == 2001
  and wiggles[1].payload[1] == 0, table.concat(values, ","))

-- Arming lets go of everything
buttonOnLine(T("dir_surfaces"), T("dir_move")).press()
before = #sent
session({connected = true, isArmed = true, apiVersionMajor = 22, apiVersionMinor = 14})
held = mixerState(before + 1)
check("arming releases the held axes", held[1] and held[1].value == 2501)
tick(ctx)
check("arming says why", staticWith(T("armed")) ~= nil)
check("Move is greyed out while armed", not buttonOnLine(T("dir_surfaces"), T("dir_move")).enabled)
before = #sent
buttonOnLine(T("dir_surfaces"), T("dir_move")).press()
check("Move while armed sends nothing", #writesOf(191, before + 1) == 0)
session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
tick(ctx)

-- Back with changes asks; Discard writes back what was loaded
headers[#headers].opts.onBack()
tick(ctx)
local d = dialogs[#dialogs]
check("Back with unsaved changes asks", d and d.opts.title == T("leave_title") and #d.opts.buttons == 3)
before = #sent
d.opts.buttons[2].action()
local restoredCfg = writesOf(212, before + 1)
local restoredIn = writesOf(171, before + 1)
check("Discard writes servo 3 back unreversed",
  #restoredCfg == 1 and restoredCfg[1].payload[1] == 2 and u16(restoredCfg[1].payload, 16) == 0)
check("Discard writes roll's axis throw back", #restoredIn == 1 and s16(restoredIn[1].payload, 2) == 1000)
local release = writesOf(0x5F1B, before + 1)
check("leaving releases the setup state", #release == 1 and bytes(release[1].payload) == "0,0,0")
check("leaving clears every servo override", #writesOf(196, before + 1) == 1)
check("leaving returns to the menu", ctx.back == 1)
check("nothing is held after leaving", not requireModule("lib/override_keepalive.lua").isActive("mode_override"))

-- Save writes EEPROM ----------------------------------------------------------

ctx = openPage(14)
buttonOnLine(string.format(T("surface_label_fmt"), 3, T("surface_elevator")), T("dir_wrong")).press()
headers[#headers].opts.onSave()
before = #sent
tick(ctx)
check("Save writes EEPROM from wakeup", #writesOf(250, before + 1) == 1)
tick(ctx)
check("after the save nothing is pending", headers[#headers].saveEnabled == false)
headers[#headers].opts.onBack()
check("Back after saving leaves without asking", ctx.back == 1 and #dialogs == 0 and ctx.wakeup == nil)

-- Save from the leave dialog: the EEPROM reply arrives in the background task,
-- so the page must leave from its next wakeup, not from the reply.
ctx = openPage(14)
buttonOnLine(string.format(T("surface_label_fmt"), 3, T("surface_elevator")), T("dir_wrong")).press()
headers[#headers].opts.onBack()
tick(ctx)
dialogs[#dialogs].opts.buttons[1].action()
before = #sent
tick(ctx)
check("Save in the leave dialog writes EEPROM", #writesOf(250, before + 1) == 1)
answerAll()
if ctx.wakeup then ctx.wakeup() end
check("and then leaves", ctx.back == 1 and ctx.wakeup == nil)
check("no form was built from a reply or a bus event", #forbidden == 0, table.concat(forbidden, ","))

-- Older firmware: explain and stop -------------------------------------------

ctx = openPage(13)
check("22.13: no setup state requested", #writesOf(0x5F1B) == 0)
check("22.13: no override sent", #writesOf(191) == 0 and #writesOf(196) == 0)
local explained = false
for _, f in ipairs(fields) do
  if f.kind == "static" and f.text and f.text:find("needs_firmware", 1, true) then explained = true end
end
check("22.13: the page says why", explained)

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
