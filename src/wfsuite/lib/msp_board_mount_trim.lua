-- Codec/message-builders for wingflight-firmware's fine board mount trim:
-- MSP2_WING_BOARD_MOUNT_TRIM / MSP2_WING_SET_BOARD_MOUNT_TRIM
-- (cmd 0x5F03/0x5F04) and MSP2_WING_BOARD_MOUNT_TRIM_AUTO (0x5F05).
--
-- Wire shape verified against wingflight-firmware src/main/msp/msp.c:
-- config read/write is roll/pitch/yaw S16 decidegrees; auto command takes
-- optional action U8 (1 starts sampling) and replies with state U8,
-- rollTrim/pitchTrim S16 decidegrees, stabilityPercent U8. Bounds for the
-- manual config fields come from settings.c's align_board_trim_* CLI vars.

if package.loaded["wfsuite.lib.msp_board_mount_trim"] then
  return package.loaded["wfsuite.lib.msp_board_mount_trim"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F03
local WRITE_COMMAND = 0x5F04
local AUTO_COMMAND = 0x5F05
local ACTION_START = 1

local STATE = {
  IDLE = 0,
  SAMPLING = 1,
  SUCCESS = 2,
  REJECTED_ARMED = 3,
  REJECTED_UNCALIBRATED = 4,
  TIMEOUT = 5,
  OUT_OF_RANGE = 6,
}

local FIELD_META = {
  roll_trim = {min = -3600, max = 3600, default = 0, scale = 10, decimals = 1, suffix = "°"},
  pitch_trim = {min = -3600, max = 3600, default = 0, scale = 10, decimals = 1, suffix = "°"},
  yaw_trim = {min = -3600, max = 3600, default = 0, scale = 10, decimals = 1, suffix = "°"},
}

local SIMULATOR_CONFIG_RESPONSE = {
  0, 0, -- roll_trim
  0, 0, -- pitch_trim
  0, 0, -- yaw_trim
}

local SIMULATOR_AUTO_IDLE_RESPONSE = {
  STATE.IDLE,
  0, 0, -- roll_trim
  0, 0, -- pitch_trim
  0,    -- stability_percent
}

local SIMULATOR_AUTO_START_RESPONSE = {
  STATE.SAMPLING,
  0, 0, -- roll_trim
  0, 0, -- pitch_trim
  0,    -- stability_percent
}

local msp_board_mount_trim = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  AUTO_COMMAND = AUTO_COMMAND,
  ACTION_START = ACTION_START,
  STATE = STATE,
  FIELD_META = FIELD_META,
}

function msp_board_mount_trim.decode(buf)
  buf.offset = 1
  return {
    roll_trim = mspcodec.readS16(buf),
    pitch_trim = mspcodec.readS16(buf),
    yaw_trim = mspcodec.readS16(buf),
  }
end

function msp_board_mount_trim.encode(data)
  local payload = {}
  data = data or {}
  mspcodec.writeS16(payload, data.roll_trim or 0)
  mspcodec.writeS16(payload, data.pitch_trim or 0)
  mspcodec.writeS16(payload, data.yaw_trim or 0)
  return payload
end

function msp_board_mount_trim.decodeAuto(buf)
  buf.offset = 1
  return {
    state = mspcodec.readU8(buf),
    roll_trim = mspcodec.readS16(buf),
    pitch_trim = mspcodec.readS16(buf),
    stability_percent = mspcodec.readU8(buf),
  }
end

function msp_board_mount_trim.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      if onData then onData(msp_board_mount_trim.decode(buf)) end
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_CONFIG_RESPONSE,
  }
end

function msp_board_mount_trim.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_board_mount_trim.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

local function buildAutoMessage(payload, simulatorResponse, onData, onError, isWrite)
  return {
    command = AUTO_COMMAND,
    payload = payload,
    isWrite = isWrite,
    processReply = function(_, buf)
      if onData then onData(msp_board_mount_trim.decodeAuto(buf)) end
    end,
    errorHandler = onError,
    simulatorResponse = simulatorResponse,
  }
end

function msp_board_mount_trim.buildAutoReadMessage(onData, onError)
  return buildAutoMessage(nil, SIMULATOR_AUTO_IDLE_RESPONSE, onData, onError, false)
end

function msp_board_mount_trim.buildAutoStartMessage(onData, onError)
  return buildAutoMessage({ACTION_START}, SIMULATOR_AUTO_START_RESPONSE, onData, onError, true)
end

package.loaded["wfsuite.lib.msp_board_mount_trim"] = msp_board_mount_trim
return msp_board_mount_trim
