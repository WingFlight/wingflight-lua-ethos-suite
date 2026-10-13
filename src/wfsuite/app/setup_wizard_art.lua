-- Setup Wizard pictures: the model seen from behind, as the pilot sees it
-- standing behind the model, with the surfaces a check moves highlighted and
-- an arrow for the way each should go.
--
-- Built from the surface kinds lib/setup_wizard_surfaces.lua finds in the
-- mix, so a V-tail, a flying wing or a model with flaps each get their own
-- picture. Which side a servo is on cannot be read from the mix (it depends
-- on how the servo is mounted, which is what the check is about), so the
-- picture shows the airframe's surfaces, not individual servos.
--
-- layout() runs when a screen is built; draw() runs from paint and only
-- draws what layout() worked out, without allocating.

if package.loaded["wfsuite.app.setup_wizard_art"] then
  return package.loaded["wfsuite.app.setup_wizard_art"]
end

local floor = math.floor
local min = math.min

local art = {}

-- Element geometry in units of half the wingspan: x -1..1 left to right as
-- seen from behind, y down. {x1, x2, y, thickness} for bars; the V-tail and
-- fin are special-cased in draw().
local STAB_Y = -0.16
local OUTER = {0.55, 0.97}   -- ailerons, elevons
local FLAPERON = {0.30, 0.97}
local INNER = {0.13, 0.50}   -- flaps
local STAB = {0.10, 0.40}
local FIN_TOP = -0.62

-- Arrow for each element on each check: "up", "down", "right", or nil when
-- the check does not move it. Sides: L and R as seen from behind.
local ARROWS = {
  pitch = {outer = {"up", "up"}, stab = {"up", "up"}, vtail = {"up", "up"}},
  roll = {outer = {"down", "up"}, inner = {"down", "up"}},
  yaw = {fin = {"right"}, vtail = {"right", "right"}},
  flap = {outer = {"down", "down"}, inner = {"down", "down"}},
}

-- What to draw for this mix, and which of it the check moves.
-- surfaces: wiz.surfaces(); axis: "pitch" | "roll" | "yaw" | "flap" | nil.
function art.layout(surfaces, axis)
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

local function arrow(x, y, dir, size, thick)
  local h = floor(size * 0.45)
  if dir == "up" or dir == "down" then
    local sign = (dir == "up") and -1 or 1
    local tipY = y + sign * size
    local baseY = tipY - sign * h
    lcd.drawFilledRectangle(x - floor(thick / 2), min(y, baseY), thick, math.abs(baseY - y) + 1)
    lcd.drawFilledTriangle(x, tipY, x - h, baseY, x + h, baseY)
  else
    local tipX = x + size
    local baseX = tipX - h
    lcd.drawFilledRectangle(x, y - floor(thick / 2), baseX - x + 1, thick)
    lcd.drawFilledTriangle(tipX, y, baseX, y - h, baseX, y + h)
  end
end

-- One bar on each side, x1..x2 out from the middle.
local function bars(cx, y, s, span, t)
  local x1, x2 = floor(span[1] * s), floor(span[2] * s)
  lcd.drawFilledRectangle(cx - x2, y - floor(t / 2), x2 - x1, t)
  lcd.drawFilledRectangle(cx + x1, y - floor(t / 2), x2 - x1, t)
end

local function barArrows(cx, y, s, span, dirs, size, thick)
  if not dirs then return end
  local mid = floor((span[1] + span[2]) / 2 * s)
  local gap = floor(s * 0.05)
  for side = 1, 2 do
    local dir = dirs[side]
    local x = (side == 1) and (cx - mid) or (cx + mid)
    local start = (dir == "up") and (y - gap) or (y + gap)
    arrow(x, start, dir, size, thick)
  end
end

-- colors: {body =, surface =, active =, text =}, from art.colors().
function art.draw(l, x, y, w, h, colors)
  -- Half the span. From the wing the drawing reaches up to the fin top
  -- (-FIN_TOP s) and down to the tip of a down arrow (about 0.38 s): fit
  -- both in h and centre them.
  local above, below = -FIN_TOP, 0.38
  local s = floor(min(w * 0.46, h / (above + below)))
  local cx = x + floor(w / 2)
  local wingY = y + floor((h - (above + below) * s) / 2 + above * s)
  local t = math.max(5, floor(s * 0.07))
  local size = math.max(12, floor(s * 0.28))
  local thick = math.max(3, floor(t * 0.8))

  -- Wing and fuselage.
  lcd.color(colors.body)
  lcd.drawFilledRectangle(cx - s, wingY - floor(t / 2), 2 * s, t)
  lcd.drawFilledCircle(cx, wingY, floor(s * 0.09))

  -- Tail, behind the wing from this view: higher on the page.
  local stabY = wingY + floor(STAB_Y * s)
  if l.fin then
    local finTop = wingY + floor(FIN_TOP * s)
    lcd.color(colors.body)
    lcd.drawFilledRectangle(cx - floor(t / 2), finTop, t, stabY - finTop)
    if l.rudder then
      lcd.color(l.arrows.fin and colors.active or colors.surface)
      lcd.drawFilledRectangle(cx - floor(t / 2), finTop, t, floor((stabY - finTop) * 0.7))
    end
  end
  if l.stab then
    lcd.color(colors.body)
    lcd.drawFilledRectangle(cx - floor(STAB[2] * s), stabY - floor(t / 2), floor(STAB[2] * s) * 2, t)
    lcd.color(l.arrows.stab and colors.active or colors.surface)
    bars(cx, stabY, s, STAB, t)
  end
  if l.vtail then
    local tipX, tipY = floor(0.38 * s), wingY + floor(-0.5 * s)
    lcd.color(l.arrows.vtail and colors.active or colors.surface)
    for side = -1, 1, 2 do
      for k = 0, thick do
        lcd.drawLine(cx, stabY + k, cx + side * tipX, tipY + k)
      end
    end
  end

  -- Wing surfaces.
  if l.outer then
    lcd.color(l.arrows.outer and colors.active or colors.surface)
    bars(cx, wingY, s, l.outer, t)
  end
  if l.inner then
    lcd.color(l.arrows.inner and colors.active or colors.surface)
    bars(cx, wingY, s, l.inner, t)
  end

  -- Arrows.
  lcd.color(colors.active)
  if l.outer then barArrows(cx, wingY, s, l.outer, l.arrows.outer, size, thick) end
  if l.inner then barArrows(cx, wingY, s, l.inner, l.arrows.inner, size, thick) end
  if l.stab then barArrows(cx, stabY, s, STAB, l.arrows.stab, size, thick) end
  if l.vtail and l.arrows.vtail then
    local tipX, tipY = floor(0.38 * s), wingY + floor(-0.5 * s)
    local midX, midY = floor(0.22 * s), floor((stabY + tipY) / 2)
    for side = 1, 2 do
      local dir = l.arrows.vtail[side]
      if dir == "right" then
        -- From each tip, clear of the arms.
        local ax = (side == 1) and (cx - tipX) or (cx + tipX)
        arrow(ax + floor(s * 0.04), tipY, dir, size, thick)
      else
        local ax = (side == 1) and (cx - midX) or (cx + midX)
        arrow(ax, midY - floor(s * 0.06), dir, size, thick)
      end
    end
  end
  if l.fin and l.arrows.fin then
    local finTop = wingY + floor(FIN_TOP * s)
    arrow(cx + t, floor((finTop + stabY) / 2) - floor(s * 0.08), "right", size, thick)
  end
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
