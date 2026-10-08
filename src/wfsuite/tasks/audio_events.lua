-- Lightweight session-driven audio events.
--
-- bus/settingsStore are the instances tasks/background.lua already loaded
-- for itself, passed in as this chunk's args rather than loadfile()'d again
-- here -- see the equivalent note atop tasks/session.lua for why.
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local batteryProfileIndex = requireModule("lib/battery_profile_index.lua")
local systemAlerts = requireModule("lib/system_alerts.lua")
local systemStatusCodec = requireModule("lib/system_status.lua")
local engineType = requireModule("lib/engine_type.lua")

local bus, settingsStore = ...

local audio_events = {}

local settings = nil
local events = nil
local timer = nil
local session = {}
local previous = {}
local initialized = false
local adjWavs = nil

local lastAlertAt = {}
-- Whether the pack has read a real voltage at any point in the current run.
-- The main-power test below needs it: a model whose pack is not measured at
-- all would otherwise look exactly like one whose pack has gone.
local packVoltageSeen = false
-- True between a main-power alert actually playing and the pack coming back,
-- so the recovery is only announced for an episode that was announced lost.
local mainPowerLostActive = false
-- When the pack first read below the warning cell voltage in the current
-- run, for the hold filter in announceVoltage(). nil while the reading is
-- at or above the threshold (or before a first below-threshold reading).
local lowVoltageHoldStart = nil
local craftNameAnnounced = false
local lastSmartfuelAnnounced = nil
-- Whether a fuel reading has been evaluated yet, as opposed to merely being
-- present. See announceSmartfuel().
local fuelEvaluated = false
local lastLowFuelAnnounced = false
local lastLowFuelRepeatAt = 0
local lastLowFuelRepeatCount = 0
local pendingAdjFunction = false
local speakingUntil = 0
local rollingSamples = {}
local timerTriggered = false
local timerLastBeep = nil
local timerPreLastBeep = nil
-- lib/system_alerts.lua rule id -> {reported, pending, since}: the state last
-- announced, and a change waiting out the rule's debounce.
local alertState = {}
-- Setup state (system_status overrideActive): a setup tool such as the
-- Configurator wizard is holding the model and may force a mode (ANGLE,
-- PASSTHROUGH). "Setup" is spoken once instead of the forced mode, and
-- flight-mode callouts pause until it ends. flightModeHeld keeps
-- previous.flightModeFlags at the mode from before, so leaving setup only
-- speaks if the real mode differs.
local SETUP_SETTLE_SECONDS = 1.0
local pendingModeSince = nil
local flightModeHeld = false

local SPEAK_WAV_SECONDS = 0.45
-- Minimum gap between "control limit" callouts while the surfaces keep
-- hitting their limit.
local CONTROL_LIMIT_REPEAT_SECONDS = 3
-- What separates "the pack is gone" from "the pack is low". A disconnected
-- main battery reads as no voltage at all, and the lowest a flight pack is
-- ever taken to is far above this, so nothing a discharge can reach falls
-- inside the window. The same number and the same test the EdgeTX suite uses
-- (lib/audio.lua, MAIN_POWER_LOST_VOLTS / Audio.mainPowerLost), and the same
-- test the Rotorflight Ethos suite gained with its own main-power alert.
local MAIN_POWER_LOST_VOLTS = 1.0
-- How often a main-power alert repeats while the pack stays gone.
local MAIN_POWER_REPEAT_SECONDS = 10
-- The sound each main-power announcement would like the sound packs to gain,
-- with the files every shipped pack already carries as the fallback. The EdgeTX
-- suite does the same, for the same reason: every shipped file names a
-- different event, so a pack without the dedicated word says the nearest one
-- rather than nothing. (pkg, file) in play order; resolved once per
-- announcement by firstResolvedSound().
local MAIN_POWER_LOST_SOUNDS = {
  {"status", "alerts/mainpower.wav"},
  {"status", "alerts/lowbat.wav"},
  {"status", "alerts/lowvoltage.wav"},
}
local MAIN_POWER_OK_SOUNDS = {
  {"status", "alerts/mainpowerok.wav"},
  {"events", "alerts/battery.wav"},
}
local SPEAK_NUM_SECONDS = 0.6

local GOVERNOR_FILES = {
  [0] = "off.wav",
  [1] = "idle.wav",
  [2] = "spoolup.wav",
  [3] = "recovery.wav",
  [4] = "active.wav",
  [5] = "thr-off.wav",
  [6] = "lost-hs.wav",
  [7] = "autorot.wav",
  [8] = "bailout.wav",
  [100] = "disabled.wav",
  [101] = "disarmed.wav",
}

-- Bit -> announcement file, checked top to bottom (first match wins) --
-- same decreasing-importance order wingflight-firmware uses for its own
-- CRSF flight-mode text sensor, so the spoken callout always matches
-- whatever a glance at the radio's telemetry screen would say. Matches
-- this project's own last-known-good tasks/scheduler/events/tasks/
-- telemetry.lua FLIGHT_MODE_PRIORITY exactly.
local FLIGHT_MODE_PRIORITY = {
  {bit = 0, file = "failsafe.wav"},     -- FAILSAFE_MODE_BIT
  {bit = 6, file = "gpsrescue.wav"},    -- GPS_RESCUE_MODE_BIT
  {bit = 13, file = "rth.wav"},         -- RTH_MODE_BIT
  {bit = 12, file = "gpsloiter.wav"},   -- LOITER_MODE_BIT
  {bit = 7, file = "passthrough.wav"},  -- PASSTHROUGH_MODE_BIT
  {bit = 10, file = "manual.wav"},      -- MANUAL_MODE_BIT
  {bit = 5, file = "atthold.wav"},      -- ATTHOLD_MODE_BIT
  {bit = 11, file = "autotrim.wav"},    -- AUTOTRIM_MODE_BIT
  {bit = 1, file = "angle.wav"},        -- ANGLE_MODE_BIT
  {bit = 3, file = "trainer.wav"},      -- TRAINER_MODE_BIT
}

