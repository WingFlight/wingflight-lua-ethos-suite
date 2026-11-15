-- Run from the repository root with Lua 5.4: lua5.4 bin/tests/setup_wizard_bus.lua
-- lib/setup_wizard_bus.lua is a port of the configurator's
-- src/tabs/setup_wizard/busOutput.js. These are the cases of the
-- configurator's scripts/tests/setup-wizard-bus-output.test.mjs, with the same
-- inputs and expected values, so a change on either side that the other lacks
-- shows up here. The codec checks at the end are the suite's own.

local ROOT = "src/wfsuite/"

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("  ok    " .. label)
  else
    failures = failures + 1
    print("  FAIL  " .. label)
    if detail then print("        " .. tostring(detail)) end
  end
end

local B = assert(loadfile(ROOT .. "lib/setup_wizard_bus.lua"))()

local SERIAL_RX = 64
-- F7B5 / F7C5 (RF007, Nexus X): UART1 is the SBUS connector
local NAMES = {[0] = "S.BUS", [1] = "TELEM", [2] = "Port C"}
local function labelOf(identifier) return NAMES[identifier] end
local function makePorts(masks)
  masks = masks or {0, 0, 0}
  local ports = {}
  for i = 1, #masks do ports[i] = {identifier = i - 1, function_mask = masks[i]} end
  return ports
end
local function masksOf(ports)
  local out = {}
  for i = 1, #ports do out[i] = tostring(ports[i].function_mask) end
  return table.concat(out, ",")
end

print("the SBUS connector is found by its name")
do
  local ports = makePorts()
  check("S.BUS on UART1", B.sbusConnectorIdentifier(ports, labelOf) == 0)
  check("S.BUS on UART2", B.sbusConnectorIdentifier(ports, function(id) return ({[0] = "DSM", [1] = "S.BUS"})[id] end) == 1)
  check("no SBUS connector", B.sbusConnectorIdentifier(ports, function(id) return ({[2] = "RX"})[id] end) == nil)
  check("no labels", B.sbusConnectorIdentifier(ports, nil) == nil)
end

print("F.Bus needs the pin swap only on the SBUS connector")
do
  local ports = makePorts()
  check("SBUS connector", B.needsPinSwap(ports, labelOf, ports[1]) == true)
  check("another port", B.needsPinSwap(ports, labelOf, ports[3]) == false)
  check("no labels", B.needsPinSwap(ports, nil, ports[1]) == false)
  check("no port", B.needsPinSwap(ports, labelOf, nil) == false)
  -- H7A1: UART3 is labelled RX, a UART RX pin too
  local function rxLabel(id) return ({[2] = "RX"})[id] end
  check("a connector labelled RX", B.needsPinSwap(ports, rxLabel, ports[3]) == true)
  check("another port on that board", B.needsPinSwap(ports, rxLabel, ports[1]) == false)
  check("RX is not offered first: only the SBUS connector is", B.recommendedPort(ports, rxLabel) == nil)
end

print("the SBUS connector is offered first when it is free")
do
  local free = makePorts()
  check("free", B.recommendedPort(free, labelOf) == free[1])
  check("in use", B.recommendedPort(makePorts({SERIAL_RX, 0, 0}), labelOf) == nil)
  check("no SBUS connector", B.recommendedPort(makePorts(), function() return "RX" end) == nil)
end

