-- Flight Tuning -> Advanced -> Auto Level -> Horizon.
-- Horizon uses the same angle limits as Angle; all other settings stay separate.
local autolevel = assert(loadfile("app/pages/autolevel.lua"))()

local function buildFields(runtime, fieldLayout)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.gain)@", {key = "horizon_level_strength"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.max)@", {key = "angle_level_limit"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.bank)@", {key = "angle_roll_limit"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.pitch)@", {key = "angle_pitch_limit"})
end

local function open(opts)
  autolevel.open(opts, "@i18n(app.modules.autolevel.horizon_mode)@", "angle", buildFields)
end

return {open = open}