-- Bits deliberately left out of FLIGHT_MODE_PRIORITY:
-- * INFLIGHT (8) is the firmware's "are we flying" latch, not a pilot mode;
--   it never appears in the table, so it can't change the spoken mode (it
--   used to re-trigger a callout of the unchanged mode at takeoff/landing).
-- * TRADITIONAL (14) layers on top of whatever mode is active, so under
--   first-match-wins it was masked by Angle/Trainer/etc. It gets its own
--   on/off edge callout in announceFlightMode() instead.
--
-- A LOITER/RTH switch that is on but can't fly (disarmed, no fix/home) never
-- sets its flight-mode bit. system_status reports it instead
-- (session.navBlocked, see lib/system_status.lua); effectiveFlightMode()
-- folds it back in as the requested mode's bit so the table still picks the
-- right name, and "unavailable" is appended.
local TRADITIONAL_MODE_BIT = 14
local NAV_BLOCKED_MODE_BIT = {
  [1] = 12, -- NAV_BLOCKED.LOITER -> LOITER_MODE_BIT
  [2] = 13, -- NAV_BLOCKED.RTH -> RTH_MODE_BIT
}

-- Arithmetic bit test, not native bitwise operators -- same convention as
-- lib/mspcodec.lua (works unmodified regardless of the Lua version's
-- bitwise-operator support).
local function flightModeHasBit(value, bitIndex)
  return (math.floor(value / (2 ^ bitIndex)) % 2) == 1
end

local function flightModeFile(value)
  value = math.floor(value or 0)
  for i = 1, #FLIGHT_MODE_PRIORITY do
    local m = FLIGHT_MODE_PRIORITY[i]
    if flightModeHasBit(value, m.bit) then return m.file end
  end
  return "normal.wav"
end

local function effectiveFlightMode(flags, navBlocked)
  local value = math.floor(flags)
  local bit = NAV_BLOCKED_MODE_BIT[navBlocked]
  if bit and not flightModeHasBit(value, bit) then value = value + 2 ^ bit end
  return value
end

local SMARTFUEL_THRESHOLDS = {
  [0] = {100, 10},
  [5] = {50, 5},
  [10] = {100, 90, 80, 70, 60, 50, 40, 30, 20, 10},
  [20] = {100, 80, 60, 40, 20, 10},
  [25] = {100, 75, 50, 25, 10},
  [50] = {100, 50, 10},
}

local AUDIO_SESSION_KEYS = {
  "connected",
  "craftName",
  "isArmed",
  "pidProfile",
  "rateProfile",
  "tvProfile",
  "batteryProfile",
  "governorMode",
  "governorState",
  "flightModeFlags",
  "navBlocked",
  "gpsFixType",
  "systemStatus",
  "systemConfig",
  "voltage",
  "batteryConfig",
  "tempEsc",
  "becVoltage",
  "fuelPercent",
  "adjFunction",
  "adjValue",
  "timerLive",
  "timerTarget",
  "smartfuelModelType",
}

local function fileExists(path)
  local file = io.open(path, "r")
  if not file then return false end
  file:close()
  return true
end

local function audioVoice()
  local voice = nil
  if system.getAudioVoice then voice = system.getAudioVoice() end
  voice = tostring(voice or "en/default")
  voice = voice:gsub("SD:", ""):gsub("RADIO:", ""):gsub("AUDIO:", ""):gsub("VOICE[1-4]:", ""):gsub("audio/", "")
  if voice:sub(1, 1) == "/" then voice = voice:sub(2) end
  if voice == "" then voice = "en/default" end
  return voice
end

local function playFile(pkg, file)
  local user = "SCRIPTS:/wfsuite.user/audio/user/" .. pkg .. "/" .. file
  local locale = "SCRIPTS:/wfsuite/audio/" .. audioVoice() .. "/" .. pkg .. "/" .. file
  local fallback = "SCRIPTS:/wfsuite/audio/en/default/" .. pkg .. "/" .. file
  if fileExists(user) then
    system.playFile(user)
  elseif fileExists(locale) then
    system.playFile(locale)
  else
    system.playFile(fallback)
  end
end

local function playCommon(file)
  system.playFile("audio/" .. file)
end

local function playAlert(file)
  playFile("events", "alerts/" .. file)
end

local function playStatus(file)
  playFile("status", "alerts/" .. file)
end

local function playGovernor(file)
  playFile("events", "gov/" .. file)
end

local function playFlightMode(file)
  playFile("events", "mode/" .. file)
end

local function playAdjFunctionToken(file)
  playFile("adjfunctions", file)
end

local function playNumber(value, unit, decimals)
  if system.playNumber then system.playNumber(value, unit, decimals) end
end

