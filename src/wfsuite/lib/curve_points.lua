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

local function round(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return -math.floor(-v + 0.5)
end

-- Inserts one new point at the midpoint of whichever gap between
-- adjacent active points is currently largest, with y taken from the
-- curve's own evaluate() at that x -- the new point starts exactly ON
-- the existing curve shape rather than at stale/zero padding data,
-- matching wingflight-configurator's own MixerCurve.js/GainCurve.js
-- addPointAtLargestGap(). Used by app/pages/curves.lua whenever the
-- point count is increased: a bare "count" field has no per-point Add
-- button to hang this off, so every count increase re-derives one
-- sensible new point this way instead of just revealing a dormant slot
-- (which would leave the wire's ascending-X assumption broken -- the
-- point that used to be last would stay at its old index, not the new
-- highest one).
--
-- No-op (returns `curve` unchanged) if already at `pointCount` active
-- points or the curve doesn't have at least 2 active points to begin
-- with (nothing to find a gap between).
function curve_points.insertAtLargestGap(curve, pointCount)
  local count = curve.count or 0
  if count < 2 or count >= pointCount then return curve end
  local points = curve.points

  local bestGap, bestIndex = -1, 1
  for i = 1, count - 1 do
    local gap = points[i + 1].x - points[i].x
    if gap > bestGap then
      bestGap = gap
      bestIndex = i
    end
  end

  local midX = round((points[bestIndex].x + points[bestIndex + 1].x) / 2)
  local midY = round(curve_points.evaluate(curve, midX, points[bestIndex].y))

  local newPoints = {}
  for i = 1, bestIndex do
    newPoints[i] = points[i]
  end
  newPoints[bestIndex + 1] = {x = midX, y = midY}
  for i = bestIndex + 1, count do
    newPoints[i + 1] = points[i]
  end
  for i = count + 2, pointCount do
    newPoints[i] = points[i] or {x = 0, y = 0}
  end

  return {count = count + 1, points = newPoints}
end

-- Removes whichever INTERIOR point (2..count-1) contributes least to the
-- curve's shape -- the one closest to the straight line between its two
-- neighbours -- mirroring insertAtLargestGap()'s logic in reverse. The
-- first and last active points are never candidates: they define the
-- curve's overall extent, and simply truncating from the end (an
-- earlier version of this function) silently collapsed that extent --
-- confirmed live: reducing a 5-point curve spanning -1000..1000 down to
-- 2 left just the first two points (-1000..-482), not the endpoints, a
-- visibly "half" curve. No-op if already at the minimum 2 points.
function curve_points.removeLeastSignificant(curve, pointCount)
  local count = curve.count or 0
  if count <= 2 then return curve end
  local points = curve.points

  local bestDeviation, bestIndex = nil, 2
  for i = 2, count - 1 do
    local a, b, p = points[i - 1], points[i + 1], points[i]
    local interpY
    if b.x == a.x then
      interpY = a.y
    else
      local t = (p.x - a.x) / (b.x - a.x)
      interpY = a.y + t * (b.y - a.y)
    end
    local deviation = p.y - interpY
    if deviation < 0 then deviation = -deviation end
    if not bestDeviation or deviation < bestDeviation then
      bestDeviation = deviation
      bestIndex = i
    end
  end

  local newPoints = {}
  local w = 1
  for i = 1, count do
    if i ~= bestIndex then
      newPoints[w] = points[i]
      w = w + 1
    end
  end
  for i = count, pointCount do
    newPoints[i] = {x = 0, y = 0}
  end

  return {count = count - 1, points = newPoints}
end

package.loaded["wfsuite.lib.curve_points"] = curve_points
return curve_points
