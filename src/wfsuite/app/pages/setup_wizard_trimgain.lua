-- Setup Wizard step: Trim and gain. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepTrimGain.svelte: a way to
-- trim in the air, and a knob for the stabilizer gain. Each control is found
-- by moving it: the AUX channel that clearly moves most from where it was
-- when Detect was pressed (lib/setup_wizard_controls.lua movedChannel(), on
-- the live MSP_RC channels). The adjustment ranges (trimRange(),
-- steppedTrimRange(), gainRange()) are written as soon as they are found,
-- so the knob and trims work on the bench straight away.
--
--   trimQ     trim buttons on one channel (the FC keeps the trim), a channel
--             per trim (the radio keeps it), or Auto trim only
--   howTo     what to set up on the radio for the choice, then Detect
--   listen    "press any trim button" / "press the roll trim" / "turn the knob"
--   buttons   live check: which trim button the channel shows
--   gainQ     one knob, one per axis, or none
--   done      what is set up
--
-- The configurator shows Ethos screenshots of the radio setup; here the
-- steps are text.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
local art = requireModule("app/setup_wizard_art.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({"wfsuite.lib.setup_wizard_controls", "wfsuite.lib.msp_adjustments"})
local controls = requireModule("lib/setup_wizard_controls.lua")
local adjustments = requireModule("lib/msp_adjustments.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.tg_title)@",
  intro = "@i18n(app.modules.setup_wizard.tg_intro)@",
  trimQ = "@i18n(app.modules.setup_wizard.tg_trim_q)@",
  trimButtons = "@i18n(app.modules.setup_wizard.tg_trim_buttons)@",
  trimChannels = "@i18n(app.modules.setup_wizard.tg_trim_channels)@",
  trimAuto = "@i18n(app.modules.setup_wizard.tg_trim_auto)@",
  howButtons = "@i18n(app.modules.setup_wizard.tg_how_buttons)@",
  howChannels = "@i18n(app.modules.setup_wizard.tg_how_channels)@",
  autoNote = "@i18n(app.modules.setup_wizard.tg_auto_note)@",
  pressButton = "@i18n(app.modules.setup_wizard.tg_press_button)@",
  pressTrim = "@i18n(app.modules.setup_wizard.tg_press_trim_fmt)@",
  turnKnob = "@i18n(app.modules.setup_wizard.tg_turn_knob)@",
  turnAxisKnob = "@i18n(app.modules.setup_wizard.tg_turn_axis_knob_fmt)@",
  buttonsCheck = "@i18n(app.modules.setup_wizard.tg_buttons_check)@",
  buttonNow = "@i18n(app.modules.setup_wizard.tg_button_now_fmt)@",
  buttonNone = "@i18n(app.modules.setup_wizard.tg_button_none_fmt)@",
  gainQ = "@i18n(app.modules.setup_wizard.tg_gain_q)@",
  gainSingle = "@i18n(app.modules.setup_wizard.tg_gain_single)@",
  gainSeparate = "@i18n(app.modules.setup_wizard.tg_gain_separate)@",
  gainNone = "@i18n(app.modules.setup_wizard.tg_gain_none)@",
  gainCentre = "@i18n(app.modules.setup_wizard.tg_gain_centre)@",
  full = "@i18n(app.modules.setup_wizard.tg_full)@",
  timedOut = "@i18n(app.modules.setup_wizard.tg_timed_out)@",
  found = "@i18n(app.modules.setup_wizard.tg_found_fmt)@",
  doneTitle = "@i18n(app.modules.setup_wizard.tg_done_title)@",
  trimRow = "@i18n(app.modules.setup_wizard.tg_row_trim)@",
  gainRow = "@i18n(app.modules.setup_wizard.tg_row_gain)@",
  auxFmt = "@i18n(app.modules.setup_wizard.tg_aux_fmt)@",
  start = "@i18n(app.modules.setup_wizard.btn_start)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
  detect = "@i18n(app.modules.setup_wizard.tg_detect)@",
  again = "@i18n(app.modules.setup_wizard.btn_again)@",
}

local AXIS_NAMES = {
  roll = "@i18n(app.modules.setup_wizard.axis_roll)@",
  pitch = "@i18n(app.modules.setup_wizard.axis_pitch)@",
  yaw = "@i18n(app.modules.setup_wizard.axis_yaw)@",
}

local AUX_OFFSET = 4          -- AUX1 is the fifth channel
local LISTEN_SECONDS = 15
-- A trim button moves its channel a little at a time; a knob a long way.
local MOVE_US = {trim = 40, buttons = 40, gain = 250}

local function new(wiz)
  local self = {liveRc = "rc"}
  local scr = ui.new(wiz)

  local ranges = nil
  local screen = "intro"
  local note = nil
  local listening = nil         -- {kind =, axis =, start =, peaks =, untilAt =, queue =}

  wiz.fetch({adj = function(ok, err) return adjustments.buildReadMessage(ok, err) end}, function(results)
    ranges = results.adj and results.adj.ranges or {}
    wiz.rebuild()
  end)

  local function go(name, n)
    screen, note = name, n
    wiz.rebuild()
  end

  local function auxValues()
    local out = {}
    for i = AUX_OFFSET + 1, #wiz.rc do out[#out + 1] = wiz.rc[i] end
    return out
  end

  local function writeRange(range)
    local index = controls.slotFor(ranges, range.adjFunction)
    if index < 0 then
      note = T.full
      return false
    end
    wiz.change("adj_" .. index, ranges[index] or adjustments.defaultRange(), function(o)
      bus.publish("msp.request", adjustments.buildWriteMessage(index, o))
    end)
    ranges[index] = range
    bus.publish("msp.request", adjustments.buildWriteMessage(index, range))
    return true
  end

  local function removeFunction(adjFunction)
    for i = 1, #ranges do
      if ranges[i] and ranges[i].adjFunction == adjFunction then
        local off = controls.resetToOff(ranges[i])
        wiz.change("adj_" .. i, ranges[i], function(o)
          bus.publish("msp.request", adjustments.buildWriteMessage(i, o))
        end)
        ranges[i] = off
        bus.publish("msp.request", adjustments.buildWriteMessage(i, off))
      end
    end
  end

  local function removeAll(functions)
    for _, axis in ipairs(controls.AXES) do removeFunction(functions[axis]) end
  end

  -- queue: the detections to run in turn, {kind =, axis =} each.
  local function listen(queue, after)
    local first = table.remove(queue, 1)
    local start = auxValues()
    local peaks = {}
    for i = 1, #start do peaks[i] = 0 end
    listening = {kind = first.kind, axis = first.axis, start = start, peaks = peaks,
      untilAt = os.clock() + LISTEN_SECONDS, queue = queue, after = after}
    go("listen")
  end

  local function onDetected(aux)
    local l = listening
    local ok = true
    if l.kind == "trim" then
      ok = writeRange(controls.trimRange(l.axis, aux))
    elseif l.kind == "buttons" then
      for _, axis in ipairs(controls.AXES) do ok = writeRange(controls.steppedTrimRange(axis, aux)) and ok end
    elseif l.axis then
      ok = writeRange(controls.gainRange(l.axis, aux))
    else
      for _, axis in ipairs(controls.AXES) do ok = writeRange(controls.gainRange(axis, aux)) and ok end
    end
    listening = nil
    if ok and #l.queue > 0 then
      listen(l.queue, l.after)
    else
      go(l.after, ok and string.format(T.found, aux + 1) or T.full)
    end
  end

  local function prompt(l)
    if l.kind == "buttons" then return T.pressButton end
    if l.kind == "trim" then return string.format(T.pressTrim, AXIS_NAMES[l.axis]) end
    if l.axis then return string.format(T.turnAxisKnob, AXIS_NAMES[l.axis]) end
    return T.turnKnob
  end

  local function describeTrim()
    local mode = controls.trimMode(ranges)
    if mode == "buttons" then
      return T.trimButtons .. ", " .. string.format(T.auxFmt, controls.channelOf(ranges, controls.SERVO_TRIM.roll) + 1)
    elseif mode == "programmable" then
      return T.trimChannels
    end
    return T.trimAuto
  end

  local function describeGain()
    local mode = controls.gainMode(ranges)
    if mode == "single" then
      return T.gainSingle .. ", " .. string.format(T.auxFmt, controls.channelOf(ranges, controls.MASTER_GAIN.roll) + 1)
    elseif mode == "separate" then
      return T.gainSeparate
    end
    return T.gainNone
  end

  local function drawButtonCheck(x, y, w, h, colors)
    local aux = controls.channelOf(ranges, controls.SERVO_TRIM.roll)
    local value = aux and wiz.rc[AUX_OFFSET + aux + 1]
    local b = controls.buttonAt(value)
    lcd.font(FONT_STD)
    lcd.color(b and colors.active or colors.muted)
    local text = b and string.format(T.buttonNow, b.button) or string.format(T.buttonNone, (aux or 0) + 1, value or 0)
    lcd.drawText(x + math.floor(w / 2), y + math.floor(h / 3), text, CENTERED)
  end

  function self.build()
    scr:begin()
    if not ranges then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end

    if screen == "intro" then
      scr:text(T.title, T.intro)
      scr:picture(art.layout(wiz.surfaces(), nil))
      return scr:row(nil, {{text = T.start, primary = true, press = function() go("trimQ") end}})

    elseif screen == "trimQ" then
      local mode = controls.trimMode(ranges)
      scr:text(T.title, T.trimQ, note)
      -- The grid first: the encoder visits fields in the order they are made.
      local focus = scr:grid({
        {text = T.trimButtons, primary = mode == "buttons", press = function() go("howButtons") end},
        {text = T.trimChannels, primary = mode == "programmable", press = function() go("howChannels") end},
        {text = T.trimAuto, primary = mode == nil, press = function()
          removeAll(controls.SERVO_TRIM)
          go("gainQ", T.autoNote)
        end},
      }, 1)
      -- Next keeps the trim as it is set up now.
      local forward = scr:row(function() go("intro") end, nil, {text = T.next, press = function() go("gainQ") end})
      return focus or forward

    elseif screen == "howButtons" or screen == "howChannels" then
      local buttons = screen == "howButtons"
      scr:text(buttons and T.trimButtons or T.trimChannels, buttons and T.howButtons or T.howChannels, note, true)
      local detectNext = {text = T.next, press = function() go("gainQ") end}
      return scr:row(function() go("trimQ") end, {
        {text = T.detect, primary = true, needsMotion = true, press = function()
          -- Switching between the two kinds starts again from scratch.
          removeAll(controls.SERVO_TRIM)
          if buttons then
            listen({{kind = "buttons"}}, "buttons")
          else
            listen({{kind = "trim", axis = "roll"}, {kind = "trim", axis = "pitch"}, {kind = "trim", axis = "yaw"}},
              "gainQ")
          end
        end},
      }, detectNext)

    elseif screen == "listen" then
      scr:text(T.title, prompt(listening))
      -- Back cancels the listening.
      return scr:row(function()
        local after = listening and listening.after or "trimQ"
        listening = nil
        go(after == "buttons" and "howButtons" or "trimQ")
      end, nil, false)

    elseif screen == "buttons" then
      scr:text(T.trimButtons, T.buttonsCheck, note, true)
      scr:draw(drawButtonCheck)
      return scr:row(function() go("howButtons") end,
        {{text = T.again, press = function() listen({{kind = "buttons"}}, "buttons") end}},
        {text = T.next, press = function() go("gainQ") end})

    elseif screen == "gainQ" then
      local mode = controls.gainMode(ranges)
      scr:text(T.title, T.gainQ .. " " .. T.gainCentre, note)
      -- The grid first: the encoder visits fields in the order they are made.
      local focus = scr:grid({
        {text = T.gainSingle, primary = mode == "single", press = function()
          listen({{kind = "gain"}}, "done")
        end},
        {text = T.gainSeparate, primary = mode == "separate", press = function()
          listen({{kind = "gain", axis = "roll"}, {kind = "gain", axis = "pitch"},
            {kind = "gain", axis = "yaw"}}, "done")
        end},
        {text = T.gainNone, primary = mode == "none", press = function()
          removeAll(controls.MASTER_GAIN)
          go("done")
        end},
      }, 1)
      -- Next keeps the gain knob as it is set up now.
      local forward = scr:row(function() go("trimQ") end, nil, {text = T.next, press = function() go("done") end})
      return focus or forward
    end

    scr:text(T.doneTitle, nil, note)
    scr:rows({{T.trimRow, describeTrim()}, {T.gainRow, describeGain()}})
    return scr:row(function() go("gainQ") end)
  end

  function self.paint() scr:paint() end

  local lastButton = nil
  function self.wakeup(now)
    if screen == "buttons" then
      local aux = controls.channelOf(ranges, controls.SERVO_TRIM.roll)
      local value = aux and wiz.rc[AUX_OFFSET + aux + 1]
      if value ~= lastButton then
        lastButton = value
        wiz.invalidate()
      end
    end
    local l = listening
    if not l or screen ~= "listen" then return end
    if now > l.untilAt then
      listening = nil
      go(l.after == "buttons" and "howButtons" or "trimQ", T.timedOut)
      return
    end
    local values = auxValues()
    for i = 1, #values do
      if l.start[i] == nil then l.start[i], l.peaks[i] = values[i], 0 end
      local move = math.abs(values[i] - l.start[i])
      if move > (l.peaks[i] or 0) then l.peaks[i] = move end
    end
    local aux = controls.movedChannel(l.peaks, {}, MOVE_US[l.kind])
    if aux >= 0 then onDetected(aux) end
  end

  function self.released() scr:refresh() end

  return self
end

return {new = new, owned = OWNED}
