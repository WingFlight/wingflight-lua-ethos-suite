-- MSP2_WING_SELECT_TV_PROFILE / MSP2_WING_COPY_TV_PID_PROFILE helpers
-- (cmd 0x5F10 / 0x5F11, both write-only).
--
-- Thrust Vector profile switching is independent of PID/rate profile
-- switching (lib/msp_select_profile.lua's cmd 210 + RATE_PROFILE_MASK
-- convention) -- it gets its own WING-namespaced commands rather than a
-- third mask bit on the shared command, since cmd 210 is a standard,
-- fixed-format MSP command shared with other tools.

if package.loaded["wfsuite.lib.msp_select_tv_profile"] then
  return package.loaded["wfsuite.lib.msp_select_tv_profile"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local SELECT_COMMAND = 0x5F10
local COPY_COMMAND = 0x5F11

local msp_select_tv_profile = {
  SELECT_COMMAND = SELECT_COMMAND,
  COPY_COMMAND = COPY_COMMAND,
}

function msp_select_tv_profile.buildSelectMessage(profile, onWritten, onError)
  local payload = {}
  mspcodec.writeU8(payload, tonumber(profile or 0) or 0)
  return {
    command = SELECT_COMMAND,
    payload = payload,
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

function msp_select_tv_profile.buildCopyMessage(dstProfile, srcProfile, onWritten, onError)
  local payload = {}
  mspcodec.writeU8(payload, tonumber(dstProfile or 0) or 0)
  mspcodec.writeU8(payload, tonumber(srcProfile or 0) or 0)
  return {
    command = COPY_COMMAND,
    payload = payload,
    isWrite = true,
    processReply = function()
      if onWritten then onWritten() end
    end,
    errorHandler = onError,
    simulatorResponse = {},
  }
end

package.loaded["wfsuite.lib.msp_select_tv_profile"] = msp_select_tv_profile
return msp_select_tv_profile
