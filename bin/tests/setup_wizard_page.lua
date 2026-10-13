-- Run from the repository root with Lua 5.4: lua5.4 bin/tests/setup_wizard_page.lua
--
-- Drives the real Setup Wizard shell (app/pages/setup_wizard.lua) and its
-- Direction step with a stubbed Ethos form, lcd, header and bus. The real MSP
-- codecs, lib/override_keepalive.lua, lib/setup_wizard_surfaces.lua and
-- app/setup_wizard_art.lua run unchanged. Every read is answered with its
-- codec's simulator reply, so the model is the firmware's default glider mix
-- (two ailerons, elevator, rudder; lib/msp_mixer_rules.lua); a second run
-- swaps in a flying wing. The checks read the bytes the page puts on the wire
-- and the text its paint draws:
--   * opening holds the setup state and clears overrides other pages left on;
--   * a check holds the other axes and the flaps at centre and flicks the
--     checked one, timed; leaving the check releases them;
--   * the answers fix things by the Configurator's rules: one wrong surface
--     on its own axis is reversed, all wrong inverts the axis, "only some"
--     wiggles each servo and reverses the ones picked, and a wrong surface
--     that also works another axis is left alone and explained;
--   * arming lets everything go and greys out the answers;
--   * Save and finish writes EEPROM and leaves; Discard writes back what was
--     loaded; leaving releases the setup state;
--   * nothing builds a form from an MSP reply or a bus event (Ethos forbids
--     it there);
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

