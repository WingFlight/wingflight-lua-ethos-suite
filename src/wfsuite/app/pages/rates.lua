-- Rates profile editor page. Loaded on demand (plain loadfile) only when
-- the user opens Flight Tuning -> Rates -- see app/tool.lua. Top-level
-- Flight Tuning entry (order 2, between PIDs and Governor in the
-- manifest), not part of the Advanced submenu.
--
-- First page against MSP_RC_TUNING (cmd 111/204, see
-- lib/msp_rc_tuning.lua). Exposes the 9 "curve shape" fields
-- (rcRates_N/rcExpo_N/rates_N per axis, roll/pitch/yaw only) the original
-- suite's own app/modules/rates/rates.lua page shows. The rest of
-- MSP_RC_TUNING (response_time/accel_limit/setpoint_boost/yaw_dynamic)
-- matches the original's own Advanced -> Rates Advanced submenu instead
-- -- see app/pages/rates_advanced.lua.
--
-- No axis-4 (Collective) row and no rates_type/table-picker concept:
-- wingflight-firmware hardcodes a single rate-curve formula
-- (applyWingflightRates() in src/main/fc/rc_rates.c) and the collective
-- axis's fields are wire-present-but-dead placeholders -- see
-- lib/msp_rc_tuning.lua's own header and lib/rate_curve_scale.lua's for
-- the full story (this used to be a 7-table, 4-axis picker page in the
-- pre-rewrite/rotorflight-based version; neither dimension is real here
-- any more). lib/rate_curve_scale.lua's scaleFor()/decimalsFor() take no
-- rates_type argument any more either, so this page needs no "guess now,
-- correct once the real type is known" dance -- bounds/decimals are
-- known and correct from construction, no onLoaded correction pass
-- needed.
--
-- Everything else -- dialog/busy/save/reload/confirm state, long-press-
-- save, profile-switch-reload -- comes from app/page_runtime.lua, shared
-- with every page. `profileField = "rateProfile"` (see the open()'s own
-- call below), not the default "pidProfile" -- this page's
-- MSP_RC_TUNING is scoped by *rate* profile, tracked the same way
-- tasks/session.lua already tracks pidProfile (its own "rate_profile"
-- telemetry sensor read), giving the same "<title> #<profile>" suffix
-- and auto-reload-on-profile-switch app/pages/pids.lua gets, just keyed
-- off the other profile slot.

local pageRuntime = assert(loadfile("app/page_runtime.lua"))()
local rcTuning = assert(loadfile("lib/msp_rc_tuning.lua"))()
local rateCurveScale = assert(loadfile("lib/rate_curve_scale.lua"))()

local PAGE_TITLE = "@i18n(app.modules.rates.name)@"

-- Column order matches the original's own grid: RC Rate, then the
-- "shape"/"super rate"/"max rate" column (always the `rates_N` wire
-- field, whatever a given table calls it -- see lib/rate_curve_scale.lua),
-- then RC Expo.
local COLUMNS = {
  {title = "@i18n(app.modules.rates.rc_rate)@", role = "rcRate"},
  {title = "@i18n(app.modules.rates.rate)@", role = "srate"},
  {title = "@i18n(app.modules.rates.rc_expo)@", role = "expo"},
}
local ROWS = {
  {label = "@i18n(app.modules.rates.roll)@", axis = 1, axisClass = "main"},
  {label = "@i18n(app.modules.rates.pitch)@", axis = 2, axisClass = "main"},
  {label = "@i18n(app.modules.rates.yaw)@", axis = 3, axisClass = "main"},
}

local function fieldKeyFor(role, axis)
  if role == "rcRate" then return "rcRates_" .. axis end
  if role == "srate" then return "rates_" .. axis end
  return "rcExpo_" .. axis
end

