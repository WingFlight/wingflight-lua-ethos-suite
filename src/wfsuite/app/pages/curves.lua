-- Curves module: shape editor for the Mixer and Gain curve pools
-- (MSP_MIXER_CURVES/MSP_SET_MIXER_CURVE, MSP_GAIN_CURVES/MSP_SET_GAIN_CURVE
-- -- see lib/msp_mixer_curves.lua/lib/msp_gain_curves.lua for the wire
-- format and its firmware-verification caveat).
--
-- app/pages/pid_controller.lua's fw_tpa_curve/gain_curve_0/1/2 fields only
-- pick WHICH of these 8 slots is assigned to a PID-profile field (a plain
-- index, matching wingflight-configurator's own Profiles-tab convention);
-- this page is where a slot's actual point-list SHAPE gets edited.
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

local bus = assert(loadfile("lib/bus.lua"))()
local closeKey = assert(loadfile("app/close_key.lua"))()
local fieldLayout = assert(loadfile("app/field_layout.lua"))()
local header = assert(loadfile("app/header.lua"))()
local pageRuntime = assert(loadfile("app/page_runtime.lua"))()
local progressDialog = assert(loadfile("app/progress_dialog.lua"))()
local curvesVisual = assert(loadfile("app/curves_visual.lua"))()
local curveSlotLabels = assert(loadfile("app/curve_slot_labels.lua"))()
local mixerCurves = assert(loadfile("lib/msp_mixer_curves.lua"))()
local gainCurves = assert(loadfile("lib/msp_gain_curves.lua"))()

local PAGE_TITLE = "@i18n(app.modules.curves.name)@"
local MSG_LOADING_TITLE = "@i18n(app.msg_loading)@"
local MSG_LOADING_BODY = "@i18n(app.msg_loading_from_fbl)@"
local MSG_LOAD_ERROR = "@i18n(app.modules.ports.load_error_prefix)@"

local TILE_MIN_SIZE = 112
local TILE_PADDING = 10
local TILE_MAX_COLUMNS = 6

local function gridMetrics(windowWidth)
  local numPerRow = math.max(1, math.floor((windowWidth - TILE_PADDING) / (TILE_MIN_SIZE + TILE_PADDING)))
  if numPerRow > TILE_MAX_COLUMNS then numPerRow = TILE_MAX_COLUMNS end
  local tileSize = math.floor((windowWidth - (TILE_PADDING * (numPerRow + 1))) / numPerRow)
  if tileSize < TILE_MIN_SIZE then tileSize = TILE_MIN_SIZE end
  return numPerRow, tileSize
end

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

local function openEditor(opts, category, listState, index)
  local pointCount = category.pointCount
  local lastAppliedCount = nil
  local lastSignature = nil
  local lastSyncCheckAt = 0
  local runtime

  local function syncPointRowEnablement(rt)
    local currentCount = math.floor(tonumber(rt.data.count) or 2)
    if currentCount == lastAppliedCount then return end
    lastAppliedCount = currentCount
    for i = 1, pointCount do
      local active = i <= currentCount
      local xField = rt.fields["point_" .. i .. "_x"]
      local yField = rt.fields["point_" .. i .. "_y"]
      if xField then xField:enable(active) end
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
      local points = {}
      for i = 1, pointCount do
        points[i] = {x = rt.data["point_" .. i .. "_x"] or 0, y = rt.data["point_" .. i .. "_y"] or 0}
      end
      curvesVisual.draw(points, math.floor(tonumber(rt.data.count) or 0), category.xRange, category.yRange)
    end,
  })

  form.clear()
  runtime:buildChrome()

  fieldLayout.buildSingle(runtime, "@i18n(app.modules.curves.point_count)@", {key = "count"})

  for i = 1, pointCount do
    fieldLayout.buildGroup(runtime, string.format("@i18n(app.modules.curves.point_row_fmt)@", i), {
      {title = "@i18n(app.modules.curves.point_x)@", spec = {
        key = "point_" .. i .. "_x",
        min = category.codec.FIELD_META.x.min,
        max = category.codec.FIELD_META.x.max,
        default = category.codec.FIELD_META.x.default,
      }},
      {title = "@i18n(app.modules.curves.point_y)@", spec = {
        key = "point_" .. i .. "_y",
        min = category.codec.FIELD_META.y.min,
        max = category.codec.FIELD_META.y.max,
        default = category.codec.FIELD_META.y.default,
      }},
    })
  end

  runtime:loadInitial()
end

openSlotList = function(opts, category, listState)
  form.clear()
  local headerHandle = header.build(PAGE_TITLE .. " / " .. category.title, {onBack = opts.onBack})

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

  local windowWidth = ({lcd.getWindowSize()})[1]
  local numPerRow, tileSize = gridMetrics(windowWidth)
  local x, y = TILE_PADDING, form.height() + TILE_PADDING
  local col = 0
  local buttons = {}

  for i = 1, category.curveCount do
    buttons[i] = form.addButton(nil, {x = x, y = y, w = tileSize, h = tileSize}, {
      text = curveSlotLabels.slotTitle(i),
      options = FONT_S,
      press = function()
        listState.selected = i
        openEditor(opts, category, listState, i - 1)
      end,
    })
    col = col + 1
    if col >= numPerRow then
      col = 0
      x = TILE_PADDING
      y = y + tileSize + TILE_PADDING
    else
      x = x + tileSize + TILE_PADDING
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
    opts.onBack()
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

local function openCategoryMenu(opts)
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

  local windowWidth = ({lcd.getWindowSize()})[1]
  local numPerRow, tileSize = gridMetrics(windowWidth)
  local x, y = TILE_PADDING, form.height() + TILE_PADDING
  local col = 0
  local buttons = {}

  for i, catKey in ipairs(CATEGORY_ORDER) do
    local category = CATEGORIES[catKey]
    buttons[i] = form.addButton(nil, {x = x, y = y, w = tileSize, h = tileSize}, {
      text = category.title,
      options = FONT_S,
      press = function() openCategory(opts, category) end,
    })
    col = col + 1
    if col >= numPerRow then
      col = 0
      x = TILE_PADDING
      y = y + tileSize + TILE_PADDING
    else
      x = x + tileSize + TILE_PADDING
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
