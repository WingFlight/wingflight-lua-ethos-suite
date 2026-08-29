-- Thrust Vector page. Loaded on demand from Advanced -> Thrust Vector.
--
-- Edits the independent Thrust Vector PID loop's config (FEATURE_THRUST_
-- VECTOR) via MSP2_WING_TV_PID_CONFIG / SET (cmd 0x5F0B/0x5F0C, see
-- lib/msp_tv_pid.lua) -- a single master config, not scoped to the active
-- PID profile (see that file's own header for the full wire story).
-- Matches wingflight-configurator's ThrustVector.svelte tab, full parity:
-- PID Gains, Master Gain, PID Settings (iterm decay/relax, error limit,
-- gyro/dterm/bterm cutoffs), and Attitude / Heading Hold, all on this one
-- page (the configurator splits Hold into its own always-visible section
-- and the rest behind Expert Mode; this page has no such gate -- Ethos's
-- vertical scroll handles the length instead).
--
-- Everything else -- dialog/busy/save/reload/confirm state, long-press-
-- save -- comes from app/page_runtime.lua, shared with every page. This
-- page passes no `profileField` override and so inherits the default
-- ("pidProfile") reload trigger even though tvPidProfile_t is NOT
-- profile-scoped -- a switch of the active PID profile has no bearing on
-- these values at all, so that reload is a harmless no-op re-read, not a
-- real requirement; not worth a special-cased profileField just to
-- suppress one extra round-trip.
--
-- The PID Gains grid (Roll/Pitch/Yaw x P/I/D/F/B) is a near-verbatim copy
-- of app/pages/pids.lua's own pidColumnSlots()/lineMetrics()/
-- windowWidth() grid math, not a shared helper -- deliberately: extracting
-- it into app/field_layout.lua would mean touching that already-tuned,
-- live-verified page's own code path to prove the extraction is safe,
-- with no on-device testing available while writing this. Duplicated
-- instead, at the cost of the two grids drifting if one is retuned later
-- without the other.
--
-- **Unverified**: nothing in this file has been confirmed on an actual
-- Ethos device or simulator -- built from this project's own established
-- patterns (app/pages/pids.lua's grid, app/pages/autolevel.lua's group
-- layout, app/pages/master_gains.lua's header-row table), but this
-- specific combination (this many fields/groups on one page) has not.

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local pageRuntime = requireModule("app/page_runtime.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local tvPid = requireModule("lib/msp_tv_pid.lua")

local PAGE_TITLE = "@i18n(app.modules.thrust_vector.name)@"

local ITERM_RELAX_OPTIONS = {
  {"@i18n(app.modules.pid_controller.tbl_off)@", 0},
  {"@i18n(app.modules.pid_controller.tbl_rp)@", 1},
  {"@i18n(app.modules.pid_controller.tbl_rpy)@", 2},
}

-- COLUMNS is display text only (i18n tags); COLUMN_SUFFIXES is the never-
-- translated internal array fieldKeyFor() uses to build MSP field names --
-- same split app/pages/pids.lua uses, and for the same reason.
local COLUMNS = {
  "@i18n(app.modules.pids.p)@", "@i18n(app.modules.pids.i)@", "@i18n(app.modules.pids.d)@",
  "@i18n(app.modules.pids.f)@", "@i18n(app.modules.pids.b)@",
}
local COLUMN_SUFFIXES = {"p", "i", "d", "f", "b"}
local ROWS = {
  {label = "@i18n(app.modules.pids.roll)@", axis = "roll"},
  {label = "@i18n(app.modules.pids.pitch)@", axis = "pitch"},
  {label = "@i18n(app.modules.pids.yaw)@", axis = "yaw"},
}

local LOW_RES_WIDTH = 640
local GRID_RATIO = 0.70
local GRID_RATIO_LOW_RES = 0.74
local FIELD_GAP = 8
local FIELD_GAP_LOW_RES = 5
local RIGHT_PADDING = 20
local RIGHT_PADDING_LOW_RES = 8
local LABEL_GUTTER_MIN = 150
local LABEL_GUTTER_MIN_LOW_RES = 112
local FIELD_MIN_W = 40

local function fieldKeyFor(axis, colIndex)
  local suffix = COLUMN_SUFFIXES[colIndex]
  return axis .. "_" .. suffix
end

local function windowWidth()
  local w = 800
  if lcd and lcd.getWindowSize then
    local gotW = lcd.getWindowSize()
    if type(gotW) == "number" and gotW > 0 then w = gotW end
  end
  return w
end

local function lineMetrics(line)
  local slots = form.getFieldSlots(line, {0})
  local slot = slots and slots[1] or nil
  return (slot and slot.y) or 0, (slot and slot.h) or 38
end

local function pidColumnSlots(line)
  local width = windowWidth()
  local lowRes = width <= LOW_RES_WIDTH
  local numCols = #COLUMNS
  local gap = lowRes and FIELD_GAP_LOW_RES or FIELD_GAP
  local rightPadding = lowRes and RIGHT_PADDING_LOW_RES or RIGHT_PADDING
  local labelMin = lowRes and LABEL_GUTTER_MIN_LOW_RES or LABEL_GUTTER_MIN
  local gridRatio = lowRes and GRID_RATIO_LOW_RES or GRID_RATIO
  local y, h = lineMetrics(line)
  local gridW = math.floor(width * gridRatio + 0.5)
  local maxGridW = width - rightPadding - labelMin

  if gridW > maxGridW then gridW = maxGridW end
  local fieldW = math.floor((gridW - gap * (numCols - 1)) / numCols)
  if fieldW < FIELD_MIN_W then fieldW = FIELD_MIN_W end

  local totalW = fieldW * numCols + gap * (numCols - 1)
  local x = width - rightPadding - totalW
  local slots = {}
  for i = 1, numCols do
    slots[i] = {x = x + (i - 1) * (fieldW + gap), y = y, w = fieldW, h = h}
  end
  return slots
end

-- opts.onBack: called to return to the menu (the header's Menu button or
-- the physical Back key -- see app/page_runtime.lua's buildChrome()).
-- opts.setEventHandler/opts.setWakeupHandler: see app/menu_container.lua
-- and app/tool.lua for how Ethos's event()/wakeup() reach a page.
local function open(opts)
  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "thrustvector",
    mspModule = tvPid,
    opts = opts,
    unloadPackageKeys = {"wfsuite.lib.msp_tv_pid"},
  })

  form.clear()
  runtime:buildChrome()
  local dataRef = runtime.dataRef
  local controlRef = runtime.controlRef
  local function markDirty()
    local rt = controlRef.runtime
    if rt then rt:markDirty() end
  end

  -- PID Gains grid -- see app/pages/pids.lua for the header-row/RIGHT-
  -- alignment reasoning this copies verbatim.
  local headerLine = form.addLine(" ")
  local headerSlots = pidColumnSlots(headerLine)
  for i, label in ipairs(COLUMNS) do
    form.addStaticText(headerLine, headerSlots[i], label, RIGHT)
  end

  for _, row in ipairs(ROWS) do
    local line = form.addLine(row.label)
    local slots = pidColumnSlots(line)
    for colIndex = 1, #COLUMNS do
      local key = fieldKeyFor(row.axis, colIndex)
      local meta = tvPid.FIELD_META[key]
      local field = form.addNumberField(line, slots[colIndex], meta.min, meta.max,
        function() return dataRef.data[key] end,
        function(value) markDirty(); dataRef.data[key] = value end)
      field:default(meta.default)
      runtime:registerField(key, field)
    end
  end

  -- Master Gain -- header row + per-axis rows, mirroring
  -- app/pages/master_gains.lua's own table (no Curve column here: the TV
  -- loop has no gain-curve concept, see lib/msp_tv_pid.lua's header).
  local mgHeaderLine = form.addLine(" ")
  local mgHeaderSlots = form.getFieldSlots(mgHeaderLine, {0})
  form.addStaticText(mgHeaderLine, mgHeaderSlots[1], "@i18n(app.modules.master_gains.gain)@", RIGHT)

  local MASTER_GAIN_AXES = {
    {label = "@i18n(app.modules.master_gains.axis_roll)@", key = "master_gain_0"},
    {label = "@i18n(app.modules.master_gains.axis_pitch)@", key = "master_gain_1"},
    {label = "@i18n(app.modules.master_gains.axis_yaw)@", key = "master_gain_2"},
  }
  for _, axis in ipairs(MASTER_GAIN_AXES) do
    local line = form.addLine(axis.label)
    local slots = form.getFieldSlots(line, {0})
    fieldLayout.buildField(runtime, line, slots[1], {key = axis.key})
  end

  -- PID Settings: iterm decay, iterm relax, error limit, cutoffs -- same
  -- grouped-line shapes app/pages/pid_controller.lua/autolevel.lua use.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.inflight_error_decay)@", {
    {title = "@i18n(app.modules.pid_controller.time)@", spec = {key = "iterm_decay_time"}},
    {title = "@i18n(app.modules.pid_controller.limit)@", spec = {key = "iterm_decay_limit"}},
  })

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.pid_controller.iterm_relax_type)@",
    {key = "iterm_relax_type", choices = ITERM_RELAX_OPTIONS})

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.iterm_relax_level)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "iterm_relax_level_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "iterm_relax_level_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "iterm_relax_level_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.iterm_relax_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "iterm_relax_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "iterm_relax_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "iterm_relax_cutoff_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.pid_controller.error_limit)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "error_limit_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "error_limit_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "error_limit_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.gyro_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "gyro_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "gyro_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "gyro_cutoff_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.dterm_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "dterm_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "dterm_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "dterm_cutoff_2"}},
  })

  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.bterm_cutoff)@", {
    {title = "@i18n(app.modules.pid_controller.roll)@", spec = {key = "bterm_cutoff_0"}},
    {title = "@i18n(app.modules.pid_controller.pitch)@", spec = {key = "bterm_cutoff_1"}},
    {title = "@i18n(app.modules.pid_controller.yaw)@", spec = {key = "bterm_cutoff_2"}},
  })

  -- Attitude / Heading Hold -- independent hold engine for this loop only
  -- (BOXTVHOLD), same Gain/Deadband/Max Rate shape as
  -- app/pages/autolevel.lua's Att Hold group.
  fieldLayout.buildGroup(runtime, "@i18n(app.modules.thrust_vector.hold)@", {
    {title = "@i18n(app.modules.autolevel.gain)@", spec = {key = "hold_gain"}},
    {title = "@i18n(app.modules.autolevel.deadband)@", spec = {key = "hold_deadband"}},
  })
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.autolevel.rate)@", {key = "hold_max_rate"})

  runtime:loadInitial()
end

return {open = open}
