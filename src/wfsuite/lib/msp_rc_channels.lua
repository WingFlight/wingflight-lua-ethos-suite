-- MSP_RC (cmd 105) and MSP_RX_CHANNELS (cmd 114), read-only: the live RC
-- channels, in us.
--
-- Wire layout verified against wingflight-firmware's src/main/msp/msp.c: both
-- send one U16 per active RC channel and nothing else, so the count is the
-- reply length / 2. MSP_RC is rcInput[], by function (roll, pitch, yaw,
-- throttle, then AUX1...), after the RX map; MSP_RX_CHANNELS is
-- rcRawChannel[], as the receiver sends them, before it.
--
-- decode() fills a caller's table in place (out[1] is channel 0), so a page
-- polling this several times a second does not allocate a table per reply.

if package.loaded["wfsuite.lib.msp_rc_channels"] then
  return package.loaded["wfsuite.lib.msp_rc_channels"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local M = {
  RC_COMMAND = 105,
  RX_CHANNELS_COMMAND = 114,
}

-- Twelve channels: sticks centred, throttle low, AUX low.
local SIMULATOR_RESPONSE = {}
do
  local values = {1500, 1500, 1500, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000}
  for i, v in ipairs(values) do
    SIMULATOR_RESPONSE[2 * i - 1] = v % 256
    SIMULATOR_RESPONSE[2 * i] = math.floor(v / 256)
  end
end

-- Returns the channel count; entries past it are cleared.
function M.decode(buf, out)
  buf.offset = 1
  local count = math.floor(#buf / 2)
  for i = 1, count do
    out[i] = mspcodec.readU16(buf)
  end
  for i = #out, count + 1, -1 do out[i] = nil end
  return count
end

-- command: M.RC_COMMAND or M.RX_CHANNELS_COMMAND. onData(out, count).
function M.buildReadMessage(command, out, onData, onError)
  return {
    command = command,
    processReply = function(_, buf)
      local count = M.decode(buf, out)
      if onData then onData(out, count) end
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

package.loaded["wfsuite.lib.msp_rc_channels"] = M
return M
