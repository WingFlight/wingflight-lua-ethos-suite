-- MSP2_WING_SERVO_NAMES (cmd 0x5F3A, read) and MSP2_WING_SET_SERVO_NAME
-- (cmd 0x5F3B, write): a short name per servo ("L AIL", "ELEV"), for
-- reference only. Nothing in flight reads it.
--
-- Wire layout verified against wingflight-firmware's src/main/msp/msp.c
-- (firmware #286):
--   read reply: U8 servo count (24), U8 name length N (8), then N bytes per
--     servo, zero-padded ASCII. Index N is servo S(N+1), as in every servo
--     message. Every servo is sent, in use or not.
--   write: U8 servo (0-based), then the name, 0 to N printable ASCII bytes;
--     none clears it. The FC drops leading and trailing spaces and refuses a
--     name that is too long or has a character outside 0x20-0x7E.
--
-- Firmware without servo names answers both with an error, which reaches
-- the errorHandler: callers treat that as "no names" and show none. The
-- name is saved to EEPROM with the rest of the config (MSP_EEPROM_WRITE).

if package.loaded["wfsuite.lib.msp_servo_names"] then
  return package.loaded["wfsuite.lib.msp_servo_names"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 0x5F3A
local WRITE_COMMAND = 0x5F3B
-- SERVO_NAME_LENGTH in the firmware (pg/servo_name.h)
local NAME_LENGTH = 8

-- 24 servos, the four in use (MSP_STATUS's servo_count fixture) named like
-- the default mix's surfaces, as the Configurator's Virtual FC does. A real
-- flight controller starts with none.
local SIMULATOR_NAMES = {"L AIL", "R AIL", "ELEV", "RUDDER"}
local SIMULATOR_RESPONSE = {24, NAME_LENGTH}
for servo = 1, 24 do
  local name = SIMULATOR_NAMES[servo] or ""
  for i = 1, NAME_LENGTH do
    SIMULATOR_RESPONSE[#SIMULATOR_RESPONSE + 1] = i <= #name and name:byte(i) or 0
  end
end

local M = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  NAME_LENGTH = NAME_LENGTH,
}

-- Cleans a name the way the firmware accepts it: printable ASCII only, no
-- leading or trailing spaces, at most NAME_LENGTH characters.
function M.clean(name)
  if type(name) ~= "string" then name = name and tostring(name) or "" end
  name = name:gsub("[^\32-\126]", "")
  name = name:match("^%s*(.-)%s*$")
  return (name:sub(1, NAME_LENGTH):gsub("%s+$", ""))
end

-- names[i] for servo i (0-based); "" for one without a name. Returns the
-- names and the servo count.
function M.decode(buf)
  buf.offset = 1
  local names = {}
  local count = mspcodec.readU8(buf) or 0
  local length = mspcodec.readU8(buf) or 0
  local chars = {}
  for servo = 0, count - 1 do
    local n = 0
    for _ = 1, length do
      local c = mspcodec.readU8(buf) or 0
      if c ~= 0 then
        n = n + 1
        chars[n] = string.char(c)
      end
    end
    names[servo] = table.concat(chars, "", 1, n)
  end
  return names, count
end

function M.encode(servo, name)
  local payload = {}
  mspcodec.writeU8(payload, servo or 0)
  name = M.clean(name)
  for i = 1, #name do
    mspcodec.writeU8(payload, name:byte(i))
  end
  return payload
end

function M.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      local names, count = M.decode(buf)
      if onData then onData(names, count) end
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

function M.buildWriteMessage(servo, name, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = M.encode(servo, name),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_servo_names"] = M
return M
