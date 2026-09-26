-- MSP2_WING_BUILD_ID (0x5F20): which firmware build this is, exactly.
--
-- The hash of the build's parameter manifest, 8 bytes, reported by the
-- firmware's msp/msp_param.c. It names the codec pack (codecs/<id>.lua) that
-- tasks/msp/virtual.lua answers legacy config opcodes with. Wire shape, fixed
-- because it has to be readable before anything else is known:
--   U8 protocol, 8 bytes id, U16 capabilities, U32 manifest size, strings...
-- Capability bit 1 set means the id is real; a build made without its
-- manifest reports zeroes and clears it.

if package.loaded["wfsuite.lib.msp_build_id"] then
  return package.loaded["wfsuite.lib.msp_build_id"]
end

local msp_build_id = {}

msp_build_id.READ_COMMAND = 0x5F20

local CAP_BUILD_ID_VALID = 2

function msp_build_id.decode(buf)
  if not buf or #buf < 11 then return nil end
  local hex = {}
  for i = 2, 9 do
    hex[#hex + 1] = string.format("%02x", buf[i])
  end
  local capabilities = buf[10] + buf[11] * 256
  if math.floor(capabilities / CAP_BUILD_ID_VALID) % 2 ~= 1 then return nil end
  return table.concat(hex)
end

-- onData(id) with the 16-hex-digit id, or nil for a build without one.
function msp_build_id.buildReadMessage(onData, onError)
  return {
    command = msp_build_id.READ_COMMAND,
    processReply = function(_, buf) onData(msp_build_id.decode(buf)) end,
    errorHandler = onError,
    maxRetries = 2,
  }
end

package.loaded["wfsuite.lib.msp_build_id"] = msp_build_id
return msp_build_id
