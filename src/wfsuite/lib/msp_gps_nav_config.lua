-- MSP2_WING_GPS_NAV_CONFIG helper (cmd 0x5F16 read / 0x5F17 write).
--
-- gpsNavConfig_t (PG_GPS_NAV) -- tuning for the fixed-wing RTH/Loiter nav
-- controller (gps_nav.c), used by BOXRTH/BOXLOITER and, since
-- wingflight-firmware#146, the GPS Rescue failsafe procedure. Had no MSP
-- command at all before -- CLI-only (nav_* settings).
--
-- Wire order matches src/main/msp/msp.c exactly (gpsNavConfig_t's own
-- field order):
--   nav_loiter_radius     U16  (meters)
--   nav_loiter_direction  U8   (0=CW, 1=CCW)
--   nav_rth_altitude      U16  (meters, above the altitude recorded at arm)
--   nav_min_sats          U8
--   nav_max_bank_angle    U8   (degrees)
--   nav_max_pitch_angle   U8   (degrees)
--   nav_bearing_kp        U16  (hundredths of a degree of bank per degree of error)
--   nav_altitude_kp       U16  (hundredths of a degree of pitch per meter of error)

if package.loaded["wfsuite.lib.msp_gps_nav_config"] then
  return package.loaded["wfsuite.lib.msp_gps_nav_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F16
local WRITE_COMMAND = 0x5F17

local SIMULATOR_RESPONSE = {
  0x4B, 0x00,    -- nav_loiter_radius=75
  0,             -- nav_loiter_direction=CW
  0x32, 0x00,    -- nav_rth_altitude=50
  8,             -- nav_min_sats
  25,            -- nav_max_bank_angle
  15,            -- nav_max_pitch_angle
  0xC8, 0x00,    -- nav_bearing_kp=200
  0x64, 0x00,    -- nav_altitude_kp=100
}

local msp_gps_nav_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
}

function msp_gps_nav_config.decode(buf)
  buf.offset = 1
  return {
    nav_loiter_radius = mspcodec.readU16(buf),
    nav_loiter_direction = mspcodec.readU8(buf),
    nav_rth_altitude = mspcodec.readU16(buf),
    nav_min_sats = mspcodec.readU8(buf),
    nav_max_bank_angle = mspcodec.readU8(buf),
    nav_max_pitch_angle = mspcodec.readU8(buf),
    nav_bearing_kp = mspcodec.readU16(buf),
    nav_altitude_kp = mspcodec.readU16(buf),
  }
end

function msp_gps_nav_config.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_gps_nav_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

function msp_gps_nav_config.buildWriteMessage(config, onWritten, onError)
  config = config or {}
  local payload = {}
  mspcodec.writeU16(payload, config.nav_loiter_radius or 75)
  mspcodec.writeU8(payload, config.nav_loiter_direction or 0)
  mspcodec.writeU16(payload, config.nav_rth_altitude or 50)
  mspcodec.writeU8(payload, config.nav_min_sats or 8)
  mspcodec.writeU8(payload, config.nav_max_bank_angle or 25)
  mspcodec.writeU8(payload, config.nav_max_pitch_angle or 15)
  mspcodec.writeU16(payload, config.nav_bearing_kp or 200)
  mspcodec.writeU16(payload, config.nav_altitude_kp or 100)
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

package.loaded["wfsuite.lib.msp_gps_nav_config"] = msp_gps_nav_config
return msp_gps_nav_config
