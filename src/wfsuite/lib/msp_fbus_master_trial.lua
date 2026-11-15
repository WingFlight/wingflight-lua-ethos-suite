-- Message-builders for MSP2_WING_FBUS_MASTER_TRIAL (cmd 0x5F37): the flight
-- controller's F.Bus output wiring detection.
--
-- The flight controller reopens the F.Bus port with each combination of pin
-- swap and inversion, starting from the one that is set, until a device on
-- the line answers (wingflight-firmware drivers/fbus_master.c,
-- fbusMasterTrialStart()). Each combination gets 1.5 s.
--
-- Request: action U8. 0 polls, 1 starts a run, 2 stops one and puts the
-- wiring back as it was. Every request is answered with the status, 8 bytes
-- (msp/msp.c):
--   state U8, combo index U8, combo count U8, pin_swap U8, inverted U8 (the
--   wiring in use now), valid frames on it U16, port open U8.
--
-- Firmware without the command answers with no payload, or with an MSP error.
-- Both reach onError: "no_payload" for an empty reply, "short_reply" for one
-- that is too short, and `true` for an MSP error (tasks/msp/queue.lua).
-- unsupported(reason) tells those apart from a timeout.
--
-- The flight controller stops a run by itself when it is not polled for 3 s
-- (FBUS_MASTER_TRIAL_WATCHDOG_MS) or the model is armed. On SUCCESS the
-- wiring it found is live and in its configuration in RAM: the page only has
-- to save. A stop after SUCCESS puts the old wiring back, so a page that
-- keeps the found wiring must not send one. A stop in any other state
-- changes nothing.

if package.loaded["wfsuite.lib.msp_fbus_master_trial"] then
  return package.loaded["wfsuite.lib.msp_fbus_master_trial"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local COMMAND = 0x5F37
local ACTION_POLL = 0
local ACTION_START = 1
local ACTION_STOP = 2

-- fbusMasterTrialState_e (drivers/fbus_master.h).
local STATE = {
  IDLE = 0,
  RUNNING = 1,
  SUCCESS = 2,
  FAILED = 3,     -- nothing answered on any wiring; the old one is back
  REJECTED = 4,   -- no F.Bus port open, armed, or an FBUS mux board
}

-- Pin swap on or off, inverted or not.
local COMBINATIONS = 4
local REPLY_BYTES = 8

-- In the simulator a run starts on the first of four wirings, and the first
-- poll finds a device on the port's other pin.
local SIMULATOR_RESPONSE_RUNNING = {STATE.RUNNING, 0, COMBINATIONS, 0, 1, 0, 0, 1}
local SIMULATOR_RESPONSE_SUCCESS = {STATE.SUCCESS, 1, COMBINATIONS, 1, 1, 2, 0, 1}
local SIMULATOR_RESPONSE_IDLE = {STATE.IDLE, 0, COMBINATIONS, 0, 1, 0, 0, 1}

local msp_fbus_master_trial = {
  COMMAND = COMMAND,
  ACTION_POLL = ACTION_POLL,
  ACTION_START = ACTION_START,
  ACTION_STOP = ACTION_STOP,
  STATE = STATE,
  COMBINATIONS = COMBINATIONS,
}

-- nil when the reply is shorter than the status.
function msp_fbus_master_trial.decode(buf)
  if #buf < REPLY_BYTES then return nil end
  buf.offset = 1
  return {
    state = mspcodec.readU8(buf),
    combo_index = mspcodec.readU8(buf),
    combo_count = mspcodec.readU8(buf),
    pin_swap = mspcodec.readU8(buf) ~= 0,
    inverted = mspcodec.readU8(buf) ~= 0,
    frame_delta = mspcodec.readU16(buf),
    port_open = mspcodec.readU8(buf) ~= 0,
  }
end

-- Whether an onError reason means the firmware does not have the command.
function msp_fbus_master_trial.unsupported(reason)
  return reason == "no_payload" or reason == true
end

local function buildMessage(action, simulatorResponse, onData, onError)
  return {
    command = COMMAND,
    payload = {action},
    isWrite = action ~= ACTION_POLL,
    processReply = function(_, buf)
      local data = msp_fbus_master_trial.decode(buf)
      if data == nil then
        if onError then onError(#buf == 0 and "no_payload" or "short_reply") end
        return
      end
      if onData then onData(data) end
    end,
    errorHandler = onError,
    simulatorResponse = simulatorResponse,
  }
end

function msp_fbus_master_trial.buildStartMessage(onData, onError)
  return buildMessage(ACTION_START, SIMULATOR_RESPONSE_RUNNING, onData, onError)
end

function msp_fbus_master_trial.buildPollMessage(onData, onError)
  return buildMessage(ACTION_POLL, SIMULATOR_RESPONSE_SUCCESS, onData, onError)
end

-- Stops a run and puts the wiring back as it was before it.
function msp_fbus_master_trial.buildStopMessage(onData, onError)
  return buildMessage(ACTION_STOP, SIMULATOR_RESPONSE_IDLE, onData, onError)
end

package.loaded["wfsuite.lib.msp_fbus_master_trial"] = msp_fbus_master_trial
return msp_fbus_master_trial
