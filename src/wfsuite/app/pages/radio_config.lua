-- Radio Config page. Loaded on demand from Setup -> Radio Config.
--
-- Ports the original suite's app/modules/radio_config module for this
-- rebuild's Wingflight 2.3 / MSP API >= 12.09 floor. That original page
-- has an older pre-12.0.9 branch with an editable arming-throttle field;
-- this rebuild deliberately omits that compatibility branch and uses the
-- current six-field layout only.
--
-- Edits MSP_RC_CONFIG / MSP_SET_RC_CONFIG (cmd 66/67, see
-- lib/msp_rc_config.lua). rc_arm_throttle is not on the 22.3 wire, so the
-- codec neither reads nor writes it.
--
-- `profileField = "none"` -- Radio Config is not PID/rate-profile scoped,
-- so the profile-switch-auto-reload machinery should stay inert.
--
-- `rebootAfterSave = true` -- matches the original module's `reboot =
-- true` return flag. page_runtime.lua applies the same armed-state safety
-- gate already used by Configuration.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local rcConfig = requireModule("lib/msp_rc_config.lua")

local PAGE_TITLE = "@i18n(app.modules.radio_config.name)@"

local function open(opts)
  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "radiocfg",
    mspModule = rcConfig,
    opts = opts,
    profileField = "none",
    rebootAfterSave = true,
    unloadPackageKeys = {"wfsuite.lib.msp_rc_config"},
  })

  form.clear()
  runtime:buildChrome()

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.radio_config.stick)@", {
    {title = "@i18n(app.modules.radio_config.deflection)@", spec = {key = "rc_deflection"}},
    {title = "@i18n(app.modules.radio_config.center)@", spec = {key = "rc_center"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.radio_config.throttle)@", {
    {title = "@i18n(app.modules.radio_config.max_throttle)@", spec = {key = "rc_max_throttle"}},
    {title = "@i18n(app.modules.radio_config.min_throttle)@", spec = {key = "rc_min_throttle"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.radio_config.deadband)@", {
    {title = "@i18n(app.modules.radio_config.roll_deadband)@", spec = {key = "rc_roll_deadband"}},
    {title = "@i18n(app.modules.radio_config.pitch_deadband)@", spec = {key = "rc_pitch_deadband"}},
    {title = "@i18n(app.modules.radio_config.yaw_deadband)@", spec = {key = "rc_yaw_deadband"}},
  })

  runtime:loadInitial()
end

return {open = open}
