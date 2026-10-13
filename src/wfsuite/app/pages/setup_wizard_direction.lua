-- Setup Wizard step: Direction. Opened by app/pages/setup_wizard.lua.
--
-- Checks that every control surface moves the right way. It asks the same
-- question as the Configurator's src/tabs/setup_wizard/StepDirection.svelte
-- and fixes things by the same rules, but as a guided sequence for a radio
-- screen: one question per screen, a picture of the model seen from behind
-- (app/setup_wizard_art.lua) with arrows for how the surfaces should move,
-- and two big answer buttons. The wizard moves the surfaces itself: it flicks
-- the checked axis between centre and the test movement, so the direction is
-- easy to see.
--
-- Screens:
--   intro    what is about to happen, Start
--   check    one axis: picture, "Like this" / "Not like this"
--   all      several surfaces and one was wrong: all of them, or only some?
--   identify only some: each surface's servo wiggles in turn, "this one?"
--   cantfix  a wrong surface that also works another axis cannot simply be
--            reversed: say so
--   done     what the wizard changed; check again, or save and go on
--
-- The fixes, as in the Configurator: a wrong surface on its own axis has its
-- servo reversed; an axis on which every surface is wrong is inverted
-- (its Axis Throw negated), which also keeps surfaces that work another axis
-- right; the flap channel has no axis to invert, so each flap servo is
-- reversed. A wrong surface that also works another axis is left alone, with
-- a pointer to Mixer Rules. After a fix the same check runs again.
--
-- Signs follow the stabilized inputs: roll + is right roll, pitch + is stick
-- forward (nose down), and yaw + is yaw left, since RC yaw is negated once in
-- the firmware's setpoint.c. The flap check moves the flap channel, positive
-- being flaps down. It comes first: flaps that follow the ailerons get their
-- roll direction from their flap direction.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")
local art = requireModule("app/setup_wizard_art.lua")

local CHECKS = {
  {axis = "flap", sign = 1,
    title = "@i18n(app.modules.setup_wizard.dir_check_flap)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_flap)@"},
  {axis = "pitch", sign = -1,
    title = "@i18n(app.modules.setup_wizard.dir_check_pitch)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_pitch)@"},
  {axis = "roll", sign = 1,
    title = "@i18n(app.modules.setup_wizard.dir_check_roll)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_roll)@"},
  {axis = "yaw", sign = -1,
    title = "@i18n(app.modules.setup_wizard.dir_check_yaw)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_yaw)@"},
}

local AXIS_NAMES = {
  pitch = "@i18n(app.modules.setup_wizard.dir_axis_pitch)@",
  roll = "@i18n(app.modules.setup_wizard.dir_axis_roll)@",
  yaw = "@i18n(app.modules.setup_wizard.dir_axis_yaw)@",
}

-- Test movement, percent of full stick: the Move button steps through these.
local DEFLECTIONS = {25, 35, 50, 15}

-- The checked axis flicks between centre and the test movement.
local FLICK_INTERVAL = 0.8
-- Identify: the servo wiggles +-WIGGLE_RAW around its centre.
local WIGGLE_RAW = 300
local WIGGLE_INTERVAL = 0.3

local BUTTON_GAP = 6

-- Whether this check moves the surface. The flap check leaves out pitch
-- surfaces carrying a Flap Compensation rule: that mix is tuned, not checked.
local function movedBy(surface, check)
  if check.axis == "flap" then
    return surface.kind == "flap" or surface.kind == "flaperon"
  end
  return surface.axes[check.axis] ~= nil
end

local function servoList(list)
  local names = {}
  for i = 1, #list do names[i] = tostring(list[i].servo + 1) end
  return table.concat(names, ", ")
end

