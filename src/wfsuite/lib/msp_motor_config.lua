-- MSP_MOTOR_CONFIG helper (cmd 131 read / 222 write).

if package.loaded["wfsuite.lib.msp_motor_config"] then
  return package.loaded["wfsuite.lib.msp_motor_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 131
local WRITE_COMMAND = 222

-- The wire values, transcribed from the firmware's own enum -- wingflight-firmware
-- src/main/drivers/motor.h:
--
--   typedef enum {
--       PWM_TYPE_STANDARD = 0,
--       PWM_TYPE_ONESHOT125,        1
--       PWM_TYPE_ONESHOT42,         2
--       PWM_TYPE_MULTISHOT,         3
--       PWM_TYPE_RESERVED,  // BRUSHED   4   <- a reserved slot, see RESERVED_BRUSHED
--       PWM_TYPE_DSHOT150,          5
--       PWM_TYPE_DSHOT300,          6
--       PWM_TYPE_DSHOT600,          7
--       PWM_TYPE_PROSHOT1000,       8
--       PWM_TYPE_CASTLE_LINK,       9
--       PWM_TYPE_SRXL2,            10
--       PWM_TYPE_DISABLED,         11
--       PWM_TYPE_MAX
--   } motorPwmProtocolTypes_e;
--
-- The values the pages test are named rather than inlined: the pages used to
-- spell "no protocol known" as a bare 10, a number carried over from a list
-- without SRXL2 -- and 10 is SRXL2. (Rotorflight's suite also had DISABLED itself
-- on 10, so selecting it wrote SRXL2; this list already had SRXL2, so only the
-- page fallbacks were wrong here. rotorflight-lua-ethos-suite#2465.)
local DISABLED = 11
local CASTLE = 9
local SRXL2 = 10
local RESERVED_BRUSHED = 4

-- SRXL2 is offered unconditionally. It reached wingflight-firmware at API 22.2
-- (f69ec2928, "Add support for Spektrum SRXL2 ESC", #51), and this suite refuses
-- to operate below 22.13 (lib/msp_api_version.lua), so every FC that can reach
-- this page has it. Rotorflight gates it on its own API 12.10; that gate has no
-- counterpart here. As with DSHOT and CASTLE, the firmware's real gate is a build
-- flag (USE_SRXL2_ESC in checkMotorProtocolEnabled(), drivers/motor.c) that no MSP
-- message reports, so a target built without it refuses SRXL2 at arm time.
--
-- BRUSHED is not a protocol. Slot 4 is PWM_TYPE_RESERVED, kept so the numbers
-- after it would not move, and checkMotorProtocolEnabled() has no case for it, so
-- it is not offered. A FC already storing 4 keeps it: the field returns the
-- stored value unchanged and a save with the row untouched writes 4 back.
local PROTOCOL_CHOICES = {
  {"PWM", 0},
  {"ONESHOT125", 1},
  {"ONESHOT42", 2},
  {"MULTISHOT", 3},
  {"DSHOT150", 5},
  {"DSHOT300", 6},
  {"DSHOT600", 7},
  {"PROSHOT", 8},
  {"CASTLE", CASTLE},
  {"SRXL2", SRXL2},
  {"DISABLED", DISABLED},
}

local ON_OFF_CHOICES = {
  {"@i18n(api.MOTOR_CONFIG.tbl_off)@", 0},
  {"@i18n(api.MOTOR_CONFIG.tbl_on)@", 1},
}

local READ_FIELDS = {
  {"minthrottle", "U16"},
  {"maxthrottle", "U16"},
  {"mincommand", "U16"},
  {"motor_count_blheli", "U8"},
  {"motor_pole_count_blheli", "U8"},
  {"use_dshot_telemetry", "U8"},
  {"motor_pwm_protocol", "U8"},
  {"motor_pwm_rate", "U16"},
  {"use_unsynced_pwm", "U8"},
  {"motor_pole_count_0", "U8"},
  {"motor_pole_count_1", "U8"},
  {"motor_pole_count_2", "U8"},
  {"motor_pole_count_3", "U8"},
  {"motor_rpm_lpf_0", "U8"},
  {"motor_rpm_lpf_1", "U8"},
  {"motor_rpm_lpf_2", "U8"},
  {"motor_rpm_lpf_3", "U8"},
  {"motor1_gear_ratio_0", "U16"},
  {"motor1_gear_ratio_1", "U16"},
  {"motor2_gear_ratio_0", "U16"},
  {"motor2_gear_ratio_1", "U16"},
}

local WRITE_FIELDS = {
  {"minthrottle", "U16"},
  {"maxthrottle", "U16"},
  {"mincommand", "U16"},
  {"motor_pole_count_blheli", "U8"},
  {"use_dshot_telemetry", "U8"},
  {"motor_pwm_protocol", "U8"},
  {"motor_pwm_rate", "U16"},
  {"use_unsynced_pwm", "U8"},
  {"motor_pole_count_0", "U8"},
  {"motor_pole_count_1", "U8"},
  {"motor_pole_count_2", "U8"},
  {"motor_pole_count_3", "U8"},
  {"motor_rpm_lpf_0", "U8"},
  {"motor_rpm_lpf_1", "U8"},
  {"motor_rpm_lpf_2", "U8"},
  {"motor_rpm_lpf_3", "U8"},
  {"motor1_gear_ratio_0", "U16"},
  {"motor1_gear_ratio_1", "U16"},
  {"motor2_gear_ratio_0", "U16"},
  {"motor2_gear_ratio_1", "U16"},
}

local FIELD_META = {
  minthrottle = {min = 50, max = 2250, default = 1070, suffix = "us"},
  maxthrottle = {min = 50, max = 2250, default = 2000, suffix = "us"},
  mincommand = {min = 50, max = 2250, default = 1000, suffix = "us"},
  use_dshot_telemetry = {choices = ON_OFF_CHOICES},
  motor_pwm_protocol = {choices = PROTOCOL_CHOICES},
  motor_pwm_rate = {min = 50, max = 8000, default = 250, suffix = "Hz"},
  use_unsynced_pwm = {choices = ON_OFF_CHOICES},
  motor_pole_count_0 = {min = 2, max = 256, default = 10},
  motor1_gear_ratio_0 = {min = 1, max = 50000, default = 1},
  motor1_gear_ratio_1 = {min = 1, max = 50000, default = 1},
  motor2_gear_ratio_0 = {min = 1, max = 50000, default = 1},
  motor2_gear_ratio_1 = {min = 1, max = 50000, default = 1},
}

local SIMULATOR_RESPONSE = {
  45, 4,
  208, 7,
  232, 3,
  1,
  6,
  0,
  0,
  250, 0,
  1,
  6,
  4,
  2,
  1,
  8,
  7,
  7,
  8,
  20, 0,
  50, 0,
  9, 0,
  30, 0,
}

local msp_motor_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FIELD_META = FIELD_META,
  PROTOCOL_CHOICES = PROTOCOL_CHOICES,
  DISABLED_PROTOCOL = DISABLED,
  CASTLE_PROTOCOL = CASTLE,
  SRXL2_PROTOCOL = SRXL2,
  RESERVED_BRUSHED_PROTOCOL = RESERVED_BRUSHED,
  ON_OFF_CHOICES = ON_OFF_CHOICES,
}

local function readByType(buf, wireType)
  if wireType == "U16" then return mspcodec.readU16(buf) end
  return mspcodec.readU8(buf)
end

local function writeByType(buf, wireType, value)
  if wireType == "U16" then
    mspcodec.writeU16(buf, value or 0)
  else
    mspcodec.writeU8(buf, value or 0)
  end
end

function msp_motor_config.decode(buf)
  buf.offset = 1
  local data = {}
  for i = 1, #READ_FIELDS do
    local name, wireType = READ_FIELDS[i][1], READ_FIELDS[i][2]
    data[name] = readByType(buf, wireType)
  end
  return data
end

function msp_motor_config.encode(data)
  local payload = {}
  data = data or {}
  for i = 1, #WRITE_FIELDS do
    local name, wireType = WRITE_FIELDS[i][1], WRITE_FIELDS[i][2]
    writeByType(payload, wireType, data[name])
  end
  return payload
end

function msp_motor_config.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_motor_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

function msp_motor_config.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_motor_config.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_motor_config"] = msp_motor_config
return msp_motor_config
