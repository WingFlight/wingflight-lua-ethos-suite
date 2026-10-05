-- MSP_MOTOR_CONFIG helper (cmd 131 read / 222 write).

if package.loaded["wfsuite.lib.msp_motor_config"] then
  return package.loaded["wfsuite.lib.msp_motor_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 131
local WRITE_COMMAND = 222

-- The wire values, transcribed from the firmware's own enum -- wingflight-firmware
-- src/main/drivers/motor.h:29-43:
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
-- The list this file used to carry had SRXL2, and its numbers happened to match the
-- enum -- but BRUSHED sat on slot 4, which is not a protocol at all (see
-- RESERVED_BRUSHED below), so the list offered a value the firmware reports as not
-- enabled. The names are constants rather than inlined for the same reason: there were
-- four bare `10`s across this file and the two pages that read it, and on this side a
-- bare `10` read as SRXL2 while it was meant as DISABLED -- so the pages' fallback for
-- a field the FC never answered enabled the PWM rows for a protocol that has none.
local DISABLED = 11
local CASTLE = 9
local SRXL2 = 10
local RESERVED_BRUSHED = 4

-- Always offered: 0..3, 5..8, CASTLE and DISABLED.
--
-- NO VERSION GATE HERE, and the reason is this repository's own floor rather than a
-- preference. CASTLE needs MSP API 12.08 and SRXL2 needs 12.10 upstream; this suite
-- refuses to operate below 22.13 (lib/msp_api_version.lua:26, MIN_API_MINOR = 13,
-- EXPECTED_API_MAJOR = 22), so every FC that can reach this page is already far past
-- both floors. A gate here could never refuse anything, and a gate that cannot fire
-- is a second thing to keep true. choicesFor() keeps the apiMinor argument anyway so
-- the shape survives a future floor, and nil -- the handshake not finished -- yields
-- this same list, which is the safe direction.
local BASE_CHOICES = {
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

-- BRUSHED is not a protocol. The firmware kept slot 4 as a placeholder so the numbers
-- after it would not move -- drivers/motor.h:34 still carries the comment
-- "// BRUSHED" on PWM_TYPE_RESERVED -- and checkMotorProtocolEnabled() (motor.c:155-177)
-- has no case for it, so an FC configured with 4 reports the motor output as not
-- enabled.
--
-- It is dropped from the menu outright. Keeping it visible for a pilot who already has
-- 4 stored would need the list rebuilt after the FC's block arrives, and that is not
-- available: app/field_layout.lua's buildSingle() calls addLine() (field_layout.lua
-- :448/:502), so a second call would put a SECOND row on the screen, and there is no
-- re-spec path. Half a mechanism is worse than none, so the parameter that would have
-- carried "what does the FC currently report" is not here.
--
-- WHAT THAT COSTS, stated rather than discovered later: a pilot whose FC sits on the
-- reserved slot opens this page to a row whose value is not in the list. Nothing is
-- corrupted -- app/field_layout.lua's choiceGet() returns the stored value unchanged and
-- encode() writes back what the codec read, so a save with that row untouched commits 4
-- again. Whether Ethos draws such a row blank or snaps it to the first entry is NOT
-- verified here and needs a live check; see the pull request.
--
-- The upstream change this is ported from also added an SRXL2 version gate and dropped
-- SRXL2's absence from the list. Neither half applies: SRXL2 was already in this list,
-- and this suite's API floor is above SRXL2's introduction, so there is nothing to gate.
local function choicesFor(apiMinor)
  -- Built by walking the base list rather than returned whole, so a future
  -- version-filtered protocol has one obvious place to go. The argument is read here
  -- so the signature is not a lie: `apiMinor` is unused on purpose, and this comment
  -- is where that is recorded.
  local _ = apiMinor
  return BASE_CHOICES
end

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
  -- The BASE list, so the fallback for any caller that builds this field without
  -- asking for a filtered list is the subset valid on every FC this suite talks to.
  -- app/pages/esc_motors_throttle.lua passes it explicitly and is the only page that
  -- builds this field.
  motor_pwm_protocol = {choices = BASE_CHOICES},
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
  ON_OFF_CHOICES = ON_OFF_CHOICES,

  -- The Throttle Protocol choices for the FC that answered.
  --
  --   apiMinor -- MSP_API_VERSION's minor, or nil if it is not known yet.
  --
  -- On this side the argument currently changes nothing: the suite's floor is 22.13,
  -- well past every protocol's introduction, so there is no protocol left to gate. The
  -- function is exported instead of the table anyway, because a table is what let the
  -- list drift out of step with the enum in the first place -- and because the pages
  -- must stop spelling DISABLED as a literal. PROTOCOL_CHOICES is deliberately gone: a
  -- caller that reaches for it should not find one.
  protocolChoices = choicesFor,
  BASE_PROTOCOL_CHOICES = BASE_CHOICES,
  DISABLED_PROTOCOL = DISABLED,
  SRXL2_PROTOCOL = SRXL2,
  CASTLE_PROTOCOL = CASTLE,
  RESERVED_BRUSHED_PROTOCOL = RESERVED_BRUSHED,
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
