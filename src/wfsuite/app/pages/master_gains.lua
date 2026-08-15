-- Master Gains page. Loaded on demand from Advanced -> Master Gains.
--
-- Edits the same MSP_PID_PROFILE / MSP_SET_PID_PROFILE command (cmd
-- 94/95, see lib/msp_pid_profile.lua) as app/pages/pid_controller.lua --
-- a second page sharing one codec, same as every field that page itself
-- doesn't build a widget for already round-trips unchanged on every save
-- (see that file's own header comment). Split out to its own page rather
-- than living inside PID Controller: master_gain_0-2/gain_curve_0-2/
-- fw_tpa_gain/fw_tpa_curve form one coherent "Master Gains" table (one
-- row per axis -- Roll/Pitch/Yaw/Throttle -- each a live P/I/D/F scale
-- plus which app/pages/curves.lua gain-curve slot shapes it vs. stick
-- input), matching wingflight-configurator's own Master Gains table,
-- where Throttle (fw_tpa_gain/fw_tpa_curve) is that table's 4th row, not
-- a separate "Throttle Attenuation" concept -- it's the same PID-gain-
-- vs-stick-input curve mechanism as the other three axes, just keyed to
-- throttle position instead of roll/pitch/yaw.
--
-- Every other MSP_PID_PROFILE field (iterm decay/relax, error limit,
-- cross-axis relax, etc.) is still read and written back unchanged every
-- round-trip here -- this page just doesn't build a widget for them,
-- exactly the same relationship PID Controller has with THESE four
-- fields' fw_tpa_gain/fw_tpa_curve/master_gain_*/gain_curve_* now that
-- they've moved here.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local pidProfile = requireModule("lib/msp_pid_profile.lua")
local curveSlotLabels = requireModule("app/curve_slot_labels.lua")

local PAGE_TITLE = "@i18n(app.modules.master_gains.name)@"

-- "None"/"Curve 1".."Curve 8" -- gain_curve_0/1/2/fw_tpa_curve only pick
-- WHICH of app/pages/curves.lua's 8 Gain-curve pool slots is assigned
-- here; shape editing lives on that page, not here.
local CURVE_SLOT_OPTIONS = curveSlotLabels.optionsTable(8)

local AXES = {
  {label = "@i18n(app.modules.master_gains.axis_roll)@", gainKey = "master_gain_0", curveKey = "gain_curve_0"},
  {label = "@i18n(app.modules.master_gains.axis_pitch)@", gainKey = "master_gain_1", curveKey = "gain_curve_1"},
  {label = "@i18n(app.modules.master_gains.axis_yaw)@", gainKey = "master_gain_2", curveKey = "gain_curve_2"},
  {label = "@i18n(app.modules.master_gains.axis_throttle)@", gainKey = "fw_tpa_gain", curveKey = "fw_tpa_curve"},
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
  local headerSlots = form.getFieldSlots(headerLine, {0, 0})
  form.addStaticText(headerLine, headerSlots[1], "@i18n(app.modules.master_gains.gain)@", RIGHT)
  form.addStaticText(headerLine, headerSlots[2], "@i18n(app.modules.master_gains.curve)@", RIGHT)

  for _, axis in ipairs(AXES) do
    local line = form.addLine(axis.label)
    local slots = form.getFieldSlots(line, {0, 0})
    fieldLayout.buildField(runtime, line, slots[1], {key = axis.gainKey})
    fieldLayout.buildField(runtime, line, slots[2], {key = axis.curveKey, choices = CURVE_SLOT_OPTIONS})
  end

  runtime:loadInitial()
end

return {open = open}
