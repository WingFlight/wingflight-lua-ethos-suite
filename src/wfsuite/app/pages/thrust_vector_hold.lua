-- Thrust Vector -> Hold.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()

local function buildFields(runtime, fieldLayout, tvPid)
  -- Attitude / Heading Hold -- independent hold engine for this loop only
  -- (BOXTVHOLD), same Gain/Deadband/Max Rate shape as
  -- app/pages/autolevel.lua's Att Hold group.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.hold)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "hold_gain"}},
    {title = "@i18n(app.modules.autolevel.deadband)@", spec = {key = "hold_deadband"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "hold_max_rate"})

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.thrust_vector.hold)@", buildFields)
end

return {open = open}
