-- Oscillation Limiter profile editor page. Loaded on demand (plain loadfile) only when the user opens Flight Tuning ->
-- Advanced -> Osc Limiter -- see app/tool.lua.
--
-- Edits the six oscillation-limiter fields on MSP_PID_PROFILE (cmd 94/95,
-- see lib/msp_pid_profile.lua): the Off/On switch, the detection band
-- (low/high edge in Hz), the energy threshold, the gain floor, and the
-- engage time. Per PID profile, off by default on the firmware. Mirrors
-- wingflight-configurator's Profiles -> PID Settings "Oscillation
-- Limiter" section, including hiding the tuning fields (here: greying
-- them out) while the limiter is off. The live "is it currently cutting
-- gain" status is separate -- that is the osc_limiter telemetry sensor
-- (see tasks/audio_events.lua), not anything on this page.
--
-- Everything else -- dialog/busy/save/reload/confirm state, long-press-
-- save, profile-switch-reload -- comes from app/page_runtime.lua, shared
-- with every page. Field/row building comes from app/field_layout.lua.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")

local PAGE_TITLE = "@i18n(app.modules.osc_limiter.name)@"

local OFF_ON_OPTIONS = {
  {"@i18n(app.modules.osc_limiter.tbl_off)@", 0},
  {"@i18n(app.modules.osc_limiter.tbl_on)@", 1},
}

-- Fields that only matter while the limiter is switched on.
local DEPENDENT_KEYS = {
  "osc_limiter_min_hz",
  "osc_limiter_max_hz",
  "osc_limiter_threshold",
  "osc_limiter_floor",
  "osc_limiter_engage_ms",
}

-- opts.onBack: called to return to the menu (the header's Menu button or
-- the physical Back key -- see app/page_runtime.lua's buildChrome()).
-- opts.setEventHandler/opts.setWakeupHandler: see app/menu_container.lua
-- and app/tool.lua for how Ethos's event()/wakeup() reach a page.
local function open(opts)
  -- Last enabled state applied to DEPENDENT_KEYS' fields, so onWakeup only
  -- touches them when the switch actually changes. Reset to nil whenever
  -- the page isn't loaded: page_runtime.lua re-enables every field itself
  -- after each (re)load, which would otherwise leave them enabled with
  -- the limiter off.
  local lastEnabled = nil

  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "osclimiter",
    mspModule = pidProfile,
    opts = opts,
    unloadPackageKeys = {"wfsuite.lib.msp_pid_profile"},
    onWakeup = function(rt)
      if not rt.loaded then
        lastEnabled = nil
        return
      end
      local enabled = rt.data.osc_limiter == 1
      if enabled == lastEnabled then return end
      lastEnabled = enabled
      for i = 1, #DEPENDENT_KEYS do
        local field = rt.fields[DEPENDENT_KEYS[i]]
        if field then field:enable(enabled) end
      end
    end,
  })

  form.clear()
  runtime:buildChrome()

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.osc_limiter.name)@", {key = "osc_limiter", choices = OFF_ON_OPTIONS})

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.osc_limiter.detection_band)@", {
    {title = "@i18n(app.modules.osc_limiter.min)@", spec = {key = "osc_limiter_min_hz"}},
    {title = "@i18n(app.modules.osc_limiter.max)@", spec = {key = "osc_limiter_max_hz"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.osc_limiter.threshold)@", {key = "osc_limiter_threshold"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.osc_limiter.gain_floor)@", {key = "osc_limiter_floor"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.osc_limiter.engage_time)@", {key = "osc_limiter_engage_ms"})

  runtime:loadInitial()
end

return {open = open}
