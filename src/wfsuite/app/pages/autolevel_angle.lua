-- Flight Tuning -> Advanced -> Auto Level -> Angle.
local autolevel = assert(loadfile("app/pages/autolevel.lua"))()

local function buildFields(runtime, fieldLayout)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.gain)@", {key = "angle_level_strength"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.bank)@", {key = "angle_roll_limit"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.pitch)@", {key = "angle_pitch_limit"})
end

local function open(opts)
  autolevel.open(opts, "@i18n(app.modules.autolevel.angle_mode)@", buildFields)
end

return {open = open}