-- opts.onBack: called to return to the menu (the header's Menu button or
-- the physical Back key -- see app/page_runtime.lua's buildChrome()).
-- opts.setEventHandler/opts.setWakeupHandler/opts.setCleanupHandler: see
-- app/menu_container.lua and app/tool.lua for how Ethos's
-- event()/wakeup()/close() reach a page.
local function open(opts)
  local runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE,
    logTag = "rates",
    mspModule = rcTuning,
    opts = opts,
    -- "Rates #<profile>" title suffix + auto-reload-on-profile-switch,
    -- same mechanism app/pages/pids.lua gets from the default
    -- "pidProfile" -- this page's MSP_RC_TUNING is scoped by *rate*
    -- profile instead (tasks/session.lua's own rateProfile tracking,
    -- read from the "rate_profile" telemetry sensor).
    profileField = "rateProfile",
    unloadPackageKeys = {"wfsuite.lib.msp_rc_tuning"},
  })

  form.clear()
  runtime:buildChrome()
  -- Captured once, right after buildChrome() -- every field's getter/
  -- setter closure below captures this small indirection table, not
  -- `runtime` itself, matching app/pages/pids.lua's own convention (see
  -- its comment, and app/page_runtime.lua's PageRuntime:dispose(), for
  -- why: Ethos retains some closures past this page's own lifetime, and
  -- dataRef -- unlike the full runtime -- gets its contents cleared on
  -- dispose, so whatever Ethos keeps alive stays small).
  local dataRef = runtime.dataRef

  -- Column header line, matching app/pages/pids.lua's own P/I/D/F/O/B
  -- header convention: a blank-but-non-empty label (" ", not "") so this
  -- line reserves the same row-label gutter width as the axis rows below
  -- (an empty "" label reserves none, throwing the 3-slot column math out
  -- of alignment -- see app/pages/pids.lua's own comment for the
  -- confirmed-live original discovery of this).
  local headerLine = form.addLine(" ")
  local headerSlots = form.getFieldSlots(headerLine, {0, 0, 0})

  -- Shows the (single, fixed) rate table's name in that same row-label
  -- gutter, in place of the blank " " -- matching the original suite's
  -- own app/modules/rates/rates.lua, which renders formdata.name at the
  -- top-left of this exact header row (its col_0). Static now, not read
  -- from dataRef: there is only ever one table (see this file's own
  -- header comment), so unlike the pre-rewrite version this never needs
  -- correcting once real data loads. headerSlots[1].x is already a
  -- known-good boundary (it's what right-aligns the "RC Rate" title
  -- correctly below), so it doubles as the right edge of this rect --
  -- same "true left edge to the first known-good boundary" idiom
  -- app/header.lua's own buildTitleRect() uses for the page title, and
  -- for the same reason: form.getFieldSlots()'s own slot 1 x/w is not
  -- reliable to use directly for an overlaid static text (see that
  -- file's header comment for the live bug that taught this).
  local rateTableRect = {x = 0, y = headerSlots[1].y, w = headerSlots[1].x, h = headerSlots[1].h}
  form.addStaticText(headerLine, rateTableRect, "@i18n(app.modules.rates.tbl_rotorflight)@", LEFT)

  for i, column in ipairs(COLUMNS) do
    form.addStaticText(headerLine, headerSlots[i], column.title, RIGHT)
  end

  for _, row in ipairs(ROWS) do
    local line = form.addLine(row.label)
    local slots = form.getFieldSlots(line, {0, 0, 0})
    for colIndex, column in ipairs(COLUMNS) do
      local key = fieldKeyFor(column.role, row.axis)
      local minVal, maxVal, decimals = rateCurveScale.displayBounds(column.role, row.axisClass)
      local field = form.addNumberField(line, slots[colIndex], minVal, maxVal,
        function()
          return rateCurveScale.toDisplayInt(dataRef.data[key], column.role, row.axisClass)
        end,
        function(value)
          dataRef.data[key] = rateCurveScale.fromDisplayInt(value, column.role, row.axisClass)
        end)
      field:decimals(decimals)
      runtime:registerField(key, field)
    end
  end

  runtime:loadInitial()
end

return {open = open}