-- The path a packaged sound would play from, in the same user -> locale ->
-- en/default order playFile() uses, but returning nil when none of them is
-- there. playFile() itself is left alone: it plays the en/default path for
-- any built-in file, and every one of those ships. This is only for the
-- main-power sounds above, which a pack may not carry yet.
local function resolveSound(pkg, file)
  local user = "SCRIPTS:/wfsuite.user/audio/user/" .. pkg .. "/" .. file
  if fileExists(user) then return user end
  local locale = "SCRIPTS:/wfsuite/audio/" .. audioVoice() .. "/" .. pkg .. "/" .. file
  if fileExists(locale) then return locale end
  local fallback = "SCRIPTS:/wfsuite/audio/en/default/" .. pkg .. "/" .. file
  if fileExists(fallback) then return fallback end
  return nil
end

local function firstResolvedSound(candidates)
  for i = 1, #candidates do
    local path = resolveSound(candidates[i][1], candidates[i][2])
    if path then return path end
  end
  return nil
end

local function haptic()
  if system.playHaptic then system.playHaptic(". . . .") end
end

local function canSpeak(now)
  return now >= speakingUntil
end

local function markSpoken(now, duration)
  local untilAt = now + duration
  if untilAt > speakingUntil then speakingUntil = untilAt end
end

local function updateRollingAverage(key, value, window)
  local state = rollingSamples[key]
  if not state or state.window ~= window then
    state = {values = {}, next = 1, count = 0, sum = 0, window = window}
    rollingSamples[key] = state
  end

  local index = state.next
  if state.count == window then
    state.sum = state.sum - (state.values[index] or 0)
  else
    state.count = state.count + 1
  end
  state.values[index] = value
  state.sum = state.sum + value

  index = index + 1
  if index > window then index = 1 end
  state.next = index

  return state.sum / state.count
end

local function copySnapshot(snapshot)
  for key in pairs(session) do session[key] = nil end
  snapshot = snapshot or {}
  for i = 1, #AUDIO_SESSION_KEYS do
    local key = AUDIO_SESSION_KEYS[i]
    session[key] = snapshot[key]
  end
end

local function onSessionUpdate(snapshot)
  copySnapshot(snapshot)
end

-- The fuel percentage and low-fuel callouts say "battery" for an electric
-- model. Auto is resolved from the battery config by lib/engine_type.lua,
-- the same rule the dashboard's isElectricEngine() uses.
local function isElectricModel()
  return engineType.isElectric(session.batteryConfig, session.smartfuelModelType)
end

-- There is no status/alerts/battery.wav, but events/alerts/battery.wav is the
-- same word, so the electric percentage callout is played from there.
local function playPercentCallout()
  if isElectricModel() then
    playAlert("battery.wav")
  else
    playStatus("fuel.wav")
  end
end

local function playLowCallout()
  if isElectricModel() then
    playStatus("lowbat.wav")
  else
    playStatus("lowfuel.wav")
  end
end

local function onSettingsUpdate(snapshot)
  settings = snapshot or {}
  events = settingsStore.audioEvents(settings)
  timer = settingsStore.audioTimer(settings)
  if events.adj_f ~= true then adjWavs = nil end
end

bus.subscribe("session.update", onSessionUpdate)
bus.subscribe("settings.update", onSettingsUpdate)

local function ensureSettings()
  if not settings then
    settings = settingsStore.load()
  end
  if not events then
    events = settingsStore.audioEvents(settings)
  end
  if not timer then
    timer = settingsStore.audioTimer(settings)
  end
end

-- Plays a pilot-recorded "/audio/<craft name>.wav" once per connect, if
-- one exists -- matches the original suite's own postconnect
-- announceCraftname.lua. Checked every wakeup (not just the first tick
-- after connecting) since session.craftName arrives asynchronously from
-- its own MSP read and may not be known yet on that first tick;
-- craftNameAnnounced latches true the first time both the setting is on
-- and the name is known, so this only ever plays (or gives up trying)
-- once per connection.
local function announceCraftName()
  if craftNameAnnounced then return end
  if not events.craft_name then return end
  local craftName = session.craftName
  if not craftName or craftName == "" then return end

  craftNameAnnounced = true
  local candidates = {
    "/audio/" .. craftName .. ".wav",
    "/audio/" .. craftName:gsub(" ", "_") .. ".wav",
  }
  for i = 1, #candidates do
    if fileExists(candidates[i]) then
      system.playFile(candidates[i])
      return
    end
  end
end

local function announceArmed()
  if not events.armflags then return end
  if previous.isArmed == nil or session.isArmed == nil then return end
  if previous.isArmed == session.isArmed then return end
  playAlert(session.isArmed and "armed.wav" or "disarmed.wav")
end

local function announceProfile(key, enabled, file)
  if not enabled then return end
  local value = tonumber(session[key])
  local last = tonumber(previous[key])
  if value == nil or last == nil or value == last then return end
  playAlert(file)
  playNumber(math.floor(value))
end

