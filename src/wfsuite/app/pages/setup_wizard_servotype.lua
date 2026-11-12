-- Setup Wizard step: Servo type. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepServoType.svelte: analog
-- (50 Hz) or digital (333 Hz). Only the update rate differs between the two:
-- every servo centres on a standard 1500 us pulse (narrow-band 760 us servos
-- are not supported), so choosing a type changes no servo's centre, limits
-- or scale. The rate is one setting for every PWM servo output
-- (servo_pwm_rate in MSP_MIXER_CONFIG, wiz.setPwmRate()), not a rate per
-- servo. It only applies after a restart, so the step ends with Save and
-- restart.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local ui = requireModule("app/setup_wizard_ui.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.st_title)@",
  intro = "@i18n(app.modules.setup_wizard.st_intro)@",
  all = "@i18n(app.modules.setup_wizard.st_all)@",
  now = "@i18n(app.modules.setup_wizard.st_now_fmt)@",
  custom = "@i18n(app.modules.setup_wizard.st_custom_fmt)@",
  applied = "@i18n(app.modules.setup_wizard.st_applied_fmt)@",
  saveRestart = "@i18n(app.modules.setup_wizard.btn_save_restart)@",
}

local TYPES = {
  {key = "analog", rate = 50, name = "@i18n(app.modules.setup_wizard.st_analog)@",
    help = "@i18n(app.modules.setup_wizard.st_analog_help)@"},
  {key = "digital", rate = 333, name = "@i18n(app.modules.setup_wizard.st_digital)@",
    help = "@i18n(app.modules.setup_wizard.st_digital_help)@"},
}

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)
  local applied = nil
  local changed = false     -- a type was applied: the step ends with a restart

  local function currentType()
    local rate = wiz.pwmRate()
    for _, tp in ipairs(TYPES) do
      if tp.rate == rate then return tp end
    end
    return nil
  end

  local function apply(tp)
    wiz.setPwmRate(tp.rate)
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
    -- One row per type, what it means beside it, the current one lit. A rate
    -- set to something else (from the CLI) matches neither, so say what it is.
    local rate = wiz.pwmRate()
    local now = (not current and rate) and (" " .. string.format(T.now, string.format(T.custom, rate))) or ""
    scr:text(T.title, T.intro, T.all .. now)
    local specs = {}
    for _, tp in ipairs(TYPES) do
      specs[#specs + 1] = {text = tp.name, help = tp.help, current = current == tp, press = function() apply(tp) end}
    end
    -- The list first: the encoder visits fields in the order they are made.
    local focus = scr:choices(specs)
    -- Next keeps the rate as it is; after a change, Save and restart.
    local forward = scr:row(nil, nil, changed and {text = T.saveRestart, press = function() wiz.saveAndReboot() end} or nil)
    return focus or forward
  end

  function self.paint() scr:paint() end
  function self.released() scr:refresh() end

  return self
end

return {new = new}
