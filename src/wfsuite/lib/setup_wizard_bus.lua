-- The Setup Wizard's Servo bus step: which port a bus output (F.Bus or SBUS)
-- is on, and which pin F.Bus uses there.
--
-- A port of wingflight-configurator src/tabs/setup_wizard/busOutput.js. Keep
-- the two in step; bin/tests/setup_wizard_bus.lua has the cases of the
-- configurator's scripts/tests/setup-wizard-bus-output.test.mjs. Ports are in
-- lib/msp_serial_config.lua's shape (function_mask, where the JS has
-- functionMask).
--
-- Servo N is sent on PWM output N where the board has one and on channel N of
-- a bus output when one is set up on a serial port (firmware flight/servos.c),
-- so a bus output is what lifts the servo count past the board's PWM pins.

if package.loaded["wfsuite.lib.setup_wizard_bus"] then
  return package.loaded["wfsuite.lib.setup_wizard_bus"]
end

local M = {}

-- Serial port function bits (firmware io/serial.h): FUNCTION_SBUS_OUT and
-- FUNCTION_FBUS_MASTER.
M.SBUS_OUT_FUNCTION = 1 << 18
M.FBUS_OUT_FUNCTION = 1 << 19
local BUS_FUNCTIONS = M.SBUS_OUT_FUNCTION | M.FBUS_OUT_FUNCTION

-- channelsKey is the channel count in lib/msp_mixer_config.lua's data.
M.PROTOCOLS = {
  fbus = {mask = M.FBUS_OUT_FUNCTION, channels = {8, 12, 16, 24}, channelsKey = "fbus_master_channels"},
  sbus = {mask = M.SBUS_OUT_FUNCTION, channels = {8, 12, 16}, channelsKey = "sbus_out_channels"},
}

local function maskOf(port)
  return port and port.function_mask or 0
end

-- The port a bus output is on, or nil.
function M.busPort(ports)
  for i = 1, #ports do
    if maskOf(ports[i]) & BUS_FUNCTIONS ~= 0 then return ports[i] end
  end
  return nil
end

-- "fbus", "sbus" or nil. F.Bus wins if a port list somehow has both.
function M.busProtocol(ports)
  local sbus = false
  for i = 1, #ports do
    local mask = maskOf(ports[i])
    if mask & M.FBUS_OUT_FUNCTION ~= 0 then return "fbus" end
    if mask & M.SBUS_OUT_FUNCTION ~= 0 then sbus = true end
  end
  return sbus and "sbus" or nil
end

-- Identifier of the port whose connector is labelled SBUS, or nil.
-- labelOf(identifier) gives the connector name of the connected board
-- (lib/port_labels.lua's lookup), or nil.
function M.sbusConnectorIdentifier(ports, labelOf)
  if not labelOf then return nil end
  for i = 1, #ports do
    local name = labelOf(ports[i].identifier)
    if name then
      local upper = string.upper(name)
      if upper == "S.BUS" or upper == "SBUS" then return ports[i].identifier end
    end
  end
  return nil
end

-- Whether F.Bus on this port needs the pin swap. F.Bus runs half-duplex on
-- the UART's TX pin. A connector labelled SBUS is a receiver input, the
-- UART's RX pin, and so is one labelled RX (the H7A1's UART3 in
-- lib/port_labels.lua), so F.Bus only reaches either with the pins swapped.
function M.needsPinSwap(ports, labelOf, port)
  if not port then return false end
  if port.identifier == M.sbusConnectorIdentifier(ports, labelOf) then return true end
  local name = labelOf and labelOf(port.identifier)
  return name ~= nil and string.upper(name) == "RX"
end

-- Takes every bus output off the ports. Returns the ports it changed.
function M.clearBusOutput(ports)
  local changed = {}
  for i = 1, #ports do
    local mask = maskOf(ports[i])
    if mask & BUS_FUNCTIONS ~= 0 then
      ports[i].function_mask = mask & ~BUS_FUNCTIONS
      changed[#changed + 1] = ports[i]
    end
  end
  return changed
end

-- Puts the protocol's bus output on `port`, and off every other port. The
-- port must be free or already a bus output. Returns the ports it changed,
-- or nil when it changed nothing.
function M.setBusOutput(ports, port, protocol)
  local config = M.PROTOCOLS[protocol]
  if not config or not port or maskOf(port) & ~BUS_FUNCTIONS ~= 0 then return nil end
  local changed = M.clearBusOutput(ports)
  port.function_mask = config.mask
  for i = 1, #changed do
    if changed[i] == port then return changed end
  end
  changed[#changed + 1] = port
  return changed
end

-- The port to offer first: the SBUS connector if it is free (or already the
-- bus output), otherwise nil.
function M.recommendedPort(ports, labelOf)
  local identifier = M.sbusConnectorIdentifier(ports, labelOf)
  if identifier == nil then return nil end
  for i = 1, #ports do
    if ports[i].identifier == identifier then
      if maskOf(ports[i]) & ~BUS_FUNCTIONS ~= 0 then return nil end
      return ports[i]
    end
  end
  return nil
end

package.loaded["wfsuite.lib.setup_wizard_bus"] = M
return M
