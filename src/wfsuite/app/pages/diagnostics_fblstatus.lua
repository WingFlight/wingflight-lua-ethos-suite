-- Tools -> Diagnostics -> FBL Status page.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local common = requireModule("app/diagnostics_common.lua")
local mspStatus = requireModule("lib/msp_status.lua")
local dataflashSummary = requireModule("lib/msp_dataflash_summary.lua")
local armingFlags = requireModule("lib/arming_flags.lua")

local PAGE_TITLE = "@i18n(app.modules.diagnostics.name)@ / @i18n(app.modules.fblstatus.name)@"

-- Heading above the per-reason rows, which are indented under it.
local ARMING_DETAIL_HEADING = "@i18n(app.modules.fblstatus.arming_flags_active_list)@"
local ARMING_DETAIL_INDENT = 12

local function percentTenths(value)
  if value == nil then return "-" end
  return string.format("%.1f%%", (tonumber(value) or 0) / 10)
end

local function dataflashText(summary)
  if not summary then return "-" end
  if not armingFlags.hasBit(summary.flags, 1) then return "@i18n(app.modules.fblstatus.unsupported)@" end
  local free = math.max((summary.total or 0) - (summary.used or 0), 0)
  return common.formatBytes(free)
end

local function open(opts)
  common.openReadOnlyPage(opts, PAGE_TITLE, function(ctx)
    local fields = {
      arming = common.addValueLine("@i18n(app.modules.fblstatus.arming_flags)@", "-"),
      dataflash = common.addValueLine("@i18n(app.modules.fblstatus.dataflash_free_space)@", "-"),
      realTimeLoad = common.addValueLine("@i18n(app.modules.fblstatus.real_time_load)@", "-"),
      cpuLoad = common.addValueLine("@i18n(app.modules.fblstatus.cpu_load)@", "-"),
      pidProfile = common.addValueLine("@i18n(app.modules.profile_select.pid_profile)@", "-"),
      rateProfile = common.addValueLine("@i18n(app.modules.profile_select.rate_profile)@", "-"),
      motors = common.addValueLine("@i18n(app.modules.diagnostics.motor_count)@", "-"),
      servos = common.addValueLine("@i18n(app.modules.diagnostics.servo_count)@", "-"),
      reboot = common.addValueLine("@i18n(app.modules.diagnostics.reboot_required)@", "-"),
      config = common.addValueLine("@i18n(app.modules.diagnostics.configuration_state)@", "-"),
    }
    local pending = 0
    local lastPoll = 0

    -- The reasons, one full-width row each, below the page's other lines.
    -- armingRows[1] is the heading. Rows are created on demand and then only
    -- re-texted: this form API can't remove a line, so a reason cleared while
    -- the page is open leaves an empty row until the page is re-entered.
    local armingRows = {}
    local armingActive = {}
    local armingMask = nil

    local function renderArming(mask)
      mask = armingFlags.normalize(mask)
      if mask == armingMask then return end
      armingMask = mask

      local active = armingFlags.active(mask, armingActive)
      common.updateField(fields.arming, armingFlags.summary(#active))
      common.setOkColor(fields.arming, #active == 0)

      if #active == 0 then
        for i = 1, #armingRows do armingRows[i]:value("") end
        return
      end
      if armingRows[1] == nil then
        armingRows[1] = common.addTextLine(ARMING_DETAIL_HEADING)
      else
        armingRows[1]:value(ARMING_DETAIL_HEADING)
      end
      for i = 1, #active do
        local row = armingRows[i + 1]
        if row == nil then
          armingRows[i + 1] = common.addTextLine(active[i], ARMING_DETAIL_INDENT)
        else
          row:value(active[i])
        end
      end
      for i = #active + 2, #armingRows do
        armingRows[i]:value("")
      end
    end

    local function finish()
      if ctx.isDisposed() then
        pending = 0
        return
      end
      pending = pending - 1
      if pending < 0 then pending = 0 end
      if ctx.header then ctx.header.setReloadEnabled(pending == 0) end
    end

    local function applyStatus(data)
      renderArming(data.arming_disable_flags)
      common.updateField(fields.realTimeLoad, percentTenths(data.max_real_time_load))
      common.updateField(fields.cpuLoad, percentTenths(data.average_cpu_load))
      common.updateField(fields.pidProfile, string.format("%d / %d", (data.current_pid_profile_index or 0) + 1, data.pid_profile_count or 0))
      common.updateField(fields.rateProfile, string.format("%d / %d", (data.current_control_rate_profile_index or 0) + 1, data.control_rate_profile_count or 0))
      common.updateField(fields.motors, data.motor_count)
      common.updateField(fields.servos, data.servo_count)
      common.updateField(fields.reboot, data.reboot_required == 0 and "@i18n(app.modules.rfstatus.ok)@" or "@i18n(app.modules.rfstatus.error)@")
      common.updateField(fields.config, data.configuration_state)
    end

    local function poll()
      if ctx.isDisposed() or pending > 0 then return end
      pending = 2
      if ctx.header then ctx.header.setReloadEnabled(false) end
      bus.publish("msp.request", mspStatus.buildReadMessage(function(data)
        if not ctx.isDisposed() then applyStatus(data) end
        finish()
      end, finish))
      bus.publish("msp.request", dataflashSummary.buildReadMessage(function(data)
        if not ctx.isDisposed() then common.updateField(fields.dataflash, dataflashText(data)) end
        finish()
      end, finish))
    end

    if ctx.header then
      ctx.header.setReloadEnabled(true)
    end
    poll()

    return {
      onReload = poll,
      wakeup = function()
        local now = os.clock()
        if now - lastPoll < 2 then return end
        lastPoll = now
        poll()
      end,
    }
  end)
end

return {open = open}
