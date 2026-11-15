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
local drawnColor = {}   -- text -> the colour it was drawn in
local currentColor = nil
_G.FONT_S, _G.FONT_STD, _G.FONT_XS = 20, 25, 10
_G.LEFT, _G.CENTERED, _G.RIGHT, _G.TEXT_LEFT = 3, 4, 5, 2
_G.lcd = {
  getWindowSize = function() return 480, 290 end,
  loadMask = function(path) return path end,
  font = function() end,
  getTextSize = function(text) return #text * 8, 18 end,
  darkMode = function() return true end,
  GREY = function(v) return v end,
  RGB = function(r) return r end,
  color = function(c) currentColor = c end,
  invalidate = function() end,
  drawText = function(_, _, text) drawn[#drawn + 1] = text; drawnColor[text] = currentColor end,
  drawFilledRectangle = function() end,
  drawFilledTriangle = function() end,
  drawFilledCircle = function() end,
  drawLine = function() end,
  setClipping = function() end,
  drawRectangle = function() end,
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
local ICON_LABEL = {
  ["app/gfx/nav/prev.png"] = "@i18n(app.modules.setup_wizard.btn_back)@",
  ["app/gfx/nav/next.png"] = "@i18n(app.modules.setup_wizard.btn_next)@",
}
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
  addButton = function(line, rect, opts)
    foreground("addButton")
    -- Icon-only buttons (the row's Back and Next) are found by what they mean.
    return newField("button", {line = line, text = opts.text or ICON_LABEL[opts.icon], icon = opts.icon,
      press = opts.press, rect = rect})
  end,
  addChoiceField = function(line, rect, values, get, set)
    foreground("addChoiceField")
    return newField("choice", {line = line, rect = rect, values = values, get = get, set = set})
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
local progressDialogs = {}
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
    open = function(opts)
      local d = {title = opts.title, text = opts.message, values = {}, closed = false}
      function d.value(_, v) d.values[#d.values + 1] = v end
      function d.message(_, text) d.text = text end
      function d.close() d.closed = true end
      progressDialogs[#progressDialogs + 1] = d
      return d
    end,
  },
  ["app/close_key.lua"] = {shouldHandleClose = function() return false end},
}

-- Cached in package.loaded under lib/require.lua's keys, so the checks can see
-- what the wizard frees when a step or the page closes.
local cache = package.loaded
local function keyOf(path) return "wfsuite." .. path:gsub("%.lua$", ""):gsub("/", ".") end
package.loaded["wfsuite.lib.require"] = function(path)
  if stubs[path] then return stubs[path] end
  local key = keyOf(path)
  if cache[key] == nil then
    local result = assert(realLoadfile(ROOT .. path))()
    cache[key] = result == nil and true or result
  end
  return cache[key]
end
local requireModule = package.loaded["wfsuite.lib.require"]

local function session(data)
  inBackground = true
  for _, fn in ipairs(subscribers["session.update"] or {}) do fn(data) end
  inBackground = false
end

-- Replies by command, overriding the codec's simulator reply.
local replies = {}

-- Commands whose replies are held back until releaseHeld(command), to put one
-- read's reply after another's.
local held, heldMessages = {}, {}

local function deliver(m)
  if not m.processReply then return end
  local buf = {}
  local reply = replies[m.command]
  if type(reply) == "function" then reply = reply(m) end
  for i, b in ipairs(reply or m.simulatorResponse or {}) do buf[i] = b end
  m.processReply(nil, buf)
end

local answeredUpTo = 0
local function answerAll()
  inBackground = true
  while answeredUpTo < #sent do
    answeredUpTo = answeredUpTo + 1
    local m = sent[answeredUpTo]
    if held[m.command] then
      heldMessages[#heldMessages + 1] = m
    else
      deliver(m)
    end
  end
  inBackground = false
end

local function releaseHeld(command)
  held[command] = nil
  inBackground = true
  for i = 1, #heldMessages do
    if heldMessages[i].command == command then deliver(heldMessages[i]) end
  end
  inBackground = false
  heldMessages = {}
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

-- The rotary encoder visits fields in the order they are made: the buttons
-- must be made in screen order, top to bottom and then left to right.
local function inScreenOrder()
  local prev
  for _, f in ipairs(fields) do
    if f.kind == "button" and f.rect then
      if prev then
        local sameRow = math.abs(f.rect.y - prev.rect.y) <= 2
        if not ((sameRow and f.rect.x > prev.rect.x) or (not sameRow and f.rect.y > prev.rect.y)) then
          return false, tostring(prev.text) .. " @" .. prev.rect.x .. "," .. prev.rect.y
            .. " before " .. tostring(f.text) .. " @" .. f.rect.x .. "," .. f.rect.y
        end
      end
      prev = f
    end
  end
  return true
end

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

local function openPage(apiMinor, stepKey)
  fields, dialogs, sent, headers = {}, {}, {}, {}
  answeredUpTo = 0
  heldMessages = {}
  subscribers["session.update"] = nil
  for k in pairs(package.loaded) do
    if type(k) == "string" and k:match("^wfsuite%.") and k ~= "wfsuite.lib.require" then package.loaded[k] = nil end
  end
  -- Where the wizard opens: the step it remembers (app/pages/setup_wizard.lua).
  package.loaded["wfsuite.setup_wizard.memory"] = {stepKey = stepKey or "direction"}
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
check("the title names the step", headers[#headers].title == T("name") .. " / 9. " .. T("step_direction"),
  headers[#headers].title)
check("the step-list button shows the checklist icon",
  headers[#headers].opts.toolIcon == "app/gfx/nav/steps.png" and headers[#headers].opts.onTool ~= nil)
do
  local icon = io.open(ROOT .. "app/gfx/nav/steps.png", "rb")
  check("and that icon is in the suite", icon ~= nil)
  if icon then icon:close() end
end
check("it opens on the intro, which moves nothing", shows("dir_intro") and #writesOf(191) == 4)
local start = button(T("dir_start"))
check("the intro's only answer is Start, and it has the focus", start and start.focused)

-- Pitch: the first check for this mix (no flaps)
local before = #sent
press(T("dir_start"))
check("Start opens the pitch check", shows("dir_check_pitch") and shows("dir_q_match"))
check("the check being done stands out in the accent colour, with its progress",
  drawnColor[T("dir_check_pitch")] == 255 and drawnColor[T("progress_fmt")] ~= 255
  and drawnColor[T("progress_fmt")] ~= nil)
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
  #cfg == 1 and cfg[1].payload[1] == 0 and #cfg[1].payload == 15 and u16(cfg[1].payload, 14) == 1,
  cfg[1] and bytes(cfg[1].payload))
check("and roll is checked again", shows("dir_check_roll") and shows("dir_status_reversed_fmt"))

-- Yaw: a single rudder the wrong way is reversed straight away
press(T("dir_like"))
check("roll done, on to yaw", shows("dir_check_yaw"))
before = #sent
press(T("dir_unlike"))
cfg = writesOf(212, before + 1)
check("one surface wrong on its own axis: its servo is reversed",
  #cfg == 1 and cfg[1].payload[1] == 3 and #cfg[1].payload == 15 and u16(cfg[1].payload, 14) == 1)

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
press(T("dir_save_next"))
check("Save and continue writes EEPROM", #writesOf(250, before + 1) == 1)
tick()
tick()
check("then opens the next step, Binding limits",
  headers[#headers].title == T("name") .. " / 10. " .. T("step_limits"), headers[#headers].title)
check("with nothing left pending", headers[#headers].saveEnabled == false)
before = #sent
headers[#headers].opts.onBack()
check("Back with nothing pending leaves the wizard", ctx.back == 1)
local release = writesOf(0x5F1B, before + 1)
check("leaving releases the setup state", #release == 1 and bytes(release[1].payload) == "0,0,0")
check("leaving frees the wizard's own modules but keeps the override ones",
  package.loaded["wfsuite.lib.msp_mixer_rules"] == nil and package.loaded["wfsuite.app.setup_wizard_ui"] == nil
  and package.loaded["wfsuite.app.plane3d"] == nil
  and package.loaded["wfsuite.lib.msp_servo_config"] == nil and package.loaded["wfsuite.lib.msp_mixer_override"] ~= nil)
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
press(T("btn_next"))
check("then checks roll again", shows("dir_check_roll") and shows("dir_status_none"))
replies[172] = nil
headers[#headers].opts.onBack()

-- The other steps -------------------------------------------------------------
--
-- Each opened on its own (the wizard reopens on the step it remembers) and
-- driven through its main path, checking what reaches the wire.

local function settle(n)
  for _ = 1, n or 3 do tick() end
end

-- Leaves the step through the step list and opens step `n` from it: a new
-- instance of the step, in the same visit to the wizard.
local function reopenStep(n, key)
  headers[#headers].opts.onTool()
  tick()
  press(n .. ". " .. T("step_" .. key))
  settle()
end

-- Leaves the wizard, discarding what is not saved.
local function discardAll()
  headers[#headers].opts.onBack()
  tick()
  local discard
  for _, b in ipairs(dialogs[#dialogs].opts.buttons) do
    if b.label == T("leave_discard") then discard = b end
  end
  discard.action()
  tick()
end
local function u16list(values)
  local out = {}
  for i, v in ipairs(values) do out[2 * i - 1] = v % 256; out[2 * i] = math.floor(v / 256) end
  return out
end
local function s16bytes(v) if v < 0 then v = v + 65536 end return v % 256, math.floor(v / 256) end

-- Sensors: calibrate, auto orientation, auto level, then save and restart.
openPage(14, "sensors")
settle()
check("sensors: opens on its intro", shows("sen_intro"))
check("sensors: the board has an accelerometer (sensor_status bit 0)", not shows("sen_no_acc"))
press(T("btn_start"))
before = #sent
press(T("sen_calibrate"))
check("sensors: Calibrate sends MSP_ACC_CALIBRATION", #writesOf(205, before + 1) == 1)
for _ = 1, 5 do tick(1) end
check("sensors: calibration done once the FC is no longer calibrating", shows("sen_acc_done"))
press(T("btn_next"))
replies[0x5F00] = function(m)
  if m.payload then return {1, 0, 0, 0, 0, 0, 0, 0} end
  return {2, 0, 0, 0, 0, 90, 0, 5}   -- SUCCESS, yaw 90
end
before = #sent
press(T("btn_start"))
settle()
local align = writesOf(39, before + 1)
check("sensors: auto orientation writes the board alignment",
  #align == 1 and bytes(align[1].payload) == "0,0,0,0,90,0", align[1] and bytes(align[1].payload))
press(T("btn_next"))
check("sensors: then shows the live orientation check", shows("sen_check_text"))
before = #sent
for _ = 1, 3 do tick(0.5) end
local attitudeReads = 0
for i = before + 1, #sent do
  if sent[i].command == 108 then attitudeReads = attitudeReads + 1 end
end
check("sensors: the check polls MSP_ATTITUDE", attitudeReads >= 2, attitudeReads)
press(T("btn_next"))
replies[0x5F05] = function(m)
  if m.payload then return {1, 0, 0, 0, 0, 0} end
  local r1, r2 = s16bytes(15)
  local p1, p2 = s16bytes(-20)
  return {2, r1, r2, p1, p2, 100}  -- SUCCESS, roll 1.5, pitch -2.0 deg
end
before = #sent
press(T("btn_start"))
settle()
local trimWrites = writesOf(0x5F04, before + 1)
check("sensors: auto level writes the mount trim, yaw kept",
  #trimWrites == 1 and bytes(trimWrites[1].payload) == "15,0,236,255,0,0", trimWrites[1] and bytes(trimWrites[1].payload))
press(T("btn_next"))
check("sensors: ends with a restart", shows("sen_done_restart"))
before = #sent
press(T("btn_save_restart"))
tick()
tick()
check("sensors: Save and restart saves, then restarts the FC",
  #writesOf(250, before + 1) == 1 and #writesOf(68, before + 1) == 1)
local restartDialog = progressDialogs[#progressDialogs]
check("sensors: the restart shows a progress dialog with the countdown",
  restartDialog and restartDialog.title == "@i18n(app.msg_restarting)@"
  and restartDialog.text == T("reboot_wait_fmt") and not restartDialog.closed,
  restartDialog and tostring(restartDialog.title) .. " " .. tostring(restartDialog.text))
check("sensors: the step's own modules are freed when it closes",
  package.loaded["wfsuite.lib.msp_board_mount_trim"] == nil and package.loaded["wfsuite.lib.msp_acc_calibration"] == nil
  and package.loaded["wfsuite.lib.acc_calibration_wait"] == nil
  and package.loaded["wfsuite.lib.msp_attitude"] == nil)
tick(3)
check("sensors: the bar fills while the FC restarts",
  restartDialog and (restartDialog.values[#restartDialog.values] or 0) >= 10,
  restartDialog and table.concat(restartDialog.values, ","))
session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
tick()
session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14, handshake = {apiVersion = true}})
before = #sent
settle(6)
check("sensors: after the restart the wizard reloads and reopens the step",
  #writesOf(101, before + 1) >= 1 and headers[#headers].title == T("name") .. " / 1. " .. T("step_sensors"),
  headers[#headers].title)
check("sensors: the restart dialog closes once the FC is back", restartDialog and restartDialog.closed)
replies[0x5F00], replies[0x5F05] = nil, nil

-- Receiver: detect the channel order from the sticks.
do
  local raw = {1500, 1500, 1500, 1000, 1000, 1000, 1000, 1000}
  replies[114] = function() return u16list(raw) end
  openPage(14, "receiver")
  settle()
  check("receiver: the check screen", shows("rx_check"))
  press(T("rx_wrong"))
  check("receiver: asks for throttle first", shows("rx_move_throttle"))
  local function move(channel)
    raw[channel + 1] = 2000
    tick(0.3)
    tick(0.3)
    tick(0.3)
  end
  move(2)
  check("receiver: then roll", shows("rx_move_roll"))
  move(1)
  move(0)
  before = #sent
  move(3)
  local map = writesOf(65, before + 1)
  check("receiver: the detected order is written",
    #map == 1 and bytes(map[1].payload) == "1,0,3,2,4,5,6,7", map[1] and bytes(map[1].payload))
  replies[114] = nil
end

-- Airframe: a flying wing replaces the mix.
openPage(14, "airframe")
settle()
press(T("air_change"))
do
  -- The choice grid sits on the button row whatever the text above it, so a
  -- status line that comes or goes never moves it.
  local rowY, gridBottom = 0, 0
  for _, f in ipairs(fields) do
    if f.kind == "button" and f.rect and f.rect.y > rowY then rowY = f.rect.y end
  end
  for _, f in ipairs(fields) do
    if f.kind == "button" and f.rect and f.rect.y < rowY then
      gridBottom = math.max(gridBottom, f.rect.y + f.rect.h)
    end
  end
  check("airframe: the type grid sits on the button row", rowY - gridBottom == 8, rowY .. " " .. gridBottom)
  check("airframe: the encoder goes through the grid, then Back", inScreenOrder())
end
press(T("air_type_flying_wing"))
check("airframe: asks about a rudder", shows("air_q_wing_yaw"))
press(T("air_none"))
check("airframe: then flaps", shows("air_q_flaps"))
press(T("air_none"))
press("1")
check("airframe: reviews before applying", shows("air_review_fmt"))
before = #sent
press(T("air_apply"))
local ruleWrites = writesOf(173, before + 1)
local cfgWrites = writesOf(43, before + 1)
check("airframe: every rule slot is written", #ruleWrites == 32
  and bytes({table.unpack(ruleWrites[1].payload, 1, 4)}) == "0,1,2,1", ruleWrites[1] and bytes(ruleWrites[1].payload))
-- The two-byte short form: the bus channel counts and the PWM rate are left alone.
check("airframe: the model type is flying wing, and nothing else is written with it",
  #cfgWrites == 1 and bytes(cfgWrites[1].payload) == "1,0", cfgWrites[1] and bytes(cfgWrites[1].payload))
check("airframe: the surfaces are elevons now", shows("surface_elevon"))

-- Servo type: digital sets the one PWM rate, then save and restart.
openPage(14, "servotype")
settle()
check("servo type: analog and digital are offered",
  button(T("st_analog")) ~= nil and button(T("st_digital")) ~= nil)
before = #sent
press(T("st_digital"))
local st = writesOf(43, before + 1)
-- MSP_SET_MIXER_CONFIG, long form, with what the page read when it opened:
-- model type 0, reserved 0, SBUS 16, F.Bus 24, then rate 333 = 77 + 1 * 256.
check("servo type: digital writes the PWM rate, 333 Hz, with the bus channel counts as read",
  #st == 1 and bytes(st[1].payload) == "0,0,16,24,77,1", st[1] and bytes(st[1].payload))
check("servo type: no servo's centre, limits or scale is written", #writesOf(212, before + 1) == 0)
before = #sent
press(T("btn_save_restart"))
tick()
tick()
check("servo type: saves and restarts", #writesOf(250, before + 1) == 1 and #writesOf(68, before + 1) == 1)

-- Servo bus: F.Bus on the SBUS connector with the pin swap, then SBUS, then
-- save and restart. The board is an F7C5 (Nexus X), where UART1 is "S.BUS".
do
  local info = {87, 71, 70, 76, 0, 0, 0, 0, 0, 0, 4}
  for _, b in ipairs({string.byte("F7C5", 1, -1)}) do info[#info + 1] = b end
  replies[4] = info
end
openPage(14, "busoutput")
settle()
check("servo bus: opens on the port question", shows("bus_title") and button(T("bus_none")) ~= nil)
check("servo bus: the ports carry the board's connector names", button("S.BUS") ~= nil and button("TELEM") ~= nil)
before = #sent
press("S.BUS")
local busPorts = writesOf(55, before + 1)
-- MSP_SET_SERIAL_CONFIG for UART1: FUNCTION_FBUS_MASTER is 1 << 19, so byte 3 of the mask is 8.
check("servo bus: a new port gets F.Bus",
  #busPorts == 1 and bytes(busPorts[1].payload) == "0,0,0,8,0,0,0,0,0", busPorts[1] and bytes(busPorts[1].payload))
local busWiring = writesOf(0x5F0A, before + 1)
-- The eight forwarding slots as read, then pin swap on and inverted as read.
check("servo bus: the SBUS connector turns the pin swap on",
  #busWiring == 1 and bytes(busWiring[1].payload) == "255,255,255,255,255,255,255,255,1,1",
  busWiring[1] and bytes(busWiring[1].payload))
check("servo bus: then asks for the protocol", shows("bus_proto_title"))
before = #sent
press("SBUS")
busPorts = writesOf(55, before + 1)
-- FUNCTION_SBUS_OUT is 1 << 18.
check("servo bus: SBUS replaces F.Bus on the same port",
  #busPorts == 1 and bytes(busPorts[1].payload) == "0,0,0,4,0,0,0,0,0", busPorts[1] and bytes(busPorts[1].payload))
check("servo bus: the pin is an F.Bus setting, so SBUS leaves it", #writesOf(0x5F0A, before + 1) == 0)
before = #sent
press(T("btn_save_restart"))
tick()
tick()
check("servo bus: saves and restarts", #writesOf(250, before + 1) == 1 and #writesOf(68, before + 1) == 1)
replies[4] = nil

-- Servo bus: Detect wiring on the signal screen. F.Bus is on UART1, as booted;
-- the wiring read is the simulator's: pin swap off, inverted.
do
  local TRIAL = 0x5F37
  -- FUNCTION_FBUS_MASTER is 1 << 19: byte 3 of UART1's function mask.
  replies[54] = function(m)
    local out = {}
    for i, b in ipairs(m.simulatorResponse) do out[i] = b end
    out[4] = 8
    return out
  end
  local polls, answer = 0, nil
  -- state, wiring tried, wirings, pin swap, inverted, valid frames (U16), port open
  local RUNNING = {1, 1, 4, 1, 1, 0, 0, 1}
  local function trialReplies()
    replies[TRIAL] = function(m)
      local action = m.payload[1]
      if action == 1 then return {1, 0, 4, 0, 1, 0, 0, 1} end   -- RUNNING, wiring 1 of 4
      if action == 2 then return {0, 0, 4, 0, 1, 0, 0, 1} end   -- IDLE
      polls = polls + 1
      if polls < 3 then return RUNNING end                      -- RUNNING, wiring 2 of 4
      return answer
    end
  end
  local function actions(from)
    local out = {}
    for _, m in ipairs(writesOf(TRIAL, from)) do out[#out + 1] = m.payload[1] end
    return out
  end
  local function stops(from)
    local n = 0
    for _, action in ipairs(actions(from)) do if action == 2 then n = n + 1 end end
    return n
  end
  local function toSignal()
    openPage(14, "busoutput")
    settle()
    press("UART1")
    press(T("btn_next"))
    -- The device count is read every 2 s and shown from the second read; the
    -- screen is rebuilt on the next wakeup.
    tick()
    tick(2.1)
    tick()
  end
  local function saveEnabled() return headers[#headers].saveEnabled == true end

  trialReplies()
  toSignal()
  check("servo bus: the signal screen offers Detect wiring, not Use the other pin",
    shows("bus_signal_title") and shows("bus_tx_pin_fmt") and button(T("esc_detect")) ~= nil
      and button(T("esc_detect")).enabled and button(T("bus_other_pin")) == nil)
  check("servo bus: with nothing answering it points to Detect wiring", shows("bus_no_answer_detect"))

  -- A device answers on the other pin.
  polls, answer = 0, {2, 1, 4, 1, 1, 3, 0, 1}   -- SUCCESS: pin swap on, inverted
  before = #sent
  press(T("esc_detect"))
  check("servo bus: Detect wiring starts the trial", actions(before + 1)[1] == 1, actions(before + 1)[1])
  check("servo bus: while it runs it says which wiring, Stop is offered and Next waits",
    shows("esc_trying_fmt") and button(T("esc_stop")) ~= nil and button(T("esc_detect")) == nil
      and not button(T("btn_next")).enabled)
  local inFlightOk, countReads = true, 0
  local sensorsCommand = requireModule("lib/msp_fbus_sensors.lua").READ_COMMAND
  for _ = 1, 6 do
    -- One request in flight: never a second poll before the first is answered.
    if #sent - answeredUpTo > 1 then inFlightOk = false end
    if button(T("esc_stop")) then countReads = #writesOf(sensorsCommand, before + 1) end
    tick(0.7)
  end
  check("servo bus: the trial is polled one request at a time", polls == 3 and inFlightOk, polls)
  check("servo bus: no device count is read while the trial runs", countReads == 0, countReads)
  check("servo bus: a new wiring is shown as found, on the RX pin",
    shows("bus_found") and shows("bus_rx_pin_fmt") and not shows("bus_tx_pin_fmt"))
  check("servo bus: the found wiring is already live: nothing is written, stopped or restarted",
    #writesOf(0x5F0A, before + 1) == 0 and stops(before + 1) == 0 and #writesOf(68, before + 1) == 0
      and #writesOf(250, before + 1) == 0)
  check("servo bus: the wizard is left pending: Save and continue, no Save and restart",
    saveEnabled() and button(T("dir_save_next")) ~= nil and button(T("btn_save_restart")) == nil
      and button(T("esc_detect")).enabled)
  before = #sent
  tick(1)
  check("servo bus: no polling once the trial has ended", #actions(before + 1) == 0)
  before = #sent
  press(T("dir_save_next"))
  tick()
  tick()
  check("servo bus: Save and continue saves, without a restart or a stop, and opens the next step",
    #writesOf(250, before + 1) == 1 and #writesOf(68, before + 1) == 0 and stops(before + 1) == 0
      and headers[#headers].title == T("name") .. " / 4. " .. T("step_airframe"), headers[#headers].title)

  -- Discard puts the old wiring back with a config write, not a stop.
  toSignal()
  polls = 2
  press(T("esc_detect"))
  settle()
  check("servo bus: found again", shows("bus_found") and saveEnabled())
  before = #sent
  headers[#headers].opts.onBack()
  tick()
  local discard
  for _, b in ipairs(dialogs[#dialogs].opts.buttons) do
    if b.label == T("leave_discard") then discard = b end
  end
  discard.action()
  tick()
  local wiringWrites = writesOf(0x5F0A, before + 1)
  check("servo bus: Discard writes the old wiring back and sends no stop",
    #wiringWrites == 1 and bytes(wiringWrites[1].payload) == "255,255,255,255,255,255,255,255,0,1"
      and stops(before + 1) == 0 and ctx.back == 1, wiringWrites[1] and bytes(wiringWrites[1].payload))

  -- The wiring already set answers: nothing to save.
  toSignal()
  polls, answer = 2, {2, 0, 4, 0, 1, 3, 0, 1}
  before = #sent
  press(T("esc_detect"))
  settle()
  check("servo bus: the wiring already set answers, so there is nothing to save",
    shows("bus_wiring_ok") and shows("bus_tx_pin_fmt") and not saveEnabled() and button(T("btn_next")) ~= nil
      and button(T("dir_save_next")) == nil and #writesOf(0x5F0A, before + 1) == 0 and stops(before + 1) == 0)

  -- Nothing answers on any wiring; a trial the flight controller refuses.
  polls, answer = 2, {3, 3, 4, 0, 1, 0, 0, 1}
  press(T("esc_detect"))
  settle()
  check("servo bus: no answer on any wiring says so",
    shows("bus_not_found") and button(T("esc_detect")).enabled and not saveEnabled())
  polls, answer = 2, {4, 0, 4, 0, 1, 0, 0, 1}
  press(T("esc_detect"))
  settle()
  check("servo bus: a refused trial says the flight controller cannot test now",
    shows("bus_rejected") and button(T("esc_detect")).enabled and not saveEnabled())

  -- A run that never ends is given up, with a stop.
  polls, answer = -100000, nil
  before = #sent
  press(T("esc_detect"))
  for _ = 1, 30 do tick() end   -- 9 s
  check("servo bus: still trying at 9 s", shows("esc_trying_fmt") and stops(before + 1) == 0)
  for _ = 1, 6 do tick() end
  check("servo bus: given up after 10 s, with a stop",
    shows("bus_not_found") and stops(before + 1) == 1 and button(T("esc_detect")) ~= nil)

  -- Back, the step list, arming, a lost link and leaving stop a run.
  local function running()
    press(T("esc_detect"))
    before = #sent
  end
  local function stopped()
    local a = actions(before + 1)
    return a[#a] == 2
  end
  running()
  press(T("esc_stop"))
  check("servo bus: Stop stops a running trial", stopped() and shows("esc_stopped") and button(T("esc_detect")) ~= nil)
  running()
  press(T("btn_back"))
  check("servo bus: Back stops a running trial", stopped() and shows("bus_proto_title"))
  press(T("btn_next"))
  running()
  headers[#headers].opts.onTool()
  tick()
  check("servo bus: the step list stops a running trial", stopped())
  headers[#headers].opts.onBack()
  tick()
  running()
  session({connected = true, isArmed = true, apiVersionMajor = 22, apiVersionMinor = 14})
  check("servo bus: arming stops a running trial", stopped())
  tick()
  check("servo bus: and Detect wiring is off while armed", not button(T("esc_detect")).enabled)
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  running()
  session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  check("servo bus: a lost link stops a running trial", stopped())
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  running()
  headers[#headers].opts.onBack()
  tick()
  check("servo bus: leaving the wizard stops a running trial", stopped() and ctx.back == 1)

  -- Firmware without the command answers the start with no payload: the pin
  -- is switched by hand, which needs a restart.
  replies[TRIAL] = {}
  toSignal()
  before = #sent
  press(T("esc_detect"))
  settle()
  check("servo bus: an empty reply falls back to Use the other pin",
    button(T("bus_other_pin")) ~= nil and button(T("esc_detect")) == nil and stops(before + 1) == 0
      and #actions(before + 1) == 1 and not saveEnabled())
  tick(2.1)
  tick(2.1)
  tick()
  check("servo bus: and the status no longer points to Detect wiring",
    shows("bus_no_answer") and not shows("bus_no_answer_detect"))
  before = #sent
  press(T("bus_other_pin"))
  wiringWrites = writesOf(0x5F0A, before + 1)
  check("servo bus: Use the other pin writes the pin swap and asks for Save and restart",
    #wiringWrites == 1 and bytes(wiringWrites[1].payload) == "255,255,255,255,255,255,255,255,1,1"
      and shows("bus_changed") and button(T("btn_save_restart")) ~= nil,
    wiringWrites[1] and bytes(wiringWrites[1].payload))
  before = #sent
  press(T("btn_save_restart"))
  tick()
  tick()
  session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14, handshake = {apiVersion = true}})
  settle(6)
  check("servo bus: after that restart the step reopens on the signal screen, still with Use the other pin",
    #writesOf(68, before + 1) == 1 and shows("bus_signal_title") and button(T("bus_other_pin")) ~= nil
      and button(T("esc_detect")) == nil)

  -- An MSP error to the start is that firmware too.
  replies[TRIAL] = function() return {1, 0, 4, 0, 1, 0, 0, 1} end
  toSignal()
  local m
  do
    local b = button(T("esc_detect"))
    b.press()
    m = sent[#sent]
    answeredUpTo = #sent
    inBackground = true
    m.errorHandler(true)
    inBackground = false
    settle()
  end
  check("servo bus: an MSP error to the start falls back to Use the other pin",
    m.command == TRIAL and button(T("bus_other_pin")) ~= nil and button(T("esc_detect")) == nil)
  -- A start that times out is not: Detect wiring stays.
  toSignal()
  do
    local b = button(T("esc_detect"))
    b.press()
    m = sent[#sent]
    answeredUpTo = #sent
    inBackground = true
    m.errorHandler("timeout")
    inBackground = false
    settle()
  end
  check("servo bus: a start that times out says so and keeps Detect wiring",
    shows("esc_no_reply") and button(T("esc_detect")) ~= nil and button(T("bus_other_pin")) == nil)

  replies[TRIAL] = nil
  check("servo bus: nothing built a form from a trial reply", #forbidden == 0, table.concat(forbidden, ","))

  -- "N answering" counts only the devices that answered since the read
  -- before: the flight controller lists every device it has ever heard.
  local packets = 10
  -- One device: physical ID 5, on F.Bus, not forwarded, packet count (U32), no name, no app IDs.
  replies[0x5F07] = function() return {1, 5, 0, 0, packets % 256, packets // 256, 0, 0, 0, 0} end
  openPage(14, "busoutput")
  settle()
  press("UART1")
  press(T("btn_next"))
  tick()
  tick()
  check("servo bus: the first read cannot tell whether a listed device still answers, so it shows no count",
    #writesOf(0x5F07) == 1 and not shows("bus_answering_fmt") and not shows("bus_no_answer_detect"),
    #writesOf(0x5F07))
  packets = 400
  tick(2.1)
  tick()
  check("servo bus: a device whose packet count rose is answering", shows("bus_answering_fmt"))
  tick(2.1)
  tick()
  check("servo bus: a device still listed whose packet count stands still is not",
    shows("bus_no_answer_detect") and not shows("bus_answering_fmt"))
  packets = 401
  tick(2.1)
  tick()
  check("servo bus: and it counts again once it answers", shows("bus_answering_fmt"))
  replies[0x5F07], replies[54] = nil, nil
end

-- Servo bus: the reads may answer in any order, and the step may be closed
-- and opened again before a restart.
do
  local info = {87, 71, 70, 76, 0, 0, 0, 0, 0, 0, 4}
  for _, b in ipairs({string.byte("F7C5", 1, -1)}) do info[#info + 1] = b end
  replies[4] = info
  local SWAPPED = "255,255,255,255,255,255,255,255,1,1"
  local AS_READ = "255,255,255,255,255,255,255,255,0,1"

  -- The serial ports answer before the wiring: no port can be chosen yet.
  held[0x5F09] = true
  openPage(14, "busoutput")
  settle()
  check("servo bus: no port is offered before the wiring has been read",
    button("S.BUS") == nil and button(T("bus_none")) == nil and #heldMessages == 1)
  releaseHeld(0x5F09)
  settle()
  before = #sent
  press("S.BUS")
  local wiringWrites = writesOf(0x5F0A, before + 1)
  check("servo bus: once it has, the SBUS connector still gets the pin swap",
    #wiringWrites == 1 and bytes(wiringWrites[1].payload) == SWAPPED,
    wiringWrites[1] and bytes(wiringWrites[1].payload))
  before = #sent
  discardAll()
  wiringWrites = writesOf(0x5F0A, before + 1)
  check("servo bus: and Discard puts back the wiring that was read",
    #wiringWrites == 1 and bytes(wiringWrites[1].payload) == AS_READ,
    wiringWrites[1] and bytes(wiringWrites[1].payload))

  -- The same for the connector names: without them the SBUS connector is not known.
  held[4] = true
  openPage(14, "busoutput")
  settle()
  check("servo bus: no port is offered before the board has been read",
    button("UART1") == nil and button("S.BUS") == nil and button(T("bus_none")) == nil)
  releaseHeld(4)
  settle()
  check("servo bus: then the ports carry the connector names", button("S.BUS") ~= nil and button("UART1") == nil)
  -- A wiring read that fails still lets the step go on, with the pin left alone.
  held[0x5F09] = true
  openPage(14, "busoutput")
  settle()
  do
    local m = heldMessages[1]
    held[0x5F09], heldMessages = nil, {}
    inBackground = true
    m.errorHandler("timeout")
    inBackground = false
    settle()
  end
  before = #sent
  press("S.BUS")
  check("servo bus: a wiring read that fails still offers the ports, and leaves the pin alone",
    #writesOf(55, before + 1) == 1 and #writesOf(0x5F0A, before + 1) == 0)

  -- A change that needs a restart is still owed after the step is closed
  -- and opened again. The flight controller holds F.Bus on UART1 by then.
  local function masks(list)
    replies[54] = function(m)
      local out = {}
      for i, b in ipairs(m.simulatorResponse) do out[i] = b end
      for index, mask in pairs(list) do out[(index - 1) * 9 + 4] = mask end
      return out
    end
  end
  openPage(14, "busoutput")
  settle()
  press("S.BUS")
  check("servo bus: a new port asks for Save and restart", button(T("btn_save_restart")) ~= nil)
  masks({[1] = 8})
  reopenStep(3, "busoutput")
  check("servo bus: closed and opened again, the step still asks for Save and restart",
    shows("bus_title") and button(T("btn_save_restart")) ~= nil)
  press("S.BUS")
  check("servo bus: and there is no way to the signal screen before it",
    shows("bus_proto_title") and shows("bus_changed") and button(T("btn_save_restart")) ~= nil
      and button(T("btn_next")) == nil)
  press(T("btn_back"))

  -- Discard after that: the undo is the first instance's, and every port
  -- goes back as it was, also the one the second instance chose.
  before = #sent
  press("TELEM")
  local moved = writesOf(55, before + 1)
  check("servo bus: the reopened step moves the bus to another port",
    #moved == 2 and bytes(moved[1].payload) == "0,0,0,0,0,0,0,0,0" and bytes(moved[2].payload) == "1,0,0,8,0,0,0,0,0",
    moved[2] and bytes(moved[2].payload))
  before = #sent
  discardAll()
  do
    local cleared, wrong = {}, 0
    for _, m in ipairs(writesOf(55, before + 1)) do
      local pl = m.payload
      if pl[2] + pl[3] + pl[4] + pl[5] == 0 then cleared[pl[1]] = true else wrong = wrong + 1 end
    end
    wiringWrites = writesOf(0x5F0A, before + 1)
    check("servo bus: Discard clears the bus from both ports and puts the wiring back",
      cleared[0] and cleared[1] and wrong == 0 and #wiringWrites == 1
        and bytes(wiringWrites[1].payload) == AS_READ and ctx.back == 1,
      wrong .. " / " .. (wiringWrites[1] and bytes(wiringWrites[1].payload) or ""))
  end
  replies[4], replies[54] = nil, nil
end

-- Motor: the protocol, and a timed spin.
openPage(14, "motor")
settle()
local function protocolY() local b = button(T("mot_pwm")); return b and b.rect.y end
local function otherPicker()
  for _, f in ipairs(fields) do
    if f.kind == "choice" then return f end
  end
end
local function otherHas(protocol)
  local picker = otherPicker()
  for _, v in ipairs(picker and picker.values or {}) do
    if v[2] == protocol then return true end
  end
  return false
end
check("motor: the quick picks are PWM, DShot150 and DShot300 only",
  button(T("mot_pwm")) and button(T("mot_dshot150")) and button(T("mot_dshot300"))
    and not button(T("mot_dshot600")) and not button(T("mot_none")))
check("motor: every other protocol is in the Other picker",
  otherPicker() and otherHas(7) and otherHas(11) and otherHas(1) and otherHas(8)
    and not otherHas(0) and not otherHas(5) and not otherHas(6))
check("motor: the Other picker shows Other while a quick pick is set", otherPicker().get() == -1,
  tostring(otherPicker().get()))
local yBefore = protocolY()
before = #sent
press(T("mot_dshot150"))
check("motor: the restart note does not move the protocol buttons", yBefore and protocolY() == yBefore,
  tostring(yBefore) .. " -> " .. tostring(protocolY()))
check("motor: the protocols are a choice list, each with its help beside it",
  button(T("mot_pwm")).rect.h >= 26 and shows("mot_pwm_help") and shows("mot_dshot150_help")
    and shows("mot_other_help"),
  button(T("mot_pwm")).rect.h)
local dshot150 = writesOf(222, before + 1)
check("motor: choosing DShot150 writes the motor config", #dshot150 == 1 and dshot150[1].payload[9] == 5
  and shows("mot_changed"), dshot150[1] and bytes(dshot150[1].payload))
do
  -- Long text: the choices keep usable buttons above the row, and the text
  -- is cut short instead (the restart note above is still shown).
  local rowY, ok = 0, true
  for _, f in ipairs(fields) do
    if f.kind == "button" and f.rect and f.rect.y > rowY then rowY = f.rect.y end
  end
  for _, f in ipairs(fields) do
    local t = f.text
    if (f.kind == "button" and (t == T("mot_pwm") or t == T("mot_dshot150") or t == T("mot_dshot300")))
      or f.kind == "choice" then
      if f.rect.h < 26 or f.rect.y + f.rect.h > rowY then ok = false end
    end
  end
  check("motor: the protocol buttons fit above the row", ok)
  check("motor: the encoder goes through the protocols, then Back, Check motor, Save and restart", inScreenOrder())
  local picker, order = otherPicker(), true
  for _, f in ipairs(fields) do
    if f == picker then break end
    if f.kind == "button" and f.rect and f.rect.y > picker.rect.y then order = false end
  end
  check("motor: the Other picker comes after the quick picks, before the row", order)
end
-- Other: DShot600 is still there for a pilot who wants it.
openPage(14, "motor")
settle()
before = #sent
otherPicker().set(7)
tick()
local dshot600 = writesOf(222, before + 1)
check("motor: Other can still choose DShot600 and writes the motor config",
  #dshot600 == 1 and dshot600[1].payload[9] == 7 and shows("mot_changed"),
  dshot600[1] and bytes(dshot600[1].payload))
check("motor: the Other picker then shows DShot600", otherPicker().get() == 7, tostring(otherPicker().get()))
before = #sent
otherPicker().set(-1)
tick()
check("motor: the Other entry itself writes nothing", #writesOf(222, before + 1) == 0)
-- DShot150 has no bidirectional DShot RPM telemetry.
local function motorReply(bidir, protocol)
  replies[131] = function(m)
    local out = {}
    for i, b in ipairs(m.simulatorResponse) do out[i] = b end
    out[9], out[10] = bidir, protocol
    return out
  end
end
check("motor: no RPM note while DShot600 is set", not shows("mot_dshot150_rpm"))
motorReply(1, 0)
openPage(14, "motor")
settle()
before = #sent
press(T("mot_dshot150"))
local bidirOff = writesOf(222, before + 1)
check("motor: choosing DShot150 turns bidirectional DShot off in the same write",
  #bidirOff == 1 and bidirOff[1].payload[8] == 0 and bidirOff[1].payload[9] == 5,
  bidirOff[1] and bytes(bidirOff[1].payload))
check("motor: after choosing DShot150 both the restart and the RPM notes show",
  shows("mot_changed") and shows("mot_dshot150_rpm"))
openPage(14, "motor")
settle()
before = #sent
press(T("mot_dshot300"))
local bidirKept = writesOf(222, before + 1)
check("motor: DShot300 leaves bidirectional DShot as it was",
  #bidirKept == 1 and bidirKept[1].payload[8] == 1 and bidirKept[1].payload[9] == 6,
  bidirKept[1] and bytes(bidirKept[1].payload))
check("motor: no RPM note after choosing DShot300", not shows("mot_dshot150_rpm"))
motorReply(0, 5)
openPage(14, "motor")
settle()
check("motor: with DShot150 set, the step says RPM needs DShot300 or telemetry",
  shows("mot_dshot150_rpm") and not shows("mot_changed"))
replies[131] = nil

-- Check motor: propeller off, calibrate a PWM ESC, spin one motor at a time.
do
  local CANCEL = "@i18n(app.btn_cancel)@"
  local function motors(count)
    replies[101] = function(m)
      local out = {}
      for i, b in ipairs(m.simulatorResponse) do out[i] = b end
      out[28] = count   -- motor_count
      return out
    end
  end
  -- Motor override writes since `from`: per motor, the values in order.
  local function overrides(from)
    local out = {}
    for _, m in ipairs(writesOf(195, from)) do
      local motor = m.payload[1]
      out[motor] = out[motor] or {}
      table.insert(out[motor], s16(m.payload, 2))
    end
    return out
  end
  local function all(values, value)
    if not values or #values == 0 then return false end
    for _, v in ipairs(values) do if v ~= value then return false end end
    return true
  end
  local function last(values) return values and values[#values] end
  local function toProp()
    openPage(14, "motor")
    settle()
    press(T("mot_test"))
  end

  -- A twin on the PWM protocol (the simulator's motor config).
  motors(2)
  toProp()
  check("motor: Check motor asks about the propeller first",
    shows("mot_prop_title") and button(T("mot_prop_off")) ~= nil
      and headers[#headers].title == T("name") .. " / 6. " .. T("step_motor"), headers[#headers].title)
  press(T("mot_prop_off"))
  check("motor: on PWM the calibration comes before the spin, and asks about the battery",
    shows("mot_cal_title") and shows("mot_cal_text") and button(T("mot_cal_unplugged")) ~= nil
      and button(T("mot_cal_full")) == nil)
  check("motor: the calibration can be skipped", button(T("btn_next")) ~= nil)
  press(T("mot_cal_unplugged"))
  check("motor: then Start full throttle, with no other way forward",
    shows("mot_cal_full_text") and button(T("mot_cal_full")) ~= nil and button(T("btn_next")) == nil)
  check("motor: nothing reaches the motors before that", #writesOf(195) == 0)

  before = #sent
  button(T("mot_cal_full")).press()
  local w = overrides(before + 1)
  check("motor: Start full throttle writes full throttle on every motor",
    all(w[0], 1000) and all(w[1], 1000) and #w[0] == 1 and #w[1] == 1 and w[2] == nil)
  tick()
  check("motor: Low throttle waits for the ramp, Cancel has the focus",
    shows("mot_cal_hold_text") and shows("mot_cal_ramping_fmt") and not button(T("mot_cal_low")).enabled
      and button(CANCEL).focused)
  button(T("mot_cal_low")).press()
  tick()
  check("motor: pressing Low throttle early does nothing",
    shows("mot_cal_ramping_fmt") and not shows("mot_cal_done") and last(overrides(before + 1)[0]) == 1000)
  for _ = 1, 13 do tick(0.3) end   -- 4.5 s in all
  check("motor: still waiting at 4.5 s", not button(T("mot_cal_low")).enabled)
  w = overrides(before + 1)
  -- Re-sent at least every 0.3 s here, against the firmware's one-second deadline.
  check("motor: full throttle is re-sent on every motor while it is held",
    all(w[0], 1000) and all(w[1], 1000) and #w[0] >= 14 and #w[1] >= 14, #w[0])
  tick(0.3)
  tick(0.3)
  tick()
  check("motor: after 5 s it says to plug the battery in, and Low throttle is on",
    shows("mot_cal_plug_in") and button(T("mot_cal_low")).enabled and button(T("mot_cal_low")).focused)
  before = #sent
  press(T("mot_cal_low"))
  w = overrides(before + 1)
  check("motor: Low throttle writes zero on every motor", all(w[0], 0) and all(w[1], 0))
  check("motor: and says it is done, back on the battery question",
    shows("mot_cal_done") and button(T("mot_cal_unplugged")) ~= nil)
  before = #sent
  tick(1)
  check("motor: nothing is sent to the motors afterwards", #writesOf(195, before + 1) == 0)

  -- Cancel, Back, the step list, Save, arming, a lost link and leaving all drop the output to zero.
  local function startFull()
    press(T("mot_cal_unplugged"))
    press(T("mot_cal_full"))
    before = #sent
  end
  local function droppedToZero()
    local z = overrides(before + 1)
    return last(z[0]) == 0 and last(z[1]) == 0
  end
  startFull()
  press(CANCEL)
  check("motor: Cancel writes zero and says the calibration stopped",
    droppedToZero() and shows("mot_cal_stopped") and button(T("mot_cal_unplugged")) ~= nil)
  startFull()
  press(T("btn_back"))
  check("motor: Back writes zero", droppedToZero() and shows("mot_cal_stopped"))
  startFull()
  headers[#headers].opts.onTool()
  tick()
  check("motor: the step list writes zero", droppedToZero())
  headers[#headers].opts.onBack()
  tick()
  startFull()
  headers[#headers].opts.onSave()
  tick()
  tick()
  check("motor: Save in the header writes zero", droppedToZero() and shows("mot_cal_stopped"))
  startFull()
  session({connected = true, isArmed = true, apiVersionMajor = 22, apiVersionMinor = 14})
  check("motor: arming writes zero", droppedToZero())
  tick()
  before = #sent
  tick(1)
  check("motor: and nothing is sent while armed", #writesOf(195, before + 1) == 0 and shows("mot_cal_stopped"))
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  startFull()
  session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  check("motor: a lost link writes zero", droppedToZero())
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  startFull()
  headers[#headers].opts.onBack()
  tick()
  check("motor: leaving the wizard writes zero", droppedToZero() and ctx.back == 1)

  -- Spin: one motor at a time.
  toProp()
  press(T("mot_prop_off"))
  press(T("btn_next"))
  check("motor: Next skips the calibration, on to the spin",
    shows("mot_spin_title") and shows("mot_spin_twin") and button(T("mot_motor_fmt")) ~= nil
      and button("10%") ~= nil and button(T("mot_spin_fmt")) ~= nil)
  check("motor: the encoder goes Back, the motor, the throttle, Spin, Next", inScreenOrder())
  before = #sent
  press(T("mot_spin_fmt"))
  tick(0.3)
  w = overrides(before + 1)
  check("motor: Spin starts on the first motor only", w[1] == nil and all(w[0], 100) and #w[0] >= 2)
  press(T("mot_stop"))
  press(T("mot_motor_fmt"))   -- motor 2
  press("10%")                -- 20 %
  before = #sent
  press(T("mot_spin_fmt"))
  tick(0.3)
  w = overrides(before + 1)
  check("motor: Spin writes only the motor chosen, at the throttle chosen",
    w[0] == nil and all(w[1], 200) and #w[1] >= 2 and shows("mot_spinning"), w[1] and table.concat(w[1], ","))
  check("motor: Next waits for the spin to end, and Stop is offered",
    button(T("mot_stop")) ~= nil and not button(T("btn_next")).enabled)
  tick(4)
  tick()
  w = overrides(before + 1)
  check("motor: it stops by itself after 3 s, with zero on every motor",
    last(w[1]) == 0 and all(w[0], 0) and button(T("mot_spin_fmt")) ~= nil)
  before = #sent
  tick(1)
  check("motor: and sends nothing more", #writesOf(195, before + 1) == 0)
  press(T("mot_spin_fmt"))
  before = #sent
  press(T("mot_stop"))
  w = overrides(before + 1)
  check("motor: Stop ends it early", last(w[1]) == 0 and all(w[0], 0) and button(T("mot_spin_fmt")) ~= nil)
  press(T("mot_spin_fmt"))
  before = #sent
  session({connected = true, isArmed = true, apiVersionMajor = 22, apiVersionMinor = 14})
  w = overrides(before + 1)
  check("motor: arming stops a spin, with zero on every motor", last(w[1]) == 0 and last(w[0]) == 0)
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  press(T("btn_back"))
  check("motor: Back from the spin on PWM is the calibration", shows("mot_cal_title"))
  press(T("btn_next"))
  before = #sent
  press(T("btn_next"))
  tick()
  check("motor: Next from the spin opens the next step, with no restart",
    headers[#headers].title == T("name") .. " / 7. " .. T("step_esctelemetry") and #writesOf(68, before + 1) == 0,
    headers[#headers].title)

  -- One motor: no motor button.
  motors(1)
  toProp()
  press(T("mot_prop_off"))
  press(T("btn_next"))
  check("motor: with one motor there is no motor button",
    shows("mot_spin_title") and button(T("mot_motor_fmt")) == nil and not shows("mot_spin_twin"))
  before = #sent
  press(T("mot_spin_fmt"))
  tick(0.3)
  w = overrides(before + 1)
  check("motor: spins at 10%", all(w[0], 100) and w[1] == nil, w[0] and table.concat(w[0], ","))
  before = #sent
  tick(4)
  w = overrides(before + 1)
  check("motor: and stops by itself", last(w[0]) == 0)

  -- DShot has no range to learn.
  motorReply(0, 6)
  toProp()
  press(T("mot_prop_off"))
  check("motor: DShot has no calibration, so the spin comes straight away",
    shows("mot_spin_title") and not shows("mot_cal_title"))
  press(T("btn_back"))
  check("motor: Back from the spin on DShot is the propeller question", shows("mot_prop_title"))
  replies[131] = nil

  -- A stall: the flight controller drops an override that is not re-sent
  -- within a second, and the next write starts a new ramp.
  toProp()
  press(T("mot_prop_off"))
  press(T("mot_cal_unplugged"))
  press(T("mot_cal_full"))
  for _ = 1, 10 do tick(0.3) end   -- 3.3 s of ramp
  tick(1.5)                        -- no write for 1.5 s
  for _ = 1, 10 do tick(0.3) end   -- 7.8 s since the start, 3 s since the stall
  check("motor: after a stall the wait for full throttle starts again",
    not button(T("mot_cal_low")).enabled and shows("mot_cal_ramping_fmt") and not shows("mot_cal_plug_in"))
  for _ = 1, 8 do tick(0.3) end    -- 5.4 s since the stall
  check("motor: and Low throttle comes on 5 s after it",
    button(T("mot_cal_low")).enabled and shows("mot_cal_plug_in"))
  before = #sent
  tick(1.5)
  tick()
  w = overrides(before + 1)
  check("motor: a stall once the battery may be in stops the calibration, without full throttle again",
    all(w[0], 0) and shows("mot_cal_stopped") and button(T("mot_cal_unplugged")) ~= nil,
    w[0] and table.concat(w[0], ","))

  -- A new protocol is not checked before the restart, also after the step
  -- is closed and opened again.
  openPage(14, "motor")
  settle()
  press(T("mot_dshot300"))
  check("motor: a new protocol asks for Save and restart, with no Check motor",
    button(T("btn_save_restart")) ~= nil and button(T("mot_test")) == nil)
  reopenStep(6, "motor")
  check("motor: closed and opened again, the step still asks for Save and restart",
    shows("mot_changed") and button(T("btn_save_restart")) ~= nil and button(T("mot_test")) == nil)
  before = #sent
  press(T("btn_save_restart"))
  tick()
  tick()
  session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14, handshake = {apiVersion = true}})
  settle(6)
  check("motor: after the restart Check motor is back",
    #writesOf(68, before + 1) == 1 and button(T("mot_test")) ~= nil and button(T("btn_save_restart")) == nil
      and not shows("mot_changed"))
  replies[101] = nil
end

-- ESC telemetry: a protocol, then a free port, then save and restart; back on
-- the wiring screen, the detection writes the wiring it found; then the
-- battery meters.
do
  local function choiceFields()
    local out = {}
    for _, f in ipairs(fields) do
      if f.kind == "choice" then out[#out + 1] = f end
    end
    return out
  end
  -- A board with six UARTs, all free: two rows of ports, with room for the
  -- text above them. escMask is UART3's function mask, byte 2.
  local function sixPorts(escMask)
    replies[54] = function(m)
      local out = {}
      for i = 1, 6 * 9 do out[i] = m.simulatorResponse[i] end
      out[2 * 9 + 3] = escMask
      return out
    end
  end
  -- The step with telemetry set up: HOBBYWING V4 (2) on UART3
  -- (FUNCTION_ESC_SENSOR, 1024), the feature on.
  local function configured()
    replies[123] = {2, 0, 200, 0, 0, 15, 0, 0, 0, 0}
    replies[36] = {0, 0, 0, 8}   -- FEATURE_ESC_SENSOR is bit 27
    sixPorts(4)
  end

  sixPorts(0)
  openPage(14, "esctelemetry")
  settle()
  check("esc telemetry: opens on the protocol question, Not used and a drop-down",
    shows("esc_title") and button(T("esc_not_used")) ~= nil and #choiceFields() == 1
      and headers[#headers].title == T("name") .. " / 7. " .. T("step_esctelemetry"), headers[#headers].title)
  do
    local offered, own = {}, false
    for _, v in ipairs(choiceFields()[1].values) do
      offered[v[2]] = true
      if v[1] == "FrSky F.BUS" or v[1] == "SRXL2" then own = true end
    end
    check("esc telemetry: F.BUS and SRXL2 are not offered, the rest are",
      not own and not offered[13] and not offered[14] and offered[1] and offered[2] and offered[12] and not offered[0])
    check("esc telemetry: the drop-down shows Choose while none is set", choiceFields()[1].get() == -1)
  end
  before = #sent
  press(T("esc_not_used"))
  check("esc telemetry: Not used on a model without it writes nothing",
    #writesOf(216, before + 1) == 0 and #writesOf(37, before + 1) == 0 and #writesOf(55, before + 1) == 0)
  choiceFields()[1].set(2)
  tick()
  local escWrites, featureWrites = writesOf(216, before + 1), writesOf(37, before + 1)
  check("esc telemetry: choosing a protocol writes the ESC sensor config",
    #escWrites == 1 and bytes(escWrites[1].payload) == "2,0,200,0,0,15,0,0,0,0",
    escWrites[1] and bytes(escWrites[1].payload))
  check("esc telemetry: and turns the ESC sensor feature on",
    #featureWrites == 1 and bytes(featureWrites[1].payload) == "0,0,0,8",
    featureWrites[1] and bytes(featureWrites[1].payload))
  check("esc telemetry: then asks for the port", shows("esc_port_title") and shows("esc_port_none"))
  check("esc telemetry: the encoder goes through the ports, then Back and Save and restart", inScreenOrder())
  before = #sent
  press("UART3")
  local escPorts = writesOf(55, before + 1)
  -- MSP_SET_SERIAL_CONFIG for UART3: FUNCTION_ESC_SENSOR is 1024, so byte 2 of the mask is 4.
  check("esc telemetry: choosing a port gives it the ESC telemetry function",
    #escPorts == 1 and bytes(escPorts[1].payload) == "2,0,4,0,0,0,0,0,0", escPorts[1] and bytes(escPorts[1].payload))
  check("esc telemetry: the feature is not written twice", #writesOf(37, before + 1) == 0)
  check("esc telemetry: the change needs a restart", shows("esc_changed") and button(T("btn_save_restart")) ~= nil)
  before = #sent
  press("UART5")
  escPorts = writesOf(55, before + 1)
  check("esc telemetry: another port frees the first",
    #escPorts == 2 and bytes(escPorts[1].payload) == "2,0,0,0,0,0,0,0,0"
      and bytes(escPorts[2].payload) == "4,0,4,0,0,0,0,0,0",
    escPorts[1] and bytes(escPorts[1].payload))

  -- Save and restart: the flight controller comes back with what was saved,
  -- and the step reopens on the wiring screen.
  configured()
  before = #sent
  press(T("btn_save_restart"))
  tick()
  tick()
  check("esc telemetry: saves and restarts", #writesOf(250, before + 1) == 1 and #writesOf(68, before + 1) == 1)
  session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
  tick()
  session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14, handshake = {apiVersion = true}})
  settle(6)
  check("esc telemetry: after the restart the step reopens on the wiring screen",
    shows("esc_wiring_title") and button(T("esc_detect")) ~= nil and button(T("esc_detect")).enabled
      and headers[#headers].title == T("name") .. " / 7. " .. T("step_esctelemetry"), headers[#headers].title)

  -- Detect wiring: start, poll while it runs, and on success write what was found.
  local polls, answer = 0, nil
  replies[0x5F14] = function(m)
    local action = m.payload[1]
    if action == 1 then return {1, 0, 0, 0, 0, 0, 0, 0, 4, 1} end   -- RUNNING, wiring 1 of 4
    if action == 2 then return {0, 0, 0, 0, 0, 0, 0, 0, 4, 1} end   -- IDLE
    polls = polls + 1
    if polls < 3 then return {1, 2, 1, 1, 100, 0, 0, 0, 4, 1} end   -- RUNNING, wiring 3 of 4
    return answer
  end
  answer = {2, 2, 1, 1, 200, 0, 2, 0, 4, 1}                         -- SUCCESS: half duplex, pin swap
  before = #sent
  press(T("esc_detect"))
  local trialWrites = writesOf(0x5F14, before + 1)
  check("esc telemetry: Detect wiring starts the trial",
    #trialWrites >= 1 and bytes(trialWrites[1].payload) == "1", trialWrites[1] and bytes(trialWrites[1].payload))
  check("esc telemetry: while it runs the button stops it",
    button(T("esc_detect")) == nil and button(T("esc_stop")) ~= nil and shows("esc_trying_fmt"))
  local inFlightOk = true
  for _ = 1, 6 do
    -- One request in flight: never a second poll before the first is answered.
    if #sent - answeredUpTo > 1 then inFlightOk = false end
    tick()
  end
  check("esc telemetry: the trial is polled one request at a time", polls == 3 and inFlightOk, polls)
  escWrites = writesOf(216, before + 1)
  check("esc telemetry: a wiring that is found writes half duplex and pin swap",
    #escWrites == 1 and bytes(escWrites[1].payload) == "2,1,200,0,0,15,1,0,0,0",
    escWrites[1] and bytes(escWrites[1].payload))
  do
    -- The stop goes first: the port goes back as it booted, then the config is written.
    local stopAt, writeAt
    for i = before + 1, #sent do
      if sent[i].command == 0x5F14 and sent[i].payload[1] == 2 then stopAt = stopAt or i end
      if sent[i].command == 216 then writeAt = i end
    end
    check("esc telemetry: the trial is stopped before the wiring is written", stopAt and writeAt and stopAt < writeAt)
  end
  check("esc telemetry: and asks for Save and restart",
    shows("esc_found") and button(T("btn_save_restart")) ~= nil and not button(T("esc_detect")).enabled)
  check("esc telemetry: pin swap and half duplex are not shown as settings", #choiceFields() == 0)
  before = #sent
  tick(1)
  check("esc telemetry: no polling once the trial has ended", #writesOf(0x5F14, before + 1) == 0)

  -- The wiring already set answers: nothing to write.
  openPage(14, "esctelemetry")
  settle()
  check("esc telemetry: with telemetry set up the drop-down shows the protocol", choiceFields()[1].get() == 2)
  press(T("btn_next"))
  check("esc telemetry: Next goes to the port, the current one in focus",
    shows("esc_port_title") and button("UART3").focused)
  press(T("btn_next"))
  polls, answer = 2, {2, 0, 0, 0, 200, 0, 2, 0, 4, 1}
  before = #sent
  press(T("esc_detect"))
  settle()
  check("esc telemetry: the wiring that is set answers, so nothing is written",
    shows("esc_wiring_ok") and #writesOf(216, before + 1) == 0 and button(T("btn_save_restart")) == nil)

  -- No answer on any wiring; a trial the flight controller refuses is not stopped.
  polls, answer = 2, {3, 3, 0, 0, 0, 0, 0, 0, 4, 1}
  press(T("esc_detect"))
  settle()
  check("esc telemetry: no answer on any wiring says so", shows("esc_not_found") and button(T("esc_detect")).enabled)
  polls, answer = 2, {4, 0, 0, 0, 0, 0, 0, 0, 0, 1}
  before = #sent
  press(T("esc_detect"))
  settle()
  local stopsSent = 0
  for _, m in ipairs(writesOf(0x5F14, before + 1)) do
    if m.payload[1] == 2 then stopsSent = stopsSent + 1 end
  end
  check("esc telemetry: a refused trial says so and is not stopped", shows("esc_rejected") and stopsSent == 0, stopsSent)

  -- Leaving the screen while it runs stops it.
  polls, answer = -100, nil
  press(T("esc_detect"))
  before = #sent
  press(T("btn_back"))
  trialWrites = writesOf(0x5F14, before + 1)
  check("esc telemetry: Back stops a running trial",
    shows("esc_port_title") and #trialWrites >= 1 and bytes(trialWrites[#trialWrites].payload) == "2")
  replies[0x5F14] = nil

  -- Battery: voltage and current from the ESC, each yes or no.
  press(T("btn_next"))
  press(T("btn_next"))
  check("esc telemetry: then the battery, two yes or no choices",
    shows("esc_battery_title") and #choiceFields() == 2 and choiceFields()[1].get() == 0 and choiceFields()[2].get() == 0)
  before = #sent
  choiceFields()[1].set(1)
  tick()
  local batteryWrites = writesOf(33, before + 1)
  -- MSP_SET_BATTERY_CONFIG: byte 4 is the voltage source, byte 5 the current source; 2 is the ESC.
  check("esc telemetry: voltage from the ESC writes the voltage meter source",
    #batteryWrites == 1 and batteryWrites[1].payload[4] == 2 and batteryWrites[1].payload[5] == 1
      and #batteryWrites[1].payload == 81, batteryWrites[1] and bytes(batteryWrites[1].payload))
  check("esc telemetry: a meter change needs a restart", shows("esc_changed") and button(T("btn_save_restart")) ~= nil)
  before = #sent
  choiceFields()[2].set(1)
  tick()
  choiceFields()[1].set(0)
  tick()
  batteryWrites = writesOf(33, before + 1)
  check("esc telemetry: turning one off puts back the source it had",
    #batteryWrites == 2 and batteryWrites[2].payload[4] == 1 and batteryWrites[2].payload[5] == 2,
    batteryWrites[2] and bytes(batteryWrites[2].payload))

  -- Not used: protocol none, the feature off, the port freed, the meter back.
  press(T("btn_back"))
  press(T("btn_back"))
  press(T("btn_back"))
  before = #sent
  press(T("esc_not_used"))
  escWrites, featureWrites, escPorts = writesOf(216, before + 1), writesOf(37, before + 1), writesOf(55, before + 1)
  batteryWrites = writesOf(33, before + 1)
  check("esc telemetry: Not used writes protocol none and turns the feature off",
    #escWrites == 1 and escWrites[1].payload[1] == 0 and #featureWrites == 1
      and bytes(featureWrites[1].payload) == "0,0,0,0", featureWrites[1] and bytes(featureWrites[1].payload))
  check("esc telemetry: Not used frees the port",
    #escPorts == 1 and bytes(escPorts[1].payload) == "2,0,0,0,0,0,0,0,0", escPorts[1] and bytes(escPorts[1].payload))
  check("esc telemetry: Not used takes the battery off the ESC",
    #batteryWrites == 1 and batteryWrites[1].payload[4] == 1 and batteryWrites[1].payload[5] == 1)
  check("esc telemetry: Not used ends with Save and restart",
    shows("esc_changed") and button(T("btn_save_restart")) ~= nil and choiceFields()[1].get() == -1)

  -- Discard writes back what the step found when it made its first change:
  -- every port as it was, and the battery as it was read.
  before = #sent
  discardAll()
  escWrites, featureWrites, escPorts = writesOf(216, before + 1), writesOf(37, before + 1), writesOf(55, before + 1)
  batteryWrites = writesOf(33, before + 1)
  check("esc telemetry: Discard puts the protocol, the feature, the ports and the battery back",
    #escWrites == 1 and bytes(escWrites[1].payload) == "2,0,200,0,0,15,0,0,0,0"
      and #featureWrites == 1 and bytes(featureWrites[1].payload) == "0,0,0,8"
      and #escPorts == 6 and bytes(escPorts[3].payload) == "2,0,4,0,0,0,0,0,0"
      and bytes(escPorts[2].payload) == "1,0,0,0,0,0,0,0,0"
      and #batteryWrites == 1 and batteryWrites[1].payload[4] == 1 and batteryWrites[1].payload[5] == 1
      and #batteryWrites[1].payload == 81 and ctx.back == 1,
    bytes(escWrites[1] and escWrites[1].payload or {}) .. " / " .. #featureWrites .. " / "
      .. #escPorts .. " / " .. #batteryWrites .. " / " .. ctx.back)

  -- A port change is still owed a restart after the step is closed and
  -- opened again, and Discard then clears the port the second instance chose.
  do
    -- Byte 2 of each port's function mask, by port number.
    local function masks(list)
      replies[54] = function(m)
        local out = {}
        for i = 1, 6 * 9 do out[i] = m.simulatorResponse[i] end
        for index, mask in pairs(list) do out[(index - 1) * 9 + 3] = mask end
        return out
      end
    end
    masks({})   -- the protocol is set, with no port yet
    openPage(14, "esctelemetry")
    settle()
    press(T("btn_next"))
    press("UART2")
    check("esc telemetry: a new port asks for Save and restart", button(T("btn_save_restart")) ~= nil)
    masks({[2] = 4})   -- what the flight controller holds now
    reopenStep(7, "esctelemetry")
    press(T("btn_next"))
    check("esc telemetry: closed and opened again, the port screen still asks for Save and restart",
      shows("esc_port_title") and shows("esc_changed") and button(T("btn_save_restart")) ~= nil
        and button(T("btn_next")) == nil and button("UART2").focused)
    press("UART2")
    check("esc telemetry: and the wiring cannot be detected before it",
      shows("esc_port_title") and button(T("esc_detect")) == nil)
    before = #sent
    press("UART3")
    escPorts = writesOf(55, before + 1)
    check("esc telemetry: the reopened step moves the telemetry to another port",
      #escPorts == 2 and bytes(escPorts[1].payload) == "1,0,0,0,0,0,0,0,0"
        and bytes(escPorts[2].payload) == "2,0,4,0,0,0,0,0,0", escPorts[2] and bytes(escPorts[2].payload))
    before = #sent
    discardAll()
    local cleared, wrong = {}, 0
    for _, m in ipairs(writesOf(55, before + 1)) do
      local pl = m.payload
      if pl[2] + pl[3] + pl[4] + pl[5] == 0 then cleared[pl[1]] = true else wrong = wrong + 1 end
    end
    check("esc telemetry: Discard then clears both ports, leaving none on ESC telemetry",
      cleared[1] and cleared[2] and wrong == 0 and ctx.back == 1, wrong)
  end

  -- The battery is read on its own and may answer after a change was made:
  -- Discard still puts back the sources it had, here both on the ESC.
  configured()
  replies[32] = function(m)
    local out = {}
    for i, b in ipairs(m.simulatorResponse) do out[i] = b end
    out[4], out[5] = 2, 2
    return out
  end
  held[32] = true
  openPage(14, "esctelemetry")
  settle()
  choiceFields()[1].set(3)   -- a change before the battery has answered
  tick()
  releaseHeld(32)
  settle()
  press(T("btn_back"))
  before = #sent
  press(T("esc_not_used"))
  batteryWrites = writesOf(33, before + 1)
  check("esc telemetry: Not used takes a battery that answered late off the ESC",
    #batteryWrites == 1 and batteryWrites[1].payload[4] == 1 and batteryWrites[1].payload[5] == 1)
  before = #sent
  discardAll()
  batteryWrites = writesOf(33, before + 1)
  check("esc telemetry: and Discard puts its sources back, not None",
    #batteryWrites == 1 and batteryWrites[1].payload[4] == 2 and batteryWrites[1].payload[5] == 2
      and #batteryWrites[1].payload == 81,
    batteryWrites[1] and (batteryWrites[1].payload[4] .. "," .. batteryWrites[1].payload[5]))
  -- A change with no battery change leaves the battery alone on Discard.
  openPage(14, "esctelemetry")
  settle()
  choiceFields()[1].set(3)
  tick()
  before = #sent
  discardAll()
  check("esc telemetry: Discard does not write a battery that was not changed", #writesOf(33, before + 1) == 0)
  replies[32] = nil

  -- F.BUS telemetry is set up elsewhere.
  replies[123] = {13, 0, 200, 0, 0, 15, 0, 0, 0, 0}
  openPage(14, "esctelemetry")
  settle()
  check("esc telemetry: F.BUS telemetry is left alone, with Next only",
    shows("esc_elsewhere_fmt") and #choiceFields() == 0 and button(T("esc_not_used")) == nil
      and button(T("btn_next")) ~= nil)
  replies[123], replies[36], replies[54] = nil, nil, nil

  -- Castle Link reads telemetry on the throttle wire.
  motorReply(0, requireModule("lib/msp_motor_config.lua").CASTLE_PROTOCOL)
  openPage(14, "esctelemetry")
  settle()
  check("esc telemetry: with Castle Link it says the throttle wire carries it, with Next only",
    shows("esc_castle") and #choiceFields() == 0 and button(T("esc_not_used")) == nil
      and button(T("btn_next")) ~= nil)
  replies[131] = nil

  -- No motor: nothing to set up.
  replies[101] = function(m)
    local out = {}
    for i, b in ipairs(m.simulatorResponse) do out[i] = b end
    out[28] = 0   -- motor_count
    return out
  end
  openPage(14, "esctelemetry")
  settle()
  check("esc telemetry: a model with no motor is told so, with Next only",
    shows("esc_no_motor") and #choiceFields() == 0 and button(T("esc_not_used")) == nil
      and button(T("btn_next")) ~= nil)
  replies[101] = nil
end

-- Centre: every surface held at its centre; nudging writes the Mid.
openPage(14, "centre")
settle()
check("center: the encoder goes Back, the nudges and Identify, then Next", inScreenOrder())
local held = {}
for _, m in ipairs(writesOf(193)) do
  if s16(m.payload, 2) == 0 and #m.payload == 5 then held[m.payload[1]] = true end
end
check("centre: holds all four servos at centre", held[0] and held[1] and held[2] and held[3])
do
  -- The servo being set stands out: the accent colour (lcd.RGB(255, ...) here),
  -- the "1 of 4" after it muted, the instructions in the text colour.
  paint()
  local name, progress
  for _, t in ipairs(drawn) do
    if t:find(T("servo_kind_fmt"), 1, true) then name = t end
    if t:find(T("progress_fmt"), 1, true) then progress = t end
  end
  check("centre: the servo being set is drawn in the accent colour",
    name and drawnColor[name] == 255 and progress and drawnColor[progress] ~= 255,
    tostring(name) .. " " .. tostring(name and drawnColor[name]))
end
before = #sent
press("+10")
local mid = writesOf(212, before + 1)
check("centre: +10 moves servo 1's centre to 1510", #mid == 1 and mid[1].payload[1] == 0 and u16(mid[1].payload, 2) == 1510)

-- Identify moves only the selected servo temporarily; configuration is untouched.
local function lastServoValue(servo, from)
  local value
  for _, m in ipairs(writesOf(193, from)) do
    if m.payload[1] == servo then value = s16(m.payload, 2) end
  end
  return value
end
before = #sent
press(T("cen_identify"))
local identifyWrites = writesOf(193, before + 1)
check("centre: Identify starts only servo 1 with a small timed movement",
  #identifyWrites == 1 and identifyWrites[1].payload[1] == 0
  and s16(identifyWrites[1].payload, 2) == 100 and #identifyWrites[1].payload == 5)
tick(0.25)
check("centre: Identify rocks to the other side", lastServoValue(0, before + 1) == -100)
tick(0.5)
check("centre: Identify rocks back", lastServoValue(0, before + 1) == 100)
tick(2.0)
check("centre: Identify centers the servo after 3 seconds", lastServoValue(0, before + 1) == 0)
check("centre: Identify changes no configuration and needs no save",
  #writesOf(212, before + 1) == 0 and #writesOf(250, before + 1) == 0)
before = #sent
tick(1)
check("centre: Identify stays stopped", #writesOf(193, before + 1) == 0)

press(T("cen_identify"))
before = #sent
press("-1")
check("centre: adjusting the center stops Identify first", lastServoValue(0, before + 1) == 0)
press(T("cen_identify"))
before = #sent
press(T("btn_next"))
check("centre: Next centers the old servo before changing surfaces", lastServoValue(0, before + 1) == 0)
before = #sent
press(T("cen_identify"))
check("centre: Identify follows the selected surface", lastServoValue(1, before + 1) == 100)
before = #sent
press(T("btn_back"))
check("centre: Back centers the servo before changing surfaces", lastServoValue(1, before + 1) == 0)

press(T("cen_identify"))
before = #sent
headers[#headers].opts.onTool()
tick()
check("centre: opening the step list centers the servo", lastServoValue(0, before + 1) == 0)
before = #sent
tick(4)
check("centre: Identify stays stopped in the step list", #writesOf(193, before + 1) == 0)
headers[#headers].opts.onBack()
tick()
press(T("cen_identify"))
before = #sent
headers[#headers].opts.onSave()
check("centre: saving centers the servo", lastServoValue(0, before + 1) == 0)
settle()

press(T("cen_identify"))
before = #sent
session({connected = true, isArmed = true, apiVersionMajor = 22, apiVersionMinor = 14})
tick()
check("centre: arming releases Identify and disables its button",
  lastServoValue(0, before + 1) == 2001 and not button(T("cen_identify")).enabled)
before = #sent
tick(4)
check("centre: Identify sends no movement while armed", #writesOf(193, before + 1) == 0)
session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
settle()
check("centre: disarming holds center without resuming Identify", lastServoValue(0) == 0)
press(T("cen_identify"))
before = #sent
session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
tick()
check("centre: disconnecting releases Identify", lastServoValue(0, before + 1) == 2001)
before = #sent
tick(4)
check("centre: Identify sends no movement while disconnected", #writesOf(193, before + 1) == 0)
session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
settle()
press(T("cen_identify"))
before = #sent
ctx.cleanup()
check("centre: closing releases the identifying servo", lastServoValue(0, before + 1) == 2001)

-- Limits: one screen per side, Min then Max for each servo, one counter.
openPage(14, "limits")
settle()
check("limits: the intro pictures the method", shows("lim_how_bind") and shows("lim_how_back"))
before = #sent
press(T("btn_start"))
local probe = writesOf(0x5F1C, before + 1)
check("limits: servo 1 is probed at its centre, timed", #probe >= 1 and bytes(probe[1].payload) == "0,0,0,16,39")
check("limits: the first screen is servo 1's Min",
  shows("lim_todo_min") and not shows("lim_todo_max") and shows("lim_head_fmt")
  and shows("lim_min") and shows("lim_max") and not button(T("lim_set")).enabled)
before = #sent
button(T("lim_set")).press()
tick()
check("limits: Set at center cannot write a zero limit", #writesOf(212, before + 1) == 0)
press("+50")
check("limits: on the Min screen, Set stays off on the Max side", not button(T("lim_set")).enabled)
press("-50")
press("-50")
press("-50")
probe = writesOf(0x5F1C)
check("limits: stepping moves the probe", s16(probe[#probe].payload, 2) == -100)
check("limits: on the Min side, Set is on", button(T("lim_set")).enabled)
before = #sent
press(T("lim_set"))
local minWrite = writesOf(212, before + 1)
check("limits: Set writes Min", #minWrite == 1 and s16(minWrite[1].payload, 4) == -100)
probe = writesOf(0x5F1C, before + 1)
check("limits: then servo 1's Max, back at center",
  shows("lim_todo_max")
  and probe[#probe].payload[1] == 0 and s16(probe[#probe].payload, 2) == 0
  and not button(T("lim_set")).enabled)
press("-10")
check("limits: on the Max screen, Set stays off on the Min side", not button(T("lim_set")).enabled)
press("+10")
press("+50")
press("+50")
before = #sent
press(T("lim_set"))
local maxWrite = writesOf(212, before + 1)
check("limits: Set writes Max and preserves Min",
  #maxWrite == 1 and maxWrite[1].payload[1] == 0
  and s16(maxWrite[1].payload, 4) == -100 and s16(maxWrite[1].payload, 6) == 100)
probe = writesOf(0x5F1C, before + 1)
check("limits: then servo 2's Min at center",
  probe[#probe].payload[1] == 1 and s16(probe[#probe].payload, 2) == 0
  and shows("lim_todo_min"))
before = #sent
press(T("btn_back"))
probe = writesOf(0x5F1C, before + 1)
check("limits: Back returns to servo 1's Max", shows("lim_todo_max")
  and probe[#probe].payload[1] == 0)

-- Next skips a side without changing its limit.
openPage(14, "limits")
settle()
press(T("btn_start"))
before = #sent
press(T("btn_next"))
check("limits: skipping Min offers Max on the same servo without a config write",
  shows("lim_todo_max") and #writesOf(212, before + 1) == 0)
probe = writesOf(0x5F1C, before + 1)
check("limits: skipping Min keeps servo 1 centered", probe[#probe].payload[1] == 0 and s16(probe[#probe].payload, 2) == 0)
before = #sent
press(T("btn_next"))
probe = writesOf(0x5F1C, before + 1)
check("limits: skipping Max moves to servo 2 without a config write",
  probe[#probe].payload[1] == 1 and shows("lim_todo_min") and #writesOf(212, before + 1) == 0)
for _ = 1, 20 do
  if not shows("lim_todo_min") and not shows("lim_todo_max") then break end
  press(T("btn_next"))
end
check("limits: after the last side, the step is done", shows("lim_done"))

-- Throws: PASSTHROUGH forced, Throw stepped.
openPage(14, "throws")
settle()
before = #sent
press(T("btn_start"))
local forced = writesOf(0x5F1B, before + 1)
check("throws: forces PASSTHROUGH", #forced >= 1 and bytes(forced[#forced].payload) == "16,39,1,12")
before = #sent
press("+5%")
local throw = writesOf(171, before + 1)
check("throws: +5% raises roll's throw to 105%", #throw == 1 and throw[1].payload[1] == 1 and s16(throw[1].payload, 2) == 1050)

-- Travel and Gyro.
openPage(14, "travel")
settle()
check("travel: every surface inside its limits", shows("trv_ok"))
before = #sent
tick(1)
check("travel: polls the live servo outputs for the gauges", #writesOf(103, before + 1) >= 1)
check("the saved servo trims were read with the servo configs", #writesOf(233) >= 1)
forced = writesOf(0x5F1B)
check("travel: forces PASSTHROUGH", #forced >= 1 and bytes(forced[#forced].payload) == "16,39,1,12")
session({connected = false, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
settle()
check("travel: without the link, says PASSTHROUGH is off", shows("thr_no_passthrough"))
session({connected = true, isArmed = false, apiVersionMajor = 22, apiVersionMinor = 14})
settle()
check("travel: back on the link, PASSTHROUGH again", shows("trv_ok") and not shows("thr_no_passthrough"))
openPage(14, "gyro")
settle()
before = #sent
press(T("btn_start"))
forced = writesOf(0x5F1B, before + 1)
check("gyro: forces ANGLE", #forced >= 1 and bytes(forced[#forced].payload) == "16,39,1,1")
press(T("dir_like"))
press(T("dir_like"))
before = #sent
press(T("dir_like"))
forced = writesOf(0x5F1B, before + 1)
check("gyro: done lets ANGLE go", shows("gyr_done") and #forced >= 1 and bytes(forced[#forced].payload) == "16,39,0")

-- Trim and gain: one gain knob found by turning it.
do
  local pool = {}
  for _ = 1, 42 * 14 do pool[#pool + 1] = 0 end
  replies[52] = pool
  local rcValues = {1500, 1500, 1500, 1000, 1000, 1000, 1000, 1000}
  replies[105] = function() return u16list(rcValues) end
  openPage(14, "trimgain")
  settle()
  press(T("btn_start"))
  press(T("tg_trim_auto"))
  press(T("tg_gain_single"))
  check("trim and gain: asks to turn the knob", shows("tg_turn_knob"))
  before = #sent
  rcValues[6] = 2000           -- AUX2
  tick(0.3)
  tick(0.3)
  local adj = writesOf(53, before + 1)
  local fns = {}
  for _, m in ipairs(adj) do fns[#fns + 1] = m.payload[2] .. "@" .. m.payload[6] end
  check("trim and gain: gain on AUX2 for roll, pitch and yaw", table.concat(fns, ",") == "85@1,84@1,86@1",
    table.concat(fns, ","))
  replies[52], replies[105] = nil, nil
end

-- Mode switches: ARM from a flicked switch.
do
  local rcValues = {1500, 1500, 1500, 1000, 1000, 1000, 1000, 1000}
  replies[105] = function() return u16list(rcValues) end
  openPage(14, "modes")
  settle()
  press(T("btn_start"))
  check("modes: ARM first", shows("mod_help_arm"))
  -- The simulator's mode ranges already have ARM on AUX1 (lib/msp_modes.lua).
  press(T("mod_change"))
  before = #sent
  rcValues[6] = 2000           -- AUX2 flicked high
  for _ = 1, 4 do tick(0.3) end
  local slot = writesOf(35, before + 1)
  check("modes: ARM moves to AUX2, 1500-2100, in its own slot",
    #slot == 1 and bytes(slot[1].payload) == "1,0,1,0,120,0,0", slot[1] and bytes(slot[1].payload))
  replies[105] = nil
end

-- Flying style and Finish.
openPage(14, "style")
settle()
check("style: the encoder goes through the styles, then Back and Next", inScreenOrder())
before = #sent
press(T("sty_3d"))
local rcw, pidw = writesOf(204, before + 1), writesOf(95, before + 1)
check("style: 3D writes 500 deg/s roll and the PID profile", #rcw == 1 and rcw[1].payload[1] == 100 and #pidw == 1)
openPage(14, "finish")
settle()
check("finish: the summary", shows("fin_intro"))
press(T("btn_next"))
check("finish: then the checks before the first flight", shows("fin_before"))
press(T("fin_button"))
check("finish: Save and finish leaves", ctx.back == 1)

-- The step list, and a step that needs surfaces on a model without any.
openPage(14, "direction")
settle()
headers[#headers].opts.onTool()
tick()
press("4. " .. T("step_airframe"))
check("the step list opens a step", headers[#headers].title == T("name") .. " / 4. " .. T("step_airframe"))
do
  local empty = {}
  for _ = 1, 32 * 14 do empty[#empty + 1] = 0 end
  replies[172] = empty
  openPage(14, "centre")
  settle()
  check("no surfaces: the step points to Airframe", button(T("go_airframe")) ~= nil)
  press(T("go_airframe"))
  check("and that opens it", headers[#headers].title == T("name") .. " / 4. " .. T("step_airframe"))
  replies[172] = nil
end

check("no form was built from a reply or a bus event", #forbidden == 0, table.concat(forbidden, ","))

-- The bottom row ---------------------------------------------------------------
--
-- One row of buttons on every screen, always in the same order: Back on the
-- left (none on the first step), the screen's own buttons, the way forward on
-- the right.

local function footer()
  local bottom, row = -1, {}
  for _, f in ipairs(fields) do
    if f.kind == "button" and f.rect then
      if f.rect.y > bottom then bottom, row = f.rect.y, {f}
      elseif f.rect.y == bottom then row[#row + 1] = f end
    end
  end
  table.sort(row, function(a, b) return a.rect.x < b.rect.x end)
  return row
end

local STEP_KEYS = {"sensors", "receiver", "busoutput", "airframe", "servotype", "motor", "esctelemetry", "centre",
  "direction", "limits", "throws", "travel", "gyro", "trimgain", "modes", "style", "finish"}
local FORWARD = {[T("btn_next")] = true, [T("dir_save_next")] = true, [T("fin_button")] = true,
  [T("btn_save_restart")] = true}
local badFooter, skips = {}, {}
for i, key in ipairs(STEP_KEYS) do
  openPage(14, key)
  settle()
  local row = footer()
  local backOk = (i == 1) == (row[1].text ~= T("btn_back"))
  local onlyOneBack = true
  for j = 2, #row do if row[j].text == T("btn_back") then onlyOneBack = false end end
  if not (backOk and onlyOneBack and FORWARD[row[#row].text]) then
    local texts = {}
    for _, f in ipairs(row) do texts[#texts + 1] = tostring(f.text) end
    badFooter[#badFooter + 1] = key .. " [" .. table.concat(texts, " | ") .. "]"
  end
  for _, f in ipairs(fields) do
    if f.kind == "button" and (f.text == T("btn_skip") or f.text == T("fin_steps")) then skips[#skips + 1] = key end
  end
end
check("every step's row has Back on the left and the way forward on the right", #badFooter == 0,
  table.concat(badFooter, "; "))
check("no Skip or Steps buttons: Next moves on, the step list jumps", #skips == 0, table.concat(skips, ", "))

-- Back and a plain Next are small chevron buttons, clear of the screen's own.
openPage(14, "centre")
settle()
do
  local row = footer()
  local back, nextB = row[1], row[#row]
  local firstOwn, lastOwn = row[2], row[#row - 1]
  check("Back and Next are small icon buttons",
    back.icon == "app/gfx/nav/prev.png" and nextB.icon == "app/gfx/nav/next.png"
    and back.rect.w <= 48 and nextB.rect.w <= 48)
  check("the screen's own buttons keep clear of them",
    firstOwn.rect.x - (back.rect.x + back.rect.w) >= 16
    and nextB.rect.x - (lastOwn.rect.x + lastOwn.rect.w) >= 16)
end
openPage(14, "servotype")
settle()
press(T("st_digital"))
check("a way forward that saves or restarts keeps its words",
  footer()[#footer()].text == T("btn_save_restart") and footer()[#footer()].icon == nil)

openPage(14, "sensors")
settle()
check("no Back on the first step", footer()[1].text ~= T("btn_back"))
check("Next on an untouched step says Next", footer()[#footer()].text == T("btn_next") and footer()[#footer()].enabled)

openPage(14, "receiver")
settle()
footer()[1].press()
tick()
check("Back from a step's first screen opens the step before",
  headers[#headers].title == T("name") .. " / 1. " .. T("step_sensors"), headers[#headers].title)

openPage(14, "finish")
settle()
press(T("btn_next"))
check("the last screen's way forward is Save and finish", footer()[#footer()].text == T("fin_button"))

do
  local ui = requireModule("app/setup_wizard_ui.lua")
  package.loaded["wfsuite.test.loaded_first"] = {}
  local owned = ui.notLoaded({"wfsuite.test.loaded_first", "wfsuite.test.absent"})
  check("a step frees only modules nothing else had loaded first",
    #owned == 1 and owned[1] == "wfsuite.test.absent")
  package.loaded["wfsuite.test.loaded_first"] = nil
end

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
