-- Thrust Vector -> Master Gains.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()

local function buildFields(runtime, fieldLayout, tvPid)
  -- Master Gain -- header row + per-axis rows, mirroring
  -- app/pages/master_gains.lua's own table (no Curve column here: the TV
  -- loop has no gain-curve concept, see lib/msp_tv_pid.lua's header).
  local mgHeaderLine = form.addLine(" ")
  local mgHeaderSlots = form.getFieldSlots(mgHeaderLine, {0})
  form.addStaticText(mgHeaderLine, mgHeaderSlots[1], "@i18n(app.modules.master_gains.gain)@", RIGHT)

  local MASTER_GAIN_AXES = {
    {label = "@i18n(app.modules.master_gains.axis_roll)@", key = "master_gain_0"},
    {label = "@i18n(app.modules.master_gains.axis_pitch)@", key = "master_gain_1"},
    {label = "@i18n(app.modules.master_gains.axis_yaw)@", key = "master_gain_2"},
  }
  for _, axis in ipairs(MASTER_GAIN_AXES) do
    local line = form.addLine(axis.label)
    local slots = form.getFieldSlots(line, {0})
    fieldLayout.buildField(runtime, line, slots[1], {key = axis.key})
  end

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.master_gains.name)@", buildFields)
end

return {open = open}
