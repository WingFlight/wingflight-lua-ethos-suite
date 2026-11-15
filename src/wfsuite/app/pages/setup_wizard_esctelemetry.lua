-- Setup Wizard step: ESC telemetry. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepEscTelemetry.svelte: an
-- ESC that sends telemetry on a wire of its own plugs that wire into a serial
-- port. Optional: "Not used" leaves the model without it.
--
--   protocol  Not used, or the ESC's telemetry protocol from a drop-down.
--             Not used turns the ESC sensor feature off, frees the port, sets
--             the protocol to none and takes the battery meters off the ESC.
--             F.BUS and SRXL2 telemetry don't use an ESC telemetry port, so
--             they are not offered; when one is set the step says so. With
--             the Castle Link motor protocol the telemetry is read on the
--             throttle wire: the step says so and changes nothing.
--   port      a free serial port (the one the telemetry is on now is lit).
--   wiring    after the restart: Detect wiring has the flight controller try
--             each way the wire can be connected (half duplex, pin swap) on
--             the live port until the ESC answers
--             (lib/msp_esc_sensor_trial.lua). A wiring that differs from the
--             one set is written. Half duplex and pin swap are never shown
--             as settings.
--   battery   use the ESC's voltage and its current for the battery, each
--             yes or no. Turning one off puts back the source it had.
--
-- Cell count, capacity, the RPM pin, bidirectional DShot and the pole counts
-- stay on their own pages.
--
-- A protocol, port, wiring or meter source change applies after a restart,
-- so those screens end with Save and restart, and the step comes back on the
-- wiring screen (the battery screen, after a restart from there).

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({
  "wfsuite.lib.msp_serial_config", "wfsuite.lib.msp_esc_sensor_config", "wfsuite.lib.msp_esc_sensor_trial",
  "wfsuite.lib.msp_feature_config", "wfsuite.lib.msp_battery_config", "wfsuite.lib.msp_board_info",
  "wfsuite.lib.port_labels", "wfsuite.lib.msp_motor_config",
})
local serialConfig = requireModule("lib/msp_serial_config.lua")
local escSensor = requireModule("lib/msp_esc_sensor_config.lua")
local trialCodec = requireModule("lib/msp_esc_sensor_trial.lua")
local featureConfig = requireModule("lib/msp_feature_config.lua")
local batteryConfig = requireModule("lib/msp_battery_config.lua")
local boardInfo = requireModule("lib/msp_board_info.lua")
local portLabels = requireModule("lib/port_labels.lua")
local motorConfig = requireModule("lib/msp_motor_config.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.esc_title)@",
  intro = "@i18n(app.modules.setup_wizard.esc_intro)@",
  noMotor = "@i18n(app.modules.setup_wizard.esc_no_motor)@",
  elsewhere = "@i18n(app.modules.setup_wizard.esc_elsewhere_fmt)@",
  castle = "@i18n(app.modules.setup_wizard.esc_castle)@",
  notUsed = "@i18n(app.modules.setup_wizard.esc_not_used)@",
  notUsedHelp = "@i18n(app.modules.setup_wizard.esc_not_used_help)@",
  choose = "@i18n(app.modules.setup_wizard.esc_choose)@",
  protocolHelp = "@i18n(app.modules.setup_wizard.esc_protocol_help)@",
  portTitle = "@i18n(app.modules.setup_wizard.esc_port_title)@",
  portIntro = "@i18n(app.modules.setup_wizard.esc_port_fmt)@",
  portNone = "@i18n(app.modules.setup_wizard.esc_port_none)@",
  changed = "@i18n(app.modules.setup_wizard.esc_changed)@",
  wiringTitle = "@i18n(app.modules.setup_wizard.esc_wiring_title)@",
  wiringText = "@i18n(app.modules.setup_wizard.esc_wiring_text)@",
  detect = "@i18n(app.modules.setup_wizard.esc_detect)@",
  stop = "@i18n(app.modules.setup_wizard.esc_stop)@",
  trying = "@i18n(app.modules.setup_wizard.esc_trying_fmt)@",
  found = "@i18n(app.modules.setup_wizard.esc_found)@",
  wiringOk = "@i18n(app.modules.setup_wizard.esc_wiring_ok)@",
  notFound = "@i18n(app.modules.setup_wizard.esc_not_found)@",
  rejected = "@i18n(app.modules.setup_wizard.esc_rejected)@",
  noReply = "@i18n(app.modules.setup_wizard.esc_no_reply)@",
  stopped = "@i18n(app.modules.setup_wizard.esc_stopped)@",
  batteryTitle = "@i18n(app.modules.setup_wizard.esc_battery_title)@",
  batteryText = "@i18n(app.modules.setup_wizard.esc_battery_text)@",
  useVoltage = "@i18n(app.modules.setup_wizard.esc_use_voltage)@",
  useCurrent = "@i18n(app.modules.setup_wizard.esc_use_current)@",
  yes = "@i18n(app.modules.setup_wizard.btn_yes)@",
  no = "@i18n(app.modules.setup_wizard.btn_no)@",
  next = "@i18n(app.modules.setup_wizard.btn_next)@",
  saveRestart = "@i18n(app.modules.setup_wizard.btn_save_restart)@",
  loading = "@i18n(app.msg_loading)@",
  loadFailed = "@i18n(app.msg_load_failed_body)@",
}

