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
--   prop      the propeller must be off before anything runs
--   calibrate only for the PWM protocol (motor_pwm_protocol 0): a PWM ESC
--             learns the throttle range. The pilot confirms the battery is
--             unplugged, then (full) full throttle is held on every motor.
--             Once the output has reached it the screen says to plug the
--             battery in, and Low throttle, pressed after the ESC's beeps,
--             drops the output to zero. Next skips the calibration, for an
--             ESC that is already calibrated.
--   spin      one motor at a time, so a twin shows which motor is which:
--             pick the motor (only with more than one) and 5, 10 or 20 %,
--             and Spin runs it for SPIN_SECONDS and stops by itself; Stop
--             ends it early.
--
-- The motor output, from the firmware (flight/motors.c and motors.h): an
-- override is -1000..1000, 1000 is full throttle. It is dropped a second
-- after the last write (MOTOR_OVERRIDE_TIMEOUT) and ignored while armed, so
-- the step re-sends it every quarter second, as app/pages/motor_override.lua
-- does, and a lost link stops the motor. A rising override is slew-limited
-- at a quarter of the range per second (MOTOR_OVERRIDE_RATE), so full
-- throttle takes four seconds to reach: Low throttle is held back, and not
-- acted on, for RAMP_SECONDS. A falling one is not limited. Low throttle,
-- Cancel, Back, the step list, Save, leaving the step, arming and a lost
-- link all write zero to every motor.
--
-- The configurator spins while a button is held; a radio button can't be
-- held, so here a press spins for a few seconds.

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
  spinTwin = "@i18n(app.modules.setup_wizard.mot_spin_twin)@",
  motor = "@i18n(app.modules.setup_wizard.mot_motor_fmt)@",
  calTitle = "@i18n(app.modules.setup_wizard.mot_cal_title)@",
  calText = "@i18n(app.modules.setup_wizard.mot_cal_text)@",
  calUnplugged = "@i18n(app.modules.setup_wizard.mot_cal_unplugged)@",
  calFullText = "@i18n(app.modules.setup_wizard.mot_cal_full_text)@",
  calFull = "@i18n(app.modules.setup_wizard.mot_cal_full)@",
  calHoldText = "@i18n(app.modules.setup_wizard.mot_cal_hold_text)@",
  calRamping = "@i18n(app.modules.setup_wizard.mot_cal_ramping_fmt)@",
  calPlugIn = "@i18n(app.modules.setup_wizard.mot_cal_plug_in)@",
  calLow = "@i18n(app.modules.setup_wizard.mot_cal_low)@",
  calDone = "@i18n(app.modules.setup_wizard.mot_cal_done)@",
  calStopped = "@i18n(app.modules.setup_wizard.mot_cal_stopped)@",
  cancel = "@i18n(app.btn_cancel)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
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
-- Only the PWM protocol has a throttle range to learn.
local PWM_PROTOCOL = 0

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
-- The override's ramp from zero to full (MOTOR_OVERRIDE_RATE), and a margin.
local RAMP_SECONDS = 5
-- Built once: the ramp note is on screen for the whole ramp.
T.calRampingNow = string.format(T.calRamping, RAMP_SECONDS)

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  local screen = "protocol"
  local config = nil
  local original = nil
  local changed = false

  -- What is driving the motors now: nil, "calibrate" or "spin". One at a time.
  local output = nil
  local outFirst, outLast, outValue = 0, 0, 0
  local nextWriteAt = 0

  local calStartedAt = nil  -- when full throttle was first sent
  local calReady = false    -- the ramp is over: Low throttle may be pressed
  local calNote = nil       -- how the last calibration ended, as the text to show

  local spinMotor = 0       -- 0-based, as the wire numbers them
  local throttleIndex = 2
  local spinUntil = nil
  local left = false

  wiz.fetch({config = function(ok, err) return motorConfig.buildReadMessage(ok, err) end}, function(results)
    config = results.config
    original = config
    wiz.rebuild()
  end)

  -- Motor output.

  local function lastMotor()
    return math.max(wiz.motorCount(), 1) - 1
  end

  local function writeMotors(first, last, value)
    for i = first, last do
      bus.publish("msp.request", motorOverride.buildWriteMessage(i, value))
    end
  end

  -- Holds `value` on motors first..last (0-based) until stopOutput().
  -- wakeup() re-sends it.
  local function hold(holder, first, last, value)
    output, outFirst, outLast, outValue = holder, first, last, value
    nextWriteAt = os.clock() + REFRESH
    writeMotors(first, last, value)
  end

  -- Zero on every motor, whichever were held.
  local function stopOutput()
    if not output then return end
    output = nil
    spinUntil = nil
    calStartedAt, calReady = nil, false
    writeMotors(0, lastMotor(), motorOverride.OVERRIDE_OFF)
  end

  -- Calibration: full throttle, battery in, low throttle.

  local function startCalibration()
    if output or wiz.armed() or not wiz.canMove() then return end
    calNote = nil
    calStartedAt, calReady = os.clock(), false
    hold("calibrate", 0, lastMotor(), motorOverride.OVERRIDE_MAX)
    wiz.rebuild()
  end

  -- Ends a calibration with the text to show, back on the screen that asks
  -- about the battery: it may be plugged in by now.
  local function endCalibration(note)
    if output ~= "calibrate" then return end
    stopOutput()
    calNote = note
    screen = "calibrate"
    if not left then wiz.rebuild() end
  end

  -- Spin.

  local function startSpin()
    if output or wiz.armed() or not wiz.canMove() then return end
    spinUntil = os.clock() + SPIN_SECONDS
    hold("spin", spinMotor, spinMotor,
      math.floor(TEST_THROTTLES[throttleIndex] * motorOverride.OVERRIDE_MAX / 100))
    wiz.rebuild()
  end

  local function stopSpin()
    if output ~= "spin" then return end
    stopOutput()
    if not left then wiz.rebuild() end
  end

  -- Whatever is running stops, with the output at zero.
  local function stopAll()
    if output == "calibrate" then endCalibration(T.calStopped) else stopSpin() end
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
    stopOutput()
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

    end

    -- Only a PWM ESC is calibrated. The protocol is the one the motor runs
    -- now: these screens are not reached with a change waiting for a restart.
    local pwm = config.motor_pwm_protocol == PWM_PROTOCOL

    if screen == "prop" then
      scr:text(T.propTitle, T.propText)
      return scr:row(function() go("protocol") end, nil,
        {text = T.propOff, press = function() go(pwm and "calibrate" or "spin") end})

    elseif screen == "calibrate" then
      scr:text(T.calTitle, T.calText, calNote)
      -- Next skips the calibration.
      return scr:row(function() go("prop") end, {
        {text = T.calUnplugged, small = true, primary = calNote ~= T.calDone, disabled = wiz.armed(),
          press = function() go("full") end},
      }, {text = T.next, press = function() go("spin") end})

    elseif screen == "full" then
      if output ~= "calibrate" then
        scr:text(T.calTitle, T.calFullText)
        return scr:row(function() go("calibrate") end, {
          {text = T.calFull, small = true, primary = true, needsMotion = true, press = startCalibration},
        }, false)
      end
      -- Full throttle is held. Back and Cancel drop it to zero.
      scr:text(T.calTitle, T.calHoldText, calReady and T.calPlugIn or T.calRampingNow)
      return scr:row(function() endCalibration(T.calStopped) end, {
        {text = T.calLow, small = true, primary = calReady, disabled = not calReady,
          press = function()
            -- Not before the output has reached full throttle.
            if calReady then endCalibration(T.calDone) end
          end},
        {text = T.cancel, small = true, primary = not calReady,
          press = function() endCalibration(T.calStopped) end},
      }, false)
    end

    -- spin
    local spinning = output == "spin"
    local count = wiz.motorCount()
    if spinMotor >= count then spinMotor = 0 end
    scr:text(T.spinTitle, T.spinText, spinning and T.spinning or (count > 1 and T.spinTwin or nil))
    local specs = {}
    if count > 1 then
      specs[#specs + 1] = {text = string.format(T.motor, spinMotor + 1), weight = 0.9, small = true,
        disabled = spinning, press = function()
          spinMotor = (spinMotor + 1) % count
          wiz.rebuild()
        end}
    end
    specs[#specs + 1] = {text = string.format("%d%%", TEST_THROTTLES[throttleIndex]), weight = 0.6, small = true,
      disabled = spinning, press = function()
        throttleIndex = throttleIndex % #TEST_THROTTLES + 1
        wiz.rebuild()
      end}
    -- Three buttons share the row on a twin: the smaller font for all.
    specs[#specs + 1] = spinning and {text = T.stop, primary = true, small = count > 1, press = stopSpin}
      or {text = string.format(T.spin, SPIN_SECONDS), primary = true, small = count > 1, needsMotion = true,
        press = startSpin}
    -- Next waits for the spin to end; Back stops it (go() does).
    local forward = wiz.forward(function() go("protocol"); wiz.finishStep() end)
    forward.disabled = spinning
    return scr:row(function() go(pwm and "calibrate" or "prop") end, specs, forward)
  end

  function self.paint() scr:paint() end

  function self.wakeup(now)
    if not output then return end
    if not wiz.canMove() then
      -- Armed, or the link is gone: the writes would not arrive anyway.
      stopAll()
    elseif spinUntil and now >= spinUntil then
      stopSpin()
    else
      if output == "calibrate" and not calReady and now - calStartedAt >= RAMP_SECONDS then
        calReady = true
        wiz.rebuild()
      end
      if now >= nextWriteAt then
        nextWriteAt = now + REFRESH
        writeMotors(outFirst, outLast, outValue)
      end
    end
  end

  -- The step list, Save and Back: nothing runs behind them.
  function self.pause() stopAll() end

  function self.released()
    stopAll()
    scr:refresh()
  end

  function self.leave()
    left = true
    stopAll()
  end

  return self
end

return {new = new, owned = OWNED}
