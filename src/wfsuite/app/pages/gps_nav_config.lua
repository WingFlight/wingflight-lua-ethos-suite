-- Controls -> GPS Navigation page.
--
-- Edits MSP2_WING_GPS_NAV_CONFIG: tuning for the fixed-wing RTH/Loiter nav
-- controller, used by BOXRTH/BOXLOITER and the Failsafe Procedure page's
-- GPS Rescue option. Same flat-record shape as failsafe_procedure.lua (see
-- that file's own header comment for why this differs from
-- failsafe.lua's per-channel indexed pattern) -- modeled directly on it.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local header = requireModule("app/header.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local eeprom = requireModule("lib/msp_eeprom.lua")
local gpsNavConfig = requireModule("lib/msp_gps_nav_config.lua")

local PAGE_TITLE = "@i18n(app.modules.gps_nav_config.name)@"
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

-- Values match TABLE_NAV_LOITER_DIRECTION (CW, CCW), 0-indexed.
local LOITER_DIRECTION_OPTIONS = {
  {"@i18n(app.modules.gps_nav_config.direction_cw)@", 0},
  {"@i18n(app.modules.gps_nav_config.direction_ccw)@", 1},
}

local function cloneConfig(config)
  return {
    nav_loiter_radius = config and config.nav_loiter_radius or 100,
    nav_loiter_direction = config and config.nav_loiter_direction or 0,
    nav_rth_altitude = config and config.nav_rth_altitude or 50,
    nav_min_sats = config and config.nav_min_sats or 8,
    nav_max_bank_angle = config and config.nav_max_bank_angle or 25,
    nav_max_pitch_angle = config and config.nav_max_pitch_angle or 15,
    nav_bearing_kp = config and config.nav_bearing_kp or 200,
    nav_altitude_kp = config and config.nav_altitude_kp or 100,
    -- Appended MSP fields: nil when read from firmware that predates them, so fall back to
    -- the firmware defaults (older firmware ignores them on write).
    nav_altitude_kd = config and config.nav_altitude_kd or 200,
    nav_throttle = config and config.nav_throttle or 60,
    nav_turn_coordination = config and config.nav_turn_coordination or 100,
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
    bus.publish("msp.request", gpsNavConfig.buildReadMessage(function(data)
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
    bus.publish("msp.request", gpsNavConfig.buildWriteMessage(config, function()
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

  addNumberRow("@i18n(app.modules.gps_nav_config.rth_altitude)@", 10, 500, "nav_rth_altitude", "m")
  addNumberRow("@i18n(app.modules.gps_nav_config.loiter_radius)@", 20, 500, "nav_loiter_radius", "m")
  addChoiceRow("@i18n(app.modules.gps_nav_config.loiter_direction)@", LOITER_DIRECTION_OPTIONS, "nav_loiter_direction")
  addNumberRow("@i18n(app.modules.gps_nav_config.min_sats)@", 5, 50, "nav_min_sats")
  addNumberRow("@i18n(app.modules.gps_nav_config.max_bank_angle)@", 5, 45, "nav_max_bank_angle", "deg")
  addNumberRow("@i18n(app.modules.gps_nav_config.max_pitch_angle)@", 5, 45, "nav_max_pitch_angle", "deg")
  addNumberRow("@i18n(app.modules.gps_nav_config.throttle)@", 0, 100, "nav_throttle", "%")
  addNumberRow("@i18n(app.modules.gps_nav_config.bearing_kp)@", 0, 1000, "nav_bearing_kp")
  addNumberRow("@i18n(app.modules.gps_nav_config.altitude_kp)@", 0, 1000, "nav_altitude_kp")
  addNumberRow("@i18n(app.modules.gps_nav_config.altitude_kd)@", 0, 1000, "nav_altitude_kd")
  addNumberRow("@i18n(app.modules.gps_nav_config.turn_coordination)@", 0, 200, "nav_turn_coordination", "%")

  loadData()
end

return {open = open}
