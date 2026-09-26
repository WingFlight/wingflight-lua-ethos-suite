-- Shared runtime for the individual Auto Level tools. Loaded with the selected
-- page only; full PID-profile reads/writes preserve settings belonging to other modes.
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")

local function open(opts, title, buildFields)
  local runtime = pageRuntime.new({
    pageTitle = title,
    logTag = "autolevel",
    mspModule = pidProfile,
    opts = opts,
    unloadPackageKeys = {"wfsuite.lib.msp_pid_profile"},
  })

  form.clear()
  runtime:buildChrome()
  buildFields(runtime, fieldLayout)
  runtime:loadInitial()
end

return {open = open}
