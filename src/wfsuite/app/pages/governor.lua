-- Setup -> Governor page.
--
-- Wingflight's fixed-wing Throttle Range Governor, not Rotorflight's
-- removed heli governor. Edits MSP2_WING_GOVERNOR_CONFIG /
-- MSP2_WING_SET_GOVERNOR_CONFIG via lib/msp_governor_config.lua.

local pageRuntime = assert(loadfile("app/page_runtime.lua"))()
local fieldLayout = assert(loadfile("app/field_layout.lua"))()
local governorConfig = assert(loadfile("lib/msp_governor_config.lua"))()

local PAGE_TITLE = "@i18n(app.modules.governor.name)@"

local MODE_OFF = 0
local MODE_RPM = 1
local MODE_THROTTLE = 2
local MODE_RPM_RANGE = 3

local function setFieldActive(field, active, loaded)
  if not field then return end
  active = active == true
  if field.active then
    local ok = pcall(function() field:active(active) end)
    if ok then
      if field.enable then field:enable(active and loaded == true) end
      return
    end
  end
  if field.enable then field:enable(active and loaded == true) end
end

local function open(opts)
  local runtime
  local panels = {}

  local function currentMode()
    return tonumber(runtime.data and runtime.data.governor_mode) or MODE_OFF
  end

  local function openPanel(panel, open)
    if panel and panel.open then panel:open(open == true) end
  end

  local function applyMode()
    local mode = currentMode()
    local loaded = runtime.loaded == true
    local rpmMode = mode == MODE_RPM
    local throttleMode = mode == MODE_THROTTLE
    local rpmRangeMode = mode == MODE_RPM_RANGE
    local activeMode = mode ~= MODE_OFF
    local rpmControlMode = rpmMode or rpmRangeMode

    openPanel(panels.rpm, rpmMode or rpmRangeMode)
    openPanel(panels.response, rpmControlMode)
    openPanel(panels.throttle, activeMode)

    setFieldActive(runtime.fields.governor_rpm, rpmMode, loaded)
    setFieldActive(runtime.fields.governor_rpm_min, rpmRangeMode, loaded)
    setFieldActive(runtime.fields.governor_rpm_max, rpmRangeMode, loaded)
    setFieldActive(runtime.fields.governor_gain, rpmControlMode, loaded)
    setFieldActive(runtime.fields.governor_i_gain, rpmControlMode, loaded)
    setFieldActive(runtime.fields.governor_throttle, throttleMode, loaded)
    setFieldActive(runtime.fields.governor_handover, rpmMode or throttleMode, loaded)
    setFieldActive(runtime.fields.governor_ceiling, activeMode, loaded)
  end

  runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "governor",
    mspModule = governorConfig,
    opts = opts,
    profileField = "none",
    rebootAfterSave = true,
    unloadPackageKeys = {"wfsuite.lib.msp_governor_config"},
    onLoaded = applyMode,
  })

  form.clear()
  runtime:buildChrome()

  local line = form.addLine("@i18n(app.modules.governor.mode)@")
  local modeField = form.addChoiceField(line, nil, governorConfig.MODE_CHOICES,
    currentMode,
    function(value)
      runtime:markDirty()
      runtime.data.governor_mode = tonumber(value) or MODE_OFF
      applyMode()
    end)
  runtime:registerField("governor_mode", modeField)

  panels.rpm = form.addExpansionPanel("@i18n(app.modules.governor.rpm_group)@")
  panels.rpm:open(false)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.rpm)@", {key = "governor_rpm"}, panels.rpm)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.rpm_min)@", {key = "governor_rpm_min"}, panels.rpm)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.rpm_max)@", {key = "governor_rpm_max"}, panels.rpm)

  panels.response = form.addExpansionPanel("@i18n(app.modules.governor.response_group)@")
  panels.response:open(false)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.gain)@", {key = "governor_gain"}, panels.response)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.i_gain)@", {key = "governor_i_gain"}, panels.response)

  panels.throttle = form.addExpansionPanel("@i18n(app.modules.governor.throttle_group)@")
  panels.throttle:open(false)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.throttle)@", {key = "governor_throttle"}, panels.throttle)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.handover)@", {key = "governor_handover"}, panels.throttle)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.governor.ceiling)@", {key = "governor_ceiling"}, panels.throttle)

  runtime:loadInitial()
end

return {open = open}
