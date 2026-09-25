-- FC status alerts: which conditions in the decoded system_status /
-- system_config telemetry words (lib/system_status.lua, published by
-- tasks/session.lua) get a dashboard footer banner and/or a callout.
--
-- One table of rules so the dashboard (widgets/dashboard.lua's
-- drawFooterAlert()) and the callouts (tasks/audio_events.lua's
-- announceSystemAlerts()) always agree on what counts as a problem.
--
-- Rule fields:
--   id         unique key (audio edge state is tracked per id)
--   level      LEVEL.CRITICAL (red banner) or LEVEL.WARNING (amber banner)
--   text       banner text, or nil for a callout-only rule
--   active     function(status, config) -> bool; both are always tables
--   setting    events.<setting> switch for the callouts
--   enterSound / exitSound  events/alerts/<file> played when the
--              condition starts / clears (nil = silent)
--   debounce   seconds a change must hold before it is announced, so a
--              flickering link doesn't chatter
--
-- Rules are in priority order: the banner shows the first active one, plus
-- a count of the others. Paint-path helpers below allocate nothing.

if package.loaded["wfsuite.lib.system_alerts"] then
  return package.loaded["wfsuite.lib.system_alerts"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local codec = requireModule("lib/system_status.lua")

local FAILSAFE = codec.FAILSAFE
local NAV_BLOCKED = codec.NAV_BLOCKED
local BATTERY = codec.BATTERY

local LEVEL = {
  CRITICAL = 1,
  WARNING = 2,
}

local EMPTY = {}

local RULES = {
  -- Critical
  {
    id = "rx_backup_active",
    level = LEVEL.CRITICAL,
    text = "@i18n(widgets.dashboard.alert_rx_backup_active)@",
    active = function(s) return s.rxBackupInControl == true end,
    setting = "status_rx_backup",
    enterSound = "rxbackup.wav",
    exitSound = "rxmain.wav",
    debounce = 0.5,
  },
  {
    -- Rarely reaches the radio (telemetry rides the main link), but when a
    -- backup RX keeps telemetry alive it is worth showing. The spoken
    -- "failsafe" already comes from the flight-mode callout.
    id = "failsafe",
    level = LEVEL.CRITICAL,
    text = "@i18n(widgets.dashboard.alert_failsafe)@",
    active = function(s)
      local phase = s.failsafePhase
      return phase ~= nil and phase ~= FAILSAFE.IDLE and phase ~= FAILSAFE.RX_LOSS_RECOVERED
    end,
  },
  {
    -- Spoken by the existing low-voltage callout; banner only.
    id = "battery_critical",
    level = LEVEL.CRITICAL,
    text = "@i18n(widgets.dashboard.alert_battery_critical)@",
    active = function(s) return s.batteryState == BATTERY.CRITICAL end,
  },
  {
    id = "gyro_overflow",
    level = LEVEL.CRITICAL,
    text = "@i18n(widgets.dashboard.alert_gyro_overflow)@",
    active = function(s) return s.gyroOverflow == true end,
    setting = "status_gyro",
    enterSound = "gyrooverflow.wav",
  },

  -- Warnings
  {
    id = "rx_backup_down",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_rx_backup_down)@",
    active = function(s, c) return c.rxBackupConfigured == true and s.rxBackupLinkUp == false end,
    setting = "status_rx_backup",
    enterSound = "rxbackuplost.wav",
    exitSound = "rxbackupok.wav",
    debounce = 1.0,
  },
  {
    -- Spoken by the flight-mode callout ("RTH unavailable"); banner only.
    id = "rth_unavailable",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_rth_unavailable)@",
    active = function(s) return s.navBlocked == NAV_BLOCKED.RTH end,
  },
  {
    id = "loiter_unavailable",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_loiter_unavailable)@",
    active = function(s) return s.navBlocked == NAV_BLOCKED.LOITER end,
  },
  {
    -- gpsCommsLost is latched by tasks/session.lua: the GPS was talking to
    -- the FC earlier this connection and has stopped.
    id = "gps_lost",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_gps_lost)@",
    active = function(s) return s.gpsCommsLost == true end,
    setting = "status_gps",
    enterSound = "gpsfail.wav",
    debounce = 1.0,
  },
  {
    id = "acc_uncalibrated",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_acc_uncalibrated)@",
    active = function(s) return s.accNotCalibrated == true end,
  },
  {
    id = "override",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_override)@",
    active = function(s) return s.overrideActive == true end,
  },
  {
    id = "reboot_required",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_reboot_required)@",
    active = function(_, c) return c.rebootRequired == true end,
  },
  {
    id = "blackbox_full",
    level = LEVEL.WARNING,
    text = "@i18n(widgets.dashboard.alert_blackbox_full)@",
    active = function(_, c) return c.blackboxFull == true end,
    setting = "status_blackbox",
    enterSound = "bbfull.wav",
  },
}

local systemAlerts = {
  LEVEL = LEVEL,
  RULES = RULES,
}

function systemAlerts.isActive(rule, status, config)
  if status == nil then return false end
  return rule.active(status, config or EMPTY) == true
end

-- Highest-priority active banner rule, and how many banner rules are active
-- in total. Returns nil, 0 when there is nothing to show.
function systemAlerts.topBanner(status, config)
  if status == nil then return nil, 0 end
  config = config or EMPTY
  local top, count = nil, 0
  for i = 1, #RULES do
    local rule = RULES[i]
    if rule.text and rule.active(status, config) == true then
      count = count + 1
      if top == nil then top = rule end
    end
  end
  return top, count
end

package.loaded["wfsuite.lib.system_alerts"] = systemAlerts
return systemAlerts
