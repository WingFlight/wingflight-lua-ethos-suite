-- Thrust Vector -> Master Gains.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local curveSlotLabels = requireModule("app/curve_slot_labels.lua")

-- "None"/"Curve 1".."Curve 8" -- the TV loop reads the same shared gain-curve
-- pool as the main loop (app/pages/curves.lua edits the shapes).
local CURVE_SLOT_OPTIONS = curveSlotLabels.optionsTable(8)

-- Gain, Curve, Lock, Bounce-back column widths, as app/pages/master_gains.lua.
local COLUMN_WEIGHTS = {1, 1.2, 0.85, 1.35}
local COLUMN_START = 0.33 -- fraction of the row width where the first column starts

local function buildFields(runtime, fieldLayout, tvPid)
  -- Master Gain -- header row + per-axis rows, mirroring
  -- app/pages/master_gains.lua's own Gain/Curve/Lock/Bounce-back table.
  local mgHeaderLine = form.addLine(" ")
  local mgHeaderSlots = fieldLayout.tableSlots(mgHeaderLine, COLUMN_WEIGHTS, COLUMN_START)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[1], "@i18n(app.modules.master_gains.gain)@", RIGHT)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[2], "@i18n(app.modules.master_gains.curve)@", RIGHT)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[3], "@i18n(app.modules.master_gains.lock)@", RIGHT)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[4], "@i18n(app.modules.master_gains.bounceback)@", RIGHT)

  local MASTER_GAIN_AXES = {
    {label = "@i18n(app.modules.master_gains.axis_roll)@", key = "master_gain_0", curveKey = "gain_curve_0", decayKey = "iterm_decay_time_0", bouncebackKey = "bounceback_0"},
    {label = "@i18n(app.modules.master_gains.axis_pitch)@", key = "master_gain_1", curveKey = "gain_curve_1", decayKey = "iterm_decay_time_1", bouncebackKey = "bounceback_1"},
    {label = "@i18n(app.modules.master_gains.axis_yaw)@", key = "master_gain_2", curveKey = "gain_curve_2", decayKey = "iterm_decay_time_2", bouncebackKey = "bounceback_2"},
  }
  for _, axis in ipairs(MASTER_GAIN_AXES) do
    local line = form.addLine(axis.label)
    local slots = fieldLayout.tableSlots(line, COLUMN_WEIGHTS, COLUMN_START)
    fieldLayout.buildField(runtime, line, slots[1], {key = axis.key})
    fieldLayout.buildField(runtime, line, slots[2], {key = axis.curveKey, choices = CURVE_SLOT_OPTIONS})
    fieldLayout.buildField(runtime, line, slots[3], {key = axis.decayKey})
    fieldLayout.buildField(runtime, line, slots[4], {key = axis.bouncebackKey})
  end

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.master_gains.name)@", buildFields)
end

return {open = open}
