-- Setup Wizard step: Direction. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's
-- src/tabs/setup_wizard/StepDirection.svelte. The wizard moves one axis at a
-- time with mixer overrides, and the pilot says for each surface whether it
-- went the right way. A wrong surface whose own axis this is gets its servo
-- reversed; an axis on which every surface is wrong is inverted instead, so a
-- surface that also works another axis is not broken. Identify (Wiggle) moves
-- one servo back and forth so the pilot can see which surface a row is.
--
-- Signs follow the stabilized inputs: roll + is right roll, pitch + is stick
-- forward (nose down), and yaw + is yaw left, since RC yaw is negated once in
-- the firmware's setpoint.c. The flap check moves the flap channel instead,
-- positive being flaps down. It comes first: flaps that follow the ailerons
-- get their roll direction from their flap direction.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local CHECKS = {
  {axis = "flap", sign = 1,
    name = "@i18n(app.modules.setup_wizard.dir_check_flap)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_flap)@"},
  {axis = "pitch", sign = -1,
    name = "@i18n(app.modules.setup_wizard.dir_check_pitch)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_pitch)@"},
  {axis = "roll", sign = 1,
    name = "@i18n(app.modules.setup_wizard.dir_check_roll)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_roll)@"},
  {axis = "yaw", sign = -1,
    name = "@i18n(app.modules.setup_wizard.dir_check_yaw)@",
    expect = "@i18n(app.modules.setup_wizard.dir_expect_yaw)@"},
}

-- Percent of full stick.
local DEFLECTIONS = {
  {"@i18n(app.modules.setup_wizard.dir_small)@", 15},
  {"@i18n(app.modules.setup_wizard.dir_medium)@", 25},
  {"@i18n(app.modules.setup_wizard.dir_large)@", 35},
  {"@i18n(app.modules.setup_wizard.dir_half)@", 50},
}

local TEXT_DONE = "@i18n(app.modules.setup_wizard.dir_done)@"
local TEXT_FIXED = "@i18n(app.modules.setup_wizard.dir_fixed)@"

-- Identify: six moves of +-300 a quarter second apart, then let go.
local WIGGLE_MOVES = 6
local WIGGLE_RAW = 300
local WIGGLE_INTERVAL = 0.25

-- Whether this check moves the surface. The flap check leaves out pitch
-- surfaces carrying a Flap Compensation rule: that mix is tuned, not checked.
local function movedBy(surface, check)
  if check.axis == "flap" then
    return surface.kind == "flap" or surface.kind == "flaperon"
  end
  return surface.axes[check.axis] ~= nil
end