local function extractCapacityValue(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then return tonumber(value:match("(%d+)")) end
  if type(value) == "table" then
    if type(value.capacity) == "number" then return value.capacity end
    if type(value.capacity) == "string" then return tonumber(value.capacity:match("(%d+)")) end
    if type(value.name) == "string" then return tonumber(value.name:match("(%d+)")) end
  end
  return nil
end

local function batteryProfileCapacity(profile)
  local profiles = session.batteryConfig and session.batteryConfig.profiles
  if type(profiles) ~= "table" then return nil end
  -- profiles is 0..5 (lib/msp_battery.lua): no profile + 1 retry, which
  -- could only ever answer with a neighbouring pack's capacity.
  local value = profiles[profile]
  value = extractCapacityValue(value)
  if value and value > 0 then return value end
  return nil
end

local function batteryProfileCellCount(profile)
  local config = session.batteryConfig
  if type(config) ~= "table" then return nil end

  local profileCells = config.profileCells
  if type(profileCells) == "table" then
    local cells = profileCells[profile]
    if type(cells) == "table" then
      cells = cells.cellCount
    end
    cells = tonumber(cells)
    if cells and cells > 0 then return cells end
  end

  local cells = tonumber(config.cellCount)
  if cells and cells > 0 then return cells end
  return nil
end

local function announceBatteryProfile()
  if not events.battery_profile then return end
  -- Both already the internal 0-based index (see lib/battery_profile_index.lua).
  local value = batteryProfileIndex.index0(session.batteryProfile)
  local last = batteryProfileIndex.index0(previous.batteryProfile)
  if value == nil or last == nil or value == last then return end

  local capacity = batteryProfileCapacity(value)
  if not capacity then return end
  local cells = batteryProfileCellCount(value)

  playAlert("battery.wav")
  playNumber(math.floor(capacity + 0.5), UNIT_MILLIAMPERE_HOUR)
  -- Ethos has no spoken unit for cells (UNIT_CELLS is not a playNumber
  -- unit), so say the number bare and follow it with our own word.
  if cells then
    playNumber(math.floor(cells + 0.5))
    playAlert("cells.wav")
  end
end

local function announceGovernor()
  if not events.governor then return end
  if session.connected ~= true or session.isArmed ~= true then return end
  local mode = tonumber(session.governorMode)
  if mode == nil or mode == 0 then return end

  local value = tonumber(session.governorState)
  local last = tonumber(previous.governorState)
  if value == nil or last == nil or value == last then return end
  local file = GOVERNOR_FILES[math.floor(value)]
  if file then playGovernor(file) end
end

-- Unlike announceGovernor(), not armed-gated: mode selection (Angle,
-- Trainer, etc.) is useful information before arming too, matching this
-- project's own last-known-good telemetry.lua, which never checked
-- isArmed for this announcement either.
local function inSetup()
  return session.systemStatus ~= nil and session.systemStatus.overrideActive == true
end

local function announceFlightMode()
  flightModeHeld = false
  if not events.flight_mode then return end
  if session.connected ~= true then return end

  local setup = inSetup()
  if setup and previous.setup ~= true then
    pendingModeSince = nil
    playFlightMode("setup.wav")
  end
  if setup then
    flightModeHeld = true
    return
  end

  local value = tonumber(session.flightModeFlags)
  local last = tonumber(previous.flightModeFlags)
  if value == nil or last == nil then return end
  local blocked = tonumber(session.navBlocked) or 0
  local lastBlocked = tonumber(previous.navBlocked) or 0
  if value == last and blocked == lastBlocked then
    pendingModeSince = nil
    return
  end

  -- Disarmed, a mode change may be a setup tool forcing it, and the setup
  -- bit comes in a separate telemetry sensor that can arrive a moment later.
  -- Wait for it before speaking. Armed, setup can't happen: speak at once.
  if session.isArmed ~= true then
    local now = os.clock()
    if pendingModeSince == nil then pendingModeSince = now end
    if now - pendingModeSince < SETUP_SETTLE_SECONDS then
      flightModeHeld = true
      return
    end
  end
  pendingModeSince = nil
  value = effectiveFlightMode(value, blocked)
  last = effectiveFlightMode(last, lastBlocked)

  -- Only speak when what would be said actually changes, not on every flag
  -- change (e.g. AutoTrim toggled underneath a higher-priority mode).
  local file = flightModeFile(value)
  local unavailable = blocked ~= 0
  local spoken = file ~= flightModeFile(last) or unavailable ~= (lastBlocked ~= 0)
  if spoken then
    playFlightMode(file)
    if unavailable then playFlightMode("unavailable.wav") end
  end

  -- Traditional on says "Traditional"; off re-announces the mode now being
  -- flown (unless the main mode changed at the same time, already spoken).
  local traditional = flightModeHasBit(value, TRADITIONAL_MODE_BIT)
  if traditional ~= flightModeHasBit(last, TRADITIONAL_MODE_BIT) then
    if traditional then
      playFlightMode("traditional.wav")
    elseif not spoken then
      playFlightMode(file)
    end
  end
end

-- Not armed-gated, same reasoning as announceFlightMode() -- a pilot
-- waiting for a fix on the bench, before ever arming, is exactly who this
-- is for. Only the acquired/lost edge is announced (session.gpsFixType 0
-- <-> >0), not the further 1 (fix only) -> 2 (fix + home) transition --
-- add a third callout here if the home-capture moment also needs its own
-- cue.
local function announceGpsFix()
  if not events.gps_fix then return end
  if session.connected ~= true then return end

  local value = tonumber(session.gpsFixType)
  local last = tonumber(previous.gpsFixType)
  if value == nil or last == nil or value == last then return end

  if value > 0 and last == 0 then
    playAlert("gpsfix.wav")
  elseif value == 0 and last > 0 then
    playAlert("gpslost.wav")
  end
end

-- FC status callouts from lib/system_alerts.lua's rules. A condition already
-- present when the status first arrives becomes the baseline silently (the
-- dashboard banner shows it); after that each change is announced once it has
-- held for the rule's debounce. Not armed-gated: a backup RX that isn't linked
-- matters most on the bench.
local function announceSystemAlerts(now)
  local status = session.systemStatus
  local config = session.systemConfig
  if status == nil and config == nil then return end
  local rules = systemAlerts.RULES

  for i = 1, #rules do
    local rule = rules[i]
    if rule.enterSound or rule.exitSound then
      local active = systemAlerts.isActive(rule, status, config)
      local state = alertState[rule.id]
      if state == nil then
        alertState[rule.id] = {reported = active, pending = nil, since = now}
      elseif active == state.reported then
        state.pending = nil
      else
        if state.pending ~= active then
          state.pending = active
          state.since = now
        end
        if now - state.since >= (rule.debounce or 0) then
          state.reported = active
          state.pending = nil
          local file
          if active then file = rule.enterSound else file = rule.exitSound end
          if file and events[rule.setting] then playAlert(file) end
        end
      end
    end
  end
end

-- Autotrim: captured (COLLECTING -> SAVE_PENDING), then kept on disarm
-- (SAVE_PENDING -> IDLE while disarmed) or reverted because the switch went
-- off first (SAVE_PENDING -> IDLE while still armed). See wingflight-firmware's
-- flight/autotrim.c.
local function announceAutotrim()
  if not events.status_autotrim then return end
  local status = session.systemStatus
  local value = status and status.autoTrim
  local last = previous.autoTrim
  if value == nil or last == nil or value == last then return end

  local AUTOTRIM = systemStatusCodec.AUTOTRIM
  if value == AUTOTRIM.SAVE_PENDING then
    playAlert("trimcaptured.wav")
  elseif value == AUTOTRIM.IDLE and last == AUTOTRIM.SAVE_PENDING then
    playAlert(status.armed and "trimcancelled.wav" or "trimsaved.wav")
  end
end

-- Stabilized roll/pitch/yaw hit its mixer limit (the FC holds the flag for
-- 500 ms). Rate-limited, and off by default: it can be chatty on 3D models.
local function announceControlLimit(now)
  if not events.status_saturation then return end
  local status = session.systemStatus
  if not (status and status.controlSaturated) then return end
  if lastAlertAt.control_limit and (now - lastAlertAt.control_limit) < CONTROL_LIMIT_REPEAT_SECONDS then return end
  lastAlertAt.control_limit = now
  playAlert("controllimit.wav")
end

local function ensureAdjWavs()
  if not adjWavs then adjWavs = requireModule("tasks/adjfunctions/wavs.lua") end
  return adjWavs
end

local function speakAdjFunction(adjFunction, now)
  local spec = ensureAdjWavs()[adjFunction]
  if type(spec) ~= "string" then return nil end

  local count = 0
  for token in spec:gmatch("[^%s]+") do
    playAdjFunctionToken(token .. ".wav")
    count = count + 1
  end
  if count == 0 then return false end
  markSpoken(now, SPEAK_WAV_SECONDS * count)
  return true
end

local function speakAdjValue(value, now)
  if value == nil then return end
  playNumber(math.floor(value))
  markSpoken(now, SPEAK_NUM_SECONDS)
end

local function announceVoltage(now)
  if not events.voltage then
    lastAlertAt.voltage = nil
    lowVoltageHoldStart = nil
    return
  end
  if session.connected ~= true then
    lowVoltageHoldStart = nil
    return
  end

  local voltage = tonumber(session.voltage)
  local config = session.batteryConfig
  local cellCount = tonumber(config and config.cellCount)
  local warnCell = tonumber(config and config.vbatWarningCell)
  if voltage == nil or cellCount == nil or cellCount <= 0 or warnCell == nil or warnCell <= 0 then
    lowVoltageHoldStart = nil
    return
  end

  -- Below 1V total is implausible for a connected battery (e.g. running on
  -- USB power alone with no pack attached) -- don't let a near-zero noise
  -- reading trigger the low-voltage alarm.
  if voltage < 1 then
    lastAlertAt.voltage = nil
    lowVoltageHoldStart = nil
    return
  end

  local cellVoltage = voltage / cellCount
  if cellVoltage >= warnCell then
    lastAlertAt.voltage = nil
    lowVoltageHoldStart = nil
    return
  end

  -- Voltage sag: a full-throttle climb or punch-out pulls the pack below the
  -- warning cell voltage for a moment and it recovers as soon as the throttle
  -- comes back. The alarm only fires once the reading has stayed below the
  -- threshold for events.voltage_hold seconds, so a transient dip is not
  -- called out. 0 disables the filter and fires on the first low reading.
  local hold = tonumber(events.voltage_hold)
  if hold == nil then hold = 2.0 end
  if not lowVoltageHoldStart then lowVoltageHoldStart = now end
  if (now - lowVoltageHoldStart) < hold then return end

  local repeatInterval = tonumber(events.voltage_repeat_interval) or 10
  if lastAlertAt.voltage and (now - lastAlertAt.voltage) < repeatInterval then return end
  lastAlertAt.voltage = now
  playAlert("lowvoltage.wav")

  -- Speak the reading itself if configured: the pack total at one decimal
  -- (e.g. "22.4 volts") or the average cell at two (e.g. "3.65 volts").
  -- playNumber() takes the value scaled to the decimals it is asked to speak,
  -- so the total is sent as tenths and the cell as hundredths. 0 (default)
  -- keeps the alert-only callout.
  local callout = tonumber(events.voltage_callout) or 0
  if callout == 1 then
    playNumber(math.floor((voltage * 10) + 0.5), UNIT_VOLT, 1)
  elseif callout == 2 then
    playNumber(math.floor((cellVoltage * 100) + 0.5), UNIT_VOLT, 2)
  end
end

-- The main pack is gone while the flight controller stays alive on a BEC or a
-- backup battery. Telemetry can report this at all only because everything
-- else keeps arriving: the receiver and the FC are on the reserve, and the
-- pack voltage is the one sensor with nothing behind it. Nothing else in this
-- file would notice the machine is flying on its backup.
--
-- Three things have to be true together, and the second is what keeps a model
-- whose pack is not measured at all quiet: the pack reads as gone rather than
-- merely low, it has read a real voltage at some point this connection, and a
-- BEC voltage is there beside it -- without one there is no evidence anything
-- is still powered. The same test as the EdgeTX suite's lib/audio.lua
-- (Audio.mainPowerLost); decoding "gone" as total voltage rather than per
-- cell is the other half of why this is its own function and not a branch of
-- announceVoltage(). Not armed-gated, for the same reason it is not there:
-- the pack-seen latch already keeps a bench setup with no pack attached quiet,
-- and a pack that goes while the model sits on the ground is still a fault.
-- The latch's one writer. Called on every wakeup the main-power alert runs --
-- including when the alert itself is switched off, because the latch answers
-- "has this connection ever seen a pack" and an alert enabled later in the same
-- session has to be able to answer that -- and once more from wakeup()'s
-- initialisation branch, which returns before any announcement would run.
-- Without that, a pack already reading when the link came up is never recorded,
-- and a loss the instant after goes unannounced for the whole episode.
local function notePackVoltage()
  local voltage = tonumber(session.voltage)
  if voltage and voltage > MAIN_POWER_LOST_VOLTS then packVoltageSeen = true end
end

local function mainPowerLost()
  local voltage = tonumber(session.voltage)
  if voltage == nil then return false end

  if voltage > MAIN_POWER_LOST_VOLTS then return false end

  if not packVoltageSeen then return false end

  local bec = tonumber(session.becVoltage)
  if bec == nil or bec <= 0 then return false end

  return true
end

-- Announced again every MAIN_POWER_REPEAT_SECONDS while the pack stays gone,
-- and once more when it comes back. The BEC voltage and not the pack's is
-- spoken on the way in: it is the reading that still means something, and it
-- says how much is left of whatever is keeping the receiver alive.
local function announceMainPowerLost(now)
  -- Recorded whether or not the alert is enabled, so switching it on later in
  -- the same session does not lose the episode that had already started.
  notePackVoltage()

  if not events.main_power_lost then
    -- Forget the whole episode, not just its "back" half: an alert switched off
    -- and back on must not wait out a repeat deadline set before it was off.
    mainPowerLostActive = false
    lastAlertAt.main_power = nil
    return
  end
  if session.connected ~= true then return end

  local voltage = tonumber(session.voltage)
  if voltage == nil then return end

  if not mainPowerLost() then
    if voltage > MAIN_POWER_LOST_VOLTS and mainPowerLostActive then
      mainPowerLostActive = false
      lastAlertAt.main_power = nil
      -- The voice goes out whether or not a sound file resolves, the same as
      -- on the way in below.
      local path = firstResolvedSound(MAIN_POWER_OK_SOUNDS)
      if path then system.playFile(path) end
      playNumber(math.floor((voltage * 10) + 0.5), UNIT_VOLTS, 1)
    end
    return
  end

  if lastAlertAt.main_power and (now - lastAlertAt.main_power) < MAIN_POWER_REPEAT_SECONDS then return end
  -- The voice and the haptic go out whether or not a sound file resolves: a
  -- pack that carries none of the loss sounds would otherwise get no alert at
  -- all, and the spoken BEC voltage is the part that says how long is left.
  local path = firstResolvedSound(MAIN_POWER_LOST_SOUNDS)
  lastAlertAt.main_power = now
  mainPowerLostActive = true
  if path then system.playFile(path) end
  local bec = tonumber(session.becVoltage)
  if bec then playNumber(math.floor((bec * 10) + 0.5), UNIT_VOLTS, 1) end
  haptic()
end

local function announceEscTemp(now)
  if not events.temp_esc then return end
  if session.connected ~= true then return end

  local temp = tonumber(session.tempEsc)
  if temp == nil then return end
  local threshold = tonumber(events.escalertvalue) or 90
  local avgTemp = updateRollingAverage("temp_esc", temp, 5)
  if avgTemp < threshold then
    lastAlertAt.temp_esc = nil
    return
  end

  if lastAlertAt.temp_esc and (now - lastAlertAt.temp_esc) < 10 then return end
  lastAlertAt.temp_esc = now
  playAlert("esctemp.wav")
  haptic()
end

local function announceBecRxVoltage(now)
  if not (events.bec_voltage or events.rx_voltage) then return end
  if session.connected ~= true then return end

  local voltage = tonumber(session.becVoltage)
  if voltage == nil then return end
  local avgVoltage = updateRollingAverage("bec_voltage", voltage, 5)

  if events.bec_voltage then
    local threshold = tonumber(events.becalertvalue) or 6.5
    if avgVoltage < threshold then
      if not lastAlertAt.bec_voltage or (now - lastAlertAt.bec_voltage) >= 10 then
        lastAlertAt.bec_voltage = now
        playAlert("becvolt.wav")
        haptic()
      end
    else
      lastAlertAt.bec_voltage = nil
    end
  else
    lastAlertAt.bec_voltage = nil
  end

  if events.rx_voltage then
    local threshold = tonumber(events.rxalertvalue) or 7.4
    if avgVoltage < threshold then
      if not lastAlertAt.rx_voltage or (now - lastAlertAt.rx_voltage) >= 10 then
        lastAlertAt.rx_voltage = now
        playAlert("rxvolt.wav")
        haptic()
      end
    else
      lastAlertAt.rx_voltage = nil
    end
  else
    lastAlertAt.rx_voltage = nil
  end
end

local function smartfuelThresholds()
  local step = tonumber(events.smartfuelcallout) or 10
  return SMARTFUEL_THRESHOLDS[step] or SMARTFUEL_THRESHOLDS[10]
end

local function resetLowFuel()
  lastLowFuelAnnounced = false
  lastLowFuelRepeatAt = 0
  lastLowFuelRepeatCount = 0
end

local function resetFuelAnnouncements()
  lastSmartfuelAnnounced = nil
  fuelEvaluated = false
  resetLowFuel()
end

-- The FC reports no battery yet: batteryState is MAX(voltageState,
-- consumptionState) in wingflight-firmware's sensors/battery.c, and it is
-- INIT from boot and NOT_PRESENT without a pack (USB on the bench) -- exactly
-- when sensors/smartfuel.c resets the charge level to 0. A 0 then means "no
-- battery", not "empty battery". nil (no system_status reading yet) doesn't
-- gate, so the first-reading seed below still covers it.
local function batteryAbsent()
  local status = session.systemStatus
  local state = status and status.batteryState
  return state == systemStatusCodec.BATTERY.NOT_PRESENT
    or state == systemStatusCodec.BATTERY.INIT
end

-- The first reading is only recorded, whatever it says. The threshold loop
-- already treated lastSmartfuelAnnounced == nil as "nothing to compare
-- against yet", but the zero branch ran before that gate, so a first reading
-- of 0 -- what a sensor that has no data yet reports -- went straight to
-- "low fuel" and a haptic. An empty pack reads 0 too, so the first 0 is seeded
-- and every later one goes through: a genuinely empty pack is announced one
-- evaluation later, not silenced. Ported from rotorflight-lua-ethos-suite
-- PR #2406; the batteryAbsent() gate is wingflight-only.
local function announceSmartfuel(now)
  if not events.smartfuel then return end
  if session.connected ~= true then return end

  if batteryAbsent() then
    -- Start over once a pack is detected, so its first reading is seeded.
    resetFuelAnnouncements()
    return
  end

  local value = tonumber(session.fuelPercent)
  if value == nil then return end
  value = math.floor(value + 0.5)

  if not fuelEvaluated then
    fuelEvaluated = true
    lastSmartfuelAnnounced = value
    resetLowFuel()
    return
  end

  if value <= 0 then
    local repeats = tonumber(events.smartfuelrepeats) or 1
    if not lastLowFuelAnnounced then
      playLowCallout()
      if events.smartfuelhaptic then haptic() end
      lastLowFuelAnnounced = true
      lastLowFuelRepeatAt = now
      lastLowFuelRepeatCount = 1
    elseif lastLowFuelRepeatCount < repeats and (now - lastLowFuelRepeatAt) >= 10 then
      playLowCallout()
      if events.smartfuelhaptic then haptic() end
      lastLowFuelRepeatAt = now
      lastLowFuelRepeatCount = lastLowFuelRepeatCount + 1
    end
    return
  end
  resetLowFuel()

  local thresholds = smartfuelThresholds()
  if not thresholds then
    lastSmartfuelAnnounced = value
    return
  end

  for i = 1, #thresholds do
    local threshold = thresholds[i]
    if value <= threshold and lastSmartfuelAnnounced > threshold then
      playPercentCallout()
      playNumber(threshold, UNIT_PERCENT)
      lastSmartfuelAnnounced = threshold
      return
    end
  end
  lastSmartfuelAnnounced = value
end

local function announceAdjustment(now)
  if not (events.adj_f or events.adj_v) then return end
  if session.connected ~= true then return end

  local adjFunction = tonumber(session.adjFunction)
  local adjValue = tonumber(session.adjValue)
  local previousFunction = tonumber(previous.adjFunction)
  local previousValue = tonumber(previous.adjValue)
  if adjFunction == nil or adjValue == nil then return end
  adjFunction = math.floor(adjFunction)
  adjValue = math.floor(adjValue)

  local functionChanged = previousFunction ~= nil and adjFunction ~= previousFunction
  local valueChanged = previousValue ~= nil and adjValue ~= previousValue
  if functionChanged then pendingAdjFunction = true end
  if pendingAdjFunction and (adjFunction == 0 or not events.adj_f) then pendingAdjFunction = false end

  if pendingAdjFunction and adjFunction ~= 0 and events.adj_f then
    if canSpeak(now) then
      if speakAdjFunction(adjFunction, now) then
        speakAdjValue(adjValue, speakingUntil)
      end
      pendingAdjFunction = false
    end
    return
  end

  if valueChanged and adjFunction ~= 0 and events.adj_v and canSpeak(now) then
    speakAdjValue(adjValue, now)
  end
end

local function resetTimerAudio()
  timerTriggered = false
  timerLastBeep = nil
  timerPreLastBeep = nil
end

local function announceTimer()
  if not timer then
    resetTimerAudio()
    return
  end
  if not timer.timeraudioenable then
    resetTimerAudio()
    return
  end
  if session.connected ~= true then
    resetTimerAudio()
    return
  end
  if session.isArmed ~= true then
    resetTimerAudio()
    return
  end

  local targetSeconds = tonumber(session.timerTarget) or 0
  if targetSeconds <= 0 then
    resetTimerAudio()
    return
  end

  local elapsed = tonumber(session.timerLive) or 0
  local elapsedMode = tonumber(timer.elapsedalertmode) or 0

  if timer.prealerton then
    local prePeriod = tonumber(timer.prealertperiod) or 30
    local preAlertStart = targetSeconds - prePeriod
    if elapsed >= preAlertStart and elapsed < targetSeconds then
      local preInterval = tonumber(timer.prealertinterval) or 10
      if not timerPreLastBeep or (elapsed - timerPreLastBeep) >= preInterval then
        playCommon("beep.wav")
        timerPreLastBeep = elapsed
      end
      timerTriggered = false
      timerLastBeep = nil
      return
    end
  else
    timerPreLastBeep = nil
  end

  if elapsed >= targetSeconds then
    if not timerTriggered then
      if elapsedMode == 0 then
        playCommon("beep.wav")
      elseif elapsedMode == 1 then
        playCommon("multibeep.wav")
      elseif elapsedMode == 2 then
        playAlert("elapsed.wav")
      elseif elapsedMode == 3 then
        playStatus("timer.wav")
        playNumber(targetSeconds, UNIT_SECOND)
      end
      timerTriggered = true
      timerLastBeep = elapsed
    end

    if timer.postalerton then
      local postPeriod = tonumber(timer.postalertperiod) or 60
      if elapsed < (targetSeconds + postPeriod) then
        local postInterval = tonumber(timer.postalertinterval) or 10
        if not timerLastBeep or (elapsed - timerLastBeep) >= postInterval then
          playCommon("beep.wav")
          timerLastBeep = elapsed
        end
      end
    end
  else
    timerTriggered = false
    timerLastBeep = nil
  end
end

local function rememberCurrent()
  previous.connected = session.connected
  previous.isArmed = session.isArmed
  previous.pidProfile = session.pidProfile
  previous.rateProfile = session.rateProfile
  previous.tvProfile = session.tvProfile
  previous.batteryProfile = session.batteryProfile
  previous.governorState = session.governorState
  if not flightModeHeld then
    previous.flightModeFlags = session.flightModeFlags
    previous.navBlocked = session.navBlocked
  end
  previous.setup = inSetup()
  previous.gpsFixType = session.gpsFixType
  previous.adjFunction = session.adjFunction
  previous.adjValue = session.adjValue
  previous.autoTrim = session.systemStatus and session.systemStatus.autoTrim
end

local function clearAlertState()
  for key in pairs(alertState) do alertState[key] = nil end
end

function audio_events.wakeup()
  ensureSettings()
  local now = os.clock()
  if session.connected ~= true then
    initialized = false
    craftNameAnnounced = false
    resetFuelAnnouncements()
    adjWavs = nil
    pendingAdjFunction = false
    resetTimerAudio()
    speakingUntil = 0
    packVoltageSeen = false
    mainPowerLostActive = false
    lowVoltageHoldStart = nil
    for key in pairs(rollingSamples) do rollingSamples[key] = nil end
    for key in pairs(lastAlertAt) do lastAlertAt[key] = nil end
    clearAlertState()
    pendingModeSince = nil
    flightModeHeld = false
    rememberCurrent()
    return
  end

  if not initialized then
    initialized = true
    pendingModeSince = nil
    flightModeHeld = false
    -- And the main-power latch, for the same kind of reason: this branch
    -- returns before any announcement runs, so a pack already reading when the
    -- link came up would never be recorded as seen at all.
    notePackVoltage()
    rememberCurrent()
    -- Force a fresh "no fix" baseline here, unlike every other field
    -- rememberCurrent() just captured: a fix acquired while the link was
    -- down (radio off, or GPS locked before this connect) should still be
    -- announced the moment we reconnect -- that's the whole point of
    -- alerting pilots waiting for a fix before arming (see
    -- announceGpsFix()). Without this, a live value of 1 on first connect
    -- would silently become the baseline and never trigger the callout.
    if tonumber(session.gpsFixType) ~= nil then
      previous.gpsFixType = 0
    end
    -- No fuel seed here: announceSmartfuel() seeds the first reading it
    -- evaluates. This one seeded a 0 as a number, which slipped past the old
    -- nil gate and is how a fresh connect came to announce "low fuel".
    return
  end

  announceCraftName()
  announceArmed()
  announceProfile("pidProfile", events.pid_profile, "profile.wav")
  announceProfile("rateProfile", events.rate_profile, "rates.wav")
  announceProfile("tvProfile", events.tv_profile, "tv.wav")
  announceBatteryProfile()
  announceGovernor()
  announceFlightMode()
  announceGpsFix()
  announceSystemAlerts(now)
  announceAutotrim()
  announceControlLimit(now)
  announceVoltage(now)
  announceEscTemp(now)
  announceBecRxVoltage(now)
  announceMainPowerLost(now)
  announceSmartfuel(now)
  announceTimer()
  announceAdjustment(now)
  rememberCurrent()
end

function audio_events.reset()
  initialized = false
  craftNameAnnounced = false
  adjWavs = nil
  for key in pairs(previous) do previous[key] = nil end
  for key in pairs(lastAlertAt) do lastAlertAt[key] = nil end
  clearAlertState()
  resetFuelAnnouncements()
  pendingAdjFunction = false
  resetTimerAudio()
  speakingUntil = 0
  packVoltageSeen = false
  mainPowerLostActive = false
  lowVoltageHoldStart = nil
  for key in pairs(rollingSamples) do rollingSamples[key] = nil end
end

function audio_events.setSettings(snapshot)
  onSettingsUpdate(snapshot)
end

return audio_events
