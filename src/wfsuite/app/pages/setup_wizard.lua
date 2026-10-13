-- Setup -> Setup Wizard.
--
-- The radio's own copy of wingflight-configurator's Setup Wizard
-- (src/tabs/setup_wizard/SetupWizard.svelte), one step at a time. This file is
-- the shell: it loads what the steps need, holds the flight controller in its
-- setup state while the wizard is open, owns every override a step asks for,
-- and saves or reverts the step's changes. Each step is its own file
-- (app/pages/setup_wizard_<step>.lua), loaded when it opens and dropped when it
-- closes, and talks to the shell only through the `wiz` table below -- the
-- counterpart of the configurator's setContext("setupWizard", ...).
--
-- Not every configurator step comes to the radio. The radio talks to the
-- flight controller through the receiver, so receiver protocol setup and the
-- ESC telemetry port stay in the Configurator. The steps here assume a mix is
-- already set up (Mixer Rules, or the Configurator's wizard) until the
-- Airframe step is ported.
--
-- Safety, as in the configurator:
--   * The wizard needs timed overrides (API 22.14). Everything it holds -- the
--     setup state, mixer and servo overrides -- is sent with a timeout and
--     re-sent by lib/override_keepalive.lua, so a radio that is switched off or
--     a link that drops lets the flight controller drop it by itself (10 s).
--     On older firmware the page explains that and stops.
--   * The setup state blocks arming while the wizard is open, and the
--     flight controller ignores overrides while armed anyway: an armed model
--     releases everything and the page says why.
--   * Every way out (Back, the close key, a step change, closing the tool)
--     releases every override the page may have set.
--
-- Changes a step makes are sent to the flight controller straight away, so
-- the surface moves; Save writes them to EEPROM. Leaving with unsaved changes
-- asks whether to save or discard them; discard writes back what the page
-- loaded. Closing the tool cannot ask, so it leaves them in RAM, unsaved, as
-- every other page does.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local header = requireModule("app/header.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local keepalive = requireModule("lib/override_keepalive.lua")
local status = requireModule("lib/msp_status.lua")
local eeprom = requireModule("lib/msp_eeprom.lua")
local mixerRules = requireModule("lib/msp_mixer_rules.lua")
local mixerInput = requireModule("lib/msp_mixer_input.lua")
local servoConfig = requireModule("lib/msp_servo_config.lua")
local servoRead = requireModule("lib/msp_servo.lua")
local servoOverride = requireModule("lib/msp_servo_override.lua")
local mixerOverride = requireModule("lib/msp_mixer_override.lua")
local modeOverride = requireModule("lib/msp_mode_override.lua")
local surfacesLib = requireModule("lib/setup_wizard_surfaces.lua")

local PAGE_TITLE = "@i18n(app.modules.setup_wizard.name)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_SAVING_TITLE = "@i18n(app.msg_saving)@"
local MSG_SAVING_BODY = "@i18n(app.msg_saving_settings)@"
local MSG_SAVE_FAILED_TITLE = "@i18n(app.msg_save_failed_title)@"
local MSG_SAVE_FAILED_BODY = "@i18n(app.msg_save_failed_body)@"
local MSG_LOAD_FAILED_TITLE = "@i18n(app.msg_load_failed_title)@"
local MSG_LOAD_FAILED_BODY = "@i18n(app.msg_load_failed_body)@"
local BTN_OK = "@i18n(app.btn_ok)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"

-- Order is the procedure, as in the configurator's STEPS: each step relies
-- on the ones before it.
local STEPS = {
  {key = "direction", title = "@i18n(app.modules.setup_wizard.step_direction)@",
    script = "app/pages/setup_wizard_direction.lua"},
}

-- PWM servos only: mixer output N drives servo config N - 1 and servo
-- override N - 1 directly. Bus servos use another index scheme and are left
-- to the Servos pages.
local PWM_SERVO_SLOTS = 8

-- Mixer inputs the wizard holds: the stabilized axes, and the flap channel
-- for the flap direction check.
local HELD_INPUTS = {1, 2, 3, surfacesLib.FLAP_INPUT}
local AXIS_INPUT = {roll = 1, pitch = 2, yaw = 3, flap = surfacesLib.FLAP_INPUT}

-- Live servo outputs, while a step shows them: four reads a second, one at a
-- time, and a read that has not answered within a second is given up.
local POLL_INTERVAL = 0.25
local POLL_GIVE_UP = 1.0

-- Flight mode bits of the "flight_mode" telemetry sensor
-- (tasks/audio_events.lua): modes that put the sticks on the surfaces.
local PASSTHROUGH_BIT = 7
local MANUAL_BIT = 10

local FORM_RIGHT_PADDING = 8

local function copyRecord(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function sameRecord(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function hasBit(flags, bit)
  return flags ~= nil and ((math.floor(flags) >> bit) & 1) == 1
end

---------------------------------------------------------------------------
-- Text helpers shared with the steps. Ethos static text does not wrap, so
-- longer instructions are wrapped here into full-width lines, measured in
-- the static text's own font (as app/header.lua does).
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
  local stage = "status"
  local outstanding = 0

  local servoCount = 0
  local rules = nil
  local inputCodecs = {roll = mixerInput.roll(), pitch = mixerInput.pitch(), yaw = mixerInput.yaw()}
  local rateKeys = {roll = "rate_stabilized_roll", pitch = "rate_stabilized_pitch", yaw = "rate_stabilized_yaw"}
  local inputs = {}        -- axis -> decoded mixer input record (sent back whole)
  local configs = {}       -- servo (0-based) -> decoded servo config
  local snapshot = nil     -- {inputs = ..., configs = ...} as last loaded or saved

  local surfaces = {}
  local missingServos = {}
  local positions = {}     -- servo (0-based) -> live output, us

  local pending = false    -- unsaved changes on the flight controller
  local connected = nil
  local armed = nil
  local modeFlags = nil
  local refused = false    -- the flight controller refused the setup state

  local stepIndex = 1
  local step = nil         -- instance of STEPS[stepIndex]
  local rebuildWanted = false

  local pollInFlight = false
  local lastPollAt = 0

  local headerHandle = nil
  local noticeField = nil
  local dialog = nil       -- progress dialog
  local messageHandle = nil
  local pendingLeave = false
  local saving = false
  local saveRequest = nil  -- {onSaved =} waiting for the next wakeup
  local saveResult = nil   -- "ok" | "failed", set by the EEPROM reply
  local afterSave = nil

  local heldInputs = {}
  local heldServos = {}

  local sessionHandler = nil
  local wiz

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

  local function releaseAll()
    releaseAxes()
    releaseServos()
  end

  -- Start from no overrides at all: one left on by another page would hold
  -- its surface still and make every check look wrong.
  local function clearForeignOverrides()
    for i = 1, #HELD_INPUTS do mixerOverride.release(HELD_INPUTS[i]) end
    servoOverride.releaseAll()
  end

  local function canMove()
    return loaded and not unsupported and not refused and connected ~= false and armed ~= true
  end

  -------------------------------------------------------------------------
  -- The interface a step sees
  -------------------------------------------------------------------------

  local function markChanged()
    pending = true
    if headerHandle and headerHandle.setSaveEnabled then headerHandle.setSaveEnabled(true) end
  end

  wiz = {
    addTextLine = addTextLine,
    addWrapped = addWrapped,
    wrapLines = wrapLines,
    lineMetrics = lineMetrics,
    windowWidth = windowWidth,
    FORM_RIGHT_PADDING = FORM_RIGHT_PADDING,
    positions = positions,
    configs = configs,
  }

  function wiz.surfaces() return surfaces end
  function wiz.missingServos() return missingServos end
  function wiz.canMove() return canMove() end

  -- Redraw the step's picture.
  function wiz.invalidate()
    if lcd.invalidate then lcd.invalidate() end
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

  wiz.releaseAxes = releaseAxes

  function wiz.holdServo(servo, raw)
    if not canMove() then return false end
    if raw < -2000 then raw = -2000 elseif raw > 2000 then raw = 2000 end
    heldServos[servo] = true
    servoOverride.hold(servo, math.floor(raw + 0.5))
    return true
  end

  wiz.releaseServo = releaseServo

  -- Sends configs[servo] as it stands now.
  function wiz.sendServo(servo)
    bus.publish("msp.request", servoConfig.buildWriteMessage(servo, configs[servo]))
    markChanged()
  end

  function wiz.invertAxis(axis)
    local record = inputs[axis]
    if not record then return end
    local key = rateKeys[axis]
    record[key] = -(record[key] or 0)
    bus.publish("msp.request", inputCodecs[axis].buildWriteMessage(record))
    markChanged()
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

  -- The step asks for its lines to be built again (on the next wakeup, never
  -- from inside a field callback), then focus on `field` if it returns one.
  function wiz.rebuild() rebuildWanted = true end

  -------------------------------------------------------------------------
  -- Building
  -------------------------------------------------------------------------

  local goBack
  local requestSave
  local leaveWizard
  local openStep

  local function noticeText()
    if refused then return "@i18n(app.modules.setup_wizard.refused)@" end
    if connected == false then return "@i18n(app.modules.setup_wizard.disconnected)@" end
    if armed == true then return "@i18n(app.modules.setup_wizard.armed)@" end
    if hasBit(modeFlags, PASSTHROUGH_BIT) then return "@i18n(app.modules.setup_wizard.bypass_passthrough)@" end
    if hasBit(modeFlags, MANUAL_BIT) then return "@i18n(app.modules.setup_wizard.bypass_manual)@" end
    return ""
  end

  local function buildHeader(title)
    headerHandle = header.build(title, {
      onBack = function() goBack() end,
      onSave = function() requestSave() end,
    })
    if headerHandle.setSaveEnabled then headerHandle.setSaveEnabled(pending) end
    if headerHandle.setReloadEnabled then headerHandle.setReloadEnabled(false) end
  end

  local function closeStep()
    if step and step.leave then step.leave() end
    step = nil
    releaseAll()
  end

  openStep = function(index)
    closeStep()
    stepIndex = index
    local factory = assert(loadfile(STEPS[index].script))()
    step = factory.new(wiz)
    rebuildWanted = true
  end

  -- A step's last screen offers this: save, then the next step, or leave the
  -- wizard after the last one (as the configurator's Save and continue).
  function wiz.isLastStep() return stepIndex >= #STEPS end

  function wiz.finishStep()
    if stepIndex < #STEPS then
      local target = stepIndex + 1
      requestSave(function() openStep(target) end)
    else
      requestSave(function() leaveWizard() end)
    end
  end

  local function buildMessagePage(text)
    form.clear()
    buildHeader(PAGE_TITLE)
    addWrapped(text)
    if headerHandle.focusMenu then headerHandle.focusMenu() end
  end

  local function build()
    rebuildWanted = false
    form.clear()
    buildHeader(PAGE_TITLE .. " / " .. STEPS[stepIndex].title)
    -- Only when there is something to say: a 320 px screen has no row to spare.
    local notice = noticeText()
    noticeField = (notice ~= "") and addTextLine(notice) or nil
    if #missingServos > 0 then
      addWrapped(string.format("@i18n(app.modules.setup_wizard.missing_servos_fmt)@",
        table.concat(missingServos, ", ")))
    end
    -- The step has the rest of the screen, from form.height() down.
    local focus = step and step.build() or nil
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
  -- Dialogs, saving and leaving
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

  local function takeSnapshot()
    local s = {inputs = {}, configs = {}}
    for axis, record in pairs(inputs) do s.inputs[axis] = copyRecord(record) end
    for servo, config in pairs(configs) do s.configs[servo] = copyRecord(config) end
    snapshot = s
  end

  -- Writes back whatever differs from the snapshot. The writes are queued and
  -- go out from the background task, so the page can close straight after.
  local function revert()
    if not snapshot then return end
    for axis, record in pairs(snapshot.inputs) do
      if inputs[axis] and not sameRecord(inputs[axis], record) then
        inputs[axis] = copyRecord(record)
        bus.publish("msp.request", inputCodecs[axis].buildWriteMessage(inputs[axis]))
      end
    end
    for servo, config in pairs(snapshot.configs) do
      if configs[servo] and not sameRecord(configs[servo], config) then
        configs[servo] = copyRecord(config)
        bus.publish("msp.request", servoConfig.buildWriteMessage(servo, configs[servo]))
      end
    end
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
      takeSnapshot()
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
    saveRequest = {onSaved = onSaved}
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
    noticeField = nil
    if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
    if opts.setPaintHandler then opts.setPaintHandler(nil) end
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
    stage = "rest"
    outstanding = 1 + 3 + servoCount
    bus.publish("msp.request", mixerRules.buildReadPoolMessage(function(pool)
      if disposed then return end
      rules = pool
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
    surfaces = surfacesLib.surfacesFromRules(rules, servoCount)
    missingServos = surfacesLib.servosPastCount(rules, servoCount, PWM_SERVO_SLOTS)
    takeSnapshot()
    closeProgress()
    if not keepalive.supported() then
      unsupported = true
      buildMessagePage("@i18n(app.modules.setup_wizard.needs_firmware)@")
      return
    end
    if #surfaces == 0 then
      buildMessagePage("@i18n(app.modules.setup_wizard.no_surfaces)@")
      return
    end
    clearForeignOverrides()
    -- The whole wizard runs in the setup state: arming blocked, radios show
    -- SETUP. The flight controller refuses it while armed.
    modeOverride.hold({}, function()
      if disposed then return end
      refused = true
      releaseAll()
      if step and step.released then step.released() end
      refreshNotice()
    end)
    openStep(1)
  end

  -------------------------------------------------------------------------
  -- Wakeup
  -------------------------------------------------------------------------

  local function poll(now)
    if not (step and step.livePositions) or not canMove() then return end
    if pollInFlight and (now - lastPollAt) < POLL_GIVE_UP then return end
    if (now - lastPollAt) < POLL_INTERVAL then return end
    pollInFlight = true
    lastPollAt = now
    bus.publish("msp.request", servoRead.buildReadMessage(positions, function()
      pollInFlight = false
    end, function()
      pollInFlight = false
    end))
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

    if not loaded then
      if stage == "rest" and outstanding <= 0 then finishLoad() end
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

    if rebuildWanted and step then
      build()
      return
    end

    local now = os.clock()
    poll(now)
    if step and step.wakeup then step.wakeup(now) end
  end

  -------------------------------------------------------------------------
  -- Open
  -------------------------------------------------------------------------

  form.clear()
  buildHeader(PAGE_TITLE)
  form.addLine(MSG_LOADING_TITLE)
  dialog = progressDialog.open({title = MSG_LOADING_TITLE, message = MSG_LOADING_BODY})

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
      if disposed or rebuildWanted then return end
      if step and step.paint then step.paint() end
    end)
  end

  -- A model that arms or a link that drops lets go of everything the step
  -- holds. The setup state itself stays held: the flight controller refuses
  -- it while armed (the hold then stops, see finishLoad()) and lets it lapse
  -- while nothing reaches it.
  sessionHandler = function(snapshotData)
    local nextConnected = snapshotData and snapshotData.connected == true
    local nextArmed = snapshotData and snapshotData.isArmed == true
    local nextFlags = snapshotData and snapshotData.flightModeFlags
    if nextConnected == connected and nextArmed == armed and nextFlags == modeFlags then return end
    local lost = (connected ~= false and nextConnected == false) or (armed ~= true and nextArmed == true)
    connected, armed, modeFlags = nextConnected, nextArmed, nextFlags
    if not loaded then return end
    if lost then
      releaseAll()
      if step and step.released then step.released() end
    end
    refreshNotice()
  end
  bus.subscribe("session.update", sessionHandler)

  bus.publish("msp.request", status.buildReadMessage(function(data)
    if disposed then return end
    servoCount = math.min(tonumber(data and data.servo_count) or 0, PWM_SERVO_SLOTS)
    requestRest()
  end, failed))
end

return {open = open}
