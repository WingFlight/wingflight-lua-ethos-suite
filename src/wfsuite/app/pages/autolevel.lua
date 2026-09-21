-- Shared runtime for the individual Auto Level tools. Loaded with the selected
-- page only; full PID-profile reads/writes preserve settings belonging to other modes.
local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")

local function open(opts, title, limitPrefix, buildFields)
  local runtime
  local function refreshLimitFields()
    if runtime.busy or not runtime.loaded or not limitPrefix then return end
    local supported = runtime.data.has_axis_limits == true
    runtime.fields[limitPrefix .. "_roll_limit"]:enable(supported)
    runtime.fields[limitPrefix .. "_pitch_limit"]:enable(supported)
    local sharedKey = limitPrefix == "trainer" and "trainer_angle_limit" or "angle_level_limit"
    runtime.fields[sharedKey]:enable(not supported)
  end
  runtime = pageRuntime.new({
    pageTitle = title,
    logTag = "autolevel",
    mspModule = pidProfile,
    opts = opts,
    onLoaded = refreshLimitFields,
    refreshOnReloadFailure = true,
    unloadPackageKeys = {"wfsuite.lib.msp_pid_profile"},
  })

  form.clear()
  runtime:buildChrome()
  buildFields(runtime, fieldLayout)
  runtime:loadInitial()
end

return {open = open}
