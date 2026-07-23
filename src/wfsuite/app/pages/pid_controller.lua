-- PID Controller profile editor page. Loaded on demand (plain loadfile) only when the user opens "PID Controller" from the
-- system tool's main menu -- see app/tool.lua.
--
-- Edits the MSP_PID_PROFILE / MSP_SET_PID_PROFILE command (cmd 94/95, see
-- lib/msp_pid_profile.lua) -- a *different* command from app/pages/pids.lua's
-- MSP_PID_TUNING (cmd 112/202), even though both are scoped to the same
-- active PID profile on the flight controller. Exposes iterm decay
-- (time/limit), error limit (roll/pitch/yaw), iterm relax (type +
-- roll/pitch/yaw cutoffs), and cross-axis relax (wingflight-native) --
-- wingflight-firmware has no HSI offset limit or ground-error-decay
-- concept (both heli-only; see lib/msp_pid_profile.lua for the full list
-- of wire-present-but-dead fields), so neither gets a widget here, unlike
-- the rotorflight-based guess this replaced.
-- master_gain_0-2/gain_curve_0-2/fw_tpa_gain/fw_tpa_curve (the "Master
-- Gains" table -- per-axis live P/I/D/F scale plus which
-- app/pages/curves.lua gain-curve slot shapes it) live on their own
-- app/pages/master_gains.lua page instead, sharing this same codec --
-- see that file's own header for why.
-- The other fields in that MSP command (gyro/dterm/bterm cutoffs,
-- angle/horizon/trainer, atthold, autohover, etc.) are still read and
-- written back unchanged every round-trip -- lib/msp_pid_profile.lua's
-- codec always handles the full struct -- this page just doesn't build an
-- editable widget for them yet (most belong on dedicated pages once those
-- features are ported). Every dead heli-only field (see
-- lib/msp_pid_profile.lua's FIELDS list) never gets a widget at all.
--
-- Everything else -- dialog/busy/save/reload/confirm state, long-press-
-- save, profile-switch-reload -- comes from app/page_runtime.lua, shared
-- with every page. Field/row building (single-field lines, grouped inline
-- label+field rows) comes from app/field_layout.lua, promoted out of this
-- file once app/pages/tail_rotor.lua needed the identical helpers. This
-- file now only owns the MSP_PID_PROFILE codec and which fields to show.

local pageRuntime = assert(loadfile("app/page_runtime.lua"))()
local fieldLayout = assert(loadfile("app/field_layout.lua"))()
local pidProfile = assert(loadfile("lib/msp_pid_profile.lua"))()

local PAGE_TITLE = "@i18n(app.modules.pid_controller.name)@"

local ITERM_RELAX_OPTIONS = {
  {"@i18n(app.modules.pid_controller.tbl_off)@", 0},
  {"@i18n(app.modules.pid_controller.tbl_rp)@", 1},
  {"@i18n(app.modules.pid_controller.tbl_rpy)@", 2},
}

-- opts.onBack: called to return to the menu (the header's Menu button or
-- the physical Back key -- see app/page_runtime.lua's buildChrome()).
-- opts.setEventHandler/opts.setWakeupHandler: see app/menu_container.lua
-- and app/tool.lua for how Ethos's event()/wakeup() reach a page.
local function open(opts)
  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "pidctrl",
    mspModule = pidProfile,
    opts = opts,
    unloadPackageKeys = {"wfsuite.lib.msp_pid_profile"},
  })

  form.clear()
  runtime:buildChrome()

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.inflight_error_decay)@", {
    {title = "@i18n(app.modules.pid_controller.time)@", spec = {key = "iterm_decay_time"}},
    {title = "@i18n(app.modules.pid_controller.limit)@", spec = {key = "iterm_decay_limit"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.error_limit)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "error_limit_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "error_limit_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "error_limit_2"}},
  })

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.pid_controller.iterm_relax_type)@", {key = "iterm_relax_type", choices = ITERM_RELAX_OPTIONS})

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.iterm_relax_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "iterm_relax_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "iterm_relax_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "iterm_relax_cutoff_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.cross_axis_relax)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "cross_axis_relax_strength"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "cross_axis_relax_pitch_strength"}},
  })

  fieldLayout.buildGroup(runtime, "", {
    {title = "@i18n(app.modules.pid_controller.level)@", spec = {key = "cross_axis_relax_level"}},
    {title = "@i18n(app.modules.pid_controller.cutoff)@", spec = {key = "cross_axis_relax_cutoff"}},
  })

  runtime:loadInitial()
end

return {open = open}
