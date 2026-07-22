-- Factory for MSP mixer-input records (cmd 174 read / 171 write).
--
-- The command payload selects a fixed input index (see wingflight-
-- firmware's src/main/pg/mixer.h mixerInput_e enum, confirmed directly,
-- not assumed from the rotorflight-based guess this replaced -- that
-- enum has no "collective" entry at all; index 4 is
-- MIXER_IN_STABILIZED_THROTTLE, not collective, which doesn't exist on
-- a fixed-wing mixer):
--   roll=1, pitch=2, yaw=3, throttle=4.
-- Replies contain only rate/min/max for that selected input; writes send
-- the index followed by the same three values.
--
-- rate/min/max are SIGNED (see msp.c's MSP_GET_MIXER_INPUT/
-- MSP_SET_MIXER_INPUT cases: mixerInputs(i)->rate/min/max are int16_t) --
-- a negative rate means "inverted" (see app/pages/mixer_config.lua's own
-- gain/invert split). The rotorflight-based guess this replaced read/
-- wrote these as unsigned U16, which would have silently corrupted any
-- inverted input to a huge positive number instead of a small negative
-- one -- caught before this factory ever got a real caller (the only
-- callers were the heli swash/tail pages, all deleted; see AGENTS.md's
-- migration notes).

if package.loaded["wfsuite.lib.msp_mixer_input"] then
  return package.loaded["wfsuite.lib.msp_mixer_input"]
end

local mspcodec = assert(loadfile("lib/mspcodec.lua"))()

local READ_COMMAND = 174
local WRITE_COMMAND = 171

local SIMULATOR_RESPONSE = {
  232, 3,   -- rate = 1000
  24, 252,  -- min = -1000
  232, 3,   -- max = 1000
}

local function new(index, rateKey, minKey, maxKey)
  local module = {
    READ_COMMAND = READ_COMMAND,
    WRITE_COMMAND = WRITE_COMMAND,
    INDEX = index,
  }

  function module.decode(buf)
    buf.offset = 1
    return {
      [rateKey] = mspcodec.readS16(buf),
      [minKey] = mspcodec.readS16(buf),
      [maxKey] = mspcodec.readS16(buf),
    }
  end

  function module.encode(data)
    data = data or {}
    local payload = {}
    mspcodec.writeU8(payload, index)
    mspcodec.writeS16(payload, data[rateKey] or 0)
    mspcodec.writeS16(payload, data[minKey] or 0)
    mspcodec.writeS16(payload, data[maxKey] or 0)
    return payload
  end

  function module.buildReadMessage(onData, onError)
    return {
      command = READ_COMMAND,
      payload = {index},
      processReply = function(_, buf)
        onData(module.decode(buf))
      end,
      errorHandler = onError,
      simulatorResponse = SIMULATOR_RESPONSE,
    }
  end

  function module.buildWriteMessage(data, onWritten, onError)
    return {
      command = WRITE_COMMAND,
      payload = module.encode(data),
      isWrite = true,
      processReply = function()
        if onWritten then onWritten() end
      end,
      errorHandler = onError,
      simulatorResponse = {},
    }
  end

  return module
end

local msp_mixer_input = {
  new = new,
  roll = function() return new(1, "rate_stabilized_roll", "min_stabilized_roll", "max_stabilized_roll") end,
  pitch = function() return new(2, "rate_stabilized_pitch", "min_stabilized_pitch", "max_stabilized_pitch") end,
  yaw = function() return new(3, "rate_stabilized_yaw", "min_stabilized_yaw", "max_stabilized_yaw") end,
  throttle = function() return new(4, "rate_stabilized_throttle", "min_stabilized_throttle", "max_stabilized_throttle") end,
}

package.loaded["wfsuite.lib.msp_mixer_input"] = msp_mixer_input
return msp_mixer_input
