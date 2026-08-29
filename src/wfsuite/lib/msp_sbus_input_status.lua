-- Schema + message-builder for wingflight-firmware's read-only SBUS-In
-- Fallback diagnostics -- MSP2_WING_SBUS_INPUT_STATUS (cmd 0x5F0D / 24333
-- decimal -- see msp_protocol.h). Read-only: there is no SET_ variant.
--
-- Wire layout verified directly against wingflight-firmware's own
-- serializer (src/main/msp/msp.c:1319-1337): U8 payload version (currently
-- always 1, unused) -> U8 enabled (a port has FUNCTION_RX_SBUS_INPUT
-- assigned) -> U8 linkUp (a valid SBUS frame decoded within the last
-- ~50ms) -> U8 activeSource (0 = main RX currently driving the aircraft,
-- 1 = SBUS-in fallback is) -> U8 channelCount -> channelCount x U16
-- channel values, in the same ~880-2012us convention MSP_RC/RX_CHANNELS
-- already use (drivers/rx_sbus_input.c's sbusInputGetChannel()).
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_sbus_input_status"] then
  return package.loaded["wfsuite.lib.msp_sbus_input_status"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F0D

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua): fallback not configured, no channels -- matches
-- what a fresh Ports page with no port assigned this function looks like.
local SIMULATOR_RESPONSE = {
  1, -- payload version
  0, -- enabled = false
  0, -- linkUp = false
  0, -- activeSource = main
  0, -- channelCount = 0
}

local msp_sbus_input_status = {
  READ_COMMAND = READ_COMMAND,
}

function msp_sbus_input_status.decode(buf)
  buf.offset = 1
  mspcodec.readU8(buf) -- payload version, unused for now

  local enabled = mspcodec.readU8(buf) ~= 0
  local linkUp = mspcodec.readU8(buf) ~= 0
  local activeSource = mspcodec.readU8(buf) ~= 0 and "fallback" or "main"
  local channelCount = mspcodec.readU8(buf) or 0

  local channels = {}
  for i = 1, channelCount do
    channels[i] = mspcodec.readU16(buf)
  end

  return {
    enabled = enabled,
    linkUp = linkUp,
    activeSource = activeSource,
    channels = channels,
  }
end

function msp_sbus_input_status.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_sbus_input_status.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

package.loaded["wfsuite.lib.msp_sbus_input_status"] = msp_sbus_input_status
return msp_sbus_input_status
