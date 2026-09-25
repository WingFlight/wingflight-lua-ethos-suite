-- Decoder for the FC's two packed status telemetry sensors:
--
--   system_status  (sensor 120; S.Port 0x5140, CRSF 0x1230) -- live state
--   system_config  (sensor 121; S.Port 0x5141, CRSF 0x1231) -- profiles and config state
--
-- Bit positions mirror wingflight-firmware's src/main/telemetry/status.h and
-- change together with it. This file is the one place on the radio side that
-- knows the layout; everything else reads the decoded tables
-- tasks/session.lua publishes.
--
-- Stateless, like lib/telemetry_sensors.lua.

if package.loaded["wfsuite.lib.system_status"] then
  return package.loaded["wfsuite.lib.system_status"]
end

local systemStatus = {}

-- Enumerations carried in multi-bit fields. Values match the firmware enums
-- named alongside each one.
systemStatus.FAILSAFE = { -- failsafePhase_e
  IDLE = 0,
  RX_LOSS_DETECTED = 1,
  LANDING = 2,
  LANDED = 3,
  RX_LOSS_MONITORING = 4,
  RX_LOSS_RECOVERED = 5,
  GPS_RESCUE = 6,
}

systemStatus.GPS_FIX = { -- telemetryGpsFix_e
  NONE = 0,
  OK = 1,
  HOME = 2, -- fix, and home position captured
}

systemStatus.NAV_BLOCKED = { -- telemetryNavBlocked_e
  NONE = 0,
  LOITER = 1, -- LOITER switched on but it can't fly
  RTH = 2,    -- RTH switched on but it can't fly
}

systemStatus.BATTERY = { -- batteryState_e
  OK = 0,
  WARNING = 1,
  CRITICAL = 2,
  NOT_PRESENT = 3,
  INIT = 4,
}

systemStatus.AUTOTRIM = { -- autoTrimState_e
  IDLE = 0,
  COLLECTING = 1,
  SAVE_PENDING = 2,
}

local LOGIC_CONDITION_COUNT = 4

local function toInt(raw)
  local value = tonumber(raw)
  if value == nil then return nil end
  value = math.floor(value)
  -- S.Port carries the word as a signed int; bit 31 is never set, but mask
  -- anyway so a sign-extended reading can't leak into the fields.
  return value & 0x7FFFFFFF
end

local function flag(value, bit)
  return (value >> bit) & 1 == 1
end

local function field(value, shift, mask)
  return (value >> shift) & mask
end

-- Returns nil for a missing reading, so callers keep their last known state.
function systemStatus.decodeStatus(raw)
  local value = toInt(raw)
  if value == nil then return nil end

  local logic = {}
  for i = 1, LOGIC_CONDITION_COUNT do
    logic[i] = flag(value, 24 + i)
  end

  return {
    raw = value,
    armed = flag(value, 0),
    airborne = flag(value, 1),
    motorsRunning = flag(value, 2),
    rxLinkUp = flag(value, 3),
    rxBackupLinkUp = flag(value, 4),
    rxBackupInControl = flag(value, 5),
    failsafePhase = field(value, 6, 0x7),
    gpsFix = field(value, 9, 0x3),
    gpsHealthy = flag(value, 11),
    navBlocked = field(value, 12, 0x3),
    batteryState = field(value, 14, 0x7),
    controlSaturated = flag(value, 17),
    gyroOverflow = flag(value, 18),
    accNotCalibrated = flag(value, 19),
    overrideActive = flag(value, 20),
    assistHolding = flag(value, 21),
    autoTrim = field(value, 22, 0x3),
    blackboxLogging = flag(value, 24),
    logic = logic, -- logic conditions 1-4
  }
end

-- Profile numbers are 1-based, as the FC's own UI shows them.
function systemStatus.decodeConfig(raw)
  local value = toInt(raw)
  if value == nil then return nil end

  return {
    raw = value,
    pidProfile = field(value, 0, 0x7),
    rateProfile = field(value, 3, 0x7),
    batteryProfile = field(value, 6, 0x7),
    tvProfile = field(value, 9, 0x7),
    configDirty = flag(value, 12),
    saving = flag(value, 13),
    rebootRequired = flag(value, 14),
    beeperOn = flag(value, 15),
    accPresent = flag(value, 16),
    baroPresent = flag(value, 17),
    magPresent = flag(value, 18),
    gpsPresent = flag(value, 19),
    rxBackupConfigured = flag(value, 20),
    blackboxFull = flag(value, 21),
    rpmSourceActive = flag(value, 22),
  }
end

-- Shallow copy for session snapshots (logic[] is the only nested table).
function systemStatus.copy(decoded)
  if decoded == nil then return nil end
  local out = {}
  for key, value in pairs(decoded) do out[key] = value end
  if decoded.logic then
    out.logic = {}
    for i = 1, #decoded.logic do out.logic[i] = decoded.logic[i] end
  end
  return out
end

package.loaded["wfsuite.lib.system_status"] = systemStatus
return systemStatus
