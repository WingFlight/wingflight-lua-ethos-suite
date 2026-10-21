-- Setup Wizard step: Binding limits. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepLimits.svelte. For each
-- surface, one side at a time: the servo is held by a probe
-- (MSP2_WING_SET_SERVO_PROBE, lib/msp_servo_probe.lua) at Mid + an offset that
-- ignores the stored Min/Max, so the stored limits are never widened while
-- exploring. Step it until the surface binds, back off one step, and Set:
-- the offset is written as that side's limit. Min first, then Max.
--
-- The range explored is what the servo's travel and signal range allow at
-- this centre (the configurator's openRange()). A flap's limits are its end
-- points: setting one also sets the scale on that side so the flap channel's
-- end lands exactly on it (matchFlapScale()).

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.lim_title)@",
  intro = "@i18n(app.modules.setup_wizard.lim_intro)@",
  min = "@i18n(app.modules.setup_wizard.lim_todo_min)@",
  max = "@i18n(app.modules.setup_wizard.lim_todo_max)@",
  now = "@i18n(app.modules.setup_wizard.lim_now_fmt)@",
  flap = "@i18n(app.modules.setup_wizard.lim_flap)@",
  set = "@i18n(app.modules.setup_wizard.lim_set)@",
  saveMin = "@i18n(app.modules.setup_wizard.lim_set_min)@",
  saveMax = "@i18n(app.modules.setup_wizard.lim_set_max)@",
  minLabel = "@i18n(app.modules.setup_wizard.lim_min)@",
  maxLabel = "@i18n(app.modules.setup_wizard.lim_max)@",
  move = "@i18n(app.modules.setup_wizard.lim_move)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  doneTitle = "@i18n(app.modules.setup_wizard.lim_done_title)@",
  done = "@i18n(app.modules.setup_wizard.lim_done)@",
  start = "@i18n(app.modules.setup_wizard.btn_start)@",
  again = "@i18n(app.modules.setup_wizard.btn_again)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
}

-- PWM_SERVO_PULSE_MIN/MAX and SERVO_LIMIT_MIN/MAX (firmware rx/rx.h,
-- flight/servos.h), as the configurator's servoLimits.js.
local SIGNAL_MIN, SIGNAL_MAX = 50, 2250
local TRAVEL = 1000
local STEPS = {-50, -10, 10, 50}

local function openRange(config)
  return math.max(-TRAVEL, SIGNAL_MIN - config.mid), math.min(TRAVEL, SIGNAL_MAX - config.mid)
end

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local surfaces = wiz.surfaces()
  local screen = "intro"
  local index = 1
  local side = "min"
  local position = 0
  local sidesDone = {}

  local function current() return surfaces[index] end

  local function hold()
    local s = current()
    if s then wiz.probeServo(s.servo, position) end
  end

  local function startSurface(i)
    local s = current()
    if s then wiz.releaseProbe(s.servo) end
    index, side, position = i, "min", 0
    sidesDone = {}
    if surfaces[index] then
      screen = "surface"
      hold()
    else
      screen = "done"
    end
    wiz.rebuild()
  end

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

  -- Setting or skipping a side always visits the other side before moving
  -- to the next surface. A skipped side keeps its stored limit.
  local function advance()
    if sidesDone.min and sidesDone.max then
      startSurface(index + 1)
    else
      side, position = sidesDone.min and "max" or "min", 0
      hold()
      wiz.rebuild()
    end
  end

  local function setHere()
    if position == 0 or not wiz.canMove() then return end
    local s = current()
    -- The side follows where the servo is, as in the configurator.
    local which = position > 0 and "max" or "min"
    wiz.editServo(s.servo, function(config)
      config[which] = position
      matchFlapScale(s, config, which, position)
    end)
    sidesDone[which] = true
    advance()
  end

  local function drawGauge(x, y, w, h, colors)
    local s = current()
    if not s then return end
    local config = wiz.configs[s.servo]
    local lo, hi = openRange(config)
    lcd.font(FONT_S)
    local _, th = lcd.getTextSize("Ag")
    local gh = math.min(30, math.max(0, h - 2 * th - 8))
    local gy = y + math.floor((h - gh) / 2)
    local function at(v) return (v - lo) / (hi - lo) end
    lcd.color(position < 0 and colors.active or colors.muted)
    lcd.drawText(x, gy - th - 4, T.minLabel, LEFT)
    lcd.color(position > 0 and colors.active or colors.muted)
    lcd.drawText(x + w, gy - th - 4, T.maxLabel, RIGHT)
    ui.gauge(x, gy, w, gh, at(position), colors, at(config.min), at(config.max))
    lcd.color(position ~= 0 and colors.active or colors.muted)
    lcd.drawText(x + math.floor(w / 2), gy + gh + 4,
      position < 0 and T.saveMin or (position > 0 and T.saveMax or T.move), CENTERED)
  end

  function self.build()
    scr:begin()
    if screen == "intro" then
      scr:text(T.title, T.intro)
      return scr:row(nil, {
        {text = T.start, primary = true, needsMotion = true, press = function() startSurface(1) end},
      })
    elseif screen == "done" then
      scr:text(T.doneTitle, T.done)
      return scr:row(function() startSurface(#surfaces) end, {{text = T.again, press = function() startSurface(1) end}})
    end
    local s = current()
    local config = wiz.configs[s.servo]
    local body = (side == "min" and T.min or T.max) .. " "
      .. string.format(T.now, position, config.min, config.max)
    scr:text(wiz.surfaceName(s), body, s.kind == "flap" and T.flap or nil,
      string.format(T.progress, index, #surfaces))
    scr:draw(drawGauge)
    local specs = {}
    for _, d in ipairs(STEPS) do
      -- Until there is a position to set, the focus starts on a step towards
      -- the side being found, not on Next.
      local towards = (side == "min" and d == -10) or (side == "max" and d == 10)
      specs[#specs + 1] = {text = (d > 0 and "+" or "") .. d, small = true, weight = 0.7, needsMotion = true,
        primary = position == 0 and towards, press = function() move(d) end}
    end
    -- The slider explains which limit Set will save; at center Set is disabled.
    specs[#specs + 1] = {text = T.set, small = true, primary = position ~= 0,
      needsMotion = true, disabled = position == 0, press = setHere}
    -- Back: the surface before, or the intro. Next: skip this side, keeping
    -- its old limit, then visit the remaining side or the next surface.
    return scr:row(function()
      if index > 1 then
        startSurface(index - 1)
      else
        local s0 = current()
        if s0 then wiz.releaseProbe(s0.servo) end
        screen = "intro"
        wiz.rebuild()
      end
    end, specs, {text = T.next, press = function()
      sidesDone[side] = true
      advance()
    end})
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
