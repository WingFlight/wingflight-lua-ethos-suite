-- Autolevel profile editor page. Loaded on demand (plain loadfile) only when the user opens Flight Tuning -> Advanced ->
-- Autolevel -- see app/tool.lua.
--
-- Edits attitude-mode tuning via MSP_PID_PROFILE. API 22.4 adds separate
-- roll/pitch limits for ANGLE and TRAINER. Older firmware retains shared limits.
-- Assign the flight-mode switches separately under Controls -> Modes.
--
-- Everything else -- dialog/busy/save/reload/confirm state, long-press-
-- save, profile-switch-reload -- comes from app/page_runtime.lua, shared
-- with every page. Field/row building comes from app/field_layout.lua.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")

local PAGE_TITLE = "@i18n(app.modules.autolevel.name)@"

-- opts.onBack: called to return to the menu (the header's Menu button or
-- the physical Back key -- see app/page_runtime.lua's buildChrome()).
-- opts.setEventHandler/opts.setWakeupHandler: see app/menu_container.lua
-- and app/tool.lua for how Ethos's event()/wakeup() reach a page.
local function open(opts)
  local runtime
  local function refreshLimitFields()
    if runtime.busy or not runtime.loaded then return end
    local supported = runtime.data.has_axis_limits == true
    runtime.fields.angle_roll_limit:enable(supported)
    runtime.fields.angle_pitch_limit:enable(supported)
    runtime.fields.trainer_roll_limit:enable(supported)
    runtime.fields.trainer_pitch_limit:enable(supported)
    runtime.fields.angle_level_limit:enable(not supported)
    runtime.fields.trainer_angle_limit:enable(not supported)
  end
  runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "autolevel",
    mspModule = pidProfile,
    opts = opts,
    onLoaded = refreshLimitFields,
    refreshOnReloadFailure = true,
    unloadPackageKeys = {"wfsuite.lib.msp_pid_profile"},
  })

  form.clear()
  runtime:buildChrome()

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.acro_trainer)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "trainer_gain"}},
    {title = "@i18n(app.modules.autolevel.max)@", spec = {key = "trainer_angle_limit"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.angle_mode)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "angle_level_strength"}},
    {title = "@i18n(app.modules.autolevel.max)@", spec = {key = "angle_level_limit"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.trainer_limits)@", {
    {title = "@i18n(app.modules.autolevel.bank)@", spec = {key = "trainer_roll_limit"}},
    {title = "@i18n(app.modules.autolevel.pitch)@", spec = {key = "trainer_pitch_limit"}},
  })
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.angle_limits)@", {
    {title = "@i18n(app.modules.autolevel.bank)@", spec = {key = "angle_roll_limit"}},
    {title = "@i18n(app.modules.autolevel.pitch)@", spec = {key = "angle_pitch_limit"}},
  })

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.horizon_mode)@",
    {key = "horizon_level_strength"})

  -- Auto Hover and Att Hold each have several fields -- more than Acro
  -- Trainer/Angle Mode above. A live screenshot showed 3 crammed onto one
  -- buildGroup() line leaves every field box too small to comfortably
  -- show its value+suffix (each field's flex width is the line's
  -- remaining space divided by the column count, so a 3-column line gives
  -- each field noticeably less room than a 2-column one). Splitting Rate
  -- onto its own buildSingle() line -- the same full-width shape Horizon
  -- Mode already uses successfully just above -- keeps Gain/Max and
  -- Gain/Deadband as comfortable 2-column lines and gives Rate the whole
  -- line to itself instead of a third cramped slot. Auto Hover's roll
  -- deadband (see lib/msp_pid_profile.lua's v9->v10 note) gets the same
  -- treatment -- its own line, rather than cramming it in beside Rate.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.auto_hover)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "autohover_gain"}},
    {title = "@i18n(app.modules.autolevel.max)@", spec = {key = "autohover_max_angle"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "autohover_max_rate"})
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.deadband)@", {key = "autohover_roll_deadband"})

  -- Throttle assist (opt-in, 0 gain = disabled/default -- see lib/msp_pid_profile.lua's
  -- v10->v11 note): its own sub-group rather than folded into Auto Hover's group above,
  -- same 2-column-then-own-line reasoning as the comment above this block already explains.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.throttle_assist)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "autohover_throttle_assist_gain"}},
    {title = "@i18n(app.modules.autolevel.max)@", spec = {key = "autohover_throttle_assist_max"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.time)@", {key = "autohover_throttle_assist_trigger_ms"})

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.att_hold)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "atthold_gain"}},
    {title = "@i18n(app.modules.autolevel.deadband)@", spec = {key = "atthold_deadband"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "atthold_max_rate"})

  runtime:loadInitial()
end

return {open = open}
