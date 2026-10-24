-- Setup Wizard step: Binding limits. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepLimits.svelte, as one
-- screen per side of each surface (servo 1 Min, servo 1 Max, servo 2 Min, ...)
-- with one counter over all of them, so there is no step inside the step.
-- The servo is held by a probe (MSP2_WING_SET_SERVO_PROBE,
-- lib/msp_servo_probe.lua) at Mid + an offset that ignores the stored
-- Min/Max, so the stored limits are never widened while exploring. Step it
-- until the surface binds, back off one step, and Set: the offset is written
-- as that screen's limit. Set only saves the screen's own side. Next skips
-- the screen, keeping the stored limit; Back returns to the screen before.
-- The intro shows the method as three servo dials
-- (app/setup_wizard_art.lua's servoDial()), and each screen shows its servo
-- on one.
--
-- The range explored is what the servo's travel and signal range allow at
-- this centre (the configurator's openRange()). A flap's limits are its end
-- points: setting one also sets the scale on that side so the flap channel's
-- end lands exactly on it (matchFlapScale()).

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
local art = requireModule("app/setup_wizard_art.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.lim_title)@",
  intro = "@i18n(app.modules.setup_wizard.lim_intro)@",
  min = "@i18n(app.modules.setup_wizard.lim_todo_min)@",
  max = "@i18n(app.modules.setup_wizard.lim_todo_max)@",
  head = "@i18n(app.modules.setup_wizard.lim_head_fmt)@",
  now = "@i18n(app.modules.setup_wizard.lim_now_fmt)@",
  flap = "@i18n(app.modules.setup_wizard.lim_flap)@",
  set = "@i18n(app.modules.setup_wizard.lim_set)@",
  minLabel = "@i18n(app.modules.setup_wizard.lim_min)@",
  maxLabel = "@i18n(app.modules.setup_wizard.lim_max)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  doneTitle = "@i18n(app.modules.setup_wizard.lim_done_title)@",
  done = "@i18n(app.modules.setup_wizard.lim_done)@",
  start = "@i18n(app.modules.setup_wizard.btn_start)@",
  again = "@i18n(app.modules.setup_wizard.btn_again)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
}

-- The intro's three pictures: the method, a step each.
local HOW = {
  {caption = "1. @i18n(app.modules.setup_wizard.lim_how_bind)@", pos = 0.8, stop = 0.86},
  {caption = "2. @i18n(app.modules.setup_wizard.lim_how_back)@", pos = 0.62, stop = 0.86, back = true},
  {caption = "3. " .. T.set, pos = 0.62, stop = 0.86, saved = 0.62},
}

-- PWM_SERVO_PULSE_MIN/MAX and SERVO_LIMIT_MIN/MAX (firmware rx/rx.h,
-- flight/servos.h), as the configurator's servoLimits.js.
local SIGNAL_MIN, SIGNAL_MAX = 50, 2250
local TRAVEL = 1000
local STEPS = {-50, -10, 10, 50}
-- A surface's limits on the last screen: "-650 / +700 us".
local DONE_VALUE = "%+d / %+d us"

local function openRange(config)
  return math.max(-TRAVEL, SIGNAL_MIN - config.mid), math.min(TRAVEL, SIGNAL_MAX - config.mid)
end

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local surfaces = wiz.surfaces()
  local screen = "intro"
  -- Screen k is surface ceil(k / 2): odd k its Min, even k its Max.
  local index = 1
  local side = "min"
  local position = 0
  local dial = {}

  local function current() return surfaces[index] end

  local function hold()
    local s = current()
    if s then wiz.probeServo(s.servo, position) end
  end

  local function screenNumber() return 2 * index - (side == "min" and 1 or 0) end

  local function show(k)
    -- The probe stays on between a surface's two sides.
    local s, nextIndex = current(), (k + 1) // 2
    if s and screen == "surface" and (nextIndex ~= index or not surfaces[nextIndex] or k < 1) then
      wiz.releaseProbe(s.servo)
    end
    index, side, position = nextIndex, (k % 2 == 1) and "min" or "max", 0
    if k >= 1 and surfaces[index] then
      screen = "surface"
      hold()
    else
      screen = k < 1 and "intro" or "done"
    end
    wiz.rebuild()
  end

  -- Set saves only this screen's side, so the servo must be on it.
  local function onSide() return (side == "min" and position < 0) or (side == "max" and position > 0) end

  local function move(delta)
    local lo, hi = openRange(wiz.configs[current().servo])
    position = math.max(lo, math.min(hi, position + delta))
    hold()
    wiz.rebuild()
  end

  -- A flap's limit sets that side's scale so the flap channel's end lands on
  -- it (StepLimits.svelte matchFlapScale()).
  local function matchFlapScale(surface, config, which, limit)
    if surface.kind ~= "flap" then return end
    local reversed = ((config.flags or 0) & surfacesLib.SERVO_FLAG_REVERSE) ~= 0
    for _, stick in ipairs({1, -1}) do
      local output = surfacesLib.outputForFlap(surface, stick)
      if output ~= 0 and ((surfacesLib.servoSide(output, reversed) == "pos") == (which == "max")) then
        config[which == "max" and "rpos" or "rneg"] = surfacesLib.maxScale(output, math.abs(limit))
        return
      end
    end
  end

  local function setHere()
    if not onSide() or not wiz.canMove() then return end
    local s = current()
    wiz.editServo(s.servo, function(config)
      config[side] = position
      matchFlapScale(s, config, side, position)
    end)
    show(screenNumber() + 1)
  end

  local function clearDial()
    dial.pos, dial.zoneFrom, dial.zoneTo, dial.side = 0, nil, nil, nil
    dial.saved, dial.stop, dial.back = nil, nil, nil
  end

  -- The method: three small dials with a caption under each.
  local function drawHow(x, y, w, h, colors)
    lcd.font(FONT_XS)
    local _, th = lcd.getTextSize("Ag")
    local cw = math.floor(w / #HOW)
    local r = math.floor(math.min(cw * 0.36, (h - th - 14) / 1.12))
    if r < 16 then return end
    local cy = y + r + 8
    for i = 1, #HOW do
      local p = HOW[i]
      clearDial()
      dial.pos, dial.side, dial.stop, dial.back, dial.saved = p.pos, "max", p.stop, p.back, p.saved
      local cx = x + (i - 1) * cw + math.floor(cw / 2)
      art.servoDial(cx, cy, r, dial, colors)
      lcd.font(FONT_XS)
      lcd.color(colors.text)
      lcd.drawText(cx, cy + math.floor(r * 0.12) + 6, p.caption, CENTERED)
    end
  end

  -- This servo on a dial: where it is, its stored limits, and the side
  -- being found lit; the numbers below it.
  local function drawServo(x, y, w, h, colors)
    local s = current()
    if not s then return end
    local config = wiz.configs[s.servo]
    local lo, hi = openRange(config)
    local function frac(v)
      if v < 0 then return lo < 0 and -v / lo or 0 end
      return hi > 0 and v / hi or 0
    end
    lcd.font(FONT_S)
    local lw = lcd.getTextSize(T.minLabel)
    local mw = lcd.getTextSize(T.maxLabel)
    local _, th = lcd.getTextSize("Ag")
    local tall = (h - th - 14) / 1.12
    local r = math.floor(math.min((w - 2 * math.max(lw, mw) - 24) / 2, tall))
    -- Labels too long for beside the arc: keep the dial, let them overlap it.
    if r < 16 then r = math.floor(math.min(w / 2 - 24, tall)) end
    if r < 16 then return end
    local cx, cy = x + math.floor(w / 2), y + r + 8
    clearDial()
    dial.pos, dial.side = frac(position), side
    dial.zoneFrom, dial.zoneTo = frac(config.min), frac(config.max)
    dial.saved = frac(config[side])
    art.servoDial(cx, cy, r, dial, colors)
    local ex, ey = art.dialEnds(r)
    lcd.font(FONT_S)
    lcd.color(side == "min" and colors.active or colors.muted)
    lcd.drawText(cx - ex - 8, cy - ey - math.floor(th / 2), T.minLabel, RIGHT)
    lcd.color(side == "max" and colors.active or colors.muted)
    lcd.drawText(cx + ex + 8, cy - ey - math.floor(th / 2), T.maxLabel, LEFT)
    lcd.color(colors.text)
    lcd.drawText(cx, cy + math.floor(r * 0.12) + 6, string.format(T.now, position, config[side]), CENTERED)
  end

  function self.build()
    scr:begin()
    if screen == "intro" then
      scr:text(T.title, T.intro)
      scr:draw(drawHow)
      return scr:row(nil, {
        {text = T.start, primary = true, needsMotion = true, press = function() show(1) end},
      })
    elseif screen == "done" then
      -- The limits each surface ended up with, either side of its center.
      scr:text(T.doneTitle, T.done)
      scr:picture(art.layout(surfaces, nil))
      local rows = {}
      for _, s in ipairs(surfaces) do
        local c = wiz.configs[s.servo]
        if c then rows[#rows + 1] = {wiz.surfaceName(s), string.format(DONE_VALUE, c.min, c.max)} end
      end
      scr:rows(rows)
      return scr:row(function() show(2 * #surfaces) end, {{text = T.again, press = function() show(1) end}})
    end
    local s = current()
    scr:text(string.format(T.head, wiz.surfaceName(s), side == "min" and T.minLabel or T.maxLabel),
      side == "min" and T.min or T.max, s.kind == "flap" and T.flap or nil,
      string.format(T.progress, screenNumber(), 2 * #surfaces))
    scr:draw(drawServo, nil, true)
    local specs = {}
    local ready = onSide()
    for _, d in ipairs(STEPS) do
      -- Until Set can save, the focus starts on a step towards this side.
      local towards = (side == "min" and d == -10) or (side == "max" and d == 10)
      specs[#specs + 1] = {text = (d > 0 and "+" or "") .. d, small = true, weight = 0.7, needsMotion = true,
        primary = not ready and towards, press = function() move(d) end}
    end
    specs[#specs + 1] = {text = T.set, small = true, primary = ready,
      needsMotion = true, disabled = not ready, press = setHere}
    -- Back: the screen before (the intro from the first). Next: skip this
    -- side, keeping its stored limit.
    local k = screenNumber()
    return scr:row(function() show(k - 1) end, specs, {text = T.next, press = function() show(k + 1) end})
  end

  function self.paint() scr:paint() end

  local lastCanMove = nil
  function self.wakeup()
    local canMove = wiz.canMove()
    if canMove ~= lastCanMove then
      lastCanMove = canMove
      if canMove and screen == "surface" then hold() end
      scr:refresh()
    end
  end

  function self.released() scr:refresh() end

  return self
end

return {new = new}
