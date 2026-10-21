-- Tools -> Setup Wizard.
--
-- The radio's own copy of wingflight-configurator's Setup Wizard
-- (src/tabs/setup_wizard/SetupWizard.svelte). It asks the same questions and
-- fixes things by the same rules, but as a guided sequence for a radio
-- screen: one question per screen, a picture, and big answer buttons (see
-- app/setup_wizard_ui.lua and app/setup_wizard_art.lua).
--
-- This file is the shell: it loads what every step needs, holds the flight
-- controller in its setup state while the wizard is open, owns every
-- override a step asks for, and saves, reverts or restarts. Each step is its
-- own file (app/pages/setup_wizard_<step>.lua), loaded when it opens and
-- dropped when it closes, and talks to the shell only through the `wiz` table
-- below -- the counterpart of the configurator's setContext("setupWizard").
--
-- Two configurator steps stay in the Configurator. The radio talks to the
-- flight controller through the receiver, so receiver protocol setup and the
-- ESC telemetry port can't be done from it: the Receiver step here only
-- checks the sticks and the channel order.
--
-- Safety, as in the configurator:
--   * The wizard needs timed overrides (API 22.14). Everything it holds -- the
--     setup state, forced modes, mixer and servo overrides, servo probes --
--     is sent with a timeout and re-sent by lib/override_keepalive.lua, so a
--     radio that is switched off or a link that drops lets the flight
--     controller drop it by itself (10 s). On older firmware the page
--     explains that and stops.
--   * The setup state blocks arming while the wizard is open, and the flight
--     controller ignores overrides while armed anyway: an armed model releases
--     everything and the page says why.
--   * Every way out (Back, the close key, a step change, closing the tool)
--     releases every override the page may have set.
--
-- Changes a step makes are sent to the flight controller straight away, so
-- the surface moves; Save writes them to EEPROM. Every change is registered
-- with wiz.change() first, so Discard can write back what was there.
-- Leaving with unsaved changes asks whether to save or discard them. Closing
-- the tool cannot ask, so it leaves them in RAM, unsaved, as every other page
-- does.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()

