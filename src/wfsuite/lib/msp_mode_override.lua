-- Schema + message-builders for wingflight-firmware's temporary mode
-- override: MSP2_WING_MODE_OVERRIDE (cmd 0x5F1A, read) and
-- MSP2_WING_SET_MODE_OVERRIDE (cmd 0x5F1B, write), both new in MSP API
-- 22.14. An FC without them answers with an MSP error (errorHandler reason
-- true), which means "needs newer firmware".
--
-- The override forces modes on in FC RAM for bench setup (SETUP so the
-- sticks drive the surfaces raw, ANGLE for a gyro check). It is never part
-- of a parameter group, so an EEPROM write cannot save it, it blocks arming
-- while active, and it lapses unless the client re-sends it before its
-- timeout. Use hold()/release() below rather than sending it once: they
-- keep it alive through lib/override_keepalive.lua, so a radio that turns off
-- or a link that drops lets it lapse.
--
-- Wire layout verified against wingflight-firmware's own serializer
-- (src/main/msp/msp.c, MSP2_WING_MODE_OVERRIDE / MSP2_WING_SET_MODE_OVERRIDE):
--   write: U16 timeout ms (FC clamps to 500-30000), U8 count,
--          count x U8 permanent box id. Replaces the whole override.
--          Timeout 0 clears it; count 0 holds the setup state (a setup tool
--          in charge, arming blocked, radios show SETUP) with no mode forced. Refused while armed, for more than 4 modes, or for a
--          mode other than ANGLE, ATT HOLD, PASSTHROUGH or MANUAL.
--   read:  U16 ms left before it lapses, U8 count, count x U8 permanent box id.
--
-- Self-caches via package.loaded (same mechanism lib/bus.lua uses).
if package.loaded["wfsuite.lib.msp_mode_override"] then
  return package.loaded["wfsuite.lib.msp_mode_override"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")
local bus = requireModule("lib/bus.lua")
local keepalive = requireModule("lib/override_keepalive.lua")

local READ_COMMAND = 0x5F1A
local WRITE_COMMAND = 0x5F1B

local DEFAULT_TIMEOUT_MS = keepalive.TIMEOUT_MS
local HOLD_KEY = "mode_override"

local msp_mode_override = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
  -- Permanent box ids (src/main/msp/msp_box.c) of the modes the FC lets
  -- you force.
  BOX_ANGLE = 1,
  BOX_ATTHOLD = 6,
  BOX_PASSTHROUGH = 12,
  BOX_MANUAL = 59,
  DEFAULT_TIMEOUT_MS = DEFAULT_TIMEOUT_MS,
}

local EMPTY = {}

function msp_mode_override.encode(ids, timeoutMs)
  ids = ids or EMPTY
  local payload = {}
  mspcodec.writeU16(payload, timeoutMs or DEFAULT_TIMEOUT_MS)
  mspcodec.writeU8(payload, #ids)
  for i = 1, #ids do
    mspcodec.writeU8(payload, ids[i])
  end
  return payload
end

function msp_mode_override.decode(buf)
  buf.offset = 1
  local data = {remainingMs = mspcodec.readU16(buf) or 0, ids = {}}
  local count = mspcodec.readU8(buf) or 0
  for i = 1, count do
    data.ids[i] = mspcodec.readU8(buf)
  end
  return data
end

function msp_mode_override.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      if onData then onData(msp_mode_override.decode(buf)) end
    end,
    errorHandler = onError,
    simulatorResponse = {0, 0, 0},
  }
end

-- onError(reason): reason true is the FC refusing (old firmware, armed, or a
-- mode it won't force); anything else is the link.
function msp_mode_override.buildWriteMessage(ids, timeoutMs, onWritten, onError)
  return {
    command = WRITE_COMMAND,
    payload = msp_mode_override.encode(ids, timeoutMs),
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

-- Keeps a set of modes forced while a page needs them:
--
--   modeOverride.hold({}, onRefused)                         -- setup state only
--   modeOverride.hold({modeOverride.BOX_PASSTHROUGH}, onRefused)
--   modeOverride.release()                                   -- page closes (always)
--
-- Returns false without sending on firmware older than API 22.14. Re-sent
-- by lib/override_keepalive.lua until release(). onRefused(reason) runs once
-- if the FC refuses (reason true: armed, or a mode it won't force); the hold
-- then stops. Link errors are left to the next refresh.
function msp_mode_override.hold(ids, onRefused)
  if not keepalive.supported() then return false end
  local function onError(reason)
    if reason ~= true or not keepalive.isActive(HOLD_KEY) then return end
    keepalive.clear(HOLD_KEY)
    if onRefused then onRefused(reason) end
  end
  keepalive.set(HOLD_KEY, function()
    return msp_mode_override.buildWriteMessage(ids, DEFAULT_TIMEOUT_MS, nil, onError)
  end)
  return true
end

function msp_mode_override.release()
  if not keepalive.isActive(HOLD_KEY) then return end
  keepalive.clear(HOLD_KEY)
  bus.publish("msp.request", msp_mode_override.buildWriteMessage(EMPTY, 0))
end

function msp_mode_override.isHeld()
  return keepalive.isActive(HOLD_KEY)
end

package.loaded["wfsuite.lib.msp_mode_override"] = msp_mode_override
return msp_mode_override
