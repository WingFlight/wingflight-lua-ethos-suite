-- Thrust Vector -> Flight Feel (Gain, Lock, Bounce Back; curves are on
-- app/pages/thrust_vector_gain_curves.lua).
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()

-- Gain, Lock, Bounce Back column widths, as app/pages/master_gains.lua.
local COLUMN_WEIGHTS = {1, 1, 1.3}
local COLUMN_START = 0.33 -- fraction of the row width where the first column starts

local function buildFields(runtime, fieldLayout, tvPid)
  -- Flight Feel -- header row + per-axis rows, mirroring
  -- app/pages/master_gains.lua's own Gain/Lock/Bounce Back table.
  local mgHeaderLine = form.addLine(" ")
  local mgHeaderSlots = fieldLayout.tableSlots(mgHeaderLine, COLUMN_WEIGHTS, COLUMN_START)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[1], "@i18n(app.modules.master_gains.gain)@", RIGHT)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[2], "@i18n(app.modules.master_gains.lock)@", RIGHT)
  form.addStaticText(mgHeaderLine, mgHeaderSlots[3], "@i18n(app.modules.master_gains.bounceback)@", RIGHT)

  local MASTER_GAIN_AXES = {
    {label = "@i18n(app.modules.master_gains.axis_roll)@", key = "master_gain_0", decayKey = "iterm_decay_time_0", bouncebackKey = "bounceback_0"},
    {label = "@i18n(app.modules.master_gains.axis_pitch)@", key = "master_gain_1", decayKey = "iterm_decay_time_1", bouncebackKey = "bounceback_1"},
    {label = "@i18n(app.modules.master_gains.axis_yaw)@", key = "master_gain_2", decayKey = "iterm_decay_time_2", bouncebackKey = "bounceback_2"},
  }
  for _, axis in ipairs(MASTER_GAIN_AXES) do
    local line = form.addLine(axis.label)
    local slots = fieldLayout.tableSlots(line, COLUMN_WEIGHTS, COLUMN_START)
    fieldLayout.buildField(runtime, line, slots[1], {key = axis.key})
    fieldLayout.buildField(runtime, line, slots[2], {key = axis.decayKey})
    fieldLayout.buildField(runtime, line, slots[3], {key = axis.bouncebackKey})
  end

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.master_gains.name)@", buildFields)
end

return {open = open}
