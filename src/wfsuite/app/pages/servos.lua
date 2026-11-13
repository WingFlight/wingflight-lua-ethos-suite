-- Setup -> Servos.
--
-- One list of every servo in use. A servo is a servo (MSP API 22.16): servo
-- N is sent on PWM output N where the board has one and on channel N of a
-- bus output (SBUS, F.Bus) when one is set up, and it is configured the same
-- way either way. Index N - 1 is that servo in every servo message, so the
-- tile's index is used as it is for the read, the write, the center and the
-- override.
--
-- Builds the list from MSP_STATUS servo_count (the servos in use, up to 24),
-- then opens an indexed per-servo config editor. Tool toggles servo override;
-- while override is enabled, Center is live-written via SET_SERVO_CENTER and
-- the other fields are locked, matching the original suite's safety shape
-- without its global session table.
--
-- The PWM update rate (servo_pwm_rate) is not offered here: 50 Hz suits
-- nearly every model, and the setup wizard's servo type step and the
-- Configurator's Servos tab set it for the rest.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local header = requireModule("app/header.lua")
local pageRuntime = requireModule("app/page_runtime.lua")
local tileGrid = requireModule("app/tile_grid.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local eeprom = requireModule("lib/msp_eeprom.lua")
local servoCenter = requireModule("lib/msp_servo_center.lua")
local servoConfig = requireModule("lib/msp_servo_config.lua")
local servoOverride = requireModule("lib/msp_servo_override.lua")
local status = requireModule("lib/msp_status.lua")

local PAGE_TITLE = "@i18n(app.modules.servos.name)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_LOAD_ERROR = "@i18n(app.modules.ports.load_error_prefix)@"
local BTN_OK = "@i18n(app.btn_ok)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"
local YES_NO = {
  {"@i18n(app.modules.servos.tbl_no)@", 0},
  {"@i18n(app.modules.servos.tbl_yes)@", 1},
}

local LIVE_SETTLE = 0.05
-- MAX_SUPPORTED_SERVOS in the firmware.
local MAX_SERVOS = 24
-- app/gfx has servo1.png to servo16.png; the servos past them share servos.png.
local NUMBERED_ICON_COUNT = 16

local function servoTitle(index)
  return "@i18n(app.modules.servos.servo_prefix)@" .. index
end

-- servoCount: MSP_STATUS servo_count, the servos in use.
local function buildRows(servoCount)
  local rows = {}
  local count = math.max(0, math.min(tonumber(servoCount) or 0, MAX_SERVOS))
  for i = 1, count do
    local icon = i <= NUMBERED_ICON_COUNT and ("servo" .. i .. ".png") or "servos.png"
    rows[i] = {index = i - 1, title = servoTitle(i), icon = icon}
  end
  return rows
end

local function flagsFor(reverse, geometry)
  if reverse == 1 and geometry == 1 then return 3 end
  if geometry == 1 then return 2 end
  if reverse == 1 then return 1 end
  return 0
end

local function unpackFlags(data)
  local flags = data.flags or 0
  data.reverse = (flags == 1 or flags == 3) and 1 or 0
  data.geometry = (flags == 2 or flags == 3) and 1 or 0
end

-- Overrides go through the codec's hold/release so that they lapse on the
-- flight controller if the radio or link goes away (timed overrides).
local function publishOverrideAll(value)
  if value == servoOverride.OVERRIDE_OFF then
    servoOverride.releaseAll()
  else
    servoOverride.holdAll(value)
  end
end

local function publishOverride(index, value)
  if value == servoOverride.OVERRIDE_OFF then
    servoOverride.release(index)
  else
    servoOverride.hold(index, value)
  end
end

local openList

local function openEditor(opts, listState, row)
  local inheritedOverride = listState.inOverride == true
  local inOverride = inheritedOverride
  local lastCenter = nil
  local lastChangeAt = 0
  local index = row.index

  local function disableOverride()
    if listState.inOverride then
      publishOverrideAll(servoOverride.OVERRIDE_OFF)
      listState.inOverride = false
    else
      publishOverride(index, servoOverride.OVERRIDE_OFF)
    end
    inOverride = false
  end

  local runtime
  runtime = pageRuntime.new({
    -- Edits are saved with the page's Save; liveWrite would skip Back's unsaved-changes question.
    liveWrite = false,
    pageTitle = PAGE_TITLE .. " / " .. row.title,
    logTag = "servos_editor",
    mspModule = servoConfig.forIndex(index),
    opts = {
      onBack = function()
        if inOverride and not inheritedOverride then
          disableOverride()
        end
        openList(opts, listState)
      end,
      setEventHandler = opts.setEventHandler,
      setWakeupHandler = opts.setWakeupHandler,
      setPaintHandler = opts.setPaintHandler,
      setCleanupHandler = opts.setCleanupHandler,
    },
    profileField = "none",
    unloadPackageKeys = {
      "wfsuite.lib.msp_servo_center",
      "wfsuite.lib.msp_servo_config",
      "wfsuite.lib.msp_servo_override",
    },
    onLoaded = function()
      unpackFlags(runtime.data)
      lastCenter = runtime.data.mid
      if inOverride then
        for key, field in pairs(runtime.fields) do
          if key ~= "mid" then field:enable(false) end
        end
      end
      if form.invalidate then form.invalidate() end
    end,
    beforeSave = function(rt)
      rt.data.flags = flagsFor(rt.data.reverse, rt.data.geometry)
    end,
    toolIcon = "app/gfx/nav/override.png",
    onTool = function(focusFn)
      form.openDialog({
        title = inOverride and "@i18n(app.modules.servos.disable_servo_override)@"
          or "@i18n(app.modules.servos.enable_servo_override)@",
        message = inOverride and "@i18n(app.modules.servos.disable_servo_override_msg)@"
          or "@i18n(app.modules.servos.enable_servo_override_msg)@",
        buttons = {
          {label = BTN_OK, action = function()
            if inOverride then
              disableOverride()
              inheritedOverride = false
              for key, field in pairs(runtime.fields) do
                if key ~= "mid" then field:enable(runtime.loaded) end
              end
            else
              -- The live write below waits for the read; so must the override.
              if not runtime.loaded then
                if focusFn then focusFn() end
                return true
              end
              publishOverride(index, servoOverride.OVERRIDE_CENTER)
              inOverride = true
              inheritedOverride = false
              lastCenter = runtime.data.mid
              lastChangeAt = os.clock()
              for key, field in pairs(runtime.fields) do
                if key ~= "mid" then field:enable(false) end
              end
            end
            if focusFn then focusFn() end
            return true
          end},
          {label = BTN_CANCEL, action = function()
            if focusFn then focusFn() end
            return true
          end},
        },
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT,
      })
    end,
    onWakeup = function(rt)
      if not inOverride or not rt.loaded or rt.activeDialog then return end
      local now = os.clock()
      local current = rt.data.mid
      if current ~= lastCenter and (now - lastChangeAt) >= LIVE_SETTLE then
        bus.publish("msp.request", servoCenter.buildWriteMessage(index, current))
        lastCenter = current
        lastChangeAt = now
      end
    end,
    onDispose = function()
      if inOverride and not inheritedOverride then
        disableOverride()
      end
    end,
  })

  form.clear()
  runtime:buildChrome()
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.servos.center)@", {key = "mid"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.servos.minimum)@", {key = "min"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.servos.maximum)@", {key = "max"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.servos.scale_negative)@", {key = "rneg"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.servos.scale_positive)@", {key = "rpos"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.servos.speed)@", {key = "speed"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.servos.reverse)@", {key = "reverse", choices = YES_NO})
  runtime:loadInitial()
