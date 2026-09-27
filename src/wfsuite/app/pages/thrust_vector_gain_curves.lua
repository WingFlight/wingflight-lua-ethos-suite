-- Thrust Vector -> Gain Curves.
--
-- Assigns a gain curve (shared pool, app/pages/curves.lua) to each axis's
-- thrust-vector Flight Feel Gain -- the TV counterpart of
-- app/pages/gain_curves.lua. The TV loop has no throttle curve.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local curveSlotLabels = requireModule("app/curve_slot_labels.lua")

-- "None"/"Curve 1".."Curve 8"
local CURVE_SLOT_OPTIONS = curveSlotLabels.optionsTable(8)

local ROWS = {
  {label = "@i18n(app.modules.master_gains.axis_roll)@", key = "gain_curve_0"},
  {label = "@i18n(app.modules.master_gains.axis_pitch)@", key = "gain_curve_1"},
  {label = "@i18n(app.modules.master_gains.axis_yaw)@", key = "gain_curve_2"},
}

local function buildFields(runtime, fieldLayout, tvPid)
  for _, row in ipairs(ROWS) do
    fieldLayout.buildSingle(runtime, row.label, {key = row.key, choices = CURVE_SLOT_OPTIONS})
  end
end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.gain_curves.name)@", buildFields)
end

return {open = open}
