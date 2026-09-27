-- Thrust Vector -> Master Gains.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local curveSlotLabels = requireModule("app/curve_slot_labels.lua")

-- "None"/"Curve 1".."Curve 8" -- the TV loop reads the same shared gain-curve
-- pool as the main loop (app/pages/curves.lua edits the shapes).
local CURVE_SLOT_OPTIONS = curveSlotLabels.optionsTable(8)

local function buildFields(runtime, fieldLayout, tvPid)
  -- Master Gain -- header row + per-axis rows, mirroring
  -- app/pages/master_gains.lua's own Gain/Curve/Decay table.
  local mgHeaderLine = form.addLine(" ")
  local mgHeaderSlots = form.getFieldSlots(mgHeaderLine, {0, 0, 0})
  form.addStaticText(mgHeaderLine, mgHeaderSlots[1], "@i18n(app.modules.master_gains.gain)@", RIGHT)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[2], "@i18n(app.modules.master_gains.curve)@", RIGHT)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[3], "@i18n(app.modules.master_gains.decay)@", RIGHT)

  local MASTER_GAIN_AXES = {
    {label = "@i18n(app.modules.master_gains.axis_roll)@", key = "master_gain_0", curveKey = "gain_curve_0", decayKey = "iterm_decay_time_0"},
    {label = "@i18n(app.modules.master_gains.axis_pitch)@", key = "master_gain_1", curveKey = "gain_curve_1", decayKey = "iterm_decay_time_1"},
    {label = "@i18n(app.modules.master_gains.axis_yaw)@", key = "master_gain_2", curveKey = "gain_curve_2", decayKey = "iterm_decay_time_2"},
  }
  for _, axis in ipairs(MASTER_GAIN_AXES) do
    local line = form.addLine(axis.label)
    local slots = form.getFieldSlots(line, {0, 0, 0})
    fieldLayout.buildField(runtime, line, slots[1], {key = axis.key})
    fieldLayout.buildField(runtime, line, slots[2], {key = axis.curveKey, choices = CURVE_SLOT_OPTIONS})
    fieldLayout.buildField(runtime, line, slots[3], {key = axis.decayKey})
  end

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.master_gains.name)@", buildFields)
end

return {open = open}
