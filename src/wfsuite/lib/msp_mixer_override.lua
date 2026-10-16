-- Message-builder for MSP_MIXER_OVERRIDE / MSP_SET_MIXER_OVERRIDE
-- (cmd 190 read / 191 write).
--
-- Write: U8 mixer input index, S16 value (-2500..2500, 1000 = full input;
-- OVERRIDE_OFF releases it), then from API 22.14 an optional U16 timeout ms:
-- the FC drops the override unless it is re-sent in time (msp.c
-- MSP_SET_MIXER_OVERRIDE, mixerSetOverrideTimed()). Pages use hold() and
-- release(), which keep it alive through lib/override_keepalive.lua on
-- firmware that supports it and send it untimed otherwise, the same as
-- lib/msp_servo_override.lua.

if package.loaded["wfsuite.lib.msp_mixer_override"] then
  return package.loaded["wfsuite.lib.msp_mixer_override"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")
local bus = requireModule("lib/bus.lua")
local keepalive = requireModule("lib/override_keepalive.lua")

local WRITE_COMMAND = 191
local OVERRIDE_OFF = 2501
local OVERRIDE_PASSTHROUGH = 2502

local msp_mixer_override = {
  WRITE_COMMAND = WRITE_COMMAND,
  OVERRIDE_OFF = OVERRIDE_OFF,
  OVERRIDE_PASSTHROUGH = OVERRIDE_PASSTHROUGH,
}

function msp_mixer_override.encode(index, value, timeoutMs)
  local payload = {}
  mspcodec.writeU8(payload, index or 0)
  mspcodec.writeS16(payload, value or 0)
  if timeoutMs then mspcodec.writeU16(payload, timeoutMs) end
  return payload
end

function msp_mixer_override.buildWriteMessage(index, value, onWritten, onError, timeoutMs)
  return {
    command = WRITE_COMMAND,
    payload = msp_mixer_override.encode(index, value, timeoutMs),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

local indexKeys = {}

local function indexKey(index)
  local key = indexKeys[index]
  if not key then
    key = "mixer_override_" .. index
    indexKeys[index] = key
  end
  return key
end

function msp_mixer_override.hold(index, value)
  if keepalive.supported() then
    keepalive.set(indexKey(index), function()
      return msp_mixer_override.buildWriteMessage(index, value, nil, nil, keepalive.TIMEOUT_MS)
    end)
  else
    bus.publish("msp.request", msp_mixer_override.buildWriteMessage(index, value))
  end
end

function msp_mixer_override.release(index)
  keepalive.clear(indexKey(index))
  bus.publish("msp.request", msp_mixer_override.buildWriteMessage(index, OVERRIDE_OFF))
end

package.loaded["wfsuite.lib.msp_mixer_override"] = msp_mixer_override
return msp_mixer_override
