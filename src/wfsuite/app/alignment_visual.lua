-- Custom Alignment 3D visualizer.
--
-- Stateless renderer for app/pages/alignment.lua. It keeps the original
-- module's important behavior: live attitude text, configured offset text,
-- nose-direction cue, and a projected aircraft model whose orientation
-- follows MSP_ATTITUDE plus any *unsaved* edits to the board offset fields
-- (see state.baseline in app/pages/alignment.lua -- the offsets already
-- saved on the FC are subtracted back out, since MSP_ATTITUDE already
-- includes them).
--
-- The aircraft is a low-poly copy of the Configurator's 3D model
-- (wingflight-configurator resources/models/model.gltf, an Extra-style
-- aerobatic plane): red body, dark ailerons/elevator/rudder, white spinner
-- and landing gear, a canopy and a two-blade prop. The mesh is written in
-- that file's own coordinates (x = span, y = up, z = aft) so its numbers
-- can be checked against the glTF, and converted once at load time to this
-- renderer's X = nose(+)/tail(-), Y = span, Z = up(+)/down(-).
--
-- Rendering, per paint: the attitude becomes one rotation matrix (built by
-- passing the three axes through rotatePoint(), so the orientation is
-- exactly the one the original rewrite tuned), every vertex is rotated and
-- projected once into reused buffers, faces of closed parts that point
-- away from the camera are dropped, the rest are flat-shaded from a fixed
-- light and drawn far-to-near. The camera sits CAMERA_ELEVATION above the
-- model's level plane, so the top of a level aircraft stays visible
-- instead of the wings collapsing to a line. No tables are allocated per
-- paint; shaded colours are built once per theme.

if package.loaded["wfsuite.app.alignment_visual"] then
  return package.loaded["wfsuite.app.alignment_visual"]
end

local cos = math.cos
local sin = math.sin
local rad = math.rad
local floor = math.floor
local sqrt = math.sqrt
local max = math.max
local min = math.min
local t_sort = table.sort

local BASE_VIEW_PITCH_R = rad(-90)
local BASE_VIEW_YAW_R = rad(90)
local CAMERA_DIST = 7.0
local CAMERA_NEAR_EPS = 0.25
local CAMERA_ELEVATION_R = rad(18)
local CAM_EC = cos(CAMERA_ELEVATION_R)
local CAM_ES = sin(CAMERA_ELEVATION_R)

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function rotatePoint(x, y, z, pitchR, yawR, rollR)
  local cbp = cos(BASE_VIEW_PITCH_R)
  local sbp = sin(BASE_VIEW_PITCH_R)
  local px = x
  local py = y * cbp - z * sbp
  local pz = y * sbp + z * cbp

  local cby = cos(BASE_VIEW_YAW_R)
  local sby = sin(BASE_VIEW_YAW_R)
  local bx = px * cby + pz * sby
  local by = py
  local bz = -px * sby + pz * cby

  local cz = cos(rollR)
  local sz = sin(rollR)
  local cx = cos(pitchR)
  local sx = sin(pitchR)
  local cy = cos(yawR)
  local sy = sin(yawR)

  local x1 = bx * cz - by * sz
  local y1 = bx * sz + by * cz
  local z1 = bz

  local x2 = x1
  local y2 = y1 * cx - z1 * sx
  local z2 = y1 * sx + z1 * cx

  local x3 = x2 * cy + z2 * sy
  local y3 = y2
  local z3 = -x2 * sy + z2 * cy

  return x3, y3, z3
end

local function projectPoint(px, py, pz, cx, cy, scale)
  local denom = CAMERA_DIST - pz
  if denom <= CAMERA_NEAR_EPS then return nil, nil end
  local f = CAMERA_DIST / denom
  return cx + (px * f * scale), cy - (py * f * scale)
end

---------------------------------------------------------------------------
-- Mesh
---------------------------------------------------------------------------

