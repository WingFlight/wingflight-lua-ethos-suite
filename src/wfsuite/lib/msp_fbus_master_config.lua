-- Schema + message-builder for wingflight-firmware's F.Bus output settings
-- -- MSP2_WING_FBUS_MASTER_CONFIG (cmd 0x5F09 / 24329 decimal -- see
-- msp_protocol.h). Read-only here: the suite only needs the channel
-- setting, to know how many bus servos the F.Bus frame carries.
--
-- Wire layout (src/main/msp/msp.c, MSP2_WING_FBUS_MASTER_CONFIG case):
-- U8 payload version -> 8 x U8 forwarded sensor physical IDs ->
-- [version >= 2 only] U8 channels (0 = 16-channel frame, 1 = 24-channel).
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_fbus_master_config"] then
  return package.loaded["wfsuite.lib.msp_fbus_master_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F09
local FORWARDED_SENSOR_SLOTS = 8

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua): no forwarded sensors, 16-channel frame.
local SIMULATOR_RESPONSE = {
  2, -- payload version
  255, 255, 255, 255, 255, 255, 255, 255, -- forwarded sensors (empty)
  0, -- channels = 16
}

local msp_fbus_master_config = {
  READ_COMMAND = READ_COMMAND,
  CHANNELS_16 = 0,
  CHANNELS_24 = 1,
}

function msp_fbus_master_config.decode(buf)
  buf.offset = 1
  local payloadVersion = mspcodec.readU8(buf) or 0
  for _ = 1, FORWARDED_SENSOR_SLOTS do
    mspcodec.readU8(buf)
  end
  local channels = payloadVersion >= 2 and mspcodec.readU8(buf) or 0

  return {
    channels = channels or 0,
  }
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

package.loaded["wfsuite.lib.msp_fbus_master_config"] = msp_fbus_master_config
return msp_fbus_master_config
