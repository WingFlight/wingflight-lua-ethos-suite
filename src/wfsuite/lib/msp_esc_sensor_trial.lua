-- Message-builders for MSP2_WING_ESC_SENSOR_TRIAL (cmd 0x5F14): the flight
-- controller's ESC telemetry wiring detection.
--
-- The flight controller tries the half duplex and pin swap combinations on
-- the live ESC telemetry port until frames arrive, starting from the wiring
-- that is set and moving outward (wingflight-firmware sensors/esc_sensor.c,
-- escSensorTrialStart()).
--
-- Request: action U8. 0 polls, 1 starts a run, 2 stops one and puts the
-- wiring back as it was. Every request is answered with the status
-- (msp/msp.c):
--   state U8, combo index U8, half_duplex U8, pin_swap U8, elapsed ms U16,
--   then diagnostics: frames seen U16, combo count U8, port open U8.
-- The first six bytes are the fixed part; the diagnostics were added after
-- them, so they are read only when they are there. A shorter reply is
-- reported as an error.
--
-- The flight controller stops a run by itself when it is not polled for 3 s
-- (ESC_SENSOR_TRIAL_WATCHDOG_MS). On SUCCESS it leaves the wiring it found
-- live, in RAM only: nothing is saved until the page writes
-- lib/msp_esc_sensor_config.lua and saves. A stop after SUCCESS puts the old
-- wiring back. Don't send a stop after REJECTED: no run was started, so the
-- firmware would put back the wiring it kept from an earlier run.

if package.loaded["wfsuite.lib.msp_esc_sensor_trial"] then
  return package.loaded["wfsuite.lib.msp_esc_sensor_trial"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local mspcodec = requireModule("lib/mspcodec.lua")

local COMMAND = 0x5F14
local ACTION_POLL = 0
local ACTION_START = 1
local ACTION_STOP = 2

-- escSensorTrialState_e (sensors/esc_sensor.h).
local STATE = {
  IDLE = 0,
  RUNNING = 1,
  SUCCESS = 2,
  FAILED = 3,
  REJECTED = 4,   -- armed, no ESC telemetry port, or a protocol with no wire to test
}

-- ESC_SENSOR_TRIAL_COMBO_COUNT: half duplex on or off, pin swap on or off.
local COMBINATIONS = 4
local FIXED_BYTES = 6
local DIAGNOSTIC_BYTES = 4

-- In the simulator a run starts on the first of four wirings, and the first
-- poll finds the ESC on half duplex without the pin swap.
local SIMULATOR_RESPONSE_RUNNING = {STATE.RUNNING, 0, 0, 0, 0, 0, 0, 0, COMBINATIONS, 1}
local SIMULATOR_RESPONSE_SUCCESS = {STATE.SUCCESS, 1, 1, 0, 200, 0, 2, 0, COMBINATIONS, 1}
local SIMULATOR_RESPONSE_IDLE = {STATE.IDLE, 0, 0, 0, 0, 0, 0, 0, 0, 1}

local msp_esc_sensor_trial = {
  COMMAND = COMMAND,
  ACTION_POLL = ACTION_POLL,
  ACTION_START = ACTION_START,
  ACTION_STOP = ACTION_STOP,
  STATE = STATE,
  COMBINATIONS = COMBINATIONS,
}

-- nil when the reply is shorter than the fixed part.
function msp_esc_sensor_trial.decode(buf)
  if #buf < FIXED_BYTES then return nil end
  buf.offset = 1
  local data = {
    state = mspcodec.readU8(buf),
    combo_index = mspcodec.readU8(buf),
    half_duplex = mspcodec.readU8(buf),
    pin_swap = mspcodec.readU8(buf),
    elapsed_ms = mspcodec.readU16(buf),
  }
  if #buf >= FIXED_BYTES + DIAGNOSTIC_BYTES then
    data.frame_delta = mspcodec.readU16(buf)
    data.combo_count = mspcodec.readU8(buf)
    data.port_open = mspcodec.readU8(buf) ~= 0
  end
  return data
end

local function buildMessage(action, simulatorResponse, onData, onError)
  return {
    command = COMMAND,
    payload = {action},
    isWrite = action ~= ACTION_POLL,
    processReply = function(_, buf)
      local data = msp_esc_sensor_trial.decode(buf)
      if data == nil then
        if onError then onError("short_reply") end
        return
      end
      if onData then onData(data) end
    end,
    errorHandler = onError,
    simulatorResponse = simulatorResponse,
  }
end

function msp_esc_sensor_trial.buildStartMessage(onData, onError)
  return buildMessage(ACTION_START, SIMULATOR_RESPONSE_RUNNING, onData, onError)
end

function msp_esc_sensor_trial.buildPollMessage(onData, onError)
  return buildMessage(ACTION_POLL, SIMULATOR_RESPONSE_SUCCESS, onData, onError)
end

-- Stops a run and puts the wiring back as it was before it.
function msp_esc_sensor_trial.buildStopMessage(onData, onError)
  return buildMessage(ACTION_STOP, SIMULATOR_RESPONSE_IDLE, onData, onError)
end

package.loaded["wfsuite.lib.msp_esc_sensor_trial"] = msp_esc_sensor_trial
return msp_esc_sensor_trial
