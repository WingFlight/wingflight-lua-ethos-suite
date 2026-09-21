-- Thrust Vector -> Pid Bandwidth.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()

local function buildFields(runtime, fieldLayout, tvPid)
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.gyro_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "gyro_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "gyro_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "gyro_cutoff_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.dterm_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "dterm_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "dterm_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "dterm_cutoff_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.bterm_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "bterm_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "bterm_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "bterm_cutoff_2"}},
  })

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.pid_bandwidth.name)@", buildFields)
end

return {open = open}
