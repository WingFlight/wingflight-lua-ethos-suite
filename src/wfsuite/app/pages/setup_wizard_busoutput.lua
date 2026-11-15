-- Setup Wizard step: Servo bus. Opened by app/pages/setup_wizard.lua.
--
-- The radio's copy of wingflight-configurator's StepBusOutput.svelte: servos
-- on an F.Bus or SBUS line plug into a serial port instead of the servo pins,
-- which gives the model more servos than the board has pins for. Optional:
-- "None" keeps the servo pins only.
--
--   port      None, or a free serial port (the one a bus is on now is lit).
--             The port whose connector is labelled SBUS is offered first.
--             A newly chosen port starts on F.Bus.
--   protocol  F.Bus or SBUS, and how many channels the bus carries.
--   signal    after the restart: for F.Bus, how many devices answer, which
--             proves the wiring. Detect wiring has the flight controller try
--             each pin and polarity on the live port until a device answers
--             (lib/msp_fbus_master_trial.lua). SBUS is one-way, so it is
--             checked in the later steps, where each servo is moved.
--
-- F.Bus runs on the UART's TX pin. A connector labelled SBUS is the RX pin,
-- so choosing that port turns the pin swap on and any other port turns it
-- off (lib/setup_wizard_bus.lua). The pin swap and the inversion are never
-- shown as settings. Firmware that doesn't send the port wiring
-- (lib/msp_fbus_master_config.lua) keeps whatever pin it has.
--
-- A port or protocol change applies after a restart, so the step ends with
-- Save and restart and comes back on the signal screen.
--
-- A wiring that Detect wiring finds is in use at once and already in the
-- flight controller's configuration, so nothing is written and no restart is
-- needed: the footer becomes Save and continue. No stop is sent after it,
-- because a stop would put the old wiring back. Discard writes the old
-- wiring, which that firmware applies at once. A run that is still going is
-- stopped by Back, the step list, Save, arming, a lost link and leaving.
--
-- Firmware without the command answers the start with no payload. The button
-- is then "Use the other pin", which flips the pin swap and needs a restart.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local ui = requireModule("app/setup_wizard_ui.lua")
-- Freed when the step closes (app/setup_wizard_ui.lua's notLoaded()).
local OWNED = ui.notLoaded({
  "wfsuite.lib.msp_serial_config", "wfsuite.lib.msp_fbus_master_config", "wfsuite.lib.msp_fbus_master_trial",
  "wfsuite.lib.msp_fbus_sensors",
  "wfsuite.lib.msp_board_info", "wfsuite.lib.port_labels", "wfsuite.lib.setup_wizard_bus",
})
local serialConfig = requireModule("lib/msp_serial_config.lua")
local fbusMaster = requireModule("lib/msp_fbus_master_config.lua")
local trialCodec = requireModule("lib/msp_fbus_master_trial.lua")
local fbusSensors = requireModule("lib/msp_fbus_sensors.lua")
local boardInfo = requireModule("lib/msp_board_info.lua")
local portLabels = requireModule("lib/port_labels.lua")
local busLib = requireModule("lib/setup_wizard_bus.lua")
-- The shell's copy: the channel counts are part of the mixer config it holds.
local mixerConfig = requireModule("lib/msp_mixer_config.lua")

local T = {
  title = "@i18n(app.modules.setup_wizard.bus_title)@",
  intro = "@i18n(app.modules.setup_wizard.bus_intro)@",
  none = "@i18n(app.modules.setup_wizard.bus_none)@",
  protoTitle = "@i18n(app.modules.setup_wizard.bus_proto_title)@",
  protoIntro = "@i18n(app.modules.setup_wizard.bus_proto_fmt)@",
  fbusHelp = "@i18n(app.modules.setup_wizard.bus_fbus_help)@",
  sbusHelp = "@i18n(app.modules.setup_wizard.bus_sbus_help)@",
  channels = "@i18n(app.modules.setup_wizard.bus_channels_fmt)@",
  channelsHelp = "@i18n(app.modules.setup_wizard.bus_channels_help)@",
  changed = "@i18n(app.modules.setup_wizard.bus_changed)@",
  signalTitle = "@i18n(app.modules.setup_wizard.bus_signal_title)@",
  fbusSignal = "@i18n(app.modules.setup_wizard.bus_fbus_signal)@",
  sbusSignal = "@i18n(app.modules.setup_wizard.bus_sbus_signal)@",
  answering = "@i18n(app.modules.setup_wizard.bus_answering_fmt)@",
  noAnswer = "@i18n(app.modules.setup_wizard.bus_no_answer)@",
  noAnswerDetect = "@i18n(app.modules.setup_wizard.bus_no_answer_detect)@",
  txPin = "@i18n(app.modules.setup_wizard.bus_tx_pin_fmt)@",
  rxPin = "@i18n(app.modules.setup_wizard.bus_rx_pin_fmt)@",
  otherPin = "@i18n(app.modules.setup_wizard.bus_other_pin)@",
  pinFixed = "@i18n(app.modules.setup_wizard.bus_pin_fixed)@",
  detect = "@i18n(app.modules.setup_wizard.esc_detect)@",
  stop = "@i18n(app.modules.setup_wizard.esc_stop)@",
  trying = "@i18n(app.modules.setup_wizard.esc_trying_fmt)@",
  found = "@i18n(app.modules.setup_wizard.bus_found)@",
  wiringOk = "@i18n(app.modules.setup_wizard.bus_wiring_ok)@",
  notFound = "@i18n(app.modules.setup_wizard.bus_not_found)@",
  rejected = "@i18n(app.modules.setup_wizard.bus_rejected)@",
  noReply = "@i18n(app.modules.setup_wizard.esc_no_reply)@",
  stopped = "@i18n(app.modules.setup_wizard.esc_stopped)@",
  saveRestart = "@i18n(app.modules.setup_wizard.btn_save_restart)@",
}

local PROTOCOL_NAMES = {fbus = "F.Bus", sbus = "SBUS"}

local USB_VCP = 20
-- Identifiers 0 to 9 are UART1 to UART10 (app/pages/ports.lua's UART_NAMES).
local UART_MAX = 9
local PORT_COLS = 3
-- Slow: on S.Port, F.Port and F.Bus links every MSP reply blanks the flight
-- controller's sensor telemetry for a moment.
local SIGNAL_POLL_SECONDS = 2

-- The flight controller stops a run that is not polled for 3 s. It gives
-- each of the four wirings 1.5 s, so a run takes up to 6 s.
local TRIAL_POLL_SECONDS = 0.3
local TRIAL_TIMEOUT_SECONDS = 10

-- The signal screen is where the step comes back after its own restart, and
-- noTrial is that the firmware was found to have no wiring detection. Kept
-- outside the step, which is dropped and loaded again around the restart.
local resume = package.loaded["wfsuite.setup_wizard.busoutput.resume"] or {signal = false, noTrial = false}
package.loaded["wfsuite.setup_wizard.busoutput.resume"] = resume

local function new(wiz)
  local self = {}
  local scr = ui.new(wiz)

  local screen = "port"
  local ports = nil         -- every serial port but the USB VCP
  local wiring = nil        -- lib/msp_fbus_master_config.lua's data; nil if the read failed
  local board = nil         -- MSP_BOARD_INFO, for the connector names
  local restart = false     -- a change that applies after a restart
  local devices = nil       -- F.Bus devices answering; nil until the first reply
  local nextPollAt = 0
  local pollInFlight = false
  local trial = nil         -- a wiring detection that is running
  local outcome = nil       -- how the last one ended, as the text to show
  local noTrial = resume.noTrial == true   -- firmware without the wiring detection
  local left = false
  resume.noTrial = false

  local function labelOf(identifier)
    return board and portLabels.lookup(board.boardDesign, identifier, board.boardName) or nil
  end

  local function portName(port)
    return labelOf(port.identifier)
      or (port.identifier <= UART_MAX and ("UART" .. (port.identifier + 1)))
      or ("@i18n(app.modules.ports.port_prefix)@ " .. tostring(port.identifier))
  end

  -- Whether the wizard can set which pin F.Bus is on.
  local function canSetPin()
    return wiring ~= nil and wiring.pin_swap ~= nil and wiring.inverted ~= nil
  end

  wiz.fetch({serial = function(ok, err) return serialConfig.buildReadMessage(ok, err) end}, function(results)
    ports = {}
    for _, port in ipairs(results.serial and results.serial.ports or {}) do
      if port.identifier ~= USB_VCP then ports[#ports + 1] = port end
    end
    if resume.signal and busLib.busPort(ports) then screen = "signal" end
    resume.signal = false
    wiz.rebuild()
  end)
  -- Each on its own, so the step still works if one read fails: without the
  -- wiring the pin is left alone, without the board the ports are UART names.
  wiz.fetch({wiring = function(ok, err) return fbusMaster.buildReadMessage(ok, err) end}, function(results)
    wiring = results.wiring
    wiz.rebuild()
  end)
  wiz.fetch({board = function(ok, err) return boardInfo.buildReadMessage(ok, err) end}, function(results)
    board = results.board
    wiz.rebuild()
  end)

  -- Discard: what the ports, the channel counts and the pin were.

  local function snapshot()
    local masks = {}
    for i = 1, #ports do masks[i] = ports[i].function_mask or 0 end
    local mix = wiz.mixConfig()
    local o = {
      masks = masks,
      fbusChannels = mix and mix.fbus_master_channels,
      sbusChannels = mix and mix.sbus_out_channels,
    }
    -- Both are booleans, and false is a wiring to put back too.
    if canSetPin() then o.pinSwap, o.inverted = wiring.pin_swap, wiring.inverted end
    return o
  end

  local function writeWiring()
    if canSetPin() then bus.publish("msp.request", fbusMaster.buildWriteMessage(wiring)) end
  end

  local function writeMixer()
    local mix = wiz.mixConfig()
    if mix then bus.publish("msp.request", mixerConfig.buildWriteMessage(mix)) end
  end

  local function restore(o)
    for i = 1, #ports do
      if (ports[i].function_mask or 0) ~= o.masks[i] then
        ports[i].function_mask = o.masks[i]
        bus.publish("msp.request", serialConfig.buildWriteMessage(ports[i]))
      end
    end
    local mix = wiz.mixConfig()
    if mix and o.fbusChannels then
      mix.fbus_master_channels, mix.sbus_out_channels = o.fbusChannels, o.sbusChannels
      writeMixer()
    end
    -- Firmware with the wiring detection applies this at once; older
    -- firmware at the next boot.
    if o.pinSwap ~= nil and canSetPin() and (wiring.pin_swap ~= o.pinSwap or wiring.inverted ~= o.inverted) then
      wiring.pin_swap, wiring.inverted = o.pinSwap, o.inverted
      writeWiring()
    end
    restart = false
    outcome = nil
  end

  local function remember()
    wiz.change("bus_output", snapshot(), restore)
  end

  local function writePorts(changed)
    for i = 1, #changed do
      bus.publish("msp.request", serialConfig.buildWriteMessage(changed[i]))
    end
  end

  -- The SBUS connector is the UART's RX pin, every other port's is TX.
  local function applyPin(port)
    if not canSetPin() or busLib.busProtocol(ports) ~= "fbus" then return end
    local swap = busLib.needsPinSwap(ports, labelOf, port)
    if wiring.pin_swap ~= swap then
      wiring.pin_swap = swap
      writeWiring()
    end
  end

  local function isFree(port)
    return (port.function_mask or 0) == 0
  end

  local function choosePort(port)
    local current = busLib.busPort(ports)
    if port == current then
      screen = "protocol"
      return wiz.rebuild()
    end
    if not isFree(port) then return end
    remember()
    -- A newly chosen port starts on F.Bus, whose devices can prove the wiring.
    local changed = busLib.setBusOutput(ports, port, busLib.busProtocol(ports) or "fbus")
    if changed then
      writePorts(changed)
      applyPin(port)
      restart = true
      screen = "protocol"
    end
    wiz.rebuild()
  end

  local function chooseNone()
    if busLib.busPort(ports) then
      remember()
      writePorts(busLib.clearBusOutput(ports))
      restart = true
    end
    wiz.rebuild()
  end

  local function chooseProtocol(protocol)
    local port = busLib.busPort(ports)
    if not port or busLib.busProtocol(ports) == protocol then return end
    remember()
    local changed = busLib.setBusOutput(ports, port, protocol)
    if changed then
      writePorts(changed)
      applyPin(port)
      restart = true
    end
    wiz.rebuild()
  end

  local function channels()
    local mix = wiz.mixConfig()
    local protocol = busLib.busProtocol(ports)
    return mix and protocol and mix[busLib.PROTOCOLS[protocol].channelsKey] or nil
  end

  local function chooseChannels(count)
    local mix = wiz.mixConfig()
    local protocol = busLib.busProtocol(ports)
    if not mix or not protocol or not count or channels() == count then return end
    remember()
    mix[busLib.PROTOCOLS[protocol].channelsKey] = count
    writeMixer()
    wiz.rebuild()
  end

  local function useOtherPin()
    if not canSetPin() then return end
    remember()
    wiring.pin_swap = not wiring.pin_swap
    writeWiring()
    restart = true
    wiz.rebuild()
  end

  -- Wiring detection. The replies arrive in the background task, where Ethos
  -- forbids building a form: they are only recorded, and wakeup() acts on them.

  local function startTrial()
    if trial or restart or noTrial or wiz.armed() or not canSetPin() then return end
    outcome = nil
    local t = {startedAt = os.clock(), nextPollAt = 0, inFlight = true, starting = true,
      combo = 0, count = trialCodec.COMBINATIONS}
    t.onData = function(data)
      if trial ~= t then return end
      t.inFlight = false
      t.reply = data
    end
    t.onError = function(reason)
      if trial ~= t then return end
      t.inFlight = false
      t.failed = true
      t.reason = reason
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
    if stop then bus.publish("msp.request", trialCodec.buildStopMessage()) end
    outcome = text
    -- The device count is read again.
    devices, nextPollAt = nil, 0
    if not left then wiz.rebuild() end
  end

  -- Only a run that is still going: after a wiring was found there is none,
  -- and a stop then would put the old wiring back.
  local function stopTrial()
    endTrial(T.stopped, true)
  end

  -- A device answered on this wiring. The flight controller left it in use
  -- and in its configuration: there is nothing to write, only to save.
  local function wiringFound(pinSwap, inverted)
    if pinSwap == wiring.pin_swap and inverted == wiring.inverted then
      return endTrial(T.wiringOk, false)
    end
    remember()
    wiring.pin_swap, wiring.inverted = pinSwap, inverted
    endTrial(T.found, false)
  end

  local function trialReply(t, data)
    local S = trialCodec.STATE
    t.starting = false
    if data.state == S.RUNNING then
      local count = (data.combo_count or 0) > 0 and data.combo_count or trialCodec.COMBINATIONS
      if t.combo ~= data.combo_index or t.count ~= count then
        t.combo, t.count = data.combo_index, count
        wiz.rebuild()
      end
    elseif data.state == S.SUCCESS then
      wiringFound(data.pin_swap, data.inverted)
    elseif data.state == S.FAILED then
      -- The flight controller has put the wiring back by itself.
      endTrial(T.notFound, false)
    elseif data.state == S.REJECTED then
      -- No run was started.
      endTrial(T.rejected, false)
    else
      -- Idle: the flight controller gave the run up (not polled in time).
      endTrial(T.stopped, false)
    end
  end

  -- A request of the run that got no usable answer.
  local function trialFailed(t)
    if t.starting and trialCodec.unsupported(t.reason) then
      -- Firmware without the command: the pin can still be switched by hand.
      noTrial = true
      return endTrial(nil, false)
    end
    endTrial(T.noReply, true)
  end

  local function go(name)
    stopTrial()
    screen = name
    outcome = nil
    devices, nextPollAt = nil, 0
    wiz.rebuild()
  end

  local function saveRestart()
    -- Back on the signal screen afterwards, if a bus is still set up.
    resume.signal = busLib.busPort(ports) ~= nil
    resume.noTrial = noTrial
    wiz.saveAndReboot()
  end

  local SAVE_RESTART = {text = T.saveRestart, press = saveRestart}

  function self.build()
    scr:begin()
    if not ports then
      scr:text(T.title, "@i18n(app.msg_loading)@")
      return nil
    end

    local port = busLib.busPort(ports)
    local protocol = busLib.busProtocol(ports)
    -- A bus that went away (None, Discard) has no protocol or signal screen.
    if not port then screen = "port" end

    if screen == "port" then
      scr:text(T.title, T.intro, restart and T.changed or nil)
      local suggested = busLib.recommendedPort(ports, labelOf)
      local specs = {{text = T.none, primary = port == nil, press = chooseNone}}
      for _, p in ipairs(ports) do
        specs[#specs + 1] = {
          text = portName(p),
          -- With no bus yet the SBUS connector is where the encoder starts.
          primary = p == port or (port == nil and p == suggested),
          disabled = p ~= port and not isFree(p),
          press = function() choosePort(p) end,
        }
      end
      if port == nil and suggested then specs[1].primary = false end
      -- The grid first: the encoder visits fields in the order they are made.
      local focus = scr:grid(specs, PORT_COLS)
      local forward = scr:row(nil, nil, restart and SAVE_RESTART or nil)
      return focus or forward

    elseif screen == "protocol" then
      scr:text(T.protoTitle, string.format(T.protoIntro, portName(port)), restart and T.changed or nil)
      local values = {}
      for _, count in ipairs(busLib.PROTOCOLS[protocol].channels) do
        values[#values + 1] = {string.format(T.channels, count), count}
      end
      local focus = scr:choices({
        {text = PROTOCOL_NAMES.fbus, help = T.fbusHelp, current = protocol == "fbus",
          press = function() chooseProtocol("fbus") end},
        {text = PROTOCOL_NAMES.sbus, help = T.sbusHelp, current = protocol == "sbus",
          press = function() chooseProtocol("sbus") end},
        {values = values, help = T.channelsHelp,
          get = function() return channels() end,
          set = function(value) chooseChannels(tonumber(value)) end},
      })
      -- The signal can only be checked on the port the board booted with.
      local forward = scr:row(function() go("port") end, nil,
        restart and SAVE_RESTART or {text = "@i18n(app.modules.setup_wizard.btn_next)@", press = function() go("signal") end})
      return focus or forward
    end

    -- signal
    if protocol == "sbus" then
      scr:text(T.signalTitle, T.sbusSignal)
      return scr:row(function() go("protocol") end)
    end
    local status
    if trial then
      status = string.format(T.trying, trial.combo + 1, trial.count)
    elseif restart then
      status = T.changed
    elseif outcome then
      status = outcome
    elseif devices ~= nil then
      status = devices > 0 and string.format(T.answering, devices) or (noTrial and T.noAnswer or T.noAnswerDetect)
    end
    local pin = canSetPin() and string.format(wiring.pin_swap and T.rxPin or T.txPin, portName(port)) or T.pinFixed
    scr:text(T.signalTitle, T.fbusSignal .. " " .. pin, status)
    local action
    if not canSetPin() then
      action = nil
    elseif noTrial then
      action = {text = T.otherPin, small = true, disabled = wiz.armed(), press = useOtherPin}
    elseif trial then
      action = {text = T.stop, primary = true, press = stopTrial}
    else
      -- The wiring can only be tried on the port the board booted with.
      action = {text = T.detect, small = true, disabled = restart or wiz.armed(), press = startTrial}
    end
    -- The way forward waits for a run to end. After a new wiring was found
    -- it is Save and continue (wiz.forward()).
    local forward = restart and SAVE_RESTART or wiz.forward()
    if trial then forward = {text = forward.text, press = forward.press, disabled = true} end
    return scr:row(function() go("protocol") end, action and {action} or nil, forward)
  end

  function self.paint() scr:paint() end

  function self.wakeup(now)
    -- A running detection: one request in flight, given up after the timeout.
    -- The device count is not read meanwhile.
    local t = trial
    if t then
      if t.failed then return trialFailed(t) end
      if t.reply then
        local data = t.reply
        t.reply = nil
        trialReply(t, data)
        if trial ~= t then return end
      end
      if not wiz.canMove() then return endTrial(T.stopped, true) end
      -- Nothing found in time is reported as nothing answering.
      if now - t.startedAt > TRIAL_TIMEOUT_SECONDS then return endTrial(T.notFound, true) end
      if t.inFlight or now < t.nextPollAt then return end
      t.inFlight = true
      t.nextPollAt = now + TRIAL_POLL_SECONDS
      bus.publish("msp.request", trialCodec.buildPollMessage(t.onData, t.onError))
      return
    end

    if screen ~= "signal" or restart or pollInFlight or not ports then return end
    if busLib.busProtocol(ports) ~= "fbus" or now < nextPollAt then return end
    nextPollAt = now + SIGNAL_POLL_SECONDS
    pollInFlight = true
    -- The reply only records the count: the screen is rebuilt from wakeup.
    bus.publish("msp.request", fbusSensors.buildReadMessage(function(data)
      pollInFlight = false
      if left then return end
      if devices ~= data.fbus then
        devices = data.fbus
        wiz.rebuild()
      end
    end, function()
      pollInFlight = false
    end))
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
