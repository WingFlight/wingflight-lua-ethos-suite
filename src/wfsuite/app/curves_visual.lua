-- Curve-shape preview for app/pages/curves.lua's point editor: a graph
-- with a polyline through the curve's active points, point markers, and
-- the currently-focused point highlighted -- same visual language as
-- rotorflight-lua-ethos-suite's own app/modules/governor/tools/curves.lua
-- (grid at quarter marks, filled-circle point markers, a highlighted
-- active marker), adapted to this app's variable-point-count/free-X curve
-- model rather than that page's fixed-9-point/Y-only one.
--
-- Unlike app/alignment_visual.lua (the only other custom-paint precedent
-- in this codebase, which always draws below form.height() since nothing
-- else needs to sit below its panel), this page's point-editing fields
-- are pinned to explicit pixel rects near the screen bottom (see
-- app/pages/curves.lua) rather than living in normal document flow below
-- this graph -- so the caller passes the exact rect to draw into, rather
-- than this file inferring "whatever's left below the fields" itself.
-- Keeping the graph's Y-range strictly above the fields' Y-range (no
-- overlap either way) avoids any paint-order ambiguity between the two.

if package.loaded["wfsuite.app.curves_visual"] then
  return package.loaded["wfsuite.app.curves_visual"]
end

local floor = math.floor
local max = math.max

local curves_visual = {}

-- points: array of up to pointCount {x=,y=} tables -- only 1..count are
-- meaningful (see lib/curve_points.lua's own comment on padding slots).
-- xRange/yRange: {min=,max=} in data space (mixer: -1000..1000 both
-- axes; gain: x 0..1000, y 0..500). activeIndex: 1-based index of the
-- point whose field currently has focus, or nil for none. rect: {x=,y=,
-- w=,h=} the exact screen area to draw into.
function curves_visual.draw(points, count, xRange, yRange, activeIndex, rect)
  if not rect or rect.w < 40 or rect.h < 40 then return end

  local isDark = lcd.darkMode()
  local bg = isDark and lcd.RGB(18, 18, 18) or lcd.RGB(245, 245, 245)
  local grid = isDark and lcd.GREY(70) or lcd.GREY(210)
  local lineColor = isDark and lcd.RGB(230, 230, 230) or lcd.RGB(20, 20, 20)
  local pointColor = isDark and lcd.RGB(220, 220, 220) or lcd.RGB(0, 0, 0)
  local activeColor = isDark and lcd.RGB(255, 200, 0) or lcd.RGB(0, 120, 255)

  local panelX, panelY, panelW, panelH = rect.x, rect.y, rect.w, rect.h

  lcd.color(bg)
  lcd.drawFilledRectangle(panelX, panelY, panelW, panelH)
  lcd.color(grid)
  lcd.drawRectangle(panelX, panelY, panelW, panelH)

  -- Horizontal grid at the quarter marks (0/25/50/75/100% of yRange) --
  -- matches rotorflight-lua-ethos-suite's own governor curve grid.
  for i = 0, 4 do
    local gy = panelY + floor((panelH * i) / 4 + 0.5)
    lcd.drawLine(panelX, gy, panelX + panelW, gy)
  end

  if not count or count < 2 then return end

  local xSpan = max(1, xRange.max - xRange.min)
  local ySpan = max(1, yRange.max - yRange.min)

  local function toPixel(px, py)
    local sx = panelX + ((px - xRange.min) / xSpan) * panelW
    local sy = panelY + panelH - (((py - yRange.min) / ySpan) * panelH)
    return sx, sy
  end

  -- Zero/neutral vertical line, only drawn when it actually falls inside
  -- the visible data range (gain curves' x axis starts at 0, so it sits
  -- on the left edge there rather than mid-panel).
  if xRange.min <= 0 and 0 <= xRange.max then
    local zx = toPixel(0, yRange.min)
    lcd.drawLine(zx, panelY, zx, panelY + panelH)
  end

  local pixelPoints = {}
  for i = 1, count do
    local p = points[i]
    if p then
      local px, py = toPixel(p.x, p.y)
      pixelPoints[i] = {x = px, y = py}
    end
  end

  lcd.color(lineColor)
  for i = 1, count - 1 do
    local a, b = pixelPoints[i], pixelPoints[i + 1]
    if a and b then
      lcd.drawLine(a.x, a.y, b.x, b.y)
    end
  end

  local r = 2
  for i = 1, count do
    local p = pixelPoints[i]
    if p then
      if activeIndex == i then
        lcd.color(activeColor)
        lcd.drawFilledCircle(p.x, p.y, r + 1)
      else
        lcd.color(pointColor)
        lcd.drawFilledCircle(p.x, p.y, r)
      end
    end
  end
end

package.loaded["wfsuite.app.curves_visual"] = curves_visual
return curves_visual
