-- Message-builders for MSP_RX_MAP (cmd 64) and MSP_SET_RX_MAP (cmd 65, only
-- written by the Setup Wizard's Receiver step). Standard MultiWii-lineage command: 8 bytes, each a U8 giving
-- the physical RX channel index for one logical control.
--
-- Field order here is Roll, Pitch, Yaw, Throttle, Aux1-4 -- the plain
-- Betaflight rc_alias_e enum (ROLL, PITCH, YAW, THROTTLE, AUX1, ...) that
-- wingflight's own firmware uses (confirmed against
-- wingflight-configurator's own ChannelAssignment.svelte channelNames list:
-- controlAxisRoll/Pitch/Yaw/Throttle/Aux1/... -- no Collective slot).
-- Deliberately NOT Rotorflight's heli-specific ROLL,PITCH,YAW,COLLECTIVE,
-- THROTTLE,AUX1-3 order (which the very first cut of this file copied
-- verbatim from rotorflight-lua-ethos-suite, since Rotorflight's own
-- decoder is the closest reference this MSP command had): that inserted a
-- Collective field wingflight's RX_MAP payload doesn't have, so every field
-- after Yaw read one byte late -- `throttle` here was actually reading
-- rcmap[AUX1], which on a normal AETR-mapped radio is CH5, not CH3 where
-- throttle actually lives. In practice that made
-- widgets/dashboard/flightmode.lua resolve the arm switch's channel instead
-- of the throttle stick's: pinned high the instant the craft armed,
-- unresponsive to actual throttle input. Caught live via debug prints (see
-- that file's inFlight()) showing exactly that -- a channel value that
-- tracked isArmed one-for-one and never moved with the stick.
--
-- Restores what widgets/dashboard/flightmode.lua's inFlight() needs to read
-- the *radio's own* throttle channel (a local, instant, always-accurate
-- signal) rather than the FC's telemetry-reported throttle_percent -- see
-- that file's own header comment for why. Fetched once per connect by
-- tasks/session.lua, same as lib/msp_handshake.lua's reads.

if package.loaded["wfsuite.lib.msp_rx_map"] then
  return package.loaded["wfsuite.lib.msp_rx_map"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 64

local SIMULATOR_RESPONSE = {
  0, -- aileron (roll)
  1, -- elevator (pitch)
  3, -- rudder (yaw) -- AETR default: physical CH4
  2, -- throttle -- AETR default: physical CH3
  4, -- aux1
  5, -- aux2
  6, -- aux3
  7, -- aux4
}

local msp_rx_map = {
  READ_COMMAND = READ_COMMAND,
}

function msp_rx_map.decode(buf)
  buf.offset = 1
  return {
    aileron = mspcodec.readU8(buf),
    elevator = mspcodec.readU8(buf),
    rudder = mspcodec.readU8(buf),
    throttle = mspcodec.readU8(buf),
    aux1 = mspcodec.readU8(buf),
    aux2 = mspcodec.readU8(buf),
    aux3 = mspcodec.readU8(buf),
    aux4 = mspcodec.readU8(buf),
  }
end

function msp_rx_map.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_rx_map.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- MSP_SET_RX_MAP (cmd 65): RX_MAPPABLE_CHANNEL_COUNT (8) bytes, the receiver
-- channel for roll, pitch, yaw, throttle, aux1-4 in that order (msp.c
-- MSP_SET_RX_MAP). `map` is that list, 1-based, of 0-based channels.
msp_rx_map.WRITE_COMMAND = 65
msp_rx_map.ORDER = {"aileron", "elevator", "rudder", "throttle", "aux1", "aux2", "aux3", "aux4"}

-- The decoded record as a list in wire order, and back.
function msp_rx_map.toList(data)
  local out = {}
  for i, key in ipairs(msp_rx_map.ORDER) do out[i] = data[key] or (i - 1) end
  return out
end

function msp_rx_map.buildWriteMessage(map, onWritten, onError)
  local payload = {}
  for i = 1, #msp_rx_map.ORDER do mspcodec.writeU8(payload, map[i] or (i - 1)) end
  return {
    command = msp_rx_map.WRITE_COMMAND,
    payload = payload,
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_rx_map"] = msp_rx_map
return msp_rx_map
