-- Shared resolution-based tile grid sizing for menu-like icon buttons.

local tile_grid = {}

local MENU_TILE_MIN_WIDTH = 84
local LOW_RES_WIDTH = 640
local BUTTON_INNER_PADDING = 12

local MENU_PROFILES = {
  {w = 784, h = 406, large = {w = 120, h = 120, pad = 10, perRow = 6}},
  {w = 632, h = 314, large = {w = 118, h = 124, pad = 7, perRow = 5}},
  {w = 472, h = 288, large = {w = 110, h = 118, pad = 8, perRow = 4}},
}

local function closestProfile(windowWidth, windowHeight)
  local bestProfile, bestDistance
  for i = 1, #MENU_PROFILES do
    local profile = MENU_PROFILES[i]
    local distance = math.abs(profile.w - windowWidth) + math.abs(profile.h - windowHeight)
    if not bestDistance or distance < bestDistance then
      bestProfile = profile
      bestDistance = distance
    end
  end
  return bestProfile or MENU_PROFILES[#MENU_PROFILES]
end

-- Use wider tiles on compact radios: 4 columns at 472 px, 5 at 632 px,
-- and 6 at 784 px. Keep the smaller font on screens up to 640 px.
local function chooseSpec(profile, windowWidth)
  if windowWidth > LOW_RES_WIDTH then
    return profile.large, FONT_S
  end
  return profile.large, FONT_XS
end

local function fitSpecToWindow(spec, windowWidth)
  local perRow = spec.perRow
  while perRow > 1 and math.floor((windowWidth - (spec.pad * (perRow - 1))) / perRow) < MENU_TILE_MIN_WIDTH do
    perRow = perRow - 1
  end

  local tileW = spec.w
  local tileH = spec.h
  local availableTileW = math.floor((windowWidth - (spec.pad * (perRow - 1))) / perRow)
  if availableTileW < tileW then
    tileW = availableTileW
    tileH = math.floor((spec.h * tileW / spec.w) + 0.5)
  end
  if tileW < MENU_TILE_MIN_WIDTH then tileW = MENU_TILE_MIN_WIDTH end
  return perRow, tileW, tileH, spec.pad
end

function tile_grid.metrics(windowWidth, windowHeight)
  if not windowWidth or not windowHeight then
    windowWidth, windowHeight = lcd.getWindowSize()
  end
  local profile = closestProfile(windowWidth, windowHeight)
  local spec, tileFont = chooseSpec(profile, windowWidth)
  local numPerRow, tileW, tileH, tilePadding = fitSpecToWindow(spec, windowWidth)
  return numPerRow, tileW, tileH, tilePadding, tileFont
end

-- Only called while constructing buttons, never from wakeup or paint.
-- Ethos truncates against the outer button width; reserve its frame padding
-- here so an ellipsis cannot overlap the border. Adapted from RFSuite #2370.
local function trimLastUtf8Char(text)
  local last = #text
  while last > 0 do
    local byte = text:byte(last)
    if byte < 128 or byte >= 192 then break end
    last = last - 1
  end
  return text:sub(1, math.max(0, last - 1))
end

function tile_grid.fitText(text, maxW, font)
  if type(text) ~= "string" or text == "" then return text end
  if text:sub(1, 6) == "@i18n(" then return text end
  if not maxW then return text end
  if maxW <= 0 then return "" end
  if not (lcd and lcd.getTextSize) then return text end
  if font and lcd.font then lcd.font(font) end
  if lcd.getTextSize(text) <= maxW then return text end

  local ellipsis = "..."
  if lcd.getTextSize(ellipsis) > maxW then return "" end
  local trimmed = text
  while #trimmed > 0 do
    trimmed = trimLastUtf8Char(trimmed):gsub("%s+$", "")
    local label = trimmed .. ellipsis
    if lcd.getTextSize(label) <= maxW then return label end
  end
  return ellipsis
end

function tile_grid.fitLabel(text, tileW, font, padding)
  return tile_grid.fitText(text, (tileW or 0) - (padding or BUTTON_INNER_PADDING), font)
end

return tile_grid
