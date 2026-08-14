-- Curves module: shape editor for the Mixer and Gain curve pools
-- (MSP_MIXER_CURVES/MSP_SET_MIXER_CURVE, MSP_GAIN_CURVES/MSP_SET_GAIN_CURVE
-- -- see lib/msp_mixer_curves.lua/lib/msp_gain_curves.lua for the wire
-- format and its firmware-verification caveat).
--
-- app/pages/master_gains.lua's gain_curve_0/1/2/fw_tpa_curve fields only
-- pick WHICH of the Gain pool's 8 slots is assigned to an axis (a plain
-- index, matching wingflight-configurator's own Master Gains table
-- convention); this page is where a slot's actual point-list SHAPE gets
-- edited.
--
-- Three screens, mirroring app/pages/servos_pwm.lua's list->editor shape
-- with one extra level on top:
--   open() -> openCategoryMenu(): Mixer / Gain chooser, no MSP traffic yet.
--   openCategory(): one-off whole-pool GET (own progress dialog, like
--     servos_pwm.lua's own top-level open()), then openSlotList().
--   openSlotList(): an 8-tile grid over the already-fetched pool (no
--     re-read -- the tiles show nothing curve-specific, just "Curve N",
--     so nothing to refresh); tapping a tile opens openEditor().
--   openEditor(): a PageRuntime-backed number-field editor for one curve
--     -- count field + POINT_COUNT X/Y field pairs, rows beyond the
--     current count disabled. field_layout.lua only indexes flat
--     runtime.data[key] (no array/table field type), so this page keeps
--     its own flatten/unflatten between the codec's natural
--     {count=,points={...}} shape and synthetic point_<n>_x/point_<n>_y
--     keys -- see flatSlotModule() below.
--
-- No drag/pointer gesture exists on Ethos (rotary-step focus + tap-to-
-- activate only) -- the preview graph (onPaint, wired the same way
-- app/pages/alignment.lua uses app/alignment_visual.lua) is read-only
-- feedback, never the editing surface itself.

local requireModule = assert(loadfile("lib/require.lua"))()
local bus = requireModule("lib/bus.lua")
local closeKey = requireModule("app/close_key.lua")
local fieldLayout = requireModule("app/field_layout.lua")
local header = requireModule("app/header.lua")
local pageRuntime = requireModule("app/page_runtime.lua")
local tileGrid = requireModule("app/tile_grid.lua")
local progressDialog = requireModule("app/progress_dialog.lua")
local curvesVisual = requireModule("app/curves_visual.lua")
local curveSlotLabels = requireModule("app/curve_slot_labels.lua")
local curvePoints = requireModule("lib/curve_points.lua")
local mixerCurves = requireModule("lib/msp_mixer_curves.lua")
local gainCurves = requireModule("lib/msp_gain_curves.lua")

local PAGE_TITLE = "@i18n(app.modules.curves.name)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_LOAD_ERROR = "@i18n(app.modules.ports.load_error_prefix)@"

-- Mixer's category tile and its 8 slot tiles use the generic curve icon
-- (also app/tool.lua's own Curves menu entry); Gain's use
-- master_gains.png instead -- the same icon app/pages/master_gains.lua's
-- own menu entry uses -- so a Gain curve slot visually ties back to the
-- Master Gains table that references it, distinct from a Mixer curve
-- slot. Loaded once here rather than per-tile inside the grid-building
-- loops, since those loops rerun on every visit to these screens.
local MIXER_ICON = lcd.loadMask("app/gfx/curves.png")
local GAIN_ICON = lcd.loadMask("app/gfx/master_gains.png")

-- Point-field row layout (openEditor). COL_GAP/SIDE_MARGIN/GUTTER_W are
-- pixel constants for the dense point editor, separate from the shared
-- tile grid used by the category/slot chooser screens.
-- ROW_GAP_FRACTION/TOOLBAR_MARGIN_ROWS scale off
-- a MEASURED real field row's height (see openEditor) rather than being
-- pixel constants themselves -- two earlier approaches broke on real
-- hardware: computing the graph/field-row split from screen-height minus
-- fixed pixel margins put the field rows mid-screen instead of pinned to
-- the bottom and left the graph's rect negative-height (silently didn't
-- paint); padding with blank form.addLine("") rows to reserve graph space
-- instead made the graph consume nearly the whole screen from a single
-- blank line, pushing the field rows below the fold -- blank/empty-title
-- lines behave as an expanding filler, not a small fixed-height row, on
-- this device. Measuring one REAL field row's own height (the "Points"
-- count field, which unambiguously has normal fixed sizing) and using
-- that as the unit for both the field rows' own height and their gap
-- avoids guessing at either extreme.
local COL_GAP = 4
local SIDE_MARGIN = 4
local GUTTER_W = 28
-- The graph's own rect used SIDE_MARGIN on both edges, but the field
-- rows/header buttons above it apparently stop a few px further in on
-- the right than that -- confirmed live: the graph's right edge visibly
-- overshot past the "Points" field/button column's own right edge.
local GRAPH_RIGHT_INSET = 5
local ROW_GAP_FRACTION = 0.15
-- The confirmed-visible "< n > - +" strip in earlier testing appeared
-- only while a field was actively being edited -- a transient overlay,
-- not a permanently reserved region -- so this only needs to be a small
-- safety buffer, not a whole extra row's worth of permanently dead space
-- (confirmed live: 1.25 left a large unused gap at the screen bottom
-- with nothing drawn in it).
local TOOLBAR_MARGIN_ROWS = 0.3
-- The dense 9-column X/Y rows don't need the full measured row height --
-- that includes touch-target padding sized for a single full-width
-- field, which looked oversized reused verbatim for a compact row.
local POINT_ROW_HEIGHT_FRACTION = 0.65
-- Extra breathing room between the count field and the graph, beyond
-- form.height()'s own line spacing.
local GRAPH_TOP_GAP_FRACTION = 0.3