local function new(wiz)
  local self = {livePositions = true}

  local checks = {}
  for i = 1, #CHECKS do
    local check = CHECKS[i]
    local surfaces = wiz.surfaces()
    for j = 1, #surfaces do
      if movedBy(surfaces[j], check) then
        checks[#checks + 1] = check
        break
      end
    end
  end

  local selected = 1
  local deflection = DEFLECTIONS[1][2]
  local holding = false
  local answers = {}     -- [axis][servo] = "ok" | "fixed"
  for i = 1, #checks do answers[checks[i].axis] = {} end

  local wiggle = nil     -- {servo =, count =, nextAt =}

  local rows = {}        -- {servo =, field =, shown =} for the selected check
  local moveButton, stopButton, checkField = nil, nil, nil
  local focusCheck = false
  local lastCanMove = nil

  local function check() return checks[selected] end

  local function rowText(row)
    local state = answers[check().axis][row.servo]
    if state == "ok" then return TEXT_DONE end
    if state == "fixed" then return TEXT_FIXED end
    local us = wiz.positions[row.servo]
    return us and tostring(us) or "-"
  end

  -- Only on change: the value is drawn every wakeup otherwise.
  local function refreshRow(row)
    local state = answers[check().axis][row.servo]
    local key = state or wiz.positions[row.servo]
    if key == row.shown then return end
    row.shown = key
    if row.field then row.field:value(rowText(row)) end
  end

  local function refreshButtons()
    local canMove = wiz.canMove()
    lastCanMove = canMove
    if moveButton then moveButton:enable(canMove and not holding) end
    if stopButton then stopButton:enable(holding) end
    for i = 1, #rows do
      if rows[i].identify then rows[i].identify:enable(canMove) end
    end
  end

  local function hold()
    local c = check()
    local values = {roll = 0, pitch = 0, yaw = 0, flap = 0}
    values[c.axis] = c.sign * deflection / 100
    holding = wiz.holdAxes(values) == true
    refreshButtons()
  end

  -- Lets the surfaces go but keeps the check open for answering.
  local function stop()
    holding = false
    wiz.releaseAxes()
    refreshButtons()
  end

  local function answer(surface, correct)
    answers[check().axis][surface.servo] = correct and "ok" or "fixed"
    if not correct then
      local config = wiz.configs[surface.servo]
      config.flags = (config.flags or 0) ~ surfacesLib.SERVO_FLAG_REVERSE
      wiz.sendServo(surface.servo)
    end
    for i = 1, #rows do refreshRow(rows[i]) end
  end

  local function invertAxis()
    local c = check()
    wiz.invertAxis(c.axis)
    local surfaces = wiz.surfaces()
    for i = 1, #surfaces do
      if movedBy(surfaces[i], c) then answers[c.axis][surfaces[i].servo] = "fixed" end
    end
    for i = 1, #rows do refreshRow(rows[i]) end
  end

  local function identify(servo)
    if wiggle and wiggle.servo ~= servo then wiz.releaseServo(wiggle.servo) end
    wiggle = {servo = servo, count = 0, nextAt = 0}
  end

  local function addSurfaceRow(surface, c)
    local line = form.addLine(wiz.surfaceLabel(surface))
    local y, h = wiz.lineMetrics(line)
    local width = wiz.windowWidth()
    local gap = 4
    local wBtn = math.floor(width * 0.135)
    local wVal = math.floor(width * 0.15)
    local xWrong = width - wiz.FORM_RIGHT_PADDING - wBtn
    local xOk = xWrong - gap - wBtn
    local xId = xOk - gap - wBtn
    local xVal = xId - gap - wVal

    local row = {servo = surface.servo}
    row.field = form.addStaticText(line, {x = xVal, y = y, w = wVal, h = h}, "", RIGHT)
    row.identify = form.addButton(line, {x = xId, y = y, w = wBtn, h = h}, {
      text = "@i18n(app.modules.setup_wizard.dir_identify)@",
      options = FONT_S + CENTERED,
      press = function() identify(surface.servo) end,
    })
    form.addButton(line, {x = xOk, y = y, w = wBtn, h = h}, {
      text = "@i18n(app.modules.setup_wizard.dir_correct)@",
      options = FONT_S + CENTERED,
      press = function() answer(surface, true) end,
    })
    -- Only on the surface's own axis: reversing a surface that also works
    -- another axis would break that one (see the hint below the rows).
    local wrong = form.addButton(line, {x = xWrong, y = y, w = wBtn, h = h}, {
      text = "@i18n(app.modules.setup_wizard.dir_wrong)@",
      options = FONT_S + CENTERED,
      press = function() answer(surface, false) end,
    })
    if wrong and wrong.enable then wrong:enable(surfacesLib.primaryAxis(surface) == c.axis) end
    rows[#rows + 1] = row
    refreshRow(row)
  end

  -- Returns the field to focus.
  function self.build()
    rows = {}
    local c = check()

    wiz.addWrapped("@i18n(app.modules.setup_wizard.dir_hands_off)@")

    form.addChoiceField(form.addLine("@i18n(app.modules.setup_wizard.dir_movement)@"), nil, DEFLECTIONS,
      function() return deflection end,
      function(value)
        deflection = value
        if holding then hold() end
      end)

    local choices = {}
    for i = 1, #checks do choices[i] = {checks[i].name, i} end
    checkField = form.addChoiceField(form.addLine("@i18n(app.modules.setup_wizard.dir_check)@"), nil, choices,
      function() return selected end,
      function(value)
        if value == selected then return end
        if holding then stop() end
        selected = value
        focusCheck = true
        wiz.rebuild()
      end)

    wiz.addWrapped(c.expect)

    local line = form.addLine("@i18n(app.modules.setup_wizard.dir_surfaces)@")
    local y, h = wiz.lineMetrics(line)
    local width = wiz.windowWidth()
    local wBtn = math.floor(width * 0.2)
    local xStop = width - wiz.FORM_RIGHT_PADDING - wBtn
    moveButton = form.addButton(line, {x = xStop - 4 - wBtn, y = y, w = wBtn, h = h}, {
      text = "@i18n(app.modules.setup_wizard.dir_move)@",
      options = FONT_S + CENTERED,
      press = function() hold() end,
    })
    stopButton = form.addButton(line, {x = xStop, y = y, w = wBtn, h = h}, {
      text = "@i18n(app.modules.setup_wizard.dir_stop)@",
      options = FONT_S + CENTERED,
      press = function() stop() end,
    })

    local anyMixed, anyFlapFollow = false, false
    local surfaces = wiz.surfaces()
    for i = 1, #surfaces do
      local surface = surfaces[i]
      if movedBy(surface, c) then
        addSurfaceRow(surface, c)
        if surfacesLib.primaryAxis(surface) ~= c.axis then
          if surface.kind == "flap" then anyFlapFollow = true else anyMixed = true end
        end
      end
    end

    if c.axis == "flap" then
      wiz.addWrapped("@i18n(app.modules.setup_wizard.dir_flap_radio)@")
    else
      local invertLine = form.addLine("@i18n(app.modules.setup_wizard.dir_all_wrong)@")
      local iy, ih = wiz.lineMetrics(invertLine)
      local wInv = math.floor(width * 0.3)
      form.addButton(invertLine, {x = width - wiz.FORM_RIGHT_PADDING - wInv, y = iy, w = wInv, h = ih}, {
        text = "@i18n(app.modules.setup_wizard.dir_invert)@",
        options = FONT_S + CENTERED,
        press = function() invertAxis() end,
      })
    end
    if anyMixed then wiz.addWrapped("@i18n(app.modules.setup_wizard.dir_mixed_hint)@") end
    if anyFlapFollow then wiz.addWrapped("@i18n(app.modules.setup_wizard.dir_flap_follow_hint)@") end

    refreshButtons()
    if focusCheck then
      focusCheck = false
      return checkField
    end
    return nil
  end

  function self.wakeup(now)
    if wiggle and now >= wiggle.nextAt then
      if wiggle.count >= WIGGLE_MOVES then
        wiz.releaseServo(wiggle.servo)
        wiggle = nil
      else
        local raw = (wiggle.count % 2 == 0) and WIGGLE_RAW or -WIGGLE_RAW
        if wiz.holdServo(wiggle.servo, raw) then
          wiggle.count = wiggle.count + 1
          wiggle.nextAt = now + WIGGLE_INTERVAL
        else
          wiggle = nil
        end
      end
    end
    for i = 1, #rows do refreshRow(rows[i]) end
    if wiz.canMove() ~= lastCanMove then refreshButtons() end
  end

  -- The shell let go of everything (armed, link lost, refused).
  function self.released()
    holding = false
    wiggle = nil
    refreshButtons()
  end

  function self.leave()
    holding = false
    wiggle = nil
    rows = {}
    moveButton, stopButton, checkField = nil, nil, nil
  end

  return self
end

return {new = new}
