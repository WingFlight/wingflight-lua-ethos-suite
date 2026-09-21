-- Run from the repository root: lua tests/autolevel_limits.lua
local runtime, callbacks
local enables = 0
local modules = {}
modules["lib/msp_pid_profile.lua"] = {}
modules["app/page_runtime.lua"] = {
  new = function(config)
    callbacks = config
    runtime = {fields = {}, data = {}, busy = false, loaded = false}
    function runtime:buildChrome() end
    function runtime:loadInitial() end
    return runtime
  end,
}
local function addField(key)
  runtime.fields[key] = {enable = function(self, enabled)
    self.enabled = enabled
    enables = enables + 1
  end}
end
modules["app/field_layout.lua"] = {
  buildGroup = function(_, _, fields)
    for _, field in ipairs(fields) do addField(field.spec.key) end
  end,
  buildSingle = function(_, _, spec) addField(spec.key) end,
}
package.loaded["wfsuite.lib.require"] = function(path) return assert(modules[path], path) end
form = {clear = function() end}
local page = assert(loadfile("src/wfsuite/app/pages/autolevel.lua"))()
page.open({})
assert(callbacks.refreshOnReloadFailure == true)
local function check(supported)
  assert(runtime.fields.trainer_roll_limit.enabled == supported)
  assert(runtime.fields.trainer_pitch_limit.enabled == supported)
  assert(runtime.fields.angle_roll_limit.enabled == supported)
  assert(runtime.fields.angle_pitch_limit.enabled == supported)
  assert(runtime.fields.trainer_angle_limit.enabled == not supported)
  assert(runtime.fields.angle_level_limit.enabled == not supported)
end
for _, supported in ipairs({false, true, false}) do
  runtime.data.has_axis_limits = supported
  runtime.loaded = true
  callbacks.onLoaded()
  check(supported)
  assert(callbacks.onWakeup == nil, "capability gates need no wakeup polling")
end
print("PASS: old/new/profile-reload field gates without wakeup polling")