end

openList = function(opts, listState)
  local rows = listState.rows or {}
  local selected = listState.selected or 1

  local function leaveList()
    if listState.inOverride then
      publishOverrideAll(servoOverride.OVERRIDE_OFF)
      listState.inOverride = false
      bus.publish("msp.request", eeprom.buildWriteMessage())
    end
    if opts.onBack then opts.onBack() end
  end

  form.clear()
  local headerHandle = header.build(PAGE_TITLE, {
    onBack = leaveList,
    toolIcon = "app/gfx/nav/override.png",
    onTool = function(focusFn)
      form.openDialog({
        title = listState.inOverride and "@i18n(app.modules.servos.disable_servo_override)@"
          or "@i18n(app.modules.servos.enable_servo_override)@",
        message = listState.inOverride and "@i18n(app.modules.servos.disable_servo_override_msg)@"
          or "@i18n(app.modules.servos.enable_servo_override_msg)@",
        buttons = {
          {label = BTN_OK, action = function()
            if listState.inOverride then
              publishOverrideAll(servoOverride.OVERRIDE_OFF)
              listState.inOverride = false
              bus.publish("msp.request", eeprom.buildWriteMessage())
            else
              publishOverrideAll(servoOverride.OVERRIDE_CENTER)
              listState.inOverride = true
            end
            if focusFn then focusFn() end
            return true
          end},
          {label = BTN_CANCEL, action = function()
            if focusFn then focusFn() end
            return true
          end},
        },
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT,
      })
    end,
  })

  if opts.setEventHandler then
    opts.setEventHandler(function(category, value)
      if closeKey.shouldHandleClose(category, value) then
        leaveList()
        return true
      end
      return false
    end)
  end
  if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
  if opts.setPaintHandler then opts.setPaintHandler(nil) end
  if opts.setCleanupHandler then
    opts.setCleanupHandler(function()
      if listState.inOverride then
        publishOverrideAll(servoOverride.OVERRIDE_OFF)
        listState.inOverride = false
      end
    end)
  end

  local windowWidth, windowHeight = lcd.getWindowSize()
  local numPerRow, tileW, tileH, tilePadding, tileFont = tileGrid.metrics(windowWidth, windowHeight)
  local x, y = 0, form.height() + tilePadding
  local col = 0
  local buttons = {}

  local function addTile(i, title, icon, press)
    buttons[i] = form.addButton(nil, {x = x, y = y, w = tileW, h = tileH}, {
      text = tileGrid.fitLabel(title, tileW, tileFont),
      icon = lcd.loadMask("app/gfx/" .. icon),
      options = tileFont,
      press = press,
    })
    col = col + 1
    if col >= numPerRow then
      col = 0
      x = 0
      y = y + tileH + tilePadding
    else
      x = x + tileW + tilePadding
    end
  end

  for i, row in ipairs(rows) do
    addTile(i, row.title, row.icon, function()
      listState.selected = i
      openEditor(opts, listState, row)
    end)
  end

  if buttons[selected] then
    buttons[selected]:focus()
  else
    headerHandle.focusMenu()
  end
