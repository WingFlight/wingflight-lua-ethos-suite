-- Thrust Vector -> Pids.
local thrustVector = assert(loadfile("app/pages/thrust_vector.lua"))()

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

local function buildFields(runtime, fieldLayout, tvPid)
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

end

local function open(opts)
  thrustVector.open(opts, "@i18n(app.modules.pids.name)@", buildFields)
end

return {open = open}
