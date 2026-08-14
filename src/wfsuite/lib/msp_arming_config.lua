-- Schema + message-builders for the MSP_ARMING_CONFIG / MSP_SET_ARMING_CONFIG
-- command pair (cmd 61 read / 62 write).
--
-- Field order/types verified directly against wingflight-firmware's own
-- wire serializer (src/main/msp/msp.c's MSP_ARMING_CONFIG/
-- MSP_SET_ARMING_CONFIG cases: armingConfig()->auto_disarm_delay (U8)
-- then armingConfig()->wiggle_flags (U32), unconditionally, no version
-- gating). Did not exist anywhere in this rebuild before -- wingflight's
-- own pre-rewrite suite had it (tasks/scheduler/msp/api/ARMING_CONFIG.lua),
-- but only ever exposed a single "wiggle when armed and ready" checkbox
-- (bit 1). Current wingflight-firmware (src/main/pg/arming.h's wiggle_e
-- enum) supports four independent triggers -- WIGGLE_READY=1,
-- WIGGLE_ARMED=2, WIGGLE_ERROR=3, WIGGLE_FATAL=4, each a bit position in
-- `wiggle_flags` (src/main/cli/settings.c's wiggle_enable_* CLI vars
-- confirm the bit-per-trigger mapping; src/main/pg/arming.c's own default
-- is BIT(WIGGLE_READY) only, matching this file's own SIMULATOR_RESPONSE)
-- -- app/pages/configuration.lua exposes all four now, not just the one
-- the pre-rewrite suite did.
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses) --
-- app/pages/configuration.lua reloads fresh via loadfile() on every open.
if package.loaded["wfsuite.lib.msp_arming_config"] then
  return package.loaded["wfsuite.lib.msp_arming_config"]
end

local requireModule = assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 61
local WRITE_COMMAND = 62

-- Bit positions within wiggle_flags -- matches wingflight-firmware's own
-- wiggle_e enum exactly (src/main/pg/arming.h). Bit 0 (WIGGLE_OFF) is not
-- a real trigger, just the enum's zero value -- no field uses it.
local WIGGLE_BIT_READY = 1
local WIGGLE_BIT_ARMED = 2
local WIGGLE_BIT_ERROR = 3
local WIGGLE_BIT_FATAL = 4

-- Fixture reply used automatically when running in the Ethos simulator
-- (see tasks/msp/queue.lua) -- auto_disarm_delay=5s, wiggle_flags=2
-- (BIT(WIGGLE_READY) only, matching wingflight-firmware's own
-- pgResetFn default).
local SIMULATOR_RESPONSE = {
  5,       -- auto_disarm_delay
  2, 0, 0, 0, -- wiggle_flags (U32 LE)
}

local msp_arming_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  WIGGLE_BIT_READY = WIGGLE_BIT_READY,
  WIGGLE_BIT_ARMED = WIGGLE_BIT_ARMED,
  WIGGLE_BIT_ERROR = WIGGLE_BIT_ERROR,
  WIGGLE_BIT_FATAL = WIGGLE_BIT_FATAL,
}

function msp_arming_config.decode(buf)
  buf.offset = 1
  return {
    auto_disarm_delay = mspcodec.readU8(buf),
    wiggle_flags = mspcodec.readU32(buf),
  }
end

function msp_arming_config.encode(data)
  local payload = {}
  mspcodec.writeU8(payload, data.auto_disarm_delay or 0)
  mspcodec.writeU32(payload, data.wiggle_flags or 0)
  return payload
end

-- Builds a ready-to-publish message for lib/bus.lua's "msp.request" topic.
-- `onData(data)` is called with the decoded field table once the reply
-- arrives; `onError(reason)` (optional) on failure.
function msp_arming_config.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_arming_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- Builds a ready-to-publish write message. `onWritten()` (optional) is
-- called once the FC acknowledges the write; `onError(reason)` on failure.
function msp_arming_config.buildWriteMessage(data, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_arming_config.encode(data),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_arming_config"] = msp_arming_config
return msp_arming_config
