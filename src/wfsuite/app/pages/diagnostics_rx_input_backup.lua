-- Tools -> Diagnostics -> Rx Backup page.
--
-- Live link/channel readout for the backup receivers (see app/pages/ports.lua's
-- RX_INPUT_BACKUP/RX_INPUT_BACKUP2 functions and
-- lib/msp_rx_input_backup_status.lua), for bench-testing that a backup
-- satellite is wired/bound correctly and to watch it take over when the main
-- RX link is pulled. One protocol/link line pair per backup; each channel row
-- shows every backup's value, "backup 1 / backup 2". Provider-selectable in
-- firmware (rx_input_backup_provider, rx_input_backup2_provider) -
-- NONE/SBUS/FBUS/FPORT/FPORT2/EXBUS/CRSF - the Protocol line is generic.
--
-- Read-only, so this uses app/diagnostics_common.lua's openReadOnlyPage()
-- helper like diagnostics_fblstatus.lua does. Refreshed faster than that
-- page (0.3s vs 2s) since the whole point here is watching values change
-- live during a bench test -- with the setFieldValue-style change-detection
-- cache from diagnostics_elrs_link.lua so a steady/unchanged value doesn't
-- re-touch the widget every tick (AGENTS.md's GC-churn guardrails).

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local common = requireModule("app/diagnostics_common.lua")
local rxInputBackupStatus = requireModule("lib/msp_rx_input_backup_status.lua")

local PAGE_TITLE = "@i18n(app.modules.diagnostics.name)@ / @i18n(app.modules.rx_input_backup_status.name)@"

local T = {
  protocol = "@i18n(app.modules.rx_input_backup_status.protocol)@",
  link = "@i18n(app.modules.rx_input_backup_status.link)@",
  linkUp = "@i18n(app.modules.rx_input_backup_status.link_up)@",
  linkDown = "@i18n(app.modules.rx_input_backup_status.link_down)@",
  activeSource = "@i18n(app.modules.rx_input_backup_status.active_source)@",
  activeMain = "@i18n(app.modules.rx_input_backup_status.active_main)@",
  activeBackup = "@i18n(app.modules.rx_input_backup_status.active_backup)@",
  notConfigured = "@i18n(app.modules.rx_input_backup_status.not_configured)@",
  channel = "@i18n(app.modules.rx_input_backup_status.channel)@",
  backup = "@i18n(app.modules.rx_input_backup_status.backup)@",
}

-- Backup receivers the firmware can carry (RX_INPUT_BACKUP_COUNT); rows are
-- built for all of them, a backup without a port reads "not configured".
local BACKUP_COUNT = 2

-- Keep in sync with wingflight-firmware's cli/settings.c
-- lookupTableRxInputBackupProvider[] (same order, NONE=0 first).
-- 4 (old FPORT2) detects the speed like FBUS in the firmware, so it is FBUS.
local PROVIDER_NAMES = {
  [0] = "NONE",
  [1] = "SBUS",
  [2] = "FBUS",
  [3] = "FPORT",
  [4] = "FBUS",
  [5] = "EXBUS",
  [6] = "CRSF",
}

local REFRESH_INTERVAL_SECONDS = 0.3

-- Up to 24 channels (a 24-channel F.Bus/F.Port2 backup; its two on/off
-- channels 25-26 aren't shown) -- the channel row
-- count is fixed at page-build time, so pre-build the maximum and only as
-- many rows as the firmware actually reports get real values; the rest stay "-".
local MAX_CHANNELS = 24

local function open(opts)
  common.openReadOnlyPage(opts, PAGE_TITLE, function(ctx)
    local fieldCache = {}

    local function setFieldValue(field, value)
      if not field or fieldCache[field] == value then return end
      fieldCache[field] = value
      common.updateField(field, value)
    end

    local protocolFields, linkFields = {}, {}
    for b = 1, BACKUP_COUNT do
      local prefix = T.backup .. " " .. b .. " "
      protocolFields[b] = common.addValueLine(prefix .. T.protocol, "-")
      linkFields[b] = common.addValueLine(prefix .. T.link, "-")
    end
    local activeField = common.addValueLine(T.activeSource, "-")

    local channelFields = {}
    for i = 1, MAX_CHANNELS do
      channelFields[i] = common.addValueLine(T.channel .. " " .. i, "-")
    end

    local pending = false

    local function applyStatus(data)
      local ports = data.ports or {}
      local anyEnabled = false

      for b = 1, BACKUP_COUNT do
        local port = ports[b]
        if not port or not port.enabled then
          setFieldValue(protocolFields[b], "-")
          setFieldValue(linkFields[b], T.notConfigured)
          if linkFields[b] and linkFields[b].color then
            linkFields[b]:color(WHITE)
          end
        else
          anyEnabled = true
          setFieldValue(protocolFields[b], PROVIDER_NAMES[port.provider] or tostring(port.provider))
          setFieldValue(linkFields[b], port.linkUp and T.linkUp or T.linkDown)
          if linkFields[b] and linkFields[b].color then
            linkFields[b]:color(port.linkUp and GREEN or RED)
          end
        end
      end

      if not anyEnabled then
        setFieldValue(activeField, "-")
      else
        local activeBackup = data.activeBackup
        setFieldValue(activeField, activeBackup and (T.activeBackup .. " " .. activeBackup) or T.activeMain)
        if activeField and activeField.color then
          activeField:color(activeBackup and RED or GREEN)
        end
      end

      -- One row per channel: every backup's value, in failover order. A
      -- backup without a value keeps its position ("- / 1500") so the reader
      -- can tell which receiver a number belongs to.
      for i = 1, MAX_CHANNELS do
        local text = nil
        local any = false
        for b = 1, BACKUP_COUNT do
          local port = ports[b]
          local value = port and port.channels and port.channels[i]
          any = any or value ~= nil
          local rendered = value ~= nil and tostring(value) or "-"
          text = text and (text .. " / " .. rendered) or rendered
        end
        setFieldValue(channelFields[i], any and text or "-")
      end
    end

    local function poll()
      if ctx.isDisposed() or pending then return end
      pending = true
      if ctx.header then ctx.header.setReloadEnabled(false) end
      bus.publish("msp.request", rxInputBackupStatus.buildReadMessage(function(data)
        if not ctx.isDisposed() then applyStatus(data) end
        pending = false
        if ctx.header then ctx.header.setReloadEnabled(true) end
      end, function()
        pending = false
        if ctx.header then ctx.header.setReloadEnabled(true) end
      end))
    end

    if ctx.header then
      ctx.header.setReloadEnabled(true)
    end
    poll()

    local lastPoll = 0

    return {
      onReload = poll,
      wakeup = function()
        local now = os.clock()
        if now - lastPoll < REFRESH_INTERVAL_SECONDS then return end
        lastPoll = now
        poll()
      end,
    }
  end)
end

return {open = open}