local drawn = {}   -- text drawn by the last paint
_G.FONT_S, _G.FONT_STD, _G.FONT_XS = 20, 25, 10
_G.LEFT, _G.CENTERED, _G.RIGHT, _G.TEXT_LEFT = 3, 4, 5, 2
_G.lcd = {
  getWindowSize = function() return 480, 290 end,
  font = function() end,
  getTextSize = function(text) return #text * 8, 18 end,
  darkMode = function() return true end,
  GREY = function(v) return v end,
  RGB = function(r) return r end,
  color = function() end,
  invalidate = function() end,
  drawText = function(_, _, text) drawn[#drawn + 1] = text end,
  drawFilledRectangle = function() end,
  drawFilledTriangle = function() end,
  drawFilledCircle = function() end,
  drawLine = function() end,
}

-- MSP replies and bus events run in the background task, where Ethos refuses
-- to build a form ("Lua::Form::clear() error: forbidden"). Updating an
-- existing field is allowed. inBackground is raised while the harness
-- delivers either.
local inBackground = false
local forbidden = {}
local function foreground(name)
  if inBackground then forbidden[#forbidden + 1] = name end
end

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

_G.form = {
  clear = function() foreground("clear") fields = {} end,
  height = function() return 50 end,
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

-- Replies by command, overriding the codec's simulator reply.
local replies = {}

local answeredUpTo = 0
local function answerAll()
  inBackground = true
  while answeredUpTo < #sent do
    answeredUpTo = answeredUpTo + 1
    local m = sent[answeredUpTo]
    if m.processReply then
      local buf = {}
      for i, b in ipairs(replies[m.command] or m.simulatorResponse or {}) do buf[i] = b end
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

-- Every mixer override value since `from`, per input: {value, timed} list.
local function mixerWrites(from, input)
  local out = {}
  for _, m in ipairs(writesOf(191, from)) do
    if m.payload[1] == input then out[#out + 1] = {value = s16(m.payload, 2), timed = #m.payload >= 5} end
  end
  return out
end
local function lastMixer(from, input)
  local w = mixerWrites(from, input)
  return w[#w]
end

local function button(text)
  for _, f in ipairs(fields) do
    if f.kind == "button" and f.text == text then return f end
  end
end

local T = function(key) return "@i18n(app.modules.setup_wizard." .. key .. ")@" end

local ctx
local function paint()
  drawn = {}
  if ctx.paint then ctx.paint() end
  return table.concat(drawn, "\n")
end
local function shows(key) return paint():find(T(key), 1, true) ~= nil end

local function tick(seconds)
  clock = clock + (seconds or 0.3)
  answerAll()
  if ctx.wakeup then ctx.wakeup() end
  answerAll()
end

local function press(text)
  local b = button(text)
  assert(b, "no button " .. text)
  b.press()
  tick()
end

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
  ctx = {back = 0}
  page.open({
    -- The real menu rebuilds itself here (app/menu_container.lua).
    onBack = function() ctx.back = ctx.back + 1; form.clear() end,
    setWakeupHandler = function(fn) ctx.wakeup = fn end,
    setPaintHandler = function(fn) ctx.paint = fn end,
    setEventHandler = function() end,
    setCleanupHandler = function(fn) ctx.cleanup = fn end,
  })
  -- keepalive.lua subscribes when it is first required, by the page.
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = apiMinor})
  for _ = 1, 4 do
    answerAll()
    if ctx.wakeup then ctx.wakeup() end
  end
end

-- 22.14, default glider ------------------------------------------------------

openPage(14)

local modeWrites = writesOf(0x5F1B)
check("opening holds the setup state, nothing forced, 10 s timeout",
  #modeWrites == 1 and bytes(modeWrites[1].payload) == "16,39,0", modeWrites[1] and bytes(modeWrites[1].payload))
check("opening clears mixer overrides on roll, pitch, yaw and flap",
  lastMixer(1, 1).value == 2501 and lastMixer(1, 2).value == 2501 and lastMixer(1, 3).value == 2501
  and lastMixer(1, 13).value == 2501)
check("opening clears every servo override", #writesOf(196) == 1 and bytes(writesOf(196)[1].payload) == "209,7")
check("the title names the step", headers[#headers].title == T("name") .. " / " .. T("step_direction"),
  headers[#headers].title)
check("it opens on the intro, which moves nothing", shows("dir_intro") and #writesOf(191) == 4)
local start = button(T("dir_start"))
check("the intro's only answer is Start, and it has the focus", start and start.focused)

-- Pitch: the first check for this mix (no flaps)
local before = #sent
press(T("dir_start"))
check("Start opens the pitch check", shows("dir_check_pitch") and shows("dir_q_match"))
check("the check holds roll, yaw and flaps at centre, timed",
  lastMixer(before + 1, 1).value == 0 and lastMixer(before + 1, 1).timed
  and lastMixer(before + 1, 3).value == 0 and lastMixer(before + 1, 13).value == 0)
for _ = 1, 4 do tick(0.9) end
local flicks = mixerWrites(before + 1, 2)
local values = {}
for i, w in ipairs(flicks) do values[i] = w.value end
check("then flicks pitch between centre and pitch up 25 %, timed",
  #flicks >= 4 and values[2] == -250 and values[3] == 0 and values[4] == -250 and flicks[2].timed,
  table.concat(values, ","))
check("only pitch is written while it flicks", #mixerWrites(before + 6, 1) == 0)

before = #sent
press(string.format(T("dir_move_fmt"), 25))
for _ = 1, 2 do tick(0.9) end
local bigger = false
for _, w in ipairs(mixerWrites(before + 1, 2)) do if w.value == -350 then bigger = true end end
check("Move steps the test movement up to 35 %", bigger)

-- Roll: both ailerons the wrong way inverts roll
press(T("dir_like"))
check("Like this goes on to roll", shows("dir_check_roll"))
press(T("dir_unlike"))
check("two surfaces: asks whether all of them were wrong", shows("dir_q_all"))
before = #sent
press(T("dir_all"))
local inputWrites = writesOf(171, before + 1)
check("All of them inverts roll's axis throw",
  #inputWrites == 1 and inputWrites[1].payload[1] == 1 and s16(inputWrites[1].payload, 2) == -1000,
  inputWrites[1] and bytes(inputWrites[1].payload))
check("and checks roll again, saying so", shows("dir_check_roll") and shows("dir_status_inverted"))
check("Save is offered once something changed", headers[#headers].saveEnabled == true)

-- Roll again: only one aileron wrong
press(T("dir_unlike"))
press(T("dir_some"))
check("Only some wiggles the first aileron and asks", shows("dir_identify_fmt"))
check("focus starts on No", button(T("dir_no")).focused == true)
before = #sent
for _ = 1, 3 do tick(0.35) end
local wiggles = {}
for _, m in ipairs(writesOf(193, before + 1)) do
  if m.payload[1] == 0 then wiggles[#wiggles + 1] = s16(m.payload, 2) end
end
check("servo 1 wiggles +-300, timed", #wiggles >= 2 and wiggles[1] ~= wiggles[2]
  and math.abs(wiggles[1]) == 300 and #writesOf(193, before + 1)[1].payload == 5, table.concat(wiggles, ","))
check("the axes are let go while a servo wiggles", lastMixer(1, 1).value == 2501)
before = #sent
press(T("dir_yes"))
local released = false
for _, m in ipairs(writesOf(193, before + 1)) do
  if m.payload[1] == 0 and s16(m.payload, 2) == 2001 then released = true end
end
check("the next servo's turn releases servo 1", released)
before = #sent
press(T("dir_no"))
local cfg = writesOf(212, before + 1)
check("the aileron picked is reversed: servo 1, reverse flag set",
  #cfg == 1 and cfg[1].payload[1] == 0 and u16(cfg[1].payload, 16) == 1, cfg[1] and bytes(cfg[1].payload))
check("and roll is checked again", shows("dir_check_roll") and shows("dir_status_reversed_fmt"))

-- Yaw: a single rudder the wrong way is reversed straight away
press(T("dir_like"))
check("roll done, on to yaw", shows("dir_check_yaw"))
before = #sent
press(T("dir_unlike"))
cfg = writesOf(212, before + 1)
check("one surface wrong on its own axis: its servo is reversed",
  #cfg == 1 and cfg[1].payload[1] == 3 and u16(cfg[1].payload, 16) == 1)

-- Arming lets go of everything
before = #sent
session({connected = true, isArmed = true, apiVersionMajor = 22, apiVersionMinor = 14})
check("arming releases the held axes", lastMixer(before + 1, 2) and lastMixer(before + 1, 2).value == 2501)
tick()
check("arming says why", (function()
  for _, f in ipairs(fields) do if f.kind == "static" and f.text == T("armed") then return true end end
end)())
check("the answers are greyed out while armed", not button(T("dir_like")).enabled)
before = #sent
tick(1)
check("nothing moves while armed", #writesOf(191, before + 1) == 0)
session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
tick()
tick(1)
check("disarming starts the check moving again", #mixerWrites(before + 1, 3) >= 1)

-- Done
press(T("dir_like"))
local summary = paint()
check("the summary lists what changed",
  summary:find(T("dir_done_changes"), 1, true) and summary:find(T("dir_change_servo_fmt"), 1, true)
  and summary:find(T("dir_change_axis_fmt"), 1, true), summary)
check("and moves nothing", lastMixer(1, 1).value == 2501 and lastMixer(1, 2).value == 2501)
before = #sent
press(T("dir_save_finish"))
check("Save and finish writes EEPROM", #writesOf(250, before + 1) == 1)
tick()
check("then leaves the wizard", ctx.back == 1)
local release = writesOf(0x5F1B, before + 1)
check("leaving releases the setup state", #release == 1 and bytes(release[1].payload) == "0,0,0")
check("nothing is held after leaving", not requireModule("lib/override_keepalive.lua").isActive("mode_override"))

-- Discard writes back what was loaded ----------------------------------------

openPage(14)
press(T("dir_start"))
press(T("dir_like"))
press(T("dir_unlike"))
press(T("dir_all"))
headers[#headers].opts.onBack()
tick()
local d = dialogs[#dialogs]
check("Back with unsaved changes asks", d and d.opts.title == T("leave_title") and #d.opts.buttons == 3)
before = #sent
d.opts.buttons[2].action()
local restored = writesOf(171, before + 1)
check("Discard writes roll's axis throw back", #restored == 1 and s16(restored[1].payload, 2) == 1000)
check("and leaves", ctx.back == 1 and ctx.wakeup == nil)

-- A flying wing: a surface that also works another axis ---------------------

do
  local mixerRules = requireModule("lib/msp_mixer_rules.lua")
  local pool = {}
  local wing = {
    {oper = 1, input = 2, output = 1, weight = 1000, weightNeg = 1000},
    {oper = 2, input = 1, output = 1, weight = 1000, weightNeg = 1000},
    {oper = 1, input = 2, output = 2, weight = 1000, weightNeg = 1000},
    {oper = 2, input = 1, output = 2, weight = -1000, weightNeg = -1000},
  }
  for i = 1, mixerRules.RULE_COUNT do
    local p = mixerRules.encodeRule(i - 1, wing[i])
    for b = 2, #p do pool[#pool + 1] = p[b] end
  end
  replies[172] = pool
end
openPage(14)
press(T("dir_start"))
check("a flying wing starts on pitch", shows("dir_check_pitch"))
press(T("dir_like"))
press(T("dir_unlike"))
press(T("dir_some"))
press(T("dir_yes"))
before = #sent
press(T("dir_no"))
check("an elevon wrong on roll alone is not reversed", #writesOf(212, before + 1) == 0)
check("the wizard says why", shows("dir_cant_fix_fmt"))
press(T("dir_continue"))
check("then checks roll again", shows("dir_check_roll") and shows("dir_status_none"))
replies[172] = nil
headers[#headers].opts.onBack()

check("no form was built from a reply or a bus event", #forbidden == 0, table.concat(forbidden, ","))

-- Older firmware: explain and stop -------------------------------------------

openPage(13)
check("22.13: no setup state requested", #writesOf(0x5F1B) == 0)
check("22.13: no override sent", #writesOf(191) == 0 and #writesOf(196) == 0)
local explained = false
for _, f in ipairs(fields) do
  if f.kind == "static" and f.text and f.text:find("needs_firmware", 1, true) then explained = true end
end
check("22.13: the page says why", explained)

print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