end

local function open(opts)
  local disposed = false
  local pendingStatus = nil
  local pendingError = nil
  local dialog = nil
  local listState = {inOverride = false}

  local function closeDialog(force)
    if not dialog then return end
    local d = dialog
    dialog = nil
    pcall(function() d:value(100) end)
    pcall(function() d:close(force == true) end)
  end

  local function goBack()
    disposed = true
    closeDialog(true)
    if opts.onBack then opts.onBack() end
  end

  form.clear()
  header.build(PAGE_TITLE, {onBack = goBack})
  form.addLine(MSG_LOADING_TITLE)
  dialog = progressDialog.open({
    title = MSG_LOADING_TITLE,
    message = MSG_LOADING_BODY,
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
      closeDialog(true)
    end)
  end
  if opts.setWakeupHandler then
    opts.setWakeupHandler(function()
      if disposed then return end
      if pendingError then
        pendingError = nil
        closeDialog()
        form.clear()
        header.build(PAGE_TITLE, {onBack = goBack})
        form.addLine(MSG_LOAD_ERROR .. " STATUS")
        return
      end
      if pendingStatus then
        listState.rows = buildRows(pendingStatus.servo_count)
        closeDialog()
        opts.setWakeupHandler(nil)
        openList(opts, listState)
      end
    end)
  end

  bus.publish("msp.request", status.buildReadMessage(function(data)
    if disposed then return end
    pendingStatus = data
  end, function()
    if disposed then return end
    pendingError = true
  end))
end

return {open = open}
