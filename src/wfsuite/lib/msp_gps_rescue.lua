-- MSP_GPS_RESCUE helper (cmd 135 read / 225 write).
--
-- gpsRescueConfig_t (PG_GPS_RESCUE). On wingflight-firmware the failsafe GPS
-- Rescue flies the fixed-wing nav controller (msp_gps_nav_config.lua), so the
-- multirotor fields in this struct are unused; the only one the suite edits is
-- gps_rescue_allow_arming_without_fix. It lifts the arming block that
-- fc/core.c raises without a GPS fix while GPS Rescue or a GPS RTH switch is
-- configured.
--
-- Wire order matches src/main/msp/msp.c:
--   angle, initialAltitudeM, descentDistanceM, rescueGroundspeed,
--   throttleMin, throttleMax, throttleHover   U16 x7  (bytes 1-14)
--   sanityChecks, minSats                     U8 x2   (bytes 15-16)
--   ascendRate, descendRate                   U16 x2  (bytes 17-20)
--   allowArmingWithoutFix                     U8      (byte 21)
--   altitudeMode                              U8      (byte 22)
--   minRescueDth                              U16     (bytes 23-24)
--
-- Read-modify-write: decode() keeps the raw reply and buildWriteMessage()
-- sends it back with only the arming byte changed, so the fields the suite
-- does not edit are written back exactly as the FC sent them.

if package.loaded["wfsuite.lib.msp_gps_rescue"] then
  return package.loaded["wfsuite.lib.msp_gps_rescue"]
end

local READ_COMMAND = 135
local WRITE_COMMAND = 225
local ALLOW_ARMING_BYTE = 21
local MIN_BYTES = 22  -- the firmware only reads byte 21 on write when bytes 17-22 are present

local SIMULATOR_RESPONSE = {
  0x20, 0x00, 0x1E, 0x00, 0x14, 0x00, 0xF4, 0x01,  -- angle, initial alt, descent dist, groundspeed
  0x4C, 0x04, 0x08, 0x07, 0x7E, 0x05,              -- throttle min/max/hover
  2, 8,                                            -- sanity checks, min sats
  0x2C, 0x01, 0x96, 0x00,                          -- ascend/descend rate
  0,                                               -- allow arming without fix = OFF
  0,                                               -- altitude mode
  0x1E, 0x00,                                      -- min rescue distance
}

local msp_gps_rescue = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
}

-- Returns {raw = <bytes>, allow_arming_without_fix = 0|1}, or nil when the reply
-- is too short to carry the field (firmware older than MSP API 1.43).
function msp_gps_rescue.decode(buf)
  if #buf < MIN_BYTES then return nil end
  local raw = {}
  for i = 1, #buf do raw[i] = buf[i] end
  return {
    raw = raw,
    allow_arming_without_fix = raw[ALLOW_ARMING_BYTE] ~= 0 and 1 or 0,
  }
end

function msp_gps_rescue.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_gps_rescue.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- `config` must come from decode(): its raw bytes are the payload.
function msp_gps_rescue.buildWriteMessage(config, onWritten, onError)
  local payload = {}
  for i = 1, #config.raw do payload[i] = config.raw[i] end
  payload[ALLOW_ARMING_BYTE] = config.allow_arming_without_fix ~= 0 and 1 or 0
  return {
    command = WRITE_COMMAND,
    payload = payload,
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_gps_rescue"] = msp_gps_rescue
return msp_gps_rescue
