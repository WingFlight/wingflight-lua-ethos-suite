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

local answeredUpTo = 0
local function answerAll()
  inBackground = true
  while answeredUpTo < #sent do
    answeredUpTo = answeredUpTo + 1
    local m = sent[answeredUpTo]
    if m.processReply then
      local buf = {}
      local reply = replies[m.command]
      if type(reply) == "function" then reply = reply(m) end
      for i, b in ipairs(reply or m.simulatorResponse or {}) do buf[i] = b end
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

local function openPage(apiMinor, stepKey)
  fields, dialogs, sent, headers = {}, {}, {}, {}
  answeredUpTo = 0
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
check("the title names the step", headers[#headers].title == T("name") .. " / 7. " .. T("step_direction"),
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
press(T("dir_save_next"))
check("Save and continue writes EEPROM", #writesOf(250, before + 1) == 1)
tick()
tick()
check("then opens the next step, Binding limits",
  headers[#headers].title == T("name") .. " / 8. " .. T("step_limits"), headers[#headers].title)
check("with nothing left pending", headers[#headers].saveEnabled == false)
before = #sent
headers[#headers].opts.onBack()
check("Back with nothing pending leaves the wizard", ctx.back == 1)
local release = writesOf(0x5F1B, before + 1)
check("leaving releases the setup state", #release == 1 and bytes(release[1].payload) == "0,0,0")
check("leaving frees the wizard's own modules but keeps the override ones",
  package.loaded["wfsuite.lib.msp_mixer_rules"] == nil and package.loaded["wfsuite.app.setup_wizard_ui"] == nil
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
press(T("dir_continue"))
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
  and package.loaded["wfsuite.lib.acc_calibration_wait"] == nil)
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
check("airframe: the model type is flying wing", #cfgWrites == 1 and cfgWrites[1].payload[1] == 1)
check("airframe: the surfaces are elevons now", shows("surface_elevon"))

-- Servo type: digital on every surface servo, then save and restart.
openPage(14, "servotype")
settle()
before = #sent
press(T("st_digital"))
local st = writesOf(212, before + 1)
local allDigital = #st == 4
for _, m in ipairs(st) do if u16(m.payload, 12) ~= 333 then allDigital = false end end
check("servo type: every surface servo set to 333 Hz", allDigital, #st)
before = #sent
press(T("btn_save_restart"))
tick()
tick()
check("servo type: saves and restarts", #writesOf(250, before + 1) == 1 and #writesOf(68, before + 1) == 1)

-- Motor: the protocol, and a timed spin.
openPage(14, "motor")
settle()
before = #sent
press(T("mot_dshot600"))
check("motor: choosing DShot600 writes the motor config", #writesOf(222, before + 1) == 1 and shows("mot_changed"))
openPage(14, "motor")
settle()
press(T("mot_test"))
press(T("mot_prop_off"))
before = #sent
press(T("mot_spin_fmt"))
tick(0.3)
local spins = writesOf(195, before + 1)
check("motor: spins at 10%", #spins >= 1 and u16(spins[1].payload, 2) == 100, spins[1] and bytes(spins[1].payload))
before = #sent
tick(4)
local stops = writesOf(195, before + 1)
check("motor: and stops by itself", #stops >= 1 and u16(stops[#stops].payload, 2) == 0)

-- Centre: every surface held at its centre; nudging writes the Mid.
openPage(14, "centre")
settle()
local held = {}
for _, m in ipairs(writesOf(193)) do
  if s16(m.payload, 2) == 0 and #m.payload == 5 then held[m.payload[1]] = true end
end
check("centre: holds all four servos at centre", held[0] and held[1] and held[2] and held[3])
before = #sent
press("+10")
local mid = writesOf(212, before + 1)
check("centre: +10 moves servo 1's centre to 1510", #mid == 1 and mid[1].payload[1] == 0 and u16(mid[1].payload, 2) == 1510)

-- Limits: probe past the stored limits, then set Min.
openPage(14, "limits")
settle()
before = #sent
press(T("btn_start"))
local probe = writesOf(0x5F1C, before + 1)
check("limits: servo 1 is probed at its centre, timed", #probe >= 1 and bytes(probe[1].payload) == "0,0,0,16,39")
press("-50")
press("-50")
probe = writesOf(0x5F1C)
check("limits: stepping moves the probe", s16(probe[#probe].payload, 2) == -100)
before = #sent
press(T("lim_set_min"))
local minWrite = writesOf(212, before + 1)
check("limits: Set Min writes it", #minWrite == 1 and s16(minWrite[1].payload, 4) == -100)
check("limits: then asks for Max", shows("lim_todo_max"))

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
press("3. " .. T("step_airframe"))
check("the step list opens a step", headers[#headers].title == T("name") .. " / 3. " .. T("step_airframe"))
do
  local empty = {}
  for _ = 1, 32 * 14 do empty[#empty + 1] = 0 end
  replies[172] = empty
  openPage(14, "centre")
  settle()
  check("no surfaces: the step points to Airframe", button(T("go_airframe")) ~= nil)
  press(T("go_airframe"))
  check("and that opens it", headers[#headers].title == T("name") .. " / 3. " .. T("step_airframe"))
  replies[172] = nil
end

check("no form was built from a reply or a bus event", #forbidden == 0, table.concat(forbidden, ","))

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
