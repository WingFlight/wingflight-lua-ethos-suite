-- Flight Tuning -> Advanced -> Auto Level -> Self-Level.
-- Angle is no longer a flight mode (API 22.12); these settings set how firmly
-- Failsafe, GPS Rescue, RTH and Loiter level the aircraft, and how far they bank.
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
