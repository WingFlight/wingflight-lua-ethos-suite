-- MSP_FAILSAFE_CONFIG helper (cmd 75 read / 76 write).
--
-- Read/write the whole failsafe_procedure / stage-2 config as one flat
-- record (unlike MSP_RXFAIL_CONFIG, this isn't per-channel).
--
-- Wire order matches src/main/msp/msp.c exactly:
--   failsafe_delay              U8   (0.1s units)
--   failsafe_off_delay          U8   (0.1s units)
--   failsafe_throttle           U16  (PWM us)
--   failsafe_switch_mode        U8   (0=Stage1, 1=Kill, 2=Stage2)
--   failsafe_throttle_low_delay U16  (0.1s units)
--   failsafe_procedure          U8   (0=Land, 1=Drop, 2=GPS Rescue)
--   failsafe_recovery_delay     U16  (0.1s units) -- appended field, only
--                                     present on firmware that supports it
--                                     (see wingflight-firmware#146); older
--                                     firmware sends the six fields above
--                                     only, so this decodes as nil rather
--                                     than a misleading 0 in that case.

if package.loaded["wfsuite.lib.msp_failsafe_config"] then
  return package.loaded["wfsuite.lib.msp_failsafe_config"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local READ_COMMAND = 75
local WRITE_COMMAND = 76
local FULL_BYTES = 10  -- delay, off_delay, throttle, switch_mode, throttle_low_delay, procedure, recovery_delay

local SIMULATOR_RESPONSE = {
  10, 20,        -- failsafe_delay=10 (1.0s), failsafe_off_delay=20 (2.0s)
  0xE8, 0x03,    -- failsafe_throttle=1000 (low16, high16)
  0,             -- failsafe_switch_mode=STAGE1
  0x0A, 0x00,    -- failsafe_throttle_low_delay=10 (1.0s)
  1,             -- failsafe_procedure=DROP
  0x64, 0x00,    -- failsafe_recovery_delay=100 (10.0s)
}

local msp_failsafe_config = {
  READ_COMMAND = READ_COMMAND,
  WRITE_COMMAND = WRITE_COMMAND,
}

function msp_failsafe_config.decode(buf)
  buf.offset = 1
  local config = {
    failsafe_delay = mspcodec.readU8(buf),
    failsafe_off_delay = mspcodec.readU8(buf),
    failsafe_throttle = mspcodec.readU16(buf),
    failsafe_switch_mode = mspcodec.readU8(buf),
    failsafe_throttle_low_delay = mspcodec.readU16(buf),
    failsafe_procedure = mspcodec.readU8(buf),
  }
  if #buf >= FULL_BYTES then
    config.failsafe_recovery_delay = mspcodec.readU16(buf)
  end
  return config
end

function msp_failsafe_config.buildReadMessage(onData, onError)
  return {
    command = READ_COMMAND,
    processReply = function(_, buf)
      onData(msp_failsafe_config.decode(buf))
    end,
    errorHandler = onError,
    simulatorResponse = SIMULATOR_RESPONSE,
  }
end

-- config.failsafe_recovery_delay may be nil (never read from older firmware,
-- e.g. right after a fresh loadData() against it) -- default it to 0 rather
-- than writing a garbage value back.
function msp_failsafe_config.buildWriteMessage(config, onWritten, onError)
  config = config or {}
  local payload = {}
  mspcodec.writeU8(payload, config.failsafe_delay or 0)
  mspcodec.writeU8(payload, config.failsafe_off_delay or 0)
  mspcodec.writeU16(payload, config.failsafe_throttle or 1000)
  mspcodec.writeU8(payload, config.failsafe_switch_mode or 0)
  mspcodec.writeU16(payload, config.failsafe_throttle_low_delay or 0)
  mspcodec.writeU8(payload, config.failsafe_procedure or 0)
  mspcodec.writeU16(payload, config.failsafe_recovery_delay or 0)
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

package.loaded["wfsuite.lib.msp_failsafe_config"] = msp_failsafe_config
return msp_failsafe_config
