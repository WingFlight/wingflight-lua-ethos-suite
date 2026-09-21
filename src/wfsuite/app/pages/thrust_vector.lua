-- Shared runtime for Thrust Vector tools. Each reads/writes the full TV profile
-- to preserve settings in the other tools. Profile selection is independent of
-- the main PID profile; the runtime handles reload, save and cleanup.
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local tvPid = requireModule("lib/msp_tv_pid.lua")

local function open(opts, title, buildFields)
  local runtime = pageRuntime.new({
    pageTitle = title,
    logTag = "thrustvector",
    mspModule = tvPid,
    opts = opts,
    profileField = "tvProfile",
    unloadPackageKeys = {"wfsuite.lib.msp_tv_pid"},
  })

  form.clear()
  runtime:buildChrome()
  buildFields(runtime, fieldLayout, tvPid)
  runtime:loadInitial()
end

return {open = open}
