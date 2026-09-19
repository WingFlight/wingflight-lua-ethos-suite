-- Indexed MSP_GET_SERVO_CONFIG / MSP_SET_SERVO_CONFIG helpers
-- (cmd 125 read / 212 write).
--
-- Wingflight 2.3 / MSP API >= 12.09 is the floor for this rebuild, so
-- the indexed API is always available. The original suite still carries a
-- bulk-config fallback for older firmware; this lite rebuild deliberately
-- does not.

if package.loaded["wfsuite.lib.msp_servo_config"] then
  return package.loaded["wfsuite.lib.msp_servo_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 125
local WRITE_COMMAND = 212

local SIMULATOR_RESPONSE = {
  220, 5,   -- mid = 1500
  232, 3,   -- min = 1000
  208, 7,   -- max = 2000
  232, 3,   -- rneg = 1000
  232, 3,   -- rpos = 1000
  100, 0,   -- rate = 100
  0, 0,     -- speed = 0
  0, 0,     -- flags = 0
  0, 0,     -- trim = 0 (API 22.3+)
}

local msp_servo_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  FIELD_META = {
    mid = {min = 50, max = 2250, default = 1500},
    min = {min = -1000, max = 1000, default = -700},
    max = {min = -1000, max = 1000, default = 700},
    rneg = {min = 100, max = 1000, default = 500},
    rpos = {min = 100, max = 1000, default = 500},
    rate = {min = 50, max = 5000, default = 333, suffix = "@i18n(app.unit_hertz)@"},
    speed = {min = 0, max = 60000, default = 0, suffix = "ms"},
    -- The FC limits trim to 20% of the servo scale (larger of rneg/rpos), so at most +-200.
    trim = {min = -200, max = 200, default = 0},
  },
}

local function clampIndex(index)
  index = tonumber(index) or 0
  if index < 0 then return 0 end
  return index
end

function msp_servo_config.decode(buf)
  buf.offset = 1
  local data = {
    mid = mspcodec.readU16(buf),
    min = mspcodec.readS16(buf),
    max = mspcodec.readS16(buf),
    rneg = mspcodec.readU16(buf),
    rpos = mspcodec.readU16(buf),
    rate = mspcodec.readU16(buf),
    speed = mspcodec.readU16(buf),
    flags = mspcodec.readU16(buf),
  }
  -- FC API 22.3+ appends the S16 servo trim; older FCs don't send it, and must not be sent one.
  data.hasTrim = #buf - (buf.offset - 1) >= 2
  data.trim = data.hasTrim and mspcodec.readS16(buf) or 0
  return data
end

function msp_servo_config.encode(index, data)
  data = data or {}
  local payload = {}
  mspcodec.writeU8(payload, clampIndex(index))
  mspcodec.writeU16(payload, data.mid or 1500)
  mspcodec.writeS16(payload, data.min or 0)
  mspcodec.writeS16(payload, data.max or 0)
  mspcodec.writeU16(payload, data.rneg or 0)
  mspcodec.writeU16(payload, data.rpos or 0)
  mspcodec.writeU16(payload, data.rate or 0)
  mspcodec.writeU16(payload, data.speed or 0)
  mspcodec.writeU16(payload, data.flags or 0)
  if data.hasTrim then
    mspcodec.writeS16(payload, data.trim or 0)
  end
  return payload
end

function msp_servo_config.buildReadMessage(index, onData, onError)
  return {
    command = READ_COMMAND,
    payload = {clampIndex(index)},
    processReply = function(_, buf)
      onData(msp_servo_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

function msp_servo_config.buildWriteMessage(index, data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_servo_config.encode(index, data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

function msp_servo_config.forIndex(index)
  return {
    FIELD_META = msp_servo_config.FIELD_META,
    buildReadMessage = function(onData, onError)
      return msp_servo_config.buildReadMessage(index, onData, onError)
    end,
    buildWriteMessage = function(data, onWritten, onError)
      return msp_servo_config.buildWriteMessage(index, data, onWritten, onError)
    end,
  }
end

package.loaded["wfsuite.lib.msp_servo_config"] = msp_servo_config
return msp_servo_config
