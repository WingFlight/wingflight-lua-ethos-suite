-- Setup Wizard step: Motor. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepMotor.svelte:
--
--   protocol  Standard PWM, DShot150 or DShot300, or any other protocol
--             (No motor, DShot600, OneShot, ...) from the Other drop-down.
--             DShot600 is not a row of its own: on long ESC leads it picks
--             up noise, so only a pilot who knows that should choose it.
--             DShot150 has no bidirectional DShot RPM telemetry, so
--             choosing it also turns bidirectional DShot off in the same
--             write (an ESC that doesn't answer may not arm), and while it
--             is set the step says RPM needs DShot300 or a telemetry source.
--             A change applies after a restart, so it ends with Save and
--             restart.
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
  otherHelp = "@i18n(app.modules.setup_wizard.mot_other_help)@",
  changed = "@i18n(app.modules.setup_wizard.mot_changed)@",
  noRpm = "@i18n(app.modules.setup_wizard.mot_dshot150_rpm)@",
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

-- Both notes at once, built once: the restart note and DShot150's RPM note.
T.changedNoRpm = T.changed .. " " .. T.noRpm

-- DShot150 never carries bidirectional DShot RPM telemetry.
local DSHOT150 = 5

local CHOICES = {
  {protocol = 0, name = "@i18n(app.modules.setup_wizard.mot_pwm)@",
    help = "@i18n(app.modules.setup_wizard.mot_pwm_help)@"},
  {protocol = DSHOT150, name = "@i18n(app.modules.setup_wizard.mot_dshot150)@",
    help = "@i18n(app.modules.setup_wizard.mot_dshot150_help)@"},
  {protocol = 6, name = "@i18n(app.modules.setup_wizard.mot_dshot300)@",
    help = "@i18n(app.modules.setup_wizard.mot_dshot300_help)@"},
}

-- The Other drop-down: every protocol the codec offers that has no row, by
-- name, after an "Other" entry shown while a row's protocol is set.
local OTHER_NONE = -1
local OTHER_NAMES = {
  [1] = "OneShot125",
  [2] = "OneShot42",
  [3] = "MultiShot",
  [7] = "@i18n(app.modules.setup_wizard.mot_dshot600)@",
  [8] = "ProShot1000",
  [motorConfig.CASTLE_PROTOCOL] = "Castle Link",
  [motorConfig.SRXL2_PROTOCOL] = "SRXL2",
  [motorConfig.DISABLED_PROTOCOL] = "@i18n(app.modules.setup_wizard.mot_none)@",
}
local OTHER_VALUES = {{T.other, OTHER_NONE}}
do
  local inRow = {}
  for _, c in ipairs(CHOICES) do inRow[c.protocol] = true end
  for _, entry in ipairs(motorConfig.BASE_PROTOCOL_CHOICES) do
    local protocol = entry[2]
    if not inRow[protocol] then
      OTHER_VALUES[#OTHER_VALUES + 1] = {OTHER_NAMES[protocol] or entry[1], protocol}
    end
  end
end

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

  local function choose(protocol)
    if protocol == nil or protocol == OTHER_NONE or config.motor_pwm_protocol == protocol then return end
    wiz.change("motor_config", original, function(o)
      bus.publish("msp.request", motorConfig.buildWriteMessage(o))
    end)
    local nextConfig = {}
    for k, v in pairs(config) do nextConfig[k] = v end
    nextConfig.motor_pwm_protocol = protocol
    -- No bidirectional DShot on DShot150: an ESC that doesn't answer the
    -- telemetry request may not arm, so it goes off in the same write.
    if protocol == DSHOT150 then nextConfig.use_dshot_telemetry = 0 end
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
      local dshot150 = config.motor_pwm_protocol == DSHOT150
      local note
      if changed then
        note = dshot150 and T.changedNoRpm or T.changed
      elseif wiz.motorCount() == 0 then
        note = T.noMotor
      elseif dshot150 then
        note = T.noRpm
      end
      scr:text(T.title, T.intro, note)
      -- One row per protocol, what it means beside it, the current one lit;
      -- the rest in the Other drop-down, which shows the protocol set when
      -- it is one of them.
      local specs = {}
      for _, c in ipairs(CHOICES) do
        specs[#specs + 1] = {text = c.name, help = c.help, current = current == c,
          press = function() choose(c.protocol) end}
      end
      specs[#specs + 1] = {values = OTHER_VALUES, help = T.otherHelp, current = current == nil,
        get = function() return current and OTHER_NONE or config.motor_pwm_protocol end,
        set = function(value) choose(tonumber(value)) end}
      -- A new protocol needs a restart; the test spins the protocol the
      -- motor runs now, so it waits until then.
      -- The list first: the encoder visits fields in the order they are made.
      local focus = scr:choices(specs)
      local forward = scr:row(nil, (not changed) and {
        {text = T.test, disabled = config.motor_pwm_protocol == motorConfig.DISABLED_PROTOCOL or wiz.motorCount() == 0,
          press = function() go("prop") end},
      } or nil, changed and {text = T.saveRestart, press = function() wiz.saveAndReboot() end} or nil)
      return focus or forward

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
