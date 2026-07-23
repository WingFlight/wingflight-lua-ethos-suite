-- Shared curve point-list math: sane defaults and linear interpolation
-- for the point-list curves lib/msp_mixer_curves.lua and
-- lib/msp_gain_curves.lua decode/encode, and app/curves_visual.lua's
-- preview. Same category of shared utility as lib/rate_curve_scale.lua
-- (curve-display math, not an MSP codec) -- kept separate from both
-- codec files since none of this touches the wire.
--
-- Mirrors wingflight-configurator's MixerCurve.js/GainCurve.js: a curve is
-- {count=, points={{x=,y=}, ... a FIXED-size array, always POINT_COUNT
-- entries long}} -- `count` (minimum 2) marks how many points from the
-- front are "active"; the remaining points are inert padding, never read
-- or drawn.

if package.loaded["wfsuite.lib.curve_points"] then
  return package.loaded["wfsuite.lib.curve_points"]
end

local curve_points = {}

-- Builds a fixed-length (pointCount slots) curve: the given `points`
-- (2 entries -- the two real endpoints a "flat"/default curve needs)
-- become the front of the array, count = #points, and the rest of the
-- pointCount slots are {x=0,y=0} padding.
function curve_points.nullCurve(pointCount, points)
  local curve = {count = #points, points = {}}
  for i = 1, pointCount do
    local p = points[i]
    curve.points[i] = p and {x = p.x, y = p.y} or {x = 0, y = 0}
  end
  return curve
end

-- Linear interpolation across curve.points[1..curve.count], clamped at
-- the ends -- mirrors wingflight-configurator's MixerCurve.js/GainCurve.js
-- evaluate(). `fallback` is returned when count < 2 (not a valid curve).
function curve_points.evaluate(curve, x, fallback)
  local count = curve.count or 0
  local points = curve.points
  if count < 2 then return fallback end
  if x <= points[1].x then return points[1].y end
  if x >= points[count].x then return points[count].y end
  for i = 1, count - 1 do
    local a, b = points[i], points[i + 1]
    if x >= a.x and x <= b.x then
      if b.x == a.x then return a.y end
      local t = (x - a.x) / (b.x - a.x)
      return a.y + t * (b.y - a.y)
    end
  end
  return points[count].y
end

package.loaded["wfsuite.lib.curve_points"] = curve_points
return curve_points
