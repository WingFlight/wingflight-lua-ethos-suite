-- Autolevel profile editor page. Loaded on demand (plain loadfile) only when the user opens Flight Tuning -> Advanced ->
-- Autolevel -- see app/tool.lua.
--
-- Edits eleven MSP_PID_PROFILE fields (cmd 94/95, see
-- lib/msp_pid_profile.lua): acro trainer gain/limit, angle mode gain/
-- limit, horizon mode gain, Auto Hover gain/max angle/max rate, and Att
-- Hold gain/deadband/max rate. Matches this project's own last-known-good
-- app/modules/profile_autolevel/autolevel.lua exactly, including Horizon
-- Mode being a single-field group (no "Max" counterpart -- the firmware
-- struct has no `horizon_level_limit`, only `horizon_level_strength`).
--
-- Auto Hover and Att Hold are both wingflight-native (not part of the
-- rotorflight-based rewrite this base came from -- see AGENTS.md's
-- migration notes); their fields were already decoded correctly by
-- lib/msp_pid_profile.lua since Phase 2a, just not yet exposed on any
-- page. Selecting *which* flight-mode switch position activates Auto
-- Hover (vs. Manual/Passthrough/Auto Trim) is a separate concern --
-- app/pages/modes.lua's flight-mode-range configuration, not this page's
-- PID-profile tuning values -- and isn't ported yet either (see
-- AGENTS.md).
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
  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "autolevel",
    mspModule = pidProfile,
    opts = opts,
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

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.horizon_mode)@",
    {key = "horizon_level_strength"})

  -- Auto Hover and Att Hold each have 3 fields -- one more than Acro
  -- Trainer/Angle Mode above. A live screenshot showed all 3 crammed onto
  -- one buildGroup() line leaves every field box too small to comfortably
  -- show its value+suffix (each field's flex width is the line's
  -- remaining space divided by the column count, so a 3-column line gives
  -- each field noticeably less room than a 2-column one). Splitting Rate
  -- onto its own buildSingle() line -- the same full-width shape Horizon
  -- Mode already uses successfully just above -- keeps Gain/Max and
  -- Gain/Deadband as comfortable 2-column lines and gives Rate the whole
  -- line to itself instead of a third cramped slot.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.auto_hover)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "autohover_gain"}},
    {title = "@i18n(app.modules.autolevel.max)@", spec = {key = "autohover_max_angle"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "autohover_max_rate"})

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.autolevel.att_hold)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "atthold_gain"}},
    {title = "@i18n(app.modules.autolevel.deadband)@", spec = {key = "atthold_deadband"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "atthold_max_rate"})

  runtime:loadInitial()
end

return {open = open}
