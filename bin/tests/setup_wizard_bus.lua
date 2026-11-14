-- Run from the repository root with Lua 5.4: lua5.4 bin/tests/setup_wizard_bus.lua
-- lib/setup_wizard_bus.lua is a port of the configurator's
-- src/tabs/setup_wizard/busOutput.js. These are the cases of the
-- configurator's scripts/tests/setup-wizard-bus-output.test.mjs, with the same
-- inputs and expected values, so a change on either side that the other lacks
-- shows up here. The codec check at the end is the suite's own.

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

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
