-- Run from the repository root: lua bin/tests/tile_grid.lua
-- LCD metrics are mocked; visual clearance still needs an Ethos radio check.
FONT_XS, FONT_S = 1, 2
local currentFont, measurements = nil, 0
local function textWidth(text)
  -- Validate that every measured candidate has complete UTF-8 characters.
  local width, pos = 0, 1
  while pos <= #text do
    local byte = text:byte(pos)
    local length
    if byte < 128 then length = 1
    elseif byte >= 194 and byte <= 223 then length = 2
    elseif byte >= 224 and byte <= 239 then length = 3
    elseif byte >= 240 and byte <= 244 then length = 4
    else error("Invalid UTF-8 leading byte") end
    for offset = 1, length - 1 do
      local nextByte = text:byte(pos + offset)
      assert(nextByte and nextByte >= 128 and nextByte <= 191, "Split UTF-8 character")
    end
    local char = text:sub(pos, pos + length - 1)
    width = width + (char == "." and 2 or char == " " and 3 or char == "i" and 3 or length > 1 and 9 or 7)
    pos = pos + length
  end
  return width * (currentFont == FONT_S and 1.25 or 1)
end
lcd = {
  font = function(font) currentFont = font end,
  getTextSize = function(text) measurements = measurements + 1; return textWidth(text), 12 end,
  getWindowSize = function() return 472, 288 end,
}
local grid = assert(loadfile("src/wfsuite/app/tile_grid.lua"))()
local function equal(actual, expected)
  assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end

for _, case in ipairs({
  {472, 288, 4, 110, 118, 8, FONT_XS},
  {632, 314, 5, 118, 124, 7, FONT_XS},
  {784, 406, 6, 120, 120, 10, FONT_S},
}) do
  local cols, w, h, gap, font = grid.metrics(case[1], case[2])
  equal(cols, case[3]); equal(w, case[4]); equal(h, case[5])
  equal(gap, case[6]); equal(font, case[7])
  assert(cols * w + (cols - 1) * gap <= case[1])
end
equal(grid.metrics(), 4)
for _, width in ipairs({320, 400, 480, 600, 640, 800}) do
  local cols, w, _, gap = grid.metrics(width, 320)
  assert(cols * w + (cols - 1) * gap <= width)
end

measurements = 0
equal(grid.fitLabel("Short", 110, FONT_XS), "Short")
equal(measurements, 1)
equal(currentFont, FONT_XS)
equal(grid.fitText("AB", 14, FONT_XS), "AB")
equal(grid.fitText("AB", 6, FONT_XS), "...")
equal(grid.fitText("AB", 5, FONT_XS), "")
equal(grid.fitText("AB", 0, FONT_XS), "")
equal(grid.fitText("AB", -1, FONT_XS), "")
equal(grid.fitText("AB", nil, FONT_XS), "AB")
equal(grid.fitText("AB   CCCCC", 29, FONT_XS), "AB...")
equal(grid.fitText(nil, 40, FONT_XS), nil)
equal(grid.fitText("", 40, FONT_XS), "")
equal(grid.fitText("@i18n(app.menu_section_flight_tuning)@", 12, FONT_XS), "@i18n(app.menu_section_flight_tuning)@")

for _, font in ipairs({FONT_XS, FONT_S}) do
  for _, text in ipairs({"Beschleunigungssensor", "Stromversorgung", "ESC/Motoren", "Übergrößen", "Élévation", "传感器配置菜单", "Flight 🛩😀 settings"}) do
    for maxWidth = 1, 130 do
      local result = grid.fitText(text, maxWidth, font)
      assert(textWidth(result) <= maxWidth, "Text exceeds available width")
      if result ~= text and result ~= "" then
        equal(result:sub(-3), "...")
        assert(not result:find("%s%.%.%.$"), "Whitespace before ellipsis")
      end
    end
    local result = grid.fitLabel(text, 110, font)
    assert(textWidth(result) <= 98, "Button frame padding was lost")
    result = grid.fitLabel(text, 110, font, 20)
    assert(textWidth(result) <= 90, "Custom padding was ignored")
  end
end
local savedLcd = lcd
lcd = nil
equal(grid.fitText("Unavailable metrics", 10, FONT_XS), "Unavailable metrics")
lcd = savedLcd
print("Tile grid checks passed: layouts, font selection, padding, UTF-8 and narrow widths")