local function new(wiz)
  local self = {}

  local checks = {}
  do
    local surfaces = wiz.surfaces()
    for i = 1, #CHECKS do
      for j = 1, #surfaces do
        if movedBy(surfaces[j], CHECKS[i]) then
          checks[#checks + 1] = CHECKS[i]
          break
        end
      end
    end
  end

  local screen = "intro"
  local ci = 1                 -- index into checks
  local deflectionIndex = 1
  local status = nil           -- line shown on the check screen after a fix
  local moved = {}             -- surfaces the current check moves
  local identifyIndex, wrongOnes = 1, {}
  local cantFix = {}
  local reversed = {}          -- servo -> true when reversed an odd number of times
  local inverted = {}          -- axis -> true when inverted an odd number of times
  local flapReversed = false

  -- What paint draws, worked out when a screen is built.
  local view = {top = 0, bottom = 0, title = nil, lines = {}, accentFrom = nil, picture = nil, caption = nil}
  local buttons = {}

  -- Motion: "axis" flicks the checked axis, "servo" wiggles one servo.
  local motion, motionServo, phase, nextMoveAt = nil, nil, false, 0

  local function check() return checks[ci] end
  local function own(surface) return surfacesLib.primaryAxis(surface) == check().axis end

  local function stopMotion()
    if motion == "servo" and motionServo then wiz.releaseServo(motionServo) end
    if motion == "axis" then wiz.releaseAxes() end
    motion, motionServo = nil, nil
  end

  local function startAxisMotion()
    stopMotion()
    -- Every other axis at centre and the flaps up, so a mix does not hide
    -- the one being checked; then only the checked one moves.
    if wiz.holdAxes({roll = 0, pitch = 0, yaw = 0, flap = 0}) then
      motion, phase, nextMoveAt = "axis", false, 0
    end
  end

  local function startServoMotion(servo)
    stopMotion()
    motion, motionServo, phase, nextMoveAt = "servo", servo, false, 0
  end

  local function collectMoved()
    moved = {}
    local surfaces = wiz.surfaces()
    for i = 1, #surfaces do
      if movedBy(surfaces[i], check()) then moved[#moved + 1] = surfaces[i] end
    end
  end

  local function reverse(surface)
    local config = wiz.configs[surface.servo]
    config.flags = (config.flags or 0) ~ surfacesLib.SERVO_FLAG_REVERSE
    wiz.sendServo(surface.servo)
    reversed[surface.servo] = not reversed[surface.servo] or nil
    if surface.kind == "flap" then flapReversed = true end
  end

  local function go(name)
    screen = name
    wiz.rebuild()
  end

  local function nextCheck()
    status = nil
    if ci < #checks then
      ci = ci + 1
      go("check")
    else
      go("done")
    end
  end

  -- Reverse the ones that can be; the rest go to the cantfix screen.
  local function fix(list)
    local done = {}
    cantFix = {}
    for i = 1, #list do
      if own(list[i]) then
        reverse(list[i])
        done[#done + 1] = list[i]
      else
        cantFix[#cantFix + 1] = list[i]
      end
    end
    if #done > 0 then
      status = string.format("@i18n(app.modules.setup_wizard.dir_status_reversed_fmt)@", servoList(done))
    else
      status = "@i18n(app.modules.setup_wizard.dir_status_none)@"
    end
    go(#cantFix > 0 and "cantfix" or "check")
  end

  local function allWrong()
    if check().axis == "flap" then
      fix(moved)
      return
    end
    wiz.invertAxis(check().axis)
    inverted[check().axis] = not inverted[check().axis] or nil
    status = "@i18n(app.modules.setup_wizard.dir_status_inverted)@"
    go("check")
  end

  local function answerIdentify(wrong)
    if wrong then wrongOnes[#wrongOnes + 1] = moved[identifyIndex] end
    if identifyIndex < #moved then
      identifyIndex = identifyIndex + 1
      go("identify")
    else
      fix(wrongOnes)
    end
  end

  local function notLikeThis()
    if #moved == 1 then
      fix(moved)
    else
      go("all")
    end
  end

  -------------------------------------------------------------------------
  -- Building a screen: the answer buttons along the bottom, and what paint
  -- draws between the header and them.
  -------------------------------------------------------------------------

  -- specs: {{text =, press =, weight =, primary =}, ...} left to right.
  local function addButtons(specs)
    local width, height = lcd.getWindowSize()
    local h = math.max(36, math.floor(height * 0.15))
    local y = height - h - 4
    local total = 0
    for i = 1, #specs do total = total + (specs[i].weight or 1) end
    local free = width - wiz.FORM_RIGHT_PADDING - BUTTON_GAP * (#specs - 1)
    local x, focus = 0, nil
    buttons = {}
    for i = 1, #specs do
      local w = math.floor(free * (specs[i].weight or 1) / total)
      local b = form.addButton(nil, {x = x, y = y, w = w, h = h}, {
        text = specs[i].text,
        options = (specs[i].small and FONT_S or FONT_STD) + CENTERED,
        press = specs[i].press,
      })
      -- The field is Ethos userdata: the flag lives beside it.
      buttons[#buttons + 1] = {field = b, needsMotion = specs[i].needsMotion}
      if specs[i].primary then focus = b end
      x = x + w + BUTTON_GAP
    end
    view.bottom = y - 4
    return focus
  end

  local function setText(title, body, accent)
    local width = lcd.getWindowSize()
    view.title = title
    view.lines = body and wiz.wrapLines(body, width - 16, FONT_S) or {}
    view.accentFrom = nil
    if accent then
      view.accentFrom = #view.lines + 1
      local extra = wiz.wrapLines(accent, width - 16, FONT_S)
      for i = 1, #extra do view.lines[#view.lines + 1] = extra[i] end
    end
  end

  local function refreshButtons()
    local canMove = wiz.canMove()
    for i = 1, #buttons do
      if buttons[i].needsMotion and buttons[i].field then buttons[i].field:enable(canMove) end
    end
  end

  local function deflection() return DEFLECTIONS[deflectionIndex] end

  -- Returns the field to focus.
  function self.build()
    view.top = form.height() + 4
    view.picture, view.caption = nil, nil
    local c = check()
    local focus

    if screen == "intro" then
      stopMotion()
      setText("@i18n(app.modules.setup_wizard.dir_intro_title)@", "@i18n(app.modules.setup_wizard.dir_intro)@")
      view.picture = art.layout(wiz.surfaces(), nil)
      focus = addButtons({
        {text = "@i18n(app.modules.setup_wizard.dir_start)@", primary = true, needsMotion = true,
          press = function() ci = 1; go("check") end},
      })

    elseif screen == "check" then
      collectMoved()
      startAxisMotion()
      setText(c.title, c.expect .. " " .. "@i18n(app.modules.setup_wizard.dir_q_match)@", status)
      view.picture = art.layout(wiz.surfaces(), c.axis)
      view.caption = "@i18n(app.modules.setup_wizard.dir_from_behind)@"
      focus = addButtons({
        {text = string.format("@i18n(app.modules.setup_wizard.dir_move_fmt)@", deflection()), weight = 0.6,
          small = true, needsMotion = true,
          press = function()
            deflectionIndex = deflectionIndex % #DEFLECTIONS + 1
            go("check")
          end},
        {text = "@i18n(app.modules.setup_wizard.dir_unlike)@", needsMotion = true, press = notLikeThis},
        {text = "@i18n(app.modules.setup_wizard.dir_like)@", primary = true, needsMotion = true, press = nextCheck},
      })

    elseif screen == "all" then
      setText(c.title, "@i18n(app.modules.setup_wizard.dir_q_all)@")
      view.picture = art.layout(wiz.surfaces(), c.axis)
      view.caption = "@i18n(app.modules.setup_wizard.dir_from_behind)@"
      focus = addButtons({
        {text = "@i18n(app.modules.setup_wizard.dir_some)@", press = function()
          identifyIndex, wrongOnes = 1, {}
          go("identify")
        end},
        {text = "@i18n(app.modules.setup_wizard.dir_all)@", primary = true, press = allWrong},
      })

    elseif screen == "identify" then
      local surface = moved[identifyIndex]
      startServoMotion(surface.servo)
      setText(c.title, string.format("@i18n(app.modules.setup_wizard.dir_identify_fmt)@", surface.servo + 1,
        wiz.kindName(surface.kind), identifyIndex, #moved))
      view.picture = art.layout(wiz.surfaces(), c.axis)
      view.caption = "@i18n(app.modules.setup_wizard.dir_from_behind)@"
      focus = addButtons({
        -- Focus starts on No: a stray press must not reverse a servo.
        {text = "@i18n(app.modules.setup_wizard.dir_no)@", primary = true, needsMotion = true,
          press = function() answerIdentify(false) end},
        {text = "@i18n(app.modules.setup_wizard.dir_yes)@", needsMotion = true,
          press = function() answerIdentify(true) end},
      })

    elseif screen == "cantfix" then
      stopMotion()
      setText(c.title, string.format("@i18n(app.modules.setup_wizard.dir_cant_fix_fmt)@", servoList(cantFix)))
      focus = addButtons({
        {text = "@i18n(app.modules.setup_wizard.dir_continue)@", primary = true, press = function() go("check") end},
      })

    else -- done
      stopMotion()
      local changes = {}
      for servo in pairs(reversed) do
        changes[#changes + 1] = string.format("@i18n(app.modules.setup_wizard.dir_change_servo_fmt)@", servo + 1)
      end
      table.sort(changes)
      for i = 1, #checks do
        local axis = checks[i].axis
        if inverted[axis] then
          changes[#changes + 1] = string.format("@i18n(app.modules.setup_wizard.dir_change_axis_fmt)@",
            AXIS_NAMES[axis])
        end
      end
      local body
      if #changes == 0 then
        body = "@i18n(app.modules.setup_wizard.dir_done_ok)@"
      else
        body = "@i18n(app.modules.setup_wizard.dir_done_changes)@ " .. table.concat(changes, ", ") .. "."
      end
      setText("@i18n(app.modules.setup_wizard.dir_done_title)@", body,
        flapReversed and "@i18n(app.modules.setup_wizard.dir_flap_radio)@" or nil)
      view.picture = art.layout(wiz.surfaces(), nil)
      focus = addButtons({
        {text = "@i18n(app.modules.setup_wizard.dir_again)@", press = function()
          ci, status = 1, nil
          go("check")
        end},
        {text = wiz.isLastStep() and "@i18n(app.modules.setup_wizard.dir_save_finish)@"
          or "@i18n(app.modules.setup_wizard.dir_save_next)@", primary = true, press = function() wiz.finishStep() end},
      })
    end

    refreshButtons()
    return focus
  end

  function self.paint()
    local colors = art.colors()
    local width = lcd.getWindowSize()
    local y = view.top
    if view.title then
      lcd.font(FONT_STD)
      lcd.color(colors.text)
      lcd.drawText(8, y, view.title, LEFT)
      local _, th = lcd.getTextSize(view.title)
      y = y + th + 2
    end
    lcd.font(FONT_S)
    for i = 1, #view.lines do
      lcd.color((view.accentFrom and i >= view.accentFrom) and colors.active or colors.text)
      lcd.drawText(8, y, view.lines[i], LEFT)
      local _, th = lcd.getTextSize(view.lines[i])
      y = y + th
    end
    if view.picture then
      local bottom = view.bottom
      if view.caption then
        lcd.font(FONT_XS)
        local _, ch = lcd.getTextSize(view.caption)
        lcd.color(colors.muted)
        lcd.drawText(8, bottom - ch, view.caption, LEFT)
        bottom = bottom - ch
      end
      art.draw(view.picture, 0, y + 4, width, bottom - y - 6, colors)
    end
  end

  local lastCanMove = nil

  function self.wakeup(now)
    local canMove = wiz.canMove()
    if canMove ~= lastCanMove then
      lastCanMove = canMove
      refreshButtons()
      if canMove and screen == "check" and motion == nil then startAxisMotion() end
      if canMove and screen == "identify" and motion == nil then startServoMotion(moved[identifyIndex].servo) end
    end
    if not motion or now < nextMoveAt then return end
    phase = not phase
    if motion == "axis" then
      local c = check()
      local ok = wiz.holdAxis(c.axis, phase and c.sign * deflection() / 100 or 0)
      nextMoveAt = now + FLICK_INTERVAL
      if not ok then motion = nil end
    else
      local ok = wiz.holdServo(motionServo, phase and WIGGLE_RAW or -WIGGLE_RAW)
      nextMoveAt = now + WIGGLE_INTERVAL
      if not ok then motion = nil end
    end
  end

  -- The shell let go of everything (armed, link lost, refused).
  function self.released()
    motion, motionServo = nil, nil
    refreshButtons()
  end

  function self.leave()
    stopMotion()
    buttons = {}
  end

  return self
end

return {new = new}
