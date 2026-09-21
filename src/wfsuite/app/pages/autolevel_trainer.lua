-- Flight Tuning -> Advanced -> Auto Level -> Trainer.
local autolevel = assert(loadfile("app/pages/autolevel.lua"))()

local function buildFields(runtime, fieldLayout)
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.gain)@", {key = "trainer_gain"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.bank)@", {key = "trainer_roll_limit"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.pitch)@", {key = "trainer_pitch_limit"})
end

local function open(opts)
  autolevel.open(opts, "@i18n(app.modules.autolevel.acro_trainer)@", buildFields)
end

return {open = open}
