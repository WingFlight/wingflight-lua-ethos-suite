-- Schema + message-builder for wingflight-firmware's read-only backup-RX
-- diagnostics -- MSP2_WING_RX_INPUT_BACKUP_STATUS (cmd 0x5F0D / 24333
-- decimal -- see msp_protocol.h). Read-only: there is no SET_ variant.
--
-- Wire layout verified directly against wingflight-firmware's own
-- serializer (src/main/msp/msp.c, MSP2_WING_RX_INPUT_BACKUP_STATUS case):
-- U8 payload version -> U8 enabled (backup 1's port is assigned)
-- -> [version >= 3 only] U8 mainLinkUp (the main RX is receiving)
-- -> [version >= 2 only] U8 provider (0 = SBUS) -> U8 linkUp (backup 1 has
-- decoded a valid frame within the last ~50ms) -> U8 activeSource (0 = main
-- RX currently driving the aircraft, n = backup n is) -> U8 channelCount ->
-- channelCount x U16 channel values, in the same ~880-2012us convention
-- MSP_RC/RX_CHANNELS already use (drivers/rx_input_backup.c's
-- rxInputBackupPortGetChannel()).
-- [version >= 4 only] U8 portCount, then for each further backup port:
-- U8 enabled -> U8 provider -> U8 linkUp -> U8 channelCount -> channels.
--
-- The `provider` byte was added in payload version 2, once the feature
-- stopped being SBUS-only; a version 1 firmware doesn't send it at all, so
-- this decoder branches on the version byte rather than assuming a fixed
-- offset. Version 4 added the second backup receiver; the top-level fields
-- keep describing backup 1 and `ports` carries every backup.
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_rx_input_backup_status"] then
  return package.loaded["wfsuite.lib.msp_rx_input_backup_status"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F0D

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua): backup not configured, no channels -- matches
-- what a fresh Ports page with no port assigned this function looks like.
local SIMULATOR_RESPONSE = {
  4, -- payload version
  0, -- backup 1 enabled = false
  0, -- mainLinkUp = false
  0, -- backup 1 provider = NONE
  0, -- backup 1 linkUp = false
  0, -- activeSource = main
  0, -- backup 1 channelCount = 0
  2, -- portCount
  0, -- backup 2 enabled = false
  0, -- backup 2 provider = NONE
  0, -- backup 2 linkUp = false
  0, -- backup 2 channelCount = 0
}

local msp_rx_input_backup_status = {
  READ_COMMAND = READ_COMMAND,
}

function msp_rx_input_backup_status.decode(buf)
  buf.offset = 1
  local payloadVersion = mspcodec.readU8(buf)

  local function readChannels()
    local channelCount = mspcodec.readU8(buf) or 0
    local channels = {}
    for i = 1, channelCount do
      channels[i] = mspcodec.readU16(buf)
    end
    return channels
  end

  local first = {}
  first.enabled = mspcodec.readU8(buf) ~= 0
  local mainLinkUp = nil -- unknown before version 3
  if payloadVersion >= 3 then mainLinkUp = mspcodec.readU8(buf) ~= 0 end
  first.provider = payloadVersion >= 2 and mspcodec.readU8(buf) or 0 -- 0 = SBUS
  first.linkUp = mspcodec.readU8(buf) ~= 0
  local activeSourceByte = mspcodec.readU8(buf) or 0
  first.channels = readChannels()

  local ports = {first}
  if payloadVersion >= 4 then
    local portCount = mspcodec.readU8(buf) or 1
    for i = 2, portCount do
      local port = {}
      port.enabled = mspcodec.readU8(buf) ~= 0
      port.provider = mspcodec.readU8(buf) or 0
      port.linkUp = mspcodec.readU8(buf) ~= 0
      port.channels = readChannels()
      ports[i] = port
    end
  end

  -- 1-based number of the backup in control, nil while the main RX is
  local activeBackup = activeSourceByte > 0 and activeSourceByte or nil

  return {
    -- backup 1, as every caller before version 4 knew it
    enabled = first.enabled,
    mainLinkUp = mainLinkUp,
    provider = first.provider,
    linkUp = first.linkUp,
    activeSource = activeBackup and "backup" or "main",
    channels = first.channels,
    -- every backup, in failover order
    activeBackup = activeBackup,
    ports = ports,
  }
end

function msp_rx_input_backup_status.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_rx_input_backup_status.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

package.loaded["wfsuite.lib.msp_rx_input_backup_status"] = msp_rx_input_backup_status
return msp_rx_input_backup_status
