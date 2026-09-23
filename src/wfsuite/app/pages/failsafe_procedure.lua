-- Controls -> Failsafe Stage 2 page.
--
-- Edits MSP_FAILSAFE_CONFIG: the failsafe_procedure the aircraft runs once
-- stage 1 (Channel Fallback, see failsafe.lua) has held for failsafe_delay,
-- plus its timing/throttle/switch settings. See
-- WingFlight/wingflight-firmware#146 -- this MSP pair/behaviour did nothing
-- before that firmware change (failsafeStartMonitoring() was a stub), so
-- this page has no earlier history to match against.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local header = requireModule("app/header.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local eeprom = requireModule("lib/msp_eeprom.lua")
local failsafeConfig = requireModule("lib/msp_failsafe_config.lua")

local PAGE_TITLE = "@i18n(app.modules.failsafe.name)@ / @i18n(app.modules.failsafe_procedure.name)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_SAVING_TITLE = "@i18n(app.msg_saving)@"
local MSG_SAVING_BODY = "@i18n(app.msg_saving_settings)@"
local MSG_SAVE_TITLE = "@i18n(app.msg_save_settings)@"
local MSG_SAVE_BODY = "@i18n(app.msg_save_current_page)@"
local MSG_RELOAD_TITLE = "@i18n(reload)@"
local MSG_RELOAD_BODY = "@i18n(app.msg_reload_settings)@"
local BTN_OK = "@i18n(app.btn_ok)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"

-- Values match TABLE_FAILSAFE in src/main/cli/settings.c (AUTO-LAND, DROP,
-- GPS-RESCUE), 0-indexed.
local PROCEDURE_OPTIONS = {
  {"@i18n(app.modules.failsafe_procedure.procedure_land)@", 0},
  {"@i18n(app.modules.failsafe_procedure.procedure_drop)@", 1},
  {"@i18n(app.modules.failsafe_procedure.procedure_gpsrescue)@", 2},
}

-- Values match TABLE_FAILSAFE_SWITCH_MODE (STAGE1, KILL, STAGE2).
local SWITCH_MODE_OPTIONS = {
  {"@i18n(app.modules.failsafe_procedure.switch_stage1)@", 0},
  {"@i18n(app.modules.failsafe_procedure.switch_kill)@", 1},
  {"@i18n(app.modules.failsafe_procedure.switch_stage2)@", 2},
}

local function cloneConfig(config)
  return {
    failsafe_delay = config and config.failsafe_delay or 10,
    failsafe_off_delay = config and config.failsafe_off_delay or 0,
    failsafe_throttle = config and config.failsafe_throttle or 1000,
    failsafe_switch_mode = config and config.failsafe_switch_mode or 0,
    failsafe_throttle_low_delay = config and config.failsafe_throttle_low_delay or 0,
    failsafe_procedure = config and config.failsafe_procedure or 0,
    -- May be nil if the connected firmware predates #146's MSP extension --
    -- default to 0 for the field, same as every other value here.
    failsafe_recovery_delay = config and config.failsafe_recovery_delay or 0,
  }
end

local function open(opts)
  local disposed = false
  local headerHandle = nil
  local dialog = nil
  local loaded = false
  local busy = false
  local dirty = false
  local config = cloneConfig()
  local original = cloneConfig()
  local fields = {}

  local function closeDialog(focusFn)
    if not dialog then return end
    dialog:value(100)
    dialog:close()
    dialog = nil
    if focusFn then
      focusFn()
    elseif headerHandle then
      headerHandle.focusMenu()
    end
  end

  local function showProgress(title, message)
    dialog = progressDialog.open({
      title = title,
      message = message,
    })
  end

  local function updateSaveEnabled()
    if not headerHandle then return end
    headerHandle.setSaveEnabled(not busy and loaded and dirty)
  end

  local function markDirty()
    if dirty then return end
    dirty = true
    updateSaveEnabled()
  end

  local function applyBusy(value)
    busy = value == true
    updateSaveEnabled()
    if headerHandle then
      headerHandle.setReloadEnabled(not busy)
    end
    for _, field in ipairs(fields) do
      field:enable(not busy and loaded)
    end
  end

  local function goBack()
    disposed = true
    if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
    if opts.setCleanupHandler then opts.setCleanupHandler(nil) end
    closeDialog()
    if opts.onBack then opts.onBack() end
  end

  local function loadData(focusFn)
    if disposed then return end
    loaded = false
    applyBusy(true)
    showProgress(MSG_LOADING_TITLE, MSG_LOADING_BODY)
    bus.publish("msp.request", failsafeConfig.buildReadMessage(function(data)
      if disposed then return end
      config = cloneConfig(data)
      original = cloneConfig(data)
      loaded = true
      dirty = false
      applyBusy(false)
      closeDialog(focusFn)
      if form.invalidate then form.invalidate() end
    end, function()
      if disposed then return end
      applyBusy(false)
      closeDialog(focusFn)
    end))
  end

  local function saveData(focusFn)
    if disposed or not loaded then return end
    applyBusy(true)
    showProgress(MSG_SAVING_TITLE, MSG_SAVING_BODY)
    bus.publish("msp.request", failsafeConfig.buildWriteMessage(config, function()
      if disposed then return end
      bus.publish("msp.request", eeprom.buildWriteMessage(function()
        if disposed then return end
        original = cloneConfig(config)
        dirty = false
        applyBusy(false)
        closeDialog(focusFn)
      end, function()
        if disposed then return end
        applyBusy(false)
        closeDialog(focusFn)
      end))
    end, function()
      if disposed then return end
      applyBusy(false)
      closeDialog(focusFn)
    end))
  end

  local function confirmSave(focusFn)
    form.openDialog({
      title = MSG_SAVE_TITLE,
      message = MSG_SAVE_BODY,
      buttons = {
        {label = BTN_OK, action = function() saveData(focusFn); return true end},
        {label = BTN_CANCEL, action = function() return true end},
      },
      wakeup = function() end,
      paint = function() end,
    })
  end

  local function confirmReload(focusFn)
    form.openDialog({
      title = MSG_RELOAD_TITLE,
      message = MSG_RELOAD_BODY,
      buttons = {
        {label = BTN_OK, action = function() loadData(focusFn); return true end},
        {label = BTN_CANCEL, action = function() return true end},
      },
      wakeup = function() end,
      paint = function() end,
    })
  end

  form.clear()
  headerHandle = header.build(PAGE_TITLE, {
    onBack = goBack,
    onSave = function() confirmSave(headerHandle and headerHandle.focusSave) end,
    onReload = function() confirmReload(headerHandle and headerHandle.focusReload) end,
  })

  if opts.setEventHandler then
    opts.setEventHandler(function(category, value)
      if closeKey.shouldHandleClose(category, value) then
        goBack()
        return true
      end
      return false
    end)
  end
  if opts.setCleanupHandler then
    opts.setCleanupHandler(function()
      disposed = true
      closeDialog()
    end)
  end

  -- Unlike failsafe.lua's per-channel array, this is one flat record, so
  -- saveData() above just writes the whole thing on every save rather than
  -- diffing against `original` field by field -- markDirty()'s own guard
  -- (only fires once, see above) is enough to drive the save button.
  local function addChoiceRow(label, options, key)
    local line = form.addLine(label)
    local field = form.addChoiceField(line, nil, options,
      function() return config[key] end,
      function(value)
        markDirty()
        config[key] = value
      end)
    field:enable(false)
    fields[#fields + 1] = field
  end

  local function addNumberRow(label, min, max, key, suffix, step)
    local line = form.addLine(label)
    local field = form.addNumberField(line, nil, min, max,
      function() return config[key] end,
      function(value)
        markDirty()
        config[key] = value
      end)
    if suffix then field:suffix(suffix) end
    if step and field.step then field:step(step) end
    field:enable(false)
    fields[#fields + 1] = field
  end

  addChoiceRow("@i18n(app.modules.failsafe_procedure.procedure)@", PROCEDURE_OPTIONS, "failsafe_procedure")
  addChoiceRow("@i18n(app.modules.failsafe_procedure.switch_mode)@", SWITCH_MODE_OPTIONS, "failsafe_switch_mode")
  -- 0.1s units throughout, matching failsafeConfig_t's own wire units (see
  -- lib/msp_failsafe_config.lua's header) -- shown raw with a unit suffix
  -- rather than converted, same convention failsafe.lua's own throttle
  -- fields already use (raw us, :suffix("us")).
  addNumberRow("@i18n(app.modules.failsafe_procedure.delay)@", 2, 200, "failsafe_delay", "0.1s")
  addNumberRow("@i18n(app.modules.failsafe_procedure.off_delay)@", 0, 200, "failsafe_off_delay", "0.1s")
  addNumberRow("@i18n(app.modules.failsafe_procedure.throttle_low_delay)@", 0, 300, "failsafe_throttle_low_delay", "0.1s")
  addNumberRow("@i18n(app.modules.failsafe_procedure.throttle)@", 750, 2250, "failsafe_throttle", "us", 5)
  addNumberRow("@i18n(app.modules.failsafe_procedure.recovery_delay)@", 0, 200, "failsafe_recovery_delay", "0.1s")

  loadData()
end

return {open = open}