local function rangeOf(meta)
  return {min = meta.min, max = meta.max}
end

local CATEGORY_ORDER = {"mixer", "gain"}
local CATEGORIES = {
  mixer = {
    key = "mixer",
    codec = mixerCurves,
    pointCount = mixerCurves.POINT_COUNT,
    curveCount = mixerCurves.CURVE_COUNT,
    title = "@i18n(app.modules.curves.category_mixer)@",
    icon = MIXER_ICON,
    xRange = rangeOf(mixerCurves.FIELD_META.x),
    yRange = rangeOf(mixerCurves.FIELD_META.y),
    unloadKey = "wfsuite.lib.msp_mixer_curves",
  },
  gain = {
    key = "gain",
    codec = gainCurves,
    pointCount = gainCurves.POINT_COUNT,
    curveCount = gainCurves.CURVE_COUNT,
    title = "@i18n(app.modules.curves.category_gain)@",
    icon = GAIN_ICON,
    xRange = rangeOf(gainCurves.FIELD_META.x),
    yRange = rangeOf(gainCurves.FIELD_META.y),
    unloadKey = "wfsuite.lib.msp_gain_curves",
  },
}

-- {count=,points={...}} (the codec's natural shape) <-> flat
-- point_<n>_x/point_<n>_y keys (what field_layout.lua's flat
-- runtime.data[key] indexing needs) -- see this file's own header.
local function flatten(curve, pointCount)
  local flat = {count = curve.count or 2}
  for i = 1, pointCount do
    local p = curve.points[i] or {x = 0, y = 0}
    flat["point_" .. i .. "_x"] = p.x
    flat["point_" .. i .. "_y"] = p.y
  end
  return flat
end

local function unflatten(flat, pointCount)
  local curve = {count = flat.count or 2, points = {}}
  for i = 1, pointCount do
    curve.points[i] = {
      x = flat["point_" .. i .. "_x"] or 0,
      y = flat["point_" .. i .. "_y"] or 0,
    }
  end
  return curve
end

-- PageRuntime-compatible mspModule for ONE slot: read re-fetches the
-- whole pool (the wire GET has no index argument -- see the codec's own
-- header) and hands back just that slot, flattened; write unflattens
-- then delegates to the codec's own single-curve SET.
local function flatSlotModule(category, index)
  local codec = category.codec
  local pointCount = category.pointCount
  return {
    FIELD_META = codec.FIELD_META,
    buildReadMessage = function(onData, onError)
      return {
        command = codec.READ_COMMAND,
        processReply = function(_, buf)
          onData(flatten(codec.decodePool(buf)[index + 1], pointCount))
        end,
        errorHandler = onError,
        simulatorResponse = codec.SIMULATOR_RESPONSE_POOL,
      }
    end,
    buildWriteMessage = function(flat, onWritten, onError)
      return codec.buildWriteMessage(index, unflatten(flat, pointCount), onWritten, onError)
    end,
  }
end

local function signatureOf(data, pointCount)
  local parts = {tostring(data.count or 0)}
  for i = 1, pointCount do
    parts[#parts + 1] = tostring(data["point_" .. i .. "_x"] or 0)
    parts[#parts + 1] = tostring(data["point_" .. i .. "_y"] or 0)
  end
  return table.concat(parts, ",")
end

local openSlotList
local openCategoryMenu

local function openEditor(opts, category, listState, index)
  local pointCount = category.pointCount
  local lastAppliedCount = nil
  local lastSignature = nil
  local lastSyncCheckAt = 0
  local activeIndex = nil
  local runtime
  -- Assigned once, after the graph's reserved space is measured out below
  -- -- declared here so onPaint's closure (built before that happens)
  -- captures the same upvalues and sees their real values by the time
  -- painting actually starts.
  local graphTop, graphBottom

  local function syncPointRowEnablement(rt)
    local currentCount = math.floor(tonumber(rt.data.count) or 2)
    if currentCount == lastAppliedCount then return end

    -- Growing/shrinking the count needs a real point inserted or removed
    -- (see lib/curve_points.lua's own header on insertAtLargestGap()/
    -- removeLeastSignificant() for why a bare "count" field can't safely
    -- just reveal/drop a slot in place). Skipped on the very first sync
    -- after a (re)load (lastAppliedCount == nil) -- that's the initial
    -- data arriving, not a user-driven count change.
    if lastAppliedCount then
      local curve = unflatten(rt.data, pointCount)
      curve.count = lastAppliedCount
      if currentCount > lastAppliedCount then
        for _ = lastAppliedCount + 1, currentCount do
          curve = curvePoints.insertAtLargestGap(curve, pointCount)
        end
      else
        for _ = currentCount + 1, lastAppliedCount do
          curve = curvePoints.removeLeastSignificant(curve, pointCount)
        end
      end
      local flat = flatten(curve, pointCount)
      for i = 1, pointCount do
        local xKey, yKey = "point_" .. i .. "_x", "point_" .. i .. "_y"
        rt.data[xKey] = flat[xKey]
        rt.data[yKey] = flat[yKey]
        local xField, yField = rt.fields[xKey], rt.fields[yKey]
        if xField and xField.value then xField:value(flat[xKey]) end
        if yField and yField.value then yField:value(flat[yKey]) end
      end
    end

    lastAppliedCount = currentCount
    for i = 1, pointCount do
      local active = i <= currentCount
      -- The first and (currently) last active point define the curve's
      -- domain extent -- only their Y is user-editable, X stays pinned
      -- to xRange.min/xRange.max. Which column counts as "last" moves
      -- with currentCount, so this is re-evaluated on every count change,
      -- not fixed to pointCount's own final column.
      local xLocked = (i == 1) or (i == currentCount)
      local xField = rt.fields["point_" .. i .. "_x"]
      local yField = rt.fields["point_" .. i .. "_y"]
      if xField then xField:enable(active and not xLocked) end
      if yField then yField:enable(active) end
    end
  end

  runtime = pageRuntime.new({
    pageTitle = PAGE_TITLE .. " / " .. category.title .. " / " .. curveSlotLabels.slotTitle(index + 1),
    logTag = "curves_editor",
    mspModule = flatSlotModule(category, index),
    initialData = flatten(listState.pool[index + 1], pointCount),
    opts = {
      onBack = function() openSlotList(opts, category, listState) end,
      setEventHandler = opts.setEventHandler,
      setWakeupHandler = opts.setWakeupHandler,
      setPaintHandler = opts.setPaintHandler,
      setCleanupHandler = opts.setCleanupHandler,
    },
    profileField = "none",
    unloadPackageKeys = {category.unloadKey},
    beforeSave = function(rt)
      listState.pool[index + 1] = unflatten(rt.data, pointCount)
    end,
    onLoaded = function()
      lastAppliedCount = nil
      syncPointRowEnablement(runtime)
      if form.invalidate then form.invalidate() end
    end,
    onWakeup = function(rt)
      if not rt.loaded then return end
      local now = os.clock()
      if (now - lastSyncCheckAt) < 0.15 then return end
      lastSyncCheckAt = now
      syncPointRowEnablement(rt)
      local sig = signatureOf(rt.data, pointCount)
      if sig ~= lastSignature then
        lastSignature = sig
        if lcd.invalidate then lcd.invalidate() end
      end
    end,
    onPaint = function(rt)
      if not graphTop then return end
      local points = {}
      for i = 1, pointCount do
        points[i] = {x = rt.data["point_" .. i .. "_x"] or 0, y = rt.data["point_" .. i .. "_y"] or 0}
      end
      local winW = ({lcd.getWindowSize()})[1]
      local graphRect = {
        x = SIDE_MARGIN,
        y = graphTop,
        w = winW - SIDE_MARGIN - GRAPH_RIGHT_INSET,
        h = graphBottom - graphTop,
      }
      curvesVisual.draw(points, math.floor(tonumber(rt.data.count) or 0), category.xRange, category.yRange, activeIndex, graphRect)
    end,
  })

  form.clear()
  runtime:buildChrome()

  local preCountHeight = form.height()
  fieldLayout.buildSingle(runtime, "@i18n(app.modules.curves.point_count)@", {key = "count"})
  -- Real, measured height of one normal field row on this device -- not
  -- a guessed pixel constant (see this file's constants comment for why
  -- two earlier guesses each broke on real hardware). The dense 9-column
  -- X/Y rows use a smaller fraction of it (POINT_ROW_HEIGHT_FRACTION):
  -- the "Points" row's own height includes padding sized for a single
  -- full-width touch target, which looks oversized reused verbatim for a
  -- compact multi-column row.
  local rowHeight = math.max(20, math.floor(form.height() - preCountHeight))
  local pointRowHeight = math.max(20, math.floor(rowHeight * POINT_ROW_HEIGHT_FRACTION))
  local rowGap = math.max(2, math.floor(pointRowHeight * ROW_GAP_FRACTION))

  graphTop = math.floor(form.height() + (rowHeight * GRAPH_TOP_GAP_FRACTION))

  -- Compact per-point X/Y rows, one narrow column per point, styled after
  -- rotorflight-lua-ethos-suite's own governor curve tool
  -- (app/modules/governor/tools/curves.lua): a graph dominating the
  -- screen with a dense field row directly tied to it, rather than a
  -- scrolling list of labelled group rows. That page has a single Y-only
  -- row (fixed, evenly-spaced X); this one needs a second row since both
  -- X and Y are editable per point here.
  --
  -- Pinned to explicit pixel rects near the screen bottom (line=nil,
  -- matching that reference page's own form.addNumberField(nil, {x=,y=,
  -- w=,h=}, ...) calls -- a confirmed-working pattern for absolute field
  -- placement) so the graph above can claim the entire gap between the
  -- count field and this block, all in units of the measured rowHeight
  -- rather than screen-height pixel math. Each column's x/w is also
  -- computed by hand rather than trusting form.getFieldSlots() to split
  -- one line into pointCount all-flex (`0`) hints: app/field_layout.lua's
  -- own header already flags that combination as "not yet confirmed
  -- live" even for two columns, and a 9-wide version of it is very likely
  -- why an earlier version of this row rendered every column but the
  -- first far too narrow to show a full value.
  local winW, screenH = lcd.getWindowSize()
  local usableW = winW - (SIDE_MARGIN * 2) - GUTTER_W - COL_GAP
  local colW = math.floor((usableW - (COL_GAP * (pointCount - 1))) / pointCount)
  local colStartX = SIDE_MARGIN + GUTTER_W + COL_GAP

  local function buildPointRow(rowTop, axis, rowLabel)
    form.addStaticText(nil, {x = SIDE_MARGIN, y = rowTop, w = GUTTER_W, h = pointRowHeight}, rowLabel, LEFT)
    for i = 1, pointCount do
      local key = "point_" .. i .. "_" .. axis
      local colX = colStartX + (i - 1) * (colW + COL_GAP)
      fieldLayout.buildField(runtime, nil, {x = colX, y = rowTop, w = colW, h = pointRowHeight}, {
        key = key,
        min = category.codec.FIELD_META[axis].min,
        max = category.codec.FIELD_META[axis].max,
        default = category.codec.FIELD_META[axis].default,
      })
      local field = runtime.fields[key]
      if field and field.onFocus then
        field:onFocus(function(state)
          if state then
            activeIndex = i
            if lcd.invalidate then lcd.invalidate() end
          end
        end)
      end
    end
  end

  -- Bottom margin reserves room for Ethos's own persistent focused-field
  -- edit toolbar (the "< n > - +" strip), sized off the full rowHeight
  -- (the toolbar's real size doesn't shrink just because these rows use a
  -- smaller pointRowHeight) rather than a guessed pixel constant.
  local toolbarMargin = math.floor(rowHeight * TOOLBAR_MARGIN_ROWS)
  local xRowTop = screenH - toolbarMargin - (2 * pointRowHeight) - rowGap
  local yRowTop = xRowTop + pointRowHeight + rowGap
  graphBottom = xRowTop - rowGap

  buildPointRow(xRowTop, "x", "@i18n(app.modules.curves.point_x)@")
  buildPointRow(yRowTop, "y", "@i18n(app.modules.curves.point_y)@")

  runtime:loadInitial()
end

openSlotList = function(opts, category, listState)
  local function backToCategoryMenu()
    openCategoryMenu(opts)
  end

  form.clear()
  local headerHandle = header.build(PAGE_TITLE .. " / " .. category.title, {onBack = backToCategoryMenu})

  if opts.setEventHandler then
    opts.setEventHandler(function(evtCategory, value)
      if closeKey.shouldHandleClose(evtCategory, value) then
        backToCategoryMenu()
        return true
      end
      return false
    end)
  end
  if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
  if opts.setPaintHandler then opts.setPaintHandler(nil) end
  if opts.setCleanupHandler then opts.setCleanupHandler(nil) end

  local windowWidth, windowHeight = lcd.getWindowSize()
  local numPerRow, tileW, tileH, tilePadding, tileFont = tileGrid.metrics(windowWidth, windowHeight)
  local x, y = 0, form.height() + tilePadding
  local col = 0
  local buttons = {}

  for i = 1, category.curveCount do
    buttons[i] = form.addButton(nil, {x = x, y = y, w = tileW, h = tileH}, {
      text = curveSlotLabels.slotTitle(i),
      icon = category.icon,
      options = tileFont,
      press = function()
        listState.selected = i
        openEditor(opts, category, listState, i - 1)
      end,
    })
    col = col + 1
    if col >= numPerRow then
      col = 0
      x = 0
      y = y + tileH + tilePadding
    else
      x = x + tileW + tilePadding
    end
  end

  if buttons[listState.selected] then
    buttons[listState.selected]:focus()
  else
    headerHandle.focusMenu()
  end
end

local function openCategory(opts, category)
  local disposed = false
  local pendingPool = nil
  local pendingError = nil
  local dialog = nil

  local function closeDialog(force)
    if not dialog then return end
    local d = dialog
    dialog = nil
    pcall(function() d:value(100) end)
    pcall(function() d:close(force == true) end)
  end

  local function goBack()
    disposed = true
    closeDialog(true)
    openCategoryMenu(opts)
  end

  form.clear()
  header.build(PAGE_TITLE .. " / " .. category.title, {onBack = goBack})
  form.addLine(MSG_LOADING_TITLE)
  dialog = progressDialog.open({
    title = MSG_LOADING_TITLE,
    message = MSG_LOADING_BODY,
  })

  if opts.setEventHandler then
    opts.setEventHandler(function(evtCategory, value)
      if closeKey.shouldHandleClose(evtCategory, value) then
        goBack()
        return true
      end
      return false
    end)
  end
  if opts.setCleanupHandler then
    opts.setCleanupHandler(function()
      disposed = true
      closeDialog(true)
    end)
  end
  if opts.setWakeupHandler then
    opts.setWakeupHandler(function()
      if disposed then return end
      if pendingError then
        pendingError = nil
        closeDialog()
        form.clear()
        header.build(PAGE_TITLE .. " / " .. category.title, {onBack = goBack})
        form.addLine(MSG_LOAD_ERROR .. " " .. category.title)
        return
      end
      if pendingPool then
        local listState = {pool = pendingPool, selected = 1}
        closeDialog()
        opts.setWakeupHandler(nil)
        openSlotList(opts, category, listState)
      end
    end)
  end

  bus.publish("msp.request", category.codec.buildReadPoolMessage(function(pool)
    if disposed then return end
    pendingPool = pool
  end, function()
    if disposed then return end
    pendingError = true
  end))
end

openCategoryMenu = function(opts)
  form.clear()
  local headerHandle = header.build(PAGE_TITLE, {onBack = opts.onBack})

  if opts.setEventHandler then
    opts.setEventHandler(function(evtCategory, value)
      if closeKey.shouldHandleClose(evtCategory, value) then
        opts.onBack()
        return true
      end
      return false
    end)
  end
  if opts.setWakeupHandler then opts.setWakeupHandler(nil) end
  if opts.setPaintHandler then opts.setPaintHandler(nil) end
  if opts.setCleanupHandler then opts.setCleanupHandler(nil) end

  local windowWidth, windowHeight = lcd.getWindowSize()
  local numPerRow, tileW, tileH, tilePadding, tileFont = tileGrid.metrics(windowWidth, windowHeight)
  local x, y = 0, form.height() + tilePadding
  local col = 0
  local buttons = {}

  for i, catKey in ipairs(CATEGORY_ORDER) do
    local category = CATEGORIES[catKey]
    buttons[i] = form.addButton(nil, {x = x, y = y, w = tileW, h = tileH}, {
      text = category.title,
      icon = category.icon,
      options = tileFont,
      press = function() openCategory(opts, category) end,
    })
    col = col + 1
    if col >= numPerRow then
      col = 0
      x = 0
      y = y + tileH + tilePadding
    else
      x = x + tileW + tilePadding
    end
  end

  if buttons[1] then
    buttons[1]:focus()
  else
    headerHandle.focusMenu()
  end
end

local function open(opts)
  openCategoryMenu(opts)
end

return {open = open}
