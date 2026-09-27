-- Flight Tuning -> Advanced -> Gain Curves.
--
-- Assigns a gain curve (one of app/pages/curves.lua's 8 shared pool slots)
-- to each axis's Flight Feel Gain, and to Throttle. Kept off the Flight Feel
-- page (app/pages/master_gains.lua) because curves are an advanced shaping
-- tool; shape editing lives on app/pages/curves.lua. Same MSP_PID_PROFILE
-- codec as Flight Feel and PID Controller.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")
local curveSlotLabels = requireModule("app/curve_slot_labels.lua")

local PAGE_TITLE = "@i18n(app.modules.gain_curves.name)@"

-- "None"/"Curve 1".."Curve 8"
local CURVE_SLOT_OPTIONS = curveSlotLabels.optionsTable(8)

local ROWS = {
  {label = "@i18n(app.modules.master_gains.axis_roll)@", key = "gain_curve_0"},
  {label = "@i18n(app.modules.master_gains.axis_pitch)@", key = "gain_curve_1"},
  {label = "@i18n(app.modules.master_gains.axis_yaw)@", key = "gain_curve_2"},
  {label = "@i18n(app.modules.master_gains.axis_throttle)@", key = "fw_tpa_curve"},
}

-- opts.onBack: called to return to the menu (see app/page_runtime.lua's
-- buildChrome()).
local function open(opts)
  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "gaincurves",
    mspModule = pidProfile,
    opts = opts,
    unloadPackageKeys = {"wfsuite.lib.msp_pid_profile"},
  })

  form.clear()
  runtime:buildChrome()

  for _, row in ipairs(ROWS) do
    fieldLayout.buildSingle(runtime, row.label, {key = row.key, choices = CURVE_SLOT_OPTIONS})
  end

  runtime:loadInitial()
end

return {open = open}
