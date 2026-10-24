-- Setup Wizard pictures: the model in 3D (app/plane3d.lua), seen from
-- behind as the pilot sees it standing behind the model, with the surfaces
-- a check moves lit and swung the way each should go.
--
-- Built from the surface kinds lib/setup_wizard_surfaces.lua finds in the
-- mix and the model type, so a V-tail, a flying wing, a delta or a model
-- with flaps each get their own airframe. Which side a servo is on cannot
-- be read from the mix (it depends on how the servo is mounted, which is
-- what the check is about), so the picture shows the airframe's surfaces,
-- not individual servos.
--
-- layout() runs when a screen is built; draw() runs from paint and only
-- draws what layout() worked out (the 3D airframe is built once per layout).
-- The wizard sets art.modelType (MSP_MIXER_CONFIG's model_type) when it
-- reads or changes the mix.

if package.loaded["wfsuite.app.setup_wizard_art"] then
  return package.loaded["wfsuite.app.setup_wizard_art"]
end

local requireModule = package.loaded["wfsuite.lib.require"] or assert(loadfile("lib/require.lua"))()
local plane3d = requireModule("app/plane3d.lua")

local floor = math.floor

local art = {}

art.modelType = nil

-- Which part of the half span the surfaces cover (0 the centreline, 1 the
-- tip): whether a layout has them, and what the 3D airframe uses (spec3d()).
local OUTER = {0.55, 0.97}   -- ailerons, elevons
local FLAPERON = {0.30, 0.97}
local INNER = {0.13, 0.50}   -- flaps

-- Arrow for each element on each check: "up", "down", "right", or nil when
-- the check does not move it. Sides: L and R as seen from behind.
local ARROWS = {
  pitch = {outer = {"up", "up"}, stab = {"up", "up"}, vtail = {"up", "up"}},
  roll = {outer = {"down", "up"}, inner = {"down", "up"}},
  yaw = {fin = {"right"}, vtail = {"right", "right"}},
  flap = {outer = {"down", "down"}, inner = {"down", "down"}},
}

local FLIP = {up = "down", down = "up", right = "left", left = "right"}

-- What to draw for this mix, and which of it the check moves.
-- surfaces: wiz.surfaces(); axis: "pitch" | "roll" | "yaw" | "flap" | nil.
-- flip: every arrow the other way (the stick the other way, or the gyro
-- pushing back against a movement).
function art.layout(surfaces, axis, flip)
  local l = art.baseLayout(surfaces, axis)
  if flip then
    for key, dirs in pairs(l.arrows) do
      local flipped = {}
      for i = 1, #dirs do flipped[i] = FLIP[dirs[i]] end
      l.arrows[key] = flipped
    end
  end
  return l
end

function art.baseLayout(surfaces, axis)
  local kinds = {}
  local flapRoll = false
  for i = 1, #surfaces do
    local s = surfaces[i]
    kinds[s.kind] = true
    if s.kind == "flap" and s.axes.roll then flapRoll = true end
  end
  local l = {
    outer = (kinds.aileron or kinds.elevon or kinds.flaperon) and (kinds.flaperon and FLAPERON or OUTER) or nil,
    outerKind = kinds.elevon and "elevon" or (kinds.flaperon and "flaperon" or "aileron"),
    inner = kinds.flap and INNER or nil,
    stab = kinds.elevator and not kinds.ruddervator,
    vtail = kinds.ruddervator,
    fin = (kinds.rudder or kinds.elevator) and not kinds.ruddervator,
    rudder = kinds.rudder,
    modelType = art.modelType,
    arrows = {},
  }
  local a = ARROWS[axis] or {}
  -- Only elements the check really moves get an arrow.
  if l.outer and a.outer then
    local moved = (axis == "pitch" and l.outerKind == "elevon")
      or (axis == "roll")
      or (axis == "flap" and l.outerKind == "flaperon")
    if moved then l.arrows.outer = a.outer end
  end
  if l.inner and a.inner and (axis == "flap" or (axis == "roll" and flapRoll)) then
    l.arrows.inner = a.inner
  end
  if l.stab and a.stab then l.arrows.stab = a.stab end
  if l.vtail and a.vtail then l.arrows.vtail = a.vtail end
  if l.rudder and a.fin then l.arrows.fin = a.fin end
  return l
end

-- The 3D airframe (app/plane3d.lua) for a layout: which tail and wing, and
-- where its surfaces sit along the half span. Elevons mean a tailless
-- model: a delta when the model type says so (lib/setup_wizard_mix.lua's
-- deltaWing, 3), a swept flying wing with winglets otherwise.
local MODEL_TYPE_DELTA = 3
local SPAN_AILERON = {0.30, 1.0}
local SPAN_AILERON_WITH_FLAPS = {0.52, 1.0}
local SPAN_FLAPERON = {0.18, 1.0}
local SPAN_ELEVON = {0.20, 0.97}
local SPAN_FLAP = {0.17, 0.50}

local function spec3d(l)
  local tailless = l.outerKind == "elevon" and not l.stab and not l.vtail
  local outer = nil
  if l.outer then
    if l.outerKind == "elevon" then outer = SPAN_ELEVON
    elseif l.outerKind == "flaperon" then outer = SPAN_FLAPERON
    else outer = l.inner and SPAN_AILERON_WITH_FLAPS or SPAN_AILERON end
  end
  local wing = "straight"
  if tailless then wing = (l.modelType == MODEL_TYPE_DELTA) and "delta" or "swept" end
  return {
    tail = tailless and "none" or (l.vtail and "vtail" or "conventional"),
    wing = wing,
    outer = outer,
    inner = l.inner and SPAN_FLAP or nil,
    fin = tailless and l.rudder or (not tailless and not l.vtail),
    rudder = l.rudder,
    winglets = tailless and wing == "swept",
    gear = not tailless,
  }
end

-- Which picture element a surface kind is (lib/setup_wizard_surfaces.lua).
local GROUP_OF = {
  aileron = "outer", elevon = "outer", flaperon = "outer", flap = "inner",
  elevator = "stab", ruddervator = "vtail", rudder = "fin",
}
local LIT_BOTH = {"lit", "lit"}

-- The airframe with one kind of surface lit (both sides: which side a servo
-- drives is not known), for a step that works one surface at a time.
function art.surfaceLayout(surfaces, kind)
  local l = art.baseLayout(surfaces, nil)
  local group = GROUP_OF[kind]
  if group then l.arrows[group] = LIT_BOTH end
  return l
end

-- The 3D airframe for this mix, for a step that draws the plane itself
-- (plane3d.setup(art.airframe(wiz.surfaces()))). Allocates: call it from
-- build, not paint.
function art.airframe(surfaces)
  return spec3d(art.baseLayout(surfaces, nil))
end

-- Seen from behind, a little from the left and well above (the nose tipped
-- down VIEW_PITCH on top of plane3d's own camera height): from low behind
-- the surfaces' chord, and how far they swing, shrink to a thin line.
local VIEW_YAW = -20
local VIEW_PITCH = -28
local VIEW_ZOOM = 1.3

-- colors: unused (plane3d has its own); kept for the caller's signature.
function art.draw(l, x, y, w, h, colors)
  l.spec3d = l.spec3d or spec3d(l)
  plane3d.setup(l.spec3d)
  plane3d.pose(l.arrows)
  plane3d.draw(x, y, w, h, 0, VIEW_PITCH, VIEW_YAW, VIEW_ZOOM)
end

-- A servo seen from above: its horn on an arc from Min (left) to Max
-- (right), for the Binding limits step. Positions are fractions of the way
-- out, -1 (full Min) .. 1 (full Max), drawn up to 75 degrees either side of
-- straight up. d is the caller's own table, refilled in place each paint:
--   pos              where the horn is
--   zoneFrom, zoneTo the stored limits (a band on the arc), or nil
--   side             "min" | "max": the half being found, lit as the horn
--                    moves along it; nil for none
--   saved            a tick at this position (a stored or just-set limit)
--   stop             a wall at this position: where the linkage binds
--   back             an arrow from the horn back towards the centre
local SWING = math.rad(75)
local sin, cos = math.sin, math.cos

local function dialPoint(cx, cy, r, f)
  local a = math.pi / 2 - f * SWING
  return cx + floor(r * cos(a) + 0.5), cy - floor(r * sin(a) + 0.5)
end

-- The arc's angles at fixed steps, worked out once: paint only looks them up.
local GRID = 20
local GRID_COS, GRID_SIN = {}, {}
for i = 0, GRID do
  local a = math.pi / 2 - (-1 + 2 * i / GRID) * SWING
  GRID_COS[i], GRID_SIN[i] = cos(a), sin(a)
end

-- The arc from..to as a band thick pixels deep inside radius r: each step a
-- quad of two filled triangles, the ends cut exactly at from and to.
local function dialArc(cx, cy, r, from, to, thick)
  if to <= from then return end
  local ri = r - thick
  local a = math.pi / 2 - from * SWING
  local c0, s0 = cos(a), sin(a)
  local ox0, oy0 = cx + floor(r * c0 + 0.5), cy - floor(r * s0 + 0.5)
  local ix0, iy0 = cx + floor(ri * c0 + 0.5), cy - floor(ri * s0 + 0.5)
  local i = floor((from + 1) * GRID / 2) + 1
  while true do
    local c1, s1
    local last = i > GRID or (-1 + 2 * i / GRID) >= to
    if last then
      a = math.pi / 2 - to * SWING
      c1, s1 = cos(a), sin(a)
    else
      c1, s1 = GRID_COS[i], GRID_SIN[i]
    end
    local ox1, oy1 = cx + floor(r * c1 + 0.5), cy - floor(r * s1 + 0.5)
    local ix1, iy1 = cx + floor(ri * c1 + 0.5), cy - floor(ri * s1 + 0.5)
    lcd.drawFilledTriangle(ox0, oy0, ix0, iy0, ox1, oy1)
    lcd.drawFilledTriangle(ix0, iy0, ix1, iy1, ox1, oy1)
    if last then return end
    ox0, oy0, ix0, iy0 = ox1, oy1, ix1, iy1
    i = i + 1
  end
end

-- A radial bar across the arc, r1 out to r2, half as wide as hw.
local function dialBar(cx, cy, r1, r2, f, hw)
  local a = math.pi / 2 - f * SWING
  local px, py = sin(a) * hw, cos(a) * hw
  local x1, y1 = cx + r1 * cos(a), cy - r1 * sin(a)
  local x2, y2 = cx + r2 * cos(a), cy - r2 * sin(a)
  local ax, ay = floor(x1 + px + 0.5), floor(y1 + py + 0.5)
  local bx, by = floor(x1 - px + 0.5), floor(y1 - py + 0.5)
  local qx, qy = floor(x2 + px + 0.5), floor(y2 + py + 0.5)
  local dx, dy = floor(x2 - px + 0.5), floor(y2 - py + 0.5)
  lcd.drawFilledTriangle(ax, ay, bx, by, qx, qy)
  lcd.drawFilledTriangle(bx, by, dx, dy, qx, qy)
end

local function clampUnit(f)
  if f < -1 then return -1 elseif f > 1 then return 1 end
  return f
end

function art.servoDial(cx, cy, r, d, colors)
  local t = math.max(3, floor(r / 18))
  -- A thin track, the stored range thick on it.
  lcd.color(colors.body)
  dialArc(cx, cy, r - floor(t / 2) + 1, -1, 1, 2)
  if d.zoneFrom and d.zoneTo then
    lcd.color(colors.surface)
    dialArc(cx, cy, r, clampUnit(d.zoneFrom), clampUnit(d.zoneTo), t)
  end
  local pos = clampUnit(d.pos or 0)
  lcd.color(colors.active)
  if d.side == "min" and pos < 0 then
    dialArc(cx, cy, r, pos, 0, t)
  elseif d.side == "max" and pos > 0 then
    dialArc(cx, cy, r, 0, pos, t)
  end
  -- Centre: where the horn starts on every side.
  lcd.color(colors.muted)
  dialBar(cx, cy, r + 4, r - t - 6, 0, 1)
  if d.saved then
    lcd.color(colors.text)
    dialBar(cx, cy, r + 6, r - t - 8, clampUnit(d.saved), 1.5)
  end
  if d.stop then
    -- The linkage binding: a solid block across the arc.
    lcd.color(colors.text)
    dialBar(cx, cy, r + 9, r - t - 9, clampUnit(d.stop), math.max(3, r / 14))
  end

  -- The horn: a tapered arm from the hub, rounded at the tip.
  local a = math.pi / 2 - pos * SWING
  local reach = floor(r * 0.82)
  local tx, ty = cx + floor(reach * cos(a) + 0.5), cy - floor(reach * sin(a) + 0.5)
  local hw = math.max(4, floor(r * 0.09))
  local px, py = floor(sin(a) * hw + 0.5), floor(cos(a) * hw + 0.5)
  lcd.color(d.side and pos ~= 0 and colors.active or colors.surface)
  lcd.drawFilledTriangle(tx, ty, cx + px, cy + py, cx - px, cy - py)
  lcd.drawFilledCircle(tx, ty, math.max(2, floor(hw / 2)))
  lcd.color(colors.body)
  lcd.drawFilledCircle(cx, cy, hw + 2)

  if d.back and pos ~= 0 then
    -- Just inside the arc, from the horn towards the centre.
    local dir = pos > 0 and -1 or 1
    local ar = r - t - floor(r * 0.16)
    local f1 = pos + dir * 0.06
    local f2 = pos + dir * 0.28
    lcd.color(colors.text)
    dialArc(cx, cy, ar + 1, math.min(f1, f2), math.max(f1, f2), 2)
    local hx, hy = dialPoint(cx, cy, ar, f2 + dir * 0.08)
    local bx1, by1 = dialPoint(cx, cy, ar - 5, f2)
    local bx2, by2 = dialPoint(cx, cy, ar + 5, f2)
    lcd.drawFilledTriangle(hx, hy, bx1, by1, bx2, by2)
  end
end

-- Where a servo dial of radius r puts its arc ends (for their labels):
-- dx out from the centre, dy up from it.
function art.dialEnds(r)
  return floor(r * sin(SWING) + 0.5), floor(r * cos(SWING) + 0.5)
end

local cachedDark, cachedColors = nil, nil

function art.colors()
  local dark = lcd.darkMode and lcd.darkMode() or false
  if dark ~= cachedDark or not cachedColors then
    cachedDark = dark
    cachedColors = {
      body = dark and lcd.GREY(110) or lcd.GREY(150),
      surface = dark and lcd.GREY(170) or lcd.GREY(90),
      active = lcd.RGB(255, 165, 30),
      text = dark and lcd.GREY(240) or lcd.GREY(20),
      muted = dark and lcd.GREY(170) or lcd.GREY(90),
    }
  end
  return cachedColors
end

package.loaded["wfsuite.app.setup_wizard_art"] = art
return art
