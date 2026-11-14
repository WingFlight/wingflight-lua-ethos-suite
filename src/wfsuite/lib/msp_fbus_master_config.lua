-- Schema + message-builders for MSP2_WING_FBUS_MASTER_CONFIG /
-- MSP2_WING_SET_FBUS_MASTER_CONFIG (cmd 0x5F09 read / 0x5F0A write).
--
-- The F.Bus master is the flight controller's F.Bus output: the bus that
-- F.Bus servos and sensors plug into. The read reply is a payload version
-- (U8), eight forwarded-sensor slots (U8 each, 0xFF = empty), and from
-- payload version 2 the port wiring: pin_swap (U8) and inverted (U8).
-- Firmware that only sends version 1 stops after the slots; pin_swap and
-- inverted are then nil, and the write leaves them out, which that firmware
-- expects.
--
-- The write is the eight slots, then the wiring when it was read. It has no
-- version byte. The forwarding slots apply at once; the wiring applies after
-- a restart, because the port is opened at boot.
--
-- pin_swap: F.Bus runs half-duplex on the UART's TX pin. With the swap on it
-- runs on the RX pin, which is the pin a connector labelled SBUS has.

if package.loaded["wfsuite.lib.msp_fbus_master_config"] then
  return package.loaded["wfsuite.lib.msp_fbus_master_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F09
local WRITE_COMMAND = 0x5F0A
local FORWARDED_SLOTS = 8
local EMPTY_SLOT = 0xFF

-- Version 2, no sensors forwarded, pin swap off, inverted on (the firmware's
-- reset defaults, pg/fbus_master.c).
local SIMULATOR_RESPONSE = {2, 255, 255, 255, 255, 255, 255, 255, 255, 0, 1}

local msp_fbus_master_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FORWARDED_SLOTS = FORWARDED_SLOTS,
  EMPTY_SLOT = EMPTY_SLOT,
}

function msp_fbus_master_config.decode(buf)
  buf.offset = 1
  local data = {version = mspcodec.readU8(buf) or 0, forwarded = {}}
  for i = 1, FORWARDED_SLOTS do
    data.forwarded[i] = mspcodec.readU8(buf) or EMPTY_SLOT
  end
  if #buf >= 1 + FORWARDED_SLOTS + 2 then
    data.pin_swap = (mspcodec.readU8(buf) or 0) ~= 0
    data.inverted = (mspcodec.readU8(buf) or 0) ~= 0
  end
  return data
end

function msp_fbus_master_config.encode(data)
  local payload = {}
  data = data or {}
  local forwarded = data.forwarded or {}
  for i = 1, FORWARDED_SLOTS do
    mspcodec.writeU8(payload, forwarded[i] or EMPTY_SLOT)
  end
  if data.pin_swap ~= nil and data.inverted ~= nil then
    mspcodec.writeU8(payload, data.pin_swap and 1 or 0)
    mspcodec.writeU8(payload, data.inverted and 1 or 0)
  end
  return payload
end

function msp_fbus_master_config.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_fbus_master_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

function msp_fbus_master_config.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_fbus_master_config.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_fbus_master_config"] = msp_fbus_master_config
return msp_fbus_master_config
