-- Flight Tuning -> Advanced -> Auto Level -> Auto Hover.
local autolevel = assert(loadfile("app/pages/autolevel.lua"))()

local function buildFields(runtime, fieldLayout)
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.auto_hover)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "autohover_gain"}},
    {title = "@i18n(app.modules.autolevel.max)@", spec = {key = "autohover_max_angle"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "autohover_max_rate"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.deadband)@", {key = "autohover_roll_deadband"})

  -- Throttle assist (opt-in, 0 gain = disabled/default -- see lib/msp_pid_profile.lua's
  -- v10->v11 note): its own sub-group rather than folded into Auto Hover's group above,
  -- keep two columns at most so values remain readable on the radio.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.throttle_assist)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "autohover_throttle_assist_gain"}},
    {title = "@i18n(app.modules.autolevel.max)@", spec = {key = "autohover_throttle_assist_max"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.time)@", {key = "autohover_throttle_assist_trigger_ms"})

end

local function open(opts)
  autolevel.open(opts, "@i18n(app.modules.autolevel.auto_hover)@", nil, buildFields)
end

return {open = open}