-- FEATURE_ESC_SENSOR (firmware config/feature.h) and the serial port
-- function FUNCTION_ESC_SENSOR (io/serial.h).
local ESC_SENSOR_BIT = 27
local ESC_SENSOR_FUNCTION = 1024

-- Battery meter sources (lib/msp_battery_config.lua's voltageMeterSource and
-- currentMeterSource): the board's own ADC, and ESC telemetry.
local METER_ADC = 1
local METER_ESC = 2
local YES_NO = {{T.no, 0}, {T.yes, 1}}

-- These read the ESC another way (F.BUS through the receiver or the F.Bus
-- output, SRXL2 on its own port), not on an ESC telemetry port.
local OWN_PORT = {["FrSky F.BUS"] = true, ["SRXL2"] = true}

-- The drop-down: a "choose" entry shown while no protocol is set, then
-- every protocol that uses an ESC telemetry port.
local CHOOSE = -1
local PROTOCOL_NAMES = {}
local PROTOCOL_VALUES = {{T.choose, CHOOSE}}
for _, entry in ipairs(escSensor.PROTOCOL_CHOICES) do
  local name, id = entry[1], entry[2]
  PROTOCOL_NAMES[id] = name
  if id > 0 and not OWN_PORT[name] then PROTOCOL_VALUES[#PROTOCOL_VALUES + 1] = {name, id} end
end

local USB_VCP = 20
-- Identifiers 0 to 9 are UART1 to UART10 (app/pages/ports.lua's UART_NAMES).
local UART_MAX = 9
local PORT_COLS = 3

-- The flight controller stops a run that is not polled for 3 s. Slower
-- protocols get 2.5 s per wiring, so all four take up to 10 s.
local POLL_SECONDS = 0.3
local TRIAL_TIMEOUT_SECONDS = 12

-- Where the step comes back after its own restart. Kept outside the step,
-- which is dropped and loaded again around the restart.
local resume = package.loaded["wfsuite.setup_wizard.esctelemetry.resume"] or {screen = nil}
package.loaded["wfsuite.setup_wizard.esctelemetry.resume"] = resume

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  local screen = "protocol"
  local loaded, failed = false, false
  local ports = nil         -- every serial port but the USB VCP
  local esc = nil           -- lib/msp_esc_sensor_config.lua's data
  local features = nil      -- the enabled feature bits
  local castle = false      -- the motor protocol is Castle Link
  local battery = nil       -- lib/msp_battery_config.lua's data; nil if the read failed
  local meterBefore = {}    -- the meter sources when the step opened
  local board = nil         -- MSP_BOARD_INFO, for the connector names
  local restart = false     -- a change that applies after a restart
  local trial = nil         -- a wiring detection that is running
  local outcome = nil       -- how the last one ended, as the text to show
  local left = false

  wiz.fetch({
    serial = function(ok, err) return serialConfig.buildReadMessage(ok, err) end,
    esc = function(ok, err) return escSensor.buildReadMessage(ok, err) end,
    feature = function(ok, err) return featureConfig.buildReadMessage(ok, err) end,
    -- Only for Castle Link; the step works without it.
    motor = function(ok, err) return motorConfig.buildReadMessage(ok, err) end,
  }, function(results)
    loaded = true
    esc = results.esc
    castle = results.motor ~= nil and results.motor.motor_pwm_protocol == motorConfig.CASTLE_PROTOCOL
    features = results.feature and results.feature.enabledFeatures
    local back = resume.screen
    resume.screen = nil
    if not (results.serial and esc and features) then
      failed = true
      return wiz.rebuild()
    end
    ports = {}
    for _, port in ipairs(results.serial.ports or {}) do
      if port.identifier ~= USB_VCP then ports[#ports + 1] = port end
    end
    -- build() falls back to an earlier screen if the telemetry is not set up.
    if back then screen = back end
    wiz.rebuild()
  end)
  -- Each on its own, so the step still works if one read fails: without the
  -- battery there is no battery screen, without the board the ports are UART
  -- names.
  wiz.fetch({battery = function(ok, err) return batteryConfig.buildReadMessage(ok, err) end}, function(results)
    battery = results.battery
    if battery then
      meterBefore.voltageMeterSource = battery.voltageMeterSource
      meterBefore.currentMeterSource = battery.currentMeterSource
    end
    wiz.rebuild()
  end)
  wiz.fetch({board = function(ok, err) return boardInfo.buildReadMessage(ok, err) end}, function(results)
    board = results.board
    wiz.rebuild()
  end)

  local function portName(port)
    return (board and portLabels.lookup(board.boardDesign, port.identifier, board.boardName))
      or (port.identifier <= UART_MAX and ("UART" .. (port.identifier + 1)))
      or ("@i18n(app.modules.ports.port_prefix)@ " .. tostring(port.identifier))
  end

  local function maskOf(port)
    return port.function_mask or 0
  end

  -- The port the ESC telemetry is on, or nil.
  local function escPort()
    for i = 1, #ports do
      if maskOf(ports[i]) & ESC_SENSOR_FUNCTION ~= 0 then return ports[i] end
    end
    return nil
  end

  local function isUsed()
    return (esc.protocol or 0) > 0
  end

  local function isElsewhere()
    return OWN_PORT[PROTOCOL_NAMES[esc.protocol or 0] or ""] == true
  end

  -- Writes. Each goes out as soon as the value is set.

  local function writePort(port)
    bus.publish("msp.request", serialConfig.buildWriteMessage(port))
  end

  local function writeEsc()
    bus.publish("msp.request", escSensor.buildWriteMessage(esc))
  end

  local function writeBattery()
    bus.publish("msp.request", batteryConfig.buildWriteMessage(battery))
  end

  local function setFeature(on)
    local value = featureConfig.setBit(features, ESC_SENSOR_BIT, on)
    if value == features then return end
    features = value
    bus.publish("msp.request", featureConfig.buildWriteMessage({enabledFeatures = features}))
  end

  -- The source a meter gets: the ESC, or what it had before this step put it
  -- on the ESC (the board's own sensor, if it was on the ESC already).
  local function meterTarget(key, on)
    local now = battery[key]
    if on then return METER_ESC end
    if now ~= METER_ESC then return now end
    return meterBefore[key] == METER_ESC and METER_ADC or meterBefore[key]
  end

  -- Discard: what the ports, the ESC sensor config, the features and the
  -- meter sources were.

  local function snapshot()
    local masks = {}
    for i = 1, #ports do masks[i] = maskOf(ports[i]) end
    return {
      masks = masks,
      esc = esc,
      features = features,
      voltage = battery and battery.voltageMeterSource,
      current = battery and battery.currentMeterSource,
    }
  end

  local function restore(o)
    for i = 1, #ports do
      if maskOf(ports[i]) ~= o.masks[i] then
        ports[i].function_mask = o.masks[i]
        writePort(ports[i])
      end
    end
    for key, value in pairs(o.esc) do esc[key] = value end
    writeEsc()
    if features ~= o.features then
      features = o.features
      bus.publish("msp.request", featureConfig.buildWriteMessage({enabledFeatures = features}))
    end
    if battery and (battery.voltageMeterSource ~= o.voltage or battery.currentMeterSource ~= o.current) then
      battery.voltageMeterSource, battery.currentMeterSource = o.voltage, o.current
      writeBattery()
    end
    restart = false
  end

  local function remember()
    wiz.change("esc_telemetry", snapshot(), restore)
  end

  -- Protocol and port.

  local function chooseProtocol(id)
    if id == nil or id == CHOOSE or id == esc.protocol then return end
    remember()
    esc.protocol = id
    writeEsc()
    setFeature(true)
    restart = true
    outcome = nil
    screen = "port"
    wiz.rebuild()
  end

  local function chooseNotUsed()
    local port = escPort()
    local used = isUsed() or port ~= nil or featureConfig.getBit(features, ESC_SENSOR_BIT)
    if not used then return end
    remember()
    -- Protocol none too: a protocol left set could turn the feature back on
    -- at the next save or boot (firmware config.c, validateAndFixConfig()).
    esc.protocol = 0
    writeEsc()
    setFeature(false)
    if port then
      port.function_mask = maskOf(port) & ~ESC_SENSOR_FUNCTION
      writePort(port)
    end
    -- The battery can't be read from an ESC that isn't there.
    if battery then
      local voltage = meterTarget("voltageMeterSource", false)
      local current = meterTarget("currentMeterSource", false)
      if voltage ~= battery.voltageMeterSource or current ~= battery.currentMeterSource then
        battery.voltageMeterSource, battery.currentMeterSource = voltage, current
        writeBattery()
      end
    end
    restart = true
    outcome = nil
    wiz.rebuild()
  end

  local function isFree(port)
    return maskOf(port) == 0
  end

  local function go(name)
    screen = name
    wiz.rebuild()
  end

  local function choosePort(port)
    local current = escPort()
    if port == current then
      -- The wiring can only be detected on the port the board booted with.
      if not restart then go("wiring") end
      return
    end
    if not isFree(port) then return end
    remember()
    if current then
      current.function_mask = maskOf(current) & ~ESC_SENSOR_FUNCTION
      writePort(current)
    end
    port.function_mask = ESC_SENSOR_FUNCTION
    writePort(port)
    setFeature(true)
    restart = true
    outcome = nil
    wiz.rebuild()
  end

  -- Wiring detection. The replies arrive in the background task, where Ethos
  -- forbids building a form: they are only recorded, and wakeup() acts on them.

  local function sendStop()
    bus.publish("msp.request", trialCodec.buildStopMessage())
  end

  local function startTrial()
    if trial or restart or wiz.armed() then return end
    outcome = nil
    local t = {startedAt = os.clock(), nextPollAt = 0, inFlight = true, combo = 0, count = trialCodec.COMBINATIONS}
    t.onData = function(data)
      if trial ~= t then return end
      t.inFlight = false
      t.reply = data
    end
    t.onError = function()
      if trial ~= t then return end
      t.inFlight = false
      t.failed = true
    end
    trial = t
    bus.publish("msp.request", trialCodec.buildStartMessage(t.onData, t.onError))
    wiz.rebuild()
  end

  -- Ends the run with the text to show. stop: the flight controller may still
  -- be trying, so it is told to put the wiring back.
  local function endTrial(text, stop)
    if not trial then return end
    trial = nil
    if stop then sendStop() end
    outcome = text
    if not left then wiz.rebuild() end
  end

  local function stopTrial()
    endTrial(T.stopped, true)
  end

  -- The ESC answered on this wiring. The flight controller left it live; the
  -- stop puts the port back as it booted, so the new wiring, like every
  -- change here, is used from the next restart.
  local function wiringFound(halfDuplex, pinSwap)
    trial = nil
    sendStop()
    if halfDuplex == esc.half_duplex and pinSwap == esc.pin_swap then
      outcome = T.wiringOk
    else
      remember()
      esc.half_duplex, esc.pin_swap = halfDuplex, pinSwap
      writeEsc()
      restart = true
      outcome = T.found
    end
    wiz.rebuild()
  end

  local function trialReply(t, data)
    local S = trialCodec.STATE
    if data.state == S.RUNNING then
      local count = (data.combo_count or 0) > 0 and data.combo_count or trialCodec.COMBINATIONS
      if t.combo ~= data.combo_index or t.count ~= count then
        t.combo, t.count = data.combo_index, count
        wiz.rebuild()
      end
    elseif data.state == S.SUCCESS then
      wiringFound(data.half_duplex, data.pin_swap)
    elseif data.state == S.FAILED then
      -- The flight controller has put the wiring back by itself.
      endTrial(T.notFound, false)
    elseif data.state == S.REJECTED then
      -- No run was started. No stop: see lib/msp_esc_sensor_trial.lua.
      endTrial(T.rejected, false)
    else
      -- Idle: the flight controller gave the run up (not polled in time).
      endTrial(T.stopped, false)
    end
  end

  -- Battery.

  local function chooseMeter(key, on)
    if not battery then return end
    local target = meterTarget(key, on)
    if target == battery[key] then return end
    remember()
    battery[key] = target
    writeBattery()
    -- A meter source is set up at boot.
    restart = true
    wiz.rebuild()
  end

  local function saveRestart()
    -- Back on the wiring screen afterwards (the battery screen from there),
    -- if the telemetry is still set up.
    resume.screen = (isUsed() and escPort()) and (screen == "battery" and "battery" or "wiring") or nil
    wiz.saveAndReboot()
  end

  local SAVE_RESTART = {text = T.saveRestart, press = saveRestart}

  function self.build()
    scr:begin()
    if wiz.motorCount() == 0 then
      scr:text(T.title, T.noMotor)
      return scr:row()
    end
    if failed then
      scr:text(T.title, T.loadFailed)
      return scr:row()
    end
    if not loaded then
      scr:text(T.title, T.loading)
      return nil
    end
    -- Set up some other way: Castle Link reads telemetry on the throttle
    -- wire, F.BUS and SRXL2 don't use an ESC telemetry port.
    if castle then
      scr:text(T.title, T.castle)
      return scr:row()
    end
    if isElsewhere() then
      scr:text(T.title, string.format(T.elsewhere, PROTOCOL_NAMES[esc.protocol]))
      return scr:row()
    end

    local used = isUsed()
    local port = escPort()
    -- Telemetry that went away (Not used, Discard) has no port, wiring or
    -- battery screen; without a port there is no wiring to detect.
    if not used then
      screen = "protocol"
    elseif not port and screen ~= "protocol" then
      screen = "port"
    elseif screen == "battery" and not battery then
      screen = "wiring"
    end

    if screen == "protocol" then
      scr:text(T.title, T.intro, restart and T.changed or nil)
      -- The list first: the encoder visits fields in the order they are made.
      local focus = scr:choices({
        {text = T.notUsed, help = T.notUsedHelp, current = not used, press = chooseNotUsed},
        {values = PROTOCOL_VALUES, help = T.protocolHelp, current = used,
          get = function() return isUsed() and esc.protocol or CHOOSE end,
          set = function(value) chooseProtocol(tonumber(value)) end},
      })
      local forward
      if used then
        forward = {text = T.next, press = function() go("port") end}
      elseif restart then
        forward = SAVE_RESTART
      end
      local rowFocus = scr:row(nil, nil, forward)
      return focus or rowFocus

    elseif screen == "port" then
      scr:text(T.portTitle, string.format(T.portIntro, PROTOCOL_NAMES[esc.protocol] or ""),
        (restart and port) and T.changed or (not port and T.portNone or nil))
      local specs = {}
      for _, p in ipairs(ports) do
        specs[#specs + 1] = {
          text = portName(p),
          primary = p == port,
          disabled = p ~= port and not isFree(p),
          press = function() choosePort(p) end,
        }
      end
      local focus = scr:grid(specs, PORT_COLS)
      local forward
      if restart then
        forward = SAVE_RESTART
      elseif port then
        forward = {text = T.next, press = function() go("wiring") end}
      end
      local rowFocus = scr:row(function() go("protocol") end, nil, forward)
      return focus or rowFocus

    elseif screen == "wiring" then
      local status = outcome
      if trial then
        status = string.format(T.trying, trial.combo + 1, trial.count)
      elseif restart and not status then
        status = T.changed
      end
      scr:text(T.wiringTitle, T.wiringText, status)
      local action
      if trial then
        action = {text = T.stop, primary = true, press = stopTrial}
      else
        action = {text = T.detect, primary = not restart, disabled = restart or wiz.armed(), press = startTrial}
      end
      local forward
      if restart then
        forward = SAVE_RESTART
      elseif battery then
        forward = {text = T.next, press = function() go("battery") end}
      end
      if forward and trial then
        forward = {text = forward.text, press = forward.press, disabled = true}
      end
      return scr:row(function() stopTrial(); go("port") end, {action}, forward)
    end

    -- battery
    scr:text(T.batteryTitle, T.batteryText, restart and T.changed or nil)
    local focus = scr:choices({
      {values = YES_NO, help = T.useVoltage, current = true,
        get = function() return battery.voltageMeterSource == METER_ESC and 1 or 0 end,
        set = function(value) chooseMeter("voltageMeterSource", tonumber(value) == 1) end},
      {values = YES_NO, help = T.useCurrent,
        get = function() return battery.currentMeterSource == METER_ESC and 1 or 0 end,
        set = function(value) chooseMeter("currentMeterSource", tonumber(value) == 1) end},
    })
    local rowFocus = scr:row(function() go("wiring") end, nil, restart and SAVE_RESTART or nil)
    return focus or rowFocus
  end

  function self.paint() scr:paint() end

  -- Polls a running detection, one request in flight, and gives it up after
  -- the timeout.
  function self.wakeup(now)
    local t = trial
    if not t then return end
    if t.failed then return endTrial(T.noReply, true) end
    if t.reply then
      local data = t.reply
      t.reply = nil
      trialReply(t, data)
      if trial ~= t then return end
    end
    if now - t.startedAt > TRIAL_TIMEOUT_SECONDS or not wiz.canMove() then
      return endTrial(T.noReply, true)
    end
    if t.inFlight or now < t.nextPollAt then return end
    t.inFlight = true
    t.nextPollAt = now + POLL_SECONDS
    bus.publish("msp.request", trialCodec.buildPollMessage(t.onData, t.onError))
  end

  -- The step list, Save and Back: a detection does not run behind them.
  function self.pause() stopTrial() end

  function self.released()
    stopTrial()
    scr:refresh()
  end

  function self.leave()
    left = true
    stopTrial()
  end

  return self
end

return {new = new, owned = OWNED}
