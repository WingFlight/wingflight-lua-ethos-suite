-- Flight Tuning -> Advanced -> Auto Level -> Attitude Hold.
local autolevel = assert(loadfile("app/pages/autolevel.lua"))()

local function buildFields(runtime, fieldLayout)
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.att_hold)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "atthold_gain"}},
    {title = "@i18n(app.modules.autolevel.deadband)@", spec = {key = "atthold_deadband"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "atthold_max_rate"})

end

local function open(opts)
  autolevel.open(opts, "@i18n(app.modules.autolevel.att_hold)@", buildFields)
end

return {open = open}
