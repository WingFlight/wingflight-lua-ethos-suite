-- Thrust Vector -> Pid Controller.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()

local ITERM_RELAX_OPTIONS = {
  {"@i18n(app.modules.pid_controller.tbl_off)@", 0},
  {"@i18n(app.modules.pid_controller.tbl_rp)@", 1},
  {"@i18n(app.modules.pid_controller.tbl_rpy)@", 2},
}

local function buildFields(runtime, fieldLayout, tvPid)
  -- PID Settings: iterm decay, iterm relax, error limit, cutoffs -- same
  -- grouped-line shapes app/pages/pid_controller.lua/autolevel.lua use.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.inflight_error_decay)@", {
    {title = "@i18n(app.modules.pid_controller.time)@", spec = {key = "iterm_decay_time"}},
    {title = "@i18n(app.modules.pid_controller.limit)@", spec = {key = "iterm_decay_limit"}},
  })

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.pid_controller.iterm_relax_type)@",
    {key = "iterm_relax_type", choices = ITERM_RELAX_OPTIONS})

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.iterm_relax_level)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "iterm_relax_level_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "iterm_relax_level_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "iterm_relax_level_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.iterm_relax_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "iterm_relax_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "iterm_relax_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "iterm_relax_cutoff_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.error_limit)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "error_limit_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "error_limit_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "error_limit_2"}},
  })

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.pid_controller.name)@", buildFields)
end

return {open = open}