-- Modules only the wizard uses: dispose() frees the ones this visit loaded,
-- as app/page_runtime.lua's unloadPackageKeys does for other pages. Not the
-- override modules: they hold what is still being released when the page
-- closes. This file runs again on every visit (app/menu_container.lua's
-- loadPage()), so the check is per visit. Each step frees its own the same
-- way (app/setup_wizard_ui.lua's notLoaded()).
local SHELL_MODULES = {
  "wfsuite.lib.msp_mixer_rules", "wfsuite.lib.msp_mixer_input", "wfsuite.lib.msp_mixer_config",
  "wfsuite.lib.msp_servo_config", "wfsuite.lib.msp_servo", "wfsuite.lib.msp_rc_channels",
  "wfsuite.lib.setup_wizard_surfaces", "wfsuite.app.setup_wizard_ui", "wfsuite.app.setup_wizard_art",
}
local shellOwned = {}
for i = 1, #SHELL_MODULES do
  if package.loaded[SHELL_MODULES[i]] == nil then shellOwned[#shellOwned + 1] = SHELL_MODULES[i] end
end

local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local header = requireModule("app/header.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local keepalive = requireModule("lib/override_keepalive.lua")
local status = requireModule("lib/msp_status.lua")
local eeprom = requireModule("lib/msp_eeprom.lua")
local reboot = requireModule("lib/msp_reboot.lua")
local mixerRules = requireModule("lib/msp_mixer_rules.lua")
local mixerInput = requireModule("lib/msp_mixer_input.lua")
local mixerConfig = requireModule("lib/msp_mixer_config.lua")
local servoConfig = requireModule("lib/msp_servo_config.lua")
local servoRead = requireModule("lib/msp_servo.lua")
local servoOverride = requireModule("lib/msp_servo_override.lua")
local servoProbe = requireModule("lib/msp_servo_probe.lua")
local mixerOverride = requireModule("lib/msp_mixer_override.lua")
local modeOverride = requireModule("lib/msp_mode_override.lua")
local rcChannels = requireModule("lib/msp_rc_channels.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
-- Steps draw with it; loaded here so they share one copy.
local art = requireModule("app/setup_wizard_art.lua")

local PAGE_TITLE = "@i18n(app.modules.setup_wizard.name)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_SAVING_TITLE = "@i18n(app.msg_saving)@"
local MSG_SAVING_BODY = "@i18n(app.msg_saving_settings)@"
local MSG_SAVE_FAILED_TITLE = "@i18n(app.msg_save_failed_title)@"
local MSG_SAVE_FAILED_BODY = "@i18n(app.msg_save_failed_body)@"
local MSG_LOAD_FAILED_TITLE = "@i18n(app.msg_load_failed_title)@"
local MSG_LOAD_FAILED_BODY = "@i18n(app.msg_load_failed_body)@"
local MSG_RESTARTING_TITLE = "@i18n(app.msg_restarting)@"
local MSG_RESTARTING = "@i18n(app.msg_restarting_fc)@"
local MSG_REBOOT_WAIT = "@i18n(app.modules.setup_wizard.reboot_wait_fmt)@"
local STEPS_ICON = "app/gfx/nav/steps.png"
local NEXT = "@i18n(app.modules.setup_wizard.btn_next)@"
local SAVE_NEXT = "@i18n(app.modules.setup_wizard.dir_save_next)@"
local SAVE_FINISH = "@i18n(app.modules.setup_wizard.fin_button)@"
local BTN_OK = "@i18n(app.btn_ok)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"

-- Order is the procedure, as in the configurator's STEPS: each step relies
-- on the ones before it. needsSurfaces: the step works on the mixed control
-- surfaces, so it waits for the Airframe step.
local STEPS = {
  {key = "sensors", title = "@i18n(app.modules.setup_wizard.step_sensors)@"},
  {key = "receiver", title = "@i18n(app.modules.setup_wizard.step_receiver)@"},
  {key = "airframe", title = "@i18n(app.modules.setup_wizard.step_airframe)@"},
  {key = "servotype", title = "@i18n(app.modules.setup_wizard.step_servotype)@", needsSurfaces = true},
  {key = "motor", title = "@i18n(app.modules.setup_wizard.step_motor)@"},
  {key = "centre", title = "@i18n(app.modules.setup_wizard.step_centre)@", needsSurfaces = true},
  {key = "direction", title = "@i18n(app.modules.setup_wizard.step_direction)@", needsSurfaces = true},
  {key = "limits", title = "@i18n(app.modules.setup_wizard.step_limits)@", needsSurfaces = true},
  {key = "throws", title = "@i18n(app.modules.setup_wizard.step_throws)@", needsSurfaces = true},
  {key = "travel", title = "@i18n(app.modules.setup_wizard.step_travel)@", needsSurfaces = true},
  {key = "gyro", title = "@i18n(app.modules.setup_wizard.step_gyro)@", needsSurfaces = true},
  {key = "trimgain", title = "@i18n(app.modules.setup_wizard.step_trimgain)@"},
  {key = "modes", title = "@i18n(app.modules.setup_wizard.step_modes)@"},
  {key = "style", title = "@i18n(app.modules.setup_wizard.step_style)@"},
  {key = "finish", title = "@i18n(app.modules.setup_wizard.step_finish)@"},
}

-- Where the wizard was, for the next time it opens in this session (the
-- configurator keeps it in localStorage). Survives a flight controller
-- restart, which the page itself sits through.
local memory = package.loaded["wfsuite.setup_wizard.memory"] or {stepKey = nil}
package.loaded["wfsuite.setup_wizard.memory"] = memory

-- PWM servos only: mixer output N drives servo config N - 1 and servo
-- override N - 1 directly. Bus servos use another index scheme and are left
-- to the Servos pages.
local PWM_SERVO_SLOTS = 8

-- Mixer inputs the wizard holds: the stabilized axes, and the flap channel
-- for the flap direction check.
local HELD_INPUTS = {1, 2, 3, surfacesLib.FLAP_INPUT}
local AXIS_INPUT = {roll = 1, pitch = 2, yaw = 3, flap = surfacesLib.FLAP_INPUT}

-- Live values, while a step shows them: one read at a time, and a read that
-- has not answered within a second is given up.
local POLL_INTERVAL = {servo = 0.25, rc = 0.2}
local POLL_GIVE_UP = 1.0

-- Give-up bound for a restart, as app/page_runtime.lua's.
local REBOOT_TIMEOUT_SECONDS = 20

-- Flight mode bits of the "flight_mode" telemetry sensor
-- (tasks/audio_events.lua): modes that put the sticks on the surfaces.
local PASSTHROUGH_BIT = 7
local MANUAL_BIT = 10

local FORM_RIGHT_PADDING = 8

local function copyDeep(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copyDeep(v) end
  return out
end

local function hasBit(flags, bit)
  return flags ~= nil and ((math.floor(flags) >> bit) & 1) == 1
end

local function stepIndexOf(key)
  for i, s in ipairs(STEPS) do
    if s.key == key then return i end
  end
  return nil
end

---------------------------------------------------------------------------
-- Text helpers shared with the steps. Ethos static text does not wrap, so
-- longer text is wrapped here, measured in the font it is drawn in (as
-- app/header.lua does).
---------------------------------------------------------------------------

local function windowWidth()
  local w = 480
  if lcd and lcd.getWindowSize then w = lcd.getWindowSize() or w end
  return w
end

local function lineMetrics(line)
  local slots = form.getFieldSlots(line, {0})
  local slot = slots and slots[1] or nil
  return (slot and slot.y) or 0, (slot and slot.h) or 38
end

-- A line that is all text: an empty form line and a rect spanning the window
-- (see app/pages/motor_override.lua's addTextLine()).
local function addTextLine(text)
  local line = form.addLine("")
  local y, h = lineMetrics(line)
  return form.addStaticText(line, {x = 0, y = y, w = windowWidth(), h = h}, text, LEFT)
end

local function wrapLines(text, maxW, font)
  local out, line = {}, ""
  lcd.font(font or FONT_STD)
  for word in text:gmatch("%S+") do
    local candidate = (line == "") and word or (line .. " " .. word)
    if line == "" or lcd.getTextSize(candidate) <= maxW then
      line = candidate
    else
      out[#out + 1] = line
      line = word
    end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end

-- WRAP_MARGIN keeps the text clear of the form's scroll bar.
local WRAP_MARGIN = 24

local function addWrapped(text)
  local lines = wrapLines(text, windowWidth() - WRAP_MARGIN)
  for i = 1, #lines do addTextLine(lines[i]) end
end

local function open(opts)
  opts = opts or {}

  local disposed = false
  local loaded = false
  local loadFailed = false
  local unsupported = false
  local outstanding = 0

  local servoCount = 0
  local motorCount = 0
  local rules = nil
  local inputCodecs = {roll = mixerInput.roll(), pitch = mixerInput.pitch(), yaw = mixerInput.yaw()}
  local rateKeys = {roll = "rate_stabilized_roll", pitch = "rate_stabilized_pitch", yaw = "rate_stabilized_yaw"}
  local inputs = {}        -- axis -> decoded mixer input record (sent back whole)
  local configs = {}       -- servo (0-based) -> decoded servo config
  local mixConfig = nil    -- decoded MSP_MIXER_CONFIG

  local surfaces = {}
  local missingServos = {}
  local positions = {}     -- servo (0-based) -> live output, us
  local rc = {}            -- MSP_RC, by function: rc[1] roll ... rc[5] AUX1
  local rcRaw = {}         -- MSP_RX_CHANNELS, as the receiver sends them

  local pending = false    -- unsaved changes on the flight controller
  local changes = {}       -- {key =, original =, restore =} in order made
  local changeIndex = {}   -- key -> true
  local connected = nil
  local armed = nil
  local modeFlags = nil
  local handshakeDone = nil
  local refused = false    -- the flight controller refused the setup state
  local forcedMode = nil   -- permanent box id forced on top of the setup state

  local stepIndex = 1
  local step = nil         -- instance of STEPS[stepIndex]
  local stepOwned = nil    -- modules the step loaded for itself, freed when it closes
  local picking = false    -- the step list is showing
  local rebuildWanted = false

  local polls = {servo = {inFlight = false, at = 0}, rc = {inFlight = false, at = 0}}
  local fetches = {}       -- {left =, failed =, onDone =} waiting for replies

  local headerHandle = nil
  local noticeField = nil
  local dialog = nil       -- progress dialog
  local messageHandle = nil
  local pendingLeave = false
  local saving = false
  local saveRequest = nil  -- {onSaved =} waiting for the next wakeup
  local saveResult = nil   -- "ok" | "failed", set by the EEPROM reply
  local afterSave = nil
  local rebootWait = nil   -- {startedAt =, sawDisconnect =, remaining =, percent =} while restarting

  local heldInputs = {}
  local heldServos = {}
  local heldProbes = {}

  local sessionHandler = nil
  local wiz
  local beginLoad

  -------------------------------------------------------------------------
  -- Overrides
  -------------------------------------------------------------------------

  local function releaseAxes()
    for i = 1, #HELD_INPUTS do
      local input = HELD_INPUTS[i]
      if heldInputs[input] then
        heldInputs[input] = nil
        mixerOverride.release(input)
      end
    end
  end

  local function releaseServo(servo)
    if not heldServos[servo] then return end
    heldServos[servo] = nil
    servoOverride.release(servo)
  end

  local function releaseServos()
    for servo in pairs(heldServos) do releaseServo(servo) end
  end

  local function releaseProbe(servo)
    if not heldProbes[servo] then return end
    heldProbes[servo] = nil
    servoProbe.release(servo)
  end

  local function releaseProbes()
    for servo in pairs(heldProbes) do releaseProbe(servo) end
  end

  local function onRefused()
    if disposed then return end
    refused = true
    releaseAxes()
    releaseServos()
    releaseProbes()
    if step and step.released then step.released() end
    rebuildWanted = true
  end

  -- The setup state, with forcedMode on top if a step asked for one.
  local function holdModes()
    modeOverride.hold(forcedMode and {forcedMode} or {}, onRefused)
  end

  local function releaseAll()
    releaseAxes()
    releaseServos()
    releaseProbes()
    if forcedMode then
      forcedMode = nil
      if loaded and not unsupported then holdModes() end
    end
  end

  -- Start from no overrides at all: one left on by another page would hold
  -- its surface still and make every check look wrong.
  local function clearForeignOverrides()
    for i = 1, #HELD_INPUTS do mixerOverride.release(HELD_INPUTS[i]) end
    servoOverride.releaseAll()
  end

  local function canMove()
    return loaded and not unsupported and not refused and connected ~= false and armed ~= true
      and rebootWait == nil
  end

  -------------------------------------------------------------------------
  -- Changes and their undo
  -------------------------------------------------------------------------

  local function markChanged()
    -- The footer's Next becomes Save and continue (wiz.forward()).
    if not pending then rebuildWanted = true end
    pending = true
    if headerHandle and headerHandle.setSaveEnabled then headerHandle.setSaveEnabled(true) end
  end

  -- Registers what `key` was before the first change since the last save,
  -- and how to put it back. Later changes to the same key keep the first.
  local function change(key, original, restore)
    if not changeIndex[key] then
      changeIndex[key] = true
      changes[#changes + 1] = {key = key, original = copyDeep(original), restore = restore}
    end
    markChanged()
  end

  local function recompute()
    surfaces = surfacesLib.surfacesFromRules(rules, servoCount)
    missingServos = surfacesLib.servosPastCount(rules, servoCount, PWM_SERVO_SLOTS)
  end

  -------------------------------------------------------------------------
  -- The interface a step sees
  -------------------------------------------------------------------------

  wiz = {
    addTextLine = addTextLine,
    addWrapped = addWrapped,
    wrapLines = wrapLines,
    lineMetrics = lineMetrics,
    windowWidth = windowWidth,
    FORM_RIGHT_PADDING = FORM_RIGHT_PADDING,
    positions = positions,
    rc = rc,
    rcRaw = rcRaw,
    configs = configs,
    inputs = inputs,
    BOX_ANGLE = modeOverride.BOX_ANGLE,
    BOX_PASSTHROUGH = modeOverride.BOX_PASSTHROUGH,
  }

  function wiz.surfaces() return surfaces end
  function wiz.missingServos() return missingServos end
  function wiz.servoCount() return servoCount end
  function wiz.motorCount() return motorCount end
  function wiz.rules() return rules end
  function wiz.mixConfig() return mixConfig end
  function wiz.canMove() return canMove() end
  function wiz.armed() return armed == true end
  function wiz.change(key, original, restore) change(key, original, restore) end
  function wiz.markChanged() markChanged() end

  -- Redraw the step's picture.
  function wiz.invalidate()
    if lcd.invalidate then lcd.invalidate() end
  end

  -- values: {roll =, pitch =, yaw =, flap =} as fractions of full input
  -- (+-1). The flap channel only when asked for: other steps leave it on
  -- the pilot's switch.
  function wiz.holdAxes(values)
    if not canMove() then return false end
    for axis, input in pairs(AXIS_INPUT) do
      local value = values[axis]
      if value ~= nil or axis ~= "flap" then
        heldInputs[input] = true
        mixerOverride.hold(input, math.floor((value or 0) * 1000 + 0.5))
      end
    end
    return true
  end

  -- One axis only (or "flap"), for a step that has already held the rest
  -- with holdAxes() and now moves one back and forth: one write per move
  -- instead of four, which a telemetry link has room for.
  function wiz.holdAxis(axis, value)
    if not canMove() then return false end
    local input = AXIS_INPUT[axis]
    heldInputs[input] = true
    mixerOverride.hold(input, math.floor(value * 1000 + 0.5))
    return true
  end

  wiz.releaseAxes = releaseAxes

  function wiz.holdServo(servo, raw)
    if not canMove() then return false end
    if raw < -2000 then raw = -2000 elseif raw > 2000 then raw = 2000 end
    heldServos[servo] = true
    servoOverride.hold(servo, math.floor(raw + 0.5))
    return true
  end

  wiz.releaseServo = releaseServo
  wiz.releaseServos = releaseServos

  -- Holds a servo at Mid + offsetUs regardless of its Min/Max (Limits step).
  function wiz.probeServo(servo, offsetUs)
    if not canMove() then return false end
    heldProbes[servo] = true
    return servoProbe.hold(servo, math.floor(offsetUs + 0.5))
  end

  wiz.releaseProbe = releaseProbe

  -- Forces a mode on top of the setup state (wiz.BOX_ANGLE, wiz.BOX_PASSTHROUGH)
  -- until the step closes or wiz.releaseMode().
  function wiz.forceMode(boxId)
    if not canMove() then return false end
    forcedMode = boxId
    holdModes()
    return true
  end

  function wiz.releaseMode()
    if not forcedMode then return end
    forcedMode = nil
    holdModes()
  end

  function wiz.forcedMode() return forcedMode end

  -- Sends configs[servo] as it stands now. original: the config before the
  -- caller changed it (a copy), for Discard.
  function wiz.sendServo(servo, original)
    change("servo_" .. servo, original or configs[servo], function(o)
      configs[servo] = copyDeep(o)
      bus.publish("msp.request", servoConfig.buildWriteMessage(servo, configs[servo]))
    end)
    bus.publish("msp.request", servoConfig.buildWriteMessage(servo, configs[servo]))
  end

  -- Changes a servo's config with fn(config) and sends it, keeping what it
  -- was for Discard. The way steps should change a servo.
  function wiz.editServo(servo, fn)
    local original = copyDeep(configs[servo])
    fn(configs[servo])
    wiz.sendServo(servo, original)
  end

  local function sendInput(axis)
    bus.publish("msp.request", inputCodecs[axis].buildWriteMessage(inputs[axis]))
  end

  local function rememberInput(axis)
    change("input_" .. axis, inputs[axis], function(o)
      inputs[axis] = copyDeep(o)
      sendInput(axis)
    end)
  end

  function wiz.invertAxis(axis)
    local record = inputs[axis]
    if not record then return end
    rememberInput(axis)
    local key = rateKeys[axis]
    record[key] = -(record[key] or 0)
    sendInput(axis)
  end

  -- Axis Throw, percent (0-200), and setting it keeping the sign.
  function wiz.axisGainPercent(axis)
    local record = inputs[axis]
    return record and math.floor(math.abs(record[rateKeys[axis]] or 0) / 10 + 0.5) or 0
  end

  function wiz.setAxisGainPercent(axis, percent)
    local record = inputs[axis]
    if not record then return end
    rememberInput(axis)
    local sign = (record[rateKeys[axis]] or 0) < 0 and -1 or 1
    record[rateKeys[axis]] = sign * percent * 10
    sendInput(axis)
  end

  -- Axis Throw as multipliers, for lib/setup_wizard_surfaces.lua.
  function wiz.axisGains()
    local rates = {}
    for axis, key in pairs(rateKeys) do rates[axis] = inputs[axis] and inputs[axis][key] or 1000 end
    return surfacesLib.axisGainsFromRates(rates)
  end

  -- Replaces the whole mix (Airframe step): every rule slot and the model type.
  function wiz.setMix(ruleTable, modelType)
    change("mix", {rules = rules, modelType = mixConfig and mixConfig.model_type}, function(o)
      rules = copyDeep(o.rules)
      for i = 1, #rules do
        bus.publish("msp.request", mixerRules.buildWriteMessage(i - 1, rules[i]))
      end
      if mixConfig then
        mixConfig.model_type = o.modelType
        bus.publish("msp.request", mixerConfig.buildWriteMessage(mixConfig))
      end
    end)
    rules = ruleTable
    for i = 1, #rules do
      bus.publish("msp.request", mixerRules.buildWriteMessage(i - 1, rules[i]))
    end
    if mixConfig then
      mixConfig.model_type = modelType
      bus.publish("msp.request", mixerConfig.buildWriteMessage(mixConfig))
    end
    recompute()
  end

  -- Reads for a step: specs = {key = function(onData, onError) return msg end}.
  -- onDone(results, failed) runs from the page's wakeup once every reply is
  -- in (never from the reply itself, where Ethos forbids building a form).
  function wiz.fetch(specs, onDone)
    local f = {left = 0, failed = false, results = {}, onDone = onDone}
    for _ in pairs(specs) do f.left = f.left + 1 end
    fetches[#fetches + 1] = f
    for key, build in pairs(specs) do
      bus.publish("msp.request", build(function(data)
        if disposed or not f.onDone then return end
        f.results[key] = data
        f.left = f.left - 1
      end, function()
        if disposed or not f.onDone then return end
        f.failed = true
        f.left = f.left - 1
      end))
    end
    return f
  end

  local KIND_NAMES = {
    aileron = "@i18n(app.modules.setup_wizard.surface_aileron)@",
    flaperon = "@i18n(app.modules.setup_wizard.surface_flaperon)@",
    elevator = "@i18n(app.modules.setup_wizard.surface_elevator)@",
    rudder = "@i18n(app.modules.setup_wizard.surface_rudder)@",
    elevon = "@i18n(app.modules.setup_wizard.surface_elevon)@",
    ruddervator = "@i18n(app.modules.setup_wizard.surface_ruddervator)@",
    flap = "@i18n(app.modules.setup_wizard.surface_flap)@",
    mixed = "@i18n(app.modules.setup_wizard.surface_mixed)@",
  }

  function wiz.kindName(kind) return KIND_NAMES[kind] or kind end

  -- "Servo 3 (Elevator)".
  function wiz.surfaceName(surface)
    return string.format("@i18n(app.modules.setup_wizard.servo_kind_fmt)@", surface.servo + 1,
      KIND_NAMES[surface.kind] or surface.kind)
  end

  -- The step asks for its screen to be built again (on the next wakeup,
  -- never from inside a field callback).
  function wiz.rebuild() rebuildWanted = true end

  -------------------------------------------------------------------------
  -- Building
  -------------------------------------------------------------------------

  local goBack
  local requestSave
  local leaveWizard
  local openStep

  local function noticeText()
    if rebootWait then return MSG_RESTARTING end
    if refused then return "@i18n(app.modules.setup_wizard.refused)@" end
    if connected == false then return "@i18n(app.modules.setup_wizard.disconnected)@" end
    if armed == true then return "@i18n(app.modules.setup_wizard.armed)@" end
    -- PASSTHROUGH forced by the wizard is meant; only the pilot's own is not.
    if hasBit(modeFlags, PASSTHROUGH_BIT) and forcedMode ~= modeOverride.BOX_PASSTHROUGH then
      return "@i18n(app.modules.setup_wizard.bypass_passthrough)@"
    end
    if hasBit(modeFlags, MANUAL_BIT) then return "@i18n(app.modules.setup_wizard.bypass_manual)@" end
    return ""
  end

  local function buildHeader(title)
    headerHandle = header.build(title, {
      onBack = ui.action("back", function() goBack() end),
      onSave = ui.action("save", function() requestSave() end),
      -- The tool button opens the step list, so it shows a checklist, not
      -- the default wrench.
      onTool = loaded and not unsupported and not rebootWait and ui.action("tool", function()
        if step and step.pause then step.pause() end
        picking = true
        rebuildWanted = true
      end) or nil,
      toolIcon = STEPS_ICON,
    })
    if headerHandle.setSaveEnabled then headerHandle.setSaveEnabled(pending) end
    if headerHandle.setReloadEnabled then headerHandle.setReloadEnabled(false) end
  end

  local function closeStep()
    ui.releaseActions()
    -- Queued replies may arrive after navigation. Detach their completion
    -- closures now, so neither the queue nor this list pins the old step.
    for i = #fetches, 1, -1 do
      fetches[i].onDone, fetches[i].results = nil, nil
      fetches[i] = nil
    end
    if step and step.leave then step.leave() end
    step = nil
    if stepOwned then
      ui.unload(stepOwned)
      stepOwned = nil
    end
    releaseAll()
  end

  openStep = function(index)
    closeStep()
    picking = false
    stepIndex = index
    memory.stepKey = STEPS[index].key
    if not (STEPS[index].needsSurfaces and #surfaces == 0) then
      local factory = assert(loadfile("app/pages/setup_wizard_" .. STEPS[index].key .. ".lua"))()
      stepOwned = factory.owned
      step = factory.new(wiz)
    end
    rebuildWanted = true
  end

  -- A step that needs control surfaces, on a model with none mixed yet.
  local noSurfacesScreen = ui.new(wiz)

  function wiz.stepNumber() return stepIndex, #STEPS end
  function wiz.isLastStep() return stepIndex >= #STEPS end

  -- A step's last screen: save, then the next step, or leave the wizard after
  -- the last one (as the configurator's Save and continue).
  function wiz.finishStep()
    if stepIndex < #STEPS then
      local target = stepIndex + 1
      requestSave(function() openStep(target) end)
    else
      requestSave(function() leaveWizard() end)
    end
  end

  -- Back to the previous step, from a step's first screen (changes stay
  -- pending, as with Next on an untouched step).
  function wiz.isFirstStep() return stepIndex <= 1 end
  function wiz.previousStep()
    if stepIndex > 1 then openStep(stepIndex - 1) end
  end

  -- The footer's default way forward (app/setup_wizard_ui.lua's nav()):
  -- Next, Save and continue once something changed, Save and finish on the
  -- last step. press defaults to wiz.finishStep().
  function wiz.forward(press)
    local text = NEXT
    if stepIndex >= #STEPS then
      text = SAVE_FINISH
    elseif pending then
      text = SAVE_NEXT
    end
    return {text = text, press = press or wiz.finishStep}
  end

  function wiz.goToStep(key)
    local index = stepIndexOf(key)
    if index then openStep(index) end
  end

  local function clearForm()
    ui.releaseActions()
    noticeField, headerHandle = nil, nil
    form.clear()
  end

  local function buildMessagePage(text)
    clearForm()
    buildHeader(PAGE_TITLE)
    addWrapped(text)
    if headerHandle.focusMenu then headerHandle.focusMenu() end
  end

  -- The step list: one button per step.
  local function buildPicker()
    clearForm()
    buildHeader(PAGE_TITLE)
    local width, height = lcd.getWindowSize()
    local gap = 6
    local top = form.height() + gap
    -- Two columns when every row still gets a usable height, else three.
    local cols = 2
    if width >= 700 or math.ceil(#STEPS / 2) * (30 + gap) > height - top then cols = 3 end
    local rows = math.ceil(#STEPS / cols)
    local h = math.max(30, math.floor((height - top - gap * rows) / rows))
    if h > 48 then h = 48 end
    local w = math.floor((width - FORM_RIGHT_PADDING - gap * (cols - 1)) / cols)
    local focus
    for i, s in ipairs(STEPS) do
      local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
      local button = form.addButton(nil, {x = col * (w + gap), y = top + row * (h + gap), w = w, h = h}, {
        text = string.format("%d. %s", i, s.title),
        options = FONT_S + CENTERED,
        press = ui.action(i, function() openStep(i) end),
      })
      if i == stepIndex then focus = button end
    end
    if focus and focus.focus then focus:focus() end
  end

  local function build()
    rebuildWanted = false
    if picking then
      buildPicker()
      return
    end
    clearForm()
    buildHeader(PAGE_TITLE .. " / " .. string.format("%d. %s", stepIndex, STEPS[stepIndex].title))
    -- Only when there is something to say: a 320 px screen has no row to spare.
    local notice = noticeText()
    noticeField = (notice ~= "") and addTextLine(notice) or nil
    if noticeField and noticeField.color then noticeField:color(art.colors().active) end
    if #missingServos > 0 and STEPS[stepIndex].needsSurfaces then
      addWrapped(string.format("@i18n(app.modules.setup_wizard.missing_servos_fmt)@",
        table.concat(missingServos, ", ")))
    end
    if not step then
      -- A step that needs control surfaces, on a model with none mixed yet.
      -- The same row as every step, with a button to the Airframe step.
      addWrapped("@i18n(app.modules.setup_wizard.no_surfaces)@")
      noSurfacesScreen:begin()
      local button = noSurfacesScreen:row(nil, {
        {text = "@i18n(app.modules.setup_wizard.go_airframe)@", primary = true,
          press = function() wiz.goToStep("airframe") end},
      })
      if button and button.focus then button:focus() end
      return
    end
    -- The step has the rest of the screen, from form.height() down.
    local focus = step.build()
    if lcd.invalidate then lcd.invalidate() end
    if focus and focus.focus then
      focus:focus()
    elseif headerHandle.focusMenu then
      headerHandle.focusMenu()
    end
  end

  -- Runs from bus callbacks too, so it never builds: a notice that appears or
  -- goes away asks for a rebuild on the next wakeup.
  local function refreshNotice()
    local notice = noticeText()
    if (notice ~= "") ~= (noticeField ~= nil) then
      rebuildWanted = true
    elseif noticeField then
      noticeField:value(notice)
    end
  end

  -------------------------------------------------------------------------
  -- Dialogs, saving, restarting and leaving
  -------------------------------------------------------------------------

  local function closeProgress()
    if not dialog then return end
    local d = dialog
    dialog = nil
    pcall(function() d:value(100) end)
    pcall(function() d:close(true) end)
  end

  local function closeMessage()
    if not messageHandle then return end
    local h = messageHandle
    messageHandle = nil
    pcall(function() h:close() end)
  end

  local function openMessage(title, body, buttons)
    closeMessage()
    messageHandle = form.openDialog({
      title = title,
      message = body,
      buttons = buttons or {{label = BTN_OK, action = function() messageHandle = nil; return true end}},
      wakeup = function() end,
      paint = function() end,
      options = TEXT_LEFT,
    })
  end

  -- Writes back everything changed since the last save, newest first. The
  -- writes are queued and go out from the background task, so the page can
  -- close straight after.
  local function revert()
    for i = #changes, 1, -1 do
      changes[i].restore(changes[i].original)
    end
    changes = {}
    changeIndex = {}
    pending = false
  end

  -- Started from wakeup (see requestSave()): the progress dialog must not be
  -- opened from inside a button or dialog callback.
  local function startSave(onSaved)
    if not pending then
      if onSaved then onSaved() end
      return
    end
    saving = true
    afterSave = onSaved
    dialog = progressDialog.open({title = MSG_SAVING_TITLE, message = MSG_SAVING_BODY})
    -- The reply arrives in the background task, where Ethos forbids form
    -- calls: it only records the outcome, and finishSave() acts on it from
    -- the next wakeup.
    bus.publish("msp.request", eeprom.buildWriteMessage(function()
      if not disposed then saveResult = "ok" end
    end, function()
      if not disposed then saveResult = "failed" end
    end))
  end

  local function finishSave(result)
    saving = false
    closeProgress()
    local done = afterSave
    afterSave = nil
    if result == "ok" then
      pending = false
      changes = {}
      changeIndex = {}
      if headerHandle and headerHandle.setSaveEnabled then headerHandle.setSaveEnabled(false) end
      if done then done() end
    else
      -- The flight controller refuses EEPROM writes while armed; the changes
      -- stay in RAM either way.
      openMessage(MSG_SAVE_FAILED_TITLE, armed and "@i18n(app.msg_please_disarm_to_save_warning)@"
        or MSG_SAVE_FAILED_BODY)
    end
  end

  -- onSaved runs once the EEPROM write is done (straight away when there is
  -- nothing to save); not at all if it fails.
  requestSave = function(onSaved)
    if saving or not loaded or saveRequest then return end
    if step and step.pause then step.pause() end
    saveRequest = {onSaved = onSaved}
  end

  -- Settings that only apply after a restart (board alignment, servo rate,
  -- ESC protocol): save, restart the flight controller, wait for it to come
  -- back, and reopen the same step, as the configurator does.
  -- A progress dialog shows the wait: the bar fills towards the give-up
  -- bound and the message counts down to it (speed 0: only updateReboot()
  -- moves the bar). A board that comes back sooner ends it early.
  local function startReboot()
    closeStep()
    rebootWait = {startedAt = os.clock(), sawDisconnect = false, remaining = REBOOT_TIMEOUT_SECONDS, percent = 0}
    bus.publish("msp.request", reboot.buildWriteMessage())
    closeProgress()
    dialog = progressDialog.open({
      title = MSG_RESTARTING_TITLE,
      message = string.format(MSG_REBOOT_WAIT, REBOOT_TIMEOUT_SECONDS),
      speed = 0,
    })
    rebuildWanted = true
  end

  function wiz.saveAndReboot()
    if armed or rebootWait then return end
    requestSave(startReboot)
  end

  -- page_runtime.lua's two edges: the link must be seen to drop (or the
  -- handshake reset), then come back with a fresh handshake.
  local function updateReboot(now)
    local wait = rebootWait
    if not wait.sawDisconnect and (connected == false or handshakeDone == false) then
      wait.sawDisconnect = true
    end
    local elapsed = now - wait.startedAt
    local remaining = math.max(0, math.ceil(REBOOT_TIMEOUT_SECONDS - elapsed))
    if wait.remaining ~= remaining then
      wait.remaining = remaining
      if dialog then dialog:message(string.format(MSG_REBOOT_WAIT, remaining)) end
    end
    local percent = math.min(99, math.floor(elapsed * 100 / REBOOT_TIMEOUT_SECONDS))
    if wait.percent ~= percent then
      wait.percent = percent
      if dialog then dialog:value(percent) end
    end
    local back = wait.sawDisconnect and connected == true and handshakeDone == true
    if back or elapsed >= REBOOT_TIMEOUT_SECONDS then
      rebootWait = nil
      -- beginLoad() opens its own Loading dialog.
      closeProgress()
      beginLoad()
    end
  end

  local function dispose()
    if disposed then return end
    disposed = true
    closeStep()
    clearForeignOverrides()
    modeOverride.release()
    closeProgress()
    closeMessage()
    if sessionHandler then
      bus.unsubscribe("session.update", sessionHandler)
      sessionHandler = nil
    end
    headerHandle = nil
    noticeField, rebootWait = nil, nil
    afterSave, saveRequest = nil, nil
    for i = #changes, 1, -1 do changes[i] = nil end
    for key in pairs(changeIndex) do changeIndex[key] = nil end
    if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
    if opts.setPaintHandler then opts.setPaintHandler(nil) end
    ui.unload(shellOwned)
  end

  local function leave()
    dispose()
    if opts.onBack then opts.onBack() end
  end
  leaveWizard = leave

  local function askLeave()
    openMessage("@i18n(app.modules.setup_wizard.leave_title)@", "@i18n(app.modules.setup_wizard.leave_body)@", {
      {label = "@i18n(app.modules.setup_wizard.leave_save)@", action = function()
        messageHandle = nil
        requestSave(leave)
        return true
      end},
      {label = "@i18n(app.modules.setup_wizard.leave_discard)@", action = function()
        messageHandle = nil
        revert()
        leave()
        return true
      end},
      {label = BTN_CANCEL, action = function()
        messageHandle = nil
        return true
      end},
    })
  end

  goBack = function()
    if disposed then return end
    if step and step.pause then step.pause() end
    if picking and step then
      -- Back from the step list returns to the step.
      picking = false
      rebuildWanted = true
      return
    end
    if pending and loaded then
      -- Opened from wakeup: a dialog opened inside a button callback is a
      -- failure this suite has hit on hardware (app/pages/motor_override.lua).
      pendingLeave = true
      return
    end
    leave()
  end

  -------------------------------------------------------------------------
  -- Loading
  -------------------------------------------------------------------------

  local function failed()
    if disposed then return end
    loadFailed = true
  end

  local function answered()
    outstanding = outstanding - 1
  end

  local function requestRest()
    outstanding = 1 + 1 + 3 + servoCount
    bus.publish("msp.request", mixerRules.buildReadPoolMessage(function(pool)
      if disposed then return end
      rules = pool
      answered()
    end, failed))
    bus.publish("msp.request", mixerConfig.buildReadMessage(function(data)
      if disposed then return end
      mixConfig = data
      answered()
    end, failed))
    for axis, codec in pairs(inputCodecs) do
      bus.publish("msp.request", codec.buildReadMessage(function(data)
        if disposed then return end
        inputs[axis] = data
        answered()
      end, failed))
    end
    for servo = 0, servoCount - 1 do
      bus.publish("msp.request", servoConfig.buildReadMessage(servo, function(data)
        if disposed then return end
        configs[servo] = data
        answered()
      end, failed))
    end
  end

  local function finishLoad()
    loaded = true
    recompute()
    closeProgress()
    if not keepalive.supported() then
      unsupported = true
      buildMessagePage("@i18n(app.modules.setup_wizard.needs_firmware)@")
      return
    end
    clearForeignOverrides()
    -- The whole wizard runs in the setup state: arming blocked, radios show
    -- SETUP. The flight controller refuses it while armed.
    refused = false
    forcedMode = nil
    holdModes()
    openStep(stepIndexOf(memory.stepKey) or 1)
  end

  -- The core reads every step relies on. Run on open and after a restart.
  beginLoad = function()
    loaded = false
    outstanding = -1
    if not dialog then
      dialog = progressDialog.open({title = MSG_LOADING_TITLE, message = MSG_LOADING_BODY})
    end
    bus.publish("msp.request", status.buildReadMessage(function(data)
      if disposed then return end
      servoCount = math.min(tonumber(data and data.servo_count) or 0, PWM_SERVO_SLOTS)
      motorCount = tonumber(data and data.motor_count) or 0
      requestRest()
    end, failed))
  end

  -------------------------------------------------------------------------
  -- Wakeup
  -------------------------------------------------------------------------

  local function poll(kind, now)
    local p = polls[kind]
    if p.inFlight and (now - p.at) < POLL_GIVE_UP then return end
    if (now - p.at) < POLL_INTERVAL[kind] then return end
    p.inFlight = true
    p.at = now
    local function done() p.inFlight = false end
    local msg
    if kind == "servo" then
      msg = servoRead.buildReadMessage(positions, done, done)
    else
      local raw = step.liveRc == "raw"
      msg = rcChannels.buildReadMessage(raw and rcChannels.RX_CHANNELS_COMMAND or rcChannels.RC_COMMAND,
        raw and rcRaw or rc, done, done)
    end
    bus.publish("msp.request", msg)
  end

  local function wakeup()
    if disposed then return end

    if loadFailed then
      loadFailed = false
      closeProgress()
      buildMessagePage(MSG_LOAD_FAILED_BODY)
      openMessage(MSG_LOAD_FAILED_TITLE, MSG_LOAD_FAILED_BODY)
      return
    end

    local now = os.clock()

    if rebootWait then
      if rebuildWanted then
        rebuildWanted = false
        buildMessagePage(MSG_RESTARTING)
      end
      updateReboot(now)
      return
    end

    if not loaded then
      if outstanding == 0 then finishLoad() end
      return
    end

    if saveResult then
      local result = saveResult
      saveResult = nil
      finishSave(result)
      return
    end

    if pendingLeave then
      pendingLeave = false
      askLeave()
      return
    end

    if saveRequest then
      local request = saveRequest
      saveRequest = nil
      startSave(request.onSaved)
      return
    end

    for i = #fetches, 1, -1 do
      local f = fetches[i]
      if f.left <= 0 then
        table.remove(fetches, i)
        local done, results = f.onDone, f.results
        f.onDone, f.results = nil, nil
        if done then done(results, f.failed) end
      end
    end

    if rebuildWanted then
      build()
      return
    end

    if step and not picking and canMove() then
      if step.livePositions then poll("servo", now) end
      if step.liveRc then poll("rc", now) end
    end
    if step and not picking and step.wakeup then step.wakeup(now) end
  end

  -------------------------------------------------------------------------
  -- Open
  -------------------------------------------------------------------------

  form.clear()
  buildHeader(PAGE_TITLE)
  form.addLine(MSG_LOADING_TITLE)

  if opts.setEventHandler then
    opts.setEventHandler(function(category, value)
      if not closeKey.shouldHandleClose(category, value) then return false end
      goBack()
      return true
    end)
  end

  if opts.setCleanupHandler then
    opts.setCleanupHandler(function() dispose() end)
  end

  if opts.setWakeupHandler then opts.setWakeupHandler(wakeup) end

  -- Steps draw their pictures below the form, from paint.
  if opts.setPaintHandler then
    opts.setPaintHandler(function()
      if disposed or rebuildWanted or picking or rebootWait then return end
      if step and step.paint then step.paint() end
    end)
  end

  -- A model that arms or a link that drops lets go of everything the step
  -- holds. The setup state itself stays held: the flight controller refuses
  -- it while armed (the hold then stops, see onRefused()) and lets it lapse
  -- while nothing reaches it.
  sessionHandler = function(snapshotData)
    local nextConnected = snapshotData and snapshotData.connected == true
    local nextArmed = snapshotData and snapshotData.isArmed == true
    local nextFlags = snapshotData and snapshotData.flightModeFlags
    local hs = snapshotData and snapshotData.handshake
    handshakeDone = hs and hs.apiVersion == true
    if nextConnected == connected and nextArmed == armed and nextFlags == modeFlags then return end
    local lost = (connected ~= false and nextConnected == false) or (armed ~= true and nextArmed == true)
    connected, armed, modeFlags = nextConnected, nextArmed, nextFlags
    if not loaded then return end
    if lost then
      releaseAxes()
      releaseServos()
      releaseProbes()
      if step and step.released then step.released() end
    end
    refreshNotice()
  end
  bus.subscribe("session.update", sessionHandler)

  beginLoad()
end

return {open = open}
