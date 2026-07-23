-- Read-only curve-shape preview for app/pages/curves.lua's point editor:
-- draws a bordered panel below the form fields with a polyline through
-- the curve's currently active points.
--
-- Deliberately much simpler than app/alignment_visual.lua (the only other
-- custom-paint precedent in this codebase, wired the same way through
-- app/page_runtime.lua's onPaint/setPaintHandler) -- a flat 2D point-plot
-- needs none of that file's rotation/projection/painter's-algorithm
-- machinery, just a data-space -> pixel-space mapping. Panel layout
-- (below form.height(), lcd.darkMode()-aware colors) mirrors that file's
-- own conventions directly.

if package.loaded["wfsuite.app.curves_visual"] then
  return package.loaded["wfsuite.app.curves_visual"]
end

local floor = math.floor
local max = math.max

local curves_visual = {}

-- points: array of up to pointCount {x=,y=} tables -- only 1..count are
-- meaningful (see lib/curve_points.lua's own comment on padding slots).
-- xRange/yRange: {min=,max=} in data space (mixer: -1000..1000 both
-- axes; gain: x 0..1000, y 0..500).
function curves_visual.draw(points, count, xRange, yRange)
  local w, h = lcd.getWindowSize()
  local y = floor(form.height() + 2)
  local vw = w - 1
  local vh = h - y - 2
  if vh < 40 then return end

  local isDark = lcd.darkMode()
  local bg = isDark and lcd.RGB(18, 18, 18) or lcd.RGB(245, 245, 245)
  local grid = isDark and lcd.GREY(70) or lcd.GREY(210)
  local lineColor = isDark and lcd.RGB(255, 220, 110) or lcd.RGB(0, 110, 235)

  local panelX = 4
  local panelY = y + 2
  local panelW = vw - 8
  local panelH = vh - 4
  if panelW < 40 or panelH < 40 then return end

  lcd.color(bg)
  lcd.drawFilledRectangle(panelX, panelY, panelW, panelH)
  lcd.color(grid)
  lcd.drawRectangle(panelX, panelY, panelW, panelH)

  if not count or count < 2 then return end

  local xSpan = max(1, xRange.max - xRange.min)
  local ySpan = max(1, yRange.max - yRange.min)

  local function toPixel(px, py)
    local sx = panelX + ((px - xRange.min) / xSpan) * panelW
    local sy = panelY + panelH - (((py - yRange.min) / ySpan) * panelH)
    return sx, sy
  end

  -- Zero/neutral crosshair, only drawn when it actually falls inside the
  -- visible data range (gain curves' x axis starts at 0, so it sits on
  -- the left edge there rather than mid-panel).
  if xRange.min <= 0 and 0 <= xRange.max then
    local zx = toPixel(0, yRange.min)
    lcd.color(grid)
    lcd.drawLine(zx, panelY, zx, panelY + panelH)
  end

  lcd.color(lineColor)
  local lastX, lastY = nil, nil
  for i = 1, count do
    local p = points[i]
    if p then
      local px, py = toPixel(p.x, p.y)
      if lastX then
        lcd.drawLine(lastX, lastY, px, py)
      end
      lastX, lastY = px, py
    end
  end
end

package.loaded["wfsuite.app.curves_visual"] = curves_visual
return curves_visual
