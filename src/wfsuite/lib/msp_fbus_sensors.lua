-- Message-builder for MSP2_WING_FBUS_SENSORS (cmd 0x5F07, read only): the
-- devices the flight controller's F.Bus master (or S.Port master) has heard
-- from. The Setup Wizard's Servo bus step only needs how many answer on
-- F.Bus, which proves the bus wiring, so decode() counts them and skips the
-- rest of each record.
--
-- The reply is a count (U8), then per device: physical ID (U8), source (U8,
-- 0 = F.Bus, 1 = S.Port), forwarded (U8), packet count (U32), a
-- length-prefixed name, and a count-prefixed list of app IDs (U16 each).

if package.loaded["wfsuite.lib.msp_fbus_sensors"] then
  return package.loaded["wfsuite.lib.msp_fbus_sensors"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F07
local SOURCE_FBUS = 0

local msp_fbus_sensors = {READ_COMMAND = READ_COMMAND}

-- {fbus = devices answering on F.Bus, total = every device listed}. A reply
-- cut short counts the devices that are whole.
function msp_fbus_sensors.decode(buf)
  buf.offset = 1
  local data = {fbus = 0, total = 0}
  if #buf < 1 then return data end
  local count = mspcodec.readU8(buf) or 0
  for _ = 1, count do
    -- Physical ID, source, forwarded, packet count, name length
    if buf.offset + 7 > #buf then break end
    mspcodec.readU8(buf)
    local source = mspcodec.readU8(buf)
    buf.offset = buf.offset + 5
    local nameLength = mspcodec.readU8(buf) or 0
    buf.offset = buf.offset + nameLength
    if buf.offset > #buf then break end
    local appIds = mspcodec.readU8(buf) or 0
    buf.offset = buf.offset + 2 * appIds
    if buf.offset > #buf + 1 then break end
    data.total = data.total + 1
    if source == SOURCE_FBUS then data.fbus = data.fbus + 1 end
  end
  return data
end

function msp_fbus_sensors.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_fbus_sensors.decode(buf))
    end,
    errorHandler = onError,
    -- No devices: the simulator has no bus.
    simulatorResponse = {0},
  }
end

package.loaded["wfsuite.lib.msp_fbus_sensors"] = msp_fbus_sensors
return msp_fbus_sensors
