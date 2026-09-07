-- Tools -> Select Profile page.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local header = requireModule("app/header.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local statusMsp = requireModule("lib/msp_status.lua")
local selectProfile = requireModule("lib/msp_select_profile.lua")
local tvPidMsp = requireModule("lib/msp_tv_pid.lua")
local selectTvProfile = requireModule("lib/msp_select_tv_profile.lua")

local PAGE_TITLE = "@i18n(app.modules.profile_select.name)@"
local BTN_OK = "@i18n(app.btn_ok_long)@"
local BTN_CANCEL = "@i18n(app.btn_cancel)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_SAVING_TITLE = "@i18n(app.msg_saving)@"
local MSG_SAVING_BODY = "@i18n(app.msg_saving_settings)@"
local MSG_SAVE_TITLE = "@i18n(app.msg_save_settings)@"
local MSG_SAVE_BODY = "@i18n(app.msg_save_current_page)@"

local MAX_PROFILE_COUNT = 6

local function clampCount(value)
  value = tonumber(value or MAX_PROFILE_COUNT) or MAX_PROFILE_COUNT
  if value < 1 then return 1 end
  if value > MAX_PROFILE_COUNT then return MAX_PROFILE_COUNT end
  return math.floor(value)
end

local function clampIndex(value, count)
  count = clampCount(count)
  value = tonumber(value or 0) or 0
  value = math.floor(value)
  if value < 0 then return 0 end
  if value >= count then return count - 1 end
  return value
end

local function profileChoices(count)
  local choices = {}
  for i = 1, clampCount(count) do
    choices[#choices + 1] = {tostring(i), i - 1}
  end
  return choices
end

local function open(opts)
  opts = opts or {}
  local disposed = false
  local headerHandle = nil
  local dialog = nil
  local loaded = false
  local busy = false
  local needsRender = false
  local status = {pid_profile_count = 6, control_rate_profile_count = 6}
  -- Thrust Vector profile count always equals pid_profile_count on the
  -- firmware side (same PID_PROFILE_COUNT constant, see pg/tv_pid.h) -- no
  -- separate count to read.
  local current = {pid = 0, rate = 0, tv = 0}
  local original = {pid = 0, rate = 0, tv = 0}
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

  local function isDirty()
    return current.pid ~= original.pid or current.rate ~= original.rate or current.tv ~= original.tv
  end

  local function updateEnabled()
    for _, field in ipairs(fields) do
      field:enable(loaded and not busy)
    end
    if headerHandle then
      headerHandle.setSaveEnabled(loaded and not busy and isDirty())
      headerHandle.setReloadEnabled(false)
    end
  end

  local renderPage

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
    busy = true
    fields = {}
    updateEnabled()
    showProgress(MSG_LOADING_TITLE, MSG_LOADING_BODY)
    bus.publish("msp.request", statusMsp.buildReadMessage(function(data)
      if disposed then return end
      status = data or status
      current.pid = clampIndex(status.current_pid_profile_index, status.pid_profile_count)
      current.rate = clampIndex(status.current_control_rate_profile_index, status.control_rate_profile_count)
      original.pid = current.pid
      original.rate = current.rate

      -- Thrust Vector's active profile index isn't part of MSP_STATUS -- it
      -- leads the MSP2_WING_TV_PID_CONFIG read reply instead (see
      -- lib/msp_tv_pid.lua). Fetched as a second step rather than blocking
      -- the PID/rate pickers on it.
      bus.publish("msp.request", tvPidMsp.buildReadMessage(function(tvData)
        if disposed then return end
        current.tv = clampIndex(tvData and tvData.tv_profile_index, status.pid_profile_count)
        original.tv = current.tv
        loaded = true
        busy = false
        needsRender = true
        closeDialog(focusFn)
      end, function()
        if disposed then return end
        -- Thrust Vector may not be supported/enabled -- fall back to profile 0
        -- rather than blocking the PID/rate pickers on it.
        loaded = true
        busy = false
        needsRender = true
        closeDialog(focusFn)
      end))
    end, function()
      if disposed then return end
      busy = false
      closeDialog(focusFn)
      updateEnabled()
    end))
  end

  local function saveData(focusFn)
    if disposed or not loaded or not isDirty() then return end
    busy = true
    updateEnabled()
    showProgress(MSG_SAVING_TITLE, MSG_SAVING_BODY)
    bus.publish("msp.request", selectProfile.buildWriteMessage(current.rate + 128, function()
      if disposed then return end
      bus.publish("msp.request", selectProfile.buildWriteMessage(current.pid, function()
        if disposed then return end
        bus.publish("msp.request", selectTvProfile.buildSelectMessage(current.tv, function()
          if disposed then return end
          original.pid = current.pid
          original.rate = current.rate
          original.tv = current.tv
          busy = false
          closeDialog(focusFn)
          updateEnabled()
        end, function()
          if disposed then return end
          busy = false
          closeDialog(focusFn)
          updateEnabled()
        end))
      end, function()
        if disposed then return end
        busy = false
        closeDialog(focusFn)
        updateEnabled()
      end))
    end, function()
      if disposed then return end
      busy = false
      closeDialog(focusFn)
      updateEnabled()
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
      options = TEXT_LEFT,
    })
  end

  renderPage = function(focusFn)
    if disposed then return end
    form.clear()
    fields = {}
    headerHandle = header.build(PAGE_TITLE, {
      onBack = goBack,
      onSave = function() confirmSave(headerHandle and headerHandle.focusSave) end,
    })

    local line = form.addLine("@i18n(app.modules.profile_select.pid_profile)@")
    local pidField = form.addChoiceField(line, nil, profileChoices(status.pid_profile_count),
      function() return current.pid end,
      function(value)
        current.pid = clampIndex(value, status.pid_profile_count)
        updateEnabled()
      end)
    fields[#fields + 1] = pidField

    line = form.addLine("@i18n(app.modules.profile_select.rate_profile)@")
    local rateField = form.addChoiceField(line, nil, profileChoices(status.control_rate_profile_count),
      function() return current.rate end,
      function(value)
        current.rate = clampIndex(value, status.control_rate_profile_count)
        updateEnabled()
      end)
    fields[#fields + 1] = rateField

    -- Thrust Vector profile count mirrors pid_profile_count -- see the
    -- comment on `current`/`original` above.
    line = form.addLine("@i18n(app.modules.profile_select.tv_profile)@")
    local tvField = form.addChoiceField(line, nil, profileChoices(status.pid_profile_count),
      function() return current.tv end,
      function(value)
        current.tv = clampIndex(value, status.pid_profile_count)
        updateEnabled()
      end)
    fields[#fields + 1] = tvField

    updateEnabled()
    if focusFn then focusFn() end
  end

  form.clear()
  headerHandle = header.build(PAGE_TITLE, {
    onBack = goBack,
    onSave = function() confirmSave(headerHandle and headerHandle.focusSave) end,
  })
  updateEnabled()

  if opts.setEventHandler then
    opts.setEventHandler(function(category, value)
      if closeKey.shouldHandleClose(category, value) then
        goBack()
        return true
      end
      return false
    end)
  end
  if opts.setWakeupHandler then
    opts.setWakeupHandler(function()
      if needsRender then
        needsRender = false
        renderPage()
      else
        updateEnabled()
      end
    end)
  end
  if opts.setCleanupHandler then
    opts.setCleanupHandler(function()
      disposed = true
      closeDialog()
    end)
  end

  loadData()
end

return {open = open}
