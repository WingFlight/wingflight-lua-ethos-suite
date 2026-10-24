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
local art = requireModule("app/setup_wizard_art.lua")

local T = {
  intro = "@i18n(app.modules.setup_wizard.cen_intro)@",
  value = "@i18n(app.modules.setup_wizard.cen_value_fmt)@",
  far = "@i18n(app.modules.setup_wizard.cen_far)@",
  flap = "@i18n(app.modules.setup_wizard.cen_flap)@",
  progress = "@i18n(app.modules.setup_wizard.progress_fmt)@",
  doneTitle = "@i18n(app.modules.setup_wizard.cen_done_title)@",
  done = "@i18n(app.modules.setup_wizard.cen_done)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
  identify = "@i18n(app.modules.setup_wizard.cen_identify)@",
}

local MID_WARN_US = 100
-- A surface's center on the last screen: "1512 us (+12)".
local DONE_VALUE = "%d us (%s)"
-- Ten percent of servo travel either side of center, within the stored limits.
local IDENTIFY_RAW = 100
local IDENTIFY_INTERVAL = 0.5
local IDENTIFY_SECONDS = 3
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
  local identifyServo, identifyUntil, nextMoveAt, phase = nil, 0, 0, false

  local function stopIdentify()
    if identifyServo == nil then return end
    local servo = identifyServo
    identifyServo = nil
    wiz.holdServo(servo, 0)
  end

  local function identify()
    local surface = surfaces[index]
    if identifyServo ~= nil or not surface or not wiz.canMove() then return end
    if not wiz.holdServo(surface.servo, IDENTIFY_RAW) then return end
    local now = os.clock()
    identifyServo, identifyUntil = surface.servo, now + IDENTIFY_SECONDS
    phase, nextMoveAt = true, now + IDENTIFY_INTERVAL
  end

  local function holdAll()
    holding = true
    for _, s in ipairs(surfaces) do
      if not wiz.holdServo(s.servo, 0) then holding = false end
    end
  end

  local function nudge(delta)
    stopIdentify()
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
    local back = index > 1 and function() stopIdentify(); index = index - 1; wiz.rebuild() end or nil
    if not surface then
      -- Where each surface's center ended up, lit when far from normal.
      scr:text(T.doneTitle, T.done)
      scr:picture(art.layout(surfaces, nil))
      local rows = {}
      for _, s in ipairs(surfaces) do
        local c = wiz.configs[s.servo]
        if c then
          local off = c.mid - bandCentre(c)
          rows[#rows + 1] = {wiz.surfaceName(s), string.format(DONE_VALUE, c.mid, (off >= 0 and "+" or "") .. off),
            math.abs(off) > MID_WARN_US}
        end
      end
      scr:rows(rows)
      return scr:row(back)
    end
    local config = wiz.configs[surface.servo]
    local offset = config.mid - bandCentre(config)
    local accent = math.abs(offset) > MID_WARN_US and T.far or (surface.kind == "flap" and T.flap or nil)
    scr:text(wiz.surfaceName(surface),
      T.intro .. " " .. string.format(T.value, config.mid, (offset >= 0 and "+" or "") .. offset), accent,
      string.format(T.progress, index, #surfaces))
    -- The surface on the plane, the centre gauge beside the words.
    scr:picture(art.surfaceLayout(surfaces, surface.kind))
    scr:live(drawGauge, 2)
    local specs = {}
    for _, d in ipairs(NUDGES) do
      specs[#specs + 1] = {text = (d > 0 and "+" or "") .. d, small = true, weight = 0.7, needsMotion = true,
        press = function() nudge(d) end}
      if d == -1 then
        specs[#specs + 1] = {text = T.identify, small = true, weight = 1.6, needsMotion = true, press = identify}
      end
    end
    return scr:row(back, specs, {text = T.next, press = function()
      stopIdentify()
      index = index + 1
      wiz.rebuild()
    end})
  end

  function self.paint() scr:paint() end

  local lastCanMove = nil
  function self.wakeup(now)
    local canMove = wiz.canMove()
    if canMove ~= lastCanMove then
      lastCanMove = canMove
      if canMove and not holding then holdAll() end
      scr:refresh()
    end
    if identifyServo == nil then return end
    if not canMove then
      identifyServo = nil
    elseif now >= identifyUntil then
      stopIdentify()
    elseif now >= nextMoveAt then
      phase = not phase
      if not wiz.holdServo(identifyServo, phase and IDENTIFY_RAW or -IDENTIFY_RAW) then
        identifyServo = nil
      end
      nextMoveAt = now + IDENTIFY_INTERVAL
    end
  end

  -- The shell pauses motion before opening the step list, saving or leaving.
  self.pause = stopIdentify
  self.leave = stopIdentify

  function self.released()
    identifyServo = nil
    holding = false
    scr:refresh()
  end

  return self
end

return {new = new}
