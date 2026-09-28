-- Flight Feel page (file name kept from its Master Gains origin). Loaded on
-- demand from Flight Tuning -> Flight Feel.
--
-- Edits the same MSP_PID_PROFILE / MSP_SET_PID_PROFILE command (cmd
-- 94/95, see lib/msp_pid_profile.lua) as app/pages/pid_controller.lua --
-- a second page sharing one codec, same as every field that page itself
-- doesn't build a widget for already round-trips unchanged on every save
-- (see that file's own header comment). One row per axis
-- (Roll/Pitch/Yaw/Throttle/Speed), matching wingflight-configurator's Flight
-- Feel table: Gain (master_gain_0-2, fw_tpa_gain on Throttle, fw_spa_gain
-- on Speed), Decay (iterm_decay_time_0-2) and Relax (bounceback_0-2).
-- Throttle and Speed have only a Gain.
--
-- Gain curves (gain_curve_0-2/fw_tpa_curve/fw_spa_curve) are assigned on
-- app/pages/gain_curves.lua under Advanced, since they are an advanced
-- shaping tool. Every other MSP_PID_PROFILE field is still read and
-- written back unchanged every round-trip here -- this page just doesn't
-- build a widget for it.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")

local PAGE_TITLE = "@i18n(app.modules.master_gains.name)@"

-- Gain, Decay, Relax column widths (see field_layout.tableSlots); Relax
-- gets a little more room. Curves are assigned on app/pages/gain_curves.lua.
local COLUMN_WEIGHTS = {1, 1, 1.3}
local COLUMN_START = 0.45 -- fraction of the row width where the first column starts

local AXES = {
  {label = "@i18n(app.modules.master_gains.axis_roll)@", gainKey = "master_gain_0", decayKey = "iterm_decay_time_0", bouncebackKey = "bounceback_0"},
  {label = "@i18n(app.modules.master_gains.axis_pitch)@", gainKey = "master_gain_1", decayKey = "iterm_decay_time_1", bouncebackKey = "bounceback_1"},
  {label = "@i18n(app.modules.master_gains.axis_yaw)@", gainKey = "master_gain_2", decayKey = "iterm_decay_time_2", bouncebackKey = "bounceback_2"},
  {label = "@i18n(app.modules.master_gains.axis_throttle)@", gainKey = "fw_tpa_gain"},
  {label = "@i18n(app.modules.master_gains.axis_speed)@", gainKey = "fw_spa_gain"},
}

-- opts.onBack: called to return to the menu (the header's Menu button or
-- the physical Back key -- see app/page_runtime.lua's buildChrome()).
local function open(opts)
  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "mastergains",
    mspModule = pidProfile,
    opts = opts,
    unloadPackageKeys = {"wfsuite.lib.msp_pid_profile"},
  })

  form.clear()
  runtime:buildChrome()

  -- Header row + per-axis rows, mirroring app/pages/mixer_config.lua's
  -- own Roll/Pitch/Yaw table (Gain/Invert columns there) -- a header row
  -- naming the columns once reads better than field_layout.buildGroup's
  -- usual per-row inline mini-labels repeated on all four rows.
  local headerLine = form.addLine(" ")
  local headerSlots = fieldLayout.tableSlots(headerLine, COLUMN_WEIGHTS, COLUMN_START)
  form.addStaticText(headerLine, headerSlots[1], "@i18n(app.modules.master_gains.gain)@", RIGHT)
  form.addStaticText(headerLine, headerSlots[2], "@i18n(app.modules.master_gains.lock)@", RIGHT)
  form.addStaticText(headerLine, headerSlots[3], "@i18n(app.modules.master_gains.bounceback)@", RIGHT)

  -- I-term Decay is the other half of how "locked" each axis
  -- feels: Master Gain sets how hard it pushes back, Decay how long it remembers
  -- the disturbance. I-term Relax is a 1-10 score (higher = more relax, less
  -- bounce-back). Throttle and Speed have neither, so their last two slots
  -- stay empty.
  for _, axis in ipairs(AXES) do
    local line = form.addLine(axis.label)
    local slots = fieldLayout.tableSlots(line, COLUMN_WEIGHTS, COLUMN_START)
    fieldLayout.buildField(runtime, line, slots[1], {key = axis.gainKey})
    if axis.decayKey then
      fieldLayout.buildField(runtime, line, slots[2], {key = axis.decayKey})
      fieldLayout.buildField(runtime, line, slots[3], {key = axis.bouncebackKey})
    end
  end

  runtime:loadInitial()
end

return {open = open}
