-- MSP_SERVO_OVERRIDE / MSP_SERVO_OVERRIDE_ALL helpers
-- (cmd 193 indexed write / 196 all-servos write).
--
-- From API 22.14 both take an optional trailing U16 timeout ms: the FC drops
-- the override unless it is re-sent in time. Pages use hold()/holdAll() and
-- release()/releaseAll(), which keep it alive through lib/override_keepalive.lua
-- on firmware that supports it and send it untimed otherwise.

if package.loaded["wfsuite.lib.msp_servo_override"] then
  return package.loaded["wfsuite.lib.msp_servo_override"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")
local bus = requireModule("lib/bus.lua")
local keepalive = requireModule("lib/override_keepalive.lua")

local WRITE_COMMAND = 193
local WRITE_ALL_COMMAND = 196
local OVERRIDE_OFF = 2001
local OVERRIDE_CENTER = 0

local msp_servo_override = {
  WRITE_COMMAND = WRITE_COMMAND,
  WRITE_ALL_COMMAND = WRITE_ALL_COMMAND,
  OVERRIDE_OFF = OVERRIDE_OFF,
  OVERRIDE_CENTER = OVERRIDE_CENTER,
}

local function writeValue(value, timeoutMs)
  local payload = {}
  mspcodec.writeU16(payload, value or OVERRIDE_OFF)
  if timeoutMs then mspcodec.writeU16(payload, timeoutMs) end
  return payload
end

function msp_servo_override.buildWriteMessage(index, value, onWritten, onError, timeoutMs)
  local payload = {tonumber(index) or 0}
  mspcodec.writeU16(payload, value or OVERRIDE_OFF)
  if timeoutMs then mspcodec.writeU16(payload, timeoutMs) end
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

function msp_servo_override.buildWriteAllMessage(value, onWritten, onError, timeoutMs)
  return {
    command = WRITE_ALL_COMMAND,
    payload = writeValue(value, timeoutMs),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

local ALL_KEY = "servo_override_all"
local indexKeys = {}

local function indexKey(index)
  local key = indexKeys[index]
  if not key then
    key = "servo_override_" .. index
    indexKeys[index] = key
  end
  return key
end

function msp_servo_override.hold(index, value)
  if keepalive.supported() then
    keepalive.set(indexKey(index), function()
      return msp_servo_override.buildWriteMessage(index, value, nil, nil, keepalive.TIMEOUT_MS)
    end)
  else
    bus.publish("msp.request", msp_servo_override.buildWriteMessage(index, value))
  end
end

function msp_servo_override.release(index)
  keepalive.clear(indexKey(index))
  bus.publish("msp.request", msp_servo_override.buildWriteMessage(index, OVERRIDE_OFF))
end

function msp_servo_override.holdAll(value)
  if keepalive.supported() then
    keepalive.set(ALL_KEY, function()
      return msp_servo_override.buildWriteAllMessage(value, nil, nil, keepalive.TIMEOUT_MS)
    end)
  else
    bus.publish("msp.request", msp_servo_override.buildWriteAllMessage(value))
  end
end

-- Also stops every per-servo hold: OFF for all servos clears them on the FC.
-- By prefix, since the pages unload this module and its key cache with it.
function msp_servo_override.releaseAll()
  keepalive.clearPrefix("servo_override_")
  bus.publish("msp.request", msp_servo_override.buildWriteAllMessage(OVERRIDE_OFF))
end

package.loaded["wfsuite.lib.msp_servo_override"] = msp_servo_override
return msp_servo_override
