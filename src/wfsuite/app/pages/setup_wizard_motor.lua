-- Setup Wizard step: Motor. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepMotor.svelte:
--
--   protocol  Standard PWM, DShot300, DShot600 or No motor (the rest stay on
--             the ESC & Motors pages). A change applies after a restart, so
--             it ends with Save and restart.
--   prop      the propeller must be off before the spin check
--   spin      runs every motor at a low throttle for SPIN_SECONDS, then stops
--             by itself
--
-- The configurator spins while a button is held; a radio button can't be
-- held, so here a press spins for a few seconds. The firmware drops a motor
-- override a second after the last write (MOTOR_OVERRIDE_TIMEOUT) and ignores
-- it while armed, so the page re-sends it every quarter second, as
-- app/pages/motor_override.lua does, and a lost link stops the motor.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({"wfsuite.lib.msp_motor_config", "wfsuite.lib.msp_motor_override"})
local motorConfig = requireModule("lib/msp_motor_config.lua")
local motorOverride = requireModule("lib/msp_motor_override.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.mot_title)@",
  intro = "@i18n(app.modules.setup_wizard.mot_intro)@",
  other = "@i18n(app.modules.setup_wizard.mot_other)@",
  changed = "@i18n(app.modules.setup_wizard.mot_changed)@",
  propTitle = "@i18n(app.modules.setup_wizard.mot_prop_title)@",
  propText = "@i18n(app.modules.setup_wizard.mot_prop_text)@",
  propOff = "@i18n(app.modules.setup_wizard.mot_prop_off)@",
  spinTitle = "@i18n(app.modules.setup_wizard.mot_spin_title)@",
  spinText = "@i18n(app.modules.setup_wizard.mot_spin_text)@",
  spinning = "@i18n(app.modules.setup_wizard.mot_spinning)@",
  spin = "@i18n(app.modules.setup_wizard.mot_spin_fmt)@",
  stop = "@i18n(app.modules.setup_wizard.mot_stop)@",
  test = "@i18n(app.modules.setup_wizard.mot_test)@",
  noMotor = "@i18n(app.modules.setup_wizard.mot_no_outputs)@",
  saveRestart = "@i18n(app.modules.setup_wizard.btn_save_restart)@",
}

local CHOICES = {
  {protocol = 0, name = "@i18n(app.modules.setup_wizard.mot_pwm)@",
    help = "@i18n(app.modules.setup_wizard.mot_pwm_help)@"},
  {protocol = 6, name = "@i18n(app.modules.setup_wizard.mot_dshot300)@",
    help = "@i18n(app.modules.setup_wizard.mot_dshot300_help)@"},
  {protocol = 7, name = "@i18n(app.modules.setup_wizard.mot_dshot600)@",
    help = "@i18n(app.modules.setup_wizard.mot_dshot600_help)@"},
  {protocol = 11, name = "@i18n(app.modules.setup_wizard.mot_none)@",
    help = "@i18n(app.modules.setup_wizard.mot_none_help)@"},
}

local TEST_THROTTLES = {5, 10, 20}
local SPIN_SECONDS = 3
local REFRESH = 0.25

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  local screen = "protocol"
  local config = nil
  local original = nil
  local changed = false
  local throttleIndex = 2
  local spinUntil, nextWriteAt = nil, 0

  wiz.fetch({config = function(ok, err) return motorConfig.buildReadMessage(ok, err) end}, function(results)
    config = results.config
    original = config
    wiz.rebuild()
  end)

  local function writeAll(value)
    for i = 0, math.max(wiz.motorCount(), 1) - 1 do
      bus.publish("msp.request", motorOverride.buildWriteMessage(i, value))
    end
  end

  local function stopSpin()
    if not spinUntil then return end
    spinUntil = nil
    writeAll(0)
  end

  local function choose(choice)
    if config.motor_pwm_protocol == choice.protocol then return end
    wiz.change("motor_config", original, function(o)
      bus.publish("msp.request", motorConfig.buildWriteMessage(o))
    end)
    local nextConfig = {}
    for k, v in pairs(config) do nextConfig[k] = v end
    nextConfig.motor_pwm_protocol = choice.protocol
    config = nextConfig
    bus.publish("msp.request", motorConfig.buildWriteMessage(config))
    changed = true
    wiz.rebuild()
  end

  local function go(name)
    stopSpin()
    screen = name
    wiz.rebuild()
  end

  function self.build()
    scr:begin()
    if not config then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end

    if screen == "protocol" then
      local current
      for _, c in ipairs(CHOICES) do
        if c.protocol == config.motor_pwm_protocol then current = c end
      end
      scr:text(T.title, T.intro,
        changed and T.changed or (not current and T.other or (wiz.motorCount() == 0 and T.noMotor or nil)))
      -- One row per protocol, what it means beside it, the current one lit.
      local specs = {}
      for _, c in ipairs(CHOICES) do
        specs[#specs + 1] = {text = c.name, help = c.help, current = current == c, press = function() choose(c) end}
      end
      -- A new protocol needs a restart; the test spins the protocol the
      -- motor runs now, so it waits until then.
      local forward = scr:row(nil, (not changed) and {
        {text = T.test, disabled = config.motor_pwm_protocol == 11 or wiz.motorCount() == 0,
          press = function() go("prop") end},
      } or nil, changed and {text = T.saveRestart, press = function() wiz.saveAndReboot() end} or nil)
      return scr:choices(specs) or forward

    elseif screen == "prop" then
      scr:text(T.propTitle, T.propText)
      return scr:row(function() go("protocol") end, nil, {text = T.propOff, press = function() go("spin") end})
    end

    -- spin
    local pct = TEST_THROTTLES[throttleIndex]
    scr:text(T.spinTitle, T.spinText, spinUntil and T.spinning or nil)
    -- Next waits for the spin to end; Back stops it (go() does).
    local forward = wiz.forward(function() go("protocol"); wiz.finishStep() end)
    forward.disabled = spinUntil ~= nil
    return scr:row(function() go("protocol") end, {
      {text = string.format("%d%%", pct), weight = 0.6, small = true, disabled = spinUntil ~= nil, press = function()
        throttleIndex = throttleIndex % #TEST_THROTTLES + 1
        wiz.rebuild()
      end},
      spinUntil and {text = T.stop, primary = true, press = function() stopSpin(); wiz.rebuild() end}
        or {text = string.format(T.spin, SPIN_SECONDS), primary = true, needsMotion = true, press = function()
          if wiz.armed() then return end
          spinUntil, nextWriteAt = os.clock() + SPIN_SECONDS, 0
          wiz.rebuild()
        end},
    }, forward)
  end

  function self.paint() scr:paint() end

  function self.wakeup(now)
    if not spinUntil then return end
    if now >= spinUntil or not wiz.canMove() then
      stopSpin()
      wiz.rebuild()
      return
    end
    if now >= nextWriteAt then
      nextWriteAt = now + REFRESH
      writeAll(math.floor(TEST_THROTTLES[throttleIndex] * motorOverride.OVERRIDE_MAX / 100))
    end
  end

  function self.released()
    stopSpin()
    scr:refresh()
  end

  function self.leave() stopSpin() end

  return self
end

return {new = new, owned = OWNED}
