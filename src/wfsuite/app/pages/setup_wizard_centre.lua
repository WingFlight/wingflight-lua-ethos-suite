-- Setup Wizard step: Centre. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepCentre.svelte. Every
-- surface servo is held at override 0, which puts it exactly at its Mid with
-- nothing from the mixer on top (gyro, offsets, flaps). One screen per
-- surface: nudge its Mid by -10/-1/+1/+10 us until the surface is neutral.
-- More than MID_WARN_US from the servo's normal centre (1500, or 760 for a
-- narrow-band servo) is flagged: the horn should be moved instead, or that
-- side loses travel.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")

local T = {
  intro = "@i18n(app.modules.setup_wizard.cen_intro)@",
  value = "@i18n(app.modules.setup_wizard.cen_value_fmt)@",
  far = "@i18n(app.modules.setup_wizard.cen_far)@",
  flap = "@i18n(app.modules.setup_wizard.cen_flap)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  doneTitle = "@i18n(app.modules.setup_wizard.cen_done_title)@",
  done = "@i18n(app.modules.setup_wizard.cen_done)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
}

local MID_WARN_US = 100
local NUDGES = {-10, -1, 1, 10}

local function bandCentre(config)
  return config.mid > 860 and 1500 or 760
end

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local surfaces = wiz.surfaces()
  local index = 1
  local holding = false

  local function holdAll()
    holding = true
    for _, s in ipairs(surfaces) do
      if not wiz.holdServo(s.servo, 0) then holding = false end
    end
  end

  local function nudge(delta)
    local surface = surfaces[index]
    wiz.editServo(surface.servo, function(config)
      config.mid = config.mid + delta
    end)
    wiz.rebuild()
  end

  local function drawGauge(x, y, w, h, colors)
    local surface = surfaces[index]
    local config = surface and wiz.configs[surface.servo]
    if not config then return end
    local offset = config.mid - bandCentre(config)
    local range = 2 * MID_WARN_US
    local gh = math.min(h, 30)
    ui.gauge(x, y + math.floor((h - gh) / 2), w, gh, (offset + range) / (2 * range), colors,
      (range - MID_WARN_US) / (2 * range), (range + MID_WARN_US) / (2 * range))
  end

  function self.build()
    scr:begin()
    if not holding then holdAll() end
    local surface = surfaces[index]
    -- Back steps through the surfaces; from the first, the previous step.
    local back = index > 1 and function() index = index - 1; wiz.rebuild() end or nil
    if not surface then
      scr:text(T.doneTitle, T.done)
      return scr:row(back)
    end
    local config = wiz.configs[surface.servo]
    local offset = config.mid - bandCentre(config)
    local accent = math.abs(offset) > MID_WARN_US and T.far or (surface.kind == "flap" and T.flap or nil)
    scr:text(wiz.surfaceName(surface),
      T.intro .. " " .. string.format(T.value, config.mid, (offset >= 0 and "+" or "") .. offset), accent,
      string.format(T.progress, index, #surfaces))
    scr:draw(drawGauge)
    local specs = {}
    for _, d in ipairs(NUDGES) do
      specs[#specs + 1] = {text = (d > 0 and "+" or "") .. d, small = true, weight = 0.7, needsMotion = true,
        press = function() nudge(d) end}
    end
    return scr:row(back, specs, {text = T.next, press = function()
      index = index + 1
      wiz.rebuild()
    end})
  end

  function self.paint() scr:paint() end

  local lastCanMove = nil
  function self.wakeup()
    local canMove = wiz.canMove()
    if canMove ~= lastCanMove then
      lastCanMove = canMove
      if canMove and not holding then holdAll() end
      scr:refresh()
    end
  end

  function self.released()
    holding = false
    scr:refresh()
  end

  return self
end

return {new = new}