-- glTF -> renderer: scale, and the glTF point that becomes the origin
-- (roughly the middle of the airframe, so it turns about its centre).
local MODEL_SCALE = 0.70
local ORIGIN_Y = 0.10
local ORIGIN_Z = 1.00

local MAT_BODY = 1
local MAT_SURFACE = 2
local MAT_WHITE = 3
local MAT_CANOPY = 4
local MAT_PROP = 5

local MX, MY, MZ = {}, {}, {}
local vertexCount = 0

-- Faces: up to four vertex indices (FD = 0 for a triangle), a material,
-- and whether the face is a flat plate seen from both sides (wings, tail,
-- prop, gear legs) or one side of a closed part (culled when facing away).
local FA, FB, FC, FD, FMAT, FTWO = {}, {}, {}, {}, {}, {}
local faceCount = 0

local function vtx(gx, gy, gz)
  vertexCount = vertexCount + 1
  MX[vertexCount] = -(gz - ORIGIN_Z) * MODEL_SCALE
  MY[vertexCount] = gx * MODEL_SCALE
  MZ[vertexCount] = (gy - ORIGIN_Y) * MODEL_SCALE
  return vertexCount
end

local function pushFace(a, b, c, d, mat, twoSided)
  faceCount = faceCount + 1
  FA[faceCount], FB[faceCount], FC[faceCount], FD[faceCount] = a, b, c, d or 0
  FMAT[faceCount] = mat
  FTWO[faceCount] = twoSided
end

local function plate(a, b, c, d, mat)
  pushFace(a, b, c, d, mat, true)
end

-- One face of a closed part. (rx, ry, rz) is a glTF point inside the part
-- next to this face; the winding is flipped if needed so the normal points
-- away from it, which is all the back-face test needs.
local function solid(a, b, c, d, mat, rx, ry, rz)
  local ix = -(rz - ORIGIN_Z) * MODEL_SCALE
  local iy = rx * MODEL_SCALE
  local iz = (ry - ORIGIN_Y) * MODEL_SCALE
  local ux, uy, uz = MX[b] - MX[a], MY[b] - MY[a], MZ[b] - MZ[a]
  local vx, vy, vz = MX[c] - MX[a], MY[c] - MY[a], MZ[c] - MZ[a]
  local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
  local n = d and 4 or 3
  local gx = (MX[a] + MX[b] + MX[c] + (d and MX[d] or 0)) / n - ix
  local gy = (MY[a] + MY[b] + MY[c] + (d and MY[d] or 0)) / n - iy
  local gz = (MZ[a] + MZ[b] + MZ[c] + (d and MZ[d] or 0)) / n - iz
  if nx * gx + ny * gy + nz * gz < 0 then
    if d then a, b, c, d = a, d, c, b else b, c = c, b end
  end
  pushFace(a, b, c, d, mat, false)
end