print("a bus output moves between ports and protocols")
do
  local ports = makePorts({0, SERIAL_RX, 0})
  check("none to start", B.busProtocol(ports) == nil and B.busPort(ports) == nil)

  check("F.Bus on a free port", B.setBusOutput(ports, ports[1], "fbus") ~= nil)
  check("is F.Bus", B.busProtocol(ports) == "fbus" and B.busPort(ports) == ports[1])

  -- Same port, other protocol
  local changed = B.setBusOutput(ports, ports[1], "sbus")
  check("SBUS on the same port", changed and #changed == 1 and ports[1].function_mask == B.SBUS_OUT_FUNCTION)
  check("is SBUS", B.busProtocol(ports) == "sbus")

  -- Another free port: the old one is released
  changed = B.setBusOutput(ports, ports[3], "fbus")
  check("moved", masksOf(ports) == "0," .. SERIAL_RX .. "," .. B.FBUS_OUT_FUNCTION, masksOf(ports))
  check("both ports reported changed", changed and #changed == 2)
end

print("a port in use is never taken, and clearing leaves other functions")
do
  local ports = makePorts({0, SERIAL_RX, B.FBUS_OUT_FUNCTION})
  check("port in use refused", B.setBusOutput(ports, ports[2], "fbus") == nil)
  check("unknown protocol refused", B.setBusOutput(ports, ports[1], "crsf") == nil)
  check("nothing changed", masksOf(ports) == "0," .. SERIAL_RX .. "," .. B.FBUS_OUT_FUNCTION, masksOf(ports))

  local changed = B.clearBusOutput(ports)
  check("cleared", masksOf(ports) == "0," .. SERIAL_RX .. ",0" and #changed == 1, masksOf(ports))
end

print("MSP2_WING_FBUS_MASTER_CONFIG: the port wiring is read and written only when sent")
do
  assert(loadfile(ROOT .. "lib/require.lua"))()
  package.loaded["wfsuite.lib.mspcodec"] = assert(loadfile(ROOT .. "lib/mspcodec.lua"))()
  local C = assert(loadfile(ROOT .. "lib/msp_fbus_master_config.lua"))()

  local v2 = C.decode({2, 10, 255, 255, 255, 255, 255, 255, 255, 1, 0})
  check("version 2 reads the slots", v2.forwarded[1] == 10 and v2.forwarded[2] == 255)
  check("version 2 reads the wiring", v2.pin_swap == true and v2.inverted == false)
  local out = C.encode(v2)
  check("version 2 writes ten bytes", #out == 10 and out[1] == 10 and out[9] == 1 and out[10] == 0, #out)

  local v1 = C.decode({1, 10, 255, 255, 255, 255, 255, 255, 255})
  check("version 1 has no wiring", v1.pin_swap == nil and v1.inverted == nil)
  check("version 1 writes eight bytes", #C.encode(v1) == 8, #C.encode(v1))
end

print("MSP2_WING_FBUS_MASTER_TRIAL: the request is one action byte, the reply eight bytes")
do
  local C = assert(loadfile(ROOT .. "lib/msp_fbus_master_trial.lua"))()

  check("the command is 0x5F37", C.COMMAND == 0x5F37)
  check("start, poll and stop send their action",
    C.buildStartMessage().payload[1] == 1 and C.buildPollMessage().payload[1] == 0
      and C.buildStopMessage().payload[1] == 2 and #C.buildStartMessage().payload == 1)
  check("the states are the firmware's",
    C.STATE.IDLE == 0 and C.STATE.RUNNING == 1 and C.STATE.SUCCESS == 2 and C.STATE.FAILED == 3
      and C.STATE.REJECTED == 4)

  -- SUCCESS on wiring 3 of 4: pin swap on, not inverted, 259 valid frames, port open.
  local d = C.decode({2, 2, 4, 1, 0, 3, 1, 1})
  check("state, wiring tried and count", d.state == 2 and d.combo_index == 2 and d.combo_count == 4)
  check("pin swap and inverted are booleans, as lib/msp_fbus_master_config.lua reads them",
    d.pin_swap == true and d.inverted == false)
  check("valid frames are a U16, then port open", d.frame_delta == 259 and d.port_open == true, d.frame_delta)
  check("a reply that is too short is not decoded", C.decode({2, 2, 4, 1, 0, 3, 1}) == nil and C.decode({}) == nil)

  local got, err
  local m = C.buildStartMessage(function(data) got = data end, function(reason) err = reason end)
  m.processReply(m, {1, 0, 4, 0, 1, 0, 0, 1})
  check("a full reply reaches onData", got and got.state == 1 and got.inverted == true and err == nil)
  got = nil
  m.processReply(m, {})
  check("no payload is reported as firmware without the command",
    got == nil and err == "no_payload" and C.unsupported(err))
  m.processReply(m, {1, 0, 4})
  check("a short reply is an error, not that", err == "short_reply" and not C.unsupported(err))
  check("an MSP error is firmware without the command, a timeout is not",
    C.unsupported(true) and not C.unsupported("timeout") and not C.unsupported(nil))
  for _, build in ipairs({C.buildStartMessage, C.buildPollMessage, C.buildStopMessage}) do
    if C.decode(build().simulatorResponse) == nil then err = "simulator" end
  end
  check("every simulator reply decodes", err ~= "simulator")
end

print("MSP2_WING_FBUS_SENSORS: each F.Bus device's packet count, and which answered since the read before")
do
  local C = assert(loadfile(ROOT .. "lib/msp_fbus_sensors.lua"))()
  -- Two devices: ID 5 on F.Bus with 300 packets, named "AB", one app ID; ID 7 on S.Port with 9.
  local d = C.decode({2, 5, 0, 1, 44, 1, 0, 0, 2, 65, 66, 1, 0, 11, 7, 1, 0, 9, 0, 0, 0, 0, 0})
  check("both are listed, one on F.Bus", d.total == 2 and d.fbus == 1, d.total .. "/" .. d.fbus)
  check("the F.Bus device's packet count is kept by physical ID", d.counts[5] == 300 and d.counts[7] == nil, d.counts[5])
  check("no read before: unknown", C.answering(nil, d.counts) == nil)
  check("the count rose: answering", C.answering({[5] = 299}, d.counts) == 1)
  check("the count stands still: not answering", C.answering({[5] = 300}, d.counts) == 0)
  check("a device first listed has answered", C.answering({}, d.counts) == 1)
  check("no devices", C.decode({0}).fbus == 0 and C.answering({}, C.decode({0}).counts) == 0)
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
