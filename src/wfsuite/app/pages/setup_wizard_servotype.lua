-- Setup Wizard step: Servo type. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepServoType.svelte: one
-- choice for every control-surface servo -- analog (50 Hz), digital
-- (333 Hz) or narrow-band (560 Hz, 760 us centre). Switching between normal
-- and narrow band also resets that servo's centre, limits and scale, as the
-- Servos tab does. The servo rate only applies after a restart, so the step
-- ends with Save and restart.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.st_title)@",
  intro = "@i18n(app.modules.setup_wizard.st_intro)@",
  all = "@i18n(app.modules.setup_wizard.st_all)@",
  now = "@i18n(app.modules.setup_wizard.st_now_fmt)@",
  unknown = "@i18n(app.modules.setup_wizard.st_unknown)@",
  applied = "@i18n(app.modules.setup_wizard.st_applied_fmt)@",
  saveRestart = "@i18n(app.modules.setup_wizard.btn_save_restart)@",
}

local TYPES = {
  {key = "analog", rate = 50, band = "wide", name = "@i18n(app.modules.setup_wizard.st_analog)@",
    help = "@i18n(app.modules.setup_wizard.st_analog_help)@"},
  {key = "digital", rate = 333, band = "wide", name = "@i18n(app.modules.setup_wizard.st_digital)@",
    help = "@i18n(app.modules.setup_wizard.st_digital_help)@"},
  {key = "narrow", rate = 560, band = "narrow", name = "@i18n(app.modules.setup_wizard.st_narrow)@",
    help = "@i18n(app.modules.setup_wizard.st_narrow_help)@"},
}

local BANDS = {
  wide = {mid = 1500, min = -700, max = 700, scale = 500},
  narrow = {mid = 760, min = -350, max = 350, scale = 250},
}

local function bandOf(config)
  return config.mid > 860 and "wide" or "narrow"
end

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local applied = nil
  local changed = false     -- a type was applied: the step ends with a restart

  local function currentType()
    local first = wiz.surfaces()[1]
    local config = first and wiz.configs[first.servo]
    if not config then return nil end
    for _, tp in ipairs(TYPES) do
      if tp.rate == config.rate and tp.band == bandOf(config) then return tp end
    end
    return nil
  end

  local function apply(tp)
    for _, surface in ipairs(wiz.surfaces()) do
      wiz.editServo(surface.servo, function(config)
        config.rate = tp.rate
        if bandOf(config) ~= tp.band then
          local band = BANDS[tp.band]
          config.mid, config.min, config.max = band.mid, band.min, band.max
          config.rneg, config.rpos = band.scale, band.scale
        end
      end)
    end
    applied, changed = tp, true
    wiz.rebuild()
  end

  function self.build()
    scr:begin()
    local current = currentType()
    if applied then
      -- Back to the choice; the new rate needs a restart.
      scr:text(T.title, string.format(T.applied, applied.name))
      return scr:row(function() applied = nil; wiz.rebuild() end, nil,
        {text = T.saveRestart, press = function() wiz.saveAndReboot() end})
    end
    -- One row per type, what it means beside it, the current one lit. A mix
    -- of types (or a custom rate) matches none, so say so.
    scr:text(T.title, T.intro,
      T.all .. (current and "" or (" " .. string.format(T.now, T.unknown))))
    local specs = {}
    for _, tp in ipairs(TYPES) do
      specs[#specs + 1] = {text = tp.name, help = tp.help, current = current == tp, press = function() apply(tp) end}
    end
    -- The list first: the encoder visits fields in the order they are made.
    local focus = scr:choices(specs)
    -- Next keeps the servos as they are; after a change, Save and restart.
    local forward = scr:row(nil, nil, changed and {text = T.saveRestart, press = function() wiz.saveAndReboot() end} or nil)
    return focus or forward
  end

  function self.paint() scr:paint() end
  function self.released() scr:refresh() end

  return self
end

return {new = new}