do
  -- Fuselage: a lofted hexagonal section (flat top and belly, chamfered
  -- sides) through six stations from the cowl to the tail post.
  -- {z, half width, bottom y, top y, side y}
  local STATIONS = {
    {-1.62, 0.36, -0.20, 0.30, 0.05},
    {-1.00, 0.54, -0.42, 0.38, 0.00},
    {-0.30, 0.60, -0.46, 0.46, 0.00},
    { 1.00, 0.50, -0.30, 0.50, 0.05},
    { 1.80, 0.30, -0.22, 0.62, 0.12},
    { 3.55, 0.05, -0.04, 0.40, 0.18},
  }
  local ring = {}
  for i = 1, #STATIONS do
    local s = STATIONS[i]
    local z, w, yb, yt, ym = s[1], s[2], s[3], s[4], s[5]
    local t = w * 0.65
    ring[i] = {
      vtx(-t, yt, z), vtx(t, yt, z), vtx(w, ym, z),
      vtx(t, yb, z), vtx(-t, yb, z), vtx(-w, ym, z),
    }
  end
  for i = 1, #STATIONS - 1 do
    local r0, r1 = ring[i], ring[i + 1]
    local s0, s1 = STATIONS[i], STATIONS[i + 1]
    local rz = (s0[1] + s1[1]) * 0.5
    local ry = (s0[5] + s1[5]) * 0.5
    for k = 1, 6 do
      local k2 = (k % 6) + 1
      solid(r0[k], r0[k2], r1[k2], r1[k], MAT_BODY, 0, ry, rz)
    end
  end
  local first, last = STATIONS[1], STATIONS[#STATIONS]
  local f, l = ring[1], ring[#STATIONS]
  solid(f[1], f[2], f[3], f[4], MAT_BODY, 0, first[5], first[1] + 1)
  solid(f[4], f[5], f[6], f[1], MAT_BODY, 0, first[5], first[1] + 1)
  solid(l[1], l[2], l[3], l[4], MAT_BODY, 0, last[5], last[1] - 1)
  solid(l[4], l[5], l[6], l[1], MAT_BODY, 0, last[5], last[1] - 1)

  -- Canopy: windscreen point on the deck, two upper corners, two lower
  -- corners, and a tail point that runs into the turtle deck.
  local cF = vtx(0, 0.47, 0.20)
  local cBL, cBR = vtx(-0.27, 0.49, 0.80), vtx(0.27, 0.49, 0.80)
  local cTL, cTR = vtx(-0.16, 0.76, 0.85), vtx(0.16, 0.76, 0.85)
  local cR = vtx(0, 0.62, 1.75)
  solid(cF, cBR, cTR, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cF, cTR, cTL, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cF, cTL, cBL, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cBR, cR, cTR, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cTR, cR, cTL, nil, MAT_CANOPY, 0, 0.55, 0.9)
  solid(cTL, cR, cBL, nil, MAT_CANOPY, 0, 0.55, 0.9)

  -- Spinner: a six-sided cone in front of the cowl.
  local tip = vtx(0, 0.05, -2.04)
  local base = {}
  for k = 1, 6 do
    local a = (k - 1) * math.pi / 3
    base[k] = vtx(0.2 * cos(a), 0.05 + 0.2 * sin(a), -1.64)
  end
  for k = 1, 6 do
    solid(tip, base[k], base[(k % 6) + 1], nil, MAT_WHITE, 0, 0.05, -1.75)
  end

  -- Prop: two blades just behind the spinner tip.
  plate(vtx(0.12, 0.11, -1.70), vtx(0.95, 0.08, -1.70), vtx(0.95, 0.02, -1.70), vtx(0.12, -0.01, -1.70), MAT_PROP)
  plate(vtx(-0.12, 0.11, -1.70), vtx(-0.95, 0.08, -1.70), vtx(-0.95, 0.02, -1.70), vtx(-0.12, -0.01, -1.70), MAT_PROP)

  for side = -1, 1, 2 do
    -- Wing, low on the fuselage with a little dihedral, tapering mostly
    -- from the trailing edge; aileron from just outboard of the root to
    -- the tip.
    local rootLE = vtx(0.55 * side, -0.12, -0.55)
    local rootTE = vtx(0.55 * side, -0.12, 1.00)
    local ailIn = vtx(1.05 * side, -0.11, 0.62)
    local ailInTE = vtx(1.05 * side, -0.11, 0.99)
    local tipLE = vtx(3.55 * side, -0.06, -0.33)
    local tipHinge = vtx(3.55 * side, -0.06, 0.40)
    local tipTE = vtx(3.55 * side, -0.06, 0.76)
    plate(rootLE, tipLE, tipHinge, ailIn, MAT_BODY)
    plate(rootLE, ailIn, ailInTE, rootTE, MAT_BODY)
    plate(ailIn, tipHinge, tipTE, ailInTE, MAT_SURFACE)

    -- Horizontal stabilizer and elevator.
    local sRootH = vtx(0.10 * side, 0.36, 3.47)
    local sTipH = vtx(1.55 * side, 0.36, 3.47)
    plate(vtx(0.10 * side, 0.36, 2.92), vtx(1.55 * side, 0.36, 3.08), sTipH, sRootH, MAT_BODY)
    plate(vtx(0.04 * side, 0.36, 3.47), vtx(1.60 * side, 0.36, 3.47), vtx(1.60 * side, 0.36, 3.80), vtx(0.04 * side, 0.36, 3.86), MAT_SURFACE)

    -- Main gear: a leg out of the belly and a spatted wheel.
    local px = 0.76 * side
    plate(vtx(0.25 * side, -0.40, -0.52), vtx(px, -0.82, -0.54), vtx(px, -0.82, -0.38), vtx(0.25 * side, -0.40, -0.25), MAT_WHITE)
    local front = vtx(px, -0.93, -0.92)
    local rear = vtx(px, -0.90, -0.10)
    local around = {
      vtx(px, -0.77, -0.50), vtx(px + 0.08, -0.92, -0.50),
      vtx(px, -1.06, -0.50), vtx(px - 0.08, -0.92, -0.50),
    }
    for k = 1, 4 do
      local k2 = (k % 4) + 1
      solid(front, around[k], around[k2], nil, MAT_WHITE, px, -0.92, -0.50)
      solid(rear, around[k2], around[k], nil, MAT_WHITE, px, -0.92, -0.50)
    end
  end

  -- Fin and rudder (with its horn balance above the fin).
  plate(vtx(0, 0.48, 2.85), vtx(0, 1.18, 3.28), vtx(0, 1.18, 3.52), vtx(0, 0.38, 3.52), MAT_BODY)
  local hingeTop = vtx(0, 1.18, 3.52)
  local hornRear = vtx(0, 1.36, 3.80)
  plate(vtx(0, -0.02, 3.52), hingeTop, hornRear, vtx(0, 0.04, 4.14), MAT_SURFACE)
  plate(hingeTop, vtx(0, 1.36, 3.36), hornRear, nil, MAT_SURFACE)
end

-- Furthest point from the origin, so draw() can size the model to fit its
-- panel in every attitude.
local MODEL_RADIUS = 0
for i = 1, vertexCount do
  MODEL_RADIUS = max(MODEL_RADIUS, sqrt(MX[i] * MX[i] + MY[i] * MY[i] + MZ[i] * MZ[i]))
end

---------------------------------------------------------------------------
-- Shading
---------------------------------------------------------------------------

-- Light from above, to the left and in front of the screen (view space:
-- x right, y up, z towards the viewer).
local LIGHT_X, LIGHT_Y, LIGHT_Z
do
  local lx, ly, lz = -0.45, 0.75, 0.50
  local l = sqrt(lx * lx + ly * ly + lz * lz)
  LIGHT_X, LIGHT_Y, LIGHT_Z = lx / l, ly / l, lz / l
end
local AMBIENT = 0.45
local DIFFUSE = 0.65
local SHADE_LEVELS = 8

local BASE_COLORS = {
  dark = {
    [MAT_BODY] = {210, 40, 45},
    [MAT_SURFACE] = {78, 80, 88},
    [MAT_WHITE] = {235, 235, 230},
    [MAT_CANOPY] = {95, 125, 160},
    [MAT_PROP] = {160, 160, 165},
  },
  light = {
    [MAT_BODY] = {200, 30, 35},
    [MAT_SURFACE] = {45, 45, 52},
    [MAT_WHITE] = {215, 215, 210},
    [MAT_CANOPY] = {55, 75, 100},
    [MAT_PROP] = {120, 120, 125},
  },
}

local shadeCache = {}

local function shadeTable(isDark)
  local key = isDark and "dark" or "light"
  local cached = shadeCache[key]
  if cached then return cached end
  cached = {}
  for mat, rgb in pairs(BASE_COLORS[key]) do
    local levels = {}
    for i = 1, SHADE_LEVELS do
      local s = AMBIENT + DIFFUSE * (i - 1) / (SHADE_LEVELS - 1)
      levels[i] = lcd.RGB(min(255, floor(rgb[1] * s)), min(255, floor(rgb[2] * s)), min(255, floor(rgb[3] * s)))
    end
    cached[mat] = levels
  end
  shadeCache[key] = cached
  return cached
end

---------------------------------------------------------------------------
-- Per-paint buffers (reused)
---------------------------------------------------------------------------

local VX, VY, VZ, SX, SY = {}, {}, {}, {}, {}
local faceDepth = {}
local faceColor = {}
local drawOrder = {}
local drawCount = 0

local function fartherFirst(a, b)
  return faceDepth[a] < faceDepth[b]
end

local function drawModel(cx, cy, scale, pitchR, yawR, rollR, shades)
  -- Rotation matrix: the images of the three model axes, then the camera
  -- elevation (a tilt about the screen's horizontal axis).
  local ax, ay, az = rotatePoint(1, 0, 0, pitchR, yawR, rollR)
  local bx, by, bz = rotatePoint(0, 1, 0, pitchR, yawR, rollR)
  local cx3, cy3, cz3 = rotatePoint(0, 0, 1, pitchR, yawR, rollR)
  ay, az = ay * CAM_EC - az * CAM_ES, ay * CAM_ES + az * CAM_EC
  by, bz = by * CAM_EC - bz * CAM_ES, by * CAM_ES + bz * CAM_EC
  cy3, cz3 = cy3 * CAM_EC - cz3 * CAM_ES, cy3 * CAM_ES + cz3 * CAM_EC

  for i = 1, vertexCount do
    local x, y, z = MX[i], MY[i], MZ[i]
    local vx = x * ax + y * bx + z * cx3
    local vy = x * ay + y * by + z * cy3
    local vz = x * az + y * bz + z * cz3
    VX[i], VY[i], VZ[i] = vx, vy, vz
    local denom = CAMERA_DIST - vz
    if denom <= CAMERA_NEAR_EPS then
      SX[i] = false
    else
      local f = CAMERA_DIST / denom * scale
      SX[i] = cx + vx * f
      SY[i] = cy - vy * f
    end
  end

  local count = 0
  for i = 1, faceCount do
    local a, b, c, d = FA[i], FB[i], FC[i], FD[i]
    if SX[a] and SX[b] and SX[c] and (d == 0 or SX[d]) then
      local x0, y0, z0 = VX[a], VY[a], VZ[a]
      local ux, uy, uz = VX[b] - x0, VY[b] - y0, VZ[b] - z0
      local wx, wy, wz = VX[c] - x0, VY[c] - y0, VZ[c] - z0
      local nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
      local facing = nx * -x0 + ny * -y0 + nz * (CAMERA_DIST - z0)
      local visible = true
      if facing < 0 then
        if FTWO[i] then
          nx, ny, nz = -nx, -ny, -nz
        else
          visible = false
        end
      end
      if visible then
        local len = sqrt(nx * nx + ny * ny + nz * nz)
        local lambert = 0
        if len > 0 then
          lambert = (nx * LIGHT_X + ny * LIGHT_Y + nz * LIGHT_Z) / len
          if lambert < 0 then lambert = 0 end
        end
        count = count + 1
        drawOrder[count] = i
        if d == 0 then
          faceDepth[i] = (z0 + VZ[b] + VZ[c]) / 3
        else
          faceDepth[i] = (z0 + VZ[b] + VZ[c] + VZ[d]) * 0.25
        end
        faceColor[i] = shades[FMAT[i]][floor(lambert * (SHADE_LEVELS - 1) + 0.5) + 1]
      end
    end
  end
  for i = count + 1, drawCount do drawOrder[i] = nil end
  drawCount = count
  if count == 0 then return end

  t_sort(drawOrder, fartherFirst)
  for k = 1, count do
    local i = drawOrder[k]
    local a, b, c, d = FA[i], FB[i], FC[i], FD[i]
    lcd.color(faceColor[i])
    lcd.drawFilledTriangle(SX[a], SY[a], SX[b], SY[b], SX[c], SY[c])
    if d ~= 0 then
      lcd.drawFilledTriangle(SX[a], SY[a], SX[c], SY[c], SX[d], SY[d])
    end
  end
end

local alignment_visual = {}

function alignment_visual.recenterYaw(state)
  local baseline = state.baseline or {}
  state.viewYawOffset = (tonumber(state.live.yaw) or 0) + (tonumber(state.display.yaw_degrees) or 0) - (tonumber(baseline.yaw_degrees) or 0)
end

function alignment_visual.draw(state)
  local w, h = lcd.getWindowSize()
  local y = floor(form.height() + 2)
  local vw = w - 1
  local vh = h - y - 2
  if vh < 40 then return end

  local isDark = lcd.darkMode()
  local bg = isDark and lcd.RGB(18, 18, 18) or lcd.RGB(245, 245, 245)
  local grid = isDark and lcd.GREY(70) or lcd.GREY(210)
  local mainColor = isDark and lcd.RGB(248, 248, 248) or lcd.RGB(8, 8, 8)
  local accent = isDark and lcd.RGB(255, 220, 110) or lcd.RGB(0, 110, 235)

  local panelX = 4
  local panelY = y + 2
  local panelW = vw - 8
  local panelH = vh - 4

  lcd.color(bg)
  lcd.drawFilledRectangle(panelX, panelY, panelW, panelH)
  lcd.color(grid)
  lcd.drawRectangle(panelX, panelY, panelW, panelH)

  -- MSP_ATTITUDE already reflects the board-alignment offsets currently
  -- saved on the FC (alignment is applied to the sensor data before
  -- attitude is computed), so state.baseline -- the offsets in effect
  -- when this page opened -- must be subtracted back out before adding
  -- state.display (the, possibly still unsaved, offsets shown in the
  -- fields). Adding state.display on its own double-counts whatever was
  -- already saved, e.g. a correctly-configured upside-down mount (board
  -- roll 180) renders upside down here even though live attitude is
  -- already level.
  local baseline = state.baseline or {}
  local pitchR = rad(-((state.live.pitch or 0) + (state.display.pitch_degrees or 0) - (baseline.pitch_degrees or 0)))
  local yawR = rad(-(((state.live.yaw or 0) + (state.display.yaw_degrees or 0) - (baseline.yaw_degrees or 0)) - (state.viewYawOffset or 0)))
  local rollR = rad(-((state.live.roll or 0) + (state.display.roll_degrees or 0) - (baseline.roll_degrees or 0)))

  local leftPanelW = clamp(floor(panelW * 0.40), 150, floor(panelW * 0.70))
  local infoX = panelX + 1
  local infoY = panelY + 1
  local infoW = leftPanelW
  local infoH = panelH - 2
  local gx0 = infoX + infoW + 1
  local gy0 = panelY + 1
  local gw0 = panelW - infoW - 3
  local gh0 = panelH - 2
  if gh0 < 40 then return end

  lcd.color(grid)
  lcd.drawRectangle(infoX, infoY, infoW, infoH)
  lcd.drawLine(gx0 - 1, panelY + 1, gx0 - 1, panelY + panelH - 2)

  lcd.font(FONT_XS)
  local liveText = string.format("@i18n(app.modules.alignment.live_fmt)@", state.live.roll or 0, state.live.pitch or 0, state.live.yaw or 0)
  local offsText = string.format("@i18n(app.modules.alignment.offset_fmt)@", state.display.roll_degrees or 0, state.display.pitch_degrees or 0, state.display.yaw_degrees or 0, state.display.mag_alignment or 0)
  local _, th1 = lcd.getTextSize(liveText)
  local _, th2 = lcd.getTextSize(offsText)
  local textX = infoX + 8
  local textY = infoY + 6
  lcd.color(mainColor)
  lcd.drawText(textX, textY, liveText, LEFT)
  lcd.drawText(textX, textY + th1 + 2, offsText, LEFT)
  lcd.drawText(textX, textY + th1 + th2 + 14, string.format("@i18n(app.modules.alignment.view_yaw_fmt)@", state.viewYawOffset or 0), LEFT)

  local miniX = infoX + 8
  local miniY = textY + th1 + th2 + 46
  local miniW = max(40, infoW - 16)
  local miniH = max(40, infoH - (miniY - infoY) - 8)
  if miniH >= 56 then
    lcd.color(grid)
    lcd.drawRectangle(miniX, miniY, miniW, miniH)
    lcd.color(mainColor)
    lcd.drawText(miniX + 4, miniY + 2, "@i18n(app.modules.alignment.nose_direction)@", LEFT)

    local mx = miniX + floor(miniW * 0.5)
    local my = miniY + floor(miniH * 0.60)
    local nwx, nwy, nwz = rotatePoint(2.2, 0.0, 0.0, pitchR, yawR, rollR)
    local twx, twy, twz = rotatePoint(-2.2, 0.0, 0.0, pitchR, yawR, rollR)
    local npx, npy = projectPoint(nwx, nwy, nwz, mx, my, 1.0)
    local tpx, tpy = projectPoint(twx, twy, twz, mx, my, 1.0)
    if npx and npy and tpx and tpy then
      local dx = npx - tpx
      local dy = -(npy - tpy)
      local mag = sqrt((dx * dx) + (dy * dy))
      if mag > 0.001 then
        local ux = dx / mag
        local uy = dy / mag
        local htxt, vtxt = "center", "center"
        if ux > 0.35 then htxt = "left" elseif ux < -0.35 then htxt = "right" end
        if uy > 0.35 then vtxt = "up" elseif uy < -0.35 then vtxt = "down" end
        local primary = "@i18n(app.modules.alignment.nose_level)@"
        if vtxt == "up" then primary = "@i18n(app.modules.alignment.nose_up)@" end
        if vtxt == "down" then primary = "@i18n(app.modules.alignment.nose_down)@" end
        local secondary = ""
        if htxt == "left" then secondary = "@i18n(app.modules.alignment.leaning_left)@" end
        if htxt == "right" then secondary = "@i18n(app.modules.alignment.leaning_right)@" end

        lcd.font(FONT_STD)
        lcd.color(accent)
        lcd.drawText(miniX + 6, miniY + floor(miniH * 0.42), primary, LEFT)
        lcd.font(FONT_XS)
        lcd.color(mainColor)
        if secondary ~= "" then
          lcd.drawText(miniX + 6, miniY + floor(miniH * 0.42) + 22, secondary, LEFT)
        end
      end
    end
  end

  -- Fit the model's radius to the shorter side of the panel, so it stays
  -- inside at any attitude. Perspective can still push a tip pointing at
  -- the camera slightly further out, so clip to the panel as well.
  local cx = gx0 + floor(gw0 * 0.5)
  local cy = gy0 + floor(gh0 * 0.5)
  local scale = max(8, (min(gw0, gh0) * 0.5 - 4) / MODEL_RADIUS)
  lcd.setClipping(gx0, gy0, gw0, gh0)
  drawModel(cx, cy, scale, pitchR, yawR, rollR, shadeTable(isDark))
  lcd.setClipping(0, 0, w, h)
end

package.loaded["wfsuite.app.alignment_visual"] = alignment_visual
return alignment_visual
